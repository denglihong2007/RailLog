"""铁路站间轨道折线的几何算法。

构图与吸附的思路移植自 TrainTrack 项目已经验证的实现（OSM 铁路网 → 图 →
吸附 → A*）。本项目独有的是**按线路名选路**：

    同一对车站之间可能存在并行线路（例如京沪高铁与京沪铁路），纯几何最短路
    永远只会选出较短的那条。这里改用 Yen 算法枚举前 k 条最短路，再按「长度 +
    离开目标线的里程 × 代价倍率」评分：目标线由 OSM way 的线路名确定，站间段
    属于哪条线来自线路库的站序。

    里程（线路库的 km）不参与选路，只作为诊断字段记录。它是运价里程，断链处
    与轨道实长能差出十几公里；经由线路的计算另有自己的数据链。

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
    同名正线，调用方据此拿到空的偏好集、交给 OSM 标签兜底或退回纯几何（见
    `line_base_key` 与 `preferred_for`）。
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


# 速度等级词。[LINE_ALIASES] 已把「高铁/客专/客运专线」归一成「高速」，这里补上它没有
# 归一的「城际」和「专线」，就是线路名里所有会区分速度等级的写法。
LINE_CLASS_WORDS = ("高速", "城际", "专线")


def line_base_key(value: str) -> str:
    """线路的「基本名」：匹配键再去掉速度等级词。

    2.6.1 的线路库把速度等级词从线路名里删掉了——「京港高铁合安段」变成「京港合安段」、
    「沪宁沿江高铁」变成「沪宁沿江」；当前线路库恢复了全名，但仍有个别线名不带等级词。
    基本名把两侧的等级词都抹掉，用来在命名分叉时说明「这是不是同一条线」：

        沪宁沿江        ↔ 沪宁沿江高速线   → 两边都是「沪宁沿江」（基本名相等）
        京包张包段      ← 京包客专线       → 「京包张包」以「京包」开头（前缀）
        京广            ↛ 京广高速线       → 只有落到前缀档时才会撞上，见调用方

    抹掉等级词会丢掉「普速/高铁」的区分，所以**不能**拿基本名直接当匹配键用：京广线与
    京广高速线在基本名上是一个键。调用方必须限定使用场景（见
    `build_rail_tracks.line_matches` 的三档递进：严格档命中就不再用基本名）。
    """
    key = line_match_key(value)
    for word in LINE_CLASS_WORDS:
        key = key.replace(word, "")
    return key


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
    """从线路名推断轨道类型。

    2.6.1 的线路库删掉了线路名里的速度等级词（「京港高铁合安段」→「京港合安段」），
    当时会把约 30 条高铁线判成普速；当前线路库恢复了全名，正常能判对。判错不致命：
    偏好集的主证据是线路名匹配（见 `build_rail_tracks.line_matches`），profile 只在
    「名字对不上任何 way」时才决定用不用 OSM 标签兜底。
    """
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

    lines 是全部 way 的坐标序列；preferred[i] 表示第 i 条 way 是否属于目标线（由
    线路名匹配，名字全线对不上时才退回 OSM 标签）；names[i] 是它的线路名
    （`name`/`name:zh`），用于把折线拆成「哪几条线拼的」。

    name_matched 记录取数范围里有没有任何 way 的名字对上了本线。选路不看它——
    preferred 已经把结论带上了——它只用于诊断（`preferred_basis`）。
    """

    lines: List[List[Coord]] = field(default_factory=list)
    preferred: List[bool] = field(default_factory=list)
    names: List[Optional[str]] = field(default_factory=list)
    name_matched: bool = False

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
            name_matched=self.name_matched or other.name_matched,
        )


