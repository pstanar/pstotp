using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace PsTotp.Server.Infrastructure.Sqlite.Migrations
{
    /// <inheritdoc />
    public partial class AddServerSettings : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ServerSettings",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "TEXT", nullable: false),
                    RegistrationEnabled = table.Column<bool>(type: "INTEGER", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "TEXT", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ServerSettings", x => x.Id);
                });

            migrationBuilder.InsertData(
                table: "ServerSettings",
                columns: new[] { "Id", "RegistrationEnabled", "UpdatedAt" },
                values: new object[] { new Guid("00000000-0000-0000-0000-000000000001"), true, new DateTime(2026, 1, 1, 0, 0, 0, 0, DateTimeKind.Utc) });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ServerSettings");
        }
    }
}
