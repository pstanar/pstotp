using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace PsTotp.Server.Infrastructure.MySql.Migrations
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

            migrationBuilder.AlterColumn<string>(
                name: "Email",
                table: "PasswordResetSessions",
                type: "varchar(255)",
                nullable: false,
                oldClrType: typeof(string),
                oldType: "longtext");

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

            migrationBuilder.AlterColumn<string>(
                name: "Email",
                table: "PasswordResetSessions",
                type: "longtext",
                nullable: false,
                oldClrType: typeof(string),
                oldType: "varchar(255)");

            migrationBuilder.CreateIndex(
                name: "IX_PasswordResetSessions_ExpiresAt",
                table: "PasswordResetSessions",
                column: "ExpiresAt");
        }
    }
}
