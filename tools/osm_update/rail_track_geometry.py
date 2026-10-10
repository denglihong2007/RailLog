"""铁路站间轨道折线的几何算法。

构图与吸附的思路移植自 TrainTrack 项目已经验证的实现（OSM 铁路网 → 图 →
吸附 → A*）。本项目独有的是**里程约束消歧**：

    RailLog 的 routes.db 带有每站的线路里程桩，站间里程因此是已知量。
    同一对车站之间可能存在并行线路（例如京沪高铁与京沪铁路），纯几何最短路
    永远只会选出较短的那条。这里改用 Yen 算法枚举前 k 条最短路，再挑选长度
    与已知里程最接近的那条，从而把并行线路区分开。

本模块只做计算、不做 IO，便于单元测试。
"""

from __future__ import annotations

import heapq
import math
import re
from dataclasses import dataclass, field
from typing import Dict, FrozenSet, Iterable, List, Optional, Sequence, Set, Tuple

Coord = Tuple[float, float]  # (lat, lon)
EdgeKey = Tuple[Coord, Coord]
Adjacency = Dict[Coord, List[Tuple[Coord, float]]]

EARTH_RADIUS_KM = 6371.0
KM_PER_DEGREE = 111.0

# 轨道分类。与 OSM 标签的对应关系见 matches_profile。
HSR = "hsr"
CONVENTIONAL = "conventional"
ALL = "all"

# OSM maxspeed 以 2~9 开头的三位数视作高速铁路（200 km/h 及以上）。
HSR_MAXSPEED_RE = re.compile(r"^(2\d\d|[3-9]\d\d)")

# route_name 中出现这些词判定为高速铁路。判错不致命，只影响同长度候选的取舍。
HSR_ROUTE_KEYWORDS = ("高铁", "客专", "城际", "高速", "专线")


# --------------------------------------------------------------------------
# 基础几何
# --------------------------------------------------------------------------


def haversine_km(a: Coord, b: Coord) -> float:
    lat1, lon1 = a
    lat2, lon2 = b
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    h = (
        math.sin(dlat / 2) ** 2
        + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon / 2) ** 2
    )
    return 2 * EARTH_RADIUS_KM * math.asin(math.sqrt(min(1.0, h)))


class Projection:
    """以某个纬度为基准的等距投影，用于统一 A* 的边权与启发式。

    边权和启发式取同一投影空间里的欧氏距离，因此启发式可采纳且一致，
    A* 的结果即为最优路径。
    """

    __slots__ = ("lat0", "cos_lat0")

    def __init__(self, lat0: float) -> None:
        self.lat0 = lat0
        self.cos_lat0 = max(0.05, math.cos(math.radians(lat0)))

    def to_xy(self, coord: Coord) -> Tuple[float, float]:
        lat, lon = coord
        return (lon * self.cos_lat0 * KM_PER_DEGREE, lat * KM_PER_DEGREE)

    def distance_km(self, a: Coord, b: Coord) -> float:
        ax, ay = self.to_xy(a)
        bx, by = self.to_xy(b)
        return math.hypot(ax - bx, ay - by)


def project_to_segment(point: Coord, a: Coord, b: Coord) -> Tuple[Coord, float]:
    """把 point 投影到线段 a-b 上，返回 (投影点, 距离 km)。"""
    if a == b:
        return a, haversine_km(point, a)

    proj = Projection((a[0] + b[0]) / 2.0)
    x, y = proj.to_xy(point)
    x1, y1 = proj.to_xy(a)
    x2, y2 = proj.to_xy(b)

    dx = x2 - x1
    dy = y2 - y1
    denom = dx * dx + dy * dy
    if denom == 0:
        return a, haversine_km(point, a)

    t = max(0.0, min(1.0, ((x - x1) * dx + (y - y1) * dy) / denom))
    lon = (x1 + t * dx) / (proj.cos_lat0 * KM_PER_DEGREE)
    lat = (y1 + t * dy) / KM_PER_DEGREE
    projected = (lat, lon)
    return projected, haversine_km(point, projected)


def path_distance_km(point: Coord, path: Sequence[Coord]) -> float:
    """点到折线的最短距离（km）。折线少于 2 点时退化为点到点。"""
    if not path:
        return float("inf")
    if len(path) == 1:
        return haversine_km(point, path[0])
    return min(
        project_to_segment(point, path[i], path[i + 1])[1]
        for i in range(len(path) - 1)
    )


def resample_path(
    path: Sequence[Coord],
    step_m: float,
    first_offset_m: Optional[float] = None,
) -> List[Coord]:
    """按 step_m 等距重采样折线。

    末端会保留原始终点，因此最后一段可能短于 step_m（移植自 TrainTrack 的同名函数）。
    """
    if not path:
        return []
    step_km = step_m / 1000.0
    current_step_km = step_km
    use_first_offset = False
    if first_offset_m is not None and first_offset_m > 0:
        current_step_km = first_offset_m / 1000.0
        use_first_offset = True

    points: List[Coord] = [path[0]]
    acc = 0.0
    for i in range(len(path) - 1):
        a = path[i]
        b = path[i + 1]
        seg = haversine_km(a, b)
        if seg == 0:
            continue
        while acc + seg >= current_step_km:
            ratio = (current_step_km - acc) / seg
            lat = a[0] + (b[0] - a[0]) * ratio
            lon = a[1] + (b[1] - a[1]) * ratio
            points.append((lat, lon))
            seg -= current_step_km - acc
            a = (lat, lon)
            acc = 0.0
            if use_first_offset:
                current_step_km = step_km
                use_first_offset = False
        acc += seg
    if points[-1] != path[-1]:
        points.append(path[-1])
    return points


def path_length_km(path: Sequence[Coord]) -> float:
    return sum(haversine_km(path[i], path[i + 1]) for i in range(len(path) - 1))


def max_gap_km(path: Sequence[Coord]) -> float:
    if len(path) < 2:
        return 0.0
    return max(haversine_km(path[i], path[i + 1]) for i in range(len(path) - 1))


SUSPECT_MILEAGE_RATIO = 3.0
SUSPECT_MILEAGE_FLOOR_KM = 200.0
SUSPECT_STRAIGHT_KM = 600.0


def suspect_leg_reason(
    a: Coord, b: Coord, mileage_km: Optional[float]
) -> Optional[str]:
    """站间段的坐标是否明显不可信；可信时返回 None。

    coordinates.csv 来自维基数据，个别站名会匹配到同名但异地的地方（如「新乡」
    命中几千公里外的同名站），使相邻两站的直线距离远超实际里程。这类段的走廊
    bbox 会大到覆盖半个国家，取数必然超时，且算出来的折线毫无意义——所以要在
    取数之前就识别出来，直接记为失败，App 端回退直线。

    铁路里程恒不短于直线距离，因此「直线 > 里程的数倍」即为异常。里程缺失时
    退回绝对上限，只拦真正离谱的段。
    """
    straight = haversine_km(a, b)
    if mileage_km is not None and mileage_km > 0:
        return "suspect_coordinate" if straight > max(
            SUSPECT_MILEAGE_RATIO * mileage_km, SUSPECT_MILEAGE_FLOOR_KM
        ) else None
    return "suspect_coordinate" if straight > SUSPECT_STRAIGHT_KM else None


