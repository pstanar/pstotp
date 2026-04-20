using System.Collections.Concurrent;
using PsTotp.Server.Application.Services;

namespace PsTotp.Server.Infrastructure.Services;

public class RateLimiter : IRateLimiter
{
    private static readonly Dictionary<string, (int maxAttempts, TimeSpan window)> CategoryLimits = new()
    {
        [Application.SharedConstants.RateLimitLogin] = (5, TimeSpan.FromMinutes(15)),
        [Application.SharedConstants.RateLimitRecovery] = (3, TimeSpan.FromHours(1)),
    };

    private readonly ConcurrentDictionary<string, ConcurrentBag<DateTimeOffset>> _attempts = new();

    public bool IsRateLimited(string key, string category)
    {
        if (!CategoryLimits.TryGetValue(category, out var limits))
            return false;

        var bucketKey = $"{category}:{key}";
        if (!_attempts.TryGetValue(bucketKey, out var bag))
            return false;

        var cutoff = DateTimeOffset.UtcNow - limits.window;
        var recentCount = bag.Count(a => a > cutoff);

        return recentCount >= limits.maxAttempts;
    }

    public void RecordAttempt(string key, string category)
    {
        var bucketKey = $"{category}:{key}";
        var bag = _attempts.GetOrAdd(bucketKey, _ => []);
        bag.Add(DateTimeOffset.UtcNow);

        // Prune old entries periodically (every 100 entries)
        if (bag.Count > 100)
        {
            var cutoff = DateTimeOffset.UtcNow - TimeSpan.FromHours(2);
            var fresh = new ConcurrentBag<DateTimeOffset>(bag.Where(a => a > cutoff));
            _attempts[bucketKey] = fresh;
        }
    }
}
