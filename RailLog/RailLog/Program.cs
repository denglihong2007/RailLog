using AutoMapper;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using RailLog.Components;
using RailLog.Components.Account;
using RailLog.Data;
using RailLog.Models;
using RailLog.Profiles;
using RailLog.Services;
using RailLog.Shared.Models;
using RailLog.Utilities;
using System.Security.Claims;
using System.Text.Json;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents()
    .AddInteractiveWebAssemblyComponents()
    .AddAuthenticationStateSerialization();

builder.Services.AddCascadingAuthenticationState();
builder.Services.AddScoped<IdentityRedirectManager>();
builder.Services.AddScoped<AuthenticationStateProvider, IdentityRevalidatingAuthenticationStateProvider>();

builder.Services.AddAuthentication(options =>
    {
        options.DefaultScheme = IdentityConstants.ApplicationScheme;
        options.DefaultSignInScheme = IdentityConstants.ExternalScheme;
    })
    .AddIdentityCookies();

builder.Services.ConfigureApplicationCookie(options =>
{
    options.ExpireTimeSpan = TimeSpan.FromDays(15);
    options.SlidingExpiration = true;
    options.Cookie.Name = "RailLog.Identity";
});

var connectionString = builder.Configuration.GetConnectionString("DefaultConnection") ?? throw new InvalidOperationException("Connection string 'DefaultConnection' not found.");
builder.Services.AddDbContextFactory<ApplicationDbContext>(options =>
    options.UseSqlite(connectionString));
builder.Services.AddDatabaseDeveloperPageExceptionFilter();

builder.Services.AddIdentityCore<ApplicationUser>(options =>
    {
        options.SignIn.RequireConfirmedAccount = false;
        options.Stores.SchemaVersion = IdentitySchemaVersions.Version3;
        options.Password.RequireUppercase = false;       // 不强制要求大写字母
        options.Password.RequireNonAlphanumeric = false; // 不强制要求特殊字符（如 @, #, $）

    })
    .AddEntityFrameworkStores<ApplicationDbContext>()
    .AddSignInManager()
    .AddDefaultTokenProviders();

builder.Services.AddTransient<IEmailSender<ApplicationUser>, EmailService>();
builder.Services.AddScoped<TripService>();
builder.Services.AddScoped<BaiduTrainTicketOcrService>();
builder.Services.AddSingleton<RouteRoutingService>();
builder.Services.AddScoped(sp => new HttpClient
{
    BaseAddress = new Uri(builder.Configuration["FrontendUrl"] ?? "https://localhost:7157")
});
builder.Services.AddHttpClient("RailGoApi", client =>
{
    client.BaseAddress = new Uri("https://data.railgo.zenglingkun.cn/");
});
builder.Services.AddHttpClient("RailGoEmuApi", client =>
{
    client.BaseAddress = new Uri("https://emu.railgo.dev/");
});
builder.Services.AddHttpClient("RailReApi", client =>
{
    client.BaseAddress = new Uri("https://api.rail.re/");
});
builder.Services.AddHttpClient("BaiduOcrApi", client =>
{
    client.BaseAddress = new Uri("https://aip.baidubce.com/");
});
builder.Services.AddAutoMapper(cfg =>
{
    cfg.AddProfile<MappingProfile>();
});
var app = builder.Build();
// 自动执行数据库迁移
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    try
    {
        var context = services.GetRequiredService<ApplicationDbContext>();
        context.Database.Migrate(); // 如果表不存在，会自动创建
    }
    catch
    {
        // 可以在这里记录日志
    }
}
// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseWebAssemblyDebugging();
    app.UseMigrationsEndPoint();
}
else
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}
app.UseStatusCodePagesWithReExecute("/not-found", createScopeForStatusCodePages: true);
app.UseHttpsRedirection();

app.UseAntiforgery();

