package io.github.pstanar.pstotp.core.model

import org.json.JSONArray
import org.json.JSONObject

/**
 * One custom icon in the user's library. `data` is a data-URL PNG
 * (the same format `VaultEntryPlaintext.icon` accepts), already
 * normalised to 64×64 at upload time.
 */
data class LibraryIcon(
    val id: String,
    val label: String,
    val data: String,
    val createdAt: String,
) {
    companion object {
        fun fromJson(obj: JSONObject) = LibraryIcon(
            id = obj.getString("id"),
            label = obj.optString("label").ifEmpty { "Icon" },
            data = obj.getString("data"),
            createdAt = obj.optString("createdAt").ifEmpty { "" },
        )
    }

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("label", label)
        put("data", data)
        put("createdAt", createdAt)
    }
}

/**
 * Decrypted icon library. `version` is the blob-format version
 * (distinct from the server's monotonic version tracked alongside
 * the ciphertext). Must match the web client's shape exactly so a
 * blob written on either client decrypts cleanly on the other.
 */
data class IconLibraryBlob(
    val version: Int = 1,
    val icons: List<LibraryIcon> = emptyList(),
) {
    companion object {
        fun fromJsonString(json: String): IconLibraryBlob {
            val obj = JSONObject(json)
            val arr = obj.optJSONArray("icons") ?: JSONArray()
            val icons = (0 until arr.length()).map { i -> LibraryIcon.fromJson(arr.getJSONObject(i)) }
            return IconLibraryBlob(
                version = obj.optInt("version", 1),
                icons = icons,
            )
        }
    }

    fun toJsonString(): String = JSONObject().apply {
        put("version", version)
        put("icons", JSONArray(icons.map { it.toJson() }))
    }.toString()
}

/** Hard cap per user — matches the web client and the server's payload limit. */
const val MAX_LIBRARY_ICONS = 100
