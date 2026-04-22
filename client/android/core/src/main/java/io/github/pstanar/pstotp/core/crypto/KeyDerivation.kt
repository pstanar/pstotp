package io.github.pstanar.pstotp.core.crypto

import java.security.MessageDigest
import java.security.SecureRandom

/**
 * Password-based key derivation flow.
 *
 * Matches the web client's crypto module exactly:
 * password → Argon2id(salt) → authKey → HKDF → verifier / envelopeKey
 *
 * Context strings MUST be identical to the web client for interop.
 */
object KeyDerivation {

    private const val AUTH_VERIFIER_CONTEXT = "auth-verifier-v1"
    private const val PASSWORD_ENVELOPE_CONTEXT = "vault-password-envelope-v1"
    private const val RECOVERY_UNLOCK_CONTEXT = "totp-vault-recovery-unlock-v1"
    const val DEVICE_ECDH_KEY_CONTEXT = "device-ecdh-private-key-v1"

    /** Generate a random 16-byte salt for Argon2id. */
    fun generateSalt(): ByteArray {
        val salt = ByteArray(16)
        SecureRandom().nextBytes(salt)
        return salt
    }

    /** Generate a random 32-byte vault key. */
    fun generateVaultKey(): ByteArray {
        val key = ByteArray(32)
        SecureRandom().nextBytes(key)
        return key
    }

    /**
     * Derive the password auth key from password + salt using Argon2id.
     * This is the base key from which verifier and envelope key are derived.
     */
    fun derivePasswordAuthKey(password: String, salt: ByteArray): ByteArray {
        return Argon2.hash(password, salt)
    }

    /** Derive the password verifier (stored for login proof). */
    fun deriveVerifier(authKey: ByteArray): ByteArray {
        return Hkdf.derive(authKey, AUTH_VERIFIER_CONTEXT)
    }

    /** Derive the envelope encryption key (wraps vault key). */
    fun deriveEnvelopeKey(authKey: ByteArray): ByteArray {
        return Hkdf.derive(authKey, PASSWORD_ENVELOPE_CONTEXT)
    }

    /** Derive recovery unlock key from recovery seed. */
    fun deriveRecoveryUnlockKey(recoverySeed: ByteArray): ByteArray {
        return Hkdf.derive(recoverySeed, RECOVERY_UNLOCK_CONTEXT)
    }

    /**
     * Full setup flow: create password → derive keys → encrypt vault key.
     *
     * @return SetupResult with salt, verifier, and encrypted vault key
     */
    fun setupPassword(password: String): SetupResult {
        val salt = generateSalt()
        val vaultKey = generateVaultKey()
        val authKey = derivePasswordAuthKey(password, salt)
        val verifier = deriveVerifier(authKey)
        val envelopeKey = deriveEnvelopeKey(authKey)
        val encryptedVaultKey = AesGcm.encrypt(envelopeKey, vaultKey)

        return SetupResult(
            salt = salt,
            verifier = verifier,
            encryptedVaultKey = encryptedVaultKey,
            vaultKey = vaultKey,
        )
    }

    /**
     * Unlock flow: password → verify → decrypt vault key.
     *
     * @return Vault key bytes, or null if password is wrong
     */
    fun unlockVault(password: String, salt: ByteArray, storedVerifier: ByteArray, encryptedVaultKey: ByteArray): ByteArray? {
        val authKey = derivePasswordAuthKey(password, salt)
        val verifier = deriveVerifier(authKey)

        // Constant-time comparison to prevent timing attacks
        if (!MessageDigest.isEqual(verifier, storedVerifier)) return null

        val envelopeKey = deriveEnvelopeKey(authKey)
        return try {
            AesGcm.decrypt(envelopeKey, encryptedVaultKey)
        } catch (e: Exception) {
            null
        }
    }

    data class SetupResult(
        val salt: ByteArray,
        val verifier: ByteArray,
        val encryptedVaultKey: ByteArray,
        val vaultKey: ByteArray,
    )
}
