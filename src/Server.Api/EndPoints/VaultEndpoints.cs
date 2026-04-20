using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class VaultEndpoints
{
    public static async Task<IResult> GetVault(
        ClaimsPrincipal user,
        AppDbContext db)
    {
        var userId = DeviceAuthHelper.GetUserId(user);
        if (!await DeviceAuthHelper.IsDeviceApproved(user, db))
            return Results.Forbid();

        var entries = await db.VaultEntries
            .Where(e => e.UserId == userId)
            .OrderBy(e => e.SortOrder)
            .Select(e => new VaultEntryDto(
                e.Id,
                Convert.ToBase64String(e.EntryPayload),
                e.EntryVersion,
                e.DeletedAt,
                e.UpdatedAt,
                e.SortOrder))
            .ToListAsync();

        return Results.Ok(new VaultSyncResponse(entries, DateTime.UtcNow));
    }

    public static async Task<IResult> UpsertEntry(
        Guid entryId,
        VaultEntryUpsertRequest request,
        ClaimsPrincipal user,
        AppDbContext db)
    {
        var userId = DeviceAuthHelper.GetUserId(user);
        if (!await DeviceAuthHelper.IsDeviceApproved(user, db))
            return Results.Forbid();

        var now = DateTime.UtcNow;

        var existing = await db.VaultEntries
            .FirstOrDefaultAsync(e => e.Id == entryId && e.UserId == userId);

        if (existing != null)
        {
            if (existing.EntryVersion != request.EntryVersion)
                return Results.Conflict(new { Error = "Version conflict", CurrentVersion = existing.EntryVersion });

            existing.EntryPayload = Convert.FromBase64String(request.EntryPayload);
            existing.EntryVersion++;
            existing.UpdatedAt = now;

            await db.SaveChangesAsync();
            return Results.Ok(new VaultEntryUpsertResponse(existing.Id, existing.EntryVersion, existing.UpdatedAt));
        }

        // New entry: place at end
        var maxSort = await db.VaultEntries
            .Where(e => e.UserId == userId && e.DeletedAt == null)
            .MaxAsync(e => (int?)e.SortOrder) ?? -1;

        var entry = new VaultEntry
        {
            Id = entryId,
            UserId = userId,
            EntryPayload = Convert.FromBase64String(request.EntryPayload),
            EntryVersion = 1,
            SortOrder = maxSort + 1,
            CreatedAt = now,
            UpdatedAt = now,
        };

        db.VaultEntries.Add(entry);
        await db.SaveChangesAsync();

        return Results.Ok(new VaultEntryUpsertResponse(entry.Id, entry.EntryVersion, entry.UpdatedAt));
    }

    public static async Task<IResult> ReorderEntries(
        VaultReorderRequest request,
        ClaimsPrincipal user,
        AppDbContext db)
    {
        var userId = DeviceAuthHelper.GetUserId(user);
        if (!await DeviceAuthHelper.IsDeviceApproved(user, db))
            return Results.Forbid();

        var entries = await db.VaultEntries
            .Where(e => e.UserId == userId && e.DeletedAt == null)
            .ToListAsync();

        var lookup = entries.ToDictionary(e => e.Id);
        for (var i = 0; i < request.EntryIds.Count; i++)
        {
            if (lookup.TryGetValue(request.EntryIds[i], out var entry))
                entry.SortOrder = i;
        }

        await db.SaveChangesAsync();
        return Results.Ok();
    }

    public static async Task<IResult> DeleteEntry(
        Guid entryId,
        ClaimsPrincipal user,
        AppDbContext db)
    {
        var userId = DeviceAuthHelper.GetUserId(user);
        if (!await DeviceAuthHelper.IsDeviceApproved(user, db))
            return Results.Forbid();

        var entry = await db.VaultEntries
            .FirstOrDefaultAsync(e => e.Id == entryId && e.UserId == userId);

        if (entry is null)
            return Results.NotFound();

        entry.DeletedAt = DateTime.UtcNow;
        entry.UpdatedAt = DateTime.UtcNow;
        entry.EntryVersion++;

        await db.SaveChangesAsync();
        return Results.Ok();
    }
}
