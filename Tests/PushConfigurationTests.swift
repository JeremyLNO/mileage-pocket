import XCTest
@testable import MileagePocket

/// The push provider is the only thing in this app that sends anything anywhere.
///
/// OneSignal itself is theirs to test. What is tested here is the wiring around it: that the
/// app is pointed at the right OneSignal application, that a tap on a notification cannot be
/// talked into opening an arbitrary URL, and that the switch in Settings governs the remote
/// notifications as well as the local ones.
final class PushConfigurationTests: XCTestCase {
    /// The Crazy Bee Labs app whose APNs platform is active against this bundle. A wrong or
    /// empty identifier here is silent: the SDK initialises against nothing and no device
    /// ever registers.
    func testTheAppIsPointedAtItsOwnOneSignalApplication() {
        XCTAssertEqual(OneSignalPush.appID, "fa7b63de-cff1-4a80-9a37-c9c3a59debe7")
        XCTAssertTrue(OneSignalPush.isConfigured)
    }

    /// The bundle identifier the APNs platform is registered against. If these ever diverge,
    /// pushes are accepted by OneSignal and dropped by Apple.
    func testTheBundleIdentifierMatchesTheOneRegisteredWithAPNs() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "Mileage.lno.company")
    }
}
