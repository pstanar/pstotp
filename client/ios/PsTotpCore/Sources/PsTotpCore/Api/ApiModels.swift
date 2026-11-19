import Foundation

extension KeyedDecodingContainer {
    /// Mirrors Android's `optStringOrNull`: absent, JSON null and "" all become nil
    /// (server DTOs encode optional tokens / GUIDs that way).
    func decodeNonEmpty(_ key: Key) throws -> String? {
        guard let value = try decodeIfPresent(String.self, forKey: key), !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Shared request/response pieces

/// KDF configuration returned by the server in login challenges.
public struct KdfConfig: Codable, Equatable, Sendable {
    public var algorithm: String
    public var memoryMb: Int
    public var iterations: Int
    public var parallelism: Int
    public var salt: String

    public init(algorithm: String, memoryMb: Int, iterations: Int, parallelism: Int, salt: String) {
        self.algorithm = algorithm
        self.memoryMb = memoryMb
        self.iterations = iterations
        self.parallelism = parallelism
        self.salt = salt
    }

    /// The pinned defaults (Argon2id, 64 MB, t=3, p=4) with the given base64 salt.
    public static func `default`(saltBase64: String) -> KdfConfig {
        KdfConfig(algorithm: "argon2id", memoryMb: 64, iterations: 3, parallelism: 4, salt: saltBase64)
    }
}

/// Encrypted envelope (password, device or recovery).
public struct Envelope: Codable, Equatable, Sendable {
    public var ciphertext: String
    public var nonce: String
    public var version: Int

    public init(ciphertext: String, nonce: String, version: Int = 1) {
        self.ciphertext = ciphertext
        self.nonce = nonce
        self.version = version
    }
}

/// Device info sent during login and registration.
public struct DeviceDto: Codable, Equatable, Sendable {
    public var deviceName: String
    public var platform: String
    public var clientType: String
    public var devicePublicKey: String

    public init(deviceName: String, platform: String, clientType: String, devicePublicKey: String) {
        self.deviceName = deviceName
        self.platform = platform
        self.clientType = clientType
        self.devicePublicKey = devicePublicKey
    }

    /// This iOS device, with its ECDH public key (base64).
    public static func ios(publicKeyBase64: String) -> DeviceDto {
        DeviceDto(deviceName: "PsTotp on iOS", platform: "ios", clientType: "ios", devicePublicKey: publicKeyBase64)
    }
}

/// Password verifier with KDF config, sent during registration and password change.
public struct PasswordVerifierDto: Codable, Equatable, Sendable {
    public var verifier: String
    public var kdf: KdfConfig

    public init(verifier: String, kdf: KdfConfig) {
        self.verifier = verifier
        self.kdf = kdf
    }
}

/// Recovery-code envelope and hashed codes.
public struct RecoveryDto: Codable, Equatable, Sendable {
    public var recoveryEnvelopeCiphertext: String
    public var recoveryEnvelopeNonce: String
    public var recoveryEnvelopeVersion: Int
    public var recoveryCodeHashes: [String]
    public var recoveryCodeSalt: String?

    public init(
        recoveryEnvelopeCiphertext: String, recoveryEnvelopeNonce: String, recoveryEnvelopeVersion: Int = 1,
        recoveryCodeHashes: [String], recoveryCodeSalt: String? = nil
    ) {
        self.recoveryEnvelopeCiphertext = recoveryEnvelopeCiphertext
        self.recoveryEnvelopeNonce = recoveryEnvelopeNonce
        self.recoveryEnvelopeVersion = recoveryEnvelopeVersion
        self.recoveryCodeHashes = recoveryCodeHashes
        self.recoveryCodeSalt = recoveryCodeSalt
    }
}

/// Step-up proof of password knowledge (a completed login challenge).
public struct ClientProofDto: Codable, Equatable, Sendable {
    public var loginSessionId: String
    public var clientProof: String

    public init(loginSessionId: String, clientProof: String) {
        self.loginSessionId = loginSessionId
        self.clientProof = clientProof
    }
}

// MARK: - Auth

public struct LoginChallenge: Codable, Equatable, Sendable {
    public var nonce: String
    public var kdf: KdfConfig
}

public struct LoginChallengeResponse: Codable, Equatable, Sendable {
    public var loginSessionId: String
    public var challenge: LoginChallenge
}

public struct LoginDeviceInfo: Decodable, Equatable, Sendable {
    public var deviceId: String
    public var status: String
    public var persistentKeyAllowed: Bool

    private enum CodingKeys: String, CodingKey { case deviceId, status, persistentKeyAllowed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try c.decode(String.self, forKey: .deviceId)
        status = try c.decode(String.self, forKey: .status)
        persistentKeyAllowed = try c.decodeIfPresent(Bool.self, forKey: .persistentKeyAllowed) ?? false
    }
}

public struct LoginEnvelopes: Codable, Equatable, Sendable {
    public var password: Envelope?
    public var device: Envelope?
}

public struct LoginCompleteResponse: Decodable, Equatable, Sendable {
    public var userId: String
    public var accessToken: String?
    public var refreshToken: String?
    public var device: LoginDeviceInfo
    public var envelopes: LoginEnvelopes?
    public var approvalRequestId: String?
    public var role: String?
    public var forcePasswordReset: Bool

    private enum CodingKeys: String, CodingKey {
        case userId, accessToken, refreshToken, device, envelopes, approvalRequestId, role, forcePasswordReset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        accessToken = try c.decodeNonEmpty(.accessToken)
        refreshToken = try c.decodeNonEmpty(.refreshToken)
        device = try c.decode(LoginDeviceInfo.self, forKey: .device)
        envelopes = try c.decodeIfPresent(LoginEnvelopes.self, forKey: .envelopes)
        approvalRequestId = try c.decodeNonEmpty(.approvalRequestId)
        role = try c.decodeNonEmpty(.role)
        forcePasswordReset = try c.decodeIfPresent(Bool.self, forKey: .forcePasswordReset) ?? false
    }
}

public struct BeginRegistrationResponse: Decodable, Equatable, Sendable {
    public var registrationSessionId: String
    public var emailVerificationRequired: Bool
    public var verificationCode: String?

    private enum CodingKeys: String, CodingKey { case registrationSessionId, emailVerificationRequired, verificationCode }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        registrationSessionId = try c.decode(String.self, forKey: .registrationSessionId)
        emailVerificationRequired = try c.decode(Bool.self, forKey: .emailVerificationRequired)
        verificationCode = try c.decodeNonEmpty(.verificationCode)
    }
}

public struct RegisterResponse: Decodable, Equatable, Sendable {
    public var userId: String
    public var deviceId: String
    public var accessToken: String?
    public var refreshToken: String?

