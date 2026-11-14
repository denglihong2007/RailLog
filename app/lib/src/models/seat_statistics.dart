import 'package:raillog/src/models/dashboard_trip_entry.dart';
import 'package:raillog/src/models/seat_selection.dart';

/// 一排座位的五个位置。字母位置来自动车组，数字位置来自普速车厢，两者
/// 在车体里是同一排的同一处，因此合并成同一条统计。
const _positionLetters = ['A', 'B', 'C', 'D', 'F'];

/// 数字座位按席位号个位归位。0/5 靠窗、1/6 中间、2/7 靠过道，
/// 另侧是 3/8 靠过道、4/9 靠窗。
const _positionNumberLabels = ['5/0', '6/1', '7/2', '8/3', '9/4'];

const _berthNames = ['上铺', '中铺', '下铺'];

const _letterPositions = {'A': 0, 'B': 1, 'C': 2, 'D': 3, 'F': 4};

const _berthPositions = {'上铺': 0, '中铺': 1, '下铺': 2};

/// 个位 → 一排五座里的位置序号；窗(5/0)(6/1)(7/2)道(8/3)(9/4)窗。
int? _positionForUnits(int units) => switch (units) {
  0 || 5 => 0,
  1 || 6 => 1,
  2 || 7 => 2,
  3 || 8 => 3,
  4 || 9 => 4,
  _ => null,
};

class SeatPositionStat {
  const SeatPositionStat({
    required this.letter,
    required this.numberLabel,
    required this.count,
    required this.trips,
  });

  final String letter;

  /// 同一物理位置的数字座位号尾数，如 `5/0`。
  final String numberLabel;
  final int count;

  /// 落在这个位置上的行程，最近的在前。
  final List<DashboardTripEntry> trips;
}

class BerthStat {
  const BerthStat({
    required this.name,
    required this.count,
    required this.trips,
  });

  final String name;
  final int count;
  final List<DashboardTripEntry> trips;
}

class SeatClassStat {
  const SeatClassStat({
    required this.name,
    required this.count,
    required this.trips,
  });

  final String name;
  final int count;
  final List<DashboardTripEntry> trips;
}

/// 由行程记录汇总出的坐席、铺位、席别统计。
class SeatStatistics {
  const SeatStatistics({
    required this.positions,
    required this.berths,
    required this.seatClasses,
    required this.positionedTripCount,
  });

  factory SeatStatistics.fromTrips(Iterable<DashboardTripEntry> trips) {
    final positionTrips = List.generate(
      _positionLetters.length,
      (_) => <DashboardTripEntry>[],
    );
    final berthTrips = List.generate(
      _berthNames.length,
      (_) => <DashboardTripEntry>[],
    );
    final classTrips = <String, List<DashboardTripEntry>>{};
    var positionedTripCount = 0;

    for (final trip in trips) {
      if (!trip.isRailTrip) continue;
      final seat = _SeatAssignment.parse(trip.seatType, trip.seatNumber);
      final seatClass = seat.seatClass;
      if (seatClass != null && seatClass.isNotEmpty) {
        classTrips.putIfAbsent(seatClass, () => []).add(trip);
      }
      final berth = seat.berth;
      if (berth != null) {
        final index = _berthPositions[berth];
        if (index != null) berthTrips[index].add(trip);
        continue;
      }
      final position = seat.positionIndex;
      if (position == null) continue;
      positionTrips[position].add(trip);
      positionedTripCount++;
    }

    final seatClasses =
        classTrips.entries
            .map(
              (entry) => SeatClassStat(
                name: entry.key,
                count: entry.value.length,
                trips: _newestFirst(entry.value),
              ),
            )
            .toList()
          ..sort((a, b) {
            final byCount = b.count.compareTo(a.count);
            return byCount != 0 ? byCount : a.name.compareTo(b.name);
          });

    return SeatStatistics(
      positions: List<SeatPositionStat>.unmodifiable([
        for (var index = 0; index < _positionLetters.length; index++)
          SeatPositionStat(
            letter: _positionLetters[index],
            numberLabel: _positionNumberLabels[index],
            count: positionTrips[index].length,
            trips: _newestFirst(positionTrips[index]),
          ),
      ]),
      berths: List<BerthStat>.unmodifiable([
        for (var index = 0; index < _berthNames.length; index++)
          BerthStat(
            name: _berthNames[index],
            count: berthTrips[index].length,
            trips: _newestFirst(berthTrips[index]),
          ),
      ]),
      seatClasses: List<SeatClassStat>.unmodifiable(seatClasses),
      positionedTripCount: positionedTripCount,
    );
  }

