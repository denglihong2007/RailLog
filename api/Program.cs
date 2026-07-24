using RailLog.API.Services;
using System.Threading.RateLimiting;

var builder = WebApplication.CreateBuilder(args);
builder.Configuration
    .AddUserSecrets<Program>(optional: true)
    .AddEnvironmentVariables();

builder.Services.AddSingleton<RailLogDatabase>();
builder.Services.AddSingleton<TrainTimetableService>();
builder.Services.Configure<EmailOptions>(builder.Configuration.GetSection("Email"));
builder.Services.AddSingleton<EmailSender>();
builder.Services.AddSingleton<EmailVerificationService>();
builder.Services.AddMemoryCache();
builder.Services.Configure<UpdateOptions>(builder.Configuration.GetSection("Updates"));
builder.Services.Configure<TicketAssetsOptions>(builder.Configuration.GetSection("TicketAssets"));
builder.Services.Configure<TicketPdfOptions>(builder.Configuration.GetSection("TicketPdf"));
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
builder.Services
    .AddAuthentication(TokenAuthenticationHandler.SchemeName)
    .AddScheme<TokenAuthenticationOptions, TokenAuthenticationHandler>(
        TokenAuthenticationHandler.SchemeName,
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
builder.Services.AddControllers();

var app = builder.Build();

await app.Services.GetRequiredService<RailLogDatabase>().InitializeAsync();

app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();
