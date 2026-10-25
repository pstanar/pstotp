import CryptoKit
import Foundation

/// SHA-256 content fingerprints as lowercase hex. Mirrors the web client's `sha256Hex`.
public enum Hash {
    public static func sha256Hex(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}
