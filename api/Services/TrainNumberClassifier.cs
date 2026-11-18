namespace RailLog.API.Services;

/// <summary>
/// 普速列车判定。2026-11-25 0 时起车次字母体系调整：此前普速为 Z、T、K、Y、L、N、A
/// 字头与纯数字车次，此后为 Z、N、V、Y 字头与纯数字车次。
/// </summary>
public static class TrainNumberClassifier
{
    public static readonly DateTime ConventionalCutover = new(2026, 11, 25);

    private static readonly HashSet<char> ConventionalPrefixesBefore =
        ['Z', 'T', 'K', 'Y', 'L', 'N', 'A'];

    private static readonly HashSet<char> ConventionalPrefixesAfter =
        ['Z', 'N', 'V', 'Y'];

    /// <summary>归一化车次号：去空白与「次」，号对只取前一个号，统一大写。</summary>
    public static string Normalize(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;
        var normalized = value
            .Replace("次", string.Empty, StringComparison.Ordinal)
            .Replace(" ", string.Empty, StringComparison.Ordinal)
            .Replace("\t", string.Empty, StringComparison.Ordinal)
            .Trim()
            .ToUpperInvariant();
        var separator = normalized.IndexOf('/');
        return separator >= 0 ? normalized[..separator] : normalized;
    }

    public static bool IsConventional(string? trainNumber, DateTime departure)
    {
        var train = Normalize(trainNumber);
        if (train.Length == 0) return false;
        if (train.All(char.IsAsciiDigit)) return true;
        var prefixes = departure < ConventionalCutover
            ? ConventionalPrefixesBefore
            : ConventionalPrefixesAfter;
        return prefixes.Contains(train[0]);
    }
}
