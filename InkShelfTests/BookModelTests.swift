import XCTest
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
