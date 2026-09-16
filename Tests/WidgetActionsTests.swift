import CoreLocation
import Foundation
import SwiftData
import XCTest
@testable import MileagePocket

/// The home screen buttons.
///
/// They are two controls in a process that owns neither the store nor the location manager,
/// which is the whole difficulty: what the widget can honestly do is *record what was asked
/// for*, and what the app must do is carry it out exactly once. Every test here is about one
/// of those two halves, because a button that records an answer nobody applies is the same
/// defect as a button that does nothing at all — it just takes a day longer to notice.
@MainActor
final class WidgetActionsTests: XCTestCase {
    private var directory: URL!
    private var inbox: SharedInbox!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // A directory of its own rather than the real App Group: these tests must not empty
        // an inbox the device is relying on, and must not depend on one being provisioned.
        directory = URL.temporaryDirectory.appending(path: "widget-actions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        inbox = SharedInbox(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    // MARK: - The inbox

    func testADecisionSurvivesTheCrossingFromTheWidgetToTheApp() {
        let id = UUID()
        inbox.record(PendingQualification(tripID: id, isBusiness: true, decidedAt: .now))

        let read = inbox.qualifications()
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read.first?.tripID, id)
        XCTAssertEqual(read.first?.tripType, .business, "which button was pressed is the whole payload")
    }

    /// Changing one's mind on the same trip leaves one answer, not two. Both applied in order
    /// would be harmless; both applied in *arbitrary* order would make the last tap lose.
    func testTheLastAnswerOnATripReplacesTheEarlierOne() {
        let id = UUID()
        inbox.record(PendingQualification(tripID: id, isBusiness: true, decidedAt: .now))
        inbox.record(PendingQualification(tripID: id, isBusiness: false, decidedAt: .now))

        XCTAssertEqual(inbox.qualifications().count, 1)
        XCTAssertEqual(inbox.qualifications().first?.tripType, .personal)
    }

    /// Draining is what makes applying idempotent. If the file survived the read, every
    /// launch would re-apply the same decision over an answer the user may since have
    /// changed inside the app.
    func testDrainingEmptiesTheInbox() {
        inbox.record(PendingQualification(tripID: UUID(), isBusiness: true, decidedAt: .now))

        XCTAssertEqual(inbox.drainQualifications().count, 1)
        XCTAssertTrue(inbox.qualifications().isEmpty)
        XCTAssertTrue(inbox.drainQualifications().isEmpty)
    }

    func testAStopRequestIsTakenOnce() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        inbox.requestStop(tripStartedAt: startedAt)

