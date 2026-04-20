namespace PsTotp.Server.Domain.Entities;

public class AuditEvent
{
    public Guid Id { get; set; }
    public Guid? UserId { get; set; }
    public Guid? DeviceId { get; set; }
    public required string EventType { get; set; }
    public string? EventData { get; set; } // JSON
    public string? IpAddress { get; set; }
    public string? UserAgent { get; set; }
    public DateTime CreatedAt { get; set; }

    public User? User { get; set; }
    public Device? Device { get; set; }
}