  final List<SeatPositionStat> positions;
  final List<BerthStat> berths;
  final List<SeatClassStat> seatClasses;

  /// 能落进一排五座、且不是卧铺的行程数。
  final int positionedTripCount;

  int get berthTripCount => berths.fold(0, (sum, berth) => sum + berth.count);

  int get seatClassTripCount =>
      seatClasses.fold(0, (sum, item) => sum + item.count);

  int get maxPositionCount => positions.fold(
    0,
    (max, position) => position.count > max ? position.count : max,
  );
}

List<DashboardTripEntry> _newestFirst(List<DashboardTripEntry> trips) {
  final result = trips.toList()
    ..sort((a, b) {
      final byTime = b.departureTime.compareTo(a.departureTime);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
  return List<DashboardTripEntry>.unmodifiable(result);
}

/// 从落库的席别与座位号里拆出统计需要的字段，规则与座位编辑器保持一致。
class _SeatAssignment {
  const _SeatAssignment({
    this.seatClass,
    this.berth,
    this.letter,
    this.number,
    this.isSleeper = false,
  });

  final String? seatClass;
  final String? berth;
  final String? letter;
  final int? number;
  final bool isSleeper;

  int? get positionIndex {
    // 卧铺的号码是铺位号，不是一排五座里的座号。
    if (isSleeper) return null;
    final positionLetter = letter;
    if (positionLetter != null) return _letterPositions[positionLetter];
    final seatNumber = number;
    if (seatNumber == null || seatNumber <= 0) return null;
    return _positionForUnits(seatNumber % 10);
  }

  static _SeatAssignment parse(String? rawType, String? rawNumber) {
    final type = rawType?.trim() ?? '';
    // 位置字母只认大写；票面 OCR 可能给成小写。
    final number = (rawNumber ?? '').trim().toUpperCase();
    var seatClass = type;
    String? typeBerth;
    // 旧数据把铺位写在席别里（硬卧上铺），先剥出来归到铺位统计。
    final berthMatch = RegExp(r'^(.*?)(上铺|中铺|下铺)$').firstMatch(type);
    if (berthMatch != null) {
      typeBerth = berthMatch.group(2);
      seatClass = berthMatch.group(1)!.trim();
    }

    final baseSeatType = splitSeatType(seatClass).seatType;
    final typeIsSleeper = baseSeatType.contains('卧');

    var remaining = number;
    final carriage = RegExp(r'^(?:不指定车厢|(?:加)?\d+车)').firstMatch(remaining);
    if (carriage != null) remaining = remaining.substring(carriage.end);
    if (remaining == '无座' || remaining == '不对号入座') {
      return _SeatAssignment(
        seatClass: _nonEmpty(seatClass),
        isSleeper: typeIsSleeper,
      );
    }

    final seatMatch = RegExp(
      r'^(\d{1,3})(?:号)?(A|B|C|D|F|上铺|中铺|下铺)?(?:号)?$',
    ).firstMatch(remaining);
    if (seatMatch == null) {
      return _SeatAssignment(
        seatClass: _nonEmpty(seatClass),
        isSleeper: typeIsSleeper,
      );
    }

    final suffix = seatMatch.group(2);
    final suffixBerth = _berthPositions.containsKey(suffix) ? suffix : null;
    final berth = suffixBerth ?? typeBerth;
    return _SeatAssignment(
      seatClass: _nonEmpty(seatClass),
      berth: berth,
      letter: _letterPositions.containsKey(suffix) ? suffix : null,
      number: int.tryParse(seatMatch.group(1)!),
      isSleeper: berth != null || typeIsSleeper,
    );
  }
}

String? _nonEmpty(String value) => value.isEmpty ? null : value;
