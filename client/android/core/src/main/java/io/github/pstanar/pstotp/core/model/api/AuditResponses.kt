package io.github.pstanar.pstotp.core.model.api

import io.github.pstanar.pstotp.core.util.optStringOrNull
import org.json.JSONObject

data class AuditEventDto(
    val id: String,
    val eventType: String,
    val eventData: String?,
    val ipAddress: String?,
    val createdAt: String,
    val deviceId: String?,
) {
    companion object {
        fun fromJson(json: JSONObject) = AuditEventDto(
            id = json.getString("id"),
            eventType = json.getString("eventType"),
            eventData = json.optStringOrNull("eventData"),
            ipAddress = json.optStringOrNull("ipAddress"),
            createdAt = json.getString("createdAt"),
            deviceId = json.optStringOrNull("deviceId"),
        )
    }
}

data class AuditEventListResponse(
    val events: List<AuditEventDto>,
) {
    companion object {
        fun fromJson(json: JSONObject): AuditEventListResponse {
            val array = json.getJSONArray("events")
            val events = (0 until array.length()).map { AuditEventDto.fromJson(array.getJSONObject(it)) }
            return AuditEventListResponse(events = events)
        }
    }
}
