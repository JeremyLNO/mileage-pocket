import XCTest
@testable import MileagePocket

final class SmokeTests: XCTestCase {
    func testBundleIdentifierMatchesAppStoreConnectRecord() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "Mileage.lno.company")
    }
}
