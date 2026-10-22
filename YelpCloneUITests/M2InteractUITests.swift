import XCTest

/// Stage 1, Milestone 2 exit criteria 7–12.
final class M2InteractUITests: XCTestCase {
    private let seed = SeedFixture.shared
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    // MARK: - Criteria

    /// 7. As a guest, Like, Dislike, Favorite, and Post show the sign-in sheet,
    /// and nothing changes if the user cancels.
    func test7_GuestActionsShowSignInAndCancelChangesNothing() {
        launch()
        openCollection("Pizza Night")

        for title in ["Like", "Dislike", "Favorite"] {
            let button = app.buttons[title]
            let valueBefore = button.value as? String
            button.tap()
            XCTAssertTrue(signInSheet.waitForExistence(timeout: 3), "\(title) didn't ask a guest to sign in")
            app.navigationBars.buttons["Cancel"].firstMatch.tap()
            XCTAssertTrue(waitUntilGone(signInSheet))
            XCTAssertEqual(button.value as? String, valueBefore, "\(title) changed without signing in")
            XCTAssertFalse(button.isSelected, "\(title) became active without signing in")
        }

        openComments()
        let draft = "Guest draft"
        typeComment(draft)
        app.buttons["Post"].tap()
        XCTAssertTrue(signInSheet.waitForExistence(timeout: 3), "Post didn't ask a guest to sign in")
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(waitUntilGone(signInSheet))
        XCTAssertEqual(commentField.value as? String, draft, "the draft should survive cancelling")
        XCTAssertFalse(firstCommentLabel.contains(draft), "the comment posted without signing in")
    }

    /// 8. After signing in from the sheet, the action that triggered it is applied.
    func test8_SigningInAppliesTheTriggeringAction() {
        launch()
        let collection = seed.collection(titled: "Pizza Night")
        openCollection(collection.title)

        app.buttons["Like"].tap()
        signIn(as: "tester")
        XCTAssertTrue(app.buttons["Like"].isSelected)
        XCTAssertEqual(app.buttons["Like"].value as? String, "\(collection.likeCount + 1)")

        // A guest's comment posts once they sign in. Sign out first to be a guest again.
        signOutFromProfile()
        app.tabBars.buttons["Explore"].tap()
        openComments()
        let text = "Posted after sign-in \(Int.random(in: 1000...9999))"
        typeComment(text)
        app.buttons["Post"].tap()
        signIn(as: "tester", creating: false)
        XCTAssertTrue(waitFor { self.firstCommentLabel.contains(text) }, "pending comment wasn't posted after sign-in")
        XCTAssertEqual(commentField.value as? String ?? "", "Add a comment", "the draft should clear once posted")
    }

    /// 9. Like and Dislike are mutually exclusive and counts update immediately.
    func test9_LikeAndDislikeAreExclusive() {
        launch(signedInAs: "tester")
        let collection = seed.collection(titled: "Best Parks in Davis")
        openCollection(collection.title)
        let like = app.buttons["Like"], dislike = app.buttons["Dislike"]

        like.tap()
        XCTAssertTrue(like.isSelected)
        XCTAssertEqual(like.value as? String, "\(collection.likeCount + 1)")
        XCTAssertEqual(dislike.value as? String, "\(collection.dislikeCount)")

        dislike.tap()
        XCTAssertTrue(dislike.isSelected)
        XCTAssertFalse(like.isSelected)
        XCTAssertEqual(like.value as? String, "\(collection.likeCount)")
        XCTAssertEqual(dislike.value as? String, "\(collection.dislikeCount + 1)")

        dislike.tap()
        XCTAssertFalse(dislike.isSelected)
        XCTAssertEqual(dislike.value as? String, "\(collection.dislikeCount)")

        // The grid card shows the same derived like count.
        like.tap()
        goBack()
        XCTAssertTrue(card(collection.title).label.contains("\(collection.likeCount + 1)"))
    }

