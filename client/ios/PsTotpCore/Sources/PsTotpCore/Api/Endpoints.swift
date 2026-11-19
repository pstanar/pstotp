import Foundation

// One struct per Android `*Api` class; each method is a thin wire call.

/// Authentication endpoints (public — no Bearer token) plus password change and logout.
public struct AuthApi: Sendable {
    let client: ApiClient
    public init(client: ApiClient) { self.client = client }

    public func requestLoginChallenge(email: String, device: DeviceDto) async throws -> LoginChallengeResponse {
        struct Body: Encodable, Sendable { let email: String; let device: DeviceDto }
        return try await client.postPublic("/auth/login", body: Body(email: email, device: device))
    }

    public func completeLogin(_ proof: ClientProofDto) async throws -> LoginCompleteResponse {
        try await client.postPublic("/auth/login/complete", body: proof)
    }

    public func registerBegin(email: String) async throws -> BeginRegistrationResponse {
        struct Body: Encodable, Sendable { let email: String }
        return try await client.postPublic("/auth/register/begin", body: Body(email: email))
    }

    public func verifyEmail(registrationSessionId: String, verificationCode: String) async throws -> Bool {
        struct Body: Encodable, Sendable { let registrationSessionId: String; let verificationCode: String }
        struct Reply: Decodable, Sendable { let verified: Bool }
        let reply: Reply = try await client.postPublic(
            "/auth/register/verify-email",
            body: Body(registrationSessionId: registrationSessionId, verificationCode: verificationCode))
        return reply.verified
    }

    public func register(
        registrationSessionId: String?, email: String, passwordVerifier: PasswordVerifierDto,
        passwordEnvelope: Envelope, device: DeviceDto, deviceEnvelope: Envelope, recovery: RecoveryDto
    ) async throws -> RegisterResponse {
        struct Body: Encodable, Sendable {
            let registrationSessionId: String?
            let email: String
            let passwordVerifier: PasswordVerifierDto
            let passwordEnvelope: Envelope
            let device: DeviceDto
            let deviceEnvelope: Envelope
            let recovery: RecoveryDto
        }
        return try await client.postPublic("/auth/register", body: Body(
            registrationSessionId: registrationSessionId, email: email, passwordVerifier: passwordVerifier,
            passwordEnvelope: passwordEnvelope, device: device, deviceEnvelope: deviceEnvelope, recovery: recovery))
    }

    /// Returns the new tokens (the server rotates them on a password change).
    public func changePassword(
        currentProof: ClientProofDto, newVerifier: PasswordVerifierDto, newPasswordEnvelope: Envelope
    ) async throws -> RefreshResponse {
        struct Body: Encodable, Sendable {
            let currentProof: ClientProofDto
            let newVerifier: PasswordVerifierDto
            let newPasswordEnvelope: Envelope
        }
        return try await client.post("/account/password/change", body: Body(
            currentProof: currentProof, newVerifier: newVerifier, newPasswordEnvelope: newPasswordEnvelope))
    }

    /// Best effort: the server may be unreachable.
    public func logout() async {
        struct Body: Encodable, Sendable { let refreshToken: String? }
        let token = await client.refreshToken
        let _: EmptyResponse? = try? await client.postPublic("/auth/logout", body: Body(refreshToken: token))
    }
}

/// Vault sync endpoints (authenticated).
public struct VaultApi: Sendable {
    let client: ApiClient
    public init(client: ApiClient) { self.client = client }

    public func fetchVault() async throws -> VaultSyncResponse { try await client.get("/vault") }

    public func upsertEntry(entryId: String, entryPayload: String, entryVersion: Int) async throws -> VaultEntryUpsertResponse {
        struct Body: Encodable, Sendable { let entryPayload: String; let entryVersion: Int }
        return try await client.put("/vault/\(entryId)", body: Body(entryPayload: entryPayload, entryVersion: entryVersion))
    }

    public func deleteEntry(entryId: String) async throws { try await client.delete("/vault/\(entryId)") }

    public func reorderEntries(entryIds: [String]) async throws {
        struct Body: Encodable, Sendable { let entryIds: [String] }
        let _: EmptyResponse = try await client.post("/vault/reorder", body: Body(entryIds: entryIds))
    }
}

/// Device management endpoints (authenticated).
public struct DevicesApi: Sendable {
    let client: ApiClient
    public init(client: ApiClient) { self.client = client }

    public func fetchDevices() async throws -> DeviceListResponse { try await client.get("/devices") }

    public func approveDevice(deviceId: String, approvalRequestId: String, deviceEnvelope: Envelope) async throws {
        struct ApprovalAuth: Encodable, Sendable { let type = "device" }
        struct Body: Encodable, Sendable {
            let approvalRequestId: String
            let approvalAuth: ApprovalAuth
            let deviceEnvelope: Envelope
        }
        let _: EmptyResponse = try await client.post("/devices/\(deviceId)/approve", body: Body(
            approvalRequestId: approvalRequestId, approvalAuth: ApprovalAuth(), deviceEnvelope: deviceEnvelope))
    }

    public func rejectDevice(deviceId: String) async throws {
        let _: EmptyResponse = try await client.post("/devices/\(deviceId)/reject")
    }

    public func revokeDevice(deviceId: String) async throws {
        let _: EmptyResponse = try await client.post("/devices/\(deviceId)/revoke")
    }

    public func updateSelfEnvelope(_ envelope: Envelope) async throws {
        let _: EmptyResponse = try await client.put("/devices/self/envelope", body: envelope)
    }
}

