import Foundation

public enum LoginResult: Sendable, Equatable {
    case approved(serverVaultKey: Data)
    case pendingApproval(approvalRequestId: String)
    case error(String)
}

public enum ChangePasswordResult: Sendable, Equatable {
    case success
    /// The server rejected the proof of the current password.
    case incorrectCurrentPassword
}

/// A recovery the server has accepted a code for but not yet released: kept across launches because
/// the hold period (24 h by default) outlasts any screen, and the server allows one active session.
public struct PendingRecovery: Codable, Equatable, Sendable {
    public var sessionId: String
    public var serverUrl: String
    public var email: String
    /// When the server will release the recovery material (ISO 8601).
    public var releaseEarliestAt: String
    /// The session needs a passkey step-up, which the app can't do yet.
    public var requiresPasskey: Bool

    public init(sessionId: String, serverUrl: String, email: String, releaseEarliestAt: String, requiresPasskey: Bool) {
        self.sessionId = sessionId
        self.serverUrl = serverUrl
        self.email = email
        self.releaseEarliestAt = releaseEarliestAt
        self.requiresPasskey = requiresPasskey
    }
}

public enum RecoveryMaterialStatus: Equatable, Sendable {
    case passkeyRequired
    case pending(releaseEarliestAt: String)
    case ready(envelope: Envelope, replacementDeviceId: String)
}

public struct RecoveryResult: Sendable, Equatable {
    public let vaultKey: Data
    public let recoveryCodes: [String]
    /// False if the server answered without tokens (the vault key and new codes are still valid).
    public let signedIn: Bool
}

public enum RecoveryError: Error, Equatable, LocalizedError {
    /// The server no longer knows the session (expired, cancelled or completed).
    case sessionGone
    case incorrectPassword
    case unexpectedStatus(String)
    case missingEnvelope

    public var errorDescription: String? {
        switch self {
        case .sessionGone: "This recovery has expired or was cancelled. Start again with a recovery code."
        case .incorrectPassword: "Incorrect password"
        case .unexpectedStatus(let status): "Unexpected recovery status: \(status)"
        case .missingEnvelope: "The server has no recovery material for this account."
        }
    }
}

/// The server has created the account (or finished the recovery), but this device couldn't finish setting
/// itself up. The recovery codes exist only here, so they travel with the error: the user must still be shown
/// them. The session was dropped; signing in with the email and password completes the setup.
public struct AccountSetupIncomplete: Error, LocalizedError, Equatable {
    public let recoveryCodes: [String]
    public let detail: String

    public var errorDescription: String? {
        "Your account is ready on the server, but this device couldn't finish setting up (\(detail)). Save your recovery codes, then sign in with your email and password."
    }
}

public enum RegenerateCodesResult: Sendable, Equatable {
    case codes([String])
    /// The password doesn't match this vault's. Nothing was sent: the recovery envelope is wrapped
    /// with a key derived from the password, so a wrong one would make recovery fail later.
    case incorrectPassword
}

public struct RegistrationResult: Sendable, Equatable {
    public let vaultKey: Data
    public let recoveryCodes: [String]
}

/// Server authentication: password login, registration, logout and session restore
/// (the password-login part of Android's `AuthService`; passkey login, recovery and password change
/// come with their own slices).
///
/// Login flow: load/generate the device ECDH key → request challenge (nonce + KDF) → Argon2id →
/// verifier → client proof → complete → tokens + envelopes → vault key.
///
/// API errors (`ApiError`) and crypto errors propagate to the caller; `LoginResult.error` is only
/// for "the server answered but gave us nothing we can decrypt".
public final class AuthService: Sendable {
    private let repository: VaultRepository
    private let client: ApiClient
    private let secrets: SecretStore
    private let authApi: AuthApi
    private let devicesApi: DevicesApi
    private let recoveryApi: RecoveryApi
    private let invalidateBiometric: @Sendable () async -> Void

