package io.github.pstanar.pstotp.core.crypto

import org.junit.Assert.*
import org.junit.Test

class AesGcmTest {

    @Test
    fun `encrypt and decrypt roundtrip`() {
        val key = ByteArray(32) { it.toByte() }
        val plaintext = "Hello, TOTP!".toByteArray()

        val encrypted = AesGcm.encrypt(key, plaintext)
        val decrypted = AesGcm.decrypt(key, encrypted)

        assertArrayEquals(plaintext, decrypted)
    }

    @Test
    fun `encrypt with associated data roundtrip`() {
        val key = ByteArray(32) { it.toByte() }
        val plaintext = "Secret entry".toByteArray()
        val ad = "entry-id-123".toByteArray()

        val encrypted = AesGcm.encrypt(key, plaintext, ad)
        val decrypted = AesGcm.decrypt(key, encrypted, ad)

        assertArrayEquals(plaintext, decrypted)
    }

    @Test(expected = Exception::class)
    fun `decrypt with wrong AD fails`() {
        val key = ByteArray(32) { it.toByte() }
        val plaintext = "Secret".toByteArray()
        val ad = "correct-id".toByteArray()

        val encrypted = AesGcm.encrypt(key, plaintext, ad)
        AesGcm.decrypt(key, encrypted, "wrong-id".toByteArray())
    }

    @Test(expected = Exception::class)
    fun `decrypt with wrong key fails`() {
        val key1 = ByteArray(32) { it.toByte() }
        val key2 = ByteArray(32) { (it + 1).toByte() }
        val plaintext = "Secret".toByteArray()

        val encrypted = AesGcm.encrypt(key1, plaintext)
        AesGcm.decrypt(key2, encrypted)
    }

    @Test
    fun `payload format is nonce plus ciphertext`() {
        val key = ByteArray(32) { it.toByte() }
        val plaintext = "Test".toByteArray()

        val encrypted = AesGcm.encrypt(key, plaintext)

        // nonce (12) + ciphertext (4) + tag (16) = 32
        assertEquals(12 + plaintext.size + 16, encrypted.size)
    }

    @Test
    fun `each encryption produces different ciphertext`() {
        val key = ByteArray(32) { it.toByte() }
        val plaintext = "Same input".toByteArray()

        val enc1 = AesGcm.encrypt(key, plaintext)
        val enc2 = AesGcm.encrypt(key, plaintext)

        // Different random nonces → different ciphertext
        assertFalse(enc1.contentEquals(enc2))
    }
}
