namespace PsTotp.Server.Application.DTOs;

public sealed record AdminUserListResponse(List<AdminUserDto> Users, int TotalCount);

public sealed record AdminUserDto(
    Guid Id,
    string Email,
    string Role,
    DateTime CreatedAt,
    DateTime? LastLoginAt,
    DateTime? DisabledAt,
    bool ForcePasswordReset,
    int DeviceCount,
    int EntryCount,
    int CredentialCount);

public sealed record AdminUserDetailResponse(
    AdminUserDto User,
    List<AdminDeviceDto> Devices,
    List<AdminRecoverySessionDto> RecoverySessions);

public sealed record AdminDeviceDto(
    Guid Id,
    string DeviceName,
    string Platform,
    string Status,
    DateTime CreatedAt,
    DateTime? ApprovedAt,
    DateTime? RevokedAt,
    DateTime? LastSeenAt);

public sealed record AdminRecoverySessionDto(
    Guid Id,
    string Status,
    DateTime CreatedAt,
    DateTime ExpiresAt,
    DateTime ReleaseEarliestAt);