@dataclass
class RailGraph:
    """站间寻路用的无向图。

    adjacency 的边权是投影空间欧氏距离（km）；preferred_edges 记录该边是否
    至少被一条属于目标线的 way 覆盖，候选评分用它算「离线里程」。

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
    因此不会影响按线名选路。
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
# 单段规划：按线路名选路
# --------------------------------------------------------------------------


@dataclass
class PathCandidate:
    path: List[Coord]
    length_km: float
    preferred_ratio: float
    # 登乘跳：折线首尾「站坐标 → 目标线上车点」两段直线的合计（km），每段各自不超
    # 过 jump_radius_km，所以这个数最大到 2×半径。0 表示两端都是同分量吸附、没跳。
    board_jump_km: float = 0.0

    @property
    def unpreferred_km(self) -> float:
        """折线里不在偏好集（名字对不上本线）的里程。

        吸附空隙也算在 length_km 里，但没参与 ratio 的统计，所以这里只是一个略偏大
        的近似——选路只拿它比较候选之间的相对大小，这点偏差不影响结论。
        """
        return self.length_km * (1.0 - self.preferred_ratio)


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
    `search_paths` 把两种锚法都算一遍、由候选评分（贴线程度 + 长度）来定。

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
    per_side: bool = False,
) -> List[Tuple[Coord, float, Coord, float]]:
    """最近的那对吸附点之间不通时，给出别的候选对，按吸附距离之和升序。

    只挑**同分量**的候选对：跨分量再近也走不通，白跑一次 Yen。`skip` 是第一对
    （也就是原来的行为），不重复试。

    `prefer_profile` 时改成优先「两端都接在目标 profile 的边上」的对，再比吸附距离：
    并行的高铁与普速各有节点，要挑的是自己那条线上的节点，而它在站场里往往不是最近的
    那个（同一个车站附近可能有好几条股道）。

    `per_side` 时不做交叉积取前 `limit` 对，而是「两端各取最近 `limit` 个节点，分别与
    另一端的最近节点配对」。交叉积按吸附距离之和排序有个盲点：一端节点密集（站场咽喉
    里十几个节点挤在两百米内）时，与它们配对的每一对都排在前面，另一端的纵深一个都
    轮不到。实测达成线 保平所→成都：最近的 16 个起始节点里前 11 个都在环线咽喉上，
    第 12 个（202m 外）才接上往西的正路；只取前 8 对时整段绕成 14.9km（直线 6.3km）。

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

    def allowed(
        start_node: Coord, end_node: Coord
    ) -> bool:
        return component.get(start_node) == component.get(end_node) and (
            start_node,
            end_node,
        ) != skip

    def entry(
        start_dist: float, start_node: Coord, end_dist: float, end_node: Coord
    ) -> Tuple[bool, float, float, Coord, float, Coord]:
        return (
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

    key = (lambda item: (item[0], item[1])) if prefer_profile else (lambda item: item[1])

    if per_side:
        pairs: List[Tuple[bool, float, float, Coord, float, Coord]] = []
        if starts and ends:
            end_dist, end_node = ends[0]
            pairs.extend(
                entry(start_dist, start_node, end_dist, end_node)
                for start_dist, start_node in starts
                if allowed(start_node, end_node)
            )
            start_dist, start_node = starts[0]
            pairs.extend(
                entry(start_dist, start_node, end_dist, end_node)
                for end_dist, end_node in ends
                if allowed(start_node, end_node)
            )
        pairs.sort(key=key)
        seen_pairs: Set[Tuple[Coord, Coord]] = set()
        selected: List[Tuple[Coord, float, Coord, float]] = []
        for _, _, start_dist, start_node, end_dist, end_node in pairs:
            node_pair = (start_node, end_node)
            if node_pair in seen_pairs:
                continue
            seen_pairs.add(node_pair)
            selected.append((start_node, start_dist, end_node, end_dist))
        return selected

    pairs = sorted(
        (
            entry(start_dist, start_node, end_dist, end_node)
            for start_dist, start_node in starts
            for end_dist, end_node in ends
            if allowed(start_node, end_node)
        ),
        key=key,
    )
    return [
        (start_node, start_dist, end_node, end_dist)
        for _, _, start_dist, start_node, end_dist, end_node in pairs[:limit]
    ]


EXTRA_SNAP_PROFILE_FLOOR = 0.5

# 主吸附对的最短候选超过直线距离这么多倍时，同样当作可疑、去试备用吸附点。
#
# 这是纯几何判据，和里程无关：最近的那个图节点有时落在站场死端/环线上，从它出发只能
# 绕一圈回到正线。取值故意压得低：触发一次的代价只是多枚举几对 Yen，而漏掉一段就会
# 在 App 上留下一个来回绕的圈。实测现库成功段的 `length / 直线距离` 中位 1.09、
# p95 1.47，1.2 会让约两成的段多算几对；真盘山的线路误触发也无妨——备用候选只是
# 多摆几条，仍由代价函数在「长度 + 离线里程」上比。
EXTRA_SNAP_RATIO = 1.2

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
# 门槛太低，会把「走在目标线上」和「只在站场里蹭到一小段目标线、出站就换别的线」的
# 候选混为一谈。实测京广高铁 广州北→广州南：站坐标吸附在京广线上（非偏好），两端
# 同分量、走得通，那条走法借道南广线，整段只有一半落在目标线上，ratio 0.5004 刚刚
# 压过 0.5 的门槛，于是登乘跳一次都不触发，这一段就一直画在 51.71km 的绕行线上。
# 跳上去的正确解是 46.10km、ratio 1.00——该跳的时候必须跳。
#
# 名字成为主证据之后，并行线不再因为「同为高铁」混进偏好集，这类候选的 ratio 会更低；
# 门槛保留 0.9，继续挡「站场内蹭到线、出站就换线」的走法。
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


def _candidates_look_right(
    candidates: Sequence[PathCandidate], start: Coord, end: Coord
) -> bool:
    """候选里有没有一条「既贴目标线、长度又不离谱」的走法。

    备用吸附对要不要继续试就以它为准：第一对通了、但只能沿站场环线绕一大圈时，
    显然不值得收手。
    """
    straight_km = haversine_km(start, end)
    for item in candidates:
        if item.preferred_ratio < EXTRA_SNAP_PROFILE_FLOOR:
            continue
        if straight_km < DETOUR_MIN_STRAIGHT_KM:
            return True
        if item.length_km <= EXTRA_SNAP_RATIO * straight_km:
            return True
    return False


def search_paths(
    graph: RailGraph,
    start: Coord,
    end: Coord,
    projection: Projection,
    *,
    k: int = 6,
    snap_threshold_km: float = 5.0,
    max_length_km: Optional[float] = None,
    extra_snaps: int = 0,
    jump_radius_km: float = DEFAULT_JUMP_RADIUS_KM,
    jump_snaps: int = DEFAULT_JUMP_SNAPS,
) -> Tuple[List[PathCandidate], Optional[str]]:
    """吸附起终点后枚举候选路径，按长度升序返回。

    主吸附对（各自最近的节点）不通时，会换到别的候选吸附点再试（见
    `_alternative_snaps`），这是原来就有的兜底，先试的永远是主吸附对。换过去的也会
    继续试下去，直到有一条「既贴目标线、长度又不离谱」的（见
    `_candidates_look_right`）——第一对通了但只能沿站场环线绕一圈的段，正是靠这一步
    才拉回直路的。

    `extra_snaps` 时，主吸附对的候选如果看着不对（大半路程压在非目标线的边上、最短
    候选比直线距离长出太多，或者这条腿根本没有名字证据），就把 [extra_snaps] 个
    「落在目标线上」的吸附对也算一遍，**候选合并在一起**返回，由调用方的评分去定。
    并行的高铁与普速在同名车站各有节点、站坐标可能离另一条线更近（实测宝成线
    昭化→江油：离西成客专的江油节点 140m、离宝成自己的 233m），只按距离锚到客专
    之后，那一段就只有沿客专走的一条 151km 的解法；把宝成那边的 136km、preferred
    0.99 的那条一起摆上，按贴线程度评分自然选对。
    """
    if graph.is_empty():
        return [], "empty_graph"

    start_node, start_dist = _snap_node(graph, start, projection, snap_threshold_km)
    end_node, end_dist = _snap_node(graph, end, projection, snap_threshold_km)
    if start_node is None or end_node is None:
        return [], "snap_failed"

    attempts = [(start_node, start_dist, end_node, end_dist)]
    # 备用吸附对的候选先攒着：第一对通了不代表通得对——站场里落在环线/死端上的节点
    # 只能绕一大圈回正线，而下一对里就有一条直路。几何上说得过去才收手。
    collected: List[PathCandidate] = []
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
                # 备用吸附对在 `_extra_snap_candidates` 里已经算过一遍了，这里可以收手。
                candidates.sort(key=lambda item: item.length_km)
                return candidates, None
            collected.extend(candidates)
            if _candidates_look_right(collected, start, end):
                collected.sort(key=lambda item: item.length_km)
                return collected, None
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

    if collected:
        # 备用对全试完也没有几何上说得过去的那条：把攒下的都摆出来，由代价函数选。
        collected.sort(key=lambda item: item.length_km)
        return collected, None

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
    extra_snaps: int,
    skip: Tuple[Coord, Coord],
) -> List[PathCandidate]:
    """主吸附对的候选看着不对时，再算几个「落在目标线上」的吸附对。

    只在主吸附对可疑时才动手，否则每个段都要为这几对多跑一遍 Yen 枚举。
    """
    if extra_snaps <= 0:
        return []
    # 可疑判据有两条，任一成立就多算几对：
    # - 有偏好集时，主吸附对的候选全都不够贴线（低于 EXTRA_SNAP_PROFILE_FLOOR）；
    # - 主吸附对的最短候选比直线距离长出太多（超过 EXTRA_SNAP_RATIO 倍）——最近的那个
    #   图节点常常落在站场死端/环线上，从它出发只能绕一大圈回正线，而离站 100m 的另一
    #   个节点就是直路。实测成灌线 犀浦→红光镇：最近节点 2m 处走 16.94km，一百多米外
    #   的节点走 3.65km（直线 3.55km）；珠机城际线 珠海长隆→井湾 15.81 vs 6.19km。
    #   撤掉里程预算之后，这是唯一还会把这类吸附点对顶掉的判据，所以必须按几何补上。
    #
    # 没有偏好集时（普速腿的线路名对不上任何 OSM way），ratio 恒为 0、说明不了任何事，
    # 但这条腿恰恰只剩吸附点这一个变量——一律多算几对，由「最短」来定。实测 新靖线
    # 新海段 盐城→东台：主锚点所在分量里只有一条 82.27km 的绕行路，备用锚点能找到
    # 61.86km 的正路；这条兜底必须留着。
    #
    # 曾经这里还有一条「长度离里程太远也可疑」的判据，它随凑里程机制一起去掉——里程
    # 不再参与选路，也就不该再用来决定要不要多算吸附对。
    straight_km = haversine_km(start, end)
    geometric_doubt = (
        straight_km >= DETOUR_MIN_STRAIGHT_KM
        and min(item.length_km for item in primary) > EXTRA_SNAP_RATIO * straight_km
    )
    if not graph.preferred_edges:
        suspicious = True
    else:
        suspicious = (
            min(item.preferred_ratio for item in primary) < EXTRA_SNAP_PROFILE_FLOOR
            or geometric_doubt
        )
    if not suspicious:
        return []

    extra: List[PathCandidate] = []
    seen = {(item.path[0], item.path[-1]) for item in primary}

    def absorb(pairs: Sequence[Tuple[Coord, float, Coord, float]]) -> None:
        for from_node, from_dist, to_node, to_dist in pairs:
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

    absorb(
        _alternative_snaps(
            graph,
            start,
            end,
            projection,
            threshold_km,
            skip=skip,
            limit=extra_snaps,
            prefer_profile=True,
        )
    )
    # 第一排备用对没救回来（最短候选仍明显比直线长），说明最近的若干个节点全在
    # 同一个站场咽喉里，需要把两端的纵深都试到：每个起始节点配最近的终点节点，
    # 每个终点节点配最近的起始节点。交叉积按吸附距离之和排序做不到这件事——一端
    # 节点越密，它占掉的名额越多。这条只在几何判据成立时才走，实测达成线
    # 保平所→成都 靠它从 14.9km 的环线改回 6.5km 的直路。
    if geometric_doubt and min(
        (item.length_km for item in [*primary, *extra]), default=float("inf")
    ) > EXTRA_SNAP_RATIO * straight_km:
        absorb(
            _alternative_snaps(
                graph,
                start,
                end,
                projection,
                threshold_km,
                skip=skip,
                limit=SNAP_NODE_POOL,
                prefer_profile=True,
                per_side=True,
            )
        )
    return extra


