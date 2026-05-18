namespace PsTotp.Server.Application;

public static class SharedConstants
{
    // JWT claim type for device identity
    public const string DeviceIdClaim = "device_id";

    // JWT issuer/audience defaults (when not configured)
    public const string DefaultJwtIssuer = "pstotp";
    public const string DefaultJwtAudience = "pstotp";

    // Role string used in JWT claims and authorization
    public const string AdminRole = "Admin";

    // Rate-limiter category keys
    public const string RateLimitLogin = "login";
    public const string RateLimitRecovery = "recovery";
    // IP-keyed budgets — backstop for email-rotation abuse on the
    // public register / password-reset paths. The existing email-keyed
    // session limits (3 per email per 15 min) don't catch an attacker
    // who rotates emails.
    public const string RateLimitRegistrationIp = "registration_ip";
    public const string RateLimitPasswordResetIp = "password_reset_ip";
}
