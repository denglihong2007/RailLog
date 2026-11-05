using System.Text.Json;

namespace RailLog.API.Services;

/// <summary>
/// 用户等级分界线。LV0 固定从 0 经验开始，之后每一级一个门槛；
/// 默认值与 App 内置值保持一致，管理后台保存后由 App 启动时拉取覆盖。
/// </summary>
public static class UserLevels
{
    public static readonly IReadOnlyList<int> DefaultThresholds = [0, 1, 50, 125, 250, 450, 800];

    public static string? Validate(IReadOnlyList<int>? thresholds)
    {
        if (thresholds is null || thresholds.Count != DefaultThresholds.Count)
            return $"需要 {DefaultThresholds.Count} 个等级门槛（LV0 至 LV{DefaultThresholds.Count - 1}）";
        if (thresholds[0] != 0) return "LV0 的门槛必须为 0";
        for (var level = 1; level < thresholds.Count; level++)
        {
            if (thresholds[level] <= 0) return "等级门槛必须大于 0";
            if (thresholds[level] <= thresholds[level - 1])
                return $"LV{level} 的门槛必须高于 LV{level - 1}";
        }
        if (thresholds[^1] > 1_000_000) return "等级门槛不能超过 1000000";
        return null;
    }

    public static IReadOnlyList<int> ParseOrDefault(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return DefaultThresholds;
        try
        {
            var thresholds = JsonSerializer.Deserialize<int[]>(json);
            return Validate(thresholds) is null && thresholds is not null
                ? thresholds
                : DefaultThresholds;
        }
        catch (JsonException)
        {
            return DefaultThresholds;
        }
    }
}
