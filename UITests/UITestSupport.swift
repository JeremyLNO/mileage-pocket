import XCTest

/// Shared setup for UI tests.
///
/// Every test here runs against the same simulator, in alphabetical order, and the app
/// legitimately restores what the previous one left behind — an unfinished trip is resumed
/// on the next launch, which is the crash-recovery feature working exactly as intended. So
/// each test has to arrive at a known state itself rather than assuming a fresh install.
extension XCTestCase {
    /// Launches the app and clears anything a previous test left running.
    @discardableResult
    func launchApp(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        discardTripInProgress(app)
        return app
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
