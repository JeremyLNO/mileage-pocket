import XCTest
@testable import MileagePocket

final class LocalizationTests: XCTestCase {
    func testExplicitOverrideWinsOverSystemLanguage() {
        XCTAssertEqual(
            LanguageResolver.resolve(hasExplicitOverride: true, selectedLanguage: "de", preferredLanguages: ["fr-FR"]),
            .de
        )
    }

    func testFirstSupportedSystemLanguageIsUsed() {
        XCTAssertEqual(
            LanguageResolver.resolve(hasExplicitOverride: false, selectedLanguage: nil, preferredLanguages: ["it-IT", "en-US"]),
            .it
        )
    }

    func testUnsupportedSystemLanguageFallsBackToEnglish() {
        XCTAssertEqual(
            LanguageResolver.resolve(hasExplicitOverride: false, selectedLanguage: nil, preferredLanguages: ["ja-JP"]),
            .en
        )
    }

    func testUnsupportedLanguageIsSkippedInFavourOfTheNextSupportedOne() {
        XCTAssertEqual(
            LanguageResolver.resolve(hasExplicitOverride: false, selectedLanguage: nil, preferredLanguages: ["ja-JP", "pt-BR", "fr-FR"]),
            .pt
        )
    }

    func testOverrideFlagWithoutValueFallsBackToSystem() {
        XCTAssertEqual(
            LanguageResolver.resolve(hasExplicitOverride: true, selectedLanguage: nil, preferredLanguages: ["es-ES"]),
            .es
        )
    }

    func testAllSixLanguagesShip() {
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)), ["en", "fr", "es", "de", "it", "pt"])
        for language in AppLanguage.allCases {
            XCTAssertFalse(language.nativeName.isEmpty)
        }
    }
}
