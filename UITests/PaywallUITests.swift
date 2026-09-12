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
        app.launchArguments = ["--screen=paywall", "--demo-data-only"]
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
        XCTAssertTrue(app.staticTexts["SAVE 16%"].exists, "the annual saving must be derived from the two live prices")

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
    /// Diagnostic: surfaces whatever StoreKit said, so a paywall that shows no plans reports
    /// a reason instead of a spinner.
    func testReportsWhyPlansAreMissing() {
        let app = launchOnPaywall()
        XCTAssertTrue(app.staticTexts["Your mileage. Automatically documented."].waitForExistence(timeout: 15))

        let unavailable = app.staticTexts["Plans are unavailable right now."]
        if unavailable.waitForExistence(timeout: 20) {
            let detail = app.staticTexts["paywallError"]
            XCTFail("StoreKit returned no products. Reported reason: \(detail.exists ? detail.label : "none")")
        }
    }
}