# 绕路护栏：折线实长相对起终点直线距离的倍率上限。
#
# 客里表的站点坐标来自维基数据，个别站与线上同名站差了很远，于是最短路会为了
# 「串上」那个站而绕出一大圈。铁路再盘山，实长也很少超过直线距离的三倍，所以
# 超过就直接舍去（这是纯几何护栏，不依赖里程），App 回退直线，
# 好过画一条明显错误的线。实测全网 5229 段的比值中位 1.10、p99 1.93，3.0 只砍
# 掉明显异常的尾巴（约 12 段），不会误伤真盘山线路。
DEFAULT_DETOUR_RATIO = 3.0
DETOUR_MIN_STRAIGHT_KM = 0.05


# 候选评分：`长度 + 离线里程 × 本倍率`，取最小的一条。
#
# 只按长度取最短，会把正确但略长的同名正线让给一条走别的线路的直线捷径；只按
# preferred_ratio 取最高，又会为了省掉几个百分点的无名站场段而选一条明显更长的
# 绕行线。折成一个标量后两个毛病都没有：离线 1km 相当于多绕 5km。实测徐兰高速线
# 渭南北→临潼东，回头支线长 33.59km、离线约 9.5km（借道大西高速线），代价约
# 81km；正线 24.3km、几乎全在徐兰上，代价约 25km。里程表在这一段本身是错的
# （相邻站 km 差 30km，OSM 实长 24.3km），以前正是它把折线拉上了回头支线。
OFF_NAME_PENALTY = 5.0