CORRIDOR_MARGIN_DEG = 0.02


def corridor_km_for(a: Coord, b: Coord) -> float:
    """起终点直线两侧的走廊半宽。

    站间段是同一线路上相邻两站，实际走向基本贴合直线；25% 的宽松余量足以容纳
    绕行，同时把取数范围压到最小。上下限避免极短/极长区段失真。
    """
    return max(10.0, min(45.0, haversine_km(a, b) * 0.25))


def bbox_for_corridor(
    a: Coord, b: Coord, corridor_km: float
) -> Tuple[float, float, float, float]:
    """覆盖整条走廊的最小轴对齐 bbox，返回 (min_lat, min_lon, max_lat, max_lon)。

    走廊内的点与线段的球面距离不超过 corridor_km，因此其经纬度偏移必然落在
    corridor_km 换算出的度数之内；经度按纬度收缩换算，高纬度才不会被切掉。
    """
    mid_lat = (a[0] + b[0]) / 2.0
    pad_lat = corridor_km / KM_PER_DEGREE
    pad_lon = corridor_km / (KM_PER_DEGREE * max(0.2, math.cos(math.radians(mid_lat))))
    margin = CORRIDOR_MARGIN_DEG
    return (
        min(a[0], b[0]) - pad_lat - margin,
        min(a[1], b[1]) - pad_lon - margin,
        max(a[0], b[0]) + pad_lat + margin,
        max(a[1], b[1]) + pad_lon + margin,
    )


def quantize(coord: Coord, digits: int = 6) -> Coord:
    return (round(coord[0], digits), round(coord[1], digits))


def edge_key(a: Coord, b: Coord) -> EdgeKey:
    return (a, b) if a <= b else (b, a)


# --------------------------------------------------------------------------
# 名称归一化。必须与 App 端 Dart 实现保持一致，否则查不到折线。
# 对应 app/lib/src/services/trip_map_service.dart 的 _stationKeys，
# 以及 route_service.dart 的 _resolveRouteName。
# --------------------------------------------------------------------------

_PAREN_SUFFIX_RE = re.compile(r"\s*\([^)]*\)\s*$")
_STATION_SUFFIX_RE = re.compile(r"(火车站|站)$")
_WHITESPACE_RE = re.compile(r"\s+")
_ROUTE_SUFFIX_RE = re.compile(r"(铁路|线)$")


def station_key(value: str) -> str:
    """站名归一化：全角括号转半角、去尾部括号注释、去「站/火车站」后缀、去空白、小写。"""
    trimmed = (value or "").strip().replace("（", "(").replace("）", ")")
    if not trimmed:
        return ""
    normalized = _PAREN_SUFFIX_RE.sub("", trimmed)
    normalized = _STATION_SUFFIX_RE.sub("", normalized)
    normalized = _WHITESPACE_RE.sub("", normalized).lower()
    return normalized or trimmed.lower()


def route_key(value: str) -> str:
    """线路名归一化：去掉「铁路/线」后缀并转小写。

    因此用户填写的「京沪高速铁路」与 routes.db 里的「京沪高速线」会归一到同一个键。
    """
    trimmed = (value or "").strip()
    if not trimmed:
        return ""
    return (_ROUTE_SUFFIX_RE.sub("", trimmed) or trimmed).lower()


# 线路匹配键的别名表：把同一件事的两种拼法归一，但**绝不抹掉速度等级本身**。抹掉
# 「高速」会让「京广线」和「京广高速线」撞成一个键，京广线的车次就会被拉上高铁正线。
LINE_ALIASES = (("客运专线", "高速"), ("高铁", "高速"), ("客专", "高速"))
_SEGMENT_SUFFIX_RE = re.compile(r"段$")


def line_match_key(value: str) -> str:
    """线路匹配键：判断「这段行程该贴哪条 OSM way」。

    与 [route_key] 严格分开——`route_key` 是折线主键（`track_key`）的一部分，动了全体
    key 都会变，所以这里另起一套。名字先去掉尾部括号注释（OSM 里有「XX线 (上行)」这种
    写法）、去空白、按 [LINE_ALIASES] 归一「高铁/客专」与「高速」，再取第一个「线」或
    「铁路」之前的部分：客里表的线路名带区段后缀，OSM 的 way 名不带。

    对不上就返回一个匹配不到任何 way 的键，这是**故意**的：说明这条线路名在 OSM 里没有
    同名正线，调用方据此拿到空的偏好集、退化成纯里程判定（见 `preferred_for`）。
    """
    trimmed = (value or "").strip().replace("（", "(").replace("）", ")")
    if not trimmed:
        return ""
    name = _PAREN_SUFFIX_RE.sub("", trimmed)
    name = _WHITESPACE_RE.sub("", name)
    if not name:
        return ""
    for alias, canonical in LINE_ALIASES:
        name = name.replace(alias, canonical)
    if "线" in name:
        name = name.split("线", 1)[0]
    elif "铁路" in name:
        name = name.split("铁路", 1)[0]
    else:
        name = _SEGMENT_SUFFIX_RE.sub("", name)
    return name.lower() or trimmed.lower()


def track_key(route_name: str, from_station: str, to_station: str) -> str:
    return "|".join(
        (route_key(route_name), station_key(from_station), station_key(to_station))
    )


def way_name(tags: dict) -> Optional[str]:
    """way 的线路名（`name`，退到 `name:zh`）；没有就返回 None。

    中国铁路正线在 OSM 里基本都带这个标签，取值就是客里表里的线路名（「新义线」
    「大郑线」「京广高速线」…），因此可以拿它把车站坐标和线路对上。少数 way 会把
    name 写成「XX线 (上行)」之类的变体，故用 route_key 归一化后再比。
    """
    name = tags.get("name") or tags.get("name:zh")
    if not name:
        return None
    return str(name).strip() or None


# --------------------------------------------------------------------------
# 轨道分类
# --------------------------------------------------------------------------


def infer_profile(route_name: str) -> str:
    """从线路名推断轨道类型。"""
    name = route_name or ""
    if any(keyword in name for keyword in HSR_ROUTE_KEYWORDS):
        return HSR
    return CONVENTIONAL


SERVICE_VALUES = frozenset({"yard", "siding"})


def is_service_rail(tags: dict) -> bool:
    """站场/侧线：正线以外的可通行轨道。

    `way_flags` 认不出它是高铁还是普速，所以它既不会被当成 preferred，也不会被当
    成某条线路的一部分。但它**确实能跑车**，而且车站咽喉、两条正线之间的渡线在中
    国 OSM 里经常就标 `service=siding`。

    整条丢掉会出大问题：图的断口正好落在每个车站的咽喉上，也就是每段行程的起终点。
    实测 80 个失败段里没有一个能在丢掉它们之后找到路，留着当非 preferred 的连接线
    反而救回 60%。所以取数时要留着，`preferred_for` 自然会给它 False。
    """
    return (
        tags.get("railway") == "rail"
        and str(tags.get("service", "")).strip().lower() in SERVICE_VALUES
    )


