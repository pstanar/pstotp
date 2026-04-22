package io.github.pstanar.pstotp.core.api

import io.github.pstanar.pstotp.core.model.api.DeviceDto
import io.github.pstanar.pstotp.core.model.api.LoginCompleteResponse
import io.github.pstanar.pstotp.core.model.api.WebAuthnBeginResponse
import io.github.pstanar.pstotp.core.model.api.WebAuthnCredentialInfo
import org.json.JSONObject

/** WebAuthn/passkey API endpoints. */
class WebAuthnApi(private val client: ApiClient) {

    // --- Registration (authenticated) ---

    suspend fun beginRegistration(): WebAuthnBeginResponse =
        client.post("/webauthn/register/begin", null) { WebAuthnBeginResponse.fromJson(it) }

    suspend fun completeRegistration(
        ceremonyId: String,
        friendlyName: String,
        attestationResponseJson: String,
    ) {
        val body = JSONObject().apply {
            put("ceremonyId", ceremonyId)
            put("friendlyName", friendlyName)
            put("attestationResponse", JSONObject(attestationResponseJson))
        }
        client.post("/webauthn/register/complete", body) { }
    }

    // --- Assertion (public — login or recovery step-up) ---

    suspend fun beginAssertion(
        email: String? = null,
        recoverySessionId: String? = null,
    ): WebAuthnBeginResponse {
        val body = JSONObject().apply {
            if (email != null) put("email", email)
            if (recoverySessionId != null) put("recoverySessionId", recoverySessionId)
        }
        return client.postPublic("/webauthn/assert/begin", body) { WebAuthnBeginResponse.fromJson(it) }
    }

    suspend fun completeAssertionForLogin(
        ceremonyId: String,
        assertionResponseJson: String,
        device: DeviceDto,
    ): LoginCompleteResponse {
        val body = JSONObject().apply {
            put("ceremonyId", ceremonyId)
            put("assertionResponse", JSONObject(assertionResponseJson))
            put("device", device.toJson())
        }
        return client.postPublic("/webauthn/assert/complete", body) { LoginCompleteResponse.fromJson(it) }
    }

    suspend fun completeAssertionForRecovery(
        ceremonyId: String,
        assertionResponseJson: String,
    ) {
        val body = JSONObject().apply {
            put("ceremonyId", ceremonyId)
            put("assertionResponse", JSONObject(assertionResponseJson))
        }
        client.postPublic("/webauthn/assert/complete", body) { }
    }

    // --- Credential management (authenticated) ---

    suspend fun listCredentials(): List<WebAuthnCredentialInfo> =
        client.get("/webauthn/credentials") { json ->
            val arr = json.getJSONArray("credentials")
            (0 until arr.length()).map { WebAuthnCredentialInfo.fromJson(arr.getJSONObject(it)) }
        }

    suspend fun renameCredential(credentialId: String, friendlyName: String) {
        val body = JSONObject().put("friendlyName", friendlyName)
        client.put("/webauthn/credentials/$credentialId/rename", body) { }
    }

    suspend fun revokeCredential(credentialId: String) {
        client.post("/webauthn/credentials/$credentialId/revoke", null) { }
    }
}
