import XCTest

/// Creating an account with a password, and signing back in with it.
final class AccountUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetUserState", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Explore"].waitForExistence(timeout: 10))
    }

    func testCreateSignOutAndSignBackIn() {
        openAccountSheet()
        XCTAssertTrue(app.navigationBars["Create Account"].exists, "a device with no accounts should start on Create Account")

        // Mismatched confirmation is caught before anything is saved.
        fill(username: "secure_sam", password: "first-password", confirm: "other-password")
        submit()
        XCTAssertEqual(errorText, "The passwords don't match.")

        // Too short.
        fill(username: nil, password: "short", confirm: "short", clearFirst: true)
        submit()
        XCTAssertEqual(errorText, "Use at least 8 characters.")

        fill(username: nil, password: "first-password", confirm: "first-password", clearFirst: true)
        submit()
        XCTAssertTrue(app.staticTexts["secure_sam"].waitForExistence(timeout: 5), "should be signed in to the new account")

        signOut()

        // Wrong password, then the right one. Starts on Sign In now that an account exists.
        openAccountSheet()
        XCTAssertTrue(app.navigationBars["Sign In"].exists)
        fill(username: "secure_sam", password: "wrong-password")
        submit()
        XCTAssertEqual(errorText, "Incorrect username or password.")
        XCTAssertFalse(app.staticTexts["secure_sam"].exists)

        fill(username: nil, password: "first-password", clearFirst: true)
        submit()
        XCTAssertTrue(app.staticTexts["secure_sam"].waitForExistence(timeout: 5))
    }

    func testUsernameCantBeTakenTwice() {
        openAccountSheet()
        fill(username: "taken_name", password: "first-password", confirm: "first-password")
        submit()
        XCTAssertTrue(app.staticTexts["taken_name"].waitForExistence(timeout: 5))
        signOut()

        openAccountSheet()
        app.segmentedControls.buttons["Create Account"].tap()
        fill(username: "Taken_Name", password: "second-password", confirm: "second-password")
        submit()
        XCTAssertEqual(errorText, "That username is taken. Sign in instead, or pick another name.")
    }

    // MARK: - Helpers

    private var errorText: String? {
        let error = app.staticTexts["SignInError"]
        return error.waitForExistence(timeout: 3) ? error.label : nil
    }

    private func openAccountSheet() {
        app.tabBars.buttons["Profile"].tap()
        app.buttons["Sign In / Sign Up"].tap()
        XCTAssertTrue(app.textFields["UsernameField"].waitForExistence(timeout: 3))
    }

    private func fill(username: String?, password: String, confirm: String? = nil, clearFirst: Bool = false) {
        if let username {
            let field = app.textFields["UsernameField"]
            field.tap()
            field.typeText(username)
        }
        type(password, into: app.secureTextFields["PasswordField"], clearFirst: clearFirst)
        if let confirm {
            type(confirm, into: app.secureTextFields["ConfirmPasswordField"], clearFirst: clearFirst)
        }
    }

    /// Typing into a password field right after focusing it can drop keys while
    /// the secure keyboard appears, so wait, then check the length and retry.
    private func type(_ text: String, into field: XCUIElement, clearFirst: Bool) {
        field.tap()
        sleep(1)
        // iOS offers "Use Strong Password?" in place of the keyboard for new
        // passwords. Decline it, as someone choosing their own password would.
        if app.buttons["GenerateStrongPasswordButton"].waitForExistence(timeout: 1) {
            app.buttons["xmark"].firstMatch.tap()
            sleep(1)
            if !((field.value(forKey: "hasKeyboardFocus") as? Bool) ?? false) { field.tap() }
        }
        if clearFirst {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        }
        for _ in 0..<3 {
            field.typeText(text)
            if (field.value as? String)?.count == text.count { return }
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40))
        }
        XCTFail("couldn't type into \(field.identifier)")
    }

    private func submit() {
        app.buttons["SubmitAccount"].tap()
    }

    private func signOut() {
        app.buttons["Sign Out"].tap()
        let confirm = app.sheets.buttons["Sign Out"].exists ? app.sheets.buttons["Sign Out"] : app.buttons.matching(identifier: "Sign Out").element(boundBy: 1)
        confirm.tap()
        XCTAssertTrue(app.staticTexts["Browsing as Guest"].waitForExistence(timeout: 3))
    }
}
