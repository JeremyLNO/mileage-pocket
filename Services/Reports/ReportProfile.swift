import Foundation

/// The identity printed on a report: who drove, under which rule, in which units.
struct ReportProfile: Sendable {
    let userName: String
    let companyName: String?
    let vehicleLabel: String?
    let countryCode: String
    let countryName: String
    /// e.g. "HMRC — Approved mileage allowance payments (AMAP)" or "Custom rate".
    let ruleDescription: String
    let ruleVersion: String
    let ruleSourceURL: URL?
    let isOfficialRate: Bool
    let unit: DistanceUnit
    let locale: Locale

    static func preview() -> ReportProfile {
        ReportProfile(
            userName: "Jane Doe",
            companyName: "Doe Consulting",
            vehicleLabel: "Tesla Model 3",
            countryCode: "FR",
            countryName: "France",
            ruleDescription: "Official mileage scale",
            ruleVersion: "2026.1",
            ruleSourceURL: URL(string: "https://www.impots.gouv.fr"),
            isOfficialRate: true,
            unit: .kilometers,
            locale: Locale(identifier: "en_US")
        )
    }
}
