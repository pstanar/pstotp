namespace PsTotp.Server.Api;

public static class AuditEvents
{
    // Auth
    public const string LoginSuccess = "login_success";
    public const string LoginFailed = "login_failed";
    public const string AccountCreated = "account_created";
    public const string PasswordChanged = "password_changed";
    public const string PasswordResetRequested = "password_reset_requested";
    public const string PasswordResetCompleted = "password_reset_completed";

    // Devices
    public const string DeviceApproved = "device_approved";
    public const string DeviceRejected = "device_rejected";
    public const string DeviceRevoked = "device_revoked";

    // Recovery
    public const string RecoveryCodeFailed = "recovery_code_failed";
    public const string RecoveryCodeRedeemed = "recovery_code_redeemed";
    public const string RecoveryMaterialReleased = "recovery_material_released";
    public const string RecoveryCompleted = "recovery_completed";
    public const string RecoveryCodesRegenerated = "recovery_codes_regenerated";
    public const string RecoverySessionCancelled = "recovery_session_cancelled";

    // Admin
    public const string UserDisabled = "user_disabled";
    public const string UserEnabled = "user_enabled";
    public const string UserDeleted = "user_deleted";
    public const string ForcePasswordResetSet = "force_password_reset_set";

    // Backup
    public const string BackupExported = "backup_exported";
    public const string BackupRestored = "backup_restored";

    // User import/export
    public const string VaultExported = "vault_exported";
    public const string VaultImported = "vault_imported";

    // WebAuthn
    public const string WebAuthnCredentialRegistered = "webauthn_credential_registered";
    public const string WebAuthnAssertionVerified = "webauthn_assertion_verified";
    public const string WebAuthnCredentialRevoked = "webauthn_credential_revoked";

    // System
    public const string SystemShutdown = "system_shutdown";
}
