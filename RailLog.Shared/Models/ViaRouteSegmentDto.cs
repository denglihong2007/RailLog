using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace RailLog.Shared.Models
{
    public class ViaRouteSegmentDto
    {
        [Required]
        public string RouteName { get; set; } = string.Empty;

        [Required]
        public string FromStation { get; set; } = string.Empty;

        [Required]
        public string ToStation { get; set; } = string.Empty;

        [Range(0.0, 50000, ErrorMessage = "分段里程不能为负数")]
        [Column(TypeName = "decimal(8, 1)")]
        public decimal MileageKm { get; set; }
    }
}
