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
}
