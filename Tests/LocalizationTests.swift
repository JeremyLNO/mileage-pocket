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

/// Keys the code composes at runtime, checked against the catalog compiled into the app.
///
/// `NSLocalizedString` returns the key itself when the lookup fails, so "the key came back
/// unchanged" is exactly the failure these assert against. This is the bug that shipped:
/// `LocalizedStringKey("vehicle.type.\(raw)")` composes `"vehicle.type.%@"`, matches nothing,
/// and draws `vehicle.type.car` on screen — with no error anywhere.
final class RuntimeLocalizationKeyTests: XCTestCase {
    private func assertResolves(_ key: String, file: StaticString = #filePath, line: UInt = #line) {
        let value = L.string(key)
        XCTAssertNotEqual(value, key, "\(key) is missing from the string catalog", file: file, line: line)
        XCTAssertFalse(value.isEmpty, "\(key) resolves to an empty string", file: file, line: line)
    }

    func testEveryVehicleTypeHasALabel() {
        for type in VehicleType.allCases {
            assertResolves("vehicle.type.\(type.rawValue)")
        }
    }

    func testEveryPurposePresetHasALabel() {
        for preset in TripPurposePreset.allCases {
            assertResolves("purpose.\(preset.rawValue)")
        }
    }

    func testEveryTripSectionHasATitle() {
        for section in TripSection.allCases {
            assertResolves(section.titleKey)
        }
    }

    func testEveryPaywallFeatureHasALabel() {
        for key in PaywallView.featureKeys() {
            assertResolves(key)
        }
        // Listed conditionally, so it would escape the loop above when iCloud is off.
        assertResolves("paywall.feature.icloud")
    }

    /// Interpolated keys resolve to their arguments, so the formatted result must differ from
    /// both the key and the bare argument.
    func testFormattedKeysAreLookedUpBeforeTheyAreFormatted() {
        let estimated = L.format("home.estimated", "€117.46")
        XCTAssertNotEqual(estimated, "home.estimated")
        XCTAssertNotEqual(estimated, "€117.46", "the key was not looked up, only interpolated")
        XCTAssertTrue(estimated.contains("117.46"), estimated)

        let plural = L.plural("home.business.trips", 6)
        XCTAssertNotEqual(plural, "home.business.trips")
        XCTAssertTrue(plural.contains("6"), plural)
    }

    func testPluralRulesSelectDifferentFormsForOneAndMany() {
        let one = L.plural("home.business.trips", 1)
        let many = L.plural("home.business.trips", 5)
        XCTAssertNotEqual(one, many, "a count of 1 must not read like a count of 5")
    }
}
