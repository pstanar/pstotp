namespace PsTotp.Server.Api;

public static class DataDirectory
{
    private const string EnvVar = "PSTOTP_DATA";
    private const string ConfigKey = "DataDirectory";
    private const string AppName = "pstotp";

    /// <summary>
    /// Resolve the platform-specific data directory. Creates it if it doesn't exist.
    /// Priority: PSTOTP_DATA env var → DataDirectory config → platform default.
    /// </summary>
    public static string Resolve(IConfiguration? configuration = null)
    {
        var path = Environment.GetEnvironmentVariable(EnvVar);

        if (string.IsNullOrEmpty(path))
            path = configuration?[ConfigKey];

        if (string.IsNullOrEmpty(path))
            path = GetPlatformDefault();

        Directory.CreateDirectory(path);
        return path;
    }

    private static string GetPlatformDefault()
    {
        if (OperatingSystem.IsWindows())
        {
            // %APPDATA%\pstotp (e.g., C:\Users\<user>\AppData\Roaming\pstotp)
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            return Path.Combine(appData, AppName);
        }

        // Linux, macOS: ~/.pstotp
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return Path.Combine(home, $".{AppName}");
    }
}
