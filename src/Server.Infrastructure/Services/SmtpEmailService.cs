using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using MimeKit;
using PsTotp.Server.Application.Services;

namespace PsTotp.Server.Infrastructure.Services;

public class SmtpEmailService : IEmailService
{
    private static readonly TimeSpan ConnectTimeout = TimeSpan.FromSeconds(10);

    private readonly ILogger<SmtpEmailService> _logger;
    private readonly string _host;
    private readonly int _port;
    private readonly string _username;
    private readonly string _password;
    private readonly string _fromAddress;
    private readonly string _fromName;

    public SmtpEmailService(IConfiguration configuration, ILogger<SmtpEmailService> logger)
    {
        _logger = logger;
        _host = configuration["Email:SmtpHost"]!;
        _port = configuration.GetValue("Email:SmtpPort", 587);
        _username = configuration["Email:Username"]!;
        _password = configuration["Email:Password"]!;
        _fromAddress = configuration["Email:FromAddress"] ?? _username;
        _fromName = configuration["Email:FromName"] ?? "PsTotp";
    }

    public bool IsConfigured => true;

    public async Task SendVerificationCodeAsync(string email, string code)
    {
        var message = new MimeMessage();
        message.From.Add(new MailboxAddress(_fromName, _fromAddress));
        message.To.Add(MailboxAddress.Parse(email));
        message.Subject = $"PsTotp verification code: {code}";

        message.Body = new TextPart("plain")
        {
            Text = $"""
                Your PsTotp verification code is: {code}

                This code expires in 15 minutes.

                If you did not request this, you can safely ignore this email.
                """,
        };

        using var cts = new CancellationTokenSource(ConnectTimeout);
        using var client = new SmtpClient();
        try
        {
            var tls = _port == 465 ? SecureSocketOptions.SslOnConnect : SecureSocketOptions.StartTls;
            await client.ConnectAsync(_host, _port, tls, cts.Token);
            await client.AuthenticateAsync(_username, _password, cts.Token);
            await client.SendAsync(message, cts.Token);
            _logger.LogInformation("Verification email sent to {Email}", email);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send verification email to {Email}", email);
            throw;
        }
        finally
        {
            if (client.IsConnected)
                await client.DisconnectAsync(true);
        }
    }
}
