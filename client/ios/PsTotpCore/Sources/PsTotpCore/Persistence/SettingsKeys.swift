import Foundation

/// Constants for the settings key-value store. Keys match the Android client's `SettingsKeys`.
public enum SettingsKeys {
    // Password / vault
    public static let kdfSalt = "kdf_salt"
    public static let passwordVerifier = "password_verifier"
    public static let encryptedVaultKey = "encrypted_vault_key"

    // App mode
    public static let mode = "mode"
    public static let modeStandalone = "standalone"
    public static let modeConnected = "connected"

    // Server sync
    public static let serverUrl = "server_url"
    public static let accessToken = "access_token"
    public static let refreshToken = "refresh_token"
    public static let deviceId = "device_id"
    public static let userId = "user_id"
    public static let email = "email"
    public static let lastSyncAt = "last_sync_at"

    // ECDH device key
    public static let deviceEcdhPublicKey = "device_ecdh_public_key"
    public static let deviceEcdhPrivateKeyEncrypted = "device_ecdh_private_key_encrypted"

    // Biometric
    public static let biometricEnabled = "biometric_enabled"
    public static let biometricIv = "biometric_iv"
    public static let biometricEncryptedKey = "biometric_encrypted_key"

    // Appearance
    public static let useSystemColors = "use_system_colors"
    /// When true, the TOTP card/grid shows a faded preview of the next code during the last 10s.
    public static let showNextCode = "show_next_code"

    // Sort mode / layout
    public static let sortMode = "sort_mode"
    public static let sortReversed = "sort_reversed"
    public static let layoutMode = "layout_mode"

    // Sync state
    public static let pendingReorder = "pending_reorder"

    // Icon library — local-first encrypted blob with last server-ack'd version.
    public static let iconLibraryCiphertext = "icon_library_ciphertext"
    public static let iconLibraryServerVersion = "icon_library_server_version"
    public static let iconLibraryDirty = "icon_library_dirty"

    // Lock timeout
    public static let lockTimeoutMs = "lock_timeout_ms"
    public static let defaultLockTimeoutMs: Int64 = 5 * 60 * 1000
}
