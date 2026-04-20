namespace PsTotp.Server.Domain.Entities;

public class VaultEntry
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public required byte[] EntryPayload { get; set; }
    public int EntryVersion { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
    public DateTime? DeletedAt { get; set; }
    public int SortOrder { get; set; }

    public User User { get; set; } = null!;
}
