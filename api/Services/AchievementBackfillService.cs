namespace RailLog.API.Services;

public sealed class AchievementBackfillService(
    RailLogDatabase database,
    ILogger<AchievementBackfillService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // Let the web host start listening before a potentially long backfill.
        await Task.Yield();
        try
        {
            await database.RecalculateAllAchievementsAsync(stoppingToken);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            // Normal application shutdown.
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Failed to backfill achievement data.");
        }
    }
}
