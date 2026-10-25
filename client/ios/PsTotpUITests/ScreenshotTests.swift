import XCTest

/// Writes screenshots to a host directory for visual review. Skipped unless run with
/// `TEST_RUNNER_PSTOTP_SHOTS=<directory>`, so it never affects normal test runs.
final class ScreenshotTests: XCTestCase {
    private var directory: String?
    private let password = "Str0ng!Passw0rd"

    override func setUpWithError() throws {
        continueAfterFailure = false
        directory = ProcessInfo.processInfo.environment["PSTOTP_SHOTS"]
        try XCTSkipIf(directory == nil, "set TEST_RUNNER_PSTOTP_SHOTS to capture screenshots")
        try FileManager.default.createDirectory(atPath: directory!, withIntermediateDirectories: true)
    }

    private func shot(_ app: XCUIApplication, _ name: String) throws {
        try app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(directory!)/\(name).png"))
    }

    private func type(_ app: XCUIApplication, _ text: String, into id: String) {
        let field = app.descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(text)
    }

    private func run(style: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-inmemory", "-AppleInterfaceStyle", style.capitalized]   // "Dark" / "Light"
        app.launch()

        type(app, password, into: "setup.password")
        type(app, password, into: "setup.confirm")
        try shot(app, "\(style)-1-setup-filled")
        app.buttons["setup.create"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["vault.empty"].waitForExistence(timeout: 10))
        try shot(app, "\(style)-2-empty")

        for (issuer, account, secret) in [
            ("GitHub", "octocat", "JBSWY3DPEHPK3PXP"),
            ("Google", "alice@example.com", "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"),
            ("Acme Bank", "alice", "NBSWY3DPFQQHO33SNRSCC"),
        ] {
            app.buttons["vault.add"].tap()
            type(app, issuer, into: "add.issuer")
            type(app, account, into: "add.account")
            type(app, secret, into: "add.secret")
            if issuer == "Acme Bank" { try shot(app, "\(style)-3-add-sheet") }
            app.buttons["add.submit"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["card.\(issuer)"].waitForExistence(timeout: 5))
        }
        try shot(app, "\(style)-4-vault")

        app.buttons["vault.sort"].tap()
        try shot(app, "\(style)-5-sort-menu")
    }

    func testLight() throws { try run(style: "light") }
    func testDark() throws { try run(style: "dark") }
}
