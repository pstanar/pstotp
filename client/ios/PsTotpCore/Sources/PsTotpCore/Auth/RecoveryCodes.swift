import Foundation

/// One-time recovery codes shown at registration.
public enum RecoveryCodes {
    public static let count = 8
    public static let length = 10
    /// No I, O, 0 or 1 — easy to misread when copied by hand.
    public static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func generate() -> [String] {
        var rng = SystemRandomNumberGenerator()
        return (0..<count).map { _ in
            String((0..<length).map { _ in alphabet.randomElement(using: &rng)! })
        }
    }
}
