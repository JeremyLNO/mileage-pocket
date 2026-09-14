import Foundation

/// One distance, published on one schedule, for every screen that shows it.
///
/// The driving screen used to render the recorder's live value on every accepted fix, while
/// the Live Activity — the lock screen, the Dynamic Island and the CarPlay dashboard — was
/// pushed on a throttle of its own. Two clocks, two numbers: at the same instant the phone
/// read 1.6 km and the car read 1.5 km. Neither was wrong, which is precisely what made it
/// impossible to trust either.
///
/// So the schedule moves here, above every surface. The published figure changes when the
/// drive has moved **100 m**, or when **5 s** have passed — whichever comes first — and
/// everything then renders *that* number, not its own reading of the recorder.
///
/// A value type with no clock of its own: the caller passes `now`, which is what makes the
/// rule testable without waiting five seconds for each case.
struct DistanceBroadcast: Equatable {
    /// Never more than five seconds behind the road.
    static let minimumInterval: TimeInterval = 5
    /// …and never more than a hundred metres, which at motorway speed arrives first.
    static let minimumDeltaMeters: Double = 100

    private(set) var publishedMeters: Double = 0
    private(set) var publishedAt: Date = .distantPast

    /// Starts a drive at zero, published immediately: a screen showing nothing at all for
    /// the first five seconds of every trip reads as a tracker that did not start.
    mutating func begin(at now: Date) {
        publishedMeters = 0
        publishedAt = now
    }

    /// Offers the recorder's live distance to the schedule.
    /// - Returns: `true` when the published number changed and the surfaces must be redrawn.
    @discardableResult
    mutating func consider(_ meters: Double, now: Date) -> Bool {
        guard meters != publishedMeters else { return false }
        guard Self.shouldPublish(
            current: meters,
            published: publishedMeters,
            since: now.timeIntervalSince(publishedAt)
        ) else { return false }
        publishedMeters = meters
        publishedAt = now
        return true
    }

    /// Publishes whatever the caller has, schedule or no schedule.
    ///
    /// For the end of a drive: the figure on the summary sheet is the one being written to
    /// the trip, and it must not be up to five seconds short of it.
    mutating func settle(on meters: Double, now: Date) {
        publishedMeters = meters
        publishedAt = now
    }

    /// The rule itself, isolated so it can be tested exactly on its two boundaries.
    ///
    /// A standing car publishes nothing: the distance does not change, so neither does the
    /// display — and the elapsed time keeps growing, which means the first metre after a red
    /// light is published at once rather than five seconds later.
    static func shouldPublish(current: Double, published: Double, since: TimeInterval) -> Bool {
        since >= minimumInterval || abs(current - published) >= minimumDeltaMeters
    }
}
