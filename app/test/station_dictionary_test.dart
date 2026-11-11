@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/train_service.dart';

/// 直接读盘，不走 rootBundle：widget 测试里 rootBundle 会静默挂死。
/// `flutter test` 的工作目录是包根，assets 路径与应用内一致。
void main() {
  Future<String> loadBundledScript() =>
      File('assets/db/station_name.js').readAsString();

  test('内置字典是 12306 的原始脚本格式，没有被改动或截断', () async {
    final script = await loadBundledScript();

    expect(script, startsWith("var station_names ='"));
    expect(script.trimRight(), endsWith("';"));
  });

  test('内置字典能解析出电报码和所属城市', () async {
    final script = await loadBundledScript();
    final codes = TrainService.parseStationCodes(script);
    final cities = TrainService.parseStationCities(script);

    // 线上约 3400 条，明显更少说明副本坏了。
    expect(codes.length, greaterThan(3000));
    expect(cities.length, greaterThan(3000));
    expect(codes['北京南'], 'VNP');
    expect(cities['北京南'], '北京');
    expect(cities['香港西九龙'], '香港');
  });
}
