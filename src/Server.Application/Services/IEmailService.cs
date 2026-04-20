namespace PsTotp.Server.Application.Services;

public interface IEmailService
{
    bool IsConfigured { get; }
    Task SendVerificationCodeAsync(string email, string code);
}