    /// 10. Favorited collections appear in Favorites, and unfavoriting removes them.
    func test10_FavoritesTab() {
        launch()
        app.tabBars.buttons["Favorites"].tap()
        XCTAssertTrue(app.staticTexts["Sign In to See Favorites"].waitForExistence(timeout: 3), "guests should see a sign-in prompt")

        launch(signedInAs: "tester")
        app.tabBars.buttons["Favorites"].tap()
        XCTAssertTrue(app.staticTexts["No Favorites Yet"].waitForExistence(timeout: 3))

        app.tabBars.buttons["Explore"].tap()
        for title in ["Pizza Night", "Dog-Friendly Davis"] {
            openCollection(title)
            app.buttons["Favorite"].tap()
            XCTAssertTrue(app.buttons["Favorite"].isSelected)
            goBack()
        }

        app.tabBars.buttons["Favorites"].tap()
        XCTAssertTrue(card("Pizza Night").waitForExistence(timeout: 3))
        XCTAssertTrue(card("Dog-Friendly Davis").exists)
        XCTAssertEqual(app.scrollViews.firstMatch.buttons.count, 2)

        // Unfavorite from a map opened in the Favorites tab.
        card("Pizza Night").tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Favorite"].tap()
        XCTAssertFalse(app.buttons["Favorite"].isSelected)
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitUntilGone(card("Pizza Night")))
        XCTAssertTrue(card("Dog-Friendly Davis").exists)
    }

    /// 11. A posted comment appears at the top of the list.
    func test11_PostedCommentIsFirst() {
        launch(signedInAs: "tester")
        openCollection("Best Parks in Davis")
        openComments()
        let text = "Top of the list \(Int.random(in: 1000...9999))"
        typeComment(text)
        app.buttons["Post"].tap()
        XCTAssertTrue(waitFor { self.firstCommentLabel.contains(text) }, "first comment is '\(firstCommentLabel)'")
        XCTAssertTrue(firstCommentLabel.contains("tester"))
    }

    /// 12. Sign-in, reactions, favorites, and comments survive a relaunch;
    /// signing out returns to guest mode, which can still browse.
    func test12_StateSurvivesRelaunchAndSignOut() {
        launch(signedInAs: "persist_me")
        openCollection("Davis End to End")
        app.buttons["Dislike"].tap()
        app.buttons["Favorite"].tap()
        openComments()
        let text = "Still here after relaunch"
        typeComment(text)
        app.buttons["Post"].tap()
        XCTAssertTrue(waitFor { self.firstCommentLabel.contains(text) })

        app.terminate()
        app.launchArguments = []
        app.launch()

        app.tabBars.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["persist_me"].waitForExistence(timeout: 3), "sign-in didn't persist")
        app.tabBars.buttons["Explore"].tap()
        openCollection("Davis End to End")
        XCTAssertTrue(app.buttons["Dislike"].isSelected, "reaction didn't persist")
        XCTAssertTrue(app.buttons["Favorite"].isSelected, "favorite didn't persist")
        openComments()
        XCTAssertTrue(firstCommentLabel.contains(text), "comment didn't persist")
        dismissComments()
        goBack()

        signOutFromProfile()
        XCTAssertTrue(app.staticTexts["Browsing as Guest"].exists)
        app.tabBars.buttons["Explore"].tap()
        openCollection("Davis End to End")
        XCTAssertFalse(app.buttons["Dislike"].isSelected, "a guest shouldn't see another user's reaction")
        XCTAssertTrue(app.otherElements["AnnotationContainer"].exists, "guest can't browse after signing out")
    }

    /// 13. A single place can be saved from its pin without favoriting the
    /// collection. It shows under Favorites > Places and can be unsaved there.
    func test13_SaveASinglePlace() {
        launch()
        let collection = seed.collection(titled: "The Only Burger That Matters")
        let place = seed.locations(in: collection)[0]
        openCollection(collection.title)
        app.otherElements["AnnotationContainer"].otherElements[place.name].tap()

        // A guest is asked to sign in, and the save applies afterward.
        let save = app.buttons["Save Place"]
        XCTAssertTrue(save.waitForExistence(timeout: 3), "the place sheet has no Save button")
        save.tap()
        signIn(as: "saver")
        XCTAssertTrue(waitFor { save.isSelected }, "the place wasn't saved after sign-in")
        XCTAssertFalse(app.buttons["Favorite"].isSelected, "saving a place shouldn't favorite its collection")
        dismissPlaceSheet()

        app.tabBars.buttons["Favorites"].tap()
        XCTAssertTrue(app.staticTexts["No Favorites Yet"].waitForExistence(timeout: 3), "the collection itself isn't a favorite")
        app.segmentedControls.buttons["Places"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", place.name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "\(place.name) isn't under Places")
        XCTAssertTrue(row.label.contains("From \(collection.title)"), "row '\(row.label)' doesn't say where it was saved from")

        // Unsave from the place's sheet.
        row.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isSelected)
        save.tap()
        XCTAssertTrue(waitFor { !save.isSelected })
        dismissPlaceSheet()
        XCTAssertTrue(app.staticTexts["No Saved Places"].waitForExistence(timeout: 3))
    }

    // MARK: - Helpers

    /// The account sheet, found by its username field since its title follows the mode.
    private var signInSheet: XCUIElement { app.textFields["UsernameField"] }
    private var commentField: XCUIElement { app.textViews["CommentField"].exists ? app.textViews["CommentField"] : app.textFields["CommentField"] }

    /// The top comment's combined label: author, time, and text.
    private var firstCommentLabel: String {
        let row = app.descendants(matching: .any).matching(identifier: "CommentRow").firstMatch
        return row.exists ? row.label : ""
    }

    private func launch(signedInAs username: String? = nil) {
        app.terminate()
        app.launchArguments = ["-resetUserState", "YES"]
        if let username { app.launchArguments += ["-signedInAs", username] }
        app.launch()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 10))
    }

    private func card(_ title: String) -> XCUIElement {
        app.scrollViews.firstMatch.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    private func openCollection(_ title: String) {
        let card = card(title)
        let tabBarTop = app.tabBars.firstMatch.frame.minY
        for _ in 0..<6 where !(card.exists && card.isHittable && card.frame.maxY < tabBarTop) {
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
        card.tap()
        XCTAssertTrue(app.buttons["Like"].waitForExistence(timeout: 5), "\(title) didn't open")
    }

    private func goBack() {
        app.navigationBars.buttons["BackButton"].tap()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 3))
    }

    private func openComments() {
        app.buttons["Comments"].tap()
        XCTAssertTrue(app.navigationBars["Comments"].waitForExistence(timeout: 3))
    }

    private func dismissComments() {
        let bar = app.navigationBars["Comments"]
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        XCTAssertTrue(waitUntilGone(bar))
    }

    /// Drags the place sheet down by its grabber.
    private func dismissPlaceSheet() {
        let grabber = app.buttons["Sheet Grabber"]
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        XCTAssertTrue(waitUntilGone(app.buttons["Save Place"]), "the place sheet didn't close")
    }

    private func typeComment(_ text: String) {
        commentField.tap()
        commentField.typeText(text)
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

    private func signOutFromProfile() {
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Sign Out"].tap()
        let confirm = app.sheets.buttons["Sign Out"].exists ? app.sheets.buttons["Sign Out"] : app.buttons.matching(identifier: "Sign Out").element(boundBy: 1)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Browsing as Guest"].waitForExistence(timeout: 3))
    }

    private func waitFor(_ timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline { usleep(200_000) }
        return condition()
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
        waitFor(timeout) { !element.exists }
    }
}
