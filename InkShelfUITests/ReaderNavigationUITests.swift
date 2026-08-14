import XCTest

final class ReaderNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSeededLocalBookOpensAndReturnsFromReader() throws {
        let app = XCUIApplication()
        app.launchArguments.append("INKSHELF_UI_TEST_SEED")
        app.launch()

        let skip = app.buttons["跳过"]
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
        }

        let book = app.descendants(matching: .any)["book-a11ce000-0000-4000-8000-000000000001"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), "The seeded local book never appeared on the shelf")
        book.tap()

        var back = app.buttons["reader-close"]
        if !back.waitForExistence(timeout: 2) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            back = app.buttons["reader-close"]
        }
        XCTAssertTrue(back.waitForExistence(timeout: 2), "Tapping a valid local book did not enter ReaderView")
        XCTAssertTrue(app.sliders["reader-progress"].exists, "Reader controls did not finish loading")

        let settings = app.buttons["reader-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2), "The bottom reader toolbar is not hittable")
        settings.tap()
        XCTAssertTrue(app.navigationBars["阅读设置"].waitForExistence(timeout: 2), "Reader settings did not open")
        app.buttons["完成"].tap()

        let thumbnails = app.buttons["reader-thumbnails"]
        XCTAssertTrue(thumbnails.waitForExistence(timeout: 2), "The thumbnail button disappeared after closing settings")
        thumbnails.tap()
        XCTAssertTrue(app.navigationBars["页面"].waitForExistence(timeout: 2), "Thumbnail navigation did not open")
        app.buttons["完成"].tap()

        let layout = app.buttons["reader-layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 2), "The layout button is not hittable")
        let originalLayoutLabel = layout.label
        layout.tap()
        XCTAssertNotEqual(layout.label, originalLayoutLabel, "The layout button did not change reader layout")

        back.tap()
        XCTAssertTrue(book.waitForExistence(timeout: 4), "Returning from ReaderView did not restore the shelf")
    }

    func testSystemDocumentPickerImportsThenOpensImage() throws {
        let app = XCUIApplication()
        app.launchArguments.append("INKSHELF_UI_TEST_PICKER")
        app.launch()

        let skip = app.buttons["跳过"]
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
        }

        if tapFirstVisible(app, labels: ["批量导入读物", "把读物带回家"], timeout: 2) {
            // Empty-shelf primary action opens the system picker directly.
        } else {
            app.buttons["导入"].tap()
            XCTAssertTrue(
                tapFirstVisible(
                    app,
                    labels: ["批量导入文件或图片", "导入文件或图片"],
                    timeout: 2
                ),
                "The import menu did not expose the file picker action"
            )
        }

        // Files presents file rows as different accessibility element types
        // across iOS releases (cell, button, or static text).
        let fixture = app.cells.matching(
            NSPredicate(
                format: "label BEGINSWITH %@ OR identifier BEGINSWITH %@",
                "picker-fixture,",
                "picker-fixture,"
            )
        ).firstMatch
        if !fixture.waitForExistence(timeout: 2) {
            // `directoryURL` is only a hint and Files may open Recents instead.
            // Walk the same visible route a user would take on either a Chinese
            // or English simulator.
            navigateIfVisible(app, labels: ["浏览", "Browse"])
            if !fixture.exists { navigateIfVisible(app, labels: ["我的 iPhone", "On My iPhone"]) }
            if !fixture.exists { navigateIfVisible(app, labels: ["二次元小家", "InkShelf"]) }
            if !fixture.exists { navigateIfVisible(app, labels: ["PickerSmokeInbox"]) }
        }
        if !fixture.waitForExistence(timeout: 8) {
            print("FILES PICKER HIERARCHY:\n\(app.debugDescription)")
        }
        XCTAssertTrue(fixture.waitForExistence(timeout: 8), "The system document picker did not open the requested folder")
        fixture.tap()

        // Multiple selection keeps the picker open until its confirmation
        // button is tapped. Files localizes this independently from the app,
        // and the title also varies slightly between iOS releases.
        if !tapFirstVisible(
            app,
            labels: ["打开", "Open", "选取", "Choose", "完成", "Done", "添加", "Add"],
            timeout: 4
        ) {
            print("FILES PICKER HIERARCHY AFTER SELECTION:\n\(app.debugDescription)")
        }

        let imported = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'picker-fixture'")
        ).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 12), "Selecting a valid image never added it to the shelf")
        imported.tap()

        var back = app.buttons["reader-close"]
        if !back.waitForExistence(timeout: 2) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            back = app.buttons["reader-close"]
        }
        XCTAssertTrue(back.waitForExistence(timeout: 2), "The imported image did not open in ReaderView")
    }

    @discardableResult
    private func tapFirstVisible(
        _ app: XCUIApplication,
        labels: [String],
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for label in labels {
                let button = app.buttons[label]
                guard button.exists && button.isHittable else { continue }
                button.tap()
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }

    @discardableResult
    private func navigateIfVisible(_ app: XCUIApplication, labels: [String]) -> Bool {
        for _ in 0..<10 {
            for label in labels {
                // File/folder cells append details such as “2 items” to the
                // accessibility label on iOS 26, so match the visible name as
                // a prefix instead of requiring an exact label.
                let predicate = NSPredicate(
                    format: "label == %@ OR label BEGINSWITH %@ OR identifier BEGINSWITH %@",
                    label,
                    "\(label),",
                    label
                )
                let candidates = [app.cells, app.buttons, app.staticTexts]
                for query in candidates {
                    let element = query.matching(predicate).firstMatch
                    guard element.exists && element.isHittable else { continue }
                    element.tap()
                    Thread.sleep(forTimeInterval: 0.45)
                    return true
                }
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }
}
