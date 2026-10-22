import XCTest

/// Adding places that aren't bundled: from Apple Maps, or by dropping a pin.
final class AddPlacesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetUserState", "YES", "-signedInAs", "adder"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 10))
        app.navigationBars["Explore"].buttons["New Collection"].tap()
        XCTAssertTrue(app.navigationBars["New Collection"].waitForExistence(timeout: 3))
        type("Late Night Eats", into: "TitleField")
        type("Fast Food", into: "LabelField")
    }

    /// Search Apple Maps for a chain that isn't bundled, add it, and publish.
    func testAddFromAppleMaps() throws {
        openPicker()
        searchPlaces("mcdonalds")

        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "McDonald")).firstMatch
        let offline = app.staticTexts["Couldn't reach Apple Maps. Check your connection, or drop a pin instead."]
        let deadline = Date().addingTimeInterval(20)
        while !result.exists && !offline.exists && Date() < deadline { usleep(300_000) }
        if offline.exists { throw XCTSkip("Apple Maps search needs a network connection") }
        XCTAssertTrue(result.exists, "no McDonald's in Apple Maps results")
        attachScreenshot("apple-maps-results")

        let name = String(result.label.prefix { $0 != "," })
        result.tap()
        XCTAssertTrue(result.isSelected)

        backToEditor()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Added by you'")).firstMatch.exists)
        publish()

        // The pin opens with no rating, since nobody has reviewed it here.
        let pin = app.otherElements["AnnotationContainer"].otherElements[name]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), "no pin for \(name)")
        pin.tap()
        XCTAssertTrue(app.staticTexts["Not yet rated"].waitForExistence(timeout: 3))
        attachScreenshot("added-place-sheet")
    }

    /// A restaurant too new for Apple Maps: drop a pin and name it.
    func testDropAPin() {
        openPicker()
        searchPlaces("Brand New Bistro")
        // Nothing matches, so Drop a Pin sits just under the search results.
        // Closing search would clear the text, so tap it while still searching.
        let dropPin = app.buttons["DropPin"]
        XCTAssertTrue(app.staticTexts["No other matches on Apple Maps."].waitForExistence(timeout: 20)
                      || app.staticTexts["Couldn't reach Apple Maps. Check your connection, or drop a pin instead."].exists)
        XCTAssertTrue(dropPin.isHittable, "Drop a Pin should be reachable without leaving search")
        dropPin.tap()
        XCTAssertTrue(app.navigationBars["Drop a Pin"].waitForExistence(timeout: 3))
        XCTAssertEqual(field("PinNameField").value as? String, "Brand New Bistro", "the search text should become the name")

        // The address fills in from the pin, and follows it when the map moves.
        let address = field("PinAddressField")
        XCTAssertTrue(waitFor(10) { !((address.value as? String) ?? "").isEmpty && address.value as? String != "Address" },
                      "address didn't fill in from the pin")
        let firstAddress = address.value as? String
        app.maps.firstMatch.swipeLeft(velocity: .slow)
        XCTAssertTrue(waitFor(10) { address.value as? String != firstAddress }, "address didn't follow the pin")
        attachScreenshot("drop-pin")
        app.navigationBars["Drop a Pin"].buttons["Add"].tap()

        XCTAssertTrue(app.navigationBars["Add Places"].waitForExistence(timeout: 3))
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Brand New Bistro")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(row.isSelected, "a dropped pin should be added and selected")

        backToEditor()
        publish()
        let pin = app.otherElements["AnnotationContainer"].otherElements["Brand New Bistro"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.tap()
        XCTAssertTrue(app.staticTexts["Not yet rated"].waitForExistence(timeout: 3))
    }

    /// Before searching, the editor and picker suggest places that fit the
    /// draft, and the full list is one tap away, grouped by type.
    func testSuggestionsBeforeSearching() {
        // The editor offers a few one-tap adds based on the title and label.
        let quickAdd = app.buttons.matching(identifier: "QuickAdd").firstMatch
        XCTAssertTrue(quickAdd.waitForExistence(timeout: 3), "no suggested places in the editor")
        attachScreenshot("editor-suggestions")
        let added = quickAdd.label.replacingOccurrences(of: "Add ", with: "")
        quickAdd.tap()
        XCTAssertTrue(app.staticTexts[added].waitForExistence(timeout: 3), "\(added) wasn't added")

        openPicker()
        let header = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'Suggested for'")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 3), "no suggestions in the picker")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'Places in the App'")).firstMatch.exists,
                       "the full list shouldn't be the first thing shown")
        attachScreenshot("picker-suggestions")

        // Tapping a suggestion selects it in place.
        let rows = app.buttons.matching(identifier: "PlaceRow")
        let suggestion = rows.allElementsBoundByIndex.first { !$0.isSelected && $0.isHittable }
        XCTAssertNotNil(suggestion, "every suggestion was already selected")
        let label = suggestion!.label
        suggestion!.tap()
        let tapped = rows.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(tapped.isSelected, "\(label) wasn't selected")

        // Browse All Places lists everything by type.
        for _ in 0..<4 where !app.buttons["BrowseAllPlaces"].isHittable { app.collectionViews.firstMatch.swipeUp() }
        app.buttons["BrowseAllPlaces"].tap()
        XCTAssertTrue(app.navigationBars["All Places"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] 'American'")).firstMatch.exists, "places aren't grouped by type")
        attachScreenshot("all-places")
        app.navigationBars["All Places"].buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Add Places"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["3 places selected"].exists || app.staticTexts["2 places selected"].exists)
    }

    // MARK: - Helpers

    private func field(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func type(_ text: String, into identifier: String) {
        let element = field(identifier)
        XCTAssertTrue(element.waitForExistence(timeout: 3), "no field \(identifier)")
        element.tap()
        element.typeText(text)
    }

    private func openPicker() {
        app.buttons["AddPlaces"].tap()
        XCTAssertTrue(app.navigationBars["Add Places"].waitForExistence(timeout: 3))
    }

    private func searchPlaces(_ text: String) {
        let search = app.navigationBars["Add Places"].searchFields.firstMatch
        search.tap()
        search.typeText(text)
    }

    private func backToEditor() {
        let close = app.navigationBars["Add Places"].buttons["Close"]
        if close.exists { close.tap() }
        app.navigationBars["Add Places"].buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["New Collection"].waitForExistence(timeout: 3))
    }

    private func publish() {
        app.navigationBars["New Collection"].buttons["Publish"].tap()
        XCTAssertTrue(app.navigationBars["Late Night Eats"].waitForExistence(timeout: 5), "publishing should open the map")
    }

    private func waitFor(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { usleep(300_000) }
        return condition()
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
