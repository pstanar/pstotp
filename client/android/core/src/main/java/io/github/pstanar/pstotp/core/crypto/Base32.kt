package io.github.pstanar.pstotp.core.crypto

/**
 * Base32 encoding/decoding (RFC 4648).
 * Used for TOTP secret keys which are stored as Base32 strings.
 */
object Base32 {
    private const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    fun decode(input: String): ByteArray {
        val cleaned = input.uppercase().replace("=", "").replace(" ", "").replace("-", "")
        if (cleaned.isEmpty()) return ByteArray(0)

        val output = ByteArray(cleaned.length * 5 / 8)
        var buffer = 0
        var bitsLeft = 0
        var outputIndex = 0

        for (c in cleaned) {
            val value = ALPHABET.indexOf(c)
            if (value < 0) throw IllegalArgumentException("Invalid Base32 character: $c")

            buffer = (buffer shl 5) or value
            bitsLeft += 5

            if (bitsLeft >= 8) {
                bitsLeft -= 8
                output[outputIndex++] = (buffer shr bitsLeft).toByte()
                buffer = buffer and ((1 shl bitsLeft) - 1)
            }
        }

        return output.copyOf(outputIndex)
    }

    fun encode(input: ByteArray): String {
        if (input.isEmpty()) return ""

        val sb = StringBuilder()
        var buffer = 0
        var bitsLeft = 0

        for (b in input) {
            buffer = (buffer shl 8) or (b.toInt() and 0xFF)
            bitsLeft += 8

            while (bitsLeft >= 5) {
                bitsLeft -= 5
                sb.append(ALPHABET[(buffer shr bitsLeft) and 0x1F])
                buffer = buffer and ((1 shl bitsLeft) - 1)
            }
        }

        if (bitsLeft > 0) {
            sb.append(ALPHABET[(buffer shl (5 - bitsLeft)) and 0x1F])
        }

        return sb.toString()
    }
}
