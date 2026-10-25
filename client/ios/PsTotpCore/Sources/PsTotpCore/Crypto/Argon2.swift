import CArgon2
import CryptoKit
import Foundation

/// Argon2id KDF wrapper with pinned parameters matching the web and Android clients.
///
/// - Memory: 64 MB, Iterations: 3, Parallelism: 4, Output: 32 bytes
public enum Argon2 {
    private static let memoryKb = 64 * 1024
    private static let iterations = 3
    private static let parallelism = 4
    private static let hashLength = 32

    // Minimum KDF parameters to prevent server-side downgrade attacks.
    private static let minMemoryMb = 32
    private static let minIterations = 2
    private static let minParallelism = 1

    public static func hash(password: String, salt: Data) throws -> Data {
        try run(password: password, salt: salt, memoryKb: memoryKb, iterations: iterations, parallelism: parallelism)
    }

    /// Hash with server-provided KDF parameters, enforcing the minimum floors.
    public static func hash(password: String, salt: Data, memoryMb: Int, iterations: Int, parallelism: Int) throws -> Data {
        guard memoryMb >= minMemoryMb else {
            throw CryptoError.kdfParameterBelowMinimum("memoryMb \(memoryMb) below minimum \(minMemoryMb)")
        }
        guard iterations >= minIterations else {
            throw CryptoError.kdfParameterBelowMinimum("iterations \(iterations) below minimum \(minIterations)")
        }
        guard parallelism >= minParallelism else {
            throw CryptoError.kdfParameterBelowMinimum("parallelism \(parallelism) below minimum \(minParallelism)")
        }
        return try run(password: password, salt: salt, memoryKb: memoryMb * 1024, iterations: iterations, parallelism: parallelism)
    }

    public static func hashRecoveryCode(_ code: String, salt: Data) throws -> Data {
        try hash(password: code, salt: salt)
    }

    public static func verifyRecoveryCode(_ code: String, salt: Data, expectedHash: Data) throws -> Bool {
        let computed = try hashRecoveryCode(code, salt: salt)
        return constantTimeEquals(computed, expectedHash)
    }

    private static func run(password: String, salt: Data, memoryKb: Int, iterations: Int, parallelism: Int) throws -> Data {
        var out = [UInt8](repeating: 0, count: hashLength)
        let pwd = Array(password.utf8)
        let salt = [UInt8](salt)
        let code = argon2id_hash_raw(
            UInt32(iterations), UInt32(memoryKb), UInt32(parallelism),
            pwd, pwd.count, salt, salt.count, &out, out.count)
        guard code == ARGON2_OK.rawValue else {
            throw CryptoError.kdfFailed(String(cString: argon2_error_message(code)))
        }
        return Data(out)
    }
}

/// Constant-time equality (the counterpart of `MessageDigest.isEqual`).
func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for (x, y) in zip(a, b) { diff |= x ^ y }
    return diff == 0
}
