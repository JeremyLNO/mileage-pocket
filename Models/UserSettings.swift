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
    /// The two reminders, each switchable on its own. They used to be decided once at
    /// onboarding and never again: declining there meant no reminder was reachable from
    /// anywhere in the app, and accepting meant the monthly one could only be silenced by
    /// turning off every notification in iOS Settings.
    /// Start recording by itself when the phone is plugged into CarPlay.
    ///
    /// Off by default: a trip that starts on its own is a trip the driver did not ask for,
    /// and the first one has to be their decision.
    var autoStartOnCarPlay: Bool = false
    /// Stop when CarPlay goes away. Paired with the switch above and on by default, because
    /// a trip that begins by itself has to be able to end by itself — otherwise the one thing
    /// that ruins a month of records, a trip left running, is exactly what automation
    /// produces.
    var autoStopOnCarPlayDisconnect: Bool = true
    var tripReminderEnabled: Bool = true
    var monthlyReportReminderEnabled: Bool = true

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
