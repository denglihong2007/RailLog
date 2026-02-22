using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.ChangeTracking;
using RailLog.Shared.Models;
using System.Text.Json;

namespace RailLog.Data
{
    public class ApplicationDbContext(DbContextOptions<ApplicationDbContext> options) : IdentityDbContext<ApplicationUser>(options)
    {
        public DbSet<TripRecord> TripRecords { get; set; }

        protected override void OnModelCreating(ModelBuilder builder)
        {
            base.OnModelCreating(builder);

            builder.Entity<ApplicationUser>()
                .HasIndex(x => x.DisplayName)
                .IsUnique();

            builder.Entity<TripRecord>()
                .Property(x => x.ViaRouteSegments)
                .HasColumnName("ViaRoutes")
                .HasColumnType("TEXT")
                .HasConversion(
                    value => JsonSerializer.Serialize(value, JsonSerializerOptions.Default),
                    value => string.IsNullOrWhiteSpace(value)
                        ? new List<ViaRouteSegmentDto>()
                        : JsonSerializer.Deserialize<List<ViaRouteSegmentDto>>(value, JsonSerializerOptions.Default) ?? new List<ViaRouteSegmentDto>());

            builder.Entity<TripRecord>()
                .Property(x => x.ViaRouteSegments)
                .Metadata.SetValueComparer(new ValueComparer<List<ViaRouteSegmentDto>>(
                    (left, right) =>
                        SerializeSegments(left) == SerializeSegments(right),
                    value => SerializeSegments(value).GetHashCode(),
                    value => value == null ? new List<ViaRouteSegmentDto>() : value.Select(x => new ViaRouteSegmentDto
                    {
                        RouteName = x.RouteName,
                        FromStation = x.FromStation,
                        ToStation = x.ToStation,
                        MileageKm = x.MileageKm
                    }).ToList()));
        }

        private static string SerializeSegments(List<ViaRouteSegmentDto>? segments)
        {
            return JsonSerializer.Serialize(segments ?? [], JsonSerializerOptions.Default);
        }
    }
}
