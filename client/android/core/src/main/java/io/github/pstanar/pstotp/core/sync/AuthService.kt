package io.github.pstanar.pstotp.core.sync

import io.github.pstanar.pstotp.core.api.AuthApi
import io.github.pstanar.pstotp.core.api.ApiClient
import io.github.pstanar.pstotp.core.crypto.AesGcm
import io.github.pstanar.pstotp.core.crypto.Argon2
import io.github.pstanar.pstotp.core.crypto.ClientProof
import io.github.pstanar.pstotp.core.crypto.Ecdh
import io.github.pstanar.pstotp.core.crypto.EnvelopeHelper
import io.github.pstanar.pstotp.core.crypto.KeystoreHelper
import io.github.pstanar.pstotp.core.crypto.SecureStore
import androidx.room.withTransaction
import io.github.pstanar.pstotp.core.db.AppDatabase
import io.github.pstanar.pstotp.core.db.SettingsEntity
import io.github.pstanar.pstotp.core.db.SettingsKeys
import io.github.pstanar.pstotp.core.crypto.KeyDerivation
import io.github.pstanar.pstotp.core.api.RecoveryApi
import io.github.pstanar.pstotp.core.api.WebAuthnApi
import io.github.pstanar.pstotp.core.model.api.DeviceDto
import io.github.pstanar.pstotp.core.model.api.LoginCompleteResponse
import io.github.pstanar.pstotp.core.model.api.LoginEnvelopes
import io.github.pstanar.pstotp.core.model.api.Envelope
import io.github.pstanar.pstotp.core.model.api.KdfConfig
import io.github.pstanar.pstotp.core.model.api.PasswordVerifierDto
import io.github.pstanar.pstotp.core.model.api.RecoveryDto
import io.github.pstanar.pstotp.core.model.api.RecoveryMaterialResponse
import io.github.pstanar.pstotp.core.model.api.RecoveryRedeemResponse
import java.security.KeyPair
import java.security.PrivateKey
import java.security.SecureRandom
import java.util.Base64

/**
 * Orchestrates server authentication: login, token storage, ECDH key management.
 *
 * Login flow:
 * 1. Generate/load ECDH key pair
 * 2. Request login challenge (nonce + KDF config)
 * 3. Derive password verifier via Argon2id + HKDF
 * 4. Compute client proof (HMAC-SHA256)
 * 5. Complete login → receive tokens + envelopes
 * 6. Decrypt vault key from envelope
 */
