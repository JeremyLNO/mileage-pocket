import CoreLocation
import SwiftData
import XCTest
@testable import MileagePocket

@MainActor
final class TripRecorderTests: XCTestCase {

    // MARK: - Doubles

    /// Stands in for `CoreLocationProvider`. The recorder cannot tell the difference, which
    /// is the whole reason the provider is behind a protocol.
    @MainActor
    private final class FakeLocationProvider: LocationProviding {
        var onSample: ((LocationSample) -> Void)?
        var authorization: CLAuthorizationStatus = .authorizedAlways
        private(set) var startCount = 0
        private(set) var stopCount = 0

        func startUpdates() { startCount += 1 }
        func stopUpdates() { stopCount += 1 }
        func requestAlways() {}
        func emit(_ sample: LocationSample) { onSample?(sample) }
    }

    @MainActor
    private final class CountingGeocoder: Geocoding {
        private(set) var calls: [(latitude: Double, longitude: Double)] = []
        func address(latitude: Double, longitude: Double) async -> String? {
            calls.append((latitude, longitude))
            return "Address \(calls.count)"
        }
    }

    /// Injected time. Nothing here ever waits for a real second to pass.
    @MainActor
    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    // MARK: - Harness

    private func makeContext() throws -> ModelContext {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        return ModelContext(container)
    }

    private struct Rig {
        let context: ModelContext
        let provider: FakeLocationProvider
        let geocoder: CountingGeocoder
        let clock: Clock
        let recorder: TripRecorder
    }

    private func makeRig(startingAt start: Date = RouteFixtures.epoch) throws -> Rig {
        let context = try makeContext()
        let provider = FakeLocationProvider()
        let geocoder = CountingGeocoder()
        let clock = Clock(start)
        let recorder = TripRecorder(
            context: context, provider: provider, geocoder: geocoder,
            now: { [clock] in clock.now }
        )
        return Rig(context: context, provider: provider, geocoder: geocoder, clock: clock, recorder: recorder)
    }

    /// Delivers each fix at the moment it was taken, which is what a receiver does — and
    /// what the filter's staleness rule expects.
    private func emit(_ samples: [LocationSample], into rig: Rig) {
        for sample in samples {
            rig.clock.now = sample.timestamp
            rig.provider.emit(sample)
        }
    }

    // MARK: - 1. Recording

    func testRecordingAThousandMetreTripTracksItsDistance() throws {
        let rig = try makeRig()
        try rig.recorder.start(vehicleID: nil)
        XCTAssertEqual(rig.provider.startCount, 1, "starting a trip has to switch the GPS on")

        emit(RouteFixtures.straightLine(), into: rig)

        XCTAssertEqual(
            rig.recorder.state.distanceMeters, 1_000, accuracy: 20,
            "the live readout is what the driver watches; it has to be the real distance"
        )
    }

    // MARK: - 2. Stopping

    func testStoppingPersistsTheTripAndClearsTheFixBuffer() async throws {
        let rig = try makeRig()
        try rig.recorder.start(vehicleID: nil)
        emit(RouteFixtures.straightLine(), into: rig)

        let trip = try await rig.recorder.stop()

        XCTAssertEqual(trip.rawDistanceMeters, 1_000, accuracy: 20)
        XCTAssertFalse(trip.encodedRoute?.isEmpty ?? true, "the trip keeps its route as a blob")
        XCTAssertEqual(rig.provider.stopCount, 1, "stopping a trip has to switch the GPS off")

        let storedTrips = try rig.context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(storedTrips.count, 1)
        XCTAssertEqual(storedTrips.first?.id, trip.id)

        XCTAssertEqual(
            try rig.context.fetch(FetchDescriptor<LocationPoint>()).count, 0,
            "the fixes were a recovery buffer; once folded into the route they must be gone"
        )
        XCTAssertEqual(
            try rig.context.fetch(FetchDescriptor<ActiveTripState>()).count, 0,
            "an active-trip row left behind would offer to resume a finished trip"
        )
        XCTAssertEqual(rig.recorder.state, .idle)
    }

    func testStoppingReverseGeocodesExactlyTwice() async throws {
        let rig = try makeRig()
        try rig.recorder.start(vehicleID: nil)
        let line = RouteFixtures.straightLine()
        emit(line, into: rig)

        let trip = try await rig.recorder.stop()

        XCTAssertEqual(
            rig.geocoder.calls.count, 2,
            "one lookup for the start and one for the end — never one per fix"
        )
        XCTAssertEqual(rig.geocoder.calls.first?.latitude ?? 0, line[0].latitude, accuracy: 1e-6)
        XCTAssertEqual(rig.geocoder.calls.last?.latitude ?? 0, line[line.count - 1].latitude, accuracy: 1e-4)
        XCTAssertEqual(trip.startAddress, "Address 1")
        XCTAssertEqual(trip.endAddress, "Address 2")
    }

    // MARK: - 3. Crash recovery

