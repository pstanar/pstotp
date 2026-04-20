using Microsoft.EntityFrameworkCore;
using PsTotp.Server.Domain.Entities;

namespace PsTotp.Server.Infrastructure.Data;

public class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<User> Users => Set<User>();
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<VaultEntry> VaultEntries => Set<VaultEntry>();
    public DbSet<VaultKeyEnvelope> VaultKeyEnvelopes => Set<VaultKeyEnvelope>();
    public DbSet<RecoveryCode> RecoveryCodes => Set<RecoveryCode>();
    public DbSet<WebAuthnCredential> WebAuthnCredentials => Set<WebAuthnCredential>();
    public DbSet<AuditEvent> AuditEvents => Set<AuditEvent>();
    public DbSet<LoginSession> LoginSessions => Set<LoginSession>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<RecoverySession> RecoverySessions => Set<RecoverySession>();
    public DbSet<RegistrationSession> RegistrationSessions => Set<RegistrationSession>();
    public DbSet<WebAuthnCeremony> WebAuthnCeremonies => Set<WebAuthnCeremony>();
    public DbSet<PasswordResetSession> PasswordResetSessions => Set<PasswordResetSession>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        var jsonType = Database.ProviderName switch
        {
            "Npgsql.EntityFrameworkCore.PostgreSQL" => "jsonb",
            "Microsoft.EntityFrameworkCore.SqlServer" => "nvarchar(max)",
            "Microsoft.EntityFrameworkCore.Sqlite" => "TEXT",
            _ => "json",
        };

        modelBuilder.Entity<User>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.Email).IsUnique();
            entity.Property(e => e.Email).IsRequired();
            entity.Property(e => e.PasswordVerifier).IsRequired();
            entity.Property(e => e.PasswordKdfConfig).HasColumnType(jsonType).IsRequired();
            entity.Property(e => e.Role).HasConversion<string>();
        });

        modelBuilder.Entity<Device>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.UserId, e.Status });
            entity.Property(e => e.Status).HasConversion<string>();
            entity.HasOne(e => e.User).WithMany(u => u.Devices).HasForeignKey(e => e.UserId);
        });

        modelBuilder.Entity<VaultEntry>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.UserId, e.DeletedAt });
            entity.HasOne(e => e.User).WithMany(u => u.VaultEntries).HasForeignKey(e => e.UserId);
        });

        modelBuilder.Entity<VaultKeyEnvelope>(entity =>
        {
            entity.HasKey(e => e.Id);
            // Not unique — revoked envelopes share the same tuple; app logic ensures one active per tuple
            entity.HasIndex(e => new { e.UserId, e.DeviceId, e.EnvelopeType });
            entity.Property(e => e.EnvelopeType).HasConversion<string>();
            entity.HasOne(e => e.User).WithMany(u => u.VaultKeyEnvelopes).HasForeignKey(e => e.UserId);
            entity.HasOne(e => e.Device).WithMany().HasForeignKey(e => e.DeviceId);
        });

        modelBuilder.Entity<RecoveryCode>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.UserId, e.UsedAt, e.ReplacedAt });
            entity.HasOne(e => e.User).WithMany(u => u.RecoveryCodes).HasForeignKey(e => e.UserId);
        });

        modelBuilder.Entity<WebAuthnCredential>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.CredentialId).IsUnique();
            entity.Property(e => e.Transports).HasColumnType(jsonType);
            entity.HasOne(e => e.User).WithMany(u => u.WebAuthnCredentials).HasForeignKey(e => e.UserId);
        });

        modelBuilder.Entity<AuditEvent>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.UserId, e.CreatedAt }).IsDescending(false, true);
            entity.Property(e => e.EventData).HasColumnType(jsonType);
            entity.HasOne(e => e.User).WithMany(u => u.AuditEvents).HasForeignKey(e => e.UserId);
            entity.HasOne(e => e.Device).WithMany().HasForeignKey(e => e.DeviceId);
        });

        modelBuilder.Entity<LoginSession>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.ExpiresAt);
        });

        modelBuilder.Entity<RefreshToken>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.TokenHash).IsUnique();
            entity.HasIndex(e => new { e.UserId, e.RevokedAt });
            entity.HasOne(e => e.User).WithMany().HasForeignKey(e => e.UserId);
            entity.HasOne(e => e.Device).WithMany().HasForeignKey(e => e.DeviceId);
        });

        modelBuilder.Entity<RecoverySession>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.Property(e => e.Status).HasConversion<string>();
            entity.HasOne(e => e.User).WithMany().HasForeignKey(e => e.UserId);
        });

        modelBuilder.Entity<RegistrationSession>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.ExpiresAt);
        });

        modelBuilder.Entity<WebAuthnCeremony>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.ExpiresAt);
            entity.Property(e => e.CeremonyType).HasConversion<string>();
        });

        modelBuilder.Entity<PasswordResetSession>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => new { e.Email, e.ExpiresAt });
        });
    }
}
