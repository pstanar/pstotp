package io.github.pstanar.pstotp.core.model.api

import org.json.JSONObject

data class RecoveryRedeemResponse(
    val recoverySessionId: String,
    val requiresWebAuthn: Boolean,
    val releaseEarliestAt: String,
) {
    companion object {
        fun fromJson(json: JSONObject) = RecoveryRedeemResponse(
            recoverySessionId = json.getString("recoverySessionId"),
            requiresWebAuthn = json.optBoolean("requiresWebAuthn", false),
            releaseEarliestAt = json.getString("releaseEarliestAt"),
        )
    }
}

data class RecoveryMaterialResponse(
    val status: String,
    val recoveryEnvelope: Envelope?,
    val replacementDeviceId: String?,
    val releaseEarliestAt: String?,
) {
    companion object {
        fun fromJson(json: JSONObject) = RecoveryMaterialResponse(
            status = json.getString("status"),
            recoveryEnvelope = json.optJSONObject("recoveryEnvelope")?.let { Envelope.fromJson(it) },
            replacementDeviceId = json.optString("replacementDeviceId", null),
            releaseEarliestAt = json.optString("releaseEarliestAt", null),
        )
    }
}
