import XCTest
import ImageIO
import UniformTypeIdentifiers
import UIKit
import ZIPFoundation
@testable import InkShelf

final class BookModelTests: XCTestCase {
    func testProgressUsesLastPageAsCompletion() {
        let book = makeBook(pageCount: 11, currentPage: 5)
        XCTAssertEqual(book.progress, 0.5, accuracy: 0.0001)
    }

    func testCurrentPageIsClampedAtInitialization() {
        let book = makeBook(pageCount: 3, currentPage: 50)
        XCTAssertEqual(book.currentPage, 2)
    }

    func testNaturalSortKeepsComicPageOrder() {
        let urls = ["10.jpg", "2.jpg", "1.jpg"].map { URL(fileURLWithPath: "/tmp/\($0)") }
        XCTAssertEqual(NaturalSort.urls(urls).map(\.lastPathComponent), ["1.jpg", "2.jpg", "10.jpg"])
    }

    func testEBookProgressIncludesProgressInsideChapter() {
        let book = Book(
            title: "电子书",
            kind: .ebook,
            sourceFileName: "test.epub",
            contentRelativePath: "test/ebook.json",
            pageCount: 10,
            currentPage: 4,
            fileSize: 100,
            ebookChapterProgress: 0.5
        )
        XCTAssertEqual(book.progress, 0.45, accuracy: 0.0001)
    }

    func testEBookPackageRoundTripsThroughJSON() throws {
        let package = EBookPackage(
            title: "测试书",
            author: "作者",
            format: .epub,
            chapters: [EBookChapter(id: "one", title: "第一章", relativePath: "one.xhtml", searchText: "正文")],
            resourceRootRelativePath: "publication"
        )
        let data = try JSONEncoder().encode(package)
        XCTAssertEqual(try JSONDecoder().decode(EBookPackage.self, from: data), package)
    }

    func testRemoteBookPayloadDecodes() throws {
        let json = """
        {
          "id": "0123456789abcdef",
          "name": "画集.epub",
          "size": 4096,
          "format": "epub",
          "content_type": "application/epub+zip",
          "imported_at": "2026-08-11T12:00:00+07:00",
          "modified_at": "2026-08-11T12:00:00+07:00",
          "download_url": "/inkshelf-api/books/0123456789abcdef/file",
          "cover_url": "/inkshelf-api/books/0123456789abcdef/cover",
          "progress": {"progress": 0.42, "position": 3, "updated_at": "2026-08-11T12:30:00+07:00"}
        }
        """
        let book = try JSONDecoder().decode(RemoteBook.self, from: Data(json.utf8))
        XCTAssertEqual(book.title, "画集")
        XCTAssertEqual(book.kind, .ebook)
        XCTAssertEqual(book.progress?.position, 3)
    }

    func testRemoteOriginSurvivesBookMetadataRoundTrip() throws {
        var book = makeBook(pageCount: 12, currentPage: 2)
        book.remoteSourceID = "0123456789abcdef"
        book.remoteModifiedAt = "2026-08-11T12:00:00+07:00"
        let decoded = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(decoded.remoteSourceID, book.remoteSourceID)
        XCTAssertEqual(decoded.remoteModifiedAt, book.remoteModifiedAt)
    }

