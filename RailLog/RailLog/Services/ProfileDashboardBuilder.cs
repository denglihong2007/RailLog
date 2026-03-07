using RailLog.Data;

namespace RailLog.Services
{
    public static class ProfileDashboardBuilder
    {
        public static DashboardStats BuildDashboardStats(List<TripRecord> trips)
        {
            if (trips.Count == 0)
            {
                return DashboardStats.Empty;
            }

            var overallTotalTrips = trips.Count;
            var overallTotalMileage = trips.Sum(GetTripMileage);
            var nonRailTrips = trips.Where(x => !x.IsRailTrip).ToList();
            var nonRailTripCount = nonRailTrips.Count;
            var nonRailMileage = nonRailTrips.Sum(GetTripMileage);
            var firstTripDate = trips.Min(x => x.TravelDate);
            var latestTripDate = trips.Max(x => x.TravelDate);

            var railTrips = trips.Where(x => x.IsRailTrip).ToList();
            if (railTrips.Count == 0)
            {
                return new DashboardStats
                {
                    OverallTotalTrips = overallTotalTrips,
                    OverallTotalMileageKm = overallTotalMileage,
                    NonRailTrips = nonRailTripCount,
                    NonRailMileageKm = nonRailMileage,
                    FirstTripDate = firstTripDate,
                    LatestTripDate = latestTripDate,
                    ExplorerLevel = ResolveExplorerLevel(overallTotalMileage)
                };
            }

            var totalTrips = railTrips.Count;
            var totalSpend = railTrips.Sum(x => x.Price);
            var highestFare = railTrips.Max(x => x.Price);

            var tripMileageList = railTrips.Select(GetTripMileage).ToList();
            var totalMileage = tripMileageList.Sum();
            var longestTripMileage = tripMileageList.Max();

            var uniqueRoutesByVia = railTrips
                .SelectMany(x => x.ViaRouteSegments ?? [])
                .Select(x => x.RouteName?.Trim())
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Count();

            var routeStatHint = "按经由线路去重";
            var uniqueRoutes = uniqueRoutesByVia;
            if (uniqueRoutes == 0)
            {
                uniqueRoutes = railTrips
                    .Select(x => $"{x.FromStation.Trim()} -> {x.ToStation.Trim()}")
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .Count();
                routeStatHint = "无经由数据时按区间统计";
            }

            var rollingStockTypes = railTrips
                .SelectMany(x => ExtractRollingStockTypes(x.RollingStock))
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            var topRouteVisits = BuildTopVisitItems(
                railTrips.SelectMany(ExtractRouteVisitsForTrip),
                8);
            var topStationVisits = BuildTopVisitItems(
                railTrips.SelectMany(ExtractStationVisitsForTrip),
                8);

            var uniqueTrainNumbers = railTrips
                .Select(x => x.TrainNumber.Trim().ToUpperInvariant())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Count();

            var uniqueStations = railTrips
                .SelectMany(ExtractStationVisitsForTrip)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Count();

            var uniqueSeatTypes = railTrips
                .Where(x => !string.IsNullOrWhiteSpace(x.SeatType))
                .Select(x => x.SeatType!.Trim())
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Count();

            return new DashboardStats
            {
                OverallTotalTrips = overallTotalTrips,
                OverallTotalMileageKm = overallTotalMileage,
                NonRailTrips = nonRailTripCount,
                NonRailMileageKm = nonRailMileage,
                TotalTrips = totalTrips,
                TotalSpend = totalSpend,
                HighestFare = highestFare,
                TotalMileageKm = totalMileage,
                LongestTripMileageKm = longestTripMileage,
                UniqueRoutes = uniqueRoutes,
                RouteStatHint = routeStatHint,
                UniqueRollingStockTypes = rollingStockTypes.Count,
                RollingStockRecords = railTrips.Count(x => !string.IsNullOrWhiteSpace(x.RollingStock)),
                UniqueStations = uniqueStations,
                TopRouteVisits = topRouteVisits,
                TopStationVisits = topStationVisits,
                UniqueTrainNumbers = uniqueTrainNumbers,
                UniqueSeatTypes = uniqueSeatTypes,
                FirstTripDate = firstTripDate,
                LatestTripDate = latestTripDate,
                ExplorerLevel = ResolveExplorerLevel(overallTotalMileage)
            };
        }

