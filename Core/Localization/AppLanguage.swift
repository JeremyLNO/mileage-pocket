import Foundation

/// The languages shipped with the app. Adding one means adding a case here and translating
/// `Localizable.xcstrings` — nothing else in the codebase needs to know.
enum AppLanguage: String, Codable, CaseIterable, Sendable, Identifiable {
    case en
    case fr
    case es
    case de
    case it
    case pt

    var id: String { rawValue }

    var locale: Locale { Locale(identifier: rawValue) }

    /// Shown in the language picker, always in the language itself — a user looking for
    /// their own language should not have to read it in someone else's.
    var nativeName: String {
        switch self {
        case .en: return "English"
        case .fr: return "Français"
        case .es: return "Español"
        case .de: return "Deutsch"
        case .it: return "Italiano"
        case .pt: return "Português"
        }
    }
}
