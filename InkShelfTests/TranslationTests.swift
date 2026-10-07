import XCTest
import UIKit
@testable import InkShelf

final class TranslationTests: XCTestCase {
    func testOldLibraryWithoutCoverFocusRemainsReadable() throws {
        let book = Book(title: "旧书", kind: .imageCollection, sourceFileName: "old", contentRelativePath: "old/pages", pageCount: 2, fileSize: 0)
        let data = try JSONEncoder().encode(book)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "coverFocus")
        let restored = try JSONDecoder().decode(Book.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.id, book.id)
        XCTAssertNil(restored.coverFocus)
    }

    func testLongTranslationFallsBackToMarkerInsteadOfClipping() {
        XCTAssertNil(TranslationTypography.font(for: String(repeating: "很长的译文", count: 50),
                                                in: CGSize(width: 80, height: 30), imageWidth: 1000))
        XCTAssertNotNil(TranslationTypography.font(for: "一起回家吧", in: CGSize(width: 500, height: 180), imageWidth: 1000))
    }

    func testDeletingBookTranslationRecordsKeepsOtherBookAndRejectsLateSave() async throws {
        let first = UUID(), other = UUID()
        let key = first.uuidString + "-0-test"
        let otherKey = other.uuidString + "-0-test"
        let document = PageTranslationDocument(regions: [region("a")])
        try await PageTranslationService.shared.save(document, key: key)
        try await PageTranslationService.shared.save(document, key: otherKey)
        try await PageTranslationService.shared.removeRecords(bookID: first)
        try await PageTranslationService.shared.save(document, key: key)
        let deleted = await PageTranslationService.shared.load(key: key)
        let retained = await PageTranslationService.shared.load(key: otherKey)
        XCTAssertNil(deleted)
        XCTAssertNotNil(retained)
        try await PageTranslationService.shared.removeRecords(bookID: other)
    }

    func testCompanionHistoryNeverIncludesAnotherBookOrUnreadPages() {
        let first = UUID(), second = UUID()
        let own = AIPageReaction(page: 1, summary: "本书", mood: "", danmaku: [], talkingPoints: [])
        let foreign = AIPageReaction(page: 0, summary: "另一册", mood: "", danmaku: [], talkingPoints: [])
        let future = AIPageReaction(page: 8, summary: "尚未读到", mood: "", danmaku: [], talkingPoints: [])
        let cache = ["\(first)-1-pro": own, "\(second)-0-pro": foreign, "\(first)-8-pro": future]
        XCTAssertEqual(AIReadingHistory.reactions(for: first, before: 3, from: cache).map(\.summary), ["本书"])
        XCTAssertEqual(AIReadingHistory.reactions(for: second, from: cache).map(\.summary), ["另一册"])
    }

    func testSelectionClampsToImageAndMapsToPixels() {
        let box = TranslationBox(CGRect(x: -0.1, y: 0.2, width: 0.5, height: 1))
        XCTAssertEqual(box.rect, CGRect(x: 0, y: 0.2, width: 0.4, height: 0.8))
        XCTAssertEqual(box.pixels(in: CGSize(width: 1000, height: 2000)), CGRect(x: 0, y: 400, width: 400, height: 1600))
        XCTAssertEqual(TranslationBox(CGRect(x: 2, y: 2, width: 1, height: 1)).rect, .zero)
    }

    func testResponsesMapByIDRatherThanReturnOrder() throws {
        let regions = [region("left"), region("right")]
        let reply = TranslationReply(segments: [
            .init(id: "right", translation: "右边的句子"), .init(id: "left", translation: "左边的句子")
        ])
        let result = try reply.validated(for: regions)
        XCTAssertEqual(result["left"], "左边的句子")
        XCTAssertEqual(result["right"], "右边的句子")
    }

    func testUnknownDuplicateAndEmptyTranslationsAreRejected() {
        let regions = [region("a")]
        let cases: [[TranslationReply.Segment]] = [
            [.init(id: "wrong-page", translation: "错误")],
            [.init(id: "a", translation: "重复一"), .init(id: "a", translation: "重复二")],
            [.init(id: "a", translation: "   ")], []
        ]
        for segments in cases {
            XCTAssertThrowsError(try TranslationReply(segments: segments).validated(for: regions))
        }
    }

    func testPartialResponseDoesNotFabricateMissingRegions() throws {
        let reply = TranslationReply(segments: [.init(id: "a", translation: "已完成")])
        let result = try reply.validated(for: [region("a"), region("b")])
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result["b"])
    }

    func testCorrectedSourceAndCoordinatesSurviveStorage() async throws {
        var corrected = region("corrected")
        corrected.source = "今日は一緒に帰ろう。"
        corrected.translated = "今天一起回家吧。"
        corrected.isEdited = true
        let key = "test-\(UUID().uuidString)"
        let document = PageTranslationDocument(regions: [corrected], modelID: "test")
        try await PageTranslationService.shared.save(document, key: key)
        let restored = await PageTranslationService.shared.load(key: key)
        XCTAssertEqual(restored?.regions, [corrected])
    }

    @MainActor
    func testJapaneseOCRPreservesTextAndLocationWithoutNetwork() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 600), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
            ("今日は一緒に帰ろう。" as NSString).draw(at: CGPoint(x: 120, y: 180), withAttributes: [
                .font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.black
            ])
        }
        let regions = try await PageTranslationService.shared.recognize(image: image)
        XCTAssertTrue(regions.map(\.source).joined().contains("一緒"))
        XCTAssertFalse(regions.isEmpty)
        XCTAssertTrue(regions.allSatisfy { $0.box.y > 0.15 && $0.box.y < 0.6 && $0.box.width > 0 })
    }

    private func region(_ id: String) -> TranslationRegion {
        TranslationRegion(id: id, box: TranslationBox(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)),
                          source: "こんにちは", confidence: 0.9, isVertical: false)
    }
}
