namespace PsTotp.Server.Application.DTOs;

// --- Registration ---

public sealed record BeginRegistrationRequest(string Email);

public sealed record BeginRegistrationResponse(Guid RegistrationSessionId, bool EmailVerificationRequired, string? VerificationCode = null);

public sealed record VerifyEmailRequest(Guid RegistrationSessionId, string VerificationCode);

public sealed record VerifyEmailResponse(bool Verified);

public sealed record KdfConfigDto(string Algorithm, int MemoryMb, int Iterations, int Parallelism, string Salt);

public sealed record PasswordVerifierDto(string Verifier, KdfConfigDto Kdf);

public sealed record EnvelopeDto(string Ciphertext, string Nonce, int Version);

public sealed record DeviceDto(string DeviceName, string Platform, string ClientType, string DevicePublicKey);

public sealed record RecoveryDto(
    string RecoveryEnvelopeCiphertext,
    string RecoveryEnvelopeNonce,
    int RecoveryEnvelopeVersion,
    List<string> RecoveryCodeHashes,
    string? RecoveryCodeSalt = null);

public sealed record RegisterRequest(
    Guid? RegistrationSessionId,
    string Email,
    PasswordVerifierDto PasswordVerifier,
    EnvelopeDto PasswordEnvelope,
    DeviceDto Device,
    EnvelopeDto DeviceEnvelope,
    RecoveryDto Recovery);

// --- Login ---

public sealed record LoginRequest(string Email, DeviceDto Device);

public sealed record LoginChallengeResponse(Guid LoginSessionId, LoginChallenge Challenge);

public sealed record LoginChallenge(string Nonce, KdfConfigDto Kdf);

public sealed record LoginCompleteRequest(Guid LoginSessionId, string ClientProof);

public sealed record LoginDeviceInfo(Guid DeviceId, string Status, bool PersistentKeyAllowed);

public sealed record LoginEnvelopes(EnvelopeDto? Password, EnvelopeDto? Device);

// --- Password Change ---

public sealed record PasswordChangeRequest(
    VerifierProof CurrentProof,
    PasswordVerifierDto NewVerifier,
    EnvelopeDto NewPasswordEnvelope);

public sealed record PasswordChangeResponse(string? AccessToken, string? RefreshToken);

// --- Token ---

public sealed record RefreshRequest(string? RefreshToken);

public sealed record RefreshResponse(string? AccessToken, string? RefreshToken);

public sealed record RegisterResponse(Guid UserId, Guid DeviceId, string? AccessToken, string? RefreshToken);

public sealed record LoginCompleteResponse(
    Guid UserId,
    string? AccessToken,
    string? RefreshToken,
    LoginDeviceInfo Device,
    LoginEnvelopes? Envelopes,
    Guid? ApprovalRequestId,
    string? Role = null,
    bool ForcePasswordReset = false);

// --- Password Reset ---

public sealed record BeginPasswordResetRequest(string Email, DeviceDto? Device);

public sealed record BeginPasswordResetResponse(Guid ResetSessionId, bool CodeSent, string? VerificationCode);

public sealed record VerifyPasswordResetCodeRequest(Guid ResetSessionId, string VerificationCode);

public sealed record VerifyPasswordResetCodeResponse(bool Verified, KdfConfigDto? Kdf, EnvelopeDto? DeviceEnvelope);

public sealed record CompletePasswordResetRequest(
    Guid ResetSessionId,
    PasswordVerifierDto NewVerifier,
    EnvelopeDto NewPasswordEnvelope);
