import XCTest

/// The two core loops from `Loops_Plan.md`: Find & Keep, and Make & Share.
final class LoopsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Loop 1: Find & Keep

    /// Search → favorite from the card menu (signing in partway) → it's in
    /// Favorites → still there after relaunch.
    func testFindAndKeep() {
        launch()
        search("dos coyotes")
        let card = card("Cheap Eats Near Campus")
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        XCTAssertTrue(card.label.contains("Includes Dos Coyotes Border Cafe"))

        card.press(forDuration: 1.2)
        app.buttons["Favorite"].firstMatch.tap()
        signIn(as: "finder")

        app.tabBars.buttons["Favorites"].tap()
        XCTAssertTrue(self.card("Cheap Eats Near Campus").waitForExistence(timeout: 3), "the favorite applied after sign-in")

        relaunch()
        app.tabBars.buttons["Favorites"].tap()
        XCTAssertTrue(self.card("Cheap Eats Near Campus").waitForExistence(timeout: 3), "favorite didn't survive relaunch")

        // Unfavorite from the same menu.
        self.card("Cheap Eats Near Campus").press(forDuration: 1.2)
        app.buttons["Unfavorite"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No Favorites Yet"].waitForExistence(timeout: 3))
    }

    // MARK: - Loop 2: Make & Share

    /// New Collection → title, new label, description, 3 places → Publish →
    /// map opens → Share → first in Explore → searchable by label → edit → delete.
    func testMakeAndShare() {
        launch(signedInAs: "maker")
        app.navigationBars["Explore"].buttons["New Collection"].tap()
        XCTAssertTrue(app.navigationBars["New Collection"].waitForExistence(timeout: 3))

        type("Taco Tour of Davis", into: "TitleField")
        type("Tacos", into: "LabelField")
        type("Where to go when you need a taco.", into: "DescriptionField")
        addPlaces(["Redrum", "Dos Coyotes", "Ali Baba"])
        XCTAssertTrue(app.staticTexts["Places (3)"].exists || app.staticTexts["PLACES (3)"].exists)
        attachScreenshot("editor-filled")

        app.navigationBars["New Collection"].buttons["Publish"].tap()
        XCTAssertTrue(app.navigationBars["Taco Tour of Davis"].waitForExistence(timeout: 5), "publishing should open the new map")
        XCTAssertEqual(app.otherElements["AnnotationContainer"].otherElements.count, 3)

        // Share opens the system share sheet.
        app.navigationBars["Taco Tour of Davis"].buttons["Share"].tap()
        let shareSheet = app.otherElements["ActivityListView"]
        XCTAssertTrue(shareSheet.waitForExistence(timeout: 5), "share sheet didn't open")
        attachScreenshot("share-sheet")
        dismissShareSheet()

        // It's first in Explore and findable by its new label.
        app.navigationBars.buttons["BackButton"].tap()
        let firstCard = app.scrollViews.firstMatch.buttons.firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 3))
        XCTAssertTrue(firstCard.label.contains("Taco Tour of Davis"), "new collection should be first, got '\(firstCard.label)'")
        XCTAssertTrue(firstCard.label.contains("by maker"))
        search("tacos")
        XCTAssertTrue(card("Taco Tour of Davis").waitForExistence(timeout: 3))
        XCTAssertEqual(cards.count, 1)

        // Edit: rename and drop a place.
        card("Taco Tour of Davis").tap()
        app.navigationBars["Taco Tour of Davis"].buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Collection"].waitForExistence(timeout: 3))
        let title = field("TitleField")
        title.tap()
        title.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        title.typeText("Taco Tour Remix")
        app.navigationBars["Edit Collection"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Taco Tour Remix"].waitForExistence(timeout: 5), "edit didn't show on the map")

        // Delete.
        app.navigationBars["Taco Tour Remix"].buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit Collection"].waitForExistence(timeout: 3))
        // Delete is the last row of the form, so scroll to it.
        let delete = app.buttons["Delete Collection"]
        for _ in 0..<5 where !(delete.exists && delete.isHittable) {
            app.collectionViews.firstMatch.swipeUp()
        }
        delete.tap()
        app.sheets.buttons["Delete Collection"].exists
            ? app.sheets.buttons["Delete Collection"].tap()
            : app.buttons.matching(identifier: "Delete Collection").element(boundBy: 1).tap()  // confirm
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 5), "deleting should close the map")
        XCTAssertTrue(waitUntilGone(card("Taco Tour Remix")))
    }

    /// The editor won't publish an invalid draft, and says why.
    func testEditorExplainsWhatsMissing() {
        launch(signedInAs: "maker")
        app.navigationBars["Explore"].buttons["New Collection"].tap()
        app.navigationBars["New Collection"].buttons["Publish"].tap()
        XCTAssertTrue(app.staticTexts["Give it a title of 3 to 60 characters."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Add a label of 2 to 24 characters."].exists)
        XCTAssertTrue(app.staticTexts["Add at least one place."].exists)
        XCTAssertTrue(app.navigationBars["New Collection"].exists, "the editor should stay open")

        // Typing part of a label offers matching labels; picking one fills it in.
        let label = field("LabelField")
        label.tap()
        label.typeText("cof")
        XCTAssertTrue(app.buttons["Use label Coffee"].waitForExistence(timeout: 3), "no completion for 'cof'")
        app.buttons["Use label Coffee"].tap()
        XCTAssertEqual(label.value as? String, "Coffee")
        XCTAssertFalse(app.buttons["Use label Coffee"].exists, "suggestions should close once a label is picked")
    }

    /// A guest who taps New Collection signs in, then lands in the editor.
    func testGuestSignsInThenCreates() {
        launch()
        app.navigationBars["Explore"].buttons["New Collection"].tap()
        signIn(as: "newbie")
        XCTAssertTrue(app.navigationBars["New Collection"].waitForExistence(timeout: 5), "editor should open after sign-in")
    }

    /// Opening someone's link shows their collection, which can be favorited.
    func testOpeningASharedLink() {
        launch(signedInAs: "receiver")
        app.tabBars.buttons["Profile"].tap()

        app.open(shareLink(id: "user-friend-1", title: "Friend's Picks", tag: "Tacos", author: "carol",
                           places: ["loc-redrum", "loc-ali-baba"]))
        XCTAssertTrue(app.navigationBars["Friend's Picks"].waitForExistence(timeout: 10), "link didn't open the collection")
        XCTAssertTrue(app.staticTexts["by carol"].exists)
        XCTAssertFalse(app.navigationBars["Friend's Picks"].buttons["Edit"].exists, "only the author can edit")

        app.buttons["Favorite"].tap()
        app.tabBars.buttons["Favorites"].tap()
        XCTAssertTrue(card("Friend's Picks").waitForExistence(timeout: 3))

        // A link to a collection already on the device just opens it.
        app.open(shareLink(id: "col-pizza-night", title: "Pizza Night", tag: "Pizza", author: "slicehunter",
                           places: ["loc-woodstocks"]))
        XCTAssertTrue(app.navigationBars["Pizza Night"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.otherElements["AnnotationContainer"].otherElements.count, 4, "the device's copy, not the link's")
    }

    // MARK: - Helpers

    private var cards: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS ' place'"))
    }

    private func card(_ title: String) -> XCUIElement {
        cards.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    private func launch(signedInAs username: String? = nil) {
        app.launchArguments = ["-resetUserState", "YES"]
        if let username { app.launchArguments += ["-signedInAs", username] }
        app.launch()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 10))
    }

    private func relaunch() {
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 10))
    }

    private func search(_ text: String) {
        let field = app.searchFields.firstMatch
        field.tap()
        field.typeText(text)
    }

    private func field(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func type(_ text: String, into identifier: String) {
        let element = field(identifier)
        XCTAssertTrue(element.waitForExistence(timeout: 3), "no field \(identifier)")
        element.tap()
        element.typeText(text)
    }

    private func addPlaces(_ queries: [String]) {
        app.buttons["AddPlaces"].tap()
        let search = app.navigationBars["Add Places"].searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        for query in queries {
            search.tap()
            if search.buttons["Clear text"].exists {
                search.buttons["Clear text"].tap()
            }
            search.typeText(query)
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", query)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 3), "no place matching \(query)")
            row.tap()
            XCTAssertTrue(row.isSelected, "\(query) wasn't selected")
        }
        // Close the keyboard's search first, then go back to the editor.
        let close = app.navigationBars["Add Places"].buttons["Close"]
        if close.exists { close.tap() }
        app.navigationBars["Add Places"].buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["New Collection"].waitForExistence(timeout: 3))
    }

    /// Fills in the account sheet. New accounts get a password and confirmation.
    private func signIn(as username: String, password: String = "test-password", creating: Bool = true) {
        let field = app.textFields["UsernameField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the sign-in sheet didn't appear")
        app.segmentedControls.buttons[creating ? "Create Account" : "Sign In"].tap()
        field.tap()
        field.typeText(username)
        typeSecurely(password, into: app.secureTextFields["PasswordField"])
        if creating {
            typeSecurely(password, into: app.secureTextFields["ConfirmPasswordField"])
        }
        app.buttons["SubmitAccount"].tap()
        XCTAssertTrue(waitUntilGone(field, timeout: 5), "sign-in didn't finish")
    }

    /// On iOS 26 and later the share sheet is a popover; tapping outside closes it.
    private func dismissShareSheet() {
        let sheet = app.otherElements["ActivityListView"]
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.85)).tap()
        XCTAssertTrue(waitUntilGone(sheet, timeout: 5), "share sheet didn't close")
    }

    /// Builds a link the same way the app does: base64url JSON.
    private func shareLink(id: String, title: String, tag: String, author: String, places: [String]) -> URL {
        let payload: [String: Any] = [
            "id": id, "title": title, "tag": tag, "authorName": author, "description": "", "locationIDs": places,
        ]
        let json = try! JSONSerialization.data(withJSONObject: payload)
        let encoded = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "daviscollections://collection?data=\(encoded)")!
    }

    /// Typing into a password field right after focusing it can drop keys while
    /// the secure keyboard appears, so wait, then check the length and retry.
    private func typeSecurely(_ text: String, into field: XCUIElement) {
        field.tap()
        sleep(1)
        // iOS offers "Use Strong Password?" in place of the keyboard for new
        // passwords. Decline it, as someone choosing their own password would.
        if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 1) {
            app.buttons["xmark"].firstMatch.tap()
            sleep(1)
            if !((field.value(forKey: "hasKeyboardFocus") as? Bool) ?? false) { field.tap() }
        }
        for _ in 0..<3 {
            field.typeText(text)
            if (field.value as? String)?.count == text.count { return }
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        }
        XCTFail("couldn't type into \(field.identifier)")
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
