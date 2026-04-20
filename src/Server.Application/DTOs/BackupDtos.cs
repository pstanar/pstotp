namespace PsTotp.Server.Application.DTOs;

public sealed record BackupRequest(string Password);

public sealed record BackupFileHeader(
    int Version,
    string Format,
    DateTime ExportedAt,
    string Salt,
    string Payload);

public sealed record BackupData(
    List<BackupUser> Users,
    List<BackupDevice> Devices,
    List<BackupVaultEntry> VaultEntries,
    List<BackupVaultKeyEnvelope> VaultKeyEnvelopes,
    List<BackupRecoveryCode> RecoveryCodes,
    List<BackupWebAuthnCredential> WebAuthnCredentials,
    List<BackupAuditEvent> AuditEvents);

public sealed record BackupUser(
    Guid Id, string Email, string PasswordVerifier, string PasswordKdfConfig,
    string Role, DateTime? DisabledAt, bool ForcePasswordReset,
    DateTime CreatedAt, DateTime UpdatedAt, DateTime? LastLoginAt,
    string? RecoveryCodeSalt = null);

public sealed record BackupDevice(
    Guid Id, Guid UserId, string DeviceName, string Platform, string ClientType,
    string Status, string? DevicePublicKey,
    DateTime CreatedAt, DateTime? ApprovedAt, DateTime? LastSeenAt, DateTime? RevokedAt);

public sealed record BackupVaultEntry(
    Guid Id, Guid UserId, string EntryPayload, int EntryVersion, int SortOrder,
    DateTime CreatedAt, DateTime UpdatedAt, DateTime? DeletedAt);

public sealed record BackupVaultKeyEnvelope(
    Guid Id, Guid UserId, Guid? DeviceId, string EnvelopeType,
    string WrappedKeyPayload, DateTime CreatedAt, DateTime? RevokedAt);

public sealed record BackupRecoveryCode(
    Guid Id, Guid UserId, string CodeHash, int CodeSlot,
    DateTime CreatedAt, DateTime? UsedAt, DateTime? ReplacedAt);

public sealed record BackupWebAuthnCredential(
    Guid Id, Guid UserId, string CredentialId, string PublicKey,
    long? SignCount, string? FriendlyName, string? Transports,
    DateTime CreatedAt, DateTime? LastUsedAt, DateTime? RevokedAt);

public sealed record BackupAuditEvent(
    Guid Id, Guid? UserId, Guid? DeviceId, string EventType,
    string? EventData, string? IpAddress, string? UserAgent, DateTime CreatedAt);
