package io.github.pstanar.pstotp.core.crypto

import java.security.MessageDigest

/**
 * SHA-256 content fingerprints as lowercase hex. Used for icon-library
 * de-duplication (hashing raw source bytes and resized data-URLs) — not a
 * secret-handling primitive, just a stable content hash. Mirrors the web
 * client's `sha256Hex` so both clients produce identical hashes for the
 * same bytes.
 */
object Hash {
    private val HEX = "0123456789abcdef".toCharArray()

    fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        val sb = StringBuilder(digest.size * 2)
        for (b in digest) {
            val v = b.toInt() and 0xff
            sb.append(HEX[v ushr 4])
            sb.append(HEX[v and 0x0f])
        }
        return sb.toString()
    }
}
