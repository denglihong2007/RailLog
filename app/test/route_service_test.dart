import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/station_pair_distance.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/services/route_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // 测试环境没有注册 path_provider 插件，用临时目录顶替应用支持目录，
  // 否则 RouteService 把打包的 routes.db 拷到可写目录时会抛 MissingPluginException。
  final supportDirectory = Directory.systemTemp.createTempSync(
    'raillog-route-service-',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => switch (call.method) {
          'getApplicationSupportDirectory' ||
          'getTemporaryDirectory' => supportDirectory.path,
          _ => null,
        },
      );
  tearDownAll(() {
    if (supportDirectory.existsSync()) {
      supportDirectory.deleteSync(recursive: true);
    }
  });

  // 胶济客专线与胶济线在共享站上的里程桩完全相同（青岛北 378、城阳 362、即墨 351、
  // 高密 295、潍坊 210、昌乐 186、淄博 110、大明湖 3、济南 0），只在中间站上不同
  // （胶济线走 蓝村/胶州/芝兰庄、黄台/金岭镇/东风/临淄；客专走 胶州北、五里堂所/
  // 章丘/青州市）。于是每一对相邻站都有两条长度一模一样的走法，只看里程分不出来。
  group('等里程的并行线路不换名', () {
    test('整段搜：里程并列时留在同一条线上', () async {
      final result = await RouteService.resolveJourney(const [
        StationPairDistance(
          fromStation: '青岛北',
          toStation: '潍坊',
          distanceKm: 168,
        ),
      ]);

      final names = result.segments.map((s) => s.routeName).toList();
      expect(names.toSet(), hasLength(1), reason: '里程并列时应留在同一条线上，实际经由：$names');
      // 换线判定只打破并列，选出来的里程必须还是最短的那条。
      expect(result.segments.single.mileageKm, 168);
    });

    test('逐段搜：相邻区间的交界处也不换名', () async {
      // 青岛北→济南 378km，拆成相邻站对逐段搜（App 对历史时刻表就是这么切的）。
      final result = await RouteService.resolveJourney(const [
        StationPairDistance(
          fromStation: '青岛北',
          toStation: '即墨',
          distanceKm: 27,
        ),
        StationPairDistance(fromStation: '即墨', toStation: '高密', distanceKm: 56),
        StationPairDistance(
          fromStation: '高密',
          toStation: '昌乐',
          distanceKm: 109,
        ),
        StationPairDistance(
          fromStation: '昌乐',
          toStation: '大明湖',
          distanceKm: 183,
        ),
        StationPairDistance(fromStation: '大明湖', toStation: '济南', distanceKm: 3),
      ]);

      final names = result.segments.map((s) => s.routeName).toList();
      expect(names.toSet(), hasLength(1), reason: '每一段都该接着上一段走，实际经由：$names');
      expect(result.segments, hasLength(1));
      expect(result.segments.single.mileageKm, 378);
      expect(result.segments.first.fromStation, '青岛北');
      expect(result.segments.single.toStation, '济南');
    });

    test('真需要换线时照旧换线', () async {
      // 青岛北→北京 873km 要经 济南线 上 京沪线，不能为了「不换名」把整趟压成一条线。
      final result = await RouteService.resolveJourney(const [
        StationPairDistance(
          fromStation: '青岛北',
          toStation: '北京',
          distanceKm: 873,
        ),
      ]);

      final names = result.segments.map((s) => s.routeName).toList();
      expect(names, contains('京沪线'), reason: '实际经由：$names');
      expect(
        result.segments.fold<double>(0, (sum, s) => sum + s.mileageKm),
        873,
      );
    });
  });

  // 1461/1462 的区间里程来自时刻表的累计里程，和 routes.db 的里程桩不是同一套刻度：
  // 沪宁段每过一个站就差 1 km（南京→常州 时刻表说 137，京沪线与沪宁高速线的里程桩
  // 都是 136）。以前这 1 km 的差会被当成「更准的匹配」，于是选中一条
  // 京沪线 南京→丹阳 92 + 沪宁高速线 丹阳→常州 45 的借道走法（合计正好 137，误差 0），
  // 把丹阳→常州 判给了沪宁高速线。现在误差 1 km 以内算并列，并列时取用到的线路名
  // 更少的走法，借道那条反而吃亏。
  group('时刻表与里程桩的 1 km 刻度差不算换线理由', () {
    test('1462 的沪宁段留在京沪线', () async {
      final result = await RouteService.resolveJourney(const [
        StationPairDistance(fromStation: '苏州', toStation: '无锡', distanceKm: 42),
        StationPairDistance(fromStation: '无锡', toStation: '常州', distanceKm: 39),
        StationPairDistance(
          fromStation: '常州',
          toStation: '南京',
          distanceKm: 137,
        ),
      ]);

      final names = result.segments.map((s) => s.routeName).toList();
      expect(names, ['京沪线'], reason: '实际经由：$names');
      expect(result.segments.single.fromStation, '苏州');
      expect(result.segments.single.toStation, '南京');
      expect(result.segments.single.mileageKm, 217);
    });

    test('1461 的沪宁段不借道沪宁高速线', () async {
      final result = await RouteService.resolveJourney(const [
        StationPairDistance(fromStation: '济南', toStation: '泰山', distanceKm: 74),
        StationPairDistance(fromStation: '泰山', toStation: '磁窑', distanceKm: 34),
        StationPairDistance(fromStation: '磁窑', toStation: '兖州', distanceKm: 49),
        StationPairDistance(
          fromStation: '兖州',
          toStation: '徐州',
          distanceKm: 164,
        ),
        StationPairDistance(fromStation: '徐州', toStation: '宿州', distanceKm: 74),
        StationPairDistance(fromStation: '宿州', toStation: '蚌埠', distanceKm: 90),
        StationPairDistance(
          fromStation: '蚌埠',
          toStation: '南京',
          distanceKm: 185,
        ),
        StationPairDistance(
          fromStation: '南京',
          toStation: '常州',
          distanceKm: 137,
        ),
        StationPairDistance(fromStation: '常州', toStation: '无锡', distanceKm: 39),
        StationPairDistance(fromStation: '无锡', toStation: '苏州', distanceKm: 42),
        StationPairDistance(fromStation: '苏州', toStation: '上海', distanceKm: 84),
      ]);

      final names = result.segments.map((s) => s.routeName).toList();
      expect(names, ['济南线', '京沪线'], reason: '实际经由：$names');
      expect(result.segments.last.toStation, '上海');
      expect(
        result.segments.fold<double>(0, (sum, s) => sum + s.mileageKm),
        968,
      );
    });
  });

  // 换向（折返）不只是「合并后首尾同名的退化段」，更一般地说：同一段走法里有一站被走了
  // 两遍。T7 在 西安 换向——从东边 新丰镇→窑村→灞桥 进西安，折返后再退到 灞桥 才上
  // 西康线南下，灞桥↔西安 这 10 km 走两遍。合并时若只判「线路名相同 + 首尾相接」，
  // 这两遍会被并成一段自相重叠的走法；而展开站表和贴轨都只按「线路名 + 首尾站」查，
  // 重叠部分被抹掉，换向站 西安 整站从行程站表里消失。
  group('换向处断开，记成进退两段', () {
    test('T7 延安→镇安 在 西安 换向（折返点就在段首）', () async {
      final result = await RouteService.resolveJourney(const [
        StationPairDistance(
          fromStation: '延安',
          toStation: '西安',
          distanceKm: 328,
        ),
        StationPairDistance(
          fromStation: '西安',
          toStation: '镇安',
          distanceKm: 141,
        ),
      ]);

      final via = _describeSegments(result.segments);
      // 新丰镇→西安 这段 陇海线 与 宁西西合段 的里程桩不同、总里程都是 35 km（宁西西合段
      // 在 灞桥 与 西安 之间多一个 浐灞），走哪条只看谁先松弛，所以这里只断言折返被记成
      // 两段，不锁死线路名。
      final reversalIndex = result.segments.indexWhere(
        (s) => s.toStation == '西安',
      );
      expect(reversalIndex, isNonNegative, reason: '实际经由：$via');
      final backTrack = result.segments[reversalIndex + 1];
      expect(backTrack.fromStation, '西安', reason: '实际经由：$via');
      expect(
        [backTrack.toStation, backTrack.mileageKm],
        ['灞桥', 10],
        reason: '折返该断开记成两段（进退各一段，原路退回 灞桥），实际经由：$via',
      );
      expect(
        result.segments.where((s) => s.fromStation == s.toStation),
        isEmpty,
        reason: '实际经由：$via',
      );
      // 延安→西安 326（包西线 291 + 宁西西合段 35），西安→镇安 141（西安→灞桥 10 +
      // 田灞联络线 8 + 西康线 田王→镇安 123），合计 467。旧库的西康线还经过 灞桥、
      // 镇安 的里程桩也不同，合出来是 473；现在的数值正好等于时刻表的 141。
      expect(
        result.segments.fold<double>(0, (sum, s) => sum + s.mileageKm),
        467,
      );

      final stations = await _tripStations(
        result.segments,
        'T7',
        '延安',
        '镇安',
        469,
      );
      // 新线路库的 宁西西合段 在 灞桥 与 西安 之间还有 浐灞，折返时进出 西安 都经过它。
      expect(
        _neighboursOf(stations, '西安'),
        ['浐灞', '浐灞'],
        reason: '西安 该留在站表里，且进出都取同一条折返路，实际站表：$stations',
      );
    });

    test('折返点落在段中间也断开（新丰镇→西安→镇安）', () async {
      // 区间 1 最短走法（陇海线 与 宁西西合段 在这段上新丰镇→窑村→灞桥→西安 都是
      // 35 km，走哪条只看谁先松弛）到 西安，区间 2 第一条边是 西安→灞桥 10 km：
      // 端点（灞桥）并不等于这一段的起点（新丰镇），只看「首尾同名」是漏的，合并出来会是
      // 新丰镇→灞桥 这种首尾不同名的重叠走法。
      final result = await RouteService.resolveJourney(const [
        StationPairDistance(
          fromStation: '新丰镇',
          toStation: '西安',
          distanceKm: 35,
        ),
        StationPairDistance(
          fromStation: '西安',
          toStation: '镇安',
          distanceKm: 141,
        ),
      ]);

      final via = _describeSegments(result.segments);
      final reversalIndex = result.segments.indexWhere(
        (s) => s.toStation == '西安' && s.mileageKm == 35,
      );
      expect(reversalIndex, isNonNegative, reason: '实际经由：$via');
      // 只断言折返被断开，不锁死线路名：陇海线与宁西西合段在这段上的总里程一样。
      final backTrack = result.segments[reversalIndex + 1];
      expect(backTrack.fromStation, '西安', reason: '实际经由：$via');
      expect(
        [backTrack.toStation, backTrack.mileageKm],
        ['灞桥', 10],
        reason: '实际经由：$via',
      );
      expect(
        result.segments.any((s) => s.toStation == '灞桥' && s.mileageKm > 10),
        isFalse,
        reason: '折返被并进前一段了，实际经由：$via',
      );

      final stations = await _tripStations(
        result.segments,
        'K1',
        '新丰镇',
        '镇安',
        176,
      );
      // 同上：宁西西合段 在 灞桥 与 西安 之间还有 浐灞。
      expect(_neighboursOf(stations, '西安'), [
        '浐灞',
        '浐灞',
      ], reason: '西安 该留在站表里，实际站表：$stations');
    });
  });

  // 太原枢纽 里 大西高铁、石太客专线、郑太客专线 共享 太原/长风街所/太原南 三站
  // （太原东 只有 石太客专线 还有），但各条线的里程桩不一样（长风街所→太原：大西 5 km、
  // 石太 4 km）。于是「大西 →石太 →大西 →石太」这种在枢纽里反复换线的走法，能比老老实实
  // 待在大西高铁上多凑出几公里：D966 的 西安北→石家庄 目标 807，反复换线那条合 806。
  // 出队次序必须先要线路名少（见 `_mileageDriftPerHop`）而不是先看谁里程短，这类走法才
  // 不会冒头。
  group('不为了凑里程在枢纽里反复换线', () {
    test('D966 西安北→石家庄 整段留在大西高铁上，到太原才换石太客专线', () async {
      final result = await RouteService.resolveJourney(const [
        StationPairDistance(
          fromStation: '西安北',
          toStation: '石家庄',
          distanceKm: 807,
        ),
      ]);

      final via = _describeSegments(result.segments);
      final names = result.segments.map((s) => s.routeName).toList();
      expect(
        names.toSet(),
        hasLength(names.length),
        reason: '同一条线不该出现两段（那就是反复换线），实际经由：$via',
      );
      expect(
        result.segments.where((s) => s.routeName == '大西高铁').single.toStation,
        '太原',
        reason: '实际经由：$via',
      );
      expect(
        result.segments.where((s) => s.routeName == '石太客专线').single.fromStation,
        '太原',
        reason: '实际经由：$via',
      );
      // 目标 807 是时刻表的累计里程，routes.db 的大西高铁 西安北→太原 是 580、
      // 石太客专线 太原→石家庄 是 224，合计差 3 km，落在「每站 0.5 km」的刻度差允许量
      // （24 站 → 12 km）里，不值得为它再插一段 5 km 的 临潼东联络（那是「借道凑里程」，
      // 线路名从 2 个涨到 4 个）。
      expect(
        result.segments.fold<double>(0, (sum, s) => sum + s.mileageKm),
        804,
      );
    });

    test('D966 成都东→北京丰台 全长只换三次线', () async {
      // 26.9.25 时刻表：成都东 0 / 广元 279 / 汉中 417 / 西安北 660 / 石家庄 1467 /
      // 高碑店东 1666 / 北京丰台 1742。
      final result = await RouteService.resolveJourney(const [
        StationPairDistance(
          fromStation: '成都东',
          toStation: '广元',
          distanceKm: 279,
        ),
        StationPairDistance(
          fromStation: '广元',
          toStation: '汉中',
          distanceKm: 138,
        ),
        StationPairDistance(
          fromStation: '汉中',
          toStation: '西安北',
          distanceKm: 243,
        ),
        StationPairDistance(
          fromStation: '西安北',
          toStation: '石家庄',
          distanceKm: 807,
        ),
        StationPairDistance(
          fromStation: '石家庄',
          toStation: '高碑店东',
          distanceKm: 199,
        ),
        StationPairDistance(
          fromStation: '高碑店东',
          toStation: '北京丰台',
          distanceKm: 76,
        ),
      ]);

      final via = _describeSegments(result.segments);
      final names = result.segments.map((s) => s.routeName).toList();
      expect(
        names.toSet(),
        hasLength(names.length),
        reason: '同一条线不该出现两段（那就是反复换线），实际经由：$via',
      );
      expect(names, contains('大西高铁'), reason: '实际经由：$via');
      expect(result.segments.first.fromStation, '成都东', reason: '实际经由：$via');
      expect(result.segments.last.toStation, '北京丰台', reason: '实际经由：$via');
    });
  });

  // 刻度差是逐站累积的，里程容差不能是个固定值。D16 的 西安东→延安 目标 328：
  // 老老实实走 西康线 + 陇海线 + 包西线 进延安是 327（经过 14 站，误差 1）。
  // 新线路库里 西康线 不再经过 灞桥、镇安 的里程桩也变了，这条正路本身已经贴着目标，
  // 不用再靠刻度差允许量去压过「在 甘泉北 换到平行的 包西延西段」的走法（换线后
  // 只有 321 km，误差 7）。保留这条断言是为了锁住结果：一路走 包西线，线路名从 3 个
  // 涨到 4 个的借道走法不该冒头。
  group('刻度差随经过站数累积，不为了几公里借道平行线', () {
    test('D16 西安东→延安 一路走包西线进延安', () async {
      final result = await RouteService.resolveJourney(const [
        StationPairDistance(
          fromStation: '西安东',
          toStation: '延安',
          distanceKm: 328,
        ),
      ]);

      final via = _describeSegments(result.segments);
      final names = result.segments.map((s) => s.routeName).toList();
      expect(
        names,
        isNot(contains('包西延西段')),
        reason: '不该在 甘泉北 换到平行的高铁线上借道，实际经由：$via',
      );
      expect(names, hasLength(3), reason: '实际经由：$via');
      expect(names.last, '包西线', reason: '实际经由：$via');
      expect(result.segments.last.toStation, '延安', reason: '实际经由：$via');
      expect(
        result.segments.fold<double>(0, (sum, s) => sum + s.mileageKm),
        327,
      );
    });
  });

  // 旧行程里存下来的经由名是新线路库之前的写法（宁西线西合段、沪宁沿江高铁）。
  // 展开站表和贴轨前都要先把它们解析到新库的线路名上，否则这些行程会退化成
  // 只剩首尾站、地图上只剩直线。
  group('旧线路名解析到新库', () {
    test('去掉速度等级词的旧写法仍能查到线路与里程', () async {
      final stations = await RouteService.getStationsForRoute('宁西线西合段');
      expect(stations, contains('西安'));
      expect(await RouteService.getDistanceOnRoute('宁西线西合段', '西安', '灞桥'), 10);

      final hsrStations = await RouteService.getStationsForRoute('沪宁沿江高铁');
      expect(hsrStations, isNotEmpty);
    });
  });
}

String _describeSegment(ViaRouteSegment segment) =>
    '${segment.routeName} ${segment.fromStation}→${segment.toStation} '
    '${_formatKm(segment.mileageKm)}';

List<String> _describeSegments(List<ViaRouteSegment> segments) =>
    segments.map(_describeSegment).toList();

String _formatKm(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toString();

/// 把经由线路展开成站表，返回该趟行程的站序。
Future<List<String>> _tripStations(
  List<ViaRouteSegment> segments,
  String trainNumber,
  String fromStation,
  String toStation,
  double mileageKm,
) async {
  final journeys = await RouteService.resolveTripStations([
    TripRecord(
      id: 1,
      trainNumber: trainNumber,
      fromStation: fromStation,
      toStation: toStation,
      departureTime: DateTime(2026, 6, 18, 2, 43),
      mileageKm: mileageKm,
      viaRouteSegments: segments,
    ),
  ]);
  return journeys.values.single.stations;
}

/// [stations] 里 [name] 的前后各一站。
List<String> _neighboursOf(List<String> stations, String name) {
  final index = stations.indexOf(name);
  expect(index, isNonNegative, reason: '$name 不在站表里：$stations');
  return [stations[index - 1], stations[index + 1]];
}
