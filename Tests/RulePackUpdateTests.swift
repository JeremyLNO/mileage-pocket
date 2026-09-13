import CryptoKit
import XCTest
@testable import MileagePocket

/// A rule pack arriving over the network is a **tax rate from outside the app**. If a forged
/// one were believed, every figure the app printed afterwards would be wrong — and signed by
/// nobody. The signature check was the only thing standing between that and the user, and it
/// had no test at all: neither the accepting path nor, far worse, any of the refusing ones.
final class RulePackUpdateTests: XCTestCase {
    private var directory: URL!
    private var key: Curve25519.Signing.PrivateKey!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "rulepack-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Made here, per test: the key the app actually ships with has a private half that is
        // deliberately not in this repository.
        key = Curve25519.Signing.PrivateKey()
        StubURLProtocol.response = nil
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        StubURLProtocol.response = nil
    }

    // MARK: - Fixtures

    private func packJSON(country: String, version: String, rate: String) -> String {
        """
        [{
          "country": "\(country)",
          "version": "\(version)",
          "validFrom": "2020-01-01",
          "validUntil": null,
          "currencyCode": "EUR",
          "distanceUnit": "kilometers",
          "source": "Test",
          "sourceURL": "https://example.com/rates",
          "lastVerified": "2026-01-01",
          "schemes": [{
            "id": "car",
            "bandMode": "marginal",
            "vehicleTypes": ["car"],
            "fuelTypes": null,
            "powerBands": null,
            "bands": [{ "fromDistance": 0, "toDistance": null, "rate": "\(rate)", "constant": null }]
          }]
        }]
        """
    }

    /// Serves `payload` under a signature made with `signingKey` (the right one unless a test
    /// says otherwise), optionally after tampering with the bytes *after* signing.
    private func serve(
        payload: String,
        signedWith signingKey: Curve25519.Signing.PrivateKey? = nil,
        tamperedTo tampered: String? = nil,
        statusCode: Int = 200
    ) throws {
        let signedBytes = Data(payload.utf8)
        let signature = try (signingKey ?? key).signature(for: signedBytes)
        let bundle = SignedRuleBundle(
            version: "1",
            payload: tampered.map { Data($0.utf8) } ?? signedBytes,
            signature: signature
        )
        StubURLProtocol.response = (try JSONEncoder().encode(bundle), statusCode)
    }

    /// `verifyingWith` is a double optional on purpose: `.some(nil)` is "no key at all",
    /// which is a case under test, and a plain `nil` default would have collapsed into the
    /// real key and quietly made that test assert nothing.
    private func makeUpdater(
        store: RulePackStore,
        verifyingWith override: Curve25519.Signing.PublicKey?? = nil
    ) -> RulePackUpdater {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return RulePackUpdater(
            endpoint: URL(string: "https://rules.example.com/packs.json")!,
            store: store,
            session: URLSession(configuration: configuration),
            cacheDirectory: directory,
            publicKey: override ?? key.publicKey
        )
    }

    /// A store with nothing bundled in it, so only what the network supplies can be there.
    private func emptyStore() -> RulePackStore {
        RulePackStore(bundle: Bundle(for: RulePackUpdateTests.self), cacheDirectory: directory)
    }

    // MARK: - The accepting path

    func testACorrectlySignedBundleIsApplied() async throws {
        let store = emptyStore()
        try serve(payload: packJSON(country: "ZZ", version: "2026.2", rate: "0.99"))

        let applied = await makeUpdater(store: store).refresh()

        XCTAssertTrue(applied)
        let pack = try XCTUnwrap(store.pack(country: "ZZ", on: .now))
        XCTAssertEqual(pack.version, "2026.2")
        XCTAssertEqual(pack.schemes.first?.bands.first?.rate, Decimal(string: "0.99"))
    }

    // MARK: - The refusing paths — the ones that matter

    /// One byte of the payload changed after signing. This is the whole threat: a rate
    /// rewritten in flight, arriving with a signature that no longer covers it.
    func testAPayloadTamperedWithAfterSigningIsRefused() async throws {
        let store = emptyStore()
        try serve(
            payload: packJSON(country: "ZZ", version: "2026.2", rate: "0.99"),
            tamperedTo: packJSON(country: "ZZ", version: "2026.2", rate: "9.99")
        )

        let applied = await makeUpdater(store: store).refresh()

        XCTAssertFalse(applied, "a payload the signature does not cover must not be believed")
        XCTAssertNil(store.pack(country: "ZZ", on: .now), "and nothing from it may reach the store")
    }

    func testABundleSignedWithAnotherKeyIsRefused() async throws {
        let store = emptyStore()
        try serve(
            payload: packJSON(country: "ZZ", version: "2026.2", rate: "0.99"),
            signedWith: Curve25519.Signing.PrivateKey()
        )

        let applied = await makeUpdater(store: store).refresh()

        XCTAssertFalse(applied, "anyone can sign; only our key counts")
        XCTAssertNil(store.pack(country: "ZZ", on: .now))
    }

    /// A bundle that was genuine once, replayed later to push a rate back to an older value.
    func testAnOlderVersionDoesNotReplaceANewerOne() async throws {
        let store = emptyStore()
        try serve(payload: packJSON(country: "ZZ", version: "2026.10", rate: "0.99"))
        _ = await makeUpdater(store: store).refresh()

        try serve(payload: packJSON(country: "ZZ", version: "2026.9", rate: "0.10"))
        let applied = await makeUpdater(store: store).refresh()

        XCTAssertFalse(applied)
        XCTAssertEqual(store.pack(country: "ZZ", on: .now)?.version, "2026.10")
        XCTAssertEqual(
            store.pack(country: "ZZ", on: .now)?.schemes.first?.bands.first?.rate,
            Decimal(string: "0.99"),
            "a replayed older bundle must not roll the rate back"
        )
    }

    func testANonSuccessResponseChangesNothing() async throws {
        let store = emptyStore()
        try serve(payload: packJSON(country: "ZZ", version: "2026.2", rate: "0.99"), statusCode: 503)

        let applied = await makeUpdater(store: store).refresh()

        XCTAssertFalse(applied)
        XCTAssertNil(store.pack(country: "ZZ", on: .now))
    }

    func testAMalformedResponseChangesNothing() async throws {
        let store = emptyStore()
        StubURLProtocol.response = (Data("not json".utf8), 200)

        let applied = await makeUpdater(store: store).refresh()

        XCTAssertFalse(applied)
        XCTAssertNil(store.pack(country: "ZZ", on: .now))
    }

    func testNoKeyMeansNothingIsEverApplied() async throws {
        let store = emptyStore()
        try serve(payload: packJSON(country: "ZZ", version: "2026.2", rate: "0.99"))

        let applied = await makeUpdater(store: store, verifyingWith: .some(nil)).refresh()

        XCTAssertFalse(applied)
        XCTAssertNil(store.pack(country: "ZZ", on: .now))
    }

    // MARK: - The verifier itself

    func testTheVerifierAcceptsOnlyTheExactBytesItSigned() throws {
        let payload = Data("2026 rates".utf8)
        let signature = try key.signature(for: payload)

        XCTAssertTrue(RulePackVerifier.verify(payload: payload, signature: signature, publicKey: key.publicKey))
        XCTAssertFalse(
            RulePackVerifier.verify(payload: Data("2027 rates".utf8), signature: signature, publicKey: key.publicKey),
            "a signature must not travel from one payload to another"
        )
        XCTAssertFalse(
            RulePackVerifier.verify(
                payload: payload,
                signature: signature,
                publicKey: Curve25519.Signing.PrivateKey().publicKey
            ),
            "nor verify under a key that did not make it"
        )
    }

    /// The key that actually ships has to be a usable Ed25519 key. A typo in the base64 makes
    /// `defaultPublicKey()` nil, and `refresh()` then returns false forever — a rule-update
    /// channel that is silently dead, which is exactly how it would fail unnoticed.
    func testTheShippingPublicKeyLoads() {
        XCTAssertNotNil(RulePackVerifier.defaultPublicKey())
    }
}

/// Serves one canned response to any request. `URLProtocol` rather than a fake `URLSession`,
/// so the real session, the real decoder and the real verifier are all in the path.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var response: (Data, Int)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let (data, statusCode) = Self.response else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
