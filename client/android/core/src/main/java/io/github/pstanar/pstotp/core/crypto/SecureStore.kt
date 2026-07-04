package io.github.pstanar.pstotp.core.crypto

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keystore-backed encrypted storage for sensitive values that must not
 * be stored in plaintext in the Room database.
 *
 * Used for:
 * - JWT access/refresh tokens (session credentials)
 * - ECDH private key (device identity, must be accessible without vault key)
 *
 * Values are individually encrypted with an AES-256-GCM key held in the
 * AndroidKeyStore (same pattern as [KeystoreHelper], minus the biometric-auth
 * requirement) rather than via the now-deprecated EncryptedSharedPreferences.
 */
object SecureStore {

    private const val PREFS_FILE = "pstotp_secure_prefs_v2"
    private const val LEGACY_PREFS_FILE = "pstotp_secure_prefs"
    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "pstotp_secure_store_key"
    private const val GCM_TAG_BITS = 128
    private const val GCM_IV_BYTES = 12

    // Keys
    const val ACCESS_TOKEN = "access_token"
    const val REFRESH_TOKEN = "refresh_token"
    const val ECDH_PRIVATE_KEY = "ecdh_private_key"
    const val ECDH_PUBLIC_KEY = "ecdh_public_key"

    private val LEGACY_KEYS = listOf(ACCESS_TOKEN, REFRESH_TOKEN, ECDH_PRIVATE_KEY, ECDH_PUBLIC_KEY)

    @Volatile
    private var migrated = false

    fun get(context: Context, key: String): String? {
        migrateIfNeeded(context)
        val stored = prefs(context).getString(key, null) ?: return null
        return try {
            decrypt(stored)
        } catch (_: Exception) {
            null
        }
    }

    fun set(context: Context, key: String, value: String) = setAll(context, mapOf(key to value))

    /** Atomically write multiple values in one commit (survives a crash mid-write). */
    fun setAll(context: Context, values: Map<String, String>) {
        migrateIfNeeded(context)
        val editor = prefs(context).edit()
        values.forEach { (key, value) -> editor.putString(key, encrypt(value)) }
        editor.commit()
    }

    fun remove(context: Context, key: String) {
        migrateIfNeeded(context)
        prefs(context).edit().remove(key).commit()
    }

    fun clear(context: Context) {
        migrateIfNeeded(context)
        prefs(context).edit().clear().commit()
    }

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)

    private fun encrypt(plaintext: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        }
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(cipher.iv + ciphertext)
    }

    private fun decrypt(stored: String): String {
        val combined = Base64.getDecoder().decode(stored)
        val iv = combined.copyOfRange(0, GCM_IV_BYTES)
        val ciphertext = combined.copyOfRange(GCM_IV_BYTES, combined.size)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, getOrCreateKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        }
        return String(cipher.doFinal(ciphertext), Charsets.UTF_8)
    }

    private fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE_PROVIDER)
        keyGenerator.init(
            KeyGenParameterSpec.Builder(KEY_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return keyGenerator.generateKey()
    }

    /**
     * One-time migration from the deprecated EncryptedSharedPreferences file.
     * Cheap no-op on every call after the first: an empty legacy file is detected
     * without touching MasterKey/Keystore at all.
     */
    private fun migrateIfNeeded(context: Context) {
        if (migrated) return
        synchronized(this) {
            if (migrated) return
            migrated = true

            val appContext = context.applicationContext
            val legacyRaw = appContext.getSharedPreferences(LEGACY_PREFS_FILE, Context.MODE_PRIVATE)
            if (legacyRaw.all.isEmpty()) return

            val legacy = try {
                val masterKey = MasterKey.Builder(appContext)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build()
                EncryptedSharedPreferences.create(
                    appContext,
                    LEGACY_PREFS_FILE,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
                )
            } catch (_: Exception) {
                null
            }

            val values = legacy?.let { store ->
                LEGACY_KEYS.mapNotNull { key -> store.getString(key, null)?.let { key to it } }.toMap()
            } ?: emptyMap()

            if (values.isNotEmpty()) setAll(context, values)
            appContext.deleteSharedPreferences(LEGACY_PREFS_FILE)
        }
    }
}
