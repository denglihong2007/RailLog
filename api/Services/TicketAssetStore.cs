using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Options;
using NPinyin;

namespace RailLog.API.Services;

public sealed class TicketAssetStore
{
    private static readonly IReadOnlyDictionary<char, string> SpecialPinyin =
        new Dictionary<char, string>
        {
            ['东'] = "dong",
            ['西'] = "xi",
            ['南'] = "nan",
            ['北'] = "bei",
        };
    private readonly string? _directory;
    private readonly Lazy<IReadOnlyDictionary<string, string>> _stationPinyin;

    public TicketAssetStore(IOptions<TicketAssetsOptions> options)
    {
        var configured = options.Value.Directory.Trim();
        _directory = configured.Length == 0 ? null : Path.GetFullPath(configured);
        _stationPinyin = new Lazy<IReadOnlyDictionary<string, string>>(LoadStationPinyin);
    }

    internal string FontPath(string fileName) => RequiredPath(fileName);
    internal string BackgroundPath(TicketStyle style) =>
        RequiredPath(style == TicketStyle.Blue ? "blue.png" : "red.png");

    public string AuxiliaryStationPinyin(string station)
        => ResolveAuxiliaryPinyin(station, _stationPinyin.Value);

    internal static string ResolveAuxiliaryPinyin(
        string station,
        IReadOnlyDictionary<string, string> districts)
    {
        var normalized = NormalizeStation(station);
        if (districts.TryGetValue(normalized, out var exact)) return TicketCase(exact);

        var prefix = districts
            .Where(entry => normalized.StartsWith(entry.Key, StringComparison.Ordinal))
            .OrderByDescending(entry => entry.Key.Length)
            .FirstOrDefault();
        var pinyin = prefix.Key is null
            ? LibraryPinyin(normalized)
            : prefix.Value + LibraryPinyin(normalized[prefix.Key.Length..]);
        if (pinyin.Length == 0)
            throw new TicketAssetException($"无法生成车站“{normalized}”的拼音");
        return TicketCase(pinyin);
    }

    private IReadOnlyDictionary<string, string> LoadStationPinyin()
    {
        using var stream = File.OpenRead(RequiredPath("District.json"));
        var rows = JsonSerializer.Deserialize<List<DistrictRow>>(stream)
            ?? throw new TicketAssetException("District.json 内容无效");
        return rows
            .Where(row => !string.IsNullOrWhiteSpace(row.Name) && !string.IsNullOrWhiteSpace(row.Pinyin))
            .GroupBy(row => NormalizeStation(row.Name), StringComparer.Ordinal)
            .ToDictionary(group => group.Key, group => group.First().Pinyin.Trim(), StringComparer.Ordinal);
    }

    private string RequiredPath(string fileName)
    {
        if (_directory is null)
            throw new TicketAssetException(
                "服务端未配置 TicketAssets:Directory（可通过 dotnet user-secrets 或 TicketAssets__Directory 环境变量设置）");
        var direct = Path.Combine(_directory, fileName);
        var fonts = Path.Combine(_directory, "Fonts", fileName);
        var path = File.Exists(direct) ? direct : fonts;
        if (!File.Exists(path)) throw new TicketAssetException($"车票素材缺失：{fileName}");
        return path;
    }

    private static string NormalizeStation(string value)
    {
        var station = value.Trim();
        return station.EndsWith('站') ? station[..^1] : station;
    }

    private static string LibraryPinyin(string value)
    {
        var result = new System.Text.StringBuilder();
        foreach (var character in value)
        {
            var pinyin = SpecialPinyin.TryGetValue(character, out var special)
                ? special
                : Pinyin.GetPinyin(character.ToString());
            foreach (var item in pinyin)
            {
                if (item is >= 'a' and <= 'z' or >= 'A' and <= 'Z' or >= '0' and <= '9')
                    result.Append(char.ToLowerInvariant(item));
            }
        }
        return result.ToString();
    }

    private static string TicketCase(string value)
    {
        var normalized = value.Trim().ToLowerInvariant();
        return normalized.Length == 0
            ? normalized
            : char.ToUpperInvariant(normalized[0]) + normalized[1..];
    }

    private sealed record DistrictRow(
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("pinyin")] string Pinyin);
}

public sealed class TicketAssetException(string message) : Exception(message);

public enum TicketStyle
{
    Red,
    Blue,
}