    /// - Parameter invalidateBiometric: Removes any enrolled biometric copy of the vault key. Called
    ///   when the local vault key is replaced by the server's: a stale biometric copy would decrypt
    ///   to the old key and silently break entry decryption.
    public init(
        repository: VaultRepository, client: ApiClient, secrets: SecretStore,
        invalidateBiometric: @escaping @Sendable () async -> Void = {}
    ) {
        self.repository = repository
        self.client = client
        self.secrets = secrets
        self.authApi = AuthApi(client: client)
        self.devicesApi = DevicesApi(client: client)
        self.recoveryApi = RecoveryApi(client: client)
        self.invalidateBiometric = invalidateBiometric
    }

    // MARK: State

    public func isConnected() async throws -> Bool {
        try await repository.isConnected() && secrets.get(.accessToken) != nil
    }

    public func serverUrl() async throws -> String? { try await repository.getSetting(SettingsKeys.serverUrl) }

    /// Restores the API client's tokens on app start (a no-op unless a session was saved).
    public func restoreSession() async throws {
        guard let url = try await serverUrl(),
              let access = try secrets.get(.accessToken),
              let refresh = try secrets.get(.refreshToken) else { return }
        await prepare(serverUrl: url)
        await client.setTokens(access: access, refresh: refresh)
    }

    // MARK: Login

    /// - Parameter localVaultKey: The unlocked vault's current key. The server's key replaces it, and the
    ///   local entries are re-encrypted with the new one in the same transaction.
    public func login(serverUrl: String, email: String, password: String, localVaultKey: Data) async throws -> LoginResult {
        await prepare(serverUrl: serverUrl)
        let challenge = try await serverChallenge(email: email, password: password)
        let (ecdhKey, kdf, salt, authKey) = (challenge.ecdhKey, challenge.kdf, challenge.salt, challenge.authKey)

        let result = try await authApi.completeLogin(try challenge.proof())
        try await persistTokens(result.accessToken, result.refreshToken)

        if result.device.status == "pending" {
            try await persistSession(serverUrl: serverUrl, userId: result.userId, deviceId: result.device.deviceId,
                                     email: email, connected: false)
            return .pendingApproval(approvalRequestId: result.approvalRequestId ?? result.device.deviceId)
        }

        // The server has granted a session. If this device can't finish setting up, don't leave it behind.
        do {
            guard let serverVaultKey = Self.decryptVaultKey(result.envelopes, authKey: authKey, devicePrivateKey: ecdhKey) else {
                await discardSession()
                return .error("No envelope available to decrypt vault key")
            }

            // The local envelope must open with the pinned parameters, because that is what offline unlock
            // derives with. An account registered with other parameters (the server stores whatever the
            // registering client sent) would otherwise lock the user out of their own vault.
            let localAuthKey = try await Self.localAuthKey(kdf: kdf, serverAuthKey: authKey, password: password, salt: salt)

            // Adopt the server's vault key locally so offline password/biometric unlocks unwrap to the key
            // synced entries are encrypted with (a device that had its own local vault gets a different one).
            try await adopt(vaultKey: serverVaultKey, replacing: localVaultKey, salt: salt, authKey: localAuthKey,
                            session: (serverUrl, result.userId, result.device.deviceId, email))
            await rebuildDeviceEnvelope(vaultKey: serverVaultKey, key: ecdhKey)
            return .approved(serverVaultKey: serverVaultKey)
        } catch {
            await discardSession()
            throw error
        }
    }

    // MARK: Registration

    public func registerBegin(serverUrl: String, email: String) async throws -> BeginRegistrationResponse {
        await prepare(serverUrl: serverUrl)
        return try await authApi.registerBegin(email: email)
    }

    public func verifyEmail(registrationSessionId: String, code: String) async throws -> Bool {
        try await authApi.verifyEmail(registrationSessionId: registrationSessionId, verificationCode: code)
    }

