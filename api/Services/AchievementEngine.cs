using System.Text.Json;
using System.Text.RegularExpressions;
using RailLog.API.Models;

namespace RailLog.API.Services;

public sealed record AchievementEvaluation(
    string Id,
    string Category,
    string Icon,
    string Title,
    string Description,
    long? TriggerTripId)
{
    public AchievementProgress? Progress { get; init; }
}

public sealed record AchievementProgress(double Current, double Target);

public static partial class AchievementEngine
{
    private const string Milestones = "milestones";
    private const string ExtremeChallenges = "extremeChallenges";
    private const string RailwayCatalog = "railwayCatalog";
    private const string Touring = "touring";
    private const string FunJourneys = "funJourneys";

    private static readonly IReadOnlyDictionary<string, string> AchievementCategories =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["sevenDayStreak"] = Milestones,
            ["thirtyDayStreak"] = Milestones,
            ["hundredTickets"] = Milestones,
            ["hundredStations"] = Milestones,
            ["thousandKilometers"] = Milestones,
            ["hundredThousandKilometers"] = Milestones,
            ["archaeologyTeam"] = Milestones,
            ["tenNumericTrains"] = Milestones,

            ["tightTransfer"] = ExtremeChallenges,
            ["wellPreparedTransfer"] = ExtremeChallenges,
            ["tripleTransfer"] = ExtremeChallenges,
            ["duration24Hours"] = ExtremeChallenges,
            ["duration48Hours"] = ExtremeChallenges,
            ["duration72Hours"] = ExtremeChallenges,
            ["overnightSeat"] = ExtremeChallenges,
            ["midnightBoarding"] = ExtremeChallenges,
            ["noSeat12Hours"] = ExtremeChallenges,
            ["highSpeedExperiment"] = ExtremeChallenges,
            ["slowCrawl"] = ExtremeChallenges,
            ["slowerThanCycling"] = ExtremeChallenges,
            ["miniTurnaround"] = ExtremeChallenges,
            ["zeroDisplacement"] = ExtremeChallenges,
            ["youthPriceless"] = ExtremeChallenges,

            ["all25Series"] = RailwayCatalog,
            ["allEmuSeries"] = RailwayCatalog,
            ["allSeatTypes"] = RailwayCatalog,
            ["grandSlam"] = RailwayCatalog,
            ["completeTrainLetters"] = RailwayCatalog,
            ["ancientLetters"] = RailwayCatalog,
            ["fTrain"] = RailwayCatalog,
            ["spontaneousTrip"] = RailwayCatalog,
            ["railwayWorkerPassenger"] = RailwayCatalog,
            ["blueHorizon"] = RailwayCatalog,
            ["axleOverheat"] = RailwayCatalog,
            ["permanentMagnetPower"] = RailwayCatalog,
            ["dreamPath"] = RailwayCatalog,
            ["snowWelcomesSpring"] = RailwayCatalog,
            ["moistensJiangnan"] = RailwayCatalog,
            ["facingTheWorld"] = RailwayCatalog,
            ["revivalPrototype"] = RailwayCatalog,
            ["vibrantJourney"] = RailwayCatalog,
            ["railwayTrailblazer"] = RailwayCatalog,
            ["whatAgeIsThis"] = RailwayCatalog,

            ["verticalChina"] = Touring,
            ["horizontalChina"] = Touring,
            ["fourFamousNorths"] = Touring,
            ["cardinalStations"] = Touring,
            ["borderPorts"] = Touring,
            ["lonelyPlanet"] = Touring,
            ["airRail"] = Touring,
            ["railFerry"] = Touring,
            ["endsOfTheEarth"] = Touring,
            ["greatWallWatch"] = Touring,
            ["icyWorld"] = Touring,
            ["redFootprints"] = Touring,
            ["advantageIsMine"] = Touring,
            ["platformSubsidence"] = Touring,
            ["strategist"] = Touring,
            ["eastRedSunRises"] = Touring,
            ["centuryMeterGauge"] = Touring,

