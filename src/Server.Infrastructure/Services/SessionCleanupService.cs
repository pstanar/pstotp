using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Infrastructure.Services;

public partial class SessionCleanupService(
    IServiceScopeFactory scopeFactory,
    ILogger<SessionCleanupService> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromHours(1);
    private static readonly TimeSpan CompletedRetention = TimeSpan.FromDays(30);

    [LoggerMessage(Level = LogLevel.Error, Message = "Session cleanup failed")]
    private partial void LogCleanupFailed(Exception ex);

    [LoggerMessage(
        Level = LogLevel.Information,
        Message = "Cleanup: {Logins} login, {Registrations} registration, {Recovery} recovery, {OldRecovery} old recovery, {Ceremonies} ceremonies, {Tokens} tokens, {Entries} entries, {Devices} devices, {Envelopes} envelopes, {Credentials} credentials removed")]
    private partial void LogCleanupSummary(
        int logins, int registrations, int recovery, int oldRecovery, int ceremonies,
        int tokens, int entries, int devices, int envelopes, int credentials);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await CleanupAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                LogCleanupFailed(ex);
            }

            await Task.Delay(Interval, stoppingToken);
        }
    }

    private async Task CleanupAsync(CancellationToken ct)
    {
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var now = DateTime.UtcNow;
        var retentionCutoff = now - CompletedRetention;

        // Expired login sessions
        var expiredLogins = await db.LoginSessions
            .Where(s => s.ExpiresAt < now)
            .ExecuteDeleteAsync(ct);

        // Expired registration sessions
        var expiredRegistrations = await db.RegistrationSessions
            .Where(s => s.ExpiresAt < now)
            .ExecuteDeleteAsync(ct);

        // Expired pending recovery sessions
        var expiredRecovery = await db.RecoverySessions
            .Where(s => s.ExpiresAt < now && s.Status == RecoverySessionStatus.Pending)
            .ExecuteUpdateAsync(s => s
                .SetProperty(e => e.Status, RecoverySessionStatus.Expired),
            ct);

        // Old completed/cancelled recovery sessions
        var oldRecovery = await db.RecoverySessions
            .Where(s => (s.Status == RecoverySessionStatus.Completed || s.Status == RecoverySessionStatus.Cancelled)
                        && s.CreatedAt < retentionCutoff)
            .ExecuteDeleteAsync(ct);

        // Expired password reset sessions
        var expiredResets = await db.PasswordResetSessions
            .Where(s => s.ExpiresAt < now)
            .ExecuteDeleteAsync(ct);

        // Expired WebAuthn ceremonies
        var expiredCeremonies = await db.WebAuthnCeremonies
            .Where(c => c.ExpiresAt < now)
            .ExecuteDeleteAsync(ct);

        // Expired or revoked refresh tokens older than retention period
        var oldTokens = await db.RefreshTokens
            .Where(t => (t.ExpiresAt < now || t.RevokedAt != null) && t.CreatedAt < retentionCutoff)
            .ExecuteDeleteAsync(ct);

        // Soft-deleted vault entries older than retention period
        var deletedEntries = await db.VaultEntries
            .Where(e => e.DeletedAt != null && e.DeletedAt < retentionCutoff)
            .ExecuteDeleteAsync(ct);

        // Revoked devices older than retention period
        var revokedDevices = await db.Devices
            .Where(d => d.RevokedAt != null && d.RevokedAt < retentionCutoff)
            .ExecuteDeleteAsync(ct);

        // Revoked vault key envelopes older than retention period
        var revokedEnvelopes = await db.VaultKeyEnvelopes
            .Where(e => e.RevokedAt != null && e.RevokedAt < retentionCutoff)
            .ExecuteDeleteAsync(ct);

        // Revoked WebAuthn credentials older than retention period
        var revokedCredentials = await db.WebAuthnCredentials
            .Where(c => c.RevokedAt != null && c.RevokedAt < retentionCutoff)
            .ExecuteDeleteAsync(ct);

        var total = expiredLogins + expiredRegistrations + expiredResets + expiredRecovery + oldRecovery
                    + expiredCeremonies + oldTokens + deletedEntries + revokedDevices + revokedEnvelopes + revokedCredentials;
        if (total > 0)
        {
            LogCleanupSummary(
                expiredLogins, expiredRegistrations, expiredRecovery, oldRecovery, expiredCeremonies,
                oldTokens, deletedEntries, revokedDevices, revokedEnvelopes, revokedCredentials);
        }
    }
}
