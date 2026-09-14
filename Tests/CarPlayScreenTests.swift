import XCTest
@testable import MileagePocket

/// What the car's screen says.
///
/// CarPlay itself cannot be exercised from a command line — there is no way to attach a head
/// unit to a simulator — so everything that can be got wrong is decided in
/// `CarPlayTripScreen` and asserted here. What remains untested is the mapping onto
/// `CPInformationTemplate`, which is three assignments.
final class CarPlayScreenTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() {
        super.setUp()
        L.languageCode = "en"
    }

    private func screen(
        isRecording: Bool = false,
        isPaused: Bool = false,
        canStart: Bool = true,
        distanceMeters: Double = 0,
        startedAt: Date? = nil,
        vehicleName: String? = "Tesla Model 3",
        elapsed: TimeInterval = 0
    ) -> CarPlayTripScreen {
        CarPlayTripScreen.make(
            isRecording: isRecording,
            isPaused: isPaused,
            canStart: canStart,
            distanceMeters: distanceMeters,
            startedAt: startedAt,
            vehicleName: vehicleName,
            unit: .kilometers,
            locale: Locale(identifier: "en_GB"),
            now: (startedAt ?? start).addingTimeInterval(elapsed)
        )
    }

    func testIdleOffersStartAndNamesTheCar() {
        let screen = screen()
        XCTAssertEqual(screen.action, .start)
        XCTAssertEqual(screen.actionTitle, "Start trip")
        XCTAssertEqual(screen.rows.first?.detail, "Ready")
        XCTAssertTrue(
            screen.rows.contains { $0.detail == "Tesla Model 3" },
            "the driver has to see which car the trip will be filed against before pressing"
        )
    }

    func testRecordingShowsDistanceAndDurationAndOffersStop() {
        let screen = screen(
            isRecording: true, distanceMeters: 24_300, startedAt: start, elapsed: 1_200
        )
        XCTAssertEqual(screen.action, .stop)
        XCTAssertEqual(screen.actionTitle, "Stop trip")
        XCTAssertEqual(screen.rows.map(\.detail).first, "Recording")
        XCTAssertTrue(screen.rows.contains { $0.detail == "24.3 km" }, screen.rows.map(\.detail).description)
        XCTAssertTrue(screen.rows.contains { $0.detail == "20 min" }, screen.rows.map(\.detail).description)
    }

    /// The clock runs from the start of the trip, not from the last movement: one that reset
    /// at every red light would be worse than none.
    func testTheClockDoesNotResetWhenTheCarStops() {
        let screen = screen(
            isRecording: true, isPaused: true, distanceMeters: 24_300, startedAt: start, elapsed: 1_200
        )
        XCTAssertTrue(screen.rows.contains { $0.detail == "20 min" })
    }

    /// Standing still is not the same as not recording, and the distance already banked must
    /// still be on screen — `RecorderState` reports 0 while paused, and reading it there
    /// would blank the figure every time the driver stopped at a light.
    func testAPausedTripStillShowsItsDistanceAndCanBeStopped() {
        let screen = screen(
            isRecording: true, isPaused: true, distanceMeters: 24_300, startedAt: start
        )
        XCTAssertEqual(screen.action, .stop)
        XCTAssertEqual(screen.rows.first?.detail, "Stopped — waiting to move")
        XCTAssertTrue(screen.rows.contains { $0.detail == "24.3 km" })
    }

    /// A paywall cannot be shown on a car screen. Offering a button that would silently fail
    /// is the worst of the three options; the screen says where to go instead.
    func testWithoutAccessThereIsNoButtonAtAll() {
        let screen = screen(canStart: false)
        XCTAssertEqual(screen.action, CarPlayTripScreen.Action.none)
        XCTAssertNil(screen.actionTitle, "a control that does nothing is worse than no control")
        XCTAssertEqual(screen.rows.first?.detail, "Subscription needed")
        XCTAssertTrue(screen.rows.contains { $0.detail == "Open Mileage Pocket on your iPhone" })
    }

    /// Access is checked for *starting*, not for stopping: a trip already running must always
    /// be stoppable, whatever happened to the subscription mid-drive.
    func testATripInProgressCanBeStoppedEvenWithoutAccess() {
        let screen = screen(isRecording: true, canStart: false, distanceMeters: 5_000, startedAt: start)
        XCTAssertEqual(screen.action, .stop)
        XCTAssertNotNil(screen.actionTitle)
    }

    func testDistanceFollowsTheUsersUnit() {
        let miles = CarPlayTripScreen.make(
            isRecording: true, isPaused: false, canStart: true,
            distanceMeters: 24_300, startedAt: start, vehicleName: nil,
            unit: .miles, locale: Locale(identifier: "en_US"), now: start
        )
        XCTAssertTrue(miles.rows.contains { $0.detail.contains("mi") }, miles.rows.map(\.detail).description)
    }

    /// The screen is only redrawn when it changes — CarPlay animates every assignment, and a
    /// template rebuilt once a second flickers for the whole drive. That relies on equality
    /// actually distinguishing two states.
    func testTwoDifferentStatesAreNotEqual() {
        let first = screen(isRecording: true, distanceMeters: 24_300, startedAt: start)
        let second = screen(isRecording: true, distanceMeters: 24_400, startedAt: start)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, screen(isRecording: true, distanceMeters: 24_300, startedAt: start))
    }
}
