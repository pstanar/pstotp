using System.Security.Claims;
using System.Text;
using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Application.Crypto;
using PsTotp.Server.Application.DTOs;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class BackupEndpoints
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false,
    };

    public static async Task<IResult> ExportBackup(
        BackupRequest request,
        ClaimsPrincipal principal,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var adminId = DeviceAuthHelper.GetUserId(principal);

        // Gather all persistent data
        var data = new BackupData(
            Users: await db.Users.AsNoTracking().Select(u => new BackupUser(
                u.Id, u.Email, Convert.ToBase64String(u.PasswordVerifier), u.PasswordKdfConfig,
                u.Role.ToString(), u.DisabledAt, u.ForcePasswordReset,
                u.CreatedAt, u.UpdatedAt, u.LastLoginAt,
                u.RecoveryCodeSalt
            )).ToListAsync(),
            Devices: await db.Devices.AsNoTracking().Select(d => new BackupDevice(
                d.Id, d.UserId, d.DeviceName, d.Platform, d.ClientType,
                d.Status.ToString(), d.DevicePublicKey,
                d.CreatedAt, d.ApprovedAt, d.LastSeenAt, d.RevokedAt
            )).ToListAsync(),
            VaultEntries: await db.VaultEntries.AsNoTracking().Select(e => new BackupVaultEntry(
                e.Id, e.UserId, Convert.ToBase64String(e.EntryPayload), e.EntryVersion, e.SortOrder,
                e.CreatedAt, e.UpdatedAt, e.DeletedAt
            )).ToListAsync(),
            VaultKeyEnvelopes: await db.VaultKeyEnvelopes.AsNoTracking().Select(e => new BackupVaultKeyEnvelope(
                e.Id, e.UserId, e.DeviceId, e.EnvelopeType.ToString(),
                Convert.ToBase64String(e.WrappedKeyPayload), e.CreatedAt, e.RevokedAt
            )).ToListAsync(),
            RecoveryCodes: await db.RecoveryCodes.AsNoTracking().Select(c => new BackupRecoveryCode(
                c.Id, c.UserId, c.CodeHash, c.CodeSlot,
                c.CreatedAt, c.UsedAt, c.ReplacedAt
            )).ToListAsync(),
            WebAuthnCredentials: await db.WebAuthnCredentials.AsNoTracking().Select(c => new BackupWebAuthnCredential(
                c.Id, c.UserId, Convert.ToBase64String(c.CredentialId), Convert.ToBase64String(c.PublicKey),
                c.SignCount, c.FriendlyName, c.Transports,
                c.CreatedAt, c.LastUsedAt, c.RevokedAt
            )).ToListAsync(),
            AuditEvents: await db.AuditEvents.AsNoTracking().Select(e => new BackupAuditEvent(
                e.Id, e.UserId, e.DeviceId, e.EventType,
                e.EventData, e.IpAddress, e.UserAgent, e.CreatedAt
            )).ToListAsync(),
            VaultIconLibraries: await db.VaultIconLibraries.AsNoTracking().Select(l => new BackupVaultIconLibrary(
                l.UserId, Convert.ToBase64String(l.EncryptedPayload), l.Version,
                l.CreatedAt, l.UpdatedAt
            )).ToListAsync()
        );

        // Serialize → encrypt
        var json = JsonSerializer.SerializeToUtf8Bytes(data, JsonOpts);
        var salt = Argon2Kdf.GenerateSalt();
        var key = Argon2Kdf.DeriveKey(Encoding.UTF8.GetBytes(request.Password), salt, KdfConfig.Default);
        var encrypted = AesGcmHelper.Encrypt(key, json);

        var header = new BackupFileHeader(
            Version: 1,
            Format: "pstotp-admin-backup",
            ExportedAt: DateTime.UtcNow,
            Salt: Convert.ToBase64String(salt),
            Payload: Convert.ToBase64String(encrypted)
        );

        audit.LogEvent(AuditEvents.BackupExported, adminId,
            eventData: new { UserCount = data.Users.Count, EntryCount = data.VaultEntries.Count },
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());
        await db.SaveChangesAsync();

        var fileBytes = JsonSerializer.SerializeToUtf8Bytes(header, JsonOpts);
        var fileName = $"pstotp-backup-{DateTime.UtcNow:yyyy-MM-dd}.json";
        return Results.Bytes(fileBytes, "application/json", fileName);
    }

    public static async Task<IResult> RestoreBackup(
        IFormFile file,
        [Microsoft.AspNetCore.Mvc.FromForm] string password,
        ClaimsPrincipal principal,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        var adminId = DeviceAuthHelper.GetUserId(principal);

        // Read uploaded file
        byte[] fileBytes;
        using (var ms = new MemoryStream())
        {
            await file.CopyToAsync(ms);
            fileBytes = ms.ToArray();
        }

        // Parse header
        BackupFileHeader header;
        try
        {
            header = JsonSerializer.Deserialize<BackupFileHeader>(fileBytes, JsonOpts)!;
        }
        catch
        {
            return Results.BadRequest(new { Error = "Invalid backup file format" });
        }

        if (header.Format != "pstotp-admin-backup")
            return Results.BadRequest(new { Error = $"Unknown backup format: {header.Format}" });

        // Decrypt
        byte[] json;
        try
        {
            var salt = Convert.FromBase64String(header.Salt);
            var key = Argon2Kdf.DeriveKey(Encoding.UTF8.GetBytes(password), salt, KdfConfig.Default);
            var payload = Convert.FromBase64String(header.Payload);
            json = AesGcmHelper.Decrypt(key, payload);
        }
        catch
        {
            return Results.BadRequest(new { Error = "Incorrect backup password or corrupted file" });
        }

        BackupData data;
        try
        {
            data = JsonSerializer.Deserialize<BackupData>(json, JsonOpts)!;
        }
        catch
        {
            return Results.BadRequest(new { Error = "Backup data is corrupted" });
        }

        // Restore within a transaction
        await using var transaction = await db.Database.BeginTransactionAsync();
        try
        {
            // Clear existing data
            await db.AuditEvents.ExecuteDeleteAsync();
            await db.WebAuthnCredentials.ExecuteDeleteAsync();
            await db.WebAuthnCeremonies.ExecuteDeleteAsync();
            await db.RecoveryCodes.ExecuteDeleteAsync();
            await db.RecoverySessions.ExecuteDeleteAsync();
            await db.PasswordResetSessions.ExecuteDeleteAsync();
            await db.VaultIconLibraries.ExecuteDeleteAsync();
            await db.VaultKeyEnvelopes.ExecuteDeleteAsync();
            await db.VaultEntries.ExecuteDeleteAsync();
            await db.RefreshTokens.ExecuteDeleteAsync();
            await db.LoginSessions.ExecuteDeleteAsync();
            await db.RegistrationSessions.ExecuteDeleteAsync();
            await db.Devices.ExecuteDeleteAsync();
            await db.Users.ExecuteDeleteAsync();

            // Insert backup data
            foreach (var u in data.Users)
            {
                db.Users.Add(new Domain.Entities.User
                {
                    Id = u.Id, Email = u.Email,
                    PasswordVerifier = Convert.FromBase64String(u.PasswordVerifier),
                    PasswordKdfConfig = u.PasswordKdfConfig,
                    Role = Enum.Parse<Domain.Entities.UserRole>(u.Role),
                    RecoveryCodeSalt = u.RecoveryCodeSalt,
                    DisabledAt = u.DisabledAt, ForcePasswordReset = u.ForcePasswordReset,
                    CreatedAt = u.CreatedAt, UpdatedAt = u.UpdatedAt, LastLoginAt = u.LastLoginAt,
                });
            }

            foreach (var d in data.Devices)
            {
                db.Devices.Add(new Domain.Entities.Device
                {
                    Id = d.Id, UserId = d.UserId, DeviceName = d.DeviceName,
                    Platform = d.Platform, ClientType = d.ClientType,
                    Status = Enum.Parse<Domain.Entities.DeviceStatus>(d.Status),
                    DevicePublicKey = d.DevicePublicKey,
                    CreatedAt = d.CreatedAt, ApprovedAt = d.ApprovedAt,
                    LastSeenAt = d.LastSeenAt, RevokedAt = d.RevokedAt,
                });
            }

            foreach (var e in data.VaultEntries)
            {
                db.VaultEntries.Add(new Domain.Entities.VaultEntry
                {
                    Id = e.Id, UserId = e.UserId,
                    EntryPayload = Convert.FromBase64String(e.EntryPayload),
                    EntryVersion = e.EntryVersion, SortOrder = e.SortOrder,
                    CreatedAt = e.CreatedAt, UpdatedAt = e.UpdatedAt, DeletedAt = e.DeletedAt,
                });
            }

            foreach (var e in data.VaultKeyEnvelopes)
            {
                db.VaultKeyEnvelopes.Add(new Domain.Entities.VaultKeyEnvelope
                {
                    Id = e.Id, UserId = e.UserId, DeviceId = e.DeviceId,
                    EnvelopeType = Enum.Parse<Domain.Entities.EnvelopeType>(e.EnvelopeType),
                    WrappedKeyPayload = Convert.FromBase64String(e.WrappedKeyPayload),
                    CreatedAt = e.CreatedAt, RevokedAt = e.RevokedAt,
                });
            }

            foreach (var c in data.RecoveryCodes)
            {
                db.RecoveryCodes.Add(new Domain.Entities.RecoveryCode
                {
                    Id = c.Id, UserId = c.UserId, CodeHash = c.CodeHash,
                    CodeSlot = c.CodeSlot, CreatedAt = c.CreatedAt,
                    UsedAt = c.UsedAt, ReplacedAt = c.ReplacedAt,
                });
            }

            foreach (var c in data.WebAuthnCredentials)
            {
                db.WebAuthnCredentials.Add(new Domain.Entities.WebAuthnCredential
                {
                    Id = c.Id, UserId = c.UserId,
                    CredentialId = Convert.FromBase64String(c.CredentialId),
                    PublicKey = Convert.FromBase64String(c.PublicKey),
                    SignCount = c.SignCount, FriendlyName = c.FriendlyName,
                    Transports = c.Transports,
                    CreatedAt = c.CreatedAt, LastUsedAt = c.LastUsedAt, RevokedAt = c.RevokedAt,
                });
            }

            foreach (var e in data.AuditEvents)
            {
                db.AuditEvents.Add(new Domain.Entities.AuditEvent
                {
                    Id = e.Id, UserId = e.UserId, DeviceId = e.DeviceId,
                    EventType = e.EventType, EventData = e.EventData,
                    IpAddress = e.IpAddress, UserAgent = e.UserAgent, CreatedAt = e.CreatedAt,
                });
            }

            // Optional in the format (backups from before icon libraries
            // landed won't carry this array — treat null as empty).
            if (data.VaultIconLibraries is not null)
            {
                foreach (var l in data.VaultIconLibraries)
                {
                    db.VaultIconLibraries.Add(new Domain.Entities.VaultIconLibrary
                    {
                        UserId = l.UserId,
                        EncryptedPayload = Convert.FromBase64String(l.EncryptedPayload),
                        Version = l.Version,
                        CreatedAt = l.CreatedAt,
                        UpdatedAt = l.UpdatedAt,
                    });
                }
            }

            // Log the restore event
            audit.LogEvent(AuditEvents.BackupRestored, adminId,
                eventData: new { UserCount = data.Users.Count, EntryCount = data.VaultEntries.Count },
                ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());

            await db.SaveChangesAsync();
            await transaction.CommitAsync();
        }
        catch
        {
            return Results.StatusCode(500);
        }

        return Results.Ok(new { RestoredUsers = data.Users.Count, RestoredEntries = data.VaultEntries.Count });
    }
}
