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

    /// The catalogue's `one`/`other` variations, asserted on the *words* rather than on the
    /// two strings differing.
    ///
    /// They always differ: both interpolate the count. Replacing the variations with a single
    /// `"%lld business trips"` left the test green while the app drew "1 business trips".
    func testPluralRulesSelectDifferentFormsForOneAndMany() {
        let previous = L.languageCode
        defer { L.languageCode = previous }
        L.languageCode = "en"

        XCTAssertEqual(L.plural("home.business.trips", 1), "1 business trip")
        XCTAssertEqual(L.plural("home.business.trips", 5), "5 business trips")
    }

    // MARK: - The language the user picked, not the device's

    /// `NSLocalizedString` reads `Bundle.main`, which follows the *device* language. Every
    /// string built outside a SwiftUI `Text` went through it — the notification bodies, the
    /// plan label, the exported PDF — and stayed in the system language while the rest of the
    /// app switched. On a French phone set to English in Settings, the PDF handed to an
    /// accountant came out in French anyway; on an English phone set to French, in English.
    func testLookupsFollowTheInAppLanguageRatherThanTheDevice() {
        let previous = L.languageCode
        defer { L.languageCode = previous }

        L.languageCode = "en"
        let english = L.string("activetrip.stop.accessibility")
        L.languageCode = "fr"
        let french = L.string("activetrip.stop.accessibility")

        XCTAssertEqual(english, "Stop trip")
        XCTAssertEqual(french, "Arrêter le trajet")
        XCTAssertNotEqual(english, french)
    }

    func testFormattedLookupsAlsoFollowTheInAppLanguage() {
        let previous = L.languageCode
        defer { L.languageCode = previous }

        L.languageCode = "de"
        let german = L.format("pdf.page", 2, 7)
        XCTAssertEqual(german, "Seite 2 von 7")
    }

    /// The report is built by a service, not a view, so it never sees `\.locale` from the
    /// environment. It has to pin its own language — and the whole document, not just its
    /// numbers, has to come out in it.
    func testTheDocumentLanguageIsPinnedIndependentlyOfTheAppLanguage() {
        let previous = L.languageCode
        defer { L.languageCode = previous }
        L.languageCode = "en"

        let spanish = LocalizedStrings(locale: Locale(identifier: "es_ES"))
        XCTAssertEqual(spanish("pdf.summary.distance"), "Distancia total")
        XCTAssertEqual(spanish.format("pdf.page", 1, 3), "Página 1 de 3")
        // And the app-wide language is untouched by it.
        XCTAssertEqual(L.string("pdf.summary.distance"), "Total distance")
    }

    /// An unknown language must still produce text, not an empty string or a raw key.
    func testAnUnsupportedLanguageFallsBackToSomethingReadable() {
        let klingon = LocalizedStrings(languageCode: "tlh")
        XCTAssertFalse(klingon("activetrip.stop.accessibility").isEmpty)
        XCTAssertNotEqual(klingon("activetrip.stop.accessibility"), "activetrip.stop.accessibility")
    }

    /// The two location prompts are Info.plist keys, which `Localizable.xcstrings` does not
    /// reach: they need their own catalogue, and without it iOS shows the English sentence
    /// to every non-English user at the single most consequential moment in the app.
    func testTheLocationPromptsAreTranslatedInEverySupportedLanguage() throws {
        let keys = [
            "NSLocationWhenInUseUsageDescription",
            "NSLocationAlwaysAndWhenInUseUsageDescription",
        ]
        for language in AppLanguage.allCases {
            let code = language.locale.language.languageCode?.identifier ?? "en"
            let bundle = try XCTUnwrap(
                Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)),
                "\(code) has no lproj in the built app"
            )
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: "MISSING", table: "InfoPlist")
                XCTAssertNotEqual(value, "MISSING", "\(key) is not translated in \(code)")
                XCTAssertFalse(value.isEmpty)
            }
        }
    }
}
