import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/achievement_engine.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/trip_record.dart';

void main() {
  group('new rolling stock achievements', () {
    const cases = [
      (DashboardAchievementKind.snowWelcomesSpring, 'CR400BF-C-5162'),
      (DashboardAchievementKind.moistensJiangnan, 'CR400BF-Z-0524'),
      (DashboardAchievementKind.facingTheWorld, 'CR400BF-0031'),
      (DashboardAchievementKind.facingTheWorld, 'CR400BF-G-0051'),
      (DashboardAchievementKind.facingTheWorld, 'CR400AF-G-0021'),
      (DashboardAchievementKind.revivalPrototype, 'CR400BF-0305'),
      (DashboardAchievementKind.revivalPrototype, 'CR400BF-0503'),
      (DashboardAchievementKind.revivalPrototype, 'CR400BF-0507'),
      (DashboardAchievementKind.revivalPrototype, 'CR400AF-0207'),
      (DashboardAchievementKind.revivalPrototype, 'CR400AF-0208'),
      (DashboardAchievementKind.revivalPrototype, 'CR300AF-0001'),
      (DashboardAchievementKind.revivalPrototype, 'CR300AF-0003'),
      (DashboardAchievementKind.revivalPrototype, 'CR300AF-0004'),
      (DashboardAchievementKind.revivalPrototype, 'CR300BF-0002'),
      (DashboardAchievementKind.revivalPrototype, 'CR300BF-0005'),
      (DashboardAchievementKind.revivalPrototype, 'CR300BF-0006'),
      (DashboardAchievementKind.vibrantJourney, 'CRH380A-0251'),
      (DashboardAchievementKind.vibrantJourney, 'CRH380A-0252'),
      (DashboardAchievementKind.vibrantJourney, 'CRH380A-0253'),
      (DashboardAchievementKind.vibrantJourney, 'CRH380A-0254'),
      (DashboardAchievementKind.vibrantJourney, 'CRH380A-0255'),
      (DashboardAchievementKind.vibrantJourney, 'CRH380A-0256'),
      (DashboardAchievementKind.vibrantJourney, 'CRH380A-0257'),
      (DashboardAchievementKind.vibrantJourney, 'CRH380A-0258'),
      (DashboardAchievementKind.vibrantJourney, 'CRH380A-0259'),
    ];

    for (final (kind, rollingStock) in cases) {
      test('${kind.name} matches $rollingStock', () {
        final achievement = _achievement([
          _trip(id: 1, rollingStock: '配属 $rollingStock 担当'),
        ], kind);

        expect(achievement.isUnlocked, isTrue);
        expect(achievement.unlockedBy?.id, 1);
      });
    }

    test('vibrantJourney excludes numbers outside 0251 through 0259', () {
      final achievement = _achievement([
        _trip(id: 1, rollingStock: 'CRH380A-0260'),
      ], DashboardAchievementKind.vibrantJourney);

      expect(achievement.isUnlocked, isFalse);
    });
  });

  test('multipleChoices unlocks on the tenth distinct train in one route', () {
    final trips = [
      for (var index = 0; index < 9; index++)
        _trip(id: index + 1, trainNumber: 'G${index + 1}'),
      _trip(id: 10, trainNumber: ' g1 '),
      _trip(id: 11, trainNumber: 'G11', fromStation: '上海站', toStation: '北京南站'),
      _trip(id: 12, trainNumber: 'G10'),
    ];

    final achievement = _achievement(
      trips,
      DashboardAchievementKind.multipleChoices,
    );

    expect(achievement.unlockedBy?.id, 12);
  });

  test('publicDisplayOfAffection requires both May 20 and coupled stock', () {
    final matching = _trip(
      id: 1,
      departureTime: DateTime(2026, 5, 20, 8),
      rollingStock: 'CR400AF&CR400AF',
    );
    final wrongDate = _trip(
      id: 2,
      departureTime: DateTime(2026, 5, 21, 8),
      rollingStock: 'CR400AF&CR400AF',
    );
    final uncoupled = _trip(
      id: 3,
      departureTime: DateTime(2026, 5, 20, 7),
      rollingStock: 'CR400AF',
    );

    expect(
      _achievement([
        uncoupled,
        wrongDate,
        matching,
      ], DashboardAchievementKind.publicDisplayOfAffection).unlockedBy?.id,
      1,
    );
  });

  test('farsighted unlocks when the seat number contains upper level', () {
    final achievement = _achievement([
      _trip(id: 1, seatNumber: '03车上层08A号'),
    ], DashboardAchievementKind.farsighted);

    expect(achievement.isUnlocked, isTrue);
  });

  test('new journey achievements use their exact thresholds', () {
    expect(
      _achievement([
        _trip(id: 1, price: 1),
      ], DashboardAchievementKind.oneYuanJourney).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(id: 1, duration: const Duration(minutes: 10)),
      ], DashboardAchievementKind.miniTurnaround).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(id: 1, duration: null),
      ], DashboardAchievementKind.miniTurnaround).isUnlocked,
      isFalse,
    );
  });

  test('cardinal stations unlock for one city', () {
    final stations = ['北京站', '北京东站', '北京西站', '北京南站', '北京北站'];
    final achievement = _achievement([
      for (var index = 0; index < stations.length; index++)
        _trip(id: index + 1, fromStation: stations[index], toStation: '上海虹桥站'),
    ], DashboardAchievementKind.cardinalStations);

    expect(achievement.isUnlocked, isTrue);
    expect(achievement.unlockedBy?.id, 5);
  });

  test('cardinal center means the station has no directional suffix', () {
    final achievement = _achievement([
      _trip(id: 1, fromStation: '北京东站'),
      _trip(id: 2, fromStation: '北京西站'),
      _trip(id: 3, fromStation: '北京南站'),
      _trip(id: 4, fromStation: '北京北站'),
      _trip(id: 5, fromStation: '北京机场站'),
    ], DashboardAchievementKind.cardinalStations);

    expect(achievement.isUnlocked, isFalse);
  });

  test('letter and rolling stock achievements recognize their ranges', () {
    expect(
      _achievement([
        _trip(id: 1, trainNumber: ' A123'),
      ], DashboardAchievementKind.ancientLetters).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        _trip(id: 1, rollingStock: 'CRH2E-2464'),
      ], DashboardAchievementKind.verticalSleeper).isUnlocked,
      isTrue,
    );

    const categories = ['G1', 'D1', 'C1', 'Z1', 'T1', 'K1', 'Y1', 'S1', '123'];
    final categoryAchievement = _achievement([
      for (var index = 0; index < categories.length; index++)
        _trip(id: index + 1, trainNumber: categories[index]),
    ], DashboardAchievementKind.completeTrainLetters);
    expect(categoryAchievement.isUnlocked, isTrue);
  });

  test('blueHorizon unlocks on the tenth CR200J trip', () {
    final achievement = _achievement([
      for (var index = 0; index < 10; index++)
        _trip(id: index + 1, rollingStock: 'CR200J'),
    ], DashboardAchievementKind.blueHorizon);

    expect(achievement.isUnlocked, isTrue);
    expect(achievement.unlockedBy?.id, 10);
  });
}

DashboardAchievement _achievement(
  List<TripRecord> trips,
  DashboardAchievementKind kind,
) => buildDashboardAchievements(
  trips,
).singleWhere((achievement) => achievement.kind == kind);

TripRecord _trip({
  required int id,
  String trainNumber = 'G1',
  String? rollingStock,
  String fromStation = '北京南站',
  String toStation = '上海虹桥站',
  DateTime? departureTime,
  String? seatNumber,
  double price = 0,
  Duration? duration = const Duration(hours: 4),
}) => TripRecord(
  id: id,
  trainNumber: trainNumber,
  rollingStock: rollingStock,
  fromStation: fromStation,
  toStation: toStation,
  departureTime: departureTime ?? DateTime(2026, 1, id, 8),
  arrivalTime: duration == null
      ? null
      : (departureTime ?? DateTime(2026, 1, id, 8)).add(duration),
  viaRouteSegments: const [],
  seatNumber: seatNumber,
  price: price,
);
