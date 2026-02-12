using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace RailLog.Shared.Models
{
    public class TripRecordDto
    {
        [Required(ErrorMessage = "请输入车次")]
        [Display(Name = "车次")]
        [RegularExpression(@"^[GDCKZTSL\d]\d{1,4}$", ErrorMessage = "车次格式不正确")]
        public string TrainNumber { get; set; } = string.Empty; // 例如：G1, D3202, K123

        [Required]
        [Display(Name = "日期")]
        public DateOnly TravelDate { get; set; } = DateOnly.FromDateTime(DateTime.Now);

        [Display(Name = "车底/本务机车")]
        public string? RollingStock { get; set; } // 例如：CR400AF-2018, HXD3C-0451

        [Required(ErrorMessage = "请输入出发站")]
        [Display(Name = "出发站")]
        public string FromStation { get; set; } = string.Empty;

        [Required(ErrorMessage = "请输入到达站")]
        [Display(Name = "到达站")]
        public string ToStation { get; set; } = string.Empty;

        [Display(Name = "出发时间")]
        public TimeOnly? DepartureTime { get; set; }

        [Display(Name = "到达时间")]
        public TimeOnly? ArrivalTime { get; set; }

        [Display(Name = "里程")]
        [Range(0.1, 50000, ErrorMessage = "里程必须大于 0")]
        [Column(TypeName = "decimal(8, 1)")]
        public decimal MileageKm { get; set; }

        [Display(Name = "席别")]
        public string? SeatType { get; set; }

        [Display(Name = "座位号")]
        public string? SeatNumber { get; set; } // 例如：05车 12A

        [Display(Name = "票价")]
        [Range(0.1, 50000, ErrorMessage = "票价必须大于 0")]
        [Column(TypeName = "decimal(18, 2)")] // 明确数据库存储精度
        public decimal Price { get; set; }

        [Display(Name = "备注")]
        public string? Notes { get; set; }
    }
}