        XCTAssertEqual(inbox.takeStopRequest()?.tripStartedAt, startedAt)
        XCTAssertNil(inbox.takeStopRequest(), "a stop asked for once must not be asked for twice")
    }

    /// Without a reachable App Group every operation has to be a silent no-op rather than a
    /// crash — which is exactly the state the whole widget mechanism was in until the group
    /// was created.
    func testAnUnreachableContainerIsHarmless() {
        let none = SharedInbox(directory: nil)
        none.record(PendingQualification(tripID: UUID(), isBusiness: true, decidedAt: .now))
        none.requestStop(tripStartedAt: .now)

        XCTAssertTrue(none.qualifications().isEmpty)
        XCTAssertNil(none.takeStopRequest())
    }

    // MARK: - The widget's own face

    /// The tap has to land visibly. The extension cannot recompute the queue, so it removes
    /// the trip it just answered for and lowers the count by one; the app rewrites the real
    /// figures the next time it runs.
    func testAnsweringRemovesThatTripAndLowersTheCount() {
        let first = PendingTrip(id: UUID(), label: "Paris → Orly", distanceText: "24.3 km")
        let second = PendingTrip(id: UUID(), label: "Orly → Paris", distanceText: "24.1 km")
        let snapshot = Self.snapshot(awaiting: 5, pending: [first, second])

        let after = snapshot.answering(first.id)

        XCTAssertEqual(after.pending.map(\.id), [second.id])
        XCTAssertEqual(after.tripsAwaitingReview, 4)
    }

    /// A count that went negative would put "-1 trips to qualify" on a home screen. The
    /// authoritative figure comes from the app; this only has to stay sane until it does.
    func testTheCountNeverGoesBelowZero() {
        let trip = PendingTrip(id: UUID(), label: "Paris → Orly", distanceText: "24.3 km")
        let snapshot = Self.snapshot(awaiting: 0, pending: [trip])

        XCTAssertEqual(snapshot.answering(trip.id).tripsAwaitingReview, 0)
    }

    /// The carried list crosses as JSON like everything else here.
    func testTheCarriedQueueSurvivesTheRoundTrip() throws {
        let original = Self.snapshot(
            awaiting: 2,
            pending: [PendingTrip(id: UUID(), label: "Paris → Orly", distanceText: "24.3 km")]
        )
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.pending.first?.label, "Paris → Orly")
    }

    /// A snapshot written by the build that shipped before this one has no such key. Decoding
    /// must not fail over it: a throw here leaves the widget blank until the app is next
    /// launched, which is the one moment an update is most visible.
    func testASnapshotFromTheBuildBeforeThisOneStillDecodes() throws {
        var fields = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.snapshot(awaiting: 2, pending: [])))
                as? [String: Any]
        )
        fields.removeValue(forKey: "pendingTrips")
        let data = try JSONSerialization.data(withJSONObject: fields)

        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded.tripsAwaitingReview, 2)
        XCTAssertTrue(decoded.pending.isEmpty)
    }

    // MARK: - The app carrying it out

    func testATripAnsweredOnTheHomeScreenIsQualifiedByTheApp() throws {
        let rig = try makeRig()
        let trip = Self.unreviewedTrip()
        rig.dependencies.context.insert(trip)
        try rig.dependencies.context.save()

        inbox.record(PendingQualification(tripID: trip.id, isBusiness: false, decidedAt: .now))
        rig.dependencies.applyPendingWidgetActions(inbox: inbox)

        XCTAssertTrue(trip.isReviewed, "the queue must let go of a trip that has been answered for")
        XCTAssertEqual(trip.tripType, .personal, "the answer given is the answer applied")
        XCTAssertTrue(inbox.qualifications().isEmpty)
    }

    /// The same path the review queue inside the app uses, which is what makes the figure
    /// right: a business trip is priced, a personal one is not.
    func testQualifyingFromTheHomeScreenPricesTheTripLikeTheAppDoes() throws {
        let rig = try makeRig()
        // A scale needs a vehicle to price against — without one the amount is deliberately
        // *unknown* rather than zero, which is a different rule and not the one under test.
        let car = Vehicle(name: "Clio", isDefault: true)
        car.fiscalHorsepower = 5
        rig.dependencies.context.insert(car)
        let business = Self.unreviewedTrip()
        let personal = Self.unreviewedTrip(startedAt: Date(timeIntervalSince1970: 1_780_100_000))
        business.vehicleID = car.id
        personal.vehicleID = car.id
        rig.dependencies.context.insert(business)
        rig.dependencies.context.insert(personal)
        try rig.dependencies.context.save()

        inbox.record(PendingQualification(tripID: business.id, isBusiness: true, decidedAt: .now))
        inbox.record(PendingQualification(tripID: personal.id, isBusiness: false, decidedAt: .now))
        rig.dependencies.applyPendingWidgetActions(inbox: inbox)

        let amount = try XCTUnwrap(
            business.calculatedAmount,
            "a business trip answered from the home screen must come out of it priced"
        )
        XCTAssertGreaterThan(amount, 0)
        XCTAssertEqual(personal.calculatedAmount, 0, "a personal trip is not claimable, whoever said so")
        XCTAssertEqual(personal.mileageRate, 0)
    }

    /// The app's own answer is the later one and wins. Otherwise a tap left in the inbox
    /// would silently overwrite a correction made afterwards on the trip's own screen.
    func testADecisionNeverOverwritesAnAnswerAlreadyGivenInTheApp() throws {
        let rig = try makeRig()
        let trip = Self.unreviewedTrip()
        rig.dependencies.context.insert(trip)
        rig.dependencies.reviewTrip(trip, as: .business)

        inbox.record(PendingQualification(tripID: trip.id, isBusiness: false, decidedAt: .now))
        rig.dependencies.applyPendingWidgetActions(inbox: inbox)

        XCTAssertEqual(trip.tripType, .business)
    }

    func testADecisionAboutADeletedTripIsDiscardedWithoutHarm() throws {
        let rig = try makeRig()
        inbox.record(PendingQualification(tripID: UUID(), isBusiness: true, decidedAt: .now))

        rig.dependencies.applyPendingWidgetActions(inbox: inbox)

        XCTAssertTrue(inbox.qualifications().isEmpty)
    }

    // MARK: - STOP

    func testStopFromTheHomeScreenEndsTheDriveInProgress() throws {
        let rig = try makeRig()
        rig.dependencies.startTrip()
        XCTAssertTrue(rig.dependencies.isRecording)

        inbox.requestStop(tripStartedAt: rig.dependencies.activeStartedAt)
        rig.dependencies.applyPendingWidgetActions(inbox: inbox)

        XCTAssertFalse(rig.dependencies.isRecording, "STOP on the home screen has to actually stop the trip")
        XCTAssertEqual(rig.recorder.stopCount, 1)
    }

    /// The request names the drive it was drawn for. A tap that arrives after that drive has
    /// ended — the app reopened days later — must not end whatever is running then.
    func testAStaleStopDoesNotEndADifferentDrive() throws {
        let rig = try makeRig()
        rig.dependencies.startTrip()

        inbox.requestStop(tripStartedAt: Date(timeIntervalSince1970: 1_600_000_000))
        rig.dependencies.applyPendingWidgetActions(inbox: inbox)

        XCTAssertTrue(rig.dependencies.isRecording, "a stop aimed at another trip must be ignored")
        XCTAssertEqual(rig.recorder.stopCount, 0)
    }

    func testAStopArrivingWhenNothingIsRecordingDoesNothing() throws {
        let rig = try makeRig()
        inbox.requestStop(tripStartedAt: Date(timeIntervalSince1970: 1_700_000_000))

        rig.dependencies.applyPendingWidgetActions(inbox: inbox)

        XCTAssertEqual(rig.recorder.stopCount, 0)
        XCTAssertNil(inbox.takeStopRequest(), "and the request is consumed rather than left to fire later")
    }

    // MARK: - What the home screen is told while a drive runs

    /// The snapshot is built from `isRecording` and `activeStartedAt`, and both are set by
    /// `syncRecorderState`. Written before that call — which is what the shipped build did —
    /// it said "no trip in progress" at the exact moment one began, so the widget showed the
    /// month all through the drive and its STOP button never appeared at all. The buttons
    /// were the reason to look: a control that is never drawn is indistinguishable from one
    /// that does not work.
    func testStartingATripTellsTheHomeScreenImmediately() throws {
        let rig = try makeRig()
        rig.dependencies.startTrip()

        let snapshot = try XCTUnwrap(WidgetSnapshotStore.read())
        XCTAssertTrue(snapshot.isTripInProgress, "the widget must say a drive is under way while it is")
        XCTAssertEqual(snapshot.tripStartedAt, rig.dependencies.activeStartedAt)
        XCTAssertEqual(snapshot.focus, .recording)
    }

    /// And the other half: written before the state was cleared, the snapshot kept
    /// `isRecording` and the old start date, leaving a timer running on the home screen over
    /// a trip that had already been saved.
    func testStoppingATripTellsTheHomeScreenImmediately() throws {
        let rig = try makeRig()
        rig.dependencies.startTrip()
        rig.dependencies.stopTrip()

        let snapshot = try XCTUnwrap(WidgetSnapshotStore.read())
        XCTAssertFalse(snapshot.isTripInProgress, "a finished trip must not still be counting on the home screen")
        XCTAssertNil(snapshot.tripStartedAt)
    }

    // MARK: - What the widget is given to ask about

    /// The widget asks about a trip by name, in the app's own queue order, and carries only
    /// a few — the rest of the count is a number, not a question.
    func testTheAppNamesTheHeadOfTheQueueForTheWidget() throws {
        let rig = try makeRig()
        for index in 0..<(WidgetSnapshot.carriedPendingTrips + 2) {
            let trip = Self.unreviewedTrip(
                startedAt: Date(timeIntervalSince1970: 1_780_000_000 + Double(index) * 3_600)
            )
            trip.startAddress = "Paris"
            trip.endAddress = "Town \(index)"
            rig.dependencies.context.insert(trip)
        }
        try rig.dependencies.context.save()

        let awaiting = rig.dependencies.tripsAwaitingReview
        let carried = rig.dependencies.carriedPendingTrips(from: awaiting)

        XCTAssertEqual(awaiting.count, WidgetSnapshot.carriedPendingTrips + 2)
        XCTAssertEqual(carried.count, WidgetSnapshot.carriedPendingTrips)
        XCTAssertEqual(carried.map(\.id), awaiting.prefix(WidgetSnapshot.carriedPendingTrips).map(\.id),
                       "the widget must ask about the same trip the app's own queue puts first")
        XCTAssertTrue(carried[0].label.contains("→"), "a trip is named by where it went")
        XCTAssertFalse(carried[0].distanceText.isEmpty)
    }

    // MARK: - Rig

    private struct Rig {
        let dependencies: AppDependencies
        let recorder: StopSpyRecorder
    }

    /// Held whole, deliberately. Destructuring this and keeping only the recorder let
    /// `AppDependencies` deallocate mid-test once before, and every `[weak self]` callback
    /// inside it then returned early — a suite that stayed green while testing nothing.
    private func makeRig() throws -> Rig {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        let recorder = StopSpyRecorder()
        let dependencies = AppDependencies(container: container, recorderFactory: { _ in recorder })
        dependencies.bootstrap()
        return Rig(dependencies: dependencies, recorder: recorder)
    }

    private final class StopSpyRecorder: TripRecording {
        var state: RecorderState = .idle
        var onUpdate: (() -> Void)?
        var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
        var authorizationStatus: CLAuthorizationStatus = .authorizedAlways
        var currentDistanceMeters: Double = 0
        var startedAt: Date?
        var routeSamples: [LocationSample] = []
        private(set) var stopCount = 0

        func start(vehicleID: UUID?) throws {
            startedAt = Date(timeIntervalSince1970: 1_700_000_000)
            state = .recording(startedAt: startedAt!, distanceMeters: 0, duration: 0)
        }

        func resume(_ trip: Trip) throws {
            startedAt = trip.startedAt
            state = .recording(startedAt: trip.startedAt, distanceMeters: trip.distanceMeters, duration: 0)
        }

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

    // MARK: - Fixtures

    /// Dated inside the bundled rule pack's validity window. A trip from before it is
    /// deliberately priced as *unknown* rather than zero, which is a different rule and
    /// would quietly make the pricing assertion here about the wrong thing.
    private static func unreviewedTrip(
        startedAt: Date = Date(timeIntervalSince1970: 1_780_000_000)
    ) -> Trip {
        let trip = Trip(startedAt: startedAt)
        trip.endedAt = startedAt.addingTimeInterval(1_200)
        trip.rawDistanceMeters = 24_300
        trip.startAddress = "Paris"
        trip.endAddress = "Orly"
        trip.isReviewed = false
        return trip
    }

    private static func snapshot(awaiting: Int, pending: [PendingTrip]) -> WidgetSnapshot {
        WidgetSnapshot(
            monthLabel: "September",
            distanceMeters: 154_000,
            unitRaw: DistanceUnit.kilometers.rawValue,
            formattedAmount: "€117.46",
            isTripInProgress: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            tripStartedAt: nil,
            tripDistanceMeters: nil,
            tripsAwaitingReview: awaiting,
            languageCode: "en",
            pendingTrips: pending
        )
    }
}
