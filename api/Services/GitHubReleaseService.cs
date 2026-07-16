using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using RailLog.API.Models;

namespace RailLog.API.Services;

public sealed class GitHubReleaseService(
    HttpClient httpClient,
    IMemoryCache cache,
    IOptions<UpdateOptions> options)
{
    private const string CacheKey = "github-latest-release";
    private readonly UpdateOptions _options = options.Value;

    public async Task<LatestReleaseResponse> GetLatestAsync(
        CancellationToken cancellationToken)
    {
        if (cache.TryGetValue(CacheKey, out LatestReleaseResponse? cached) &&
            cached is not null)
            return cached;

        using var response = await httpClient.GetAsync(
            $"repos/{Uri.EscapeDataString(_options.GitHubOwner)}/" +
            $"{Uri.EscapeDataString(_options.GitHubRepository)}/releases/latest",
            cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var json = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);
        var root = json.RootElement;
        var tagName = RequiredString(root, "tag_name");
        var releaseUrl = RequiredString(root, "html_url");
        var assets = root.TryGetProperty("assets", out var assetsElement)
            ? assetsElement.EnumerateArray().Select(ParseAsset).ToList()
            : [];
        var result = new LatestReleaseResponse(
            NormalizeVersion(tagName),
            tagName,
            OptionalString(root, "name") ?? tagName,
            DateTime.Parse(RequiredString(root, "published_at")),
            OptionalString(root, "body"),
            releaseUrl,
            SelectWindowsAsset(assets)?.Url,
            SelectAndroidAsset(assets)?.Url,
            _options.DomesticDownloadName,
            NormalizeOptionalUrl(_options.WindowsDomesticDownloadUrl),
            NormalizeOptionalUrl(_options.AndroidDomesticDownloadUrl),
            _options.DownloadPageUrl);
        cache.Set(
            CacheKey,
            result,
            TimeSpan.FromMinutes(Math.Max(1, _options.CacheMinutes)));
        return result;
    }

    private static ReleaseAsset ParseAsset(JsonElement element) => new(
        RequiredString(element, "name"),
        RequiredString(element, "browser_download_url"));

    private static ReleaseAsset? SelectWindowsAsset(IEnumerable<ReleaseAsset> assets) =>
        assets
            .Where(asset => Regex.IsMatch(
                asset.Name,
                @"(^|[-_. ])win(dows)?([-_. ]|$)",
                RegexOptions.IgnoreCase))
            .OrderBy(asset => WindowsExtensionScore(asset.Name))
            .FirstOrDefault();

    private static ReleaseAsset? SelectAndroidAsset(IEnumerable<ReleaseAsset> assets) =>
        assets.FirstOrDefault(asset => asset.Name.EndsWith(".apk", StringComparison.OrdinalIgnoreCase));

    private static int WindowsExtensionScore(string name)
    {
        if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) return 0;
        if (name.EndsWith(".msix", StringComparison.OrdinalIgnoreCase) ||
            name.EndsWith(".msixbundle", StringComparison.OrdinalIgnoreCase)) return 1;
        if (name.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)) return 2;
        return 3;
    }

    private static string NormalizeVersion(string tagName)
    {
        var value = tagName.Trim();
        return value.StartsWith('v') || value.StartsWith('V') ? value[1..] : value;
    }

    private static string? NormalizeOptionalUrl(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static string RequiredString(JsonElement element, string property) =>
        element.GetProperty(property).GetString()
        ?? throw new InvalidDataException($"GitHub release is missing {property}");

    private static string? OptionalString(JsonElement element, string property) =>
        element.TryGetProperty(property, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private sealed record ReleaseAsset(string Name, string Url);
}
