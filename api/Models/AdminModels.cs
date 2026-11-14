namespace RailLog.API.Models;

public sealed record AdminLoginRequest(string Email, string Password);

public sealed record AdminSessionResponse(
    string Token,
    DateTime ExpiresAt,
    string UserId,
    string DisplayName);

public sealed record AdminAnnouncementRequest(
    string? Id,
    string Text,
    int Weight,
    bool IsActive,
    int SortOrder);

public sealed record AdminAnnouncement(
    string Id,
    string Text,
    int Weight,
    bool IsActive,
    int SortOrder,
    DateTime CreatedAt,
    DateTime UpdatedAt);

public sealed record AdminUserSummary(
    string Id,
    string Email,
    string DisplayName,
    string? AvatarUrl,
    DateTime CreatedAt,
    long TripCount,
    long DeletedTripCount,
    int AchievementExperience,
    int Level,
    string? Bio = null,
    bool ShowEmailOnProfile = false);

public sealed record AdminUserUpdateRequest(
    string DisplayName,
    string Email,
    string? AvatarUrl,
    string? Bio,
    bool ShowEmailOnProfile);

public sealed record AdminUserPage(
    IReadOnlyList<AdminUserSummary> Items,
    long Total);

public sealed record AdminTrip(
    long TicketId,
    string UserId,
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
    string? GroupName,
    bool IsRailTrip,
    DateTime UpdatedAt,
    DateTime? DeletedAt,
    long SyncVersion);

public sealed record AdminTripRequest(
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
    string? GroupName,
    bool IsRailTrip,
    bool IsDeleted);

public sealed record AdminReviewTrip(
    long TicketId,
    string TrainNumber,
    DateTime TravelDate,
    string FromStation,
    string ToStation,
    DateTime? DeletedAt);

public sealed record AdminReview(
    long Id,
    string EntityType,
    string EntityKey,
    string ReviewType,
    string UserId,
    string DisplayName,
    string? Email,
    string? AvatarUrl,
    int Rating,
    string Comment,
    long? TripId,
    long? SecondTripId,
    string? RouteFromStation,
    string? RouteToStation,
    string? Dish,
    decimal? Price,
    DateTime CreatedAt,
    long ReactionCount,
    AdminReviewTrip? Trip);

public sealed record AdminReviewPage(
    IReadOnlyList<AdminReview> Items,
    long Total);

/// <summary>某条评价收到的单个表情回应，回应者信息供管理员核对。</summary>
public sealed record AdminReviewReaction(
    long ReviewId,
    string UserId,
    string DisplayName,
    string? Email,
    string? AvatarUrl,
    string Emoji,
    DateTime CreatedAt);

/// <summary>
/// 全站回应列表的一行：同时带回应者与被回应评价的信息，
/// 管理员无需再跳转页面就能判断内容是否正常。
/// </summary>
public sealed record AdminReaction(
    long ReviewId,
    string EntityType,
    string EntityKey,
    string ReviewType,
    int ReviewRating,
    string ReviewComment,
    DateTime ReviewCreatedAt,
    string ReviewAuthorId,
    string ReviewAuthorName,
    string? ReviewAuthorEmail,
    string UserId,
    string DisplayName,
    string? Email,
    string? AvatarUrl,
    string Emoji,
    DateTime CreatedAt);

public sealed record AdminReactionPage(
    long Total,
    IReadOnlyList<AdminReaction> Items);

/// <summary>
/// 评价用户聚合：评价数、收到的回应数、发出的回应数。
/// 只列出至少有过评价或回应行为的用户。
/// </summary>
public sealed record AdminReviewUser(
    string UserId,
    string DisplayName,
    string? Email,
    string? AvatarUrl,
    long ReviewCount,
    long ReceivedReactionCount,
    long GivenReactionCount,
    double? AverageRating,
    DateTime? LatestReviewAt);

public sealed record AdminReviewUserPage(
    long Total,
    IReadOnlyList<AdminReviewUser> Items);

