import Foundation

/// A finished trip the app has never been told the nature of, named well enough for the
/// home screen to ask about it.
struct PendingTrip: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    /// "Paris → Orly", already resolved in the app's language.
    let label: String
    /// "24.3 km", in the unit the user chose.
    let distanceText: String
}

/// The little the home screen widget needs: this month's figures and whether a trip is
/// running. Written by the app into the shared App Group container whenever a trip ends,
/// read by the widget — which has no access to the app's SwiftData store.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    var monthLabel: String
    var distanceMeters: Double
    var unitRaw: String
    var formattedAmount: String?
    var isTripInProgress: Bool
    var updatedAt: Date
    /// When the trip in progress began, so the widget can run its own clock instead of
    /// showing a duration frozen at whatever the last write happened to be.
    var tripStartedAt: Date?
    /// Distance of the trip in progress, as of the last write.
    var tripDistanceMeters: Double?
    /// How many finished trips are still waiting to be called business or personal. This is
    /// the one thing the app asks of its user, and the only number here worth acting on.
    var tripsAwaitingReview: Int
    /// The language chosen *in the app*, so the widget speaks it too. A widget resolves
    /// strings against the system language by default, which would have put the home screen
    /// in one language and the app in another.
    var languageCode: String
    /// The head of that queue, in the app's own order, carried so the widget can ask about
    /// a named trip rather than about a number — and can move to the next one on its own
    /// after a tap, without waiting for the app to run.
    ///
    /// Optional, and deliberately so: a snapshot written by an earlier build has no such key,
    /// and a non-optional property would fail to decode and leave the widget blank until the
    /// next launch rewrote it.
    var pendingTrips: [PendingTrip]? = nil

    /// How many are carried. Fewer than `tripsAwaitingReview` when the queue is long — the
    /// widget asks about the ones it knows and stops asking when it runs out, rather than
    /// inventing a trip.
    static let carriedPendingTrips = 4

    var pending: [PendingTrip] { pendingTrips ?? [] }

    var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .kilometers }

    /// What the widget should put in front of the reader, in priority order: a drive under
    /// way beats a queue, and a queue beats a monthly total nobody taps.
    enum Focus: Equatable {
        case recording
        case awaitingReview(Int)
        case month
    }

    var focus: Focus {
        if isTripInProgress { return .recording }
        if tripsAwaitingReview > 0 { return .awaitingReview(tripsAwaitingReview) }
        return .month
    }

    /// Where a tap should land, given that focus.
    var destination: URL? {
        switch focus {
        case .recording: return URL(string: "mileagepocket://trip")
        case .awaitingReview: return URL(string: "mileagepocket://review")
        case .month: return URL(string: "mileagepocket://start")
        }
    }

    /// The snapshot as it reads once a trip has been answered for on the home screen.
    ///
    /// Applied by the widget extension the moment the button is tapped, so the face changes
    /// under the finger instead of waiting for the app to be opened. The count falls by one
    /// whether or not that trip was among the carried few, and never below zero — the
    /// authoritative figure is rewritten by the app the next time it runs.
    func answering(_ tripID: UUID) -> WidgetSnapshot {
        var copy = self
        copy.pendingTrips = pending.filter { $0.id != tripID }
        copy.tripsAwaitingReview = max(0, tripsAwaitingReview - 1)
        return copy
    }

    static let placeholder = WidgetSnapshot(
        monthLabel: "September",
        distanceMeters: 486_000,
        unitRaw: DistanceUnit.kilometers.rawValue,
        formattedAmount: nil,
        isTripInProgress: false,
        updatedAt: .now,
        tripStartedAt: nil,
        tripDistanceMeters: nil,
        tripsAwaitingReview: 0,
        languageCode: "en",
        pendingTrips: nil
    )
}

enum WidgetSnapshotStore {
    static let appGroupIdentifier = "group.company.lno.mileage"
    private static let fileName = "widget-snapshot.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent(fileName)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let fileURL else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        // A failed write leaves the previous snapshot in place, which is a stale widget —
        // strictly better than an empty one.
        try? data.write(to: fileURL, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
