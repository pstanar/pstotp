using System.Text.Json;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Infrastructure.Services;

public class AuditService(AppDbContext db) : IAuditService
{
    public void LogEvent(
        string eventType,
        Guid? userId = null,
        Guid? deviceId = null,
        object? eventData = null,
        string? ipAddress = null,
        string? userAgent = null)
    {
        db.AuditEvents.Add(new AuditEvent
        {
            Id = Guid.NewGuid(),
            UserId = userId,
            DeviceId = deviceId,
            EventType = eventType,
            EventData = eventData != null ? JsonSerializer.Serialize(eventData) : null,
            IpAddress = ipAddress,
            UserAgent = userAgent,
            CreatedAt = DateTime.UtcNow,
        });
    }
}
