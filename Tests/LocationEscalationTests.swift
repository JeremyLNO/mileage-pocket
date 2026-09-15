import CoreLocation
import SwiftData
import XCTest
@testable import MileagePocket

/// Getting from "While Using" to "Always".
///
/// iOS refuses to jump straight to Always: the first prompt can only be the While-Using one,
/// and the upgrade has to be a second, separate request — shown **once**. Miss that moment
/// and the app sits on While Using forever, which records a drive begun from the phone and
/// records nothing at all from one begun on the car's screen.
@MainActor
final class LocationEscalationTests: XCTestCase {
    private final class PermissionRecorder: TripRecording {
        var state: RecorderState = .idle
        var onUpdate: (() -> Void)?
        var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
        var authorizationStatus: CLAuthorizationStatus = .notDetermined
        var currentDistanceMeters: Double = 0
        var startedAt: Date?
        var routeSamples: [LocationSample] = []
        private(set) var permissionRequests = 0

        func start(vehicleID: UUID?) throws {}
        func resume(_ trip: Trip) throws {}
        func setBackgroundWatch(_ enabled: Bool) {}
        func stop() throws -> Trip { throw RecorderError.notRecording }
        func resumeIfNeeded() throws -> ResumeOutcome { .none }
        func attachPlaces(to trip: Trip) async {}
        func requestPermission() { permissionRequests += 1 }

        /// iOS answering the first prompt.
        func answer(_ status: CLAuthorizationStatus) {
            authorizationStatus = status
            onAuthorizationChange?(status)
        }
    }

    private var defaultsKey = "location.askedForAlways"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        super.tearDown()
    }

    private func makeRig() throws -> (AppDependencies, PermissionRecorder) {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        let recorder = PermissionRecorder()
        let dependencies = AppDependencies(container: container, recorderFactory: { _ in recorder })
        dependencies.bootstrap()
        return (dependencies, recorder)
    }

    /// The second step, at the only moment iOS will honour it.
    ///
    /// `dependencies` is held, not discarded into `_`: the callback captures `[weak self]`,
    /// so a released `AppDependencies` makes every one of these tests pass for the wrong
    /// reason — or, as here, fail for one.
    func testGrantingWhileUsingImmediatelyAsksForAlways() throws {
        let (dependencies, recorder) = try makeRig()
        let before = recorder.permissionRequests

        recorder.answer(.authorizedWhenInUse)

        XCTAssertEqual(
            recorder.permissionRequests, before + 1,
            "the upgrade has to be asked for the moment While Using is granted"
        )
        XCTAssertTrue(dependencies.hasAskedForAlwaysAuthorization)
    }

    /// Asked once, never again — iOS ignores the rest, so the app must not pretend otherwise.
    func testTheUpgradeIsAskedForOnlyOnce() throws {
        let (dependencies, recorder) = try makeRig()

        recorder.answer(.authorizedWhenInUse)
        let afterFirst = recorder.permissionRequests
        recorder.answer(.authorizedWhenInUse)

        XCTAssertEqual(recorder.permissionRequests, afterFirst)
        XCTAssertTrue(dependencies.hasAskedForAlwaysAuthorization)
        XCTAssertFalse(
            dependencies.canStillAskForAlways,
            "the UI must send the driver to Settings rather than offer a button that does nothing"
        )
    }

    func testAlwaysNeedsNoEscalation() throws {
        let (dependencies, recorder) = try makeRig()
        let before = recorder.permissionRequests

        recorder.answer(.authorizedAlways)

        XCTAssertEqual(recorder.permissionRequests, before, "nothing to upgrade")
        XCTAssertFalse(dependencies.canStillAskForAlways)
        XCTAssertTrue(dependencies.canRecordFromCar)
    }

    /// A refusal is an answer. Asking again from here only ever reaches Settings.
    func testARefusalIsNotEscalated() throws {
        let (dependencies, recorder) = try makeRig()
        let before = recorder.permissionRequests

        recorder.answer(.denied)

        XCTAssertEqual(recorder.permissionRequests, before)
        XCTAssertFalse(dependencies.canStillAskForAlways)
        XCTAssertFalse(dependencies.canRecordFromCar)
    }


    /// Probe: is the injected recorder the one `AppDependencies` actually holds?

    /// Before anything has been answered, asking is still worth offering.
    func testAnUnansweredPromptCanStillBeAsked() throws {
        let (dependencies, recorder) = try makeRig()
        XCTAssertEqual(recorder.authorizationStatus, .notDetermined)
        XCTAssertTrue(dependencies.canStillAskForAlways)
    }
}
