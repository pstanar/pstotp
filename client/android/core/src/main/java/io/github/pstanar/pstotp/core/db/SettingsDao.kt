package io.github.pstanar.pstotp.core.db

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query

@Dao
interface SettingsDao {

    @Query("SELECT value FROM settings WHERE `key` = :key")
    suspend fun get(key: String): String?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun set(setting: SettingsEntity)

    @Query("DELETE FROM settings WHERE `key` = :key")
    suspend fun delete(key: String)

    /** Check if the app has been set up (has a password verifier). */
    @Query("SELECT COUNT(*) > 0 FROM settings WHERE `key` = 'password_verifier'")
    suspend fun isSetUp(): Boolean
}
