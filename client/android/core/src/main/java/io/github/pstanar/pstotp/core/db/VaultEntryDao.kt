package io.github.pstanar.pstotp.core.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

/**
 * Data access object for vault entries.
 *
 * Flow<> return types emit automatically when data changes (like LiveData/Observable).
 * Suspend functions run on a background thread via coroutines.
 */
@Dao
interface VaultEntryDao {

    /** Observe all non-deleted entries ordered by sort order. */
    @Query("SELECT * FROM vault_entries WHERE deletedAt IS NULL ORDER BY sortOrder ASC")
    fun observeAll(): Flow<List<VaultEntryEntity>>

    /** Get all non-deleted entries (one-shot). */
    @Query("SELECT * FROM vault_entries WHERE deletedAt IS NULL ORDER BY sortOrder ASC")
    suspend fun getAll(): List<VaultEntryEntity>

    /** Get a single entry by ID. */
    @Query("SELECT * FROM vault_entries WHERE id = :id")
    suspend fun getById(id: String): VaultEntryEntity?

    /** Insert or replace an entry. */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entry: VaultEntryEntity)

    /** Update an existing entry. */
    @Update
    suspend fun update(entry: VaultEntryEntity)

    /** Soft-delete an entry. */
    @Query("UPDATE vault_entries SET deletedAt = :timestamp, updatedAt = :timestamp WHERE id = :id")
    suspend fun softDelete(id: String, timestamp: Long = System.currentTimeMillis())

    /** Hard-delete an entry (for cleanup). */
    @Query("DELETE FROM vault_entries WHERE id = :id")
    suspend fun hardDelete(id: String)

    /** Get the max sort order (for placing new entries at the end). */
    @Query("SELECT MAX(sortOrder) FROM vault_entries WHERE deletedAt IS NULL")
    suspend fun getMaxSortOrder(): Int?

    /** Update sort orders for reordering. */
    @Query("UPDATE vault_entries SET sortOrder = :sortOrder WHERE id = :id")
    suspend fun updateSortOrder(id: String, sortOrder: Int)

    // --- Sync support ---

    /** Get all entries including soft-deleted (for sync merge). */
    @Query("SELECT * FROM vault_entries ORDER BY sortOrder ASC")
    suspend fun getAllIncludingDeleted(): List<VaultEntryEntity>

    /** Get entries queued for server sync. */
    @Query("SELECT * FROM vault_entries WHERE pendingSync = 1")
    suspend fun getPendingSync(): List<VaultEntryEntity>

    /** Mark an entry as synced with the server. */
    @Query("UPDATE vault_entries SET pendingSync = 0, entryVersion = :version, serverUpdatedAt = :serverUpdatedAt WHERE id = :id")
    suspend fun markSynced(id: String, version: Int, serverUpdatedAt: String)

    /** Mark an entry as needing sync. */
    @Query("UPDATE vault_entries SET pendingSync = 1 WHERE id = :id")
    suspend fun markPendingSync(id: String)
}
