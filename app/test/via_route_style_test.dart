import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/via_route_segment.dart';
import 'package:raillog/src/widgets/trip_details/via_route_style.dart';

void main() {
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF005AC1),
    brightness: Brightness.light,
  );

  group('buildViaRouteLineStyles', () {
    test('同一条线路只出现一次，里程累加', () {
      final styles = buildViaRouteLineStyles(const [
        ViaRouteSegment(
          routeName: '京沪高速铁路',
          fromStation: '北京南',
          toStation: '济南西',
          mileageKm: 406,
        ),
        ViaRouteSegment(
          routeName: '京沪高速铁路',
          fromStation: '济南西',
          toStation: '上海虹桥',
          mileageKm: 912,
        ),
        ViaRouteSegment(
          routeName: '胶济客专线',
          fromStation: '济南西',
          toStation: '青岛',
          mileageKm: 393,
        ),
      ], colors);

      expect(styles, hasLength(2));
      expect(styles.first.route, '京沪高速铁路');
      expect(styles.first.mileageKm, 1318);
      expect(styles.last.route, '胶济客专线');
      expect(styles.first.color, isNot(styles.last.color));
    });

    test('线路名不同就是两条线，不按写法归一', () {
      final styles = buildViaRouteLineStyles(const [
        ViaRouteSegment(
          routeName: '兰新线',
          fromStation: '乌鲁木齐',
          toStation: '乌鲁木齐南',
          mileageKm: 9,
        ),
        ViaRouteSegment(
          routeName: '兰新客专线',
          fromStation: '乌鲁木齐南',
          toStation: '吐鲁番北',
          mileageKm: 158,
        ),
      ], colors);

      expect(styles.map((style) => style.route), ['兰新线', '兰新客专线']);
      expect(styles.map((style) => style.mileageKm), [9, 158]);
      expect(styles.first.color, isNot(styles.last.color));
    });

    test('空线路名归一为手动线路，未记录里程保持 0', () {
      final styles = buildViaRouteLineStyles(const [
        ViaRouteSegment(
          routeName: '  ',
          fromStation: '甲',
          toStation: '乙',
        ),
      ], colors);

      expect(styles.single.route, '手动线路');
      expect(styles.single.mileageKm, 0);
    });
  });

  group('findViaRouteColor', () {
    test('按线路原名精确配色', () {
      final styles = buildViaRouteLineStyles(const [
        ViaRouteSegment(
          routeName: '京沪高速铁路',
          fromStation: '北京南',
          toStation: '上海虹桥',
        ),
      ], colors);

      expect(findViaRouteColor('京沪高速铁路', styles), styles.single.color);
      // 名字不同就是另一条线路，不做写法归一去套用别人的颜色。
      expect(findViaRouteColor('京沪高速线', styles), isNull);
      expect(findViaRouteColor('胶济客专线', styles), isNull);
      expect(findViaRouteColor(null, styles), isNull);
    });
  });
}
