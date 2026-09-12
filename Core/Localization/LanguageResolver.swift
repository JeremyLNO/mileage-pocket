import Foundation

/// Pure resolution logic, kept out of `LocalizationService` so the priority rule is
/// testable without depending on whatever `Locale.preferredLanguages` the test host has.
///
/// Priority: explicit user override > first supported system language > English.
enum LanguageResolver {
    static func resolve(
        hasExplicitOverride: Bool,
        selectedLanguage: String?,
        preferredLanguages: [String]
    ) -> AppLanguage {
        if hasExplicitOverride, let raw = selectedLanguage, let explicit = AppLanguage(rawValue: raw) {
            return explicit
        }
        for identifier in preferredLanguages {
            if let code = Locale(identifier: identifier).language.languageCode?.identifier,
               let match = AppLanguage(rawValue: code) {
                return match
            }
        }
        return .en
    }
}
