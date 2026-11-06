using RailLog.API.Services;
using Microsoft.AspNetCore.ResponseCompression;
using System.Threading.RateLimiting;

var builder = WebApplication.CreateBuilder(args);
builder.Configuration
    .AddUserSecrets<Program>(optional: true)
    .AddEnvironmentVariables();

// Windows 上默认日志会带上 EventLog provider，而写 ".NET Runtime" 事件源需要管理员权限。
// 非管理员运行（VSCode 调试、普通终端）时，任何 Warning 级别以上的日志都会抛
// AggregateException: Cannot open log for source '.NET Runtime'. You may not have write access.
// 这会直接打断请求与后台任务（例如敏感词目录缺失时的 LogWarning 会让首页接口 500），
// 所以本地/非管理员场景直接屏蔽该 provider，日志仍由 Console/Debug 输出。
builder.Logging.AddFilter<Microsoft.Extensions.Logging.EventLog.EventLogLoggerProvider>(
    category: null, level: LogLevel.None);

builder.Services.AddSingleton<RailLogDatabase>();
builder.Services.Configure<DatabaseBackupOptions>(
    builder.Configuration.GetSection("DatabaseBackup"));
builder.Services.AddHostedService<DatabaseBackupService>();
builder.Services.AddHostedService<AchievementBackfillService>();
builder.Services.AddSingleton<AchievementRecomputeService>();
builder.Services.Configure<TrainTimetablesOptions>(
    builder.Configuration.GetSection("TrainTimetables"));
builder.Services.AddSingleton<TrainTimetableService>();
builder.Services.AddHttpClient("timetable-sync", client =>
{
    client.BaseAddress = new Uri("https://api.github.com/");
    client.Timeout = TimeSpan.FromMinutes(10);
    client.DefaultRequestHeaders.UserAgent.ParseAdd("RailLog-Timetable-Sync/1.0");
});
// 同步服务既要后台定时跑，也要给管理后台提供状态与手动触发，所以注册成
// 单例再以同一个实例充当 HostedService。
builder.Services.AddSingleton<TimetableSyncService>();
builder.Services.AddHostedService(provider =>
    provider.GetRequiredService<TimetableSyncService>());
builder.Services.Configure<ContentModerationOptions>(
    builder.Configuration.GetSection("ContentModeration"));
builder.Services.AddSingleton<SensitiveWordService>();
builder.Services.Configure<EmailOptions>(builder.Configuration.GetSection("Email"));
builder.Services.AddSingleton<EmailSender>();
builder.Services.AddSingleton<EmailVerificationService>();
builder.Services.AddMemoryCache();
builder.Services.AddResponseCompression(options =>
{
    options.EnableForHttps = true;
});
builder.Services.Configure<UpdateOptions>(builder.Configuration.GetSection("Updates"));
builder.Services.Configure<AnnouncementOptions>(builder.Configuration.GetSection("Announcements"));
builder.Services.Configure<AdminOptions>(builder.Configuration.GetSection("Admin"));
builder.Services.Configure<TicketAssetsOptions>(builder.Configuration.GetSection("TicketAssets"));
builder.Services.Configure<TicketPdfOptions>(builder.Configuration.GetSection("TicketPdf"));
builder.Services.Configure<AmapOptions>(builder.Configuration.GetSection("Amap"));
builder.Services.AddSingleton<TicketAssetStore>();
builder.Services.AddSingleton<TicketRenderer>();
builder.Services.AddSingleton<TicketDownloadLinkStore>();
builder.Services.AddHttpClient("12306-stations", client =>
{
    client.BaseAddress = new Uri("https://kyfw.12306.cn/");
    client.Timeout = TimeSpan.FromSeconds(15);
    client.DefaultRequestHeaders.UserAgent.ParseAdd("RailLog-Station-Pinyin/1.0");
});
builder.Services.AddSingleton<StationPinyinService>();
builder.Services.AddHttpClient<TicketGeneratorService>(client =>
{
    client.BaseAddress = new Uri("https://quickchart.io/");
    client.Timeout = TimeSpan.FromSeconds(15);
});
builder.Services.AddHttpClient<GitHubReleaseService>(client =>
{
    client.BaseAddress = new Uri("https://api.github.com/");
    client.DefaultRequestHeaders.UserAgent.ParseAdd("RailLog-Update-Service/1.0");
    client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
});
builder.Services.AddHttpClient<AmapProxyService>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(20);
    client.DefaultRequestHeaders.UserAgent.ParseAdd("RailLog-Amap-Proxy/1.0");
}).ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
{
    AutomaticDecompression = System.Net.DecompressionMethods.All,
});
builder.Services
    .AddAuthentication(TokenAuthenticationHandler.SchemeName)
    .AddScheme<TokenAuthenticationOptions, TokenAuthenticationHandler>(
        TokenAuthenticationHandler.SchemeName,
        _ => { })
    .AddScheme<AdminAuthenticationOptions, AdminAuthenticationHandler>(
        AdminAuthenticationHandler.SchemeName,
        _ => { });
builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(options => options.AddPolicy("ticket-pdf", context =>
    RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 8,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0,
        })));
builder.Services.AddRateLimiter(options => options.AddPolicy("amap-proxy", context =>
    RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = 120,
            Window = TimeSpan.FromMinutes(1),
            QueueLimit = 0,
        })));
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("admin-login", context =>
        RateLimitPartition.GetFixedWindowLimiter(
            context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 5,
                Window = TimeSpan.FromMinutes(1),
                QueueLimit = 0,
            }));
});
builder.Services.AddCors(options => options.AddDefaultPolicy(policy =>
{
    if (builder.Environment.IsDevelopment())
    {
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod();
        return;
    }
    var origins = builder.Configuration
        .GetSection("Cors:AllowedOrigins")
        .Get<string[]>() ?? [];
    policy.WithOrigins(origins).AllowAnyHeader().AllowAnyMethod();
}));
builder.Services.AddCors(options => options.AddPolicy("amap-proxy", policy =>
    policy.AllowAnyOrigin().WithMethods("GET").AllowAnyHeader()));
builder.Services.AddCors(options => options.AddPolicy("public-api", policy =>
    policy.AllowAnyOrigin().WithMethods("GET").AllowAnyHeader()));
builder.Services.AddControllers();

var app = builder.Build();

await app.Services.GetRequiredService<RailLogDatabase>().InitializeAsync();

app.UseResponseCompression();
app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();
