package io.github.pstanar.pstotp.core.crypto

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class KeyDerivationTest {

    @Test
    fun `generateSalt produces 16 bytes`() {
        val salt = KeyDerivation.generateSalt()
        assertEquals(16, salt.size)
    }

    @Test
    fun `generateVaultKey produces 32 bytes`() {
        val key = KeyDerivation.generateVaultKey()
        assertEquals(32, key.size)
    }

    @Test
    fun `generateSalt produces unique values`() {
        val salt1 = KeyDerivation.generateSalt()
        val salt2 = KeyDerivation.generateSalt()
        assert(!salt1.contentEquals(salt2))
    }

    @Test
    fun `deriveVerifier produces 32 bytes`() {
        val authKey = ByteArray(32) { it.toByte() }
        val verifier = KeyDerivation.deriveVerifier(authKey)
        assertEquals(32, verifier.size)
    }

    @Test
    fun `deriveEnvelopeKey produces 32 bytes`() {
        val authKey = ByteArray(32) { it.toByte() }
        val key = KeyDerivation.deriveEnvelopeKey(authKey)
        assertEquals(32, key.size)
    }

    @Test
    fun `verifier and envelope key differ for same auth key`() {
        val authKey = ByteArray(32) { it.toByte() }
        val verifier = KeyDerivation.deriveVerifier(authKey)
        val envelopeKey = KeyDerivation.deriveEnvelopeKey(authKey)
        assert(!verifier.contentEquals(envelopeKey))
    }

    @Test
    fun `deriveRecoveryUnlockKey produces 32 bytes`() {
        val authKey = ByteArray(32) { it.toByte() }
        val key = KeyDerivation.deriveRecoveryUnlockKey(authKey)
        assertEquals(32, key.size)
    }

    @Test
    fun `DEVICE_ECDH_KEY_CONTEXT is defined`() {
        assertNotNull(KeyDerivation.DEVICE_ECDH_KEY_CONTEXT)
        assert(KeyDerivation.DEVICE_ECDH_KEY_CONTEXT.isNotEmpty())
    }
}
