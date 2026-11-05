using RailLog.API.Models;

namespace RailLog.API.Services;

/// <summary>
/// 全站成就重算的单飞执行器。等级分界线是成就引擎的输入之一，保存后必须重算
/// 所有用户；一轮重算约需数分钟，连续保存若各起一轮，不仅重复消耗 CPU，
/// 还会让先读到旧分界线的那一轮晚落地、覆盖新结果。这里保证同一时刻只跑一轮，
/// 运行期间的请求合并成「本轮结束后再跑一轮」。
/// </summary>
public sealed class AchievementRecomputeService(
    RailLogDatabase database,
    IHostApplicationLifetime lifetime,
    ILogger<AchievementRecomputeService> logger)
{
    private readonly object _gate = new();
    private bool _running;
    private bool _pending;
    private DateTime? _lastStartedAt;
    private DateTime? _lastFinishedAt;
    private string? _lastError;

    public AdminAchievementRecomputeStatus GetStatus()
    {
        lock (_gate) return Snapshot();
    }

    /// <summary>
    /// 请求一轮全站重算。已在运行时只登记「结束后再来一轮」，并立即返回当前状态。
    /// </summary>
    public AdminAchievementRecomputeStatus Request()
    {
        lock (_gate)
        {
            _pending = true;
            if (!_running)
            {
                _running = true;
                _pending = false;
                _ = Task.Run(RunAsync);
            }
            return Snapshot();
        }
    }

    private AdminAchievementRecomputeStatus Snapshot() =>
        new(_running, _pending, _lastStartedAt, _lastFinishedAt, _lastError);

    private async Task RunAsync()
    {
        try
        {
            while (true)
            {
                lock (_gate) _lastStartedAt = DateTime.Now;
                try
                {
                    await database.RecalculateAllAchievementsAsync(lifetime.ApplicationStopping);
                    lock (_gate) _lastError = null;
                }
                catch (OperationCanceledException) when (lifetime.ApplicationStopping.IsCancellationRequested)
                {
                    // 服务正在关闭。重算结果不是丢数据，下次启动的补算会重新覆盖。
                    lock (_gate)
                    {
                        _lastError = "服务正在关闭，重算已中止";
                        _running = false;
                        _pending = false;
                        _lastFinishedAt = DateTime.Now;
                    }
                    return;
                }
                catch (Exception exception)
                {
                    logger.LogError(exception, "Achievement recompute failed.");
                    lock (_gate) _lastError = exception.Message;
                }

                lock (_gate)
                {
                    if (!_pending)
                    {
                        _running = false;
                        _lastFinishedAt = DateTime.Now;
                        return;
                    }
                    // 重算期间又保存了新分界线，用最新配置再跑一轮。
                    _pending = false;
                }
            }
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Achievement recompute worker crashed.");
            lock (_gate)
            {
                _lastError = exception.Message;
                _running = false;
                _pending = false;
                _lastFinishedAt = DateTime.Now;
            }
        }
    }
}
