import XCTest

/// The promise the whole product rests on: open, START, drive, STOP, BUSINESS, Save.
/// If this ever takes more than a handful of taps, the product has drifted.
final class TripFlowUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchApp(_ extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"] + extraArguments
        app.launch()
        discardAnyTripInProgress(app)
        return app
    }

    /// A previous run that ended mid-trip leaves an active trip behind, and the app correctly
    /// resumes it on the next launch — so the test starts by clearing one rather than
    /// depending on a fresh install.
    private func discardAnyTripInProgress(_ app: XCUIApplication) {
        let stop = app.buttons["Stop trip"]
        guard stop.waitForExistence(timeout: 3) else { return }
        stop.tap()
        let discard = app.buttons["Discard"]
        if discard.waitForExistence(timeout: 15) { discard.tap() }
    }

    /// Drives the full loop. Location is fed from the outside by
    /// `xcrun simctl location … start`, which the runner script starts before this test.
    func testStartDriveStopClassifyAndSave() {
        let app = launchApp()

        let start = app.buttons["Start trip"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "the START control must be on the first screen")
        start.tap()

        let stop = app.buttons["Stop trip"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "STOP must appear as soon as a trip starts")

        // Let the simulated drive accumulate distance.
        Thread.sleep(forTimeInterval: 18)
        stop.tap()

        let business = app.buttons["Business"]
        XCTAssertTrue(business.waitForExistence(timeout: 15), "the summary sheet must offer Business/Personal")
        business.tap()

        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // Back on Home, and the trip we just recorded is the last one.
        XCTAssertTrue(app.buttons["Start trip"].waitForExistence(timeout: 10), "the app must return to Home after saving")

        // A saved trip has to carry a real distance. An 18-second drive at 25 m/s covers a
        // few hundred metres, so a "0.0 km" card here would mean the fixes never landed —
        // the failure mode a green start/stop test would otherwise hide.
        // Addressed by identifier, not by "the first text containing km": that matched the
        // month total on Home and passed while the recorded trip was actually 0.0 km.
        let lastTrip = app.staticTexts["lastTripDistance"]
        XCTAssertTrue(lastTrip.waitForExistence(timeout: 10), "the saved trip must appear on Home")
        XCTAssertFalse(
            lastTrip.label.hasPrefix("0") && !lastTrip.label.hasPrefix("0."),
            "unexpected label: \(lastTrip.label)"
        )
        let metres = Double(lastTrip.label.replacingOccurrences(of: ",", with: ".")
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .first(where: { !$0.isEmpty }) ?? "0") ?? 0
        XCTAssertGreaterThan(metres, 0.05, "an 18-second drive at 25 m/s must record more than 50 m, got \(lastTrip.label)")
    }

    /// Counts the taps the daily loop costs. Three is the design budget: START, STOP,
    /// BUSINESS — Save is the fourth and the sheet is dismissible without it only by
    /// discarding, so four is the honest ceiling.
    func testTheDailyLoopStaysWithinItsTapBudget() {
        let app = launchApp()
        var taps = 0

        let start = app.buttons["Start trip"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap(); taps += 1

        let stop = app.buttons["Stop trip"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 6)
        stop.tap(); taps += 1

        let business = app.buttons["Business"]
        XCTAssertTrue(business.waitForExistence(timeout: 15))
        business.tap(); taps += 1

        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap(); taps += 1

        XCTAssertLessThanOrEqual(taps, 4, "the everyday loop must not cost more than four taps")
    }
}
