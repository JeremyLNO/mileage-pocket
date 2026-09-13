import XCTest

/// Shared setup for UI tests.
///
/// Every test here runs against the same simulator, in alphabetical order, and the app
/// legitimately restores what the previous one left behind — an unfinished trip is resumed
/// on the next launch, which is the crash-recovery feature working exactly as intended. So
/// each test has to arrive at a known state itself rather than assuming a fresh install.
extension XCTestCase {
    /// Launches the app, answers the location prompt if it appears, and clears anything a
    /// previous test left running.
    @discardableResult
    func launchApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        allowLocationIfAsked()
        discardTripInProgress(app)
        return app
    }

    /// Answers the system location prompt.
    ///
    /// `simctl privacy grant` is not enough on its own: a reinstall during the run can put the
    /// authorisation back to "not determined", the prompt then appears over the app, no fixes
    /// are delivered while it is up, and the trip records 0.0 km — which reads exactly like a
    /// tracking bug. Handling the prompt here makes the tests independent of whatever TCC
    /// state the simulator happens to be in.
    func allowLocationIfAsked() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Autoriser lorsque l'app est active"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
    }

    /// A trip left running by an earlier test shows the driving screen instead of the app,
    /// and every subsequent assertion then fails looking for a tab bar that is not there.
    func discardTripInProgress(_ app: XCUIApplication) {
        let stop = app.buttons["Stop trip"]
        guard stop.waitForExistence(timeout: 3) else { return }
        stop.tap()
        let discard = app.buttons["Discard"]
        if discard.waitForExistence(timeout: 15) { discard.tap() }
    }
}
