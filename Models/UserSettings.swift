import Foundation
import SwiftData

/// Single-row settings model. Read through `SettingsStore`, which guarantees the row exists.
@Model
final class UserSettings {
    var id: UUID = UUID()

    var userName: String?
    var companyName: String?
    var email: String?

    var countryCode: String = "US"
    var currencyCode: String = "USD"
    var distanceUnitRaw: String = DistanceUnit.kilometers.rawValue
    var selectedLanguage: String?
    var hasExplicitLanguageOverride: Bool = false

    var defaultVehicleID: UUID?
    var defaultTripTypeRaw: String = TripType.business.rawValue

    var rateModeRaw: String = RateMode.official.rawValue
    var customRate: Decimal?
    var customRateCurrencyCode: String?
    var employerRate: Decimal?

    var iCloudSyncEnabled: Bool = true
    var hasCompletedOnboarding: Bool = false
    var notificationsEnabled: Bool = false

    init() {
        self.id = UUID()
    }

    var distanceUnit: DistanceUnit {
        get { DistanceUnit(rawValue: distanceUnitRaw) ?? .kilometers }
        set { distanceUnitRaw = newValue.rawValue }
    }

    var defaultTripType: TripType {
        get { TripType(rawValue: defaultTripTypeRaw) ?? .business }
        set { defaultTripTypeRaw = newValue.rawValue }
    }

    var rateMode: RateMode {
        get { RateMode(rawValue: rateModeRaw) ?? .official }
        set { rateModeRaw = newValue.rawValue }
    }
}
