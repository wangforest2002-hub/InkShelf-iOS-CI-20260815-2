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

        let emptyImport = app.buttons["把读物带回家"]
        if emptyImport.waitForExistence(timeout: 2) {
            emptyImport.tap()
        } else {
            app.buttons["导入"].tap()
            XCTAssertTrue(app.buttons["导入文件或图片"].waitForExistence(timeout: 2))
            app.buttons["导入文件或图片"].tap()
        }

        let fixture = app.staticTexts["picker-fixture.png"]
        XCTAssertTrue(fixture.waitForExistence(timeout: 8), "The system document picker did not open the requested folder")
        fixture.tap()

        let open = app.buttons["打开"]
        if open.waitForExistence(timeout: 2) {
            open.tap()
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
}
