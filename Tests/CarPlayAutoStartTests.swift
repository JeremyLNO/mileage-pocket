import AVFoundation
import CoreLocation
import SwiftData
import XCTest
@testable import MileagePocket

/// Plugging into CarPlay is the one moment the app can know a drive is beginning without
/// being asked — and the moment a driver is least likely to reach for their phone.
///
/// The dangerous half is the other one: a trip that starts on its own and never stops
/// records a duration and an end point that never happened, which is the single failure this
/// product exists to prevent.
@MainActor
final class CarPlayAutoStartTests: XCTestCase {
    /// Stands in for the audio route.
    private final class FakeCarConnection: CarConnectionObserving {
        var isConnected = false
        var onChange: ((Bool) -> Void)?
        private(set) var started = false
        private(set) var refreshCount = 0

        func start() { started = true }
        func stop() { started = false }
        func refresh() { refreshCount += 1 }

        func plugIn() { isConnected = true; onChange?(true) }
        func unplug() { isConnected = false; onChange?(false) }
    }

    /// Records what it was asked to do, without a GPS behind it.
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

        func resume(_ trip: Trip) throws {
            startCount += 1
            startedAt = trip.startedAt
            currentDistanceMeters = trip.distanceMeters
            state = .recording(startedAt: trip.startedAt, distanceMeters: currentDistanceMeters, duration: 0)
        }

        /// Moves the car, for the rule that refuses to end a trip that is still under way.
        func drive(_ meters: Double) { currentDistanceMeters += meters }

        func stop() throws -> Trip {
            stopCount += 1
            state = .idle
            let trip = Trip(startedAt: startedAt ?? .now)
            trip.endedAt = trip.startedAt.addingTimeInterval(600)
            trip.rawDistanceMeters = 5_000
            return trip
        }