def _railway_service_excluded(tags: dict) -> bool:
    if not tags or tags.get("railway") != "rail":
        return True
    return is_service_rail(tags)


def _is_hsr_way(tags: dict) -> bool:
    if _railway_service_excluded(tags):
        return False
    if str(tags.get("highspeed", "")).lower() == "yes":
        return True
    maxspeed = str(tags.get("maxspeed", ""))
    return bool(maxspeed and HSR_MAXSPEED_RE.match(maxspeed))


def _is_conventional_way(tags: dict) -> bool:
    if _railway_service_excluded(tags):
        return False
    if str(tags.get("highspeed", "")).lower() == "yes":
        return False
    maxspeed = str(tags.get("maxspeed", ""))
    return not (maxspeed and HSR_MAXSPEED_RE.match(maxspeed))


def matches_profile(tags: dict, profile: str) -> bool:
    if profile == HSR:
        return _is_hsr_way(tags)
    if profile == CONVENTIONAL:
        return _is_conventional_way(tags)
    return not _railway_service_excluded(tags)


def way_flags(tags: dict) -> Tuple[bool, bool]:
    """返回 (是否高铁, 是否普速)。

    取数时算一次存进缓存，之后就可以按不同 profile 复用同一份 way 数据，
    不必为每种 profile 各抓一次 bbox。
    """
    return _is_hsr_way(tags), _is_conventional_way(tags)


# --------------------------------------------------------------------------
# 铁路数据与图
# --------------------------------------------------------------------------


@dataclass
class RailData:
    """一次取数范围内的铁路 way。

    lines 是全部 way 的坐标序列；preferred[i] 表示第 i 条 way 是否匹配目标 profile；
    names[i] 是它的线路名（`name`/`name:zh`），只用于把折线拆成「哪几条线拼的」。
    """

    lines: List[List[Coord]] = field(default_factory=list)
    preferred: List[bool] = field(default_factory=list)
    names: List[Optional[str]] = field(default_factory=list)

    def is_empty(self) -> bool:
        return not self.lines

    def names_padded(self) -> List[Optional[str]]:
        """补到与 lines 等长。

        names 是后加的字段，测试里大量字面构造只给 lines/preferred；补齐比要求每个
        构造点都跟上一个 None 稳妥。
        """
        return [*self.names, *([None] * max(0, len(self.lines) - len(self.names)))]

    def merged(self, other: "RailData") -> "RailData":
        return RailData(
            lines=[*self.lines, *other.lines],
            preferred=[*self.preferred, *other.preferred],
            names=[*self.names_padded(), *other.names_padded()],
        )


@dataclass
class RailGraph:
    """站间寻路用的无向图。

    adjacency 的边权是投影空间欧氏距离（km）；preferred_edges 记录该边是否
    至少被一条匹配目标 profile 的 way 覆盖，用于在长度相近的候选之间取舍。

    way_of/way_names 是给「这条折线由哪几条线路拼成」用的侧表：edge → 建图时的 way
    序号。**不塞进 adjacency 的元组里**——那个元组被 A*/Yen/重采样等一堆地方按
    `(neighbor, weight)` 解包，动它等于全改一遍。
    """

    adjacency: Adjacency = field(default_factory=dict)
    preferred_edges: Set[EdgeKey] = field(default_factory=set)
    way_of: Dict[EdgeKey, int] = field(default_factory=dict)
    way_names: List[Optional[str]] = field(default_factory=list)

    def is_empty(self) -> bool:
        return not self.adjacency


def build_graph(
    lines: Iterable[Sequence[Coord]],
    preferred: Sequence[bool],
    names: Optional[Sequence[Optional[str]]] = None,
) -> RailGraph:
    graph = RailGraph()
    for index, line in enumerate(lines):
        is_preferred = preferred[index] if index < len(preferred) else True
        graph.way_names.append(
            names[index] if names is not None and index < len(names) else None
        )
        for i in range(len(line) - 1):
            a = quantize(line[i])
            b = quantize(line[i + 1])
            if a == b:
                continue
            graph.adjacency.setdefault(a, [])
            graph.adjacency.setdefault(b, [])
            weight = haversine_km(a, b)
            graph.adjacency[a].append((b, weight))
            graph.adjacency[b].append((a, weight))
            key = edge_key(a, b)
            # 两条 way 压在同一段边上时（并行 way、正线叠站线），归属记到 preferred 的
            # 那条：拆段明细要回答的是「走的哪条线」，正线比站线更接近这个答案。
            if key not in graph.way_of or is_preferred:
                graph.way_of[key] = index
            if is_preferred:
                graph.preferred_edges.add(key)
    return graph


def corridor_filter(
    rail: RailData, start: Coord, end: Coord, corridor_km: Optional[float] = None
) -> RailData:
    """只保留落在起终点直线走廊内的 way，显著缩小图的规模。

    并行线路（高铁/普速）通常相距只有几公里到几十公里，走廊宽度足以同时容纳，
    因此不会影响里程消歧。
    """
    if rail.is_empty():
        return rail
    if corridor_km is None:
        corridor_km = corridor_km_for(start, end)

    lines: List[List[Coord]] = []
    preferred: List[bool] = []
    names: List[Optional[str]] = []
    for line, is_preferred, name in zip(rail.lines, rail.preferred, rail.names_padded()):
        for i in range(len(line) - 1):
            _, dist = project_to_segment(line[i], start, end)
            if dist <= corridor_km:
                lines.append(line)
                preferred.append(is_preferred)
                names.append(name)
                break
    return RailData(lines=lines, preferred=preferred, names=names)


# --------------------------------------------------------------------------
# 寻路：A* 与 Yen k-最短路
# --------------------------------------------------------------------------


def _astar(
    adjacency: Adjacency,
    start: Coord,
    goal: Coord,
    projection: Projection,
    *,
    banned_nodes: FrozenSet[Coord] = frozenset(),
    banned_edges: FrozenSet[EdgeKey] = frozenset(),
    max_cost: Optional[float] = None,
) -> Optional[Tuple[List[Coord], float]]:
    if start not in adjacency or goal not in adjacency:
        return None
    if start in banned_nodes or goal in banned_nodes:
        return None
    if start == goal:
        return [start], 0.0

    best_cost: Dict[Coord, float] = {start: 0.0}
    came_from: Dict[Coord, Coord] = {}
    heap: List[Tuple[float, float, Coord]] = [
        (projection.distance_km(start, goal), 0.0, start)
    ]

    while heap:
        _, cost, node = heapq.heappop(heap)
        if node == goal:
            path = [node]
            while path[-1] != start:
                path.append(came_from[path[-1]])
            path.reverse()
            return path, cost
        if cost > best_cost.get(node, math.inf):
            continue
        for neighbor, weight in adjacency.get(node, ()):
            if neighbor in banned_nodes:
                continue
            if edge_key(node, neighbor) in banned_edges:
                continue
            next_cost = cost + weight
            if max_cost is not None and next_cost > max_cost:
                continue
            if next_cost < best_cost.get(neighbor, math.inf):
                best_cost[neighbor] = next_cost
                came_from[neighbor] = node
                heapq.heappush(
                    heap,
                    (
                        next_cost + projection.distance_km(neighbor, goal),
                        next_cost,
                        neighbor,
                    ),
                )
    return None


