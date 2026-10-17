import 'package:raillog/src/models/station_pair_distance.dart';

class TrainScheduleStop {
  const TrainScheduleStop({
    required this.stationName,
    required this.stationNo,
    required this.arriveTime,
    required this.startTime,
    required this.runningTime,
    required this.arriveDay,
    required this.arriveDayDifference,
    this.mileage,
    this.arrivalDateTime,
    this.departureDateTime,
  });

  final String stationName;
  final String stationNo;
  final String arriveTime;
  final String startTime;
  final String runningTime;
  final String arriveDay;
  final int arriveDayDifference;
  final double? mileage;
  final DateTime? arrivalDateTime;
  final DateTime? departureDateTime;

  TrainScheduleStop copyWith({
    DateTime? arrivalDateTime,
    DateTime? departureDateTime,
  }) {
    return TrainScheduleStop(
      stationName: stationName,
      stationNo: stationNo,
      arriveTime: arriveTime,
      startTime: startTime,
      runningTime: runningTime,
      arriveDay: arriveDay,
      arriveDayDifference: arriveDayDifference,
      mileage: mileage,
      arrivalDateTime: arrivalDateTime,
      departureDateTime: departureDateTime,
    );
  }

  factory TrainScheduleStop.fromJson(Map<String, dynamic> json) {
    return TrainScheduleStop(
      stationName: (json['station_name']?.toString() ?? '').replaceAll(
        RegExp(r'\s+'),
        '',
      ),
      stationNo: json['station_no'] ?? '',
      arriveTime: json['arrive_time'] ?? '',
      startTime: json['start_time'] ?? '',
      runningTime: json['running_time'] ?? '',
      arriveDay: json['arrive_day_str'] ?? '',
      arriveDayDifference:
          int.tryParse(json['arrive_day_diff']?.toString() ?? '') ?? 0,
      mileage: (json['mileage'] as num?)?.toDouble(),
    );
  }
}

/// 站名归一化：去掉首尾空白与结尾的「站」。
///
/// 历史时刻表里的站名与 12306、车票上的站名未必逐字相同（「北京南」对「北京南站」），
/// 两边比对前都走这一遍。仓库里另有三处各自的归一化（地图轨迹、站站查询的输入），
/// 它们面对的脏数据不同，不要强行合并。
String normalizeStationName(String value) =>
    value.trim().replaceFirst(RegExp(r'站$'), '');

double? historicalJourneyMileage(
  TrainScheduleStop departure,
  TrainScheduleStop arrival,
) {
  final departureMileage = departure.mileage;
  final arrivalMileage = arrival.mileage;
  if (departureMileage == null || arrivalMileage == null) return null;

  final distance = (arrivalMileage - departureMileage).abs();
  return distance > 0 ? distance : null;
}

/// 所选区间里每一对相邻站的里程，全部来自站序自带的累计里程。
///
/// 途经线路推断要的是「这一段大概多远」，而站序里每一站都写着从始发站起算的累计
/// 里程，相邻两站相减就是这一段 —— 不必再对每对相邻站各打一次里程接口。
/// 缺里程或里程差为 0 的段给 null，推断会退回最短路径。
List<StationPairDistance> historicalSectionDistances(
  List<TrainScheduleStop> stops,
  int departureStopIndex,
  int arrivalStopIndex,
) {
  return _sectionDistances(
    stops,
    (index) => _cumulativeMileageAt(stops, index),
    departureStopIndex,
    arrivalStopIndex,
  );
}

/// 用 [reference]（历史站序，带累计里程）的里程，给 [stops]（在线站序，不带里程）
/// 所选区间逐段算里程。站序本身仍用 [stops] 的，换的只是里程。
///
/// 对齐靠一条**单调游标**：从游标处往后找当前站，命中就记下它的里程、把游标推到命中位置
/// 之后；**没命中不动游标** —— 扫到末尾就把游标留在那里的话，一个缺失的中间站会让后面
/// 每一站都跟着对不上。
///
/// 单调（而不是先建一张「站名 → 里程」的表）是折返车唯一正确的走法：西安换向的车在
/// 灞桥→西安→灞桥→田王 里同名站出现两次，累计里程递增（x、x+10、x+20），游标依次落到
/// 去程灞桥、西安、回程灞桥，两段才都是 10 km；查表一个站名只能取到一个里程，两段里
/// 必有一段错。
///
/// 对不上的站里程记 null，挨着它的那两段跟着为 null，推断退回最短路径
/// （与 [historicalSectionDistances] 的约定一致）。
List<StationPairDistance> historicalSectionDistancesFromReference(
  List<TrainScheduleStop> stops,
  List<TrainScheduleStop> reference,
  int departureStopIndex,
  int arrivalStopIndex,
) {
  final aligned = List<double?>.filled(stops.length, null);
  var cursor = 0;
  for (var index = 0; index < stops.length; index++) {
    final name = normalizeStationName(stops[index].stationName);
    if (name.isEmpty) continue;
    for (var probe = cursor; probe < reference.length; probe++) {
      if (normalizeStationName(reference[probe].stationName) != name) continue;
      aligned[index] = _cumulativeMileageAt(reference, probe);
      cursor = probe + 1;
      break;
    }
  }
  return _sectionDistances(
    stops,
    (index) => aligned[index],
    departureStopIndex,
    arrivalStopIndex,
  );
}

/// 站序里第 [index] 站的累计里程；缺失记 null。
///
/// 历史库把「没有里程」存成 0.0 而不是 NULL（建库脚本的 normalize_mileage、表结构的
/// `REAL NOT NULL DEFAULT 0`、接口侧的 ReadDouble 都这么落），所以非始发站的 0 或负值
/// 只能理解成缺失：真按 0 算，这一段就成了「从 0 到 900」的巨大里程，经由线路跟着整条
/// 错掉。始发站本来就是 0，不能误伤。
double? _cumulativeMileageAt(List<TrainScheduleStop> stops, int index) {
  final mileage = stops[index].mileage;
  if (mileage == null) return null;
  if (index > 0 && mileage <= 0) return null;
  return mileage;
}

/// 按 [mileageAt] 给出的累计里程，把所选区间的相邻站对折成 [StationPairDistance]。
List<StationPairDistance> _sectionDistances(
  List<TrainScheduleStop> stops,
  double? Function(int index) mileageAt,
  int departureStopIndex,
  int arrivalStopIndex,
) {
  if (stops.isEmpty ||
      departureStopIndex < 0 ||
      arrivalStopIndex >= stops.length ||
      arrivalStopIndex <= departureStopIndex) {
    return const [];
  }

  return List.generate(arrivalStopIndex - departureStopIndex, (offset) {
    final from = departureStopIndex + offset;
    final to = from + 1;
    final fromMileage = mileageAt(from);
    final toMileage = mileageAt(to);
    return StationPairDistance(
      fromStation: stops[from].stationName,
      toStation: stops[to].stationName,
      distanceKm: fromMileage == null || toMileage == null
          ? null
          : _positiveDistance(fromMileage, toMileage),
    );
  }, growable: false);
}

/// 相邻两站累计里程之差；两边一样（原地折返的脏数据）时给 null。
double? _positiveDistance(double fromMileage, double toMileage) {
  final distance = (toMileage - fromMileage).abs();
  return distance > 0 ? distance : null;
}
