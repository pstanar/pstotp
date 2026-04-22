package io.github.pstanar.pstotp.core.crypto

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Manages a biometric-bound AES-256-GCM key in the Android Keystore.
 *
 * The key requires BIOMETRIC_STRONG authentication each time it is used.
 * Used to wrap/unwrap the vault key so that biometric unlock can retrieve it
 * without the user entering their password.
 */
object KeystoreHelper {

    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "pstotp_biometric_vault_key"
    private const val GCM_TAG_BITS = 128

    /**
     * Generate a new biometric-bound AES-256-GCM key.
     * Overwrites any existing key with the same alias.
     */
    fun generateKey() {
        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER,
        )
        keyGenerator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setUserAuthenticationRequired(true)
                .setInvalidatedByBiometricEnrollment(true)
                .build()
        )
        keyGenerator.generateKey()
    }

    /** Check whether a biometric key exists and is still valid. */
    fun hasValidKey(): Boolean {
        return try {
            val key = getKey() ?: return false
            // Test that the key hasn't been invalidated (e.g. by new biometric enrollment)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, key)
            true
        } catch (_: KeyPermanentlyInvalidatedException) {
            deleteKey()
            false
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Get a Cipher in ENCRYPT mode for wrapping the vault key.
     * Must be passed to BiometricPrompt as a CryptoObject.
     * After biometric auth succeeds, use the authenticated cipher to encrypt.
     */
    fun getEncryptCipher(): Cipher {
        val key = getKey() ?: throw IllegalStateException("Biometric key not found")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        return cipher
    }

    /**
     * Get a Cipher in DECRYPT mode for unwrapping the vault key.
     * Must be passed to BiometricPrompt as a CryptoObject.
     * After biometric auth succeeds, use the authenticated cipher to decrypt.
     *
     * @param iv The IV from the original encryption (stored alongside the wrapped key)
     */
    fun getDecryptCipher(iv: ByteArray): Cipher {
        val key = getKey() ?: throw IllegalStateException("Biometric key not found")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(GCM_TAG_BITS, iv))
        return cipher
    }

    /** Delete the biometric key. */
    fun deleteKey() {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)
        if (keyStore.containsAlias(KEY_ALIAS)) {
            keyStore.deleteEntry(KEY_ALIAS)
        }
    }

    private fun getKey(): SecretKey? {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER)
        keyStore.load(null)
        return keyStore.getKey(KEY_ALIAS, null) as? SecretKey
    }
}