        public static List<AchievementItem> BuildAchievementItems(DashboardStats stats)
        {
            return
            [
                BuildCountAchievement(
                    "发车达人",
                    "bi bi-ticket-perforated-fill",
                    stats.TotalTrips,
                    [10, 50, 100, 250, 500],
                    ["铁路新人", "发车达人", "运转狂魔", "铁道行者", "钢轨统御者"],
                    "次"),
                BuildCountAchievement(
                    "线路探索家",
                    "bi bi-signpost-split-fill",
                    stats.UniqueRoutes,
                    [5, 10, 50, 100, 250],
                    ["站台访客", "路线侦察员", "线路探索家", "干线绘图师", "路网掌控者"],
                    "条"),
                BuildMileageAchievement(
                    "里程征服者",
                    "bi bi-geo-alt-fill",
                    stats.TotalMileageKm,
                    [1000m, 5000m, 10000m, 25000m, 50000m],
                    ["短途乘客", "里程追踪者", "里程征服者", "干线穿越者", "万里轨迹王"]),
                BuildCurrencyAchievement(
                    "票价记录员",
                    "bi bi-cash-stack",
                    stats.TotalSpend,
                    [1000m, 5000m, 10000m, 25000m, 50000m],
                    ["购票新手", "预算能手", "票价记录员", "舱位策略师", "票券收藏家"]),
                BuildCountAchievement(
                    "车型图鉴",
                    "bi bi-train-front-fill",
                    stats.UniqueRollingStockTypes,
                    [5, 10, 50, 100, 250],
                    ["车型学徒", "编组观察者", "车型图鉴", "动车鉴赏家", "列车博物馆长"],
                    "种")
            ];
        }

        private static AchievementItem BuildCountAchievement(string name, string iconClass, int current, int[] targets, string[] tierTitles, string unit)
        {
            var tier = ResolveTier(current, targets);
            var nextTarget = targets.FirstOrDefault(x => x > current);

            return new AchievementItem
            {
                Name = name,
                IconClass = iconClass,
                Tier = tier,
                TierName = ResolveTierTitle(tier, tierTitles),
                Unlocked = tier > 0,
                CurrentText = $"当前：{current} {unit}",
                NextLevelText = nextTarget > 0
                    ? $"下一等级：{ResolveTierTitle(tier + 1, tierTitles)}"
                    : "下一等级：已达最高等级",
                TargetText = nextTarget > 0
                    ? $"目标：{nextTarget} {unit}"
                    : "目标：已达成最高档"
            };
        }

        private static AchievementItem BuildMileageAchievement(string name, string iconClass, decimal current, decimal[] targets, string[] tierTitles)
        {
            var tier = ResolveTier(current, targets);
            var nextTarget = targets.FirstOrDefault(x => x > current);

            return new AchievementItem
            {
                Name = name,
                IconClass = iconClass,
                Tier = tier,
                TierName = ResolveTierTitle(tier, tierTitles),
                Unlocked = tier > 0,
                CurrentText = $"当前：{current:N1} km",
                NextLevelText = nextTarget > 0
                    ? $"下一等级：{ResolveTierTitle(tier + 1, tierTitles)}"
                    : "下一等级：已达最高等级",
                TargetText = nextTarget > 0
                    ? $"目标：{nextTarget:N0} km"
                    : "目标：已达成最高档"
            };
        }

        private static AchievementItem BuildCurrencyAchievement(string name, string iconClass, decimal current, decimal[] targets, string[] tierTitles)
        {
            var tier = ResolveTier(current, targets);
            var nextTarget = targets.FirstOrDefault(x => x > current);

            return new AchievementItem
            {
                Name = name,
                IconClass = iconClass,
                Tier = tier,
                TierName = ResolveTierTitle(tier, tierTitles),
                Unlocked = tier > 0,
                CurrentText = $"当前：¥{current:N2}",
                NextLevelText = nextTarget > 0
                    ? $"下一等级：{ResolveTierTitle(tier + 1, tierTitles)}"
                    : "下一等级：已达最高等级",
                TargetText = nextTarget > 0
                    ? $"目标：¥{nextTarget:N0}"
                    : "目标：已达成最高档"
            };
        }

        private static int ResolveTier(int current, int[] targets)
        {
            var tier = 0;
            foreach (var target in targets)
            {
                if (current >= target)
                {
                    tier++;
                }
            }

            return tier;
        }

        private static int ResolveTier(decimal current, decimal[] targets)
        {
            var tier = 0;
            foreach (var target in targets)
            {
                if (current >= target)
                {
                    tier++;
                }
            }

            return tier;
        }

        private static string ResolveTierTitle(int tier, string[] tierTitles)
        {
            if (tier <= 0)
            {
                return "未点亮";
            }

            if (tier <= tierTitles.Length)
            {
                return tierTitles[tier - 1];
            }

            return tierTitles.Length == 0 ? "未点亮" : tierTitles[^1];
        }

