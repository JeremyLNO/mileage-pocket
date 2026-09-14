import Foundation
import SwiftData
import XCTest
@testable import MileagePocket

/// Saying what a drive was for — the half of a mileage log that no GPS can produce.
///
/// A trip carries a type whether or not anyone chose one, so an unqualified trip is
/// indistinguishable on a claim from a business one: it arrives as whatever the default
/// was. These are the two rules that keep that from happening quietly.
@MainActor
final class QualificationTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_700_000_000)
    private let paris = (latitude: 48.8566, longitude: 2.3522)

    private func trip(
        from start: (latitude: Double, longitude: Double),
        to end: (latitude: Double, longitude: Double),
        type: TripType = .business,
        reviewed: Bool = true,
        purpose: String? = nil,
        clientID: UUID? = nil,
        startedAt: Date? = nil
    ) -> Trip {
        let trip = Trip(startedAt: startedAt ?? epoch)
        trip.endedAt = (startedAt ?? epoch).addingTimeInterval(900)
        trip.startLatitude = start.latitude
        trip.startLongitude = start.longitude
        trip.endLatitude = end.latitude
        trip.endLongitude = end.longitude
        trip.tripType = type
        trip.isReviewed = reviewed
        trip.purpose = purpose
        trip.clientID = clientID
        return trip
    }

    private func offset(_ point: (latitude: Double, longitude: Double), metres: Double)
        -> (latitude: Double, longitude: Double) {
        RouteFixtures.offset(
            latitude: point.latitude, longitude: point.longitude,
            eastMeters: metres, northMeters: 0
        )
    }

    // MARK: - A journey remembers what it was

    func testTheLastIdenticalJourneyDecides() {
        let office = offset(paris, metres: 8_000)
        let client = UUID()
        let history = [
            trip(from: paris, to: office, type: .business, purpose: "Weekly review", clientID: client)
        ]

        let pattern = TripPatternMatcher.match(start: paris, end: office, in: history)

        XCTAssertEqual(pattern?.tripType, .business)
        XCTAssertEqual(pattern?.purpose, "Weekly review")
        XCTAssertEqual(pattern?.clientID, client)
        XCTAssertEqual(pattern?.occurrences, 1)
    }

    /// The correction has to win. When a route changes hands, the driver fixes one trip and
    /// expects the next to follow — waiting for a majority would make the app argue with the
    /// person filling it in.
    func testTheMostRecentAnswerWinsOverTheMoreFrequentOne() {
        let office = offset(paris, metres: 8_000)
        let history = [
            trip(from: paris, to: office, type: .business, startedAt: epoch),
            trip(from: paris, to: office, type: .business, startedAt: epoch.addingTimeInterval(86_400)),
            trip(from: paris, to: office, type: .personal, startedAt: epoch.addingTimeInterval(172_800)),
        ]

        let pattern = TripPatternMatcher.match(start: paris, end: office, in: history)

        XCTAssertEqual(pattern?.tripType, .personal)
        XCTAssertEqual(pattern?.occurrences, 3)
    }

    /// Learning from an unqualified trip would propagate a default into every trip that
    /// follows it — the app agreeing with itself about something nobody ever said.
    func testAnUnqualifiedTripTeachesNothing() {
        let office = offset(paris, metres: 8_000)
        let history = [trip(from: paris, to: office, type: .business, reviewed: false)]

        XCTAssertNil(TripPatternMatcher.match(start: paris, end: office, in: history))
    }

    /// Two endpoints, both of which must match. One in common is a coincidence: every drive
    /// of the day starts at home.
    func testTheSameStartWithADifferentEndIsADifferentJourney() {
        let office = offset(paris, metres: 8_000)
        let elsewhere = offset(paris, metres: 40_000)
        let history = [trip(from: paris, to: office)]

        XCTAssertNil(TripPatternMatcher.match(start: paris, end: elsewhere, in: history))
    }

    /// Direction matters: home → office and office → home are two journeys, and for someone
    /// billing a client they are not always worth the same.
    func testTheReverseJourneyDoesNotMatch() {
        let office = offset(paris, metres: 8_000)
        let history = [trip(from: paris, to: office)]

        XCTAssertNil(TripPatternMatcher.match(start: office, end: paris, in: history))
    }

    /// A different parking space at either end is the same journey; the next street is not.
    func testTheRadiusHoldsAtItsBoundary() {
        let office = offset(paris, metres: 8_000)
        let history = [trip(from: paris, to: office)]
        let radius = TripPatternMatcher.radiusMeters

        XCTAssertNotNil(
            TripPatternMatcher.match(start: offset(paris, metres: radius - 1), end: office, in: history),
            "just inside has to match"
        )
        XCTAssertNil(
            TripPatternMatcher.match(start: offset(paris, metres: radius + 20), end: office, in: history),
            "just outside must not"
        )
    }

    /// The trip being qualified is in the store by the time the sheet asks. Matching itself
    /// would make every trip its own precedent — and confirm whatever default it carries.
    func testATripIsNeverItsOwnPrecedent() {
        let office = offset(paris, metres: 8_000)
        let current = trip(from: paris, to: office)

        XCTAssertNil(
            TripPatternMatcher.match(start: paris, end: office, excluding: current.id, in: [current])
        )
    }

    // MARK: - The queue

    func testARecordedTripArrivesUnqualifiedAndLeavesTheQueueWhenAnswered() throws {
        let container = try PersistenceController.makeContainer(cloudKitEnabled: false, inMemory: true)
        let dependencies = AppDependencies(container: container, recorderFactory: { _ in InertRecorder() })
        dependencies.bootstrap()

        let recorded = trip(from: paris, to: offset(paris, metres: 5_000), reviewed: false)
        dependencies.context.insert(recorded)
        try dependencies.context.save()

        XCTAssertEqual(dependencies.tripsAwaitingReview.count, 1)

        dependencies.reviewTrip(recorded, as: .personal)

        XCTAssertTrue(dependencies.tripsAwaitingReview.isEmpty)
        XCTAssertEqual(recorded.tripType, .personal)
        XCTAssertTrue(recorded.isReviewed)
    }

    /// The default is `true`, and that is the whole point: a queue that opened on day one
    /// with years of history in it would be closed and never opened again.
    func testTripsWrittenBeforeThisExistedStayOutOfTheQueue() {
        let legacy = Trip(startedAt: epoch)
        legacy.endedAt = epoch.addingTimeInterval(600)

        XCTAssertTrue(legacy.isReviewed, "an old row decodes with the default and must not resurface")
    }
}
