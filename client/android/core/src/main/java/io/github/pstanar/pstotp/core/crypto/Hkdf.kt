package io.github.pstanar.pstotp.core.crypto

import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * HKDF-SHA256 key derivation (RFC 5869).
 *
 * Used with context strings for domain separation:
 * - "auth-verifier-v1" → password verifier
 * - "vault-password-envelope-v1" → envelope encryption key
 * - "totp-vault-recovery-unlock-v1" → recovery unlock key
 * - "device-envelope-v1" → ECDH device envelope key
 *
 * Must match the web client's hkdfDerive() — NO salt, context string as info.
 */
object Hkdf {

    /**
     * Derive a key using HKDF-SHA256.
     *
     * @param ikm Input key material
     * @param info Context string for domain separation
     * @param length Output length in bytes (default 32)
     * @return Derived key bytes
     */
    fun derive(ikm: ByteArray, info: String, length: Int = 32): ByteArray {
        // HKDF-Extract: PRK = HMAC-SHA256(salt, IKM)
        // Salt is empty (matching web client)
        val salt = ByteArray(32) // zero-filled = default salt per RFC 5869
        val prk = hmacSha256(salt, ikm)

        // HKDF-Expand: OKM = T(1) || T(2) || ...
        val infoBytes = info.toByteArray(Charsets.UTF_8)
        val n = (length + 31) / 32  // ceiling division
        var t = ByteArray(0)
        val okm = ByteArray(length)
        var offset = 0

        for (i in 1..n) {
            val input = t + infoBytes + byteArrayOf(i.toByte())
            t = hmacSha256(prk, input)
            val copyLen = minOf(t.size, length - offset)
            System.arraycopy(t, 0, okm, offset, copyLen)
            offset += copyLen
        }

        return okm
    }

    internal fun hmacSha256(key: ByteArray, data: ByteArray): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(key, "HmacSHA256"))
        return mac.doFinal(data)
    }
}
