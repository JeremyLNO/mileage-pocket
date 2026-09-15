import Foundation

/// Looks strings up in a *chosen* language rather than the system one.
///
/// `NSLocalizedString` reads `Bundle.main`, which follows the device's language and knows
/// nothing about the picker in Settings. Every string that went through it stayed in the
/// system language while the rest of the app switched — and the exported PDF, a document a
/// French user hands to their accountant, was printed in English whatever they chose.
enum LocalizedBundle {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Bundle] = [:]

    /// The bundle for `language`, or `Bundle.main` when the app carries no catalogue for it
    /// — which is the right fallback, not a failure: `main` resolves through the system's
    /// own preference chain and always produces text.
    static func bundle(forLanguageCode code: String) -> Bundle {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[code] { return cached }
        let resolved = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
        cache[code] = resolved
        return resolved
    }

    static func bundle(for locale: Locale) -> Bundle {
        bundle(forLanguageCode: locale.language.languageCode?.identifier ?? "en")
    }
}

/// A language pinned once and asked for strings many times — how a document is built.
///
/// Held by language code rather than by `Bundle`, which is not `Sendable`; the bundle is
/// resolved (and cached) per lookup, which costs a dictionary read.
struct LocalizedStrings: Sendable {
    let languageCode: String

    init(locale: Locale) {
        self.languageCode = locale.language.languageCode?.identifier ?? "en"
    }

    init(languageCode: String) {
        self.languageCode = languageCode
    }

    func callAsFunction(_ key: String) -> String {
        LocalizedBundle.bundle(forLanguageCode: languageCode)
            .localizedString(forKey: key, value: nil, table: nil)
    }

    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: self(key), locale: Locale(identifier: languageCode), arguments: arguments)
    }

    /// Plural-aware. A count formatted flat renders "1 trips" — and this one is printed on
    /// the document handed to an accountant.
    func plural(_ key: String, _ count: Int) -> String {
        String(format: self(key), locale: Locale(identifier: languageCode), count)
    }
}