        private static string ResolveExplorerLevel(decimal totalMileageKm)
        {
            if (totalMileageKm >= 20000)
            {
                return "钢轨征服者";
            }

            if (totalMileageKm >= 5000)
            {
                return "干线旅行家";
            }

            if (totalMileageKm >= 1000)
            {
                return "区域通勤者";
            }

            return "见习铁路迷";
        }

        private static decimal GetTripMileage(TripRecord trip)
        {
            if (trip.MileageKm > 0)
            {
                return trip.MileageKm;
            }

            var segmentMileage = (trip.ViaRouteSegments ?? []).Sum(x => x.MileageKm);
            return segmentMileage > 0 ? segmentMileage : 0m;
        }

        private static IEnumerable<string> ExtractRollingStockTypes(string? rollingStock)
        {
            if (string.IsNullOrWhiteSpace(rollingStock))
            {
                return [];
            }

            var results = new List<string>();
            var tokens = rollingStock.Split(['、', '，', ',', '/', ';', '；', '+', ' '], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

            foreach (var token in tokens)
            {
                var head = token.Split(['-', '(', '（', '#'], 2)[0];
                var normalized = new string(head.Where(char.IsLetterOrDigit).ToArray()).ToUpperInvariant();
                if (normalized.Any(char.IsLetter))
                {
                    results.Add(normalized);
                }
            }

            return results;
        }

        private static List<VisitRankItem> BuildTopVisitItems(IEnumerable<string> values, int top)
        {
            return values
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Select(x => x.Trim())
                .GroupBy(x => x, StringComparer.OrdinalIgnoreCase)
                .Select(g => new VisitRankItem(g.First(), g.Count()))
                .OrderByDescending(x => x.Count)
                .ThenBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
                .Take(top)
                .ToList();
        }

        private static IEnumerable<string> ExtractRouteVisitsForTrip(TripRecord trip)
        {
            var routeNames = (trip.ViaRouteSegments ?? [])
                .Select(x => x.RouteName?.Trim())
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Cast<string>()
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToList();

            if (routeNames.Count > 0)
            {
                return routeNames;
            }

            var from = trip.FromStation?.Trim();
            var to = trip.ToStation?.Trim();
            if (string.IsNullOrWhiteSpace(from) || string.IsNullOrWhiteSpace(to))
            {
                return [];
            }

            return [$"{from} -> {to}"];
        }

        private static IEnumerable<string> ExtractStationVisitsForTrip(TripRecord trip)
        {
            var stations = new List<string>();
            AddStation(stations, trip.FromStation);
            AddStation(stations, trip.ToStation);

            return stations.Distinct(StringComparer.OrdinalIgnoreCase);
        }

        private static void AddStation(List<string> stations, string? station)
        {
            if (!string.IsNullOrWhiteSpace(station))
            {
                stations.Add(station.Trim());
            }
        }
    }

    public sealed class DashboardStats
    {
        public static DashboardStats Empty { get; } = new();

        public int OverallTotalTrips { get; init; }

        public decimal OverallTotalMileageKm { get; init; }

        public int NonRailTrips { get; init; }

        public decimal NonRailMileageKm { get; init; }

        public int TotalTrips { get; init; }

        public decimal TotalSpend { get; init; }

        public decimal HighestFare { get; init; }

        public decimal TotalMileageKm { get; init; }

        public decimal LongestTripMileageKm { get; init; }

        public int UniqueRoutes { get; init; }

        public string RouteStatHint { get; init; } = "按经由线路去重";

        public int UniqueRollingStockTypes { get; init; }

        public int RollingStockRecords { get; init; }

        public int UniqueStations { get; init; }

        public List<VisitRankItem> TopRouteVisits { get; init; } = [];

        public List<VisitRankItem> TopStationVisits { get; init; } = [];

        public int UniqueTrainNumbers { get; init; }

        public int UniqueSeatTypes { get; init; }

        public DateOnly? FirstTripDate { get; init; }

        public DateOnly? LatestTripDate { get; init; }

        public string ExplorerLevel { get; init; } = "见习铁路迷";
    }

    public sealed class VisitRankItem
    {
        public VisitRankItem(string name, int count)
        {
            Name = name;
            Count = count;
        }

        public string Name { get; }

        public int Count { get; }
    }

    public sealed class AchievementItem
    {
        public string Name { get; init; } = string.Empty;

        public string IconClass { get; init; } = string.Empty;

        public int Tier { get; init; }

        public string TierName { get; init; } = string.Empty;

        public bool Unlocked { get; init; }

        public string CurrentText { get; init; } = string.Empty;

        public string NextLevelText { get; init; } = string.Empty;

        public string TargetText { get; init; } = string.Empty;
    }
}
