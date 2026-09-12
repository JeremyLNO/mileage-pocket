import Foundation

/// A trip is either a deductible/reimbursable business drive or a private one.
enum TripType: String, Codable, CaseIterable, Sendable {
    case business
    case personal
}

enum DistanceUnit: String, Codable, CaseIterable, Sendable {
    case kilometers
    case miles

    /// Metres in one unit. All distances are stored in metres; this converts for display
    /// and for rule evaluation, never the other way round.
    var metersPerUnit: Double {
        switch self {
        case .kilometers: return 1000
        case .miles: return 1609.344
        }
    }

    func value(fromMeters meters: Double) -> Double { meters / metersPerUnit }
    func meters(fromValue value: Double) -> Double { value * metersPerUnit }
}

enum VehicleType: String, Codable, CaseIterable, Sendable {
    case car
    case electricCar
    case van
    case motorcycle
    case moped
    case bicycle
}

enum FuelType: String, Codable, CaseIterable, Sendable {
    case petrol
    case diesel
    case hybrid
    case electric
    case other
}

/// Which rate the user wants applied. `official` falls back to `custom` automatically when
/// the selected country has no verified rule pack — the app never invents a tax rate.
enum RateMode: String, Codable, CaseIterable, Sendable {
    case official
    case employer
    case custom
}

/// Preset purposes offered on the post-trip sheet, alongside a free-text field.
enum TripPurposePreset: String, CaseIterable, Sendable {
    case clientVisit
    case meeting
    case delivery
    case siteVisit
    case other
}