    func testResumeIfNeededPicksUpAnInterruptedTrip() throws {
        let context = try makeContext()
        let interruptedAt = RouteFixtures.epoch
        let tripID = UUID()
        let vehicleID = UUID()

        // What the store looks like after the app was killed mid-drive.
        let active = ActiveTripState(tripID: tripID, startedAt: interruptedAt, vehicleID: vehicleID)
        active.distanceMeters = 4_321
        active.lastUpdatedAt = interruptedAt.addingTimeInterval(600)
        active.startLatitude = RouteFixtures.originLatitude
        active.startLongitude = RouteFixtures.originLongitude
        context.insert(active)
        try context.save()

        let provider = FakeLocationProvider()
        let clock = Clock(interruptedAt.addingTimeInterval(700))
        let recorder = TripRecorder(
            context: context, provider: provider, geocoder: CountingGeocoder(),
            now: { [clock] in clock.now }
        )
        XCTAssertEqual(recorder.state, .idle, "nothing is resumed until it is asked for")

        try recorder.resumeIfNeeded()

        guard case .recording(let startedAt, let distance, let duration) = recorder.state else {
            return XCTFail("an interrupted trip must come back as recording, got \(recorder.state)")
        }
        XCTAssertEqual(startedAt, interruptedAt)
        XCTAssertEqual(distance, 4_321, "the distance driven before the crash is not lost")
        XCTAssertEqual(duration, 700, accuracy: 0.001)
        XCTAssertEqual(provider.startCount, 1, "resuming has to switch the GPS back on")

        // And it keeps counting from there rather than starting over.
        let continuation = RouteFixtures.straightLine(
            pointCount: 5, stepMeters: 25, speedMetersPerSecond: 25,
            startingAt: interruptedAt.addingTimeInterval(700)
        )
        for sample in continuation {
            clock.now = sample.timestamp
            provider.emit(sample)
        }
        XCTAssertEqual(recorder.state.distanceMeters, 4_321 + 100, accuracy: 5)
    }

    func testResumeIfNeededDoesNothingWhenThereIsNoInterruptedTrip() throws {
        let rig = try makeRig()
        try rig.recorder.resumeIfNeeded()
        XCTAssertEqual(rig.recorder.state, .idle)
        XCTAssertEqual(rig.provider.startCount, 0)
    }

    // MARK: - 4. The recovery row is rewritten on every accepted fix

    func testActiveTripStateIsRewrittenForEveryAcceptedFix() throws {
        let rig = try makeRig()
        try rig.recorder.start(vehicleID: nil)

        // 25 m apart, so every fix clears the noise floor and is accepted.
        let samples = RouteFixtures.straightLine(
            pointCount: 5, stepMeters: 25, speedMetersPerSecond: 25
        )

        var writes = 0
        for sample in samples {
            rig.clock.now = sample.timestamp
            rig.provider.emit(sample)

            let stored = try XCTUnwrap(rig.context.fetch(FetchDescriptor<ActiveTripState>()).first)
            if stored.lastUpdatedAt == sample.timestamp,
               abs(stored.distanceMeters - rig.recorder.distanceMeters) < 1e-9 {
                writes += 1
            }
        }

        XCTAssertEqual(
            writes, samples.count,
            "every accepted fix must land in the store — a crash costs one fix, not the drive"
        )
        XCTAssertGreaterThan(writes, 0)

        let stored = try XCTUnwrap(rig.context.fetch(FetchDescriptor<ActiveTripState>()).first)
        XCTAssertEqual(stored.distanceMeters, 100, accuracy: 5)
        XCTAssertEqual(
            try rig.context.fetch(FetchDescriptor<LocationPoint>()).count, 5,
            "the fixes themselves are buffered too, or a resumed trip has no route"
        )
    }

    // MARK: - 5. Across midnight

    func testTripCrossingMidnightKeepsBothEnds() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let startTime = try XCTUnwrap(calendar.date(
            from: DateComponents(year: 2026, month: 3, day: 14, hour: 23, minute: 58)
        ))
        let endTime = startTime.addingTimeInterval(5 * 60)  // 00:03 the next day

        let rig = try makeRig(startingAt: startTime)
        try rig.recorder.start(vehicleID: nil)
        emit(RouteFixtures.straightLine(startingAt: startTime), into: rig)

        rig.clock.now = endTime
        let trip = try await rig.recorder.stop()

        XCTAssertEqual(trip.startedAt, startTime, "the trip started the day before it ended")
        XCTAssertEqual(trip.endedAt, endTime)
        XCTAssertFalse(
            calendar.isDate(trip.startedAt, inSameDayAs: try XCTUnwrap(trip.endedAt)),
            "the fixture has to actually straddle midnight or this test proves nothing"
        )
        XCTAssertEqual(trip.duration, 300, accuracy: 0.001, "duration is wall time, not a day offset")
    }

    // MARK: - Guards

    func testStartingTwiceIsRefused() throws {
        let rig = try makeRig()
        try rig.recorder.start(vehicleID: nil)
        XCTAssertThrowsError(try rig.recorder.start(vehicleID: nil)) { error in
            XCTAssertEqual(error as? RecorderError, .alreadyRecording)
        }
    }

    func testStoppingWhenIdleIsRefused() async throws {
        let rig = try makeRig()
        do {
            _ = try await rig.recorder.stop()
            XCTFail("stopping a trip that was never started must not invent one")
        } catch {
            XCTAssertEqual(error as? RecorderError, .notRecording)
        }
    }
}
