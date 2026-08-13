import Foundation
import Observation

@MainActor
@Observable
final class RemoteLibraryStore {
    static let defaultServerAddress = "https://4-3rail.top"
    private static let serverDefaultsKey = "remote.serverAddress"

    var books: [RemoteBook] = []
    var serverAddress: String
    var isLoading = false
    var isUploading = false
    var isOnline = false
    var downloadProgress: [String: Double] = [:]
    var alert: LibraryAlert?

    @ObservationIgnored private var didInitialLoad = false
    @ObservationIgnored private var progressTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let fileManager = FileManager.default

    init() {
        serverAddress = UserDefaults.standard.string(forKey: Self.serverDefaultsKey)
            ?? Self.defaultServerAddress
        // One-time cleanup for credentials saved by the short-lived coupled prototype.
        try? KeychainStore.delete(account: "remote-library-username")
        try? KeychainStore.delete(account: "remote-library-password")
    }

    func loadIfNeeded() async {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        await refresh(showErrors: false)
    }

    func updateServerAddress(_ value: String) async {
        serverAddress = value.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(serverAddress, forKey: Self.serverDefaultsKey)
        books = []
        isOnline = false
        await refresh()
    }

    func refresh(showErrors: Bool = true) async {
        isLoading = true
        defer { isLoading = false }
        do {
            books = try await makeService().fetchBooks()
            isOnline = true
        } catch {
            isOnline = false
            if showErrors {
                alert = LibraryAlert(title: "无法连接云书库", message: errorMessage(error))
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

    func upload(_ urls: [URL], removeSourcesAfterUpload: Bool = false) {
        guard !urls.isEmpty else { return }
        guard !isUploading else {
            alert = LibraryAlert(title: "正在上传", message: "请等待当前上传完成。")
            return
        }
        isUploading = true
        let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        Task {
            defer {
                for url in accessedURLs {
                    url.stopAccessingSecurityScopedResource()
                }
                if removeSourcesAfterUpload {
                    for url in urls { try? fileManager.removeItem(at: url) }
                }
            }
            await uploadWithActiveAccess(urls)
        }
    }

    private func uploadWithActiveAccess(_ urls: [URL]) async {
        defer { isUploading = false }
        do {
            let service = try makeService()
            for url in urls {
                _ = try await service.upload(url)
            }
            await refresh(showErrors: false)
        } catch {
            alert = LibraryAlert(title: "上传失败", message: errorMessage(error))
        }
    }

    func delete(_ book: RemoteBook) async {
        do {
            try await makeService().delete(book)
            books.removeAll { $0.id == book.id }
        } catch {
            alert = LibraryAlert(title: "无法删除远程书籍", message: errorMessage(error))
        }
    }

    func scheduleProgress(book: Book, position: Int, progress: Double) {
        guard let remoteID = book.remoteSourceID, !remoteID.hasPrefix("icloud:") else { return }
        progressTasks[remoteID]?.cancel()
        progressTasks[remoteID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, let self else { return }
            await self.sendProgress(remoteID: remoteID, position: position, progress: progress)
        }
    }

    func flushProgress(book: Book, position: Int, progress: Double) {
        guard let remoteID = book.remoteSourceID, !remoteID.hasPrefix("icloud:") else { return }
        progressTasks[remoteID]?.cancel()
        progressTasks[remoteID] = Task { [weak self] in
            guard let self else { return }
            await self.sendProgress(remoteID: remoteID, position: position, progress: progress)
        }
    }

    private func sendProgress(remoteID: String, position: Int, progress: Double) async {
        try? await makeService().updateProgress(
            bookID: remoteID,
            progress: progress,
            position: position
        )
    }

    private func makeService() throws -> RemoteLibraryService {
        try RemoteLibraryService(serverAddress: serverAddress)
    }

    private func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