def _path_cost(path: Sequence[Coord], adjacency: Adjacency) -> float:
    total = 0.0
    for i in range(len(path) - 1):
        best = None
        for neighbor, weight in adjacency.get(path[i], ()):
            if neighbor == path[i + 1] and (best is None or weight < best):
                best = weight
        total += best if best is not None else haversine_km(path[i], path[i + 1])
    return total


def k_shortest_paths(
    adjacency: Adjacency,
    start: Coord,
    goal: Coord,
    projection: Projection,
    *,
    k: int = 6,
    max_cost: Optional[float] = None,
) -> List[Tuple[List[Coord], float]]:
    """Yen 算法枚举前 k 条无环最短路，按长度升序返回 [(path, cost), ...]。

    max_cost 会同时剪掉超出长度上限的搜索分支和候选路径，长区间的开销因此可控。
    """
    first = _astar(adjacency, start, goal, projection, max_cost=max_cost)
    if first is None:
        return []
    accepted: List[Tuple[List[Coord], float]] = [first]
    if k <= 1:
        return accepted

    candidates: List[Tuple[float, int, List[Coord]]] = []
    seen: Set[Tuple[Coord, ...]] = {tuple(first[0])}
    serial = 0

    while len(accepted) < k:
        previous_path, _ = accepted[-1]
        for i in range(len(previous_path) - 1):
            spur_node = previous_path[i]
            root = previous_path[: i + 1]

            banned_edges: Set[EdgeKey] = set()
            for path, _ in accepted:
                if len(path) > i + 1 and path[: i + 1] == root:
                    banned_edges.add(edge_key(path[i], path[i + 1]))

            root_cost = _path_cost(root, adjacency)
            budget = None if max_cost is None else max_cost - root_cost
            if budget is not None and budget < 0:
                continue

            spur = _astar(
                adjacency,
                spur_node,
                goal,
                projection,
                banned_nodes=frozenset(root[:-1]),
                banned_edges=frozenset(banned_edges),
                max_cost=budget,
            )
            if spur is None:
                continue
            spur_path, spur_cost = spur
            total_path = [*root[:-1], *spur_path]
            key = tuple(total_path)
            if key in seen:
                continue
            seen.add(key)
            serial += 1
            candidates.append((root_cost + spur_cost, serial, total_path))

        if not candidates:
            break
        candidates.sort(key=lambda item: (item[0], item[1]))
        cost, _, path = candidates.pop(0)
        if max_cost is not None and cost > max_cost:
            break
        accepted.append((path, cost))

    return accepted


# --------------------------------------------------------------------------
# 单段规划：里程约束消歧
# --------------------------------------------------------------------------


@dataclass
class PathCandidate:
    path: List[Coord]
    length_km: float
    preferred_ratio: float
    # 登乘跳：折线首尾「站坐标 → 目标线上车点」两段直线的合计（km），每段各自不超
    # 过 jump_radius_km，所以这个数最大到 2×半径。0 表示两端都是同分量吸附、没跳。
    board_jump_km: float = 0.0


@dataclass
class LegPlan:
    ok: bool
    reason: str = ""
    polyline: List[Coord] = field(default_factory=list)
    length_km: float = 0.0
    mileage_km: Optional[float] = None
    mileage_error_km: Optional[float] = None
    mileage_error_ratio: Optional[float] = None
    preferred_ratio: float = 0.0
    board_jump_km: float = 0.0
    # 折线由哪几条线路拼成：[(线路名, km), ...]，相邻同名合并。
    line_runs: List[Tuple[str, float]] = field(default_factory=list)


def _preferred_ratio(path: Sequence[Coord], graph: RailGraph) -> float:
    if len(path) < 2:
        return 0.0
    preferred_km = 0.0
    total_km = 0.0
    for i in range(len(path) - 1):
        length = haversine_km(path[i], path[i + 1])
        total_km += length
        if edge_key(path[i], path[i + 1]) in graph.preferred_edges:
            preferred_km += length
    return preferred_km / total_km if total_km > 0 else 0.0


def _on_preferred_edge(graph: RailGraph, node: Coord) -> bool:
    """节点是否接在至少一条匹配目标 profile 的边上。"""
    return any(
        edge_key(node, neighbor) in graph.preferred_edges
        for neighbor, _ in graph.adjacency.get(node, ())
    )


# 没有 name 标签的 way（站场股道、少数没标名字的联络线）在拆段明细里的名字。
# 用哨兵串而不是 SQL NULL：落库后可以直接 GROUP BY，NOT NULL 约束也不用放宽。
UNNAMED_LINE = "未命名"


def line_runs(path: Sequence[Coord], graph: RailGraph) -> List[Tuple[str, float]]:
    """把一条已选路径切成 [(线路名, km), ...]，相邻同名合并。

    只合并**相邻**的同名段：同一条线走一段、借道别的线、再回到它，应该留下两段，
    跨着合并就把「在哪儿换的线」这个信息抹掉了。

    跑在选中的原始 path 上，所以 `sum(km) + board_jump_km ≈ length_km`；`_finalize`
    会把首尾顶点覆盖成站点坐标、再按 step 重采样，落在折线上的长度会略有出入。
    """
    runs: List[Tuple[str, float]] = []
    for i in range(len(path) - 1):
        a, b = path[i], path[i + 1]
        index = graph.way_of.get(edge_key(a, b))
        name = graph.way_names[index] if index is not None and index < len(graph.way_names) else None
        label = name or UNNAMED_LINE
        length = haversine_km(a, b)
        if runs and runs[-1][0] == label:
            runs[-1] = (label, runs[-1][1] + length)
        else:
            runs.append((label, length))
    return runs


