import 'package:raillog/src/models/via_route_segment.dart';

class RouteResolution {
  const RouteResolution({
    required this.segments,
    required this.usedShortestPath,
    required this.unresolvedSections,
    this.inferenceLog = const [],
  });

  final List<ViaRouteSegment> segments;
  final bool usedShortestPath;
  final List<String> unresolvedSections;
  final List<String> inferenceLog;
}
