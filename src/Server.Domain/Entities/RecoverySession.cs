namespace PsTotp.Server.Domain.Entities;

public class RecoverySession
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public required RecoverySessionStatus Status { get; set; }
    public bool RequiresWebAuthn { get; set; }
    public bool WebAuthnCompleted { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime ReleaseEarliestAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public DateTime? CompletedAt { get; set; }
    public DateTime? CancelledAt { get; set; }
    public Guid? ReplacementDeviceId { get; set; }

    public User User { get; set; } = null!;
}

public enum RecoverySessionStatus
{
    Pending,
    Ready,
    Completed,
    Cancelled,
    Expired
}
