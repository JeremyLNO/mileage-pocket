import Foundation
import Observation
import SwiftData

/// Guarantees the single `UserSettings` row exists and is the one everyone reads.
///
/// Without this, two code paths each create their own row after a fresh install and the app
/// starts disagreeing with itself about the country.
@Observable
@MainActor
final class SettingsStore {
    private(set) var settings: UserSettings
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        self.settings = Self.fetchOrCreate(in: context)
    }

    private static func fetchOrCreate(in context: ModelContext) -> UserSettings {
        let descriptor = FetchDescriptor<UserSettings>(sortBy: [SortDescriptor(\.id)])
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = UserSettings()
        let detected = CountryCatalog.detectedCountryCode()
        created.countryCode = detected
        created.currencyCode = CountryCatalog.currencyCode(for: detected)
        created.distanceUnit = CountryCatalog.distanceUnit(for: detected)
        context.insert(created)
        try? context.save()
        return created
    }

    func save() {
        try? context.save()
    }

    /// Applying a country resets the units and currency it implies, but **never** touches an
    /// existing trip: a trip carries the rate that was applied when it was saved.
    func applyCountry(_ code: String) {
        settings.countryCode = code.uppercased()
        settings.currencyCode = CountryCatalog.currencyCode(for: code)
        settings.distanceUnit = CountryCatalog.distanceUnit(for: code)
        save()
    }
}
