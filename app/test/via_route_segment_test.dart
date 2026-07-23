import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/via_route_segment.dart';

void main() {
  test('rejects a segment whose endpoints are the same', () {
    final error = validateViaRouteSegments(
      [
        const ViaRouteSegment(
          routeName: '京广线',
          fromStation: '北京西',
          toStation: '北京西',
        ),
      ],
      startStation: '北京西',
      endStation: '北京西',
    );

    expect(error, '第1段经由的始发站和终到站不能相同');
  });

  test('rejects the same route in adjacent segments', () {
    final error = validateViaRouteSegments(
      [
        const ViaRouteSegment(
          routeName: '京广线',
          fromStation: '北京西',
          toStation: '石家庄',
        ),
        const ViaRouteSegment(
          routeName: ' 京广线 ',
          fromStation: '石家庄',
          toStation: '郑州',
        ),
      ],
      startStation: '北京西',
      endStation: '郑州',
    );

    expect(error, '第1段和第2段经由的线路不能相同');
  });

  test('accepts connected segments on different routes', () {
    final error = validateViaRouteSegments(
      [
        const ViaRouteSegment(
          routeName: '京广线',
          fromStation: '北京西',
          toStation: '石家庄',
        ),
        const ViaRouteSegment(
          routeName: '陇海线',
          fromStation: '石家庄',
          toStation: '郑州',
        ),
      ],
      startStation: '北京西',
      endStation: '郑州',
    );

    expect(error, isNull);
  });
}
