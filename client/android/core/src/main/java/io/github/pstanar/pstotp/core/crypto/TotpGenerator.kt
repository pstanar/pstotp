package io.github.pstanar.pstotp.core.crypto

import java.nio.ByteBuffer
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/**
 * TOTP code generator per RFC 6238 / RFC 4226.
 *
 * Generates time-based one-time passwords from a Base32-encoded secret.
 * Must produce identical output to the web client's generateTotp() for interop.
 */
object TotpGenerator {

    /**
     * Generate a TOTP code.
     *
     * @param secret Base32-encoded secret key
     * @param algorithm Hash algorithm: "SHA1", "SHA256", "SHA512"
     * @param digits Number of digits (6 or 8)
     * @param period Time step in seconds (typically 30)
     * @param timestampSeconds Unix timestamp in seconds (default: now)
     * @return Zero-padded TOTP code string
     */
    fun generate(
        secret: String,
        algorithm: String = "SHA1",
        digits: Int = 6,
        period: Int = 30,
        timestampSeconds: Long = System.currentTimeMillis() / 1000,
    ): String {
        val key = Base32.decode(secret)
        val counter = timestampSeconds / period

        // Counter as 8-byte big-endian
        val counterBytes = ByteBuffer.allocate(8).putLong(counter).array()

        // HMAC
        val macAlgorithm = when (algorithm.uppercase()) {
            "SHA1" -> "HmacSHA1"
            "SHA256" -> "HmacSHA256"
            "SHA512" -> "HmacSHA512"
            else -> "HmacSHA1"
        }
        val mac = Mac.getInstance(macAlgorithm)
        mac.init(SecretKeySpec(key, macAlgorithm))
        val hmac = mac.doFinal(counterBytes)

        // Dynamic truncation (RFC 4226 section 5.4)
        val offset = hmac[hmac.size - 1].toInt() and 0x0F
        val code = ((hmac[offset].toInt() and 0x7F) shl 24) or
            ((hmac[offset + 1].toInt() and 0xFF) shl 16) or
            ((hmac[offset + 2].toInt() and 0xFF) shl 8) or
            (hmac[offset + 3].toInt() and 0xFF)

        val modulus = Math.pow(10.0, digits.toDouble()).toLong()
        return (code % modulus).toString().padStart(digits, '0')
    }

    /**
     * Calculate seconds remaining until the current code expires.
     */
    fun timeRemaining(period: Int = 30): Int {
        val now = System.currentTimeMillis() / 1000
        return period - (now % period).toInt()
    }
}
