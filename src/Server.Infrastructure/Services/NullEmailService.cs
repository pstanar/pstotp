using PsTotp.Server.Application.Services;

namespace PsTotp.Server.Infrastructure.Services;

/// <summary>
/// No-op email service used when no email provider is configured.
/// Returns IsConfigured = false so callers can fall back to returning codes inline.
/// </summary>
public class NullEmailService : IEmailService
{
    public bool IsConfigured => false;

    public Task SendVerificationCodeAsync(string email, string code) =>
        Task.CompletedTask;
}
