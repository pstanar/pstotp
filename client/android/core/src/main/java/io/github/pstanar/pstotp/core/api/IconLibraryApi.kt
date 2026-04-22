package io.github.pstanar.pstotp.core.api

import org.json.JSONObject

/**
 * Snapshot of the server's icon-library row. `encryptedPayload` is
 * empty and `version` is 0 when the user hasn't written a library yet.
 */
data class IconLibraryResponse(
    val encryptedPayload: String,
    val version: Int,
    val updatedAt: String?,
)

data class IconLibraryUpdateResponse(
    val version: Int,
    val updatedAt: String,
)

class IconLibraryApi(private val client: ApiClient) {

    suspend fun fetch(): IconLibraryResponse =
        client.get("/vault/icon-library") { json ->
            IconLibraryResponse(
                encryptedPayload = json.optString("encryptedPayload", ""),
                version = json.optInt("version", 0),
                updatedAt = json.optString("updatedAt", "").ifEmpty { null },
            )
        }

    suspend fun update(
        encryptedPayload: String,
        expectedVersion: Int,
    ): IconLibraryUpdateResponse {
        val body = JSONObject().apply {
            put("encryptedPayload", encryptedPayload)
            put("expectedVersion", expectedVersion)
        }
        return client.put("/vault/icon-library", body) { json ->
            IconLibraryUpdateResponse(
                version = json.getInt("version"),
                updatedAt = json.getString("updatedAt"),
            )
        }
    }
}
