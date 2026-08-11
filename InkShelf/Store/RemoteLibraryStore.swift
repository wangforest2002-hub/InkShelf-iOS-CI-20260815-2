import Foundation
import Observation

@MainActor
@Observable
final class RemoteLibraryStore {
    static let defaultServerAddress = "https://4-3rail.top"
    private static let serverDefaultsKey = "remote.serverAddress"
    private static let usernameAccount = "remote-library-username"
    private static let passwordAccount = "remote-library-password"

    var books: [RemoteBook] = []
    var currentUser: RemoteLibraryUser?
    var serverAddress: String
    var username: String
    var password: String
    var isConnecting = false
    var isLoading = false
    var isUploading = false
    var downloadProgress: [String: Double] = [:]
    var alert: LibraryAlert?

    @ObservationIgnored private var didAttemptRestore = false
    @ObservationIgnored private var progressTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let fileManager = FileManager.default

    init() {
        serverAddress = UserDefaults.standard.string(forKey: Self.serverDefaultsKey)
            ?? Self.defaultServerAddress
        username = KeychainStore.read(account: Self.usernameAccount) ?? ""
        password = KeychainStore.read(account: Self.passwordAccount) ?? ""
    }

    var isAuthenticated: Bool { currentUser != nil }
    var hasSavedLogin: Bool { !username.isEmpty && !password.isEmpty }

    func restoreIfNeeded() async {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        isConnecting = true
        defer { isConnecting = false }

        do {
            let service = try makeService()
            if let user = try await service.currentUser() {
                currentUser = user
                await refresh(showErrors: false)
                return
            }
            if hasSavedLogin {
                try await authenticate(using: service, saveCredentials: false)
            }
        } catch {
            currentUser = nil
        }
    }

    func login() async {
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUsername.isEmpty, !password.isEmpty else {
            alert = LibraryAlert(title: "还不能登录", message: "请填写网站账号和密码。")
            return
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let service = try makeService()
            username = cleanUsername
            try await authenticate(using: service, saveCredentials: true)
        } catch {
            currentUser = nil
            alert = LibraryAlert(title: "远程书库登录失败", message: errorMessage(error))
        }
    }

    func logout() async {
        if let service = try? makeService() {
            try? await service.logout()
        }
        currentUser = nil
        books = []
        password = ""
        try? KeychainStore.delete(account: Self.passwordAccount)
    }

    func refresh(showErrors: Bool = true) async {
        guard currentUser != nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            books = try await makeService().fetchBooks()
        } catch {
            if let remoteError = error as? RemoteLibraryError,
               case .authenticationRequired = remoteError {
                currentUser = nil
            }
            if showErrors {
                alert = LibraryAlert(title: "无法刷新云书库", message: errorMessage(error))
            }
        }
    }

    func coverURL(for book: RemoteBook) -> URL? {
        try? makeService().absoluteURL(for: book.coverPath)
    }

    func download(_ remoteBook: RemoteBook, into library: LibraryStore) async -> Book? {
        if let cached = library.cachedBook(remoteID: remoteBook.id, modifiedAt: remoteBook.modifiedAt) {
            return cached
        }
        guard downloadProgress[remoteBook.id] == nil else { return nil }

        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("InkShelfRemote", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = temporaryRoot.appendingPathComponent(remoteBook.name)
        downloadProgress[remoteBook.id] = 0
        defer {
            downloadProgress[remoteBook.id] = nil
            try? fileManager.removeItem(at: temporaryRoot)
        }

        do {
            try fileManager.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            let service = try makeService()
            let file = try await service.download(remoteBook, to: destination) { [weak self] value in
                self?.downloadProgress[remoteBook.id] = value
            }
            let imported = try await library.importRemoteFile(
                file,
                remoteID: remoteBook.id,
                remoteModifiedAt: remoteBook.modifiedAt,
                serverProgress: remoteBook.progress
            )
            return imported
        } catch {
            alert = LibraryAlert(title: "下载失败", message: errorMessage(error))
            return nil
        }
    }

    func upload(_ urls: [URL]) async {
        guard currentUser?.isAdmin == true, !urls.isEmpty else { return }
        guard !isUploading else {
            alert = LibraryAlert(title: "正在上传", message: "请等待当前上传完成。")
            return
        }
        isUploading = true
        defer { isUploading = false }
        do {
            let service = try makeService()
            for url in urls {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                _ = try await service.upload(url)
            }
            await refresh(showErrors: false)
        } catch {
            alert = LibraryAlert(title: "上传失败", message: errorMessage(error))
        }
    }

    func delete(_ book: RemoteBook) async {
        guard currentUser?.isAdmin == true else { return }
        do {
            try await makeService().delete(book)
            books.removeAll { $0.id == book.id }
        } catch {
            alert = LibraryAlert(title: "无法删除远程书籍", message: errorMessage(error))
        }
    }

    func scheduleProgress(book: Book, position: Int, progress: Double) {
        guard let remoteID = book.remoteSourceID, currentUser != nil else { return }
        progressTasks[remoteID]?.cancel()
        progressTasks[remoteID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self else { return }
            await self.sendProgress(remoteID: remoteID, position: position, progress: progress)
        }
    }

    func flushProgress(book: Book, position: Int, progress: Double) {
        guard let remoteID = book.remoteSourceID, currentUser != nil else { return }
        progressTasks[remoteID]?.cancel()
        progressTasks[remoteID] = Task { [weak self] in
            guard let self else { return }
            await self.sendProgress(remoteID: remoteID, position: position, progress: progress)
        }
    }

    private func authenticate(using service: RemoteLibraryService, saveCredentials: Bool) async throws {
        let user = try await service.login(username: username, password: password)
        currentUser = user
        if saveCredentials {
            UserDefaults.standard.set(serverAddress, forKey: Self.serverDefaultsKey)
            try KeychainStore.save(username, account: Self.usernameAccount)
            try KeychainStore.save(password, account: Self.passwordAccount)
        }
        await refresh(showErrors: false)
    }

    private func sendProgress(remoteID: String, position: Int, progress: Double) async {
        do {
            try await makeService().updateProgress(
                bookID: remoteID,
                progress: progress,
                position: position
            )
        } catch {
            // Reading must never be interrupted by a background sync failure.
        }
    }

    private func makeService() throws -> RemoteLibraryService {
        try RemoteLibraryService(serverAddress: serverAddress)
    }

    private func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
