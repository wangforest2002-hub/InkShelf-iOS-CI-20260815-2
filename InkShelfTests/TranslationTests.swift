import XCTest
import UIKit
@testable import InkShelf

final class TranslationTests: XCTestCase {
    func testWrappedDialogueBecomesOneParagraphWithoutJoiningSeparateBubblesOrRuby() {
        let lines = [
            line("second", "帰ろう。", 0.23, 0.159, 0.34, 0.045),
            line("first", "今日は一緒に", 0.20, 0.10, 0.40, 0.045),
            line("other", "寄り道しない？", 0.20, 0.35, 0.45, 0.045),
            line("ruby", "いっしょ", 0.33, 0.078, 0.08, 0.013),
            line("neighbor", "また明日。", 0.70, 0.10, 0.25, 0.045)
        ]
        let result = TranslationParagraphs.group(lines, imageSize: CGSize(width: 1000, height: 1400))
        XCTAssertEqual(result.count, 4)
        let paragraph = result.first { $0.id == "first" }
        XCTAssertEqual(paragraph?.source, "今日は一緒に\n帰ろう。")
        XCTAssertEqual(paragraph?.box.rect.maxY ?? 0, 0.204, accuracy: 0.0001)
        XCTAssertTrue(result.contains { $0.id == "ruby" && $0.source == "いっしょ" })
        XCTAssertTrue(result.contains { $0.id == "neighbor" && $0.source == "また明日。" })
    }

    func testVerticalColumnsReadFromRightToLeftWithUnevenTops() {
        var right = line("right", "今日は", 0.65, 0.10, 0.04, 0.30)
        var left = line("left", "帰ろう。", 0.595, 0.105, 0.04, 0.28)
        right.isVertical = true; left.isVertical = true
        let separate = line("below", "またね。", 0.60, 0.65, 0.25, 0.04)
        let result = TranslationParagraphs.group([left, separate, right], imageSize: CGSize(width: 1000, height: 1400))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.source, "今日は\n帰ろう。")
        XCTAssertEqual(result.first?.id, "right")
    }

    func testLegacyLineTranslationsArePreservedAndMarkedForParagraphRetranslation() throws {
        var first = line("first", "一緒に", 0.20, 0.10, 0.40, 0.045)
        var second = line("second", "帰ろう。", 0.20, 0.16, 0.40, 0.045)
        var edited = line("corrected", "明日ね。", 0.20, 0.22, 0.40, 0.045)
        first.translated = "一起"; second.translated = "回家吧。"
        edited.translated = "明天见。"; edited.isEdited = true
        let legacy = PageTranslationDocument(schema: 1, regions: [first, second, edited])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        var records = try XCTUnwrap(json["regions"] as? [[String: Any]])
        for index in records.indices { records[index].removeValue(forKey: "needsRetranslation") }
        json["regions"] = records
        let decoded = try JSONDecoder().decode(PageTranslationDocument.self, from: JSONSerialization.data(withJSONObject: json))
        let grouped = TranslationParagraphs.group(decoded.regions, imageSize: CGSize(width: 1000, height: 1400))
        XCTAssertEqual(grouped.count, 2)
        XCTAssertEqual(grouped[0].translated, "一起\n回家吧。")
        XCTAssertEqual(grouped[0].needsRetranslation, true)
        XCTAssertEqual(grouped[1], edited)
        let roundTrip = try JSONDecoder().decode(PageTranslationDocument.self, from: JSONEncoder().encode(PageTranslationDocument(regions: grouped)))
        XCTAssertEqual(roundTrip.schema, 2)
        XCTAssertEqual(roundTrip.regions, grouped)
    }

    func testContextPrioritizesNeighborsAndExcludesStaleTranslation() {
        var page = (0..<9).map { index -> TranslationRegion in
            var r = region("\(index)"); r.source = "\(index)あいうえ"; return r
        }
        page[5].translated = "旧译文"; page[5].needsRetranslation = true
        let input = TranslationRequestInput(targets: [page[4]], page: page, contextBudget: 10)
        XCTAssertEqual(input.targets.map(\.id), ["4"])
        XCTAssertEqual(input.context.map(\.id), ["3", "5"])
        XCTAssertNil(input.context.last?.previousTranslation)
        XCTAssertEqual(input.targets[0].text, "4あいうえ")
    }

    @MainActor
    func testActualMultilineJapaneseOCRProducesOneDialogueParagraph() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 64), .foregroundColor: UIColor.black]
            ("今日は一緒に" as NSString).draw(at: CGPoint(x: 120, y: 180), withAttributes: attributes)
            ("帰ろう。" as NSString).draw(at: CGPoint(x: 120, y: 265), withAttributes: attributes)
            ("また明日。" as NSString).draw(at: CGPoint(x: 120, y: 530), withAttributes: attributes)
        }
        let result = try await PageTranslationService.shared.recognize(image: image)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result[0].source.contains("一緒"))
        XCTAssertTrue(result[0].source.contains("帰ろう"))
        XCTAssertTrue(result[1].source.contains("明日"))
    }

    private func line(_ id: String, _ source: String, _ x: Double, _ y: Double, _ width: Double, _ height: Double) -> TranslationRegion {
        TranslationRegion(id: id, box: TranslationBox(CGRect(x: x, y: y, width: width, height: height)),
                          source: source, confidence: 0.95, isVertical: false)
    }

    func testOldLibraryWithoutCoverFocusRemainsReadable() throws {
        let book = Book(title: "旧书", kind: .imageCollection, sourceFileName: "old", contentRelativePath: "old/pages", pageCount: 2, fileSize: 0)
        let data = try JSONEncoder().encode(book)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "coverFocus")
        let restored = try JSONDecoder().decode(Book.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.id, book.id)
        XCTAssertNil(restored.coverFocus)
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
