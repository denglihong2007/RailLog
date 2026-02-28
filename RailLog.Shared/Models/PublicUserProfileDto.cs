namespace RailLog.Shared.Models;

public sealed class PublicUserProfileDto
{
    public string UserId { get; init; } = string.Empty;

    public string DisplayName { get; init; } = string.Empty;

    public string? UserName { get; init; }

    public string? Email { get; init; }

    public string? AvatarUrl { get; init; }

    public string? Bio { get; init; }

    public bool ShowEmail { get; init; }
}
