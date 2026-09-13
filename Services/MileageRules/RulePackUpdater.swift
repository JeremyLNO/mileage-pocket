import CryptoKit
import Foundation
import OSLog

/// Fetches newer rule packs, verifies them and caches them.
///
/// Every failure path here is silent by design. The app ships with valid packs and must keep
/// working with no network at all; a refresh that cannot complete is a non-event, not an
/// error worth showing someone about to drive.
actor RulePackUpdater {
    private let logger = Logger(subsystem: "company.lno.mileage", category: "RulePackUpdater")
    private let endpoint: URL
    private let store: RulePackStore
    private let injectedSession: URLSession?
    private let cacheDirectory: URL?
    /// The key a bundle must be signed with. Injectable so the refusal paths can be tested
    /// with a key pair made on the spot — the shipping private key is not in this repository
    /// and must never be — and so a key can be rotated without a code change here.
    private let publicKey: Curve25519.Signing.PublicKey?

    init(
        endpoint: URL,
        store: RulePackStore,
        session: URLSession? = nil,
        cacheDirectory: URL? = RulePackStore.defaultCacheDirectory,
        publicKey: Curve25519.Signing.PublicKey? = RulePackVerifier.defaultPublicKey()
    ) {
        self.endpoint = endpoint
        self.store = store
        self.cacheDirectory = cacheDirectory
        self.publicKey = publicKey
        self.injectedSession = session
    }

    /// Built on first use, not at init.
    ///
    /// Constructing a `URLSession` costs a `dlopen` of CFNetwork's proxy plug-in, which the
    /// iOS 18.6 simulator runtime crashes on under this toolchain — and doing it in `init`
    /// put that on the app's launch path for a request that may never be made. Nothing here
    /// needs a session until a refresh actually runs.
    private func makeSession() -> URLSession {
        if let injectedSession { return injectedSession }
        let configuration = URLSessionConfiguration.ephemeral
        // Any network call reachable from a launch path carries a timeout. Without one, a
        // hung connection is indistinguishable from a hung app.
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }

    @discardableResult
    func refresh() async -> Bool {
        guard let publicKey else { return false }

        do {
            let (data, response) = try await makeSession().data(from: endpoint)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }

            let bundle = try JSONDecoder().decode(SignedRuleBundle.self, from: data)
            guard RulePackVerifier.verify(payload: bundle.payload, signature: bundle.signature, publicKey: publicKey) else {
                logger.error("Rule pack bundle failed signature verification — ignored")
                return false
            }

            let packs = try RulePack.decoder().decode([RulePack].self, from: bundle.payload)
            var applied = 0
            for pack in packs where isNewer(pack) {
                store.insert(pack)
                cache(pack)
                applied += 1
            }
            return applied > 0
        } catch {
            logger.debug("Rule pack refresh skipped: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Never step backwards: a replayed older bundle must not undo a newer pack already held.
    private func isNewer(_ pack: RulePack) -> Bool {
        guard let existing = store.pack(country: pack.country, on: .now) else { return true }
        return pack.version.compare(existing.version, options: .numeric) == .orderedDescending
    }

    private func cache(_ pack: RulePack) {
        guard let cacheDirectory else { return }
        let directory = cacheDirectory.appendingPathComponent(pack.country.uppercased(), isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        encoder.dateEncodingStrategy = .formatted(formatter)

        guard let data = try? encoder.encode(pack) else { return }
        try? data.write(to: directory.appendingPathComponent("\(pack.version).json"), options: .atomic)
    }
}
