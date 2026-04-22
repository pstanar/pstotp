namespace PsTotp.Server.Application.DTOs;

/// <summary>
/// Response payload for the user-scoped icon library. When the user
/// hasn't initialised a library yet, <see cref="EncryptedPayload"/> is
/// empty and <see cref="Version"/> is 0 — the client treats this as
/// "no library yet" and sends PUT with Version=0 to create one.
/// </summary>
public sealed record IconLibraryResponse(
    string EncryptedPayload,
    int Version,
    DateTime? UpdatedAt);

/// <summary>
/// Request to replace the encrypted icon-library blob. ExpectedVersion
/// guards against concurrent writes (last-write-wins still applies —
/// the client just finds out it lost and refetches).
/// </summary>
public sealed record IconLibraryUpdateRequest(
    string EncryptedPayload,
    int ExpectedVersion);

public sealed record IconLibraryUpdateResponse(
    int Version,
    DateTime UpdatedAt);
