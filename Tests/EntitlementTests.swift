import XCTest
@testable import MileagePocket

/// Pins the access rules down as a test rather than a comment: which features the paywall
/// guards is a product decision that must not drift silently as screens are added.
final class EntitlementTests: XCTestCase {
    func testOnlyAnActiveEntitlementUnlocksPremium() {
        XCTAssertFalse(Entitlement.none.isActive)
        XCTAssertTrue(Entitlement.trial(productID: ProductIDs.monthly, expires: .now).isActive)
        XCTAssertTrue(Entitlement.subscribed(productID: ProductIDs.annual, expires: nil).isActive)
        XCTAssertTrue(Entitlement.gracePeriod(productID: ProductIDs.monthly, expires: .now).isActive)
    }

    func testEveryPremiumFeatureIsGuarded() {
        // If a new case is added, this list must be updated deliberately — which is the
        // point: gating is not something to decide by accident at the call site.
        XCTAssertEqual(
            Set(PremiumFeature.allCases.map(\.rawValue)),
            ["startTrip", "manualTrip", "exportReport", "multipleVehicles"]
        )
    }

    func testEntitlementCarriesTheProductAndExpiry() {
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        let entitlement = Entitlement.subscribed(productID: ProductIDs.annual, expires: expiry)
        XCTAssertEqual(entitlement.productID, ProductIDs.annual)
        XCTAssertEqual(entitlement.expirationDate, expiry)
        XCTAssertNil(Entitlement.none.productID)
    }
}
