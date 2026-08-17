import XCTest

final class ReaderNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHomeWorldOpensAndEditingControlsRemainHittable() throws {
        let app = XCUIApplication()
        app.launchArguments.append("INKSHELF_UI_TEST_HOME")
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["home-3d-scene"].waitForExistence(timeout: 8),
            "The native 3D home scene did not appear"
        )
        XCTAssertTrue(app.descendants(matching: .any)["home-theme"].exists)
        attachScreenshot(app, name: "01-home-living")

        let chat = app.buttons["和可可聊聊"].firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 3), "Koko chat entry point is missing")
        chat.tap()
        XCTAssertTrue(app.navigationBars["和可可聊聊"].waitForExistence(timeout: 3))
        attachScreenshot(app, name: "02-koko-chat")
        app.buttons["关闭"].tap()

        let edit = app.buttons["home-edit-toggle"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3), "The home editing entry point is missing")
        XCTAssertTrue(edit.isHittable, "The home editing entry point is covered by another view")
        edit.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "家具")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "画集")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "收藏")).firstMatch.exists)
        attachScreenshot(app, name: "03-home-editing")

        let kokoSettings = app.buttons["可可"].firstMatch
        XCTAssertTrue(kokoSettings.isHittable)
        kokoSettings.tap()
        XCTAssertTrue(app.navigationBars["可可的活动范围"].waitForExistence(timeout: 3))
        attachScreenshot(app, name: "04-koko-autonomy")
        app.navigationBars["可可的活动范围"].buttons["完成"].tap()

        let furniture = app.buttons["家具"].firstMatch
        XCTAssertTrue(furniture.waitForExistence(timeout: 3))
        furniture.tap()
        XCTAssertTrue(app.navigationBars["添加家具"].waitForExistence(timeout: 3))
        attachScreenshot(app, name: "05-furniture-catalog")
        app.navigationBars["添加家具"].buttons["完成"].tap()

        XCTAssertTrue(edit.isHittable, "The editing completion button became unreachable")
        edit.tap()
    }

    func testSeededLocalBookOpensAndReturnsFromReader() throws {
        let app = XCUIApplication()
        app.launchArguments.append("INKSHELF_UI_TEST_SEED")
        app.launch()

        let skip = app.buttons["跳过"]
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
        }

        XCTAssertTrue(
            app.buttons["shelf-new-group"].waitForExistence(timeout: 4),
            "The custom shelf-group entry point is missing"
        )
        attachScreenshot(app, name: "06-shelf")

        let book = app.descendants(matching: .any)["book-a11ce000-0000-4000-8000-000000000001"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), "The seeded local book never appeared on the shelf")
        if book.isHittable {
            book.tap()
        } else {
            // iOS 26 occasionally reports the first grid card one pixel beyond
            // the accessibility viewport even though its center is visible.
            book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        var back = app.buttons["reader-close"]
        if !back.waitForExistence(timeout: 2) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            back = app.buttons["reader-close"]
        }
        XCTAssertTrue(back.waitForExistence(timeout: 2), "Tapping a valid local book did not enter ReaderView")
        XCTAssertTrue(app.sliders["reader-progress"].exists, "Reader controls did not finish loading")
        attachScreenshot(app, name: "07-reader")
        let aiToggle = app.buttons["reader-ai-toggle"]
        XCTAssertTrue(aiToggle.exists, "The AI control is not a simple on/off button")
        aiToggle.tap()
        let missingAIKey = app.alerts["还没有连接 AI"]
        XCTAssertTrue(missingAIKey.waitForExistence(timeout: 2), "Tapping AI without a key produced no visible feedback")
        missingAIKey.buttons["好"].tap()
        XCTAssertTrue(app.buttons["reader-sharp-enhance"].exists, "The Sharp current-page action is missing")

        XCTAssertTrue(app.buttons["reader-save-page"].waitForExistence(timeout: 2), "The current-page save action is missing")
        let pageFavorite = app.buttons["reader-page-favorite"]
        XCTAssertTrue(pageFavorite.waitForExistence(timeout: 2), "The single-page favorite action is missing")
        XCTAssertEqual(pageFavorite.label, "收藏当前页")
        pageFavorite.tap()
        XCTAssertTrue(app.descendants(matching: .any)["reader-notice"].waitForExistence(timeout: 2))
        XCTAssertEqual(pageFavorite.label, "取消收藏当前页")

        let settings = revealReaderControls(app, probeIdentifier: "reader-settings")
        settings.tap()
        XCTAssertTrue(app.navigationBars["阅读设置"].waitForExistence(timeout: 2), "Reader settings did not open")
        attachScreenshot(app, name: "08-reader-settings")
        app.navigationBars["阅读设置"].buttons["完成"].tap()

        let thumbnails = revealReaderControls(app, probeIdentifier: "reader-thumbnails")
        thumbnails.tap()
        XCTAssertTrue(app.navigationBars["页面"].waitForExistence(timeout: 2), "Thumbnail navigation did not open")
        attachScreenshot(app, name: "09-page-browser")
        app.navigationBars["页面"].buttons["完成"].tap()

        let layout = revealReaderControls(app, probeIdentifier: "reader-layout")
        let originalLayoutLabel = layout.label
        layout.tap()
        XCTAssertNotEqual(layout.label, originalLayoutLabel, "The layout button did not change reader layout")

        revealReaderControls(app, probeIdentifier: "reader-close").tap()
        XCTAssertTrue(book.waitForExistence(timeout: 4), "Returning from ReaderView did not restore the shelf")
        XCTAssertTrue(app.tabBars.buttons["最近"].exists)
        XCTAssertTrue(app.tabBars.buttons["珍藏"].exists)
        XCTAssertFalse(app.tabBars.buttons["云阁楼"].exists)

        app.tabBars.buttons["设置"].tap()
        let onlineUpdate = app.buttons["settings-online-update"]
        for _ in 0..<5 where !onlineUpdate.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(onlineUpdate.waitForExistence(timeout: 3), "The online-update center is missing from Settings")
        onlineUpdate.tap()
        XCTAssertTrue(app.navigationBars["应用更新"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["update-check"].exists)
    }

    func testSystemDocumentPickerImportsThenOpensImage() throws {
        let app = XCUIApplication()
        app.launchArguments.append("INKSHELF_UI_TEST_PICKER")
        app.launch()

        let skip = app.buttons["跳过"]
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
        }

        // The debug launch argument presents the real system picker directly,
        // avoiding menu accessibility-label differences between iOS releases.

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

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func revealReaderControls(_ app: XCUIApplication, probeIdentifier: String) -> XCUIElement {
        var probe = app.buttons[probeIdentifier]
        if !probe.exists || !probe.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            probe = app.buttons[probeIdentifier]
        }
        XCTAssertTrue(probe.waitForExistence(timeout: 2), "Reader controls did not reappear")
        XCTAssertTrue(probe.isHittable, "Reader control \(probeIdentifier) is covered")
        return probe
    }
}
