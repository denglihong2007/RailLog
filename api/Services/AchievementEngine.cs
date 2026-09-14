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
    public bool NarrativeNote { get; init; }
}

public sealed record AchievementProgress(double Current, double Target);
public sealed record AchievementReview(string EntityType, string EntityKey);

public static partial class AchievementEngine
{
    private static readonly ChineseLunisolarCalendar ChineseCalendar = new();
    private const string Milestones = "milestones";
    private const string ExtremeChallenges = "extremeChallenges";
    private const string RailwayCatalog = "railwayCatalog";
    private const string Touring = "touring";
    private const string FunJourneys = "funJourneys";

    private static readonly IReadOnlyDictionary<string, string> AchievementCategories =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            ["firstTrip"] = Milestones,
            ["sevenDayStreak"] = Milestones,
            ["thirtyDayStreak"] = Milestones,
            ["hundredTickets"] = Milestones,
            ["thousandTickets"] = Milestones,
            ["hundredStations"] = Milestones,
            ["thousandKilometers"] = Milestones,
            ["hundredThousandKilometers"] = Milestones,
            ["archaeologyTeam"] = Milestones,
            ["tenNumericTrains"] = RailwayCatalog,
            ["traverseOneRegion"] = Milestones,
            ["halfTheRealm"] = Milestones,
            ["centuryDreamFulfilled"] = Milestones,
            ["fiftyThousandSpending"] = Milestones,
            ["reviewedTrainNumbers"] = Milestones,
            ["unknownTerritory"] = Milestones,
            ["careerRecord"] = Milestones,
            ["nonOrdinary"] = Milestones,
            ["ancientMemory"] = Milestones,
            ["thousandCities"] = Milestones,
            ["rottenAxe"] = Milestones,
            ["roamFreely"] = Milestones,
            ["travelAllMountains"] = Milestones,
            ["immovableMountain"] = ExtremeChallenges,
            ["richerThanNation"] = ExtremeChallenges,

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
            ["fourThousandKmInDay"] = ExtremeChallenges,

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
            ["meritAndHonor"] = RailwayCatalog,
            ["friendshipForever"] = RailwayCatalog,
            ["steamPower"] = RailwayCatalog,
            ["flowersAmong"] = RailwayCatalog,
            ["refinedMechanic"] = RailwayCatalog,
            ["dawnBreaks"] = RailwayCatalog,
            ["hundredPeople"] = RailwayCatalog,

            ["verticalChina"] = Touring,
            ["horizontalChina"] = Touring,
            ["fourFamousNorths"] = Touring,
            ["cardinalStations"] = Touring,
            ["borderPorts"] = Touring,
            ["singleBikeBorder"] = Touring,
            ["travelerAbroad"] = Touring,
            ["skyAndSea"] = Touring,
            ["greatWallExpress"] = RailwayCatalog,
            ["qinlingPassage"] = Touring,
            ["heavenlyThoroughfare"] = Touring,
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
            ["centuryMeterGauge"] = RailwayCatalog,
            ["fourExtremes"] = Touring,
            ["waterIsCalm"] = Touring,
            ["roadBlazing"] = Touring,
            ["goddessYangtzeBridges"] = Touring,

