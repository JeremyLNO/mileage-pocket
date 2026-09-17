import XCTest

/// The screen someone actually meets on their first day.
///
/// With no car yet, the vehicle sheet said "Add the car you drive for work" and gave nothing
/// to add it with — you could read the instruction and not carry it out. The demo data hid
/// this completely: every screenshot, every other test and every run of the suite started
/// with a Tesla already in the store, so the one state a new user cannot avoid was the one
/// state nothing ever looked at.
final class VehicleEmptyStateUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testWithNoVehicleTheSheetOffersToAddOneAndOpensTheForm() {
        // `--empty`: onboarding finished, nothing seeded.
        let app = launchApp(["--empty"])

        let picker = app.buttons["vehiclePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 15), "Home must offer the vehicle sheet")
        picker.tap()

        XCTAssertTrue(
            app.staticTexts["No vehicle yet"].waitForExistence(timeout: 10),
            "with nothing in the store the sheet must show its empty state"
        )

        let add = app.buttons["addVehicleFromPicker"]
        XCTAssertTrue(
            add.waitForExistence(timeout: 5),
            "the empty state names the gesture — it has to carry it too"
        )
        add.tap()

        // The form itself, not just a screen change: the name field is what the user came for.
        XCTAssertTrue(
            app.textFields["Name"].waitForExistence(timeout: 10),
            "the add button must open the vehicle form"
        )
        XCTAssertTrue(app.buttons["Cancel"].exists)
    }

    /// And it has to go all the way through: a car typed in must come back as the one
    /// selected on Home, with the sheet out of the way.
    func testAddingTheFirstVehicleSelectsItAndClosesTheSheet() {
        let app = launchApp(["--empty"])

        app.buttons["vehiclePicker"].tap()
        let add = app.buttons["addVehicleFromPicker"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()

        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap()
        name.typeText("Clio")

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isEnabled, "Done stays disabled until the car has a name")
        done.tap()

        // Asserted on Home's own control, not on the word "Clio".
        //
        // The first version of this test looked for a "Clio" element and passed with the
        // dismissal removed: the picker stays open and simply *lists* the new car, and a row
        // in a list is a button with that label. It proved the vehicle had been created and
        // nothing about the sheet getting out of the way. START exists only on Home.
        XCTAssertTrue(
            app.buttons["Start trip"].waitForExistence(timeout: 10),
            "the sheet must close on its own once the car it asked for exists"
        )
        XCTAssertFalse(app.navigationBars["Vehicle"].exists, "the vehicle sheet is still up")
        XCTAssertEqual(
            app.buttons["vehiclePicker"].label.contains("Clio"), true,
            "Home must now name the car that was just created"
        )
    }
}
