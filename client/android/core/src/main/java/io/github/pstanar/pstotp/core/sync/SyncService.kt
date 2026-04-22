package io.github.pstanar.pstotp.core.sync

import io.github.pstanar.pstotp.core.api.ApiClient
import io.github.pstanar.pstotp.core.api.ConflictException
import io.github.pstanar.pstotp.core.api.SessionExpiredException
import io.github.pstanar.pstotp.core.api.VaultApi
import io.github.pstanar.pstotp.core.db.AppDatabase
import io.github.pstanar.pstotp.core.db.SettingsEntity
import io.github.pstanar.pstotp.core.db.SettingsKeys
import io.github.pstanar.pstotp.core.db.VaultEntryEntity
import java.util.Base64

/**
 * Vault sync service: pulls server state and pushes local changes.
 *
 * The server's entryPayload (base64) decodes to the same byte format as the
 * local encryptedPayload (nonce || ciphertext+tag, AAD = entry ID). No
 * re-encryption is needed — the vault key is the same across all devices.
 */
class SyncService(
    private val db: AppDatabase,
    private val apiClient: ApiClient,
    private val vaultApi: VaultApi,
    private val repository: io.github.pstanar.pstotp.core.repository.VaultRepository? = null,
) {
    private val entryDao = db.vaultEntryDao()
    private val settingsDao = db.settingsDao()

    /**
     * Full sync: push local changes first, then pull server state.
     * Push-before-pull avoids overwriting local changes with stale server data.
     */
    suspend fun fullSync(): SyncResult {
        if (!apiClient.hasTokens()) return SyncResult.NotConnected

        return try {
            val pushed = pushAllPending()
            val pulled = pullVault()
            SyncResult.Success(pulled = pulled, pushed = pushed)
        } catch (_: SessionExpiredException) {
            SyncResult.SessionExpired
        } catch (e: Exception) {
            SyncResult.Error(e.message ?: "Sync failed")
        }
    }

    /**
     * Pull vault entries from the server and merge into the local database.
     * Returns the number of entries pulled.
     */
    suspend fun pullVault(): Int {
        val response = vaultApi.fetchVault()
        val localEntries = entryDao.getAllIncludingDeleted().associateBy { it.id }

        var pulled = 0

        for (serverEntry in response.entries) {
            val localEntry = localEntries[serverEntry.id]
            val serverPayload = Base64.getDecoder().decode(serverEntry.entryPayload)

            if (serverEntry.deletedAt != null) {
                if (localEntry != null && localEntry.deletedAt == null) {
                    entryDao.softDelete(serverEntry.id)
                }
                continue
            }

            if (localEntry == null) {
                entryDao.upsert(
                    VaultEntryEntity(
                        id = serverEntry.id,
                        encryptedPayload = serverPayload,
                        sortOrder = serverEntry.sortOrder,
                        createdAt = System.currentTimeMillis(),
                        updatedAt = System.currentTimeMillis(),
                        entryVersion = serverEntry.entryVersion,
                        serverUpdatedAt = serverEntry.updatedAt,
                    )
                )
                pulled++
            } else if (serverEntry.entryVersion > localEntry.entryVersion && !localEntry.pendingSync) {
                entryDao.upsert(
                    localEntry.copy(
                        encryptedPayload = serverPayload,
                        sortOrder = serverEntry.sortOrder,
                        updatedAt = System.currentTimeMillis(),
                        entryVersion = serverEntry.entryVersion,
                        serverUpdatedAt = serverEntry.updatedAt,
                        pendingSync = false,
                    )
                )
                pulled++
            }
        }

        settingsDao.set(SettingsEntity(SettingsKeys.LAST_SYNC_AT, response.serverTime))
        return pulled
    }

    /**
     * Push all locally modified entries to the server.
     * Returns the number of entries pushed.
     */
    suspend fun pushAllPending(): Int {
        val pending = entryDao.getPendingSync()
        var pushed = 0

        for (entity in pending) {
            if (pushEntry(entity)) pushed++
        }

        // Push sort order if entries were pushed or reorder is pending
        val reorderPending = repository?.isPendingReorder() == true
        if (pushed > 0 || reorderPending) {
            val allLocal = entryDao.getAll()
            vaultApi.reorderEntries(allLocal.map { it.id })
            repository?.clearPendingReorder()
        }

        return pushed
    }

    /**
     * Push a single entry to the server.
     * Returns true if successfully pushed, false on conflict or error.
     */
    private suspend fun pushEntry(entity: VaultEntryEntity): Boolean {
        val payloadB64 = Base64.getEncoder().encodeToString(entity.encryptedPayload)

        if (entity.deletedAt != null) {
            // Entry was deleted locally — delete on server
            try {
                vaultApi.deleteEntry(entity.id)
                entryDao.hardDelete(entity.id)
            } catch (_: Exception) {
                // Server may not have this entry — that's fine
                entryDao.hardDelete(entity.id)
            }
            return true
        }

        return try {
            val response = vaultApi.upsertEntry(entity.id, payloadB64, entity.entryVersion)
            entryDao.markSynced(entity.id, response.entryVersion, response.updatedAt)
            true
        } catch (_: ConflictException) {
            // Version conflict — server has a newer version.
            // Clear pendingSync so next pull overwrites with server version.
            entryDao.markSynced(entity.id, entity.entryVersion, entity.serverUpdatedAt ?: "")
            false
        }
    }
}

sealed class SyncResult {
    data class Success(val pulled: Int, val pushed: Int = 0) : SyncResult()
    data class Error(val message: String) : SyncResult()
    data object NotConnected : SyncResult()
    data object SessionExpired : SyncResult()
}
