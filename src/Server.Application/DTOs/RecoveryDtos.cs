namespace PsTotp.Server.Application.DTOs;

public sealed record RecoveryCodeRegenerateRequest(RecoveryDto RotatedRecovery);

public sealed record RecoveryCodeRegenerateResponse(DateTime RotatedAt);

public sealed record RecoveryRedeemRequest(
    string Email,
    string RecoveryCode,
    VerifierProof VerifierProof);

public sealed record VerifierProof(Guid LoginSessionId, string ClientProof);

public sealed record RecoveryRedeemResponse(
    Guid RecoverySessionId,
    bool RequiresWebAuthn,
    DateTime ReleaseEarliestAt);

public sealed record RecoveryMaterialRequest(DeviceDto ReplacementDevice);

public sealed record RecoveryMaterialResponse(
    string Status,
    EnvelopeDto? RecoveryEnvelope,
    Guid? ReplacementDeviceId,
    DateTime? ReleaseEarliestAt);

public sealed record RecoveryCompleteRequest(
    Guid ReplacementDeviceId,
    EnvelopeDto DeviceEnvelope,
    RecoveryDto RotatedRecovery);
