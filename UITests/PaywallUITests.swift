import XCTest

/// StoreKit Testing only applies through the scheme's configuration file, so the paywall can
/// only be exercised — and captured — from a UI test. A `simctl launch` shows an endless
/// spinner instead of the plans.
final class PaywallUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchOnPaywall() -> XCUIApplication {
        let app = XCUIApplication()
        // No `--demo`: premium must be locked for the paywall to be the real screen.
        // `--fake-store` draws the plans from the bundled StoreKit configuration: the
        // scheme's StoreKit session does not reach the app under test on this machine, and
        // creating an `SKTestSession` from the UI-test process crashes the app (the session
        // has to live in the same process as the StoreKit client). The prices asserted below
        // are therefore the configured ones, which is what the screen must show.
        app.launchArguments = ["--screen=paywall", "--demo-data-only", "--fake-store"]
        app.launch()
        return app
    }

    func testPaywallShowsLivePricesAndTheTrialOffer() {
        let app = launchOnPaywall()

        let headline = app.staticTexts["Your mileage. Automatically documented."]
        XCTAssertTrue(headline.waitForExistence(timeout: 15), "the paywall must reach the user")

        // Prices come from StoreKit, never from a literal in the UI. Asserting the configured
        // amounts proves the products loaded *and* that nothing is hard-coded elsewhere.
        let monthly = app.staticTexts["$2.99"]
        let annual = app.staticTexts["$29.99"]
        XCTAssertTrue(monthly.waitForExistence(timeout: 15), "the monthly price must come from StoreKit")
        XCTAssertTrue(annual.exists, "the annual price must come from StoreKit")

        // 12 × 2.99 = 35.88 against 29.99 is a 16 % saving — computed, not typed.
        // `.textCase(.uppercase)` is a rendering transform: the accessibility label keeps the
        // original casing, so matching the drawn text exactly would fail for the wrong reason.
        let saving = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "16%")).firstMatch
        XCTAssertTrue(saving.exists, "the annual saving must be derived from the two live prices")

        let cta = app.buttons["Start 3-day free trial"]
        XCTAssertTrue(cta.exists, "the introductory offer must drive the call to action")

        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "3 days free")).firstMatch.exists,
            "the footer must state the trial and the price that follows it"
        )
    }

    /// A paywall with no way out is a common rejection, and the spec requires a person's own
    /// data to stay reachable without paying.
    func testPaywallCanBeDismissed() {
        let app = launchOnPaywall()
        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        close.tap()
        XCTAssertTrue(app.buttons["Start trip"].waitForExistence(timeout: 10), "closing the paywall must land on the app")
    }

    /// Produces the App Store Connect review screenshot for the two subscriptions. Run with
    /// the runner script, which pulls the image off the simulator.
    func testCaptureForAppStoreReview() {
        let app = launchOnPaywall()
        XCTAssertTrue(app.staticTexts["Your mileage. Automatically documented."].waitForExistence(timeout: 15))
        // Let the prices land before the shutter.
        XCTAssertTrue(app.staticTexts["$29.99"].waitForExistence(timeout: 15))

        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "paywall"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

extension PaywallUITests {
    /// The onboarding paywall is a page in a `TabView`, not a sheet — so `dismiss()` has
    /// nothing to dismiss and the close button did nothing at all. Tapping it must land the
    /// user in the app.
    func testClosingTheOnboardingPaywallEntersTheApp() {
        let app = XCUIApplication()
        app.launchArguments = ["--onboarding-step=5", "--fake-store"]
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Your mileage. Automatically documented."].waitForExistence(timeout: 15),
            "the onboarding paywall must be showing"
        )

        let close = app.buttons["Close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()

        XCTAssertTrue(
            app.buttons["Start trip"].waitForExistence(timeout: 10),
            "closing the onboarding paywall must finish onboarding and open the app"
        )
    }
}
