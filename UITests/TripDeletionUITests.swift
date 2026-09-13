import XCTest

/// Deleting a trip must remove it from the list there and then.
///
/// It used to persist the deletion but leave the row on screen until the next launch: the
/// app ran two SwiftData contexts, and the one the writes went through was not the one
/// `@Query` observes. Nothing failed — the data was correct, only the screen was not — which
/// is why only a test that looks at the screen catches it.
final class TripDeletionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Deleting asks for confirmation — it is destructive and irreversible. The dialog's own
    /// Delete is a second, distinct button.
    private func confirmDeletion(_ app: XCUIApplication) {
        let confirm = app.sheets.buttons["Delete"].firstMatch
        if confirm.waitForExistence(timeout: 5) {
            confirm.tap()
            return
        }
        // Presented as an alert on some size classes.
        let alertConfirm = app.alerts.buttons["Delete"].firstMatch
        if alertConfirm.waitForExistence(timeout: 3) { alertConfirm.tap() }
    }

    func testDeletingATripRemovesItFromTheListWithoutRelaunching() {
        // `--reset-data` reseeds: these tests delete rows, and the seed only runs on an
        // empty store, so without it the demo data would shrink with every run.
        let app = launchApp(["--demo", "--reset-data"])

        app.tabBars.buttons["Trips"].tap()

        // Rows are buttons, not cells: a `NavigationLink` inside a `List` is exposed as a
        // button, and targeting cells tapped nothing at all.
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "→"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "the demo data must produce a list of trips")

        // Held by its own label so the assertion cannot be satisfied by the next row sliding
        // up into the same position.
        let label = rows.firstMatch.label
        XCTAssertFalse(label.isEmpty)

        rows.firstMatch.tap()
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "the detail screen must offer Delete")
        delete.tap()
        confirmDeletion(app)

        XCTAssertTrue(app.navigationBars["Trips"].waitForExistence(timeout: 10), "deleting must return to the list")

        // Asserted on that row's own label rather than on a row count: the list scrolls, so
        // a row below simply moves up into the freed space and the number of rendered rows
        // does not change. The label is what proves this particular trip is gone.
        XCTAssertFalse(
            app.buttons[label].waitForExistence(timeout: 3),
            "the deleted trip is still in the list — it used to stay until the next launch"
        )
    }

    /// Home shows the most recent trip; deleting that trip must take the card with it.
    func testDeletingTheLastTripUpdatesTheHomeCard() {
        // `--reset-data` reseeds: these tests delete rows, and the seed only runs on an
        // empty store, so without it the demo data would shrink with every run.
        let app = launchApp(["--demo", "--reset-data"])

        let lastTripDistance = app.staticTexts["lastTripDistance"]
        XCTAssertTrue(lastTripDistance.waitForExistence(timeout: 10))
        let before = lastTripDistance.label

        app.tabBars.buttons["Trips"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "→"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        rows.firstMatch.tap()

        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        confirmDeletion(app)

        // The tab switch has to wait for the pop to land: a tab tap fired while the
        // navigation stack is still animating back is swallowed, and the app simply stays
        // on Trips — which reads exactly like a missing Home card.
        XCTAssertTrue(app.navigationBars["Trips"].waitForExistence(timeout: 10))

        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(lastTripDistance.waitForExistence(timeout: 10))
        XCTAssertNotEqual(
            lastTripDistance.label, before,
            "Home still shows the trip that was just deleted"
        )
    }
}
