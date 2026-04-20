namespace PsTotp.Server.Domain.Entities;

public enum WebAuthnCeremonyType
{
    Register,
    Assert,
}

public class WebAuthnCeremony
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public WebAuthnCeremonyType CeremonyType { get; set; }
    public required string OptionsJson { get; set; }
    public Guid? RecoverySessionId { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public bool IsCompleted { get; set; }
}
