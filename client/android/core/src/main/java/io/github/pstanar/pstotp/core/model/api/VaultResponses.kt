package io.github.pstanar.pstotp.core.model.api

import org.json.JSONObject

/** Null-safe string read: returns null for missing or JSON-null values. */
private fun JSONObject.optStringOrNull(key: String): String? =
    if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }

data class VaultSyncResponse(
    val entries: List<VaultEntryDto>,
    val serverTime: String,
) {
    companion object {
        fun fromJson(json: JSONObject): VaultSyncResponse {
            val array = json.getJSONArray("entries")
            val entries = (0 until array.length()).map { VaultEntryDto.fromJson(array.getJSONObject(it)) }
            return VaultSyncResponse(
                entries = entries,
                serverTime = json.getString("serverTime"),
            )
        }
    }
}

data class VaultEntryDto(
    val id: String,
    val entryPayload: String,
    val entryVersion: Int,
    val deletedAt: String?,
    val updatedAt: String,
    val sortOrder: Int,
) {
    companion object {
        fun fromJson(json: JSONObject) = VaultEntryDto(
            id = json.getString("id"),
            entryPayload = json.getString("entryPayload"),
            entryVersion = json.getInt("entryVersion"),
            deletedAt = json.optString("deletedAt", null),
            updatedAt = json.getString("updatedAt"),
            sortOrder = json.optInt("sortOrder", 0),
        )
    }
}

data class VaultEntryUpsertResponse(
    val id: String,
    val entryVersion: Int,
    val updatedAt: String,
) {
    companion object {
        fun fromJson(json: JSONObject) = VaultEntryUpsertResponse(
            id = json.getString("id"),
            entryVersion = json.getInt("entryVersion"),
            updatedAt = json.getString("updatedAt"),
        )
    }
}

data class DeviceListResponse(
    val devices: List<DeviceInfoDto>,
) {
    companion object {
        fun fromJson(json: JSONObject): DeviceListResponse {
            val array = json.getJSONArray("devices")
            val devices = (0 until array.length()).map { DeviceInfoDto.fromJson(array.getJSONObject(it)) }
            return DeviceListResponse(devices = devices)
        }
    }
}

data class DeviceInfoDto(
    val deviceId: String,
    val deviceName: String,
    val platform: String,
    val status: String,
    val devicePublicKey: String?,
    val approvalRequestId: String?,
    val approvedAt: String?,
    val revokedAt: String?,
) {
    companion object {
        fun fromJson(json: JSONObject) = DeviceInfoDto(
            deviceId = json.getString("deviceId"),
            deviceName = json.getString("deviceName"),
            platform = json.getString("platform"),
            status = json.getString("status"),
            devicePublicKey = json.optStringOrNull("devicePublicKey"),
            approvalRequestId = json.optStringOrNull("approvalRequestId"),
            approvedAt = json.optStringOrNull("approvedAt"),
            revokedAt = json.optStringOrNull("revokedAt"),
        )
    }
}
