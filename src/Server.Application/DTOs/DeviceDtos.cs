namespace PsTotp.Server.Application.DTOs;

public sealed record DeviceListResponse(List<DeviceInfoDto> Devices);

public sealed record DeviceInfoDto(
    Guid DeviceId,
    string DeviceName,
    string Platform,
    string Status,
    DateTime? ApprovedAt,
    Guid? ApprovalRequestId,
    string? DevicePublicKey,
    DateTime? RequestedAt,
    DateTime? RevokedAt);

public sealed record ApproveDeviceRequest(
    Guid ApprovalRequestId,
    ApprovalAuth ApprovalAuth,
    EnvelopeDto DeviceEnvelope);

public sealed record ApprovalAuth(string Type);

public sealed record ApproveDeviceResponse(Guid DeviceId, string Status);
