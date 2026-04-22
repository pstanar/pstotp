package io.github.pstanar.pstotp.core.crypto

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class EnvelopeHelperTest {

    @Test
    fun `encrypt and decrypt round-trips`() {
        val key = ByteArray(32) { it.toByte() }
        val plaintext = "hello world".toByteArray()

        val envelope = EnvelopeHelper.encrypt(key, plaintext)
        val decrypted = EnvelopeHelper.decrypt(key, envelope)

        assertArrayEquals(plaintext, decrypted)
    }

    @Test
    fun `envelope has non-empty ciphertext and nonce`() {
        val key = ByteArray(32) { 0x42 }
        val plaintext = ByteArray(32) { it.toByte() }

        val envelope = EnvelopeHelper.encrypt(key, plaintext)

        assertNotNull(envelope.ciphertext)
        assertNotNull(envelope.nonce)
        assert(envelope.ciphertext.isNotEmpty())
        assert(envelope.nonce.isNotEmpty())
        assertEquals(1, envelope.version)
    }

    @Test
    fun `fromRaw and toRaw are inverse operations`() {
        val key = ByteArray(32) { 0xAA.toByte() }
        val plaintext = "test data".toByteArray()

        val raw = AesGcm.encrypt(key, plaintext)
        val envelope = EnvelopeHelper.fromRaw(raw)
        val reconstructed = EnvelopeHelper.toRaw(envelope)

        assertArrayEquals(raw, reconstructed)
    }

    @Test
    fun `different plaintexts produce different ciphertexts`() {
        val key = ByteArray(32) { 0x01 }

        val env1 = EnvelopeHelper.encrypt(key, "aaa".toByteArray())
        val env2 = EnvelopeHelper.encrypt(key, "bbb".toByteArray())

        assert(env1.ciphertext != env2.ciphertext)
    }
}
