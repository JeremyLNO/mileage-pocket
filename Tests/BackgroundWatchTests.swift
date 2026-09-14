import CoreLocation
import SwiftData
import XCTest
@testable import MileagePocket

/// The watch that lets iOS relaunch a closed app at the start of a drive.
///
/// It is the only mechanism an app without a CarPlay entitlement has for noticing a drive
/// it was not present for. It is also a standing cost in the battery report, which is why it
/// answers to one switch and to one authorisation, and to nothing else.
@MainActor
final class BackgroundWatchTests: XCTestCase {

    // MARK: - The rule

    func testTheWatchNeedsBothTheSwitchAndAlways() {
        XCTAssertTrue(BackgroundWatch.shouldWatch(autoStartEnabled: true, authorization: .authorizedAlways))
        XCTAssertFalse(BackgroundWatch.shouldWatch(autoStartEnabled: false, authorization: .authorizedAlways),
                       "nobody asked for automatic trips; nobody pays for the wake-ups")
    }

    /// Not a preference — a fact about iOS. Significant-change monitoring is not delivered
    /// under When In Use, so arming it there costs the same and buys nothing, while letting
    /// the settings screen promise something that never happens.
    func testWhenInUseIsNotEnough() {
        XCTAssertFalse(BackgroundWatch.shouldWatch(autoStartEnabled: true, authorization: .authorizedWhenInUse))
        XCTAssertFalse(BackgroundWatch.shouldWatch(autoStartEnabled: true, authorization: .notDetermined))
        XCTAssertFalse(BackgroundWatch.shouldWatch(autoStartEnabled: true, authorization: .denied))
        XCTAssertFalse(BackgroundWatch.shouldWatch(autoStartEnabled: true, authorization: .restricted))
    }

    // MARK: - The wiring

    /// Records what it was asked to watch, and nothing else.
    private final class WatchSpy: TripRecording {
        var state: RecorderState = .idle
        var onUpdate: (() -> Void)?
        var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
        var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
        var currentDistanceMeters: Double = 0
        var startedAt: Date?
        var routeSamples: [LocationSample] = []
        private(set) var watchStates: [Bool] = []
        private(set) var permissionRequests = 0

        func start(vehicleID: UUID?) throws {
            startedAt = Date(timeIntervalSince1970: 1_700_000_000)
            state = .recording(startedAt: startedAt!, distanceMeters: 0, duration: 0)
        }

        func resume(_ trip: Trip) throws {}

        func stop() throws -> Trip {
            state = .idle
            let trip = Trip(startedAt: startedAt ?? .now)
            trip.endedAt = trip.startedAt.addingTimeInterval(600)
            return trip
        }

        func resumeIfNeeded() throws -> ResumeOutcome { .none }
        func attachPlaces(to trip: Trip) async {}
        func requestPermission() { permissionRequests += 1 }
        func setBackgroundWatch(_ enabled: Bool) { watchStates.append(enabled) }
    }

    private func makeDependencies(_ recorder: WatchSpy) throws -> AppDependencies {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        return AppDependencies(container: container, recorderFactory: { _ in recorder })
    }

    func testTurningTheSwitchOnArmsTheWatch() throws {
        let recorder = WatchSpy()
        let dependencies = try makeDependencies(recorder)
        dependencies.bootstrap()

        dependencies.setAutoStartOnCarPlay(true)

        XCTAssertEqual(recorder.watchStates.last, true)
        XCTAssertTrue(dependencies.settingsStore.settings.autoStartOnCarPlay)
    }

    func testTurningItOffDisarmsTheWatch() throws {
        let recorder = WatchSpy()
        let dependencies = try makeDependencies(recorder)
        dependencies.bootstrap()
        dependencies.setAutoStartOnCarPlay(true)

        dependencies.setAutoStartOnCarPlay(false)

        XCTAssertEqual(recorder.watchStates.last, false, "off has to cost nothing")
    }

    /// Without Always the switch keeps a promise it cannot keep, so turning it on is the one
    /// moment worth raising the prompt — on an explicit gesture, never at launch.
    func testTurningItOnWithoutAlwaysAsksForIt() throws {
        let recorder = WatchSpy()
        recorder.authorizationStatus = .authorizedWhenInUse
        let dependencies = try makeDependencies(recorder)
        dependencies.bootstrap()

        dependencies.setAutoStartOnCarPlay(true)

        XCTAssertEqual(recorder.permissionRequests, 1)
        XCTAssertEqual(recorder.watchStates.last, false, "and nothing is armed until it is granted")
    }

    /// Granted later, from the system prompt or from Settings: the watch has to notice, or
    /// the switch stays inert until the next launch.
    func testAlwaysGrantedLaterArmsTheWatch() throws {
        let recorder = WatchSpy()
        recorder.authorizationStatus = .authorizedWhenInUse
        let dependencies = try makeDependencies(recorder)
        dependencies.bootstrap()
        dependencies.setAutoStartOnCarPlay(true)

        recorder.authorizationStatus = .authorizedAlways
        recorder.onAuthorizationChange?(.authorizedAlways)

        XCTAssertEqual(recorder.watchStates.last, true)
    }

    // MARK: - The receiver itself

    /// A `CLLocationManager` that records what it was told, so the one rule that cannot be
    /// checked from above — the end of a trip taking the standing watch down with it — is
    /// checked where it actually lives.
    private final class RecordingManager: CLLocationManager {
        var status: CLAuthorizationStatus = .authorizedAlways
        private(set) var significantChangeCalls: [Bool] = []

        override var authorizationStatus: CLAuthorizationStatus { status }
        override func startMonitoringSignificantLocationChanges() { significantChangeCalls.append(true) }
        override func stopMonitoringSignificantLocationChanges() { significantChangeCalls.append(false) }
        override func startUpdatingLocation() {}
        override func stopUpdatingLocation() {}
    }

    func testStoppingATripLeavesAWantedWatchStanding() throws {
        try XCTSkipUnless(CLLocationManager.significantLocationChangeMonitoringAvailable())
        let manager = RecordingManager()
        let provider = CoreLocationProvider(manager: manager)

        provider.setSignificantChangeWatch(true)
        provider.startUpdates()
        provider.stopUpdates()

        XCTAssertEqual(manager.significantChangeCalls.last, true,
                       "the trip's teardown must not cancel a watch nobody asked it to cancel")
    }

    func testStoppingATripTakesDownAnUnwantedWatch() throws {
        try XCTSkipUnless(CLLocationManager.significantLocationChangeMonitoringAvailable())
        let manager = RecordingManager()
        let provider = CoreLocationProvider(manager: manager)

        provider.startUpdates()
        provider.stopUpdates()

        XCTAssertEqual(manager.significantChangeCalls.last, false,
                       "nobody asked to keep it; an app waking for nothing is a battery complaint")
    }

    /// The end of a trip tears down the receiver the trip was using. The standing watch is a
    /// separate promise: if it went down with it, automatic starting would work exactly once
    /// per launch, which is indistinguishable from not working.
    func testTheWatchSurvivesTheEndOfATrip() throws {
        let recorder = WatchSpy()
        let dependencies = try makeDependencies(recorder)
        dependencies.bootstrap()
        dependencies.setAutoStartOnCarPlay(true)

        dependencies.startTrip()
        dependencies.stopTrip()

        XCTAssertEqual(recorder.watchStates.last, true, "the next drive still has to be noticed")
    }
}
