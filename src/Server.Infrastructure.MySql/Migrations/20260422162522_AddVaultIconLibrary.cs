using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace PsTotp.Server.Infrastructure.MySql.Migrations
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
                    UserId = table.Column<Guid>(type: "char(36)", nullable: false),
                    EncryptedPayload = table.Column<byte[]>(type: "longblob", nullable: false),
                    Version = table.Column<int>(type: "int", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "datetime(6)", nullable: false)
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
                })
                .Annotation("MySQL:Charset", "utf8mb4");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "VaultIconLibraries");
        }
    }
}
