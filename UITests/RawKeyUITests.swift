import XCTest

/// Catches untranslated keys drawn on screen.
///
/// The unit tests prove the catalog holds every key; they cannot see a *call site* that
/// never looks one up. `LocalizedStringKey("vehicle.type.\(raw)")` composes
/// `"vehicle.type.%@"`, matches nothing, and SwiftUI then draws the interpolated text — so
/// `vehicle.type.car` appeared in a shipped build with every unit test green.
///
/// The only place that shows is the screen, so that is where this looks.
final class RawKeyUITests: XCTestCase {
    /// A raw key looks like `word.word` or `word.word.word`: lowercase segments joined by
    /// dots, no spaces. Real copy has spaces, capitals or punctuation.
    private static let rawKeyPattern = try! NSRegularExpression(pattern: "^[a-z][a-zA-Z0-9]*(\\.[a-zA-Z0-9]+){1,3}$")

    private func assertNoRawKeys(in app: XCUIApplication, screen: String, file: StaticString = #filePath, line: UInt = #line) {
        var offenders: [String] = []
        for element in app.staticTexts.allElementsBoundByIndex + app.buttons.allElementsBoundByIndex {
            let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty, !label.contains(" ") else { continue }
            let range = NSRange(label.startIndex..., in: label)
            if Self.rawKeyPattern.firstMatch(in: label, range: range) != nil {
                offenders.append(label)
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "\(screen) shows untranslated keys: \(offenders.joined(separator: ", "))",
            file: file,
            line: line
        )
    }

    func testOnboardingShowsNoRawKeys() {
        let app = XCUIApplication()
        // No `--demo`: onboarding is skipped in demo mode, and the vehicle picker lives here.
        app.launchArguments = ["--reset-onboarding"]
        app.launch()

        let welcome = app.staticTexts["Track every business mile."]
        XCTAssertTrue(welcome.waitForExistence(timeout: 15), "onboarding must be showing")
        assertNoRawKeys(in: app, screen: "onboarding — welcome")

        app.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Your country"].waitForExistence(timeout: 5))
        assertNoRawKeys(in: app, screen: "onboarding — country")

        app.buttons["Continue"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Your vehicle"].waitForExistence(timeout: 5))
        assertNoRawKeys(in: app, screen: "onboarding — vehicle")

        // The picker's own menu is where the keys appeared, and it is only rendered once open.
        let picker = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Car")).firstMatch
        if picker.waitForExistence(timeout: 3) {
            picker.tap()
            // Give the menu a moment to present before reading its labels.
            XCTAssertTrue(app.buttons["Van"].waitForExistence(timeout: 5), "the vehicle type menu must be open")
            assertNoRawKeys(in: app, screen: "onboarding — vehicle type menu")
        }
    }

    func testMainTabsShowNoRawKeys() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()

        XCTAssertTrue(app.buttons["Start trip"].waitForExistence(timeout: 15))
        assertNoRawKeys(in: app, screen: "home")

        for tab in ["Trips", "Reports", "Settings"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
            assertNoRawKeys(in: app, screen: tab.lowercased())
        }
    }
}