    /// Creates the account: vault key, password verifier + envelope, device envelope, recovery codes
    /// + envelope. The caller must show `recoveryCodes` to the user — they are not stored.
    public func register(
        serverUrl: String, email: String, password: String, registrationSessionId: String?, localVaultKey: Data
    ) async throws -> RegistrationResult {
        await prepare(serverUrl: serverUrl)

        let vaultKey = KeyDerivation.generateVaultKey()
        let password = try await Self.newPasswordMaterial(password: password, vaultKey: vaultKey)

        let ecdhKey = Ecdh.generateKeyPair()
        let deviceEnvelope = try Ecdh.packDeviceEnvelope(vaultKey: vaultKey, recipientPublicKey: ecdhKey.publicKey)
        let (recovery, recoveryCodes) = try await Self.makeRecovery(authKey: password.authKey, vaultKey: vaultKey)

        let result = try await authApi.register(
            registrationSessionId: registrationSessionId, email: email,
            passwordVerifier: password.verifierDto, passwordEnvelope: password.envelope,
            device: .ios(for: ecdhKey), deviceEnvelope: deviceEnvelope, recovery: recovery)

        // The account exists now, and the recovery codes exist nowhere else: whatever goes wrong below, the
        // user must still get them.
        do {
            // The device key goes first: without it the device envelope the server now holds is unusable.
            try persistEcdhKey(ecdhKey)
            try await persistTokens(result.accessToken, result.refreshToken)
            try await adopt(vaultKey: vaultKey, replacing: localVaultKey, salt: password.salt, authKey: password.authKey,
                            session: (serverUrl, result.userId, result.deviceId, email))
        } catch {
            await discardSession()
            throw AccountSetupIncomplete(recoveryCodes: recoveryCodes, detail: error.localizedDescription)
        }
        return RegistrationResult(vaultKey: vaultKey, recoveryCodes: recoveryCodes)
    }

    /// Removes every stored secret, device key included. For a fresh install: Keychain items survive
    /// an uninstall, and they belong to a vault that no longer exists.
    public func removeAllSecrets() throws {
        for key in SecretKey.allCases { try secrets.remove(key) }
    }

    // MARK: Change password

    /// Changes the password on the server and on this device. The vault key stays the same; only the
    /// password-derived wrapper of it is replaced (so a biometric copy remains valid).
    ///
    /// Step-up: a fresh login challenge proves knowledge of the current password. On success the
    /// server revokes every session and hands this device new tokens, so other devices have to sign
    /// in again.
    ///
    /// - Parameter vaultKey: The unlocked vault's key, to wrap under the new password.
    public func changePassword(
        email: String, currentPassword: String, newPassword: String, vaultKey: Data
    ) async throws -> ChangePasswordResult {
        let challenge = try await serverChallenge(email: email, password: currentPassword)
        let new = try await Self.newPasswordMaterial(password: newPassword, vaultKey: vaultKey)

        let response: RefreshResponse
        do {
            response = try await authApi.changePassword(
                currentProof: try challenge.proof(), newVerifier: new.verifierDto, newPasswordEnvelope: new.envelope)
        } catch ApiError.http(401, _) {
            // The session is fresh and the token was just refreshed if needed, so a 401 here means the
            // proof was wrong. (The server leaves the login session unused in that case.)
            return .incorrectCurrentPassword
        }

        // The local password material first: the server has already changed, so offline unlock has to
        // match it before anything else can fail. (The vault key is unchanged: no biometric reset.)
        try await repository.updateSettings(set: Self.passwordSettings(
            salt: new.salt, verifier: new.verifier, wrapped: try EnvelopeHelper.toRaw(new.envelope)))
        try await persistTokens(response.accessToken, response.refreshToken)
        return .success
    }

    // MARK: Recovery codes

    /// Replaces the account's recovery codes with a fresh set. The old ones stop working. The vault
    /// key is unchanged.
    ///
    /// The password is needed to derive the key that wraps the vault key for recovery; the server can't
    /// check it, so it is checked here against this vault's own password first.
    public func regenerateRecoveryCodes(email: String, password: String, vaultKey: Data) async throws -> RegenerateCodesResult {
        guard try await repository.unlockVault(password: password) != nil else { return .incorrectPassword }

        // Recovery derives its key from the password with the server's parameters, so does this.
        let challenge = try await serverChallenge(email: email, password: password)
        let (recovery, codes) = try await Self.makeRecovery(authKey: challenge.authKey, vaultKey: vaultKey)
        try await recoveryApi.regenerateCodes(rotatedRecovery: recovery)
        return .codes(codes)
    }

