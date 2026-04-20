using PsTotp.Server.Api.EndPoints;
using PsTotp.Server.Api.Filters;

namespace PsTotp.Server.Api;

public static class Routes
{
    private const string ApiPrefix = "/api";
    private const string UserPolicy = AuthConstants.UserPolicy;
    private const string AdminPolicy = AuthConstants.AdminPolicy;

    public static void MapRoutes(WebApplication app)
    {
        var publicApi = app.MapGroup(ApiPrefix);
        var protectedApi = app.MapGroup(ApiPrefix)
            .RequireAuthorization(UserPolicy)
            .AddEndpointFilter<OriginValidationFilter>()
            .AddEndpointFilter<AccountStatusFilter>();
        var adminApi = app.MapGroup(ApiPrefix)
            .RequireAuthorization(AdminPolicy)
            .AddEndpointFilter<OriginValidationFilter>()
            .AddEndpointFilter<AccountStatusFilter>();

        MapPublicEndpoints(publicApi);
        MapProtectedEndpoints(protectedApi);
        MapAdminEndpoints(adminApi);
        MapWellKnownEndpoints(app);

        // SPA fallback: serve index.html for non-API routes in production.
        // The base path is injected into a window global so the React bundle
        // can route and call the API under the proxy prefix without a rebuild.
        if (!app.Environment.IsDevelopment())
        {
            app.MapFallback(async context =>
            {
                var env = context.RequestServices.GetRequiredService<IWebHostEnvironment>();
                var indexPath = Path.Combine(env.WebRootPath, "index.html");
                if (!File.Exists(indexPath))
                {
                    context.Response.StatusCode = StatusCodes.Status404NotFound;
                    return;
                }
                var basePath = context.RequestServices.GetRequiredService<IConfiguration>()["_Resolved:BasePath"] ?? "";
                // Normalize the bare prefix URL (e.g. /totp) to the slashed
                // form (/totp/) so Vite's relative asset URLs resolve against
                // the SPA root rather than its parent. After UsePathBase
                // strips the prefix, Path is "" for the bare form and "/"
                // (or an SPA route) otherwise — we only redirect the former.
                if (!string.IsNullOrEmpty(basePath) && context.Request.Path.Value == "")
                {
                    context.Response.Redirect($"{basePath}/", permanent: false);
                    return;
                }
                var html = await File.ReadAllTextAsync(indexPath, context.RequestAborted);
                html = html.Replace("__BASE_PATH__", basePath);
                context.Response.ContentType = "text/html; charset=utf-8";
                await context.Response.WriteAsync(html, context.RequestAborted);
            });
        }
    }

    private static void MapPublicEndpoints(RouteGroupBuilder group)
    {
        group.MapGet("/health", () => Results.Ok(new { Status = "healthy" }));
        group.MapPost("/system/closing", SystemEndpoints.BrowserClosing);

        // Registration
        group.MapPost("/auth/register/begin", RegistrationEndpoints.Begin);
        group.MapPost("/auth/register/verify-email", RegistrationEndpoints.VerifyEmail);
        group.MapPost("/auth/register", RegistrationEndpoints.Complete);

        // Login
        group.MapPost("/auth/login", LoginEndpoints.Login);
        group.MapPost("/auth/login/complete", LoginEndpoints.CompleteLogin);

        // Token lifecycle
        group.MapPost("/auth/refresh", TokenEndpoints.Refresh);
        group.MapPost("/auth/logout", TokenEndpoints.Logout);

        // Password reset (public — user forgot password)
        group.MapPost("/auth/password/reset/begin", PasswordResetEndpoints.BeginPasswordReset);
        group.MapPost("/auth/password/reset/verify", PasswordResetEndpoints.VerifyPasswordResetCode);
        group.MapPost("/auth/password/reset/complete", PasswordResetEndpoints.CompletePasswordReset);

        // Recovery flow (public — user lost all devices)
        group.MapPost("/recovery/codes/redeem", RecoveryFlowEndpoints.RedeemCode);
        group.MapPost("/recovery/session/{sessionId:guid}/material", RecoveryFlowEndpoints.GetMaterial);
        group.MapPost("/recovery/session/{sessionId:guid}/complete", RecoveryFlowEndpoints.Complete);

        // WebAuthn assertion (public — for login and recovery step-up)
        group.MapPost("/webauthn/assert/begin", WebAuthnAssertionEndpoints.Begin);
        group.MapPost("/webauthn/assert/complete", WebAuthnAssertionEndpoints.Complete);
    }

