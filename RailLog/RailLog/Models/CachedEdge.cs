using MessagePack;

namespace RailLog.Models
{
    [MessagePackObject]
    public sealed class CachedEdge
    {
        [Key(0)]
        public string To { get; set; } = string.Empty;

        [Key(1)]
        public int Distance { get; set; }

        [Key(2)]
        public string RouteName { get; set; } = string.Empty;
    }
}