    /// New recovery codes (hashed with their own salt, not the password's) and the recovery envelope:
    /// the vault key wrapped with a key derived from the password's `authKey`, which recovery
    /// re-derives after proving the password through step-up auth.
    private static func makeRecovery(authKey: Data, vaultKey: Data) async throws -> (RecoveryDto, [String]) {
        let salt = KeyDerivation.generateSalt()
        let codes = RecoveryCodes.generate()
        let hashes = try await offMainThread {
            try codes.map { try Argon2.hashRecoveryCode($0, salt: salt).base64EncodedString() }
        }
        let envelope = try EnvelopeHelper.encrypt(
            key: KeyDerivation.deriveRecoveryUnlockKey(recoverySeed: authKey), plaintext: vaultKey)
        return (RecoveryDto(recoveryEnvelopeCiphertext: envelope.ciphertext, recoveryEnvelopeNonce: envelope.nonce,
                            recoveryCodeHashes: hashes, recoveryCodeSalt: salt.base64EncodedString()), codes)
    }

    // MARK: Account recovery

    /// The recovery that is waiting out its hold period, if any.
    public func pendingRecovery() async throws -> PendingRecovery? {
        guard let json = try await repository.getSetting(SettingsKeys.recoverySession) else { return nil }
        return try? JSONDecoder().decode(PendingRecovery.self, from: Data(json.utf8))
    }

    public func forgetPendingRecovery() async throws {
        try await repository.deleteSetting(SettingsKeys.recoverySession)
    }

    private func save(_ pending: PendingRecovery) async throws {
        try await repository.setSetting(SettingsKeys.recoverySession, String(decoding: try JSONEncoder().encode(pending), as: UTF8.self))
    }

    /// Step 1: redeem a recovery code, proving the password through a step-up proof. The session is
    /// saved so recovery can be resumed after the hold period.
    public func startRecovery(serverUrl: String, email: String, password: String, recoveryCode: String) async throws -> PendingRecovery {
        await prepare(serverUrl: serverUrl)
        // The device key is the same in every recovery step: the server registers it as the replacement device.
        let challenge = try await serverChallenge(email: email, password: password)
        let redeemed = try await recoveryApi.redeemRecoveryCode(
            email: email, recoveryCode: recoveryCode, verifierProof: try challenge.proof())
        let pending = PendingRecovery(
            sessionId: redeemed.recoverySessionId, serverUrl: serverUrl, email: email,
            releaseEarliestAt: redeemed.releaseEarliestAt, requiresPasskey: redeemed.requiresWebAuthn)
        try await save(pending)
        return pending
    }

    /// Step 2: ask whether the recovery material can be released yet. When it can, the server
    /// registers this device as the replacement.
    public func recoveryMaterial(for pending: PendingRecovery) async throws -> RecoveryMaterialStatus {
        await prepare(serverUrl: pending.serverUrl)
        let device = DeviceDto.ios(for: try loadOrGenerateEcdhKey())
        let material = try await forgettingGoneSession {
            try await recoveryApi.getRecoveryMaterial(sessionId: pending.sessionId, replacementDevice: device)
        }
        switch material.status {
        case "webauthn_required":
            return .passkeyRequired
        case "pending":
            var updated = pending
            if let release = material.releaseEarliestAt { updated.releaseEarliestAt = release }
            try await save(updated)
            return .pending(releaseEarliestAt: updated.releaseEarliestAt)
        case "ready":
            guard let envelope = material.recoveryEnvelope else { throw RecoveryError.missingEnvelope }
            guard let deviceId = material.replacementDeviceId else { throw RecoveryError.unexpectedStatus("ready without a device") }
            return .ready(envelope: envelope, replacementDeviceId: deviceId)
        default:
            throw RecoveryError.unexpectedStatus(material.status)
        }
    }

