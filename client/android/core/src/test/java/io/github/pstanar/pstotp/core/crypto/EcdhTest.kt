package io.github.pstanar.pstotp.core.crypto

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class EcdhTest {

    @Test
    fun `generate key pair produces valid keys`() {
        val keyPair = Ecdh.generateKeyPair()
        assertNotNull(keyPair.public)
        assertNotNull(keyPair.private)
    }

    @Test
    fun `export public key produces 65-byte uncompressed point`() {
        val keyPair = Ecdh.generateKeyPair()
        val exported = Ecdh.exportPublicKey(keyPair.public)
        assertEquals(65, exported.size)
        assertEquals(0x04.toByte(), exported[0])
    }

    @Test
    fun `public key round-trips through export and import`() {
        val keyPair = Ecdh.generateKeyPair()
        val exported = Ecdh.exportPublicKey(keyPair.public)
        val imported = Ecdh.importPublicKey(exported)
        val reExported = Ecdh.exportPublicKey(imported)
        assertArrayEquals(exported, reExported)
    }

    @Test
    fun `private key round-trips through export and import`() {
        val keyPair = Ecdh.generateKeyPair()
        val exported = Ecdh.exportPrivateKey(keyPair.private)
        val imported = Ecdh.importPrivateKey(exported)
        val reExported = Ecdh.exportPrivateKey(imported)
        assertArrayEquals(exported, reExported)
    }

    @Test
    fun `ECDH shared secret is symmetric`() {
        val alice = Ecdh.generateKeyPair()
        val bob = Ecdh.generateKeyPair()

        val secretAlice = Ecdh.deriveWrappingKey(alice.private, bob.public)
        val secretBob = Ecdh.deriveWrappingKey(bob.private, alice.public)

        assertArrayEquals(secretAlice, secretBob)
        assertEquals(32, secretAlice.size)
    }

    @Test
    fun `device envelope round-trips pack and unpack`() {
        val deviceKeyPair = Ecdh.generateKeyPair()
        val vaultKey = ByteArray(32) { it.toByte() }

        val envelope = Ecdh.packDeviceEnvelope(vaultKey, deviceKeyPair.public)
        val recovered = Ecdh.unpackDeviceEnvelope(
            envelope.ciphertext,
            envelope.nonce,
            deviceKeyPair.private,
        )

        assertArrayEquals(vaultKey, recovered)
    }

    @Test
    fun `different ephemeral keys produce different ciphertexts`() {
        val deviceKeyPair = Ecdh.generateKeyPair()
        val vaultKey = ByteArray(32) { 0x42 }

        val envelope1 = Ecdh.packDeviceEnvelope(vaultKey, deviceKeyPair.public)
        val envelope2 = Ecdh.packDeviceEnvelope(vaultKey, deviceKeyPair.public)

        // Ephemeral key pairs are random, so ciphertexts should differ
        assert(envelope1.ciphertext != envelope2.ciphertext)

        // Both should still decrypt to the same vault key
        val recovered1 = Ecdh.unpackDeviceEnvelope(envelope1.ciphertext, envelope1.nonce, deviceKeyPair.private)
        val recovered2 = Ecdh.unpackDeviceEnvelope(envelope2.ciphertext, envelope2.nonce, deviceKeyPair.private)
        assertArrayEquals(vaultKey, recovered1)
        assertArrayEquals(vaultKey, recovered2)
    }
}
