import XCTest

/// Searching collections from the Explore tab.
final class SearchUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetUserState", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 10))
    }

    func testSearchFiltersAndExplainsPlaceMatches() {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "search field should always be visible")
        field.tap()
        // Symposium is only in Pizza Night, so this matches by place alone.
        field.typeText("symposium")

        let pizzaNight = card("Pizza Night")
        XCTAssertTrue(pizzaNight.waitForExistence(timeout: 3))
        XCTAssertEqual(cards.count, 1)
        XCTAssertTrue(pizzaNight.label.contains("Includes Symposium Restaurant"), "card '\(pizzaNight.label)' doesn't say why it matched")
        attachScreenshot("search-symposium")

        // Results open their map, and the query survives going back.
        pizzaNight.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(pizzaNight.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "symposium")
    }

    func testNoResultsAndClearing() {
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("karting")
        XCTAssertTrue(app.staticTexts["No Results for “karting”"].waitForExistence(timeout: 3))
        attachScreenshot("search-no-results")

        // iOS 26 and later replace the search bar's Cancel button with Close.
        let close = app.navigationBars["Explore"].buttons["Close"]
        (close.exists ? close : app.buttons["Cancel"]).tap()
        XCTAssertTrue(card("Best Parks in Davis").waitForExistence(timeout: 3), "closing search should restore the full grid")
    }

    func testMultipleWordsNarrowResults() {
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("venus")
        XCTAssertTrue(card("Date Night Downtown").waitForExistence(timeout: 3))
        XCTAssertTrue(card("Brunch Worth the Wait").exists)

        field.typeText(" date")
        XCTAssertTrue(waitUntilGone(card("Brunch Worth the Wait")))
        XCTAssertTrue(card("Date Night Downtown").exists)
    }

    // While searching, the keyboard adds its own scroll views, so find cards by
    // label rather than through the grid's scroll view.
    private var cards: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS ' place'"))
    }

    private func card(_ title: String) -> XCUIElement {
        cards.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while element.exists && Date() < deadline { usleep(200_000) }
        return !element.exists
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
