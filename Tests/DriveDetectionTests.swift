import CoreLocation
import CoreMotion
import SwiftData
import XCTest
@testable import MileagePocket

/// Starting a trip in a car the app has never seen.
///
/// The asymmetry that governs every rule here: a trip that starts by itself and should not
/// have is a line on a tax document for a journey that never happened; a trip that fails to
/// start is a line the driver adds by hand. The second is a nuisance. The first is a false
/// statement, so the classifier is only ever believed when it is sure.
@MainActor
final class DriveDetectionTests: XCTestCase {

    // MARK: - The signal

    private let sure = CMMotionActivityConfidence.high.rawValue
    private let unsure = CMMotionActivityConfidence.low.rawValue

    func testDrivingIsAutomotiveAndSure() {
        XCTAssertEqual(
            DriveSignal.state(automotive: true, stationary: false, walking: false, cycling: false, confidence: sure),
            .driving
        )
    }

    /// A car at a red light is automotive *and* stationary. Reading that as the end of a
    /// drive would cut a commute into one trip per junction.
    func testAStandingCarIsStillDriving() {
        XCTAssertEqual(
            DriveSignal.state(automotive: true, stationary: true, walking: false, cycling: false, confidence: sure),
            .driving
        )
    }

    func testWalkingAndCyclingAreNotDriving() {
        XCTAssertEqual(
            DriveSignal.state(automotive: false, stationary: false, walking: true, cycling: false, confidence: sure),
            .notDriving
        )
        XCTAssertEqual(
            DriveSignal.state(automotive: false, stationary: false, walking: false, cycling: true, confidence: sure),
            .notDriving
        )
    }

    /// Low confidence is the coprocessor saying it has not made up its mind — at a bus stop,
    /// on a train, in a lift. Nothing is decided on it, in either direction.
    func testAnUnsureClassifierDecidesNothing() {
        XCTAssertEqual(
            DriveSignal.state(automotive: true, stationary: false, walking: false, cycling: false, confidence: unsure),
            .unknown
        )
        XCTAssertEqual(
            DriveSignal.state(automotive: false, stationary: true, walking: false, cycling: false, confidence: unsure),
            .unknown
        )
    }

    /// Medium is the floor, and a threshold is wrong at its boundary first.
    func testMediumConfidenceIsEnoughAndLowIsNot() {
        let medium = CMMotionActivityConfidence.medium.rawValue
        XCTAssertEqual(
            DriveSignal.state(automotive: true, stationary: false, walking: false, cycling: false, confidence: medium),
            .driving
        )
        XCTAssertEqual(
            DriveSignal.state(automotive: true, stationary: false, walking: false, cycling: false, confidence: medium - 1),
            .unknown
        )
    }

    // MARK: - The wiring

    private final class FakeDetector: DriveDetecting {
        var isAvailable = true
        var onChange: ((DriveSignal.State) -> Void)?
        private(set) var isRunning = false

        func start() { isRunning = true }
        func stop() { isRunning = false }
        func checkNow() {}

        func report(_ state: DriveSignal.State) { onChange?(state) }
    }

    private final class SpyRecorder: TripRecording {
        var state: RecorderState = .idle
        var onUpdate: (() -> Void)?
        var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
        var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
        var currentDistanceMeters: Double = 0
        var startedAt: Date?
        var routeSamples: [LocationSample] = []
        private(set) var startCount = 0
        private(set) var stopCount = 0

        func start(vehicleID: UUID?) throws {
            startCount += 1
            startedAt = Date(timeIntervalSince1970: 1_700_000_000)
            state = .recording(startedAt: startedAt!, distanceMeters: 0, duration: 0)
        }

        func resume(_ trip: Trip) throws {}

        func stop() throws -> Trip {
            stopCount += 1
            state = .idle
            let trip = Trip(startedAt: startedAt ?? .now)
            trip.endedAt = trip.startedAt.addingTimeInterval(600)
            return trip
        }

        func resumeIfNeeded() throws -> ResumeOutcome { .none }
        func attachPlaces(to trip: Trip) async {}
        func requestPermission() {}
        func setBackgroundWatch(_ enabled: Bool) {}
        func drive(_ metres: Double) { currentDistanceMeters += metres }
    }

    private struct Rig {
        let dependencies: AppDependencies
        let detector: FakeDetector
        let recorder: SpyRecorder
    }

    private func makeRig(enabled: Bool, available: Bool = true) throws -> Rig {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        let detector = FakeDetector()
        detector.isAvailable = available
        let recorder = SpyRecorder()
        let dependencies = AppDependencies(
            container: container, recorderFactory: { _ in recorder }, driveDetector: detector
        )
        dependencies.bootstrap()
        dependencies.setAutoStartOnDriving(enabled)
        return Rig(dependencies: dependencies, detector: detector, recorder: recorder)
    }

    func testDrivingStartsATripWhenTheSwitchIsOn() throws {
        let rig = try makeRig(enabled: true)
        XCTAssertTrue(rig.detector.isRunning)

        rig.detector.report(.driving)

        XCTAssertEqual(rig.recorder.startCount, 1)
        XCTAssertTrue(rig.dependencies.isRecording)
    }

    func testNothingHappensWhenTheSwitchIsOff() throws {
        let rig = try makeRig(enabled: false)
        XCTAssertFalse(rig.detector.isRunning, "off costs nothing, including the coprocessor")

        rig.detector.report(.driving)

        XCTAssertEqual(rig.recorder.startCount, 0)
    }

    /// A switch that can do nothing must not be offered, and must not be obeyed either.
    func testAPhoneWithoutTheSensorNeverStartsTheDetector() throws {
        let rig = try makeRig(enabled: true, available: false)
        XCTAssertFalse(rig.detector.isRunning)
    }

    /// The end of a drive waits, like a head unit going quiet — the classifier hesitates at
    /// long red lights, and a drive must not end at one.
    func testTheEndOfDrivingIsConfirmedBeforeTheTripStops() throws {
        let rig = try makeRig(enabled: true)
        rig.detector.report(.driving)

        rig.detector.report(.notDriving)
        XCTAssertEqual(rig.recorder.stopCount, 0, "not on the spot")

        rig.dependencies.confirmAutoStop()
        XCTAssertEqual(rig.recorder.stopCount, 1)
    }

    /// The classifier changing its mind back inside the window is the case this exists for.
    func testDrivingAgainDuringTheWindowKeepsTheTrip() throws {
        let rig = try makeRig(enabled: true)
        rig.detector.report(.driving)
        rig.detector.report(.notDriving)
        rig.detector.report(.driving)

        rig.dependencies.confirmAutoStop()

        XCTAssertEqual(rig.recorder.stopCount, 0)
        XCTAssertEqual(rig.recorder.startCount, 1, "and no second trip either")
    }

    /// Two signals answering different questions. A drive is over only when neither of them
    /// says otherwise — a phone that lost the head unit but is plainly still in a moving car
    /// has not arrived anywhere.
    func testTheMotionSignalKeepsATripAliveWhenCarPlayGoesQuiet() throws {
        let rig = try makeRig(enabled: true)
        rig.detector.report(.driving)

        rig.dependencies.carPlayConnectionChanged(false)
        rig.dependencies.confirmAutoStop()

        XCTAssertEqual(rig.recorder.stopCount, 0, "the phone is still in a moving car")
    }
}
