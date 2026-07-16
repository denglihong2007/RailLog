import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/achievement_engine.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/models/trip_record.dart';

void main() {
  test('轴温过高仅由 CR400BF-5033 车型解锁', () {
    final wrongModel = _trip(id: 1, rollingStock: 'CR400BF-5032');
    final matchingModel = _trip(id: 2, rollingStock: 'CR400BF-5033');

    expect(
      _achievement([
        wrongModel,
      ], DashboardAchievementKind.axleOverheat).isUnlocked,
      isFalse,
    );
    expect(
      _achievement([
        wrongModel,
        matchingModel,
      ], DashboardAchievementKind.axleOverheat).unlockedBy?.id,
      matchingModel.id,
    );
  });

  test('优势在我可由徐州或徐州东解锁', () {
    final xuzhouDeparture = _trip(id: 1, fromStation: '徐州站');
    final xuzhouEastArrival = _trip(
      id: 2,
      toStation: '徐州东',
      arrivalTime: DateTime(2026, 1, 3, 9),
    );

    expect(
      _achievement([
        xuzhouDeparture,
      ], DashboardAchievementKind.advantageIsMine).isUnlocked,
      isTrue,
    );
    expect(
      _achievement([
        xuzhouEastArrival,
      ], DashboardAchievementKind.advantageIsMine).isUnlocked,
      isTrue,
    );
  });

  test('站台沉降兼容站名后缀且要求实际探访', () {
    final notArrived = _trip(id: 1, toStation: '杭州东站');
    final arrived = _trip(
      id: 2,
      toStation: '杭州东站',
      arrivalTime: DateTime(2026, 1, 3, 9),
    );

    expect(
      _achievement([
        notArrived,
      ], DashboardAchievementKind.platformSubsidence).isUnlocked,
      isFalse,
    );
    expect(
      _achievement([
        arrived,
      ], DashboardAchievementKind.platformSubsidence).isUnlocked,
      isTrue,
    );
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
  String? rollingStock,
  String fromStation = '北京南',
  String toStation = '上海虹桥',
  DateTime? arrivalTime,
}) => TripRecord(
  id: id,
  trainNumber: 'G$id',
  rollingStock: rollingStock,
  fromStation: fromStation,
  toStation: toStation,
  departureTime: DateTime(2026, 1, 1, 8).add(Duration(days: id)),
  arrivalTime: arrivalTime,
  viaRouteSegments: const [],
);
