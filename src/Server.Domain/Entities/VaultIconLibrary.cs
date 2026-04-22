namespace PsTotp.Server.Domain.Entities;

/// <summary>
/// Per-user encrypted blob holding the user's custom-uploaded icons,
/// reusable across vault entries. One row per user (UserId is the PK).
/// The client AES-GCM-encrypts the whole JSON-serialised list with the
/// user's vault key; the server only stores ciphertext and a monotonic
/// version for optimistic concurrency. See
/// VaultIconLibraryEndpoints / docs/CONFIG.md.
/// </summary>
public class VaultIconLibrary
{
    public Guid UserId { get; set; }
    public required byte[] EncryptedPayload { get; set; }
    public int Version { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }

    public User User { get; set; } = null!;
}
