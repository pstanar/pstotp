using System.Text.Json;

namespace PsTotp.Server.Application.DTOs;

// Registration
public sealed record WebAuthnRegisterBeginResponse(
    Guid CeremonyId,
    JsonElement PublicKeyOptions);

public sealed record WebAuthnRegisterCompleteRequest(
    Guid CeremonyId,
    string FriendlyName,
    JsonElement AttestationResponse);

// Assertion
public sealed record WebAuthnAssertBeginRequest(
    string? Email,
    Guid? RecoverySessionId);

public sealed record WebAuthnAssertBeginResponse(
    Guid CeremonyId,
    JsonElement PublicKeyOptions);

public sealed record WebAuthnAssertCompleteRequest(
    Guid CeremonyId,
    JsonElement AssertionResponse,
    DeviceDto? Device);

// Management
public sealed record WebAuthnCredentialDto(
    Guid Id,
    string? FriendlyName,
    DateTime CreatedAt,
    DateTime? LastUsedAt);

public sealed record WebAuthnCredentialListResponse(List<WebAuthnCredentialDto> Credentials);

public sealed record WebAuthnRenameRequest(string FriendlyName);
