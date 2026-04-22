package io.github.pstanar.pstotp.core.api

import io.github.pstanar.pstotp.core.model.api.DeviceListResponse
import io.github.pstanar.pstotp.core.model.api.Envelope
import org.json.JSONObject

/** Device management API endpoints (authenticated). */
class DevicesApi(private val client: ApiClient) {

    suspend fun fetchDevices(): DeviceListResponse =
        client.get("/devices") { DeviceListResponse.fromJson(it) }

    suspend fun approveDevice(
        deviceId: String,
        approvalRequestId: String,
        deviceEnvelope: Envelope,
    ) {
        val body = JSONObject().apply {
            put("approvalRequestId", approvalRequestId)
            put("approvalAuth", JSONObject().put("type", "device"))
            put("deviceEnvelope", deviceEnvelope.toJson())
        }
        client.post("/devices/$deviceId/approve", body) { }
    }

    suspend fun rejectDevice(deviceId: String) {
        client.post("/devices/$deviceId/reject", null) { }
    }

    suspend fun revokeDevice(deviceId: String) {
        client.post("/devices/$deviceId/revoke", null) { }
    }

    suspend fun updateSelfEnvelope(envelope: Envelope) {
        client.put("/devices/self/envelope", envelope.toJson()) { }
    }
}
