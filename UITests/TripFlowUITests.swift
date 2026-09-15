import XCTest

/// The promise the whole product rests on: open, START, drive, STOP, BUSINESS, Save.
/// If this ever takes more than a handful of taps, the product has drifted.
final class TripFlowUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchDemoApp(_ extraArguments: [String] = []) -> XCUIApplication {
        launchApp(["--demo"] + extraArguments)
    }

    /// Drives the full loop. Location is fed from the outside by
    /// `xcrun simctl location … start`, which the runner script starts before this test.
    func testStartDriveAndStopSavesTheTripWithoutAskingAnything() {
        let app = launchDemoApp()

        let start = app.buttons["Start trip"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "the START control must be on the first screen")
        start.tap()
        // The prompt is raised by START, not by launching: answering it at launch was too
        // early, and the trip then recorded 0.0 km while the dialog sat over the app.
        allowLocationIfAsked()

        let stop = app.buttons["Stop trip"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "STOP must appear as soon as a trip starts")

        // Let the simulated drive accumulate distance.
        Thread.sleep(forTimeInterval: 18)
        stop.tap()

        // Nothing is asked. Stopping used to open a summary sheet that had to be filled in
        // before the trip counted; a drive that is over is a drive that is recorded, and the
        // classification is asked for later, from the review queue.
        XCTAssertTrue(
            app.buttons["Start trip"].waitForExistence(timeout: 15),
            "stopping must land straight back on Home, with the trip already saved"
        )
        XCTAssertFalse(
            app.buttons["Business"].exists,
            "stopping must not put a form between the driver and a saved trip"
        )

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
        XCTAssertGreaterThan(
            metres, 0.05,
            """
            Recorded \(lastTrip.label) for an 18-second drive at 25 m/s.
            Either the app recorded nothing, or nothing was moving — run this through             tools/run-tests.sh, which grants location permission and feeds a simulated drive.             Those preconditions failing look identical to a tracking bug from here.
            """
        )
    }

    /// The everyday loop must cost four taps — START, STOP, BUSINESS, Save — and nothing
    /// must stand between them.
    ///
    /// This used to count a variable the test incremented itself and assert it was at most
    /// four, which is true by construction: no change to the app could make it fail. What
    /// actually has to be proved is that nothing is *interposed* — a paywall on START (which
    /// shipped, and which the free period now prevents), a confirmation on STOP, a form
    /// standing between a finished drive and a saved one.
    ///
    /// The loop is now **two** taps: START, STOP. It used to be four, because stopping
    /// opened a summary that had to be filled in before the trip counted.
    func testTheDailyLoopIsTwoTapsAndNothingElse() {
        let app = launchDemoApp()

        let start = app.buttons["Start trip"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        allowLocationIfAsked()

        // Tap 1 must put the app on the driving screen, not in front of an offer.
        XCTAssertFalse(
            app.staticTexts["Your mileage. Automatically documented."].waitForExistence(timeout: 2),
            "starting a trip must never raise the paywall"
        )
        let stop = app.buttons["Stop trip"]
        XCTAssertTrue(stop.waitForExistence(timeout: 10), "START alone has to reach the driving screen")

        Thread.sleep(forTimeInterval: 6)
        stop.tap()

        // Tap 2 ends it. Nothing asks anything, and the app is ready for the next drive.
        XCTAssertTrue(
            app.buttons["Start trip"].waitForExistence(timeout: 15),
            "STOP alone has to save the trip and return to Home"
        )
        XCTAssertEqual(app.alerts.count, 0, "stopping must not ask anything")
        XCTAssertEqual(app.sheets.count, 0, "nor put a sheet in the way")
        XCTAssertFalse(app.buttons["Save"].exists, "nor a form to fill in")

        // And the drive really was recorded — the whole point of not asking.
        let lastTrip = app.staticTexts["lastTripDistance"]
        XCTAssertTrue(lastTrip.waitForExistence(timeout: 10), "the trip must be on Home already")
    }
}
