import CryptoKit
import Foundation

/// TOTP code generator per RFC 6238 / RFC 4226.
/// Must produce identical output to the web and Android clients.
public enum TotpGenerator {
    /// - Parameters:
    ///   - secret: Base32-encoded secret key
    ///   - algorithm: "SHA1", "SHA256" or "SHA512" (anything else falls back to SHA1, as on Android)
    ///   - timestampSeconds: Unix time in seconds (default: now)
    public static func generate(
        secret: String,
        algorithm: String = "SHA1",
        digits: Int = 6,
        period: Int = 30,
        timestampSeconds: Int64 = Int64(Date().timeIntervalSince1970)
    ) throws -> String {
        let key = SymmetricKey(data: try Base32.decode(secret))
        var counter = UInt64(timestampSeconds / Int64(period)).bigEndian
        let counterBytes = withUnsafeBytes(of: &counter) { Data($0) }

        let hmac: [UInt8]
        switch algorithm.uppercased() {
        case "SHA256": hmac = Array(HMAC<SHA256>.authenticationCode(for: counterBytes, using: key))
        case "SHA512": hmac = Array(HMAC<SHA512>.authenticationCode(for: counterBytes, using: key))
        default: hmac = Array(HMAC<Insecure.SHA1>.authenticationCode(for: counterBytes, using: key))
        }

        // Dynamic truncation (RFC 4226 §5.4)
        let offset = Int(hmac[hmac.count - 1] & 0x0F)
        let code = (UInt32(hmac[offset] & 0x7F) << 24)
            | (UInt32(hmac[offset + 1]) << 16)
            | (UInt32(hmac[offset + 2]) << 8)
            | UInt32(hmac[offset + 3])

        let modulus = (0..<digits).reduce(UInt64(1)) { acc, _ in acc * 10 }
        let value = String(UInt64(code) % modulus)
        return String(repeating: "0", count: max(0, digits - value.count)) + value
    }

    /// Seconds remaining until the current code expires.
    public static func timeRemaining(period: Int = 30, now: Int64 = Int64(Date().timeIntervalSince1970)) -> Int {
        period - Int(now % Int64(period))
    }
}
