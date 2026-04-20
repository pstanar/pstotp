namespace PsTotp.Server.Application.Services;

public interface IRateLimiter
{
    bool IsRateLimited(string key, string category);
    void RecordAttempt(string key, string category);
}
