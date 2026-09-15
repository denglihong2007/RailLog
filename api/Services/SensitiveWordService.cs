using System.Text;
using Microsoft.Extensions.Options;

namespace RailLog.API.Services;

public sealed class ContentModerationOptions
{
    public string SensitiveWordsFile { get; set; } = string.Empty;
}

public sealed class SensitiveWordService
{
    private readonly IReadOnlyList<string> _sensitiveWords;

    public SensitiveWordService(
        IOptions<ContentModerationOptions> options,
        IHostEnvironment environment,
        ILogger<SensitiveWordService> logger)
    {
        _sensitiveWords = LoadWords(
            options.Value.SensitiveWordsFile,
            environment.ContentRootPath,
            logger);
    }

    public bool ContainsSensitiveWord(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || _sensitiveWords.Count == 0)
            return false;

        var normalizedValue = Normalize(value);
        return _sensitiveWords.Any(word =>
            normalizedValue.Contains(word, StringComparison.Ordinal));
    }

    private static IReadOnlyList<string> LoadWords(
        string? filePath,
        string contentRootPath,
        ILogger logger)
    {
        if (string.IsNullOrWhiteSpace(filePath))
        {
            logger.LogWarning(
                "内容审核未启用：请通过 User Secrets 配置 ContentModeration:SensitiveWordsFile。");
            return [];
        }

        var resolvedPath = Path.IsPathRooted(filePath)
            ? filePath
            : Path.Combine(contentRootPath, filePath);
        resolvedPath = Path.GetFullPath(resolvedPath);

        if (!File.Exists(resolvedPath))
        {
            logger.LogWarning(
                "内容审核未启用：敏感词文件不存在，路径为 {SensitiveWordsFile}。",
                resolvedPath);
            return [];
        }

        try
        {
            return File.ReadLines(resolvedPath)
                .Select(Normalize)
                .Where(word => word.Length > 0)
                .Distinct(StringComparer.Ordinal)
                .ToArray();
        }
        catch (Exception exception) when (
            exception is IOException or UnauthorizedAccessException or
            ArgumentException or NotSupportedException)
        {
            logger.LogError(
                exception,
                "内容审核未启用：读取敏感词文件失败，路径为 {SensitiveWordsFile}。",
                resolvedPath);
            return [];
        }
    }

    private static string Normalize(string value)
    {
        var normalized = value.Normalize(NormalizationForm.FormKC);
        var compact = string.Concat(normalized.Where(character =>
            !char.IsWhiteSpace(character) &&
            character is not '\u200B' and not '\u200C' and not '\u200D' and not '\uFEFF'));
        return compact.ToLowerInvariant();
    }
}
