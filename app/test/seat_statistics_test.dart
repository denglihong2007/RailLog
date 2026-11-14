import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/seat_statistics.dart';

DashboardTripEntry _trip({
  String? seatType,
  String? seatNumber,
  bool isRailTrip = true,
  int id = 1,
}) => DashboardTripEntry(
  id: id,
  trainNumber: 'G$id',
  fromStation: '北京南',
  toStation: '上海虹桥',
  departureTime: DateTime(2026, 1, 1, 8),
  arrivalTime: DateTime(2026, 1, 1, 13),
  mileageKm: 1300,
  seatType: seatType,
  seatNumber: seatNumber,
  price: 600,
  isRailTrip: isRailTrip,
);

void main() {
  test('字母座位与数字座位按同一排五个位置合并', () {
    final statistics = SeatStatistics.fromTrips([
      _trip(id: 1, seatType: '二等座', seatNumber: '5车12A号'),
      _trip(id: 2, seatType: '二等座', seatNumber: '5车12B号'),
      _trip(id: 3, seatType: '二等座', seatNumber: '5车12C号'),
      _trip(id: 4, seatType: '二等座', seatNumber: '5车12D号'),
      _trip(id: 5, seatType: '二等座', seatNumber: '5车12F号'),
      _trip(id: 6, seatType: '硬座', seatNumber: '5车10号'),
      _trip(id: 7, seatType: '硬座', seatNumber: '5车11号'),
      _trip(id: 8, seatType: '硬座', seatNumber: '5车12号'),
      _trip(id: 9, seatType: '硬座', seatNumber: '5车13号'),
      _trip(id: 10, seatType: '硬座', seatNumber: '5车14号'),
      _trip(id: 11, seatType: '硬座', seatNumber: '5车15号'),
      _trip(id: 12, seatType: '硬座', seatNumber: '5车16号'),
      _trip(id: 13, seatType: '硬座', seatNumber: '5车17号'),
      _trip(id: 14, seatType: '硬座', seatNumber: '5车18号'),
      _trip(id: 15, seatType: '硬座', seatNumber: '5车19号'),
    ]);

    expect(statistics.positions.map((position) => position.letter), [
      'A',
      'B',
      'C',
      'D',
      'F',
    ]);
    expect(statistics.positions.map((position) => position.numberLabel), [
      '5/0',
      '6/1',
      '7/2',
      '8/3',
      '9/4',
    ]);
    expect(statistics.positions.map((position) => position.count), [
      3,
      3,
      3,
      3,
      3,
    ]);
    expect(statistics.positionedTripCount, 15);
  });

  test('上中下铺单独统计，且不进入座席位置', () {
    final statistics = SeatStatistics.fromTrips([
      _trip(id: 1, seatType: '硬卧', seatNumber: '5车12号上铺'),
      _trip(id: 2, seatType: '硬卧', seatNumber: '5车13号中铺'),
      _trip(id: 3, seatType: '硬卧', seatNumber: '5车14号下铺'),
      _trip(id: 4, seatType: '硬卧上铺', seatNumber: '5车15号'),
      _trip(id: 5, seatType: '硬卧', seatNumber: '5车16号'),
    ]);

    expect(statistics.berths.map((berth) => berth.name), ['上铺', '中铺', '下铺']);
    expect(statistics.berths.map((berth) => berth.count), [2, 1, 1]);
    expect(statistics.berthTripCount, 4);
    expect(statistics.positionedTripCount, 0);
    expect(statistics.seatClasses.single.name, '硬卧');
    expect(statistics.seatClasses.single.count, 5);
  });

  test('卧代座按普通座位统计，不当作卧铺', () {
    final statistics = SeatStatistics.fromTrips([
      _trip(id: 1, seatType: '硬卧代硬座', seatNumber: '5车12号'),
      _trip(id: 2, seatType: '混编硬卧代硬座', seatNumber: '5车19号'),
    ]);

    expect(statistics.positionedTripCount, 2);
    // 12 → 个位 2 → C；19 → 个位 9 → F。
    expect(statistics.positions[2].count, 1);
    expect(statistics.positions[4].count, 1);
    expect(statistics.berthTripCount, 0);
    expect(statistics.seatClasses.map((item) => item.name), [
      '混编硬卧代硬座',
      '硬卧代硬座',
    ]);
  });

  test('无座与不对号只进入席别统计', () {
    final statistics = SeatStatistics.fromTrips([
      _trip(id: 1, seatType: '二等座', seatNumber: '5车无座'),
      _trip(id: 2, seatType: '硬座', seatNumber: '加3车不对号入座'),
    ]);

    expect(statistics.positionedTripCount, 0);
    expect(statistics.seatClasses.map((item) => item.name), ['二等座', '硬座']);
    expect(statistics.seatClassTripCount, 2);
  });

  test('非铁路行程不参与统计', () {
    final statistics = SeatStatistics.fromTrips([
      _trip(id: 1, seatType: '二等座', seatNumber: '5车12A号', isRailTrip: false),
    ]);

    expect(statistics.positionedTripCount, 0);
    expect(statistics.seatClasses, isEmpty);
  });

  test('未知座位号 0 不落到任何位置', () {
    final statistics = SeatStatistics.fromTrips([
      _trip(seatType: '二等座', seatNumber: '5车0号'),
    ]);

    expect(statistics.positionedTripCount, 0);
    expect(statistics.seatClasses.single.name, '二等座');
  });

  test('小写字母与加挂车厢照常解析', () {
    final statistics = SeatStatistics.fromTrips([
      _trip(seatType: '二等座', seatNumber: '加5车12c号'),
    ]);

    expect(statistics.positions[2].count, 1);
  });

  test('席别按次数降序排列', () {
    final statistics = SeatStatistics.fromTrips([
      _trip(id: 1, seatType: '二等座', seatNumber: '5车1A号'),
      _trip(id: 2, seatType: '二等座', seatNumber: '5车2A号'),
      _trip(id: 3, seatType: '硬座', seatNumber: '5车3号'),
    ]);

    expect(statistics.seatClasses.map((item) => '${item.name}:${item.count}'), [
      '二等座:2',
      '硬座:1',
    ]);
  });

  test('每条统计都保留对应行程', () {
    final statistics = SeatStatistics.fromTrips([
      _trip(id: 1, seatType: '二等座', seatNumber: '5车12A号'),
      _trip(id: 2, seatType: '硬卧', seatNumber: '5车13号下铺'),
      _trip(id: 3, seatType: '二等座', seatNumber: '5车14F号'),
    ]);

    expect(statistics.positions[0].trips.single.id, 1);
    expect(statistics.positions[4].trips.single.id, 3);
    expect(statistics.berths[2].trips.single.id, 2);
    expect(statistics.berths[2].trips.single.seatNumber, '5车13号下铺');
    expect(statistics.seatClasses.first.name, '二等座');
    expect(statistics.seatClasses.first.trips.map((trip) => trip.id).toSet(), {
      1,
      3,
    });
  });

  test('没有座位信息时五个位置仍完整展示', () {
    final statistics = SeatStatistics.fromTrips(const []);

    expect(statistics.positions, hasLength(5));
    expect(
      statistics.positions.every((position) => position.count == 0),
      isTrue,
    );
    expect(statistics.berths, hasLength(3));
    expect(statistics.seatClasses, isEmpty);
    expect(statistics.positionedTripCount, 0);
  });
}
