package io.github.pstanar.pstotp.core.repository

import io.github.pstanar.pstotp.core.api.ApiException
import io.github.pstanar.pstotp.core.api.IconLibraryApi
import io.github.pstanar.pstotp.core.crypto.IconLibraryCrypto
import io.github.pstanar.pstotp.core.db.AppDatabase
import io.github.pstanar.pstotp.core.db.SettingsEntity
import io.github.pstanar.pstotp.core.db.SettingsKeys
import io.github.pstanar.pstotp.core.model.IconLibraryBlob
import io.github.pstanar.pstotp.core.model.LibraryIcon
import io.github.pstanar.pstotp.core.model.MAX_LIBRARY_ICONS
import java.util.Base64
import java.util.UUID

/**
 * Local-first icon library:
 *   - Blob persists in SettingsDao as ciphertext so the on-disk shape
 *     matches what's on the server (same AEAD, same AD, same bytes).
 *   - In standalone mode the library lives only on this device.
 *   - In connected mode every mutation writes through to the server via
 *     [pushIfDirty]. If the server is unreachable the local change
 *     sticks and a dirty flag is set; next successful push catches up.
 *   - On sign-in / sync the caller invokes [pullFromServer] to adopt
 *     the server's copy; any local unpushed changes can be pushed
 *     afterwards (last-write-wins per project policy).
 */
class IconLibraryRepository(db: AppDatabase) {

    private val settingsDao = db.settingsDao()

    /** Read + decrypt the local blob. Returns empty when no library exists yet. */
    suspend fun loadLocal(vaultKey: ByteArray): IconLibraryBlob {
        val cipherB64 = settingsDao.get(SettingsKeys.ICON_LIBRARY_CIPHERTEXT)
            ?: return IconLibraryBlob()
        if (cipherB64.isEmpty()) return IconLibraryBlob()
        return try {
            val payload = Base64.getDecoder().decode(cipherB64)
            IconLibraryCrypto.decrypt(vaultKey, payload)
        } catch (_: Exception) {
            // Wrong key / corrupted blob — treat as empty rather than crashing.
            // The caller should surface a warning if this matters.
            IconLibraryBlob()
        }
    }

    /** Current server-acknowledged version, or 0 if the library hasn't been pushed. */
    suspend fun getServerVersion(): Int =
        settingsDao.get(SettingsKeys.ICON_LIBRARY_SERVER_VERSION)?.toIntOrNull() ?: 0

    suspend fun hasUnpushedChanges(): Boolean =
        settingsDao.get(SettingsKeys.ICON_LIBRARY_DIRTY) == "true"

    /**
     * Encrypt [icons] and write the ciphertext to local settings,
     * marking the library dirty. If [api] is supplied, push to the
     * server immediately; on 409 refetch + retry once, matching the
     * web client's last-write-wins policy. Returns the updated blob
     * after the operation.
     */
    suspend fun save(
        vaultKey: ByteArray,
        icons: List<LibraryIcon>,
        api: IconLibraryApi? = null,
    ): IconLibraryBlob {
        val blob = IconLibraryBlob(version = 1, icons = icons)
        val payload = IconLibraryCrypto.encrypt(vaultKey, blob)
        val payloadB64 = Base64.getEncoder().encodeToString(payload)

        settingsDao.set(SettingsEntity(SettingsKeys.ICON_LIBRARY_CIPHERTEXT, payloadB64))
        settingsDao.set(SettingsEntity(SettingsKeys.ICON_LIBRARY_DIRTY, "true"))

        if (api != null) {
            runCatching { pushCiphertext(api, payloadB64) }
                // Push failure (network, 5xx, etc.) — local stays dirty, next
                // successful push catches up. Don't throw: the mutation still
                // succeeded locally from the user's point of view.
        }
        return blob
    }

    /**
     * Fetch the server's copy and replace local with it. Intended to
     * run on sign-in and/or sync. Returns the adopted blob.
     */
    suspend fun pullFromServer(vaultKey: ByteArray, api: IconLibraryApi): IconLibraryBlob {
        val response = api.fetch()
        if (response.version == 0 || response.encryptedPayload.isEmpty()) {
            // Server has nothing yet — if we have local content, leave it
            // alone (it'll get pushed next save); otherwise just return empty.
            return loadLocal(vaultKey)
        }
        settingsDao.set(SettingsEntity(SettingsKeys.ICON_LIBRARY_CIPHERTEXT, response.encryptedPayload))
        settingsDao.set(SettingsEntity(SettingsKeys.ICON_LIBRARY_SERVER_VERSION, response.version.toString()))
        settingsDao.set(SettingsEntity(SettingsKeys.ICON_LIBRARY_DIRTY, "false"))
        return loadLocal(vaultKey)
    }

    /**
     * Push local changes if the dirty flag is set. Safe to call opportunistically
     * (e.g. after reconnecting, after a manual sync). Returns true when a push
     * actually happened.
     */
    suspend fun pushIfDirty(api: IconLibraryApi): Boolean {
        if (!hasUnpushedChanges()) return false
        val cipherB64 = settingsDao.get(SettingsKeys.ICON_LIBRARY_CIPHERTEXT) ?: return false
        if (cipherB64.isEmpty()) return false
        pushCiphertext(api, cipherB64)
        return true
    }

    /**
     * Drop local state. Called on vault lock so the in-memory + on-disk
     * ciphertext stops shadowing the real data once the key is gone.
     * We don't actually remove the ciphertext — it's useless without
     * the vault key anyway, and keeping it avoids a round-trip to the
     * server on next unlock.
     */
    suspend fun clearDirtyFlag() {
        settingsDao.set(SettingsEntity(SettingsKeys.ICON_LIBRARY_DIRTY, "false"))
    }

    /**
     * Internal: PUT with the current server version; on 409 refetch the
     * current version and retry once. On success records the new
     * version and clears the dirty flag.
     */
    private suspend fun pushCiphertext(api: IconLibraryApi, payloadB64: String) {
        val v1 = getServerVersion()
        val result = try {
            api.update(payloadB64, v1)
        } catch (e: Exception) {
            if (!isVersionConflict(e)) throw e
            val fresh = api.fetch()
            api.update(payloadB64, fresh.version)
        }
        settingsDao.set(SettingsEntity(SettingsKeys.ICON_LIBRARY_SERVER_VERSION, result.version.toString()))
        settingsDao.set(SettingsEntity(SettingsKeys.ICON_LIBRARY_DIRTY, "false"))
    }

    private fun isVersionConflict(e: Exception): Boolean =
        e is ApiException && e.statusCode == 409

    companion object {
        /** Generate a fresh library-icon id. Intentionally small wrapper so
         *  callers don't need to know we're using UUIDs. */
        fun newIconId(): String = UUID.randomUUID().toString()

        /** Hard cap — matches MAX_LIBRARY_ICONS in the model. */
        const val MAX_ICONS = MAX_LIBRARY_ICONS
    }
}
