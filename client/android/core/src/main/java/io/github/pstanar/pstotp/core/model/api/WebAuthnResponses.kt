package io.github.pstanar.pstotp.core.model.api

import org.json.JSONObject

data class WebAuthnBeginResponse(
    val ceremonyId: String,
    val publicKeyOptionsJson: String,
) {
    companion object {
        fun fromJson(json: JSONObject) = WebAuthnBeginResponse(
            ceremonyId = json.getString("ceremonyId"),
            publicKeyOptionsJson = json.getJSONObject("publicKeyOptions").toString(),
        )
    }
}

data class WebAuthnCredentialInfo(
    val id: String,
    val friendlyName: String?,
    val createdAt: String,
    val lastUsedAt: String?,
) {
    companion object {
        fun fromJson(json: JSONObject) = WebAuthnCredentialInfo(
            id = json.getString("id"),
            friendlyName = if (json.isNull("friendlyName")) null else json.getString("friendlyName"),
            createdAt = json.getString("createdAt"),
            lastUsedAt = if (json.isNull("lastUsedAt")) null else json.getString("lastUsedAt"),
        )
    }
}