            ["freeMeal"] = FunJourneys,
            ["wallFacingSeat"] = FunJourneys,
            ["farsighted"] = FunJourneys,
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
            ["dejaVu"] = FunJourneys,
            ["vowAtQinling"] = FunJourneys,
            ["differentRoutesSameDestination"] = FunJourneys,
            ["spendsLikeWater"] = FunJourneys,
            ["wealthyTraveler"] = ExtremeChallenges,
            ["hundredDeparturesFromStation"] = FunJourneys,
            ["thousandDeparturesFromStation"] = FunJourneys,
            ["multipleLocomotives"] = FunJourneys,
            ["snowBlockingBlueGate"] = FunJourneys,
            ["oneStoneThreeBirds"] = FunJourneys,
        };

    private sealed record AchievementMetadata(
        int Experience,
        int? MaxExperience = null,
        string? Note = null,
        bool Hidden = false,
        bool NarrativeNote = false);

    private static readonly IReadOnlyDictionary<string, AchievementMetadata>
        AchievementMetadataById = new Dictionary<string, AchievementMetadata>(
            StringComparer.Ordinal)
        {
            ["firstTrip"] = new(10),
            ["hundredTickets"] = new(10),
            ["thousandTickets"] = new(40),
            ["archaeologyTeam"] = new(
                25,
                Note: "即使忘记了许多细节也没关系",
                NarrativeNote: true),
            ["hundredStations"] = new(15),
            ["sevenDayStreak"] = new(15),
            ["thirtyDayStreak"] = new(30),
            ["thousandKilometers"] = new(10),
            ["hundredThousandKilometers"] = new(25),
            ["lonelyPlanet"] = new(30),
            ["traverseOneRegion"] = new(10),
            ["halfTheRealm"] = new(30),
            ["centuryDreamFulfilled"] = new(
                50,
                Note: "一百年前，孙中山曾梦想全国修建起16万千米的铁路网……",
                NarrativeNote: true),
            ["fiftyThousandSpending"] = new(30),
            ["reviewedTrainNumbers"] = new(20),
            ["unknownTerritory"] = new(40),
            ["careerRecord"] = new(50),

            ["overnightSeat"] = new(10),
            ["midnightBoarding"] = new(10),
            ["duration24Hours"] = new(10),
            ["duration48Hours"] = new(25),
            ["duration72Hours"] = new(
                50,
                Note: "也许只有临客了",
                NarrativeNote: true),
            ["slowCrawl"] = new(10),
            ["slowerThanCycling"] = new(30),
            ["highSpeedExperiment"] = new(15),
            ["wellPreparedTransfer"] = new(10),
            ["tightTransfer"] = new(10),
            ["tripleTransfer"] = new(10),
            ["miniTurnaround"] = new(10),
            ["fourThousandKmInDay"] = new(
                30,
                Note: "早上坐最快的高铁出发，晚上再坐动卧回来……",
                NarrativeNote: true),
            ["noSeat12Hours"] = new(25),
            ["youthPriceless"] = new(
                40,
                Note: "The sky is the limit.",
                NarrativeNote: true),
            ["zeroDisplacement"] = new(20),
            ["wealthyTraveler"] = new(40),

            ["all25Series"] = new(30, Note: "25B, 25G, 25Z, 25K, 25T, 25DT"),
            ["allEmuSeries"] = new(
                40,
                Note: "CRH1, CRH2, CRH3, CRH5, CRH6, CRH380A, CRH380B, "
                    + "CRH380CL, CRH380D, CR400AF, CR400BF, CR300AF, "
                    + "CR300BF, CR200J, CR200J-C"),
            ["whatAgeIsThis"] = new(
                20,
                Note: "21, 22, 22B, 22C, 23, 24, 25A, 25C, 25Z, 19, 30, "
                    + "31, 10, 14, 82, 96"),
            ["allSeatTypes"] = new(
                40,
                Note: "无座、硬座、软座、二等座、一等座、特等座、优选一等座、商务座、"
                    + "硬卧、软卧、二等卧、一等卧、高级软卧、动卧、高级动卧"),
            ["greatWallExpress"] = new(10),
            ["railwayWorkerPassenger"] = new(25),
            ["fTrain"] = new(40),
            ["spontaneousTrip"] = new(10),
            ["ancientLetters"] = new(20),
            ["tenNumericTrains"] = new(25),
            ["completeTrainLetters"] = new(
                30,
                Note: "G, D, C, S, Z, T, K, Y, 纯数字；未来车次调整后该成就将大幅重构"),
            ["permanentMagnetPower"] = new(25),
            ["axleOverheat"] = new(25),
            ["snowWelcomesSpring"] = new(25),
            ["moistensJiangnan"] = new(25),
            ["facingTheWorld"] = new(20),
            ["vibrantJourney"] = new(20),
            ["verticalSleeper"] = new(20),
            ["blueHorizon"] = new(20),
            ["railwayTrailblazer"] = new(
                25,
                MaxExperience: 50,
                Note: "X2000, KDZ1A, DJF1, DJF2, DJF3, DJJ1, DJJ2, NZJ1, "
                    + "NZJ2, NDJ3, NYJ1；每多一种额外获得10点经验，上限为50点"),
            ["meritAndHonor"] = new(
                20,
                MaxExperience: 50,
                Note: "SS3B 5151, HXD1 1937, HXD1C 1927, HXD1D 1898, HXD2B 0001, "
                    + "HXD3CA 8161, HXD3D 0035, 0039, 0631, 1886, 1893, 1921；"
                    + "每多一种额外获得5点经验，上限为50点"),
            ["friendshipForever"] = new(
                25,
                MaxExperience: 50,
                Note: "6Y2, 6G, 6K, 8G, 8K, DJ1, ND2, ND4, ND5, NY5, NY6, "
                    + "NY7, NJ2；每多一种额外获得5点经验，上限为50点"),
            ["steamPower"] = new(
                40,
                Note: "JF, SL, KD, FD, KF, JS, RM, QJ；多于一种额外获得10点经验"),
            ["grandSlam"] = new(30),
            ["centuryMeterGauge"] = new(15),

            ["verticalChina"] = new(
                30,
                MaxExperience: 50,
                Note: "每少二日额外获得5点经验，上限为50点"),
            ["horizontalChina"] = new(
                30,
                MaxExperience: 50,
                Note: "每少二日额外获得5点经验，上限为50点"),
            ["skyAndSea"] = new(
                30,
                MaxExperience: 50,
                Note: "每少二日额外获得5点经验，上限为50点"),
            ["fourExtremes"] = new(50),
            ["eastRedSunRises"] = new(30),
            ["platformSubsidence"] = new(10),
            ["endsOfTheEarth"] = new(10),
            ["greatWallWatch"] = new(10),
            ["advantageIsMine"] = new(10),
            ["waterIsCalm"] = new(20),
            ["roadBlazing"] = new(40),
            ["fourFamousNorths"] = new(
                15,
                MaxExperience: 35,
                Note: "每多一站额外获得5点经验，上限为35点"),
            ["borderPorts"] = new(
                20,
                MaxExperience: 50,
                Note: "每多一站额外获得5点经验，上限为50点"),
            ["airRail"] = new(
                15,
                MaxExperience: 50,
                Note: "每多一站额外获得5点经验，上限为50点"),
            ["railFerry"] = new(
                15,
                Note: "线路名称包含“轮渡”即可；大连与烟台间接续可替代轮渡线路"),
            ["singleBikeBorder"] = new(30),
            ["travelerAbroad"] = new(50),
            ["qinlingPassage"] = new(10),
            ["heavenlyThoroughfare"] = new(10),
            ["goddessYangtzeBridges"] = new(40),
            ["strategist"] = new(
                25,
                Note: "目前查无此车",
                NarrativeNote: true),
            ["icyWorld"] = new(30),
            ["cardinalStations"] = new(25),

            ["wallFacingSeat"] = new(10, Note: "并不是所有的第1排或第18排都面壁", NarrativeNote: true),
            ["overnightSleeper"] = new(10),
            ["hundredDeparturesFromStation"] = new(25),
            ["modestAppetite"] = new(10),
            ["freeMeal"] = new(10, Note: "11:00-13:00, 17:00-19:00"),
            ["multipleLocomotives"] = new(
                20,
                MaxExperience: 50,
                Note: "每多一台额外获得10点经验，上限为50点"),
            ["farsighted"] = new(25),
            ["fleetingMoment"] = new(20),
            ["commuterSpecial"] = new(20),
            ["eveOfTheStorm"] = new(25),
            ["snowBlockingBlueGate"] = new(30),
            ["storedUpReward"] = new(30),
            ["unnecessaryExtra"] = new(
                30,
                MaxExperience: 50,
                Note: "每多一张额外获得10点经验，上限为50点"),
            ["newYearsEve"] = new(10),
            ["blessChina"] = new(10),
            ["monotonousTrainNumber"] = new(25, Note: "中途切换车次也可以"),
            ["multipleChoices"] = new(20),
            ["differentRoutesSameDestination"] = new(
                20,
                MaxExperience: 50,
                Note: "每多一种额外获得10点经验，上限为50点"),
            ["publicDisplayOfAffection"] = new(15),
            ["vowAtQinling"] = new(20),
            ["dejaVu"] = new(
                30,
                Note: "不知道有多少人忘了填座号",
                NarrativeNote: true),
            ["oneYuanJourney"] = new(20),
            ["spendsLikeWater"] = new(40),
            ["oneStoneThreeBirds"] = new(30, Note: "之前取得过的成就也可以"),

            ["ancientMemory"] = new(
                50,
                Note: "那时甚至还没有软纸车票",
                Hidden: true,
                NarrativeNote: true),
            ["thousandCities"] = new(
                80,
                Note: "进站，安检，检票，上车……这个流程想必早就习以为常了",
                Hidden: true,
                NarrativeNote: true),
            ["rottenAxe"] = new(
                80,
                Note: "师傅你是做什么工作的",
                Hidden: true,
                NarrativeNote: true),
            ["roamFreely"] = new(
                80,
                Note: "你一定把全国铁路网都背熟了吧",
                Hidden: true,
                NarrativeNote: true),
            ["travelAllMountains"] = new(
                80,
                Note: "小汽车也很少开得到这个里程……大货车也许可以与之一试？",
                Hidden: true,
                NarrativeNote: true),
            ["immovableMountain"] = new(
                50,
                Note: "你站你也麻",
                Hidden: true,
                NarrativeNote: true),
            ["richerThanNation"] = new(
                80,
                Note: "坐一次丝路梦享号的最豪华包间就够了",
                Hidden: true,
                NarrativeNote: true),
            ["flowersAmong"] = new(
                80,
                Note: "截至2026年9月共65种，详见附表2",
                Hidden: true),
            ["refinedMechanic"] = new(
                80,
                Note: "HXD1, HXD1B, HXD1C, HXD1D, HXD2, HXD2B, HXD2C, "
                    + "HXD3, HXD3B, HXD3C, HXD3D, HXN3, HXN5, FXD1, FXD1BA, "
                    + "FXD2BA, FXD3, FXN3C, FXN5C, FXSY",
                Hidden: true),
            ["dawnBreaks"] = new(
                80,
                Note: "DF1, DF3, DF4, DF4B, DF4C, DF4D, DF7D, DF8, DF8B, "
                    + "DF9, DF10F, DF11, DF11Z, DF11G, SS1, SS3, SS3B, SS4, "
                    + "SS6, SS6B, SS7, SS7C, SS7D, SS7E, SS8, SS9",
                Hidden: true),
            ["hundredPeople"] = new(
                50,
                Note: "所以你觉得哪个客运段的服务最好，哪个又最差？",
                Hidden: true,
                NarrativeNote: true),
            ["thousandDeparturesFromStation"] = new(
                80,
                Note: "车站的结构图已经早就被你刻在DNA里了吧！",
                Hidden: true,
                NarrativeNote: true),
            ["nonOrdinary"] = new(
                150,
                Note: "阁下是……人类？",
                Hidden: true,
                NarrativeNote: true),
        };

    private static readonly IReadOnlySet<string> RegularAchievementIdSet =
        AchievementCategories.Keys
            .Where(id => !(AchievementMetadataById.GetValueOrDefault(id)?.Hidden ?? false))
            .ToHashSet(StringComparer.Ordinal);

    public static IReadOnlySet<string> RegularAchievementIds =>
        RegularAchievementIdSet;

    public static bool IsHiddenAchievement(string id) => IsHidden(id);

    private static readonly HashSet<string> Regular25Models =
        ["25B", "25Z", "25G", "25K", "25T", "25DT"];
    private static readonly IReadOnlyList<RollingStockTarget> EarlyEmuModels =
    [
        new("X2000"), new("KDZ1A"), new("DJF1"), new("DJF2"), new("DJF3"),
        new("DJJ1"), new("DJJ2"), new("NZJ1"), new("NZJ2"), new("NDJ3"), new("NYJ1")
    ];
    private static readonly IReadOnlyList<RollingStockTarget> EarlyPassengerCoachModels =
    [
        new("21"), new("22"), new("22A"), new("22B"), new("22C"), new("23"),
        new("24"), new("25A"), new("25Z"), new("25C"), new("31"), new("19"),
        new("30"), new("10"), new("14"), new("82"), new("96")
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
            "CR400AF", "CR400AF-A", "CR400AF-AE", "CR400AF-AS", "CR400AF-AZ",
            "CR400AF-B", "CR400AF-BS", "CR400AF-BZ", "CR400AF-C", "CR400AF-G",
            "CR400AF-S", "CR400AF-Z"
        ]),
        new("CR400BF",
        [
            "CR400BF", "CR400BF-A", "CR400BF-AS", "CR400BF-AZ", "CR400BF-B",
            "CR400BF-BS", "CR400BF-BZ", "CR400BF-C", "CR400BF-G", "CR400BF-GS",
            "CR400BF-GZ", "CR400BF-S", "CR400BF-Z"
        ]),
        new("CR300AF", ["CR300AF"]),
        new("CR300BF", ["CR300BF"]),
        new("CR200J",
        [
            "CR200J1-A", "CR200J1-B", "CR200J2-A", "CR200J2-B",
            "CR200J3-A", "CR200J3-B", "CR200JS-G"
        ]),
        new("CR200J-C", ["CR200J1-C", "CR200J1-D", "CR200J2-C", "CR200J3-C"])
    ];
    private static readonly HashSet<string> RegularSeatTypes =
    [
        "无座", "硬座", "软座", "二等座", "一等座", "特等座", "优选一等座", "商务座",
        "硬卧", "软卧", "二等卧", "一等卧", "高级软卧", "动卧", "高级动卧"
    ];
    private static readonly HashSet<string> AirportStationsWithoutAirportSuffix = ["美兰", "龙洞堡", "上海虹桥"];
    private static readonly IReadOnlyList<RollingStockTarget> VariableGaugeModels =
    [
        new("CR400BF", "0031"),
        new("CR400BF-G", "0051"),
        new("CR400AF-G", "0021")
    ];
    private static readonly IReadOnlyList<RollingStockTarget> PrototypeModels =
    [
        new("CR400BF", "0305"), new("CR400BF", "0503"), new("CR400BF", "0507"),
        new("CR400AF", "0207"), new("CR400AF", "0208"), new("CR300AF", "0001"),
        new("CR300AF", "0003"), new("CR300AF", "0004"), new("CR300BF", "0002"),
        new("CR300BF", "0005"), new("CR300BF", "0006")
    ];
    private static readonly IReadOnlyList<RollingStockTarget> GreatWallExpressModels =
    [
        new("CR400AF-B"), new("CR400AF-BZ"), new("CR400AF-BS"), new("CR400AF-BX"),
        new("CR400BF-B"), new("CR400BF-BZ"), new("CR400BF-BS"), new("CR400BF-BX")
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
        "DF8B", "DF9", "DF10F", "DF11", "DF11Z", "DF11G", "SS1", "SS3",
        "SS3B", "SS4", "SS6", "SS6B", "SS7", "SS7C", "SS7D", "SS7E",
        "SS8", "SS9"
    ];
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

    private static readonly IReadOnlyList<YangtzeBridge> YangtzeBridges =
    [
        new("虎跳峡金沙江大桥", "滇藏线", "拉市海", "小中甸"),
        new("三堆子金沙江大桥", "成昆线", "三堆子", "攀枝花"),
        new("成昆复线金沙江大桥", "峨广线", "盐边", "普达"),
        new("水富金沙江大桥", "内六线", "一步滩", "翠屏"),
        new("白沙沱长江大桥", "渝贵线", "重庆西", "珞璜南"),
        new("明月峡长江大桥", "重庆东环线", "皂角树所", "迎龙"),
        new("长寿长江大桥", "渝怀线", "长寿", "王家坝"),
        new("韩家沱长江大桥", "宁蓉线", "丰都", "涪陵北"),
        new("万州长江大桥", "万凉线", "万州", "五桥"),
        new("宜昌长江大桥", "宁蓉线", "宜昌东", "宜昌南"),
        new("枝城长江大桥", "焦柳线", "枝江", "枝城"),
        new("武汉长江大桥", "京广线", "汉西", "武昌"),
        new("天兴洲长江大桥", "京广高速线", "横店东", "武汉"),
        new("天兴洲长江大桥", "滠武线", "滠口", "武汉"),
        new("黄冈长江大桥", "武黄城际", "华容东", "黄冈西"),
        new("鳊鱼洲长江大桥", "安九高速线", "黄梅南", "庐山"),
        new("九江长江大桥", "京九线", "小池口", "九江"),
        new("安庆长江大桥", "宁安客专", "池州", "安庆"),
        new("铜陵长江大桥", "京港高速线", "无为", "铜陵北"),
        new("铜陵长江大桥", "庐铜线", "龙桥", "钟鸣所"),
        new("芜湖长江三桥", "合杭高速线", "芜湖北", "芜湖"),
        new("芜湖长江大桥", "淮南线", "裕溪口", "芜湖"),
        new("大胜关长江大桥", "京沪高速线", "滁州", "南京南"),
        new("大胜关长江大桥", "宁蓉线", "南京南", "江浦"),
        new("南京长江大桥", "京沪线", "林场", "南京"),
        new("五峰山长江大桥", "连镇客专", "扬州东", "大港南"),
        new("沪苏通长江大桥", "沪通线", "南通西", "张家港")
    ];

    private static readonly Lazy<IReadOnlyDictionary<string, IReadOnlyDictionary<string, int>>> RouteStations = new(LoadRouteStations);
    private static readonly string[] BorderRouteMarkers = ["丹东国境线", "绥芬河交界", "满洲里交界", "二连交界", "阿拉山口交界", "凭祥交界"];

    public static IReadOnlyList<AchievementEvaluation> Evaluate(
        IEnumerable<PublicTrip> sourceTrips,
        IEnumerable<AchievementReview>? sourceReviews = null,
        DateTime? now = null)
    {
        var trips = sourceTrips
            .Where(trip => trip.IsRailTrip)
            .OrderBy(trip => trip.DepartureTime ?? trip.CreatedAt)
            .ThenBy(trip => trip.TicketId)
            .ToList();
        var reviews = sourceReviews?.ToList() ?? [];
        var today = (now ?? DateTime.Now).Date;
        var fifteenYearsAgo = new DateTime(today.Year - 15, 1, 1)
            .AddMonths(today.Month - 1)
            .AddDays(today.Day - 1);
        var emuModels = EmuModelFamilies
            .Select(family => family.Series)
            .ToHashSet(StringComparer.Ordinal);
        var smallEmuModels = EmuModelFamilies
            .SelectMany(family => family.Models)
            .ToHashSet(StringComparer.Ordinal);

        var values = new List<AchievementEvaluation>
        {
            A("freeMeal", "restaurant_outlined", "蹭吃蹭喝", "在用餐时段乘坐里程不超过 50 公里的商务座",
                First(trips, UnlocksFreeMeal)),
            A("overnightSeat", "airline_seat_recline_extra_outlined", "坐待天明", "乘坐硬座或二等座，完整度过 00:00 至 06:00",
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
            A("allEmuSeries", "train_outlined", "琳琅满目", "分别乘坐全部常规和谐号、复兴号系列",
                FirstCollectionCompletion(trips, emuModels, trip => EmuMatches(trip.RollingStock))),
            A("allSeatTypes", "checklist_outlined", "我全都要", "分别乘坐全部常规席别",
                FirstCollectionCompletion(trips, RegularSeatTypes, trip => SeatTypeMatches(trip.SeatType))),
            A("noSeat12Hours", "accessibility_new", "体力非凡", "持无座车票乘坐至少 12 小时",
                First(trips, trip => NormalizedSeatType(trip.SeatType) == "无座" &&
                    ValidDuration(trip) >= TimeSpan.FromHours(12))),
            A("hundredTickets", "collections_bookmark_outlined", "日积月累", "累计留存至少 100 张本人车票",
                trips.Count >= 100 ? trips[99] : null),
            A("midnightBoarding", "nightlight_outlined", "夜半钟声", "在 00:00 至 05:00 乘车或下车",
                FirstMidnightBoarding(trips)),
            A("wallFacingSeat", "visibility_off_outlined", "一墙障目", "乘坐车厢第 1 排或第 18 排的二等座",
                First(trips, UnlocksWallFacingSeat)),
            A("hundredStations", "location_on_outlined", "百站印记", "累计到访至少 100 座不同的客运车站",
                FirstStationCompletion(trips, 100)),
            A("thousandKilometers", "route_outlined", "千里足迹", "完成单程至少 1,000 公里的行程",
                First(trips, trip => trip.MileageKm >= 1000)),
            A("airRail", "connecting_airports_outlined", "扶摇直上", "累计到访至少 3 座不同的国内机场铁路站",
                FirstAirportStationCompletion(trips, 3)),
            A("railFerry", "directions_boat_outlined", "长风破浪", "乘坐经由任意轮渡线的列车，或在大连与烟台间完成 24 小时内的跨海接续",
                FirstRailFerryCompletion(trips)),
            A("railwayWorkerPassenger", "directions_railway_outlined", "顺风班车", "乘坐一次 57XXX 或 40XXX 路用列车",
                First(trips, trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^(?:57|40)\d{3}$"))),
            A("verticalChina", "swap_vert", "通津南北", "在 14 天内到访漠河站和三亚站",
                FirstStationPairWithin(trips, "漠河", "三亚", TimeSpan.FromDays(14))),
            A("horizontalChina", "swap_horiz", "东奔西走", "在 14 天内到访阿克陶站和抚远站",
                FirstStationPairWithin(trips, "阿克陶", "抚远", TimeSpan.FromDays(14))),
            A("eastRedSunRises", "wb_sunny_outlined", "其道大光", "到访东方红站和太阳升站",
                FirstStationPairCompletion(trips, "东方红", "太阳升")),
            A("highSpeedExperiment", "speed_outlined", "冲高试验", "完成时长超过 1 小时且均速超过 300 公里/小时的行程",
                First(trips, trip => ValidDuration(trip) > TimeSpan.FromHours(1) && AverageSpeed(trip) > 300)),
            A("slowCrawl", "slow_motion_video_outlined", "龟速爬行", "完成时长超过 1 小时且均速不超过 50 公里/小时的行程",
                First(trips, trip => ValidDuration(trip) > TimeSpan.FromHours(1) && AverageSpeed(trip) is > 0 and <= 50)),
            A("slowerThanCycling", "directions_bike_outlined", "不如骑车", "完成时长超过 1 小时且均速低于 30 公里/小时的行程",
                First(trips, trip => ValidDuration(trip) > TimeSpan.FromHours(1) && AverageSpeed(trip) is > 0 and < 30)),
            A("fleetingMoment", "flash_on_outlined", "转瞬即逝", "乘坐福田或深圳北与香港西九龙间的一等座、商务座或特等座",
                First(trips, UnlocksFleetingMoment)),
            A("borderPorts", "language_outlined", "异域风情", "到访阿拉山口、二连、满洲里、绥芬河、丹东、崇左或磨憨站",
                FirstStationVisit(trips, ["阿拉山口", "二连", "满洲里", "绥芬河", "丹东", "崇左", "磨憨"])),
            A("singleBikeBorder", "directions_railway_outlined", "单车问边", "乘坐联运列车从任一口岸车站出入境",
                First(trips, UnlocksBorderCrossing)),
            A("travelerAbroad", "luggage_outlined", "他乡旅人", "从任一口岸车站入境后 14 天内由另一口岸车站出境",
                FirstDifferentBorderCompletion(trips)),
            A("skyAndSea", "public_outlined", "上天入海", "在 14 天内到访雁石坪站和香港西九龙站",
                FirstStationPairWithin(trips, "雁石坪", "香港西九龙", TimeSpan.FromDays(14))),
            A("greatWallExpress", "speed_outlined", "飞驰长城", "乘坐一次 17 节编组的动力分散型动车组",
                FirstRollingStockMatch(trips, GreatWallExpressModels)),
            A("qinlingPassage", "landscape_outlined", "蜀道不难", "行经任一横穿秦岭的铁路客运区间",
                First(trips, UnlocksQinlingPassage)),
            A("heavenlyThoroughfare", "route_outlined", "天堑通途", "行经京广线的汉西到武昌区间",
                First(trips, UnlocksHanxiWuchang)),
            A("lonelyPlanet", "map_outlined", "孤独星球", "分别乘坐经由和若线与格库线的列车",
                FirstRouteCollectionCompletion(trips, ["若和铁路", "格库线"])),
            A("hundredThousandKilometers", "route_outlined", "轻车熟路", "累计乘车里程至少 100,000 公里",
                FirstCumulativeMileageCompletion(trips, 100000)),
            A("fTrain", "u_turn_left_outlined", "中途遣返", "乘坐一次 F 字头列车",
                First(trips, trip => trip.TrainNumber.Trim().StartsWith("F", StringComparison.OrdinalIgnoreCase))),
            A("axleOverheat", "device_thermostat_outlined", "轴温过高", "乘坐一次 CR400BF-5033 型列车",
                FirstRollingStockMatch(trips, [new("CR400BF", "5033")])),
            A("permanentMagnetPower", "bolt_outlined", "永磁动力", "乘坐一次 CRH380AN 型列车",
                FirstRollingStockMatch(trips, [new("CRH380AN")])),
            A("advantageIsMine", "flag_outlined", "优势在我", "到访徐州站或徐州东站",
                FirstStationVisit(trips, ["徐州", "徐州东"])),
            A("platformSubsidence", "vertical_align_bottom_outlined", "站台沉降", "到访杭州东站",
                FirstStationVisit(trips, ["杭州东"])),
            A("archaeologyTeam", "history_edu_outlined", "朝花夕拾", "录入至少 15 年前的行程",
                First(trips, trip => Departure(trip) <= fifteenYearsAgo)),
            A("strategist", "psychology_outlined", "文韬武略", "乘坐定西北站至镇江南站的列车",
                First(trips, trip => NormalizedStation(trip.FromStation) == "定西北" &&
                    NormalizedStation(trip.ToStation) == "镇江南")),
            A("eveOfTheStorm", "thunderstorm_outlined", "风雨前夜", "在 2019-12-01 至 2020-01-23 到访武汉站、汉口站或武昌站",
                FirstStationVisitDuring(trips, ["武汉", "汉口", "武昌"],
                    new DateTime(2019, 12, 1), new DateTime(2020, 1, 24))),
            A("tenNumericTrains", "pin_outlined", "慢慢旅途", "累计乘坐至少 10 次纯数字车次",
                FirstCountCompletion(trips, 10, trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^\d+$"))),
            A("overnightSleeper", "bedtime_outlined", "夕发朝至", "乘坐 18:00 至 00:00 发车且 05:00 至 11:00 到达的卧铺列车",
                First(trips, UnlocksOvernightSleeper)),
            A("tripleTransfer", "multiple_stop_outlined", "辗转挪移", "连续换乘至少 2 次，每次换乘间隔不超过 3 小时",
                FirstTransferChainCompletion(trips, 2)),
            A("endsOfTheEarth", "landscape_outlined", "天涯海角", "到访天涯海角站",
                FirstStationVisit(trips, ["天涯海角"])),
            A("fourFamousNorths", "explore_outlined", "四大名北", "到访阳泉北站、盘锦北站、孝感北站或邵阳北站",
                FirstStationVisit(trips, ["阳泉北", "盘锦北", "孝感北", "邵阳北"])),
            A("youthPriceless", "airline_seat_recline_normal", "欲试天高", "从北京、上海或广州出发，乘坐全程硬座列车到达拉萨站",
                First(trips, trip => NormalizedStation(trip.ToStation) == "拉萨" &&
                    NormalizedSeatType(trip.SeatType) == "硬座" &&
                    NormalizedStation(trip.FromStation) is "北京" or "上海" or "广州")),
            A("zeroDisplacement", "loop", "位移为零", "乘坐始发站与终到站相同的环线列车全程",
                First(trips, trip => NormalizedStation(trip.FromStation) == NormalizedStation(trip.ToStation))),
            A("dreamPath", "auto_awesome_outlined", "逐梦之路", "乘坐一次 25DT 型列车",
                FirstRollingStockMatch(trips, [new("25DT")])),
            A("commuterSpecial", "work_outline", "牛马专列", "乘坐北京与上海间经由京沪高铁的一等座、优选一等座、商务座或特等座",
                First(trips, UnlocksCommuterSpecial)),
            A("grandSlam", "palette_outlined", "十人十色", "分别乘坐全部铁路局担当的列车",
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
            A("newYearsEve", "celebration_outlined", "新年快乐", "在列车上完成跨年",
                First(trips, UnlocksNewYearsEve)),
            A("monotonousTrainNumber", "format_list_numbered_outlined", "千篇一律", "乘坐数字部分为三或四个相同数字的车次",
                First(trips, UnlocksMonotonousTrainNumber)),
            A("snowWelcomesSpring", "ac_unit_outlined", "瑞雪迎春", "乘坐一次北京冬奥会限定车型 CR400BF-C-5162",
                FirstRollingStockMatch(trips, [new("CR400BF-C", "5162")])),
            A("moistensJiangnan", "water_drop_outlined", "润泽江南", "乘坐一次杭州亚运会限定车型 CR400BF-Z-0524",
                FirstRollingStockMatch(trips, [new("CR400BF-Z", "0524")])),
            A("facingTheWorld", "public_outlined", "面向世界", "乘坐一次 CR400 系列可变轨距列车",
                FirstRollingStockMatch(trips, VariableGaugeModels)),
            A("revivalPrototype", "precision_manufacturing_outlined", "复兴之路", "乘坐一次 CR400 或 CR300 原样车",
                FirstRollingStockMatch(trips, PrototypeModels)),
            A("vibrantJourney", "directions_railway_outlined", "动感之旅", "乘坐一次港铁动感号列车",
                FirstRollingStockMatch(trips, VibrantExpressModels)),
            A("multipleChoices", "format_list_numbered_outlined", "多重选择", "在同一乘车区间累计乘坐至少 10 个不同车次",
                FirstDistinctTrainCountForRoute(trips, 10)),
            A("publicDisplayOfAffection", "people_outline", "成双成对", "在 5 月 20 日、2 月 14 日或七夕乘坐重联动车组列车",
                First(trips, trip => IsRomanticDate(Departure(trip)) &&
                    HasCoupledEmu(trip.RollingStock))),
            A("farsighted", "visibility_outlined", "高瞻远瞩", "乘坐双层车厢的上层席位",
                First(trips, trip => trip.SeatNumber is not null && Regex.IsMatch(trip.SeatNumber, @"上(?!铺)"))),
            A("oneYuanJourney", "currency_yen", "一元旅程", "单次行程票价为 1 元",
                First(trips, trip => trip.Price == 1)),
            A("cardinalStations", "explore_outlined", "东西南北", "到访过一个城市的东西南北中五个车站",
                FirstCardinalStationCompletion(trips)),
            A("ancientLetters", "history_edu_outlined", "远古字母", "乘坐过以 A、N 或 L 开头的列车，或在 2000 年以前乘坐过 G 字头列车",
                First(trips, trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^[ANL]\s*\d", RegexOptions.IgnoreCase) ||
                    (Departure(trip).Year < 2000 && Regex.IsMatch(trip.TrainNumber.Trim(), @"^G", RegexOptions.IgnoreCase)))),
            A("miniTurnaround", "timer_outlined", "迷你运转", "单次旅程时间在 10 分钟以内",
                First(trips, trip => trip.ArrivalTime is not null && trip.ArrivalTime >= Departure(trip) &&
                    trip.ArrivalTime - Departure(trip) <= TimeSpan.FromMinutes(10))),
            A("verticalSleeper", "train_outlined", "私人小窝", "乘坐过 CRH2E 纵向动卧列车",
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
                First(trips, trip => trip.MileageKm is > 0 and <= 20)),
            A("whatAgeIsThis", "history_edu_outlined", "今乃何世", "乘坐一次 2000 年之前停产的客车",
                FirstRollingStockMatch(trips, EarlyPassengerCoachModels)),
            A("centuryMeterGauge", "map_outlined", "碧色芳华", "乘坐经由昆河线的列车",
                First(trips, trip => RouteNames(trip).Any(
                    route => route.Contains("昆河线", StringComparison.Ordinal)))),
            A("vowAtQinling", "landscape_outlined", "海誓山盟", "在 5 月 20 日、2 月 14 日或七夕到访海拔 1,314 米的秦岭站",
                First(trips, UnlocksVowAtQinling)),
            A("differentRoutesSameDestination", "alt_route_outlined", "殊途同归", "在相同起终点（方向不限）间，经由至少 3 种不同路线",
                FirstDifferentRoutesSameDestination(trips)),
            A("dejaVu", "loop", "似曾相识", "至少两次乘坐除日期和车号外均完全一致的行程",
                FirstRepeatedTripCompletion(trips, 2)),
            A("traverseOneRegion", "route_outlined", "遍历一方", "经由区间去重后的累计里程达到 5,000 公里",
                FirstUniqueRouteMileageCompletion(trips, 5000)),
            A("halfTheRealm", "route_outlined", "半壁江山", "经由区间去重后的累计里程达到 80,000 公里",
                FirstUniqueRouteMileageCompletion(trips, 80000)),
            A("centuryDreamFulfilled", "route_outlined", "世纪梦圆", "经由区间去重后的累计里程达到 160,000 公里",
                FirstUniqueRouteMileageCompletion(trips, 160000)),
            A("spendsLikeWater", "currency_yen", "挥金如土", "单程票价超过 2,000 元",
                First(trips, trip => trip.Price > 2000)),
            A("wealthyTraveler", "account_balance_outlined", "腰缠万贯", "任意 30 天内的车票总支出超过 10,000 元",
                FirstThirtyDaySpendingCompletion(trips, 10000)),
            A("meritAndHonor", "military_tech_outlined", "功成名就", "乘坐至少一种荣誉机车牵引的列车",
                FirstRollingStockMatch(trips, HonorLocomotives)),
            A("firstTrip", "directions_walk_outlined", "始于足下", "首次录入行程",
                trips.FirstOrDefault()),
            A("thousandTickets", "collections_bookmark_outlined", "千千晚星", "累计出发 1,000 次",
                trips.Count >= 1000 ? trips[999] : null),
            A("fiftyThousandSpending", "account_balance_wallet_outlined", "千金散尽", "累计车票总支出超过 50,000 元",
                FirstCumulativeSpendingCompletion(trips, 50000)),
            A("reviewedTrainNumbers", "rate_review_outlined", "激扬文字", "累计点评过 200 个不同的车次",
                reviews.Where(review => review.EntityType.Equals("train", StringComparison.OrdinalIgnoreCase))
                    .Select(review => review.EntityKey.Trim())
                    .Where(key => key.Length > 0)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .Count() >= 200 ? trips.LastOrDefault() : null),
            A("fourThousandKmInDay", "calendar_view_day_outlined", "日行万里", "24 小时内的总移动里程超过 4,000 公里",
                FirstRolling24HourMileageCompletion(trips, 4000)),
            A("hundredDeparturesFromStation", "pin_drop_outlined", "脚步不止", "从单一车站出发 100 次",
                FirstStationDepartureCompletion(trips, 100)),
            A("multipleLocomotives", "precision_manufacturing_outlined", "其利断金", "乘坐同时由至少两台机车牵引或担当补机的列车",
                First(trips, trip => LocomotiveCount(trip.RollingStock) >= 2)),
            A("snowBlockingBlueGate", "severe_cold_outlined", "雪拥蓝关", "在 2008-01-10 至 2008-02-10 之间行经京广线武昌至广州间的任意区间",
                First(trips, UnlocksSnowBlockingBlueGate)),
            A("steamPower", "local_fire_department_outlined", "传统动力", "乘坐至少一种蒸汽机车牵引或担当补机的列车",
                FirstRollingStockMatch(trips, SteamLocomotives)),
            A("fourExtremes", "explore_outlined", "遍览四境", "在 60 天内分别到访漠河站、三亚站、阿克陶站、抚远站，次序不限",
                FirstFourExtremesCompletion(trips, TimeSpan.FromDays(60))),
            A("waterIsCalm", "water_outlined", "水何澹澹", "到访东戴河站",
                FirstStationVisit(trips, ["东戴河"])),
            A("roadBlazing", "account_balance_outlined", "筚路蓝缕", "到访中国原子城站",
                FirstStationVisit(trips, ["中国原子城"])),
            A("goddessYangtzeBridges", "architecture_outlined", "神女无恙", "行经全部承担客运的铁路长江大桥",
                FirstYangtzeBridgeCompletion(trips)),
            A("oneStoneThreeBirds", "filter_3_outlined", "一石三鸟", "单次行程同时满足其他至少三项成就的取得条件",
                null),
            A("unknownTerritory", "visibility_outlined", "未知领域", "取得任意隐藏成就",
                null),
            A("careerRecord", "emoji_events_outlined", "履历斐然", "取得其他所有常规成就",
                null),
            A("ancientMemory", "history_edu_outlined", "远古回忆", "录入 1995 年以前的行程",
                First(trips, trip => Departure(trip) < new DateTime(1995, 1, 1))),
            A("thousandCities", "location_on_outlined", "千城千面", "累计到访过 2,500 座不同的客运车站",
                FirstStationCompletion(trips, 2500)),
            A("rottenAxe", "calendar_month_outlined", "烂柯之人", "连续 365 天乘坐列车",
                FirstStreakCompletion(trips, 365)),
            A("roamFreely", "route_outlined", "随心徜徉", "分别行经全部客运线路的任意区间",
                FirstRouteCatalogCompletion(trips)),
            A("travelAllMountains", "public_outlined", "踏遍山河", "累计乘车里程至少 500,000 公里",
                FirstCumulativeMileageCompletion(trips, 500000)),
            A("immovableMountain", "accessibility_new", "不动如山", "持硬座或二等座无座车票乘坐至少 24 小时",
                First(trips, trip => NormalizedSeatType(trip.SeatType) == "无座" &&
                    ValidDuration(trip) >= TimeSpan.FromHours(24))),
            A("richerThanNation", "account_balance_outlined", "富可敌国", "任意 30 天内的车票总支出超过 50,000 元",
                FirstThirtyDaySpendingCompletion(trips, 50000)),
            A("flowersAmong", "auto_awesome_outlined", "百花丛中", "分别乘坐全部常规和谐号、复兴号小类型号",
                FirstCollectionCompletion(trips, smallEmuModels, trip => SmallEmuMatches(trip.RollingStock))),
            A("refinedMechanic", "precision_manufacturing_outlined", "精益求精", "分别乘坐全部和谐型与复兴型量产机车牵引的列车",
                FirstCollectionCompletion(trips, ModernLocomotives, trip => RollingStockMatches(trip.RollingStock, ModernLocomotives))),
            A("dawnBreaks", "history_edu_outlined", "曙光乍现", "分别乘坐全部东风型与韶山型量产机车牵引的列车",
                FirstCollectionCompletion(trips, DongfengShaoshanLocomotives, trip => RollingStockMatches(trip.RollingStock, DongfengShaoshanLocomotives))),
            A("hundredPeople", "people_outline", "百人百相", "分别乘坐全部客运段担当的列车",
                FirstCollectionCompletion(trips, AllPassengerCompanies, trip =>
                    AllPassengerCompanies.Where(company =>
                        (trip.CompanyName?.Contains(company, StringComparison.Ordinal) ?? false))
                        .ToHashSet(StringComparer.Ordinal))),
            A("thousandDeparturesFromStation", "pin_drop_outlined", "百转千回", "从单一车站出发 1,000 次",
                FirstStationDepartureCompletion(trips, 1000)),
            A("nonOrdinary", "workspace_premium_outlined", "非同凡人", "完成除本成就外其他所有成就（该成就可能随其他成就增补而失去）",
                null),
            A("friendshipForever", "handshake_outlined", "友谊长存", "乘坐至少一种早期进口机车牵引的列车",
                FirstRollingStockMatch(trips, EarlyImportedLocomotives)),
        };

        var aggregateIds = new HashSet<string>(
            ["oneStoneThreeBirds", "unknownTerritory", "careerRecord", "nonOrdinary"],
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

        if (values.Count != AchievementCategories.Count ||
            values.Select(item => item.Id).Distinct(StringComparer.Ordinal).Count() != values.Count)
            throw new InvalidOperationException("Achievement category mapping is incomplete or contains duplicate IDs.");

        return values
            .Select(item =>
            {
                var metadata = MetadataFor(item.Id);
                var progress = ProgressFor(item.Id, trips, reviews, today, fifteenYearsAgo);
                return item with
                {
                    Progress = progress,
                    Experience = ExperienceFor(
                        item.Id,
                        metadata,
                        item.TriggerTripId.HasValue,
                        trips),
                    Hidden = metadata.Hidden,
                    Note = metadata.Note,
                    NarrativeNote = metadata.NarrativeNote
                };
            })
            .OrderByDescending(item => item.TriggerTripId.HasValue)
            .ToList();
    }

    private static AchievementMetadata MetadataFor(string id) =>
        AchievementMetadataById.GetValueOrDefault(id) ?? new AchievementMetadata(20);

    private static bool IsHidden(string id) => MetadataFor(id).Hidden;

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
        AchievementMetadata metadata,
        bool unlocked,
        List<PublicTrip> trips)
    {
        if (!unlocked) return metadata.Experience;
        var experience = metadata.Experience;
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
            "steamPower" => Math.Max(
                0,
                CollectedCount(trips, trip =>
                    RollingStockMatches(trip.RollingStock, SteamLocomotives)) - 1) * 10,
            "verticalChina" => StationPairWindowBonus(trips, "漠河", "三亚"),
            "horizontalChina" => StationPairWindowBonus(trips, "阿克陶", "抚远"),
            "skyAndSea" => StationPairWindowBonus(trips, "雁石坪", "香港西九龙"),
            "fourFamousNorths" => Math.Max(
                0,
                VisitedStationCount(trips, ["阳泉北", "盘锦北", "孝感北", "邵阳北"]) - 1) * 5,
            "borderPorts" => Math.Max(
                0,
                VisitedStationCount(trips, ["阿拉山口", "二连", "满洲里", "绥芬河", "丹东", "崇左", "磨憨"]) - 1) * 5,
            "airRail" => Math.Max(0, AirportStationCount(trips) - 3) * 5,
            "multipleLocomotives" => Math.Max(0, MaxLocomotiveCount(trips) - 2) * 10,
            "unnecessaryExtra" => Math.Max(0, MaxSameTrainTicketChain(trips) - 3) * 10,
            "differentRoutesSameDestination" => Math.Max(
                0,
                MaxDifferentRoutesSameDestination(trips) - 3) * 10,
            _ => 0
        };
        experience += bonus;
        return metadata.MaxExperience is int maximum
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

    private static AchievementProgress? ProgressFor(
        string id,
        List<PublicTrip> trips,
        List<AchievementReview> reviews,
        DateTime today,
        DateTime fifteenYearsAgo) => id switch
    {
        "firstTrip" => P(trips.Count > 0 ? 1 : 0, 1),
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
        "allSeatTypes" => P(CollectedCount(trips, trip => SeatTypeMatches(trip.SeatType)), RegularSeatTypes.Count),
        "noSeat12Hours" => P(MaxDurationHours(trips.Where(trip => NormalizedSeatType(trip.SeatType) == "无座")), 12),
        "immovableMountain" => P(MaxDurationHours(trips.Where(trip => NormalizedSeatType(trip.SeatType) == "无座")), 24),
        "hundredTickets" => P(trips.Count, 100),
        "thousandTickets" => P(trips.Count, 1000),
        "hundredStations" => P(trips.SelectMany(trip => new[] { trip.FromStation.Trim(), trip.ToStation.Trim() }).Where(value => value.Length > 0).Distinct(StringComparer.Ordinal).Count(), 100),
        "thousandCities" => P(StationCount(trips), 2500),
        "thousandKilometers" => P(trips.Select(trip => trip.MileageKm).DefaultIfEmpty(0).Max(), 1000),
        "airRail" => P(AirportStationCount(trips), 3),
        "lonelyPlanet" => P(CollectedCount(trips, trip => new[] { "和若线", "格库线" }.Where(route => RouteNames(trip).Any(name => name.Contains(route, StringComparison.Ordinal)))), 2),
        "hundredThousandKilometers" => P(trips.Where(trip => trip.MileageKm > 0).Sum(trip => trip.MileageKm), 100000),
        "travelAllMountains" => P(trips.Where(trip => trip.MileageKm > 0).Sum(trip => trip.MileageKm), 500000),
        "fiftyThousandSpending" => P(trips.Sum(trip => trip.Price), 50000),
        "reviewedTrainNumbers" => P(
            reviews.Where(review => review.EntityType.Equals("train", StringComparison.OrdinalIgnoreCase))
                .Select(review => review.EntityKey.Trim())
                .Where(key => key.Length > 0)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .Count(),
            200),
        "archaeologyTeam" => P(OldestTripAgeYears(trips, today, fifteenYearsAgo), 15),
        "tenNumericTrains" => P(trips.Count(trip => Regex.IsMatch(trip.TrainNumber.Trim(), @"^\d+$")), 10),
        "tripleTransfer" => P(MaxTransferCount(trips), 2),
        "grandSlam" => P(RailwayBureauCount(trips), RailwayBureaus.Count),
        "hundredPeople" => P(PassengerCompanyCount(trips), AllPassengerCompanies.Count),
        "unnecessaryExtra" => P(MaxSameTrainTicketChain(trips), 3),
        "multipleChoices" => P(MaxDistinctTrainCountForRoute(trips), 10),
        "cardinalStations" => P(MaxCardinalStationCount(trips), 5),
        "eastRedSunRises" => P(VisitedStationCount(trips, ["东方红", "太阳升"]), 2),
        "fourExtremes" => P(VisitedStationCount(trips, ["漠河", "三亚", "阿克陶", "抚远"]), 4),
        "fourFamousNorths" => P(VisitedStationCount(trips, ["阳泉北", "盘锦北", "孝感北", "邵阳北"]), 1),
        "borderPorts" => P(VisitedStationCount(trips, ["阿拉山口", "二连", "满洲里", "绥芬河", "丹东", "崇左", "磨憨"]), 1),
        "verticalChina" => P(ShortestStationPairWindowDays(trips, "漠河", "三亚"), 14),
        "horizontalChina" => P(ShortestStationPairWindowDays(trips, "阿克陶", "抚远"), 14),
        "skyAndSea" => P(ShortestStationPairWindowDays(trips, "雁石坪", "香港西九龙"), 14),
        "goddessYangtzeBridges" => P(
            YangtzeBridgeCount(trips),
            AvailableYangtzeBridges.Select(bridge => bridge.Name).Distinct(StringComparer.Ordinal).Count()),
        "differentRoutesSameDestination" => P(MaxDifferentRoutesSameDestination(trips), 3),
        "completeTrainLetters" => P(trips.Select(trip => CommonTrainCategory(trip.TrainNumber)).Where(value => value is not null).Distinct(StringComparer.Ordinal).Count(), CommonTrainCategories.Count),
        "blueHorizon" => P(trips.Count(trip => ContainsRollingStock(trip, "CR200J")), 10),
        "railwayTrailblazer" => P(
            CollectedCount(trips, trip => RollingStockMatches(trip.RollingStock, EarlyEmuModels)),
            1),
        "meritAndHonor" => P(
            CollectedCount(trips, trip => RollingStockMatches(trip.RollingStock, HonorLocomotives)),
            1),
        "friendshipForever" => P(
            CollectedCount(trips, trip => RollingStockMatches(trip.RollingStock, EarlyImportedLocomotives)),
            1),
        "steamPower" => P(
            CollectedCount(trips, trip => RollingStockMatches(trip.RollingStock, SteamLocomotives)),
            1),
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
        "multipleLocomotives" => P(MaxLocomotiveCount(trips), 2),
        "roamFreely" => P(RouteCatalogCount(trips), Math.Max(1, RouteStations.Value.Count)),
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

    private static AchievementEvaluation A(
        string id, string icon, string title, string description, PublicTrip? trip)
    {
        if (!AchievementCategories.TryGetValue(id, out var category))
            throw new InvalidOperationException($"Achievement {id} has no category.");
        return new(id, category, icon, title, description, trip?.TicketId);
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

    private static bool ContainsRollingStock(PublicTrip trip, string value) =>
        RollingStockModelCodes(trip.RollingStock)
            .Any(code => code.Contains(value.ToUpperInvariant(), StringComparison.Ordinal));

    private static bool HasCoupledEmu(string? value) =>
        TrainModelParser.ParseTrainString(value)
            .Any(model => model.Category == TrainCategory.EMU && model.Numbers.Count > 1);

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
        return new RouteSectionKey(segment.RouteName, first, second);
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

    private static int LocomotiveCount(string? value) =>
        TrainModelParser.ParseTrainString(value)
            .Count(model => model.Category == TrainCategory.Locomotive);

    private static int MaxLocomotiveCount(IEnumerable<PublicTrip> trips) => trips
        .Select(trip => LocomotiveCount(trip.RollingStock))
        .DefaultIfEmpty(0)
        .Max();

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

    private static int RouteCatalogCount(IEnumerable<PublicTrip> trips)
    {
        var catalog = RouteStations.Value.Keys.ToHashSet(StringComparer.Ordinal);
        return trips
            .SelectMany(RouteNames)
            .Select(name => catalog.Contains(name)
                ? name
                : catalog.FirstOrDefault(route => route.Contains(name, StringComparison.Ordinal)))
            .Where(name => !string.IsNullOrEmpty(name))
            .Distinct(StringComparer.Ordinal)
            .Count();
    }

    private static PublicTrip? FirstRouteCatalogCompletion(IEnumerable<PublicTrip> trips)
    {
        var requiredCount = RouteStations.Value.Count;
        var covered = new HashSet<string>(StringComparer.Ordinal);
        foreach (var trip in trips)
        {
            foreach (var name in RouteNames(trip))
            {
                var match = RouteStations.Value.Keys.FirstOrDefault(route =>
                    route == name || route.Contains(name, StringComparison.Ordinal));
                if (match is not null) covered.Add(match);
            }
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
            var route = string.Join("|", RouteNames(trip));
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
            var route = string.Join("|", RouteNames(trip));
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

    private static bool UnlocksBorderCrossing(PublicTrip trip) => RouteSegments(trip).Any(segment =>
        BorderRouteMarkers.Any(marker => segment.RouteName.Contains(marker, StringComparison.Ordinal)) ||
        (segment.RouteName.Contains("中老昆万铁路昆磨段", StringComparison.Ordinal) &&
            (NormalizedStation(segment.FromStation) == "磨憨（境）" || NormalizedStation(segment.ToStation) == "磨憨（境）")));

    private static PublicTrip? FirstDifferentBorderCompletion(List<PublicTrip> trips)
    {
        var visits = new List<(string Border, bool Entry, DateTime Time, PublicTrip Trip)>();
        foreach (var trip in trips)
        foreach (var segment in RouteSegments(trip))
        {
            var border = BorderName(segment);
            if (border is null) continue;
            var entry = IsEntryDirection(segment);
            visits.Add((border, entry, entry ? Departure(trip) : (trip.ArrivalTime ?? Departure(trip)), trip));
        }
        visits.Sort((a, b) => a.Time != b.Time ? a.Time.CompareTo(b.Time) : a.Trip.TicketId.CompareTo(b.Trip.TicketId));
        foreach (var current in visits.Where(item => !item.Entry))
            if (visits.Any(previous => previous.Entry && previous.Border != current.Border && current.Time >= previous.Time && current.Time - previous.Time <= TimeSpan.FromDays(14)))
                return current.Trip;
        return null;
    }

    private static string? BorderName(RouteSegment segment)
    {
        var marker = BorderRouteMarkers.FirstOrDefault(value => segment.RouteName.Contains(value, StringComparison.Ordinal));
        if (marker is not null) return marker;
        return segment.RouteName.Contains("中老昆万铁路昆磨段", StringComparison.Ordinal) &&
            (NormalizedStation(segment.FromStation) == "磨憨（境）" || NormalizedStation(segment.ToStation) == "磨憨（境）") ? "磨憨（境）" : null;
    }

    private static bool IsEntryDirection(RouteSegment segment)
    {
        var from = NormalizedStation(segment.FromStation);
        var to = NormalizedStation(segment.ToStation);
        return from.Contains("交接", StringComparison.Ordinal) || from == "新义州" || from == "磨憨（境）" || from.Contains("（境）", StringComparison.Ordinal);
    }

    private static bool UnlocksQinlingPassage(PublicTrip trip)
    {
        var segments = RouteSegments(trip);
        return segments.Any(segment =>
                CoversRouteSection(segment, "兰渝线兰渭段", "渭源", "广元") ||
                CoversRouteSection(segment, "宝成线", "宝鸡", "阳平关") ||
                CoversRouteSection(segment, "西成客专线", "西安西", "汉中")) ||
            UnlocksXikangPassage(segments);
    }

    private static bool UnlocksXikangPassage(IReadOnlyList<RouteSegment> segments)
    {
        if (segments.Any(segment => CoversRouteSection(segment, "西康线", "西安东", "安康"))) return true;
        for (var index = 0; index + 1 < segments.Count; index++)
        {
            var first = segments[index];
            var second = segments[index + 1];
            if (CoversRouteSection(first, "西康线", "西安东", "大岭铺") &&
                IsXikangDirectSection(second, "大岭铺", "安康")) return true;
            if (IsXikangDirectSection(first, "安康", "大岭铺") &&
                CoversRouteSection(second, "西康线", "大岭铺", "西安东")) return true;
        }
        return false;
    }

    private static bool IsXikangDirectSection(RouteSegment segment, string from, string to)
    {
        if (!segment.RouteName.Contains("西康直通线", StringComparison.Ordinal)) return false;
        var actualFrom = NormalizedStation(segment.FromStation);
        var actualTo = NormalizedStation(segment.ToStation);
        var expectedFrom = NormalizedStation(from);
        var expectedTo = NormalizedStation(to);
        return (actualFrom == expectedFrom || expectedFrom == "安康" && actualFrom == "安康东") &&
            (actualTo == expectedTo || expectedTo == "安康" && actualTo == "安康东");
    }

    private static bool UnlocksHanxiWuchang(PublicTrip trip) => RouteSegments(trip).Any(segment =>
        CoversRouteSection(segment, "京广线", "汉西", "武昌"));

    private static bool UnlocksSnowBlockingBlueGate(PublicTrip trip)
    {
        var departure = Departure(trip);
        var arrival = trip.ArrivalTime ?? departure;
        var start = new DateTime(2008, 1, 10);
        var end = new DateTime(2008, 2, 10);
        if (arrival < start || departure >= end) return false;
        return RouteSegments(trip).Any(segment =>
            CoversRouteSection(segment, "京广线", "武昌", "广州"));
    }

    private static int YangtzeBridgeCount(IEnumerable<PublicTrip> trips)
    {
        var covered = new HashSet<string>(StringComparer.Ordinal);
        var bridges = AvailableYangtzeBridges;
        foreach (var trip in trips)
        {
            var segments = RouteSegments(trip);
            foreach (var bridge in bridges)
                if (segments.Any(segment => CoversRouteSection(
                        segment,
                        bridge.RouteName,
                        bridge.FromStation,
                        bridge.ToStation)))
                    covered.Add(bridge.Name);
        }
        return covered.Count;
    }

    private static PublicTrip? FirstYangtzeBridgeCompletion(List<PublicTrip> trips)
    {
        var covered = new HashSet<string>(StringComparer.Ordinal);
        var bridges = AvailableYangtzeBridges;
        var required = bridges
            .Select(bridge => bridge.Name)
            .ToHashSet(StringComparer.Ordinal);
        if (required.Count == 0) return null;
        foreach (var trip in trips)
        {
            var segments = RouteSegments(trip);
            foreach (var bridge in bridges)
                if (segments.Any(segment => CoversRouteSection(
                        segment,
                        bridge.RouteName,
                        bridge.FromStation,
                        bridge.ToStation)))
                    covered.Add(bridge.Name);
            if (required.IsSubsetOf(covered)) return trip;
        }
        return null;
    }

    private static IReadOnlyList<YangtzeBridge> AvailableYangtzeBridges
    {
        get
        {
            var routes = RouteStations.Value.Keys;
            return YangtzeBridges
                .Where(bridge => routes.Any(route =>
                    route == bridge.RouteName ||
                    route.Contains(bridge.RouteName, StringComparison.Ordinal) ||
                    bridge.RouteName.Contains(route, StringComparison.Ordinal)))
                .ToList();
        }
    }

    private static bool CoversRouteSection(RouteSegment segment, string routeName, string first, string second)
    {
        if (!segment.RouteName.Contains(routeName, StringComparison.Ordinal)) return false;
        var stations = RouteStations.Value.GetValueOrDefault(routeName) ??
            RouteStations.Value.FirstOrDefault(item => item.Key.Contains(routeName, StringComparison.Ordinal)).Value;
        if (stations is null) return false;
        if (!stations.TryGetValue(NormalizedStation(segment.FromStation), out var from) ||
            !stations.TryGetValue(NormalizedStation(segment.ToStation), out var to)) return false;
        if (!stations.TryGetValue(first, out var start) || !stations.TryGetValue(second, out var end))
            return false;
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
        command.CommandText = "SELECT r.route_name, s.station_name, s.station_index FROM routes r JOIN stations s USING(route_version_id)";
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

    private sealed record YangtzeBridge(
        string Name,
        string RouteName,
        string FromStation,
        string ToStation);

    private sealed record StationVisit(string Station, DateTime Time, PublicTrip Trip);

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();
}
