import XCTest

/// Appearance capture only: no page-turn gestures or reading-position tests.
final class AppearancePreviewUITests: XCTestCase {
    func testCaptureAppearancePreview() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["INKSHELF_UI_TEST_APPEARANCE"]
        app.launch()
        XCTAssertTrue(app.buttons["appearance-mode-toggle"].waitForExistence(timeout: 15))
        capture("01-shelf-day", app: app)

        let continueReading = app.buttons["library-continue-reading"]
        for _ in 0..<3 where !continueReading.isHittable { app.swipeUp() }
        XCTAssertTrue(continueReading.waitForExistence(timeout: 5))
        continueReading.tap()
        XCTAssertTrue(app.buttons["reader-close"].waitForExistence(timeout: 10))
        capture("03-reader-controls", app: app)
        app.buttons["reader-close"].tap()

        app.swipeUp()
        capture("02-shelf-covers", app: app)
        if app.frame.width > 700 {
            XCUIDevice.shared.orientation = .landscapeLeft
            capture("02b-shelf-landscape", app: app)
            XCUIDevice.shared.orientation = .portrait
        }

        app.buttons["appearance-mode-toggle"].tap()
        app.swipeDown()
        capture("04-shelf-night", app: app)
        selectTab("画廊", app: app)
        capture("05-gallery", app: app)
        selectTab("设置", app: app)
        capture("06-settings", app: app)
        let achievements = app.buttons["settings-achievements"]
        for _ in 0..<8 where !achievements.isHittable { app.swipeUp() }
        XCTAssertTrue(achievements.waitForExistence(timeout: 5))
        achievements.tap()
        XCTAssertTrue(app.navigationBars["回家足迹"].waitForExistence(timeout: 5))
        capture("07-achievements", app: app)
        app.terminate()
    }

    private func selectTab(_ title: String, app: XCUIApplication) {
        let tab = app.tabBars.buttons[title].firstMatch
        if tab.exists {
            tab.tap()
        } else {
            app.buttons[title].firstMatch.tap()
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        // Allow short presentation and image decode transitions to settle.
        Thread.sleep(forTimeInterval: 1.2)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