    func testAfterDarkProfileRoundTripsAndClampsRatings() throws {
        var book = makeBook(pageCount: 12, currentPage: 2)
        book.isAfterDark = true
        book.mood = .teasing
        book.tags = ["御姐", "暧昧"]
        book.personalNote = "今晚最喜欢这一本"
        book.heartRating = 9
        book.spiceRating = -2

        let decoded = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(book))
        XCTAssertTrue(decoded.belongsToAfterDark)
        XCTAssertEqual(decoded.mood, .teasing)
        XCTAssertEqual(decoded.normalizedTags, ["御姐", "暧昧"])
        XCTAssertEqual(decoded.normalizedHeartRating, 5)
        XCTAssertEqual(decoded.normalizedSpiceRating, 0)
    }

    func testLegacyBookWithoutAfterDarkFieldsStillDecodes() throws {
        let json = """
        {
          "id": "A11CE000-0000-4000-8000-000000000099",
          "title": "旧版画集",
          "kind": "imageCollection",
          "sourceFileName": "旧版画集",
          "contentRelativePath": "legacy/pages",
          "pageCount": 8,
          "currentPage": 1,
          "importedAt": "2026-08-01T00:00:00Z",
          "fileSize": 128,
          "isFavorite": false
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let book = try decoder.decode(Book.self, from: Data(json.utf8))
        XCTAssertFalse(book.belongsToAfterDark)
        XCTAssertNil(book.mood)
        XCTAssertTrue(book.normalizedTags.isEmpty)
    }

    @MainActor
    func testAfterDarkProfilePersistsAcrossLibraryReload() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "InkShelfAfterDarkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? fileManager.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let id = UUID()
        let library = root.appendingPathComponent("InkShelf Library", isDirectory: true)
        let pages = library.appendingPathComponent(id.uuidString.lowercased()).appendingPathComponent("pages")
        try fileManager.createDirectory(at: pages, withIntermediateDirectories: true)
        try testPNG(color: .systemPink).write(to: pages.appendingPathComponent("001.png"))
        let book = Book(
            id: id,
            title: "夜读持久化",
            kind: .imageCollection,
            sourceFileName: "夜读持久化",
            contentRelativePath: "\(id.uuidString.lowercased())/pages",
            pageCount: 1,
            fileSize: 128
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([book]).write(to: library.appendingPathComponent("library.json"))

        var store: LibraryStore? = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        store?.updateBookProfile(
            bookID: id,
            isAfterDark: true,
            mood: .glamorous,
            tags: ["御姐", "御姐", "  魅惑  "],
            personalNote: "成熟角色的气场很漂亮",
            heartRating: 5,
            spiceRating: 4
        )
        XCTAssertEqual(store?.afterDarkBooks.map(\.id), [id])
        XCTAssertEqual(store?.books.first?.normalizedTags, ["御姐", "魅惑"])
        store = nil

        let restored = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        let profile = try XCTUnwrap(restored.books.first)
        XCTAssertTrue(profile.belongsToAfterDark)
        XCTAssertEqual(profile.mood, .glamorous)
        XCTAssertEqual(profile.normalizedHeartRating, 5)
        XCTAssertEqual(profile.normalizedSpiceRating, 4)
        XCTAssertEqual(profile.personalNote, "成熟角色的气场很漂亮")
    }

    func testICloudBookIdentityIsStableAcrossScans() {
        let folderID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let first = ICloudBook.stableID(folderID: folderID, relativePath: "anmi/画集 01.cbz")
        let second = ICloudBook.stableID(folderID: folderID, relativePath: "anmi/画集 01.cbz")
        let another = ICloudBook.stableID(folderID: folderID, relativePath: "anmi/画集 02.cbz")
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first, another)
    }

    func testICloudBookRoundTripsWithoutBookmarkOrFileContents() throws {
        let book = ICloudBook(
            id: "1234567890abcdef12345678",
            folderID: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            relativePath: "kantoku/sample.cbz",
            name: "sample.cbz",
            collection: "kantoku",
            size: 1_024,
            modifiedAt: Date(timeIntervalSince1970: 123_456),
            format: "cbz"
        )
        let decoded = try JSONDecoder().decode(ICloudBook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(decoded, book)
        XCTAssertEqual(decoded.kind, .archive)
        XCTAssertEqual(decoded.sourceID, "icloud:1234567890abcdef12345678")
    }

    func testGenericFileProviderDataIsSelectable() {
        XCTAssertTrue(UTType.inkShelfFileTypes.contains(.data))
        XCTAssertTrue(UTType.comicBookArchive.conforms(to: .zip))
    }

    func testXPostLinksAreStrictlyNormalizedForSocialImport() {
        let service = SocialPostImportService.shared
        XCTAssertEqual(
            service.normalizedPostURL("https://x.com/kemari_kkr/status/2033518392037257415?s=20")?.absoluteString,
            "https://x.com/kemari_kkr/status/2033518392037257415"
        )
        XCTAssertEqual(
            service.normalizedPostURL("https://mobile.twitter.com/artist/status/1234567890/photo/1")?.absoluteString,
            "https://x.com/artist/status/1234567890"
        )
        XCTAssertNil(service.normalizedPostURL("https://example.com/artist/status/1234567890"))
        XCTAssertNil(service.normalizedPostURL("http://x.com/artist/status/1234567890"))
    }

    func testAITranslationRoundTripsAndOldReactionStillDecodes() throws {
        let translation = AIPageTranslation(
            detectedJapanese: true,
            title: "本页日文翻译",
            segments: [
                AITranslationSegment(
                    source: "おかえり！",
                    translation: "欢迎回家！",
                    role: .dialogue,
                    speaker: "少女"
                )
            ],
            note: "语气很亲近"
        )
        let reaction = AIPageReaction(
            page: 0,
            summary: "角色回到了家",
            mood: "温暖",
            danmaku: [],
            talkingPoints: [],
            translation: translation
        )
        let data = try JSONEncoder().encode(reaction)
        let decoded = try JSONDecoder().decode(AIPageReaction.self, from: data)
        XCTAssertEqual(decoded.translation?.segments.first?.translation, "欢迎回家！")

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "translation")
        legacy.removeValue(forKey: "source")
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let legacyReaction = try JSONDecoder().decode(AIPageReaction.self, from: legacyData)
        XCTAssertNil(legacyReaction.translation)
        XCTAssertNil(legacyReaction.source)
        XCTAssertFalse(legacyReaction.isLocalFallback)
    }

    func testAIReliabilityConfigurationRejectsUnsafeRemoteValues() {
        XCTAssertNotNil(AIReliabilityConfiguration.bundled.validated(forBuild: 15))
        let unsafe = AIReliabilityConfiguration(
            schema: 1,
            revision: 1,
            minimumBuild: 15,
            requestTimeoutSeconds: 5,
            maximumAttempts: 20,
            retryBaseDelayMilliseconds: 1
        )
        XCTAssertNil(unsafe.validated(forBuild: 15))
    }

    func testLocalCompanionFallbackAlwaysProducesVisiblePageContent() {
        let insight = AIPageInsight(
            page: 4,
            pageCount: 20,
            recognizedText: "おかえり",
            visualLabels: ["illustration"],
            faceCount: 1,
            sourceKind: "画集"
        )
        let settings = DeepSeekPageSettings(
            model: .pro,
            persona: .friend,
            density: .balanced,
            strictSpoilers: true,
            includeRecognizedText: true,
            allowsCellularAccess: true
        )
        let reaction = LocalCompanionFallback.pageReaction(insight: insight, settings: settings)
        XCTAssertTrue(reaction.isLocalFallback)
        XCTAssertEqual(reaction.page, 4)
        XCTAssertEqual(reaction.danmaku.count, AIDanmakuDensity.balanced.messageCount)
        XCTAssertFalse(reaction.summary.isEmpty)
    }

    func testLocalCompanionFallbackKeepsAfterDarkPersonaWhenCloudIsUnavailable() {
        let insight = AIPageInsight(
            page: 1,
            pageCount: 12,
            recognizedText: "",
            visualLabels: ["illustration"],
            faceCount: 1,
            sourceKind: "画集"
        )
        let settings = DeepSeekPageSettings(
            model: .pro,
            persona: .bold,
            density: .balanced,
            strictSpoilers: true,
            includeRecognizedText: true,
            allowsCellularAccess: true
        )
        let reaction = LocalCompanionFallback.pageReaction(insight: insight, settings: settings)
        XCTAssertTrue(reaction.isLocalFallback)
        XCTAssertEqual(reaction.mood, "本地大胆陪伴")
        XCTAssertTrue(reaction.danmaku.contains { $0.text.contains("张力") || $0.text.contains("涩气") })
    }

    func testCoordinatedCopyPreservesOriginalBytes() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let source = root.appendingPathComponent("sample.cbz")
        let destination = root.appendingPathComponent("copy.cbz")
        let original = Data([0x50, 0x4B, 0x03, 0x04, 0x01, 0x02, 0x03])
        try original.write(to: source)
        let copied = try await Task.detached {
            try ExternalFileAccess.copyItem(from: source, to: destination)
            return try Data(contentsOf: destination)
        }.value

        XCTAssertEqual(copied, original)
    }

    @MainActor
    func testLocalCBZPDFFolderSmokeImport() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let archivePages = root.appendingPathComponent("archive-pages", isDirectory: true)
        let gallery = root.appendingPathComponent("本地画集", isDirectory: true)
        try fileManager.createDirectory(at: archivePages, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: gallery, withIntermediateDirectories: true)
        try testPNG(color: .systemPink).write(to: archivePages.appendingPathComponent("001.png"))
        try testPNG(color: .systemBlue).write(to: archivePages.appendingPathComponent("002.png"))
        try testPNG(color: .systemMint).write(to: gallery.appendingPathComponent("001.png"))

        let cbz = root.appendingPathComponent("冒烟漫画.cbz")
        try fileManager.zipItem(at: archivePages, to: cbz, shouldKeepParent: false)
        let originalArchiveBytes = try Data(contentsOf: cbz)

        let pdf = root.appendingPathComponent("冒烟 PDF.pdf")
        let pdfData = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 320, height: 480)).pdfData { context in
            context.beginPage()
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 320, height: 480))
            UIColor.systemPurple.setFill()
            context.cgContext.fill(CGRect(x: 32, y: 32, width: 256, height: 416))
        }
        try pdfData.write(to: pdf)

        let documents = root.appendingPathComponent("app-documents", isDirectory: true)
        let suiteName = "InkShelfImportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: documents)
        store.importFiles([cbz, pdf, gallery], removeSourcesAfterImport: true)

        for _ in 0..<400 where store.isImporting {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(store.isImporting, "The document-picker import pipeline did not finish in ten seconds")
        XCTAssertNil(store.alert)
        let imported = store.books

        XCTAssertEqual(imported.count, 3)
        XCTAssertEqual(imported.first(where: { $0.kind == .archive })?.pageCount, 2)
        XCTAssertEqual(imported.first(where: { $0.kind == .pdf })?.pageCount, 1)
        XCTAssertEqual(imported.first(where: { $0.kind == .imageCollection })?.pageCount, 1)
        XCTAssertEqual(store.imageCollectionBooks.count, 1)
        XCTAssertTrue(store.favoritePageItems.isEmpty, "Imported images must not be mixed with pages favorited in the reader")
        let archiveBook = try XCTUnwrap(imported.first(where: { $0.kind == .archive }))
        let importedSource = try XCTUnwrap(store.sourceURL(for: archiveBook))
        XCTAssertEqual(try Data(contentsOf: importedSource), originalArchiveBytes)
        XCTAssertNil(store.openingError(for: archiveBook))
        XCTAssertNotNil(store.importNotice)

        XCTAssertFalse(fileManager.fileExists(atPath: cbz.path), "The picker-owned CBZ copy should be cleaned up")
        XCTAssertFalse(fileManager.fileExists(atPath: pdf.path), "The picker-owned PDF copy should be cleaned up")
        XCTAssertFalse(fileManager.fileExists(atPath: gallery.path), "The picker-owned folder copy should be cleaned up")

        try fileManager.removeItem(at: store.contentURL(for: archiveBook))
        XCTAssertNotNil(store.openingError(for: archiveBook), "A missing page directory must produce visible feedback")
    }

    @MainActor
    func testSelectedFolderBulkImportsEveryBookAndUsesFirstPageCover() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        let selectedFolder = root.appendingPathComponent("批量书库", isDirectory: true)
        let archivePages = root.appendingPathComponent("zip-pages", isDirectory: true)
        let imageAlbum = selectedFolder.appendingPathComponent("插画集", isDirectory: true)
        try fileManager.createDirectory(at: archivePages, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: imageAlbum, withIntermediateDirectories: true)
        try testPNG(color: .systemPink).write(to: archivePages.appendingPathComponent("001.png"))
        try testPNG(color: .systemBlue).write(to: archivePages.appendingPathComponent("002.png"))
        try testPNG(color: .systemMint).write(to: imageAlbum.appendingPathComponent("001.png"))
        try testPNG(color: .systemOrange).write(to: imageAlbum.appendingPathComponent("002.png"))

        let firstCBZ = selectedFolder.appendingPathComponent("第一本.cbz")
        let secondCBZ = selectedFolder.appendingPathComponent("子目录/第二本.cbz")
        try fileManager.createDirectory(at: secondCBZ.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.zipItem(at: archivePages, to: firstCBZ, shouldKeepParent: false)
        try fileManager.copyItem(at: firstCBZ, to: secondCBZ)

        let documents = root.appendingPathComponent("app-documents", isDirectory: true)
        let suiteName = "InkShelfFolderBatchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: documents)
        store.importFiles([selectedFolder])

        for _ in 0..<600 where store.isImporting {
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertFalse(store.isImporting, "Bulk folder import did not finish in fifteen seconds")
        XCTAssertNil(store.alert)
        XCTAssertEqual(store.books.filter { $0.kind == .archive }.count, 2)
        XCTAssertEqual(store.books.filter { $0.kind == .imageCollection }.count, 1)
        XCTAssertEqual(store.books.count, 3)
        XCTAssertTrue(fileManager.fileExists(atPath: selectedFolder.path), "A linked source folder must never be deleted")
        XCTAssertTrue(store.books.allSatisfy { ($0.previewRelativePaths ?? []).count <= 1 })
    }

    @MainActor
    func testInterruptedReadingSessionRestoresOnlyUntilReaderCloses() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "InkShelfTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? fileManager.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let id = UUID()
        let library = root.appendingPathComponent("InkShelf Library", isDirectory: true)
        try fileManager.createDirectory(
            at: library.appendingPathComponent(id.uuidString.lowercased()).appendingPathComponent("pages"),
            withIntermediateDirectories: true
        )
        let book = Book(
            id: id,
            title: "恢复现场",
            kind: .imageCollection,
            sourceFileName: "恢复现场",
            contentRelativePath: "\(id.uuidString.lowercased())/pages",
            pageCount: 20,
            currentPage: 7,
            fileSize: 1
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([book]).write(to: library.appendingPathComponent("library.json"))
        defaults.set(id.uuidString, forKey: "reader.activeBookID")

        let store = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        XCTAssertEqual(store.interruptedReadingBook?.id, id)
        XCTAssertEqual(store.interruptedReadingBook?.currentPage, 7)
        store.endReading(id)
        XCTAssertNil(store.interruptedReadingBook)
    }

    func testOlderBookMetadataDecodesWithoutFavoritePages() throws {
        let original = makeBook(pageCount: 8, currentPage: 2)
        let data = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "favoritePages")
        object.removeValue(forKey: "shelfGroupID")
        let decoded = try JSONDecoder().decode(
            Book.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertNil(decoded.favoritePages)
        XCTAssertNil(decoded.shelfGroupID)
        XCTAssertEqual(decoded.currentPage, 2)
        XCTAssertEqual(decoded.storageState, .full)
    }

    @MainActor
    func testShelfGroupsPersistAndDeletingGroupKeepsBook() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "InkShelfGroupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? fileManager.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let bookID = UUID()
        let library = root.appendingPathComponent("InkShelf Library", isDirectory: true)
        let pages = library.appendingPathComponent(bookID.uuidString.lowercased()).appendingPathComponent("pages")
        try fileManager.createDirectory(at: pages, withIntermediateDirectories: true)
        try testPNG(color: .systemCyan).write(to: pages.appendingPathComponent("001.png"))
        let book = Book(
            id: bookID,
            title: "分组测试画集",
            kind: .imageCollection,
            sourceFileName: "分组测试画集",
            contentRelativePath: "\(bookID.uuidString.lowercased())/pages",
            pageCount: 1,
            fileSize: 1
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([book]).write(to: library.appendingPathComponent("library.json"))

        var store: LibraryStore? = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        let group = try XCTUnwrap(store?.createShelfGroup(title: "温暖收藏"))
        store?.assignBook(bookID, toShelfGroup: group.id)
        XCTAssertEqual(store?.bookCount(inShelfGroup: group.id), 1)
        store = nil

        store = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        XCTAssertEqual(store?.shelfGroups.first?.title, "温暖收藏")
        XCTAssertEqual(store?.books.first?.shelfGroupID, group.id)
        store?.deleteShelfGroup(group.id)
        XCTAssertEqual(store?.books.count, 1)
        XCTAssertNil(store?.books.first?.shelfGroupID)
        XCTAssertTrue(store?.shelfGroups.isEmpty == true)
    }

    @MainActor
    func testImportCanLandDirectlyInSelectedGroupAndFavorites() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "InkShelfPlacedImportTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? fileManager.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let image = root.appendingPathComponent("来自 X 的珍藏.png")
        try testPNG(color: .systemPink).write(to: image)
        let store = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        let group = try XCTUnwrap(store.createShelfGroup(title: "画师收藏"))

        store.importFiles([image], shelfGroupID: group.id, favoriteOnImport: true)
        for _ in 0..<400 where store.isImporting {
            try await Task.sleep(for: .milliseconds(25))
        }

        let imported = try XCTUnwrap(store.books.first)
        XCTAssertEqual(imported.shelfGroupID, group.id)
        XCTAssertTrue(imported.isFavorite)
        XCTAssertEqual(store.filteredBooks(scope: .favorites, query: "").map(\.id), [imported.id])
    }

    @MainActor
    func testPageFavoritePersistsAndAppearsInFavoritePageItems() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "InkShelfFavoritePageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? fileManager.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let id = UUID()
        let library = root.appendingPathComponent("InkShelf Library", isDirectory: true)
        let pages = library.appendingPathComponent(id.uuidString.lowercased()).appendingPathComponent("pages")
        try fileManager.createDirectory(at: pages, withIntermediateDirectories: true)
        try testPNG(color: .systemIndigo).write(to: pages.appendingPathComponent("001.png"))
        try testPNG(color: .systemPink).write(to: pages.appendingPathComponent("002.png"))
        let book = Book(
            id: id,
            title: "单页珍藏",
            kind: .imageCollection,
            sourceFileName: "单页珍藏",
            contentRelativePath: "\(id.uuidString.lowercased())/pages",
            pageCount: 2,
            fileSize: 2
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([book]).write(to: library.appendingPathComponent("library.json"))

        var store: LibraryStore? = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        store?.togglePageFavorite(bookID: id, page: 1)
        XCTAssertTrue(store?.isPageFavorite(bookID: id, page: 1) == true)
        XCTAssertEqual(store?.favoritePageItems.first?.page, 1)
        store = nil

        let restored = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        XCTAssertTrue(restored.isPageFavorite(bookID: id, page: 1))
        restored.togglePageFavorite(bookID: id, page: 1)
        XCTAssertFalse(restored.isPageFavorite(bookID: id, page: 1))
    }

    func testPDFPageRendersToHighResolutionPNG() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 320, height: 480)).pdfData { context in
            context.beginPage()
            UIColor.systemTeal.setFill()
            context.cgContext.fill(CGRect(x: 20, y: 20, width: 280, height: 440))
        }
        try data.write(to: url)
        let png = try ReaderPageSaveService.renderedPDFPageData(url: url, page: 0, password: "")
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertEqual(image.size.width, 1_280, accuracy: 1)
        XCTAssertEqual(image.size.height, 1_920, accuracy: 1)
    }

    func testEveryAIWritingPurposeHasUsableCopy() {
        XCTAssertEqual(AIWritingPurpose.allCases.count, 7)
        for purpose in AIWritingPurpose.allCases {
            XCTAssertFalse(purpose.title.isEmpty)
            XCTAssertFalse(purpose.promptDescription.isEmpty)
            XCTAssertFalse(purpose.systemImage.isEmpty)
        }
    }

    func testEveryAICompanionPersonaHasUsableAndSafeCopy() {
        XCTAssertEqual(AICompanionPersona.allCases.count, 6)
        for persona in AICompanionPersona.allCases {
            XCTAssertFalse(persona.title.isEmpty)
            XCTAssertFalse(persona.promptDescription.isEmpty)
            XCTAssertFalse(persona.systemImage.isEmpty)
            if persona.isAfterDark {
                XCTAssertTrue(persona.promptDescription.contains("成年"))
            }
        }
    }

    @MainActor
    func testImageBookCanBecomeLowQualityPreviewWithoutTouchingCover() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let id = UUID()
        let folder = root.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        let pages = folder.appendingPathComponent("pages", isDirectory: true)
        try fileManager.createDirectory(at: pages, withIntermediateDirectories: true)
        let cover = folder.appendingPathComponent("cover.jpg")
        try testPNG(color: .systemOrange).write(to: cover)
        try testPNG(color: .systemPurple).write(to: pages.appendingPathComponent("001.png"))
        try testPNG(color: .systemBlue).write(to: pages.appendingPathComponent("002.png"))
        let source = folder.appendingPathComponent("source.cbz")
        try Data(repeating: 0x42, count: 100).write(to: source)
        let book = Book(
            id: id,
            title: "省空间测试",
            kind: .archive,
            sourceFileName: "source.cbz",
            contentRelativePath: "\(id.uuidString.lowercased())/pages",
            sourceRelativePath: "\(id.uuidString.lowercased())/source.cbz",
            coverRelativePath: "\(id.uuidString.lowercased())/cover.jpg",
            pageCount: 2,
            fileSize: 1_000
        )

        let optimized = try StorageOptimizationService.optimize(book: book, libraryURL: root, mode: .previewOnly)
        XCTAssertEqual(optimized.storageState, .previewOnly)
        XCTAssertEqual(optimized.kind, .imageCollection)
        XCTAssertEqual(optimized.pageCount, 2)
        XCTAssertTrue(fileManager.fileExists(atPath: cover.path))
        XCTAssertFalse(fileManager.fileExists(atPath: source.path))
        XCTAssertEqual(
            try fileManager.contentsOfDirectory(atPath: root.appendingPathComponent(optimized.contentRelativePath).path).count,
            2
        )
    }

    @MainActor
    func testCoverOnlyBookSurvivesLibraryReloadAndShowsOpeningMessage() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "InkShelfCoverOnlyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? fileManager.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }
        let id = UUID()
        let library = root.appendingPathComponent("InkShelf Library", isDirectory: true)
        let folder = library.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let coverPath = "\(id.uuidString.lowercased())/cover.jpg"
        try testPNG(color: .systemMint).write(to: library.appendingPathComponent(coverPath))
        let book = Book(
            id: id,
            title: "只留封面",
            kind: .pdf,
            sourceFileName: "gone.pdf",
            contentRelativePath: "\(id.uuidString.lowercased())/content-removed",
            coverRelativePath: coverPath,
            pageCount: 20,
            fileSize: 100,
            localStorageState: .coverOnly
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([book]).write(to: library.appendingPathComponent("library.json"))

        let store = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        XCTAssertEqual(store.books.first?.storageState, .coverOnly)
        XCTAssertEqual(store.openingError(for: book)?.title, "这里只留下了封面")
    }

    @MainActor
    func testReadingAchievementsUnlockAndPersist() throws {
        let suiteName = "InkShelfAchievementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AchievementStore(defaults: defaults)
        let bookID = UUID()
        store.recordOpened(bookID: bookID)
        store.recordFavoritedPage()
        store.recordPageTurn(bookID: bookID, reachedLastPage: true)
        XCTAssertTrue(store.footprint.unlockedAt.keys.contains("first-home"))
        XCTAssertTrue(store.footprint.unlockedAt.keys.contains("page-spark"))
        XCTAssertTrue(store.footprint.unlockedAt.keys.contains("first-finale"))

        let restored = AchievementStore(defaults: defaults)
        XCTAssertEqual(restored.footprint.openedBookIDs, Set([bookID]))
        XCTAssertEqual(restored.footprint.pagesTurned, 1)
        XCTAssertEqual(restored.unlockedCount, 3)
        restored.resetProgress()
        XCTAssertTrue(restored.footprint.openedBookIDs.isEmpty)
        XCTAssertEqual(restored.footprint.pagesTurned, 0)
        XCTAssertEqual(restored.unlockedCount, 0)
        XCTAssertNil(defaults.data(forKey: "reading.footprint.v1"))
    }

    func testReaderPagePositionKeepsSpreadLabelAndSliderInSync() {
        let spread = ReaderPagePosition(
            currentPage: 2,
            pageCount: 10,
            layout: .spread,
            flow: .horizontal,
            coverSingle: true,
            isEBook: false
        )
        XCTAssertEqual(spread.visibleRange, 1...2)
        XCTAssertEqual(spread.anchorPage, 1)
        XCTAssertEqual(spread.displayLabel, "第 2–3 页 · 共 10 页")
        XCTAssertEqual(spread.sliderValue(ebookProgress: 0), 2)
        XCTAssertEqual(spread.comicPage(forSliderValue: 2), 1)
        XCTAssertEqual(spread.comicPage(forSliderValue: 4), 3)
        XCTAssertEqual(spread.progressPercentage(ebookProgress: 0), 30)

        let firstCover = ReaderPagePosition(
            currentPage: 0,
            pageCount: 10,
            layout: .spread,
            flow: .vertical,
            coverSingle: true,
            isEBook: false
        )
        XCTAssertEqual(firstCover.visibleRange, 0...0)

        let continuous = ReaderPagePosition(
            currentPage: 2,
            pageCount: 10,
            layout: .spread,
            flow: .continuous,
            coverSingle: true,
            isEBook: false
        )
        XCTAssertEqual(continuous.visibleRange, 2...2)
    }

    func testEBookProgressScrubberIncludesChapterProgress() {
        let position = ReaderPagePosition(
            currentPage: 1,
            pageCount: 4,
            layout: .single,
            flow: .horizontal,
            coverSingle: true,
            isEBook: true
        )
        XCTAssertEqual(position.sliderValue(ebookProgress: 0.5), 1.5, accuracy: 0.0001)
        XCTAssertEqual(position.progressPercentage(ebookProgress: 0.5), 38)
        let target = position.ebookTarget(forSliderValue: 3.75)
        XCTAssertEqual(target.chapter, 3)
        XCTAssertEqual(target.progress, 0.75, accuracy: 0.0001)
        let ending = position.ebookTarget(forSliderValue: 4)
        XCTAssertEqual(ending.chapter, 3)
        XCTAssertEqual(ending.progress, 1, accuracy: 0.0001)
    }

    @MainActor
    func testAchievementStoreMigratesOldFootprintAndBuildsDailyQuests() throws {
        let oldJSON = """
        {
          "openedBookIDs": [],
          "completedBookIDs": [],
          "pagesTurned": 12,
          "readingSeconds": 90,
          "pagesSaved": 1,
          "pagesFavorited": 2,
          "unlockedAt": {}
        }
        """
        let migrated = try JSONDecoder().decode(ReadingFootprint.self, from: Data(oldJSON.utf8))
        XCTAssertEqual(migrated.pagesTurned, 12)
        XCTAssertEqual(migrated.homeVisits, 0)
        XCTAssertTrue(migrated.readingDayKeys.isEmpty)

        let suiteName = "InkShelfDailyQuestTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AchievementStore(defaults: defaults)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 12)))
        let second = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: first))
        let third = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: first))
        let bookID = UUID()
        store.recordOpened(bookID: bookID, at: first)
        store.recordOpened(bookID: bookID, at: second)
        store.recordOpened(bookID: bookID, at: third)
        for _ in 0..<10 { store.recordPageTurn(bookID: bookID, reachedLastPage: false, at: third) }
        store.recordReadingDuration(15 * 60, at: third)

        XCTAssertEqual(store.footprint.homeVisits, 3)
        XCTAssertEqual(store.footprint.longestReadingStreak, 3)
        XCTAssertEqual(store.dailyQuests(on: third).filter(\.isCompleted).count, 3)
        XCTAssertTrue(store.footprint.unlockedAt.keys.contains("three-day-lamp"))
    }

    func testUpdateVersionComparisonUsesVersionThenBuild() {
        let release = AppUpdateRelease(
            schema: 1,
            version: "1.8.0",
            build: 13,
            minimumIOS: "18.0",
            publishedAt: .now,
            title: "更新",
            notes: ["测试"],
            mandatory: false,
            bundleIdentifier: "com.inkshelf.reader",
            packageSize: 1024,
            sha256: nil,
            installURL: nil,
            dataPolicy: "preserve_app_container"
        )
        XCTAssertTrue(release.isNewer(thanVersion: "1.7.9", build: 99))
        XCTAssertTrue(release.isNewer(thanVersion: "1.8", build: 12))
        XCTAssertFalse(release.isNewer(thanVersion: "1.8.0", build: 13))
        XCTAssertFalse(release.isNewer(thanVersion: "1.9.0", build: 1))
        XCTAssertTrue(release.supports(systemVersion: "26.0.1"))
        XCTAssertTrue(release.preservesAppData)
    }

    func testReaderImagePipelineUsesStablePreviewAndReadingBuckets() {
        XCTAssertEqual(ReaderImagePipeline.pixelBucket(for: 360), 512)
        XCTAssertEqual(ReaderImagePipeline.pixelBucket(for: 640), 1_024)
        XCTAssertEqual(ReaderImagePipeline.pixelBucket(for: 1_024), 1_024)
        XCTAssertEqual(ReaderImagePipeline.pixelBucket(for: 1_800), 3_072)
        XCTAssertEqual(ReaderImagePipeline.pixelBucket(for: 4_096), 3_072)
    }

    func testLibraryQuerySearchesMetadataAndFiltersReadingState() {
        let now = Date(timeIntervalSince1970: 10_000)
        let unread = Book(
            title: "晨光画集",
            kind: .imageCollection,
            sourceFileName: "artist-special.zip",
            contentRelativePath: "unread/pages",
            pageCount: 20,
            importedAt: now.addingTimeInterval(-200),
            fileSize: 300,
            tags: ["御姐", "光影"]
        )
        let reading = Book(
            title: "夜色漫画",
            kind: .archive,
            sourceFileName: "night.cbz",
            contentRelativePath: "reading/pages",
            pageCount: 10,
            currentPage: 4,
            importedAt: now.addingTimeInterval(-100),
            lastOpenedAt: now,
            fileSize: 900,
            personalNote: "喜欢这一册的构图"
        )
        let finished = Book(
            title: "终章",
            kind: .pdf,
            sourceFileName: "final.pdf",
            contentRelativePath: "finished/source.pdf",
            pageCount: 5,
            currentPage: 4,
            importedAt: now,
            lastOpenedAt: now.addingTimeInterval(-50),
            fileSize: 500,
            isFavorite: true
        )

        let metadataSearch = LibraryQuery(
            scope: .all,
            searchText: "御姐 光影",
            sortOrder: .lastOpened,
            status: .all
        ).apply(to: [reading, finished, unread])
        XCTAssertEqual(metadataSearch.map(\.id), [unread.id])

        let inProgress = LibraryQuery(
            scope: .all,
            searchText: "构图",
            sortOrder: .progress,
            status: .reading
        ).apply(to: [unread, reading, finished])
        XCTAssertEqual(inProgress.map(\.id), [reading.id])

        let favorites = LibraryQuery(
            scope: .favorites,
            searchText: "pdf",
            sortOrder: .fileSize,
            status: .finished
        ).apply(to: [unread, reading, finished])
        XCTAssertEqual(favorites.map(\.id), [finished.id])
    }

    func testReaderProfileNormalizesInvalidPersistedValuesAndOffersContinuousFlow() {
        let profile = BookReaderProfile(
            layoutRaw: "unknown-layout",
            flowRaw: ReaderFlow.continuous.rawValue,
            orderRaw: "unknown-order",
            backdropRaw: "unknown-backdrop",
            coverSingle: false
        )
        XCTAssertEqual(profile.layoutRaw, ReaderLayout.single.rawValue)
        XCTAssertEqual(profile.flowRaw, ReaderFlow.continuous.rawValue)
        XCTAssertEqual(profile.orderRaw, ReadingOrder.leftToRight.rawValue)
        XCTAssertEqual(profile.backdropRaw, ReaderBackdrop.black.rawValue)
        XCTAssertFalse(profile.coverSingle)
        XCTAssertTrue(ReaderFlow.allCases.contains(.continuous))
    }

    @MainActor
    func testPerBookReaderProfilePersistsAcrossLibraryReload() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "InkShelfReaderProfileTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? fileManager.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let id = UUID()
        let libraryURL = root.appendingPathComponent("InkShelf Library", isDirectory: true)
        let pagesURL = libraryURL.appendingPathComponent(id.uuidString.lowercased()).appendingPathComponent("pages")
        try fileManager.createDirectory(at: pagesURL, withIntermediateDirectories: true)
        try testPNG(color: .systemTeal).write(to: pagesURL.appendingPathComponent("001.png"))
        let book = Book(
            id: id,
            title: "独立阅读预设",
            kind: .imageCollection,
            sourceFileName: "profile",
            contentRelativePath: "\(id.uuidString.lowercased())/pages",
            pageCount: 1,
            fileSize: 100
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([book]).write(to: libraryURL.appendingPathComponent("library.json"))

        var store: LibraryStore? = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        let profile = BookReaderProfile(
            layoutRaw: ReaderLayout.spread.rawValue,
            flowRaw: ReaderFlow.continuous.rawValue,
            orderRaw: ReadingOrder.rightToLeft.rawValue,
            backdropRaw: ReaderBackdrop.graphite.rawValue,
            coverSingle: false
        )
        store?.updateReaderProfile(bookID: id, profile: profile)
        store?.flushProgress()
        store = nil

        let restored = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        XCTAssertEqual(restored.books.first?.readerProfile, profile)
    }

    func testLibraryMetadataRepositoryRecoversCorruptedPrimaryIndex() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InkShelfMetadataRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let primary = root.appendingPathComponent("library.json")
        let repository = LibraryMetadataRepository(primaryURL: primary)
        let book = Book(
            title: "可恢复书架",
            kind: .pdf,
            sourceFileName: "recovery.pdf",
            contentRelativePath: "recovery/source.pdf",
            pageCount: 12,
            fileSize: 1_024
        )

        try repository.save([book])
        try Data("{broken-json".utf8).write(to: primary, options: .atomic)
        let recovered = try repository.load()

        XCTAssertTrue(recovered.recoveredFromBackup)
        XCTAssertEqual(recovered.books.map(\.id), [book.id])
        let repaired = try repository.load()
        XCTAssertFalse(repaired.recoveredFromBackup)
        XCTAssertEqual(repaired.books.map(\.id), [book.id])
    }

    @MainActor
    func testReaderImagePipelineShowsPreviewBeforeFullDecode() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InkShelfProgressiveDecode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("large-page.jpg")
        let source = UIGraphicsImageRenderer(size: CGSize(width: 1_200, height: 1_800)).image { context in
            UIColor.systemPink.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 1_200, height: 1_800))
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 120, y: 180, width: 960, height: 1_440))
        }
        try XCTUnwrap(source.jpegData(compressionQuality: 0.92)).write(to: url)

        let previewReady = expectation(description: "fast preview")
        let fullReady = expectation(description: "reading quality")
        var previewSize = CGSize.zero
        var fullSize = CGSize.zero
        ReaderImagePipeline.shared.loadProgressively(url, maxPixelSize: 3_072) { image, isFinal in
            guard let image else { return }
            if isFinal {
                fullSize = image.size
                fullReady.fulfill()
            } else if previewSize == .zero {
                previewSize = image.size
                previewReady.fulfill()
            }
        }

        await fulfillment(of: [previewReady, fullReady], timeout: 8, enforceOrder: true)
        XCTAssertLessThanOrEqual(max(previewSize.width, previewSize.height), 1_024)
        XCTAssertGreaterThan(max(fullSize.width, fullSize.height), max(previewSize.width, previewSize.height))
    }

    func testBundledSharpModelUsesConfirmedPipeline() async throws {
        let status = try await OnDeviceSharpProcessor.shared.status()
        XCTAssertEqual(status.model, "realesrgan-x4plus-anime")
        XCTAssertEqual(status.tileSize, 128)
        XCTAssertEqual(status.upscale, 4)
        XCTAssertEqual(status.finalScale, 2)
    }

    @MainActor
    func testOnDeviceSharpProducesLosslessTwoTimesPNG() async throws {
        let fileManager = FileManager.default
        let inputRoot = fileManager.temporaryDirectory
            .appendingPathComponent("InkShelfSharpTest-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: inputRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: inputRoot) }
        let inputURL = inputRoot.appendingPathComponent("source.png")
        try testPNG(color: .systemPink).write(to: inputURL, options: .atomic)
        let inputSource = try XCTUnwrap(CGImageSourceCreateWithURL(inputURL as CFURL, nil))
        let inputProperties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(inputSource, 0, nil) as? [CFString: Any]
        )
        let inputWidth = try XCTUnwrap(inputProperties[kCGImagePropertyPixelWidth] as? Int)
        let inputHeight = try XCTUnwrap(inputProperties[kCGImagePropertyPixelHeight] as? Int)

        let result = try await OnDeviceSharpProcessor.shared.enhance(
            source: .image(inputURL),
            outputName: "device-smoke.png"
        )
        defer { try? fileManager.removeItem(at: result.temporaryRoot) }
        XCTAssertEqual(result.executionLocation, .device)
        XCTAssertEqual(result.outputURL.pathExtension.lowercased(), "png")

        let data = try Data(contentsOf: result.outputURL)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(result.outputURL as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, inputWidth * 2)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, inputHeight * 2)
    }

    @MainActor
    func testPreparingOnlineUpdateBacksUpIndexesWithoutTouchingBookPages() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "InkShelfUpdateSafetyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            try? fileManager.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }

        let id = UUID()
        let library = root.appendingPathComponent("InkShelf Library", isDirectory: true)
        let pages = library.appendingPathComponent(id.uuidString.lowercased()).appendingPathComponent("pages")
        try fileManager.createDirectory(at: pages, withIntermediateDirectories: true)
        let pageURL = pages.appendingPathComponent("001.png")
        try testPNG(color: .systemYellow).write(to: pageURL)
        let book = Book(
            id: id,
            title: "更新保护测试",
            kind: .imageCollection,
            sourceFileName: "更新保护测试",
            contentRelativePath: "\(id.uuidString.lowercased())/pages",
            pageCount: 1,
            fileSize: 1
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([book]).write(to: library.appendingPathComponent("library.json"))

        let store = LibraryStore(fileManager: fileManager, defaults: defaults, documentsURL: root)
        let group = try XCTUnwrap(store.createShelfGroup(title: "更新后仍在"))
        store.assignBook(id, toShelfGroup: group.id)
        let backup = try store.prepareForAppUpdate(targetVersion: "1.8.1", targetBuild: 14)

        XCTAssertTrue(fileManager.fileExists(atPath: pageURL.path), "Online updates must never touch cached pages")
        XCTAssertTrue(fileManager.fileExists(atPath: backup.appendingPathComponent("library.json").path))
        XCTAssertTrue(fileManager.fileExists(atPath: backup.appendingPathComponent("shelf-groups.json").path))
        let snapshotData = try Data(contentsOf: backup.appendingPathComponent("update-safety.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UpdateSafetySnapshot.self, from: snapshotData)
        XCTAssertEqual(snapshot.targetBuild, 14)
        XCTAssertEqual(snapshot.bookIDs, [id])
        XCTAssertEqual(snapshot.shelfGroupIDs, [group.id])
        XCTAssertEqual(snapshot.policy, "preserve_app_container")
    }

    @MainActor
    private func testPNG(color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 48, height: 64)).pngData { context in
            color.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 48, height: 64))
        }
    }

    private func makeBook(pageCount: Int, currentPage: Int) -> Book {
        Book(
            title: "测试",
            kind: .pdf,
            sourceFileName: "test.pdf",
            contentRelativePath: "test/source.pdf",
            pageCount: pageCount,
            currentPage: currentPage,
            fileSize: 100
        )
    }

}
