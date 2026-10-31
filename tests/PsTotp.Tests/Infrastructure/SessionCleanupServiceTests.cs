using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;
using PsTotp.Server.Infrastructure.Services;

namespace PsTotp.Tests.Infrastructure;

[TestClass]
public class SessionCleanupServiceTests
{
    private SqliteConnection _connection = null!;
    private ServiceProvider _provider = null!;

    [TestInitialize]
    public void TestSetUp()
    {
        // Real SQLite so FOREIGN KEY constraints are enforced like in production.
        _connection = new SqliteConnection("DataSource=:memory:");
        _connection.Open();

        _provider = new ServiceCollection()
            .AddDbContext<AppDbContext>(o => o.UseSqlite(_connection))
            .BuildServiceProvider();

        using var scope = _provider.CreateScope();
        scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.EnsureCreated();
    }

    [TestCleanup]
    public void TestTearDown()
    {
        _provider.Dispose();
        _connection.Dispose();
    }

    private SessionCleanupService CreateService() =>
        new(_provider.GetRequiredService<IServiceScopeFactory>(), NullLogger<SessionCleanupService>.Instance);

    private static Device NewDevice(Guid userId, DateTime? revokedAt) => new()
    {
        Id = Guid.NewGuid(),
        UserId = userId,
        DeviceName = "test",
        Platform = "test",
        ClientType = "web",
        Status = revokedAt is null ? DeviceStatus.Approved : DeviceStatus.Revoked,
        CreatedAt = DateTime.UtcNow.AddDays(-120),
        RevokedAt = revokedAt,
    };

    [TestMethod]
    public async Task Cleanup_DeletesOldRevokedDevice_WithDependentRows_AndKeepsAuditTrail()
    {
        var userId = Guid.NewGuid();
        var staleDevice = NewDevice(userId, DateTime.UtcNow.AddDays(-60));
        var recentlyRevoked = NewDevice(userId, DateTime.UtcNow.AddDays(-2));
        var activeDevice = NewDevice(userId, null);
        var auditId = Guid.NewGuid();

        using (var scope = _provider.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            db.Users.Add(new User
            {
                Id = userId,
                Email = "cleanup@example.com",
                PasswordVerifier = [1],
                PasswordKdfConfig = "{}",
            });
            db.Devices.AddRange(staleDevice, recentlyRevoked, activeDevice);
            await db.SaveChangesAsync();

            db.VaultKeyEnvelopes.AddRange(
                new VaultKeyEnvelope
                {
                    Id = Guid.NewGuid(), UserId = userId, DeviceId = staleDevice.Id,
                    EnvelopeType = EnvelopeType.Device, WrappedKeyPayload = [1],
                    CreatedAt = DateTime.UtcNow.AddDays(-120), RevokedAt = staleDevice.RevokedAt,
                },
                new VaultKeyEnvelope
                {
                    Id = Guid.NewGuid(), UserId = userId, DeviceId = activeDevice.Id,
                    EnvelopeType = EnvelopeType.Device, WrappedKeyPayload = [1],
                    CreatedAt = DateTime.UtcNow.AddDays(-1),
                });
            db.RefreshTokens.AddRange(
                new RefreshToken
                {
                    Id = Guid.NewGuid(), UserId = userId, DeviceId = staleDevice.Id, TokenHash = "stale",
                    CreatedAt = DateTime.UtcNow.AddDays(-120), ExpiresAt = DateTime.UtcNow.AddDays(-90),
                },
                new RefreshToken
                {
                    Id = Guid.NewGuid(), UserId = userId, DeviceId = activeDevice.Id, TokenHash = "active",
                    CreatedAt = DateTime.UtcNow.AddDays(-1), ExpiresAt = DateTime.UtcNow.AddDays(29),
                });
            db.AuditEvents.Add(new AuditEvent
            {
                Id = auditId, UserId = userId, DeviceId = staleDevice.Id,
                EventType = "device.revoked", CreatedAt = DateTime.UtcNow.AddDays(-60),
            });
            await db.SaveChangesAsync();
        }

        await CreateService().CleanupAsync(CancellationToken.None);

        using var verify = _provider.CreateScope();
        var check = verify.ServiceProvider.GetRequiredService<AppDbContext>();

        var deviceIds = await check.Devices.Select(d => d.Id).ToListAsync();
        CollectionAssert.AreEquivalent(new[] { recentlyRevoked.Id, activeDevice.Id }, deviceIds);

        Assert.IsFalse(await check.VaultKeyEnvelopes.AnyAsync(e => e.DeviceId == staleDevice.Id));
        Assert.IsTrue(await check.VaultKeyEnvelopes.AnyAsync(e => e.DeviceId == activeDevice.Id));
        Assert.IsFalse(await check.RefreshTokens.AnyAsync(t => t.DeviceId == staleDevice.Id));
        Assert.IsTrue(await check.RefreshTokens.AnyAsync(t => t.DeviceId == activeDevice.Id));

        var audit = await check.AuditEvents.SingleAsync(a => a.Id == auditId);
        Assert.IsNull(audit.DeviceId);
    }
}
