namespace PsTotp.Server.Application.Crypto;

public sealed record KdfConfig
{
    public string Algorithm { get; init; } = "argon2id";
    public int MemoryMb { get; init; } = 64;
    public int Iterations { get; init; } = 3;
    public int Parallelism { get; init; } = 4;
    public int HashLength { get; init; } = 32;

    public static KdfConfig Default => new();
}
