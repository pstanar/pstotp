namespace PsTotp.Server.Domain.Entities;

public enum UserRole
{
    User,
    Admin,
}

public class User
{
    public Guid Id { get; set; }
    public required string Email { get; set; }
    public required byte[] PasswordVerifier { get; set; }
    public required string PasswordKdfConfig { get; set; } // JSON
    public UserRole Role { get; set; }
    public DateTime? DisabledAt { get; set; }
    public bool ForcePasswordReset { get; set; }
    public string? RecoveryCodeSalt { get; set; } // Base64, independent of password KDF salt
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? LastLoginAt { get; set; }

    public List<Device> Devices { get; set; } = [];
    public List<VaultEntry> VaultEntries { get; set; } = [];
    public List<VaultKeyEnvelope> VaultKeyEnvelopes { get; set; } = [];
    public List<RecoveryCode> RecoveryCodes { get; set; } = [];
    public List<WebAuthnCredential> WebAuthnCredentials { get; set; } = [];
    public List<AuditEvent> AuditEvents { get; set; } = [];
}
