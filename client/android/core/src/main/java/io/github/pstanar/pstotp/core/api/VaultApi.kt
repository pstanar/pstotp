package io.github.pstanar.pstotp.core.api

import io.github.pstanar.pstotp.core.model.api.VaultEntryUpsertResponse
import io.github.pstanar.pstotp.core.model.api.VaultSyncResponse
import org.json.JSONArray
import org.json.JSONObject

/** Vault sync API endpoints (authenticated — requires Bearer token). */
class VaultApi(private val client: ApiClient) {

    suspend fun fetchVault(): VaultSyncResponse =
        client.get("/vault") { VaultSyncResponse.fromJson(it) }

    suspend fun upsertEntry(
        entryId: String,
        entryPayload: String,
        entryVersion: Int,
    ): VaultEntryUpsertResponse {
        val body = JSONObject().apply {
            put("entryPayload", entryPayload)
            put("entryVersion", entryVersion)
        }
        return client.put("/vault/$entryId", body) { VaultEntryUpsertResponse.fromJson(it) }
    }

    suspend fun deleteEntry(entryId: String) {
        client.delete("/vault/$entryId")
    }

    suspend fun reorderEntries(entryIds: List<String>) {
        val body = JSONObject().apply {
            put("entryIds", JSONArray(entryIds))
        }
        client.post("/vault/reorder", body) { }
    }
}
