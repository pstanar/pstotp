namespace PsTotp.Server.Application.DTOs;

public sealed record VaultSyncResponse(List<VaultEntryDto> Entries, DateTime ServerTime);

public sealed record VaultEntryDto(
    Guid Id,
    string EntryPayload,
    int EntryVersion,
    DateTime? DeletedAt,
    DateTime UpdatedAt,
    int SortOrder);

public sealed record VaultEntryUpsertRequest(string EntryPayload, int EntryVersion);

public sealed record VaultEntryUpsertResponse(Guid Id, int EntryVersion, DateTime UpdatedAt);

public sealed record VaultReorderRequest(List<Guid> EntryIds);
