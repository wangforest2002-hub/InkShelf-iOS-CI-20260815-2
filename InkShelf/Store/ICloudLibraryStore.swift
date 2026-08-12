import Foundation
import Observation

@MainActor
@Observable
final class ICloudLibraryStore {
    private(set) var folders: [ICloudFolderLink] = []
    private(set) var books: [ICloudBook] = []
    var isIndexing = false
    var downloadProgress: [String: Double] = [:]
    var alert: LibraryAlert?

    @ObservationIgnored private let fileManager = FileManager.default
    @ObservationIgnored private let metadataURL: URL
    @ObservationIgnored private let indexURL: URL
    @ObservationIgnored private var didInitialLoad = false

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InkShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        metadataURL = support.appendingPathComponent("icloud-folders.json")
        indexURL = support.appendingPathComponent("icloud-index.json")
        loadMetadata()
    }

    var totalCloudSize: Int64 { books.reduce(0) { $0 + $1.size } }
    var isDownloading: Bool { !downloadProgress.isEmpty }

    func loadIfNeeded() async {
        guard !didInitialLoad else { return }
        didInitialLoad = true
        if !folders.isEmpty { await refresh(showErrors: false) }
    }

    func linkFolder(_ url: URL) async {
        do {
            let bookmark = try ICloudFolderService.bookmark(for: url)
            let selectedPath = url.standardizedFileURL.path
            if let existingIndex = folders.firstIndex(where: { link in
                (try? ICloudFolderService.resolve(link).url.standardizedFileURL.path) == selectedPath
            }) {
                folders[existingIndex].bookmark = bookmark
                folders[existingIndex].name = url.lastPathComponent.isEmpty ? "iCloud 画集" : url.lastPathComponent
                saveMetadata()
                await refresh()
                return
            }
            let newLink = ICloudFolderLink(
                id: UUID(),
                name: url.lastPathComponent.isEmpty ? "iCloud 画集" : url.lastPathComponent,
                bookmark: bookmark,
                linkedAt: .now
            )
            folders.append(newLink)
            saveMetadata()
            await refresh()
        } catch {
            alert = LibraryAlert(title: "无法连接文件夹", message: errorMessage(error))
        }
    }

    func unlink(_ folder: ICloudFolderLink) {
        folders.removeAll { $0.id == folder.id }
        books.removeAll { $0.folderID == folder.id }
        saveMetadata()
        saveIndex()
    }

    func refresh(showErrors: Bool = true) async {
        guard !folders.isEmpty else {
            books = []
            saveIndex()
            return
        }
        isIndexing = true
        defer { isIndexing = false }

        var refreshed: [ICloudBook] = []
        var refreshedLinks = folders
        var errors: [String] = []
        for (index, link) in refreshedLinks.enumerated() {
            do {
                let resolved = try ICloudFolderService.resolve(link)
                if resolved.stale {
                    refreshedLinks[index].bookmark = try ICloudFolderService.bookmark(for: resolved.url)
                }
                let scanLink = refreshedLinks[index]
                let rootURL = resolved.url
                let scanned = try await Task.detached(priority: .utility) {
                    try ICloudFolderService.scan(link: scanLink, rootURL: rootURL)
                }.value
                refreshed.append(contentsOf: scanned)
            } catch {
                errors.append("\(link.name)：\(errorMessage(error))")
                refreshed.append(contentsOf: books.filter { $0.folderID == link.id })
            }
        }
        folders = refreshedLinks
        books = refreshed.sorted {
            let collectionOrder = $0.collection.localizedStandardCompare($1.collection)
            if collectionOrder != .orderedSame { return collectionOrder == .orderedAscending }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        saveMetadata()
        saveIndex()

        if showErrors, !errors.isEmpty {
            alert = LibraryAlert(title: "部分 iCloud 文件夹不可用", message: errors.joined(separator: "\n"))
        }
    }

    func open(_ cloudBook: ICloudBook, into library: LibraryStore) async -> Book? {
        if let cached = library.cachedBook(remoteID: cloudBook.sourceID, modifiedAt: cloudBook.revision) {
            return cached
        }
        guard downloadProgress[cloudBook.id] == nil else { return nil }
        guard let link = folders.first(where: { $0.id == cloudBook.folderID }) else {
            alert = LibraryAlert(title: "文件夹已断开", message: "请重新连接这本书所在的 iCloud 文件夹。")
            return nil
        }

        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("InkShelfICloud", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = temporaryRoot.appendingPathComponent(cloudBook.name)
        downloadProgress[cloudBook.id] = 0
        defer {
            downloadProgress[cloudBook.id] = nil
            try? fileManager.removeItem(at: temporaryRoot)
        }

        do {
            let resolved = try ICloudFolderService.resolve(link)
            let localFile = try await ICloudFolderService.materialize(
                book: cloudBook,
                rootURL: resolved.url,
                destination: destination
            ) { [weak self] value in
                self?.downloadProgress[cloudBook.id] = value
            }
            return try await library.importRemoteFile(
                localFile,
                remoteID: cloudBook.sourceID,
                remoteModifiedAt: cloudBook.revision,
                serverProgress: nil
            )
        } catch {
            alert = LibraryAlert(title: "iCloud 下载失败", message: errorMessage(error))
            return nil
        }
    }

    func cachedBook(for cloudBook: ICloudBook, in library: LibraryStore) -> Book? {
        library.cachedBook(remoteID: cloudBook.sourceID, modifiedAt: cloudBook.revision)
    }

    func removeLocalCopy(of cloudBook: ICloudBook, from library: LibraryStore) {
        guard let cached = cachedBook(for: cloudBook, in: library) else { return }
        library.delete(cached)
    }

    private func loadMetadata() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: metadataURL),
           let decoded = try? decoder.decode([ICloudFolderLink].self, from: data) {
            folders = decoded
        }
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? decoder.decode([ICloudBook].self, from: data) {
            books = decoded
        }
    }

    private func saveMetadata() {
        encode(folders, to: metadataURL)
    }

    private func saveIndex() {
        encode(books, to: indexURL)
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            alert = LibraryAlert(title: "无法保存 iCloud 索引", message: error.localizedDescription)
        }
    }

    private nonisolated func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
