package io.github.pstanar.pstotp.core.db

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Key-value settings store.
 *
 * Used for:
 * - "kdf_salt" — Base64 encoded 16-byte Argon2id salt
 * - "password_verifier" — Base64 encoded 32-byte verifier
 * - "encrypted_vault_key" — Base64 encoded password envelope (nonce || ciphertext || tag)
 * - "lock_timeout_ms" — inactivity lock timeout in milliseconds
 * - "biometric_enabled" — "true" or "false"
 * - "mode" — "standalone" or "connected"
 */
@Entity(tableName = "settings")
data class SettingsEntity(
    @PrimaryKey val key: String,
    val value: String,
)
