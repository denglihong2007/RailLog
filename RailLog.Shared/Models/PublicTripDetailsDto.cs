namespace RailLog.Shared.Models
{
    public sealed class PublicTripDetailsDto
    {
        public required TripRecordDto Trip { get; init; }

        public required string OwnerUserId { get; init; }

        public required string OwnerDisplayName { get; init; }

        public string? OwnerAvatarUrl { get; init; }

        public string? OwnerBio { get; init; }
    }
}
