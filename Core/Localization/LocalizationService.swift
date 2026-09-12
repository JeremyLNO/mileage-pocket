import Foundation
import Observation

/// Resolves the active language and exposes it as a `Locale` that `RootView` pushes into
/// the SwiftUI environment, so switching language takes effect immediately — no relaunch.
@Observable
@MainActor
final class LocalizationService {
    private(set) var currentLanguage: AppLanguage

    private let settings: UserSettings

    init(settings: UserSettings) {
        self.settings = settings
        self.currentLanguage = LanguageResolver.resolve(
            hasExplicitOverride: settings.hasExplicitLanguageOverride,
            selectedLanguage: settings.selectedLanguage,
            preferredLanguages: Locale.preferredLanguages
        )
    }

    var locale: Locale { currentLanguage.locale }

    func setLanguage(_ language: AppLanguage) {
        settings.selectedLanguage = language.rawValue
        settings.hasExplicitLanguageOverride = true
        currentLanguage = language
    }

    /// Drops the override and follows the system again.
    func useSystemLanguage() {
        settings.hasExplicitLanguageOverride = false
        settings.selectedLanguage = nil
        currentLanguage = LanguageResolver.resolve(
            hasExplicitOverride: false,
            selectedLanguage: nil,
            preferredLanguages: Locale.preferredLanguages
        )
    }
}

/// Interpolating inside a `Text("key \(value)")` literal does **not** look up `key`: SwiftUI
/// builds the key `"key %@"`, which is not in the catalog, so the raw key is drawn on screen.
/// These helpers do the lookup first and format second, which is the only combination that
/// resolves — and, for a count, the only one that applies the language's plural rule.
enum L {
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), arguments: arguments)
    }

    /// Plural-aware. The catalog entry carries `one`/`other` variations; the rule is applied
    /// here, at format time, exactly as a `.stringsdict` entry is.
    static func plural(_ key: String, _ count: Int) -> String {
        String.localizedStringWithFormat(NSLocalizedString(key, comment: ""), count)
    }
}
