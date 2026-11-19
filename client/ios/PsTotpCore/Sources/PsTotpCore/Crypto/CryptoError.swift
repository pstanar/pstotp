import Foundation

public enum CryptoError: Error, Equatable {
    case invalidKeyLength(expected: Int)
    case payloadTooShort
    case decryptionFailed
    case invalidBase32Character(Character)
    case kdfParameterBelowMinimum(String)
    case kdfFailed(String)
    /// Digits or period that can't produce a code (e.g. an imported `period: 0`).
    case invalidTotpParameters
    /// Not a 32-hex-digit GUID.
    case invalidGuid(String)
    /// Envelope field that isn't valid base64.
    case invalidEncoding
    /// Not a 65-byte uncompressed P-256 point, or a point not on the curve.
    case invalidPublicKey
    /// Not a valid P-256 private key.
    case invalidPrivateKey
}
