namespace RailLog.API.Services;

public enum TrainCategory
{
    EMU,
    Coach,
    Locomotive
}

public sealed class TrainModelParseResult
{
    public string RawSegment { get; init; } = string.Empty;
    public TrainCategory Category { get; init; }
    public string Prefix { get; init; } = string.Empty;
    public string Model { get; init; } = string.Empty;
    public List<string> Numbers { get; init; } = [];

    public string ModelCode => $"{Prefix}{Model}";
    public string StatisticsCode => Category == TrainCategory.Coach ? Model : ModelCode;
}

public static class TrainModelParser
{
    private static readonly string[] SortedPrefixes =
    [
        "SYZ", "SYW", "SRZ", "SRW", "GRW", "RZT", "RZ1", "RZ2",
        "YZ", "YW", "RZ", "RW", "KD", "WX"
    ];

    // "RZ2" is also the beginning of the standard 25-type coach models (RZ25G,
    // RZ25K, RZ25T, ...). Such a segment must be split as "RZ" + "25x" instead,
    // so a prefix listed here only applies when the segment does not start with
    // its longer counterpart.
    private static readonly Dictionary<string, string> LongerPrefixes =
        new(StringComparer.OrdinalIgnoreCase) { ["RZ2"] = "RZ25" };

    /// <summary>解析整条车型录入串。同一编组内的车型以“+”分隔，同一车型的多个
    /// 车号以“&amp;”分隔，不同完整编组之间以“/”分隔。跨编组按车型合并，因此
    /// 一个行程里的同一车型只会出现一次。</summary>
    public static List<TrainModelParseResult> ParseTrainString(string? input)
    {
        if (string.IsNullOrWhiteSpace(input))
            return [];

        var segments = new List<string>();
        foreach (var formation in input.Split('/'))
            segments.AddRange(formation.Split('+'));

        return MergeSegments(segments);
    }

    /// <summary>按编组解析，供需要区分“同时编组”语义的调用方使用：编组内部
    /// 与 <see cref="ParseTrainString"/> 一样按车型合并去重，空编组直接丢弃。</summary>
    public static List<List<TrainModelParseResult>> ParseTrainFormations(string? input)
    {
        if (string.IsNullOrWhiteSpace(input))
            return [];

        var formations = new List<List<TrainModelParseResult>>();
        foreach (var formation in input.Split('/'))
        {
            var segments = MergeSegments(formation.Split('+'));
            if (segments.Count > 0)
                formations.Add(segments);
        }
        return formations;
    }

    private static List<TrainModelParseResult> MergeSegments(IEnumerable<string> rawSegments)
    {
        var resultMap = new Dictionary<string, TrainModelParseResult>(StringComparer.OrdinalIgnoreCase);
        var orderedKeys = new List<string>();

        foreach (var rawSegment in rawSegments)
        {
            var segment = rawSegment.AsSpan().Trim();
            if (segment.IsEmpty) continue;

            TrainCategory category;
            var prefix = string.Empty;
            string model;
            var numbers = new List<string>();

            if (segment.StartsWith("MTR", StringComparison.OrdinalIgnoreCase) ||
                segment.StartsWith("CR", StringComparison.OrdinalIgnoreCase) ||
                segment.StartsWith("CJ", StringComparison.OrdinalIgnoreCase) ||
                segment.StartsWith("LCR", StringComparison.OrdinalIgnoreCase))
            {
                category = TrainCategory.EMU;
                ParseEmuSegment(segment, out model, numbers);
            }
            else
            {
                ParseLocoOrCoachSegment(segment, out category, out prefix, out model, numbers);
            }

            var key = $"{category}_{prefix}_{model}";
            if (resultMap.TryGetValue(key, out var existingResult))
            {
                foreach (var number in numbers)
                {
                    if (!existingResult.Numbers.Contains(number, StringComparer.OrdinalIgnoreCase))
                        existingResult.Numbers.Add(number);
                }
            }
            else
            {
                resultMap[key] = new TrainModelParseResult
                {
                    RawSegment = segment.ToString(),
                    Category = category,
                    Prefix = prefix,
                    Model = model,
                    Numbers = numbers
                };
                orderedKeys.Add(key);
            }
        }

        return orderedKeys.Select(key => resultMap[key]).ToList();
    }

    private static void ParseEmuSegment(
        ReadOnlySpan<char> segment,
        out string model,
        List<string> numbers)
    {
        var lastAmpersand = segment.LastIndexOf('&');
        var searchEnd = lastAmpersand >= 0 ? lastAmpersand : segment.Length;
        var numberStart = searchEnd;

        while (numberStart > 0 &&
               (char.IsDigit(segment[numberStart - 1]) || segment[numberStart - 1] == '&'))
        {
            numberStart--;
        }

        if (numberStart > 0 && numberStart < segment.Length)
        {
            var separator = segment[numberStart - 1];
            if (separator is '-' or ' ')
            {
                model = segment[..(numberStart - 1)].ToString();
                ParseAndAddNumbers(segment[numberStart..], numbers);
                return;
            }
        }

        model = segment.ToString();
    }

    private static void ParseLocoOrCoachSegment(
        ReadOnlySpan<char> segment,
        out TrainCategory category,
        out string prefix,
        out string model,
        List<string> numbers)
    {
        prefix = string.Empty;

        var spaceIndex = segment.IndexOf(' ');
        var modelPart = spaceIndex >= 0 ? segment[..spaceIndex].Trim() : segment;
        var numberPart = spaceIndex >= 0 ? segment[(spaceIndex + 1)..].Trim() : ReadOnlySpan<char>.Empty;

        if (!numberPart.IsEmpty)
            ParseAndAddNumbers(numberPart, numbers);

        foreach (var candidate in SortedPrefixes)
        {
            if (!modelPart.StartsWith(candidate, StringComparison.OrdinalIgnoreCase)) continue;
            if (LongerPrefixes.TryGetValue(candidate, out var longerPrefix) &&
                modelPart.StartsWith(longerPrefix, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            category = TrainCategory.Coach;
            prefix = candidate;
            model = modelPart[candidate.Length..].ToString();
            return;
        }

        var hasM1 = modelPart.Contains("M1", StringComparison.OrdinalIgnoreCase);
        var hasTwoDigits = HasTwoContinuousDigits(modelPart);
        var hasDf = modelPart.Contains("DF", StringComparison.OrdinalIgnoreCase);

        category = hasM1 || (hasTwoDigits && !hasDf)
            ? TrainCategory.Coach
            : TrainCategory.Locomotive;
        model = modelPart.ToString();
    }

    private static void ParseAndAddNumbers(ReadOnlySpan<char> numberSpan, List<string> targetList)
    {
        while (!numberSpan.IsEmpty)
        {
            var ampersandIndex = numberSpan.IndexOf('&');
            var number = (ampersandIndex >= 0 ? numberSpan[..ampersandIndex] : numberSpan).Trim();

            if (!number.IsEmpty)
            {
                var value = number.ToString();
                if (!targetList.Contains(value, StringComparer.OrdinalIgnoreCase))
                    targetList.Add(value);
            }

            numberSpan = ampersandIndex >= 0
                ? numberSpan[(ampersandIndex + 1)..]
                : ReadOnlySpan<char>.Empty;
        }
    }

    private static bool HasTwoContinuousDigits(ReadOnlySpan<char> span)
    {
        for (var index = 0; index < span.Length - 1; index++)
        {
            if (char.IsDigit(span[index]) && char.IsDigit(span[index + 1]))
                return true;
        }

        return false;
    }
}
