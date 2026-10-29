import XCTest

// libnotify (part of libSystem); its header isn't exposed to Swift on iOS.
@_silgen_name("notify_post") private func notify_post(_ name: UnsafePointer<CChar>) -> UInt32
@_silgen_name("notify_register_check")
private func notify_register_check(_ name: UnsafePointer<CChar>, _ token: UnsafeMutablePointer<Int32>) -> UInt32
@_silgen_name("notify_set_state") private func notify_set_state(_ token: Int32, _ state: UInt64) -> UInt32

/// Biometric unlock against the real Keychain + LocalAuthentication, driving the simulator's
/// Face ID through BiometricKit's simulator notifications (the same switches as the Simulator's
/// Features ▸ Face ID menu). A physical device is still needed to vouch for the real sensor.
@MainActor
final class BiometricUITests: XCTestCase {
    private let password = "Str0ng!Passw0rd"
    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("drives the simulator's Face ID")
        #endif
        continueAfterFailure = false
        Self.setFaceIDEnrolled(true)
        app = XCUIApplication()
        app.launchArguments = ["-uitest-inmemory"]
        app.launch()
    }

    override func tearDown() async throws {
        Self.setFaceIDEnrolled(false)
    }

    private static func setFaceIDEnrolled(_ enrolled: Bool) {
        var token: Int32 = 0
        _ = notify_register_check("com.apple.BiometricKit.enrollmentChanged", &token)
        _ = notify_set_state(token, enrolled ? 1 : 0)
        _ = notify_post("com.apple.BiometricKit.enrollmentChanged")
    }

    private static func presentFace(matching: Bool) {
        _ = notify_post(matching ? "com.apple.BiometricKit_Sim.pearl.match" : "com.apple.BiometricKit_Sim.pearl.nomatch")
    }

    /// The first use asks for Face ID permission (NSFaceIDUsageDescription).
    private func allowFaceIDIfAsked() {
        let ok = springboard.buttons["OK"]
        if ok.waitForExistence(timeout: 3) { ok.tap() }
    }

    private func createVault() {
        let field = app.secureTextFields["setup.password"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(password)
        app.secureTextFields["setup.confirm"].tap(); app.secureTextFields["setup.confirm"].typeText(password)
        app.buttons["setup.create"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["vault.empty"].waitForExistence(timeout: 10))
    }

    func testEnableThenUnlockWithFaceID() {
        createVault()
        app.buttons["vault.settings"].tap()
        let toggle = app.switches["settings.biometric"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Face ID toggle: enrollment not seen")
        XCTAssertEqual(toggle.value as? String, "0")

        toggle.switches.firstMatch.tap()
        allowFaceIDIfAsked()
        Self.presentFace(matching: true)
        XCTAssertTrue(waitFor(toggle, value: "1"), "Face ID enrol didn't complete")

        // Lock: the unlock screen prompts on its own; a matching face unlocks.
        backToVault()
        lockVault()
        XCTAssertTrue(app.buttons["unlock.biometric"].waitForExistence(timeout: 5))
        Self.presentFace(matching: true)
        XCTAssertTrue(app.descendants(matching: .any)["vault.empty"].waitForExistence(timeout: 10))

        // A face that doesn't match leaves it locked; the password still works.
        lockVault()
        XCTAssertTrue(app.buttons["unlock.biometric"].waitForExistence(timeout: 5))
        Self.presentFace(matching: false)
        let cancel = springboard.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 5) { cancel.tap() }
        XCTAssertFalse(app.descendants(matching: .any)["vault.empty"].waitForExistence(timeout: 2))
        let field = app.secureTextFields["unlock.password"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText(password)
        app.buttons["unlock.submit"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["vault.empty"].waitForExistence(timeout: 10))

        // Turning it off removes the button.
        app.buttons["vault.settings"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.tap()
        XCTAssertTrue(waitFor(toggle, value: "0"))
        backToVault()
        lockVault()
        XCTAssertTrue(app.secureTextFields["unlock.password"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["unlock.biometric"].exists)
    }

    /// The Face ID HUD can still be fading out and swallow a tap, so retry.
    private func backToVault() {
        for _ in 0..<5 where !app.buttons["vault.lock"].exists {
            app.navigationBars.buttons["BackButton"].tap()
            _ = app.buttons["vault.lock"].waitForExistence(timeout: 2)
        }
        XCTAssertTrue(app.buttons["vault.lock"].exists)
    }

    /// Same HUD problem as `backToVault`.
    private func lockVault() {
        for _ in 0..<5 where app.buttons["vault.lock"].exists {
            app.buttons["vault.lock"].tap()
            _ = app.secureTextFields["unlock.password"].waitForExistence(timeout: 2)
        }
        XCTAssertTrue(app.secureTextFields["unlock.password"].exists)
    }

    private func waitFor(_ element: XCUIElement, value: String, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate(format: "value == %@", value)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
}
