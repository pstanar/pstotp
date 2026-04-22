package io.github.pstanar.pstotp.core.model

/**
 * Decrypted vault entry, held in memory.
 * Matches the web client's VaultEntry/VaultEntryPlaintext types.
 */
data class VaultEntry(
    val id: String,
    val issuer: String,
    val accountName: String,
    val secret: String,          // Base32-encoded
    val algorithm: String = "SHA1",
    val digits: Int = 6,
    val period: Int = 30,
    val icon: String? = null,    // Emoji or data URL
    val version: Int = 1,
    val sortOrder: Int = 0,
)

/**
 * JSON-serializable plaintext for encryption.
 * The encrypted payload stored in Room is this serialized as JSON → AES-GCM.
 */
data class VaultEntryPlaintext(
    val issuer: String,
    val accountName: String,
    val secret: String,
    val algorithm: String = "SHA1",
    val digits: Int = 6,
    val period: Int = 30,
    val icon: String? = null,
)