    private static void MapProtectedEndpoints(RouteGroupBuilder group)
    {
        // Vault sync
        group.MapGet("/vault", VaultEndpoints.GetVault);
        group.MapPut("/vault/{entryId:guid}", VaultEndpoints.UpsertEntry);
        group.MapDelete("/vault/{entryId:guid}", VaultEndpoints.DeleteEntry);
        group.MapPost("/vault/reorder", VaultEndpoints.ReorderEntries);

        // Devices
        group.MapGet("/devices", DeviceEndpoints.ListDevices);
        group.MapPost("/devices/{deviceId:guid}/approve", DeviceEndpoints.ApproveDevice);
        group.MapPost("/devices/{deviceId:guid}/reject", DeviceEndpoints.RejectDevice);
        group.MapPost("/devices/{deviceId:guid}/revoke", DeviceEndpoints.RevokeDevice);
        group.MapPut("/devices/self/envelope", DeviceEndpoints.UpdateSelfEnvelope);

        // Audit
        group.MapGet("/security/audit-events", AuditEndpoints.GetAuditEvents);

        // Import/export audit
        group.MapPost("/account/vault/exported", AccountEndpoints.LogVaultExported);
        group.MapPost("/account/vault/imported", AccountEndpoints.LogVaultImported);

        // Password change
        group.MapPost("/account/password/change", AccountEndpoints.ChangePassword);

        // Recovery management (authenticated)
        group.MapPost("/recovery/codes/regenerate", RecoveryManagementEndpoints.RegenerateCodes);
        group.MapPost("/recovery/session/{sessionId:guid}/cancel", RecoveryManagementEndpoints.CancelRecovery);

        // WebAuthn registration + management (authenticated)
        group.MapPost("/webauthn/register/begin", WebAuthnRegistrationEndpoints.Begin);
        group.MapPost("/webauthn/register/complete", WebAuthnRegistrationEndpoints.Complete);
        group.MapGet("/webauthn/credentials", WebAuthnManagementEndpoints.ListCredentials);
        group.MapPut("/webauthn/credentials/{credentialId:guid}/rename", WebAuthnManagementEndpoints.RenameCredential);
        group.MapPost("/webauthn/credentials/{credentialId:guid}/revoke", WebAuthnManagementEndpoints.RevokeCredential);

        // System
        group.MapGet("/system/info", SystemEndpoints.GetSystemInfo);
        group.MapPost("/system/shutdown", SystemEndpoints.Shutdown);

        // Icon proxy (for fetching external favicons/images without CORS blocks)
        group.MapGet("/icon-proxy", IconProxyEndpoints.ProxyIcon);
    }

    private static void MapAdminEndpoints(RouteGroupBuilder group)
    {
        group.MapGet("/admin/users", AdminEndpoints.ListUsers);
        group.MapGet("/admin/users/{userId:guid}", AdminEndpoints.GetUserDetail);
        group.MapPost("/admin/users/{userId:guid}/disable", AdminEndpoints.DisableUser);
        group.MapPost("/admin/users/{userId:guid}/enable", AdminEndpoints.EnableUser);
        group.MapPost("/admin/users/{userId:guid}/force-password-reset", AdminEndpoints.ForcePasswordReset);
        group.MapDelete("/admin/users/{userId:guid}", AdminEndpoints.DeleteUser);
        group.MapPost("/admin/users/{userId:guid}/recovery-sessions/{sessionId:guid}/cancel",
            AdminEndpoints.CancelRecoverySession);

        // Backup/restore
        group.MapPost("/admin/backup", BackupEndpoints.ExportBackup);
        group.MapPost("/admin/restore", BackupEndpoints.RestoreBackup).DisableAntiforgery();
    }

    /// <summary>
    /// Digital Asset Links for Android passkey support.
    /// Auto-generated from Android:PackageName and Android:CertFingerprints in appsettings.
    /// </summary>
    private static void MapWellKnownEndpoints(WebApplication app)
    {
        app.MapGet("/.well-known/assetlinks.json", (IConfiguration config) =>
        {
            var packageName = config["Android:PackageName"];
            var fingerprints = config.GetSection("Android:CertFingerprints").Get<string[]>();

            if (string.IsNullOrEmpty(packageName) || fingerprints is null || fingerprints.Length == 0)
                return Results.NotFound();

            var statements = fingerprints.Select(fp => new
            {
                relation = new[] { "delegate_permission/common.handle_all_urls", "delegate_permission/common.get_login_creds" },
                target = new
                {
                    @namespace = "android_app",
                    package_name = packageName,
                    sha256_cert_fingerprints = new[] { fp },
                },
            });

            return Results.Json(statements, contentType: "application/json");
        }).ExcludeFromDescription();
    }
}
