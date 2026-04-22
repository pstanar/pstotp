package io.github.pstanar.pstotp.core.db

import androidx.room.Entity
import androidx.room.PrimaryKey

/**
 * Encrypted vault entry stored in Room/SQLite.
 *
 * The encryptedPayload contains: nonce(12) || ciphertext || tag(16)
 * Decrypted contents are JSON-serialized VaultEntryPlaintext.
 * Associated data for AES-GCM is the entry ID as UTF-8 string.
 */
@Entity(tableName = "vault_entries")
data class VaultEntryEntity(
    @PrimaryKey val id: String,
    val encryptedPayload: ByteArray,
    val sortOrder: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
    val deletedAt: Long? = null,
    val pendingSync: Boolean = false,
    val entryVersion: Int = 0,         // Server version (0 = never synced)
    val serverUpdatedAt: String? = null, // Server's updatedAt ISO timestamp
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is VaultEntryEntity) return false
        return id == other.id
    }

    override fun hashCode(): Int = id.hashCode()
}
