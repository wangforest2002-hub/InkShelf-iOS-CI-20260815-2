import XCTest

/// Focused translation UI checks; deliberately performs no page-turn gestures.
final class TranslationInteractionUITests: XCTestCase {
    func testParagraphTapAndFullPageChineseRemainReadable() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["INKSHELF_UI_TEST_APPEARANCE", "INKSHELF_UI_TEST_TRANSLATION_TIGHT_BOXES"]
        app.launch()
        let resume = app.buttons["library-continue-reading"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20))
        for _ in 0..<3 where !resume.isHittable { app.swipeUp() }
        resume.tap()
        let translate = app.buttons["reader-translate"]
        XCTAssertTrue(translate.waitForExistence(timeout: 10))
        translate.tap()
        let paragraph = app.buttons["translation-region-preview-1"]
        XCTAssertTrue(paragraph.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["translation-text-preview-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["translation-text-preview-1"].label, "今天一起回家吧。")
        capture("translation-01-comparison")
        paragraph.tap()
        let selected = app.staticTexts["translation-selected-text"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertEqual(selected.label, "今天一起回家吧。")
        capture("translation-02-paragraph")
        app.buttons["完成"].tap()
        app.segmentedControls["translation-mode"].buttons["中文"].tap()
        XCTAssertTrue(app.staticTexts["translation-text-preview-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["translation-text-preview-1"].label, "今天一起回家吧。")
        capture("translation-03-chinese")
        app.buttons["translation-full-page"].tap()
        XCTAssertTrue(app.navigationBars["本页完整译文"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["要不要稍微绕个路？"].exists)
        XCTAssertTrue(app.staticTexts["好呀。晚霞真好看。"].exists)
        capture("translation-04-full-page")
        app.buttons["完成"].tap()
        app.segmentedControls["translation-mode"].buttons["原图"].tap()
        XCTAssertTrue(app.buttons["translation-region-preview-1"].exists)
        app.buttons["translation-region-preview-1"].tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertEqual(selected.label, "今天一起回家吧。")
        app.terminate()
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