    private enum CodingKeys: String, CodingKey { case userId, deviceId, accessToken, refreshToken }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        deviceId = try c.decode(String.self, forKey: .deviceId)
        accessToken = try c.decodeNonEmpty(.accessToken)
        refreshToken = try c.decodeNonEmpty(.refreshToken)
    }
}

/// Tokens-only response: `/auth/refresh`, password change, and recovery completion
/// (the latter also carries `userId`).
public struct RefreshResponse: Decodable, Equatable, Sendable {
    public var userId: String?
    public var accessToken: String?
    public var refreshToken: String?

    private enum CodingKeys: String, CodingKey { case userId, accessToken, refreshToken }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeNonEmpty(.userId)
        accessToken = try c.decodeNonEmpty(.accessToken)
        refreshToken = try c.decodeNonEmpty(.refreshToken)
    }
}

// MARK: - Vault & devices

public struct VaultEntryDto: Decodable, Equatable, Sendable {
    public var id: String
    public var entryPayload: String
    public var entryVersion: Int
    public var deletedAt: String?
    public var updatedAt: String
    public var sortOrder: Int

    private enum CodingKeys: String, CodingKey { case id, entryPayload, entryVersion, deletedAt, updatedAt, sortOrder }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        entryPayload = try c.decode(String.self, forKey: .entryPayload)
        entryVersion = try c.decode(Int.self, forKey: .entryVersion)
        deletedAt = try c.decodeNonEmpty(.deletedAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
    }
}

public struct VaultSyncResponse: Decodable, Equatable, Sendable {
    public var entries: [VaultEntryDto]
    public var serverTime: String
}

public struct VaultEntryUpsertResponse: Decodable, Equatable, Sendable {
    public var id: String
    public var entryVersion: Int
    public var updatedAt: String
}

public struct DeviceInfoDto: Decodable, Equatable, Sendable {
    public var deviceId: String
    public var deviceName: String
    public var platform: String
    public var status: String
    public var devicePublicKey: String?
    public var approvalRequestId: String?
    public var approvedAt: String?
    public var revokedAt: String?

