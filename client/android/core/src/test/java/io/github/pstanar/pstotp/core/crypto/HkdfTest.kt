package io.github.pstanar.pstotp.core.crypto

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class HkdfTest {

    @Test
    fun `derive produces 32 bytes by default`() {
        val ikm = ByteArray(32) { it.toByte() }
        val result = Hkdf.derive(ikm, "test-context")
        assertEquals(32, result.size)
    }

    @Test
    fun `derive is deterministic`() {
        val ikm = ByteArray(32) { it.toByte() }
        val result1 = Hkdf.derive(ikm, "test-context")
        val result2 = Hkdf.derive(ikm, "test-context")
        assert(result1.contentEquals(result2))
    }

    @Test
    fun `different contexts produce different keys`() {
        val ikm = ByteArray(32) { it.toByte() }
        val key1 = Hkdf.derive(ikm, "auth-verifier-v1")
        val key2 = Hkdf.derive(ikm, "vault-password-envelope-v1")
        assert(!key1.contentEquals(key2))
    }

    @Test
    fun `different IKM produces different keys`() {
        val ikm1 = ByteArray(32) { 0x01 }
        val ikm2 = ByteArray(32) { 0x02 }
        val key1 = Hkdf.derive(ikm1, "same-context")
        val key2 = Hkdf.derive(ikm2, "same-context")
        assert(!key1.contentEquals(key2))
    }

    @Test
    fun `custom output length works`() {
        val ikm = ByteArray(32) { it.toByte() }
        val result = Hkdf.derive(ikm, "test", 64)
        assertEquals(64, result.size)
    }

    @Test
    fun `hmacSha256 produces 32 bytes`() {
        val key = ByteArray(32) { 0x0B }
        val data = "test message".toByteArray()
        val result = Hkdf.hmacSha256(key, data)
        assertEquals(32, result.size)
    }
}
