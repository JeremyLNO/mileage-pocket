import XCTest
@testable import MileagePocket

/// What the widget decides to show, and where a tap lands.
///
/// The whole mechanism was inert until 2026-09-16: the App Group did not exist, so
/// `containerURL(forSecurityApplicationGroupIdentifier:)` returned nil, the app never wrote
/// a snapshot and the widget never read one. It rendered its empty state on every device
/// while the code that draws the month's figures was never reached — a widget that could not
/// have been wrong because it was never right.
final class WidgetSnapshotTests: XCTestCase {
    private func snapshot(
        recording: Bool = false,
        awaiting: Int = 0,
        distanceMeters: Double = 154_000
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            monthLabel: "September",
            distanceMeters: distanceMeters,
            unitRaw: DistanceUnit.kilometers.rawValue,
            formattedAmount: "€117.46",
            isTripInProgress: recording,
            updatedAt: .now,
            tripStartedAt: recording ? Date(timeIntervalSince1970: 1_700_000_000) : nil,
            tripDistanceMeters: recording ? 4_800 : nil,
            tripsAwaitingReview: awaiting,
            languageCode: "en"
        )
    }

    /// A drive under way beats everything: it is the only state where something is happening
    /// that the reader might need to end.
    func testADriveUnderWayWinsOverEverythingElse() {
        let live = snapshot(recording: true, awaiting: 3)
        XCTAssertEqual(live.focus, .recording)
        XCTAssertEqual(live.destination?.host, "trip")
    }

    /// The queue is the one thing the app asks of its user, so it outranks the month.
    func testTheQueueOutranksTheMonthlyTotal() {
        let queued = snapshot(awaiting: 2)
        XCTAssertEqual(queued.focus, .awaitingReview(2))
        XCTAssertEqual(queued.destination?.host, "review")
    }

    /// With nothing to do, the month — and a tap that starts the next drive.
    func testWithNothingPendingItShowsTheMonthAndOffersToStart() {
        let idle = snapshot()
        XCTAssertEqual(idle.focus, .month)
        XCTAssertEqual(idle.destination?.host, "start")
    }

    /// An empty queue is not a queue. Off by one here would put "0 trips to qualify" on the
    /// home screen of someone who is completely up to date.
    func testAnEmptyQueueIsNotShown() {
        XCTAssertEqual(snapshot(awaiting: 0).focus, .month)
        XCTAssertEqual(snapshot(awaiting: 1).focus, .awaitingReview(1))
    }

    /// The snapshot crosses a process boundary as JSON, so a field that fails to round-trip
    /// is a field the widget silently loses.
    func testEveryFieldSurvivesTheRoundTripToTheWidget() throws {
        let original = snapshot(recording: true, awaiting: 4)
        let decoded = try JSONDecoder().decode(
            WidgetSnapshot.self, from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.tripsAwaitingReview, 4)
        XCTAssertEqual(decoded.languageCode, "en")
        XCTAssertNotNil(decoded.tripStartedAt)
    }

    /// The container has to actually resolve. If the entitlement ever drifts from this
    /// identifier — or is dropped, as it was for months — `containerURL` returns nil, both
    /// sides no-op, and the widget goes blank without an error anywhere.
    func testTheSharedContainerResolves() throws {
        XCTAssertEqual(WidgetSnapshotStore.appGroupIdentifier, "group.company.lno.mileage")
        XCTAssertNotNil(
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupIdentifier
            ),
            "the App Group is not provisioned — the widget can neither be written to nor read"
        )
    }

    /// And a snapshot written by the app must come back out of that container.
    func testASnapshotWrittenIsASnapshotRead() throws {
        let written = snapshot(awaiting: 5)
        WidgetSnapshotStore.write(written)
        XCTAssertEqual(WidgetSnapshotStore.read(), written)
    }
}
