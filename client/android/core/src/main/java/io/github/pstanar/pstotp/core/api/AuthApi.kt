package io.github.pstanar.pstotp.core.api

import io.github.pstanar.pstotp.core.model.api.BeginRegistrationResponse
import io.github.pstanar.pstotp.core.model.api.DeviceDto
import io.github.pstanar.pstotp.core.model.api.Envelope
import io.github.pstanar.pstotp.core.model.api.LoginChallengeResponse
import io.github.pstanar.pstotp.core.model.api.LoginCompleteResponse
import io.github.pstanar.pstotp.core.model.api.PasswordVerifierDto
import io.github.pstanar.pstotp.core.model.api.RecoveryDto
import io.github.pstanar.pstotp.core.model.api.RegisterResponse
import org.json.JSONObject

/** Authentication API endpoints (public — no Bearer token). */
class AuthApi(private val client: ApiClient) {

    suspend fun requestLoginChallenge(email: String, device: DeviceDto): LoginChallengeResponse {
        val body = JSONObject().apply {
            put("email", email)
            put("device", device.toJson())
        }
        return client.postPublic("/auth/login", body) { LoginChallengeResponse.fromJson(it) }
    }

    suspend fun completeLogin(loginSessionId: String, clientProof: String): LoginCompleteResponse {
        val body = JSONObject().apply {
            put("loginSessionId", loginSessionId)
            put("clientProof", clientProof)
        }
        return client.postPublic("/auth/login/complete", body) { LoginCompleteResponse.fromJson(it) }
    }

    suspend fun registerBegin(email: String): BeginRegistrationResponse {
        val body = JSONObject().put("email", email)
        return client.postPublic("/auth/register/begin", body) { BeginRegistrationResponse.fromJson(it) }
    }

    suspend fun verifyEmail(registrationSessionId: String, verificationCode: String): Boolean {
        val body = JSONObject().apply {
            put("registrationSessionId", registrationSessionId)
            put("verificationCode", verificationCode)
        }
        return client.postPublic("/auth/register/verify-email", body) { it.getBoolean("verified") }
    }

    suspend fun register(
        registrationSessionId: String?,
        email: String,
        passwordVerifier: PasswordVerifierDto,
        passwordEnvelope: Envelope,
        device: DeviceDto,
        deviceEnvelope: Envelope,
        recovery: RecoveryDto,
    ): RegisterResponse {
        val body = JSONObject().apply {
            if (registrationSessionId != null) put("registrationSessionId", registrationSessionId)
            put("email", email)
            put("passwordVerifier", passwordVerifier.toJson())
            put("passwordEnvelope", passwordEnvelope.toJson())
            put("device", device.toJson())
            put("deviceEnvelope", deviceEnvelope.toJson())
            put("recovery", recovery.toJson())
        }
        return client.postPublic("/auth/register", body) { RegisterResponse.fromJson(it) }
    }

    suspend fun changePassword(
        currentProof: JSONObject,
        newVerifier: JSONObject,
        newPasswordEnvelope: JSONObject,
    ): JSONObject {
        val body = JSONObject().apply {
            put("currentProof", currentProof)
            put("newVerifier", newVerifier)
            put("newPasswordEnvelope", newPasswordEnvelope)
        }
        return client.post("/account/password/change", body) { it }
    }

    suspend fun logout() {
        val body = JSONObject().apply {
            client.refreshToken?.let { put("refreshToken", it) }
        }
        try {
            client.postPublic("/auth/logout", body) { }
        } catch (_: Exception) {
            // Best-effort — server may be unreachable
        }
    }
}
