using RailLog.Shared.Models;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace RailLog.Data
{
    public class TripRecord : TripRecordDto
    {
        [Key]
        public int Id { get; set; }

        public required string UserId { get; set; }

        [ForeignKey(nameof(UserId))]
        public ApplicationUser? User { get; set; }

        public DateTime CreatedAt { get; set; } = DateTime.Now;
    }
}
