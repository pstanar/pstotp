namespace PsTotp.Server.Domain.Entities;

public class WebAuthnCredential
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public required byte[] CredentialId { get; set; }
    public required byte[] PublicKey { get; set; }
    public long? SignCount { get; set; }
    public string? FriendlyName { get; set; }
    public string? Transports { get; set; } // JSON
    public DateTime CreatedAt { get; set; }
    public DateTime? LastUsedAt { get; set; }
    public DateTime? RevokedAt { get; set; }

    public User User { get; set; } = null!;
}
