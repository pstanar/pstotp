package io.github.pstanar.pstotp.core.db

/**
 * Constants for settings key-value store.
 * Centralizes all key strings to prevent typos and enable rename refactoring.
 */
object SettingsKeys {
    // Password / vault
    const val KDF_SALT = "kdf_salt"
    const val PASSWORD_VERIFIER = "password_verifier"
    const val ENCRYPTED_VAULT_KEY = "encrypted_vault_key"

    // App mode
    const val MODE = "mode"
    const val MODE_STANDALONE = "standalone"
    const val MODE_CONNECTED = "connected"

    // Server sync
    const val SERVER_URL = "server_url"
    const val ACCESS_TOKEN = "access_token"
    const val REFRESH_TOKEN = "refresh_token"
    const val DEVICE_ID = "device_id"
    const val USER_ID = "user_id"
    const val EMAIL = "email"
    const val LAST_SYNC_AT = "last_sync_at"

    // ECDH device key
    const val DEVICE_ECDH_PUBLIC_KEY = "device_ecdh_public_key"
    const val DEVICE_ECDH_PRIVATE_KEY_ENCRYPTED = "device_ecdh_private_key_encrypted"

    // Biometric
    const val BIOMETRIC_ENABLED = "biometric_enabled"
    const val BIOMETRIC_IV = "biometric_iv"
    const val BIOMETRIC_ENCRYPTED_KEY = "biometric_encrypted_key"

    // Appearance
    const val USE_SYSTEM_COLORS = "use_system_colors"
    // When true, the TOTP card/grid shows a faded preview of the next
    // code during the last 10s, and tapping in the last 3s copies it.
    const val SHOW_NEXT_CODE = "show_next_code"

    // Sort mode
    const val SORT_MODE = "sort_mode"
    const val SORT_REVERSED = "sort_reversed"

    // Layout (list vs grid)
    const val LAYOUT_MODE = "layout_mode"

    // Sync state
    const val PENDING_REORDER = "pending_reorder"

    // Icon library — local-first encrypted blob with last server-ack'd version.
    // Empty (absent) when the user hasn't written a library yet.
    const val ICON_LIBRARY_CIPHERTEXT = "icon_library_ciphertext"         // base64 of nonce||ciphertext||tag
    const val ICON_LIBRARY_SERVER_VERSION = "icon_library_server_version" // int as string; "0" when never pushed
    const val ICON_LIBRARY_DIRTY = "icon_library_dirty"                   // "true" when local has unpushed changes

    // Lock timeout
    const val LOCK_TIMEOUT_MS = "lock_timeout_ms"
    const val DEFAULT_LOCK_TIMEOUT_MS = 5 * 60 * 1000L // 5 minutes
}
