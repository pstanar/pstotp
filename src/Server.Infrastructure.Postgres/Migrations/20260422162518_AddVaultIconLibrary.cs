using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace PsTotp.Server.Infrastructure.Postgres.Migrations
{
    /// <inheritdoc />
    public partial class AddVaultIconLibrary : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "VaultIconLibraries",
                columns: table => new
                {
                    UserId = table.Column<Guid>(type: "uuid", nullable: false),
                    EncryptedPayload = table.Column<byte[]>(type: "bytea", nullable: false),
                    Version = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_VaultIconLibraries", x => x.UserId);
                    table.ForeignKey(
                        name: "FK_VaultIconLibraries_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "VaultIconLibraries");
        }
    }
}
