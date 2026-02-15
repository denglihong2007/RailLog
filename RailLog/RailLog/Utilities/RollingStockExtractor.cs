using System.Text.Json;
using System.Text.RegularExpressions;

namespace RailLog.Utilities;

public static class RollingStockExtractor
{
    public static string ExtractFromRailGo(JsonElement root, string train, DateOnly date)
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

    public static string ExtractFromRailRe(JsonElement root, DateOnly date)
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

    private static DateOnly? ParseRunDate(string rawDate)
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

    private static bool IsTrainMatch(string requestedTrain, string? candidateTrain)
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

    private static string FormatEmuNo(string raw)
    {
        var value = raw.Trim().ToUpperInvariant();
        var match = Regex.Match(value, @"^(CR(?:H)?\d{1,3}[A-Z]+)(\d{4})$");
        if (!match.Success)
        {
            return value;
        }

        var prefix = match.Groups[1].Value;
        var number = match.Groups[2].Value;
        var formattedPrefix = FormatModelPrefix(prefix);
        return $"{formattedPrefix}-{number}";
    }

    private static string FormatModelPrefix(string prefix)
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
}
