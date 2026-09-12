import CryptoKit
import Foundation

/// A rule pack downloaded from the network is a tax rate arriving from outside the app, so it
/// is signed and the signature is checked before it is believed. Anything that fails is
/// dropped and the bundled pack keeps applying.
enum RulePackVerifier {
    /// Ed25519 public key, base64. The matching private key lives outside this repository
    /// (`~/crazybee-license-signing/`) and never ships.
    static let publicKeyBase64 = "/bdjrhhIFV8dDMpKQFBtxxtDNOWWHV3/G0vFy9jASM8="

    static func verify(payload: Data, signature: Data, publicKey: Curve25519.Signing.PublicKey) -> Bool {
        publicKey.isValidSignature(signature, for: payload)
    }

    static func defaultPublicKey() -> Curve25519.Signing.PublicKey? {
        guard let raw = Data(base64Encoded: publicKeyBase64) else { return nil }
        return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    }
}

/// What the endpoint serves: the packs as a JSON payload, plus a detached signature over
/// exactly those bytes.
struct SignedRuleBundle: Codable, Sendable {
    let version: String
    /// Base64 of the JSON array of `RulePack`.
    let payload: Data
    let signature: Data
}
