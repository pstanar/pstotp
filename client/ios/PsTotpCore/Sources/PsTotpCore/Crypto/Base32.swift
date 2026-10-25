import Foundation

/// Base32 encoding/decoding (RFC 4648). TOTP secrets are stored as Base32 strings.
public enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    public static func decode(_ input: String) throws -> Data {
        let cleaned = input.uppercased()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        if cleaned.isEmpty { return Data() }

        var output = [UInt8]()
        output.reserveCapacity(cleaned.count * 5 / 8)
        var buffer = 0
        var bitsLeft = 0

        for c in cleaned {
            guard let value = alphabet.firstIndex(of: c) else {
                throw CryptoError.invalidBase32Character(c)
            }
            buffer = (buffer << 5) | value
            bitsLeft += 5
            if bitsLeft >= 8 {
                bitsLeft -= 8
                output.append(UInt8((buffer >> bitsLeft) & 0xFF))
                buffer &= (1 << bitsLeft) - 1
            }
        }
        return Data(output)
    }

    public static func encode(_ input: Data) -> String {
        if input.isEmpty { return "" }
        var result = ""
        var buffer = 0
        var bitsLeft = 0

        for b in input {
            buffer = (buffer << 8) | Int(b)
            bitsLeft += 8
            while bitsLeft >= 5 {
                bitsLeft -= 5
                result.append(alphabet[(buffer >> bitsLeft) & 0x1F])
                buffer &= (1 << bitsLeft) - 1
            }
        }
        if bitsLeft > 0 {
            result.append(alphabet[(buffer << (5 - bitsLeft)) & 0x1F])
        }
        return result
    }
}
