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
            record.IsRailTrip = dto.IsRailTrip;

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

        public async Task<TripRecord?> GetAnyTripByIdAsync(int id)
        {
            await using var context = await contextFactory.CreateDbContextAsync();
            return await context.TripRecords
                .AsNoTracking()
                .FirstOrDefaultAsync(t => t.Id == id);
        }

        public async Task<PublicUserProfile?> GetUserProfileAsync(string userId)
        {
            if (string.IsNullOrWhiteSpace(userId))
            {
                return null;
            }

            await using var context = await contextFactory.CreateDbContextAsync();
            return await context.Users
                .AsNoTracking()
                .Where(x => x.Id == userId)
                .Select(x => new PublicUserProfile
                {
                    UserId = x.Id,
                    DisplayName = ResolveDisplayName(x.DisplayName, x.UserName, x.Email),
                    UserName = x.UserName,
                    Email = x.Email,
                    AvatarUrl = NormalizeAvatarUrl(x.AvatarUrl),
                    Bio = NormalizeBio(x.Bio),
                    ShowEmail = x.ShowEmailOnProfile
                })
                .FirstOrDefaultAsync();
        }

        public async Task<PersonalOverlapSummary> GetPersonalOverlapSummaryAsync(string userId)
        {
            if (string.IsNullOrWhiteSpace(userId))
            {
                return PersonalOverlapSummary.Empty;
            }

            await using var context = await contextFactory.CreateDbContextAsync();

            var myTrips = await context.TripRecords
                .AsNoTracking()
                .Where(x => x.UserId == userId)
                .Where(x => x.IsRailTrip)
                .ToListAsync();

            if (myTrips.Count == 0)
            {
                return PersonalOverlapSummary.Empty;
            }

            var trainDatesByKey = myTrips
                .Select(x => new
                {
                    Key = NormalizeTrainNumber(x.TrainNumber),
                    x.TravelDate
                })
                .Where(x => !string.IsNullOrWhiteSpace(x.Key))
                .GroupBy(x => x.Key, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(
                    x => x.Key,
                    x => x.Select(y => y.TravelDate)
                        .Distinct()
                        .OrderByDescending(y => y)
                        .ToList(),
                    StringComparer.OrdinalIgnoreCase);

            var stationVisitPairs = myTrips
                .SelectMany(trip => ExtractTripStations(trip).Select(station => new
                {
                    StationName = station,
                    Key = NormalizeStationName(station),
                    trip.TravelDate
                }))
                .Where(x => !string.IsNullOrWhiteSpace(x.Key))
                .ToList();

            var stationDatesByKey = stationVisitPairs
                .GroupBy(x => x.Key, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(
                    x => x.Key,
                    x => x.Select(y => y.TravelDate)
                        .Distinct()
                        .OrderByDescending(y => y)
                        .ToList(),
                    StringComparer.OrdinalIgnoreCase);

            var stationDisplayByKey = stationVisitPairs
                .GroupBy(x => x.Key, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(
                    x => x.Key,
                    x => x.Select(y => y.StationName.Trim())
                        .FirstOrDefault(y => !string.IsNullOrWhiteSpace(y)) ?? x.Key,
                    StringComparer.OrdinalIgnoreCase);

            if (trainDatesByKey.Count == 0 && stationDatesByKey.Count == 0)
            {
                return PersonalOverlapSummary.Empty;
            }

            var otherTrips = await context.TripRecords
                .AsNoTracking()
                .Where(x => x.UserId != userId)
                .Where(x => x.IsRailTrip)
                .OrderByDescending(x => x.TravelDate)
                .ToListAsync();

            if (otherTrips.Count == 0)
            {
                return PersonalOverlapSummary.Empty;
            }

            var otherUserIds = otherTrips
                .Select(x => x.UserId)
                .Distinct()
                .ToList();

            var userProfiles = await context.Users
                .AsNoTracking()
                .Where(x => otherUserIds.Contains(x.Id))
                .Select(x => new UserProfile(
                    Id: x.Id,
                    DisplayName: x.DisplayName,
                    UserName: x.UserName,
                    Email: x.Email,
                    AvatarUrl: x.AvatarUrl))
                .ToDictionaryAsync(x => x.Id);

            var trainOverlaps = new List<TrainOverlapEntry>();
            var stationOverlaps = new List<StationOverlapEntry>();

            foreach (var otherTrip in otherTrips)
            {
                userProfiles.TryGetValue(otherTrip.UserId, out var profile);

                var displayName = ResolveDisplayName(profile?.DisplayName, profile?.UserName, profile?.Email);
                var avatarUrl = NormalizeAvatarUrl(profile?.AvatarUrl);

                var trainKey = NormalizeTrainNumber(otherTrip.TrainNumber);
                if (!string.IsNullOrWhiteSpace(trainKey) && trainDatesByKey.TryGetValue(trainKey, out var myTrainDates))
                {
                    trainOverlaps.Add(new TrainOverlapEntry
                    {
                        UserId = otherTrip.UserId,
                        DisplayName = displayName,
                        AvatarUrl = avatarUrl,
                        TrainNumber = otherTrip.TrainNumber?.Trim() ?? trainKey,
                        OtherTravelDate = otherTrip.TravelDate,
                        TripId = otherTrip.Id,
                        MyTravelDates = [.. myTrainDates]
                    });
                }

                foreach (var station in ExtractTripStations(otherTrip))
                {
                    var stationKey = NormalizeStationName(station);
                    if (string.IsNullOrWhiteSpace(stationKey) || !stationDatesByKey.TryGetValue(stationKey, out var myVisitDates))
                    {
                        continue;
                    }

                    stationOverlaps.Add(new StationOverlapEntry
                    {
                        UserId = otherTrip.UserId,
                        DisplayName = displayName,
                        AvatarUrl = avatarUrl,
                        StationName = stationDisplayByKey.TryGetValue(stationKey, out var stationName)
                            ? stationName
                            : station.Trim(),
                        OtherTravelDate = otherTrip.TravelDate,
                        TripId = otherTrip.Id,
                        MyVisitDates = [.. myVisitDates]
                    });
                }
            }

            return new PersonalOverlapSummary
            {
                TrainOverlaps = trainOverlaps
                    .OrderByDescending(x => x.OtherTravelDate)
                    .ThenBy(x => x.TrainNumber, StringComparer.OrdinalIgnoreCase)
                    .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
                    .ThenBy(x => x.TripId)
                    .ToList(),
                StationOverlaps = stationOverlaps
                    .OrderByDescending(x => x.OtherTravelDate)
                    .ThenBy(x => x.StationName, StringComparer.OrdinalIgnoreCase)
                    .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
                    .ThenBy(x => x.TripId)
                    .ToList()
            };
        }

        public async Task<GlobalLeaderboard> GetGlobalLeaderboardAsync(int top = 10)
        {
            top = Math.Clamp(top, 1, 50);
            await using var context = await contextFactory.CreateDbContextAsync();

            var railTrips = await context.TripRecords
                .AsNoTracking()
                .Where(x => x.IsRailTrip)
                .ToListAsync();

            var nonRailTrips = await context.TripRecords
                .AsNoTracking()
                .Where(x => !x.IsRailTrip)
                .ToListAsync();

            if (railTrips.Count == 0 && nonRailTrips.Count == 0)
            {
                return GlobalLeaderboard.Empty;
            }

            var allTrips = railTrips
                .Concat(nonRailTrips)
                .ToList();

            var today = DateOnly.FromDateTime(DateTime.Today);
            var yearStart = new DateOnly(today.Year, 1, 1);
            var nextYearStart = yearStart.AddYears(1);
            var monthStart = GetCurrentMonthStart();
            var nextMonthStart = monthStart.AddMonths(1);
            var currentMonthTrips = allTrips
                .Where(x => x.TravelDate >= monthStart && x.TravelDate < nextMonthStart)
                .ToList();
            var weekStart = GetCurrentWeekStart(today);
            var nextWeekStart = weekStart.AddDays(7);
            var currentWeekTrips = allTrips
                .Where(x => x.TravelDate >= weekStart && x.TravelDate < nextWeekStart)
                .ToList();
            var currentYearTrips = allTrips
                .Where(x => x.TravelDate >= yearStart && x.TravelDate < nextYearStart)
                .ToList();

            var userTripStats = railTrips
                .GroupBy(x => x.UserId)
                .Select(g => new UserTripStat(
                    UserId: g.Key,
                    TotalTrips: g.Count(),
                    TotalSpend: g.Sum(x => x.Price),
                    TotalMileageKm: g.Sum(GetTripMileage)))
                .ToList();

            var nonRailUserMileageStats = nonRailTrips
                .GroupBy(x => x.UserId)
                .Select(g => new UserMileageStat(
                    UserId: g.Key,
                    TotalMileageKm: g.Sum(GetTripMileage)))
                .ToList();

            var userIds = userTripStats
                .Select(x => x.UserId)
                .Concat(nonRailUserMileageStats.Select(x => x.UserId))
                .Distinct()
                .ToList();
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

            var nonRailEntries = nonRailUserMileageStats
                .Select(x =>
                {
                    userProfiles.TryGetValue(x.UserId, out var profile);
                    return new LeaderboardEntry
                    {
                        UserId = x.UserId,
                        DisplayName = ResolveDisplayName(profile?.DisplayName, profile?.UserName, profile?.Email),
                        AvatarUrl = NormalizeAvatarUrl(profile?.AvatarUrl),
                        TotalMileageKm = x.TotalMileageKm
                    };
                })
                .ToList();

            var tripEntries = railTrips
                .Select(trip =>
                {
                    userProfiles.TryGetValue(trip.UserId, out var profile);
                    var mileageKm = GetTripMileage(trip);
                    return new TripLeaderboardEntry
                    {
                        TripId = trip.Id,
                        UserId = trip.UserId,
                        DisplayName = ResolveDisplayName(profile?.DisplayName, profile?.UserName, profile?.Email),
                        AvatarUrl = NormalizeAvatarUrl(profile?.AvatarUrl),
                        TrainNumber = trip.TrainNumber,
                        FromStation = trip.FromStation,
                        ToStation = trip.ToStation,
                        TravelDate = trip.TravelDate,
                        Price = trip.Price,
                        MileageKm = mileageKm,
                        PricePerKm = CalculatePricePerKm(trip.Price, mileageKm)
                    };
                })
                .ToList();

            var mileagePricedTripEntries = tripEntries
                .Where(x => x.MileageKm > 0 && x.PricePerKm > 0)
                .ToList();

            return new GlobalLeaderboard
            {
                CumulativeTotalTrips = allTrips.Count,
                CumulativeTotalMileageKm = allTrips.Sum(GetTripMileage),
                CurrentYearTotalTrips = currentYearTrips.Count,
                CurrentYearTotalMileageKm = currentYearTrips.Sum(GetTripMileage),
                CurrentMonthTotalTrips = currentMonthTrips.Count,
                CurrentMonthTotalMileageKm = currentMonthTrips.Sum(GetTripMileage),
                CurrentWeekTotalTrips = currentWeekTrips.Count,
                CurrentWeekTotalMileageKm = currentWeekTrips.Sum(GetTripMileage),
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
                    .ToList(),
                TopByNonRailMileage = nonRailEntries
                    .Where(x => x.TotalMileageKm > 0)
                    .OrderByDescending(x => x.TotalMileageKm)
                    .ThenBy(x => x.DisplayName, StringComparer.OrdinalIgnoreCase)
                    .Take(top)
                    .ToList(),
                TopSingleBySpend = tripEntries
                    .OrderByDescending(x => x.Price)
                    .ThenByDescending(x => x.MileageKm)
                    .ThenByDescending(x => x.TravelDate)
                    .ThenBy(x => x.TripId)
                    .Take(top)
                    .ToList(),
                TopSingleByMileage = tripEntries
                    .OrderByDescending(x => x.MileageKm)
                    .ThenByDescending(x => x.Price)
                    .ThenByDescending(x => x.TravelDate)
                    .ThenBy(x => x.TripId)
                    .Take(top)
                    .ToList(),
                TopSingleByCostPerformance = mileagePricedTripEntries
                    .OrderBy(x => x.PricePerKm)
                    .ThenByDescending(x => x.MileageKm)
                    .ThenBy(x => x.Price)
                    .ThenBy(x => x.TripId)
                    .Take(top)
                    .ToList(),
                TopSingleByLuxury = mileagePricedTripEntries
                    .OrderByDescending(x => x.PricePerKm)
                    .ThenByDescending(x => x.Price)
                    .ThenByDescending(x => x.MileageKm)
                    .ThenBy(x => x.TripId)
                    .Take(top)
                    .ToList(),
                TopStationsByVisits = BuildTopElementEntries(
                    railTrips.SelectMany(ExtractTripStations),
                    top),
                TopTrainsByTrips = BuildTopElementEntries(
                    railTrips.Select(x => x.TrainNumber),
                    top),
                TopRoutesByTrips = BuildTopElementEntries(
                    railTrips.SelectMany(ExtractRouteVisitsForTrip),
                    top)
            };
        }

        private static List<ElementLeaderboardEntry> BuildTopElementEntries(IEnumerable<string?> values, int top)
        {
            return values
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Select(x => x!.Trim())
                .GroupBy(x => x, StringComparer.OrdinalIgnoreCase)
                .Select(g => new ElementLeaderboardEntry
                {
                    Name = g.First(),
                    Count = g.Count()
                })
                .OrderByDescending(x => x.Count)
                .ThenBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
                .Take(top)
                .ToList();
        }

        private static DateOnly GetCurrentMonthStart()
        {
            var today = DateOnly.FromDateTime(DateTime.Today);
            return new DateOnly(today.Year, today.Month, 1);
        }

        private static DateOnly GetCurrentWeekStart(DateOnly date)
        {
            var dayOfWeek = (int)date.DayOfWeek;
            var offset = dayOfWeek == 0 ? 6 : dayOfWeek - 1;
            return date.AddDays(-offset);
        }

        private static IEnumerable<string> ExtractRouteVisitsForTrip(TripRecord trip)
        {
            var routeNames = (trip.ViaRouteSegments ?? [])
                .Select(x => x.RouteName?.Trim())
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Cast<string>()
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            if (routeNames.Count > 0)
            {
                return routeNames;
            }

            var from = trip.FromStation?.Trim();
            var to = trip.ToStation?.Trim();
            if (string.IsNullOrWhiteSpace(from) || string.IsNullOrWhiteSpace(to))
            {
                return [];
            }

            return [$"{from} -> {to}"];
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

        private static decimal CalculatePricePerKm(decimal price, decimal mileageKm)
        {
            if (price <= 0 || mileageKm <= 0)
            {
                return 0m;
            }

            return price / mileageKm;
        }

        private static string NormalizeTrainNumber(string? trainNumber)
        {
            if (string.IsNullOrWhiteSpace(trainNumber))
            {
                return string.Empty;
            }

            return trainNumber.Trim().ToUpperInvariant();
        }

        private static string NormalizeStationName(string? stationName)
        {
            if (string.IsNullOrWhiteSpace(stationName))
            {
                return string.Empty;
            }

            return stationName.Trim();
        }

        private static IEnumerable<string> ExtractTripStations(TripRecord trip)
        {
            var stations = new List<string>();
            AddStation(stations, trip.FromStation);
            AddStation(stations, trip.ToStation);

            return stations.Distinct(StringComparer.OrdinalIgnoreCase);
        }

        private static void AddStation(List<string> stations, string? station)
        {
            if (!string.IsNullOrWhiteSpace(station))
            {
                stations.Add(station.Trim());
            }
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

        private static string? NormalizeBio(string? bio)
        {
            if (string.IsNullOrWhiteSpace(bio))
            {
                return null;
            }

            return bio.Trim();
        }

        public sealed class GlobalLeaderboard
        {
            public static GlobalLeaderboard Empty { get; } = new();

            public int CumulativeTotalTrips { get; init; }

            public decimal CumulativeTotalMileageKm { get; init; }

            public int CurrentYearTotalTrips { get; init; }

            public decimal CurrentYearTotalMileageKm { get; init; }

            public int CurrentMonthTotalTrips { get; init; }

            public decimal CurrentMonthTotalMileageKm { get; init; }

            public int CurrentWeekTotalTrips { get; init; }

            public decimal CurrentWeekTotalMileageKm { get; init; }

            public List<LeaderboardEntry> TopBySpend { get; init; } = [];

            public List<LeaderboardEntry> TopByTrips { get; init; } = [];

            public List<LeaderboardEntry> TopByMileage { get; init; } = [];

            public List<LeaderboardEntry> TopByNonRailMileage { get; init; } = [];

            public List<TripLeaderboardEntry> TopSingleBySpend { get; init; } = [];

            public List<TripLeaderboardEntry> TopSingleByMileage { get; init; } = [];

            public List<TripLeaderboardEntry> TopSingleByCostPerformance { get; init; } = [];

            public List<TripLeaderboardEntry> TopSingleByLuxury { get; init; } = [];

            public List<ElementLeaderboardEntry> TopStationsByVisits { get; init; } = [];

            public List<ElementLeaderboardEntry> TopTrainsByTrips { get; init; } = [];

            public List<ElementLeaderboardEntry> TopRoutesByTrips { get; init; } = [];
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

        public sealed class PublicUserProfile
        {
            public required string UserId { get; init; }

            public required string DisplayName { get; init; }

            public string? UserName { get; init; }

            public string? Email { get; init; }

            public string? AvatarUrl { get; init; }

            public string? Bio { get; init; }

            public bool ShowEmail { get; init; }
        }

        public sealed class TripLeaderboardEntry
        {
            public int TripId { get; init; }

            public required string UserId { get; init; }

            public required string DisplayName { get; init; }

            public string? AvatarUrl { get; init; }

            public required string TrainNumber { get; init; }

            public required string FromStation { get; init; }

            public required string ToStation { get; init; }

            public DateOnly TravelDate { get; init; }

            public decimal Price { get; init; }

            public decimal MileageKm { get; init; }

            public decimal PricePerKm { get; init; }
        }

        public sealed class ElementLeaderboardEntry
        {
            public required string Name { get; init; }

            public int Count { get; init; }
        }

        public sealed class PersonalOverlapSummary
        {
            public static PersonalOverlapSummary Empty { get; } = new();

            public List<TrainOverlapEntry> TrainOverlaps { get; init; } = [];

            public List<StationOverlapEntry> StationOverlaps { get; init; } = [];
        }

        public sealed class TrainOverlapEntry
        {
            public required string UserId { get; init; }

            public required string DisplayName { get; init; }

            public string? AvatarUrl { get; init; }

            public required string TrainNumber { get; init; }

            public DateOnly OtherTravelDate { get; init; }

            public int TripId { get; init; }

            public List<DateOnly> MyTravelDates { get; init; } = [];
        }

        public sealed class StationOverlapEntry
        {
            public required string UserId { get; init; }

            public required string DisplayName { get; init; }

            public string? AvatarUrl { get; init; }

            public required string StationName { get; init; }

            public DateOnly OtherTravelDate { get; init; }

            public int TripId { get; init; }

            public List<DateOnly> MyVisitDates { get; init; } = [];
        }

        private sealed record UserTripStat(string UserId, int TotalTrips, decimal TotalSpend, decimal TotalMileageKm);

        private sealed record UserMileageStat(string UserId, decimal TotalMileageKm);

        private sealed record UserProfile(string Id, string? DisplayName, string? UserName, string? Email, string? AvatarUrl);
    }
}
