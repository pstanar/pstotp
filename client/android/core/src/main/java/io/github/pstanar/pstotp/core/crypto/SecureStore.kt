package io.github.pstanar.pstotp.core.crypto

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Keystore-backed encrypted storage for sensitive values that must not
 * be stored in plaintext in the Room database.
 *
 * Used for:
 * - JWT access/refresh tokens (session credentials)
 * - ECDH private key (device identity, must be accessible without vault key)
 */
object SecureStore {

    private const val FILE_NAME = "pstotp_secure_prefs"

    @Volatile
    private var instance: SharedPreferences? = null

    fun getInstance(context: Context): SharedPreferences {
        return instance ?: synchronized(this) {
            val appContext = context.applicationContext
            val masterKey = MasterKey.Builder(appContext)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            instance ?: EncryptedSharedPreferences.create(
                appContext,
                FILE_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            ).also { instance = it }
        }
    }

    // Keys
    const val ACCESS_TOKEN = "access_token"
    const val REFRESH_TOKEN = "refresh_token"
    const val ECDH_PRIVATE_KEY = "ecdh_private_key"
    const val ECDH_PUBLIC_KEY = "ecdh_public_key"

    fun get(context: Context, key: String): String? =
        getInstance(context).getString(key, null)

    fun set(context: Context, key: String, value: String) =
        getInstance(context).edit().putString(key, value).apply()

    fun remove(context: Context, key: String) =
        getInstance(context).edit().remove(key).apply()

    fun clear(context: Context) =
        getInstance(context).edit().clear().apply()
}
