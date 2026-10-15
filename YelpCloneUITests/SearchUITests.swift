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
        field.typeText("temple")

        let studySpots = card("Study Spots That Won't Kick You Out")
        let coffeeCrawl = card("Downtown Coffee Crawl")
        XCTAssertTrue(studySpots.waitForExistence(timeout: 3))
        XCTAssertTrue(coffeeCrawl.exists)
        XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(studySpots.label.contains("Includes Temple Coffee Roasters"), "card '\(studySpots.label)' doesn't say why it matched")
        attachScreenshot("search-temple")

        // Results open their map, and the query survives going back.
        coffeeCrawl.tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(studySpots.waitForExistence(timeout: 3))
        XCTAssertEqual(field.value as? String, "temple")
    }

    func testNoResultsAndClearing() {
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText("sushi")
        XCTAssertTrue(app.staticTexts["No Results for “sushi”"].waitForExistence(timeout: 3))
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
