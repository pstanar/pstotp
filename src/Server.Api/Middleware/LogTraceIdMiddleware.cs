using System.Diagnostics;
using Serilog.Context;

namespace PsTotp.Server.Api.Middleware;

public class LogTraceIdMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext context)
    {
        var traceId = Activity.Current?.Id;
        if (traceId != null)
        {
            using (LogContext.PushProperty("TraceId", traceId))
            {
                await next(context).ConfigureAwait(false);
                return;
            }
        }

        await next(context).ConfigureAwait(false);
    }
}
