namespace PsTotp.Server.Domain.Entities;

public class RecoveryCode
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public required string CodeHash { get; set; }
    public int CodeSlot { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? UsedAt { get; set; }
    public DateTime? ReplacedAt { get; set; }

    public User User { get; set; } = null!;
}
