import 'package:raillog/src/models/via_route_segment.dart';

class RouteResolution {
  const RouteResolution({
    required this.segments,
    required this.usedShortestPath,
    required this.unresolvedSections,
  });

  final List<ViaRouteSegment> segments;
  final bool usedShortestPath;
  final List<String> unresolvedSections;
}
