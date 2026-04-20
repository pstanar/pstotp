using System.Security.Claims;
using PsTotp.Server.Application.Services;
using PsTotp.Server.Infrastructure.Data;

namespace PsTotp.Server.Api.EndPoints;

public static class SystemEndpoints
{
    private static CancellationTokenSource? _pendingShutdown;

    public static IResult GetSystemInfo(IConfiguration configuration)
    {
        return Results.Ok(new
        {
            ShutdownAvailable = configuration.GetValue<bool>("_Resolved:ShutdownEnabled"),
            MultiUser = configuration.GetValue<bool>("_Resolved:MultiUser"),
        });
    }

    public static async Task<IResult> Shutdown(
        ClaimsPrincipal principal,
        IHostApplicationLifetime lifetime,
        IConfiguration configuration,
        AppDbContext db,
        IAuditService audit,
        HttpContext httpContext)
    {
        if (!configuration.GetValue<bool>("_Resolved:ShutdownEnabled"))
            return Results.NotFound();

        var userId = DeviceAuthHelper.GetUserId(principal);
        var deviceId = DeviceAuthHelper.GetDeviceId(principal);

        audit.LogEvent(AuditEvents.SystemShutdown, userId, deviceId,
            ipAddress: httpContext.Connection.RemoteIpAddress?.ToString());
        await db.SaveChangesAsync();

        // Delay shutdown so the HTTP response is sent first
        _ = Task.Run(async () =>
        {
            await Task.Delay(500);
            lifetime.StopApplication();
        });

        return Results.Ok(new { Message = "Shutdown initiated" });
    }

    /// <summary>
    /// Called by the browser via sendBeacon on pagehide. Starts a deferred shutdown
    /// that is cancelled if any subsequent request arrives (e.g. page refresh).
    /// </summary>
    public static IResult BrowserClosing(IHostApplicationLifetime lifetime, IConfiguration configuration)
    {
        if (!configuration.GetValue<bool>("_Resolved:ShutdownEnabled"))
            return Results.NotFound();

        CancelPendingShutdown();
        var cts = new CancellationTokenSource();
        Volatile.Write(ref _pendingShutdown, cts);

        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(TimeSpan.FromSeconds(5), cts.Token);
                lifetime.StopApplication();
            }
            catch (OperationCanceledException) { }
        });

        return Results.Ok();
    }

    /// <summary>
    /// Cancels a pending deferred shutdown (called from middleware on every non-closing request).
    /// </summary>
    public static void CancelPendingShutdown()
    {
        var cts = Interlocked.Exchange(ref _pendingShutdown, null);
        if (cts == null) return;
        cts.Cancel();
        cts.Dispose();
    }
}