        func resumeIfNeeded() throws -> ResumeOutcome { .none }
        func attachPlaces(to trip: Trip) async {}
        func requestPermission() {}
        func setBackgroundWatch(_ enabled: Bool) {}
    }

    private struct Rig {
        let dependencies: AppDependencies
        let car: FakeCarConnection
        let recorder: SpyRecorder
    }

    private func makeRig(autoStart: Bool, autoStop: Bool = true) throws -> Rig {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        let car = FakeCarConnection()
        let recorder = SpyRecorder()
        let dependencies = AppDependencies(
            container: container,
            recorderFactory: { _ in recorder },
            carConnectionMonitor: car
        )
        dependencies.bootstrap()
        dependencies.settingsStore.settings.autoStartOnCarPlay = autoStart
        dependencies.settingsStore.settings.autoStopOnCarPlayDisconnect = autoStop
        dependencies.settingsStore.save()
        return Rig(dependencies: dependencies, car: car, recorder: recorder)
    }

    func testPluggingIntoCarPlayStartsATripWhenTheSettingIsOn() throws {
        let rig = try makeRig(autoStart: true)
        rig.car.plugIn()

        XCTAssertEqual(rig.recorder.startCount, 1, "connecting to a car has to start the trip")
        XCTAssertTrue(rig.dependencies.isRecording)
    }

    func testPluggingInDoesNothingWhenTheSettingIsOff() throws {
        let rig = try makeRig(autoStart: false)
        rig.car.plugIn()

        XCTAssertEqual(rig.recorder.startCount, 0, "off means off — a trip must stay the driver's decision")
        XCTAssertFalse(rig.dependencies.isRecording)
    }

    /// The half that keeps the record honest — but not instantly.
    ///
    /// The audio route is not a seatbelt sensor: it drops for a phone call, for Siri, when
    /// the head unit switches to radio, when a wireless link stutters at a junction. Ending
    /// the drive on the spot is what Jeremy saw as "the trip stops for no reason", mid-drive,
    /// with nothing said.
    func testUnpluggingDoesNotEndTheTripUntilTheCarHasStayedGone() throws {
        let rig = try makeRig(autoStart: true)
        rig.car.plugIn()
        rig.car.unplug()

        XCTAssertEqual(rig.recorder.stopCount, 0, "a dropped link is not a parked car")
        XCTAssertTrue(rig.dependencies.isRecording)

        rig.dependencies.confirmCarPlayStop()

        XCTAssertEqual(rig.recorder.stopCount, 1, "a trip that starts by itself has to end by itself")
        XCTAssertFalse(rig.dependencies.isRecording)
    }

    /// The link comes back before the window is up: whatever that was, it was not the end of
    /// the drive, and the confirmation that was armed must find nothing to do.
    func testPluggingBackInDuringTheGraceCancelsTheStop() throws {
        let rig = try makeRig(autoStart: true)
        rig.car.plugIn()
        rig.car.unplug()
        rig.car.plugIn()

        rig.dependencies.confirmCarPlayStop()

        XCTAssertEqual(rig.recorder.stopCount, 0, "the car is right there")
        XCTAssertTrue(rig.dependencies.isRecording)
        XCTAssertEqual(rig.recorder.startCount, 1, "and no second trip was opened either")
    }

    /// Still covering ground with no head unit: a dropped link, not a parked car. Cutting the
    /// drive in half here is the expensive half of the mistake — the rest of the journey is
    /// never recorded at all.
    func testATripStillCoveringGroundIsNotEnded() throws {
        let rig = try makeRig(autoStart: true)
        rig.car.plugIn()
        rig.car.unplug()
        rig.recorder.drive(400)

        rig.dependencies.confirmCarPlayStop()

        XCTAssertEqual(rig.recorder.stopCount, 0, "the car is still driving")
        XCTAssertTrue(rig.dependencies.isRecording)

        // Parked at last: nothing moves during the next window, and the trip ends.
        rig.dependencies.confirmCarPlayStop()
        XCTAssertEqual(rig.recorder.stopCount, 1)
    }

    /// Automatic stopping belongs to automatic starting, even when the setting is on: a drive
    /// the driver began by hand is theirs to end.
    func testAHandStartedTripIsNeverEndedByTheCar() throws {
        let rig = try makeRig(autoStart: true)
        rig.dependencies.startTrip()
        rig.car.unplug()
        rig.dependencies.confirmCarPlayStop()

        XCTAssertEqual(rig.recorder.stopCount, 0)
        XCTAssertTrue(rig.dependencies.isRecording)
    }

    func testUnpluggingLeavesTheTripRunningWhenAutomaticStoppingIsOff() throws {
        let rig = try makeRig(autoStart: true, autoStop: false)
        rig.car.plugIn()
        rig.car.unplug()
        rig.dependencies.confirmCarPlayStop()

        XCTAssertEqual(rig.recorder.stopCount, 0)
        XCTAssertTrue(rig.dependencies.isRecording)
    }

    /// A drive already under way, started by hand, must not be ended by a car radio being
    /// switched off at a petrol station.
    func testUnpluggingDoesNotStopATripTheDriverStartedThemselves() throws {
        let rig = try makeRig(autoStart: false)
        rig.dependencies.startTrip()
        XCTAssertEqual(rig.recorder.startCount, 1)

        rig.car.unplug()
        rig.dependencies.confirmCarPlayStop()

        XCTAssertEqual(rig.recorder.stopCount, 0, "automatic stopping belongs to automatic starting")
        XCTAssertTrue(rig.dependencies.isRecording)
    }

    /// Plugging in while a trip is already running must not start a second one.
    func testPluggingInDuringATripStartsNothingNew() throws {
        let rig = try makeRig(autoStart: true)
        rig.dependencies.startTrip()
        rig.car.plugIn()

        XCTAssertEqual(rig.recorder.startCount, 1)
    }

    /// iOS can launch the app *because* the phone was plugged in, so the route is already
    /// established and no change notification ever arrives. Waiting for one would mean the
    /// feature works only when the app happened to be open.
    func testALaunchWithCarPlayAlreadyConnectedStartsATrip() throws {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        let car = FakeCarConnection()
        car.isConnected = true
        let recorder = SpyRecorder()
        let dependencies = AppDependencies(
            container: container, recorderFactory: { _ in recorder }, carConnectionMonitor: car
        )
        // The setting has to exist before bootstrap, the way it does on a real launch.
        dependencies.settingsStore.settings.autoStartOnCarPlay = true
        dependencies.settingsStore.save()

        dependencies.bootstrap()

        XCTAssertTrue(car.started, "the monitor has to be listening whatever the setting says")
        XCTAssertEqual(recorder.startCount, 1)
    }

    // MARK: - What counts as a car

    /// Bluetooth is a car stereo *and* a pair of earbuds. Starting a trip because someone put
    /// their headphones in is worse than not starting one at all.
    func testOnlyACarPlayRouteCountsAsACar() {
        XCTAssertFalse(CarConnectionMonitor.isCarRoute(AVAudioSession.sharedInstance().currentRoute))
    }
}