    /// Step 3: open the recovery envelope with the password, rotate the recovery codes, give this device
    /// its own envelope, and sign in. The account's vault key replaces the local one (local entries are
    /// re-encrypted). A wrong password is caught before anything is sent.
    public func completeRecovery(
        pending: PendingRecovery, password: String, envelope: Envelope, replacementDeviceId: String, localVaultKey: Data
    ) async throws -> RecoveryResult {
        await prepare(serverUrl: pending.serverUrl)
        // The challenge's device key is the one getRecoveryMaterial registered.
        let challenge = try await serverChallenge(email: pending.email, password: password)
        let (ecdhKey, kdf, salt, authKey) = (challenge.ecdhKey, challenge.kdf, challenge.salt, challenge.authKey)

        let vaultKey: Data
        do {
            vaultKey = try EnvelopeHelper.decrypt(key: KeyDerivation.deriveRecoveryUnlockKey(recoverySeed: authKey), envelope: envelope)
        } catch CryptoError.decryptionFailed {
            throw RecoveryError.incorrectPassword
        }

        let (rotated, newCodes) = try await Self.makeRecovery(authKey: authKey, vaultKey: vaultKey)
        let deviceEnvelope = try Ecdh.packDeviceEnvelope(vaultKey: vaultKey, recipientPublicKey: ecdhKey.publicKey)

        let response = try await forgettingGoneSession {
            try await recoveryApi.completeRecovery(
                sessionId: pending.sessionId, replacementDeviceId: replacementDeviceId,
                deviceEnvelope: deviceEnvelope, rotatedRecovery: rotated)
        }

        // The server has changed (codes rotated, session completed), so this recovery can't be resumed and the
        // new codes exist only here. Keep what we have even if the response carries no tokens, and if the
        // local setup fails, hand the codes over with the error.
        try? await forgetPendingRecovery()
        let signedIn = response.accessToken != nil && response.refreshToken != nil
        do {
            try await persistTokens(response.accessToken, response.refreshToken)
            let localKey = try await Self.localAuthKey(kdf: kdf, serverAuthKey: authKey, password: password, salt: salt)
            try await adopt(vaultKey: vaultKey, replacing: localVaultKey, salt: salt, authKey: localKey,
                            session: (pending.serverUrl, response.userId ?? replacementDeviceId, replacementDeviceId, pending.email),
                            connected: signedIn)
        } catch {
            await discardSession()
            throw AccountSetupIncomplete(recoveryCodes: newCodes, detail: error.localizedDescription)
        }
        return RecoveryResult(vaultKey: vaultKey, recoveryCodes: newCodes, signedIn: signedIn)
    }

    // MARK: Logout

    /// Best-effort server logout; local state is always cleaned up, even offline. The device key stays.
    public func logout() async throws {
        await authApi.logout()
        await client.clearTokens()
        try secrets.remove(.accessToken)
        try secrets.remove(.refreshToken)
        try await repository.updateSettings(
            set: [SettingsKeys.mode: SettingsKeys.modeStandalone],
            delete: [SettingsKeys.serverUrl, SettingsKeys.deviceId, SettingsKeys.userId, SettingsKeys.lastSyncAt,
                     // The next account may differ: treat the library as never synced.
                     SettingsKeys.iconLibraryServerVersion])
    }

    // MARK: Persistence

    /// Points the client at the server and makes refreshed tokens survive a restart.
    private func prepare(serverUrl: String) async {
        await client.setBaseURL(serverUrl)
        let secrets = secrets
        await client.setOnTokensRefreshed { access, refresh in
            // The server has already replaced the old refresh token. If the new pair can't be stored, a stored
            // old pair would be a revoked one at the next launch, so drop both: the next launch then asks
            // for a sign-in instead of trying a token that can never work.
            for attempt in 1...2 {
                do { return try secrets.setAll([.accessToken: access, .refreshToken: refresh]) }
                catch where attempt == 2 {
                    try? secrets.remove(.accessToken)
                    try? secrets.remove(.refreshToken)
                } catch {}
            }
        }
    }

    /// Drops a session the server just granted but this device couldn't finish setting up, so no live tokens
    /// are left behind. Best effort on the server side; the settings are not touched.
    private func discardSession() async {
        await authApi.logout()   // revokes the refresh token; reads it before it is cleared
        await client.clearTokens()
        try? secrets.remove(.accessToken)
        try? secrets.remove(.refreshToken)
    }

