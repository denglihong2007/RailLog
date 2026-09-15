using System.Text;
using Microsoft.Extensions.Options;

namespace RailLog.API.Services;

public sealed class ContentModerationOptions
{
    public string SensitiveWordsDirectory { get; set; } = string.Empty;
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
            options.Value.SensitiveWordsDirectory,
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
        string? directoryPath,
        string contentRootPath,
        ILogger logger)
    {
        if (string.IsNullOrWhiteSpace(directoryPath))
        {
            logger.LogWarning(
                "内容审核未启用：请通过 User Secrets 配置 ContentModeration:SensitiveWordsDirectory。");
            return [];
        }

        var resolvedDirectory = Path.IsPathRooted(directoryPath)
            ? directoryPath
            : Path.Combine(contentRootPath, directoryPath);
        resolvedDirectory = Path.GetFullPath(resolvedDirectory);

        if (!Directory.Exists(resolvedDirectory))
        {
            logger.LogWarning(
                "内容审核未启用：敏感词目录不存在，路径为 {SensitiveWordsDirectory}。",
                resolvedDirectory);
            return [];
        }

        try
        {
            var files = Directory
                .EnumerateFiles(resolvedDirectory, "*", SearchOption.AllDirectories)
                .Where(path => Path.GetExtension(path)
                    .Equals(".txt", StringComparison.OrdinalIgnoreCase))
                .OrderBy(path => path, StringComparer.OrdinalIgnoreCase)
                .ToArray();
            if (files.Length == 0)
            {
                logger.LogWarning(
                    "内容审核未启用：敏感词目录中没有 .txt 文件，路径为 {SensitiveWordsDirectory}。",
                    resolvedDirectory);
                return [];
            }

            return files
                .SelectMany(File.ReadLines)
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
                "内容审核未启用：读取敏感词目录失败，路径为 {SensitiveWordsDirectory}。",
                resolvedDirectory);
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