def _snap_node(
    graph: RailGraph,
    point: Coord,
    projection: Projection,
    threshold_km: float,
) -> Tuple[Optional[Coord], float]:
    """把站点吸附到最近节点，返回 (节点, 吸附距离)。

    只按距离取最近的那个节点。并行的高铁与普速在同名车站各有自己的节点，站坐标可能
    离**另一条线**的节点更近，于是整段只能沿那条线走——这一层不去猜，交给
    `search_paths` 把两种锚法都算一遍、由候选评分（里程误差 + 贴 profile）来定。

    阈值内一个节点都没有时，兜底是找到最近的一条**图上的边**，把该边从中拆开、插入
    投影点，这样只有两端有节点的稀疏 way 也能走得通，且不会多出翻越端点的近路。
    """
    nearby = [
        (distance, node)
        for node in graph.adjacency
        if (distance := projection.distance_km(point, node)) <= threshold_km
    ]
    if nearby:
        distance, node = min(nearby, key=lambda item: item[0])
        return node, distance

    split = _nearest_edge(graph, point)
    if split is None:
        return None, 0.0
    proj, dist, a, b = split
    if dist > threshold_km:
        return None, 0.0

    node = quantize(proj)
    if node == a:
        return a, dist
    if node == b:
        return b, dist

    was_preferred = edge_key(a, b) in graph.preferred_edges
    split_way = graph.way_of.pop(edge_key(a, b), None)
    graph.preferred_edges.discard(edge_key(a, b))
    graph.adjacency[a] = [edge for edge in graph.adjacency[a] if edge[0] != b]
    graph.adjacency[b] = [edge for edge in graph.adjacency[b] if edge[0] != a]
    graph.adjacency.setdefault(node, [])
    for endpoint in (a, b):
        weight = haversine_km(node, endpoint)
        graph.adjacency[node].append((endpoint, weight))
        graph.adjacency[endpoint].append((node, weight))
        if split_way is not None:
            graph.way_of[edge_key(node, endpoint)] = split_way
        if was_preferred:
            graph.preferred_edges.add(edge_key(node, endpoint))
    return node, dist


def _nearest_edge(
    graph: RailGraph, point: Coord
) -> Optional[Tuple[Coord, float, Coord, Coord]]:
    """找到离 point 最近的边，返回 (投影点, 距离, 边的一端, 边的另一端)。"""
    best: Optional[Tuple[Coord, float, Coord, Coord]] = None
    for a, neighbors in graph.adjacency.items():
        for b, _ in neighbors:
            if a >= b:  # 无向边只看一次
                continue
            proj, dist = project_to_segment(point, a, b)
            if best is None or dist < best[1]:
                best = (proj, dist, a, b)
    return best


SNAP_CANDIDATE_LIMIT = 4

# 两端各自参与「哪个节点才是自己那条线」比较的节点数。只影响候选对的挑选，不影响
# 路径枚举，放宽些不花什么钱。
SNAP_NODE_POOL = 16


def _snap_candidates(
    graph: RailGraph,
    point: Coord,
    projection: Projection,
    threshold_km: float,
    limit: int = SNAP_CANDIDATE_LIMIT,
) -> List[Tuple[float, Coord]]:
    """阈值内按距离升序的**已有节点**候选（最近的排最前），最多 limit 个。

    只管已有节点，不涉及 `_snap_node` 的拆边兜底——候选存在时那条路本来也走不到。
    """
    near = [
        (distance, node)
        for node in graph.adjacency
        if (distance := projection.distance_km(point, node)) <= threshold_km
    ]
    near.sort(key=lambda item: item[0])
    return near[:limit]


def _component_ids(graph: RailGraph) -> Dict[Coord, int]:
    """给每个节点标一个连通分量号（无向看待：铁路两个方向都能走）。"""
    component: Dict[Coord, int] = {}
    current = 0
    for start in graph.adjacency:
        if start in component:
            continue
        stack = [start]
        while stack:
            node = stack.pop()
            if node in component:
                continue
            component[node] = current
            for neighbor, _ in graph.adjacency.get(node, ()):
                if neighbor not in component:
                    stack.append(neighbor)
        current += 1
    return component


def _alternative_snaps(
    graph: RailGraph,
    start: Coord,
    end: Coord,
    projection: Projection,
    threshold_km: float,
    *,
    skip: Tuple[Coord, Coord],
    limit: int = SNAP_CANDIDATE_LIMIT,
    prefer_profile: bool = False,
) -> List[Tuple[Coord, float, Coord, float]]:
    """最近的那对吸附点之间不通时，给出别的候选对，按吸附距离之和升序。

    只挑**同分量**的候选对：跨分量再近也走不通，白跑一次 Yen。`skip` 是第一对
    （也就是原来的行为），不重复试。

    `prefer_profile` 时改成优先「两端都接在目标 profile 的边上」的对，再比吸附距离：
    并行的高铁与普速各有节点，要挑的是自己那条线上的节点，而它在站场里往往不是最近的
    那个（同一个车站附近可能有好几条股道）。

    为什么需要这个：站场里一个车站附近常有好几条股道，`_snap_node` 只看距离，
    于是最近的节点可能落在一条与正线不通的孤立侧线上，整段就变成「找不到路」。
    实测全量 5796 段里有 101 段本来是通的、加上站场数据后反而失败，都是这个原因。
    """
    # 两端各取一整片候选节点再两两比：只取 limit 个会漏掉自己那条线上的节点——站场里
    # 比它近的股道多的是（实测宝成线江油节点的 233m 在客专的 140m 之后，要往前数好几个
    # 才轮到它）。取多少个节点不影响「按距离取前 limit 对」的结果，只是把池子放宽。
    starts = _snap_candidates(graph, start, projection, threshold_km, SNAP_NODE_POOL)
    ends = _snap_candidates(graph, end, projection, threshold_km, SNAP_NODE_POOL)
    component = _component_ids(graph)
    pairs = sorted(
        (
            (
                not (
                    _on_preferred_edge(graph, start_node)
                    and _on_preferred_edge(graph, end_node)
                ),
                start_dist + end_dist,
                start_dist,
                start_node,
                end_dist,
                end_node,
            )
            for start_dist, start_node in starts
            for end_dist, end_node in ends
            if component.get(start_node) == component.get(end_node)
            and (start_node, end_node) != skip
        ),
        key=(lambda item: (item[0], item[1])) if prefer_profile else (lambda item: item[1]),
    )
    return [
        (start_node, start_dist, end_node, end_dist)
        for _, _, start_dist, start_node, end_dist, end_node in pairs[:limit]
    ]


EXTRA_SNAP_ERROR_RATIO = 0.05
EXTRA_SNAP_PROFILE_FLOOR = 0.5

# 站坐标所在的分量与目标线不通时，允许「跳」到目标线上的节点上车，这一跳的最大长度。
#
# 站场与正线在 OSM 里常常是两套互不共点的几何——并行正线本来就不该共点（实测广州北：
# 京广线与京广高速线并行 14~24m、无共点，站坐标离京广线 31m、离京广高速线 417m）。
# 同分量约束下，从普速侧走到正线要绕 40.40km，整段于是被画成 51.71km 的绕行线。
# 这一跳本来就会以一小段直线出现在折线首尾，与站坐标到锚点的接驳段同性质（见
# `_finalize`），所以这里只是把「接驳」从「5km 内的任意节点」收紧到「1km 内的**目标线**
# 节点」。
DEFAULT_JUMP_RADIUS_KM = 1.0
# 每端参与配对的、接在目标边上的最近节点数。
JUMP_SNAP_POOL = 8
DEFAULT_JUMP_SNAPS = 4

