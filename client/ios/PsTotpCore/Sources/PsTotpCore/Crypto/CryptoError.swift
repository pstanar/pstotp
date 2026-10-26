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
}
