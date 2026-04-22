package io.github.pstanar.pstotp.core.model.api

import io.github.pstanar.pstotp.core.util.optStringOrNull
import org.json.JSONObject

data class LoginChallengeResponse(
    val loginSessionId: String,
    val challenge: LoginChallenge,
) {
    companion object {
        fun fromJson(json: JSONObject) = LoginChallengeResponse(
            loginSessionId = json.getString("loginSessionId"),
            challenge = LoginChallenge.fromJson(json.getJSONObject("challenge")),
        )
    }
}

data class LoginChallenge(
    val nonce: String,
    val kdf: KdfConfig,
) {
    companion object {
        fun fromJson(json: JSONObject) = LoginChallenge(
            nonce = json.getString("nonce"),
            kdf = KdfConfig.fromJson(json.getJSONObject("kdf")),
        )
    }
}

data class LoginCompleteResponse(
    val userId: String,
    val accessToken: String?,
    val refreshToken: String?,
    val device: LoginDeviceInfo,
    val envelopes: LoginEnvelopes?,
    val approvalRequestId: String?,
    val role: String?,
    val forcePasswordReset: Boolean,
) {
    companion object {
        fun fromJson(json: JSONObject) = LoginCompleteResponse(
            userId = json.getString("userId"),
            accessToken = json.optStringOrNull("accessToken"),
            refreshToken = json.optStringOrNull("refreshToken"),
            device = LoginDeviceInfo.fromJson(json.getJSONObject("device")),
            envelopes = json.optJSONObject("envelopes")?.let { LoginEnvelopes.fromJson(it) },
            approvalRequestId = json.optStringOrNull("approvalRequestId"),
            role = json.optStringOrNull("role"),
            forcePasswordReset = json.optBoolean("forcePasswordReset", false),
        )
    }
}

data class LoginDeviceInfo(
    val deviceId: String,
    val status: String,
    val persistentKeyAllowed: Boolean,
) {
    companion object {
        fun fromJson(json: JSONObject) = LoginDeviceInfo(
            deviceId = json.getString("deviceId"),
            status = json.getString("status"),
            persistentKeyAllowed = json.optBoolean("persistentKeyAllowed", false),
        )
    }
}

data class LoginEnvelopes(
    val password: Envelope?,
    val device: Envelope?,
) {
    companion object {
        fun fromJson(json: JSONObject) = LoginEnvelopes(
            password = json.optJSONObject("password")?.let { Envelope.fromJson(it) },
            device = json.optJSONObject("device")?.let { Envelope.fromJson(it) },
        )
    }
}

data class BeginRegistrationResponse(
    val registrationSessionId: String,
    val emailVerificationRequired: Boolean,
    val verificationCode: String?,
) {
    companion object {
        fun fromJson(json: JSONObject) = BeginRegistrationResponse(
            registrationSessionId = json.getString("registrationSessionId"),
            emailVerificationRequired = json.getBoolean("emailVerificationRequired"),
            verificationCode = json.optStringOrNull("verificationCode"),
        )
    }
}

data class RegisterResponse(
    val userId: String,
    val deviceId: String,
    val accessToken: String?,
    val refreshToken: String?,
) {
    companion object {
        fun fromJson(json: JSONObject) = RegisterResponse(
            userId = json.getString("userId"),
            deviceId = json.getString("deviceId"),
            accessToken = json.optStringOrNull("accessToken"),
            refreshToken = json.optStringOrNull("refreshToken"),
        )
    }
}

data class RefreshResponse(
    val accessToken: String?,
    val refreshToken: String?,
) {
    companion object {
        fun fromJson(json: JSONObject) = RefreshResponse(
            accessToken = json.optStringOrNull("accessToken"),
            refreshToken = json.optStringOrNull("refreshToken"),
        )
    }
}
