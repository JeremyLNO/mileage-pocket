import StoreKit
import StoreKitTest
import XCTest
@testable import MileagePocket

/// Runs against a real `SKTestSession` built from the app's own StoreKit configuration —
/// which is why that file is copied into the bundle. Driving the session directly beats
/// relying on the scheme's configuration: the session here is created, asserted on and torn
/// down by the test, so a green run means StoreKit really answered.
///
/// ⚠️ StoreKit Testing is inert on the iOS 26.x runtimes. Run this suite on **iOS 18.6**.
@MainActor
final class SubscriptionTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        try await super.setUp()
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: "MileagePocket", withExtension: "storekit"),
            "the StoreKit configuration must ship in the app bundle for this suite to run"
        )
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()

        // An empty storefront is a dead session, not an empty catalogue — fail loudly rather
        // than reporting "no products" as if that were a result.
        XCTAssertFalse(session.storefront.isEmpty, "StoreKit test session is inert — run this on iOS 18.6")
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
        try await super.tearDown()
    }

    private func makeService() async -> SubscriptionService {
        let service = SubscriptionService()
        await service.load()
        return service
    }

    func testBothPlansLoadFromStoreKit() async throws {
        let service = await makeService()
        XCTAssertEqual(service.products.count, 2, service.lastError ?? "no error reported")
        XCTAssertNotNil(service.monthly)
        XCTAssertNotNil(service.annual)
    }

    func testBothPlansCarryTheThreeDayIntroductoryOffer() async throws {
        let service = await makeService()
        for product in service.products {
            let offer = try XCTUnwrap(service.introductoryOffer(for: product), product.id)
            XCTAssertEqual(offer.paymentMode, .freeTrial)
            XCTAssertEqual(offer.period.unit, .day)
            XCTAssertEqual(offer.period.value, 3)
        }
    }

    /// The saving is computed from the two live prices, never typed into the UI: 12 × 2.99 =
    /// 35.88 against 29.99 is 16 %.
    func testAnnualSavingIsDerivedFromTheLivePrices() async throws {
        let service = await makeService()
        XCTAssertEqual(service.annualSavingsPercent, 16)
    }

    func testNoEntitlementBeforeAnyPurchase() async throws {
        let service = await makeService()
        XCTAssertEqual(service.entitlement, .none)
        XCTAssertFalse(service.entitlement.isActive)
    }

    func testPurchasingTheMonthlyPlanGrantsAccess() async throws {
        let service = await makeService()
        let monthly = try XCTUnwrap(service.monthly)
        let purchased = try await service.purchase(monthly)
        XCTAssertTrue(purchased)

        XCTAssertTrue(service.entitlement.isActive)
        XCTAssertEqual(service.entitlement.productID, ProductIDs.monthly)
    }

    func testPurchasingTheAnnualPlanGrantsAccess() async throws {
        let service = await makeService()
        let annual = try XCTUnwrap(service.annual)
        let purchased = try await service.purchase(annual)
        XCTAssertTrue(purchased)
        XCTAssertEqual(service.entitlement.productID, ProductIDs.annual)
    }

    /// The trial is the App Store's introductory offer, never a date the app writes down.
    func testAnIntroductoryPurchaseIsReportedAsATrial() async throws {
        let service = await makeService()
        let monthly = try XCTUnwrap(service.monthly)
        try await service.purchase(monthly)

        guard case .trial = service.entitlement else {
            return XCTFail("a first purchase with an introductory offer must read as a trial, got \(service.entitlement)")
        }
    }

    /// Every renewal state, mapped. `SKTestSession.expireSubscription` cannot produce a
    /// lapsed auto-renewing subscription — auto-renew simply renews it, which the diagnostic
    /// run confirmed (state stayed `.subscribed`). So the branch that closes the paywall is
    /// tested here, on the mapping itself, rather than left to a test that cannot reach it.
    func testEveryRenewalStateMapsToTheRightEntitlement() {
        let id = ProductIDs.monthly
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertEqual(
            SubscriptionService.entitlement(for: .subscribed, productID: id, expires: expiry, isTrial: false),
            .subscribed(productID: id, expires: expiry)
        )
        XCTAssertEqual(
            SubscriptionService.entitlement(for: .subscribed, productID: id, expires: expiry, isTrial: true),
            .trial(productID: id, expires: expiry)
        )
        XCTAssertEqual(
            SubscriptionService.entitlement(for: .inGracePeriod, productID: id, expires: expiry, isTrial: false),
            .gracePeriod(productID: id, expires: expiry)
        )
        XCTAssertNil(SubscriptionService.entitlement(for: .expired, productID: id, expires: expiry, isTrial: false))
        XCTAssertNil(SubscriptionService.entitlement(for: .revoked, productID: id, expires: expiry, isTrial: false))
        XCTAssertNil(SubscriptionService.entitlement(for: .inBillingRetryPeriod, productID: id, expires: expiry, isTrial: false))
    }

    /// Owning nothing means premium is closed — the state after a lapse that has fully
    /// settled, and after a fresh install by someone who never subscribed.
    func testWithNoTransactionsPremiumIsClosed() async throws {
        let service = await makeService()
        let monthly = try XCTUnwrap(service.monthly)
        _ = try await service.purchase(monthly)
        XCTAssertTrue(service.entitlement.isActive)

        session.clearTransactions()
        await service.refreshEntitlement()

        XCTAssertFalse(service.entitlement.isActive)
    }

    /// Refund and expiry, tested on the guard itself.
    ///
    /// `SKTestSession.refundTransaction` was tried first and does **not** revoke an
    /// auto-renewable entitlement: after refunding, `currentEntitlements` still reported the
    /// purchase as owned with `revocationDate == nil`. A test driven through it would have
    /// been green whatever this guard did, which is worse than no test.
    func testRevokedOrExpiredTransactionsGrantNothing() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let past = now.addingTimeInterval(-1)
        let future = now.addingTimeInterval(60)

        XCTAssertTrue(SubscriptionService.grantsAccess(revokedAt: nil, expiresAt: future, now: now))
        XCTAssertTrue(SubscriptionService.grantsAccess(revokedAt: nil, expiresAt: nil, now: now))
        XCTAssertFalse(SubscriptionService.grantsAccess(revokedAt: past, expiresAt: future, now: now), "a refund ends access")
        XCTAssertFalse(SubscriptionService.grantsAccess(revokedAt: nil, expiresAt: past, now: now), "an expiry ends access")

        // Tested on the bound itself: a transaction revoked or expiring exactly now is over.
        XCTAssertFalse(SubscriptionService.grantsAccess(revokedAt: now, expiresAt: future, now: now))
        XCTAssertFalse(SubscriptionService.grantsAccess(revokedAt: nil, expiresAt: now, now: now))
        XCTAssertTrue(SubscriptionService.grantsAccess(revokedAt: nil, expiresAt: now.addingTimeInterval(0.001), now: now))
    }

    func testRestoringBringsBackAPreviousPurchase() async throws {
        let service = await makeService()
        let annual = try XCTUnwrap(service.annual)
        try await service.purchase(annual)
        XCTAssertTrue(service.entitlement.isActive)

        // A fresh service, as after a reinstall: nothing is remembered locally, everything
        // comes back from StoreKit.
        let reinstalled = await makeService()
        XCTAssertTrue(reinstalled.entitlement.isActive, "a reinstall must not lose an active subscription")
        try await reinstalled.restore()
        XCTAssertEqual(reinstalled.entitlement.productID, ProductIDs.annual)
    }

    /// What a purchase unlocks is `AccessPolicy`'s business, not StoreKit's — see
    /// `AccessPolicyTests`. This suite stops at the entitlement.
    func testNoEntitlementIsReportedWithoutAPurchase() async throws {
        let service = await makeService()
        XCTAssertEqual(service.entitlement, .none)
    }

}
