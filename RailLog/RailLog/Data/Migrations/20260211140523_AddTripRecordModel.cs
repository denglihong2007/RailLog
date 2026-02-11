using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RailLog.Migrations
{
    /// <inheritdoc />
    public partial class AddTripRecordModel : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "TripRecords",
                columns: table => new
                {
                    Id = table.Column<int>(type: "int", nullable: false)
                        .Annotation("SqlServer:Identity", "1, 1"),
                    TrainNumber = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    TravelDate = table.Column<DateOnly>(type: "date", nullable: false),
                    RollingStock = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    FromStation = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    ToStation = table.Column<string>(type: "nvarchar(max)", nullable: false),
                    DepartureTime = table.Column<TimeOnly>(type: "time", nullable: true),
                    ArrivalTime = table.Column<TimeOnly>(type: "time", nullable: true),
                    SeatNumber = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    Price = table.Column<decimal>(type: "decimal(18,2)", nullable: false),
                    Notes = table.Column<string>(type: "nvarchar(max)", nullable: true),
                    UserId = table.Column<string>(type: "nvarchar(450)", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "datetime2", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_TripRecords", x => x.Id);
                    table.ForeignKey(
                        name: "FK_TripRecords_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_TripRecords_UserId",
                table: "TripRecords",
                column: "UserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "TripRecords");
        }
    }
}
