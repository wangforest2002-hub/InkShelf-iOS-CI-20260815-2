import XCTest

/// Translation interactions only; no reader page-turn gestures.
final class TranslationInteractionUITests: XCTestCase {
    func testCachedTranslationHasOneActionAndInlineParagraphs() throws {
        continueAfterFailure = false
        let app = openTranslation(arguments: ["INKSHELF_UI_TEST_TRANSLATION_TIGHT_BOXES"])
        XCTAssertTrue(app.staticTexts["translation-text-preview-1"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["translation-text-preview-1"].label, "今天一起回家吧。")
        XCTAssertFalse(app.segmentedControls["translation-mode"].exists)
        XCTAssertFalse(app.buttons["识别本页"].exists)
        XCTAssertFalse(app.buttons["框选识别"].exists)
        XCTAssertEqual(app.buttons["translation-start"].label, "翻译完成")
        capture("translation-01-page")

        app.buttons["translation-region-preview-1"].tap()
        let selected = app.staticTexts["translation-selected-text"]
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertEqual(selected.label, "今天一起回家吧。")
        XCTAssertTrue(app.buttons["translation-close"].isHittable)
        XCTAssertFalse(app.navigationBars["这段的翻译"].exists)
        capture("translation-02-inline-paragraph")
        app.buttons["translation-next-paragraph"].tap()
        XCTAssertEqual(selected.label, "要不要稍微绕个路？")
        app.buttons["translation-previous-paragraph"].tap()
        XCTAssertEqual(selected.label, "今天一起回家吧。")

        app.segmentedControls["translation-scope"].buttons["整页译文"].tap()
        app.buttons["translation-full-page"].tap()
        XCTAssertTrue(app.navigationBars["整页译文"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["translation-full-text-preview-2"].exists)
        XCTAssertTrue(app.staticTexts["translation-full-text-preview-3"].exists)
        capture("translation-03-full-page")
        app.descendants(matching: .any)["translation-full-detail-preview-2"].firstMatch.tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        XCTAssertEqual(selected.label, "要不要稍微绕个路？")
        XCTAssertTrue(app.buttons["translation-close"].isHittable)

        app.buttons["translation-paragraph-tools"].tap()
        app.buttons["校对原文与译文"].tap()
        XCTAssertTrue(app.textViews["translation-editor-source"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["translation-editor-source"].value as? String, "少しだけ、寄り道しない？")
        app.buttons["translation-editor-cancel"].tap()
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        app.buttons["translation-retranslate-paragraph"].tap()
        XCTAssertTrue(app.buttons["translation-error-settings"].waitForExistence(timeout: 5))
        app.buttons["translation-error-settings"].tap()
        XCTAssertTrue(app.navigationBars["翻译设置"].waitForExistence(timeout: 5))
        app.buttons["translation-settings-close"].tap()
        app.buttons["translation-close"].tap()
        XCTAssertTrue(app.buttons["reader-close"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testOpeningTranslationAutomaticallyRecognizesWithoutPositionSelection() throws {
        continueAfterFailure = false
        let app = openTranslation(arguments: ["INKSHELF_UI_TEST_TRANSLATION_EMPTY"])
        // No button or region is tapped after entering the workspace. Vision
        // must run and the pipeline must reach the credential check itself.
        XCTAssertTrue(app.buttons["translation-error-settings"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.segmentedControls["translation-scope"].exists)
        XCTAssertGreaterThan(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "translation-region-")).count, 0)
        XCTAssertFalse(app.segmentedControls["translation-mode"].exists)
        XCTAssertFalse(app.buttons["识别本页"].exists)
        XCTAssertFalse(app.buttons["框选识别"].exists)
        XCTAssertEqual(app.buttons["translation-start"].label, "重试翻译")
        capture("translation-04-automatic-ocr")
        app.terminate()
    }

    private func openTranslation(arguments: [String]) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["INKSHELF_UI_TEST_APPEARANCE"] + arguments
        app.launch()
        let resume = app.buttons["library-continue-reading"]
        XCTAssertTrue(resume.waitForExistence(timeout: 20))
        for _ in 0..<3 where !resume.isHittable { app.swipeUp() }
        resume.tap()
        let translate = app.buttons["reader-translate"]
        XCTAssertTrue(translate.waitForExistence(timeout: 10))
        translate.tap()
        XCTAssertTrue(app.buttons["translation-close"].waitForExistence(timeout: 10))
        return app
    }

    private func capture(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
