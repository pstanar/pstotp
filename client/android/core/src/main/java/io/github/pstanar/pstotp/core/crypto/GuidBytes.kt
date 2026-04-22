package io.github.pstanar.pstotp.core.crypto

/**
 * Convert a UUID/GUID string to .NET's mixed-endian 16-byte format.
 *
 * .NET GUIDs store the first three groups in little-endian order and the
 * last two groups in big-endian order. This must match the web client's
 * guidToBytes() for client proof computation to be interoperable.
 */
object GuidBytes {

    fun guidToBytes(guid: String): ByteArray {
        val hex = guid.replace("-", "")
        require(hex.length == 32) { "Invalid GUID: $guid" }

        val raw = ByteArray(16)
        for (i in 0 until 16) {
            raw[i] = hex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }

        // .NET mixed-endian: reverse first 4 bytes, bytes 4-5, bytes 6-7
        return byteArrayOf(
            raw[3], raw[2], raw[1], raw[0],  // group 1: little-endian
            raw[5], raw[4],                    // group 2: little-endian
            raw[7], raw[6],                    // group 3: little-endian
            raw[8], raw[9], raw[10], raw[11],  // group 4: big-endian
            raw[12], raw[13], raw[14], raw[15], // group 5: big-endian
        )
    }
}