    private enum CodingKeys: String, CodingKey {
        case deviceId, deviceName, platform, status, devicePublicKey, approvalRequestId, approvedAt, revokedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try c.decode(String.self, forKey: .deviceId)
        deviceName = try c.decode(String.self, forKey: .deviceName)
        platform = try c.decode(String.self, forKey: .platform)
        status = try c.decode(String.self, forKey: .status)
        devicePublicKey = try c.decodeNonEmpty(.devicePublicKey)
        approvalRequestId = try c.decodeNonEmpty(.approvalRequestId)
        approvedAt = try c.decodeNonEmpty(.approvedAt)
        revokedAt = try c.decodeNonEmpty(.revokedAt)
    }
}

public struct DeviceListResponse: Decodable, Equatable, Sendable {
    public var devices: [DeviceInfoDto]
}

// MARK: - Audit

public struct AuditEventDto: Decodable, Equatable, Sendable {
    public var id: String
    public var eventType: String
    public var eventData: String?
    public var ipAddress: String?
    public var createdAt: String
    public var deviceId: String?

    private enum CodingKeys: String, CodingKey { case id, eventType, eventData, ipAddress, createdAt, deviceId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        eventType = try c.decode(String.self, forKey: .eventType)
        eventData = try c.decodeNonEmpty(.eventData)
        ipAddress = try c.decodeNonEmpty(.ipAddress)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        deviceId = try c.decodeNonEmpty(.deviceId)
    }
}

public struct AuditEventListResponse: Decodable, Equatable, Sendable {
    public var events: [AuditEventDto]
}

// MARK: - Recovery

public struct RecoveryRedeemResponse: Decodable, Equatable, Sendable {
    public var recoverySessionId: String
    public var requiresWebAuthn: Bool
    public var releaseEarliestAt: String

    private enum CodingKeys: String, CodingKey { case recoverySessionId, requiresWebAuthn, releaseEarliestAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recoverySessionId = try c.decode(String.self, forKey: .recoverySessionId)
        requiresWebAuthn = try c.decodeIfPresent(Bool.self, forKey: .requiresWebAuthn) ?? false
        releaseEarliestAt = try c.decode(String.self, forKey: .releaseEarliestAt)
    }
}

public struct RecoveryMaterialResponse: Decodable, Equatable, Sendable {
    public var status: String
    public var recoveryEnvelope: Envelope?
    public var replacementDeviceId: String?
    public var releaseEarliestAt: String?

    private enum CodingKeys: String, CodingKey { case status, recoveryEnvelope, replacementDeviceId, releaseEarliestAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        recoveryEnvelope = try c.decodeIfPresent(Envelope.self, forKey: .recoveryEnvelope)
        replacementDeviceId = try c.decodeNonEmpty(.replacementDeviceId)
        releaseEarliestAt = try c.decodeNonEmpty(.releaseEarliestAt)
    }
}

// MARK: - WebAuthn

public struct WebAuthnBeginResponse: Decodable, Equatable, Sendable {
    public var ceremonyId: String
    /// The server's `publicKeyOptions` object, re-serialised as a JSON string.
    public var publicKeyOptionsJson: String

    private enum CodingKeys: String, CodingKey { case ceremonyId, publicKeyOptions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ceremonyId = try c.decode(String.self, forKey: .ceremonyId)
        publicKeyOptionsJson = try c.decode(JSONValue.self, forKey: .publicKeyOptions).jsonString()
    }
}

public struct WebAuthnCredentialInfo: Decodable, Equatable, Sendable {
    public var id: String
    public var friendlyName: String?
    public var createdAt: String
    public var lastUsedAt: String?
}

// MARK: - Icon library

/// Snapshot of the server's icon-library row: empty payload and version 0 when never written.
public struct IconLibraryResponse: Decodable, Equatable, Sendable {
    public var encryptedPayload: String
    public var version: Int
    public var updatedAt: String?

    private enum CodingKeys: String, CodingKey { case encryptedPayload, version, updatedAt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        encryptedPayload = try c.decodeIfPresent(String.self, forKey: .encryptedPayload) ?? ""
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        updatedAt = try c.decodeNonEmpty(.updatedAt)
    }
}

public struct IconLibraryUpdateResponse: Decodable, Equatable, Sendable {
    public var version: Int
    public var updatedAt: String
}