/// Audit events (authenticated).
public struct AuditApi: Sendable {
    let client: ApiClient
    public init(client: ApiClient) { self.client = client }

    public func fetchEvents(limit: Int = 50) async throws -> AuditEventListResponse {
        try await client.get("/security/audit-events?limit=\(limit)")
    }
}

/// Recovery flow endpoints (public, except regenerate).
public struct RecoveryApi: Sendable {
    let client: ApiClient
    public init(client: ApiClient) { self.client = client }

    public func redeemRecoveryCode(email: String, recoveryCode: String, verifierProof: ClientProofDto) async throws -> RecoveryRedeemResponse {
        struct Body: Encodable, Sendable { let email: String; let recoveryCode: String; let verifierProof: ClientProofDto }
        return try await client.postPublic("/recovery/codes/redeem",
                                           body: Body(email: email, recoveryCode: recoveryCode, verifierProof: verifierProof))
    }

    public func getRecoveryMaterial(sessionId: String, replacementDevice: DeviceDto) async throws -> RecoveryMaterialResponse {
        struct Body: Encodable, Sendable { let replacementDevice: DeviceDto }
        return try await client.postPublic("/recovery/session/\(sessionId)/material", body: Body(replacementDevice: replacementDevice))
    }

    public func regenerateCodes(rotatedRecovery: RecoveryDto) async throws {
        struct Body: Encodable, Sendable { let rotatedRecovery: RecoveryDto }
        let _: EmptyResponse = try await client.post("/recovery/codes/regenerate", body: Body(rotatedRecovery: rotatedRecovery))
    }

    public func completeRecovery(
        sessionId: String, replacementDeviceId: String, deviceEnvelope: Envelope, rotatedRecovery: RecoveryDto
    ) async throws -> RefreshResponse {
        struct Body: Encodable, Sendable {
            let replacementDeviceId: String
            let deviceEnvelope: Envelope
            let rotatedRecovery: RecoveryDto
        }
        return try await client.postPublic("/recovery/session/\(sessionId)/complete", body: Body(
            replacementDeviceId: replacementDeviceId, deviceEnvelope: deviceEnvelope, rotatedRecovery: rotatedRecovery))
    }
}

/// WebAuthn / passkey endpoints.
public struct WebAuthnApi: Sendable {
    let client: ApiClient
    public init(client: ApiClient) { self.client = client }

    // Registration (authenticated)

    public func beginRegistration() async throws -> WebAuthnBeginResponse {
        try await client.post("/webauthn/register/begin")
    }

    public func completeRegistration(ceremonyId: String, friendlyName: String, attestationResponseJson: String) async throws {
        struct Body: Encodable, Sendable { let ceremonyId: String; let friendlyName: String; let attestationResponse: JSONValue }
        let _: EmptyResponse = try await client.post("/webauthn/register/complete", body: Body(
            ceremonyId: ceremonyId, friendlyName: friendlyName,
            attestationResponse: try JSONValue(jsonString: attestationResponseJson)))
    }

    // Assertion (public — login or recovery step-up)

    public func beginAssertion(email: String? = nil, recoverySessionId: String? = nil) async throws -> WebAuthnBeginResponse {
        struct Body: Encodable, Sendable { let email: String?; let recoverySessionId: String? }
        return try await client.postPublic("/webauthn/assert/begin", body: Body(email: email, recoverySessionId: recoverySessionId))
    }

    public func completeAssertionForLogin(ceremonyId: String, assertionResponseJson: String, device: DeviceDto) async throws -> LoginCompleteResponse {
        struct Body: Encodable, Sendable { let ceremonyId: String; let assertionResponse: JSONValue; let device: DeviceDto }
        return try await client.postPublic("/webauthn/assert/complete", body: Body(
            ceremonyId: ceremonyId, assertionResponse: try JSONValue(jsonString: assertionResponseJson), device: device))
    }

    public func completeAssertionForRecovery(ceremonyId: String, assertionResponseJson: String) async throws {
        struct Body: Encodable, Sendable { let ceremonyId: String; let assertionResponse: JSONValue }
        let _: EmptyResponse = try await client.postPublic("/webauthn/assert/complete", body: Body(
            ceremonyId: ceremonyId, assertionResponse: try JSONValue(jsonString: assertionResponseJson)))
    }

    // Credential management (authenticated)

    public func listCredentials() async throws -> [WebAuthnCredentialInfo] {
        struct Reply: Decodable, Sendable { let credentials: [WebAuthnCredentialInfo] }
        let reply: Reply = try await client.get("/webauthn/credentials")
        return reply.credentials
    }

    public func renameCredential(credentialId: String, friendlyName: String) async throws {
        struct Body: Encodable, Sendable { let friendlyName: String }
        let _: EmptyResponse = try await client.put("/webauthn/credentials/\(credentialId)/rename", body: Body(friendlyName: friendlyName))
    }

    public func revokeCredential(credentialId: String) async throws {
        let _: EmptyResponse = try await client.post("/webauthn/credentials/\(credentialId)/revoke")
    }
}

/// Icon-library blob (authenticated).
public struct IconLibraryApi: Sendable {
    let client: ApiClient
    public init(client: ApiClient) { self.client = client }

    public func fetch() async throws -> IconLibraryResponse { try await client.get("/vault/icon-library") }

    public func update(encryptedPayload: String, expectedVersion: Int) async throws -> IconLibraryUpdateResponse {
        struct Body: Encodable, Sendable { let encryptedPayload: String; let expectedVersion: Int }
        return try await client.put("/vault/icon-library", body: Body(encryptedPayload: encryptedPayload, expectedVersion: expectedVersion))
    }
}
