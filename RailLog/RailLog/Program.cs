using AutoMapper;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using RailLog.Components;
using RailLog.Components.Account;
using RailLog.Data;
using RailLog.Profiles;
using RailLog.Services;
using RailLog.Shared.Models;
using System.Security.Claims;
using System.Text.Json;
using System.Text.RegularExpressions;

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

var connectionString = builder.Configuration.GetConnectionString("DefaultConnection") ?? throw new InvalidOperationException("Connection string 'DefaultConnection' not found.");
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(connectionString));
builder.Services.AddDatabaseDeveloperPageExceptionFilter();

builder.Services.AddIdentityCore<ApplicationUser>(options =>
    {
        options.SignIn.RequireConfirmedAccount = true;
        options.Stores.SchemaVersion = IdentitySchemaVersions.Version3;
        options.Password.RequireUppercase = false;       // 不强制要求大写字母
        options.Password.RequireNonAlphanumeric = false; // 不强制要求特殊字符（如 @, #, $）
    })
    .AddEntityFrameworkStores<ApplicationDbContext>()
    .AddSignInManager()
    .AddDefaultTokenProviders();

builder.Services.AddSingleton<IEmailSender<ApplicationUser>, IdentityNoOpEmailSender>();
builder.Services.AddScoped<TripService>();
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
builder.Services.AddAutoMapper(cfg =>
{
    cfg.AddProfile<MappingProfile>();
});
var app = builder.Build();

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
    var record = mapper.Map<TripRecord>(dto);
    record.UserId = userId;
    await service.SaveRecordAsync(record);
    return Results.Ok();

}).RequireAuthorization();
app.MapGet("/api/trips", async (TripService service, ClaimsPrincipal user) =>
{
    var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
    if (userId == null) return Results.Unauthorized();

    var trips = await service.GetUserTripsAsync(userId);
    return Results.Ok(trips); // 这会自动序列化为 JSON
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
            var railGoResult = ExtractRollingStockFromRailGo(railGoDoc.RootElement, normalizedTrain, date);
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
    var rollingStock = ExtractRollingStockFromRailRe(railReDoc.RootElement, date);
    return Results.Ok(new { rollingStock });
}).RequireAuthorization();

static string ExtractRollingStockFromRailGo(JsonElement root, string train, DateOnly date)
{
    if (root.ValueKind != JsonValueKind.Object)
    {
        return string.Empty;
    }

    if (!root.TryGetProperty("data", out var dataElement) || dataElement.ValueKind != JsonValueKind.Array)
    {
        return string.Empty;
    }

    var codes = new List<string>();
    foreach (var item in dataElement.EnumerateArray())
    {
        if (item.ValueKind != JsonValueKind.Object)
        {
            continue;
        }

        var runDate = item.TryGetProperty("runDate", out var runDateElement)
            ? ParseRunDate(runDateElement.GetString() ?? string.Empty)
            : null;
        if (runDate != date)
        {
            continue;
        }

        var trainNum = item.TryGetProperty("trainNum", out var trainNumElement)
            ? trainNumElement.GetString()
            : null;
        if (!IsTrainMatch(train, trainNum))
        {
            continue;
        }

        var trainCode = item.TryGetProperty("trainCode", out var codeElement)
            ? codeElement.GetString()
            : null;
        if (string.IsNullOrWhiteSpace(trainCode))
        {
            continue;
        }

        // RailGO already returns formatted model; only normalize coupling separator.
        codes.Add(trainCode.Replace(" + ", " ", StringComparison.Ordinal).Trim());
    }

    return string.Join(" ", codes.Distinct(StringComparer.OrdinalIgnoreCase));
}

static string ExtractRollingStockFromRailRe(JsonElement root, DateOnly date)
{
    if (root.ValueKind != JsonValueKind.Array)
    {
        return string.Empty;
    }

    var emuNos = new List<string>();
    foreach (var item in root.EnumerateArray())
    {
        if (item.ValueKind != JsonValueKind.Object)
        {
            continue;
        }

        if (!item.TryGetProperty("date", out var dateElement))
        {
            continue;
        }

        if (!item.TryGetProperty("emu_no", out var emuElement))
        {
            continue;
        }

        var rawDate = dateElement.GetString();
        var rawEmuNo = emuElement.GetString();
        if (string.IsNullOrWhiteSpace(rawDate) || string.IsNullOrWhiteSpace(rawEmuNo))
        {
            continue;
        }

        var runDate = ParseRunDate(rawDate);
        if (runDate is null || runDate != date)
        {
            continue;
        }

        emuNos.Add(FormatEmuNo(rawEmuNo));
    }

    return string.Join(" ", emuNos.Distinct(StringComparer.OrdinalIgnoreCase));
}

static DateOnly? ParseRunDate(string rawDate)
{
    if (DateTime.TryParse(rawDate, out var dateTime))
    {
        return DateOnly.FromDateTime(dateTime);
    }

    if (rawDate.Length >= 10 && DateOnly.TryParse(rawDate[..10], out var dateOnly))
    {
        return dateOnly;
    }

    return null;
}

static bool IsTrainMatch(string requestedTrain, string? candidateTrain)
{
    if (string.IsNullOrWhiteSpace(candidateTrain))
    {
        return false;
    }

    var requested = requestedTrain.Trim().ToUpperInvariant();
    var candidates = candidateTrain
        .Split('/', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
        .Select(x => x.ToUpperInvariant());

    return candidates.Contains(requested, StringComparer.OrdinalIgnoreCase);
}

static string FormatEmuNo(string raw)
{
    var value = raw.Trim().ToUpperInvariant();
    var match = Regex.Match(value, @"^(CR(?:H)?\d{3}[A-Z]+)(\d{4})$");
    if (!match.Success)
    {
        return value;
    }

    var prefix = match.Groups[1].Value;
    var number = match.Groups[2].Value;
    var formattedPrefix = FormatModelPrefix(prefix);
    return $"{formattedPrefix}-{number}";
}

static string FormatModelPrefix(string prefix)
{
    var baseModels = new[]
    {
        "CR400AF",
        "CR400BF",
        "CR300AF",
        "CR300BF",
        "CR200J",
        "CRH380A",
        "CRH380B",
        "CRH380C",
        "CRH380D",
        "CRH2G",
        "CRH2E",
        "CRH2C",
        "CRH2B",
        "CRH2A",
        "CRH1E",
        "CRH1B",
        "CRH1A",
        "CRH5A",
        "CRH6A",
        "CRH6F",
        "CRH3C",
        "CRH3A",
        "CRH380AL",
        "CRH380BL",
        "CRH380CL",
    };

    foreach (var baseModel in baseModels)
    {
        if (!prefix.StartsWith(baseModel, StringComparison.Ordinal))
        {
            continue;
        }

        if (prefix.Length == baseModel.Length)
        {
            return prefix;
        }

        var variant = prefix[baseModel.Length..];
        return $"{baseModel}-{variant}";
    }

    return prefix;
}

app.MapStaticAssets();
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode()
    .AddInteractiveWebAssemblyRenderMode()
    .AddAdditionalAssemblies(typeof(RailLog.Client._Imports).Assembly);

// Add additional endpoints required by the Identity /Account Razor components.
app.MapAdditionalIdentityEndpoints();

app.Run();
