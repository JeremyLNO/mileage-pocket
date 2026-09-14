import Foundation

/// What stands between a period and being declared finished, and what happens to it after.
///
/// Two questions, both pure arithmetic over the trips:
///
/// * **Can it be closed?** Not while drives in it are still unqualified. Closing a month
///   whose trips are waiting on an answer files a claim containing whatever the default
///   happened to be — which is the failure the qualification queue exists to prevent, and it
///   would be pointless to let the closing screen walk straight past it.
/// * **Has it moved since?** Nothing forbids correcting a trip after the claim went out. But
///   a figure that changes after being filed has to be visible, or the app quietly produces
///   two documents that disagree.
enum PeriodClosing {
    /// Everything the closing screen needs to know about one period.
    struct Status: Equatable {
        let tripCount: Int
        let unqualifiedCount: Int
        let distanceMeters: Double
        /// When it was closed, if it was.
        let closedAt: Date?
        /// A trip inside the period was created or edited after that moment.
        let changedSinceClose: Bool
        /// What the period was worth at the moment it was closed.
        let closedDistanceMeters: Double?

        var isClosed: Bool { closedAt != nil }
        var canClose: Bool { !isClosed && unqualifiedCount == 0 && tripCount > 0 }
        /// Metres the period has gained or lost since it was filed.
        var drift: Double? {
            guard let closedDistanceMeters, changedSinceClose else { return nil }
            return distanceMeters - closedDistanceMeters
        }
    }

    static func status(
        trips: [Trip],
        range: Range<Date>,
        closed: ClosedPeriod?
    ) -> Status {
        let inPeriod = trips.filter { $0.endedAt != nil && range.contains($0.startedAt) }
        let closedAt = closed?.closedAt
        return Status(
            tripCount: inPeriod.count,
            unqualifiedCount: inPeriod.filter { !$0.isReviewed }.count,
            distanceMeters: inPeriod.reduce(0) { $0 + $1.distanceMeters },
            closedAt: closedAt,
            // `updatedAt` covers both cases that matter: a trip edited after the close, and
            // one added afterwards — a manual entry for a drive someone remembered later
            // carries a fresh `updatedAt` too.
            changedSinceClose: closedAt.map { at in inPeriod.contains { $0.updatedAt > at } } ?? false,
            closedDistanceMeters: closed?.distanceMeters
        )
    }
}
