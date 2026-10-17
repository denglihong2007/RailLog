using System.Globalization;
using Microsoft.Extensions.Options;

namespace RailLog.API.Services;

public sealed class DatabaseBackupService(
    RailLogDatabase database,
    IOptions<DatabaseBackupOptions> options,
    IWebHostEnvironment environment,
    ILogger<DatabaseBackupService> logger) : BackgroundService
{
    private const string BackupPrefix = "raillog-";
    private const string BackupSuffix = ".db";
    private static readonly TimeSpan CheckInterval = TimeSpan.FromHours(1);
    private static readonly TimeSpan StaleTempAge = TimeSpan.FromHours(1);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Let the web host start listening before a potentially slow first backup.
        await Task.Yield();

        var settings = options.Value;
        if (!settings.Enabled)
        {
            logger.LogInformation("Database backup is disabled.");
            return;
        }

        var interval = TimeSpan.FromDays(Math.Max(1, settings.IntervalDays));
        var configuredDirectory = string.IsNullOrWhiteSpace(settings.Directory)
            ? "backups"
            : settings.Directory;
        var directory = Path.IsPathRooted(configuredDirectory)
            ? configuredDirectory
            : Path.Combine(environment.ContentRootPath, configuredDirectory);

        using var timer = new PeriodicTimer(CheckInterval);
        try
        {
            do
            {
                try
                {
                    await BackupIfDueAsync(directory, interval, settings.KeepCount, stoppingToken);
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
                {
                    return;
                }
                catch (Exception exception)
                {
                    logger.LogError(exception, "Failed to back up the database.");
                }
            }
            while (await timer.WaitForNextTickAsync(stoppingToken));
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            // Normal application shutdown.
        }
    }

    private async Task BackupIfDueAsync(
        string directory, TimeSpan interval, int keepCount, CancellationToken cancellationToken)
    {
        System.IO.Directory.CreateDirectory(directory);
        DeleteStaleTempFiles(directory);

        var lastBackupUtc = EnumerateBackups(directory)
            .Select(file => (DateTime?)file.LastWriteTimeUtc)
            .Max();
        if (lastBackupUtc is { } last && DateTime.UtcNow - last < interval) return;

        var timestamp = DateTime.UtcNow.ToString(
            "yyyyMMdd-HHmmssfff'Z'", CultureInfo.InvariantCulture);
        var path = Path.Combine(directory, $"{BackupPrefix}{timestamp}{BackupSuffix}");
        var tempPath = path + ".tmp";

        try
        {
            await database.BackupToAsync(tempPath, cancellationToken);
            File.Move(tempPath, path);
        }
        catch
        {
            TryDeleteFile(tempPath);
            throw;
        }

        logger.LogInformation("Database backup created at {Path}.", path);
        PruneOldBackups(directory, Math.Max(1, keepCount));
    }

    private void PruneOldBackups(string directory, int keepCount)
    {
        var expired = EnumerateBackups(directory)
            .OrderByDescending(file => file.LastWriteTimeUtc)
            .ThenByDescending(file => file.Name, StringComparer.Ordinal)
            .Skip(keepCount);
        foreach (var file in expired)
        {
            try
            {
                file.Delete();
                logger.LogInformation("Removed old database backup {Path}.", file.FullName);
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Failed to remove old database backup {Path}.", file.FullName);
            }
        }
    }

    private static IEnumerable<FileInfo> EnumerateBackups(string directory) =>
        new System.IO.DirectoryInfo(directory)
            .EnumerateFiles($"{BackupPrefix}*{BackupSuffix}", SearchOption.TopDirectoryOnly);

    private static void DeleteStaleTempFiles(string directory)
    {
        var cutoff = DateTime.UtcNow - StaleTempAge;
        foreach (var file in new System.IO.DirectoryInfo(directory)
                     .EnumerateFiles($"{BackupPrefix}*{BackupSuffix}.tmp", SearchOption.TopDirectoryOnly))
        {
            if (file.LastWriteTimeUtc < cutoff) TryDeleteFile(file.FullName);
        }
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
            // A later attempt will clean it up.
        }
        catch (UnauthorizedAccessException)
        {
            // A later attempt will clean it up.
        }
    }
}
