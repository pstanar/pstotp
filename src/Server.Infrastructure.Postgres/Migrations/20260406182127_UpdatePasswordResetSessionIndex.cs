using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace PsTotp.Server.Infrastructure.Postgres.Migrations
{
    /// <inheritdoc />
    public partial class UpdatePasswordResetSessionIndex : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_PasswordResetSessions_ExpiresAt",
                table: "PasswordResetSessions");

            migrationBuilder.CreateIndex(
                name: "IX_PasswordResetSessions_Email_ExpiresAt",
                table: "PasswordResetSessions",
                columns: new[] { "Email", "ExpiresAt" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_PasswordResetSessions_Email_ExpiresAt",
                table: "PasswordResetSessions");

            migrationBuilder.CreateIndex(
                name: "IX_PasswordResetSessions_ExpiresAt",
                table: "PasswordResetSessions",
                column: "ExpiresAt");
        }
    }
}
