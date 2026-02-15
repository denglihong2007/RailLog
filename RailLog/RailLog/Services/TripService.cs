using Microsoft.EntityFrameworkCore;
using RailLog.Data;
using RailLog.Shared.Models;

namespace RailLog.Services
{
    public class TripService(IDbContextFactory<ApplicationDbContext> contextFactory)
    {
        public async Task SaveRecordAsync(TripRecord record)
        {
            await using var context = await contextFactory.CreateDbContextAsync();
            context.TripRecords.Add(record);
            await context.SaveChangesAsync();
        }

        public async Task<List<TripRecord>> GetUserTripsAsync(string userId)
        {
            await using var context = await contextFactory.CreateDbContextAsync();
            return await context.TripRecords
                .Where(t => t.UserId == userId)
                .OrderByDescending(t => t.TravelDate)
                .ToListAsync();
        }

        public async Task<TripRecord?> GetUserTripByIdAsync(string userId, int id)
        {
            await using var context = await contextFactory.CreateDbContextAsync();
            return await context.TripRecords
                .FirstOrDefaultAsync(t => t.UserId == userId && t.Id == id);
        }

        public async Task<bool> UpdateUserTripAsync(string userId, int id, TripRecordDto dto)
        {
            await using var context = await contextFactory.CreateDbContextAsync();
            var record = await context.TripRecords
                .FirstOrDefaultAsync(t => t.UserId == userId && t.Id == id);

            if (record is null)
            {
                return false;
            }

            record.TrainNumber = dto.TrainNumber;
            record.TravelDate = dto.TravelDate;
            record.RollingStock = dto.RollingStock;
            record.FromStation = dto.FromStation;
            record.ToStation = dto.ToStation;
            record.DepartureTime = dto.DepartureTime;
            record.ArrivalTime = dto.ArrivalTime;
            record.MileageKm = dto.MileageKm;
            record.ViaRouteSegments = [.. dto.ViaRouteSegments
                .Select(x => new ViaRouteSegmentDto
                {
                    RouteName = x.RouteName,
                    FromStation = x.FromStation,
                    ToStation = x.ToStation,
                    MileageKm = x.MileageKm
                })];
            record.SeatType = dto.SeatType;
            record.SeatNumber = dto.SeatNumber;
            record.Price = dto.Price;
            record.Notes = dto.Notes;

            await context.SaveChangesAsync();
            return true;
        }

        public async Task<bool> DeleteUserTripAsync(string userId, int id)
        {
            await using var context = await contextFactory.CreateDbContextAsync();
            var record = await context.TripRecords
                .FirstOrDefaultAsync(t => t.UserId == userId && t.Id == id);

            if (record is null)
            {
                return false;
            }

            context.TripRecords.Remove(record);
            await context.SaveChangesAsync();
            return true;
        }

        public async Task<GlobalLeaderboard> GetGlobalLeaderboardAsync(int top = 10)
        {
            top = Math.Clamp(top, 1, 50);
            await using var context = await contextFactory.CreateDbContextAsync();

            var allTrips = await context.TripRecords
                .AsNoTracking()
                .ToListAsync();

            if (allTrips.Count == 0)
            {
                return GlobalLeaderboard.Empty;
            }

            var userTripStats = allTrips
                .GroupBy(x => x.UserId)
                .Select(g => new UserTripStat(
                    UserId: g.Key,
                    TotalTrips: g.Count(),
                    TotalSpend: g.Sum(x => x.Price),
                    TotalMileageKm: g.Sum(GetTripMileage)))
                .ToList();

            var userIds = userTripStats.Select(x => x.UserId).Distinct().ToList();
            var userProfiles = await context.Users
                .AsNoTracking()
                .Where(x => userIds.Contains(x.Id))
                .Select(x => new UserProfile(
                    Id: x.Id,
                    DisplayName: x.DisplayName,
                    UserName: x.UserName,
                    Email: x.Email,
                    AvatarUrl: x.AvatarUrl))
                .ToDictionaryAsync(x => x.Id);

            var entries = userTripStats
                .Select(x =>
                {
                    userProfiles.TryGetValue(x.UserId, out var profile);
                    return new LeaderboardEntry
                    {
                        UserId = x.UserId,
                        DisplayName = ResolveDisplayName(profile?.DisplayName, profile?.UserName, profile?.Email),
                        AvatarUrl = NormalizeAvatarUrl(profile?.AvatarUrl),
                        TotalSpend = x.TotalSpend,
                        TotalTrips = x.TotalTrips,
                        TotalMileageKm = x.TotalMileageKm
                    };
                })
                .ToList();

            return new GlobalLeaderboard
            {
                TopBySpend = entries
                    .OrderByDescending(x => x.TotalSpend)
                    .ThenByDescending(x => x.TotalTrips)
                    .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
                    .Take(top)
                    .ToList(),
                TopByTrips = entries
                    .OrderByDescending(x => x.TotalTrips)
                    .ThenByDescending(x => x.TotalMileageKm)
                    .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
                    .Take(top)
                    .ToList(),
                TopByMileage = entries
                    .OrderByDescending(x => x.TotalMileageKm)
                    .ThenByDescending(x => x.TotalTrips)
                    .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
                    .Take(top)
                    .ToList()
            };
        }

        private static decimal GetTripMileage(TripRecord trip)
        {
            if (trip.MileageKm > 0)
            {
                return trip.MileageKm;
            }

            var segmentMileage = (trip.ViaRouteSegments ?? []).Sum(x => x.MileageKm);
            return segmentMileage > 0 ? segmentMileage : 0m;
        }

        private static string ResolveDisplayName(string? displayName, string? userName, string? email)
        {
            if (!string.IsNullOrWhiteSpace(displayName))
            {
                return displayName.Trim();
            }

            if (!string.IsNullOrWhiteSpace(userName))
            {
                return userName.Trim();
            }

            if (!string.IsNullOrWhiteSpace(email))
            {
                var normalized = email.Trim();
                var splitIndex = normalized.IndexOf('@');
                return splitIndex > 0 ? normalized[..splitIndex] : normalized;
            }

            return "匿名旅客";
        }

        private static string? NormalizeAvatarUrl(string? avatarUrl)
        {
            if (string.IsNullOrWhiteSpace(avatarUrl))
            {
                return null;
            }

            return avatarUrl.Trim();
        }

        public sealed class GlobalLeaderboard
        {
            public static GlobalLeaderboard Empty { get; } = new();

            public List<LeaderboardEntry> TopBySpend { get; init; } = [];

            public List<LeaderboardEntry> TopByTrips { get; init; } = [];

            public List<LeaderboardEntry> TopByMileage { get; init; } = [];
        }

        public sealed class LeaderboardEntry
        {
            public required string UserId { get; init; }

            public required string DisplayName { get; init; }

            public string? AvatarUrl { get; init; }

            public decimal TotalSpend { get; init; }

            public int TotalTrips { get; init; }

            public decimal TotalMileageKm { get; init; }
        }

        private sealed record UserTripStat(string UserId, int TotalTrips, decimal TotalSpend, decimal TotalMileageKm);

        private sealed record UserProfile(string Id, string? DisplayName, string? UserName, string? Email, string? AvatarUrl);
    }
}
