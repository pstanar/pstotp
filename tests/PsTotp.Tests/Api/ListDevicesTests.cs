using System.Net;
using System.Net.Http.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Domain.Entities;
using PsTotp.Tests.Infrastructure;

namespace PsTotp.Tests.Api;

[TestClass]
public class ListDevicesTests : IntegrationTestBase
{
    [TestMethod]
    public async Task List_Sorts_Approved_By_ApprovedAt_Desc_With_Pending_Last()
    {
        // Register creates the caller's approved device with ApprovedAt=now.
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (register, client) = await RegisterTestUserAsync(email);
        var callerDeviceId = Guid.Parse(register.DeviceId);

        // Seed the DB with:
        //   - an older approved device
        //   - a revoked device (which still has ApprovedAt populated)
        //   - a newer pending device (null ApprovedAt — should fall to the bottom)
        Guid userId;
        var now = DateTime.UtcNow;
        var olderApprovedId = Guid.NewGuid();
        var revokedId = Guid.NewGuid();
        var pendingId = Guid.NewGuid();
        {
            var (scope, db) = GetDbContext();
            using (scope)
            {
                var user = await db.Users.FirstAsync(u => u.Email == email, TestContext.CancellationToken);
                userId = user.Id;

                // Normalise the caller's ApprovedAt so ordering is deterministic
                // relative to the rows we're about to insert.
                var caller = await db.Devices.FirstAsync(d => d.Id == callerDeviceId, TestContext.CancellationToken);
                caller.ApprovedAt = now;

                db.Devices.AddRange(
                    new Device
                    {
                        Id = olderApprovedId,
                        UserId = userId,
                        DeviceName = "Older Approved",
                        Platform = "web",
                        ClientType = "web",
                        Status = DeviceStatus.Approved,
                        CreatedAt = now.AddHours(-2),
                        ApprovedAt = now.AddHours(-1),
                    },
                    new Device
                    {
                        Id = revokedId,
                        UserId = userId,
                        DeviceName = "Revoked",
                        Platform = "web",
                        ClientType = "web",
                        Status = DeviceStatus.Revoked,
                        CreatedAt = now.AddHours(-3),
                        ApprovedAt = now.AddHours(-2),
                        RevokedAt = now.AddMinutes(-30),
                    },
                    new Device
                    {
                        Id = pendingId,
                        UserId = userId,
                        DeviceName = "Pending",
                        Platform = "web",
                        ClientType = "web",
                        Status = DeviceStatus.Pending,
                        DevicePublicKey = "AAAA",
                        CreatedAt = now.AddMinutes(-5),
                        ApprovedAt = null,
                    }
                );
                await db.SaveChangesAsync(TestContext.CancellationToken);
            }
        }

        var response = await client.GetAsync("/api/devices", TestContext.CancellationToken);
        Assert.AreEqual(HttpStatusCode.OK, response.StatusCode);

        var payload = await response.Content.ReadFromJsonAsync<DeviceListResponse>(JsonOptions, TestContext.CancellationToken);
        Assert.IsNotNull(payload);

        var ids = payload.Devices.Select(d => d.DeviceId).ToList();

        // Caller was approved "now" → newest ApprovedAt wins, comes first.
        // Older-approved (1h ago) is second.
        // Revoked has ApprovedAt 2h ago → third.
        // Pending has null ApprovedAt → last (HasValue sort).
        Assert.AreEqual(4, ids.Count);
        Assert.AreEqual(callerDeviceId, ids[0], "Caller (newest approval) should be first");
        Assert.AreEqual(olderApprovedId, ids[1]);
        Assert.AreEqual(revokedId, ids[2]);
        Assert.AreEqual(pendingId, ids[3], "Pending (null ApprovedAt) should be last");
    }

    [TestMethod]
    public async Task List_Includes_RevokedAt_In_Response()
    {
        var email = $"test-{Guid.NewGuid():N}@example.com";
        var (_, client) = await RegisterTestUserAsync(email);

        var revokedId = Guid.NewGuid();
        var revokedAt = DateTime.UtcNow.AddMinutes(-10);
        {
            var (scope, db) = GetDbContext();
            using (scope)
            {
                var user = await db.Users.FirstAsync(u => u.Email == email, TestContext.CancellationToken);
                db.Devices.Add(new Device
                {
                    Id = revokedId,
                    UserId = user.Id,
                    DeviceName = "Revoked",
                    Platform = "web",
                    ClientType = "web",
                    Status = DeviceStatus.Revoked,
                    CreatedAt = revokedAt.AddHours(-1),
                    ApprovedAt = revokedAt.AddMinutes(-30),
                    RevokedAt = revokedAt,
                });
                await db.SaveChangesAsync(TestContext.CancellationToken);
            }
        }

        var response = await client.GetAsync("/api/devices", TestContext.CancellationToken);
        var payload = await response.Content.ReadFromJsonAsync<DeviceListResponse>(JsonOptions, TestContext.CancellationToken);
        Assert.IsNotNull(payload);

        var revoked = payload.Devices.FirstOrDefault(d => d.DeviceId == revokedId);
        Assert.IsNotNull(revoked, "Revoked device should appear in the list");
        Assert.IsNotNull(revoked.RevokedAt, "RevokedAt should be populated in the DTO so clients can sort");
    }

    public TestContext TestContext { get; set; } = null!;
}
