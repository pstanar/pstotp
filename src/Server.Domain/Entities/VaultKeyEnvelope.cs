namespace PsTotp.Server.Domain.Entities;

public class VaultKeyEnvelope
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public Guid? DeviceId { get; set; }
    public required EnvelopeType EnvelopeType { get; set; }
    public required byte[] WrappedKeyPayload { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? RevokedAt { get; set; }

    public User User { get; set; } = null!;
    public Device? Device { get; set; }
}

public enum EnvelopeType
{
    Password,
    Device,
    Recovery
}
