namespace PsTotp.Server.Application.Services;

public interface IAuditService
{
    void LogEvent(
        string eventType,
        Guid? userId = null,
        Guid? deviceId = null,
        object? eventData = null,
        string? ipAddress = null,
        string? userAgent = null);
}