def _candidate_cost(item: PathCandidate) -> float:
    return item.length_km + OFF_NAME_PENALTY * item.unpreferred_km


# 主吸附对的候选看着不对时，额外再算几个「落在目标线上」的吸附点对。
#
# 只在可疑时才动手（大半路程压在非目标线的边上，或这条腿根本没有名字证据），否则
# 每个成功的段都要多付一次 Yen 枚举。实测全量 5225 段里有 1681 段（32%）会触发。
#
# 上限取 8 是因为「自己那条线」的节点在站场里往往排得很后：实测兰新线 达坂城→乌鲁木齐南
# 乌鲁木齐南一端最近的 6 个节点走出来的都是绕经市区那条 100.3km 的走法，直的那条
# 83.4km 要到第 7 个节点才出得来。每对多跑一次 Yen，代价 ~0.05s 量级，8 对换这一段
# 画对，划算。
DEFAULT_EXTRA_SNAPS = 8


# 折线实长与运价里程差在这个容差内，就算「里程佐证了这段绕路」。
#
# 绕路护栏是纯几何的，对「线路本身就绕」无能为力：宁铜线 南京→中华门 直线只有
# 9.1km，正线却要沿城南绕到 30km 外，里程表写 33km——3.0 倍护栏会把唯一正确的
# 几何判成坐标失真。里程表虽然不能用来选路（断链处的 km 差能差出十几公里，见
# `plan_leg` 的说明），但用来**验证**一条已经选出来的路由是否离谱是够的：
# 差 2.6km / 8% 说明这条线确实这么绕。
#
# 下限只能给 3km，不能再宽：站坐标离已映射的轨道很远时，吸附空隙也计进实长，
# 短段会凭空「变长」好几公里。实测昆河线 泸江河→1909广场 站间直线 1.5km、轨道
# 节点只有 0.37km，可两端各吸附出 2-3km 空隙，实长 5.46km；里程表 1km。若容差
# 取 5km，这种段会被当成「里程佐证」放行，画出来就是一条靠跳线拉长的假绕路。
MILEAGE_CORROBORATION_KM = 3.0
MILEAGE_CORROBORATION_RATIO = 0.2


