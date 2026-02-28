using RailLog.Data;
using RailLog.Shared.Models;

namespace RailLog.Services;

public static class TripApiDtoMapper
{
    public static TripRecordDto ToDto(this TripRecord source)
    {
        return new TripRecordDto
        {
            Id = source.Id,
            TrainNumber = source.TrainNumber,
            TravelDate = source.TravelDate,
            RollingStock = source.RollingStock,
            FromStation = source.FromStation,
            ToStation = source.ToStation,
            DepartureTime = source.DepartureTime,
            ArrivalTime = source.ArrivalTime,
            MileageKm = source.MileageKm,
            ViaRouteSegments = source.ViaRouteSegments?
                .Select(x => new ViaRouteSegmentDto
                {
                    RouteName = x.RouteName,
                    FromStation = x.FromStation,
                    ToStation = x.ToStation,
                    MileageKm = x.MileageKm
                })
                .ToList() ?? [],
            SeatType = source.SeatType,
            SeatNumber = source.SeatNumber,
            Price = source.Price,
            Notes = source.Notes
        };
    }

    public static DashboardStatsDto ToDto(this DashboardStats source)
    {
        return new DashboardStatsDto
        {
            TotalTrips = source.TotalTrips,
            TotalSpend = source.TotalSpend,
            HighestFare = source.HighestFare,
            TotalMileageKm = source.TotalMileageKm,
            LongestTripMileageKm = source.LongestTripMileageKm,
            UniqueRoutes = source.UniqueRoutes,
            RouteStatHint = source.RouteStatHint,
            UniqueRollingStockTypes = source.UniqueRollingStockTypes,
            RollingStockRecords = source.RollingStockRecords,
            UniqueStations = source.UniqueStations,
            TopRouteVisits = source.TopRouteVisits.Select(x => x.ToDto()).ToList(),
            TopStationVisits = source.TopStationVisits.Select(x => x.ToDto()).ToList(),
            UniqueTrainNumbers = source.UniqueTrainNumbers,
            UniqueSeatTypes = source.UniqueSeatTypes,
            FirstTripDate = source.FirstTripDate,
            LatestTripDate = source.LatestTripDate,
            ExplorerLevel = source.ExplorerLevel
        };
    }

    public static AchievementItemDto ToDto(this AchievementItem source)
    {
        return new AchievementItemDto
        {
            Name = source.Name,
            IconClass = source.IconClass,
            Tier = source.Tier,
            TierName = source.TierName,
            Unlocked = source.Unlocked,
            CurrentText = source.CurrentText,
            NextLevelText = source.NextLevelText,
            TargetText = source.TargetText
        };
    }

    public static VisitRankItemDto ToDto(this VisitRankItem source)
    {
        return new VisitRankItemDto
        {
            Name = source.Name,
            Count = source.Count
        };
    }

    public static PublicUserProfileDto ToDto(this TripService.PublicUserProfile source)
    {
        return new PublicUserProfileDto
        {
            UserId = source.UserId,
            DisplayName = source.DisplayName,
            UserName = source.UserName,
            Email = source.Email,
            AvatarUrl = source.AvatarUrl,
            Bio = source.Bio,
            ShowEmail = source.ShowEmail
        };
    }

    public static PersonalOverlapSummaryDto ToDto(this TripService.PersonalOverlapSummary source)
    {
        return new PersonalOverlapSummaryDto
        {
            TrainOverlaps = source.TrainOverlaps
                .Select(x => new TrainOverlapEntryDto
                {
                    UserId = x.UserId,
                    DisplayName = x.DisplayName,
                    AvatarUrl = x.AvatarUrl,
                    TrainNumber = x.TrainNumber,
                    OtherTravelDate = x.OtherTravelDate,
                    TripId = x.TripId,
                    MyTravelDates = [.. x.MyTravelDates]
                })
                .ToList(),
            StationOverlaps = source.StationOverlaps
                .Select(x => new StationOverlapEntryDto
                {
                    UserId = x.UserId,
                    DisplayName = x.DisplayName,
                    AvatarUrl = x.AvatarUrl,
                    StationName = x.StationName,
                    OtherTravelDate = x.OtherTravelDate,
                    TripId = x.TripId,
                    MyVisitDates = [.. x.MyVisitDates]
                })
                .ToList()
        };
    }

    public static GlobalLeaderboardDto ToDto(this TripService.GlobalLeaderboard source)
    {
        return new GlobalLeaderboardDto
        {
            TopBySpend = source.TopBySpend.Select(x => x.ToDto()).ToList(),
            TopByTrips = source.TopByTrips.Select(x => x.ToDto()).ToList(),
            TopByMileage = source.TopByMileage.Select(x => x.ToDto()).ToList(),
            TopSingleBySpend = source.TopSingleBySpend.Select(x => x.ToDto()).ToList(),
            TopSingleByMileage = source.TopSingleByMileage.Select(x => x.ToDto()).ToList()
        };
    }

    private static LeaderboardEntryDto ToDto(this TripService.LeaderboardEntry source)
    {
        return new LeaderboardEntryDto
        {
            UserId = source.UserId,
            DisplayName = source.DisplayName,
            AvatarUrl = source.AvatarUrl,
            TotalSpend = source.TotalSpend,
            TotalTrips = source.TotalTrips,
            TotalMileageKm = source.TotalMileageKm
        };
    }

    private static TripLeaderboardEntryDto ToDto(this TripService.TripLeaderboardEntry source)
    {
        return new TripLeaderboardEntryDto
        {
            TripId = source.TripId,
            UserId = source.UserId,
            DisplayName = source.DisplayName,
            AvatarUrl = source.AvatarUrl,
            TrainNumber = source.TrainNumber,
            FromStation = source.FromStation,
            ToStation = source.ToStation,
            TravelDate = source.TravelDate,
            Price = source.Price,
            MileageKm = source.MileageKm
        };
    }
}
