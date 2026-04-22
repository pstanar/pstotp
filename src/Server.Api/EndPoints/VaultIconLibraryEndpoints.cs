using System.Security.Claims;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Domain.Entities;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

/// <summary>
/// User-scoped, client-encrypted icon library. One row per user, stored
/// as a single AES-GCM blob that the client builds from
/// { id, label, data(base64 PNG) } entries. The server never sees the
/// plaintext; it just brokers the read/write with optimistic concurrency.
/// </summary>
public static class VaultIconLibraryEndpoints
{
    /// <summary>
    /// Hard cap on encrypted blob size — matches the client-side 100-icon
    /// limit with generous headroom. Catches pathological growth before
    /// it becomes a DB problem.
    /// </summary>
    private const int MaxEncryptedPayloadBytes = 2 * 1024 * 1024;

    public static async Task<IResult> Get(
        ClaimsPrincipal principal,
        AppDbContext db)
    {
        var userId = DeviceAuthHelper.GetUserId(principal);
        var library = await db.VaultIconLibraries
            .AsNoTracking()
            .FirstOrDefaultAsync(l => l.UserId == userId);

        if (library is null)
        {
            // Client treats empty payload + version 0 as "no library yet"
            // and calls PUT to create one.
            return Results.Ok(new IconLibraryResponse(string.Empty, 0, null));
        }

        return Results.Ok(new IconLibraryResponse(
            Convert.ToBase64String(library.EncryptedPayload),
            library.Version,
            library.UpdatedAt));
    }

    public static async Task<IResult> Update(
        IconLibraryUpdateRequest request,
        ClaimsPrincipal principal,
        AppDbContext db)
    {
        var userId = DeviceAuthHelper.GetUserId(principal);

        byte[] payload;
        try
        {
            payload = Convert.FromBase64String(request.EncryptedPayload);
        }
        catch (FormatException)
        {
            return Results.BadRequest(new { Error = "encryptedPayload must be valid base64" });
        }

        if (payload.Length == 0)
        {
            return Results.BadRequest(new { Error = "encryptedPayload cannot be empty" });
        }
        if (payload.Length > MaxEncryptedPayloadBytes)
        {
            return Results.BadRequest(new { Error = $"encryptedPayload exceeds {MaxEncryptedPayloadBytes} bytes" });
        }

        var library = await db.VaultIconLibraries.FirstOrDefaultAsync(l => l.UserId == userId);
        var now = DateTime.UtcNow;

        if (library is null)
        {
            // First write — client should send ExpectedVersion=0.
            if (request.ExpectedVersion != 0)
                return Results.Conflict(new { Error = "No library exists yet; send ExpectedVersion=0" });

            library = new VaultIconLibrary
            {
                UserId = userId,
                EncryptedPayload = payload,
                Version = 1,
                CreatedAt = now,
                UpdatedAt = now,
            };
            db.VaultIconLibraries.Add(library);
        }
        else
        {
            if (library.Version != request.ExpectedVersion)
                return Results.Conflict(new { Error = "Library was modified on another device; refetch and retry", library.Version });

            library.EncryptedPayload = payload;
            library.Version += 1;
            library.UpdatedAt = now;
        }

        await db.SaveChangesAsync();
        return Results.Ok(new IconLibraryUpdateResponse(library.Version, library.UpdatedAt));
    }
}
