import ActivityKit
import Foundation

/// The Live Activity's payload. Lives in `Shared/` because both the app (which pushes
/// updates) and the widget extension (which renders them) must agree on it byte for byte.
///
/// Only what the lock screen shows travels here: no route, no coordinates. A Live Activity
/// payload is small by contract, and a driver's position has no business being in one.
struct TripAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var distanceMeters: Double
        var startedAt: Date
        /// Raw value of `DistanceUnit` — the widget formats with the user's unit without
        /// having to reach into the app's settings store.
        var unitRaw: String

        var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .kilometers }
    }

    var vehicleName: String
}