public sealed record AdminOverviewCounts(
    long Users,
    long NewUsers,
    long ActiveTrips,
    long NewTrips,
    long DeletedTrips,
    long Reviews,
    long NewReviews,
    long ActiveAnnouncements);

public sealed record AdminFlaggedTrip(
    long TicketId,
    string UserId,
    string DisplayName,
    string TrainNumber,
    string FromStation,
    string ToStation,
    DateTime TravelDate,
    double MileageKm,
    double? SpeedKmh);

public sealed record AdminRecentReview(
    long Id,
    string UserId,
    string DisplayName,
    string EntityType,
    string EntityKey,
    string ReviewType,
    int Rating,
    string Comment,
    DateTime CreatedAt);

public sealed record AdminRecentUser(
    string Id,
    string DisplayName,
    string? Email,
    DateTime CreatedAt,
    long TripCount);

/// <summary>
/// 成就只读视图：管理员可以查看达成情况，但不能修改成就或用户记录。
/// </summary>
public sealed record AdminAchievement(
    string Id,
    string Category,
    string Icon,
    string Title,
    string Description,
    int Experience,
    bool Hidden,
    long UnlockedUserCount,
    double UnlockedPercent,
    DateTime? LatestTriggerAt);

public sealed record AdminAchievementOverview(
    long TotalUsers,
    long TotalUnlocks,
    IReadOnlyList<AdminAchievement> Achievements);

public sealed record AdminAchievementUnlock(
    string UserId,
    string DisplayName,
    string? Email,
    long TicketId,
    string TrainNumber,
    string FromStation,
    string ToStation,
    DateTime TriggeredAt,
    DateTime? DeletedAt);

public sealed record AdminAchievementUnlockPage(
    string AchievementId,
    long Total,
    IReadOnlyList<AdminAchievementUnlock> Items);

/// <summary>
/// PDF 下载密码的配置状态。出于安全考虑只描述「有没有、来自哪里」，
/// 不回传密码本身或它的摘要。
/// </summary>
/// <param name="Source">database / configuration / none</param>
public sealed record AdminTicketPasswordStatus(
    bool Configured,
    string Source,
    DateTime? UpdatedAt);

public sealed record AdminTicketPasswordRequest(string Password);

/// <summary>
/// 重复行程组内的单条行程。带上录入时间，便于判断该保留哪一条。
/// </summary>
public sealed record AdminDuplicateTrip(
    long TicketId,
    string FromStation,
    string ToStation,
    DateTime? DepartureTime,
    DateTime? ArrivalTime,
    double MileageKm,
    double Price,
    string? RollingStock,
    string? SeatType,
    string? SeatNumber,
    DateTime CreatedAt);

/// <summary>
/// 一组疑似重复行程：同一用户、同一车次、同一乘车日期、同一上下车站 ——
/// 只差录入时间的多条记录。车次号与站名按与客户端相同的规则归一化后比对；
/// 票价与里程允许不同，组上的值取最早录入的一条。
/// </summary>
public sealed record AdminDuplicateGroup(
    string UserId,
    string DisplayName,
    string TrainNumber,
    DateTime TravelDate,
    string FromStation,
    string ToStation,
    double MileageKm,
    double Price,
    IReadOnlyList<AdminDuplicateTrip> Trips);

public sealed record AdminDuplicateGroupPage(
    long TotalGroups,
    long TotalTrips,
    IReadOnlyList<AdminDuplicateGroup> Items);

/// <summary>
/// 一键处理重复行程的结果：每组保留录入时间最早的一条，其余全部软删除。
/// </summary>
public sealed record AdminDuplicateResolveResult(
    long Groups,
    long DeletedTrips,
    long AffectedUsers);

