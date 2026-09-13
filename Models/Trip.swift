import Foundation
import SwiftData

/// One recorded drive.
///
/// Every property is optional or carries a default and no attribute is `.unique`: CloudKit
/// rejects a SwiftData schema that has either, and the store then fails to open at launch.
///
/// The applied rate is frozen here at save time (`mileageRuleVersion`, `mileageRate`,
/// `calculatedAmount`). A later rate change, country change or vehicle change never
/// rewrites an existing trip — only an explicit "Recalculate using current rules" does.
@Model
final class Trip: Identifiable {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?

    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?

    /// The town at each end — "Courbevoie".
    var startAddress: String?
    var endAddress: String?
    /// The street at each end — "12 Avenue Gambetta". Kept alongside the town because a trip
    /// that starts and ends in the same town is named by its streets or by nothing at all.
    var startStreet: String?
    var endStreet: String?

    /// Distance as measured by the GPS filter. Never overwritten by a manual correction.
    var rawDistanceMeters: Double = 0
    /// Set only when the user edits the distance by hand; `nil` means "use the raw value".
    var correctedDistanceMeters: Double?

    var tripTypeRaw: String = TripType.business.rawValue
    var purpose: String?

    var clientID: UUID?
    var projectID: UUID?
    var vehicleID: UUID?

    var countryCode: String = "US"
    var mileageRuleVersion: String?
    var mileageRate: Decimal?
    var calculatedAmount: Decimal?
    var currencyCode: String?
    /// The unit the frozen `mileageRate` is expressed in. Without it, correcting a distance
    /// re-applied a per-kilometre rate to a mileage figure, or the reverse — and the display
    /// unit is a Settings toggle that has nothing to do with the scale that was applied.
    var mileageUnitRaw: String?
    var rateModeRaw: String = RateMode.official.rawValue
    var isOfficialRate: Bool = false

    /// Seconds of driving GPS went quiet for, too long to reconstruct, so not counted.
    ///
    /// Kept on the trip rather than thrown away: the distance is genuinely short, and a
    /// driver who is not told why has no reason to reach for the distance editor.
    var unbridgedGapSeconds: Double = 0
    var isManuallyEdited: Bool = false
    var isManualEntry: Bool = false

    /// Simplified polyline, produced by `RouteCompactor` when the trip ends. The raw
    /// `LocationPoint` rows are deleted at that moment — keeping them would put hundreds of
    /// thousands of records into the user's CloudKit database for no readable benefit.
    var encodedRoute: Data?

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(id: UUID = UUID(), startedAt: Date = Date()) {
        self.id = id
        self.startedAt = startedAt
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var tripType: TripType {
        get { TripType(rawValue: tripTypeRaw) ?? .business }
        set { tripTypeRaw = newValue.rawValue }
    }

    var mileageUnit: DistanceUnit? {
        get { mileageUnitRaw.flatMap(DistanceUnit.init(rawValue:)) }
        set { mileageUnitRaw = newValue?.rawValue }
    }

    var rateMode: RateMode {
        get { RateMode(rawValue: rateModeRaw) ?? .official }
        set { rateModeRaw = newValue.rawValue }
    }

    /// The distance that counts: the manual correction when there is one, the measured
    /// distance otherwise.
    var distanceMeters: Double { correctedDistanceMeters ?? rawDistanceMeters }

    var duration: TimeInterval {
        guard let endedAt else { return 0 }
        return endedAt.timeIntervalSince(startedAt)
    }
}
