import Foundation

enum TripSection: Hashable, Sendable, CaseIterable {
    case today
    case yesterday
    case thisWeek
    case earlier

    var titleKey: String {
        switch self {
        case .today: return "trips.section.today"
        case .yesterday: return "trips.section.yesterday"
        case .thisWeek: return "trips.section.thisweek"
        case .earlier: return "trips.section.earlier"
        }
    }
}

/// Buckets trips for the list.
///
/// Everything is decided by the **current** calendar, not by whatever offset was in force
/// when the trip was recorded: a drive taken abroad still reads as "today" to someone
/// looking at their phone today, which is the only reading that makes sense on screen.
enum TripGrouping {
    static func group(_ trips: [Trip], now: Date = .now, calendar: Calendar = .current) -> [(TripSection, [Trip])] {
        let sorted = trips.sorted { $0.startedAt > $1.startedAt }
        var buckets: [TripSection: [Trip]] = [:]

        for trip in sorted {
            buckets[section(for: trip.startedAt, now: now, calendar: calendar), default: []].append(trip)
        }

        // Empty sections are never emitted: a header with nothing under it is noise.
        return TripSection.allCases.compactMap { section in
            guard let trips = buckets[section], !trips.isEmpty else { return nil }
            return (section, trips)
        }
    }

    /// Every boundary is derived from the injected `now`.
    ///
    /// `isDateInToday` and `isDateInYesterday` read the *system* clock and ignore the `now`
    /// passed in, so this function silently disagreed with its own parameter — invisible in
    /// production, where `now` is always the real time, and invisible in the tests too until
    /// midnight passed mid-session and "yesterday" became "this week".
    static func section(for date: Date, now: Date = .now, calendar: Calendar = .current) -> TripSection {
        let startOfToday = calendar.startOfDay(for: now)
        if date >= startOfToday { return .today }

        guard let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) else { return .earlier }
        if date >= startOfYesterday { return .yesterday }

        guard let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: startOfToday) else { return .earlier }
        return date >= sevenDaysAgo ? .thisWeek : .earlier
    }
}