def mileage_corroborates(length_km: float, mileage_km: Optional[float]) -> bool:
    """实长与运价里程对得上（容差 max(3km, 20%)）。里程缺失时无话可说，返回 False。"""
    if mileage_km is None or mileage_km <= 0:
        return False
    tolerance = max(
        MILEAGE_CORROBORATION_KM, MILEAGE_CORROBORATION_RATIO * mileage_km
    )
    return abs(length_km - mileage_km) <= tolerance


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
    detour_ratio: float = DEFAULT_DETOUR_RATIO,
    extra_snaps: int = DEFAULT_EXTRA_SNAPS,
    jump_radius_km: float = DEFAULT_JUMP_RADIUS_KM,
    jump_snaps: int = DEFAULT_JUMP_SNAPS,
    corridor_km: Optional[float] = None,
) -> LegPlan:
    """规划一个站间区间的轨道折线。

    先用走廊过滤缩小图，再枚举前 k 条最短路，按 `长度 + 离线里程 ×
    [OFF_NAME_PENALTY]` 取代价最低的一条。哪条线是「本线」由线路名决定：偏好集由
    调用方按 OSM 的 way 名匹配好（见 build_rail_tracks 的 `line_matches`）。并行的高铁
    与普速在同名车站各有节点，站坐标可能离另一条线更近，所以主锚点的候选看着不对时
    会再算几个「落在目标线上」的锚点一起评（见 `search_paths`）；连贴线的候选都没有
    时，还会跨连通分量跳到目标线上车（`_jump_snap_candidates`）。

    `mileage_km` **只写进结果、不参与选路**：线路库的 km 是运价里程，断链处相邻站的
    差值能和轨道实长差出十几公里（实测徐兰高速线 渭南北→临潼东 的 km 差 30km、OSM
    实长 24.3km），拿它反推几何会把折线拽到并行的另一条线上，或者绕出回头支线。
    里程的用途在经由线路计算，那边另有自己的数据链。

    最后还有一道收尾：折线实长超过起终点直线距离 [detour_ratio] 倍的段直接舍去
    （`circuitous`），这是站坐标飞到同名异地时的兜底，与里程无关。唯一的例外是
    运价里程正好也这么长（见 [mileage_corroborates]）——那就不是坐标飞了，是这条
    线路本身绕。

    `corridor_km` 只在调用方想重试更宽的数据时才传：默认按起终点直线距离算
    （[corridor_km_for]）。站间有大弯时正线会整段落在默认走廊外，见
    build_rail_tracks 的宽走廊重试。
    """
    if rail.is_empty():
        return LegPlan(ok=False, reason="no_rail_data", mileage_km=mileage_km)

    corridor = corridor_filter(rail, start, end, corridor_km)
    if corridor.is_empty():
        return LegPlan(ok=False, reason="no_rail_data", mileage_km=mileage_km)

    graph = build_graph(corridor.lines, corridor.preferred, corridor.names_padded())
    if graph.is_empty():
        return LegPlan(ok=False, reason="empty_graph", mileage_km=mileage_km)

    projection = Projection((start[0] + end[0]) / 2.0)
    candidates, reason = search_paths(
        graph,
        start,
        end,
        projection,
        k=k_paths,
        snap_threshold_km=snap_threshold_km,
        extra_snaps=extra_snaps,
        jump_radius_km=jump_radius_km,
        jump_snaps=jump_snaps,
    )
    # 只有 1 个节点的「路径」不是轨道：起终点吸附到同一个节点时 Yen 就是给这个，长度
    # 等于两端吸附空隙之和，几何上却是一个点——`_finalize` 把首尾覆盖成站点坐标后连 2
    # 个点都剩不下，App 什么也画不出来（实测「昆河线 南洞→大塔」1.68km 那段就是），
    # 所以在这里剔除。
    usable = [item for item in candidates if len(item.path) >= 2]
    if candidates and not usable:
        reason = "no_path"  # 当作没找到路，走下面同一套归类
    candidates = usable

    if not candidates:
        return LegPlan(ok=False, reason=reason or "no_path", mileage_km=mileage_km)

    chosen = min(candidates, key=_candidate_cost)
    # 里程只作为诊断数据落库：折线实长与运价里程差多少，查库时能看到。它不再决定
    # 选哪条候选，也不再因为差得远而把整段判失败。
    if mileage_km is not None and mileage_km > 0:
        error_km = abs(chosen.length_km - mileage_km)
        error_ratio = error_km / mileage_km
    else:
        error_km = None
        error_ratio = None

    straight_km = haversine_km(start, end)
    if (
        straight_km >= DETOUR_MIN_STRAIGHT_KM
        and chosen.length_km > detour_ratio * straight_km
        and not mileage_corroborates(chosen.length_km, mileage_km)
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
