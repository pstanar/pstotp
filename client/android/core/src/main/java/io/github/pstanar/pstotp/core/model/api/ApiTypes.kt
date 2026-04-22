package io.github.pstanar.pstotp.core.model.api

import org.json.JSONObject

/** KDF configuration returned by the server in login challenges. */
data class KdfConfig(
    val algorithm: String,
    val memoryMb: Int,
    val iterations: Int,
    val parallelism: Int,
    val salt: String,
) {
    fun toJson() = JSONObject().apply {
        put("algorithm", algorithm)
        put("memoryMb", memoryMb)
        put("iterations", iterations)
        put("parallelism", parallelism)
        put("salt", salt)
    }

    companion object {
        private const val DEFAULT_ALGORITHM = "argon2id"
        private const val DEFAULT_MEMORY_MB = 64
        private const val DEFAULT_ITERATIONS = 3
        private const val DEFAULT_PARALLELISM = 4

        fun fromJson(json: JSONObject) = KdfConfig(
            algorithm = json.getString("algorithm"),
            memoryMb = json.getInt("memoryMb"),
            iterations = json.getInt("iterations"),
            parallelism = json.getInt("parallelism"),
            salt = json.getString("salt"),
        )

        /** Create a default KDF config with the given salt (base64). */
        fun default(saltBase64: String) = KdfConfig(
            algorithm = DEFAULT_ALGORITHM,
            memoryMb = DEFAULT_MEMORY_MB,
            iterations = DEFAULT_ITERATIONS,
            parallelism = DEFAULT_PARALLELISM,
            salt = saltBase64,
        )
    }
}

/** Encrypted envelope (password, device, or recovery). */
data class Envelope(
    val ciphertext: String,
    val nonce: String,
    val version: Int = 1,
) {
    fun toJson() = JSONObject().apply {
        put("ciphertext", ciphertext)
        put("nonce", nonce)
        put("version", version)
    }

    companion object {
        fun fromJson(json: JSONObject) = Envelope(
            ciphertext = json.getString("ciphertext"),
            nonce = json.getString("nonce"),
            version = json.getInt("version"),
        )
    }
}

/** Device info sent to the server during login and registration. */
data class DeviceDto(
    val deviceName: String,
    val platform: String,
    val clientType: String,
    val devicePublicKey: String,
) {
    fun toJson() = JSONObject().apply {
        put("deviceName", deviceName)
        put("platform", platform)
        put("clientType", clientType)
        put("devicePublicKey", devicePublicKey)
    }

    companion object {
        private const val DEVICE_NAME = "PsTotp on Android"
        private const val PLATFORM = "android"
        private const val CLIENT_TYPE = "android"

        /** Build a DeviceDto for this Android device with the given ECDH public key (base64). */
        fun android(publicKeyBase64: String) = DeviceDto(
            deviceName = DEVICE_NAME,
            platform = PLATFORM,
            clientType = CLIENT_TYPE,
            devicePublicKey = publicKeyBase64,
        )
    }
}

/** Password verifier with KDF config, sent during registration. */
data class PasswordVerifierDto(
    val verifier: String,
    val kdf: KdfConfig,
) {
    fun toJson() = JSONObject().apply {
        put("verifier", verifier)
        put("kdf", kdf.toJson())
    }
}

/** Recovery code envelope and hashed codes, sent during registration. */
data class RecoveryDto(
    val recoveryEnvelopeCiphertext: String,
    val recoveryEnvelopeNonce: String,
    val recoveryEnvelopeVersion: Int = 1,
    val recoveryCodeHashes: List<String>,
    val recoveryCodeSalt: String? = null,
) {
    fun toJson() = JSONObject().apply {
        put("recoveryEnvelopeCiphertext", recoveryEnvelopeCiphertext)
        put("recoveryEnvelopeNonce", recoveryEnvelopeNonce)
        put("recoveryEnvelopeVersion", recoveryEnvelopeVersion)
        put("recoveryCodeHashes", org.json.JSONArray(recoveryCodeHashes))
        if (recoveryCodeSalt != null) put("recoveryCodeSalt", recoveryCodeSalt)
    }
}
