using RailLog.Shared.Models;

namespace RailLog.Utilities;

public static class ViaRouteSegmentValidator
{
    public static bool AreConnected(IReadOnlyList<ViaRouteSegmentDto>? segments, string fromStation, string toStation)
    {
        if (segments is null || segments.Count == 0)
        {
            return true;
        }

        if (!string.Equals(segments[0].FromStation?.Trim(), fromStation?.Trim(), StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (!string.Equals(segments[^1].ToStation?.Trim(), toStation?.Trim(), StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        for (var i = 0; i < segments.Count - 1; i++)
        {
            var current = segments[i];
            var next = segments[i + 1];
            if (!string.Equals(current.ToStation?.Trim(), next.FromStation?.Trim(), StringComparison.OrdinalIgnoreCase))
            {
                return false;
            }
        }

        return true;
    }
}
