namespace PsTotp.Server.Domain.Entities;

public class LoginSession
{
    public Guid Id { get; set; }
    public required string Email { get; set; }
    public required byte[] Nonce { get; set; }
    public DateTime CreatedAt { get; set; }
    public DateTime ExpiresAt { get; set; }
    public bool IsCompleted { get; set; }
    public Guid? DeviceId { get; set; }
}
