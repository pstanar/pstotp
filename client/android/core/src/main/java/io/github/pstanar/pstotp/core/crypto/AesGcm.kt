package io.github.pstanar.pstotp.core.crypto

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-256-GCM encryption/decryption.
 *
 * Payload format: [nonce (12 bytes)] [ciphertext + auth tag (16 bytes)]
 * Must match the web client's aesGcmEncrypt/aesGcmDecrypt for interop.
 */
object AesGcm {
    private const val NONCE_SIZE = 12
    private const val TAG_SIZE_BITS = 128  // 16 bytes
    private const val KEY_SIZE = 32         // 256 bits

    /**
     * Encrypt plaintext with AES-256-GCM.
     *
     * @param key 32-byte encryption key
     * @param plaintext Data to encrypt
     * @param associatedData Optional AAD (e.g., entry ID as UTF-8 bytes)
     * @return nonce || ciphertext || tag
     */
    fun encrypt(key: ByteArray, plaintext: ByteArray, associatedData: ByteArray? = null): ByteArray {
        require(key.size == KEY_SIZE) { "Key must be $KEY_SIZE bytes" }

        val nonce = ByteArray(NONCE_SIZE)
        SecureRandom().nextBytes(nonce)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_SIZE_BITS, nonce))
        if (associatedData != null) {
            cipher.updateAAD(associatedData)
        }
        val ciphertextAndTag = cipher.doFinal(plaintext)

        // Prepend nonce: nonce || ciphertext || tag
        return nonce + ciphertextAndTag
    }

    /**
     * Decrypt an AES-256-GCM payload.
     *
     * @param key 32-byte decryption key
     * @param payload nonce || ciphertext || tag
     * @param associatedData Optional AAD (must match what was used during encryption)
     * @return Decrypted plaintext
     */
    fun decrypt(key: ByteArray, payload: ByteArray, associatedData: ByteArray? = null): ByteArray {
        require(key.size == KEY_SIZE) { "Key must be $KEY_SIZE bytes" }
        require(payload.size > NONCE_SIZE) { "Payload too short" }

        val nonce = payload.copyOfRange(0, NONCE_SIZE)
        val ciphertextAndTag = payload.copyOfRange(NONCE_SIZE, payload.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_SIZE_BITS, nonce))
        if (associatedData != null) {
            cipher.updateAAD(associatedData)
        }
        return cipher.doFinal(ciphertextAndTag)
    }
}