# 现有候选「大半走在目标线上」时就不必跳了——它已经是对的了，再跳只是白花钱。
#
# 为什么不用 `EXTRA_SNAP_PROFILE_FLOOR`（0.5）：那个数是给「主对候选可疑不可疑」用的，
# 分不清「走在目标线上」和「走在另一条同样被偏好命中的线上」。高铁侧尤其糊——preferred
# 的定义是「带 highspeed/maxspeed 标签」，于是任何一条 200km/h 以上的线都算数。实测
# 京广高铁 广州北→广州南：站坐标吸附在京广线上（非偏好），两端同分量、走得通，那条
# 走法借道南广线（250km/h，同样带标签），整段 ratio 0.5004 刚刚压过 0.5 的门槛，于是
# 登乘跳一次都不触发，这一段就一直画在 51.71km 的绕行线上（里程差 4.71km）。跳上去的
# 正确解是 46.10km、ratio 1.00、里程差 0.90km——两个指标都更好，只是没机会上场。
JUMP_PROFILE_FLOOR = 0.9


def _plan_attempt(
    graph: RailGraph,
    projection: Projection,
    from_node: Coord,
    from_dist: float,
    to_node: Coord,
    to_dist: float,
    *,
    k: int,
    max_length_km: Optional[float],
    board_jump: bool = False,
) -> List[PathCandidate]:
    """从一个吸附点对出发枚举候选路径，长度里补上两端吸附空隙。"""
    offset = from_dist + to_dist
    budget = None if max_length_km is None else max_length_km + offset
    raw_paths = k_shortest_paths(
        graph.adjacency, from_node, to_node, projection, k=k, max_cost=budget
    )
    return [
        PathCandidate(
            path=path,
            length_km=path_length_km(path) + offset,
            preferred_ratio=_preferred_ratio(path, graph),
            board_jump_km=offset if board_jump else 0.0,
        )
        for path, _ in raw_paths
    ]


def _jump_snap_candidates(
    graph: RailGraph,
    start: Coord,
    end: Coord,
    projection: Projection,
    *,
    radius_km: float,
    k: int,
    max_length_km: Optional[float],
    jump_snaps: int,
    seen: Set[Tuple[Coord, Coord]],
) -> List[PathCandidate]:
    """跨连通分量跳到目标线上的节点上车。

    与 `_alternative_snaps` 的两点区别，缺一不可：

    1. 池子**先按「接在目标边上的节点」过滤**、再按距离取最近几个。站场咽喉里的股道
       节点比正线节点近得多，先按距离取池的话正线节点根本进不来——这正是 16 个节点的
       旧池子（`SNAP_NODE_POOL`）在广州北失效的原因。
    2. 不要求「两端节点同分量」只作为省钱的剪枝保留（不同分量之间 `_astar` 本来也
       只会返回空），**不要求与站上最近的节点同分量**——这正是这一跳存在的理由。
    """
    if jump_snaps <= 0 or not graph.preferred_edges:
        return []

    def pool(point: Coord) -> List[Tuple[float, Coord]]:
        near = [
            (distance, node)
            for node in graph.adjacency
            if (distance := projection.distance_km(point, node)) <= radius_km
            and _on_preferred_edge(graph, node)
        ]
        near.sort(key=lambda item: item[0])
        return near[:JUMP_SNAP_POOL]

    component = _component_ids(graph)
    pairs = sorted(
        (
            (start_dist + end_dist, start_dist, start_node, end_dist, end_node)
            for start_dist, start_node in pool(start)
            for end_dist, end_node in pool(end)
            if (start_node, end_node) not in seen
            and component.get(start_node) == component.get(end_node)
        ),
        key=lambda item: item[0],
    )

    candidates: List[PathCandidate] = []
    for _, from_dist, from_node, to_dist, to_node in pairs[:jump_snaps]:
        candidates.extend(
            _plan_attempt(
                graph,
                projection,
                from_node,
                from_dist,
                to_node,
                to_dist,
                k=k,
                max_length_km=max_length_km,
                board_jump=True,
            )
        )
    return candidates


def search_paths(
    graph: RailGraph,
    start: Coord,
    end: Coord,
    projection: Projection,
    *,
    k: int = 6,
    snap_threshold_km: float = 5.0,
    max_length_km: Optional[float] = None,
    mileage_km: Optional[float] = None,
    extra_snaps: int = 0,
    jump_radius_km: float = DEFAULT_JUMP_RADIUS_KM,
    jump_snaps: int = DEFAULT_JUMP_SNAPS,
) -> Tuple[List[PathCandidate], Optional[str]]:
    """吸附起终点后枚举候选路径，按长度升序返回。

    主吸附对（各自最近的节点）不通时，会换到别的候选吸附点再试（见
    `_alternative_snaps`），这是原来就有的兜底，先试的永远是主吸附对。

    `mileage_km` 与 `extra_snaps` 一起用时，多算一层：主吸附对的候选如果看着不对
    （离里程太远，或者大半路程压在非目标 profile 的边上），就把 [extra_snaps] 个
    「落在目标 profile 边上的节点」组成的吸附对也算一遍，**候选合并在一起**返回，
    由调用方的评分去定。并行的高铁与普速在同名车站各有节点、站坐标可能离另一条线更近
    （实测宝成线 昭化→江油：离西成客专的江油节点 140m、离宝成自己的 233m），只按距离
    锚到客专之后，那一段就只有沿客专走的一条 151km 的解法（里程 135km，误差 16km 仍在
    35% 容差里）；把宝成那边的 136km、preferred 0.99 的那条一起摆上，评分自然选对。

    多算出来的候选要进得了「与里程相容」的那一档（见 `plan_leg` 的 close_error_ratio）
    才有机会被选中，所以本来就贴里程的段不会被一堆差候选挤掉；反过来，主吸附对已经
    贴里程又贴 profile 的段也不会多算这一次。
    """
    if graph.is_empty():
        return [], "empty_graph"

    start_node, start_dist = _snap_node(graph, start, projection, snap_threshold_km)
    end_node, end_dist = _snap_node(graph, end, projection, snap_threshold_km)
    if start_node is None or end_node is None:
        return [], "snap_failed"

    attempts = [(start_node, start_dist, end_node, end_dist)]
    for index, (from_node, from_dist, to_node, to_dist) in enumerate(attempts):
        candidates = _plan_attempt(
            graph,
            projection,
            from_node,
            from_dist,
            to_node,
            to_dist,
            k=k,
            max_length_km=max_length_km,
        )
        if candidates:
            if index == 0:
                # 只对主吸附对做这一层：换到的兜底对已经是「主对不通」时的候选了。
                candidates.extend(
                    _extra_snap_candidates(
                        graph,
                        start,
                        end,
                        projection,
                        snap_threshold_km,
                        candidates,
                        k=k,
                        max_length_km=max_length_km,
                        mileage_km=mileage_km,
                        extra_snaps=extra_snaps,
                        skip=(from_node, to_node),
                    )
                )
                # 现有候选里连一条「大半走在目标线上」的都没有，才允许跨分量跳上去。
                # 站上本来就有同分量的目标线节点时，上面的候选里必然有一个 ratio 达标的，
                # 不会走到这里。
                if not any(
                    item.preferred_ratio >= JUMP_PROFILE_FLOOR
                    for item in candidates
                ):
                    candidates.extend(
                        _jump_snap_candidates(
                            graph,
                            start,
                            end,
                            projection,
                            radius_km=jump_radius_km,
                            k=k,
                            max_length_km=max_length_km,
                            jump_snaps=jump_snaps,
                            seen={(item.path[0], item.path[-1]) for item in candidates},
                        )
                    )
            candidates.sort(key=lambda item: item.length_km)
            return candidates, None
        if index == 0:
            # 第一次不通才去算候选对：算分量是 O(V+E)，不该让每个成功的段都付这笔钱。
            attempts.extend(
                _alternative_snaps(
                    graph,
                    start,
                    end,
                    projection,
                    snap_threshold_km,
                    skip=(start_node, end_node),
                )
            )

    # 同分量的吸附对全试过了还是不通，最后试一把跨分量登乘跳。
    #
    # 这一步不能并进上面的 `if candidates:` 里：主吸附对**直接不通**时（站场节点与正线
    # 分属两个连通分量、又不在彼此的候选池里），`_plan_attempt` 返回 0 个候选，
    # `_alternative_snaps` 的同分量约束又永远够不着正线，上面那段根本执行不到——而这里
    # 是此时唯一的出路。
    #
    # 「通了但走错线」不走这条路，走上面那个判断：广州北→广州南 的主对就是通的（京广线
    # 接联络线到南广线，51.71km），是 `JUMP_PROFILE_FLOOR` 那道门槛把跳线放行的。
    jumped = _jump_snap_candidates(
        graph,
        start,
        end,
        projection,
        radius_km=jump_radius_km,
        k=k,
        max_length_km=max_length_km,
        jump_snaps=jump_snaps,
        seen=set(),
    )
    if jumped:
        jumped.sort(key=lambda item: item.length_km)
        return jumped, None
    return [], "no_path"


