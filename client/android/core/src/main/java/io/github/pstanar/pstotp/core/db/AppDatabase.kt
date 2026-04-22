package io.github.pstanar.pstotp.core.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

/**
 * Room database for PsTotp.
 *
 * Stores encrypted vault entries and app settings.
 * The database file itself is NOT encrypted — vault entries contain
 * AES-GCM encrypted payloads that are only decryptable with the vault key.
 */
@Database(
    entities = [VaultEntryEntity::class, SettingsEntity::class, EntryUsageEntity::class],
    version = 3,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun vaultEntryDao(): VaultEntryDao
    abstract fun settingsDao(): SettingsDao
    abstract fun entryUsageDao(): EntryUsageDao

    companion object {
        @Volatile
        private var instance: AppDatabase? = null

        private val MIGRATION_1_2 = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE vault_entries ADD COLUMN entryVersion INTEGER NOT NULL DEFAULT 0")
                db.execSQL("ALTER TABLE vault_entries ADD COLUMN serverUpdatedAt TEXT")
            }
        }

        private val MIGRATION_2_3 = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS entry_usage (" +
                        "entryId TEXT NOT NULL PRIMARY KEY, " +
                        "lastUsedAt INTEGER NOT NULL, " +
                        "useCount INTEGER NOT NULL)",
                )
            }
        }

        fun getInstance(context: Context): AppDatabase {
            return instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "pstotp.db",
                ).addMigrations(MIGRATION_1_2, MIGRATION_2_3).build().also { instance = it }
            }
        }
    }
}
