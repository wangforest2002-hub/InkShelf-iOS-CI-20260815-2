import XCTest
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
