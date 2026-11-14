import 'package:flutter/material.dart';
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

    test('同一条线的不同写法合并成一种颜色和一条图例', () {
      final styles = buildViaRouteLineStyles(const [
        ViaRouteSegment(
          routeName: '京沪高速铁路',
          fromStation: '北京南',
          toStation: '济南西',
          mileageKm: 406,
        ),
        ViaRouteSegment(
          routeName: '京沪高速线',
          fromStation: '济南西',
          toStation: '上海虹桥',
          mileageKm: 912,
        ),
      ], colors);

      expect(styles, hasLength(1));
      expect(styles.single.route, '京沪高速铁路');
      expect(styles.single.mileageKm, 1318);
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
    test('规范线路名能对上行程里记录的别名', () {
      final styles = buildViaRouteLineStyles(const [
        ViaRouteSegment(
          routeName: '京沪高速铁路',
          fromStation: '北京南',
          toStation: '上海虹桥',
        ),
      ], colors);

      // 地图折线来自线路库，名字是「京沪高速线」。
      expect(findViaRouteColor('京沪高速线', styles), styles.single.color);
      expect(findViaRouteColor('京沪高速铁路', styles), styles.single.color);
      expect(findViaRouteColor('胶济客专线', styles), isNull);
      expect(findViaRouteColor(null, styles), isNull);
    });
  });

  test('viaRouteLineKey 去掉线别后缀', () {
    expect(viaRouteLineKey('京沪高速铁路'), '京沪高速');
    expect(viaRouteLineKey('京沪高速线'), '京沪高速');
    expect(viaRouteLineKey('胶济客运专线'), '胶济');
    expect(viaRouteLineKey('胶济客专线'), '胶济');
    expect(viaRouteLineKey('宝成线'), '宝成');
  });
}
