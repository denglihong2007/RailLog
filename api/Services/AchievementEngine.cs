using System.Collections.Concurrent;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Globalization;
using Microsoft.Data.Sqlite;
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
    public int Experience { get; init; }
    public bool Hidden { get; init; }
    public string? Note { get; init; }
    public string? NarrativeNote { get; init; }
    public IReadOnlyList<AchievementRequirement>? Requirements { get; init; }
}

public sealed record AchievementProgress(double Current, double Target);
public sealed record AchievementRequirement(string Key, string Label, PublicTrip? Trip)
{
    public bool Completed => Trip is not null;
}
public sealed record AchievementReview(string EntityType, string EntityKey);
public sealed record AchievementContext(int TotalExperience, int TotalReviewReactions);

public static partial class AchievementEngine
{
    private static readonly ChineseLunisolarCalendar ChineseCalendar = new();
    private const string Milestones = "milestones";
    private const string ExtremeChallenges = "extremeChallenges";
    private const string RailwayCatalog = "railwayCatalog";
    private const string Touring = "touring";
    private const string FunJourneys = "funJourneys";

    private static readonly HashSet<string> Regular25Models =
        ["25B", "25Z", "25G", "25K", "25T", "25DT"];
    // 梦之特快：全部动力分散式动卧车组。
    private static readonly HashSet<string> DistributedSleeperEmuModels =
        ["CRH1E", "CRH2E", "CRH5E", "CR400AF-AE"];
    private static readonly IReadOnlyList<RollingStockTarget> EarlyEmuModels =
    [
        new("X2000"), new("KDZ1A"), new("DJF1"), new("DJF2"), new("DJF3"),
        new("DJJ1"), new("DJJ2"), new("NZJ1"), new("NZJ2"), new("NDJ3"), new("NYJ1")
    ];
    private static readonly IReadOnlyList<RollingStockTarget> EarlyPassengerCoachModels =
    [
        new("21"), new("22"), new("22A"), new("22B"), new("22C"), new("23"),
        new("24"), new("25A"), new("25Z"), new("25C"), new("31"), new("19"),
        new("30"), new("M1"), new("10"), new("14"), new("82"), new("96")
    ];
    private static readonly IReadOnlyList<EmuModelFamily> EmuModelFamilies =
    [
        new("CRH1", ["CRH1A", "CRH1A-A", "CRH1B", "CRH1E"]),
        new("CRH2", ["CRH2A", "CRH2B", "CRH2C", "CRH2E", "CRH2G"]),
        new("CRH3", ["CRH3A", "CRH3A-A", "CRH3C"]),
        new("CRH5", ["CRH5A", "CRH5E", "CRH5G"]),
        new("CRH6", ["CRH6A", "CRH6A-A", "CRH6F", "CRH6F-A"]),
        new("CRH380A", ["CRH380A", "CRH380AL", "CRH380AN"]),
        new("CRH380B", ["CRH380B", "CRH380BG", "CRH380BL"]),
        new("CRH380CL", ["CRH380CL"]),
        new("CRH380D", ["CRH380D"]),
        new("CR400AF",
        [
            "CR400AF", "CR400AF-A", "CR400AF-AE", "CR400AF-AS", "CR400AF-AX",
            "CR400AF-AZ", "CR400AF-B", "CR400AF-BS", "CR400AF-BZ", "CR400AF-C",
            "CR400AF-G", "CR400AF-S", "CR400AF-X", "CR400AF-Z"
        ]),
        new("CR400BF",
        [
            "CR400BF", "CR400BF-A", "CR400BF-AS", "CR400BF-AX", "CR400BF-AZ",
            "CR400BF-B", "CR400BF-BS", "CR400BF-BZ", "CR400BF-C", "CR400BF-G",
            "CR400BF-GS", "CR400BF-GX", "CR400BF-GZ", "CR400BF-S", "CR400BF-X",
            "CR400BF-Z"
        ]),
        new("CR300AF", ["CR300AF"]),
        new("CR300BF", ["CR300BF"]),
        new("CR200J",
        [
            "CR200J-A", "CR200J-B", "CR200JS-G", "LCR200J"
        ]),
        new("CR200J-C", ["CR200J-C", "CR200J-D"])
    ];
    private static readonly IReadOnlySet<string> EmuSeriesNames =
        EmuModelFamilies.Select(family => family.Series).ToHashSet(StringComparer.Ordinal);
    private static readonly IReadOnlySet<string> EmuSubModelNames =
        EmuModelFamilies.SelectMany(family => family.Models).ToHashSet(StringComparer.Ordinal);
    // 忽略大小写：EmuSetNumbers 不做归一，而 covered / EmuSetCatalog 都是 OrdinalIgnoreCase。
    private static readonly IReadOnlyDictionary<string, EmuModelFamily> EmuFamilyByModel =
        EmuModelFamilies
            .SelectMany(family => family.Models.Select(model => (Model: model, Family: family)))
            .ToDictionary(entry => entry.Model, entry => entry.Family, StringComparer.OrdinalIgnoreCase);

    // 附表6：每个和谐号/复兴号子型号的全部载客车组。车组号一律按 4 位十进制归一后
    // 存成闭区间，因此 "0207" 与 "207" 等价；区间中跳过的号即已退役车组（见 RetiredEmus）。
    private static readonly IReadOnlyDictionary<string, IReadOnlyList<(int From, int To)>> EmuSetCatalog =
        new Dictionary<string, IReadOnlyList<(int From, int To)>>(StringComparer.OrdinalIgnoreCase)
        {
            ["CRH1A"] = [(1001, 1040), (1081, 1168)],
            ["CRH1A-A"] = [(1169, 1228), (1234, 1260)],
            ["CRH1B"] = [(1041, 1045), (1047, 1060), (1076, 1080)],
            ["CRH1E"] = [(1061, 1075), (1229, 1233)],
            ["CRH2A"] = [(2001, 2060), (2151, 2416), (2427, 2460), (2473, 2499), (2828, 2828), (4001, 4019),
                (4021, 4071), (4082, 4088), (4091, 4095), (4114, 4131)],
            ["CRH2B"] = [(2111, 2120), (2466, 2472), (4096, 4105)],
            ["CRH2C"] = [(2062, 2067), (2069, 2110), (2141, 2149)],
            ["CRH2E"] = [(2121, 2138), (2140, 2140), (2461, 2465)],
            ["CRH2G"] = [(2417, 2426), (4073, 4081), (4106, 4113), (4501, 4501)],
            ["CRH3A"] = [(302, 302), (502, 502), (3081, 3111), (5230, 5257)],
            ["CRH3A-A"] = [(511, 521), (526, 530)],
            ["CRH3C"] = [(3001, 3080)],
            ["CRH5A"] = [(5001, 5140)],
            ["CRH5E"] = [(5201, 5202)],
            ["CRH5G"] = [(5141, 5200), (5206, 5229)],
            ["CRH6A"] = [(216, 218), (401, 408), (414, 417), (420, 429), (436, 439), (478, 478), (601, 643),
                (649, 649), (4132, 4137), (4502, 4509)],
            ["CRH6A-A"] = [(212, 215), (219, 229), (233, 233), (234, 234), (451, 460), (480, 490), (644, 648),
                (653, 666), (901, 912)],
            ["CRH6F"] = [(1, 1), (230, 232), (409, 413), (418, 418), (419, 419), (430, 435), (474, 477),
                (479, 479), (650, 650), (651, 651)],
            ["CRH6F-A"] = [(211, 211), (440, 443), (445, 450), (461, 473), (491, 499), (667, 673)],
            ["CRH380A"] = [(251, 259), (2501, 2540), (2641, 2807), (2809, 2817), (2819, 2912), (2921, 2925),
                (2931, 2935)],
            ["CRH380AL"] = [(2541, 2640), (2913, 2920), (2926, 2930)],
            ["CRH380AN"] = [(206, 206)],
            ["CRH380B"] = [(3571, 3731), (3738, 3774), (5637, 5683), (5730, 5802), (5829, 5888)],
            ["CRH380BG"] = [(5546, 5600), (5626, 5636), (5684, 5729), (5762, 5786), (5803, 5822)],
            ["CRH380BL"] = [(3501, 3570), (3732, 3737), (3775, 3786), (5501, 5545), (5823, 5828), (5889, 5898)],
            ["CRH380CL"] = [(5601, 5625)],
            ["CRH380D"] = [(1501, 1585)],
            ["CR200J-A"] = [(1001, 1048), (2001, 2047), (3001, 3004), (4001, 4003), (5001, 5018), (6001, 6018)],
            ["CR200J-B"] = [(1049, 1086), (1093, 1110), (2048, 2084), (3005, 3007), (4004, 4008)],
            ["CR200JS-G"] = [(2901, 2903)],
            ["LCR200J"] = [(401, 405)],
            ["CR200J-C"] = [(1087, 1093), (1111, 1144), (2085, 2127), (5019, 5079), (6019, 6075), (7001, 7001),
                (7002, 7002), (8001, 8001), (8002, 8002)],
            ["CR200J-D"] = [(2801, 2838)],
            ["CR300AF"] = [(1, 1), (3, 3), (4, 4), (1001, 1013), (2001, 2047), (6001, 6004)],
            ["CR300BF"] = [(2, 2), (5, 5), (6, 6), (3001, 3026), (5001, 5041)],
            ["CR400AF"] = [(207, 207), (208, 208), (1006, 1040), (2001, 2017), (2022, 2028), (2030, 2064),
                (2085, 2094), (2124, 2165), (2170, 2187), (2213, 2213), (2222, 2248), (2254, 2256)],
            ["CR400AF-A"] = [(1001, 1005), (1028, 1038), (2065, 2084), (2095, 2115), (2190, 2205),
                (2211, 2212)],
            ["CR400AF-B"] = [(2116, 2123), (2206, 2210)],
            ["CR400AF-G"] = [(21, 21), (2215, 2217)],
            ["CR400AF-C"] = [(2214, 2214)],
            ["CR400AF-Z"] = [(211, 223), (1041, 1063), (2251, 2253), (2257, 2310), (2316, 2340)],
            ["CR400AF-AZ"] = [(2311, 2315)],
            ["CR400AF-BZ"] = [(2249, 2249), (2250, 2250)],
            ["CR400AF-AE"] = [(2398, 2402), (2548, 2560)],
            ["CR400AF-S"] = [(224, 242), (1064, 1105), (1112, 1119), (2346, 2397), (2403, 2481), (2501, 2514),
                (2522, 2541)],
            ["CR400AF-AS"] = [(1106, 1111), (2482, 2500), (2515, 2521)],
            ["CR400AF-BS"] = [(2341, 2345)],
            ["CR400AF-X"] = [(1120, 1120), (2542, 2547), (2561, 2578)],
            ["CR400AF-AX"] = [(2579, 2584)],
            ["CR400BF"] = [(31, 31), (305, 305), (503, 503), (507, 507), (3001, 3023), (3034, 3049),
                (3059, 3091), (3106, 3106), (3107, 3107), (5001, 5047), (5068, 5081), (5106, 5112)],
            ["CR400BF-A"] = [(3024, 3033), (3050, 3058), (3092, 3105), (5048, 5067), (5082, 5096),
                (5156, 5161)],
            ["CR400BF-B"] = [(5097, 5105), (5151, 5155)],
            ["CR400BF-G"] = [(51, 51), (3108, 3116), (5113, 5142), (5146, 5150), (5163, 5202)],
            ["CR400BF-C"] = [(5144, 5144), (5145, 5145), (5162, 5162)],
            ["CR400BF-Z"] = [(311, 311), (312, 312), (511, 514), (521, 524), (3117, 3156), (5210, 5251),
                (5263, 5275)],
            ["CR400BF-AZ"] = [(515, 520), (5252, 5255)],
            ["CR400BF-BZ"] = [(5208, 5208), (5209, 5209)],
            ["CR400BF-GZ"] = [(5143, 5143), (5203, 5207), (5214, 5219), (5256, 5262)],
            ["CR400BF-S"] = [(3157, 3223), (3229, 3266), (3273, 3275), (3285, 3292), (5281, 5306), (5320, 5336),
                (5369, 5386)],
            ["CR400BF-AS"] = [(3224, 3228), (3267, 3272), (3276, 3284), (5364, 5368), (5417, 5423),
                (5441, 5441), (5442, 5442)],
            ["CR400BF-BS"] = [(5276, 5280), (5347, 5347), (5348, 5348)],
            ["CR400BF-GS"] = [(5307, 5319), (5337, 5346), (5349, 5363), (5387, 5416), (5425, 5440),
                (5443, 5447)],
            ["CR400BF-X"] = [(3293, 3312), (5458, 5463)],
            ["CR400BF-AX"] = [(3313, 3316), (5489, 5499)],
            ["CR400BF-GX"] = [(5464, 5488)],
        };
    private static readonly IReadOnlyList<RollingStockTarget> RetiredEmus =
    [
        new("CRH1B", "1046"),
        new("CRH2A", "4020"),
        new("CRH2A", "4089"),
        new("CRH2A", "4090"),
        new("CRH2E", "2139")
    ];
    /// <summary>「我全都要」的收集清单。无座不是席别而是入座方式，靠座位号判定（见 IsNoSeat），
    /// 所以在清单里它是特殊项：站票只点亮它，不再计入票面席别。</summary>
    private static readonly HashSet<string> RegularSeatTypes =
    [
        "无座", "硬座", "软座", "二等座", "一等座", "特等座", "优选一等座", "商务座",
        "硬卧", "软卧", "二等卧", "一等卧", "高级软卧", "动卧", "高级动卧"
    ];
    private static readonly HashSet<string> LuxurySeatTypes =
    [
        "商务座", "特等座", "高级软卧", "高级动卧"
    ];
    private static readonly HashSet<string> AirportStationsWithoutAirportSuffix = ["美兰", "龙洞堡", "上海虹桥"];
    private static readonly IReadOnlyList<RollingStockTarget> VariableGaugeModels =
    [
        new("CR400BF", "0031"),
        new("CR400BF-G", "0051"),
        new("CR400AF-G", "0021")
    ];
    // 「宫车之过」：加装 LKJ 装置的高速动车组。
    private static readonly IReadOnlyList<RollingStockTarget> LkjEquippedEmuModels =
    [
        new("CRH380A", "2796"),
        new("CR400AF", "2183"),
        new("CR400AF", "2184"),
        new("CR400AF", "2185"),
        new("CR400AF", "2186"),
        new("CR400AF", "2187")
    ];
    private static readonly IReadOnlyList<RollingStockTarget> PrototypeModels =
    [
        new("CR400BF", "0305"), new("CR400BF", "0503"), new("CR400BF", "0507"),
        new("CR400AF", "0207"), new("CR300AF", "0001"),
        new("CR300AF", "0003"), new("CR300AF", "0004"), new("CR300BF", "0002"),
        new("CR300BF", "0005"), new("CR300BF", "0006")
    ];
    private static readonly IReadOnlyList<RollingStockTarget> GreatWallExpressModels =
    [
        new("CR400AF-B"), new("CR400AF-BZ"), new("CR400AF-BS"),
        new("CR400BF-B"), new("CR400BF-BZ"), new("CR400BF-BS")
    ];
    private static readonly IReadOnlyList<RollingStockTarget> VibrantExpressModels =
        Enumerable.Range(251, 9)
            .SelectMany(number => new[]
            {
                new RollingStockTarget("CRH380A", $"0{number}"),
                new RollingStockTarget("MTR380A", $"0{number}")
            })
            .Append(new RollingStockTarget("MTR380A"))
            .ToArray();
    private static readonly HashSet<string> CommonTrainCategories =
        ["G", "D", "C", "Z", "T", "K", "Y", "S", "numeric"];
    private static readonly IReadOnlyList<RollingStockTarget> HonorLocomotives =
    [
        new("HXD3CA", "8161"), new("HXD3D", "0035"), new("HXD3D", "0039"),
        new("HXD3D", "0631"), new("HXD3D", "1886"), new("HXD3D", "1893"),
        new("HXD3D", "1921"), new("HXD1", "1937"), new("HXD1C", "1927"),
        new("HXD1D", "1898"), new("HXD2B", "0001"), new("SS3B", "5151")
    ];
    private static readonly IReadOnlyList<RollingStockTarget> EarlyImportedLocomotives =
    [
        new("6Y2"), new("6G"), new("6K"), new("8G"), new("8K"), new("DJ1"),
        new("ND2"), new("ND4"), new("ND5"), new("NY5"), new("NY6"), new("NY7"), new("NJ2")
    ];
    private static readonly IReadOnlyList<RollingStockTarget> SteamLocomotives =
    [
        new("JF"), new("SL"), new("KD"), new("FD"), new("KF"), new("JS"), new("RM"), new("QJ")
    ];
    private static readonly HashSet<string> ModernLocomotives =
    [
        "HXD1", "HXD1B", "HXD1C", "HXD1D", "HXD2", "HXD2B", "HXD2C",
        "HXD3", "HXD3B", "HXD3C", "HXD3D", "HXN3", "HXN5", "FXD1",
        "FXD1BA", "FXD2BA", "FXD3", "FXN3C", "FXN5C", "FXSY"
    ];
    private static readonly HashSet<string> DongfengShaoshanLocomotives =
    [
        "DF1", "DF3", "DF4", "DF4B", "DF4C", "DF4D", "DF7D", "DF8",
        "DF8B", "DF9", "DF10F", "DF11", "DF11Z", "DF11G", "DF21", "SS1", "SS3",
        "SS3B", "SS4", "SS6", "SS6B", "SS7", "SS7C", "SS7D", "SS7E",
        "SS8", "SS9"
    ];

    // Non-air-conditioned coaches are the older 21/22/23/25B/30/31/M1 types plus
    // the 18/10/14/82/96 series used on international or special services. Their
    // hard-seat and hard-sleeper versions are all unairconditioned, while of the
    // soft sleepers only the 21/18/22A/22C/10/14/M1 types are.
    private static readonly HashSet<string> NonAirConditionedHardSeatAndSleeperModels =
        new(StringComparer.OrdinalIgnoreCase)
        {
            "21", "22", "22A", "22B", "22C", "23", "25B", "30", "31", "M1",
            "18", "10", "14", "82", "96"
        };

    private static readonly HashSet<string> NonAirConditionedSoftSleeperModels =
        new(StringComparer.OrdinalIgnoreCase) { "21", "18", "22A", "22C", "10", "14", "M1" };

