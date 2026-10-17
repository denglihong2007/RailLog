namespace RailLog.API.Services;

public sealed class DatabaseBackupOptions
{
    public bool Enabled { get; init; } = true;
    public string Directory { get; init; } = "backups";
    public int IntervalDays { get; init; } = 2;
    public int KeepCount { get; init; } = 7;
}
