namespace RailLog.API.Models;

public sealed record RegisterRequest(
    string Email,
    string DisplayName,
    string Password,
    string VerificationCode);
public sealed record LoginRequest(string Email, string Password);
public sealed record SendVerificationCodeRequest(string Email, string Purpose);
public sealed record ResetPasswordRequest(string Email, string VerificationCode, string NewPassword);
public sealed record UpdateProfileRequest(
    string DisplayName,
    string? AvatarUrl,
    string? Bio,
    bool ShowEmailOnProfile);
public sealed record UserProfile(
    string Id,
    string Email,
    string DisplayName,
    string? AvatarUrl,
    string? Bio,
    bool ShowEmailOnProfile);
public sealed record AuthResponse(string Token, DateTime ExpiresAt, UserProfile User);
public sealed record MessageResponse(string Message);
public sealed record LatestReleaseResponse(
    string Version,
    string TagName,
    string Name,
    DateTime PublishedAt,
    string? ReleaseNotes,
    string ReleaseUrl,
    string? WindowsDownloadUrl,
    string? AndroidDownloadUrl,
    string DomesticDownloadName,
    string? WindowsDomesticDownloadUrl,
    string? AndroidDomesticDownloadUrl,
    string DownloadPageUrl);
public sealed record DownloadLinksResponse(
    string DomesticDownloadName,
    string? WindowsDomesticDownloadUrl,
    string? AndroidDomesticDownloadUrl);

public sealed record GenerateTicketRequest(
    long TripId,
    string Style,
    string Passenger,
    string MaskedId,
    string SerialPrefix,
    bool ShowNewAirConditioned);

public sealed record CreateTicketPdfKeyResponse(string Key, DateTime ExpiresAt);
public sealed record DownloadTicketPdfRequest(string Key, string Password);

public sealed record SyncTrip(
    long? TicketId,
    string ClientId,
    DateTime CreatedAt,
    string TrainNumber,
    DateTime TravelDate,
    string? RollingStock,
    string? CompanyName,
    string FromStation,
    string ToStation,
    DateTime? DepartureTime,
    DateTime? ArrivalTime,
    double MileageKm,
    string ViaRoutes,
    string? SeatType,
    string? SeatNumber,
    double Price,
    string? Notes,
    bool IsRailTrip,
    DateTime UpdatedAt,
    DateTime? DeletedAt);

public sealed record SyncRequest(IReadOnlyList<SyncTrip> Trips);
public sealed record SyncResponse(IReadOnlyList<SyncTrip> Trips, DateTime ServerTime);

public sealed record IntersectionTrip(
    long TicketId,
    string UserId,
    string DisplayName,
    string? AvatarUrl,
    DateTime OccurredAt,
    bool IsStrict,
    string TrainNumber);

public sealed record IntersectionGroup(
    string Kind,
    string Location,
    int IntersectionCount,
    IReadOnlyList<IntersectionTrip> Trips);

public sealed record IntersectionsResponse(IReadOnlyList<IntersectionGroup> Intersections);

public sealed record PublicUser(
    string Id,
    string DisplayName,
    string? AvatarUrl,
    string? Bio,
    string? Email);

public sealed record PublicTrip(
    long TicketId,
    DateTime CreatedAt,
    string TrainNumber,
    string? RollingStock,
    string? CompanyName,
    string FromStation,
    string ToStation,
    DateTime? DepartureTime,
    DateTime? ArrivalTime,
    double MileageKm,
    string ViaRoutes,
    string? SeatType,
    string? SeatNumber,
    double Price,
    string? Notes,
    bool IsRailTrip);

public sealed record PublicTripSummary(
    long TicketId,
    DateTime CreatedAt,
    string TrainNumber,
    string FromStation,
    string ToStation,
    DateTime? DepartureTime,
    DateTime? ArrivalTime,
    double MileageKm,
    string? SeatType,
    string? SeatNumber,
    double Price,
    bool IsRailTrip);

public sealed record PublicTripDetailsResponse(PublicUser User, PublicTrip Trip);

public sealed record PublicUserDashboardResponse(
    PublicUser User,
    IReadOnlyList<PublicTrip> Trips);

public sealed record SiteStatistics(
    int Total,
    int ThisYear,
    int ThisMonth,
    int ThisWeek,
    SitePeriodStatistics TotalMetrics,
    SitePeriodStatistics ThisYearMetrics,
    SitePeriodStatistics ThisMonthMetrics,
    SitePeriodStatistics ThisWeekMetrics);

public sealed record SitePeriodStatistics(
    int TripCount,
    double MileageKm,
    double DurationSeconds,
    double Spending);

public sealed record UserRankingEntry(
    int Rank,
    PublicUser User,
    double Value);

public sealed record UserLeaderboards(
    IReadOnlyList<UserRankingEntry> TotalSpending,
    IReadOnlyList<UserRankingEntry> TripCount,
    IReadOnlyList<UserRankingEntry> DurationSeconds,
    IReadOnlyList<UserRankingEntry> MileageKm);

public sealed record TripRankingEntry(
    int Rank,
    PublicUser User,
    PublicTripSummary Trip,
    double Value);

public sealed record TripLeaderboards(
    IReadOnlyList<TripRankingEntry> SingleSpending,
    IReadOnlyList<TripRankingEntry> MileageKm,
    IReadOnlyList<TripRankingEntry> DurationSeconds,
    IReadOnlyList<TripRankingEntry> BestValueYuanPerKm,
    IReadOnlyList<TripRankingEntry> LuxuryYuanPerKm,
    IReadOnlyList<TripRankingEntry> SlowestAverageSpeedKmh,
    IReadOnlyList<TripRankingEntry> FastestAverageSpeedKmh);

public sealed record ElementRankingEntry(
    int Rank,
    string Name,
    int Value);

public sealed record ElementLeaderboards(
    IReadOnlyList<ElementRankingEntry> Stations,
    IReadOnlyList<ElementRankingEntry> Routes,
    IReadOnlyList<ElementRankingEntry> Trains);

public sealed record StatisticsResponse(
    SiteStatistics Site,
    UserLeaderboards Users,
    TripLeaderboards Trips,
    ElementLeaderboards Elements);
