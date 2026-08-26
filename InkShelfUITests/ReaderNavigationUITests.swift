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

        XCTAssertTrue(
            app.buttons["shelf-new-group"].waitForExistence(timeout: 4),
            "The custom shelf-group entry point is missing"
        )
        XCTAssertTrue(
            app.buttons["library-organize"].waitForExistence(timeout: 3),
            "The shelf sort, status, and density menu is missing"
        )

        let book = app.descendants(matching: .any)["book-a11ce000-0000-4000-8000-000000000001"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), "The seeded local book never appeared on the shelf")
        XCTAssertGreaterThanOrEqual(
            book.frame.minX,
            app.frame.minX - 1,
            "The shelf grid starts outside the visible viewport"
        )
        XCTAssertLessThanOrEqual(
            book.frame.maxX,
            app.frame.maxX + 1,
            "The shelf grid extends outside the visible viewport"
        )
        XCTAssertGreaterThan(
            book.frame.width,
            app.frame.width * 0.82,
            "A landscape cover should span both compact shelf columns"
        )

        let landscapeGroup = app.buttons["shelf-filter-group-a11ce000-0000-4000-8000-000000000101"]
        XCTAssertTrue(landscapeGroup.waitForExistence(timeout: 3), "The seeded landscape shelf group is missing")
        landscapeGroup.tap()
        let groupedBook = app.descendants(matching: .any)["book-a11ce000-0000-4000-8000-000000000001"]
        XCTAssertTrue(groupedBook.waitForExistence(timeout: 3), "The category switch lost its matching book")
        XCTAssertEqual(
            app.descendants(matching: .any)
                .matching(identifier: "book-a11ce000-0000-4000-8000-000000000001").count,
            1,
            "A category switch left a duplicate accessibility card behind"
        )
        app.buttons["shelf-filter-all"].tap()
        XCTAssertTrue(book.waitForExistence(timeout: 3), "Returning to the full shelf lost the landscape book")

        if book.isHittable {
            book.tap()
        } else {
            // iOS 26 occasionally reports the first grid card one pixel beyond
            // the accessibility viewport even though its center is visible.
            book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        let back = app.buttons["reader-close"]
        XCTAssertTrue(
            back.waitForExistence(timeout: 12),
            "Tapping a valid local book did not expose ReaderView controls"
        )
        let progress = app.sliders["reader-progress"]
        XCTAssertTrue(progress.exists, "Reader controls did not finish loading")
        let pageLabel = app.staticTexts["reader-page-label"]
        XCTAssertTrue(pageLabel.exists, "The page counter did not appear")
        XCTAssertTrue(
            pageLabel.label.contains("第 1 页 · 共 3 页"),
            "The initial page number is incorrect"
        )
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

        let settings = app.buttons["reader-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2), "The reader settings button is not hittable")
        settings.tap()
        XCTAssertTrue(app.navigationBars["阅读设置"].waitForExistence(timeout: 2), "Reader settings did not open")
        XCTAssertTrue(
            app.descendants(matching: .any)["reader-flow"].exists,
            "The horizontal, vertical, and continuous reading selector is missing"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["reader-page-transition"].exists,
            "The book-turn and smooth-slide selector is missing"
        )
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
        progress.adjust(toNormalizedSliderPosition: 1)
        XCTAssertTrue(
            pageLabel.label.contains("第 2–3 页 · 共 3 页"),
            "The spread page label and progress scrubber are out of sync"
        )

        // Rapid external navigation used to leave several asynchronous scroll
        // requests queued. A stale request could execute last and pull the
        // reader back to an older page after the user's finger had stopped.
        progress.adjust(toNormalizedSliderPosition: 0)
        progress.adjust(toNormalizedSliderPosition: 1)
        progress.adjust(toNormalizedSliderPosition: 0)
        progress.adjust(toNormalizedSliderPosition: 1)
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertTrue(
            pageLabel.label.contains("第 2–3 页 · 共 3 页"),
            "A stale image-pager alignment request changed the final spread"
        )

        layout.tap()
        progress.adjust(toNormalizedSliderPosition: 0)
        progress.adjust(toNormalizedSliderPosition: 1)
        progress.adjust(toNormalizedSliderPosition: 0.5)
        Thread.sleep(forTimeInterval: 0.7)
        XCTAssertTrue(
            pageLabel.label.contains("第 2 页 · 共 3 页"),
            "Rapid single-page scrubbing did not settle on the user's final request"
        )

        back.tap()
        XCTAssertTrue(book.waitForExistence(timeout: 4), "Returning from ReaderView did not restore the shelf")
        XCTAssertTrue(app.tabBars.buttons["最近"].exists)
        XCTAssertTrue(app.tabBars.buttons["画廊"].exists)
        XCTAssertFalse(app.tabBars.buttons["珍藏"].exists)
        XCTAssertFalse(app.tabBars.buttons["夜读"].exists)
        XCTAssertFalse(app.tabBars.buttons["云阁楼"].exists)

        let appearanceToggle = app.buttons["appearance-mode-toggle"]
        XCTAssertTrue(
            appearanceToggle.waitForExistence(timeout: 3),
            "The global day/night mode switch is missing from the shelf"
        )
        if String(describing: appearanceToggle.value).contains("日间模式已开启") {
            appearanceToggle.tap()
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["night-mode-library-card"].waitForExistence(timeout: 3),
            "Night mode did not keep the full shelf and its adults-only profile summary visible"
        )

        app.tabBars.buttons["画廊"].tap()
        XCTAssertTrue(app.navigationBars["我的画廊"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["gallery-section-picker"].exists,
            "Imported images, favorite pages, and favorite books are not visibly separated"
        )
        XCTAssertTrue(app.buttons["gallery-import"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["book-a11ce000-0000-4000-8000-000000000001"].exists,
            "An independently imported image collection did not appear in My Images"
        )

        app.tabBars.buttons["设置"].tap()
        let achievementSettings = app.buttons["settings-achievements"]
        for _ in 0..<4 where !achievementSettings.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(achievementSettings.waitForExistence(timeout: 3), "The achievement center is missing from Settings")
        achievementSettings.tap()
        XCTAssertTrue(app.navigationBars["回家足迹"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["achievements-options"].exists, "The safe achievement reset menu is missing")
        app.navigationBars["回家足迹"].buttons.element(boundBy: 0).tap()

        let duplicateSettings = app.buttons["settings-duplicate-content"]
        for _ in 0..<6 where !duplicateSettings.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(duplicateSettings.waitForExistence(timeout: 3), "The duplicate-content scanner is missing")
        duplicateSettings.tap()
        XCTAssertTrue(app.navigationBars["重复内容检测"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["duplicate-scan-start"].waitForExistence(timeout: 3))
        app.navigationBars["重复内容检测"].buttons.element(boundBy: 0).tap()

        let welcomeTour = app.buttons["settings-welcome-tour"]
        for _ in 0..<6 where !welcomeTour.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(welcomeTour.waitForExistence(timeout: 3), "The 2.5 welcome tour is missing from Settings")
        welcomeTour.tap()
        XCTAssertTrue(app.descendants(matching: .any)["welcome-2-5"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["welcome-continue"].exists)
        app.buttons["welcome-skip"].tap()
        XCTAssertTrue(app.navigationBars["小家设置"].waitForExistence(timeout: 3))

        let onlineUpdate = app.buttons["settings-online-update"]
        for _ in 0..<5 where !onlineUpdate.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(onlineUpdate.waitForExistence(timeout: 3), "The online-update center is missing from Settings")
        onlineUpdate.tap()
        XCTAssertTrue(app.navigationBars["应用更新"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["update-check"].exists)
    }

    func testLongSinglePageAlbumAdvancesExactlyOnceAtStartMiddleAndEnd() throws {
        let app = XCUIApplication()
        app.launchArguments.append("INKSHELF_UI_TEST_LONG_READER")
        app.launch()

        let skip = app.buttons["跳过"]
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
        }

        let book = app.descendants(matching: .any)["book-a11ce000-0000-4000-8000-000000000061"]
        XCTAssertTrue(book.waitForExistence(timeout: 8), "The long paging fixture never appeared")
        book.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        let progress = app.sliders["reader-progress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 12), "The long album did not open")
        let pageLabel = app.staticTexts["reader-page-label"]
        XCTAssertTrue(pageLabel.waitForExistence(timeout: 3), "The long album page counter did not appear")
        assertPage(1, of: 61, on: pageLabel)

        // UIPageViewController exposes only its adjacent controller. A native
        // XCTest swipe therefore has one possible completed destination and is
        // less prone to the delayed synthetic-drag delivery seen on iPad.
        for page in 2...59 {
            advanceExactlyOnePageForward(
                from: page - 1,
                to: page,
                of: 61,
                in: app,
                on: pageLabel
            )
            if page == 39 {
                advanceExactlyOnePageBackward(
                    from: 39,
                    to: 38,
                    of: 61,
                    in: app,
                    on: pageLabel
                )
                advanceExactlyOnePageForward(
                    from: 38,
                    to: 39,
                    of: 61,
                    in: app,
                    on: pageLabel
                )
            }
        }

        // The progress control keeps its native numeric accessibility value,
        // so a midpoint request must settle at the middle physical page. XCU's
        // slider API is explicitly best-effort, so one page of quantization is
        // acceptable while a large jump is still caught as a regression.
        progress.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertEqual(Double(progress.normalizedSliderPosition), 0.5, accuracy: 0.05)
        assertPage(near: 31, tolerance: 3, of: 61, on: pageLabel)
    }

    private func swipeOnePageForward(in app: XCUIApplication) {
        app.swipeLeft()
    }

    private func swipeOnePageBackward(in app: XCUIApplication) {
        app.swipeRight()
    }

    private func advanceExactlyOnePageForward(
        from currentPage: Int,
        to expectedPage: Int,
        of pageCount: Int,
        in app: XCUIApplication,
        on pageLabel: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertPage(currentPage, of: pageCount, on: pageLabel, file: file, line: line)
        swipeOnePageForward(in: app)
        let expected = "第 \(expectedPage) 页 · 共 \(pageCount) 页"
        XCTAssertTrue(
            waitForPage(expectedPage, of: pageCount, on: pageLabel, timeout: 6),
            "Expected exactly one completed page turn to \(expected), got \(pageLabel.label)",
            file: file,
            line: line
        )
    }

    private func advanceExactlyOnePageBackward(
        from currentPage: Int,
        to expectedPage: Int,
        of pageCount: Int,
        in app: XCUIApplication,
        on pageLabel: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertPage(currentPage, of: pageCount, on: pageLabel, file: file, line: line)
        swipeOnePageBackward(in: app)
        let expected = "第 \(expectedPage) 页 · 共 \(pageCount) 页"
        XCTAssertTrue(
            waitForPage(expectedPage, of: pageCount, on: pageLabel, timeout: 6),
            "Expected exactly one completed page turn to \(expected), got \(pageLabel.label)",
            file: file,
            line: line
        )
    }

    private func waitForPage(
        _ page: Int,
        of pageCount: Int,
        on pageLabel: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expected = "第 \(page) 页 · 共 \(pageCount) 页"
        let predicate = NSPredicate(format: "label CONTAINS %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: pageLabel)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func assertPage(
        _ page: Int,
        of pageCount: Int,
        on pageLabel: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expected = "第 \(page) 页 · 共 \(pageCount) 页"
        XCTAssertTrue(
            waitForPage(page, of: pageCount, on: pageLabel, timeout: 3),
            "Expected \(expected), got \(pageLabel.label)",
            file: file,
            line: line
        )
    }

    private func assertPage(
        near page: Int,
        tolerance: Int,
        of pageCount: Int,
        on pageLabel: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let acceptable = ((page - tolerance)...(page + tolerance)).map {
            "第 \($0) 页 · 共 \(pageCount) 页"
        }
        let predicate = NSPredicate(format: "label IN %@", acceptable)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: pageLabel)
        let result = XCTWaiter.wait(for: [expectation], timeout: 3)
        XCTAssertEqual(
            result,
            .completed,
            "Expected one of \(acceptable), got \(pageLabel.label)",
            file: file,
            line: line
        )
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
        let confirmedSelection = tapFirstVisible(
            app,
            labels: ["打开", "Open", "选取", "Choose", "完成", "Done", "添加", "Add"],
            timeout: 4
        )
        if !confirmedSelection {
            print("FILES PICKER HIERARCHY AFTER SELECTION:\n\(app.debugDescription)")
        }
        XCTAssertTrue(confirmedSelection, "The system picker never exposed a confirmation action")

        // On a compact phone the taller welcome card can legitimately place
        // the first lazy-grid book below the fold. Search every accessibility
        // element and scroll the real shelf instead of treating off-screen as
        // an import failure.
        let imported = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH[c] 'picker-fixture'")
        ).firstMatch
        for _ in 0..<5 where !imported.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        if !imported.exists {
            print("SHELF HIERARCHY AFTER IMPORT:\n\(app.debugDescription)")
        }
        XCTAssertTrue(imported.waitForExistence(timeout: 3), "Selecting a valid image never added it to the shelf")
        imported.tap()

        XCTAssertTrue(
            app.buttons["reader-close"].waitForExistence(timeout: 12),
            "The imported image did not expose ReaderView controls"
        )
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
