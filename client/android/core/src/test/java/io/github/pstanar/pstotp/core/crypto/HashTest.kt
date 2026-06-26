package io.github.pstanar.pstotp.core.crypto

import org.junit.Assert.assertEquals
import org.junit.Test

class HashTest {
    @Test
    fun `sha256Hex matches the known digest of abc`() {
        assertEquals(
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            Hash.sha256Hex("abc".toByteArray(Charsets.UTF_8)),
        )
    }

    @Test
    fun `sha256Hex of empty input`() {
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            Hash.sha256Hex(ByteArray(0)),
        )
    }
}
