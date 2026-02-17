using MessagePack;
using System.Text.Json;
using System.Text.Json.Serialization;
using RailLog.Models;
using RailLog.Shared.Models;

namespace RailLog.Services
{
    public sealed class RouteRoutingService
    {
        private const int MileageSearchNodeLimit = 150_000;
        private readonly ILogger<RouteRoutingService> _logger;
        private readonly Dictionary<string, List<GraphEdge>> _adjacency;
        private readonly HashSet<string> _routeNames = new(StringComparer.OrdinalIgnoreCase);
        private readonly HashSet<string> _stationNames = new(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, IReadOnlyList<RouteStationOption>> _routeStations =
            new(StringComparer.OrdinalIgnoreCase);

        public RouteRoutingService(IWebHostEnvironment environment, ILogger<RouteRoutingService> logger)
        {
            _logger = logger;

            var routesJsonPath = Path.Combine(environment.ContentRootPath, "Assets", "routes.json");
            var graphCachePath = Path.Combine(environment.ContentRootPath, "Assets", "graph.bin");
            _adjacency = LoadOrBuildGraph(routesJsonPath, graphCachePath);
            LoadRouteStations(routesJsonPath);
        }

        public RoutePathResult? CalculatePath(string start, string end, int? targetMileageKm = null, bool allowShortestFallback = true)
        {
            var normalizedStart = NormalizeStationName(start);
            var normalizedEnd = NormalizeStationName(end);

            if (string.IsNullOrWhiteSpace(normalizedStart) || string.IsNullOrWhiteSpace(normalizedEnd))
            {
                return null;
            }

            if (!_adjacency.ContainsKey(normalizedStart) || !_adjacency.ContainsKey(normalizedEnd))
            {
                return null;
            }

            if (targetMileageKm is > 0)
            {
                if (TryFindPathByMileage(normalizedStart, normalizedEnd, targetMileageKm.Value, out var mileageMatched) &&
                    mileageMatched is not null)
                {
                    return mileageMatched with { IsMileageMatch = true };
                }

                if (!allowShortestFallback)
                {
                    return null;
                }
            }

            return FindShortestPath(normalizedStart, normalizedEnd);
        }

        private Dictionary<string, List<GraphEdge>> LoadOrBuildGraph(string routesJsonPath, string graphCachePath)
        {
            if (!File.Exists(routesJsonPath))
            {
                _logger.LogWarning("Route data file not found: {Path}", routesJsonPath);
                return new Dictionary<string, List<GraphEdge>>(StringComparer.OrdinalIgnoreCase);
            }

            var cacheVersion = BuildCacheVersion(routesJsonPath);
            if (TryLoadGraphCache(graphCachePath, cacheVersion, out var cachedGraph))
            {
                _logger.LogInformation("Loaded railway graph from cache: {Path}", graphCachePath);
                RebuildIndicesFromGraph(cachedGraph);
                return cachedGraph;
            }

            var graph = BuildGraphFromJson(routesJsonPath);
            RebuildIndicesFromGraph(graph);
            TrySaveGraphCache(graphCachePath, cacheVersion, graph);
            return graph;
        }

        private Dictionary<string, List<GraphEdge>> BuildGraphFromJson(string routesJsonPath)
        {
            using var stream = File.OpenRead(routesJsonPath);
            var routeData = JsonSerializer.Deserialize<RouteData>(stream) ?? new RouteData();
            var graph = new Dictionary<string, List<GraphEdge>>(StringComparer.OrdinalIgnoreCase);

            foreach (var route in routeData.Routes)
            {
                if (route.Stations.Count < 2)
                {
                    continue;
                }

                for (var i = 0; i < route.Stations.Count - 1; i++)
                {
                    var from = route.Stations[i];
                    var to = route.Stations[i + 1];
                    var distance = Math.Abs(to.Mileage - from.Mileage);
                    var routeName = route.RouteName;

                    AddEdge(graph, from.StationName, to.StationName, distance, routeName);
                    AddEdge(graph, to.StationName, from.StationName, distance, routeName);
                }
            }

            _logger.LogInformation("Built railway graph from JSON. Station count: {StationCount}", graph.Count);
            return graph;
        }

        private static void AddEdge(
            Dictionary<string, List<GraphEdge>> graph,
            string from,
            string to,
            int distance,
            string routeName)
        {
            var normalizedFrom = NormalizeStationName(from);
            var normalizedTo = NormalizeStationName(to);
            if (string.IsNullOrWhiteSpace(normalizedFrom) || string.IsNullOrWhiteSpace(normalizedTo))
            {
                return;
            }

            if (!graph.TryGetValue(normalizedFrom, out var edges))
            {
                edges = [];
                graph[normalizedFrom] = edges;
            }

            if (edges.Any(edge =>
                    string.Equals(edge.To, normalizedTo, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(edge.RouteName, routeName, StringComparison.OrdinalIgnoreCase)))
            {
                return;
            }

            edges.Add(new GraphEdge(normalizedTo, Math.Max(0, distance), routeName.Trim()));
        }

        private RoutePathResult? FindShortestPath(string start, string end)
        {
            var distances = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
            {
                [start] = 0
            };
            var previous = new Dictionary<string, PreviousHop>(StringComparer.OrdinalIgnoreCase);
            var queue = new PriorityQueue<string, int>();
            queue.Enqueue(start, 0);

            while (queue.TryDequeue(out var current, out var currentDistance))
            {
                if (distances.TryGetValue(current, out var knownDistance) && currentDistance > knownDistance)
                {
                    continue;
                }

                if (string.Equals(current, end, StringComparison.OrdinalIgnoreCase))
                {
                    break;
                }

                if (!_adjacency.TryGetValue(current, out var neighbors))
                {
                    continue;
                }

                foreach (var neighbor in neighbors)
                {
                    var distance = currentDistance + neighbor.Distance;
                    if (distances.TryGetValue(neighbor.To, out var bestDistance) && distance >= bestDistance)
                    {
                        continue;
                    }

                    distances[neighbor.To] = distance;
                    previous[neighbor.To] = new PreviousHop(current, neighbor.RouteName, neighbor.Distance);
                    queue.Enqueue(neighbor.To, distance);
                }
            }

            if (!distances.TryGetValue(end, out var totalMileageKm))
            {
                return null;
            }

            var path = ReconstructPath(start, end, previous, totalMileageKm);
            if (path is null)
            {
                return null;
            }

            return path with { IsMileageMatch = false };
        }

        private bool TryFindPathByMileage(string start, string end, int targetMileageKm, out RoutePathResult? result)
        {
            result = null;
            if (targetMileageKm < 0)
            {
                return false;
            }

            var stations = new List<string> { start };
            var edgeRoutes = new List<string>();
            var edgeDistances = new List<int>();
            var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { start };
            var exploredNodes = 0;

            var found = DfsFindPathByMileage(
                current: start,
                destination: end,
                remainingMileageKm: targetMileageKm,
                visited: visited,
                stations: stations,
                edgeRoutes: edgeRoutes,
                edgeDistances: edgeDistances,
                exploredNodes: ref exploredNodes);

            if (!found)
            {
                return false;
            }

            result = new RoutePathResult(
                Stations: stations,
                Routes: CompressRouteList(edgeRoutes),
                RouteSegments: BuildRouteSegments(stations, edgeRoutes, edgeDistances),
                TotalMileageKm: targetMileageKm,
                IsMileageMatch: true);
            return true;
        }

        private bool DfsFindPathByMileage(
            string current,
            string destination,
            int remainingMileageKm,
            HashSet<string> visited,
            List<string> stations,
            List<string> edgeRoutes,
            List<int> edgeDistances,
            ref int exploredNodes)
        {
            if (exploredNodes++ > MileageSearchNodeLimit)
            {
                return false;
            }

            if (remainingMileageKm < 0)
            {
                return false;
            }

            if (string.Equals(current, destination, StringComparison.OrdinalIgnoreCase) && remainingMileageKm == 0)
            {
                return true;
            }

            if (!_adjacency.TryGetValue(current, out var edges))
            {
                return false;
            }

            foreach (var edge in edges.OrderBy(x => x.Distance))
            {
                if (edge.Distance > remainingMileageKm)
                {
                    continue;
                }

                if (visited.Contains(edge.To))
                {
                    continue;
                }

                visited.Add(edge.To);
                stations.Add(edge.To);
                edgeRoutes.Add(edge.RouteName);
                edgeDistances.Add(edge.Distance);

                var found = DfsFindPathByMileage(
                    current: edge.To,
                    destination: destination,
                    remainingMileageKm: remainingMileageKm - edge.Distance,
                    visited: visited,
                    stations: stations,
                    edgeRoutes: edgeRoutes,
                    edgeDistances: edgeDistances,
                    exploredNodes: ref exploredNodes);

                if (found)
                {
                    return true;
                }

                edgeRoutes.RemoveAt(edgeRoutes.Count - 1);
                edgeDistances.RemoveAt(edgeDistances.Count - 1);
                stations.RemoveAt(stations.Count - 1);
                visited.Remove(edge.To);
            }

            return false;
        }

        private static RoutePathResult? ReconstructPath(
            string start,
            string end,
            Dictionary<string, PreviousHop> previous,
            int totalMileageKm)
        {
            var stations = new List<string>();
            var edgeRoutes = new List<string>();
            var edgeDistances = new List<int>();

            var current = end;
            stations.Add(current);

            while (!string.Equals(current, start, StringComparison.OrdinalIgnoreCase))
            {
                if (!previous.TryGetValue(current, out var hop))
                {
                    return null;
                }

                edgeRoutes.Add(hop.RouteName);
                edgeDistances.Add(hop.Distance);
                current = hop.From;
                stations.Add(current);
            }

            stations.Reverse();
            edgeRoutes.Reverse();
            edgeDistances.Reverse();
            var segments = BuildRouteSegments(stations, edgeRoutes, edgeDistances);

            return new RoutePathResult(
                Stations: stations,
                Routes: CompressRouteList(edgeRoutes),
                RouteSegments: segments,
                TotalMileageKm: totalMileageKm,
                IsMileageMatch: false);
        }

        private bool TryLoadGraphCache(
            string graphCachePath,
            string expectedVersion,
            out Dictionary<string, List<GraphEdge>> graph)
        {
            graph = new Dictionary<string, List<GraphEdge>>(StringComparer.OrdinalIgnoreCase);

            if (!File.Exists(graphCachePath))
            {
                return false;
            }

            try
            {
                var bytes = File.ReadAllBytes(graphCachePath);
                var cachedGraph = MessagePackSerializer.Deserialize<CachedGraph>(bytes);
                if (cachedGraph is null || !string.Equals(cachedGraph.Version, expectedVersion, StringComparison.Ordinal))
                {
                    return false;
                }

                foreach (var kvp in cachedGraph.AdjacencyList)
                {
                    if (string.IsNullOrWhiteSpace(kvp.Key))
                    {
                        continue;
                    }

                    var edges = kvp.Value
                        .Where(edge => !string.IsNullOrWhiteSpace(edge.To))
                        .Select(edge => new GraphEdge(edge.To, edge.Distance, edge.RouteName))
                        .ToList();

                    graph[kvp.Key] = edges;
                }

                return graph.Count > 0;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to read graph cache: {Path}", graphCachePath);
                return false;
            }
        }

        private void TrySaveGraphCache(
            string graphCachePath,
            string version,
            Dictionary<string, List<GraphEdge>> graph)
        {
            try
            {
                var directory = Path.GetDirectoryName(graphCachePath);
                if (!string.IsNullOrWhiteSpace(directory))
                {
                    Directory.CreateDirectory(directory);
                }

                var cachedGraph = new CachedGraph
                {
                    Version = version,
                    AdjacencyList = graph.ToDictionary(
                        kvp => kvp.Key,
                        kvp => kvp.Value.Select(edge => new CachedEdge
                        {
                            To = edge.To,
                            Distance = edge.Distance,
                            RouteName = edge.RouteName
                        }).ToList(),
                        StringComparer.OrdinalIgnoreCase)
                };

                var bytes = MessagePackSerializer.Serialize(cachedGraph);
                File.WriteAllBytes(graphCachePath, bytes);
                _logger.LogInformation("Saved railway graph cache: {Path}", graphCachePath);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to save graph cache: {Path}", graphCachePath);
            }
        }

        private static string BuildCacheVersion(string routeJsonPath)
        {
            var fileInfo = new FileInfo(routeJsonPath);
            return $"{fileInfo.Length}:{fileInfo.LastWriteTimeUtc.Ticks}";
        }

        private static string NormalizeStationName(string stationName)
        {
            return stationName.Trim();
        }

        private static IReadOnlyList<string> CompressRouteList(IEnumerable<string> routeNames)
        {
            var result = new List<string>();
            string? previous = null;

            foreach (var routeName in routeNames)
            {
                if (string.IsNullOrWhiteSpace(routeName))
                {
                    continue;
                }

                if (string.Equals(previous, routeName, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                result.Add(routeName);
                previous = routeName;
            }

            return result;
        }

        public IReadOnlyList<string> SuggestRouteNames(string keyword, int limit = 20)
        {
            return SuggestFromSet(_routeNames, keyword, limit);
        }

        public IReadOnlyList<string> SuggestStationNames(string keyword, int limit = 30)
        {
            return SuggestFromSet(_stationNames, keyword, limit);
        }

        public IReadOnlyList<RouteStationOption> GetRouteStations(string routeName)
        {
            var key = routeName?.Trim() ?? string.Empty;
            if (string.IsNullOrWhiteSpace(key))
            {
                return [];
            }

            return _routeStations.TryGetValue(key, out var stations) ? stations : [];
        }

        private static IReadOnlyList<string> SuggestFromSet(HashSet<string> source, string keyword, int limit)
        {
            var key = keyword?.Trim() ?? string.Empty;
            if (string.IsNullOrWhiteSpace(key))
            {
                return source.OrderBy(x => x).Take(limit).ToList();
            }

            return source
                .Where(x => x.Contains(key, StringComparison.OrdinalIgnoreCase))
                .OrderBy(x => x.StartsWith(key, StringComparison.OrdinalIgnoreCase) ? 0 : 1)
                .ThenBy(x => x)
                .Take(limit)
                .ToList();
        }

        private void RebuildIndicesFromGraph(Dictionary<string, List<GraphEdge>> graph)
        {
            _routeNames.Clear();
            _stationNames.Clear();
            foreach (var kvp in graph)
            {
                _stationNames.Add(kvp.Key);
                foreach (var edge in kvp.Value)
                {
                    _stationNames.Add(edge.To);
                    if (!string.IsNullOrWhiteSpace(edge.RouteName))
                    {
                        _routeNames.Add(edge.RouteName);
                    }
                }
            }
        }

        private void LoadRouteStations(string routesJsonPath)
        {
            _routeStations.Clear();
            if (!File.Exists(routesJsonPath))
            {
                return;
            }

            using var stream = File.OpenRead(routesJsonPath);
            var routeData = JsonSerializer.Deserialize<RouteData>(stream) ?? new RouteData();

            foreach (var route in routeData.Routes)
            {
                var routeName = route.RouteName?.Trim() ?? string.Empty;
                if (string.IsNullOrWhiteSpace(routeName) || route.Stations.Count == 0)
                {
                    continue;
                }

                var stations = new List<RouteStationOption>(route.Stations.Count);
                var seenStations = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (var station in route.Stations)
                {
                    var stationName = NormalizeStationName(station.StationName);
                    if (string.IsNullOrWhiteSpace(stationName) || !seenStations.Add(stationName))
                    {
                        continue;
                    }

                    stations.Add(new RouteStationOption(stationName, station.Mileage));
                }

                if (stations.Count == 0)
                {
                    continue;
                }

                if (!_routeStations.TryGetValue(routeName, out var existing) || stations.Count > existing.Count)
                {
                    _routeStations[routeName] = stations;
                }
            }
        }

        private static IReadOnlyList<RouteSegment> BuildRouteSegments(
            IReadOnlyList<string> stations,
            IReadOnlyList<string> edgeRoutes,
            IReadOnlyList<int> edgeDistances)
        {
            var result = new List<RouteSegment>();
            if (stations.Count < 2 || edgeRoutes.Count != stations.Count - 1 || edgeDistances.Count != edgeRoutes.Count)
            {
                return result;
            }

            var currentRoute = edgeRoutes[0];
            var segmentStart = stations[0];
            var segmentEnd = stations[1];
            var segmentMileage = edgeDistances[0];

            for (var i = 1; i < edgeRoutes.Count; i++)
            {
                var route = edgeRoutes[i];
                var from = stations[i];
                var to = stations[i + 1];

                if (string.Equals(route, currentRoute, StringComparison.OrdinalIgnoreCase) &&
                    string.Equals(from, segmentEnd, StringComparison.OrdinalIgnoreCase))
                {
                    segmentEnd = to;
                    segmentMileage += edgeDistances[i];
                    continue;
                }

                result.Add(new RouteSegment(currentRoute, segmentStart, segmentEnd, segmentMileage));
                currentRoute = route;
                segmentStart = from;
                segmentEnd = to;
                segmentMileage = edgeDistances[i];
            }

            result.Add(new RouteSegment(currentRoute, segmentStart, segmentEnd, segmentMileage));
            return result;
        }
        private sealed record GraphEdge(string To, int Distance, string RouteName);
        private sealed record PreviousHop(string From, string RouteName, int Distance);

        private sealed class RouteData
        {
            [JsonPropertyName("routes")]
            public List<RouteInfo> Routes { get; set; } = [];
        }

        private sealed class RouteInfo
        {
            [JsonPropertyName("route_name")]
            public string RouteName { get; set; } = string.Empty;

            [JsonPropertyName("stations")]
            public List<StationInfo> Stations { get; set; } = [];
        }

        private sealed class StationInfo
        {
            [JsonPropertyName("station_name")]
            public string StationName { get; set; } = string.Empty;

            [JsonPropertyName("mileage")]
            public int Mileage { get; set; }
        }

    }
}