def _extra_snap_candidates(
    graph: RailGraph,
    start: Coord,
    end: Coord,
    projection: Projection,
    threshold_km: float,
    primary: Sequence[PathCandidate],
    *,
    k: int,
    max_length_km: Optional[float],
    mileage_km: Optional[float],
    extra_snaps: int,
    skip: Tuple[Coord, Coord],
) -> List[PathCandidate]:
    """主吸附对的候选看着不对时，再算几个「落在目标 profile 边上」的吸附对。

    只在主吸附对可疑时才动手，否则每个段都要为这几对多跑一遍 Yen 枚举。
    """
    if extra_snaps <= 0:
        return []
    # 一条偏好边都没有（普速腿的线路名对不上任何 OSM way）时，「ratio < 阈值」不再说明
    # 任何事——它恒成立，所以那一条判据要整个让开，否则每个这样的段都白跑一遍额外枚举。
    #
    # 但**只让开 ratio 那条**，里程误差那条必须留着：那才是真正判断「这个吸附对看着就不对」
    # 的判据，而名字对不上的腿恰恰最需要它。曾把两条一起挡掉（`if not graph.preferred_edges:
    # return []`），代价是普速 name-miss 段丢掉了备用吸附锚点的兜底——实测 新靖线新海段
    # 盐城→东台：主线吸附对所在分量里只有一条 82.27km 的绕行路（里程差 19.27km），而备用
    # 锚点能找到 61.86km 的正路（里程差 1.14km）；护栏一挡，兜底不再执行，这段从「准」变
    # 成「差 19km」。全国约 30 段因此从误差 <2km 劣化到 >2km。
    suspicious = bool(graph.preferred_edges) and (
        min(item.preferred_ratio for item in primary) < EXTRA_SNAP_PROFILE_FLOOR
    )
    if not suspicious and mileage_km is not None and mileage_km > 0:
        best_error = min(abs(item.length_km - mileage_km) for item in primary)
        suspicious = best_error > EXTRA_SNAP_ERROR_RATIO * mileage_km
    if not suspicious:
        return []

    extra: List[PathCandidate] = []
    seen = {(item.path[0], item.path[-1]) for item in primary}
    for from_node, from_dist, to_node, to_dist in _alternative_snaps(
        graph,
        start,
        end,
        projection,
        threshold_km,
        skip=skip,
        limit=extra_snaps,
        prefer_profile=True,
    ):
        for item in _plan_attempt(
            graph,
            projection,
            from_node,
            from_dist,
            to_node,
            to_dist,
            k=k,
            max_length_km=max_length_km,
        ):
            key = (item.path[0], item.path[-1])
            if key in seen:
                continue
            seen.add(key)
            extra.append(item)
    return extra


# 绕路护栏：折线实长相对起终点直线距离的倍率上限。
#
# 客里表的站点坐标来自维基数据，个别站与线上同名站差了很远，于是最短路会为了
# 「串上」那个站而绕出一大圈——里程判据反而可能放它过去，因为运价里程同样失真。
# 铁路再盘山，实长也很少超过直线距离的三倍，所以超过就直接舍去，App 回退直线，
# 好过画一条明显错误的线。实测全网 5229 段的比值中位 1.10、p99 1.93，3.0 只砍
# 掉明显异常的尾巴（约 12 段），不会误伤真盘山线路。
DEFAULT_DETOUR_RATIO = 3.0
DETOUR_MIN_STRAIGHT_KM = 0.05


# 里程接受判据的绝对余量下限（km）：误差在 `里程 * max_error_ratio` 之内**或**在
# 这么多公里之内，都算接受。
#
# 为什么必须有：`mileage` 是客运运价里程，不是轨道实长。短腿尤其明显——线路所、
# 联络线这类区段根本不计客运运价，里程是个名义值，实测一批 1km 量级的腿，轨道实长
# 比里程长 36%~56%，纯按 35% 相对余量就会被判「里程不匹配」而退回直线。而 1km 量级
# 的腿多出的这几百米摊到行程地图上肉眼看不出来，丢掉折线的代价反而大得多。
#
# 长腿不受影响：35% 相对余量在小里程之外总是更大，所以这个下限只在里程 ≲5.7km 时
# 生效，那边界之外的口径一个字没变。
DEFAULT_ERROR_SLACK_KM = 2.0


# 主吸附对的候选看着不对时，额外再算几个「落在目标 profile 边上」的吸附点对。
#
# 只在可疑时才动手（离里程太远、或大半路程压在非目标 profile 的边上），否则每个成功
# 的段都要多付一次 Yen 枚举。实测全量 5225 段里有 1681 段（32%）会触发。
#
# 上限取 8 是因为「自己那条线」的节点在站场里往往排得很后：实测兰新线 达坂城→乌鲁木齐南
# 乌鲁木齐南一端最近的 6 个节点走出来的都是绕经市区那条 100.3km 的走法，直的那条
# 83.4km（同为目标 profile 的线，只有里程能分辨，误差 3.4km vs 13.3km）要到第 7 个
# 节点才出得来。每对多跑一次 Yen，代价 ~0.05s 量级，8 对换这一段画对，划算。
DEFAULT_EXTRA_SNAPS = 8


