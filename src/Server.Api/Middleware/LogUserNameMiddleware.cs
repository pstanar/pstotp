using System.Security.Claims;
using Serilog.Context;

namespace PsTotp.Server.Api.Middleware;

public class LogUserNameMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var claim = context.User.Claims
            .FirstOrDefault(c => c.Type == ClaimTypes.NameIdentifier);
        if (claim != null)
        {
            using (LogContext.PushProperty("UserName", claim.Value))
            {
                await next(context).ConfigureAwait(false);
                return;
            }
        }

        await next(context).ConfigureAwait(false);
    }
}
