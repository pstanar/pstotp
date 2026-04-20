namespace PsTotp.Server.Domain.Entities;

public class RegistrationSession
{
    public Guid Id { get; set; }
    public required string Email { get; set; }
    public required string VerificationCode { get; set; }
    public bool IsVerified { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public int FailedVerifyAttempts { get; set; }
}
