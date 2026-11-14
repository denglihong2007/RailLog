using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;
using RailLog.API.Models;
using RailLog.API.Services;

namespace RailLog.API.Controllers;

[ApiController]
[Authorize(AuthenticationSchemes = AdminAuthenticationHandler.SchemeName)]
[Route("api/admin")]
public sealed class AdminController(
    RailLogDatabase database,
    IOptions<AdminOptions> options,
    IOptions<TicketPdfOptions> pdfOptions,
    IOptions<DatabaseBackupOptions> backupOptions,
    BackupStorageService backupStorage,
    TimetableSyncService timetableSync,
    AchievementRecomputeService achievementRecompute,
    IWebHostEnvironment environment,
    IHostApplicationLifetime lifetime,
    ILogger<AdminController> logger) : ControllerBase
{
    private readonly AdminOptions _options = options.Value;
    private readonly TicketPdfOptions _pdfOptions = pdfOptions.Value;
    private readonly DatabaseBackupOptions _backupOptions = backupOptions.Value;

    private string? AdminUserId =>
        User.FindFirstValue(ClaimTypes.NameIdentifier);

    /// <summary>
    /// 写一条管理员操作日志。日志失败不应让已经成功的业务操作变成 500，
    /// 因此这里吞掉异常并记录到应用程序日志。
    /// </summary>
    private async Task AuditAsync(string action, string? target = null, string? detail = null)
    {
        var adminUserId = AdminUserId;
        if (string.IsNullOrWhiteSpace(adminUserId)) return;
        try
        {
            await database.WriteAdminAuditAsync(adminUserId, action, target, detail);
        }
        catch (Exception exception)
        {
            HttpContext.RequestServices
                .GetRequiredService<ILogger<AdminController>>()
                .LogError(exception, "Failed to write admin audit entry {Action}", action);
        }
    }

    [AllowAnonymous]
    [EnableRateLimiting("admin-login")]
    [HttpPost("login")]
    public async Task<ActionResult<AdminSessionResponse>> Login(AdminLoginRequest request)
    {
        var email = request.Email?.Trim() ?? string.Empty;
        if (email.Length == 0 || string.IsNullOrEmpty(request.Password))
            return Unauthorized(new MessageResponse("请输入邮箱和密码"));
        var session = await database.LoginAsync(new LoginRequest(email, request.Password));
        if (session is null)
        {
            // 让暴力破解保持一个不痛不痒但也不为零的成本。
            await Task.Delay(250);
            return Unauthorized(new MessageResponse("邮箱或密码错误"));
        }
        if (!_options.IsAdmin(session.User.Id))
        {
            // 密码本身有效，但这个账户不是管理员；撤销刚签发的普通令牌，
            // 避免管理员登录页悄悄变成普通用户令牌的签发入口。
            await database.RevokeTokenAsync(session.Token);
            return StatusCode(
                StatusCodes.Status403Forbidden,
                new MessageResponse("该账户没有管理员权限"));
        }
        return Ok(new AdminSessionResponse(
            session.Token,
            session.ExpiresAt,
            session.User.Id,
            session.User.DisplayName));
    }

    [HttpPost("logout")]
    public async Task<IActionResult> Logout()
    {
        var header = Request.Headers.Authorization.ToString();
        if (header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            await database.RevokeTokenAsync(header["Bearer ".Length..].Trim());
        return NoContent();
    }

    // ---- 公告 ----

    [HttpGet("announcements")]
    public async Task<ActionResult<IReadOnlyList<AdminAnnouncement>>> GetAnnouncements() =>
        Ok(await database.GetAnnouncementsAsync());

    [HttpPost("announcements")]
    public async Task<ActionResult<AdminAnnouncement>> SaveAnnouncement(
        AdminAnnouncementRequest request)
    {
        var result = await database.SaveAnnouncementAsync(request);
        if (result.Item is null)
            return BadRequest(new MessageResponse(result.Error!));
        await AuditAsync(
            "announcement.save",
            result.Item.Id,
            string.IsNullOrWhiteSpace(request.Id) ? "新建公告" : "修改公告");
        return Ok(result.Item);
    }

    [HttpDelete("announcements/{id}")]
    public async Task<IActionResult> DeleteAnnouncement(string id)
    {
        if (!await database.DeleteAnnouncementAsync(id)) return NotFound();
        await AuditAsync("announcement.delete", id);
        return NoContent();
    }

    // ---- 用户与行程 ----

    [HttpGet("users")]
    public async Task<ActionResult<AdminUserPage>> GetUsers(
        [FromQuery] string? query,
        [FromQuery] int? level,
        [FromQuery] string? sort,
        [FromQuery] string? order,
        [FromQuery] int offset = 0,
        [FromQuery] int limit = 50) =>
        Ok(await database.GetAdminUsersAsync(query, level, sort, order, offset, limit));

    [HttpGet("users/{userId}")]
    public async Task<ActionResult<AdminUserSummary>> GetUser(string userId)
    {
        var user = await database.GetAdminUserAsync(userId);
        return user is null ? NotFound() : Ok(user);
    }

    [HttpPut("users/{userId}")]
    public async Task<ActionResult<AdminUserSummary>> UpdateUser(
        string userId,
        AdminUserUpdateRequest request)
    {
        var result = await database.UpdateAdminUserAsync(userId, request);
        if (result.User is null)
            return BadRequest(new MessageResponse(result.Error!));
        await AuditAsync("user.update", userId, $"昵称 {result.User.DisplayName}");
        return Ok(result.User);
    }

    /// <summary>
    /// 删除账户是硬删除：外键级联会带走行程、评价、成就与令牌。
    /// 管理员账户不允许通过后台删除，避免把自己锁在门外。
    /// </summary>
    [HttpDelete("users/{userId}")]
    public async Task<IActionResult> DeleteUser(string userId)
    {
        if (_options.IsAdmin(userId))
            return BadRequest(new MessageResponse("不能删除管理员账户"));
        var user = await database.GetAdminUserAsync(userId);
        if (!await database.DeleteAdminUserAsync(userId)) return NotFound();
        await AuditAsync(
            "user.delete",
            userId,
            user is null ? null : $"昵称 {user.DisplayName}，{user.Email}");
        return NoContent();
    }

    [HttpGet("users/{userId}/trips")]
    public async Task<ActionResult<IReadOnlyList<AdminTrip>>> GetTrips(
        string userId,
        [FromQuery] bool includeDeleted = true) =>
        Ok(await database.GetAdminTripsAsync(userId, includeDeleted));

    [HttpPost("users/{userId}/trips")]
    public async Task<ActionResult<AdminTrip>> CreateTrip(
        string userId,
        AdminTripRequest request)
    {
        var result = await database.CreateAdminTripAsync(userId, request);
        if (result.Trip is null)
            return BadRequest(new MessageResponse(result.Error!));
        await AuditAsync(
            "trip.create",
            result.Trip.TicketId.ToString(),
            $"{result.Trip.TrainNumber} {result.Trip.FromStation}→{result.Trip.ToStation}");
        return Ok(result.Trip);
    }

    /// <summary>按行程 ID 直接定位，供顶栏的「行程 ID」跳转使用。</summary>
    [HttpGet("trips/{ticketId:long}")]
    public async Task<ActionResult<AdminTrip>> GetTrip(long ticketId)
    {
        var trip = await database.GetAdminTripAsync(ticketId);
        return trip is null ? NotFound(new MessageResponse("没有找到该行程")) : Ok(trip);
    }

    [HttpPut("trips/{ticketId:long}")]
    public async Task<ActionResult<AdminTrip>> UpdateTrip(
        long ticketId,
        AdminTripRequest request)
    {
        var result = await database.UpdateAdminTripAsync(ticketId, request);
        if (result.Trip is null)
            return BadRequest(new MessageResponse(result.Error!));
        await AuditAsync(
            "trip.update",
            ticketId.ToString(),
            $"{result.Trip.TrainNumber} {result.Trip.FromStation}→{result.Trip.ToStation}");
        return Ok(result.Trip);
    }

    [HttpDelete("trips/{ticketId:long}")]
    public async Task<IActionResult> DeleteTrip(long ticketId)
    {
        if (!await database.DeleteAdminTripAsync(ticketId)) return NotFound();
        await AuditAsync("trip.delete", ticketId.ToString());
        return NoContent();
    }

    // ---- PDF 下载密码 ----

    [HttpGet("ticket-password")]
    public async Task<ActionResult<AdminTicketPasswordStatus>> GetTicketPasswordStatus()
    {
        var stored = await database.GetTicketPasswordHashAsync();
        if (stored is not null)
            return Ok(new AdminTicketPasswordStatus(true, "database", stored.Value.UpdatedAt));
        return Ok(string.IsNullOrWhiteSpace(_pdfOptions.DownloadPassword)
            ? new AdminTicketPasswordStatus(false, "none", null)
            : new AdminTicketPasswordStatus(true, "configuration", null));
    }

    [HttpPut("ticket-password")]
    public async Task<IActionResult> SetTicketPassword(AdminTicketPasswordRequest request)
    {
        var password = request.Password ?? string.Empty;
        if (password.Length is < 4 or > 128 || string.IsNullOrWhiteSpace(password))
            return BadRequest(new MessageResponse("密码长度应为 4 至 128 个字符"));
        await database.SetTicketPasswordAsync(password);
        // 日志只记「改过密码」，绝不记录密码本身或它的摘要。
        await AuditAsync("ticket-password.set");
        return NoContent();
    }

    [HttpDelete("ticket-password")]
    public async Task<IActionResult> ClearTicketPassword()
    {
        if (!await database.ClearTicketPasswordAsync()) return NotFound();
        await AuditAsync("ticket-password.clear");
        return NoContent();
    }

    // ---- PDF 下载请求 Key ----

    [HttpGet("pdf-requests")]
    public async Task<ActionResult<AdminPdfRequestPage>> GetPdfRequests(
        [FromQuery] string? query,
        [FromQuery] string? sort,
        [FromQuery] string? order,
        [FromQuery] int offset = 0,
        [FromQuery] int limit = 50) =>
        Ok(await database.GetAdminPdfRequestsAsync(query, sort, order, offset, limit));

    [HttpDelete("pdf-requests/{id}")]
    public async Task<IActionResult> DeletePdfRequest(string id)
    {
        if (!await database.DeleteAdminPdfRequestAsync(id)) return NotFound();
        await AuditAsync("pdf-request.revoke", id);
        return NoContent();
    }

    /// <summary>清理已经过期的请求 Key；新的 Key 生成时也会顺手清理一遍。</summary>
    [HttpPost("pdf-requests/cleanup")]
    public async Task<ActionResult<AdminPdfCleanupResult>> CleanupPdfRequests()
    {
        var removed = await database.DeleteExpiredPdfRequestsAsync();
        await AuditAsync("pdf-request.cleanup", null, $"清理 {removed} 个过期 Key");
        return Ok(new AdminPdfCleanupResult(removed));
    }

    // ---- 用户等级分界线 ----

    [HttpGet("user-levels")]
    public async Task<ActionResult<AdminUserLevelConfig>> GetUserLevels() =>
        Ok(await ReadUserLevelConfigAsync());

    [HttpPut("user-levels")]
    public async Task<ActionResult<AdminUserLevelConfig>> SaveUserLevels(
        AdminUserLevelConfigRequest request)
    {
        var (previous, _) = await database.GetUserLevelThresholdsAsync();
        var result = await database.SaveUserLevelThresholdsAsync(
            request.Thresholds ?? []);
        if (result.Thresholds is null)
            return BadRequest(new MessageResponse(result.Error!));

        // 「达到 N 级」类成就要跟随新分界线重算；全站逐个用户重算很慢，
        // 交给单飞服务在后台跑，接口先返回保存结果。
        if (!previous.SequenceEqual(result.Thresholds))
        {
            achievementRecompute.Request();
            await AuditAsync(
                "user-levels.save",
                null,
                string.Join(" / ", result.Thresholds));
        }

        return Ok(await ReadUserLevelConfigAsync());
    }

    /// <summary>等级分界线 + 按该分界线统计的各等级用户数 + 后台重算状态。</summary>
    private async Task<AdminUserLevelConfig> ReadUserLevelConfigAsync()
    {
        var (thresholds, updatedAt) = await database.GetUserLevelThresholdsAsync();
        var (totalUsers, levels) = await database.GetUserLevelStatsAsync();
        return new AdminUserLevelConfig(
            thresholds,
            UserLevels.DefaultThresholds,
            updatedAt,
            totalUsers,
            levels,
            achievementRecompute.GetStatus());
    }

    // ---- 操作日志 ----

    [HttpGet("audit-logs")]
    public async Task<ActionResult<AdminAuditPage>> GetAuditLogs(
        [FromQuery] string? query,
        [FromQuery] string? sort,
        [FromQuery] string? order,
        [FromQuery] int offset = 0,
        [FromQuery] int limit = 50) =>
        Ok(await database.GetAdminAuditLogsAsync(query, sort, order, offset, limit));

    // ---- 数据备份 ----

    [HttpGet("backups")]
    public async Task<ActionResult<AdminBackupOverview>> GetBackups(
        CancellationToken cancellationToken)
    {
        if (backupStorage.IsEnabled)
        {
            try
            {
                var remote = await backupStorage.ListAsync(cancellationToken);
                var remoteFiles = remote
                    .OrderByDescending(item => item.CreatedAt)
                    .Select(item => new AdminBackupFile(
                        item.Name, item.SizeBytes, item.CreatedAt))
                    .ToList();
                return Ok(new AdminBackupOverview(
                    _backupOptions.Enabled,
                    backupStorage.Location,
                    _backupOptions.IntervalDays,
                    _backupOptions.KeepCount,
                    remoteFiles,
                    Encrypted: true));
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                throw;
            }
            catch (Exception exception)
            {
                logger.LogError(exception, "Failed to list database backups in object storage.");
                return StatusCode(
                    StatusCodes.Status503ServiceUnavailable,
                    new MessageResponse("无法读取对象存储中的备份，请稍后重试"));
            }
        }

        var directory = ResolveBackupDirectory();
        var files = Directory.Exists(directory)
            ? new DirectoryInfo(directory)
                .EnumerateFiles("raillog-*.db", SearchOption.TopDirectoryOnly)
                .OrderByDescending(file => file.LastWriteTimeUtc)
                .Select(file => new AdminBackupFile(file.Name, file.Length, file.LastWriteTime))
                .ToList()
            : [];
        return Ok(new AdminBackupOverview(
            _backupOptions.Enabled,
            // 只回传配置值（如 backups），不把服务器的绝对路径暴露到浏览器。
            string.IsNullOrWhiteSpace(_backupOptions.Directory)
                ? "backups"
                : _backupOptions.Directory,
            _backupOptions.IntervalDays,
            _backupOptions.KeepCount,
            files,
            Encrypted: false));
    }

    /// <summary>
    /// 现场生成一份快照并直接下载。写到系统临时目录而不是 backups/，
    /// 否则这份「下载副本」会被当成一次定时备份，推迟下一轮自动备份。
    /// </summary>
    [HttpGet("backups/download")]
    public async Task<IActionResult> DownloadBackup(CancellationToken cancellationToken)
    {
        var downloadName = $"raillog-backup-{DateTime.Now:yyyyMMdd-HHmmss}.db";
        var tempPath = Path.Combine(
            Path.GetTempPath(), $"{Guid.NewGuid():N}-{downloadName}");
        try
        {
            await database.BackupToAsync(tempPath, cancellationToken);
            var stream = new FileStream(
                tempPath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read,
                bufferSize: 64 * 1024,
                options: FileOptions.Asynchronous | FileOptions.SequentialScan |
                         FileOptions.DeleteOnClose);
            await AuditAsync("backup.download", downloadName);
            return File(stream, "application/octet-stream", downloadName);
        }
        catch
        {
            TryDeleteFile(tempPath);
            throw;
        }
    }

    [HttpGet("backups/{name}/download")]
    public async Task<IActionResult> DownloadBackupFile(
        string name, CancellationToken cancellationToken)
    {
        if (!IsBackupFileName(name))
            return BadRequest(new MessageResponse("备份文件名无效"));

        if (backupStorage.IsEnabled)
        {
            if (!await backupStorage.ExistsAsync(name, cancellationToken))
                return NotFound();

            var tempPath = Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}-{name}");
            try
            {
                await backupStorage.DownloadDecryptedAsync(
                    name, tempPath, cancellationToken);
            }
            catch (InvalidDataException exception)
            {
                TryDeleteFile(tempPath);
                logger.LogError(exception, "Failed to decrypt database backup {Name}.", name);
                return StatusCode(
                    StatusCodes.Status500InternalServerError,
                    new MessageResponse("备份文件无法解密，请检查对象存储的加密口令配置"));
            }
            catch
            {
                TryDeleteFile(tempPath);
                throw;
            }

            try
            {
                var stream = new FileStream(
                    tempPath,
                    FileMode.Open,
                    FileAccess.Read,
                    FileShare.Read,
                    bufferSize: 64 * 1024,
                    options: FileOptions.Asynchronous | FileOptions.SequentialScan |
                             FileOptions.DeleteOnClose);
                await AuditAsync("backup.download-file", name);
                return File(stream, "application/octet-stream", name);
            }
            catch
            {
                TryDeleteFile(tempPath);
                throw;
            }
        }

        var path = Path.Combine(ResolveBackupDirectory(), name);
        if (!System.IO.File.Exists(path)) return NotFound();
        await AuditAsync("backup.download-file", name);
        return PhysicalFile(path, "application/octet-stream", name);
    }

    /// <summary>
    /// 删除一份保留的备份文件。删除不可撤销，前端必须二次确认；
    /// 定时备份服务只会在下一轮按保留策略补新文件，不会恢复被删的版本。
    /// </summary>
    [HttpDelete("backups/{name}")]
    public async Task<IActionResult> DeleteBackup(
        string name, CancellationToken cancellationToken)
    {
        if (!IsBackupFileName(name))
            return BadRequest(new MessageResponse("备份文件名无效"));

        if (backupStorage.IsEnabled)
        {
            if (!await backupStorage.ExistsAsync(name, cancellationToken))
                return NotFound();
            await backupStorage.DeleteAsync(name, cancellationToken);
            await AuditAsync("backup.delete", name);
            return NoContent();
        }

        var path = Path.Combine(ResolveBackupDirectory(), name);
        if (!System.IO.File.Exists(path)) return NotFound();
        try
        {
            System.IO.File.Delete(path);
        }
        catch (IOException)
        {
            return Conflict(new MessageResponse("备份文件正在被使用，请稍后再试"));
        }
        catch (UnauthorizedAccessException)
        {
            return StatusCode(
                StatusCodes.Status500InternalServerError,
                new MessageResponse("没有权限删除该备份文件"));
        }
        await AuditAsync("backup.delete", name);
        return NoContent();
    }

    private string ResolveBackupDirectory()
    {
        var configured = string.IsNullOrWhiteSpace(_backupOptions.Directory)
            ? "backups"
            : _backupOptions.Directory;
        return Path.IsPathRooted(configured)
            ? configured
            : Path.Combine(environment.ContentRootPath, configured);
    }

    private static bool IsBackupFileName(string name) =>
        name.StartsWith("raillog-", StringComparison.Ordinal) &&
        name.EndsWith(".db", StringComparison.Ordinal) &&
        name.IndexOfAny(Path.GetInvalidFileNameChars()) < 0 &&
        string.Equals(Path.GetFileName(name), name, StringComparison.Ordinal);

    private static void TryDeleteFile(string path)
    {
        try
        {
            System.IO.File.Delete(path);
        }
        catch (IOException)
        {
            // 临时文件交给系统清理。
        }
        catch (UnauthorizedAccessException)
        {
            // 临时文件交给系统清理。
        }
    }

    // ---- 历史时刻表同步 ----

    [HttpGet("timetable-sync")]
    public ActionResult<AdminTimetableSyncStatus> GetTimetableSyncStatus() =>
        Ok(timetableSync.GetStatus());

    /// <summary>
    /// 触发一轮同步。首次补齐可能持续几分钟，因此只启动后台任务并立即返回，
    /// 由页面轮询状态查看进度。
    /// </summary>
    [HttpPost("timetable-sync/run")]
    public async Task<IActionResult> RunTimetableSync()
    {
        if (timetableSync.IsRunning)
            return Conflict(new MessageResponse("历史时刻表正在同步中，请稍后再试"));

        _ = Task.Run(async () =>
        {
            try
            {
                await timetableSync.TryRunAsync("manual", lifetime.ApplicationStopping);
            }
            catch (OperationCanceledException)
            {
                // 服务正在关闭，本轮同步中止。
            }
        }, CancellationToken.None);
        await AuditAsync("timetable-sync.run");
        return Accepted(new MessageResponse("已开始同步历史时刻表"));
    }

    [HttpGet("timetable-sync/upstream")]
    public async Task<ActionResult<AdminTimetableUpstream>> GetTimetableUpstream(
        CancellationToken cancellationToken) =>
        Ok(await timetableSync.CheckUpstreamAsync(cancellationToken));

    // ---- 首页 ----

    [HttpGet("overview")]
    public async Task<ActionResult<AdminOverview>> GetOverview() =>
        Ok(await database.GetAdminOverviewAsync());

    /// <summary>概览页「查看全部」用的重复行程分组列表。</summary>
    [HttpGet("duplicates")]
    public async Task<ActionResult<AdminDuplicateGroupPage>> GetDuplicates(
        [FromQuery] int offset = 0,
        [FromQuery] int limit = 20) =>
        Ok(await database.GetAdminDuplicateGroupsAsync(offset, limit));

    /// <summary>
    /// 一键处理全部疑似重复行程：每组保留最早录入的一条，其余软删除。
    /// </summary>
    [HttpPost("duplicates/resolve")]
    public async Task<ActionResult<AdminDuplicateResolveResult>> ResolveDuplicates()
    {
        var result = await database.ResolveAdminDuplicateGroupsAsync();
        await AuditAsync(
            "duplicate.resolve",
            detail: $"处理 {result.Groups} 组，删除 {result.DeletedTrips} 条，" +
                    $"涉及 {result.AffectedUsers} 名用户");
        return Ok(result);
    }

    // ---- 排行榜 ----

    [HttpGet("leaderboards")]
    public async Task<ActionResult<StatisticsResponse>> GetLeaderboards() =>
        Ok(await database.GetStatisticsAsync(string.Empty));

    // ---- 评价管理 ----

    [HttpGet("reviews")]
    public async Task<ActionResult<AdminReviewPage>> GetReviews(
        [FromQuery] string? query,
        [FromQuery] string? entityType,
        [FromQuery] string? reviewType,
        [FromQuery] string? userId,
        [FromQuery] string? sort,
        [FromQuery] string? order,
        [FromQuery] int offset = 0,
        [FromQuery] int limit = 20) =>
        Ok(await database.GetAdminReviewsAsync(
            query, entityType, reviewType, userId, sort, order, offset, limit));

    [HttpDelete("reviews/{id:long}")]
    public async Task<IActionResult> DeleteReview(long id)
    {
        if (!await database.DeleteAdminReviewAsync(id)) return NotFound();
        await AuditAsync("review.delete", id.ToString());
        return NoContent();
    }

    /// <summary>某条评价收到的全部回应，供详情弹窗展开查看与逐条删除。</summary>
    [HttpGet("reviews/{id:long}/reactions")]
    public async Task<ActionResult<IReadOnlyList<AdminReviewReaction>>> GetReviewReactions(
        long id) =>
        Ok(await database.GetAdminReviewReactionsAsync(id));

    /// <summary>删除单条回应。作者（评价作者）的成就随之重算。</summary>
    [HttpDelete("reviews/{id:long}/reactions/{userId}")]
    public async Task<IActionResult> DeleteReviewReaction(long id, string userId)
    {
        if (!await database.RemoveEntityReviewReactionAsync(id, userId)) return NotFound();
        await AuditAsync("review-reaction.delete", $"{id}/{userId}");
        return NoContent();
    }

    /// <summary>全站回应列表：支持按回应者、评价作者、表情与关键词筛选。</summary>
    [HttpGet("reactions")]
    public async Task<ActionResult<AdminReactionPage>> GetReactions(
        [FromQuery] string? query,
        [FromQuery] string? emoji,
        [FromQuery] string? entityType,
        [FromQuery] string? reactorId,
        [FromQuery] string? authorId,
        [FromQuery] string? sort,
        [FromQuery] string? order,
        [FromQuery] int offset = 0,
        [FromQuery] int limit = 50) =>
        Ok(await database.GetAdminReactionsAsync(
            query, emoji, entityType, reactorId, authorId,
            sort, order, offset, limit));

    /// <summary>评价用户聚合榜：评价数、收到回应数、发出回应数。</summary>
    [HttpGet("review-users")]
    public async Task<ActionResult<AdminReviewUserPage>> GetReviewUsers(
        [FromQuery] string? query,
        [FromQuery] string? sort,
        [FromQuery] string? order,
        [FromQuery] int offset = 0,
        [FromQuery] int limit = 50) =>
        Ok(await database.GetAdminReviewUsersAsync(
            query, sort, order, offset, limit));

    // ---- 成就（只读） ----

    [HttpGet("achievements")]
    public async Task<ActionResult<AdminAchievementOverview>> GetAchievements() =>
        Ok(await database.GetAdminAchievementsAsync());

    [HttpGet("achievements/{achievementId}/unlocks")]
    public async Task<ActionResult<AdminAchievementUnlockPage>> GetAchievementUnlocks(
        string achievementId,
        [FromQuery] int offset = 0,
        [FromQuery] int limit = 50)
    {
        var page = await database.GetAdminAchievementUnlocksAsync(
            achievementId, offset, limit);
        return page is null
            ? NotFound(new MessageResponse("没有找到该成就"))
            : Ok(page);
    }
}
