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

/// Everything the home screen shows that is not a question or a control.
///
/// One optional field on the snapshot rather than a dozen: a snapshot written by an earlier
/// build has no such key, and a missing key is a decode failure unless the property is
/// optional — a default value does not rescue it (Swift's synthesised decoder asks for every
/// non-optional key, and the test that removes this one proves it).
///
/// Amounts and distances arrive already formatted. The app owns the locale, the currency and
/// the country's mileage rule; the widget draws a string it was handed. The two processes
/// spelling one figure differently is a defect this project has already paid for once.
struct WidgetFigures: Codable, Sendable, Equatable {
    /// Every trip today, business and personal alike — what was driven, not what is claimable.
    var todayDistanceMeters: Double
    /// The same figure for yesterday, for the one comparison a driver actually makes.
    var yesterdayDistanceMeters: Double
    /// This month, split. `business + personal` is the month's total; the two are carried
    /// separately because the bar is the point, not the sum.
    var monthBusinessMeters: Double
    var monthPersonalMeters: Double
    var monthTripCount: Int
    /// "€0,529/km" — shown only when a single rate really does apply to the whole month.
    ///
    /// Nil is the common case in France and everywhere else with a tiered scale: there is no
    /// one rate, and printing one under a total would be inventing the arithmetic that
    /// produced it. A figure nobody can reproduce is worse than a figure that is absent.
    var formattedRate: String?
    var lastTrip: LastTrip?

    struct LastTrip: Codable, Sendable, Equatable {
        var start: String
        var end: String
        var distanceText: String
        var durationText: String
        var isBusiness: Bool
    }

    var monthTotalMeters: Double { monthBusinessMeters + monthPersonalMeters }

    /// The share of the month driven for work, 0...1 — nil when nothing has been driven,
    /// because a bar drawn from no data is a bar that says something.
    var businessShare: Double? {
        let total = monthTotalMeters
        guard total > 0 else { return nil }
        return monthBusinessMeters / total
    }

    /// Today against yesterday, as a signed fraction — nil when yesterday was zero.
    ///
    /// Not "+100%", and certainly not "+∞": a first drive after a day off is not a hundred
    /// per cent of anything, and the honest thing to draw is nothing at all.
    var dayChange: Double? {
        guard yesterdayDistanceMeters > 0 else { return nil }
        return (todayDistanceMeters - yesterdayDistanceMeters) / yesterdayDistanceMeters
    }

    static let placeholder = WidgetFigures(
        todayDistanceMeters: 67_600,
        yesterdayDistanceMeters: 60_400,
        monthBusinessMeters: 792_000,
        monthPersonalMeters: 308_000,
        monthTripCount: 24,
        formattedRate: "€0.529/km",
        lastTrip: LastTrip(
            start: "Downtown Office",
            end: "Client Site",
            distanceText: "58 km",
            durationText: "48 min",
            isBusiness: true
        )
    )
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
    /// And the locale its numbers are set in.
    ///
    /// Words were carried from the start; numbers were not, and `.formatted()` in the
    /// extension quietly fell back to the *system* locale. An English widget on a French
    /// phone wrote "1 100 km" and "+12 %" while the app beside it wrote "1,100 km" and
    /// "+12%" — the same two figures, spelled two ways, which is how a reader concludes one
    /// of the two screens is wrong.
    var localeIdentifier: String? = nil
    /// The head of that queue, in the app's own order, carried so the widget can ask about
    /// a named trip rather than about a number — and can move to the next one on its own
    /// after a tap, without waiting for the app to run.
    ///
    /// Optional, and deliberately so: a snapshot written by an earlier build has no such key,
    /// and a non-optional property would fail to decode and leave the widget blank until the
    /// next launch rewrote it.
    var pendingTrips: [PendingTrip]? = nil
    /// The month, the day, and the last drive — see `WidgetFigures`. Optional for the same
    /// reason as `pendingTrips`, and the widget falls back to what it can still say without
    /// them rather than to an empty card.
    var figures: WidgetFigures? = nil

    /// How many are carried. Fewer than `tripsAwaitingReview` when the queue is long — the
    /// widget asks about the ones it knows and stops asking when it runs out, rather than
    /// inventing a trip.
    static let carriedPendingTrips = 4

    var pending: [PendingTrip] { pendingTrips ?? [] }

    /// The app's locale, or the system's when a snapshot predates the field.
    var locale: Locale { localeIdentifier.map(Locale.init(identifier:)) ?? .current }

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
        localeIdentifier: "en_US",
        pendingTrips: nil,
        figures: .placeholder
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