app.MapPost("/api/trips", async (TripRecordDto dto, TripService service, ClaimsPrincipal user, IMapper mapper) =>
{
    var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (string.IsNullOrEmpty(userId)) return Results.Unauthorized();
    if (!ViaRouteSegmentValidator.AreConnected(dto.ViaRouteSegments, dto.FromStation, dto.ToStation))
    {
        return Results.BadRequest(new { message = "经由线路分段不连通，请保证上一段终点等于下一段起点。" });
    }

    var record = mapper.Map<TripRecord>(dto);
    record.UserId = userId;
    await service.SaveRecordAsync(record);
    return Results.Created($"/api/trips/{record.Id}", record);

}).RequireAuthorization();
app.MapGet("/api/trips", async (TripService service, ClaimsPrincipal user) =>
{
    var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (userId == null) return Results.Unauthorized();

    var trips = await service.GetUserTripsAsync(userId);
    return Results.Ok(trips); // 这会自动序列化为 JSON
}).RequireAuthorization();
app.MapGet("/api/trips/{id:int}", async (int id, TripService service, ClaimsPrincipal user) =>
{
    var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (userId is null) return Results.Unauthorized();

    var trip = await service.GetUserTripByIdAsync(userId, id);
    return trip is null ? Results.NotFound() : Results.Ok(trip);
}).RequireAuthorization();
app.MapGet("/api/leaderboard/trips/{id:int}", async (int id, TripService service, ClaimsPrincipal user) =>
{
    var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (userId is null) return Results.Unauthorized();

    var trip = await service.GetAnyTripByIdAsync(id);
    if (trip is null)
    {
        return Results.NotFound();
    }

    return Results.Ok(new TripRecordDto
    {
        Id = trip.Id,
        TrainNumber = trip.TrainNumber,
        TravelDate = trip.TravelDate,
        RollingStock = trip.RollingStock,
        FromStation = trip.FromStation,
        ToStation = trip.ToStation,
        DepartureTime = trip.DepartureTime,
        ArrivalTime = trip.ArrivalTime,
        MileageKm = trip.MileageKm,
        ViaRouteSegments = trip.ViaRouteSegments ?? [],
        SeatType = trip.SeatType,
        SeatNumber = trip.SeatNumber,
        Price = trip.Price,
        Notes = trip.Notes
    });
}).RequireAuthorization();
app.MapPut("/api/trips/{id:int}", async (int id, TripRecordDto dto, TripService service, ClaimsPrincipal user) =>
{
    var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (userId is null) return Results.Unauthorized();
    if (!ViaRouteSegmentValidator.AreConnected(dto.ViaRouteSegments, dto.FromStation, dto.ToStation))
    {
        return Results.BadRequest(new { message = "经由线路分段不连通，请保证上一段终点等于下一段起点。" });
    }

    var updated = await service.UpdateUserTripAsync(userId, id, dto);
    return updated ? Results.NoContent() : Results.NotFound();
}).RequireAuthorization();
app.MapDelete("/api/trips/{id:int}", async (int id, TripService service, ClaimsPrincipal user) =>
{
    var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (userId is null) return Results.Unauthorized();

    var deleted = await service.DeleteUserTripAsync(userId, id);
    return deleted ? Results.NoContent() : Results.NotFound();
}).RequireAuthorization();

app.MapGet("/api/routes/path", (string from, string to, int? targetMileage, bool? allowShortestFallback, RouteRoutingService routingService) =>
{
    if (string.IsNullOrWhiteSpace(from) || string.IsNullOrWhiteSpace(to))
    {
        return Results.BadRequest(new { message = "from and to are required" });
    }

    var fallback = allowShortestFallback ?? true;
    var result = routingService.CalculatePath(from, to, targetMileage, fallback);
    if (result is null)
    {
        return Results.Ok(new { found = false });
    }

    return Results.Ok(new
    {
        found = true,
        isMileageMatch = result.IsMileageMatch,
        totalMileageKm = result.TotalMileageKm,
        stations = result.Stations,
        routes = result.Routes,
        routeSegments = result.RouteSegments,
        stationsText = result.StationsText,
        routesText = result.RoutesText
    });
}).RequireAuthorization();

app.MapGet("/api/routes/suggest", (string type, string keyword, RouteRoutingService routingService) =>
{
    if (string.Equals(type, "route", StringComparison.OrdinalIgnoreCase))
    {
        return Results.Ok(routingService.SuggestRouteNames(keyword));
    }

    return Results.Ok(routingService.SuggestStationNames(keyword));
}).RequireAuthorization();

app.MapGet("/api/routes/stations", (string routeName, RouteRoutingService routingService) =>
{
    if (string.IsNullOrWhiteSpace(routeName))
    {
        return Results.Ok(Array.Empty<RouteStationOption>());
    }

    return Results.Ok(routingService.GetRouteStations(routeName));
}).RequireAuthorization();

app.MapGet("/api/train/preselect", async (string keyword, IHttpClientFactory httpClientFactory) =>
{
    if (string.IsNullOrWhiteSpace(keyword))
    {
        return Results.Ok(Array.Empty<string>());
    }

    var client = httpClientFactory.CreateClient("RailGoApi");
    using var response = await client.GetAsync($"api/train/preselect?keyword={Uri.EscapeDataString(keyword)}");
    if (!response.IsSuccessStatusCode)
    {
        return Results.StatusCode((int)response.StatusCode);
    }

    var raw = await response.Content.ReadAsStringAsync();
    try
    {
        var items = JsonSerializer.Deserialize<List<string>>(raw) ?? [];
        return Results.Ok(items);
    }
    catch (JsonException)
    {
        return Results.Ok(Array.Empty<string>());
    }
}).RequireAuthorization();

