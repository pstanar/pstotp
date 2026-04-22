package io.github.pstanar.pstotp.core.db

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.Query

@Entity(tableName = "entry_usage")
data class EntryUsageEntity(
    @PrimaryKey val entryId: String,
    val lastUsedAt: Long,
    val useCount: Int,
)

@Dao
interface EntryUsageDao {
    @Query("SELECT * FROM entry_usage")
    suspend fun getAll(): List<EntryUsageEntity>

    @Query(
        "INSERT INTO entry_usage (entryId, lastUsedAt, useCount) VALUES (:entryId, :now, 1) " +
            "ON CONFLICT(entryId) DO UPDATE SET lastUsedAt = :now, useCount = useCount + 1",
    )
    suspend fun recordUse(entryId: String, now: Long)

    @Query("DELETE FROM entry_usage WHERE entryId = :entryId")
    suspend fun delete(entryId: String)
}