class AuthService(
    private val context: android.content.Context,
    private val db: AppDatabase,
    private val apiClient: ApiClient,
    private val authApi: AuthApi,
) {
    private val settingsDao = db.settingsDao()

    /** Write multiple settings atomically inside a Room transaction. */
    private suspend fun persistSettings(vararg entries: SettingsEntity) {
        db.withTransaction {
            for (entry in entries) settingsDao.set(entry)
        }
    }

    /**
     * Persist the session metadata that every successful (or intermediate)
     * auth flow writes: server URL + user/device IDs + email, plus a MODE
     * when the flow is fully connected. Pass `mode = null` for intermediate
     * states (pending approval, need password) where the flow isn't yet
     * fully CONNECTED.
     */
    private suspend fun persistSession(
        serverUrl: String,
        userId: String,
        deviceId: String,
        email: String,
        mode: String? = SettingsKeys.MODE_CONNECTED,
    ) {
        val entries = buildList {
            add(SettingsEntity(SettingsKeys.SERVER_URL, serverUrl))
            add(SettingsEntity(SettingsKeys.USER_ID, userId))
            add(SettingsEntity(SettingsKeys.DEVICE_ID, deviceId))
            add(SettingsEntity(SettingsKeys.EMAIL, email))
            if (mode != null) add(SettingsEntity(SettingsKeys.MODE, mode))
        }
        persistSettings(*entries.toTypedArray())
    }

    /**
     * Persist the local password envelope (KDF_SALT, PASSWORD_VERIFIER,
     * ENCRYPTED_VAULT_KEY) so future offline password unlocks return
     * exactly this vaultKey. Clears any previously-enrolled biometric by
     * default since its Keystore-wrapped copy of the old key would silently
     * disagree with the new one.
     *
     * `clearBiometric = false` is only correct when the vault key itself is
     * unchanged (e.g. password change where only the password-derived wrapper
     * is rotated). Any flow that *replaces* the vault key must clear biometric.
     */
    private suspend fun persistPasswordEnvelope(
        salt: ByteArray,
        authKey: ByteArray,
        vaultKey: ByteArray,
        clearBiometric: Boolean = true,
    ) {
        val verifier = KeyDerivation.deriveVerifier(authKey)
        val envelopeKey = KeyDerivation.deriveEnvelopeKey(authKey)
        val localEncryptedVaultKey = AesGcm.encrypt(envelopeKey, vaultKey)
        persistSettings(
            SettingsEntity(SettingsKeys.KDF_SALT, Base64.getEncoder().encodeToString(salt)),
            SettingsEntity(SettingsKeys.PASSWORD_VERIFIER, Base64.getEncoder().encodeToString(verifier)),
            SettingsEntity(SettingsKeys.ENCRYPTED_VAULT_KEY, Base64.getEncoder().encodeToString(localEncryptedVaultKey)),
        )
        if (clearBiometric) disableBiometricMaterial()
    }

    /**
     * Clear any previously enrolled biometric material. Called after the vault
     * key we store locally is replaced by a key pulled from the server, since
     * a stale Keystore-wrapped key would decrypt to the old key and silently
     * break entry decryption after a local biometric unlock.
     */
    private suspend fun disableBiometricMaterial() {
        try { KeystoreHelper.deleteKey() } catch (_: Exception) { /* key may not exist */ }
        persistSettings(
            SettingsEntity(SettingsKeys.BIOMETRIC_ENABLED, "false"),
            SettingsEntity(SettingsKeys.BIOMETRIC_IV, ""),
            SettingsEntity(SettingsKeys.BIOMETRIC_ENCRYPTED_KEY, ""),
        )
    }

    /** Write both tokens atomically to SecureStore and update in-memory client. */
    private fun persistTokens(accessToken: String, refreshToken: String) {
        apiClient.setTokens(accessToken, refreshToken)
        // commit() for synchronous write — tokens must survive a crash
        SecureStore.getInstance(context).edit()
            .putString(SecureStore.ACCESS_TOKEN, accessToken)
            .putString(SecureStore.REFRESH_TOKEN, refreshToken)
            .commit()
    }

    suspend fun isConnected(): Boolean =
        settingsDao.get(SettingsKeys.MODE) == SettingsKeys.MODE_CONNECTED && SecureStore.get(context, SecureStore.ACCESS_TOKEN) != null

    suspend fun getServerUrl(): String? = settingsDao.get(SettingsKeys.SERVER_URL)

    /**
     * Log in to the server and retrieve the vault key.
     *
     * @param serverUrl Base URL (e.g., "https://totp.example.com/api")
     * @param email User's email
     * @param password User's password
     * @param localVaultKey Current local vault key (for ECDH key encryption)
     * @return LoginResult with status and vault key from server
     */
    suspend fun login(
        serverUrl: String,
        email: String,
        password: String,
        localVaultKey: ByteArray,
    ): LoginResult {
        apiClient.baseUrl = serverUrl.trimEnd('/')

        // Load or generate ECDH key pair
        val ecdhKeyPair = loadOrGenerateEcdhKeyPair()
        val publicKeyBytes = Ecdh.exportPublicKey(ecdhKeyPair.public)
        val publicKeyB64 = Base64.getEncoder().encodeToString(publicKeyBytes)

        val device = DeviceDto.android(publicKeyB64)

        // Step 1: Request login challenge
        val challenge = authApi.requestLoginChallenge(email, device)
        val kdf = challenge.challenge.kdf
        val nonce = Base64.getDecoder().decode(challenge.challenge.nonce)
        val salt = Base64.getDecoder().decode(kdf.salt)

        // Step 2: Derive auth key using server's KDF config
        val authKey = Argon2.hash(password, salt, kdf.memoryMb, kdf.iterations, kdf.parallelism)

        // Step 3: Derive verifier and compute proof
        val verifier = KeyDerivation.deriveVerifier(authKey)
        val proof = ClientProof.compute(verifier, nonce, challenge.loginSessionId)
        val proofB64 = Base64.getEncoder().encodeToString(proof)

        // Step 4: Complete login
        val result = authApi.completeLogin(challenge.loginSessionId, proofB64)

        // Step 5: Store tokens atomically in SecureStore (Keystore-backed)
        if (result.accessToken != null && result.refreshToken != null) {
            persistTokens(result.accessToken, result.refreshToken)
        }

        // Step 6: Handle device status
        if (result.device.status == "pending") {
            persistSession(serverUrl, result.userId, result.device.deviceId, email, mode = null)
            return LoginResult.PendingApproval(result.approvalRequestId ?: result.device.deviceId)
        }

        // Step 7: Decrypt vault key from envelopes
        val serverVaultKey = decryptVaultKey(result.envelopes, authKey, ecdhKeyPair.private)
            ?: return LoginResult.Error("No envelope available to decrypt vault key")

        persistSession(serverUrl, result.userId, result.device.deviceId, email)

        // Adopt the server's vault key locally so offline password/biometric
        // unlocks unwrap to the same key that sync'd entries are encrypted
        // with. When joining an existing account from a device that had its
        // own local vault, the server returns a different key than local setup.
        persistPasswordEnvelope(salt, authKey, serverVaultKey)

        // Rebuild device envelope for future passkey/device logins
        rebuildDeviceEnvelope(serverVaultKey, ecdhKeyPair)

        return LoginResult.Approved(serverVaultKey)
    }

    // --- Passkey login ---

    val webAuthnApi = WebAuthnApi(apiClient)

    /**
     * Complete a passkey login after the Credential Manager ceremony.
     *
     * Unlike password login, passkey login has no authKey, so the vault key
     * can only come from the ECDH device envelope. If only the password
     * envelope is available, returns NeedPassword so the UI can prompt.
     *
     * @param serverUrl Base URL
     * @param email User's email (used to persist settings)
     * @param assertionResponseJson JSON from Credential Manager getPasskey()
     * @return PasskeyLoginResult with the outcome
     */
    suspend fun passkeyLogin(
        serverUrl: String,
        email: String,
        assertionResponseJson: String,
        ceremonyId: String,
    ): PasskeyLoginResult {
        apiClient.baseUrl = serverUrl.trimEnd('/')

        val ecdhKeyPair = loadOrGenerateEcdhKeyPair()
        val publicKeyBytes = Ecdh.exportPublicKey(ecdhKeyPair.public)
        val device = DeviceDto.android(Base64.getEncoder().encodeToString(publicKeyBytes))

        val result = webAuthnApi.completeAssertionForLogin(ceremonyId, assertionResponseJson, device)

        // Store tokens
        if (result.accessToken != null && result.refreshToken != null) {
            persistTokens(result.accessToken, result.refreshToken)
        }

        // Device pending — needs approval from an existing device
        if (result.device.status == "pending") {
            persistSession(serverUrl, result.userId, result.device.deviceId, email, mode = null)
            return PasskeyLoginResult.PendingApproval(result.approvalRequestId ?: result.device.deviceId)
        }

        // Try device envelope (ECDH — no password needed)
        val deviceVaultKey = result.envelopes?.device?.let { envelope ->
            try {
                Ecdh.unpackDeviceEnvelope(envelope.ciphertext, envelope.nonce, ecdhKeyPair.private)
            } catch (_: Exception) { null }
        }

        if (deviceVaultKey != null) {
            persistSession(serverUrl, result.userId, result.device.deviceId, email)
            rebuildDeviceEnvelope(deviceVaultKey, ecdhKeyPair)
            return PasskeyLoginResult.Approved(deviceVaultKey)
        }

        // No device envelope — need password to decrypt password envelope
        if (result.envelopes?.password != null) {
            // Persist partial state so unlockWithPassword can complete
            persistSession(serverUrl, result.userId, result.device.deviceId, email, mode = null)
            return PasskeyLoginResult.NeedPassword(result.envelopes, result.userId, result.device.deviceId)
        }

        return PasskeyLoginResult.Error("No envelope available to decrypt vault key")
    }

    /**
     * Complete passkey login when user provides password for password envelope decryption.
     * Called after PasskeyLoginResult.NeedPassword.
     */
    suspend fun passkeyUnlockWithPassword(
        serverUrl: String,
        email: String,
        password: String,
        envelopes: LoginEnvelopes,
        userId: String,
        deviceId: String,
    ): PasskeyLoginResult {
        apiClient.baseUrl = serverUrl.trimEnd('/')

        val ecdhKeyPair = loadOrGenerateEcdhKeyPair()
        val publicKeyBytes = Ecdh.exportPublicKey(ecdhKeyPair.public)
        val device = DeviceDto.android(Base64.getEncoder().encodeToString(publicKeyBytes))

        // Get KDF config from server
        val challenge = authApi.requestLoginChallenge(email, device)
        val kdf = challenge.challenge.kdf
        val salt = Base64.getDecoder().decode(kdf.salt)

        val authKey = Argon2.hash(password, salt, kdf.memoryMb, kdf.iterations, kdf.parallelism)
        val envelopeKey = KeyDerivation.deriveEnvelopeKey(authKey)

        val vaultKey = try {
            EnvelopeHelper.decrypt(envelopeKey, envelopes.password!!)
        } catch (_: Exception) {
            return PasskeyLoginResult.Error("Incorrect password")
        }

        persistSession(serverUrl, userId, deviceId, email)
        persistPasswordEnvelope(salt, authKey, vaultKey)
        rebuildDeviceEnvelope(vaultKey, ecdhKeyPair)
        return PasskeyLoginResult.Approved(vaultKey)
    }

    /**
     * Complete the WebAuthn step-up during recovery.
     * Called after getting "webauthn_required" from getRecoveryMaterial.
     */
    suspend fun recoveryWebAuthnStepUp(
        serverUrl: String,
        ceremonyId: String,
        assertionResponseJson: String,
    ) {
        apiClient.baseUrl = serverUrl.trimEnd('/')
        webAuthnApi.completeAssertionForRecovery(ceremonyId, assertionResponseJson)
    }

    /**
     * Register a new account on the server.
     *
     * Generates all cryptographic material: vault key, password verifier,
     * password envelope, device envelope, recovery codes + envelope.
     *
     * @return RegistrationResult with recovery codes to display to the user
     */
    suspend fun register(
        serverUrl: String,
        email: String,
        password: String,
        registrationSessionId: String?,
    ): RegistrationResult {
        apiClient.baseUrl = serverUrl.trimEnd('/')

        // Generate vault key and salt
        val vaultKey = KeyDerivation.generateVaultKey()
        val salt = KeyDerivation.generateSalt()

        // Derive password material
        val authKey = KeyDerivation.derivePasswordAuthKey(password, salt)
        val verifier = KeyDerivation.deriveVerifier(authKey)
        val envelopeKey = KeyDerivation.deriveEnvelopeKey(authKey)

        val kdfConfig = KdfConfig.default(Base64.getEncoder().encodeToString(salt))

        val passwordVerifier = PasswordVerifierDto(
            verifier = Base64.getEncoder().encodeToString(verifier),
            kdf = kdfConfig,
        )

        // Password envelope: encrypt vault key with envelope key
        val passwordEnvelope = EnvelopeHelper.encrypt(envelopeKey, vaultKey)

        // ECDH device envelope
        val ecdhKeyPair = Ecdh.generateKeyPair()
        val publicKeyBytes = Ecdh.exportPublicKey(ecdhKeyPair.public)
        val deviceEnvelopeParts = Ecdh.packDeviceEnvelope(vaultKey, ecdhKeyPair.public)
        val deviceEnvelope = Envelope(deviceEnvelopeParts.ciphertext, deviceEnvelopeParts.nonce)

        val device = DeviceDto.android(Base64.getEncoder().encodeToString(publicKeyBytes))

        // Recovery codes with independent salt (not tied to password KDF salt)
        val recoveryCodeSalt = KeyDerivation.generateSalt()
        val recoveryCodes = (1..RECOVERY_CODE_COUNT).map { generateRecoveryCode() }
        val codeHashes = recoveryCodes.map { code ->
            Base64.getEncoder().encodeToString(Argon2.hashRecoveryCode(code, recoveryCodeSalt))
        }

        // Recovery envelope: encrypt vault key with recovery-derived key
        // Recovery envelope encrypted with password-derived key so recovery can decrypt
        // using the same password (proven via step-up auth during recovery flow)
        val recoveryUnlockKey = KeyDerivation.deriveRecoveryUnlockKey(authKey)
        val recoveryEnv = EnvelopeHelper.encrypt(recoveryUnlockKey, vaultKey)
        val recovery = RecoveryDto(
            recoveryEnvelopeCiphertext = recoveryEnv.ciphertext,
            recoveryEnvelopeNonce = recoveryEnv.nonce,
            recoveryCodeHashes = codeHashes,
            recoveryCodeSalt = Base64.getEncoder().encodeToString(recoveryCodeSalt),
        )

        // Call server
        val result = authApi.register(
            registrationSessionId = registrationSessionId,
            email = email,
            passwordVerifier = passwordVerifier,
            passwordEnvelope = passwordEnvelope,
            device = device,
            deviceEnvelope = deviceEnvelope,
            recovery = recovery,
        )

        // Store tokens atomically
        if (result.accessToken != null && result.refreshToken != null) {
            persistTokens(result.accessToken, result.refreshToken)
        }

        persistSession(serverUrl, result.userId, result.deviceId, email)
        persistPasswordEnvelope(salt, authKey, vaultKey)

        // Persist ECDH key pair
        persistEcdhKeyPair(ecdhKeyPair)

        return RegistrationResult(
            vaultKey = vaultKey,
            recoveryCodes = recoveryCodes,
        )
    }

    /**
     * Change password on the server.
     *
     * Requires step-up authentication: a fresh login challenge + proof using the
     * current password, then sends the new verifier and password envelope.
     */
    suspend fun changePassword(
        email: String,
        currentPassword: String,
        newPassword: String,
        vaultKey: ByteArray,
    ): ChangePasswordResult {
        // Load ECDH key pair for device info
        val ecdhKeyPair = loadOrGenerateEcdhKeyPair()
        val publicKeyBytes = Ecdh.exportPublicKey(ecdhKeyPair.public)

        val device = DeviceDto.android(Base64.getEncoder().encodeToString(publicKeyBytes))

        // Step 1: Get fresh challenge for step-up auth with current password
        val challenge = authApi.requestLoginChallenge(email, device)
        val kdf = challenge.challenge.kdf
        val nonce = Base64.getDecoder().decode(challenge.challenge.nonce)
        val salt = Base64.getDecoder().decode(kdf.salt)

        val currentAuthKey = Argon2.hash(currentPassword, salt, kdf.memoryMb, kdf.iterations, kdf.parallelism)
        val currentVerifier = KeyDerivation.deriveVerifier(currentAuthKey)
        val proof = ClientProof.compute(currentVerifier, nonce, challenge.loginSessionId)

        val currentProof = org.json.JSONObject().apply {
            put("loginSessionId", challenge.loginSessionId)
            put("clientProof", Base64.getEncoder().encodeToString(proof))
        }

        // Step 2: Derive new password material
        val newSalt = KeyDerivation.generateSalt()
        val newAuthKey = KeyDerivation.derivePasswordAuthKey(newPassword, newSalt)
        val newVerifier = KeyDerivation.deriveVerifier(newAuthKey)
        val newEnvelopeKey = KeyDerivation.deriveEnvelopeKey(newAuthKey)

        val newKdfConfig = KdfConfig.default(Base64.getEncoder().encodeToString(newSalt))

        val newVerifierDto = org.json.JSONObject().apply {
            put("verifier", Base64.getEncoder().encodeToString(newVerifier))
            put("kdf", newKdfConfig.toJson())
        }

        val newEnvelope = EnvelopeHelper.encrypt(newEnvelopeKey, vaultKey).toJson()

        // Step 3: Call server
        val response = authApi.changePassword(currentProof, newVerifierDto, newEnvelope)

        // Step 4: Persist local password material FIRST (must succeed before tokens update)
        // If this fails after the server accepted the change, offline unlock would be
        // out of sync. By writing credentials before tokens, we ensure the critical
        // path completes atomically before updating the session.
        // vault key is UNCHANGED by password change, only the password-derived
        // wrapper rotates — so biometric (which wraps the raw key) stays valid.
        persistPasswordEnvelope(newSalt, newAuthKey, vaultKey, clearBiometric = false)

        // Step 5: Now safe to update tokens
        val newAccessToken = if (response.isNull("accessToken")) null else response.getString("accessToken")
        val newRefreshToken = if (response.isNull("refreshToken")) null else response.getString("refreshToken")
        if (newAccessToken != null && newRefreshToken != null) {
            persistTokens(newAccessToken, newRefreshToken)
        }

        // Re-encrypt ECDH private key with new vault key
        persistEcdhKeyPair(ecdhKeyPair)

        return ChangePasswordResult.Success
    }

    // --- Recovery ---

    private val recoveryApi = RecoveryApi(apiClient)

    /**
     * Step 1: Redeem a recovery code. Proves password knowledge via step-up auth.
     * Returns the recovery session ID and hold period info.
     */
    suspend fun redeemRecoveryCode(
        serverUrl: String,
        email: String,
        password: String,
        recoveryCode: String,
    ): RecoveryRedeemResponse {
        apiClient.baseUrl = serverUrl.trimEnd('/')

        // Use persisted ECDH key pair for consistent device identity across recovery steps
        val ecdhKeyPair = loadOrGenerateEcdhKeyPair()
        val publicKeyBytes = Ecdh.exportPublicKey(ecdhKeyPair.public)
        val device = DeviceDto.android(Base64.getEncoder().encodeToString(publicKeyBytes))

        val challenge = authApi.requestLoginChallenge(email, device)
        val kdf = challenge.challenge.kdf
        val nonce = Base64.getDecoder().decode(challenge.challenge.nonce)
        val salt = Base64.getDecoder().decode(kdf.salt)

        val authKey = Argon2.hash(password, salt, kdf.memoryMb, kdf.iterations, kdf.parallelism)
        val verifier = KeyDerivation.deriveVerifier(authKey)
        val proof = ClientProof.compute(verifier, nonce, challenge.loginSessionId)

        val verifierProof = org.json.JSONObject().apply {
            put("loginSessionId", challenge.loginSessionId)
            put("clientProof", Base64.getEncoder().encodeToString(proof))
        }

        return recoveryApi.redeemRecoveryCode(email, recoveryCode, verifierProof)
    }

    /**
     * Step 2: Check if recovery material is ready (after hold period).
     * Uses the persisted ECDH key pair so the replacement device identity
     * matches what completeRecovery will use.
     */
    suspend fun getRecoveryMaterial(
        serverUrl: String,
        sessionId: String,
    ): RecoveryMaterialResponse {
        apiClient.baseUrl = serverUrl.trimEnd('/')

        val ecdhKeyPair = loadOrGenerateEcdhKeyPair()
        val publicKeyBytes = Ecdh.exportPublicKey(ecdhKeyPair.public)
        val device = DeviceDto.android(Base64.getEncoder().encodeToString(publicKeyBytes))

        return recoveryApi.getRecoveryMaterial(sessionId, device)
    }

    /**
     * Step 3: Complete recovery — decrypt vault key from recovery envelope,
     * generate new recovery codes, create replacement device.
     */
    suspend fun completeRecovery(
        serverUrl: String,
        email: String,
        password: String,
        sessionId: String,
        recoveryEnvelope: Envelope,
        replacementDeviceId: String,
    ): RecoveryResult {
        apiClient.baseUrl = serverUrl.trimEnd('/')

        // Use the SAME persisted ECDH key pair that getRecoveryMaterial registered
        val ecdhKeyPair = loadOrGenerateEcdhKeyPair()
        val publicKeyBytes = Ecdh.exportPublicKey(ecdhKeyPair.public)
        val device = DeviceDto.android(Base64.getEncoder().encodeToString(publicKeyBytes))

        // Get KDF config from server to derive authKey
        val challenge = authApi.requestLoginChallenge(email, device)
        val kdf = challenge.challenge.kdf
        val salt = Base64.getDecoder().decode(kdf.salt)

        val authKey = Argon2.hash(password, salt, kdf.memoryMb, kdf.iterations, kdf.parallelism)
        val recoveryUnlockKey = KeyDerivation.deriveRecoveryUnlockKey(authKey)

        // Decrypt recovery envelope
        val vaultKey = EnvelopeHelper.decrypt(recoveryUnlockKey, recoveryEnvelope)

        // Generate new recovery codes with independent salt
        val recoveryCodeSalt = KeyDerivation.generateSalt()
        val newCodes = (1..RECOVERY_CODE_COUNT).map { generateRecoveryCode() }
        val codeHashes = newCodes.map { code ->
            Base64.getEncoder().encodeToString(Argon2.hashRecoveryCode(code, recoveryCodeSalt))
        }

        // New recovery envelope — encrypted with password-derived key
        val newRecoveryEnv = EnvelopeHelper.encrypt(recoveryUnlockKey, vaultKey)

        val rotatedRecovery = RecoveryDto(
            recoveryEnvelopeCiphertext = newRecoveryEnv.ciphertext,
            recoveryEnvelopeNonce = newRecoveryEnv.nonce,
            recoveryCodeHashes = codeHashes,
            recoveryCodeSalt = Base64.getEncoder().encodeToString(recoveryCodeSalt),
        )

        // Device envelope for the replacement device (same key pair as getRecoveryMaterial)
        val deviceEnvelopeParts = Ecdh.packDeviceEnvelope(vaultKey, ecdhKeyPair.public)
        val deviceEnvelope = Envelope(deviceEnvelopeParts.ciphertext, deviceEnvelopeParts.nonce)

        // Complete on server — returns auth tokens in the response
        val completeResponse = recoveryApi.completeRecovery(sessionId, replacementDeviceId, deviceEnvelope, rotatedRecovery)

        val userId = if (completeResponse.isNull("userId")) null else completeResponse.getString("userId")
        val accessToken = if (completeResponse.isNull("accessToken")) null else completeResponse.getString("accessToken")
        val refreshToken = if (completeResponse.isNull("refreshToken")) null else completeResponse.getString("refreshToken")
        val hasTokens = accessToken != null && refreshToken != null
        if (hasTokens) {
            persistTokens(accessToken!!, refreshToken!!)
        }

        // Persist ECDH key pair used for the replacement device envelope
        persistEcdhKeyPair(ecdhKeyPair)

        // Only mark connected if we got tokens
        persistSession(
            serverUrl = serverUrl,
            userId = userId ?: replacementDeviceId,
            deviceId = replacementDeviceId,
            email = email,
            mode = if (hasTokens) SettingsKeys.MODE_CONNECTED else SettingsKeys.MODE_STANDALONE,
        )
        // Recovery decrypts the same vault key the user registered with (the
        // recovery envelope just wraps it with a recovery-unlock-key). Any
        // stale biometric on this device still wraps the SAME key and is
        // still valid — we'd only need to clear it if the vault key itself
        // changed, which recovery doesn't do.
        persistPasswordEnvelope(salt, authKey, vaultKey, clearBiometric = false)

        return RecoveryResult(
            vaultKey = vaultKey,
            recoveryCodes = newCodes,
        )
    }

    /** Regenerate recovery codes. Requires password to derive the recovery unlock key. */
    suspend fun regenerateRecoveryCodes(email: String, password: String, vaultKey: ByteArray): List<String> {
        // Derive authKey from password (need KDF config from server)
        val ecdhKeyPair = loadOrGenerateEcdhKeyPair()
        val publicKeyBytes = Ecdh.exportPublicKey(ecdhKeyPair.public)
        val device = DeviceDto.android(Base64.getEncoder().encodeToString(publicKeyBytes))
        val challenge = authApi.requestLoginChallenge(email, device)
        val kdf = challenge.challenge.kdf
        val salt = Base64.getDecoder().decode(kdf.salt)
        val authKey = Argon2.hash(password, salt, kdf.memoryMb, kdf.iterations, kdf.parallelism)

        // Generate codes with independent salt
        val recoveryCodeSalt = KeyDerivation.generateSalt()
        val codes = (1..RECOVERY_CODE_COUNT).map { generateRecoveryCode() }
        val codeHashes = codes.map { code ->
            Base64.getEncoder().encodeToString(Argon2.hashRecoveryCode(code, recoveryCodeSalt))
        }

        val recoveryUnlockKey = KeyDerivation.deriveRecoveryUnlockKey(authKey)
        val regenEnv = EnvelopeHelper.encrypt(recoveryUnlockKey, vaultKey)

        val rotatedRecovery = RecoveryDto(
            recoveryEnvelopeCiphertext = regenEnv.ciphertext,
            recoveryEnvelopeNonce = regenEnv.nonce,
            recoveryCodeHashes = codeHashes,
            recoveryCodeSalt = Base64.getEncoder().encodeToString(recoveryCodeSalt),
        )

        recoveryApi.regenerateCodes(rotatedRecovery)
        return codes
    }

    /** Begin registration — request verification code. */
    suspend fun registerBegin(serverUrl: String, email: String) =
        authApi.also { apiClient.baseUrl = serverUrl.trimEnd('/') }.registerBegin(email)

    /** Verify email during registration. */
    suspend fun verifyEmail(registrationSessionId: String, code: String) =
        authApi.verifyEmail(registrationSessionId, code)

    companion object {
        const val RECOVERY_CODE_COUNT = 8
        const val RECOVERY_CODE_LENGTH = 10
        private const val RECOVERY_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // no I/O/0/1
    }

    private fun generateRecoveryCode(): String {
        val random = SecureRandom()
        return (1..RECOVERY_CODE_LENGTH).map {
            RECOVERY_CODE_ALPHABET[random.nextInt(RECOVERY_CODE_ALPHABET.length)]
        }.joinToString("")
    }

    suspend fun logout() {
        // Best-effort server logout — always clean up local state even if network fails
        try {
            authApi.logout()
        } catch (_: Exception) { }

        apiClient.clearTokens()
        SecureStore.remove(context, SecureStore.ACCESS_TOKEN)
        SecureStore.remove(context, SecureStore.REFRESH_TOKEN)

        db.withTransaction {
            settingsDao.set(SettingsEntity(SettingsKeys.MODE, SettingsKeys.MODE_STANDALONE))
            for (key in listOf(SettingsKeys.SERVER_URL, SettingsKeys.DEVICE_ID, SettingsKeys.USER_ID, SettingsKeys.LAST_SYNC_AT)) {
                settingsDao.delete(key)
            }
        }
    }

    /** Restore API client tokens from persisted settings (called on app startup). */
    suspend fun restoreSession() {
        val serverUrl = settingsDao.get(SettingsKeys.SERVER_URL) ?: return
        val prefs = SecureStore.getInstance(context)
        val accessToken = prefs.getString(SecureStore.ACCESS_TOKEN, null) ?: return
        val refreshToken = prefs.getString(SecureStore.REFRESH_TOKEN, null) ?: return
        apiClient.baseUrl = serverUrl.trimEnd('/')
        apiClient.setTokens(accessToken, refreshToken)
    }

    // --- ECDH key management ---

    /**
     * Load or generate ECDH key pair.
     * Keys are stored in EncryptedSharedPreferences (Keystore-backed),
     * NOT wrapped with the vault key — this breaks the circular dependency
     * so the device envelope can decrypt without the password.
     */
    private fun loadOrGenerateEcdhKeyPair(): KeyPair {
        val existingPubB64 = SecureStore.get(context, SecureStore.ECDH_PUBLIC_KEY)
        val existingPrivB64 = SecureStore.get(context, SecureStore.ECDH_PRIVATE_KEY)

        if (existingPubB64 != null && existingPrivB64 != null) {
            try {
                val privateKey = Ecdh.importPrivateKey(Base64.getDecoder().decode(existingPrivB64))
                val publicKey = Ecdh.importPublicKey(Base64.getDecoder().decode(existingPubB64))
                return KeyPair(publicKey, privateKey)
            } catch (_: Exception) {
                // Key corrupted — regenerate
            }
        }

        val keyPair = Ecdh.generateKeyPair()
        persistEcdhKeyPair(keyPair)
        return keyPair
    }

    private fun persistEcdhKeyPair(keyPair: KeyPair) {
        val pubBytes = Ecdh.exportPublicKey(keyPair.public)
        val privBytes = Ecdh.exportPrivateKey(keyPair.private)

        SecureStore.set(context, SecureStore.ECDH_PUBLIC_KEY, Base64.getEncoder().encodeToString(pubBytes))
        SecureStore.set(context, SecureStore.ECDH_PRIVATE_KEY, Base64.getEncoder().encodeToString(privBytes))
    }

    private fun decryptVaultKey(
        envelopes: io.github.pstanar.pstotp.core.model.api.LoginEnvelopes?,
        authKey: ByteArray,
        devicePrivateKey: PrivateKey,
    ): ByteArray? {
        if (envelopes == null) return null

        // Try device envelope first (ECDH)
        envelopes.device?.let { envelope ->
            try {
                return Ecdh.unpackDeviceEnvelope(envelope.ciphertext, envelope.nonce, devicePrivateKey)
            } catch (_: Exception) {
                // Fall through to password envelope
            }
        }

        // Fall back to password envelope
        envelopes.password?.let { envelope ->
            try {
                val envelopeKey = KeyDerivation.deriveEnvelopeKey(authKey)
                return EnvelopeHelper.decrypt(envelopeKey, envelope)
            } catch (_: Exception) {
                // Both envelopes failed
            }
        }

        return null
    }

    private suspend fun rebuildDeviceEnvelope(vaultKey: ByteArray, keyPair: KeyPair) {
        try {
            val envelope = Ecdh.packDeviceEnvelope(vaultKey, keyPair.public)
            val devicesApi = io.github.pstanar.pstotp.core.api.DevicesApi(apiClient)
            devicesApi.updateSelfEnvelope(Envelope(envelope.ciphertext, envelope.nonce))
        } catch (_: Exception) {
            // Best-effort — will retry on next login
        }
    }
}

sealed class LoginResult {
    data class Approved(val serverVaultKey: ByteArray) : LoginResult()
    data class PendingApproval(val approvalRequestId: String) : LoginResult()
    data class Error(val message: String) : LoginResult()
}

sealed class ChangePasswordResult {
    data object Success : ChangePasswordResult()
    data class Error(val message: String) : ChangePasswordResult()
}

data class RecoveryResult(
    val vaultKey: ByteArray,
    val recoveryCodes: List<String>,
)

data class RegistrationResult(
    val vaultKey: ByteArray,
    val recoveryCodes: List<String>,
)

sealed class PasskeyLoginResult {
    data class Approved(val serverVaultKey: ByteArray) : PasskeyLoginResult()
    data class NeedPassword(
        val envelopes: LoginEnvelopes,
        val userId: String,
        val deviceId: String,
    ) : PasskeyLoginResult()
    data class PendingApproval(val approvalRequestId: String) : PasskeyLoginResult()
    data class Error(val message: String) : PasskeyLoginResult()
}