def plan_leg(
    start: Coord,
    end: Coord,
    rail: RailData,
    profile: str,
    *,
    mileage_km: Optional[float] = None,
    step_m: float = 400.0,
    snap_threshold_km: float = 5.0,
    k_paths: int = 6,
    max_error_ratio: float = 0.35,
    error_slack_km: float = DEFAULT_ERROR_SLACK_KM,
    close_error_ratio: float = 0.05,
    detour_ratio: float = DEFAULT_DETOUR_RATIO,
    extra_snaps: int = DEFAULT_EXTRA_SNAPS,
    jump_radius_km: float = DEFAULT_JUMP_RADIUS_KM,
    jump_snaps: int = DEFAULT_JUMP_SNAPS,
) -> LegPlan:
    """规划一个站间区间的轨道折线。

    先用走廊过滤缩小图，再枚举前 k 条最短路；里程已知时选长度最接近里程的那条，
    长度相近时优先贴目标 profile 的（preferred_ratio 高）。并行的高铁与普速在同名
    车站各有节点，站坐标可能离另一条线更近，所以主锚点的候选看着不对时会再算几个
    「落在目标 profile 边上」的锚点一起评（见 `search_paths`）；连贴线的候选都没有时，
    还会跨连通分量跳到目标线上车（`_jump_snap_candidates`）。

    接受判据是「误差在 [max_error_ratio] 或 [error_slack_km] 之内」，取较宽松的一
    边——见 [DEFAULT_ERROR_SLACK_KM] 里为什么短腿必须有绝对余量。

    通过判据后还有一道收尾：折线实长超过起终点直线距离 [detour_ratio] 倍的段直接
    舍去（`circuitous`）。
    """
    if rail.is_empty():
        return LegPlan(ok=False, reason="no_rail_data", mileage_km=mileage_km)

    corridor = corridor_filter(rail, start, end)
    if corridor.is_empty():
        return LegPlan(ok=False, reason="no_rail_data", mileage_km=mileage_km)

    graph = build_graph(corridor.lines, corridor.preferred, corridor.names_padded())
    if graph.is_empty():
        return LegPlan(ok=False, reason="empty_graph", mileage_km=mileage_km)

    projection = Projection((start[0] + end[0]) / 2.0)
    max_length = (
        None
        if mileage_km is None or mileage_km <= 0
        else mileage_km * (1.0 + max_error_ratio) + 5.0
    )
    candidates, reason = search_paths(
        graph,
        start,
        end,
        projection,
        k=k_paths,
        snap_threshold_km=snap_threshold_km,
        max_length_km=max_length,
        mileage_km=mileage_km,
        extra_snaps=extra_snaps,
        jump_radius_km=jump_radius_km,
        jump_snaps=jump_snaps,
    )
    # 只有 1 个节点的「路径」不是轨道：起终点吸附到同一个节点时 Yen 就是给这个，长度
    # 等于两端吸附空隙之和，几何上却是一个点——`_finalize` 把首尾覆盖成站点坐标后连 2
    # 个点都剩不下，App 什么也画不出来。里程够长时它还会落进 `DEFAULT_ERROR_SLACK_KM`
    # 的余量里被接受（实测「昆河线 南洞→大塔」1.68km 那段就是），所以在这里剔除。
    usable = [item for item in candidates if len(item.path) >= 2]
    if candidates and not usable:
        reason = "no_path"  # 当作没找到路，走下面同一套归类
    candidates = usable

    if not candidates:
        # 里程已知时，长度上限来自里程；搜不到路径说明没有与里程相容的走法，
        # 这本身就是一次里程不匹配，而不是单纯的拓扑断裂。
        if reason == "no_path" and mileage_km is not None and mileage_km > 0:
            return LegPlan(ok=False, reason="mileage_mismatch", mileage_km=mileage_km)
        return LegPlan(ok=False, reason=reason or "no_path", mileage_km=mileage_km)

    if mileage_km is None or mileage_km <= 0:
        # 里程未知：只能信几何，取最短；长度相同时优先贴目标 profile 的。
        chosen = min(candidates, key=lambda item: (item.length_km, -item.preferred_ratio))
        error_km = None
        error_ratio = None
    else:
        by_error = sorted(candidates, key=lambda item: abs(item.length_km - mileage_km))
        best_error = abs(by_error[0].length_km - mileage_km)
        # 长度接近时优先「贴 profile」的候选，避免为几十米的误差选到冗余支线。
        tolerance = max(best_error, mileage_km * close_error_ratio)
        close = [
            item for item in by_error if abs(item.length_km - mileage_km) <= tolerance
        ]
        chosen = min(
            close,
            key=lambda item: (
                -round(item.preferred_ratio, 2),
                abs(item.length_km - mileage_km),
            ),
        )
        error_km = abs(chosen.length_km - mileage_km)
        error_ratio = error_km / mileage_km
        if error_km > max(mileage_km * max_error_ratio, error_slack_km):
            return LegPlan(
                ok=False,
                reason="mileage_mismatch",
                length_km=chosen.length_km,
                mileage_km=mileage_km,
                mileage_error_km=error_km,
                mileage_error_ratio=error_ratio,
                preferred_ratio=chosen.preferred_ratio,
                board_jump_km=chosen.board_jump_km,
            )

    straight_km = haversine_km(start, end)
    if (
        straight_km >= DETOUR_MIN_STRAIGHT_KM
        and chosen.length_km > detour_ratio * straight_km
    ):
        return LegPlan(
            ok=False,
            reason="circuitous",
            length_km=chosen.length_km,
            mileage_km=mileage_km,
            mileage_error_km=error_km,
            mileage_error_ratio=error_ratio,
            preferred_ratio=chosen.preferred_ratio,
        )

    plan = LegPlan(
        ok=True,
        polyline=_finalize(chosen.path, start, end, step_m),
        length_km=chosen.length_km,
        mileage_km=mileage_km,
        mileage_error_km=error_km,
        mileage_error_ratio=error_ratio,
        preferred_ratio=chosen.preferred_ratio,
        board_jump_km=chosen.board_jump_km,
        line_runs=line_runs(chosen.path, graph),
    )
    return plan


def _finalize(
    path: Sequence[Coord], start: Coord, end: Coord, step_m: float
) -> List[Coord]:
    """重采样并保证首尾正好是站点坐标。

    站点坐标来自 coordinates.csv，精度高于 OSM 节点；端点对齐后相邻区段才能
    在 App 侧正确拼接。
    """
    if step_m > 0 and path_length_km(path) > step_m / 1000.0:
        path = resample_path(path, step_m)
    points = [quantize(point, 5) for point in path]
    points[0] = (round(start[0], 6), round(start[1], 6))
    points[-1] = (round(end[0], 6), round(end[1], 6))
    return points