            ["freeMeal"] = FunJourneys,
            ["wallFacingSeat"] = FunJourneys,
            ["farsighted"] = RailwayCatalog,
            ["verticalSleeper"] = RailwayCatalog,
            ["overnightSleeper"] = FunJourneys,
            ["commuterSpecial"] = FunJourneys,
            ["eveOfTheStorm"] = FunJourneys,
            ["blessChina"] = FunJourneys,
            ["publicDisplayOfAffection"] = FunJourneys,
            ["multipleChoices"] = FunJourneys,
            ["unnecessaryExtra"] = FunJourneys,
            ["storedUpReward"] = FunJourneys,
            ["oneYuanJourney"] = FunJourneys,
            ["fleetingMoment"] = FunJourneys,
            ["newYearsEve"] = FunJourneys,
            ["monotonousTrainNumber"] = FunJourneys,
            ["modestAppetite"] = FunJourneys,
        };

    private static readonly HashSet<string> Regular25Models =
        ["25B", "25Z", "25G", "25K", "25T", "25DT"];
    private static readonly HashSet<string> EarlyEmuModels =
        ["X2000", "KDZ1A", "DJF1", "DJF2", "DJF3", "DJJ1", "DJJ2", "NZJ1", "NZJ2", "NDJ3", "NYJ1"];
    private static readonly HashSet<string> EarlyPassengerCoachModels =
        ["21", "22", "22A", "22B", "22C", "23", "24", "25", "25A", "25C", "31"];
    private static readonly HashSet<string> EmuModels =
    [
        "CRH1", "CRH2", "CRH3", "CRH5", "CRH6", "CR200J", "CR300AF",
        "CR300BF", "CR400AF", "CR400BF", "CJ6", "CRH380A", "CRH380B",
        "CRH380C", "CRH380D"
    ];
    private static readonly HashSet<string> RegularSeatTypes =
    [
        "无座", "硬座", "软座", "一等座", "优选一等座","特等座", "商务座", "硬卧", "软卧",
        "高级软卧", "动卧", "二等卧", "一等卧", "高级动卧"
    ];
    private static readonly HashSet<string> AirportStationsWithoutAirportSuffix = ["美兰", "龙洞堡", "上海虹桥"];
    private static readonly HashSet<string> VariableGaugeModels =
        ["CR400BF-0031", "CR400BF-G-0051", "CR400AF-G-0021"];
    private static readonly HashSet<string> PrototypeModels =
    [
        "CR400BF-0305", "CR400BF-0503", "CR400BF-0507", "CR400AF-0207",
        "CR400AF-0208", "CR300AF-0001", "CR300AF-0003", "CR300AF-0004",
        "CR300BF-0002", "CR300BF-0005", "CR300BF-0006"
    ];
    private static readonly HashSet<string> VibrantExpressModels = Enumerable.Range(251, 9)
        .SelectMany(number => new[] { $"CRH380A-0{number}", $"MTR380A-0{number}", "MTR380A" })
        .ToHashSet(StringComparer.Ordinal);
    private static readonly HashSet<string> CommonTrainCategories =
        ["G", "D", "C", "Z", "T", "K", "Y", "S", "numeric"];

    private static readonly IReadOnlyDictionary<string, HashSet<string>> RailwayBureaus =
        new Dictionary<string, HashSet<string>>(StringComparer.Ordinal)
        {
            ["哈尔滨局"] = ["哈局哈尔滨段", "哈局牡丹江段", "哈局齐齐哈尔段"],
            ["呼和浩特局"] = ["呼和局包头段", "集通公司呼和段"],
            ["郑州局"] = ["郑州局郑州段"],
            ["南昌局"] = ["南昌局南昌段", "南昌局福州段", "南昌局福龙客车公司"],
            ["上海局"] = ["上局上海段", "上局南京段", "上局杭州段", "上局合肥段", "合九公司", "金温公司"],
            ["兰州局"] = ["兰州局兰州段", "兰州局银川段"],
            ["济南局"] = ["济南局济南段", "济南局青岛段", "济南局威海地铁"],
            ["昆明局"] = ["昆明局昆明段", "昆明局万象段", "老中铁路公司"],
            ["武汉局"] = ["武汉局武汉段", "武汉局襄阳段"],
            ["青藏公司"] = ["青藏公司西宁段"],
            ["北京局"] = ["京局北京客运段", "京局天津客运段", "京局石家庄客运段", "北京局承德车务段"],
            ["广铁集团"] = ["广铁广九段", "广铁广州段", "广铁长沙段", "广东城际公司", "广州局海口车务段", "广州局长沙车辆段"],
            ["乌鲁木齐局"] = ["乌局乌鲁木齐段", "乌局库尔勒段"],
            ["沈阳局"] = ["沈局长春段", "沈局大连段", "沈局吉林段", "沈局锦州段", "沈局沈阳段"],
            ["太原局"] = ["太原局太原客运段"],
            ["成都局"] = ["成都局成都客运段", "成都局贵阳客运段", "成都局重庆客运段"],
            ["香港铁路公司"] = ["港铁公司"],
            ["西安局"] = ["西安局西安段"],
            ["南宁局"] = ["南宁局南宁客运段", "广西沿海铁路公司"]
        };

    public static IReadOnlyList<AchievementEvaluation> Evaluate(
        IEnumerable<PublicTrip> sourceTrips,
        DateTime? now = null)
    {
        var trips = sourceTrips
            .Where(trip => trip.IsRailTrip)
            .OrderBy(trip => trip.DepartureTime ?? trip.CreatedAt)
            .ThenBy(trip => trip.TicketId)
            .ToList();
        var today = (now ?? DateTime.Now).Date;
        var fifteenYearsAgo = new DateTime(today.Year - 15, 1, 1)
            .AddMonths(today.Month - 1)
            .AddDays(today.Day - 1);

        var values = new List<AchievementEvaluation>
        {
            A("freeMeal", "restaurant_outlined", "蹭吃蹭喝", "在用餐时段乘坐里程不超过 50 公里的商务座",
                First(trips, UnlocksFreeMeal)),
            A("overnightSeat", "airline_seat_recline_extra_outlined", "铁腚行", "乘坐硬座或二等座，完整度过 00:00 至 06:00",
                First(trips, UnlocksOvernightSeat)),
            A("tightTransfer", "transfer_within_a_station", "极限换乘", "完成同站换乘，换乘时间少于 10 分钟",
                FirstTightTransfer(trips)),
            A("wellPreparedTransfer", "schedule_outlined", "充分打算", "完成同站换乘，等待至少 6 小时但少于 12 小时",
                FirstWellPreparedTransfer(trips)),
            A("sevenDayStreak", "local_fire_department", "马不停蹄", "连续 7 天乘坐列车",
                FirstStreakCompletion(trips, 7)),
            A("thirtyDayStreak", "calendar_month_outlined", "漂泊不定", "连续 30 天乘坐列车",
                FirstStreakCompletion(trips, 30)),
            A("duration24Hours", "looks_one_outlined", "恍如昨日", "乘坐单程时长至少 24 小时的列车",
                First(trips, trip => ValidDuration(trip) >= TimeSpan.FromHours(24))),
            A("duration48Hours", "looks_two_outlined", "旦复旦兮", "乘坐单程时长至少 48 小时的列车",
                First(trips, trip => ValidDuration(trip) >= TimeSpan.FromHours(48))),
            A("duration72Hours", "looks_3_outlined", "舟车劳顿", "乘坐单程时长至少 72 小时的列车",
                First(trips, trip => ValidDuration(trip) >= TimeSpan.FromHours(72))),
            A("all25Series", "palette_outlined", "五彩斑斓", "分别乘坐全部常规 25 系列客车型号",
                FirstCollectionCompletion(trips, Regular25Models,
                    trip => RollingStockMatches(trip.RollingStock, Regular25Models))),
            A("allEmuSeries", "train_outlined", "琳琅满目", "分别乘坐全部常规和谐号、复兴号子型号",
                FirstCollectionCompletion(trips, EmuModels, trip => EmuMatches(trip.RollingStock))),
            A("allSeatTypes", "checklist_outlined", "我全都要", "分别乘坐全部常规席别",
                FirstCollectionCompletion(trips, RegularSeatTypes, trip => SeatTypeMatches(trip.SeatType))),
            A("noSeat12Hours", "accessibility_new", "体力非凡", "持无座车票乘坐至少 12 小时",
                First(trips, trip => NormalizedSeatType(trip.SeatType) == "无座" &&
                    ValidDuration(trip) >= TimeSpan.FromHours(12))),
            A("hundredTickets", "collections_bookmark_outlined", "日积月累", "累计留存至少 100 张本人车票",
                trips.Count >= 100 ? trips[99] : null),
            A("midnightBoarding", "nightlight_outlined", "夜半钟声", "在 00:00 至 05:00 乘车或下车",
                FirstMidnightBoarding(trips)),
            A("wallFacingSeat", "airline_seat_recline_normal", "面壁者", "乘坐车厢第 1 排或第 18 排的二等座",
                First(trips, UnlocksWallFacingSeat)),
            A("hundredStations", "location_on_outlined", "百站印记", "累计到访至少 100 座不同的客运车站",
                FirstStationCompletion(trips, 100)),
            A("thousandKilometers", "route_outlined", "千里足迹", "完成单程至少 1,000 公里的行程",
                First(trips, trip => trip.MileageKm >= 1000)),
            A("airRail", "connecting_airports_outlined", "空铁联运", "累计到访至少 3 座不同的国内机场铁路站",
                FirstAirportStationCompletion(trips, 3)),
            A("railFerry", "directions_boat_outlined", "铁水联运", "乘坐经由粤海轮渡线的列车，或在大连与烟台间完成 24 小时内的跨海接续",
                FirstRailFerryCompletion(trips)),
            A("railwayWorkerPassenger", "engineering_outlined", "待旅客如职工", "乘坐一次 57XXX 或 40XXX 路用列车",
                First(trips, trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^(?:57|40)\d{3}$"))),
            A("verticalChina", "swap_vert", "纵贯中国", "在 14 天内到访漠河站和三亚站",
                FirstStationPairWithin(trips, "漠河", "三亚", TimeSpan.FromDays(14))),
            A("horizontalChina", "swap_horiz", "横贯中国", "在 14 天内到访阿克陶站和抚远站",
                FirstStationPairWithin(trips, "阿克陶", "抚远", TimeSpan.FromDays(14))),
            A("eastRedSunRises", "wb_sunny_outlined", "东方红，太阳升", "到访东方红站和太阳升站",
                FirstStationPairCompletion(trips, "东方红", "太阳升")),
            A("highSpeedExperiment", "speed_outlined", "冲高实验", "完成时长超过 1 小时且均速超过 300 公里/小时的行程",
                First(trips, trip => ValidDuration(trip) > TimeSpan.FromHours(1) && AverageSpeed(trip) > 300)),
            A("slowCrawl", "slow_motion_video_outlined", "龟速爬行", "完成时长超过 1 小时且均速不超过 50 公里/小时的行程",
                First(trips, trip => ValidDuration(trip) > TimeSpan.FromHours(1) && AverageSpeed(trip) is > 0 and <= 50)),
            A("slowerThanCycling", "directions_bike_outlined", "不如骑车", "完成时长超过 1 小时且均速低于 30 公里/小时的行程",
                First(trips, trip => ValidDuration(trip) > TimeSpan.FromHours(1) && AverageSpeed(trip) is > 0 and < 30)),
            A("fleetingMoment", "flash_on_outlined", "转瞬即逝", "乘坐福田或深圳北与香港西九龙间的一等座、商务座或特等座",
                First(trips, UnlocksFleetingMoment)),
            A("borderPorts", "language_outlined", "异域风情", "到访阿拉山口、二连、满洲里、绥芬河、丹东、崇左或磨憨站",
                FirstStationVisit(trips, ["阿拉山口", "二连", "满洲里", "绥芬河", "丹东", "崇左", "磨憨"])),
            A("lonelyPlanet", "map_outlined", "孤独星球", "分别乘坐经由和若线与格库线的列车",
                FirstRouteCollectionCompletion(trips, ["和若线", "格库线"])),
            A("hundredThousandKilometers", "gps_fixed_outlined", "我就是GPS", "累计乘车里程至少 100,000 公里",
                FirstCumulativeMileageCompletion(trips, 100000)),
            A("fTrain", "u_turn_left_outlined", "中途遣返", "乘坐一次 F 字头列车",
                First(trips, trip => trip.TrainNumber.Trim().StartsWith("F", StringComparison.OrdinalIgnoreCase))),
            A("axleOverheat", "device_thermostat_outlined", "轴温过高", "乘坐一次 CR400BF-5033 型列车",
                FirstRollingStockMatch(trips, ["CR400BF-5033"])),
            A("permanentMagnetPower", "bolt_outlined", "永磁动力", "乘坐一次 CRH380AN 型列车",
                FirstRollingStockMatch(trips, ["CRH380AN"])),
            A("advantageIsMine", "flag_outlined", "优势在我", "到访徐州站或徐州东站",
                FirstStationVisit(trips, ["徐州", "徐州东"])),
            A("platformSubsidence", "vertical_align_bottom_outlined", "站台沉降", "到访杭州东站",
                FirstStationVisit(trips, ["杭州东"])),
            A("archaeologyTeam", "history_edu_outlined", "考古队", "录入至少 15 年前的行程",
                First(trips, trip => Departure(trip) <= fifteenYearsAgo)),
            A("strategist", "alt_route_outlined", "战略家", "乘坐定西北站至镇江南站的列车",
                First(trips, trip => NormalizedStation(trip.FromStation) == "定西北" &&
                    NormalizedStation(trip.ToStation) == "镇江南")),
            A("eveOfTheStorm", "thunderstorm_outlined", "风雨前夜", "在 2019-12-01 至 2020-01-23 到访武汉站、汉口站或武昌站",
                FirstStationVisitDuring(trips, ["武汉", "汉口", "武昌"],
                    new DateTime(2019, 12, 1), new DateTime(2020, 1, 24))),
            A("tenNumericTrains", "pin_outlined", "慢慢旅途", "累计乘坐至少 10 次纯数字车次",
                FirstCountCompletion(trips, 10, trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^\d+$"))),
            A("overnightSleeper", "bedtime_outlined", "夕发朝至", "乘坐 18:00 至 00:00 发车且 05:00 至 11:00 到达的卧铺列车",
                First(trips, UnlocksOvernightSleeper)),
            A("tripleTransfer", "multiple_stop_outlined", "辗转挪移", "连续换乘至少 3 次，每次换乘间隔不超过 3 小时",
                FirstTransferChainCompletion(trips, 3)),
            A("endsOfTheEarth", "landscape_outlined", "天涯海角", "到访天涯海角站",
                FirstStationVisit(trips, ["天涯海角"])),
            A("fourFamousNorths", "explore_outlined", "四大名北", "到访阳泉北站、盘锦北站、孝感北站或邵阳北站",
                FirstStationVisit(trips, ["阳泉北", "盘锦北", "孝感北", "邵阳北"])),
            A("youthPriceless", "airline_seat_recline_normal", "青春没有售价", "乘坐全程硬座列车到达拉萨站",
                First(trips, trip => NormalizedStation(trip.ToStation) == "拉萨" && NormalizedSeatType(trip.SeatType) == "硬座")),
            A("zeroDisplacement", "loop", "位移为零", "乘坐始发站与终到站相同的环线列车全程",
                First(trips, trip => NormalizedStation(trip.FromStation) == NormalizedStation(trip.ToStation))),
            A("dreamPath", "auto_awesome_outlined", "逐梦之路", "乘坐一次 25DT 型列车",
                FirstRollingStockMatch(trips, ["25DT"])),
            A("commuterSpecial", "work_outline", "牛马专列", "乘坐北京与上海间经由京沪高铁的一等座、优选一等座、商务座或特等座",
                First(trips, UnlocksCommuterSpecial)),
            A("grandSlam", "emoji_events_outlined", "大满贯", "分别乘坐全部铁路局担当的列车",
                FirstRailwayBureauCompletion(trips)),
            A("storedUpReward", "redeem_outlined", "厚积薄发", "使用积分兑换里程超过 50 公里的商务座或特等座车票",
                First(trips, UnlocksStoredUpReward)),
            A("spontaneousTrip", "luggage_outlined", "说走就走", "乘坐一次 Y 字头旅游列车",
                First(trips, trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^Y\s*\d", RegexOptions.IgnoreCase))),
            A("redFootprints", "directions_walk_outlined", "红色足迹", "乘坐韶山南站至延安站的列车",
                First(trips, trip => NormalizedStation(trip.FromStation) == "韶山南" && NormalizedStation(trip.ToStation) == "延安")),
            A("greatWallWatch", "account_balance_outlined", "长城守望", "到访八达岭站或八达岭长城站",
                FirstStationVisit(trips, ["八达岭", "八达岭长城"])),
            A("icyWorld", "ac_unit_outlined", "冰天雪地", "在 12 月、1 月或 2 月到访根河站",
                First(trips, UnlocksIcyWorld)),
            A("unnecessaryExtra", "filter_3_outlined", "多此一举", "至少分 3 张车票接续乘坐同一列车",
                FirstThreeTicketSameTrainCompletion(trips)),
            A("blessChina", "flag_outlined", "祝福祖国", "在 10 月 1 日乘坐列车",
                First(trips, trip => Departure(trip).Month == 10 && Departure(trip).Day == 1)),
            A("newYearsEve", "celebration_outlined", "跨年夜", "在列车上完成跨年",
                First(trips, UnlocksNewYearsEve)),
            A("monotonousTrainNumber", "format_list_numbered_outlined", "千篇一律", "乘坐数字部分为三或四个相同数字的车次",
                First(trips, UnlocksMonotonousTrainNumber)),
            A("snowWelcomesSpring", "ac_unit_outlined", "瑞雪迎春", "乘坐一次北京冬奥会限定车型 CR400BF-C-5162",
                FirstRollingStockMatch(trips, ["CR400BF-C-5162"])),
            A("moistensJiangnan", "water_drop_outlined", "润泽江南", "乘坐一次杭州亚运会限定车型 CR400BF-Z-0524",
                FirstRollingStockMatch(trips, ["CR400BF-Z-0524"])),
            A("facingTheWorld", "public_outlined", "面向世界", "乘坐一次 CR400 系列可变轨距列车",
                FirstRollingStockMatch(trips, VariableGaugeModels)),
            A("revivalPrototype", "precision_manufacturing_outlined", "复兴之路", "乘坐一次 CR400 或 CR300 原样车",
                FirstRollingStockMatch(trips, PrototypeModels)),
            A("vibrantJourney", "directions_railway_outlined", "动感之旅", "乘坐一次港铁动感号列车",
                FirstRollingStockMatch(trips, VibrantExpressModels)),
            A("multipleChoices", "format_list_numbered_outlined", "多重选择", "在同一乘车区间累计乘坐至少 10 个不同车次",
                FirstDistinctTrainCountForRoute(trips, 10)),
            A("publicDisplayOfAffection", "favorite_outline", "秀恩爱", "在 5 月 20 日乘坐重联动车组列车",
                First(trips, trip => Departure(trip).Month == 5 && Departure(trip).Day == 20 &&
                    (trip.RollingStock?.Contains('&') ?? false))),
            A("farsighted", "visibility_outlined", "高瞻远瞩", "乘坐双层车厢的上层席位",
                First(trips, trip => trip.SeatNumber is not null && Regex.IsMatch(trip.SeatNumber, @"上(?!铺)"))),
            A("oneYuanJourney", "currency_yen", "一元旅程", "单次行程票价为 1 元",
                First(trips, trip => trip.Price == 1)),
            A("cardinalStations", "explore_outlined", "东西南北", "到访过一个城市的东西南北中五个车站",
                FirstCardinalStationCompletion(trips)),
            A("ancientLetters", "history_edu_outlined", "远古字母", "乘坐过以 A、N 或 L 开头的列车",
                First(trips, trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^[ANL]\s*\d", RegexOptions.IgnoreCase))),
            A("miniTurnaround", "timer_outlined", "迷你运转", "单次旅程时间在 10 分钟以内",
                First(trips, trip => trip.ArrivalTime is not null && trip.ArrivalTime >= Departure(trip) &&
                    trip.ArrivalTime - Departure(trip) <= TimeSpan.FromMinutes(10))),
            A("verticalSleeper", "train_outlined", "纵向动卧", "乘坐过 CRH2E 纵向动卧列车",
                First(trips, UnlocksVerticalSleeper)),
            A("completeTrainLetters", "format_list_numbered_outlined", "车次大全", "常见车次字母都坐过至少一次",
                FirstCollectionCompletion(trips, CommonTrainCategories, trip =>
                {
                    var category = CommonTrainCategory(trip.TrainNumber);
                    return category is null ? [] : [category];
                })),
            A("blueHorizon", "water_drop_outlined", "一碧千里", "至少坐过 10 次动集列车",
                FirstCountCompletion(trips, 10, trip => ContainsRollingStock(trip, "CR200J"))),
            A("railwayTrailblazer", "train_outlined", "开路先锋", "乘坐一次早期动车组列车（不含后期编入普通列车的 25DT）",
                FirstRollingStockMatch(trips, EarlyEmuModels)),
            A("modestAppetite", "route_outlined", "腹犹果然", "完成单程不超过 20 公里的行程",
                First(trips, trip => trip.MileageKm <= 20)),
            A("whatAgeIsThis", "history_edu_outlined", "今乃何世", "乘坐一次 25C 型或更早上线的客车",
                FirstRollingStockMatch(trips, EarlyPassengerCoachModels)),
            A("centuryMeterGauge", "map_outlined", "百年米轨", "乘坐经由昆河线的列车",
                First(trips, trip => RouteNames(trip).Any(
                    route => route.Contains("昆河线", StringComparison.Ordinal))))
        };

        if (values.Count != AchievementCategories.Count ||
            values.Select(item => item.Id).Distinct(StringComparer.Ordinal).Count() != values.Count)
            throw new InvalidOperationException("Achievement category mapping is incomplete or contains duplicate IDs.");

        return values
            .Select(item => item with { Progress = ProgressFor(item.Id, trips, today, fifteenYearsAgo) })
            .OrderByDescending(item => item.TriggerTripId.HasValue)
            .ToList();
    }

    private static AchievementProgress? ProgressFor(
        string id,
        List<PublicTrip> trips,
        DateTime today,
        DateTime fifteenYearsAgo) => id switch
    {
        "sevenDayStreak" => P(LongestStreak(trips), 7),
        "thirtyDayStreak" => P(LongestStreak(trips), 30),
        "duration24Hours" => P(MaxDurationHours(trips), 24),
        "duration48Hours" => P(MaxDurationHours(trips), 48),
        "duration72Hours" => P(MaxDurationHours(trips), 72),
        "all25Series" => P(CollectedCount(trips, trip => RollingStockMatches(trip.RollingStock, Regular25Models)), Regular25Models.Count),
        "allEmuSeries" => P(CollectedCount(trips, trip => EmuMatches(trip.RollingStock)), EmuModels.Count),
        "allSeatTypes" => P(CollectedCount(trips, trip => SeatTypeMatches(trip.SeatType)), RegularSeatTypes.Count),
        "noSeat12Hours" => P(MaxDurationHours(trips.Where(trip => NormalizedSeatType(trip.SeatType) == "无座")), 12),
        "hundredTickets" => P(trips.Count, 100),
        "hundredStations" => P(trips.SelectMany(trip => new[] { trip.FromStation.Trim(), trip.ToStation.Trim() }).Where(value => value.Length > 0).Distinct(StringComparer.Ordinal).Count(), 100),
        "thousandKilometers" => P(trips.Select(trip => trip.MileageKm).DefaultIfEmpty(0).Max(), 1000),
        "airRail" => P(AirportStationCount(trips), 3),
        "lonelyPlanet" => P(CollectedCount(trips, trip => new[] { "和若线", "格库线" }.Where(route => RouteNames(trip).Any(name => name.Contains(route, StringComparison.Ordinal)))), 2),
        "hundredThousandKilometers" => P(trips.Where(trip => trip.MileageKm > 0).Sum(trip => trip.MileageKm), 100000),
        "archaeologyTeam" => P(OldestTripAgeYears(trips, today, fifteenYearsAgo), 15),
        "tenNumericTrains" => P(trips.Count(trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^\d+$")), 10),
        "tripleTransfer" => P(MaxTransferCount(trips), 3),
        "grandSlam" => P(RailwayBureauCount(trips), RailwayBureaus.Count),
        "unnecessaryExtra" => P(MaxSameTrainTicketChain(trips), 3),
        "multipleChoices" => P(MaxDistinctTrainCountForRoute(trips), 10),
        "cardinalStations" => P(MaxCardinalStationCount(trips), 5),
        "eastRedSunRises" => P(VisitedStationCount(trips, ["东方红", "太阳升"]), 2),
        "completeTrainLetters" => P(trips.Select(trip => CommonTrainCategory(trip.TrainNumber)).Where(value => value is not null).Distinct(StringComparer.Ordinal).Count(), CommonTrainCategories.Count),
        "blueHorizon" => P(trips.Count(trip => ContainsRollingStock(trip, "CR200J")), 10),
        _ => null
    };

    private static AchievementProgress P(double current, double target) =>
        new(Math.Clamp(current, 0, target), target);

    private static double MaxDurationHours(IEnumerable<PublicTrip> trips) => trips
        .Select(trip => ValidDuration(trip).TotalHours)
        .DefaultIfEmpty(0)
        .Max();

    private static double OldestTripAgeYears(
        IEnumerable<PublicTrip> trips,
        DateTime today,
        DateTime fifteenYearsAgo)
    {
        var oldest = trips.Select(Departure).Select(value => value.Date).DefaultIfEmpty(today).Min();
        var targetDays = (today - fifteenYearsAgo).TotalDays;
        return targetDays <= 0 ? 0 : (today - oldest).TotalDays * 15 / targetDays;
    }

    private static int CollectedCount(
        IEnumerable<PublicTrip> trips,
        Func<PublicTrip, IEnumerable<string>> valuesForTrip) =>
        trips.SelectMany(valuesForTrip).Distinct(StringComparer.Ordinal).Count();

    private static int VisitedStationCount(
        IEnumerable<PublicTrip> trips,
        IEnumerable<string> targets)
    {
        var stations = targets.Select(NormalizedStation).ToHashSet(StringComparer.Ordinal);
        return trips
            .SelectMany(trip => new[] { trip.FromStation, trip.ToStation })
            .Select(NormalizedStation)
            .Where(stations.Contains)
            .Distinct(StringComparer.Ordinal)
            .Count();
    }

    private static int LongestStreak(IEnumerable<PublicTrip> trips)
    {
        var longest = 0;
        var streak = 0;
        DateTime? previous = null;
        foreach (var day in trips.Select(Departure).Select(value => value.Date).Distinct().Order())
        {
            streak = previous is not null && (day - previous.Value).Days == 1 ? streak + 1 : 1;
            longest = Math.Max(longest, streak);
            previous = day;
        }
        return longest;
    }

    private static int AirportStationCount(IEnumerable<PublicTrip> trips) => trips
        .SelectMany(trip => new[] { trip.FromStation, trip.ToStation })
        .Select(station => Regex.Replace(station.Trim(), "站$", string.Empty))
        .Where(station => station.Contains("机场", StringComparison.Ordinal) || AirportStationsWithoutAirportSuffix.Contains(station))
        .Distinct(StringComparer.Ordinal)
        .Count();

    private static int RailwayBureauCount(IEnumerable<PublicTrip> trips) => trips
        .Select(trip => RailwayBureaus.FirstOrDefault(entry => entry.Value.Contains(trip.CompanyName?.Trim() ?? string.Empty)).Key)
        .Where(value => value is not null)
        .Distinct(StringComparer.Ordinal)
        .Count();

    private static int MaxDistinctTrainCountForRoute(IEnumerable<PublicTrip> trips) => trips
        .Where(trip => NormalizedStation(trip.FromStation).Length > 0 && NormalizedStation(trip.ToStation).Length > 0)
        .GroupBy(trip => (NormalizedStation(trip.FromStation), NormalizedStation(trip.ToStation)))
        .Select(group => group.Select(trip => WhitespaceRegex().Replace(trip.TrainNumber, string.Empty).ToUpperInvariant())
            .Where(train => train.Length > 0).Distinct(StringComparer.Ordinal).Count())
        .DefaultIfEmpty(0)
        .Max();

    private static int MaxTransferCount(List<PublicTrip> trips)
    {
        var transferCounts = new int[trips.Count];
        for (var outgoingIndex = 0; outgoingIndex < trips.Count; outgoingIndex++)
        {
            var outgoing = trips[outgoingIndex];
            var station = NormalizedStation(outgoing.FromStation);
            if (station.Length == 0) continue;
            for (var incomingIndex = 0; incomingIndex < outgoingIndex; incomingIndex++)
            {
                var incoming = trips[incomingIndex];
                if (incoming.ArrivalTime is null || NormalizedStation(incoming.ToStation) != station) continue;
                var transfer = Departure(outgoing) - incoming.ArrivalTime.Value;
                if (transfer >= TimeSpan.Zero && transfer <= TimeSpan.FromHours(3))
                    transferCounts[outgoingIndex] = Math.Max(transferCounts[outgoingIndex], transferCounts[incomingIndex] + 1);
            }
        }
        return transferCounts.DefaultIfEmpty(0).Max();
    }

    private static int MaxSameTrainTicketChain(List<PublicTrip> trips)
    {
        var chainLengths = Enumerable.Repeat(1, trips.Count).ToArray();
        for (var currentIndex = 0; currentIndex < trips.Count; currentIndex++)
        {
            var current = trips[currentIndex];
            var train = current.TrainNumber.Trim().ToUpperInvariant();
            var from = NormalizedStation(current.FromStation);
            if (train.Length == 0 || from.Length == 0) continue;
            for (var previousIndex = 0; previousIndex < currentIndex; previousIndex++)
            {
                var previous = trips[previousIndex];
                if (previous.ArrivalTime is null || previous.TrainNumber.Trim().ToUpperInvariant() != train ||
                    NormalizedStation(previous.ToStation) != from || Departure(current) < previous.ArrivalTime) continue;
                chainLengths[currentIndex] = Math.Max(chainLengths[currentIndex], chainLengths[previousIndex] + 1);
            }
        }
        return trips.Count == 0 ? 0 : chainLengths.Max();
    }

    private static int MaxCardinalStationCount(IEnumerable<PublicTrip> trips)
    {
        var visited = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        foreach (var station in trips.SelectMany(trip => new[] { trip.FromStation, trip.ToStation }))
        {
            var normalized = NormalizedStation(station);
            if (normalized.Length == 0) continue;
            var match = Regex.Match(normalized, @"^(.+)(东|西|南|北)$");
            var city = match.Success ? match.Groups[1].Value : normalized;
            var direction = match.Success ? match.Groups[2].Value : string.Empty;
            if (!visited.TryGetValue(city, out var directions))
            {
                directions = new HashSet<string>(StringComparer.Ordinal);
                visited[city] = directions;
            }
            directions.Add(direction);
        }
        return visited.Values.Select(directions => directions.Count).DefaultIfEmpty(0).Max();
    }

    private static AchievementEvaluation A(
        string id, string icon, string title, string description, PublicTrip? trip)
    {
        if (!AchievementCategories.TryGetValue(id, out var category))
            throw new InvalidOperationException($"Achievement {id} has no category.");
        return new(id, category, icon, title, description, trip?.TicketId);
    }

    private static DateTime Departure(PublicTrip trip) => trip.DepartureTime ?? trip.CreatedAt;

    private static PublicTrip? First(IEnumerable<PublicTrip> trips, Func<PublicTrip, bool> predicate) =>
        trips.FirstOrDefault(predicate);

    private static PublicTrip? FirstCountCompletion(
        IEnumerable<PublicTrip> trips, int target, Func<PublicTrip, bool> predicate)
    {
        var count = 0;
        foreach (var trip in trips)
        {
            if (!predicate(trip)) continue;
            count++;
            if (count >= target) return trip;
        }
        return null;
    }

    private static PublicTrip? FirstStreakCompletion(List<PublicTrip> trips, int targetDays)
    {
        var firstTripByDay = new Dictionary<DateTime, PublicTrip>();
        foreach (var trip in trips) firstTripByDay.TryAdd(Departure(trip).Date, trip);
        var streak = 0;
        DateTime? previous = null;
        foreach (var day in firstTripByDay.Keys.Order())
        {
            streak = previous is not null && (day - previous.Value).Days == 1 ? streak + 1 : 1;
            if (streak >= targetDays) return firstTripByDay[day];
            previous = day;
        }
        return null;
    }

    private static PublicTrip? FirstCollectionCompletion(
        IEnumerable<PublicTrip> trips,
        IReadOnlySet<string> required,
        Func<PublicTrip, HashSet<string>> valuesForTrip)
    {
        var collected = new HashSet<string>(StringComparer.Ordinal);
        foreach (var trip in trips)
        {
            collected.UnionWith(valuesForTrip(trip));
            if (required.IsSubsetOf(collected)) return trip;
        }
        return null;
    }

    private static HashSet<string> RollingStockMatches(string? value, IEnumerable<string> models)
    {
        var normalized = value?.Trim().ToUpperInvariant() ?? string.Empty;
        return models.Where(model => Regex.IsMatch(
                normalized, $"^{Regex.Escape(model)}(?![A-Z0-9])"))
            .ToHashSet(StringComparer.Ordinal);
    }

    private static PublicTrip? FirstRollingStockMatch(List<PublicTrip> trips, IEnumerable<string> models)
    {
        var values = models.ToHashSet(StringComparer.Ordinal);
        return First(trips, trip => RollingStockMatches(trip.RollingStock, values).Count > 0);
    }

    private static bool ContainsRollingStock(PublicTrip trip, string value) =>
        trip.RollingStock?.Contains(value, StringComparison.OrdinalIgnoreCase) ?? false;

    private static PublicTrip? FirstDistinctTrainCountForRoute(List<PublicTrip> trips, int target)
    {
        var trainsByRoute = new Dictionary<(string From, string To), HashSet<string>>();
        foreach (var trip in trips)
        {
            var from = NormalizedStation(trip.FromStation);
            var to = NormalizedStation(trip.ToStation);
            var train = WhitespaceRegex().Replace(trip.TrainNumber, string.Empty).ToUpperInvariant();
            if (from.Length == 0 || to.Length == 0 || train.Length == 0) continue;
            var key = (from, to);
            if (!trainsByRoute.TryGetValue(key, out var trains))
            {
                trains = new HashSet<string>(StringComparer.Ordinal);
                trainsByRoute[key] = trains;
            }
            trains.Add(train);
            if (trains.Count >= target) return trip;
        }
        return null;
    }

    private static HashSet<string> EmuMatches(string? value)
    {
        var normalized = value?.Trim().ToUpperInvariant() ?? string.Empty;
        var result = new HashSet<string>(StringComparer.Ordinal);
        foreach (var model in EmuModels)
        {
            var pattern = model is "CRH1" or "CRH2" or "CRH3" or "CRH5" or "CRH6"
                ? $"^{model}(?![0-9])"
                : $"^{model}";
            if (Regex.IsMatch(normalized, pattern)) result.Add(model);
        }
        return result;
    }

    private static HashSet<string> SeatTypeMatches(string? value)
    {
        var normalized = NormalizedSeatType(value);
        return RegularSeatTypes.Where(seat => seat == normalized).ToHashSet(StringComparer.Ordinal);
    }

    private static string NormalizedSeatType(string? value) =>
        Regex.Replace(value?.Trim() ?? string.Empty, "[上中下]铺$", string.Empty);

    private static PublicTrip? FirstMidnightBoarding(List<PublicTrip> trips)
    {
        PublicTrip? result = null;
        DateTime? eventTime = null;
        foreach (var trip in trips)
        {
            foreach (var value in new DateTime?[] { Departure(trip), trip.ArrivalTime })
            {
                if (value is null || !(value.Value.Hour < 5 || value.Value is { Hour: 5, Minute: 0 })) continue;
                if (eventTime is null || value < eventTime)
                {
                    eventTime = value;
                    result = trip;
                }
            }
        }
        return result;
    }

    private static bool UnlocksWallFacingSeat(PublicTrip trip)
    {
        if (NormalizedSeatType(trip.SeatType) != "二等座") return false;
        var seat = (trip.SeatNumber ?? string.Empty).Replace(" ", string.Empty).ToUpperInvariant();
        return Regex.IsMatch(seat, @"车(?:1|18)[A-Z]?号");
    }

    private static PublicTrip? FirstStationCompletion(List<PublicTrip> trips, int target)
    {
        var stations = new HashSet<string>(StringComparer.Ordinal);
        foreach (var trip in trips)
        {
            AddStation(stations, trip.FromStation);
            AddStation(stations, trip.ToStation);
            if (stations.Count >= target) return trip;
        }
        return null;
    }

    private static PublicTrip? FirstStationVisit(List<PublicTrip> trips, IEnumerable<string> targets)
    {
        var values = targets.ToHashSet(StringComparer.Ordinal);
        return First(trips, trip => values.Contains(NormalizedStation(trip.FromStation)) ||
            values.Contains(NormalizedStation(trip.ToStation)));
    }

    private static PublicTrip? FirstStationPairWithin(
        List<PublicTrip> trips, string first, string second, TimeSpan maxWindow)
    {
        var targets = new HashSet<string>([NormalizedStation(first), NormalizedStation(second)], StringComparer.Ordinal);
        var latest = new Dictionary<string, StationVisit>(StringComparer.Ordinal);
        foreach (var visit in StationVisits(trips))
        {
            if (!targets.Contains(visit.Station)) continue;
            latest[visit.Station] = visit;
            var other = targets.First(station => station != visit.Station);
            if (latest.TryGetValue(other, out var otherVisit) && visit.Time - otherVisit.Time <= maxWindow)
                return visit.Trip;
        }
        return null;
    }

    private static PublicTrip? FirstStationPairCompletion(
        List<PublicTrip> trips, string first, string second)
    {
        var targets = new HashSet<string>([NormalizedStation(first), NormalizedStation(second)], StringComparer.Ordinal);
        var visited = new HashSet<string>(StringComparer.Ordinal);
        foreach (var visit in StationVisits(trips))
        {
            if (!targets.Contains(visit.Station)) continue;
            visited.Add(visit.Station);
            if (targets.IsSubsetOf(visited)) return visit.Trip;
        }
        return null;
    }

    private static List<StationVisit> StationVisits(List<PublicTrip> trips)
    {
        var visits = new List<StationVisit>();
        foreach (var trip in trips)
        {
            visits.Add(new StationVisit(NormalizedStation(trip.FromStation), Departure(trip), trip));
            visits.Add(new StationVisit(NormalizedStation(trip.ToStation), trip.ArrivalTime ?? Departure(trip), trip));
        }
        return visits.OrderBy(visit => visit.Time).ThenBy(visit => visit.Trip.TicketId).ToList();
    }

    private static PublicTrip? FirstStationVisitDuring(
        List<PublicTrip> trips, IEnumerable<string> targets, DateTime start, DateTime end)
    {
        var values = targets.ToHashSet(StringComparer.Ordinal);
        return First(trips, trip =>
            (Departure(trip) >= start && Departure(trip) < end && values.Contains(NormalizedStation(trip.FromStation))) ||
            ((trip.ArrivalTime ?? Departure(trip)) >= start && (trip.ArrivalTime ?? Departure(trip)) < end &&
                values.Contains(NormalizedStation(trip.ToStation))));
    }

    private static PublicTrip? FirstCumulativeMileageCompletion(List<PublicTrip> trips, double target)
    {
        var mileage = 0d;
        foreach (var trip in trips)
        {
            if (trip.MileageKm > 0) mileage += trip.MileageKm;
            if (mileage >= target) return trip;
        }
        return null;
    }

    private static PublicTrip? FirstCardinalStationCompletion(List<PublicTrip> trips)
    {
        var directions = new HashSet<string>(["东", "西", "南", "北", ""], StringComparer.Ordinal);
        var visited = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
        foreach (var trip in trips)
        {
            foreach (var station in new[] { trip.FromStation, trip.ToStation })
            {
                var normalized = NormalizedStation(station);
                if (normalized.Length == 0) continue;
                var match = Regex.Match(normalized, @"^(.+)(东|西|南|北)$");
                var city = match.Success ? match.Groups[1].Value : normalized;
                var direction = match.Success ? match.Groups[2].Value : string.Empty;
                if (!visited.TryGetValue(city, out var cityDirections))
                {
                    cityDirections = new HashSet<string>(StringComparer.Ordinal);
                    visited[city] = cityDirections;
                }
                cityDirections.Add(direction);
                if (directions.IsSubsetOf(cityDirections)) return trip;
            }
        }
        return null;
    }

    private static bool UnlocksVerticalSleeper(PublicTrip trip)
    {
        var stock = trip.RollingStock?.Trim().ToUpperInvariant() ?? string.Empty;
        if (!stock.Contains("CRH2E", StringComparison.Ordinal)) return false;
        var serialInStock = Regex.IsMatch(stock, @"CRH2E\s*[- ]?\s*(2463|2464|2465)(?!\d)");
        var train = WhitespaceRegex().Replace(trip.TrainNumber.Trim(), string.Empty);
        return serialInStock || train is "2463" or "2464" or "2465";
    }

    private static string? CommonTrainCategory(string value)
    {
        var train = value.Trim().ToUpperInvariant();
        if (Regex.IsMatch(train, @"^\d+$")) return "numeric";
        var match = Regex.Match(train, @"^([GDCZTKYS])\s*\d");
        return match.Success ? match.Groups[1].Value : null;
    }

    private static PublicTrip? FirstRouteCollectionCompletion(List<PublicTrip> trips, IEnumerable<string> routes)
    {
        var required = routes.ToHashSet(StringComparer.Ordinal);
        return FirstCollectionCompletion(trips, required, trip => required
            .Where(route => RouteNames(trip).Any(name => name.Contains(route, StringComparison.Ordinal)))
            .ToHashSet(StringComparer.Ordinal));
    }

    private static PublicTrip? FirstRailFerryCompletion(List<PublicTrip> trips)
    {
        for (var currentIndex = 0; currentIndex < trips.Count; currentIndex++)
        {
            var current = trips[currentIndex];
            if (RouteNames(current).Any(route => route.Contains("粤海轮渡线", StringComparison.Ordinal))) return current;
            var departure = NormalizedStation(current.FromStation);
            if (!departure.Contains("大连", StringComparison.Ordinal) && !departure.Contains("烟台", StringComparison.Ordinal)) continue;
            var requiredArrival = departure.Contains("大连", StringComparison.Ordinal) ? "烟台" : "大连";
            for (var previousIndex = 0; previousIndex < currentIndex; previousIndex++)
            {
                var previous = trips[previousIndex];
                if (previous.ArrivalTime is null ||
                    !NormalizedStation(previous.ToStation).Contains(requiredArrival, StringComparison.Ordinal)) continue;
                var connection = Departure(current) - previous.ArrivalTime.Value;
                if (connection >= TimeSpan.Zero && connection <= TimeSpan.FromHours(24)) return current;
            }
        }
        return null;
    }

    private static PublicTrip? FirstAirportStationCompletion(List<PublicTrip> trips, int target)
    {
        var stations = new HashSet<string>(StringComparer.Ordinal);
        foreach (var trip in trips)
        {
            foreach (var station in new[] { trip.FromStation, trip.ToStation })
            {
                var normalized = Regex.Replace(station.Trim(), "站$", string.Empty);
                if (normalized.Contains("机场", StringComparison.Ordinal) || AirportStationsWithoutAirportSuffix.Contains(normalized))
                    stations.Add(normalized);
            }
            if (stations.Count >= target) return trip;
        }
        return null;
    }

    private static void AddStation(HashSet<string> stations, string value)
    {
        var station = value.Trim();
        if (station.Length > 0) stations.Add(station);
    }

    private static string NormalizedStation(string value) => Regex.Replace(value.Trim(), "站$", string.Empty);

    private static TimeSpan ValidDuration(PublicTrip trip) =>
        trip.ArrivalTime is not null && trip.ArrivalTime >= Departure(trip)
            ? trip.ArrivalTime.Value - Departure(trip)
            : TimeSpan.Zero;

    private static double? AverageSpeed(PublicTrip trip)
    {
        var duration = ValidDuration(trip);
        return duration > TimeSpan.Zero && trip.MileageKm > 0
            ? trip.MileageKm / duration.TotalHours
            : null;
    }

    private static bool UnlocksFreeMeal(PublicTrip trip)
    {
        if (NormalizedSeatType(trip.SeatType) != "商务座" || trip.MileageKm <= 0 || trip.MileageKm > 50) return false;
        var departure = Departure(trip);
        var minutes = departure.Hour * 60 + departure.Minute;
        return minutes is >= 660 and < 780 or >= 1020 and < 1140;
    }

    private static bool UnlocksOvernightSeat(PublicTrip trip)
    {
        var seat = NormalizedSeatType(trip.SeatType);
        if (seat is not ("硬座" or "二等座") || trip.ArrivalTime is null || trip.ArrivalTime < Departure(trip)) return false;
        for (var day = Departure(trip).Date; day <= trip.ArrivalTime.Value.Date; day = day.AddDays(1))
        {
            var windowEnd = day.AddHours(6);
            if (Departure(trip) <= day && trip.ArrivalTime >= windowEnd) return true;
        }
        return false;
    }

    private static bool UnlocksOvernightSleeper(PublicTrip trip)
    {
        if (trip.ArrivalTime is null || trip.ArrivalTime < Departure(trip) ||
            !NormalizedSeatType(trip.SeatType).Contains("卧", StringComparison.Ordinal)) return false;
        var departureMinutes = Departure(trip).Hour * 60 + Departure(trip).Minute;
        var arrivalMinutes = trip.ArrivalTime.Value.Hour * 60 + trip.ArrivalTime.Value.Minute;
        return departureMinutes >= 1080 && arrivalMinutes is >= 300 and <= 660;
    }

    private static bool UnlocksFleetingMoment(PublicTrip trip)
    {
        if (NormalizedSeatType(trip.SeatType) is not ("一等座" or "商务座" or "特等座")) return false;
        var from = NormalizedStation(trip.FromStation);
        var to = NormalizedStation(trip.ToStation);
        return ((from is "福田" or "深圳北") && to == "香港西九龙") ||
            (from == "香港西九龙" && to is "福田" or "深圳北");
    }

    private static bool UnlocksCommuterSpecial(PublicTrip trip)
    {
        if (NormalizedSeatType(trip.SeatType) is not ("优选一等座" or "一等座" or "商务座" or "特等座")) return false;
        var from = NormalizedStation(trip.FromStation);
        var to = NormalizedStation(trip.ToStation);
        return ((from is "北京" or "北京南") && to is "上海虹桥" or "上海") ||
            ((from is "上海虹桥" or "上海") && to is "北京" or "北京南");
    }

    private static PublicTrip? FirstRailwayBureauCompletion(List<PublicTrip> trips) =>
        FirstCollectionCompletion(trips, RailwayBureaus.Keys.ToHashSet(StringComparer.Ordinal), trip =>
        {
            var company = trip.CompanyName?.Trim() ?? string.Empty;
            var bureau = RailwayBureaus.FirstOrDefault(entry => entry.Value.Contains(company)).Key;
            return bureau is null ? [] : [bureau];
        });

    private static bool UnlocksStoredUpReward(PublicTrip trip) =>
        trip.Price == 0 && trip.MileageKm > 50 && NormalizedSeatType(trip.SeatType) is "商务座" or "特等座";

    private static bool UnlocksIcyWorld(PublicTrip trip)
    {
        if (NormalizedStation(trip.FromStation) == "根河" && Departure(trip).Month is 12 or 1 or 2) return true;
        var arrival = trip.ArrivalTime ?? Departure(trip);
        return NormalizedStation(trip.ToStation) == "根河" && arrival.Month is 12 or 1 or 2;
    }

    private static bool UnlocksNewYearsEve(PublicTrip trip)
    {
        if (trip.ArrivalTime is null || trip.ArrivalTime < Departure(trip)) return false;
        var departure = Departure(trip);
        return trip.ArrivalTime.Value.Year > departure.Year;
    }

    private static bool UnlocksMonotonousTrainNumber(PublicTrip trip)
    {
        var digits = Regex.Replace(trip.TrainNumber ?? string.Empty, "[A-Za-z]", string.Empty)
            .Replace(" ", string.Empty);
        return Regex.IsMatch(digits, @"^(\d)\1{2,3}$");
    }

    private static PublicTrip? FirstThreeTicketSameTrainCompletion(List<PublicTrip> trips)
    {
        var chainLengths = Enumerable.Repeat(1, trips.Count).ToArray();
        for (var currentIndex = 0; currentIndex < trips.Count; currentIndex++)
        {
            var current = trips[currentIndex];
            var train = current.TrainNumber.Trim().ToUpperInvariant();
            var from = NormalizedStation(current.FromStation);
            if (train.Length == 0 || from.Length == 0) continue;
            for (var previousIndex = 0; previousIndex < currentIndex; previousIndex++)
            {
                var previous = trips[previousIndex];
                if (previous.ArrivalTime is null || previous.TrainNumber.Trim().ToUpperInvariant() != train ||
                    NormalizedStation(previous.ToStation) != from || Departure(current) < previous.ArrivalTime) continue;
                chainLengths[currentIndex] = Math.Max(chainLengths[currentIndex], chainLengths[previousIndex] + 1);
            }
            if (chainLengths[currentIndex] >= 3) return current;
        }
        return null;
    }

    private static PublicTrip? FirstTightTransfer(List<PublicTrip> trips)
    {
        for (var outgoingIndex = 0; outgoingIndex < trips.Count; outgoingIndex++)
        {
            var outgoing = trips[outgoingIndex];
            var station = outgoing.FromStation.Trim();
            if (station.Length == 0) continue;
            for (var incomingIndex = 0; incomingIndex < outgoingIndex; incomingIndex++)
            {
                var incoming = trips[incomingIndex];
                if (incoming.ArrivalTime is null || incoming.ToStation.Trim() != station) continue;
                var transfer = Departure(outgoing) - incoming.ArrivalTime.Value;
                if (transfer >= TimeSpan.Zero && transfer < TimeSpan.FromMinutes(10)) return outgoing;
            }
        }
        return null;
    }

    private static PublicTrip? FirstWellPreparedTransfer(List<PublicTrip> trips)
    {
        for (var outgoingIndex = 0; outgoingIndex < trips.Count; outgoingIndex++)
        {
            var outgoing = trips[outgoingIndex];
            var station = NormalizedStation(outgoing.FromStation);
            var destination = NormalizedStation(outgoing.ToStation);
            if (station.Length == 0 || destination.Length == 0) continue;
            for (var incomingIndex = 0; incomingIndex < outgoingIndex; incomingIndex++)
            {
                var incoming = trips[incomingIndex];
                if (incoming.ArrivalTime is null || NormalizedStation(incoming.ToStation) != station ||
                    NormalizedStation(incoming.FromStation) == destination) continue;
                var transfer = Departure(outgoing) - incoming.ArrivalTime.Value;
                if (transfer >= TimeSpan.FromHours(6) && transfer < TimeSpan.FromHours(12)) return outgoing;
            }
        }
        return null;
    }

    private static PublicTrip? FirstTransferChainCompletion(List<PublicTrip> trips, int targetTransfers)
    {
        var transferCounts = new int[trips.Count];
        for (var outgoingIndex = 0; outgoingIndex < trips.Count; outgoingIndex++)
        {
            var outgoing = trips[outgoingIndex];
            var station = NormalizedStation(outgoing.FromStation);
            if (station.Length == 0) continue;
            for (var incomingIndex = 0; incomingIndex < outgoingIndex; incomingIndex++)
            {
                var incoming = trips[incomingIndex];
                if (incoming.ArrivalTime is null || NormalizedStation(incoming.ToStation) != station) continue;
                var transfer = Departure(outgoing) - incoming.ArrivalTime.Value;
                if (transfer < TimeSpan.Zero || transfer > TimeSpan.FromHours(3)) continue;
                transferCounts[outgoingIndex] = Math.Max(transferCounts[outgoingIndex], transferCounts[incomingIndex] + 1);
            }
            if (transferCounts[outgoingIndex] >= targetTransfers) return outgoing;
        }
        return null;
    }

    private static IEnumerable<string> RouteNames(PublicTrip trip)
    {
        try
        {
            using var document = JsonDocument.Parse(trip.ViaRoutes);
            if (document.RootElement.ValueKind != JsonValueKind.Array) return [];
            return document.RootElement.EnumerateArray()
                .Where(item => item.ValueKind == JsonValueKind.Object && item.TryGetProperty("routeName", out var name) &&
                    name.ValueKind == JsonValueKind.String)
                .Select(item => item.GetProperty("routeName").GetString()?.Trim() ?? string.Empty)
                .Where(name => name.Length > 0)
                .ToList();
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private sealed record StationVisit(string Station, DateTime Time, PublicTrip Trip);

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();
}
