using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace PsTotp.Server.Infrastructure.Sqlite.Migrations
{
    /// <inheritdoc />
    public partial class DropUniqueEnvelopeIndex : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_VaultKeyEnvelopes_UserId_DeviceId_EnvelopeType",
                table: "VaultKeyEnvelopes");

            migrationBuilder.AddColumn<string>(
                name: "RecoveryCodeSalt",
                table: "Users",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<int>(
                name: "FailedVerifyAttempts",
                table: "RegistrationSessions",
                type: "INTEGER",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.AddColumn<int>(
                name: "FailedVerifyAttempts",
                table: "PasswordResetSessions",
                type: "INTEGER",
                nullable: false,
                defaultValue: 0);

            migrationBuilder.CreateIndex(
                name: "IX_VaultKeyEnvelopes_UserId_DeviceId_EnvelopeType",
                table: "VaultKeyEnvelopes",
                columns: new[] { "UserId", "DeviceId", "EnvelopeType" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_VaultKeyEnvelopes_UserId_DeviceId_EnvelopeType",
                table: "VaultKeyEnvelopes");

            migrationBuilder.DropColumn(
                name: "RecoveryCodeSalt",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "FailedVerifyAttempts",
                table: "RegistrationSessions");

            migrationBuilder.DropColumn(
                name: "FailedVerifyAttempts",
                table: "PasswordResetSessions");

            migrationBuilder.CreateIndex(
                name: "IX_VaultKeyEnvelopes_UserId_DeviceId_EnvelopeType",
                table: "VaultKeyEnvelopes",
                columns: new[] { "UserId", "DeviceId", "EnvelopeType" },
                unique: true);
        }
    }
}
