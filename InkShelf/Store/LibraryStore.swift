import Foundation
import Observation

struct LibraryAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
@Observable
final class LibraryStore {
    private(set) var books: [Book] = []
    private(set) var isImporting = false
    private(set) var importStatusText: String?
    private(set) var importNotice: String?
    var alert: LibraryAlert?

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let metadataURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    let libraryURL: URL

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        documentsURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        let documents = documentsURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        libraryURL = documents.appendingPathComponent("InkShelf Library", isDirectory: true)
        metadataURL = libraryURL.appendingPathComponent("library.json")
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_PICKER") {
            // Each picker test must begin on a truly empty shelf. UI test
            // methods share the same simulator container unless we reset it.
            try? fileManager.removeItem(at: libraryURL)
            defaults.removeObject(forKey: Self.activeReaderKey)
        }
#endif
        try? fileManager.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        load()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_SEED") {
            installReaderNavigationSmokeBook()
        }
        if ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_PICKER") {
            installPickerSmokeInput()
        }
#endif
    }

    var storageUsage: Int64 {
        books.reduce(0) { $0 + $1.fileSize }
    }

    var continueReadingBook: Book? {
        books
            .filter { $0.lastOpenedAt != nil }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    var favoritePageItems: [FavoritePageItem] {
        books.flatMap { book in
            (book.favoritePages ?? [])
                .filter { $0 >= 0 && $0 < book.pageCount }
                .map { FavoritePageItem(book: book, page: $0) }
        }
        .sorted {
            ($0.book.lastOpenedAt ?? $0.book.importedAt) > ($1.book.lastOpenedAt ?? $1.book.importedAt)
        }
    }

    var interruptedReadingBook: Book? {
        guard let value = defaults.string(forKey: Self.activeReaderKey),
              let id = UUID(uuidString: value),
              let book = books.first(where: { $0.id == id })
        else { return nil }
        return book
    }

    func filteredBooks(scope: LibraryScope, query: String) -> [Book] {
        books
            .filter {
                switch scope {
                case .all: true
                case .recent: $0.lastOpenedAt != nil
                case .favorites: $0.isFavorite
                }
            }
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            .sorted {
                let left = $0.lastOpenedAt ?? $0.importedAt
                let right = $1.lastOpenedAt ?? $1.importedAt
                return left > right
            }
    }

    func cachedBook(remoteID: String, modifiedAt: String? = nil) -> Book? {
        books.first {
            $0.remoteSourceID == remoteID && (modifiedAt == nil || $0.remoteModifiedAt == modifiedAt)
        }
    }

    func importFiles(
        _ urls: [URL],
        cleanupDirectory: URL? = nil,
        removeSourcesAfterImport: Bool = false
    ) {
        guard !urls.isEmpty else {
            if let cleanupDirectory { try? fileManager.removeItem(at: cleanupDirectory) }
            return
        }
        guard !isImporting else {
            if let cleanupDirectory { try? fileManager.removeItem(at: cleanupDirectory) }
            alert = LibraryAlert(title: "正在导入", message: "请等待当前导入完成后再试。")
            return
        }
        isImporting = true
        importStatusText = urls.count == 1
            ? "正在接收“\(urls[0].lastPathComponent)”…"
            : "正在接收 \(urls.count) 个项目…"
        importNotice = nil
        let destination = libraryURL
        // Document-picker permissions are ephemeral. Acquire them synchronously
        // in the completion callback and retain them until the detached importer
        // has fully copied every selected item into the app container.
        let accessedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }

        Task {
            defer {
                for url in accessedURLs {
                    url.stopAccessingSecurityScopedResource()
                }
                if let cleanupDirectory {
                    try? fileManager.removeItem(at: cleanupDirectory)
                }
                if removeSourcesAfterImport {
                    for url in urls { try? fileManager.removeItem(at: url) }
                }
            }
            do {
                importStatusText = "正在整理封面和页面…"
                let imported = try await BookImporter.importBooks(from: urls, into: destination)
                books.append(contentsOf: imported)
                saveImmediately()
                importNotice = imported.count == 1
                    ? "“\(imported[0].title)”已经回到书架"
                    : "已把 \(imported.count) 本读物带回小家"
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2.8))
                    self?.importNotice = nil
                }
            } catch {
                alert = LibraryAlert(
                    title: "导入失败",
                    message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
            importStatusText = nil
            isImporting = false
        }
    }

    func openingError(for book: Book) -> LibraryAlert? {
        let content = contentURL(for: book)
        guard fileManager.fileExists(atPath: content.path) else {
            return LibraryAlert(
                title: "找不到这本书",
                message: "本地文件可能已被系统清理或移动。请删除这个失效书架项目后重新导入。"
            )
        }

        switch book.kind {
        case .archive, .imageCollection:
            guard !pageURLs(for: book).isEmpty else {
                return LibraryAlert(title: "没有可读页面", message: "这本画集的页面目录为空，请重新导入原文件。")
            }
        case .ebook:
            guard ebookPackage(for: book) != nil else {
                return LibraryAlert(title: "电子书索引损坏", message: "无法读取章节索引，请重新导入原电子书。")
            }
        case .pdf:
            break
        }
        return nil
    }

    func importRemoteFile(
        _ url: URL,
        remoteID: String,
        remoteModifiedAt: String,
        serverProgress: RemoteReadingProgress?
    ) async throws -> Book {
        guard !isImporting else { throw LibraryStoreError.importInProgress }
        isImporting = true
        defer { isImporting = false }

        let imported = try await BookImporter.importBooks(from: [url], into: libraryURL)
        guard var book = imported.first else { throw BookImportError.noImages }
        book.remoteSourceID = remoteID
        book.remoteModifiedAt = remoteModifiedAt

        if let serverProgress {
            let maximum = max(0, book.pageCount - 1)
            book.currentPage = min(max(0, serverProgress.position), maximum)
            if book.kind == .ebook, book.pageCount > 0 {
                let exact = min(max(serverProgress.progress, 0), 1) * Double(book.pageCount)
                book.currentPage = min(Int(exact.rounded(.down)), maximum)
                book.ebookChapterProgress = min(max(exact - Double(book.currentPage), 0), 1)
            }
        }

        if let old = books.first(where: { $0.remoteSourceID == remoteID }) {
            book.isFavorite = old.isFavorite
            let oldFolder = libraryURL.appendingPathComponent(old.folderName, isDirectory: true)
            books.removeAll { $0.id == old.id }
            try? fileManager.removeItem(at: oldFolder)
        }
        books.append(book)
        saveImmediately()
        return book
    }

    func markOpened(_ id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].lastOpenedAt = .now
        scheduleSave()
    }

    func beginReading(_ id: UUID) {
        markOpened(id)
        defaults.set(id.uuidString, forKey: Self.activeReaderKey)
    }

    func endReading(_ id: UUID) {
        guard defaults.string(forKey: Self.activeReaderKey) == id.uuidString else { return }
        defaults.removeObject(forKey: Self.activeReaderKey)
    }

    func updateProgress(bookID: UUID, page: Int) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        let clamped = min(max(0, page), max(0, books[index].pageCount - 1))
        guard books[index].currentPage != clamped else { return }
        books[index].currentPage = clamped
        books[index].lastOpenedAt = .now
        scheduleSave()
    }

    func updatePageCount(bookID: UUID, pageCount: Int) {
        guard pageCount > 0, let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        guard books[index].pageCount != pageCount else { return }
        books[index].pageCount = pageCount
        books[index].currentPage = min(books[index].currentPage, pageCount - 1)
        scheduleSave()
    }

    func updateEBookProgress(bookID: UUID, chapter: Int, progression: Double) {
        guard let index = books.firstIndex(where: { $0.id == bookID }), books[index].kind == .ebook else { return }
        let chapterIndex = min(max(0, chapter), max(0, books[index].pageCount - 1))
        let chapterProgress = min(max(0, progression), 1)
        guard books[index].currentPage != chapterIndex || books[index].ebookChapterProgress != chapterProgress else { return }
        books[index].currentPage = chapterIndex
        books[index].ebookChapterProgress = chapterProgress
        books[index].lastOpenedAt = .now
        scheduleSave()
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].isFavorite.toggle()
        saveImmediately()
    }

    func isPageFavorite(bookID: UUID, page: Int) -> Bool {
        books.first(where: { $0.id == bookID })?.favoritePages?.contains(page) == true
    }

    func togglePageFavorite(bookID: UUID, page: Int) {
        guard let index = books.firstIndex(where: { $0.id == bookID }),
              page >= 0,
              page < books[index].pageCount
        else { return }
        var pages = Set(books[index].favoritePages ?? [])
        if !pages.insert(page).inserted { pages.remove(page) }
        books[index].favoritePages = pages.sorted()
        saveImmediately()
    }

    func rename(_ id: UUID, to newTitle: String) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].title = title
        saveImmediately()
    }

    func delete(_ book: Book) {
        let folder = libraryURL.appendingPathComponent(book.folderName, isDirectory: true)
        do {
            if fileManager.fileExists(atPath: folder.path) {
                try fileManager.removeItem(at: folder)
            }
            books.removeAll { $0.id == book.id }
            endReading(book.id)
            saveImmediately()
        } catch {
            alert = LibraryAlert(title: "无法删除", message: error.localizedDescription)
        }
    }

    func contentURL(for book: Book) -> URL {
        libraryURL.appendingPathComponent(book.contentRelativePath)
    }

    func sourceURL(for book: Book) -> URL? {
        book.sourceRelativePath.map { libraryURL.appendingPathComponent($0) }
    }

    func coverURL(for book: Book) -> URL? {
        book.coverRelativePath.map { libraryURL.appendingPathComponent($0) }
    }

    func previewURLs(for book: Book) -> [URL] {
        let paths = book.previewRelativePaths ?? book.coverRelativePath.map { [$0] } ?? []
        return paths
            .map { libraryURL.appendingPathComponent($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    func ebookPackage(for book: Book) -> EBookPackage? {
        guard book.kind == .ebook,
              let data = try? Data(contentsOf: contentURL(for: book))
        else { return nil }
        return try? JSONDecoder().decode(EBookPackage.self, from: data)
    }

    func pageURLs(for book: Book) -> [URL] {
        guard book.kind == .archive || book.kind == .imageCollection else { return [] }
        let folder = contentURL(for: book)
        let urls = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return NaturalSort.urls(urls.filter { url in
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            return isFile
        })
    }

    func flushProgress() {
        saveTask?.cancel()
        saveImmediately()
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            books = try decoder.decode([Book].self, from: data)
                .filter { fileManager.fileExists(atPath: contentURL(for: $0).path) }
            if let value = defaults.string(forKey: Self.activeReaderKey),
               let id = UUID(uuidString: value),
               !books.contains(where: { $0.id == id }) {
                defaults.removeObject(forKey: Self.activeReaderKey)
            }
        } catch {
            alert = LibraryAlert(title: "书架数据需要修复", message: "本地文件仍然保留，但书架索引无法读取：\(error.localizedDescription)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.saveImmediately()
        }
    }

    private func saveImmediately() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(books)
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            alert = LibraryAlert(title: "无法保存书架", message: error.localizedDescription)
        }
    }

    private static let activeReaderKey = "reader.activeBookID"

#if DEBUG
    private func installReaderNavigationSmokeBook() {
        let id = UUID(uuidString: "A11CE000-0000-4000-8000-000000000001")!
        guard !books.contains(where: { $0.id == id }) else { return }
        let folder = libraryURL.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let pages = folder.appendingPathComponent("pages", isDirectory: true)
        let page = pages.appendingPathComponent("000001.png")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLxVQAAAABJRU5ErkJggg==")!
        do {
            try fileManager.createDirectory(at: pages, withIntermediateDirectories: true)
            try png.write(to: page, options: .atomic)
            books.append(Book(
                id: id,
                title: "UI 冒烟读物",
                kind: .imageCollection,
                sourceFileName: "UI 冒烟读物",
                contentRelativePath: "\(id.uuidString.lowercased())/pages",
                pageCount: 1,
                fileSize: Int64(png.count)
            ))
            saveImmediately()
        } catch {
            alert = LibraryAlert(title: "UI 冒烟数据失败", message: error.localizedDescription)
        }
    }

    private func installPickerSmokeInput() {
        let folder = libraryURL.deletingLastPathComponent()
            .appendingPathComponent("PickerSmokeInbox", isDirectory: true)
        let file = folder.appendingPathComponent("picker-fixture.png")
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLxVQAAAABJRU5ErkJggg==")!
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: file, options: .atomic)
        } catch {
            alert = LibraryAlert(title: "UI 选择器数据失败", message: error.localizedDescription)
        }
    }
#endif
}

enum LibraryScope: Equatable {
    case all
    case recent
    case favorites
}

struct FavoritePageItem: Identifiable, Hashable {
    let book: Book
    let page: Int

    var id: String { "\(book.id.uuidString)-\(page)" }
}

private enum LibraryStoreError: LocalizedError {
    case importInProgress

    var errorDescription: String? { "正在整理另一本书，请稍后再试。" }
}
