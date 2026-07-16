import 'package:raillog/src/models/via_route_segment.dart';

class RoutePathMatch {
  const RoutePathMatch({
    required this.segments,
    required this.targetMileageKm,
    required this.actualMileageKm,
    required this.isExactMileage,
  });

  final List<ViaRouteSegment> segments;
  final double targetMileageKm;
  final double actualMileageKm;
  final bool isExactMileage;
}
