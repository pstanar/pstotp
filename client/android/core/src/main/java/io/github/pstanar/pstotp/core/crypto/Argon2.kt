package io.github.pstanar.pstotp.core.crypto

import com.lambdapioneer.argon2kt.Argon2Kt
import com.lambdapioneer.argon2kt.Argon2Mode

/**
 * Argon2id KDF wrapper with pinned parameters matching the web client.
 *
 * Parameters are non-configurable to ensure interop:
 * - Memory: 64 MB
 * - Iterations: 3
 * - Parallelism: 4
 * - Output: 32 bytes
 */
object Argon2 {
    private const val MEMORY_KB = 64 * 1024  // 64 MB in KB
    private const val ITERATIONS = 3
    private const val PARALLELISM = 4
    private const val HASH_LENGTH = 32

    /**
     * Hash a password with Argon2id.
     *
     * @param password The password string
     * @param salt 16-byte salt
     * @return 32-byte hash
     */
    fun hash(password: String, salt: ByteArray): ByteArray {
        val argon2 = Argon2Kt()
        val result = argon2.hash(
            mode = Argon2Mode.ARGON2_ID,
            password = password.toByteArray(Charsets.UTF_8),
            salt = salt,
            tCostInIterations = ITERATIONS,
            mCostInKibibyte = MEMORY_KB,
            parallelism = PARALLELISM,
            hashLengthInBytes = HASH_LENGTH,
        )
        return result.rawHashAsByteArray()
    }

    // Minimum KDF parameters to prevent server-side downgrade attacks
    private const val MIN_MEMORY_MB = 32
    private const val MIN_ITERATIONS = 2
    private const val MIN_PARALLELISM = 1

    /**
     * Hash a password with Argon2id using server-provided KDF parameters.
     * Enforces minimum floors to prevent a compromised server or MITM
     * from downgrading KDF cost on unauthenticated challenge endpoints.
     */
    fun hash(password: String, salt: ByteArray, memoryMb: Int, iterations: Int, parallelism: Int): ByteArray {
        require(memoryMb >= MIN_MEMORY_MB) { "KDF memoryMb $memoryMb below minimum $MIN_MEMORY_MB" }
        require(iterations >= MIN_ITERATIONS) { "KDF iterations $iterations below minimum $MIN_ITERATIONS" }
        require(parallelism >= MIN_PARALLELISM) { "KDF parallelism $parallelism below minimum $MIN_PARALLELISM" }

        val argon2 = Argon2Kt()
        val result = argon2.hash(
            mode = Argon2Mode.ARGON2_ID,
            password = password.toByteArray(Charsets.UTF_8),
            salt = salt,
            tCostInIterations = iterations,
            mCostInKibibyte = memoryMb * 1024,
            parallelism = parallelism,
            hashLengthInBytes = HASH_LENGTH,
        )
        return result.rawHashAsByteArray()
    }

    /**
     * Hash a recovery code with Argon2id (same parameters).
     * Used for recovery code verification.
     */
    fun hashRecoveryCode(code: String, salt: ByteArray): ByteArray {
        return hash(code, salt)
    }

    /**
     * Verify a recovery code against a stored hash.
     */
    fun verifyRecoveryCode(code: String, salt: ByteArray, expectedHash: ByteArray): Boolean {
        val computed = hashRecoveryCode(code, salt)
        return java.security.MessageDigest.isEqual(computed, expectedHash)
    }
}
