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
    private(set) var shelfGroups: [ShelfGroup] = []
    private(set) var isImporting = false
    private(set) var importStatusText: String?
    private(set) var importNotice: String?
    private(set) var optimizingBookID: UUID?
    private(set) var storageOptimizationProgress: Double?
    private(set) var measuredStorageSizes: [UUID: Int64] = [:]
    var alert: LibraryAlert?

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let metadataURL: URL
    @ObservationIgnored private let metadataRepository: LibraryMetadataRepository
    @ObservationIgnored private let groupsURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var pageURLCache: [UUID: [URL]] = [:]
    let libraryURL: URL

    init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        documentsURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        let documents = documentsURL ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = documents.appendingPathComponent("InkShelf Library", isDirectory: true)
        let metadata = root.appendingPathComponent("library.json")
        libraryURL = root
        metadataURL = metadata
        metadataRepository = LibraryMetadataRepository(primaryURL: metadata)
        groupsURL = root.appendingPathComponent("shelf-groups.json")
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
        loadShelfGroups()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_SEED")
            || ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_NIGHT") {
            installReaderNavigationSmokeBook()
        }
        if ProcessInfo.processInfo.arguments.contains("INKSHELF_UI_TEST_PICKER") {
            installPickerSmokeInput()
        }
#endif
    }

    var storageUsage: Int64 {
        books.reduce(0) { $0 + storageSize(for: $1) }
    }

    func storageSize(for book: Book) -> Int64 {
        measuredStorageSizes[book.id] ?? book.fileSize
    }

    func refreshStorageMeasurements() async {
        let rootURL = libraryURL
        let snapshot = books.map { ($0.id, $0.folderName) }
        let measured = await Task.detached(priority: .utility) {
            var result: [UUID: Int64] = [:]
            for (id, folderName) in snapshot {
                let folder = rootURL.appendingPathComponent(folderName, isDirectory: true)
                let enumerator = FileManager.default.enumerator(
                    at: folder,
                    includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
                )
                var total: Int64 = 0
                while let url = enumerator?.nextObject() as? URL {
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                    if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
                }
                result[id] = total
            }
            return result
        }.value
        measuredStorageSizes = measured
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

    var afterDarkBooks: [Book] {
        books
            .filter(\.belongsToAfterDark)
            .sorted {
                let left = $0.lastOpenedAt ?? $0.importedAt
                let right = $1.lastOpenedAt ?? $1.importedAt
                return left > right
            }
    }

    var interruptedReadingBook: Book? {
        guard let value = defaults.string(forKey: Self.activeReaderKey),
              let id = UUID(uuidString: value),
              let book = books.first(where: { $0.id == id })
        else { return nil }
        return book
    }

    func filteredBooks(
        scope: LibraryScope,
        query: String,
        sortOrder: LibrarySortOrder = .lastOpened,
        status: ReadingStatusFilter = .all
    ) -> [Book] {
        LibraryQuery(
            scope: scope,
            searchText: query,
            sortOrder: sortOrder,
            status: status
        ).apply(to: books)
    }

    func cachedBook(remoteID: String, modifiedAt: String? = nil) -> Book? {
        books.first {
            $0.remoteSourceID == remoteID && (modifiedAt == nil || $0.remoteModifiedAt == modifiedAt)
        }
    }

    func importFiles(
        _ urls: [URL],
        cleanupDirectory: URL? = nil,
        removeSourcesAfterImport: Bool = false,
        shelfGroupID: UUID? = nil,
        favoriteOnImport: Bool = false
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
                var imported = try await BookImporter.importBooks(from: urls, into: destination)
                let destinationGroupID = shelfGroupID.flatMap { requestedID in
                    shelfGroups.contains(where: { $0.id == requestedID }) ? requestedID : nil
                }
                for index in imported.indices {
                    imported[index].shelfGroupID = destinationGroupID
                    imported[index].isFavorite = favoriteOnImport
                }
                books.append(contentsOf: imported)
                saveImmediately()
                let destinationName = destinationGroupID.flatMap { id in
                    shelfGroups.first(where: { $0.id == id })?.title
                }
                if favoriteOnImport {
                    importNotice = imported.count == 1
                        ? "“\(imported[0].title)”已放进珍藏角落"
                        : "已把 \(imported.count) 组图片放进珍藏角落"
                } else if let destinationName {
                    importNotice = imported.count == 1
                        ? "“\(imported[0].title)”已放进“\(destinationName)”"
                        : "已把 \(imported.count) 本读物放进“\(destinationName)”"
                } else {
                    importNotice = imported.count == 1
                        ? "“\(imported[0].title)”已经回到书架"
                        : "已把 \(imported.count) 本读物带回小家"
                }
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
        if book.storageState == .coverOnly {
            return LibraryAlert(
                title: "这里只留下了封面",
                message: "你之前清理了这本读物的本地内容。如需重新阅读，请再次导入原文件；同名书会作为新项目回到书架。"
            )
        }
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
            book.shelfGroupID = old.shelfGroupID
            book.isAfterDark = old.isAfterDark
            book.mood = old.mood
            book.tags = old.tags
            book.personalNote = old.personalNote
            book.heartRating = old.heartRating
            book.spiceRating = old.spiceRating
            book.readerProfile = old.readerProfile
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

    func toggleAfterDark(_ id: UUID) {
        guard let index = books.firstIndex(where: { $0.id == id }) else { return }
        books[index].isAfterDark = !books[index].belongsToAfterDark
        saveImmediately()
        importNotice = books[index].belongsToAfterDark ? "已加入成年人夜读" : "已移出成年人夜读"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            self?.importNotice = nil
        }
    }

    func updateBookProfile(
        bookID: UUID,
        isAfterDark: Bool,
        mood: BookMood?,
        tags: [String],
        personalNote: String,
        heartRating: Int,
        spiceRating: Int
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        var seen = Set<String>()
        let normalizedTags = tags.compactMap { value -> String? in
            let cleaned = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
            guard !cleaned.isEmpty, seen.insert(cleaned.lowercased()).inserted else { return nil }
            return cleaned
        }
        let note = String(personalNote.trimmingCharacters(in: .whitespacesAndNewlines).prefix(600))
        books[index].isAfterDark = isAfterDark
        books[index].mood = mood
        books[index].tags = Array(normalizedTags.prefix(12))
        books[index].personalNote = note.isEmpty ? nil : note
        books[index].heartRating = min(max(heartRating, 0), 5)
        books[index].spiceRating = min(max(spiceRating, 0), 5)
        saveImmediately()
        importNotice = "“\(books[index].title)”的心动档案已保存"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            self?.importNotice = nil
        }
    }

    func updateReaderProfile(bookID: UUID, profile: BookReaderProfile) {
        guard let index = books.firstIndex(where: { $0.id == bookID }),
              books[index].readerProfile != profile
        else { return }
        books[index].readerProfile = profile
        scheduleSave()
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

    @discardableResult
    func createShelfGroup(title: String) -> ShelfGroup? {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let group = ShelfGroup(title: cleaned, styleIndex: shelfGroups.count)
        shelfGroups.append(group)
        saveShelfGroups()
        return group
    }

    func renameShelfGroup(_ id: UUID, to title: String) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let index = shelfGroups.firstIndex(where: { $0.id == id }) else { return }
        shelfGroups[index].title = cleaned
        saveShelfGroups()
    }

    func deleteShelfGroup(_ id: UUID) {
        shelfGroups.removeAll { $0.id == id }
        for index in books.indices where books[index].shelfGroupID == id {
            books[index].shelfGroupID = nil
        }
        saveShelfGroups()
        saveImmediately()
    }

    func assignBook(_ bookID: UUID, toShelfGroup groupID: UUID?) {
        guard groupID == nil || shelfGroups.contains(where: { $0.id == groupID }),
              let index = books.firstIndex(where: { $0.id == bookID })
        else { return }
        books[index].shelfGroupID = groupID
        saveImmediately()
        importNotice = groupID.flatMap { id in shelfGroups.first(where: { $0.id == id })?.title }
            .map { "已放进“\($0)”" } ?? "已移到未分组"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            self?.importNotice = nil
        }
    }

    func bookCount(inShelfGroup id: UUID) -> Int {
        books.filter { $0.shelfGroupID == id }.count
    }

    @discardableResult
    func prepareForAppUpdate(targetVersion: String, targetBuild: Int) throws -> URL {
        saveTask?.cancel()
        saveImmediately()
        saveShelfGroups()

        let backupsRoot = libraryURL.appendingPathComponent("Update Backups", isDirectory: true)
        try fileManager.createDirectory(at: backupsRoot, withIntermediateDirectories: true)
        let folderName = "build-\(AppIdentity.build)-to-\(targetBuild)-\(UUID().uuidString.prefix(8))"
        let backupURL = backupsRoot.appendingPathComponent(folderName, isDirectory: true)
        try fileManager.createDirectory(at: backupURL, withIntermediateDirectories: true)

        do {
            if fileManager.fileExists(atPath: metadataURL.path) {
                try fileManager.copyItem(
                    at: metadataURL,
                    to: backupURL.appendingPathComponent("library.json")
                )
            }
            if fileManager.fileExists(atPath: groupsURL.path) {
                try fileManager.copyItem(
                    at: groupsURL,
                    to: backupURL.appendingPathComponent("shelf-groups.json")
                )
            }

            let snapshot = UpdateSafetySnapshot(
                preparedAt: .now,
                sourceVersion: AppIdentity.version,
                sourceBuild: AppIdentity.build,
                targetVersion: targetVersion,
                targetBuild: targetBuild,
                bundleIdentifier: AppIdentity.bundleIdentifier,
                bookIDs: books.map(\.id),
                shelfGroupIDs: shelfGroups.map(\.id),
                bookCount: books.count,
                favoritePageCount: favoritePageItems.count,
                policy: "preserve_app_container"
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(
                to: backupURL.appendingPathComponent("update-safety.json"),
                options: .atomic
            )
            pruneUpdateBackups(in: backupsRoot, keeping: 3)
            return backupURL
        } catch {
            try? fileManager.removeItem(at: backupURL)
            throw error
        }
    }

    func optimizeStorage(bookID: UUID, mode: StorageRetentionMode) async {
        guard optimizingBookID == nil,
              let originalIndex = books.firstIndex(where: { $0.id == bookID })
        else { return }
        let book = books[originalIndex]
        let rootURL = libraryURL
        optimizingBookID = bookID
        storageOptimizationProgress = 0
        alert = nil
        do {
            let updated = try await Task.detached(priority: .userInitiated) {
                try StorageOptimizationService.optimize(book: book, libraryURL: rootURL, mode: mode) { progress in
                    Task { @MainActor [weak self] in
                        guard self?.optimizingBookID == bookID else { return }
                        self?.storageOptimizationProgress = progress
                    }
                }
            }.value
            guard let index = books.firstIndex(where: { $0.id == bookID }) else {
                optimizingBookID = nil
                storageOptimizationProgress = nil
                return
            }
            books[index] = updated
            pageURLCache.removeValue(forKey: updated.id)
            measuredStorageSizes[updated.id] = updated.fileSize
            saveImmediately()
            importNotice = mode == .previewOnly
                ? "“\(updated.title)”已换成省空间预览"
                : "“\(updated.title)”现在只保留封面"
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                self?.importNotice = nil
            }
        } catch {
            alert = LibraryAlert(
                title: "无法整理本地空间",
                message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            )
        }
        optimizingBookID = nil
        storageOptimizationProgress = nil
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
            pageURLCache.removeValue(forKey: book.id)
            measuredStorageSizes.removeValue(forKey: book.id)
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
        if let cached = pageURLCache[book.id] { return cached }
        let folder = contentURL(for: book)
        let urls = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sorted = NaturalSort.urls(urls.filter { url in
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            return isFile
        })
        pageURLCache[book.id] = sorted
        return sorted
    }

    func flushProgress() {
        saveTask?.cancel()
        saveImmediately()
    }

    private func load() {
        do {
            let result = try metadataRepository.load()
            books = result.books
                .filter {
                    $0.storageState == .coverOnly || fileManager.fileExists(atPath: contentURL(for: $0).path)
                }
            if result.recoveredFromBackup {
                alert = LibraryAlert(title: "书架已自动恢复", message: "主索引出现异常，已从最近一份完整快照恢复，画册文件没有受到影响。")
            }
            if let value = defaults.string(forKey: Self.activeReaderKey),
               let id = UUID(uuidString: value),
               !books.contains(where: { $0.id == id }) {
                defaults.removeObject(forKey: Self.activeReaderKey)
            }
        } catch {
            alert = LibraryAlert(title: "书架数据需要修复", message: "本地文件仍然保留，但书架索引无法读取：\(error.localizedDescription)")
        }
    }

    private func loadShelfGroups() {
        guard let data = try? Data(contentsOf: groupsURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            shelfGroups = try decoder.decode([ShelfGroup].self, from: data)
            let validIDs = Set(shelfGroups.map(\.id))
            var repaired = false
            for index in books.indices {
                if let id = books[index].shelfGroupID, !validIDs.contains(id) {
                    books[index].shelfGroupID = nil
                    repaired = true
                }
            }
            if repaired { saveImmediately() }
        } catch {
            alert = LibraryAlert(
                title: "分组数据需要修复",
                message: "书籍仍然保留，但分组列表无法读取：\(error.localizedDescription)"
            )
        }
    }

    private func saveShelfGroups() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(shelfGroups).write(to: groupsURL, options: .atomic)
        } catch {
            alert = LibraryAlert(title: "无法保存分组", message: error.localizedDescription)
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
            try metadataRepository.save(books)
        } catch {
            alert = LibraryAlert(title: "无法保存书架", message: error.localizedDescription)
        }
    }

    private func pruneUpdateBackups(in root: URL, keeping limit: Int) {
        guard let folders = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey]
        ) else { return }
        let sorted = folders.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted {
            let left = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return left > right
        }
        for folder in sorted.dropFirst(max(1, limit)) {
            try? fileManager.removeItem(at: folder)
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
                coverRelativePath: "\(id.uuidString.lowercased())/pages/000001.png",
                pageCount: 1,
                fileSize: Int64(png.count),
                isAfterDark: true,
                mood: .teasing,
                tags: ["御姐", "暧昧"],
                personalNote: "测试今晚的心动档案",
                heartRating: 5,
                spiceRating: 4
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

struct FavoritePageItem: Identifiable, Hashable {
    let book: Book
    let page: Int

    var id: String { "\(book.id.uuidString)-\(page)" }
}

private enum LibraryStoreError: LocalizedError {
    case importInProgress

    var errorDescription: String? { "正在整理另一本书，请稍后再试。" }
}
