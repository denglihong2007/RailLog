using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RailLog.Migrations
{
    /// <inheritdoc />
    public partial class UpdateTripRecordFields : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "SeatType",
                table: "TripRecords",
                type: "nvarchar(max)",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SeatType",
                table: "TripRecords");
        }
    }
}
