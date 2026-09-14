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
        /// The language the user chose *in the app*, which is not necessarily the system's.
        /// Without it the lock screen wrote `1.6 km` where the driving screen wrote `1,6 km`
        /// — one measurement, two spellings, and a driver comparing the two screens
        /// concluding that one of them is lying.
        ///
        /// Optional so an activity started by an older build still decodes: a payload that
        /// fails to decode is a Live Activity that silently stops updating.
        var localeIdentifier: String?

        var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .kilometers }
        var locale: Locale { localeIdentifier.map(Locale.init(identifier:)) ?? .current }
    }

    var vehicleName: String
}
