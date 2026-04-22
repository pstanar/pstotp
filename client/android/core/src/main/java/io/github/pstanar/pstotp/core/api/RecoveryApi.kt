package io.github.pstanar.pstotp.core.api

import io.github.pstanar.pstotp.core.model.api.DeviceDto
import io.github.pstanar.pstotp.core.model.api.Envelope
import io.github.pstanar.pstotp.core.model.api.RecoveryDto
import io.github.pstanar.pstotp.core.model.api.RecoveryMaterialResponse
import io.github.pstanar.pstotp.core.model.api.RecoveryRedeemResponse
import org.json.JSONObject

/** Recovery flow API endpoints (public — no Bearer token required). */
class RecoveryApi(private val client: ApiClient) {

    suspend fun redeemRecoveryCode(
        email: String,
        recoveryCode: String,
        verifierProof: JSONObject,
    ): RecoveryRedeemResponse {
        val body = JSONObject().apply {
            put("email", email)
            put("recoveryCode", recoveryCode)
            put("verifierProof", verifierProof)
        }
        return client.postPublic("/recovery/codes/redeem", body) { RecoveryRedeemResponse.fromJson(it) }
    }

    suspend fun getRecoveryMaterial(
        sessionId: String,
        replacementDevice: DeviceDto,
    ): RecoveryMaterialResponse {
        val body = JSONObject().put("replacementDevice", replacementDevice.toJson())
        return client.postPublic("/recovery/session/$sessionId/material", body) {
            RecoveryMaterialResponse.fromJson(it)
        }
    }

    suspend fun regenerateCodes(rotatedRecovery: RecoveryDto) {
        val body = JSONObject().put("rotatedRecovery", rotatedRecovery.toJson())
        client.post("/recovery/codes/regenerate", body) { }
    }

    suspend fun completeRecovery(
        sessionId: String,
        replacementDeviceId: String,
        deviceEnvelope: Envelope,
        rotatedRecovery: RecoveryDto,
    ): org.json.JSONObject {
        val body = JSONObject().apply {
            put("replacementDeviceId", replacementDeviceId)
            put("deviceEnvelope", deviceEnvelope.toJson())
            put("rotatedRecovery", rotatedRecovery.toJson())
        }
        return client.postPublic("/recovery/session/$sessionId/complete", body) { it }
    }
}
