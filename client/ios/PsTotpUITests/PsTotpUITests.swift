import PsTotpCore
import XCTest

/// End-to-end flow on a fresh in-memory vault (`-uitest-inmemory`).
@MainActor
final class PsTotpUITests: XCTestCase {
    private let password = "Str0ng!Passw0rd"
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest-inmemory"]
        app.launch()
    }

    private func type(_ text: String, into id: String, in scope: XCUIElementQuery? = nil) {
        let query = scope ?? app.descendants(matching: .any)
        let field = query[id].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "\(id) missing")
        field.tap()
        field.typeText(text)
    }

    /// Opens the add sheet and switches to the Manual method (Scan QR is the default).
    private func openAddManual() {
        app.buttons["vault.add"].tap()
        let manual = app.segmentedControls.buttons["Manual"]
        XCTAssertTrue(manual.waitForExistence(timeout: 5))
        manual.tap()
    }

    private func createVault() {
        type(password, into: "setup.password")
        type(password, into: "setup.confirm")
        app.buttons["setup.create"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["vault.empty"].waitForExistence(timeout: 10))
    }

    func testSetupRejectsAWeakPassword() {
        type("weak", into: "setup.password")
        type("weak", into: "setup.confirm")
        app.buttons["setup.create"].tap()
        let error = app.staticTexts["setup.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Password must be at least 8 characters")
        XCTAssertFalse(app.descendants(matching: .any)["vault.empty"].exists)
    }

    func testFullFlowSetupAddLockUnlockDelete() {
        createVault()

        // Add via the manual form.
        openAddManual()
        type("GitHub", into: "add.issuer")
        type("octocat", into: "add.account")
        type("JBSWY3DPEHPK3PXP", into: "add.secret")
        app.buttons["add.submit"].tap()

        let card = app.descendants(matching: .any)["card.GitHub"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let code = card.staticTexts["code"]
        XCTAssertTrue(code.exists)
        XCTAssertNotNil(code.label.range(of: #"^Code (\d ){5}\d$"#, options: .regularExpression),
                        "unexpected code label: \(code.label)")

        // Lock, fail to unlock, unlock.
        app.buttons["vault.lock"].tap()
        type("not the password", into: "unlock.password")
        app.buttons["unlock.submit"].tap()
        let error = app.staticTexts["unlock.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertEqual(error.label, "Incorrect password")

        let field = app.secureTextFields["unlock.password"]
        field.tap()
        field.clearText()
        field.typeText(password)
        app.buttons["unlock.submit"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["card.GitHub"].waitForExistence(timeout: 10))

        // Delete by swipe + confirm.
        app.descendants(matching: .any)["card.GitHub"].swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        app.alerts["Delete Account"].buttons["Delete"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["vault.empty"].waitForExistence(timeout: 5))
    }

    func testInvalidSecretShowsAnErrorAndAddsNothing() {
        createVault()
        openAddManual()
        type("Oops", into: "add.issuer")
        type("not base32 !!", into: "add.secret")
        app.buttons["add.submit"].tap()
        let error = app.staticTexts["add.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Secret key is not valid Base32")
        XCTAssertFalse(app.descendants(matching: .any)["card.Oops"].exists)
    }

    func testShowQRCodeEncodesTheEntry() throws {
        createVault()
        openAddManual()
        type("GitHub", into: "add.issuer")
        type("octocat", into: "add.account")
        type("JBSWY3DPEHPK3PXP", into: "add.secret")
        app.buttons["add.submit"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["card.GitHub"].waitForExistence(timeout: 5))

        app.buttons["More options for GitHub"].tap()
        app.buttons["Show QR Code"].tap()

        let qr = app.descendants(matching: .any)["qr.image"]
        XCTAssertTrue(qr.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["GitHub — octocat"].exists)

        // Decode what is actually on screen: the code must carry this account.
        let shot = try XCTUnwrap(qr.screenshot().image.cgImage)
        XCTAssertEqual(
            QRCode.decode(shot),
            ["otpauth://totp/octocat?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA1&digits=6&period=30"])

        app.buttons["Close"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["card.GitHub"].waitForExistence(timeout: 5))
    }

    func testScanTabExplainsAMissingCameraOnTheSimulator() throws {
        #if targetEnvironment(simulator)
        createVault()
        app.buttons["vault.add"].tap()
        // Scan QR is the default method; the simulator has no camera.
        XCTAssertTrue(app.descendants(matching: .any)["scan.unavailable"].waitForExistence(timeout: 5))
        // The other methods are still reachable from here.
        XCTAssertTrue(app.segmentedControls.buttons["Image"].exists)
        XCTAssertTrue(app.segmentedControls.buttons["Paste URI"].exists)
        // Scan/Image add on detection, so the toolbar Add button is hidden.
        XCTAssertFalse(app.buttons["add.submit"].exists)
        app.segmentedControls.buttons["Manual"].tap()
        XCTAssertTrue(app.buttons["add.submit"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("simulator-only: a real device has a camera")
        #endif
    }
}

private extension XCUIElement {
    func clearText() {
        guard let value = value as? String, !value.isEmpty else { return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
}
