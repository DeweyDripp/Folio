import XCTest

/// Exercises the imported EPUB used for simulator smoke testing.
/// Skip on an empty simulator; the test never imports or deletes library books.
final class PaperCurlUITests: XCTestCase {
    @MainActor
    func testEPUBCurlGestures() throws {
        let app = XCUIApplication()
        app.launch()
        let book = app.staticTexts["Children's Literature"].firstMatch
        try XCTSkipUnless(book.waitForExistence(timeout: 5), "Import the smoke-test EPUB first")
        book.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))

        let title = app.buttons["Reader menu for Children's Literature"]
        title.tap()
        let toggle = app.switches["Page turn animation"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        if toggle.value as? String == "0" { toggle.tap() }
        app.buttons["Close reader menu"].tap()

        let page = app.webViews.firstMatch
        let start = page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.55))
        let middle = page.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.55))
        // Hold halfway through so a simulator recording can inspect the curved paper.
        start.press(forDuration: 0.05, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 6)
        XCTAssertTrue(page.exists)
        attach(app, name: "After forward curl")

        let left = page.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.55))
        left.press(forDuration: 0.05, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 2)
        XCTAssertTrue(page.exists)
        attach(app, name: "After backward curl")

        title.tap()
        if toggle.value as? String == "1" { toggle.tap() }
        app.buttons["Close reader menu"].tap()
        page.swipeLeft()
        XCTAssertTrue(page.exists)
        attach(app, name: "Animation disabled")
        // Restore the enabled preference used at the start of the test.
        title.tap()
        if toggle.value as? String == "0" { toggle.tap() }
        app.buttons["Close reader menu"].tap()
    }

    @MainActor
    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
