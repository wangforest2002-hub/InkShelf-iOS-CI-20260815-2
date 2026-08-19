import XCTest
import ImageIO
import SceneKit
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
        XCTAssertEqual(AIWritingPurpose.allCases.count, 6)
        for purpose in AIWritingPurpose.allCases {
            XCTAssertFalse(purpose.title.isEmpty)
            XCTAssertFalse(purpose.promptDescription.isEmpty)
            XCTAssertFalse(purpose.systemImage.isEmpty)
        }
    }

    func testKokoAutonomyUsesNeedsBeforePickingAnActivity() {
        let tiredState = KokoInnerState(
            mood: .sleepy,
            energy: 0.12,
            curiosity: 0.95,
            socialNeed: 0.90,
            orderNeed: 0.90
        )
        let perception = KokoPerception(
            trigger: .periodic,
            localHour: 15,
            roomTheme: .sunset,
            furnitureNames: ["画集书架"],
            books: [],
            displayedBookIDs: [],
            recentMemories: [],
            recentActions: [.stroll],
            innerState: tiredState
        )

        let decision = KokoDecision.localFallback(for: perception)
        XCTAssertEqual(decision.action, .rest)
        XCTAssertFalse(decision.phrase.isEmpty)

        var recovered = tiredState
        recovered.apply(.rest, localHour: 15)
        XCTAssertGreaterThan(recovered.energy, tiredState.energy)
    }

    @MainActor
    func testBundledKokoModelLoadsRenderableGeometry() throws {
        let root = HomeSceneFactory().makeKokoNode()
        let model = try XCTUnwrap(root.childNode(withName: "koko-model", recursively: false))
        var geometryCount = 0
        var texturedMaterialCount = 0
        var bodyMaterial: SCNMaterial?
        var transparentMaterialCount = 0
        model.enumerateChildNodes { node, _ in
            if let geometry = node.geometry {
                geometryCount += 1
                texturedMaterialCount += geometry.materials.filter { $0.diffuse.contents is UIImage }.count
                transparentMaterialCount += geometry.materials.filter { $0.blendMode == .alpha }.count
                bodyMaterial = bodyMaterial ?? geometry.materials.first {
                    $0.name?.localizedCaseInsensitiveContains("Body_00_SKIN") == true
                }
            }
        }
        XCTAssertGreaterThanOrEqual(geometryCount, 3, "Koko.usdz loaded without its visible meshes")
        XCTAssertGreaterThanOrEqual(texturedMaterialCount, 12, "Koko loaded without her face, hair, or clothing textures")
        XCTAssertGreaterThanOrEqual(transparentMaterialCount, 6, "Koko's hair and facial overlays lost alpha rendering")
        let body = try XCTUnwrap(bodyMaterial)
        XCTAssertEqual(body.blendMode, .replace, "Koko's body must not be alpha-sorted behind her clothes")
        XCTAssertTrue(body.writesToDepthBuffer, "Koko's opaque body must write depth so her legs remain visible")
        let bounds = model.boundingBox
        XCTAssertGreaterThan(bounds.max.y - bounds.min.y, 1.2, "Koko.usdz is not using the SceneKit Y-up orientation")
        XCTAssertLessThan(bounds.max.y - bounds.min.y, 2.2, "Koko.usdz has an unsafe scene scale")
        XCTAssertNil(root.childNode(withName: "koko-model-fallback", recursively: false))
    }

    @MainActor
    func testTokyoApartmentRoomBuildsCompleteImmersiveShell() throws {
        let room = HomeSceneFactory().makeRoom(theme: .sunset)
        let expectedNodes = [
            "room-floor",
            "room-back-wall",
            "room-right-wall",
            "room-front-wall",
            "room-ceiling",
            "room-entryway",
            "room-balcony-window",
            "room-outdoor-panorama",
            "room-shoji-partition",
            "room-tatami-corner",
            "room-cherry-branch",
            "room-washi-pendant"
        ]
        for name in expectedNodes {
            XCTAssertNotNil(room.childNode(withName: name, recursively: true), "Missing Tokyo apartment detail: \(name)")
        }

        let panorama = try XCTUnwrap(room.childNode(withName: "room-outdoor-panorama", recursively: true))
        let panoramaContents = panorama.geometry?.firstMaterial?.diffuse.contents
        XCTAssertTrue(panoramaContents is NSURL || panoramaContents is UIImage)
        XCTAssertEqual(panorama.geometry?.firstMaterial?.isDoubleSided, true)
        var geometryCount = 0
        room.enumerateChildNodes { node, _ in
            if node.geometry != nil { geometryCount += 1 }
        }
        XCTAssertGreaterThan(geometryCount, 80, "The apartment shell lost too many architectural details")

        let panoramaURL = try XCTUnwrap(
            Bundle.main.url(forResource: "WindowPanoramaTokyoSpring", withExtension: "png")
        )
        let byteCount = try panoramaURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        XCTAssertGreaterThan(byteCount, 1_000_000, "Tokyo exterior panorama was not bundled at useful quality")
    }

    @MainActor
    func testHomeWorldPersistsLayoutArtworkAndKokoZone() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        var store: HomeWorldStore? = HomeWorldStore(fileManager: fileManager, documentsURL: root)
        store?.setTheme(.rain)
        let furnitureID = try XCTUnwrap(store?.addFurniture(.desk))
        store?.updatePlacement(
            furnitureID,
            transform: HomeTransform(x: 1.2, y: 0, z: -0.4, yaw: 0.7, scale: 1.1)
        )
        store?.updateKokoZone(KokoActivityZone(centerX: 0.4, centerZ: 0.2, width: 3.2, depth: 2.4))
        let artData = testPNG(color: .systemPink)
        _ = try store?.importArtwork(data: artData, kind: .standee, title: "旅行纪念")
        store?.flush()
        store = nil

        let restored = HomeWorldStore(fileManager: fileManager, documentsURL: root)
        XCTAssertEqual(restored.state.theme, .rain)
        let restoredFurniture = try XCTUnwrap(restored.placement(withID: furnitureID))
        XCTAssertEqual(restoredFurniture.furniture, .desk)
        XCTAssertEqual(restoredFurniture.transform.x, 1.2, accuracy: 0.001)
        XCTAssertEqual(restored.state.koko.activityZone.width, 3.2, accuracy: 0.001)
        let artwork = try XCTUnwrap(restored.state.artworks.first)
        XCTAssertEqual(artwork.title, "旅行纪念")
        XCTAssertTrue(fileManager.fileExists(atPath: restored.artworkURL(for: artwork).path))
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