    private func persistTokens(_ access: String?, _ refresh: String?) async throws {
        guard let access, let refresh else { return }
        await client.setTokens(access: access, refresh: refresh)
        try secrets.setAll([.accessToken: access, .refreshToken: refresh])
    }

    /// `connected: false` is for intermediate states (pending approval) that aren't a usable session yet.
    private func persistSession(serverUrl: String, userId: String, deviceId: String, email: String, connected: Bool = true) async throws {
        var values = [SettingsKeys.serverUrl: serverUrl, SettingsKeys.userId: userId,
                      SettingsKeys.deviceId: deviceId, SettingsKeys.email: email]
        if connected { values[SettingsKeys.mode] = SettingsKeys.modeConnected }
        try await repository.updateSettings(set: values)
    }

    /// Makes `vaultKey` the device's key and marks the session connected, atomically: the local
    /// password envelope (so later offline password unlocks return exactly this key), the session
    /// and the re-encryption of everything stored under `localVaultKey`. A biometric copy of the
    /// old key is removed.
    private func adopt(
        vaultKey: Data, replacing localVaultKey: Data, salt: Data, authKey: Data,
        session: (serverUrl: String, userId: String, deviceId: String, email: String),
        connected: Bool = true
    ) async throws {
        let wrapped = try AesGcm.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: authKey), plaintext: vaultKey)
        var settings = Self.passwordSettings(salt: salt, verifier: KeyDerivation.deriveVerifier(authKey: authKey), wrapped: wrapped)
        settings[SettingsKeys.serverUrl] = session.serverUrl
        settings[SettingsKeys.userId] = session.userId
        settings[SettingsKeys.deviceId] = session.deviceId
        settings[SettingsKeys.email] = session.email
        settings[SettingsKeys.mode] = connected ? SettingsKeys.modeConnected : SettingsKeys.modeStandalone
        try await repository.replaceVaultKey(from: localVaultKey, to: vaultKey, settings: settings)
        // A stale biometric copy would decrypt to the old key and break entry decryption.
        if vaultKey != localVaultKey { await invalidateBiometric() }
    }

    // MARK: Shared steps

    /// A login challenge answered with the password: what login and every step-up flow (password change,
    /// recovery codes, account recovery) need from it.
    private struct ServerChallenge {
        let ecdhKey: Ecdh.PrivateKey
        let loginSessionId: String
        let kdf: KdfConfig
        let salt: Data
        let nonce: String
        /// The password under the server's KDF parameters.
        let authKey: Data

        /// HMAC proof of the password for this challenge (the nonce is decoded here, so flows that
        /// only want the key never depend on it).
        func proof() throws -> ClientProofDto {
            guard let nonce = Data(base64Encoded: nonce) else { throw CryptoError.invalidEncoding }
            let proof = try ClientProof.compute(
                verifier: KeyDerivation.deriveVerifier(authKey: authKey), nonce: nonce, loginSessionId: loginSessionId)
            return ClientProofDto(loginSessionId: loginSessionId, clientProof: proof.base64EncodedString())
        }
    }

    /// Requests a login challenge as this device and derives the password's key with the server's KDF
    /// parameters (floors enforced, off the caller's executor).
    private func serverChallenge(email: String, password: String) async throws -> ServerChallenge {
        let ecdhKey = try loadOrGenerateEcdhKey()
        let response = try await authApi.requestLoginChallenge(email: email, device: .ios(for: ecdhKey))
        let kdf = response.challenge.kdf
        guard let salt = Data(base64Encoded: kdf.salt) else { throw CryptoError.invalidEncoding }
        let authKey = try await Self.offMainThread {
            try Argon2.hash(password: password, salt: salt, memoryMb: kdf.memoryMb,
                            iterations: kdf.iterations, parallelism: kdf.parallelism)
        }
        return ServerChallenge(ecdhKey: ecdhKey, loginSessionId: response.loginSessionId, kdf: kdf, salt: salt,
                               nonce: response.challenge.nonce, authKey: authKey)
    }

    /// A new password's credentials: its key (pinned KDF, fresh salt), the verifier the server stores, and
    /// the envelope that wraps the vault key under it. Used by registration and password change.
    private struct PasswordMaterial {
        let salt: Data
        let authKey: Data
        let verifier: Data
        let verifierDto: PasswordVerifierDto
        let envelope: Envelope
    }

    private static func newPasswordMaterial(password: String, vaultKey: Data) async throws -> PasswordMaterial {
        let salt = KeyDerivation.generateSalt()
        let authKey = try await offMainThread { try KeyDerivation.derivePasswordAuthKey(password: password, salt: salt) }
        let verifier = KeyDerivation.deriveVerifier(authKey: authKey)
        return PasswordMaterial(
            salt: salt, authKey: authKey, verifier: verifier,
            verifierDto: PasswordVerifierDto(verifier: verifier.base64EncodedString(),
                                             kdf: .default(saltBase64: salt.base64EncodedString())),
            envelope: try EnvelopeHelper.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: authKey), plaintext: vaultKey))
    }

    /// The settings that let offline unlock recreate the vault key from the password. `wrapped` is the raw
    /// `nonce || ciphertext || tag`.
    private static func passwordSettings(salt: Data, verifier: Data, wrapped: Data) -> [String: String] {
        [SettingsKeys.kdfSalt: salt.base64EncodedString(),
         SettingsKeys.passwordVerifier: verifier.base64EncodedString(),
         SettingsKeys.encryptedVaultKey: wrapped.base64EncodedString()]
    }

    /// Runs a recovery-session call; if the server no longer knows the session, forget it locally too.
    private func forgettingGoneSession<T>(_ call: () async throws -> T) async throws -> T {
        do {
            return try await call()
        } catch ApiError.http(404, _) {
            try await forgetPendingRecovery()
            throw RecoveryError.sessionGone
        }
    }

    // MARK: Device key

    private func loadOrGenerateEcdhKey() throws -> Ecdh.PrivateKey {
        if let stored = try secrets.get(.ecdhPrivateKey), let der = Data(base64Encoded: stored),
           let key = try? Ecdh.importPrivateKey(der) {
            return key
        }
        let key = Ecdh.generateKeyPair()   // none yet, or unreadable: start over
        try persistEcdhKey(key)
        return key
    }

    private func persistEcdhKey(_ key: Ecdh.PrivateKey) throws {
        try secrets.setAll([.ecdhPrivateKey: Ecdh.exportPrivateKey(key).base64EncodedString()])
    }

    // MARK: Helpers

    /// Device envelope first (ECDH, no password needed), then the password envelope.
    static func decryptVaultKey(_ envelopes: LoginEnvelopes?, authKey: Data, devicePrivateKey: Ecdh.PrivateKey) -> Data? {
        guard let envelopes else { return nil }
        if let device = envelopes.device,
           let key = try? Ecdh.unpackDeviceEnvelope(device, devicePrivateKey: devicePrivateKey) { return key }
        if let password = envelopes.password,
           let key = try? EnvelopeHelper.decrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: authKey), envelope: password) {
            return key
        }
        return nil
    }

    /// Best effort: retried at the next login.
    private func rebuildDeviceEnvelope(vaultKey: Data, key: Ecdh.PrivateKey) async {
        guard let envelope = try? Ecdh.packDeviceEnvelope(vaultKey: vaultKey, recipientPublicKey: key.publicKey) else { return }
        try? await devicesApi.updateSelfEnvelope(envelope)
    }

    /// The key for the local password envelope: the one derived for the server when its parameters are
    /// the pinned ones, otherwise a second derivation with them (offline unlock always uses those).
    private static func localAuthKey(kdf: KdfConfig, serverAuthKey: Data, password: String, salt: Data) async throws -> Data {
        kdf.isPinnedDefault ? serverAuthKey : try await offMainThread {
            try KeyDerivation.derivePasswordAuthKey(password: password, salt: salt)
        }
    }

    /// Argon2 is deliberately expensive; keep it off the caller's executor.
    private static func offMainThread<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated, operation: work).value
    }
}

extension DeviceDto {
    /// This iOS device, identified by `key`'s public half.
    static func ios(for key: Ecdh.PrivateKey) -> DeviceDto {
        .ios(publicKeyBase64: Ecdh.exportPublicKey(key.publicKey).base64EncodedString())
    }
}
