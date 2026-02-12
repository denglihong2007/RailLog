using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace RailLog.Migrations
{
    /// <inheritdoc />
    public partial class AddMileageKmToTripRecords : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<decimal>(
                name: "MileageKm",
                table: "TripRecords",
                type: "decimal(8,1)",
                nullable: false,
                defaultValue: 0m);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "MileageKm",
                table: "TripRecords");
        }
    }
}
