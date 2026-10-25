import Foundation

public enum CryptoError: Error, Equatable {
    case invalidKeyLength(expected: Int)
    case payloadTooShort
    case decryptionFailed
    case invalidBase32Character(Character)
    case kdfParameterBelowMinimum(String)
    case kdfFailed(String)
}