/// <summary>
/// 网页端 PDF 下载的「请求 Key」：用户先选票生成 Key，再凭 Key + 下载密码
/// 换取 PDF。后台只能看到摘要、行程与有效期，无法还原 Key 本身。
/// </summary>
public sealed record AdminPdfRequest(
    string Id,
    DateTime CreatedAt,
    DateTime ExpiresAt,
    bool Expired,
    string Style,
    string Passenger,
    string MaskedId,
    IReadOnlyList<long> TripIds);

public sealed record AdminPdfRequestPage(
    long Total,
    long ActiveCount,
    IReadOnlyList<AdminPdfRequest> Items);

public sealed record AdminPdfCleanupResult(int Removed);

// ---- 用户等级分界线 ----

/// <summary>某一等级的用户数；Percent 以全部注册用户为分母。</summary>
public sealed record AdminUserLevelStat(
    int Level,
    int MinimumExperience,
    long UserCount,
    double Percent);

/// <summary>
/// 全站成就重算的后台任务状态。调整等级分界线后需要重算所有用户的成就，
/// 该过程约需数分钟；后台页面据此显示进度并在完成后刷新等级人数。
/// </summary>
public sealed record AdminAchievementRecomputeStatus(
    bool Running,
    bool Pending,
    DateTime? LastStartedAt,
    DateTime? LastFinishedAt,
    string? LastError);

public sealed record AdminUserLevelConfig(
    IReadOnlyList<int> Thresholds,
    IReadOnlyList<int> Defaults,
    DateTime? UpdatedAt,
    long TotalUsers,
    IReadOnlyList<AdminUserLevelStat> Levels,
    AdminAchievementRecomputeStatus Recompute);

public sealed record AdminUserLevelConfigRequest(IReadOnlyList<int>? Thresholds);

// ---- 操作日志 ----

/// <summary>
/// 管理员操作留痕。AdminName 在写入时快照，账号改名后历史记录仍可读。
/// </summary>
public sealed record AdminAuditEntry(
    long Id,
    string AdminUserId,
    string AdminName,
    string Action,
    string? Target,
    string? Detail,
    DateTime CreatedAt);

public sealed record AdminAuditPage(
    long Total,
    IReadOnlyList<AdminAuditEntry> Items);

// ---- 数据备份 ----

public sealed record AdminBackupFile(
    string Name,
    long SizeBytes,
    DateTime CreatedAt);

// Directory 是本地目录或 s3://bucket/prefix，由服务端决定。
public sealed record AdminBackupOverview(
    bool Enabled,
    string Directory,
    int IntervalDays,
    int KeepCount,
    IReadOnlyList<AdminBackupFile> Items,
    bool Encrypted);

// ---- 历史时刻表同步 ----

public sealed record AdminTimetableVersion(
    string Version,
    long SizeBytes,
    DateTime ModifiedAt);

public sealed record AdminTimetableSyncStatus(
    bool Enabled,
    bool Running,
    bool HasGitHubToken,
    string Owner,
    string Repository,
    string AssetName,
    int Hour,
    int Minute,
    string TimeZone,
    string Directory,
    long TotalVersions,
    long TotalSizeBytes,
    string? NewestVersion,
    string? OldestVersion,
    DateTime? LastStartedAt,
    DateTime? LastFinishedAt,
    DateTime? NextRunAt,
    string? LastError,
    int LastSyncedCount,
    int LastMissingCount,
    string? LastTrigger,
    IReadOnlyList<AdminTimetableVersion> Versions);

public sealed record AdminTimetableUpstream(
    string Repository,
    long LocalVersions,
    long UpstreamVersions,
    IReadOnlyList<string> MissingVersions,
    string? Error);

public sealed record AdminOverview(
    AdminOverviewCounts Counts,
    long OverspeedTripCount,
    IReadOnlyList<AdminFlaggedTrip> OverspeedTrips,
    long DuplicateTripCount,
    long DuplicateGroupCount,
    IReadOnlyList<AdminDuplicateGroup> DuplicateGroups,
    IReadOnlyList<AdminRecentReview> RecentReviews,
    IReadOnlyList<AdminRecentUser> RecentUsers);
