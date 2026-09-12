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