    private static readonly Dictionary<string, HashSet<string>> NonAirConditionedCoaches =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["YZ"] = NonAirConditionedHardSeatAndSleeperModels,
            ["YW"] = NonAirConditionedHardSeatAndSleeperModels,
            ["RW"] = NonAirConditionedSoftSleeperModels,
        };

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

    private static readonly HashSet<string> AllPassengerCompanies =
        RailwayBureaus.Values
            .SelectMany(companies => companies)
            .ToHashSet(StringComparer.Ordinal);

    private static readonly IReadOnlyList<RailwaySection> YangtzeBridges =
    [
        new("长江源特大桥", "青藏线", "沱沱河", "雁石坪"),
        new("虎跳峡金沙江大桥", "滇藏铁路", "拉市海", "小中甸"),
        new("三堆子金沙江大桥", "成昆线成攀段", "三堆子", "攀枝花"),
        new("成昆复线金沙江大桥", "峨广铁路", "盐边", "普达"),
        new("水富金沙江大桥", "内六线", "一步滩", "翠屏"),
        new("白沙沱长江大桥", "渝贵线", "重庆西", "珞璜南"),
        new("明月峡长江大桥", "重庆东环铁路", "皂角树所", "迎龙"),
        new("长寿长江大桥", "渝怀线", "长寿", "王家坝"),
        new("韩家沱长江大桥", "宁蓉线宁渝段", "丰都", "涪陵北"),
        new("万州长江大桥", "万凉线", "万州", "五桥"),
        new("宜昌长江大桥", "宁蓉线宁渝段", "宜昌东", "长阳"),
        new("枝城长江大桥", "焦柳线焦怀段", "鸦雀岭", "枝城"),
        new("武汉长江大桥", "京广线", "汉西", "武昌"),
        new("天兴洲长江大桥", "京广高铁", "横店东", "武汉"),
        new("天兴洲长江大桥", "滠武线", "滠口", "楠姆庙所"),
        new("黄冈长江大桥", "武冈城际线", "华容东", "黄冈西"),
        new("鳊鱼洲长江大桥", "京港高铁安九段", "黄梅南", "庐山"),
        new("九江长江大桥", "京九线", "小池口", "九江"),
        new("安庆长江大桥", "宁安城际线", "池州", "安庆"),
        new("铜陵长江大桥", "合福高速线", "无为", "铜陵北"),
        new("铜陵长江大桥", "庐铜线", "龙桥", "钟鸣所"),
        new("芜湖长江三桥", "合杭高铁", "芜湖北", "芜湖"),
        new("芜湖长江大桥", "淮南线", "裕溪口", "芜湖"),
        new("大胜关长江大桥", "京沪高速线", "滁州", "南京南"),
        new("大胜关长江大桥", "宁蓉线宁渝段", "南京南", "浦口南"),
        new("南京长江大桥", "京沪线", "林场", "南京"),
        new("五峰山长江大桥", "连镇铁路", "扬州东", "大港南"),
        new("沪苏通长江大桥", "沪苏通线", "南通西", "张家港")
    ];

    // 附表2：33 座黄河大桥。
    private static readonly IReadOnlyList<RailwaySection> YellowRiverBridges =
    [
        new("河口黄河大桥", "兰新客专线", "兰州西", "陈家湾西"),
        new("八盘峡黄河大桥", "兰青线", "八盘峡", "张家祠"),
        new("兰新铁路黄河大桥", "兰新线", "河口南", "龙泉寺"),
        new("西固黄河大桥", "中川铁路", "西固", "树屏"),
        new("东岗黄河大桥", "包兰线", "水源", "兰州东"),
        new("靖远黄河大桥", "红会线", "吴家川", "靖远西"),
        new("靖远黄河特大桥", "银兰高铁", "平川西", "靖远北"),
        new("中卫黄河大桥", "宝中线", "宣和", "柳家庄"),
        new("中宁黄河特大桥", "太中线", "中宁东", "黄羊湾"),
        new("永宁黄河特大桥", "定银线", "灵武", "银川南"),
        new("银川机场黄河特大桥", "银兰高铁", "银川东", "河东机场"),
        new("乌海黄河大桥", "包银高铁", "乌海南", "惠农南"),
        new("三道坎黄河大桥", "包兰线", "乌海东", "乌海西"),
        new("磴口黄河特大桥", "包银高铁", "磴口", "碱柜"),
        new("三盛公黄河大桥", "包兰线", "巴彦高勒", "杭锦旗"),
        new("包西铁路黄河特大桥", "包西线", "包头", "达拉特西"),
        new("呼准鄂铁路黄河特大桥", "呼鄂线", "托克托东", "准格尔"),
        new("吴堡黄河特大桥", "太中线", "柳林南", "吴堡"),
        new("禹门口黄河大桥", "侯阎线", "禹门口", "韩城"),
        new("风陵渡黄河大桥", "南同蒲线", "风陵渡", "孟塬"),
        new("焦枝铁路黄河大桥", "焦柳线焦怀段", "留庄", "王庄"),
        new("郑焦城际铁路黄河大桥", "郑太客专", "黄河景区", "武陟"),
        new("郑焦城际铁路黄河大桥", "京广线", "焦作东", "南阳寨"),
        new("郑新黄河大桥", "京广高铁", "新乡东", "郑州东"),
        new("万滩黄河大桥", "济郑高铁", "新乡南", "杨庄所"),
        new("长东黄河大桥", "新石线", "文庄村", "东明县"),
        new("孙口黄河大桥", "京九线", "台前", "梁山"),
        new("台前黄河大桥", "京港高铁雄商段", "台前东", "梁山"),
        new("长清黄河大桥", "济郑高铁", "长清", "茌平南"),
        new("曹家圈黄河特大桥", "京沪线", "晏城", "桥南"),
        new("济南黄河大桥", "京沪高速线", "德州东", "济南西"),
        new("济南黄河大桥", "齐河联络线", "大漠刘所", "济南西"),
        new("泺口黄河大桥", "济南线", "桥南", "济南"),
        new("济南黄河公铁两用桥", "石济客专线", "大郑庄所", "济南东"),
        new("龙居黄河大桥", "德大线", "利津南", "刘集")
    ];
    private static readonly IReadOnlyList<RailwaySection> SeaBayBridges =
    [
        new("普兰店海湾特大桥", "沈大高速线", "瓦房店西", "金普"),
        new("宁德特大桥", "杭深线", "宁德", "罗源"),
        new("平潭海峡公铁大桥", "福平铁路", "长乐南", "平潭"),
        new("湄洲湾跨海大桥", "甬广高铁福漳段", "莆田", "泉港"),
        new("泉州湾跨海大桥", "甬广高铁福漳段", "泉州东", "泉州南"),
        new("安海湾特大桥", "甬广高铁福漳段", "泉州南", "禾山所"),
        new("杏林大桥", "鹰厦线", "杏林", "厦门高崎")
    ];

    // 附表4：承担客运、长度超过 20 公里的特长隧道。
    private static readonly IReadOnlyList<RailwaySection> Tunnels =
    [
        new("松山湖隧道", "广惠城际", "道滘", "常平东"),
        new("深港隧道", "广深港高速线", "深圳北", "香港西九龙"),
        new("新关角隧道", "青藏线", "天峻", "察汗诺"),
        new("平安隧道", "川青铁路青黄段", "石大关", "叠溪"),
        new("西秦岭隧道", "兰渝线兰渭段", "陇南", "姚渡"),
        new("太行山隧道", "石太客专线", "获鹿所", "阳泉北"),
        new("德胜隧道", "川青铁路青黄段", "镇江关", "松潘"),
        new("秦岭马白山隧道", "武西高铁云十段", "商洛西", "蓝田"),
        new("中天山隧道", "南疆线", "鱼儿沟", "马兰"),
        new("青云山隧道", "永莆线", "永泰", "涵江北"),
        new("小相岭隧道", "峨广铁路", "越西", "喜德西"),
        new("吕梁山隧道", "太中线", "汾阳", "吕梁"),
        new("当金山隧道", "敦煌线", "肃北", "苏干湖"),
        new("乌鞘岭隧道", "兰新线", "打柴沟", "龙沟"),
        new("跃龙门隧道", "川青铁路青黄段", "高川", "茂县")
    ];

    // 「蜀道不难」要求的 7 个横穿秦岭的客运区间。
    private static readonly IReadOnlyList<RailwaySection> QinlingPassages =
    [
        new("兰渝线", "兰渝线兰渭段", "夏官营客车所", "广元"),
        new("宝成线", "宝成线", "宝鸡", "阳平关"),
        new("西成客专线", "西成客专线", "鄠邑", "洋县西"),
        new("西康线", "西康线", "引镇", "大岭铺"),
        new("西渝高速线", "西渝高铁西康段", "西安东", "安康西"),
        new("宁西线", "宁西线西合段", "西峡", "渭南西"),
        new("武西高速线", "武西高铁云十段", "十堰东", "蓝田")
    ];

    private static readonly Lazy<IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>>> RouteStations = new(LoadRouteStations);
    private static readonly Lazy<IReadOnlySet<string>> KnownStations = new(() =>
        RouteStations.Value.Values
            .SelectMany(stations => stations.Keys)
            .ToHashSet(StringComparer.Ordinal));
    // 旧线路库用这些合成线路表示出入境；新库只把口岸线修到国境站，存量行程仍按它们认。
    private static readonly string[] BorderRouteMarkers = ["丹东国境线", "绥芬河交界", "满洲里交界", "二连交界", "阿拉山口交界", "凭祥交界"];
    // 新库里口岸线的终点站。磨憨（境）单独判——它的境外段也在库里。
    private static readonly string[] BorderStationNames = ["丹东", "绥芬河", "满洲里", "二连", "阿拉山口", "凭祥"];

    // 使者莅临的别国首都车站。同一座城市的多个车站算作一项（阿斯塔纳的 1 号站与光明之路站），
    // 站名按别名做包含匹配，因为行程里的站名是用户自由填写的（"河内嘉林"、"莫斯科雅罗斯拉夫尔"
    // 都应算作到访）。
    private static readonly IReadOnlyList<ForeignCapitalStation> ForeignCapitals =
    [
        new("莫斯科", "莫斯科（雅罗斯拉夫尔）", ["雅罗斯拉夫尔"]),
        new("乌兰巴托", "乌兰巴托", ["乌兰巴托"]),
        new("平壤", "平壤", ["平壤"]),
        new("河内", "河内（嘉林）", ["嘉林"]),
        new("万象", "万象", ["万象"]),
        new("阿斯塔纳", "阿斯塔纳（1号站、光明之路站）", ["阿斯塔纳", "光明之路"])
    ];

    // 附表5：内地省会、自治区首府、直辖市与香港的主城区车站，供「纵横九州」
    // （每座城市任意一站）与「功盖振声」（全部必选站）判定。站名已按 NormalizedStation
    // 去掉末尾的「站」；Required=false 即附表里带 * 的站。旧站名只收录无歧义的——
    // 中华门站的旧名「南京南」与现南京南站撞车、长宁站的旧名「上海西」与现上海西站撞车。
    private static readonly IReadOnlyList<CapitalStation> CapitalStations =
    [
        new("北京", "北京", true, []),
        new("北京", "北京南", true, []),
        new("北京", "北京西", true, []),
        new("北京", "北京北", true, []),
        new("北京", "北京东", true, []),
        new("北京", "北京丰台", true, ["丰台"]),
        new("北京", "北京朝阳", true, []),
        new("北京", "清河", true, []),
        new("北京", "北京大兴", true, []),
        new("哈尔滨", "哈尔滨", true, []),
        new("哈尔滨", "哈尔滨西", true, []),
        new("哈尔滨", "哈尔滨东", true, []),
        new("哈尔滨", "哈尔滨北", true, []),
        new("哈尔滨", "香坊", true, []),
        new("长春", "长春", true, []),
        new("长春", "长春西", true, []),
        new("沈阳", "沈阳", true, []),
        new("沈阳", "沈阳北", true, []),
        new("沈阳", "沈阳南", true, []),
        new("天津", "天津", true, []),
        new("天津", "天津西", true, []),
        new("天津", "天津南", true, []),
        new("天津", "北辰", true, []),
        new("呼和浩特", "呼和浩特", true, []),
        new("呼和浩特", "呼和浩特东", true, []),
        new("乌鲁木齐", "乌鲁木齐", true, []),
        new("乌鲁木齐", "乌鲁木齐南", true, []),
        new("银川", "银川", true, []),
        new("银川", "河东机场", true, []),
        new("西宁", "西宁", true, []),
        new("西宁", "西宁西", false, []),
        new("兰州", "兰州", true, []),
        new("兰州", "兰州西", true, []),
        new("兰州", "兰州新区", true, []),
        new("兰州", "中川机场东", true, []),
        new("兰州", "福利区", true, []),
        new("兰州", "秦王川", true, []),
        new("西安", "西安", true, []),
        new("西安", "西安北", true, []),
        new("西安", "西安东", true, []),
        new("西安", "西安西", true, ["阿房宫"]),
        new("西安", "引镇", true, ["西安南"]),
        new("拉萨", "拉萨", true, []),
        new("成都", "成都", false, []),
        new("成都", "成都东", true, []),
        new("成都", "成都南", true, []),
        new("成都", "成都西", true, []),
        new("成都", "双流机场", true, []),
        new("成都", "成都龙泉驿", false, []),
        new("重庆", "重庆", false, []),
        new("重庆", "重庆西", true, []),
        new("重庆", "重庆北", true, []),
        new("重庆", "重庆东", true, []),
        new("重庆", "沙坪坝", true, []),
        new("重庆", "江北机场", true, []),
        new("贵阳", "贵阳", true, []),
        new("贵阳", "贵阳北", true, []),
        new("贵阳", "贵阳东", true, []),
        new("昆明", "昆明", true, []),
        new("昆明", "昆明北", false, []),
        new("昆明", "昆明南", true, []),
        new("太原", "太原", true, []),
        new("太原", "太原南", true, []),
        new("石家庄", "石家庄", true, []),
        new("石家庄", "石家庄北", true, []),
        new("济南", "济南", true, []),
        new("济南", "济南西", true, []),
        new("济南", "济南东", true, []),
        new("济南", "大明湖", true, []),
        new("郑州", "郑州", true, []),
        new("郑州", "郑州东", true, []),
        new("郑州", "郑州西", true, []),
        new("郑州", "南阳寨", true, []),
        new("郑州", "郑州航空港", true, []),
        new("郑州", "新郑机场", true, []),
        new("郑州", "黄河景区", true, []),
        new("合肥", "合肥", true, []),
        new("合肥", "合肥南", true, []),
        new("合肥", "合肥西", true, []),
        new("合肥", "合肥北城", true, []),
        new("南京", "南京", true, []),
        new("南京", "南京西", false, []),
        new("南京", "南京南", true, []),
        new("南京", "仙林", true, []),
        new("南京", "中华门", false, []),
        new("上海", "上海", true, []),
        new("上海", "上海南", true, []),
        new("上海", "上海西", true, ["真如"]),
        new("上海", "上海虹桥", true, []),
        new("上海", "上海松江", true, ["松江", "松江南"]),
        new("上海", "莘庄", true, []),
        new("上海", "长宁", false, []),
        new("武汉", "汉口", true, []),
        new("武汉", "武昌", true, []),
        new("武汉", "武汉", true, []),
        new("武汉", "武汉东", true, []),
        new("武汉", "天河机场", true, []),
        new("长沙", "长沙", true, []),
        new("长沙", "长沙南", true, []),
        new("长沙", "长沙西", false, []),
        new("南昌", "南昌", true, []),
        new("南昌", "南昌西", true, []),
        new("南昌", "南昌南", true, []),
        new("南昌", "南昌东", true, []),
        new("杭州", "杭州", true, []),
        new("杭州", "杭州东", true, []),
        new("杭州", "杭州南", true, []),
        new("杭州", "杭州西", true, []),
        new("福州", "福州", true, []),
        new("福州", "福州南", true, []),
        new("福州", "长乐", true, []),
        new("南宁", "南宁", true, []),
        new("南宁", "南宁东", true, []),
        new("南宁", "南宁西", true, []),
        new("南宁", "南宁北", true, []),
        new("海口", "海口", true, []),
        new("海口", "海口东", true, []),
        new("海口", "美兰", true, []),
        new("广州", "广州", true, []),
        new("广州", "广州东", true, []),
        new("广州", "广州西", false, []),
        new("广州", "广州南", true, []),
        new("广州", "广州北", true, []),
        new("广州", "广州白云", true, []),
        new("广州", "广州新塘", true, []),
        new("香港", "香港红磡", false, ["九龙"]),
        new("香港", "香港西九龙", true, []),
    ];
    private static readonly IReadOnlyList<string> CapitalCityNames =
        CapitalStations.Select(station => station.City).Distinct(StringComparer.Ordinal).ToList();
    private static readonly int RequiredCapitalStationCount =
        CapitalStations.Count(station => station.Required);

    private sealed record AchievementDefinition(
        string Id,
        string Category,
        string Icon,
        string Title,
        string Description,
        int Experience,
        int? MaxExperience = null,
        string? Note = null,
        string? NarrativeNote = null,
        bool Hidden = false,
        Func<AchievementTriggerInput, PublicTrip?>? Trigger = null);

    private sealed record AchievementTriggerInput(
        List<PublicTrip> Trips,
        List<AchievementReview> Reviews,
        AchievementContext? Context,
        PublicTrip? LatestTrip,
        DateTime FifteenYearsAgo);

    private static readonly IReadOnlyList<AchievementDefinition> Definitions =
    [
        new("freeMeal", FunJourneys, "restaurant_outlined", "蹭吃蹭喝", "在用餐时段乘坐里程不超过 50 公里的商务座", 10,
            Note: "11:00-13:00, 17:00-19:00",
            NarrativeNote: "下班车上正好把晚饭解决了",
            Trigger: i => First(i.Trips, UnlocksFreeMeal)),
        new("overnightSeat", ExtremeChallenges, "airline_seat_recline_extra_outlined", "坐待天明",
            "乘坐硬座或二等座，完整度过 00:00 至 06:00", 10,
            NarrativeNote: "相与枕藉乎座中，而知东方之既白",
            Trigger: i => First(i.Trips, UnlocksOvernightSeat)),
        new("tightTransfer", ExtremeChallenges, "transfer_within_a_station", "极限换乘", "完成同站换乘，换乘时间少于 10 分钟", 10,
            NarrativeNote: "哦，那是接近的",
            Trigger: i => FirstTightTransfer(i.Trips)),
        new("wellPreparedTransfer", ExtremeChallenges, "schedule_outlined", "充分打算", "完成同站换乘，等待至少 6 小时但不超过 12 小时", 10,
            NarrativeNote: "在候车厅打发时间的方式其实很多",
            Trigger: i => FirstWellPreparedTransfer(i.Trips)),
        new("sevenDayStreak", Milestones, "local_fire_department", "马不停蹄", "连续 7 天乘坐列车", 15,
            NarrativeNote: "买了计次票的话就会很方便",
            Trigger: i => FirstStreakCompletion(i.Trips, 7)),
        new("thirtyDayStreak", Milestones, "calendar_month_outlined", "漂泊不定", "连续 30 天乘坐列车", 30,
            NarrativeNote: "不要停下来啊……",
            Trigger: i => FirstStreakCompletion(i.Trips, 30)),
        new("duration24Hours", ExtremeChallenges, "looks_one_outlined", "恍如昨日", "乘坐单程时长至少 24 小时的列车", 10,
            NarrativeNote: "下车后多活动活动吧",
            Trigger: i => First(i.Trips, trip => ValidDuration(trip) >= TimeSpan.FromHours(24))),
        new("duration48Hours", ExtremeChallenges, "looks_two_outlined", "旦复旦兮", "乘坐单程时长至少 48 小时的列车", 25,
            NarrativeNote: "跪求硬座过夜技巧",
            Trigger: i => First(i.Trips, trip => ValidDuration(trip) >= TimeSpan.FromHours(48))),
        new("duration72Hours", ExtremeChallenges, "looks_3_outlined", "舟车劳顿", "乘坐单程时长至少 72 小时的列车", 50,
            NarrativeNote: "也许只有临客了",
            Trigger: i => First(i.Trips, trip => ValidDuration(trip) >= TimeSpan.FromHours(72))),
        new("all25Series", RailwayCatalog, "palette_outlined", "五彩斑斓", "分别乘坐全部常规 25 系列客车型号", 30,
            Note: "25B, 25G, 25Z, 25K, 25T, 25DT",
            NarrativeNote: "反对直特换桶.mp4",
            Trigger: i => FirstCollectionCompletion(i.Trips, Regular25Models,
                trip => RollingStockMatches(trip.RollingStock, Regular25Models))),
        new("allEmuSeries", RailwayCatalog, "train_outlined", "琳琅满目", "分别乘坐全部常规和谐号、复兴号系列", 40,
            Note: "CRH1, CRH2, CRH3, CRH5, CRH6, CRH380A, CRH380B, CRH380CL, CRH380D, CR400AF, CR400BF, CR300AF, CR300BF, CR200J, CR200J-C",
            NarrativeNote: "从博采众长到自主创新的历程缩影",
            Trigger: i => FirstCollectionCompletion(i.Trips, EmuSeriesNames, trip => EmuMatches(trip.RollingStock))),
        new("allSeatTypes", RailwayCatalog, "checklist_outlined", "我全都要", "分别乘坐全部常规席别", 40,
            Note: "无座、硬座、软座、二等座、一等座、特等座、优选一等座、商务座、硬卧、软卧、二等卧、一等卧、高级软卧、动卧、高级动卧",
            NarrativeNote: "能看出你很热衷于尝试未体验过的事物",
            Trigger: i => FirstCollectionCompletion(i.Trips, RegularSeatTypes, SeatTypeMatches)),
        new("noSeat12Hours", ExtremeChallenges, "fitness_center_outlined", "体力非凡", "持无座车票乘坐至少 12 小时", 25,
            NarrativeNote: "还好国铁没有放开自由席",
            Trigger: i => First(i.Trips, trip => IsNoSeat(trip) &&
                ValidDuration(trip) >= TimeSpan.FromHours(12))),
        new("sweatLikeRain", ExtremeChallenges, "mode_fan_off", "汗如雨下", "乘坐单程至少 12 小时的非空调列车", 15,
            NarrativeNote: "即使风扇开到最大也是杯水车薪",
            Trigger: i => First(i.Trips, trip => ValidDuration(trip) >= TimeSpan.FromHours(12) &&
                HasNonAirConditionedCoach(trip.RollingStock))),
        new("hundredTickets", Milestones, "collections_bookmark_outlined", "日积月累", "累计出发 100 次", 10,
            NarrativeNote: "总有一天会习惯乘火车出行的",
            Trigger: i => i.Trips.Count >= 100 ? i.Trips[99] : null),
        new("midnightBoarding", ExtremeChallenges, "nightlight_outlined", "夜半钟声", "在 00:00 至 05:00 乘车或下车", 10,
            NarrativeNote: "您旅途辛苦了",
            Trigger: i => FirstMidnightBoarding(i.Trips)),
        new("wallFacingSeat", FunJourneys, "visibility_off_outlined", "一墙障目", "乘坐车厢第 1 排或第 18 排的二等座", 10,
            NarrativeNote: "并不是所有的第1排或第18排都面壁",
            Trigger: i => First(i.Trips, UnlocksWallFacingSeat)),
        new("hundredStations", Milestones, "location_on_outlined", "百站印记", "累计到访至少 100 座不同的客运车站", 15,
            NarrativeNote: "虽然不少车站千篇一律，但也有些独具特色",
            Trigger: i => FirstStationCompletion(i.Trips, 100)),
        new("thousandKilometers", Milestones, "straighten_outlined", "千里足迹", "完成单程至少 1,000 公里的行程", 10,
            NarrativeNote: "适千里者，如今无需三月聚粮",
            Trigger: i => First(i.Trips, trip => trip.MileageKm >= 1000)),
        new("fourThousandKmJourney", Milestones, "nights_stay_outlined", "云月相照",
            "完成单程至少 4,000 公里的行程", 30,
            NarrativeNote: "还是得准备好两三天的干粮",
            Trigger: i => First(i.Trips, trip => trip.MileageKm >= 4000)),
        new("airRail", Touring, "connecting_airports_outlined", "扶摇直上", "累计到访至少 3 座不同的国内机场铁路站", 15,
            MaxExperience: 50,
            Note: "每多一站额外获得5点经验，上限为50点",
            NarrativeNote: "一对恋人在虹桥机场分手的故事是虚构的，听听就行了",
            Trigger: i => FirstAirportStationCompletion(i.Trips, 3)),
        new("acrossTheRealm", Touring, "travel_explore", "纵横九州",
            "到访内地全部省会、自治区首府、直辖市以及香港的任意一座主城区车站", 30,
            Note: "不含城际车站与市域铁路车站，详见附表5",
            NarrativeNote: "就只差一个台湾了",
            Trigger: i => FirstCapitalCityCompletion(i.Trips, CapitalCityNames.Count)),
        new("railFerry", Touring, "directions_boat_outlined", "长风破浪", "乘坐经由任意轮渡线的列车，或在大连与烟台间完成 24 小时内的跨海接续", 15,
            Note: "粤海铁路轮渡、南京长江铁路轮渡、芜湖长江铁路轮渡、新长铁路轮渡；大连与烟台间接续可替代轮渡线路",
            NarrativeNote: "谁不喜欢看火车上船呢",
            Trigger: i => FirstRailFerryCompletion(i.Trips)),
        new("railwayWorkerPassenger", RailwayCatalog, "engineering_outlined", "顺风班车", "乘坐一次路用列车", 25,
            Note: "车次 57XXX 或 40XXX ",
            NarrativeNote: "目前为数不多能收到纸票的方式",
            Trigger: i => First(i.Trips, trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^(?:57|40)\d{3}$"))),
        new("verticalChina", Touring, "swap_vert", "通津南北", "在 14 天内到访漠河站和三亚站", 30,
            MaxExperience: 50,
            Note: "每少二日额外获得5点经验，上限为50点",
            NarrativeNote: "一周之内，感受四季",
            Trigger: i => FirstStationPairWithin(i.Trips, "漠河", "三亚", TimeSpan.FromDays(14))),
        new("horizontalChina", Touring, "swap_horiz", "东奔西走", "在 14 天内到访阿克陶站和抚远站", 30,
            MaxExperience: 50,
            Note: "每少二日额外获得5点经验，上限为50点",
            NarrativeNote: "乌苏里江畔旭日初升，帕米尔高原繁星满天",
            Trigger: i => FirstStationPairWithin(i.Trips, "阿克陶", "抚远", TimeSpan.FromDays(14))),
        new("eastRedSunRises", Touring, "wb_sunny_outlined", "其道大光", "到访东方红站和太阳升站", 30,
            NarrativeNote: "我们的生活天天向上♪我们的前程万丈光芒♪",
            Trigger: i => FirstStationPairCompletion(i.Trips, "东方红", "太阳升")),
        new("highSpeedExperiment", ExtremeChallenges, "speed_outlined", "冲高试验", "完成时长超过 1 小时且均速超过 300 公里/小时的行程", 15,
            NarrativeNote: "虽乘奔御风，不以疾也",
            Trigger: i => First(i.Trips, trip => ValidDuration(trip) > TimeSpan.FromHours(1) && AverageSpeed(trip) > 300)),
        new("slowCrawl", ExtremeChallenges, "slow_motion_video_outlined", "龟速爬行", "完成时长超过 1 小时且均速不超过 50 公里/小时的行程", 10,
            NarrativeNote: "这几十年前修的路压根就开不快",
            Trigger: i => First(i.Trips, trip => ValidDuration(trip) > TimeSpan.FromHours(1) && AverageSpeed(trip) is > 0 and <= 50)),
        new("slowerThanCycling", ExtremeChallenges, "directions_bike_outlined", "不如骑车",
            "完成时长超过 1 小时且均速不超过 30 公里/小时的行程", 30,
            NarrativeNote: "火车不比单车快，不只是云南有这种怪事",
            Trigger: i => First(i.Trips, trip => ValidDuration(trip) > TimeSpan.FromHours(1) && AverageSpeed(trip) is > 0 and <= 30)),
        new("fleetingMoment", FunJourneys, "flash_on_outlined", "转瞬即逝", "乘坐福田或深圳北与香港西九龙间的一等座、商务座或特等座", 20,
            NarrativeNote: "指你的钱",
            Trigger: i => First(i.Trips, UnlocksFleetingMoment)),
        new("borderPorts", Touring, "language_outlined", "异域风情", "到访阿拉山口、二连、满洲里、绥芬河、丹东、崇左或磨憨站", 20,
            MaxExperience: 50,
            Note: "每多一站额外获得5点经验，上限为50点",
            NarrativeNote: "前面的区域，办了护照再来探索吧",
            Trigger: i => FirstStationVisit(i.Trips, ["阿拉山口", "二连", "满洲里", "绥芬河", "丹东", "崇左", "磨憨"])),
        new("singleBikeBorder", Touring, "departure_board_outlined", "单车问边", "乘坐联运列车从任一口岸车站出入境", 30,
            NarrativeNote: "……我护照领到了",
            Trigger: i => First(i.Trips, UnlocksBorderCrossing)),
        new("travelerAbroad", Touring, "luggage_outlined", "他乡旅人", "从任一口岸车站入境后 14 天内由另一口岸车站出境", 50,
            NarrativeNote: "你挥了挥衣袖，没有带走一片云彩",
            Trigger: i => FirstDifferentBorderCompletion(i.Trips)),
        new("skyAndSea", Touring, "filter_hdr_outlined", "上天入海", "在 14 天内到访雁石坪站和香港西九龙站", 30,
            MaxExperience: 50,
            Note: "每少二日额外获得5点经验，上限为50点",
            NarrativeNote: "可上九天揽月，可下五洋捉鳖，谈笑凯歌还",
            Trigger: i => FirstStationPairWithin(i.Trips, "雁石坪", "香港西九龙", TimeSpan.FromDays(14))),
        new("greatWallExpress", RailwayCatalog, "electric_bolt_outlined", "飞驰长城", "乘坐一次 17 节编组的动力分散型动车组", 10,
            NarrativeNote: "惊人的长度，极致的运量",
            Trigger: i => FirstRollingStockMatch(i.Trips, GreatWallExpressModels)),
        new("qinlingPassage", Touring, "landscape_outlined", "蜀道不难", "至少经由 5 条铁路线路完整横穿秦岭", 20,
            MaxExperience: 30,
            Note: "兰渝线夏官营-广元、宝成线宝鸡-阳平关、西成客专线鄠邑-洋县西、西康线引镇-大岭铺、西渝高速线西安东-安康西、宁西线西峡-渭南西、武西高速线十堰东-蓝田；每多一种额外获得5点经验，上限为30点",
            NarrativeNote: "西当太白有铁道，可以横插群山间",
            Trigger: i => FirstSectionThresholdCompletion(i.Trips, AvailableSections(QinlingPassages), 5)),
        new("tunnelCollection", Touring, "subway_outlined", "云霞明灭",
            "行经全部承担客运的 20 公里以上的特长隧道", 40,
            Note: "截至2026年10月共15座，详见附表4",
            NarrativeNote: "这就是地铁吧",
            Trigger: i => FirstSectionCompletion(i.Trips, AvailableSections(Tunnels))),
        new("heavenlyThoroughfare", Touring, "add_road_outlined", "天堑通途", "行经武汉长江大桥", 10,
            Note: "京广线汉西-武昌区间",
            NarrativeNote: "万里长江横渡，极目楚天舒",
            Trigger: i => First(i.Trips, UnlocksHanxiWuchang)),
        new("lonelyPlanet", Touring, "travel_explore_outlined", "孤独星球", "分别乘坐经由和若线与格库线的列车", 30,
            NarrativeNote: "21世纪工程奇迹之环塔克拉玛干沙漠铁路",
            Trigger: i => FirstRouteCollectionCompletion(i.Trips, ["若和铁路", "格库线"])),
        new("hundredThousandKilometers", Milestones, "route_outlined", "轻车熟路", "累计乘车里程至少 100,000 公里", 25,
            NarrativeNote: "你对哪里的印象最深刻呢",
            Trigger: i => FirstCumulativeMileageCompletion(i.Trips, 100000)),
        new("fTrain", RailwayCatalog, "u_turn_left_outlined", "中途遣返", "乘坐一次 F 字头列车", 40,
            NarrativeNote: "列车行驶未半而中道折返",
            Trigger: i => First(i.Trips, trip => trip.TrainNumber.Trim().StartsWith("F", StringComparison.OrdinalIgnoreCase))),
        new("axleOverheat", RailwayCatalog, "device_thermostat_outlined", "轴温过高", "乘坐一次 CR400BF-5033 号列车", 25,
            NarrativeNote: "西成机破京沪焚，掌声送给○○人",
            Trigger: i => FirstRollingStockMatch(i.Trips, [new("CR400BF", "5033")])),
        new("permanentMagnetPower", RailwayCatalog, "bolt_outlined", "永磁动力", "乘坐一次 CRH380AN 型列车", 25,
            NarrativeNote: "未来的应用前景一片光明",
            Trigger: i => FirstRollingStockMatch(i.Trips, [new("CRH380AN")])),
        new("advantageIsMine", Touring, "sports_score_outlined", "优势在我", "到访徐州站或徐州东站", 10,
            NarrativeNote: "站场规模，是15线对13线",
            Trigger: i => FirstStationVisit(i.Trips, ["徐州", "徐州东"])),
        new("thousandMilesToSea", Touring, "sailing_outlined", "去海千里", "到访额敏站或铁厂沟站", 15,
            NarrativeNote: "欧亚大陆难抵极并没有想象的那样干燥",
            Trigger: i => FirstStationVisit(i.Trips, ["额敏", "铁厂沟"])),
        new("platformSubsidence", Touring, "vertical_align_bottom_outlined", "站台沉降", "到访杭州东站", 10,
            NarrativeNote: "事实上只有头尾几节车厢能明显感受到沉降",
            Trigger: i => FirstStationVisit(i.Trips, ["杭州东"])),
        new("archaeologyTeam", Milestones, "history_edu_outlined", "朝花夕拾", "录入至少 15 年前的行程", 25,
            NarrativeNote: "即使忘记了许多细节也没关系",
            Trigger: i => First(i.Trips, trip => Departure(trip) <= i.FifteenYearsAgo)),
        new("strategist", Touring, "psychology_outlined", "文韬武略", "乘坐定西北站至镇江南站的列车", 25,
            Note: "方向不限",
            NarrativeNote: "目前查无此车",
            Trigger: i => First(i.Trips, trip =>
                (NormalizedStation(trip.FromStation) == "定西北" &&
                    NormalizedStation(trip.ToStation) == "镇江南") ||
                (NormalizedStation(trip.FromStation) == "镇江南" &&
                    NormalizedStation(trip.ToStation) == "定西北"))),
        new("eveOfTheStorm", FunJourneys, "thunderstorm_outlined", "风雨前夜",
            "在 2019-12-01 至 2020-01-23 到访武汉站、汉口站或武昌站", 25,
            NarrativeNote: "起初，谁也不知这场风暴最后能席卷全球",
            Trigger: i => FirstStationVisitDuring(i.Trips, ["武汉", "汉口", "武昌"],
                new DateTime(2019, 12, 1), new DateTime(2020, 1, 24))),
        new("tenNumericTrains", RailwayCatalog, "pin_outlined", "慢慢旅途", "累计乘坐至少 10 次纯数字车次", 25,
            NarrativeNote: "时间充足的话，何必还要过分追求速度",
            Trigger: i => FirstCountCompletion(i.Trips, 10, trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^\d+$"))),
        new("overnightSleeper", FunJourneys, "bedtime_outlined", "夕发朝至",
            "乘坐 18:00 至 00:00 发车且 05:00 至 11:00 到达的卧铺列车", 10,
            NarrativeNote: "省了一夜酒店房钱",
            Trigger: i => First(i.Trips, UnlocksOvernightSleeper)),
        new("tripleTransfer", ExtremeChallenges, "multiple_stop_outlined", "辗转挪移", "连续换乘至少 2 次，每次换乘间隔不超过 3 小时", 10,
            NarrativeNote: "专业提示：有时中转反而比直达更实惠",
            Trigger: i => FirstTransferChainCompletion(i.Trips, 2)),
        new("endsOfTheEarth", Touring, "beach_access_outlined", "天涯海角", "到访天涯海角站", 10,
            NarrativeNote: "这其实还不是国铁的最南端",
            Trigger: i => FirstStationVisit(i.Trips, ["天涯海角"])),
        new("fourFamousNorths", Touring, "navigation_outlined", "四大名北", "到访阳泉北站、盘锦北站、孝感北站或邵阳北站", 15,
            MaxExperience: 30,
            Note: "每多一站额外获得5点经验，上限为30点",
            NarrativeNote: "一个比一个名不符实",
            Trigger: i => FirstStationVisit(i.Trips, ["阳泉北", "盘锦北", "孝感北", "邵阳北"])),
        new("youthPriceless", ExtremeChallenges, "airline_seat_recline_normal", "欲试天高",
            "从北京、上海或广州出发，乘坐全程硬座列车到达拉萨站", 40,
            NarrativeNote: "The sky is the limit.",
            Trigger: i => First(i.Trips, trip => NormalizedStation(trip.ToStation) == "拉萨" &&
                NormalizedSeatType(trip.SeatType) == "硬座" &&
                (NormalizedStation(trip.FromStation) .Contains("北京") || NormalizedStation(trip.FromStation) .Contains("上海") || NormalizedStation(trip.FromStation) .Contains("广州")))),
        new("zeroDisplacement", ExtremeChallenges, "loop", "周而复始", "乘坐始发站与终到站相同的环线列车全程", 20,
            NarrativeNote: "再来一圈？",
            Trigger: i => First(i.Trips, trip => NormalizedStation(trip.FromStation) == NormalizedStation(trip.ToStation))),
        new("dreamPath", RailwayCatalog, "auto_awesome_outlined", "逐梦之路", "乘坐一次 25DT 型列车", 20,
            NarrativeNote: "即便是退下来的也很珍贵",
            Trigger: i => FirstRollingStockMatch(i.Trips, [new("25DT")])),
        new("commuterSpecial", FunJourneys, "work_outline", "牛马专列", "乘坐北京与上海间经由京沪高铁的一等座、优选一等座、商务座或特等座", 20,
            NarrativeNote: "也许这些牛马当中也有轨记用户",
            Trigger: i => First(i.Trips, UnlocksCommuterSpecial)),
        new("grandSlam", RailwayCatalog, "hub_outlined", "十人十色", "分别乘坐全部铁路局担当的列车", 30,
            NarrativeNote: "哪个路局又是你的心头好",
            Trigger: i => FirstRailwayBureauCompletion(i.Trips)),
        new("storedUpReward", FunJourneys, "redeem_outlined", "厚积薄发", "使用积分兑换里程超过 50 公里的商务座或特等座车票", 20,
            NarrativeNote: "这要花不少积分，先生",
            Trigger: i => First(i.Trips, UnlocksStoredUpReward)),
        new("drippingStone", FunJourneys, "opacity_outlined", "滴水穿石",
            "在任意 30 天内用积分兑换至少 10 次里程超过 50 公里的车票", 25,
            NarrativeNote: "像极了在B站一直白嫖攒硬币的人",
            Trigger: i => FirstThirtyDayRedemptionCompletion(i.Trips, 10)),
        new("soundSleep", FunJourneys, "hotel_outlined", "酣然入梦", "乘坐全程高级软卧或高级动卧列车的下铺", 25,
            NarrativeNote: "和酒店房间之间就差一间淋浴室",
            Trigger: i => First(i.Trips, UnlocksSoundSleep)),
        new("shortLuxurySleeper", FunJourneys, "single_bed_outlined", "昼寝乍兴",
            "乘坐里程不超过 400 公里的高级软卧或高级动卧", 30,
            NarrativeNote: "年轻真好，倒头就睡",
            Trigger: i => First(i.Trips, trip => trip.MileageKm is > 0 and <= 400 &&
                NormalizedSeatType(trip.SeatType) is "高级软卧" or "高级动卧")),
        new("soloCompartment", FunJourneys, "chair_alt_outlined", "目中无人",
            "乘坐一人软包的卧铺", 30,
            NarrativeNote: "真正的顶级享受",
            Trigger: i => First(i.Trips, trip => NormalizedSeatType(trip.SeatType) == "一人软包")),
        new("spontaneousTrip", RailwayCatalog, "tour_outlined", "说走就走", "乘坐一次 Y 字头旅游列车", 10,
            NarrativeNote: "内饰是不是和传统的列车很不一样呢",
            Trigger: i => First(i.Trips, trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^Y\s*\d", RegexOptions.IgnoreCase))),
        new("redFootprints", Touring, "directions_walk_outlined", "红色足迹", "乘坐韶山南站至延安站或瑞金站至延安站的全程列车", 20,
            Note: "必须以延安为终点站",
            NarrativeNote: "重走一次先辈们的来时路吧",
            Trigger: i => First(i.Trips, trip =>
                NormalizedStation(trip.ToStation) == "延安" &&
                NormalizedStation(trip.FromStation) is "韶山南" or "瑞金")),
        new("greatWallWatch", Touring, "account_balance_outlined", "长城守望", "到访八达岭站或八达岭长城站", 10,
            NarrativeNote: "中国人的铁路就应该中国人自己建",
            Trigger: i => FirstStationVisit(i.Trips, ["八达岭", "八达岭长城"])),
        new("icyWorld", Touring, "ac_unit_outlined", "冰天雪地", "在 12 月、1 月或 2 月到访根河站", 30,
            NarrativeNote: "不做好保暖就只会被冻成英吉利牛肉了",
            Trigger: i => First(i.Trips, UnlocksIcyWorld)),
        new("unnecessaryExtra", FunJourneys, "call_split_outlined", "多此一举", "至少分 3 张车票接续乘坐同一列车", 30,
            MaxExperience: 50,
            Note: "每多一张额外获得10点经验，上限为50点",
            NarrativeNote: "才不是因为没买到全程票呢",
            Trigger: i => FirstThreeTicketSameTrainCompletion(i.Trips)),
        new("blessChina", FunJourneys, "flag_outlined", "祝福祖国", "在 10 月 1 日乘坐列车", 10,
            NarrativeNote: "以前报销凭证上会写些特别的贺词",
            Trigger: i => First(i.Trips, trip => Departure(trip).Month == 10 && Departure(trip).Day == 1)),
        new("newYearsEve", FunJourneys, "celebration_outlined", "新年快乐", "在列车上完成跨年", 10,
            NarrativeNote: "这车去年就发车了，现在才到",
            Trigger: i => First(i.Trips, UnlocksNewYearsEve)),
        new("specialGift", FunJourneys, "card_giftcard_outlined", "特别贺礼",
            "在 1 月 1 日乘坐数字部分为该年年份的车次", 25,
            Note: "中途切换车次也可以",
            NarrativeNote: "即使不打报销凭证也很有纪念意义了",
            Trigger: i => First(i.Trips, UnlocksSpecialGift)),
        new("monotonousTrainNumber", FunJourneys, "repeat_outlined", "千篇一律", "乘坐数字部分为三或四个相同数字的车次", 25,
            Note: "中途切换车次也可以",
            NarrativeNote: "但是朗朗上口",
            Trigger: i => First(i.Trips, UnlocksMonotonousTrainNumber)),
        new("snowWelcomesSpring", RailwayCatalog, "downhill_skiing_outlined", "瑞雪迎春",
            "乘坐一次北京冬奥会限定车型 CR400BF-C-5162", 25,
            NarrativeNote: "仅此一处的多功能座",
            Trigger: i => FirstRollingStockMatch(i.Trips, [new("CR400BF-C", "5162")])),
        new("moistensJiangnan", RailwayCatalog, "water_drop_outlined", "润泽江南", "乘坐一次杭州亚运会限定车型 CR400BF-Z-0524", 25,
            NarrativeNote: "天王老子来了这也是紫茄子",
            Trigger: i => FirstRollingStockMatch(i.Trips, [new("CR400BF-Z", "0524")])),
        new("lkjEquippedEmu", RailwayCatalog, "help_outline", "宫车之过",
            "至少乘坐过 3 列加装 LKJ 装置的高速动车组", 25,
            MaxExperience: 40,
            Note: "CRH380A-2796, CR400AF-2183, 2184, 2185, 2186, 2187；每多一组额外获得5点经验，上限为40点",
            NarrativeNote: "开门，社区送温暖",
            Trigger: i => FirstPartialRollingStockCompletion(i.Trips, LkjEquippedEmuModels, 3)),
        new("facingTheWorld", RailwayCatalog, "public_outlined", "面向世界", "乘坐一次 CR400 系列可变轨距动车组", 20,
            Note: "CR400AF-G-0021, CR400BF-0031, CR400BF-G-0051",
            NarrativeNote: "跨国高铁项目何时再次重启",
            Trigger: i => FirstRollingStockMatch(i.Trips, VariableGaugeModels)),
        new("revivalPrototype", RailwayCatalog, "science_outlined", "复兴之路", "乘坐一次 CR400 或 CR300 原样车", 20,
            MaxExperience: 50,
            Note: "CR400AF-0207, CR400BF-0305, 0503, 0507, CR300AF-0001, 0003, 0004, CR300BF-0002, 0005, 0006；每多一种额外获得5点经验，上限为50点",
            NarrativeNote: "动车组自主创新之路，就此迈出第一步",
            Trigger: i => FirstRollingStockMatch(i.Trips, PrototypeModels)),
        new("vibrantJourney", RailwayCatalog, "movie_outlined", "动感之旅", "乘坐一次港铁动感号列车", 20,
            NarrativeNote: "Caring for life's money",
            Trigger: i => FirstRollingStockMatch(i.Trips, VibrantExpressModels)),
        new("dreamExpress", RailwayCatalog, "format_list_numbered_outlined", "梦之特快",
            "乘坐过全部种类的动力分散式动卧列车", 20,
            Note: "CRH1E, CRH2E, CRH5E, CR400AF-AE",
            NarrativeNote: "现在已经很晚啦，做个好梦，晚安~",
            Trigger: i => FirstCollectionCompletion(i.Trips, DistributedSleeperEmuModels,
                trip => RollingStockMatches(trip.RollingStock, DistributedSleeperEmuModels))),
        new("multipleChoices", FunJourneys, "list_alt_outlined", "多重选择", "在同一乘车区间累计乘坐至少 10 个不同车次", 20,
            NarrativeNote: "车次多就是可以为所欲为的",
            Trigger: i => FirstDistinctTrainCountForRoute(i.Trips, 10)),
        new("publicDisplayOfAffection", FunJourneys, "favorite_outline", "成双成对",
            "在 5 月 20 日、2 月 14 日或七夕乘坐重联动车组列车", 15,
            NarrativeNote: "你是不是也和你的那个TA一起出行呢",
            Trigger: i => First(i.Trips, trip => IsRomanticDate(Departure(trip)) &&
                HasCoupledEmu(trip.RollingStock))),
        new("farsighted", FunJourneys, "view_day_outlined", "高瞻远瞩", "乘坐双层车厢的上层席位", 25,
            NarrativeNote: "再也不怕隔壁列车挡视线了",
            Trigger: i => First(i.Trips, trip => trip.SeatNumber is not null && Regex.IsMatch(trip.SeatNumber, @"上(?!铺)"))),
        new("extraCarriage", FunJourneys, "rv_hookup", "未雨绸缪", "乘坐一次加车车厢", 15,
            NarrativeNote: "看准站务指示，加车可以加在任何位置",
            Trigger: i => First(i.Trips, trip => HasExtraCarriage(trip.SeatNumber))),
        new("substituteSeats", FunJourneys, "event_seat_outlined", "物尽其用", "至少乘坐三次代用席位", 20,
            MaxExperience: 50,
            Note: "每多一次额外获得5点经验，上限为50点",
            NarrativeNote: "你当然可以躺下……只要旁边人不介意",
            Trigger: i => FirstCountCompletion(i.Trips, 3, trip => IsSubstituteSeat(trip.SeatType))),
        new("oneYuanJourney", FunJourneys, "currency_yen", "一元旅程", "单次行程票价为 1 元", 20,
            NarrativeNote: "1995年以后就几乎无法通过全价票取得这一成就了",
            Trigger: i => First(i.Trips, trip => trip.Price == 1)),
        new("cardinalStations", Touring, "assistant_navigation", "东西南北", "到访过一个城市的东西南北中五个车站", 25,
            NarrativeNote: "这样的城市一只手也能数得过来",
            Trigger: i => FirstCardinalStationCompletion(i.Trips)),
        new("ancientLetters", RailwayCatalog, "abc_outlined", "远古字母",
            "在 2004 至 2009 年之间乘坐过以 A、N 或 L 开头的列车，或在 2000 年以前乘坐过 G 字头列车", 20,
            NarrativeNote: "坐过的人年纪都不小了",
            Trigger: i => First(i.Trips, trip =>
            {
                var year = Departure(trip).Year;
                var train = trip.TrainNumber.Trim();
                return (year is >= 2004 and <= 2009 &&
                        Regex.IsMatch(train, @"^[ANL]\s*\d", RegexOptions.IgnoreCase)) ||
                    (year < 2000 && Regex.IsMatch(train, @"^G", RegexOptions.IgnoreCase));
            })),
        new("miniTurnaround", ExtremeChallenges, "timer_outlined", "迷你运转", "单次旅程时间在 10 分钟以内", 10,
            NarrativeNote: "座位还没坐热就到了？！",
            Trigger: i => First(i.Trips, trip => trip.ArrivalTime is not null && trip.ArrivalTime >= Departure(trip) &&
                trip.ArrivalTime - Departure(trip) <= TimeSpan.FromMinutes(10))),
        new("verticalSleeper", RailwayCatalog, "king_bed_outlined", "私人小窝", "乘坐过 CRH2E 纵向动卧列车", 20,
            NarrativeNote: "要是床帘遮光就更好了",
            Trigger: i => First(i.Trips, UnlocksVerticalSleeper)),
        new("completeTrainLetters", RailwayCatalog, "sort_by_alpha_outlined", "车次大全", "常见车次字母都坐过至少一次", 30,
            Note: "G, D, C, S, Z, T, K, Y, 纯数字；未来车次调整后该成就将大幅重构",
            NarrativeNote: "实际上只有四个字母完全没有在车次里用过",
            Trigger: i => FirstCollectionCompletion(i.Trips, CommonTrainCategories, trip =>
                {
                    var category = CommonTrainCategory(trip.TrainNumber);
                    return category is null ? [] : [category];
                })),
        new("blueHorizon", RailwayCatalog, "waves_outlined", "一碧千里", "至少坐过 10 次动集列车", 20,
            NarrativeNote: "到底都是谁在喜欢高饱和度配色啊",
            Trigger: i => FirstCountCompletion(i.Trips, 10, trip => ContainsRollingStock(trip, "CR200J"))),
        new("unpredictableWorld", RailwayCatalog, "heart_broken_outlined", "世事难料", "乘坐过任意已提前退役的动车组", 25,
            Note: "CRH1B-1046, CRH2A-4020, 4089, 4090, CRH2E-2139",
            NarrativeNote: "那日一别，即是永别QAQ",
            Trigger: i => FirstRollingStockMatch(i.Trips, RetiredEmus)),
        new("railwayTrailblazer", RailwayCatalog, "rocket_launch_outlined", "开路先锋",
            "乘坐一次早期动车组列车（不含后期编入普通列车的 25DT）", 25,
            MaxExperience: 50,
            Note: "X2000, KDZ1A, DJF1, DJF2, DJF3, DJJ1, DJJ2, NZJ1, NZJ2, NDJ3, NYJ1；每多一种额外获得10点经验，上限为50点",
            NarrativeNote: "对前辈们艰辛的探索致以崇高的敬意",
            Trigger: i => FirstRollingStockMatch(i.Trips, EarlyEmuModels)),
        new("modestAppetite", FunJourneys, "near_me_outlined", "腹犹果然", "完成单程不超过 20 公里的行程", 10,
            NarrativeNote: "适莽苍者，古时且能三餐而反，遑论今朝？",
            Trigger: i => First(i.Trips, trip => trip.MileageKm is > 0 and <= 20)),
        new("whatAgeIsThis", RailwayCatalog, "history_outlined", "今乃何世", "乘坐一次 2000 年之前停产的客车", 20,
            MaxExperience: 50,
            Note: "21, 22, 22A, 22B, 22C, 23, 24, 25A, 25C, 25Z, 19, 30, 31, M1, 10, 14, 82, 96；每多一种额外获得5点经验，上限为50点",
            NarrativeNote: "以后或许只能在博物馆里见到了",
            Trigger: i => FirstRollingStockMatch(i.Trips, EarlyPassengerCoachModels)),
        new("centuryMeterGauge", RailwayCatalog, "map_outlined", "碧色芳华", "乘坐经由昆河线的列车", 15,
            NarrativeNote: "全国最早的动车组也在这里",
            Trigger: i => First(i.Trips, trip => RouteNames(trip).Any(
                route => route.Contains("昆河线", StringComparison.Ordinal)))),
        new("vowAtQinling", FunJourneys, "favorite", "海誓山盟", "在 5 月 20 日、2 月 14 日或七夕到访海拔 1,314 米的秦岭站", 20,
            NarrativeNote: "山无陵，江水为竭，冬雷震震，夏雨雪，天地合，乃敢与君绝",
            Trigger: i => First(i.Trips, UnlocksVowAtQinling)),
        new("differentRoutesSameDestination", FunJourneys, "alt_route_outlined", "殊途同归",
            "在相同起终点（方向不限）间，经由至少 3 种不同路线", 20,
            MaxExperience: 50,
            Note: "每多一种额外获得10点经验，上限为50点",
            NarrativeNote: "铁路枢纽是方便走邪道的好地方",
            Trigger: i => FirstDifferentRoutesSameDestination(i.Trips)),
        new("fourOfAKind", FunJourneys, "numbers", "四重存在", "乘坐车组号为四位相同数字的动车组列车", 20,
            Note: "CRH1A-1111, CR200JC-1111, CR400AF-AS-1111, CRH2A-2222, CR400AF-2222, CRH380BL-5555",
            NarrativeNote: "如果在车上遇到了一只金发吸血鬼，请告诉我",
            Trigger: i => First(i.Trips, trip => HasQuadrupleSetNumber(trip.RollingStock))),
        new("allAlone", FunJourneys, "person_outline", "茕茕孑立", "乘坐一次 RZ25K 111111 车厢或 CR400AF-AS-1111 的 11 车厢", 30,
            MaxExperience: 50,
            Note: "以下附加条件每满足一项额外获得10点经验，总上限为50点：(1) 座位号为11，不限后缀；(2) 乘车日期为11月11日",
            NarrativeNote: "你最好是刻意来完成这个成就的QAQ",
            Trigger: i => First(i.Trips, UnlocksAllAlone)),
        new("dejaVu", FunJourneys, "replay_outlined", "似曾相识", "至少两次乘坐除日期和车号外均完全一致的行程", 30,
            NarrativeNote: "不知道有多少人忘了填座号",
            Trigger: i => FirstRepeatedTripCompletion(i.Trips, 2)),
        new("traverseOneRegion", Milestones, "linear_scale_outlined", "遍历一方", "经由区间去重后的累计里程达到 5,000 公里", 10,
            NarrativeNote: "继续下去，还有广大的区域等着你来探索",
            Trigger: i => FirstUniqueRouteMileageCompletion(i.Trips, 5000)),
        new("halfTheRealm", Milestones, "pie_chart_outline", "半壁江山", "经由区间去重后的累计里程达到 80,000 公里", 30,
            NarrativeNote: "探索度50%是什么水平？只有自己才知道",
            Trigger: i => FirstUniqueRouteMileageCompletion(i.Trips, 80000)),
        new("centuryDreamFulfilled", Milestones, "flag_circle_outlined", "世纪梦圆", "经由区间去重后的累计里程达到 160,000 公里", 50,
            NarrativeNote: "一百年前，孙中山曾梦想全国修建起16万千米的铁路网",
            Trigger: i => FirstUniqueRouteMileageCompletion(i.Trips, 160000)),
        new("spendsLikeWater", FunJourneys, "payments_outlined", "挥金如土", "单程票价超过 2,000 元", 40,
            NarrativeNote: "商务座，爽！高级软卧，爽！",
            Trigger: i => First(i.Trips, trip => trip.Price > 2000)),
        new("wealthyTraveler", ExtremeChallenges, "savings_outlined", "腰缠万贯", "任意 30 天内的车票总支出超过 10,000 元", 40,
            NarrativeNote: "要是能报销倒还好说",
            Trigger: i => FirstThirtyDaySpendingCompletion(i.Trips, 10000)),
        new("meritAndHonor", RailwayCatalog, "military_tech_outlined", "功成名就", "乘坐至少一种荣誉机车牵引的列车", 20,
            MaxExperience: 50,
            Note: "SS3B 5151, HXD1 1937, HXD1C 1927, HXD1D 1898, HXD2B 0001, HXD3CA 8161, HXD3D 0035, 0039, 0631, 1886, 1893, 1921；每多一种额外获得5点经验，上限为50点",
            NarrativeNote: "真正坐一次挂牌车的体验是单纯拍车感受不到的",
            Trigger: i => FirstRollingStockMatch(i.Trips, HonorLocomotives)),
        new("firstTrip", Milestones, "trip_origin", "始于足下", "首次录入行程", 10,
            NarrativeNote: "就此开始你的第一次出行吧",
            Trigger: i => i.Trips.FirstOrDefault()),
        new("thousandTickets", Milestones, "confirmation_number_outlined", "千千晚星", "累计出发 1,000 次", 40,
            NarrativeNote: "来日纵使千千阙歌♪飘于远方我路上♪",
            Trigger: i => i.Trips.Count >= 1000 ? i.Trips[999] : null),
        new("fiftyThousandSpending", Milestones, "account_balance_wallet_outlined", "千金散尽", "累计车票总支出超过 50,000 元", 30,
            NarrativeNote: "……还复来，但转化成积分了",
            Trigger: i => FirstCumulativeSpendingCompletion(i.Trips, 50000)),
        new("reviewedTrainNumbers", Milestones, "rate_review_outlined", "激扬文字", "累计发布 200 次评论", 20,
            NarrativeNote: "你的点评就是为后人规划出行的参考",
            Trigger: i => i.Reviews.Count >= 200 ? i.Trips.LastOrDefault() : null),
        new("reviewReplies5000", Milestones, "forum_outlined", "交口称赞", "全部评论累计获得 5,000 次回复", 20,
            NarrativeNote: "先生所言极是",
            Trigger: i => ContextTrigger(i, (i.Context?.TotalReviewReactions ?? 0) >= 5000)),
        new("reachLevel3", Milestones, "stairs_outlined", "初出茅庐", "达到 3 级", 10,
            NarrativeNote: "期待有朝一日也能升到6级",
            Trigger: i => ContextTrigger(i, ReachedLevel(i.Context?.TotalExperience ?? 0, 125))),
        new("reachLevel5", Milestones, "trending_up_outlined", "卓尔不群", "达到 5 级", 25,
            NarrativeNote: "到这里你已经超过大部分人了",
            Trigger: i => ContextTrigger(i, ReachedLevel(i.Context?.TotalExperience ?? 0, 450))),
        new("reachLevel6", Milestones, "leaderboard_outlined", "百里挑一", "达到 6 级", 40,
            NarrativeNote: "不畏浮云遮望眼，自缘身在最高层",
            Trigger: i => ContextTrigger(i, ReachedLevel(i.Context?.TotalExperience ?? 0, 800))),
        new("fourThousandKmInDay", ExtremeChallenges, "calendar_view_day_outlined", "日行万里",
            "24 小时内的总移动里程超过 4,000 公里", 30,
            NarrativeNote: "早上坐最快的高铁出发，晚上再坐动卧回来……",
            Trigger: i => FirstRolling24HourMileageCompletion(i.Trips, 4000)),
        new("hundredDeparturesFromStation", FunJourneys, "pin_drop_outlined", "脚步不止", "从单一车站出发 100 次", 25,
            NarrativeNote: "又要开始下一次远行吗……",
            Trigger: i => FirstStationDepartureCompletion(i.Trips, 100)),
        new("multipleLocomotives", FunJourneys, "precision_manufacturing_outlined", "其利断金",
            "乘坐同时由至少两台机车牵引或担当补机的列车", 20,
            MaxExperience: 50,
            Note: "中途换挂的也可以；每多一台额外获得10点经验，上限为50点",
            NarrativeNote: "沿线车迷注意接车，今天×××次双机",
            Trigger: i => First(i.Trips, trip => LocomotiveCount(trip.RollingStock) >= 2)),
        new("relayLocomotives", FunJourneys, "sync_alt_outlined", "前赴后继",
            "乘坐除上下车站外中途至少换挂三次的列车", 25,
            MaxExperience: 50,
            Note: "每多一次额外获得10点经验，上限为50点",
            NarrativeNote: "当心你的泡面或便当",
            Trigger: i => First(i.Trips, trip => LocomotiveChangeCount(trip.RollingStock) >= 3)),
        new("snowBlockingBlueGate", FunJourneys, "severe_cold_outlined", "雪拥蓝关",
            "在 2008-01-10 至 2008-02-10 之间行经京广线武昌至广州间的任意区间", 30,
            NarrativeNote: "你知道吗？那年甚至调机也上了正线",
            Trigger: i => First(i.Trips, UnlocksSnowBlockingBlueGate)),
        new("steamPower", RailwayCatalog, "local_fire_department_outlined", "传统动力", "乘坐至少一种蒸汽机车牵引或担当补机的列车", 50,
            MaxExperience: 80,
            Note: "JF, SL, KD, FD, KF, JS, RM, QJ；每多一种额外获得10点经验，上限为80点",
            NarrativeNote: "这就是为什么火车叫做火车",
            Hidden: true,
            Trigger: i => FirstRollingStockMatch(i.Trips, SteamLocomotives)),
        new("fourExtremes", Touring, "explore_outlined", "遍览四境", "在 60 天内分别到访漠河站、三亚站、阿克陶站、抚远站，次序不限", 30,
            MaxExperience: 50,
            Note: "每少五日额外获得5点经验，上限为50点",
            NarrativeNote: "四境之内，皆为汉土",
            Trigger: i => FirstFourExtremesCompletion(i.Trips, TimeSpan.FromDays(60))),
        new("waterIsCalm", Touring, "water_outlined", "水何澹澹", "到访东戴河站", 20,
            NarrativeNote: "萧瑟秋风今又是，换了人间",
            Trigger: i => FirstStationVisit(i.Trips, ["东戴河"])),
        new("roadBlazing", Touring, "foundation_outlined", "筚路蓝缕", "到访中国原子城站", 40,
            NarrativeNote: "草原深处，石破天惊",
            Trigger: i => FirstStationVisit(i.Trips, ["中国原子城"])),
        new("remoteWilderness", Touring, "forest_outlined", "渺无人烟", "到访茫崖站或花土沟站", 20,
            NarrativeNote: "望不到周围有别的城市",
            Trigger: i => FirstStationVisit(i.Trips, ["茫崖", "花土沟"])),
        new("goddessYangtzeBridges", Touring, "architecture_outlined", "神女无恙", "行经全部承担客运的铁路长江大桥", 40,
            Note: "截至2026年10月共25座，详见附表1",
            NarrativeNote: "1950年的人也许也不会想到如今有这么多长江大桥",
            Trigger: i => FirstSectionCompletion(i.Trips, AvailableSections(YangtzeBridges))),
        new("muddyWavesSweepSky", Touring, "tsunami", "浊浪排空", "行经全部承担客运的铁路黄河大桥", 40,
            Note: "截至2026年10月共33座，详见附表2",
            NarrativeNote: "一桥飞架，百尺之冰亦可渡",
            Trigger: i => FirstSectionCompletion(i.Trips, AvailableSections(YellowRiverBridges))),
        new("mistyVastWaters", Touring, "anchor", "烟波微茫", "行经全部承担客运的铁路跨海大桥或海湾大桥", 20,
            Note: "截至2026年10月共7座，详见附表3",
            NarrativeNote: "或许大多数人只能想起其中一两座",
            Trigger: i => FirstSectionCompletion(i.Trips, AvailableSections(SeaBayBridges))),
        new("oneStoneThreeBirds", FunJourneys, "filter_3_outlined", "一石三鸟", "单次行程同时满足其他至少三项成就的取得条件", 30,
            Note: "必须均为之前未取得过的成就",
            NarrativeNote: "要 素 过 多"),
        new("unknownTerritory", Milestones, "visibility_outlined", "未知领域", "取得任意隐藏成就", 40,
            NarrativeNote: "并非做不到，只要有这个决心，没什么不可能"),
        new("careerRecord", Milestones, "emoji_events_outlined", "履历斐然", "取得其他所有常规成就", 50,
            NarrativeNote: "阁下真的是人类？"),
        new("ancientMemory", Milestones, "auto_stories_outlined", "远古回忆", "录入 1995 年以前的行程", 50,
            NarrativeNote: "那时甚至还没有软纸车票",
            Hidden: true,
            Trigger: i => First(i.Trips, trip => Departure(trip) < new DateTime(1995, 1, 1))),
        new("thousandCities", Milestones, "location_city_outlined", "千城千面", "累计到访过 2,500 座不同的客运车站", 80,
            NarrativeNote: "进站，安检，检票，上车……这个流程想必已经形成肌肉记忆了吧",
            Hidden: true,
            Trigger: i => FirstStationCompletion(i.Trips, 2500)),
        new("rottenAxe", Milestones, "hourglass_bottom_outlined", "烂柯之人", "连续 365 天乘坐列车", 80,
            NarrativeNote: "师傅你是做什么工作的",
            Hidden: true,
            Trigger: i => FirstStreakCompletion(i.Trips, 365)),
        new("roamFreely", Milestones, "signpost_outlined", "随心徜徉", "分别行经全部客运线路的任意区间", 80,
            NarrativeNote: "你一定把全国铁路网都背熟了吧",
            Hidden: true,
            Trigger: i => FirstRouteCatalogCompletion(i.Trips)),
        new("travelAllMountains", Milestones, "terrain_outlined", "踏遍山河", "累计乘车里程至少 500,000 公里", 80,
            NarrativeNote: "小汽车也很少开得到这个里程……大货车也许可以与之一试？",
            Hidden: true,
            Trigger: i => FirstCumulativeMileageCompletion(i.Trips, 500000)),
        new("reviewReplies100000", Milestones, "campaign_outlined", "有口皆碑", "全部评论累计获得 100,000 次回复", 50,
            NarrativeNote: "新时代的国铁嘴替就是你了",
            Hidden: true,
            Trigger: i => ContextTrigger(i, (i.Context?.TotalReviewReactions ?? 0) >= 100000)),
        new("reach2500Experience", Milestones, "stars_outlined", "九重天外", "总经验值达到 2,500 点", 80,
            Note: "包括从隐藏成就获得的经验",
            NarrativeNote: "这波你在大气层",
            Hidden: true,
            Trigger: i => ContextTrigger(i, (i.Context?.TotalExperience ?? 0) >= 2500)),
        new("immovableMountain", ExtremeChallenges, "accessibility_new", "不动如山", "持无座车票乘坐至少 24 小时", 50,
            NarrativeNote: "你站你也麻",
            Hidden: true,
            Trigger: i => First(i.Trips, trip => IsNoSeat(trip) &&
                ValidDuration(trip) >= TimeSpan.FromHours(24))),
        new("pitchDark", ExtremeChallenges, "inventory_2_outlined", "暗无天日",
            "乘坐单程至少 30 分钟的棚车代客列车", 80,
            Note: "路用列车也可以",
            NarrativeNote: "我是在坐车吗……这分明是在坐牢！",
            Hidden: true,
            Trigger: i => First(i.Trips, trip => IsBoxcarSeat(trip.SeatType) &&
                ValidDuration(trip) >= TimeSpan.FromMinutes(30))),
        new("standingTall", ExtremeChallenges, "directions_railway_outlined", "顶天立地",
            "持无座或硬座车票乘坐单程至少 24 小时的非空调列车", 80,
            NarrativeNote: "老资历我敬你",
            Hidden: true,
            Trigger: i => First(i.Trips, trip => (IsNoSeat(trip) || NormalizedSeatType(trip.SeatType) == "硬座") &&
                ValidDuration(trip) >= TimeSpan.FromHours(24) &&
                HasNonAirConditionedCoach(trip.RollingStock))),
        new("richerThanNation", ExtremeChallenges, "diamond_outlined", "富可敌国", "任意 30 天内的车票总支出超过 50,000 元", 80,
            NarrativeNote: "坐一次丝路梦享号的最豪华包间就够了",
            Hidden: true,
            Trigger: i => FirstThirtyDaySpendingCompletion(i.Trips, 50000)),
        new("crowningGlory", Touring, "military_tech", "功盖振声",
            "到访内地全部省会、自治区首府、直辖市，以及香港的全部主城区车站", 80,
            Note: "不含城际车站与市域铁路车站，详见附表5",
            NarrativeNote: "火车在这些铁路枢纽当中到底有多少种走法",
            Hidden: true,
            Trigger: i => FirstCapitalStationCompletion(i.Trips, RequiredCapitalStationCount)),
        new("envoyArrival", Touring, "gps_fixed_outlined", "使者莅临",
            "乘坐直达联运列车到访至少 3 座别国首都车站", 50,
            MaxExperience: 80,
            Note: "莫斯科（雅罗斯拉夫尔）、乌兰巴托、平壤、河内（嘉林）、万象、阿斯塔纳（1号站、光明之路站）；每多一站额外获得10点经验，上限为80点",
            NarrativeNote: "未来还会有更多的跨国铁路，拭目以待吧",
            Hidden: true,
            Trigger: i => FirstForeignCapitalCompletion(i.Trips, 3)),
        new("flowersAmong", RailwayCatalog, "local_florist_outlined", "百花丛中", "分别乘坐全部常规和谐号、复兴号小类型号", 80,
            Note: "截至2026年10月共65种，详见附表6",
            NarrativeNote: "各种技术参数你或许比车辆厂的职工还熟悉",
            Hidden: true,
            Trigger: i => FirstCollectionCompletion(i.Trips, EmuSubModelNames, trip => SmallEmuMatches(trip.RollingStock))),
        new("refinedMechanic", RailwayCatalog, "handyman_outlined", "精益求精", "分别乘坐全部和谐型与复兴型量产机车牵引的列车（不含动集动力车、调机与非国铁机车）", 80,
            Note: "HXD1, HXD1B, HXD1C, HXD1D, HXD2, HXD2B, HXD2C, HXD3, HXD3B, HXD3C, HXD3D, HXN3, HXN5, FXD1, FXD1BA, FXD2BA, FXD3, FXN3C, FXN5C, FXSY",
            NarrativeNote: "更大功率，更高运力",
            Hidden: true,
            Trigger: i => FirstCollectionCompletion(i.Trips, ModernLocomotives, trip => RollingStockMatches(trip.RollingStock, ModernLocomotives))),
        new("dawnBreaks", RailwayCatalog, "wb_twilight_outlined", "曙光乍现", "分别乘坐全部东风型与韶山型量产机车牵引的列车（不含调机与非国铁机车）", 80,
            Note: "DF1, DF3, DF4, DF4B, DF4C, DF4D, DF7D, DF8, DF8B, DF9, DF10F, DF11, DF11Z, DF11G, DF21, SS1, SS3, SS3B, SS4, SS6, SS6B, SS7, SS7C, SS7D, SS7E, SS8, SS9",
            NarrativeNote: "听说这是HCM的最爱",
            Hidden: true,
            Trigger: i => FirstCollectionCompletion(i.Trips, DongfengShaoshanLocomotives, trip => RollingStockMatches(trip.RollingStock, DongfengShaoshanLocomotives))),
        new("completeEmuFleet", RailwayCatalog, "menu_book_outlined", "百车全书", "分别乘坐任意和谐号或复兴号系列的全部载客车组", 80,
            MaxExperience: 200,
            Note: "详见附表6，每多一个系列额外获得30点经验，上限为200点",
            NarrativeNote: "建议是没有必要继续贪这个成就的额外经验",
            Hidden: true,
            Trigger: i => FirstCompleteEmuFamily(i.Trips)),
        new("hundredPeople", RailwayCatalog, "groups_outlined", "百人百相", "分别乘坐全部客运段担当的列车", 50,
            NarrativeNote: "所以你觉得哪个客运段的服务最好，哪个又最差？",
            Hidden: true,
            Trigger: i => FirstCollectionCompletion(i.Trips, AllPassengerCompanies, trip =>
                AllPassengerCompanies.Where(company =>
                    (trip.CompanyName?.Contains(company, StringComparison.Ordinal) ?? false))
                    .ToHashSet(StringComparer.Ordinal))),
        new("thousandDeparturesFromStation", FunJourneys, "outbound_outlined", "百转千回", "从单一车站出发 1,000 次", 80,
            NarrativeNote: "车站的结构图已经早就被你刻在DNA里了吧！",
            Hidden: true,
            Trigger: i => FirstStationDepartureCompletion(i.Trips, 1000)),
        new("luxuryStreak2", FunJourneys, "airline_seat_flat_angled_outlined", "车驾肥轻",
            "连续两次乘坐商务座、特等座、高级软卧或高级动卧出行", 30,
            NarrativeNote: "不要告诉我是因为买不到别的席位的票",
            Trigger: i => FirstLuxuryStreakCompletion(i.Trips, 2)),
        new("luxuryStreak20", FunJourneys, "airline_seat_individual_suite_outlined", "君临天下",
            "连续 20 次乘坐商务座、特等座、高级软卧或高级动卧出行", 80,
            NarrativeNote: "我太想进步了",
            Hidden: true,
            Trigger: i => FirstLuxuryStreakCompletion(i.Trips, 20)),
        new("misfortuneTwice", FunJourneys, "car_repair_outlined", "厄运成双",
            "乘坐单程因故中途更换过两次编组的动车组列车", 80,
            NarrativeNote: "什么叫机破了之后换的热备车又机破了？你解释一下",
            Hidden: true,
            Trigger: i => First(i.Trips, trip => EmuFormationChangeCount(trip.RollingStock) >= 2)),
        new("nonOrdinary", Milestones, "workspace_premium_outlined", "非同凡人", "完成除本成就外其他所有成就（该成就可能随其他成就增补而失去）", 0,
            NarrativeNote: "这个成就你居然达成了？已经没有人类了。必须给你专门颁个奖，毕竟再多的经验如今对你而言也没有什么意义orz",
            Hidden: true),
        new("friendshipForever", RailwayCatalog, "handshake_outlined", "友谊长存", "乘坐至少一种早期进口机车牵引的列车", 25,
            MaxExperience: 50,
            Note: "6Y2, 6G, 6K, 8G, 8K, DJ1, ND2, ND4, ND5, NY5, NY6, NY7, NJ2；每多一种额外获得5点经验，上限为50点",
            NarrativeNote: "For the sake of auld lang syne",
            Trigger: i => FirstRollingStockMatch(i.Trips, EarlyImportedLocomotives)),
    ];

    private static readonly IReadOnlyDictionary<string, AchievementDefinition> DefinitionById =
        BuildDefinitionIndex();

    private static IReadOnlyDictionary<string, AchievementDefinition> BuildDefinitionIndex()
    {
        var index = new Dictionary<string, AchievementDefinition>(StringComparer.Ordinal);
        foreach (var definition in Definitions)
        {
            if (!index.TryAdd(definition.Id, definition))
                throw new InvalidOperationException($"Achievement definition {definition.Id} is duplicated.");
        }
        if (Definitions.Select(definition => definition.Icon).Distinct(StringComparer.Ordinal).Count() != Definitions.Count)
            throw new InvalidOperationException("Achievement icon mapping contains duplicate icons.");
        return index;
    }

    private static readonly IReadOnlySet<string> RegularAchievementIdSet =
        Definitions.Where(definition => !definition.Hidden)
            .Select(definition => definition.Id)
            .ToHashSet(StringComparer.Ordinal);

    public static IReadOnlySet<string> RegularAchievementIds =>
        RegularAchievementIdSet;

    public static bool IsHiddenAchievement(string id) => IsHidden(id);

    private static PublicTrip? ContextTrigger(AchievementTriggerInput input, bool condition) =>
        condition ? input.LatestTrip : null;

    public static IReadOnlyList<AchievementEvaluation> Evaluate(
        IEnumerable<PublicTrip> sourceTrips,
        IEnumerable<AchievementReview>? sourceReviews = null,
        AchievementContext? context = null,
        DateTime? now = null)
    {
        var trips = sourceTrips
            .Where(trip => trip.IsRailTrip)
            .OrderBy(trip => trip.DepartureTime ?? trip.CreatedAt)
            .ThenBy(trip => trip.TicketId)
            .ToList();
        var reviews = sourceReviews?.ToList() ?? [];
        var latestTrip = trips.Count > 0 ? trips[^1] : null;
        var today = (now ?? DateTime.Now).Date;
        var fifteenYearsAgo = new DateTime(today.Year - 15, 1, 1)
            .AddMonths(today.Month - 1)
            .AddDays(today.Day - 1);
        var input = new AchievementTriggerInput(trips, reviews, context, latestTrip, fifteenYearsAgo);
        var values = Definitions
            .Select(definition => new AchievementEvaluation(
                definition.Id,
                definition.Category,
                definition.Icon,
                definition.Title,
                definition.Description,
                definition.Trigger?.Invoke(input)?.TicketId))
            .ToList();

        var aggregateIds = new HashSet<string>(
            [
                "oneStoneThreeBirds", "unknownTerritory", "careerRecord", "nonOrdinary",
                "reviewReplies5000", "reachLevel3", "reachLevel5", "reachLevel6",
                "reviewReplies100000", "reach2500Experience"
            ],
            StringComparer.Ordinal);
        var oneStoneIndex = values.FindIndex(item => item.Id == "oneStoneThreeBirds");
        var oneStoneTrigger = values
            .Where(item => !aggregateIds.Contains(item.Id) && item.TriggerTripId.HasValue)
            .GroupBy(item => item.TriggerTripId!.Value)
            .Where(group => group.Count() >= 3)
            .Select(group => (int?)group.Key)
            .OrderBy(id => trips.FindIndex(trip => trip.TicketId == id))
            .FirstOrDefault();
        if (oneStoneTrigger is int triggerTripId)
            values[oneStoneIndex] = values[oneStoneIndex] with { TriggerTripId = triggerTripId };

        var hiddenTriggers = values
            .Where(item => item.Id != "unknownTerritory" && IsHidden(item.Id) && item.TriggerTripId.HasValue)
            .Select(item => item.TriggerTripId!.Value)
            .ToList();
        if (hiddenTriggers.Count > 0)
        {
            var unknownIndex = values.FindIndex(item => item.Id == "unknownTerritory");
            values[unknownIndex] = values[unknownIndex] with
            {
                TriggerTripId = EarliestTrigger(hiddenTriggers, trips)
            };
        }

        var regularOthers = values
            .Where(item => item.Id != "careerRecord" && !IsHidden(item.Id))
            .ToList();
        if (regularOthers.All(item => item.TriggerTripId.HasValue))
        {
            var careerIndex = values.FindIndex(item => item.Id == "careerRecord");
            values[careerIndex] = values[careerIndex] with
            {
                TriggerTripId = LatestTrigger(
                    regularOthers.Select(item => item.TriggerTripId!.Value),
                    trips)
            };
        }

        var allOthers = values.Where(item => item.Id != "nonOrdinary").ToList();
        if (allOthers.All(item => item.TriggerTripId.HasValue))
        {
            var nonOrdinaryIndex = values.FindIndex(item => item.Id == "nonOrdinary");
            values[nonOrdinaryIndex] = values[nonOrdinaryIndex] with
            {
                TriggerTripId = LatestTrigger(
                    allOthers.Select(item => item.TriggerTripId!.Value),
                    trips)
            };
        }

        return values
            .Select(item =>
            {
                var definition = DefinitionFor(item.Id);
                var progress = ProgressFor(
                    item.Id,
                    trips,
                    reviews,
                    today,
                    fifteenYearsAgo,
                    context);
                var requirements = definition.Hidden
                    ? null
                    : RequirementsFor(item.Id, trips);
                return item with
                {
                    Progress = progress,
                    Requirements = requirements,
                    Experience = ExperienceFor(
                        item.Id,
                        definition,
                        item.TriggerTripId.HasValue,
                        trips),
                    Hidden = definition.Hidden,
                    Note = definition.Note,
                    NarrativeNote = definition.NarrativeNote
                };
            })
            .OrderByDescending(item => item.TriggerTripId.HasValue)
            .ToList();
    }

    private static AchievementDefinition DefinitionFor(string id) => DefinitionById[id];

    private static bool IsHidden(string id) =>
        DefinitionById.TryGetValue(id, out var definition) && definition.Hidden;

    private static long? EarliestTrigger(IEnumerable<long> triggerIds, List<PublicTrip> trips)
    {
        var tripOrder = trips
            .Select((trip, index) => (trip.TicketId, index))
            .ToDictionary(item => item.TicketId, item => item.index);
        return triggerIds
            .OrderBy(id => tripOrder.GetValueOrDefault(id, int.MaxValue))
            .Cast<long?>()
            .FirstOrDefault();
    }

    private static long? LatestTrigger(IEnumerable<long> triggerIds, List<PublicTrip> trips)
    {
        var tripOrder = trips
            .Select((trip, index) => (trip.TicketId, index))
            .ToDictionary(item => item.TicketId, item => item.index);
        return triggerIds
            .OrderByDescending(id => tripOrder.GetValueOrDefault(id, -1))
            .Cast<long?>()
            .FirstOrDefault();
    }

    private static int ExperienceFor(
        string id,
        AchievementDefinition definition,
        bool unlocked,
        List<PublicTrip> trips)
    {
        if (!unlocked) return definition.Experience;
        var experience = definition.Experience;
        var bonus = id switch
        {
            "railwayTrailblazer" => Math.Max(
                0,
                CollectedCount(trips, trip =>
                    RollingStockMatches(trip.RollingStock, EarlyEmuModels)) - 1) * 10,
            "meritAndHonor" => Math.Max(
                0,
                CollectedCount(trips, trip =>
                    RollingStockMatches(trip.RollingStock, HonorLocomotives)) - 1) * 5,
            "friendshipForever" => Math.Max(
                0,
                CollectedCount(trips, trip =>
                    RollingStockMatches(trip.RollingStock, EarlyImportedLocomotives)) - 1) * 5,
            "whatAgeIsThis" => Math.Max(
                0,
                CollectedCount(trips, trip =>
                    RollingStockMatches(trip.RollingStock, EarlyPassengerCoachModels)) - 1) * 5,
            "revivalPrototype" => Math.Max(
                0,
                CollectedCount(trips, trip =>
                    RollingStockMatches(trip.RollingStock, PrototypeModels)) - 1) * 5,
            "lkjEquippedEmu" => Math.Max(
                0,
                CollectedCount(trips, trip =>
                    RollingStockMatches(trip.RollingStock, LkjEquippedEmuModels)) - 3) * 5,
            "qinlingPassage" => Math.Max(
                0,
                SectionCoverageCount(trips, AvailableSections(QinlingPassages)) - 5) * 5,
            "steamPower" => Math.Max(
                0,
                CollectedCount(trips, trip =>
                    RollingStockMatches(trip.RollingStock, SteamLocomotives)) - 1) * 10,
            "verticalChina" => StationPairWindowBonus(trips, "漠河", "三亚"),
            "horizontalChina" => StationPairWindowBonus(trips, "阿克陶", "抚远"),
            "skyAndSea" => StationPairWindowBonus(trips, "雁石坪", "香港西九龙"),
            "fourExtremes" => FourExtremesWindowBonus(trips),
            "fourFamousNorths" => Math.Max(
                0,
                VisitedStationCount(trips, ["阳泉北", "盘锦北", "孝感北", "邵阳北"]) - 1) * 5,
            "borderPorts" => Math.Max(
                0,
                VisitedStationCount(trips, ["阿拉山口", "二连", "满洲里", "绥芬河", "丹东", "崇左", "磨憨"]) - 1) * 5,
            "airRail" => Math.Max(0, AirportStationCount(trips) - 3) * 5,
            "completeEmuFleet" => Math.Max(0, CompleteEmuFamilyCount(trips) - 1) * 30,
            "envoyArrival" => Math.Max(0, ForeignCapitalCount(trips) - 3) * 10,
            "multipleLocomotives" => Math.Max(0, MaxLocomotiveCount(trips) - 2) * 10,
            "relayLocomotives" => Math.Max(0, MaxLocomotiveChangeCount(trips) - 3) * 10,
            "substituteSeats" => Math.Max(
                0,
                trips.Count(trip => IsSubstituteSeat(trip.SeatType)) - 3) * 5,
            "unnecessaryExtra" => Math.Max(0, MaxSameTrainTicketChain(trips) - 3) * 10,
            "differentRoutesSameDestination" => Math.Max(
                0,
                MaxDifferentRoutesSameDestination(trips) - 3) * 10,
            "allAlone" => AllAloneBonus(trips),
            _ => 0
        };
        experience += bonus;
        return definition.MaxExperience is int maximum
            ? Math.Min(experience, maximum)
            : experience;
    }

    private static int StationPairWindowBonus(
        List<PublicTrip> trips,
        string first,
        string second)
    {
        var days = ShortestStationPairWindowDays(trips, first, second);
        return Math.Max(0, (int)Math.Floor((14 - days) / 2)) * 5;
    }

    private static bool ReachedLevel(int totalExperience, int requiredExperience) =>
        totalExperience >= requiredExperience;

    private static int FourExtremesWindowBonus(List<PublicTrip> trips)
    {
        var days = ShortestFourExtremesWindowDays(trips);
        return Math.Max(0, (int)Math.Floor((60 - days) / 5)) * 5;
    }

    private static AchievementProgress? ProgressFor(
        string id,
        List<PublicTrip> trips,
        List<AchievementReview> reviews,
        DateTime today,
        DateTime fifteenYearsAgo,
        AchievementContext? context) => id switch
    {
        "sevenDayStreak" => P(LongestStreak(trips), 7),
        "thirtyDayStreak" => P(LongestStreak(trips), 30),
        "rottenAxe" => P(LongestStreak(trips), 365),
        "duration24Hours" => P(MaxDurationHours(trips), 24),
        "duration48Hours" => P(MaxDurationHours(trips), 48),
        "duration72Hours" => P(MaxDurationHours(trips), 72),
        "all25Series" => P(CollectedCount(trips, trip => RollingStockMatches(trip.RollingStock, Regular25Models)), Regular25Models.Count),
        "allEmuSeries" => P(
            CollectedCount(trips, trip => EmuMatches(trip.RollingStock)),
            EmuModelFamilies.Count),
        "allSeatTypes" => P(CollectedCount(trips, SeatTypeMatches), RegularSeatTypes.Count),
        "lkjEquippedEmu" => P(
            CollectedCount(trips, trip => RollingStockMatches(trip.RollingStock, LkjEquippedEmuModels)),
            3),
        "noSeat12Hours" => P(MaxDurationHours(trips.Where(IsNoSeat)), 12),
        "sweatLikeRain" => P(MaxDurationHours(trips.Where(trip => HasNonAirConditionedCoach(trip.RollingStock))), 12),
        "immovableMountain" => P(MaxDurationHours(trips.Where(IsNoSeat)), 24),
        "hundredTickets" => P(trips.Count, 100),
        "thousandTickets" => P(trips.Count, 1000),
        "hundredStations" => P(trips.SelectMany(trip => new[] { trip.FromStation.Trim(), trip.ToStation.Trim() }).Where(value => value.Length > 0).Distinct(StringComparer.Ordinal).Count(), 100),
        "thousandCities" => P(StationCount(trips), 2500),
        "thousandKilometers" => P(trips.Select(trip => trip.MileageKm).DefaultIfEmpty(0).Max(), 1000),
        "fourThousandKmJourney" => P(trips.Select(trip => trip.MileageKm).DefaultIfEmpty(0).Max(), 4000),
        "airRail" => P(AirportStationCount(trips), 3),
        "lonelyPlanet" => P(CollectedCount(trips, trip => MatchingRoutes(trip, ["若和铁路", "格库线"])), 2),
        "hundredThousandKilometers" => P(trips.Where(trip => trip.MileageKm > 0).Sum(trip => trip.MileageKm), 100000),
        "travelAllMountains" => P(trips.Where(trip => trip.MileageKm > 0).Sum(trip => trip.MileageKm), 500000),
        "fiftyThousandSpending" => P(trips.Sum(trip => trip.Price), 50000),
        "reviewedTrainNumbers" => P(reviews.Count, 200),
        "reviewReplies5000" => P(context?.TotalReviewReactions ?? 0, 5000),
        "reviewReplies100000" => P(context?.TotalReviewReactions ?? 0, 100000),
        "reachLevel3" => P(context?.TotalExperience ?? 0, 125),
        "reachLevel5" => P(context?.TotalExperience ?? 0, 450),
        "reachLevel6" => P(context?.TotalExperience ?? 0, 800),
        "reach2500Experience" => P(context?.TotalExperience ?? 0, 2500),
        "archaeologyTeam" => P(OldestTripAgeYears(trips, today, fifteenYearsAgo), 15),
        "tenNumericTrains" => P(trips.Count(trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^\d+$")), 10),
        "tripleTransfer" => P(MaxTransferCount(trips), 2),
        "grandSlam" => P(RailwayBureauCount(trips), RailwayBureaus.Count),
        "hundredPeople" => P(PassengerCompanyCount(trips), AllPassengerCompanies.Count),
        "unnecessaryExtra" => P(MaxSameTrainTicketChain(trips), 3),
        "multipleChoices" => P(MaxDistinctTrainCountForRoute(trips), 10),
        "cardinalStations" => P(MaxCardinalStationCount(trips), 5),
        "verticalChina" => P(VisitedStationCount(trips, ["漠河", "三亚"]), 2),
        "horizontalChina" => P(VisitedStationCount(trips, ["阿克陶", "抚远"]), 2),
        "skyAndSea" => P(VisitedStationCount(trips, ["雁石坪", "香港西九龙"]), 2),
        "fourExtremes" => P(VisitedStationCount(trips, ["漠河", "三亚", "阿克陶", "抚远"]), 4),
        "borderPorts" => P(
            VisitedStationCount(trips, ["阿拉山口", "二连", "满洲里", "绥芬河", "丹东", "崇左", "磨憨"]),
            7),
        "fourFamousNorths" => P(
            VisitedStationCount(trips, ["阳泉北", "盘锦北", "孝感北", "邵阳北"]),
            4),
        "acrossTheRealm" => P(CapitalCityCount(trips), CapitalCityNames.Count),
        "crowningGlory" => P(CapitalStationCount(trips), RequiredCapitalStationCount),
        "eastRedSunRises" => P(VisitedStationCount(trips, ["东方红", "太阳升"]), 2),
        "goddessYangtzeBridges" => SectionProgress(trips, YangtzeBridges),
        "muddyWavesSweepSky" => SectionProgress(trips, YellowRiverBridges),
        "mistyVastWaters" => SectionProgress(trips, SeaBayBridges),
        "qinlingPassage" => SectionProgress(trips, QinlingPassages, 5),
        "tunnelCollection" => SectionProgress(trips, Tunnels),
        "completeEmuFleet" => P(CompleteEmuFamilyCount(trips), 1),
        "dreamExpress" => P(
            CollectedCount(trips, trip => RollingStockMatches(trip.RollingStock, DistributedSleeperEmuModels)),
            DistributedSleeperEmuModels.Count),
        "standingTall" => P(
            MaxDurationHours(trips.Where(trip => (IsNoSeat(trip) || NormalizedSeatType(trip.SeatType) == "硬座") &&
                HasNonAirConditionedCoach(trip.RollingStock))),
            24),
        "envoyArrival" => P(ForeignCapitalCount(trips), 3),
        "differentRoutesSameDestination" => P(MaxDifferentRoutesSameDestination(trips), 3),
        "completeTrainLetters" => P(trips.Select(trip => CommonTrainCategory(trip.TrainNumber)).Where(value => value is not null).Distinct(StringComparer.Ordinal).Count(), CommonTrainCategories.Count),
        "blueHorizon" => P(trips.Count(trip => ContainsRollingStock(trip, "CR200J")), 10),
        "flowersAmong" => P(
            CollectedCount(trips, trip => SmallEmuMatches(trip.RollingStock)),
            EmuModelFamilies.Sum(family => family.Models.Count)),
        "refinedMechanic" => P(
            CollectedCount(trips, trip => RollingStockMatches(trip.RollingStock, ModernLocomotives)),
            ModernLocomotives.Count),
        "dawnBreaks" => P(
            CollectedCount(trips, trip => RollingStockMatches(trip.RollingStock, DongfengShaoshanLocomotives)),
            DongfengShaoshanLocomotives.Count),
        "traverseOneRegion" => P(UniqueRouteMileage(trips), 5000),
        "halfTheRealm" => P(UniqueRouteMileage(trips), 80000),
        "centuryDreamFulfilled" => P(UniqueRouteMileage(trips), 160000),
        "spendsLikeWater" => P(
            trips.Select(trip => trip.Price).DefaultIfEmpty(0).Max(), 2000),
        "wealthyTraveler" => P(MaxThirtyDaySpending(trips), 10000),
        "richerThanNation" => P(MaxThirtyDaySpending(trips), 50000),
        "fourThousandKmInDay" => P(MaxRolling24HourMileage(trips), 4000),
        "hundredDeparturesFromStation" => P(MaxStationDepartureCount(trips), 100),
        "thousandDeparturesFromStation" => P(MaxStationDepartureCount(trips), 1000),
        "luxuryStreak2" => P(LuxuryStreakCount(trips), 2),
        "luxuryStreak20" => P(LuxuryStreakCount(trips), 20),
        "multipleLocomotives" => P(MaxLocomotiveCount(trips), 2),
        "relayLocomotives" => P(MaxLocomotiveChangeCount(trips), 3),
        "substituteSeats" => P(trips.Count(trip => IsSubstituteSeat(trip.SeatType)), 3),
        "extraCarriage" => P(trips.Count(trip => HasExtraCarriage(trip.SeatNumber)), 1),
        "specialGift" => P(trips.Count(UnlocksSpecialGift), 1),
        "pitchDark" => P(MaxDurationHours(trips.Where(trip => IsBoxcarSeat(trip.SeatType))) * 60, 30),
        "drippingStone" => P(MaxThirtyDayRedemptionCount(trips), 10),
        "fourOfAKind" => P(trips.Count(trip => HasQuadrupleSetNumber(trip.RollingStock)), 1),
        "allAlone" => P(trips.Count(UnlocksAllAlone), 1),
        "misfortuneTwice" => P(MaxEmuFormationChangeCount(trips), 2),
        "roamFreely" => P(RouteCatalogCount(trips), Math.Max(1, RouteStations.Value.Count)),
        _ => null
    };

    private static AchievementProgress P(double current, double target) =>
        new(Math.Clamp(current, 0, target), target);

    private static IReadOnlyList<AchievementRequirement>? RequirementsFor(
        string id,
        List<PublicTrip> trips) => id switch
    {
        "all25Series" => RollingStockRequirements(
            trips,
            new[] { "25B", "25G", "25Z", "25K", "25T", "25DT" }
                .Select(model => new RollingStockTarget(model))),
        "allEmuSeries" => CollectionRequirements(
            trips,
            EmuModelFamilies.Select(family => (Key: family.Series, Label: family.Series)),
            trip => EmuMatches(trip.RollingStock)),
        "allSeatTypes" => CollectionRequirements(
            trips,
            new[]
            {
                "无座", "硬座", "软座", "二等座", "一等座", "特等座", "优选一等座", "商务座",
                "硬卧", "软卧", "二等卧", "一等卧", "高级软卧", "动卧", "高级动卧"
            }.Select(seat => (Key: seat, Label: seat)),
            SeatTypeMatches),
        "lonelyPlanet" => RouteRequirements(trips, ["若和铁路", "格库线"]),
        "verticalChina" => StationRequirements(trips, ["漠河", "三亚"]),
        "horizontalChina" => StationRequirements(trips, ["阿克陶", "抚远"]),
        "skyAndSea" => StationRequirements(trips, ["雁石坪", "香港西九龙"]),
        "fourExtremes" => StationRequirements(trips, ["漠河", "三亚", "阿克陶", "抚远"]),
        "borderPorts" => StationRequirements(
            trips,
            ["阿拉山口", "二连", "满洲里", "绥芬河", "丹东", "崇左", "磨憨"]),
        "fourFamousNorths" => StationRequirements(
            trips,
            ["阳泉北", "盘锦北", "孝感北", "邵阳北"]),
        "eastRedSunRises" => StationRequirements(trips, ["东方红", "太阳升"]),
        "acrossTheRealm" => CollectionRequirements(
            trips,
            CapitalCityNames.Select(city => (Key: city, Label: city)),
            trip => CapitalCitiesFor(trip)),
        "completeTrainLetters" => CollectionRequirements(
            trips,
        [
            (Key: "G", Label: "G 字头"),
            (Key: "D", Label: "D 字头"),
            (Key: "C", Label: "C 字头"),
            (Key: "S", Label: "S 字头"),
            (Key: "Z", Label: "Z 字头"),
            (Key: "T", Label: "T 字头"),
            (Key: "K", Label: "K 字头"),
            (Key: "Y", Label: "Y 字头"),
            (Key: "numeric", Label: "纯数字车次")
        ],
            trip => CommonTrainCategory(trip.TrainNumber) is { } category
                ? [category]
                : []),
        "grandSlam" => CollectionRequirements(
            trips,
            RailwayBureaus.Keys.Select(bureau => (Key: bureau, Label: bureau)),
            trip =>
            {
                var company = trip.CompanyName?.Trim() ?? string.Empty;
                var bureau = RailwayBureaus.FirstOrDefault(entry => entry.Value.Contains(company)).Key;
                return bureau is null ? [] : [bureau];
            }),
        "dreamExpress" => RollingStockRequirements(
            trips,
            DistributedSleeperEmuModels.OrderBy(model => model, StringComparer.Ordinal)
                .Select(model => new RollingStockTarget(model))),
        "railwayTrailblazer" => RollingStockRequirements(trips, EarlyEmuModels),
        "whatAgeIsThis" => RollingStockRequirements(trips, EarlyPassengerCoachModels),
        "revivalPrototype" => RollingStockRequirements(trips, PrototypeModels),
        "lkjEquippedEmu" => RollingStockRequirements(trips, LkjEquippedEmuModels),
        "meritAndHonor" => RollingStockRequirements(trips, HonorLocomotives),
        "friendshipForever" => RollingStockRequirements(trips, EarlyImportedLocomotives),
        "steamPower" => RollingStockRequirements(trips, SteamLocomotives),
        "goddessYangtzeBridges" => SectionRequirements(trips, AvailableSections(YangtzeBridges)),
        "muddyWavesSweepSky" => SectionRequirements(trips, AvailableSections(YellowRiverBridges)),
        "mistyVastWaters" => SectionRequirements(trips, AvailableSections(SeaBayBridges)),
        "qinlingPassage" => SectionRequirements(trips, AvailableSections(QinlingPassages)),
        "tunnelCollection" => SectionRequirements(trips, AvailableSections(Tunnels)),
        "flowersAmong" => CollectionRequirements(
            trips,
            EmuModelFamilies.SelectMany(family => family.Models)
                .Select(model => (Key: model, Label: model)),
            trip => SmallEmuMatches(trip.RollingStock)),
        "refinedMechanic" => CollectionRequirements(
            trips,
            ModernLocomotives.OrderBy(model => model, StringComparer.Ordinal)
                .Select(model => (Key: model, Label: model)),
            trip => RollingStockMatches(trip.RollingStock, ModernLocomotives)),
        "dawnBreaks" => CollectionRequirements(
            trips,
            DongfengShaoshanLocomotives.OrderBy(model => model, StringComparer.Ordinal)
                .Select(model => (Key: model, Label: model)),
            trip => RollingStockMatches(trip.RollingStock, DongfengShaoshanLocomotives)),
        "hundredPeople" => CollectionRequirements(
            trips,
            AllPassengerCompanies.OrderBy(company => company, StringComparer.Ordinal)
                .Select(company => (Key: company, Label: company)),
            trip =>
            {
                var company = trip.CompanyName?.Trim() ?? string.Empty;
                return AllPassengerCompanies.Where(candidate =>
                    company.Contains(candidate, StringComparison.Ordinal));
            }),
        "roamFreely" => RouteCatalogRequirements(trips),
        _ => null
    };

    private static IReadOnlyList<AchievementRequirement> CollectionRequirements(
        List<PublicTrip> trips,
        IEnumerable<(string Key, string Label)> targets,
        Func<PublicTrip, IEnumerable<string>> keysForTrip)
    {
        var entries = targets
            .GroupBy(target => target.Key, StringComparer.Ordinal)
            .Select(group => group.First())
            .ToList();
        var targetKeys = entries
            .Select(target => target.Key)
            .ToHashSet(StringComparer.Ordinal);
        var completedTrips = new Dictionary<string, PublicTrip>(StringComparer.Ordinal);
        foreach (var trip in trips)
        {
            foreach (var key in keysForTrip(trip))
            {
                if (targetKeys.Contains(key))
                    completedTrips.TryAdd(key, trip);
            }
        }

        return entries
            .Select(target => new AchievementRequirement(
                target.Key,
                target.Label,
                completedTrips.GetValueOrDefault(target.Key)))
            .ToList();
    }

    private static IReadOnlyList<AchievementRequirement> StationRequirements(
        List<PublicTrip> trips,
        IEnumerable<string> stations) =>
        CollectionRequirements(
            trips,
            stations.Select(station =>
            {
                var normalized = NormalizedStation(station);
                return (Key: normalized, Label: $"{normalized}站");
            }),
            trip => new[] { trip.FromStation, trip.ToStation }.Select(NormalizedStation));

    private static IReadOnlyList<AchievementRequirement> RouteRequirements(
        List<PublicTrip> trips,
        IEnumerable<string> routes) =>
        CollectionRequirements(
            trips,
            routes.Select(route => (Key: route, Label: route)),
            trip => MatchingRoutes(trip, routes));

    /// <summary>行程里哪些要求的线路被走到了。旧名与新名都认（若和铁路 / 若和线）。</summary>
    private static IEnumerable<string> MatchingRoutes(
        PublicTrip trip,
        IEnumerable<string> routes)
    {
        var routeNames = RouteNames(trip).ToList();
        return routes.Where(route => routeNames.Any(name =>
            name.Contains(route, StringComparison.Ordinal) || RouteNameMatches(name, route)));
    }

    private static IReadOnlyList<AchievementRequirement> RollingStockRequirements(
        List<PublicTrip> trips,
        IEnumerable<RollingStockTarget> targets)
    {
        var values = targets.ToList();
        return CollectionRequirements(
            trips,
            values.Select(target => (
                Key: RollingStockTargetKey(target),
                Label: RollingStockTargetLabel(target))),
            trip => RollingStockMatches(trip.RollingStock, values)
                .Select(RollingStockTargetKey));
    }

    private static string RollingStockTargetKey(RollingStockTarget target) =>
        target.Number is null ? target.Model : $"{target.Model}-{target.Number}";

    private static string RollingStockTargetLabel(RollingStockTarget target) =>
        RollingStockTargetKey(target);

    private static IReadOnlyList<AchievementRequirement> SectionRequirements(
        List<PublicTrip> trips,
        IReadOnlyList<RailwaySection> availableSections)
    {
        // 同名区段可能有多条走法（天兴洲：京广高铁 / 滠武线；大胜关：京沪高速线 / 宁蓉线……）。
        // 去重只用于展示，判定必须遍历全部走法，否则只认表里排在前面的那一条。
        return CollectionRequirements(
            trips,
            availableSections
                .GroupBy(section => section.Name, StringComparer.Ordinal)
                .Select(group => (Key: group.Key, Label: group.Key)),
            trip =>
            {
                var segments = RouteSpans(trip);
                return availableSections
                    .Where(section => segments.Any(segment => CoversRouteSection(segment, section)))
                    .Select(section => section.Name);
            });
    }

    private static IReadOnlyList<AchievementRequirement> RouteCatalogRequirements(
        List<PublicTrip> trips)
    {
        return CollectionRequirements(
            trips,
            RouteStations.Value.Keys.Order(StringComparer.Ordinal)
                .Select(route => (Key: route, Label: route)),
            trip => RouteNames(trip).SelectMany(CatalogRoutesFor));
    }

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

    private static int CollectedCount<T>(
        IEnumerable<PublicTrip> trips,
        Func<PublicTrip, IEnumerable<T>> valuesForTrip) =>
        trips.SelectMany(valuesForTrip).Distinct().Count();

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

    private static int StationCount(IEnumerable<PublicTrip> trips) => trips
        .SelectMany(trip => new[] { trip.FromStation, trip.ToStation })
        .Select(NormalizedStation)
        .Where(station => station.Length > 0)
        .Distinct(StringComparer.Ordinal)
        .Count();

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

    private static int PassengerCompanyCount(IEnumerable<PublicTrip> trips) => trips
        .Select(trip => trip.CompanyName?.Trim() ?? string.Empty)
        .Where(company => company.Length > 0)
        .SelectMany(company => AllPassengerCompanies.Where(candidate =>
            company.Contains(candidate, StringComparison.Ordinal)))
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

    private static DateTime Departure(PublicTrip trip) => trip.DepartureTime ?? trip.CreatedAt;

    private static bool IsRomanticDate(DateTime value) =>
        value is { Month: 5, Day: 20 } or { Month: 2, Day: 14 } || IsQixi(value);

    private static bool IsQixi(DateTime value)
    {
        try
        {
            return ChineseCalendar.GetMonth(value) == 7 &&
                ChineseCalendar.GetDayOfMonth(value) == 7;
        }
        catch (ArgumentOutOfRangeException)
        {
            return false;
        }
    }

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
        var expected = models.ToHashSet(StringComparer.Ordinal);
        return RollingStockModelCodes(value)
            .Where(expected.Contains)
            .ToHashSet(StringComparer.Ordinal);
    }

    private static bool RollingStockMatches(string? value, RollingStockTarget target) =>
        TrainModelParser.ParseTrainString(value).Any(parsed =>
            RollingStockModelMatches(parsed, target.Model) &&
            (target.Number is null ||
             parsed.Numbers.Contains(target.Number, StringComparer.OrdinalIgnoreCase)));

    private static HashSet<RollingStockTarget> RollingStockMatches(
        string? value,
        IEnumerable<RollingStockTarget> targets) =>
        targets.Where(target => RollingStockMatches(value, target)).ToHashSet();

    private static bool RollingStockModelMatches(TrainModelParseResult parsed, string model) =>
        parsed.ModelCode.Equals(model, StringComparison.OrdinalIgnoreCase) ||
        parsed.Model.Equals(model, StringComparison.OrdinalIgnoreCase);

    private static IEnumerable<string> RollingStockModelCodes(string? value)
    {
        foreach (var parsed in TrainModelParser.ParseTrainString(value))
        {
            if (parsed.ModelCode.Length > 0)
                yield return parsed.ModelCode.ToUpperInvariant();
            if (parsed.Model.Length > 0 && !parsed.Model.Equals(parsed.ModelCode, StringComparison.Ordinal))
                yield return parsed.Model.ToUpperInvariant();
        }
    }

    private static PublicTrip? FirstRollingStockMatch(
        List<PublicTrip> trips,
        IEnumerable<RollingStockTarget> targets)
    {
        var values = targets.ToHashSet();
        return First(trips, trip => RollingStockMatches(trip.RollingStock, values).Count > 0);
    }

    /// <summary>至少收集到 <paramref name="required"/> 个不同车组时返回该次行程。</summary>
    private static PublicTrip? FirstPartialRollingStockCompletion(
        List<PublicTrip> trips,
        IReadOnlyList<RollingStockTarget> targets,
        int required)
    {
        var collected = new HashSet<RollingStockTarget>();
        foreach (var trip in trips)
        {
            collected.UnionWith(RollingStockMatches(trip.RollingStock, targets));
            if (collected.Count >= required) return trip;
        }
        return null;
    }

    private static bool ContainsRollingStock(PublicTrip trip, string value) =>
        RollingStockModelCodes(trip.RollingStock)
            .Any(code => code.Contains(value.ToUpperInvariant(), StringComparison.Ordinal));

    private static bool HasNonAirConditionedCoach(string? value) =>
        TrainModelParser.ParseTrainString(value)
            .Any(model => model.Category == TrainCategory.Coach &&
                NonAirConditionedCoaches.TryGetValue(model.Prefix, out var models) &&
                models.Contains(model.Model));

    /// <summary>重联须发生在同一编组内：跨编组的两个车组号只是中途换了编组，
    /// 不算重联。</summary>
    private static bool HasCoupledEmu(string? value) =>
        TrainModelParser.ParseTrainFormations(value)
            .Any(formation => formation.Any(model =>
                model.Category == TrainCategory.EMU && model.Numbers.Count > 1));

    /// <summary>“换挂”：相邻两个编组之间机车车组完全不同、客车完全相同，且都不含动车组。
    /// 换的是机车本身，所以同一型号换车号（SS8 0001 → SS8 0002）也算，只要没有一台车
    /// 两边都在。</summary>
    private static int LocomotiveChangeCount(string? value)
    {
        var formations = TrainModelParser.ParseTrainFormations(value);
        var count = 0;
        for (var index = 1; index < formations.Count; index++)
            if (IsLocomotiveChange(formations[index - 1], formations[index]))
                count++;
        return count;
    }

    private static bool IsLocomotiveChange(
        IEnumerable<TrainModelParseResult> before,
        IEnumerable<TrainModelParseResult> after)
    {
        if (before.Any(model => model.Category == TrainCategory.EMU) ||
            after.Any(model => model.Category == TrainCategory.EMU))
            return false;
        var beforeLocomotives = LocomotiveIdentities(before);
        var afterLocomotives = LocomotiveIdentities(after);
        if (beforeLocomotives.Count == 0 || afterLocomotives.Count == 0) return false;
        if (beforeLocomotives.Overlaps(afterLocomotives)) return false;
        var beforeCoaches = CoachIdentities(before);
        return beforeCoaches.Count > 0 && beforeCoaches.SetEquals(CoachIdentities(after));
    }

    private static int MaxLocomotiveChangeCount(IEnumerable<PublicTrip> trips) => trips
        .Select(trip => LocomotiveChangeCount(trip.RollingStock))
        .DefaultIfEmpty(0)
        .Max();

    /// <summary>“厄运成双”的换编组：相邻两个含动车组的编组车组号不同即算一次。与
    /// <see cref="HasCoupledEmu"/> 相反，跨编组的不同车组号正是这里要找的东西。</summary>
    private static int EmuFormationChangeCount(string? value)
    {
        var formations = TrainModelParser.ParseTrainFormations(value)
            .Select(EmuIdentities)
            .Where(identities => identities.Count > 0)
            .ToList();
        var count = 0;
        for (var index = 1; index < formations.Count; index++)
            if (!formations[index - 1].SetEquals(formations[index]))
                count++;
        return count;
    }

    private static int MaxEmuFormationChangeCount(IEnumerable<PublicTrip> trips) => trips
        .Select(trip => EmuFormationChangeCount(trip.RollingStock))
        .DefaultIfEmpty(0)
        .Max();

    private static HashSet<string> LocomotiveIdentities(IEnumerable<TrainModelParseResult> formation) =>
        formation
            .Where(model => model.Category == TrainCategory.Locomotive)
            .SelectMany(RollingStockIdentities)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

    private static HashSet<string> CoachIdentities(IEnumerable<TrainModelParseResult> formation) =>
        formation
            .Where(model => model.Category == TrainCategory.Coach)
            .SelectMany(RollingStockIdentities)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

    private static HashSet<string> EmuIdentities(IEnumerable<TrainModelParseResult> formation) =>
        formation
            .Where(model => model.Category == TrainCategory.EMU)
            .SelectMany(RollingStockIdentities)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

    /// <summary>一个车型段的具体身份：有车号就是“型号 车号”，没车号就只是型号。</summary>
    private static IEnumerable<string> RollingStockIdentities(TrainModelParseResult model)
    {
        var code = model.ModelCode.Length > 0 ? model.ModelCode : model.Model;
        return model.Numbers.Count > 0
            ? model.Numbers.Select(number => $"{code} {number}")
            : [code];
    }

    /// <summary>代用席位：席别里带“代”即可（“硬卧代硬座”“硬座代卧铺”都算）。</summary>
    private static bool IsSubstituteSeat(string? value) => (value ?? string.Empty).Contains('代');

    /// <summary>棚车代客：席别里出现“棚车”即可。棚车不在席别下拉表里，只能靠导入或
    /// 手填进来，落库形态不确定（“棚车”“棚车代硬座”都可能），所以按包含判定。</summary>
    private static bool IsBoxcarSeat(string? value) => (value ?? string.Empty).Contains("棚车");

    /// <summary>加挂车厢：座位号的车厢段写成“加X车”。车厢未知时 App 读写都不保留这个
    /// 前缀，所以历史数据里残留的“加0车”不算加挂。</summary>
    private static bool HasExtraCarriage(string? value)
    {
        var match = Regex.Match(value ?? string.Empty, @"^\s*加(\d+)车");
        return match.Success && match.Groups[1].Value.TrimStart('0').Length > 0;
    }

    private static PublicTrip? FirstRepeatedTripCompletion(List<PublicTrip> trips, int target)
    {
        var counts = new Dictionary<RepeatedTripKey, int>();
        foreach (var trip in trips)
        {
            var key = RepeatedTripKeyFor(trip);
            var count = counts.GetValueOrDefault(key) + 1;
            counts[key] = count;
            if (count >= target) return trip;
        }
        return null;
    }

    private static PublicTrip? FirstUniqueRouteMileageCompletion(
        List<PublicTrip> trips, double target)
    {
        var sections = new HashSet<RouteSectionKey>();
        var mileage = 0d;
        foreach (var trip in trips)
        {
            foreach (var segment in RouteSegments(trip))
            {
                if (segment.MileageKm <= 0 || !sections.Add(RouteSectionKeyFor(segment))) continue;
                mileage += segment.MileageKm;
            }
            if (mileage >= target) return trip;
        }
        return null;
    }

    private static double UniqueRouteMileage(List<PublicTrip> trips)
    {
        var sections = new HashSet<RouteSectionKey>();
        var mileage = 0d;
        foreach (var segment in trips.SelectMany(RouteSegments))
        {
            if (segment.MileageKm <= 0 || !sections.Add(RouteSectionKeyFor(segment))) continue;
            mileage += segment.MileageKm;
        }
        return mileage;
    }

    private static RouteSectionKey RouteSectionKeyFor(RouteSegment segment)
    {
        var first = NormalizedStation(segment.FromStation);
        var second = NormalizedStation(segment.ToStation);
        if (StringComparer.Ordinal.Compare(first, second) > 0) (first, second) = (second, first);
        return new RouteSectionKey(CanonicalRouteName(segment.RouteName), first, second);
    }

    private static RepeatedTripKey RepeatedTripKeyFor(PublicTrip trip)
    {
        var departure = trip.DepartureTime;
        var arrival = trip.ArrivalTime;
        return new RepeatedTripKey(
            trip.TrainNumber.Trim().ToUpperInvariant(),
            RollingStockModel(trip.RollingStock),
            trip.CompanyName?.Trim() ?? string.Empty,
            trip.FromStation.Trim(),
            trip.ToStation.Trim(),
            departure?.TimeOfDay,
            arrival?.TimeOfDay,
            departure is null || arrival is null ? null : (arrival.Value.Date - departure.Value.Date).Days,
            trip.MileageKm,
            trip.ViaRoutes.Trim(),
            trip.SeatType?.Trim() ?? string.Empty,
            trip.SeatNumber?.Trim() ?? string.Empty,
            trip.Price);
    }

    private static string RollingStockModel(string? value)
    {
        var models = TrainModelParser.ParseTrainString(value)
            .Select(model => model.ModelCode.ToUpperInvariant())
            .Where(model => model.Length > 0)
            .ToArray();
        return models.Length == 0 ? string.Empty : string.Join('+', models);
    }

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
        var models = RollingStockModelCodes(value).ToHashSet(StringComparer.OrdinalIgnoreCase);
        return EmuModelFamilies
            .Where(family => family.Models.Any(models.Contains))
            .Select(family => family.Series)
            .ToHashSet(StringComparer.Ordinal);
    }

    private static HashSet<string> SmallEmuMatches(string? value)
    {
        var models = RollingStockModelCodes(value).ToHashSet(StringComparer.OrdinalIgnoreCase);
        return EmuModelFamilies
            .SelectMany(family => family.Models)
            .Where(models.Contains)
            .ToHashSet(StringComparer.Ordinal);
    }

    /// <summary>行程里出现的 (子型号, 车组号) 对。车组号按十进制整数归一，故附表里的
    /// "0207" 与 "207" 视作同一车组；解析不出数字的条目直接丢弃。</summary>
    private static IEnumerable<(string Model, int Number)> EmuSetNumbers(string? value)
    {
        foreach (var parsed in TrainModelParser.ParseTrainString(value))
        {
            if (parsed.Category != TrainCategory.EMU) continue;
            var model = parsed.ModelCode.Length > 0 ? parsed.ModelCode : parsed.Model;
            if (model.Length == 0) continue;
            foreach (var number in parsed.Numbers)
                if (int.TryParse(number, out var setNumber))
                    yield return (model, setNumber);
        }
    }

    private static Dictionary<string, HashSet<int>> CoveredEmuSets(IEnumerable<PublicTrip> trips)
    {
        var covered = new Dictionary<string, HashSet<int>>(StringComparer.OrdinalIgnoreCase);
        foreach (var trip in trips)
            foreach (var (model, number) in EmuSetNumbers(trip.RollingStock))
            {
                if (!covered.TryGetValue(model, out var numbers))
                    covered[model] = numbers = [];
                numbers.Add(number);
            }
        return covered;
    }

    /// <summary>该子型号的全部载客车组是否都坐过（附表6 的区间须被完整覆盖）。</summary>
    private static bool IsFleetComplete(string model, IReadOnlySet<int> numbers) =>
        EmuSetCatalog.TryGetValue(model, out var spans) &&
        spans.Count > 0 &&
        spans.All(span => Enumerable
            .Range(span.From, span.To - span.From + 1)
            .All(numbers.Contains));

    /// <summary>该大类下全部子型号是否都已集齐。没在附表6 里登记的子型号不参与判定，
    /// 免得某个大类被一个无据可查的型号永久卡死。</summary>
    private static bool IsFamilyFleetComplete(
        EmuModelFamily family,
        IReadOnlyDictionary<string, HashSet<int>> covered)
    {
        var catalogued = family.Models.Where(EmuSetCatalog.ContainsKey).ToArray();
        return catalogued.Length > 0
            && catalogued.All(model =>
                covered.TryGetValue(model, out var numbers) && IsFleetComplete(model, numbers));
    }

    private static int CompleteEmuFamilyCount(IEnumerable<PublicTrip> trips)
    {
        var covered = CoveredEmuSets(trips);
        return EmuModelFamilies.Count(family => IsFamilyFleetComplete(family, covered));
    }

    private static PublicTrip? FirstCompleteEmuFamily(List<PublicTrip> trips)
    {
        var covered = new Dictionary<string, HashSet<int>>(StringComparer.OrdinalIgnoreCase);
        var complete = new HashSet<EmuModelFamily>();
        foreach (var trip in trips)
        {
            var touched = new HashSet<EmuModelFamily>();
            foreach (var (model, number) in EmuSetNumbers(trip.RollingStock))
            {
                if (!covered.TryGetValue(model, out var numbers))
                    covered[model] = numbers = [];
                if (numbers.Add(number) && EmuFamilyByModel.TryGetValue(model, out var family))
                    touched.Add(family);
            }
            foreach (var family in touched)
                if (!complete.Contains(family) && IsFamilyFleetComplete(family, covered))
                    complete.Add(family);
            if (complete.Count > 0) return trip;
        }
        return null;
    }

    /// <summary>“其利断金”要的是同时牵引，故按编组分别计数后取最大值：中途换挂
    /// 机车（各编组各一台）不算双机。机车上按台数计——同一型号写成两个车号
    /// （HXD1D 0001&amp;0002）就是两台重联机车。</summary>
    private static int LocomotiveCount(string? value) =>
        TrainModelParser.ParseTrainFormations(value)
            .Select(formation => formation
                .Where(model => model.Category == TrainCategory.Locomotive)
                .Sum(model => Math.Max(model.Numbers.Count, 1)))
            .DefaultIfEmpty(0)
            .Max();

    private static int MaxLocomotiveCount(IEnumerable<PublicTrip> trips) => trips
        .Select(trip => LocomotiveCount(trip.RollingStock))
        .DefaultIfEmpty(0)
        .Max();

    private static HashSet<string> SeatTypeMatches(PublicTrip trip)
    {
        // 无座是入座方式而不是席别，站票只点亮「无座」这一项，不再计入票面席别。
        if (IsNoSeat(trip)) return new HashSet<string>(StringComparer.Ordinal) { "无座" };
        var normalized = NormalizedSeatType(trip.SeatType);
        return RegularSeatTypes.Where(seat => seat == normalized).ToHashSet(StringComparer.Ordinal);
    }

    /// <summary>无座：座位号里带“无座”即算（“无座”“2车无座”“99车无座”），与席别无关。
    /// 旧数据里有把无座写进席别的（“无座”“二等座无座”），一并兼容。</summary>
    private static bool IsNoSeat(PublicTrip trip) =>
        (trip.SeatNumber ?? string.Empty).Contains("无座", StringComparison.Ordinal) ||
        (trip.SeatType ?? string.Empty).Contains("无座", StringComparison.Ordinal);

    private static string NormalizedSeatType(string? value)
    {
        var normalized = Regex.Replace(value?.Trim() ?? string.Empty, "[上中下]铺$", string.Empty);
        // 「车体席别代席别」（如硬卧代硬座）表示实际按后一个席别乘车，成就照后者判定。
        // 中文席别名不含「代」，所以不必维护白名单，取最后一个「代」之后即可。
        var proxy = normalized.LastIndexOf('代');
        return proxy > 0 && proxy < normalized.Length - 1 ? normalized[(proxy + 1)..] : normalized;
    }

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

    /// <summary>这趟行程到访的别国首都车站（按 ForeignCapitals 的键去重，同一城市的
    /// 多个车站只算一项）。</summary>
    private static HashSet<string> ForeignCapitalMatches(PublicTrip trip)
    {
        var stations = new[] { NormalizedStation(trip.FromStation), NormalizedStation(trip.ToStation) };
        return ForeignCapitals
            .Where(capital => capital.Aliases.Any(alias =>
                stations.Any(station => station.Contains(alias, StringComparison.Ordinal))))
            .Select(capital => capital.Key)
            .ToHashSet(StringComparer.Ordinal);
    }

    private static int ForeignCapitalCount(IEnumerable<PublicTrip> trips) =>
        trips.SelectMany(ForeignCapitalMatches).ToHashSet(StringComparer.Ordinal).Count;

    private static PublicTrip? FirstForeignCapitalCompletion(List<PublicTrip> trips, int target)
    {
        var visited = new HashSet<string>(StringComparer.Ordinal);
        foreach (var trip in trips)
        {
            visited.UnionWith(ForeignCapitalMatches(trip));
            if (visited.Count >= target) return trip;
        }
        return null;
    }

    /// <summary>这趟行程到访的附表5 车站（站名与旧站名都按归一化后精确比对）。</summary>
    private static IEnumerable<CapitalStation> CapitalStationsVisitedBy(PublicTrip trip)
    {
        var stations = new[] { NormalizedStation(trip.FromStation), NormalizedStation(trip.ToStation) };
        return CapitalStations.Where(capital =>
            stations.Any(station =>
                station == capital.Station ||
                capital.Aliases.Contains(station, StringComparer.Ordinal)));
    }

    private static HashSet<string> CapitalCitiesFor(PublicTrip trip) =>
        CapitalStationsVisitedBy(trip)
            .Select(capital => capital.City)
            .ToHashSet(StringComparer.Ordinal);

    private static HashSet<string> RequiredCapitalStationsFor(PublicTrip trip) =>
        CapitalStationsVisitedBy(trip)
            .Where(capital => capital.Required)
            .Select(capital => capital.Station)
            .ToHashSet(StringComparer.Ordinal);

    private static int CapitalCityCount(IEnumerable<PublicTrip> trips) =>
        trips.SelectMany(CapitalCitiesFor).ToHashSet(StringComparer.Ordinal).Count;

    private static int CapitalStationCount(IEnumerable<PublicTrip> trips) =>
        trips.SelectMany(RequiredCapitalStationsFor).ToHashSet(StringComparer.Ordinal).Count;

    private static PublicTrip? FirstCapitalCityCompletion(List<PublicTrip> trips, int target) =>
        FirstCollectedCompletion(trips, CapitalCitiesFor, target);

    private static PublicTrip? FirstCapitalStationCompletion(List<PublicTrip> trips, int target) =>
        FirstCollectedCompletion(trips, RequiredCapitalStationsFor, target);

    private static PublicTrip? FirstCollectedCompletion(
        List<PublicTrip> trips,
        Func<PublicTrip, HashSet<string>> collectedBy,
        int target)
    {
        var collected = new HashSet<string>(StringComparer.Ordinal);
        foreach (var trip in trips)
        {
            collected.UnionWith(collectedBy(trip));
            if (collected.Count >= target) return trip;
        }
        return null;
    }

    /// <summary>「四重存在」：车组号为四位相同数字（1111、2222、5555…）。</summary>
    private static bool HasQuadrupleSetNumber(string? value) =>
        TrainModelParser.ParseTrainString(value).Any(parsed =>
            parsed.Category == TrainCategory.EMU &&
            parsed.Numbers.Any(number =>
                number.Length == 4 && number.All(digit => digit == number[0])));

    private static bool UnlocksAllAlone(PublicTrip trip) =>
        HasLonelyCarriage(trip.RollingStock) || RidesEleventhCarriageOf1111(trip);

    /// <summary>「茕茕孑立」的第一种解锁方式：坐过车号 111111 的 RZ25K 车厢。</summary>
    private static bool HasLonelyCarriage(string? value) =>
        RollingStockMatches(value, new RollingStockTarget("RZ25K", "111111"));

    /// <summary>第二种解锁方式：坐 CR400AF-AS-1111 的 11 车厢。车组号同样按
    /// RollingStockTarget 判，只有座位号里的车厢段是另一条线（车组号对了还得在 11 车）。</summary>
    private static bool RidesEleventhCarriageOf1111(PublicTrip trip) =>
        CarriageNumber(trip.SeatNumber) == 11 &&
        RollingStockMatches(trip.RollingStock, new RollingStockTarget("CR400AF-AS", "1111"));

    /// <summary>座位号里的车厢号（“11车11号”）。加挂车厢单独编号、不属于车组的第 11 车厢，
    /// 所以“加X车”一律不算。</summary>
    private static int? CarriageNumber(string? value)
    {
        var match = Regex.Match(value ?? string.Empty, @"^\s*(\d+)\s*车");
        return match.Success && int.TryParse(match.Groups[1].Value, out var carriage)
            ? carriage
            : null;
    }

    /// <summary>座位号里的座号（“11车11A”取 11，后缀不限）。</summary>
    private static int? SeatNumberInCarriage(string? value)
    {
        var seat = Regex.Replace(value ?? string.Empty, @"^\s*加?\d+\s*车", string.Empty);
        var match = Regex.Match(seat, @"^\s*(\d+)");
        return match.Success && int.TryParse(match.Groups[1].Value, out var number)
            ? number
            : null;
    }

    /// <summary>「茕茕孑立」的附加经验：解锁那趟行程的座号是 11，或乘车日期是 11 月 11 日，
    /// 每满足一项加 10 点（总上限由定义的 MaxExperience 兜底）。</summary>
    private static int AllAloneBonus(List<PublicTrip> trips)
    {
        if (First(trips, UnlocksAllAlone) is not { } trip) return 0;
        var bonus = 0;
        if (SeatNumberInCarriage(trip.SeatNumber) == 11) bonus += 10;
        var departure = Departure(trip);
        if (departure.Month == 11 && departure.Day == 11) bonus += 10;
        return bonus;
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

    private static double ShortestStationPairWindowDays(
        List<PublicTrip> trips,
        string first,
        string second)
    {
        var targets = new HashSet<string>(
            [NormalizedStation(first), NormalizedStation(second)],
            StringComparer.Ordinal);
        var latest = new Dictionary<string, StationVisit>(StringComparer.Ordinal);
        var shortest = double.MaxValue;
        foreach (var visit in StationVisits(trips))
        {
            if (!targets.Contains(visit.Station)) continue;
            latest[visit.Station] = visit;
            var other = targets.First(station => station != visit.Station);
            if (!latest.TryGetValue(other, out var otherVisit)) continue;
            var firstVisit = visit.Time <= otherVisit.Time ? visit : otherVisit;
            var secondVisit = visit.Time <= otherVisit.Time ? otherVisit : visit;
            shortest = Math.Min(shortest, (secondVisit.Time - firstVisit.Time).TotalDays);
        }
        return shortest == double.MaxValue ? 0 : shortest;
    }

    private static double ShortestFourExtremesWindowDays(List<PublicTrip> trips)
    {
        var targets = new HashSet<string>(
            ["漠河", "三亚", "阿克陶", "抚远"],
            StringComparer.Ordinal);
        var shortest = double.MaxValue;
        for (var end = 0; end < trips.Count; end++)
        {
            var endTime = Departure(trips[end]);
            var visited = new HashSet<string>(StringComparer.Ordinal);
            for (var start = end; start >= 0; start--)
            {
                if (endTime - Departure(trips[start]) > TimeSpan.FromDays(60)) break;
                foreach (var station in new[]
                         {
                             NormalizedStation(trips[start].FromStation),
                             NormalizedStation(trips[start].ToStation)
                         })
                    if (targets.Contains(station)) visited.Add(station);
                if (!targets.IsSubsetOf(visited)) continue;
                shortest = Math.Min(
                    shortest,
                    (endTime - Departure(trips[start])).TotalDays);
            }
        }
        return shortest == double.MaxValue ? 0 : shortest;
    }

    private static PublicTrip? FirstFourExtremesCompletion(
        List<PublicTrip> trips,
        TimeSpan maxWindow)
    {
        var targets = new HashSet<string>(
            ["漠河", "三亚", "阿克陶", "抚远"],
            StringComparer.Ordinal);
        for (var end = 0; end < trips.Count; end++)
        {
            var endTime = Departure(trips[end]);
            var visited = new HashSet<string>(StringComparer.Ordinal);
            for (var start = end; start >= 0; start--)
            {
                if (endTime - Departure(trips[start]) > maxWindow) break;
                foreach (var station in new[]
                         {
                             NormalizedStation(trips[start].FromStation),
                             NormalizedStation(trips[start].ToStation)
                         })
                    if (targets.Contains(station)) visited.Add(station);
            }
            if (targets.IsSubsetOf(visited)) return trips[end];
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

    private static PublicTrip? FirstCumulativeSpendingCompletion(
        List<PublicTrip> trips,
        double target)
    {
        var spending = 0d;
        foreach (var trip in trips)
        {
            spending += Math.Max(0, trip.Price);
            if (spending > target) return trip;
        }
        return null;
    }

    private static PublicTrip? FirstRolling24HourMileageCompletion(
        List<PublicTrip> trips,
        double target)
    {
        var ordered = trips.OrderBy(Departure).ThenBy(trip => trip.TicketId).ToList();
        for (var start = 0; start < ordered.Count; start++)
        {
            var startTime = Departure(ordered[start]);
            var mileage = 0d;
            for (var end = start; end < ordered.Count; end++)
            {
                if (Departure(ordered[end]) - startTime > TimeSpan.FromHours(24)) break;
                mileage += Math.Max(0, ordered[end].MileageKm);
                if (mileage > target) return ordered[end];
            }
        }
        return null;
    }

    private static double MaxRolling24HourMileage(List<PublicTrip> trips)
    {
        var ordered = trips.OrderBy(Departure).ThenBy(trip => trip.TicketId).ToList();
        var maximum = 0d;
        for (var start = 0; start < ordered.Count; start++)
        {
            var startTime = Departure(ordered[start]);
            var mileage = 0d;
            for (var end = start; end < ordered.Count; end++)
            {
                if (Departure(ordered[end]) - startTime > TimeSpan.FromHours(24)) break;
                mileage += Math.Max(0, ordered[end].MileageKm);
                maximum = Math.Max(maximum, mileage);
            }
        }
        return maximum;
    }

    private static PublicTrip? FirstLuxuryStreakCompletion(
        List<PublicTrip> trips,
        int target)
    {
        var streak = 0;
        foreach (var trip in trips)
        {
            streak = LuxurySeatTypes.Contains(NormalizedSeatType(trip.SeatType))
                ? streak + 1
                : 0;
            if (streak >= target) return trip;
        }
        return null;
    }

    private static int LuxuryStreakCount(List<PublicTrip> trips)
    {
        var streak = 0;
        var maximum = 0;
        foreach (var trip in trips)
        {
            streak = LuxurySeatTypes.Contains(NormalizedSeatType(trip.SeatType))
                ? streak + 1
                : 0;
            maximum = Math.Max(maximum, streak);
        }
        return maximum;
    }

    private static PublicTrip? FirstStationDepartureCompletion(
        IEnumerable<PublicTrip> trips,
        int target)
    {
        var counts = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var trip in trips)
        {
            var station = NormalizedStation(trip.FromStation);
            if (station.Length == 0) continue;
            var count = counts.GetValueOrDefault(station) + 1;
            counts[station] = count;
            if (count >= target) return trip;
        }
        return null;
    }

    private static int MaxStationDepartureCount(IEnumerable<PublicTrip> trips) => trips
        .Select(trip => NormalizedStation(trip.FromStation))
        .Where(station => station.Length > 0)
        .GroupBy(station => station, StringComparer.Ordinal)
        .Select(group => group.Count())
        .DefaultIfEmpty(0)
        .Max();

    private static PublicTrip? FirstThirtyDaySpendingCompletion(List<PublicTrip> trips, double target)
    {
        var ordered = trips.OrderBy(Departure).ThenBy(trip => trip.TicketId).ToList();
        for (var end = 0; end < ordered.Count; end++)
        {
            var endTime = Departure(ordered[end]);
            var total = 0d;
            for (var start = end; start >= 0; start--)
            {
                if (endTime - Departure(ordered[start]) > TimeSpan.FromDays(30)) break;
                total += ordered[start].Price;
            }
            if (total > target) return ordered[end];
        }
        return null;
    }

    private static double MaxThirtyDaySpending(List<PublicTrip> trips)
    {
        var ordered = trips.OrderBy(Departure).ToList();
        var maximum = 0d;
        for (var end = 0; end < ordered.Count; end++)
        {
            var endTime = Departure(ordered[end]);
            var total = 0d;
            for (var start = end; start >= 0; start--)
            {
                if (endTime - Departure(ordered[start]) > TimeSpan.FromDays(30)) break;
                total += ordered[start].Price;
            }
            maximum = Math.Max(maximum, total);
        }
        return maximum;
    }

    /// <summary>积分兑换没有单独字段，沿用「票价为 0 且里程超过 50 公里」的约定，
    /// 与「厚积薄发」对积分票的判定保持一致。</summary>
    private static bool IsRedeemedTicket(PublicTrip trip) =>
        trip.Price == 0 && trip.MileageKm > 50;

    private static PublicTrip? FirstThirtyDayRedemptionCompletion(List<PublicTrip> trips, int target)
    {
        var ordered = trips
            .Where(IsRedeemedTicket)
            .OrderBy(Departure)
            .ThenBy(trip => trip.TicketId)
            .ToList();
        for (var end = 0; end < ordered.Count; end++)
        {
            var endTime = Departure(ordered[end]);
            var count = 0;
            for (var start = end; start >= 0; start--)
            {
                if (endTime - Departure(ordered[start]) > TimeSpan.FromDays(30)) break;
                count++;
            }
            if (count >= target) return ordered[end];
        }
        return null;
    }

    private static int MaxThirtyDayRedemptionCount(List<PublicTrip> trips)
    {
        var ordered = trips
            .Where(IsRedeemedTicket)
            .OrderBy(Departure)
            .ToList();
        var maximum = 0;
        for (var end = 0; end < ordered.Count; end++)
        {
            var endTime = Departure(ordered[end]);
            var count = 0;
            for (var start = end; start >= 0; start--)
            {
                if (endTime - Departure(ordered[start]) > TimeSpan.FromDays(30)) break;
                count++;
            }
            maximum = Math.Max(maximum, count);
        }
        return maximum;
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
        var serialInStock = new[] { "2463", "2464", "2465" }
            .Any(number => RollingStockMatches(trip.RollingStock, new RollingStockTarget("CRH2E", number)));
        var train = WhitespaceRegex().Replace(trip.TrainNumber.Trim(), string.Empty);
        return serialInStock || train is "2463" or "2464" or "2465";
    }

    private static bool UnlocksSoundSleep(PublicTrip trip) =>
        NormalizedSeatType(trip.SeatType) is "高级软卧" or "高级动卧" &&
        (trip.SeatNumber?.Trim().Contains("下铺", StringComparison.Ordinal) ?? false);

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
            .Where(route => RouteNames(trip).Any(name =>
                name.Contains(route, StringComparison.Ordinal) || RouteNameMatches(name, route)))
            .ToHashSet(StringComparer.Ordinal));
    }

    private static int RouteCatalogCount(IEnumerable<PublicTrip> trips) => trips
        .SelectMany(RouteNames)
        .SelectMany(CatalogRoutesFor)
        .Distinct(StringComparer.Ordinal)
        .Count();

    private static PublicTrip? FirstRouteCatalogCompletion(IEnumerable<PublicTrip> trips)
    {
        var requiredCount = RouteStations.Value.Count;
        var covered = new HashSet<string>(StringComparer.Ordinal);
        foreach (var trip in trips)
        {
            foreach (var name in RouteNames(trip))
                foreach (var match in CatalogRoutesFor(name))
                    covered.Add(match);
            if (covered.Count >= requiredCount) return trip;
        }
        return null;
    }

    private static PublicTrip? FirstDifferentRoutesSameDestination(List<PublicTrip> trips)
    {
        var groups = new Dictionary<(string From, string To), HashSet<string>>();
        foreach (var trip in trips)
        {
            var from = NormalizedStation(trip.FromStation);
            var to = NormalizedStation(trip.ToStation);
            // 新旧线路名指同一条走法时不能算两种路线，否则同一趟车重录一次就能刷成就。
            var route = CanonicalRouteSignature(trip);
            if (from.Length == 0 || to.Length == 0 || route.Length == 0) continue;
            var key = string.CompareOrdinal(from, to) <= 0 ? (from, to) : (to, from);
            if (!groups.TryGetValue(key, out var routes))
                groups[key] = routes = new(StringComparer.Ordinal);
            if (routes.Add(route) && routes.Count >= 3) return trip;
        }
        return null;
    }

    private static int MaxDifferentRoutesSameDestination(List<PublicTrip> trips)
    {
        var groups = new Dictionary<(string From, string To), HashSet<string>>();
        foreach (var trip in trips)
        {
            var from = NormalizedStation(trip.FromStation);
            var to = NormalizedStation(trip.ToStation);
            var route = CanonicalRouteSignature(trip);
            if (from.Length == 0 || to.Length == 0 || route.Length == 0) continue;
            var key = string.CompareOrdinal(from, to) <= 0 ? (from, to) : (to, from);
            if (!groups.TryGetValue(key, out var routes))
                groups[key] = routes = new(StringComparer.Ordinal);
            routes.Add(route);
        }
        return groups.Values.Select(routes => routes.Count).DefaultIfEmpty(0).Max();
    }

    private static PublicTrip? FirstRailFerryCompletion(List<PublicTrip> trips)
    {
        for (var currentIndex = 0; currentIndex < trips.Count; currentIndex++)
        {
            var current = trips[currentIndex];
            if (RouteNames(current).Any(route => route.Contains("轮渡", StringComparison.Ordinal))) return current;
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

    private static bool UnlocksBorderCrossing(PublicTrip trip) => BorderCrossing(trip) is not null;

    private static PublicTrip? FirstDifferentBorderCompletion(List<PublicTrip> trips)
    {
        var visits = new List<(string Border, bool Entry, DateTime Time, PublicTrip Trip)>();
        foreach (var trip in trips)
        {
            if (BorderCrossing(trip) is not { } crossing) continue;
            visits.Add((
                crossing.Border,
                crossing.Entry,
                crossing.Entry ? Departure(trip) : (trip.ArrivalTime ?? Departure(trip)),
                trip));
        }
        visits.Sort((a, b) => a.Time != b.Time ? a.Time.CompareTo(b.Time) : a.Trip.TicketId.CompareTo(b.Trip.TicketId));
        foreach (var current in visits.Where(item => !item.Entry))
            if (visits.Any(previous => previous.Entry && previous.Border != current.Border && current.Time >= previous.Time && current.Time - previous.Time <= TimeSpan.FromDays(14)))
                return current.Trip;
        return null;
    }

    /// <summary>一次出入境：口岸站与方向（true 为入境）。</summary>
    private static (string Border, bool Entry)? BorderCrossing(PublicTrip trip)
    {
        var segments = RouteSegments(trip);
        if (segments.Count == 0) return null;

        // 中老铁路的磨万段连同万象这些境外站都在库里，「终点不在库」的端点规则对它不成立；
        // 跨过磨憨（境）本身就算出入境。只认昆磨段——磨万段是以磨憨（境）为起点的。
        foreach (var segment in segments)
        {
            if (segment.RouteName.Trim() is not ("中老昆万铁路昆磨段" or "昆万昆磨段")) continue;
            if (NormalizedStation(segment.ToStation) == "磨憨（境）") return ("磨憨（境）", false);
            if (NormalizedStation(segment.FromStation) == "磨憨（境）") return ("磨憨（境）", true);
        }

        // 存量行程里还留着旧库的合成边境线（丹东国境线等）；当前库也保留了这些线，按老办法认。
        foreach (var segment in segments)
        {
            if (!BorderRouteMarkers.Any(marker =>
                    segment.RouteName.Contains(marker, StringComparison.Ordinal))) continue;
            var border = BorderStationAt(segment.FromStation) ?? BorderStationAt(segment.ToStation);
            if (border is null) continue;
            var from = NormalizedStation(segment.FromStation);
            return (border, from.Contains("交接", StringComparison.Ordinal) ||
                from == "新义州" || from.Contains("（境）", StringComparison.Ordinal));
        }

        // 新库的口岸线只修到国境站：出境看最后一条在库线路是否止于口岸站、而行程终点不在库中，
        // 入境反过来看第一条在库线路。
        var last = segments.LastOrDefault(segment => ResolvesInCatalog(segment.RouteName));
        if (BorderStationAt(last?.ToStation) is { } exit && !IsKnownStation(trip.ToStation))
            return (exit, false);
        var first = segments.FirstOrDefault(segment => ResolvesInCatalog(segment.RouteName));
        if (BorderStationAt(first?.FromStation) is { } entry && !IsKnownStation(trip.FromStation))
            return (entry, true);
        return null;
    }

    private static bool ResolvesInCatalog(string routeName) => CatalogRoutesFor(routeName).Count > 0;

    private static string? BorderStationAt(string? station)
    {
        var normalized = NormalizedStation(station ?? string.Empty);
        if (normalized.Length == 0) return null;
        if (normalized is "磨憨" or "磨憨（境）") return "磨憨（境）";
        return BorderStationNames.FirstOrDefault(name =>
            string.Equals(name, normalized, StringComparison.Ordinal));
    }

    /// <summary>行程里的站名是否出现在线路库中——口岸线止于国境站，境外站都不在库。</summary>
    private static bool IsKnownStation(string station)
    {
        var normalized = NormalizedStation(station);
        if (normalized.Length == 0) return false;
        if (KnownStations.Value.Contains(normalized)) return true;
        return StationNameAliases.TryGetValue(normalized, out var aliases) &&
            aliases.Any(alias => KnownStations.Value.Contains(alias));
    }

    private static bool UnlocksHanxiWuchang(PublicTrip trip) => RouteSpans(trip).Any(segment =>
        CoversRouteSection(segment, "京广线", "汉西", "武昌"));

    private static bool UnlocksSnowBlockingBlueGate(PublicTrip trip)
    {
        var departure = Departure(trip);
        var arrival = trip.ArrivalTime ?? departure;
        var start = new DateTime(2008, 1, 10);
        var end = new DateTime(2008, 2, 10);
        if (arrival < start || departure >= end) return false;
        return RouteSpans(trip).Any(segment =>
            CoversRouteSection(segment, "京广线", "武昌", "广州"));
    }

    private static int SectionCoverageCount(
        IEnumerable<PublicTrip> trips,
        IReadOnlyList<RailwaySection> availableSections)
    {
        var covered = new HashSet<string>(StringComparer.Ordinal);
        var sections = availableSections;
        foreach (var trip in trips)
        {
            var segments = RouteSpans(trip);
            foreach (var section in sections)
                if (segments.Any(segment => CoversRouteSection(segment, section)))
                    covered.Add(section.Name);
        }
        return covered.Count;
    }

    private static PublicTrip? FirstSectionCompletion(
        List<PublicTrip> trips,
        IReadOnlyList<RailwaySection> availableSections)
    {
        var required = availableSections
            .Select(section => section.Name)
            .ToHashSet(StringComparer.Ordinal);
        if (required.Count == 0) return null;
        return FirstSectionThresholdCompletion(trips, availableSections, required.Count);
    }

    /// <summary>至少完整行经 <paramref name="required"/> 个不同区段时返回该次行程。</summary>
    private static PublicTrip? FirstSectionThresholdCompletion(
        List<PublicTrip> trips,
        IReadOnlyList<RailwaySection> availableSections,
        int required)
    {
        var covered = new HashSet<string>(StringComparer.Ordinal);
        foreach (var trip in trips)
        {
            var segments = RouteSpans(trip);
            foreach (var section in availableSections)
                if (segments.Any(segment => CoversRouteSection(segment, section)))
                    covered.Add(section.Name);
            if (covered.Count >= required) return trip;
        }
        return null;
    }

    /// <summary>只保留线路与两端车站都能在路网库中解析的区段——附表里的线路名未必都能解析。</summary>
    private static IReadOnlyList<RailwaySection> AvailableSections(
        IReadOnlyList<RailwaySection> sections)
    {
        return sections
            .Where(section =>
                SectionStations(section) is { } stations &&
                TryRouteStation(stations, section.FromStation, out _) &&
                TryRouteStation(stations, section.ToStation, out _))
            .ToList();
    }

    private static IReadOnlyDictionary<string, int>? SectionStations(RailwaySection section) =>
        section.SpansLines
            ? FamilyChain(section.RouteName)
            : RouteStations.Value.GetValueOrDefault(section.RouteName);

    /// <summary>区段类成就的进度：按区段名去重计数，分母是实际可判定的区段数；
    /// 传 <paramref name="target"/> 时按该门槛计数（用于「至少 N 段」类成就）。</summary>
    private static AchievementProgress SectionProgress(
        IEnumerable<PublicTrip> trips,
        IReadOnlyList<RailwaySection> sections,
        int? target = null)
    {
        var available = AvailableSections(sections);
        var required = target ?? available
            .Select(section => section.Name)
            .Distinct(StringComparer.Ordinal)
            .Count();
        return P(SectionCoverageCount(trips, available), required);
    }

    // 2.6.1 的线路库删过速度等级词与分段名里的「线」（京港高铁安九段→京港安九段、
    // 宁西线西合段→宁西西合段）；当前线路库恢复成 2.6.0 以前的全名。历史行程里
    // 新旧两种写法都有，所以线路名比对按三档递进：同名 → 去掉末尾「线/铁路」 →
    // 抹平速度等级词与所有「线/铁路」。最后一档会把 京广线 与 京广高铁 归到同一个键，
    // 因此仅当涉及的名字不在线路库里时才启用——在册的两条不同线路绝不合并。
    private static readonly string[] RouteSuffixWords = ["铁路", "线"];
    private static readonly string[] RouteSpeedWords = ["客运专线", "高铁", "客专", "城际", "高速"];

    // 字面规则救不了的别名：跨段合并（宁蓉线、焦柳线）、2.6.1 拆分（广深港）、
    // 2.6.1 与当前库的换词（西渝高速线/西渝西康段 ↔ 西渝高铁西康段、
    // 武西高速线/武西高铁 ↔ 武西高铁云十段/走革段、连镇客专线 ↔ 连镇铁路）。
    // 同一族视为同一条线；中老铁路的磨万段是境外延伸，跨境判定一并认。
    private static readonly string[][] RouteNameFamilies =
    [
        ["广深港高速线", "广深港广深", "广深港福田", "广深港香港"],
        ["宁蓉线", "宁蓉线宁渝段", "宁蓉线成渝段"],
        ["焦柳线", "焦柳线焦怀段", "焦柳线怀柳段"],
        ["西渝高速线", "西渝西康段", "西渝高铁西康段"],
        ["武西高速线", "武西高铁", "武西高铁云十段", "武西高铁走革段", "武西走革段"],
        ["连镇铁路", "连镇客专线"],
        ["中老昆万铁路昆磨段", "昆万昆磨段", "中老昆万铁路磨万段", "昆万磨万段"]
    ];

    private static readonly Lazy<IReadOnlyDictionary<string, string[]>> RouteNameFamilyIndex = new(
        () =>
        {
            var index = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
            foreach (var family in RouteNameFamilies)
            foreach (var name in family)
            {
                if (!index.TryGetValue(name, out var members))
                    index[name] = members = new HashSet<string>(StringComparer.Ordinal);
                members.UnionWith(family);
            }
            return index.ToDictionary(
                pair => pair.Key,
                pair => pair.Value.ToArray(),
                StringComparer.Ordinal);
        });

    /// <summary>同族各线首尾相接拼成一条虚拟线的站序，给 2.6.1 拆线后的跨段区段（深港隧道）判定用。</summary>
    private static readonly Lazy<IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>>> RouteFamilyChains =
        new(BuildRouteFamilyChains);

    private static IReadOnlyDictionary<string, int>? FamilyChain(string routeName) =>
        RouteFamilyChains.Value.GetValueOrDefault(routeName.Trim());

    private static IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>> BuildRouteFamilyChains()
    {
        var chains = new Dictionary<string, IReadOnlyDictionary<string, int>>(StringComparer.Ordinal);
        foreach (var family in RouteNameFamilies)
        {
            var lines = family
                .Select(name => RouteStations.Value.TryGetValue(name, out var stations) ? stations : null)
                .Where(stations => stations is not null)
                .Select(stations => stations!.OrderBy(pair => pair.Value).Select(pair => pair.Key).ToList())
                .ToList();
            if (lines.Count < 2) continue;
            var chain = new List<string>(lines[0]);
            var remaining = lines.Skip(1).ToList();
            var joined = true;
            while (remaining.Count > 0)
            {
                var next = remaining.FindIndex(line =>
                    line[0] == chain[^1] || line[^1] == chain[^1]);
                if (next < 0) { joined = false; break; }
                var following = remaining[next];
                remaining.RemoveAt(next);
                if (following[^1] == chain[^1]) following.Reverse();
                chain.AddRange(following.Skip(1));
            }
            // 接不起来的族不建虚拟线——宁可判不了，也不要给出错位的站序。
            if (!joined) continue;
            var index = new Dictionary<string, int>(StringComparer.Ordinal);
            for (var i = 0; i < chain.Count; i++) index.TryAdd(chain[i], i);
            foreach (var name in family) chains[name] = index;
        }
        return chains;
    }

    /// <summary>各版线路库改过个别站名（夏官营客车所→夏官营客所、浦口→浦口南），
    /// 行程里的名称按各自当时的库生成。</summary>
    private static readonly IReadOnlyDictionary<string, string[]> StationNameAliases =
        new Dictionary<string, string[]>(StringComparer.Ordinal)
        {
            ["夏官营客车所"] = ["夏官营客所"],
            ["夏官营客所"] = ["夏官营客车所"],
            ["浦口"] = ["浦口南"],
            ["浦口南"] = ["浦口"]
        };

    private static string TrimRouteSuffix(string value)
    {
        var result = value.Trim();
        foreach (var suffix in RouteSuffixWords)
            if (result.EndsWith(suffix, StringComparison.Ordinal))
                return result[..^suffix.Length];
        return result;
    }

    private static string LooseRouteName(string value)
    {
        var result = value.Trim();
        foreach (var word in RouteSpeedWords)
            result = result.Replace(word, string.Empty, StringComparison.Ordinal);
        foreach (var word in RouteSuffixWords)
            result = result.Replace(word, string.Empty, StringComparison.Ordinal);
        return result;
    }

    private static bool RouteNameMatches(string name, string target)
    {
        var left = name.Trim();
        var right = target.Trim();
        if (left.Length == 0 || right.Length == 0) return false;
        if (string.Equals(left, right, StringComparison.Ordinal)) return true;
        if (RouteNameFamilyIndex.Value.TryGetValue(left, out var family) &&
            family.Contains(right, StringComparer.Ordinal)) return true;
        if (string.Equals(TrimRouteSuffix(left), TrimRouteSuffix(right), StringComparison.Ordinal)) return true;
        if (RouteStations.Value.ContainsKey(left) && RouteStations.Value.ContainsKey(right)) return false;
        return string.Equals(LooseRouteName(left), LooseRouteName(right), StringComparison.Ordinal);
    }

    // 归一化要遍历 794 条云端线路，而行程里出现的线路名种类很少，按名缓存即可。
    private static readonly ConcurrentDictionary<string, IReadOnlyList<string>> CatalogRoutesCache =
        new(StringComparer.Ordinal);

    /// <summary>把行程里的线路名解析到云端线路库里的一到多条线路（同名优先，其次逐档归一）。</summary>
    private static IReadOnlyList<string> CatalogRoutesFor(string name)
    {
        var value = name.Trim();
        return value.Length == 0 ? [] : CatalogRoutesCache.GetOrAdd(value, ResolveCatalogRoutes);
    }

    private static IReadOnlyList<string> ResolveCatalogRoutes(string value)
    {
        var catalog = RouteStations.Value;
        if (catalog.ContainsKey(value)) return [value];
        if (RouteNameFamilyIndex.Value.TryGetValue(value, out var family))
        {
            var familyMatches = family
                .Where(catalog.ContainsKey)
                .Order(StringComparer.Ordinal)
                .ToList();
            if (familyMatches.Count > 0) return familyMatches;
        }
        var suffix = TrimRouteSuffix(value);
        var suffixMatches = catalog.Keys
            .Where(route => string.Equals(TrimRouteSuffix(route), suffix, StringComparison.Ordinal))
            .Order(StringComparer.Ordinal)
            .ToList();
        if (suffixMatches.Count > 0) return suffixMatches;
        var loose = LooseRouteName(value);
        return catalog.Keys
            .Where(route => string.Equals(LooseRouteName(route), loose, StringComparison.Ordinal))
            .Order(StringComparer.Ordinal)
            .ToList();
    }

    /// <summary>区段去重、路线去重用的线路身份：旧名与新名落到同一个键。</summary>
    private static string CanonicalRouteName(string name)
    {
        var value = name.Trim();
        if (value.Length == 0 || RouteStations.Value.ContainsKey(value)) return value;
        var candidates = CatalogRoutesFor(value);
        return candidates.Count > 0 ? candidates[0] : LooseRouteName(value);
    }

    private static string CanonicalRouteSignature(PublicTrip trip) =>
        string.Join("|", RouteNames(trip).Select(CanonicalRouteName));

    private static bool TryRouteStation(
        IReadOnlyDictionary<string, int> stations, string station, out int index)
    {
        var normalized = NormalizedStation(station);
        if (stations.TryGetValue(normalized, out index)) return true;
        if (StationNameAliases.TryGetValue(normalized, out var aliases))
            foreach (var alias in aliases)
                if (stations.TryGetValue(alias, out index))
                    return true;
        index = 0;
        return false;
    }

    private static bool CoversRouteSection(RouteSegment segment, RailwaySection section) =>
        CoversRouteSection(
            segment,
            section.RouteName,
            section.FromStation,
            section.ToStation,
            section.SpansLines);

    private static bool CoversRouteSection(RouteSegment segment, string routeName, string first, string second) =>
        CoversRouteSection(segment, routeName, first, second, spansLines: false);

    private static bool CoversRouteSection(
        RouteSegment segment,
        string routeName,
        string first,
        string second,
        bool spansLines)
    {
        if (!RouteNameMatches(segment.RouteName, routeName)) return false;
        var stations = spansLines
            ? FamilyChain(routeName)
            : RouteStations.Value.GetValueOrDefault(routeName) ??
                RouteStations.Value.FirstOrDefault(item =>
                    item.Key.Contains(routeName, StringComparison.Ordinal) ||
                    RouteNameMatches(routeName, item.Key)).Value;
        if (stations is null) return false;
        if (!TryRouteStation(stations, segment.FromStation, out var from) ||
            !TryRouteStation(stations, segment.ToStation, out var to)) return false;
        if (!TryRouteStation(stations, first, out var start) ||
            !TryRouteStation(stations, second, out var end)) return false;
        var low = Math.Min(start, end); var high = Math.Max(start, end);
        return Math.Min(from, to) <= low && Math.Max(from, to) >= high;
    }

    private static IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>> LoadRouteStations()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Assets", "db", "routes.db");
        if (!File.Exists(path)) return new Dictionary<string, IReadOnlyDictionary<string, int>>(StringComparer.Ordinal);
        using var connection = new SqliteConnection($"Data Source={path};Mode=ReadOnly");
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT l.line_name, ls.station, ls.seq FROM lines l JOIN line_stations ls USING(line_id) ORDER BY l.line_id, ls.seq";
        using var reader = command.ExecuteReader();
        var result = new Dictionary<string, Dictionary<string, int>>(StringComparer.Ordinal);
        while (reader.Read())
        {
            var route = reader.GetString(0); var station = NormalizedStation(reader.GetString(1));
            if (!result.TryGetValue(route, out var stations)) result[route] = stations = new(StringComparer.Ordinal);
            stations.TryAdd(station, reader.GetInt32(2));
        }
        return result.ToDictionary(item => item.Key, item => (IReadOnlyDictionary<string, int>)item.Value, StringComparer.Ordinal);
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

    private static bool UnlocksVowAtQinling(PublicTrip trip)
    {
        var departure = Departure(trip);
        if (NormalizedStation(trip.FromStation) == "秦岭" && IsRomanticDate(departure))
            return true;
        var arrival = trip.ArrivalTime ?? departure;
        return NormalizedStation(trip.ToStation) == "秦岭" && IsRomanticDate(arrival);
    }

    private static bool UnlocksNewYearsEve(PublicTrip trip)
    {
        if (trip.ArrivalTime is null || trip.ArrivalTime < Departure(trip)) return false;
        var departure = Departure(trip);
        var arrival = trip.ArrivalTime.Value;
        if (arrival.Year > departure.Year) return true;
        try
        {
            return ChineseCalendar.GetYear(arrival) > ChineseCalendar.GetYear(departure);
        }
        catch (ArgumentOutOfRangeException)
        {
            return false;
        }
    }

    private static bool UnlocksMonotonousTrainNumber(PublicTrip trip)
    {
        var digits = Regex.Replace(trip.TrainNumber ?? string.Empty, "[A-Za-z]", string.Empty)
            .Replace(" ", string.Empty);
        return Regex.IsMatch(digits, @"^(\d)\1{2,3}$");
    }

    /// <summary>特别贺礼：元旦当天乘坐以当年年份命名的列车。</summary>
    private static bool UnlocksSpecialGift(PublicTrip trip)
    {
        var departure = Departure(trip);
        if (departure.Month != 1 || departure.Day != 1) return false;
        var digits = Regex.Replace(trip.TrainNumber ?? string.Empty, "[A-Za-z]", string.Empty)
            .Replace(" ", string.Empty);
        return digits.Length > 0 && digits == departure.Year.ToString(CultureInfo.InvariantCulture);
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
                if (transfer >= TimeSpan.FromHours(6) && transfer <= TimeSpan.FromHours(12)) return outgoing;
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

    private static IReadOnlyList<RouteSegment> RouteSegments(PublicTrip trip)
    {
        try
        {
            using var document = JsonDocument.Parse(trip.ViaRoutes);
            if (document.RootElement.ValueKind != JsonValueKind.Array) return [];
            var segments = new List<RouteSegment>();
            foreach (var item in document.RootElement.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.Object ||
                    !item.TryGetProperty("routeName", out var routeValue) ||
                    !item.TryGetProperty("fromStation", out var fromValue) ||
                    !item.TryGetProperty("toStation", out var toValue) ||
                    !item.TryGetProperty("mileageKm", out var mileageValue) ||
                    routeValue.ValueKind != JsonValueKind.String ||
                    fromValue.ValueKind != JsonValueKind.String ||
                    toValue.ValueKind != JsonValueKind.String ||
                    mileageValue.ValueKind != JsonValueKind.Number ||
                    !mileageValue.TryGetDouble(out var mileage)) continue;
                var route = routeValue.GetString()?.Trim() ?? string.Empty;
                var from = fromValue.GetString()?.Trim() ?? string.Empty;
                var to = toValue.GetString()?.Trim() ?? string.Empty;
                if (route.Length == 0 || from.Length == 0 || to.Length == 0) continue;
                segments.Add(new RouteSegment(route, from, to, mileage));
            }
            return segments;
        }
        catch (JsonException)
        {
            return [];
        }
    }

    /// <summary>把同一线路族里相邻的几段并成一段：2.6.1 的库把 广深港高速线 拆成广深/福田/香港
    /// 三条，一段行程因此会在同一条物理线路上留下两三条相邻段，逐段判定会漏掉跨段的区段
    /// （深港隧道的 深圳北-香港西九龙）。只并显式登记过的族，不按归一化键并——那会把
    /// 京广线与京广高铁并为一条。</summary>
    private static IReadOnlyList<RouteSegment> RouteSpans(PublicTrip trip)
    {
        var spans = new List<RouteSegment>();
        foreach (var segment in RouteSegments(trip))
        {
            if (spans.Count > 0)
            {
                var previous = spans[^1];
                // 只有首尾相接的两段才合并：2.6.1 的库把广深港高速线拆成了广深/福田/香港三条，
                // 深圳北→福田、福田→香港西九龙 要拼回一段才覆盖得了深港隧道这一区间。
                if (NormalizedStation(previous.ToStation) == NormalizedStation(segment.FromStation) &&
                    RouteNameFamilyIndex.Value.TryGetValue(previous.RouteName, out var family) &&
                    family.Contains(segment.RouteName, StringComparer.Ordinal))
                {
                    spans[^1] = previous with
                    {
                        ToStation = segment.ToStation,
                        MileageKm = previous.MileageKm + segment.MileageKm
                    };
                    continue;
                }
            }
            spans.Add(segment);
        }
        return spans;
    }

    private sealed record RepeatedTripKey(
        string TrainNumber,
        string RollingStockModel,
        string CompanyName,
        string FromStation,
        string ToStation,
        TimeSpan? DepartureTime,
        TimeSpan? ArrivalTime,
        int? ArrivalDayOffset,
        double MileageKm,
        string ViaRoutes,
        string SeatType,
        string SeatNumber,
        double Price);

    private sealed record RollingStockTarget(
        string Model,
        string? Number = null);

    private sealed record EmuModelFamily(
        string Series,
        IReadOnlyList<string> Models);

    private sealed record RouteSegment(
        string RouteName,
        string FromStation,
        string ToStation,
        double MileageKm);

    private sealed record RouteSectionKey(
        string RouteName,
        string FirstStation,
        string SecondStation);

    /// <summary>一条用于判定的铁路区段：在线路 <paramref name="RouteName"/> 上，行经
    /// FromStation→ToStation 即视为经过。附表 1–4 的桥梁、隧道共用。
    /// <paramref name="SpansLines"/> 表示这条物理线在 2.6.1 的库里被拆成了同族的几条线
    /// （广深港高速线 → 广深/福田/香港），判定时要先把同族各线接成一条虚拟线。</summary>
    private sealed record RailwaySection(
        string Name,
        string RouteName,
        string FromStation,
        string ToStation,
        bool SpansLines = false);

    private sealed record StationVisit(string Station, DateTime Time, PublicTrip Trip);

    /// <summary>一座别国首都车站。<paramref name="Aliases"/> 中任意一段出现在站名里即算到访，
    /// 同一 <paramref name="Key"/> 下的多个车站（阿斯塔纳的 1 号站与光明之路站）合并为一项。</summary>
    private sealed record ForeignCapitalStation(
        string Key,
        string Label,
        IReadOnlyList<string> Aliases);

    /// <summary>附表5 里的一座省会/自治区首府/直辖市/香港车站。<paramref name="Required"/> 为 false
    /// 即附表里带 * 的站，只满足「纵横九州」、不计入「功盖振声」；<paramref name="Aliases"/> 是
    /// 附注里写到的旧站名（改名前的叫法）。</summary>
    private sealed record CapitalStation(
        string City,
        string Station,
        bool Required,
        IReadOnlyList<string> Aliases);

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();
}
