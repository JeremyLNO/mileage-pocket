import Foundation

/// Whether this build is entitled to CloudKit.
///
/// This is not a nicety. Opening a CloudKit-backed SwiftData store without the
/// `com.apple.developer.icloud-container-identifiers` entitlement does **not** throw — the
/// container is created, CloudKit then traps on a background queue, and the process dies a
/// second after launch. A `try?` around the constructor catches nothing.
///
/// iOS exposes no public way to read one's own entitlements, so the answer comes from the
/// build configuration instead: `CLOUDKIT_AVAILABLE` in `Config/Base.xcconfig`, right next
/// to the decision it describes, carried into Info.plist. Flip it to YES in the same commit
/// that puts the container back in the entitlements file — never separately.
enum CloudKitAvailability {
    static let containerIdentifier = "iCloud.company.lno.mileage"

    static var isEntitled: Bool {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CloudKitAvailable") as? String else {
            return false
        }
        return ["YES", "1", "true", "TRUE"].contains(raw)
    }
}