app.MapGet("/api/train/query", async (string train, IHttpClientFactory httpClientFactory) =>
{
    if (string.IsNullOrWhiteSpace(train))
    {
        return Results.BadRequest(new { message = "train is required" });
    }

    var client = httpClientFactory.CreateClient("RailGoApi");
    using var response = await client.GetAsync($"api/train/query?train={Uri.EscapeDataString(train)}");
    if (!response.IsSuccessStatusCode)
    {
        return Results.StatusCode((int)response.StatusCode);
    }

    var json = await response.Content.ReadAsStringAsync();
    return Results.Content(json, "application/json; charset=utf-8");
}).RequireAuthorization();

app.MapGet("/api/train/rolling-stock", async (string train, DateOnly date, IHttpClientFactory httpClientFactory) =>
{
    if (string.IsNullOrWhiteSpace(train))
    {
        return Results.BadRequest(new { message = "train is required" });
    }

    var normalizedTrain = train.Trim().ToUpperInvariant();

    // Priority 1: RailGO emu API (already formatted model string).
    try
    {
        var railGoClient = httpClientFactory.CreateClient("RailGoEmuApi");
        using var railGoResponse = await railGoClient.GetAsync($"api/query?keyword={Uri.EscapeDataString(normalizedTrain)}");
        if (railGoResponse.IsSuccessStatusCode)
        {
            await using var railGoStream = await railGoResponse.Content.ReadAsStreamAsync();
            using var railGoDoc = await JsonDocument.ParseAsync(railGoStream);
            var railGoResult = RollingStockExtractor.ExtractFromRailGo(railGoDoc.RootElement, normalizedTrain, date);
            if (!string.IsNullOrWhiteSpace(railGoResult))
            {
                return Results.Ok(new { rollingStock = railGoResult });
            }
        }
    }
    catch
    {
        // Ignore and fallback to Rail.Re.
    }

    // Priority 2: Rail.Re fallback.
    var railReClient = httpClientFactory.CreateClient("RailReApi");
    using var railReResponse = await railReClient.GetAsync($"train/{Uri.EscapeDataString(normalizedTrain)}");
    if (!railReResponse.IsSuccessStatusCode)
    {
        return Results.StatusCode((int)railReResponse.StatusCode);
    }

    await using var railReStream = await railReResponse.Content.ReadAsStreamAsync();
    using var railReDoc = await JsonDocument.ParseAsync(railReStream);
    var rollingStock = RollingStockExtractor.ExtractFromRailRe(railReDoc.RootElement, date);
    return Results.Ok(new { rollingStock });
}).RequireAuthorization();
app.MapPost("/api/ocr/train-ticket", async (HttpRequest request, BaiduTrainTicketOcrService ocrService, CancellationToken cancellationToken) =>
{
    if (!request.HasFormContentType)
    {
        return Results.BadRequest(new { message = "请使用 multipart/form-data 上传图片。" });
    }

    var form = await request.ReadFormAsync(cancellationToken);
    var imageFile = form.Files.GetFile("imageFile");
    if (imageFile is null || imageFile.Length == 0)
    {
        return Results.BadRequest(new { message = "请选择要识别的图片。" });
    }

    if (imageFile.Length > BaiduTrainTicketOcrService.MaxImageBytes)
    {
        return Results.BadRequest(new { message = $"图片大小不能超过 {BaiduTrainTicketOcrService.MaxImageBytes / 1024 / 1024}MB。" });
    }

    using var memory = new MemoryStream();
    await imageFile.CopyToAsync(memory, cancellationToken);

    var result = await ocrService.RecognizeAsync(memory.ToArray(), cancellationToken);
    if (!result.Success || result.Data is null)
    {
        return Results.BadRequest(new { message = result.Message });
    }

    return Results.Ok(result.Data);
}).DisableAntiforgery().RequireAuthorization();

app.MapStaticAssets();
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode()
    .AddInteractiveWebAssemblyRenderMode()
    .AddAdditionalAssemblies(typeof(RailLog.Client._Imports).Assembly);

// Add additional endpoints required by the Identity /Account Razor components.
app.MapAdditionalIdentityEndpoints();

app.Run();

