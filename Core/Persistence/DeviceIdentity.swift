import Foundation

/// A stable id for *this* install, used to keep one device's in-flight trip out of another's.
///
/// `ActiveTripState` syncs through CloudKit like every other model, so the row an iPhone
/// writes at the start of a drive lands on the iPad within seconds. Without this, the iPad's
/// next launch found that row and "resumed" a trip it was not on — two devices appending
/// fixes to the same trip id, and whichever stopped last overwrote the other.
enum DeviceIdentity {
    private static let key = "deviceIdentifier"

    /// Persisted rather than derived: `identifierForVendor` is nil while the device is
    /// locked at first launch, which is exactly when a trip started from the widget begins.
    static var current: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty { return existing }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: key)
        return generated
    }
}
