using MessagePack;

namespace RailLog.Models;

[MessagePackObject]
public sealed class CachedGraph
{
    [Key(0)]
    public string Version { get; set; } = string.Empty;

    [Key(1)]
    public Dictionary<string, List<CachedEdge>> AdjacencyList { get; set; } = new(StringComparer.OrdinalIgnoreCase);
}
