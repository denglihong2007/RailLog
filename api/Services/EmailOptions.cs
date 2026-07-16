namespace RailLog.API.Services;

public sealed class EmailOptions
{
    public SmtpOptions Smtp { get; init; } = new();
    public VerificationOptions Verification { get; init; } = new();
}

public sealed class SmtpOptions
{
    public string Host { get; init; } = string.Empty;
    public int Port { get; init; } = 465;
    public bool UseSsl { get; init; } = true;
    public string UserName { get; init; } = string.Empty;
    public string Password { get; init; } = string.Empty;
    public string FromEmail { get; init; } = string.Empty;
    public string FromName { get; init; } = "RailLog 轨记";
}

public sealed class VerificationOptions
{
    public int CodeLifetimeMinutes { get; init; } = 10;
    public int ResendCooldownSeconds { get; init; } = 60;
    public int MaxAttempts { get; init; } = 5;
    public string HashKey { get; init; } = string.Empty;
}
