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
        let ecdhKey = try loadOrGenerateEcdhKey()
        let device = DeviceDto.ios(publicKeyBase64: Ecdh.exportPublicKey(ecdhKey.publicKey).base64EncodedString())

        let challenge = try await authApi.requestLoginChallenge(email: email, device: device)
        let kdf = challenge.challenge.kdf
        guard let nonce = Data(base64Encoded: challenge.challenge.nonce),
              let salt = Data(base64Encoded: kdf.salt) else { throw CryptoError.invalidEncoding }

        let authKey = try await Self.offMainThread {
            try Argon2.hash(password: password, salt: salt, memoryMb: kdf.memoryMb,
                            iterations: kdf.iterations, parallelism: kdf.parallelism)
        }
        let verifier = KeyDerivation.deriveVerifier(authKey: authKey)
        let proof = try ClientProof.compute(verifier: verifier, nonce: nonce, loginSessionId: challenge.loginSessionId)

        let result = try await authApi.completeLogin(
            loginSessionId: challenge.loginSessionId, clientProof: proof.base64EncodedString())
        try await persistTokens(result.accessToken, result.refreshToken)

        if result.device.status == "pending" {
            try await persistSession(serverUrl: serverUrl, userId: result.userId, deviceId: result.device.deviceId,
                                     email: email, connected: false)
            return .pendingApproval(approvalRequestId: result.approvalRequestId ?? result.device.deviceId)
        }

        guard let serverVaultKey = Self.decryptVaultKey(result.envelopes, authKey: authKey, devicePrivateKey: ecdhKey) else {
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
        let salt = KeyDerivation.generateSalt()

        let authKey = try await Self.offMainThread { try KeyDerivation.derivePasswordAuthKey(password: password, salt: salt) }
        let verifier = KeyDerivation.deriveVerifier(authKey: authKey)
        let passwordEnvelope = try EnvelopeHelper.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: authKey), plaintext: vaultKey)

        let ecdhKey = Ecdh.generateKeyPair()
        let publicKey = Ecdh.exportPublicKey(ecdhKey.publicKey)
        let deviceEnvelope = try Ecdh.packDeviceEnvelope(vaultKey: vaultKey, recipientPublicKey: ecdhKey.publicKey)

        let (recovery, recoveryCodes) = try await Self.makeRecovery(authKey: authKey, vaultKey: vaultKey)

        let result = try await authApi.register(
            registrationSessionId: registrationSessionId, email: email,
            passwordVerifier: PasswordVerifierDto(verifier: verifier.base64EncodedString(),
                                                  kdf: .default(saltBase64: salt.base64EncodedString())),
            passwordEnvelope: passwordEnvelope,
            device: .ios(publicKeyBase64: publicKey.base64EncodedString()),
            deviceEnvelope: deviceEnvelope,
            recovery: recovery)

        // The device key goes first: without it the device envelope the server now holds is unusable.
        try persistEcdhKey(ecdhKey)
        try await persistTokens(result.accessToken, result.refreshToken)
        try await adopt(vaultKey: vaultKey, replacing: localVaultKey, salt: salt, authKey: authKey,
                        session: (serverUrl, result.userId, result.deviceId, email))
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
        let ecdhKey = try loadOrGenerateEcdhKey()
        let device = DeviceDto.ios(publicKeyBase64: Ecdh.exportPublicKey(ecdhKey.publicKey).base64EncodedString())

        let challenge = try await authApi.requestLoginChallenge(email: email, device: device)
        let kdf = challenge.challenge.kdf
        guard let nonce = Data(base64Encoded: challenge.challenge.nonce),
              let currentSalt = Data(base64Encoded: kdf.salt) else { throw CryptoError.invalidEncoding }

        let newSalt = KeyDerivation.generateSalt()
        let (currentAuthKey, newAuthKey) = try await Self.offMainThread {
            (try Argon2.hash(password: currentPassword, salt: currentSalt, memoryMb: kdf.memoryMb,
                             iterations: kdf.iterations, parallelism: kdf.parallelism),
             try KeyDerivation.derivePasswordAuthKey(password: newPassword, salt: newSalt))
        }
        let proof = try ClientProof.compute(
            verifier: KeyDerivation.deriveVerifier(authKey: currentAuthKey), nonce: nonce,
            loginSessionId: challenge.loginSessionId)

        let newVerifier = KeyDerivation.deriveVerifier(authKey: newAuthKey)
        let newEnvelope = try EnvelopeHelper.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: newAuthKey), plaintext: vaultKey)

        let response: RefreshResponse
        do {
            response = try await authApi.changePassword(
                currentProof: ClientProofDto(loginSessionId: challenge.loginSessionId, clientProof: proof.base64EncodedString()),
                newVerifier: PasswordVerifierDto(verifier: newVerifier.base64EncodedString(),
                                                 kdf: .default(saltBase64: newSalt.base64EncodedString())),
                newPasswordEnvelope: newEnvelope)
        } catch ApiError.http(401, _) {
            // The session is fresh and the token was just refreshed if needed, so a 401 here means the
            // proof was wrong. (The server leaves the login session unused in that case.)
            return .incorrectCurrentPassword
        }

        // The local password material first: the server has already changed, so offline unlock has to
        // match it before anything else can fail. (The vault key is unchanged: no biometric reset.)
        let wrapped = try AesGcm.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: newAuthKey), plaintext: vaultKey)
        try await repository.updateSettings(set: [
            SettingsKeys.kdfSalt: newSalt.base64EncodedString(),
            SettingsKeys.passwordVerifier: newVerifier.base64EncodedString(),
            SettingsKeys.encryptedVaultKey: wrapped.base64EncodedString(),
        ])
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

        let ecdhKey = try loadOrGenerateEcdhKey()
        let device = DeviceDto.ios(publicKeyBase64: Ecdh.exportPublicKey(ecdhKey.publicKey).base64EncodedString())
        let challenge = try await authApi.requestLoginChallenge(email: email, device: device)
        let kdf = challenge.challenge.kdf
        guard let salt = Data(base64Encoded: kdf.salt) else { throw CryptoError.invalidEncoding }

        // Recovery derives this key from the password with the server's parameters, so does this.
        let authKey = try await Self.offMainThread {
            try Argon2.hash(password: password, salt: salt, memoryMb: kdf.memoryMb,
                            iterations: kdf.iterations, parallelism: kdf.parallelism)
        }
        let (recovery, codes) = try await Self.makeRecovery(authKey: authKey, vaultKey: vaultKey)
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
        let ecdhKey = try loadOrGenerateEcdhKey()   // the same device identity in every recovery step
        let device = DeviceDto.ios(publicKeyBase64: Ecdh.exportPublicKey(ecdhKey.publicKey).base64EncodedString())

        let challenge = try await authApi.requestLoginChallenge(email: email, device: device)
        let kdf = challenge.challenge.kdf
        guard let nonce = Data(base64Encoded: challenge.challenge.nonce),
              let salt = Data(base64Encoded: kdf.salt) else { throw CryptoError.invalidEncoding }
        let authKey = try await Self.offMainThread {
            try Argon2.hash(password: password, salt: salt, memoryMb: kdf.memoryMb,
                            iterations: kdf.iterations, parallelism: kdf.parallelism)
        }
        let proof = try ClientProof.compute(verifier: KeyDerivation.deriveVerifier(authKey: authKey), nonce: nonce,
                                            loginSessionId: challenge.loginSessionId)

        let redeemed = try await recoveryApi.redeemRecoveryCode(
            email: email, recoveryCode: recoveryCode,
            verifierProof: ClientProofDto(loginSessionId: challenge.loginSessionId, clientProof: proof.base64EncodedString()))
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
        let ecdhKey = try loadOrGenerateEcdhKey()
        let device = DeviceDto.ios(publicKeyBase64: Ecdh.exportPublicKey(ecdhKey.publicKey).base64EncodedString())
        let material: RecoveryMaterialResponse
        do {
            material = try await recoveryApi.getRecoveryMaterial(sessionId: pending.sessionId, replacementDevice: device)
        } catch ApiError.http(404, _) {
            try await forgetPendingRecovery()
            throw RecoveryError.sessionGone
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
        let ecdhKey = try loadOrGenerateEcdhKey()   // the key getRecoveryMaterial registered
        let device = DeviceDto.ios(publicKeyBase64: Ecdh.exportPublicKey(ecdhKey.publicKey).base64EncodedString())

        let challenge = try await authApi.requestLoginChallenge(email: pending.email, device: device)
        let kdf = challenge.challenge.kdf
        guard let salt = Data(base64Encoded: kdf.salt) else { throw CryptoError.invalidEncoding }
        let authKey = try await Self.offMainThread {
            try Argon2.hash(password: password, salt: salt, memoryMb: kdf.memoryMb,
                            iterations: kdf.iterations, parallelism: kdf.parallelism)
        }

        let vaultKey: Data
        do {
            vaultKey = try EnvelopeHelper.decrypt(key: KeyDerivation.deriveRecoveryUnlockKey(recoverySeed: authKey), envelope: envelope)
        } catch CryptoError.decryptionFailed {
            throw RecoveryError.incorrectPassword
        }

        let (rotated, newCodes) = try await Self.makeRecovery(authKey: authKey, vaultKey: vaultKey)
        let deviceEnvelope = try Ecdh.packDeviceEnvelope(vaultKey: vaultKey, recipientPublicKey: ecdhKey.publicKey)

        let response: RefreshResponse
        do {
            response = try await recoveryApi.completeRecovery(
                sessionId: pending.sessionId, replacementDeviceId: replacementDeviceId,
                deviceEnvelope: deviceEnvelope, rotatedRecovery: rotated)
        } catch ApiError.http(404, _) {
            try await forgetPendingRecovery()
            throw RecoveryError.sessionGone
        }

        // The server has changed (codes rotated, session completed): from here on, keep what we have even
        // if the response carries no tokens, because the new codes must still reach the user.
        try await persistTokens(response.accessToken, response.refreshToken)
        let signedIn = response.accessToken != nil && response.refreshToken != nil
        let localKey = try await Self.localAuthKey(kdf: kdf, serverAuthKey: authKey, password: password, salt: salt)
        try await adopt(vaultKey: vaultKey, replacing: localVaultKey, salt: salt, authKey: localKey,
                        session: (pending.serverUrl, response.userId ?? replacementDeviceId, replacementDeviceId, pending.email),
                        connected: signedIn)
        try await forgetPendingRecovery()
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
            try? secrets.setAll([.accessToken: access, .refreshToken: refresh])
        }
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
        let verifier = KeyDerivation.deriveVerifier(authKey: authKey)
        let wrapped = try AesGcm.encrypt(key: KeyDerivation.deriveEnvelopeKey(authKey: authKey), plaintext: vaultKey)
        try await repository.replaceVaultKey(from: localVaultKey, to: vaultKey, settings: [
            SettingsKeys.kdfSalt: salt.base64EncodedString(),
            SettingsKeys.passwordVerifier: verifier.base64EncodedString(),
            SettingsKeys.encryptedVaultKey: wrapped.base64EncodedString(),
            SettingsKeys.serverUrl: session.serverUrl, SettingsKeys.userId: session.userId,
            SettingsKeys.deviceId: session.deviceId, SettingsKeys.email: session.email,
            SettingsKeys.mode: connected ? SettingsKeys.modeConnected : SettingsKeys.modeStandalone,
        ])
        // A stale biometric copy would decrypt to the old key and break entry decryption.
        if vaultKey != localVaultKey { await invalidateBiometric() }
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
