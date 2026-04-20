namespace PsTotp.Server.Domain.Entities;

public class Device
{
    public Guid Id { get; set; }
    public Guid UserId { get; set; }
    public required string DeviceName { get; set; }
    public required string Platform { get; set; }
    public required string ClientType { get; set; }
    public required DeviceStatus Status { get; set; }
    public string? DevicePublicKey { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime? ApprovedAt { get; set; }
    public DateTime? LastSeenAt { get; set; }
    public DateTime? RevokedAt { get; set; }

    public User User { get; set; } = null!;
}

public enum DeviceStatus
{
    Pending,
    Approved,
    Revoked
}
