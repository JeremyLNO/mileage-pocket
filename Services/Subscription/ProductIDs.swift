import Foundation

/// The two subscription products, named in exactly one place. A typo here is a paywall that
/// silently shows nothing, which is why nothing else in the app spells these out.
enum ProductIDs {
    static let monthly = "company.lno.mileage.monthly"
    static let annual = "company.lno.mileage.annual"

    static var all: [String] { [monthly, annual] }

    static func isAnnual(_ productID: String) -> Bool { productID == annual }
}
