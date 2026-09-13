import Foundation
import Security

/// Remembers when this person first opened the app.
///
/// Stored in the keychain rather than `UserDefaults` or the SwiftData store, because both of
/// those go away with the app: deleting and reinstalling would hand out a fresh free period
/// every time. A keychain item survives deletion, so the period is granted once per device.
///
/// It is still not tamper-proof — erasing the device resets it — but it is the strongest
/// guarantee available without a server, and the paid entitlement itself remains StoreKit's
/// to decide.
enum InstallDateStore {
    private static let service = "company.lno.mileage.access"
    private static let account = "firstLaunch"

    /// The stored date, writing today's if there is none yet.
    static func firstLaunchDate(now: Date = .now) -> Date {
        if let existing = read() { return existing }
        write(now)
        return read() ?? now
    }

    static func read() -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let seconds = String(data: data, encoding: .utf8).flatMap(Double.init)
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static func write(_ date: Date) {
        let data = Data(String(date.timeIntervalSince1970).utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Readable in the background, so a trip started from the widget or resumed after
            // a reboot is not blocked behind the first unlock of the day.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        } else {
            SecItemAdd(query.merging(attributes) { current, _ in current } as CFDictionary, nil)
        }
    }

    /// Used by tests and by "Delete all data".
    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
