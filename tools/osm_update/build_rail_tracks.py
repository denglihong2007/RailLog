#!/usr/bin/env python3
"""离线生成站间轨道折线，写入 app/assets/db/rail_tracks.db。

输入：
  app/assets/db/routes.db        线路与车站里程表（决定站间对与里程约束）
  app/assets/db/coordinates.csv  站点 WGS84 坐标（兜底）
  china.osm.pbf                  铁路网几何 + OSM 车站坐标（主源，--source pbf）
                                 或 Overpass API（--source overpass，调试用）

输出：
  app/assets/db/rail_tracks.db   tracks(route_name, from_station, to_station) →
                                 gzip(JSON([[lat,lon], ...]))，WGS84
                                 stations(station_name, latitude, longitude)
                                 —— 解析后的站坐标，App 侧优先用它标站

站间对的枚举必须与 App 侧 TripMapService.buildData 完全一致：同一线路内按
station_index 排序，只保留能查到坐标的站点，相邻坐标相同者合并，然后相邻两站
构成一段。这样管线里的每一段都能在 App 侧被真实绘制到。

车站坐标以 coordinates.csv 为基线，OSM（railway=station/halt 节点）只就近校正它、
并补上它缺的站。OSM 坐标就是轨道上的点，能让折线端点与 App 标记的站位置一致；
但**不能**让 OSM 无条件优先——它的车站是按站名全局索引的，通用站名会撞到外省
的同名节点（实测会把错配段从 36 段放大到 135 段）。详见 from_sources 的说明。

用法（默认路径都锚在仓库里，从哪运行都一样）：
    # 只看会生成多少段，不读 PBF、不写文件
    python tools/osm_update/build_rail_tracks.py

    # 单线路试跑（首次读 PBF 约 20s；只算一小撮线路时配 --workers 1 最快）
    python tools/osm_update/build_rail_tracks.py --source pbf --route 京沪高速线 --apply

    # 全量（一般用 update.py 更省事，它会把最新数据先下好）
    python tools/osm_update/build_rail_tracks.py --source pbf --apply

    # 兜底：Overpass 在线取数（调试用，慢且受镜像影响）
    python tools/osm_update/build_rail_tracks.py --source overpass --route 宝成线 --apply
"""

from __future__ import annotations

import argparse
import concurrent.futures
import gzip
import io
import json
import math
import multiprocessing
import os
import re
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, Iterable, Iterator, List, Mapping, Optional, Sequence, Tuple

# 同目录平级 import：这样既能当脚本直接跑，也能被 unittest 当包发现。
MODULE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(MODULE_DIR))

import rail_track_geometry as geo  # noqa: E402

TOOLS_DIR = MODULE_DIR.parent
REPO_ROOT = TOOLS_DIR.parent
DEFAULT_ROUTES_DB = REPO_ROOT / "app" / "assets" / "db" / "routes.db"
DEFAULT_COORDINATES = REPO_ROOT / "app" / "assets" / "db" / "coordinates.csv"
DEFAULT_OUT = REPO_ROOT / "app" / "assets" / "db" / "rail_tracks.db"
# 缓存留在 tools/.cache/ 下（1.7GB 的 PBF 已经在那儿），不跟着代码一起搬。
DEFAULT_CACHE = TOOLS_DIR / ".cache" / "rail_tracks"
# 一次性下载的全国 OSM 数据（1.7GB，不进 Git）。见 tools/.gitignore。
DEFAULT_PBF = DEFAULT_CACHE / "china.osm.pbf"
# 从 PBF 里抽出的车站坐标，2MB 左右：有了它，看计划就不必再读一遍 PBF。
OSM_STATIONS_CACHE = "osm_stations.json"
# 与之配套的坐标修正清单（消歧改了哪些站），同样只为省一次 PBF 重读。
OSM_STATION_FIXES_CACHE = "osm_station_fixes.json"

# OSM 车站坐标只在离 coordinates.csv 这么近时才覆盖它。见 from_sources 的说明：
# 站名是全局索引的，通用站名会撞到外省的同名节点，必须有个「不可能是同一个站」的
# 半径来兜住。30km 足够容纳真实的位置修正（实测最大 9.2km），又远小于任何跨市距离。
#
# 这条守卫只用于**线路消歧没给出结论**的站；被消歧验证过的坐标不受它约束——那正是
# 「CSV 错、OSM 对且相距上千公里」（新立屯）这类必须越过守卫的场景。
OSM_TRUST_RADIUS_KM = 30.0

# 线路消歧：候选坐标离本线路的 way 这么近，才认定「就是这个站」。
# 车站节点在 OSM 里通常是轨道旁的独立点（不在 way 的节点序列里），实测正确匹配的
# 距离在几百米内；5km 足以容纳站场尺度与几处测绘偏差，又远小于跨市距离。
LINE_SNAP_RADIUS_KM = 5.0

# 依次尝试的 Overpass 实例。overpass-api.de 在请求量大时会直接断开连接，
# 因此把实测更稳的镜像放在前面，失败后自动换下一个。
OVERPASS_ENDPOINTS = (
    "https://overpass.private.coffee/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass-api.de/api/interpreter",
)
USER_AGENT = "RailLog-TrackBuilder/1.0 (railway geometry data pipeline)"

# bbox 量化到 0.05°，相邻区段共用同一次取数。
BBOX_QUANTUM = 0.05


def _utf8_stdout() -> None:
    """把 stdout/stderr 换成 UTF-8，中文进度才不会被控制台代码页吞掉。

    必须幂等：再包一层会把旧的那层丢掉，而 TextIOWrapper 被回收时会顺手关掉底层
    buffer，于是整个进程的 stdout 就废了（`lost sys.stdout`）。单进程路径会在
    main() 和 _init_worker() 里各调一次，正好踩中。
    """
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name)
        if not hasattr(stream, "buffer"):
            continue
        if (getattr(stream, "encoding", "") or "").lower().replace("-", "") == "utf8":
            continue  # 已经是 UTF-8（或已被本函数包过），不要再包
        setattr(
            sys,
            stream_name,
            io.TextIOWrapper(stream.buffer, encoding="utf-8", line_buffering=True),
        )


# --------------------------------------------------------------------------
# 站点坐标索引：逐字复刻 Dart 的 _stationKeys + StationCoordinateIndex
# --------------------------------------------------------------------------

_PAREN_SUFFIX_RE = re.compile(r"\s*\([^)]*\)\s*$")
_STATION_SUFFIX_RE = re.compile(r"(火车站|站)$")
_WHITESPACE_RE = re.compile(r"\s+")


def _station_keys(value: str) -> List[str]:
    """与 Dart _stationKeys 完全一致：先给原始小写，再给归一化名。"""
    trimmed = value.strip().replace("（", "(").replace("）", ")")
    if not trimmed:
        return []
    keys = [trimmed.lower()]
    normalized = _PAREN_SUFFIX_RE.sub("", trimmed)
    normalized = _STATION_SUFFIX_RE.sub("", normalized)
    normalized = _WHITESPACE_RE.sub("", normalized).lower()
    if normalized:
        keys.append(normalized)
    return keys


def _parse_csv_row(line: str) -> Optional[Tuple[str, float, float]]:
    """解析 coordinates.csv 的一行；站名里可能含逗号，与 Dart 一样从后往前找两个逗号。"""
    last = line.rfind(",")
    if last <= 0:
        return None
    second_last = line.rfind(",", 0, last)
    if second_last <= 0:
        return None
    name = line[:second_last].strip()
    if not name:
        return None
    try:
        latitude = float(line[second_last + 1 : last].strip())
        longitude = float(line[last + 1 :].strip())
    except ValueError:
        return None
    return name, latitude, longitude


class StationCoordinateIndex:
    """对应 Dart 的 StationCoordinateIndex：putIfAbsent 索引 + find 双键回退。"""

    def __init__(self) -> None:
        self._coordinates: Dict[str, geo.Coord] = {}

    def seed(self, name: str, latitude: float, longitude: float) -> None:
        """写入一个站名坐标，已存在则不改（putIfAbsent）。

        「先写入的源优先」正是坐标优先级机制：OSM 先 seed，CSV 随后只能补空缺。
        """
        for key in _station_keys(name):
            self._coordinates.setdefault(key, (latitude, longitude))

    @classmethod
    def from_csv(cls, path: Path) -> "StationCoordinateIndex":
        return cls._with_csv(cls(), path)

    @classmethod
    def from_sources(
        cls,
        osm_stations: Mapping[str, Tuple[str, float, float]],
        csv_path: Path,
        verified: Optional[Mapping[str, Tuple[str, float, float]]] = None,
    ) -> "StationCoordinateIndex":
        """coordinates.csv 为基线，OSM 车站坐标就近校正 + 补缺。

        不能简单地「OSM 优先」：OSM 的 station/halt 节点是按站名全局索引的，而
        「莲塘」「康庄」「双桥」「大厂」「安定」这类通用站名在全国有几十个同名
        节点，first-wins 会稳定地挑到外省那一个。实测这么做会把护栏拦下的错配段
        从 36 段放大到 135 段——覆盖率 92.9% 只说明「查得到」，不说明「查得对」。

        所以 OSM 只在两种情况下被采信：

        * CSV 没有这个站 → 直接用 OSM（这正是我们要补的那 129 个站）；
        * CSV 有，且 OSM 的值在 [OSM_TRUST_RADIUS_KM] 之内 → 当作把车站挪到轨道
          上的微调（实测 沧州西 就靠这个修正了 9.2km 的偏差）。

        超出半径的一律保留 CSV：宁可留着一个已知的小偏差，也不能把车站瞬移到
        上千公里外。

        [verified] 是例外，也是唯一能越过那条半径的来源：它由
        [disambiguate_stations] 按线路几何确认过（正确的坐标必然紧邻本线路的
        way），比 CSV 和 first-wins 的 OSM 都可靠。CSV 错、OSM 对、两者相距上千
        公里的站（新立屯）只能靠它救回来。
        """
        index = cls.from_csv(csv_path)
        verified_keys: set = set()
        for name, latitude, longitude in (verified or {}).values():
            for key in _station_keys(name):
                index._coordinates[key] = (latitude, longitude)
                verified_keys.add(key)
        for name, latitude, longitude in osm_stations.values():
            coordinate = (latitude, longitude)
            for key in _station_keys(name):
                if key in verified_keys:
                    continue  # 已验证的站不被 first-wins 的同名节点覆盖
                existing = index._coordinates.get(key)
                if existing is None or geo.haversine_km(existing, coordinate) <= OSM_TRUST_RADIUS_KM:
                    index._coordinates[key] = coordinate
        return index

    @classmethod
    def _with_csv(cls, index: "StationCoordinateIndex", path: Path) -> "StationCoordinateIndex":
        # coordinates.csv 带 UTF-8 BOM。
        for line in path.read_text(encoding="utf-8-sig").splitlines()[1:]:
            row = _parse_csv_row(line)
            if row is not None:
                index.seed(*row)
        return index

    def find(self, station: str) -> Optional[geo.Coord]:
        for key in _station_keys(station):
            coordinate = self._coordinates.get(key)
            if coordinate is not None:
                return coordinate
        return None

    def get(self, key: str) -> Optional[geo.Coord]:
        """按归一化键直接取坐标（键由 [_station_keys] 生成）。"""
        return self._coordinates.get(key)

    def remove(self, name: str) -> None:
        """删掉一个站的坐标，连同它在索引里的其他写法。

        舍去不可信坐标时用：索引是 name-keyed 的，删的是这个站名在全国的那一个
        值。被删的站随后在 [enumerate_legs] 里等同「没有坐标」，前后两站自动桥接。

        不能只删 [name] 自己那几个键：同一个站可能以多种写法进了索引（CSV 一行
        「永乐」、OSM 一个节点叫「永乐站」，或同一节点的 alt_name），归一化后是
        同一个站，留着别的写法就会把坐标顶回来、这个站其实没被舍去。
        """
        keys = _station_keys(name)
        if not keys:
            return
        normalized = keys[-1]
        for key in [k for k in self._coordinates if normalized in _station_keys(k)]:
            del self._coordinates[key]

    def __len__(self) -> int:
        return len(self._coordinates)


# --------------------------------------------------------------------------
# 枚举站间对
# --------------------------------------------------------------------------


@dataclass
class Leg:
    route_name: str
    from_station: str
    to_station: str
    start: geo.Coord
    end: geo.Coord
    mileage_km: Optional[float]
    profile: str
    suspect_reason: Optional[str] = None

    def key(self) -> Tuple[str, str, str]:
        return (self.route_name, self.from_station, self.to_station)


@dataclass
class EnumerationStats:
    route_count: int = 0
    station_rows: int = 0
    located_stations: int = 0
    missing_station_rows: int = 0
    collided_pairs: int = 0
    suspect_legs: int = 0
    legs: List[Leg] = field(default_factory=list)
    # 截断前的段数。[legs] 被 --limit 截断后，它是唯一还记得「全量有多少段」的地方。
    legs_total: int = 0

    def profile_counts(self) -> Dict[str, int]:
        counts = {geo.HSR: 0, geo.CONVENTIONAL: 0}
        for leg in self.legs:
            counts[leg.profile] = counts.get(leg.profile, 0) + 1
        return counts


def _version_sort_key(datatype: str, version_id: str) -> Tuple[Tuple[int, ...], Tuple[int, ...]]:
    """datatype 形如 '2026-7-15'；按数字段比较，避免字符串比较把 10 排到 2 前面。"""
    numbers = tuple(int(part) for part in re.findall(r"\d+", datatype or ""))
    version_numbers = tuple(int(part) for part in re.findall(r"\d+", version_id or ""))
    return (numbers, version_numbers)


def _pick_route_versions(connection: sqlite3.Connection) -> List[Tuple[str, str]]:
    """每个 route_name 取一个版本：datatype 最新，其次 version_id 最大，其次站点最多。

    个别线路在库里有两个版本（如「田灞联络线」），必须定一个，否则主键会冲突。
    这与 App 侧 routeStationIndexes 用 route_name 做键、后者覆盖前者的行为一致。
    """
    rows = connection.execute(
        """
        SELECT r.route_version_id, r.route_name, r.datatype, COUNT(s.id)
        FROM routes r
        LEFT JOIN stations s ON s.route_version_id = r.route_version_id
        GROUP BY r.route_version_id
        """
    ).fetchall()

    best: Dict[str, Tuple[Tuple, str]] = {}
    for version_id, route_name, datatype, station_count in rows:
        sort_key = (*_version_sort_key(datatype, version_id), int(station_count or 0))
        current = best.get(route_name)
        if current is None or sort_key > current[0]:
            best[route_name] = (sort_key, version_id)
    return sorted((route_name, entry[1]) for route_name, entry in best.items())


def _leg_mileage(
    from_mileage: Optional[float], to_mileage: Optional[float]
) -> Optional[float]:
    """两站里程桩之差；任一端缺失或不是正里程时返回 None。

    [enumerate_legs] 与 [discard_implausible_station_coordinates] 必须用同一套算法，
    否则「哪段被判异常」和「据此舍去哪一站」会指向不同的段。
    """
    if from_mileage is None or to_mileage is None:
        return None
    mileage = abs(float(to_mileage) - float(from_mileage))
    return mileage if mileage > 0 else None


def enumerate_legs(
    routes_db: Path,
    coordinates: StationCoordinateIndex,
    route_filter: Optional[Sequence[str]] = None,
    limit: Optional[int] = None,
) -> EnumerationStats:
    stats = EnumerationStats()
    connection = sqlite3.connect(f"file:{routes_db}?mode=ro", uri=True)
    try:
        wanted = {geo.route_key(name) for name in route_filter} if route_filter else None

        for route_name, version_id in _pick_route_versions(connection):
            if wanted is not None and geo.route_key(route_name) not in wanted:
                continue
            stats.route_count += 1

            rows = connection.execute(
                """
                SELECT station_index, station_name, mileage
                FROM stations WHERE route_version_id = ?
                ORDER BY station_index
                """,
                (version_id,),
            ).fetchall()
            stats.station_rows += len(rows)

            # 与 App 侧一致：先按 station_index 排序，剔除查不到坐标的站，
            # 再合并相邻的同坐标站（同一地点两个站名会塌成一个）。
            located: List[Tuple[str, geo.Coord, Optional[float]]] = []
            for _, station_name, mileage in rows:
                coordinate = coordinates.find(station_name)
                if coordinate is None:
                    stats.missing_station_rows += 1
                    continue
                if located and located[-1][1] == coordinate:
                    stats.collided_pairs += 1
                    continue
                located.append((station_name, coordinate, mileage))
            stats.located_stations += len(located)

            profile = geo.infer_profile(route_name)
            for index in range(len(located) - 1):
                from_name, start, from_mileage = located[index]
                to_name, end, to_mileage = located[index + 1]
                mileage = _leg_mileage(from_mileage, to_mileage)
                suspect = geo.suspect_leg_reason(start, end, mileage)
                if suspect is not None:
                    stats.suspect_legs += 1
                stats.legs.append(
                    Leg(
                        route_name=route_name,
                        from_station=from_name,
                        to_station=to_name,
                        start=start,
                        end=end,
                        mileage_km=mileage,
                        profile=profile,
                        suspect_reason=suspect,
                    )
                )
    finally:
        connection.close()

    stats.legs_total = len(stats.legs)
    if limit is not None:
        stats.legs = stats.legs[:limit]
    return stats


# --------------------------------------------------------------------------
# 铁路数据取数
# --------------------------------------------------------------------------


@dataclass
class CachedWay:
    is_hsr: bool
    is_conventional: bool
    coords: List[geo.Coord]
    # OSM 的 way 名（`name`/`name:zh`），绝大多数中国铁路正线都带，且就是客里表里的
    # 线路名。只用于车站坐标消歧（见 disambiguate_stations），寻路本身不看它。
    name: Optional[str] = None

    def preferred_for(self, profile: str) -> bool:
        if profile == geo.HSR:
            return self.is_hsr
        if profile == geo.CONVENTIONAL:
            return self.is_conventional
        return self.is_hsr or self.is_conventional


def _tags_to_flags(tags: dict) -> Tuple[bool, bool]:
    """把 OSM 标签折算成 (是否高铁, 是否普速)，与 rail_track_geometry 的判定一致。"""
    return geo.way_flags(tags)


def _bbox_cache_key(bbox: Tuple[float, float, float, float]) -> str:
    quantized = [round(value / BBOX_QUANTUM) * BBOX_QUANTUM for value in bbox]
    return "%.2f_%.2f_%.2f_%.2f" % tuple(quantized)


def _quantized_bbox(bbox: Tuple[float, float, float, float]) -> Tuple[float, float, float, float]:
    return tuple(round(value / BBOX_QUANTUM) * BBOX_QUANTUM for value in bbox)  # type: ignore[return-value]


class RailSource:
    """按 bbox 取数，带磁盘缓存；返回该范围内的全部 railway=rail way。"""

    name = "unknown"

    def __init__(self, cache_dir: Path) -> None:
        self.cache_dir = cache_dir
        self.cache_dir.mkdir(parents=True, exist_ok=True)

    def ways(self, bbox: Tuple[float, float, float, float]) -> List[CachedWay]:
        bbox = _quantized_bbox(bbox)
        cache_path = self.cache_dir / self.name / f"{_bbox_cache_key(bbox)}.json.gz"
        if cache_path.exists():
            return _read_cache(cache_path)
        ways = self.fetch(bbox)
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        _write_cache(cache_path, ways)
        return ways

    def fetch(self, bbox: Tuple[float, float, float, float]) -> List[CachedWay]:
        raise NotImplementedError


def _read_cache(path: Path) -> List[CachedWay]:
    with gzip.open(path, "rt", encoding="utf-8") as handle:
        payload = json.load(handle)
    return [
        CachedWay(is_hsr=bool(flags & 1), is_conventional=bool(flags & 2), coords=[tuple(c) for c in coords])
        for flags, coords in payload
    ]


def _write_cache(path: Path, ways: List[CachedWay]) -> None:
    payload = [
        (
            (1 if way.is_hsr else 0) | (2 if way.is_conventional else 0),
            [[lat, lon] for lat, lon in way.coords],
        )
        for way in ways
    ]
    with gzip.open(path, "wt", encoding="utf-8") as handle:
        json.dump(payload, handle, separators=(",", ":"))


def _parse_overpass(payload: dict) -> List[CachedWay]:
    """解析 Overpass `out tags geom;` 的结果。"""
    ways: List[CachedWay] = []
    for element in payload.get("elements", []):
        if element.get("type") != "way":
            continue
        geometry = element.get("geometry") or []
        coords = [(point["lat"], point["lon"]) for point in geometry if "lat" in point]
        if len(coords) < 2:
            continue
        tags = element.get("tags") or {}
        is_hsr, is_conventional = _tags_to_flags(tags)
        if not (is_hsr or is_conventional) and not geo.is_service_rail(tags):
            continue  # 地铁/电车等非正线，直接丢掉
        ways.append(CachedWay(is_hsr, is_conventional, coords))
    return ways


def _parse_geojson(payload: dict) -> List[CachedWay]:
    """解析 osmium export 的 GeoJSON（坐标是 [lon, lat]）。"""
    ways: List[CachedWay] = []
    for feature in payload.get("features", []):
        properties = feature.get("properties") or {}
        if properties.get("railway") != "rail":
            continue
        is_hsr, is_conventional = _tags_to_flags(properties)
        if not (is_hsr or is_conventional) and not geo.is_service_rail(properties):
            continue
        geometry = feature.get("geometry") or {}
        if geometry.get("type") != "LineString":
            continue
        coords = [(lat, lon) for lon, lat in geometry.get("coordinates") or []]
        if len(coords) < 2:
            continue
        ways.append(CachedWay(is_hsr, is_conventional, coords))
    return ways


class OverpassRailSource(RailSource):
    """Overpass API。

    overpass-api.de 在负载高时会直接断开连接（表现为 SSL EOF），因此单个 bbox
    先做几次指数退避重试，仍失败再拆成四块分别重试；四块合并仍为空才认输。
    拆块后每块的查询更轻，通常能绕开超时。
    """

    name = "overpass"

    def __init__(
        self,
        cache_dir: Path,
        endpoints: Sequence[str] = OVERPASS_ENDPOINTS,
        retries: int = 3,
        backoff_sec: float = 4.0,
    ) -> None:
        super().__init__(cache_dir)
        self.endpoints = list(endpoints) or list(OVERPASS_ENDPOINTS)
        self.retries = max(1, retries)
        self.backoff_sec = backoff_sec

    def fetch(self, bbox: Tuple[float, float, float, float]) -> List[CachedWay]:
        ways, error = self._try_bbox(bbox)
        if ways is not None:
            return ways

        print(f"    Overpass 各端点均失败（{error}），拆分 bbox 重试", file=sys.stderr)
        south, west, north, east = bbox
        mid_lat = (south + north) / 2.0
        mid_lon = (west + east) / 2.0
        quadrants = [
            (south, west, mid_lat, mid_lon),
            (south, mid_lon, mid_lat, east),
            (mid_lat, west, north, mid_lon),
            (mid_lat, mid_lon, north, east),
        ]
        merged: List[CachedWay] = []
        errors: List[str] = []
        for quadrant in quadrants:
            part, quadrant_error = self._try_bbox(quadrant)
            if part is None:
                errors.append(str(quadrant_error))
            else:
                merged.extend(part)
        if errors and not merged:
            raise RuntimeError("; ".join(errors[:2]))
        return merged

    def _try_bbox(
        self, bbox: Tuple[float, float, float, float]
    ) -> Tuple[Optional[List[CachedWay]], Optional[Exception]]:
        """把每个端点都试过；全部失败返回 (None, 最后一个错误)。

        返回空列表是合法的成功——那表示这个范围内确实没有铁路。
        """
        last_error: Optional[Exception] = None
        for attempt in range(self.retries):
            for endpoint in self.endpoints:
                try:
                    return self._query(endpoint, bbox), None
                except Exception as exc:
                    last_error = exc
                    print(f"    {endpoint} 失败：{str(exc)[:60]}", file=sys.stderr)
            if attempt + 1 < self.retries:
                time.sleep(self.backoff_sec * (2**attempt))
        return None, last_error

    def _query(
        self, endpoint: str, bbox: Tuple[float, float, float, float]
    ) -> List[CachedWay]:
        south, west, north, east = bbox
        query = (
            "[out:json][timeout:180];"
            f'way["railway"="rail"]({south:.4f},{west:.4f},{north:.4f},{east:.4f});'
            "out tags geom;"
        )
        data = urllib.parse.urlencode({"data": query}).encode()
        request = urllib.request.Request(
            endpoint,
            data=data,
            headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
        )
        with urllib.request.urlopen(request, timeout=240) as response:
            payload = json.loads(response.read().decode("utf-8"))
        return _parse_overpass(payload)


# 网格边长（度）。0.1° 约 11km，走廊 bbox 通常只跨几个格子；取大些省内存、
# 取小些每格 way 更少，0.1° 是实测的折中。
GRID_DEG = 0.1


class WayGrid:
    """把 way 按固定网格登记，供按 bbox 快速取数。

    单段走廊只有十几公里，逐段全表扫描（419k way × 5767 段）不可行；按 0.1°
    建格后，一段只碰几个格子里的几百条 way。
    """

    def __init__(self, grid_deg: float = GRID_DEG) -> None:
        self.grid_deg = grid_deg
        self.ways: List[CachedWay] = []
        self._bboxes: List[Tuple[float, float, float, float]] = []
        self._cells: Dict[Tuple[int, int], List[int]] = {}

    def add(self, way: CachedWay) -> None:
        index = len(self.ways)
        self.ways.append(way)
        latitudes = [point[0] for point in way.coords]
        longitudes = [point[1] for point in way.coords]
        bbox = (min(latitudes), min(longitudes), max(latitudes), max(longitudes))
        self._bboxes.append(bbox)
        for cell in self.cells_for_bbox(bbox):
            self._cells.setdefault(cell, []).append(index)

    def cells_for_bbox(
        self, bbox: Tuple[float, float, float, float]
    ) -> List[Tuple[int, int]]:
        size = self.grid_deg
        south, west, north, east = bbox
        return [
            (lat, lon)
            for lat in range(math.floor(south / size), math.floor(north / size) + 1)
            for lon in range(math.floor(west / size), math.floor(east / size) + 1)
        ]

    def find(self, bbox: Tuple[float, float, float, float]) -> List[CachedWay]:
        south, west, north, east = bbox
        seen: set[int] = set()
        found: List[CachedWay] = []
        for cell in self.cells_for_bbox(bbox):
            for index in self._cells.get(cell, ()):
                if index in seen:
                    continue
                seen.add(index)
                way_bbox = self._bboxes[index]
                # 格子只是粗筛，再按 way 的真实 bbox 相交细筛；走廊过滤交给下游。
                if (
                    way_bbox[0] <= north
                    and way_bbox[2] >= south
                    and way_bbox[1] <= east
                    and way_bbox[3] >= west
                ):
                    found.append(self.ways[index])
        return found

    def __len__(self) -> int:
        return len(self.ways)


class PbfRailSource(RailSource):
    """本地 china.osm.pbf：pyosmium 两遍扫描 + 网格索引。

    不用 osmium CLI（pip 只装得到 pyosmium，没有命令行工具），也不走基类的
    逐 bbox 磁盘缓存——整网读进内存后，每段取数只是按网格取下标，5767 段全部
    在本地内存完成，没有任何网络往返（Overpass 逐段取数实测 0.8 段/分钟，不可用）。

    **两遍，且两遍都在 C++ 侧预过滤**。这是整条管线最耗时的一步，关键约束是
    「Python 回调次数」而不是「扫描的字节数」：

    * 一遍 locations=True 不行：那要 pyosmium 给全国数亿个节点建位置索引，而铁路
      way 只引用其中约 160 万个；实测建索引时 CPU 几乎不动（40 秒才 6 秒 CPU）、
      内存一路涨，而且 Windows wheel 根本没编进省内存的 sparse_mem。
    * 不带过滤器地扫节点更不行：那意味着数亿次 Python 回调（实测 496 秒），而全
      进程只占 1 个核——总 CPU 利用率因此常年只有个位数。

    所以给每一遍都挂上 C++ 过滤器，把交给 Python 的对象数压到与铁路数据同量级：

      第一遍 KeyFilter('railway')  —— 只放行 railway=* 的对象（约 50 万个）：
                                      收 way 的节点号序列 + 车站节点坐标；
      第二遍 IdFilter(要用的节点号) —— 只放行 160 万个待解析节点，取它们的坐标。

    两遍都是顺序扫描，内存只与铁路数据量成正比（实测 ~300MB 量级）。
    """

    name = "pbf"

    def __init__(
        self,
        cache_dir: Path,
        pbf_path: Path,
        grid_deg: float = GRID_DEG,
        stations_context: Optional[Tuple[Path, Path]] = None,
    ) -> None:
        super().__init__(cache_dir)
        if not pbf_path.exists():
            raise RuntimeError(f"找不到 PBF 文件：{pbf_path}")
        self.pbf_path = pbf_path
        self.grid = WayGrid(grid_deg)
        self._stations: Dict[str, Tuple[str, float, float]] = {}
        self._station_candidates: Dict[str, List[Tuple[str, float, float]]] = {}
        self._verified: Dict[str, Tuple[str, float, float]] = {}
        self._fixes: List[StationFix] = []
        # (routes.db, coordinates.csv)：有这两份才能按线路消歧车站坐标；缺省不消歧，
        # 退回「CSV 基线 + OSM first-wins」的老行为（单测里的小 PBF 就不需要它们）。
        self._stations_context = stations_context
        self._load()

    def _collect_ways(self, wanted: set) -> List[Tuple[bool, bool, List[int], Optional[str]]]:
        """第一遍：留下铁路 way 的 (高铁?, 普速?, 节点号序列, 线路名)，并把节点号收进 wanted。

        顺带收 railway=station/halt 的节点坐标——车站节点也带 railway 标签，正好
        被同一个 KeyFilter 放行，不必为此多扫一遍 PBF。
        """
        import osmium

        collected: List[Tuple[bool, bool, List[int], Optional[str]]] = []
        source = self

        class WayCollector(osmium.SimpleHandler):
            def way(self, w: osmium.osm.Way) -> None:
                # 两者皆假有两种可能：真正的站场/侧线，或者根本不是正线（地铁、电车）。
                # 前者要留着当连接线（见 geo.is_service_rail），后者才丢。
                is_hsr, is_conventional = geo.way_flags(w.tags)
                if not (is_hsr or is_conventional):
                    if not geo.is_service_rail(w.tags):
                        return
                node_ids = [node.ref for node in w.nodes]
                if len(node_ids) < 2:
                    return
                wanted.update(node_ids)
                collected.append(
                    (is_hsr, is_conventional, node_ids, geo.way_name(w.tags))
                )

            def node(self, n: osmium.osm.Node) -> None:
                if n.tags.get("railway") not in ("station", "halt"):
                    return
                location = n.location
                if location.valid():
                    source._add_station(n.tags, location.lat, location.lon)

        WayCollector().apply_file(
            str(self.pbf_path),
            locations=False,
            filters=[osmium.filter.KeyFilter("railway")],
        )
        return collected

    def _resolve_locations(self, wanted: set) -> Dict[int, Tuple[float, float]]:
        """第二遍：只放行要用的节点号，取它们的坐标。

        过滤掉无关节点后就不需要 locations=True —— 节点自身的坐标总是可读的，
        位置索引只在「从 way 反查节点」时才用得着。
        """
        import osmium

        locations: Dict[int, Tuple[float, float]] = {}

        class NodeCollector(osmium.SimpleHandler):
            def node(self, n: osmium.osm.Node) -> None:
                location = n.location
                if location.valid():
                    locations[n.id] = (location.lat, location.lon)

        NodeCollector().apply_file(
            str(self.pbf_path),
            locations=False,
            filters=[osmium.filter.IdFilter(wanted)],
        )
        return locations

    def _load(self) -> None:
        import osmium  # 延迟导入：不用 --source pbf 时不强制依赖 pyosmium

        started = time.time()
        wanted: set = set()
        raw_ways = self._collect_ways(wanted)
        first_pass = time.time()

        locations = self._resolve_locations(wanted)
        second_pass = time.time()
        # 三份大结构（way 的节点号序列、待解析节点集合、解析出的坐标）加起来上 GB，
        # 这里每样用完就放：16 个 worker 同时加载时，峰值是它们相加还是取最大，
        # 决定了这台机器能不能跑满。
        node_refs = len(wanted)
        del wanted

        # 按下标走、用完就把槽位置空（不是 pop：顺序变了会影响路径的择优结果）。
        for index in range(len(raw_ways)):
            is_hsr, is_conventional, node_ids, way_name = raw_ways[index]
            raw_ways[index] = None
            coords = [locations[node_id] for node_id in node_ids if node_id in locations]
            if len(coords) >= 2:
                self.grid.add(CachedWay(is_hsr, is_conventional, coords, way_name))
        del raw_ways, locations  # 两份坐标表都不能逐条 pop：相邻 way 共用接轨节点

        resolved_at = time.time()
        self._resolve_stations()
        save_osm_stations(
            self.cache_dir, self._stations, self._verified, self._fixes
        )
        print(
            f"  PBF 读入       : {len(self.grid)} 条 way、{node_refs} 个节点引用、"
            f"{len(self._stations)} 个车站键"
            f"（第一遍 {first_pass - started:.0f}s、第二遍 {second_pass - first_pass:.0f}s"
            + (
                f"、坐标消歧 {time.time() - resolved_at:.0f}s"
                if self._stations_context
                else ""
            )
            + "）",
            file=sys.stderr,
        )

    def _resolve_stations(self) -> None:
        """按线路几何消歧同名车站，结果进 [verified_stations]；不消歧时是空操作。"""
        if not self._stations_context:
            return
        routes_db, coordinates_path = self._stations_context
        candidates: Dict[str, List[Tuple[str, float, float]]] = {
            key: list(values) for key, values in self._station_candidates.items()
        }
        for name, latitude, longitude in _csv_candidates(coordinates_path):
            for key in _station_keys(name):
                bucket = candidates.setdefault(key, [])
                if not any(
                    abs(latitude - item[1]) < 1e-6 and abs(longitude - item[2]) < 1e-6
                    for item in bucket
                ):
                    bucket.append((name, latitude, longitude))
        # 报告里的「旧值」要和改动前真正写进库的一致，也就是套着 30km 守卫的那一份。
        current = StationCoordinateIndex.from_sources(self._stations, coordinates_path)
        fallback = {
            key: coordinate
            for key in candidates
            if (coordinate := current.get(key)) is not None
        }
        self._verified, self._fixes = disambiguate_stations(
            self.grid,
            candidates,
            routes_station_names(routes_db),
            fallback,
        )

    def verified_stations(self) -> Dict[str, Tuple[str, float, float]]:
        """经线路消歧确认的车站坐标（优先级高于 coordinates.csv）。"""
        return self._verified

    def station_fixes(self) -> List[StationFix]:
        """本进程做过的坐标修正，供日志展示。"""
        return self._fixes

    def _add_station(self, tags: object, latitude: float, longitude: float) -> None:
        """登记一个车站节点的全部别名与坐标。

        同一个站名在全国有几十个同名节点，这里**全部留下**（去重按坐标），
        由 [disambiguate_stations] 用线路几何挑出对的那个；`_stations` 只保留
        先扫到的那个，供没有线路上下文时兜底（也就是改动前的行为）。

        每个别名都登记：`name` 是英文而 `name:zh` 是中文时，客里表用的是中文，
        只留第一个会把这条站彻底查不到。
        """
        for alias in (
            tags.get("name"),
            tags.get("name:zh"),
            tags.get("alt_name"),
            tags.get("old_name"),
        ):
            if not alias:
                continue
            for key in _station_keys(alias):
                candidates = self._station_candidates.setdefault(key, [])
                if not any(
                    abs(latitude - item[1]) < 1e-6 and abs(longitude - item[2]) < 1e-6
                    for item in candidates
                ):
                    candidates.append((alias, latitude, longitude))
                self._stations.setdefault(key, (alias, latitude, longitude))

    def station_coordinates(self) -> Dict[str, Tuple[str, float, float]]:
        """归一化站名 → (原始站名, 纬度, 经度)。"""
        return self._stations

    def station_candidates(self) -> Dict[str, List[Tuple[str, float, float]]]:
        """归一化站名 → 全部同名候选坐标（含别名去重）。"""
        return self._station_candidates

    def ways(self, bbox: Tuple[float, float, float, float]) -> List[CachedWay]:
        """返回与 bbox 相交的 way；内存网格索引，不走基类的磁盘缓存。"""
        return self.grid.find(bbox)


def _osm_stations_path(cache_dir: Path) -> Path:
    return cache_dir / PbfRailSource.name / OSM_STATIONS_CACHE


def _station_fixes_path(cache_dir: Path) -> Path:
    return cache_dir / PbfRailSource.name / OSM_STATION_FIXES_CACHE


@dataclass
class OsmStationSet:
    """从 PBF 抽出的车站坐标。

    * [stations]：按站名 first-wins 的兜底表，用法与改动前一致（受 30km 守卫约束）；
    * [verified]：经线路消歧确认过的坐标，优先级高于 coordinates.csv。

    分两份是因为两者的可信度不同：verified 是「离本线路的 way 几百米」这个几何
    事实断定的，stations 只是「扫到第一个同名节点」。
    """

    stations: Dict[str, Tuple[str, float, float]] = field(default_factory=dict)
    verified: Dict[str, Tuple[str, float, float]] = field(default_factory=dict)

    def __bool__(self) -> bool:
        return bool(self.stations or self.verified)

    def __len__(self) -> int:
        return len(self.stations)


def _write_json_atomic(path: Path, payload: object) -> None:
    """先写同目录临时文件再原子替换。

    PBF 路径下 16 个 worker 会各自写一遍同一份缓存，直接写同一个路径有读到半截
    文件的风险；内容本来就完全一致，谁最后落地都一样。
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f"{path.name}.{os.getpid()}.tmp")
    temporary.write_text(
        json.dumps(payload, ensure_ascii=False), encoding="utf-8"
    )
    os.replace(temporary, path)


def save_osm_stations(
    cache_dir: Path,
    stations: Mapping[str, Tuple[str, float, float]],
    verified: Optional[Mapping[str, Tuple[str, float, float]]] = None,
    fixes: Sequence[StationFix] = (),
) -> None:
    """写车站坐标缓存，第 4 位标记该坐标是否经线路消歧验证过。

    同时写一份修正清单：消歧要读 PBF 才能算，而之后的运行都吃缓存、不读 PBF，
    清单不落盘就再也看不到了——这份清单正是「改了哪些站」唯一可核对的地方。
    """
    verified_keys = set(verified or {})
    payload = {
        key: [value[0], value[1], value[2], key in verified_keys]
        for key, value in stations.items()
    }
    for key, value in (verified or {}).items():
        payload[key] = [value[0], value[1], value[2], True]
    _write_json_atomic(_osm_stations_path(cache_dir), payload)

    if fixes:
        _write_json_atomic(
            _station_fixes_path(cache_dir),
            [
                [fix.name, *fix.old, *fix.new, fix.line, fix.distance_km, fix.moved_km]
                for fix in fixes
            ],
        )


def load_station_fixes(cache_dir: Path) -> List[StationFix]:
    """读坐标修正清单；没有或读不动就返回空。"""
    path = _station_fixes_path(cache_dir)
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        return [
            StationFix(
                name=str(row[0]),
                old=(float(row[1]), float(row[2])),
                new=(float(row[3]), float(row[4])),
                line=str(row[5]),
                distance_km=float(row[6]),
                moved_km=float(row[7]),
            )
            for row in payload
        ]
    except (OSError, ValueError, TypeError, KeyError, IndexError):
        return []


def load_osm_stations(cache_dir: Path) -> Optional[OsmStationSet]:
    """读车站坐标缓存；没有或读不动就返回 None（调用方回退到只用 CSV）。

    这样「只看计划」不必为了车站坐标先读一遍 1.7GB 的 PBF。损坏的缓存一律当
    没有——重扫 PBF 的代价是几十秒到几分钟，不该让一个截断的 JSON 把整条管线打断。

    旧缓存（改动前写的）只有三元组、没有验证标记，一律当未验证：那些坐标是
    first-wins 的，本来就该继续受 30km 守卫约束。想要消歧过的坐标得让管线带着
    `stations_context` 重读一次 PBF。
    """
    path = _osm_stations_path(cache_dir)
    if not path.exists():
        return None
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(payload, dict):
            return None
        result = OsmStationSet()
        for key, value in payload.items():
            entry = (str(value[0]), float(value[1]), float(value[2]))
            if len(value) > 3 and value[3]:
                result.verified[key] = entry
            else:
                result.stations[key] = entry
        return result
    except (OSError, ValueError, TypeError, KeyError, IndexError):
        return None


# --------------------------------------------------------------------------
# 车站坐标消歧：用线路几何在全部同名候选里挑对的那个
# --------------------------------------------------------------------------


@dataclass
class StationFix:
    """一次坐标修正，供日志/报告展示。"""

    name: str
    old: geo.Coord
    new: geo.Coord
    line: str
    distance_km: float  # 新坐标离该线路的 way 的距离
    moved_km: float     # 相对旧坐标挪了多远


def routes_station_names(routes_db: Path) -> Dict[str, List[str]]:
    """线路名 → 站名序列（按 station_index）。与 enumerate_legs 挑版本的方式一致。"""
    connection = sqlite3.connect(f"file:{routes_db}?mode=ro", uri=True)
    try:
        result: Dict[str, List[str]] = {}
        for route_name, version_id in _pick_route_versions(connection):
            rows = connection.execute(
                """
                SELECT station_name FROM stations
                WHERE route_version_id = ? ORDER BY station_index
                """,
                (version_id,),
            ).fetchall()
            result[route_name] = [row[0] for row in rows]
        return result
    finally:
        connection.close()


def _csv_candidates(path: Path) -> List[Tuple[str, float, float]]:
    """coordinates.csv 的全部行，作为同名候选取集的一部分。"""
    rows: List[Tuple[str, float, float]] = []
    for line in path.read_text(encoding="utf-8-sig").splitlines()[1:]:
        row = _parse_csv_row(line)
        if row is not None:
            rows.append(row)
    return rows


class LineWayLookup:
    """「某个坐标离某条线路的 way 有多近」。

    车站节点在 OSM 里通常是轨道旁的独立点（不在 way 的节点序列里），所以判断
    「这个候选是不是在这条线上」只能按空间距离查。同名站会出现在多条线上，同一
    个坐标会被反复查，因此按坐标（毫米级取整）缓存 way 列表。

    线路名比对用 [geo.route_key]，与折线主键、profile 判定同一套归一化。
    """

    def __init__(self, grid: "WayGrid", radius_km: float) -> None:
        self._grid = grid
        self._radius_km = radius_km
        self._ways: Dict[Tuple[float, float], List[CachedWay]] = {}
        self._distances: Dict[Tuple[float, float, str], float] = {}

    def _ways_near(self, coordinate: geo.Coord) -> List[CachedWay]:
        key = (round(coordinate[0], 3), round(coordinate[1], 3))
        cached = self._ways.get(key)
        if cached is None:
            cached = self._grid.find(
                geo.bbox_for_corridor(coordinate, coordinate, self._radius_km)
            )
            self._ways[key] = cached
        return cached

    def distance_to_line(self, coordinate: geo.Coord, line_key: str) -> float:
        """候选坐标到该线路 way 的最短距离；半径内没有该线路的 way 时为 inf。"""
        key = (round(coordinate[0], 3), round(coordinate[1], 3), line_key)
        cached = self._distances.get(key)
        if cached is not None:
            return cached
        best = float("inf")
        for way in self._ways_near(coordinate):
            if not way.name or geo.route_key(way.name) != line_key:
                continue
            distance = geo.path_distance_km(coordinate, way.coords)
            if distance < best:
                best = distance
        # way 的 bbox 与搜索框相交、但几何仍可能在半径外，这种不算「在这条线上」。
        if best > self._radius_km:
            best = float("inf")
        self._distances[key] = best
        return best


def disambiguate_stations(
    grid: "WayGrid",
    candidates: Mapping[str, Sequence[Tuple[str, float, float]]],
    line_stations: Mapping[str, Sequence[str]],
    fallback: Mapping[str, geo.Coord],
    radius_km: float = LINE_SNAP_RADIUS_KM,
) -> Tuple[Dict[str, Tuple[str, float, float]], List[StationFix]]:
    """在全部同名候选里，挑「离它所在线路最近」的那个坐标。

    这是坐标解析的仲裁者：coordinates.csv（维基数据按站名取坐标）和 OSM 的车站
    节点（同名 first-wins）都会把通用站名匹配到外省，谁都不能单独当真。但两者
    都不对时，「正确的新立屯必然紧邻名为新义线的 way」这条约束仍然成立——它来自
    轨道几何本身，与那两份文件无关。

    只处理**有两个以上候选**且**知道它属于哪些线路**的站名：单候选没有什么可挑，
    没有线路上下文的站无从判断（留给 [StationCoordinateIndex.from_sources] 的
    30km 守卫兜底）。所有线路里最近的距离仍超过 [radius_km] 时不硬挪，保持原值。

    返回 (被修正的键 → 坐标, 修正清单)。未列出的键沿用原值。
    """
    lines_by_station: Dict[str, List[str]] = {}
    for route_name, names in line_stations.items():
        for name in names:
            for key in _station_keys(name):
                lines = lines_by_station.setdefault(key, [])
                if route_name not in lines:
                    lines.append(route_name)

    lookup = LineWayLookup(grid, radius_km)
    resolved: Dict[str, Tuple[str, float, float]] = {}
    fixes: List[StationFix] = []

    for key, options in candidates.items():
        if len(options) < 2:
            continue
        lines = lines_by_station.get(key)
        if not lines:
            continue
        best: Optional[Tuple[str, float, float]] = None
        best_line = ""
        best_distance = float("inf")
        for alias, latitude, longitude in options:
            coordinate = (latitude, longitude)
            for route_name in lines:
                distance = lookup.distance_to_line(coordinate, geo.route_key(route_name))
                if distance < best_distance:
                    best, best_line, best_distance = (
                        (alias, latitude, longitude),
                        route_name,
                        distance,
                    )
        if best is None or best_distance == float("inf"):
            continue

        resolved[key] = best
        current = fallback.get(key)
        if current is None or geo.haversine_km(current, (best[1], best[2])) > 1e-6:
            fixes.append(
                StationFix(
                    name=best[0],
                    old=current or (float("nan"), float("nan")),
                    new=(best[1], best[2]),
                    line=best_line,
                    distance_km=best_distance,
                    moved_km=(
                        geo.haversine_km(current, (best[1], best[2])) if current else 0.0
                    ),
                )
            )
    return resolved, fixes


def print_station_fixes(fixes: Sequence[StationFix], limit: int = 20) -> None:
    """打印坐标修正清单：这类改动直接影响画出来的位置，必须可核对。"""
    if not fixes:
        return
    print(f"  坐标消歧     : 修正 {len(fixes)} 个站的坐标（按线路就近）")
    for fix in sorted(fixes, key=lambda item: -item.moved_km)[:limit]:
        print(
            f"      {fix.name:10} {fix.old[0]:.4f},{fix.old[1]:.4f}"
            f" → {fix.new[0]:.4f},{fix.new[1]:.4f}"
            f"（挪 {fix.moved_km:.0f}km，离 {fix.line} {fix.distance_km * 1000:.0f}m）"
        )
    if len(fixes) > limit:
        print(f"      …另有 {len(fixes) - limit} 个")


def discard_implausible_station_coordinates(
    index: StationCoordinateIndex, routes_db: Path
) -> List[Tuple[str, str, str]]:
    """舍去「与前后站距离对不上里程」的车站坐标，返回 (站名, 前站, 后站)。

    这是坐标消歧之外的**第二道独立裁判**。消歧靠「正确的站必然紧邻本线路的 way」，
    对「CSV 和 OSM 都挑了同名异地、而正确位置没有 OSM 节点可吸附」的站无能为力
    （永乐在南昆线，两源却都指向北京永乐店）。但这些站还有一个与两份坐标文件都
    无关的约束：routes.db 的逐站里程桩。铁路里程恒不短于直线距离，所以坐标飞到
    外省的站，它与前后站的直线距离会远大于里程桩之差——[geo.suspect_leg_reason]
    就是这个判据，只不过 [enumerate_legs] 只拿它标记那条腿失败，从不修正坐标。

    这里把它上移到坐标生成之后、枚举之前：逐线走站序，对每个**中间站**，若它到
    前站、到后站两段都被判异常，那它就是两段异常的共同原因——舍去它的坐标。

    不走 [enumerate_legs] 之后再删，是因为那样只能删掉整条腿；舍去坐标则让前后两
    站桥接成一条里程正确的长段，代价只有中间那一个站（本来也是错的位置）不显示。

    端点站只有一个邻居，异常可能是邻居错、也可能是自己错，分不清，不动——留给
    现有的 leg 级 suspect 标记。
    """
    discarded: List[Tuple[str, str, str]] = []
    seen: set = set()
    connection = sqlite3.connect(f"file:{routes_db}?mode=ro", uri=True)
    try:
        for _route_name, version_id in _pick_route_versions(connection):
            rows = connection.execute(
                """
                SELECT station_index, station_name, mileage
                FROM stations WHERE route_version_id = ?
                ORDER BY station_index
                """,
                (version_id,),
            ).fetchall()

            # 与 enumerate_legs 完全一致的取站方式：跳过无坐标站、合并相邻同坐标站。
            located: List[Tuple[str, geo.Coord, Optional[float]]] = []
            for _station_index, station_name, mileage in rows:
                coordinate = index.find(station_name)
                if coordinate is None:
                    continue
                if located and located[-1][1] == coordinate:
                    continue
                located.append((station_name, coordinate, mileage))

            for position in range(1, len(located) - 1):
                prev_name, prev_coord, prev_mileage = located[position - 1]
                name, coord, mileage = located[position]
                next_name, next_coord, next_mileage = located[position + 1]
                # 按归一化键去重：同一条线写「新立屯」、另一条写「新立屯站」时，
                # find 认作同一个站，这里也只该报一次（remove 本来就两种情况都删）。
                keys = _station_keys(name)
                if not keys or keys[-1] in seen:
                    continue
                if (
                    geo.suspect_leg_reason(
                        prev_coord, coord, _leg_mileage(prev_mileage, mileage)
                    )
                    is None
                ):
                    continue
                if (
                    geo.suspect_leg_reason(
                        coord, next_coord, _leg_mileage(mileage, next_mileage)
                    )
                    is None
                ):
                    continue
                seen.add(keys[-1])
                discarded.append((name, prev_name, next_name))
    finally:
        connection.close()

    # 先收集、后删除：遍历期间还要用这些坐标判断别的站。
    for name, _prev_name, _next_name in discarded:
        index.remove(name)
    return discarded


def print_discarded_stations(
    discarded: Sequence[Tuple[str, str, str]], limit: int = 20
) -> None:
    """打印被舍去的车站坐标：这类改动会让站点从地图上消失，必须可核对。"""
    if not discarded:
        return
    print(f"  坐标舍去     : {len(discarded)} 个站（与前后站的里程都对不上，前后桥接）")
    for name, prev_name, next_name in discarded[:limit]:
        print(f"      {name:10} 夹在 {prev_name} 与 {next_name} 之间")
    if len(discarded) > limit:
        print(f"      …另有 {len(discarded) - limit} 个")


def rail_data_for_leg(source: RailSource, leg: Leg) -> geo.RailData:
    # 只取走廊范围内的数据：plan_leg 里的 corridor_filter 会丢掉走廊外的一切，
    # 所以 bbox 按走廊宽度收紧既不影响结果，又能大幅减少取数量。
    corridor_km = geo.corridor_km_for(leg.start, leg.end)
    bbox = geo.bbox_for_corridor(leg.start, leg.end, corridor_km)
    ways = source.ways(bbox)
    lines = [way.coords for way in ways]
    preferred = [way.preferred_for(leg.profile) for way in ways]
    return geo.RailData(lines=lines, preferred=preferred)


# --------------------------------------------------------------------------
# 逐段规划
# --------------------------------------------------------------------------


@dataclass
class LegResult:
    leg: Leg
    plan: geo.LegPlan


def plan_leg_with_source(
    source: RailSource,
    leg: Leg,
    step_m: float,
    max_error_ratio: float,
    detour_ratio: float = geo.DEFAULT_DETOUR_RATIO,
) -> LegResult:
    # 坐标不可信的段在枚举阶段就定好了：取数毫无意义（走廊会覆盖半个国家），直接记失败。
    if leg.suspect_reason is not None:
        return LegResult(leg, geo.LegPlan(ok=False, reason=leg.suspect_reason))
    try:
        rail = rail_data_for_leg(source, leg)
    except Exception as exc:
        return LegResult(leg, geo.LegPlan(ok=False, reason=f"fetch_failed: {exc}"))
    plan = geo.plan_leg(
        leg.start,
        leg.end,
        rail,
        leg.profile,
        mileage_km=leg.mileage_km,
        step_m=step_m,
        max_error_ratio=max_error_ratio,
        detour_ratio=detour_ratio,
    )
    return LegResult(leg, plan)


# --------------------------------------------------------------------------
# 多进程逐段规划
# --------------------------------------------------------------------------
#
# 逐段规划是纯 Python 的 CPU 活（ corridor 过滤 + 构图 + Yen k-最短路），线程池拿不
# 到加速——GIL 挡着。所以用进程池，每个 worker 自己读一份 PBF。
#
# Windows 只有 spawn，子进程不继承父进程的内存，`PbfRailSource` 那个几百 MB 的网格
# 也就不可能传过去（也不可 pickle）。办法是 initializer：每个 worker 进程启动时各读
# 一遍 PBF，之后一直复用它处理分到的所有段。读一遍约 25s，16 个进程并行读，换来的是
# 整轮规划真正的 16 路并行。
#
# 代价是内存：每进程稳定后约 0.6GB（那座网格），但读 PBF 的那 20 来秒里，way 的节点号
# 序列、待解析节点集合、解析出的坐标会同时在手——实测单进程瞬时私有内存到过 2.4GB。
# 而 16 个 worker 是同时启动、同时开始读的，于是峰值不取决于 `--workers` 乘 0.6，
# 而取决于乘 2.4，这台 32GB 的机器根本吃不下。
#
# 所以加载阶段用一个跨进程信号量排队：同时在读的进程数按可用内存算（见
# `_load_slot_count`），其余的等前面读完再读。读完之后大家都只占那 0.6GB，
# 规划阶段照样是 `--workers` 路并行。

# 单个 worker 加载时的瞬时私有内存与稳定后的占用（实测值，用来估算能同时读几个）。
WORKER_LOAD_PEAK_GB = 2.6
WORKER_STEADY_GB = 0.6
# 留给别的程序的内存比例：可用内存的 70% 才拿来给 worker 加载。
LOAD_MEMORY_BUDGET_RATIO = 0.7

_WORKER_SOURCE: Optional[RailSource] = None
_WORKER_OPTIONS: Tuple[float, float, float] = (
    400.0,
    0.35,
    geo.DEFAULT_DETOUR_RATIO,
)


def _available_ram_bytes() -> Optional[int]:
    """物理内存可用量；拿不到（非 Windows、API 不可用）返回 None。"""
    try:
        import ctypes

        class _Status(ctypes.Structure):
            _fields_ = [
                ("dwLength", ctypes.c_ulong),
                ("dwMemoryLoad", ctypes.c_ulong),
                ("ullTotalPhys", ctypes.c_ulonglong),
                ("ullAvailPhys", ctypes.c_ulonglong),
                ("ullTotalPageFile", ctypes.c_ulonglong),
                ("ullAvailPageFile", ctypes.c_ulonglong),
                ("ullTotalVirtual", ctypes.c_ulonglong),
                ("ullAvailVirtual", ctypes.c_ulonglong),
                ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
            ]

        status = _Status()
        status.dwLength = ctypes.sizeof(_Status)
        if not ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
            return None
        return int(status.ullAvailPhys)
    except (AttributeError, OSError):
        return None


def _load_slot_count(workers: int, available_bytes: Optional[int]) -> int:
    """允许多少个 worker 同时读 PBF。"""
    if workers <= 1 or not available_bytes:
        return workers
    budget_gb = available_bytes / 2**30 * LOAD_MEMORY_BUDGET_RATIO
    # 每个已经读完的 worker 还要留 0.6GB 常驻：先按满员扣掉，剩下的才够加载用。
    for slots in range(workers, 0, -1):
        if slots * WORKER_LOAD_PEAK_GB + (workers - slots) * WORKER_STEADY_GB <= budget_gb:
            return slots
    return 1


def _init_worker(
    source_kind: str,
    cache_dir: str,
    pbf: Optional[str],
    endpoints: Sequence[str],
    step_m: float,
    max_error_ratio: float,
    detour_ratio: float,
    load_slots: Optional[object] = None,
    stations_context: Optional[Tuple[str, str]] = None,
) -> None:
    """worker 进程启动时建好自己的数据源（每个进程一次）。"""
    global _WORKER_SOURCE, _WORKER_OPTIONS
    # spawn 出来的进程没有父进程那份 UTF-8 包装，不补一下的话 worker 的进度行会按
    # 系统默认编码写进同一份日志，和父进程的输出混成乱码。
    _utf8_stdout()
    if load_slots is not None:
        load_slots.acquire()
    try:
        if source_kind == "pbf":
            _WORKER_SOURCE = PbfRailSource(
                Path(cache_dir),
                Path(pbf) if pbf else DEFAULT_PBF,
                stations_context=(
                    (Path(stations_context[0]), Path(stations_context[1]))
                    if stations_context
                    else None
                ),
            )
        else:
            _WORKER_SOURCE = OverpassRailSource(Path(cache_dir), list(endpoints))
    finally:
        if load_slots is not None:
            load_slots.release()
    _WORKER_OPTIONS = (step_m, max_error_ratio, detour_ratio)


def _plan_leg_in_worker(leg: Leg) -> LegResult:
    source = _WORKER_SOURCE
    if source is None:  # initializer 没跑成，说明进程池配置有问题
        return LegResult(leg, geo.LegPlan(ok=False, reason="worker_not_initialized"))
    step_m, max_error_ratio, detour_ratio = _WORKER_OPTIONS
    return plan_leg_with_source(source, leg, step_m, max_error_ratio, detour_ratio)


def _worker_initializer_args(args: argparse.Namespace, load_slots: object = None) -> Tuple:
    context = stations_context_of(args) if args.source == "pbf" else None
    return (
        args.source,
        str(args.cache_dir),
        str(args.pbf) if args.pbf else None,
        tuple(args.overpass_endpoints or OVERPASS_ENDPOINTS),
        args.step_m,
        args.max_error_ratio,
        args.detour_ratio,
        load_slots,
        (str(context[0]), str(context[1])) if context else None,
    )


def _progress(results: Iterable[LegResult], total: int) -> Iterator[LegResult]:
    """原样转发结果，顺便每 25 段报一次进度（父进程里跑，不占 worker）。"""
    done = 0
    kept = 0
    for result in results:
        done += 1
        kept += 1 if result.plan.ok else 0
        if done % 25 == 0 or done == total:
            print(f"  [{done}/{total}] 成功 {kept}", flush=True)
        yield result


# --------------------------------------------------------------------------
# 写库
# --------------------------------------------------------------------------

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE tracks (
  route_name      TEXT NOT NULL,
  from_station    TEXT NOT NULL,
  to_station      TEXT NOT NULL,
  profile         TEXT NOT NULL,
  -- 上下行分离：'' 表示该区间在 OSM 里只有一条线（或两条贴在一起画成一条）；
  -- 'up'/'down' 表示上下行画成了两条明显分开的轨道，这两行各是其中一条，
  -- 按左行规则沿 from→to 走向更靠左的那条为 'up'。App 端据此分画两条。
  direction       TEXT NOT NULL DEFAULT '',
  polyline        BLOB NOT NULL,   -- gzip(JSON([[lat,lon], ...]))，WGS84
  point_count     INTEGER NOT NULL,
  length_km       REAL NOT NULL,
  mileage_km      REAL,
  mileage_error_km REAL,
  PRIMARY KEY (route_name, from_station, to_station, direction)
);
CREATE TABLE failures (
  route_name    TEXT NOT NULL,
  from_station  TEXT NOT NULL,
  to_station    TEXT NOT NULL,
  reason        TEXT NOT NULL,
  length_km     REAL,
  mileage_km    REAL,
  mileage_error_ratio REAL,
  PRIMARY KEY (route_name, from_station, to_station)
);
-- 管线解析出的站坐标（OSM 为主、CSV 兜底）。App 优先用它标站，才能保证
-- 标记位置与折线端点一致——coordinates.csv 有 36 段同名异地错配。
--
-- 坐标为 NULL 表示「这个站有，但管线判定它没有可信坐标」（前后站里程对不上，
-- 见 discard_implausible_station_coordinates）。这与「表里没有这一行」是两回事：
-- 没有行时 App 可以退回 coordinates.csv，而 NULL 行必须让 App 一并丢弃 CSV 里
-- 的同名值——那正是被舍掉的那个错坐标。
CREATE TABLE stations (
  station_name TEXT PRIMARY KEY,
  latitude     REAL,
  longitude    REAL
);
"""


def encode_polyline(points: Sequence[geo.Coord]) -> bytes:
    payload = json.dumps(
        [[round(lat, 5), round(lon, 5)] for lat, lon in points],
        separators=(",", ":"),
    ).encode("utf-8")
    # mtime=0：gzip 头默认带当前时间，同一份输入重跑两次也会得到不同的字节，
    # 这个库是进仓库的构建产物，只有确定性的输出才能靠 diff 看出到底改了什么。
    return gzip.compress(payload, compresslevel=9, mtime=0)


def station_rows(
    index: StationCoordinateIndex,
    legs: Sequence[Leg],
    discarded: Sequence[str] = (),
) -> List[Tuple[str, Optional[float], Optional[float]]]:
    """枚举出的段用到的站名 → 已解析坐标，供 App 标记车站。

    只导出真正被绘制到的站（段的两个端点），没被任何段用到的站不必塞进包里。
    原始站名照写，App 侧会按同样的归一化规则再查一次。

    [discarded] 里的站写成**坐标为 NULL** 的行：App 见到 NULL 行就不许退回
    coordinates.csv，否则那个被舍掉的错坐标会从 CSV 里原样回来。
    """
    rows: Dict[str, Tuple[str, Optional[float], Optional[float]]] = {
        name: (name, None, None) for name in discarded
    }
    for leg in legs:
        for name in (leg.from_station, leg.to_station):
            if name in rows:
                continue
            coordinate = index.find(name)
            if coordinate is not None:
                rows[name] = (name, coordinate[0], coordinate[1])
    return list(rows.values())


def write_database(
    out_path: Path,
    results: Sequence[LegResult],
    meta: Dict[str, str],
    stations: Sequence[Tuple[str, Optional[float], Optional[float]]] = (),
) -> Tuple[int, int, int]:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    connection = sqlite3.connect(out_path)
    try:
        connection.executescript(SCHEMA)
        ok_count = 0
        failure_count = 0
        total_bytes = 0
        for result in sorted(results, key=lambda item: item.leg.key()):
            leg = result.leg
            plan = result.plan
            if plan.ok:
                if plan.split:
                    # 上行线是 plan.polyline（见 LegPlan 的字段说明），下行另写一行。
                    rows = [
                        ("up", plan.polyline, plan.length_km),
                        ("down", plan.down_polyline, plan.down_length_km),
                    ]
                else:
                    rows = [("", plan.polyline, plan.length_km)]
                for direction, points, length_km in rows:
                    polyline = encode_polyline(points)
                    total_bytes += len(polyline)
                    connection.execute(
                        "INSERT OR REPLACE INTO tracks VALUES (?,?,?,?,?,?,?,?,?,?)",
                        (
                            leg.route_name,
                            leg.from_station,
                            leg.to_station,
                            leg.profile,
                            direction,
                            polyline,
                            len(points),
                            length_km,
                            plan.mileage_km,
                            plan.mileage_error_km,
                        ),
                    )
                ok_count += 1
            else:
                connection.execute(
                    "INSERT OR REPLACE INTO failures VALUES (?,?,?,?,?,?,?)",
                    (
                        leg.route_name,
                        leg.from_station,
                        leg.to_station,
                        plan.reason,
                        plan.length_km or None,
                        plan.mileage_km,
                        plan.mileage_error_ratio,
                    ),
                )
                failure_count += 1

        connection.executemany(
            "INSERT OR REPLACE INTO stations VALUES (?,?,?)", stations
        )

        for key, value in meta.items():
            connection.execute("INSERT OR REPLACE INTO meta VALUES (?,?)", (key, str(value)))
        connection.commit()
    finally:
        connection.close()
    return ok_count, failure_count, total_bytes


# --------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="离线生成站间轨道折线（app/assets/db/rail_tracks.db）",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--routes-db", type=Path, default=DEFAULT_ROUTES_DB)
    parser.add_argument("--coordinates", type=Path, default=DEFAULT_COORDINATES)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--route", action="append", dest="routes", metavar="NAME",
                        help="只处理指定线路（可重复；「线/铁路」后缀可省略）")
    parser.add_argument("--source", choices=["overpass", "pbf"], default="pbf",
                        help="铁路网数据来源；pbf 为本地整网读取（推荐），overpass 为在线取数")
    parser.add_argument("--pbf", type=Path, default=None,
                        help=f"--source pbf 的 OSM 文件路径（默认 {DEFAULT_PBF}）")
    parser.add_argument("--overpass-endpoint", action="append", dest="overpass_endpoints",
                        metavar="URL",
                        help="覆盖 Overpass 端点（可重复；缺省轮流用内置镜像列表）")
    parser.add_argument("--workers", type=int, default=16,
                        help="并行规划的进程数；每个进程各读一份 PBF，稳定后约 0.6GB，"
                             "启动那 20 秒瞬时约 2.4GB（16 进程约需 36GB 富余内存）")
    parser.add_argument("--step-m", type=float, default=400.0, help="折线重采样步长（米）")
    parser.add_argument("--max-error-ratio", type=float, default=0.35,
                        help="折线长度与里程的最大相对偏差，超出则记为失败")
    parser.add_argument("--detour-ratio", type=float, default=geo.DEFAULT_DETOUR_RATIO,
                        help="折线实长相对起终点直线距离的倍率上限，超出则记为失败"
                             "（客里表站坐标失真导致的绕路）")
    parser.add_argument("--limit", type=int, help="只处理前 N 段（调试用）")
    parser.add_argument("--apply", action="store_true",
                        help="真正联网取数并写库；缺省只打印计划")
    parser.add_argument("--stub", action="store_true",
                        help="只写一个空库（schema 正确、0 条折线），"
                             "供尚未跑过管线时能构建 App；不需要 --apply")
    return parser.parse_args(argv)


def print_enumeration(stats: EnumerationStats, legs_total: int) -> None:
    profiles = stats.profile_counts()
    print(f"线路           : {stats.route_count}")
    print(f"车站行         : {stats.station_rows}（无坐标 {stats.missing_station_rows}）")
    print(f"可用坐标车站   : {stats.located_stations}")
    print(f"相邻同坐标合并 : {stats.collided_pairs}")
    print(f"站间段         : {len(stats.legs)}"
          + (f"（已按 --limit 截断，全量 {legs_total}）" if len(stats.legs) != legs_total else ""))
    print(f"  高铁/城际    : {profiles.get(geo.HSR, 0)}")
    print(f"  普速         : {profiles.get(geo.CONVENTIONAL, 0)}")
    with_mileage = sum(1 for leg in stats.legs if leg.mileage_km)
    print(f"  带里程约束   : {with_mileage} / {len(stats.legs)}")
    if stats.suspect_legs:
        print(f"  坐标不可信   : {stats.suspect_legs}（跳过取数，记为失败、App 回退直线）")


def stations_context_of(args: argparse.Namespace) -> Optional[Tuple[Path, Path]]:
    """消歧车站坐标所需的两份输入；没有它们就只能按站名 first-wins。"""
    return (args.routes_db, args.coordinates)


def build_source(args: argparse.Namespace) -> RailSource:
    if args.source == "pbf":
        return PbfRailSource(
            args.cache_dir,
            args.pbf or DEFAULT_PBF,
            stations_context=stations_context_of(args),
        )
    return OverpassRailSource(args.cache_dir, args.overpass_endpoints or OVERPASS_ENDPOINTS)


def build_coordinates(
    args: argparse.Namespace, stations: Optional[OsmStationSet]
) -> Tuple[StationCoordinateIndex, str]:
    """coordinates.csv 为基线，OSM 车站校正并补缺；没有 OSM 数据时只用 CSV。

    其中 [OsmStationSet.verified]（经线路消歧确认的坐标）优先级最高，能越过 30km
    守卫——CSV 错、OSM 对且相距上千公里的站只能靠它救回来。见
    [StationCoordinateIndex.from_sources]。
    """
    if stations:
        return (
            StationCoordinateIndex.from_sources(
                stations.stations, args.coordinates, stations.verified
            ),
            f"{args.coordinates.name} 为基线 + OSM 车站 {len(stations)} 个键"
            f"就近校正（{OSM_TRUST_RADIUS_KM:.0f}km 内）并补缺"
            + (
                f"，另有 {len(stations.verified)} 个键经线路消歧确认"
                if stations.verified
                else ""
            ),
        )
    reason = f"仅 {args.coordinates.name}"
    if args.source == "pbf":
        reason += "（尚无 OSM 车站缓存，跑一次 --source pbf --apply 即会生成）"
    return StationCoordinateIndex.from_csv(args.coordinates), reason


def main(argv: Optional[Sequence[str]] = None) -> int:
    _utf8_stdout()
    args = parse_args(argv)
    started = time.time()

    source: Optional[RailSource] = None

    def get_source() -> RailSource:
        """惰性构造并复用：读 PBF 要几十秒到几分钟（视机器而定），绝不能因为枚举
        坐标再读一遍。"""
        nonlocal source
        if source is None:
            source = build_source(args)
        return source

    stations = load_osm_stations(args.cache_dir) if args.source == "pbf" else None
    if stations is None and args.source == "pbf" and args.apply and not args.stub:
        # 反正待会儿要读整网，顺手把车站坐标缓存出来给后续 dry run 用。
        built = get_source()
        stations = OsmStationSet(
            stations=built.station_coordinates(),
            verified=built.verified_stations(),
        )
        fixes = built.station_fixes()
    else:
        # 吃缓存时不读 PBF，也就重算不出清单了，读落盘的那份。
        fixes = load_station_fixes(args.cache_dir)

    coordinates, coordinate_source = build_coordinates(args, stations)
    print(f"坐标索引       : {len(coordinates)} 个键（{coordinate_source}）")
    print_station_fixes(fixes)

    # 消歧之后仍对不上里程的站，坐标本身就不可信：舍去。之后 enumerate_legs 会把
    # 它们当作无坐标站跳过、桥接前后两站——与既有的无坐标站行为完全一致。
    discarded = discard_implausible_station_coordinates(coordinates, args.routes_db)
    print_discarded_stations(discarded)

    full = enumerate_legs(args.routes_db, coordinates, args.routes, args.limit)
    print_enumeration(full, full.legs_total)

    if args.stub:
        write_database(
            args.out,
            [],
            {
                "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "source": "stub",
                "legs_total": "0",
                "legs_ok": "0",
                "legs_failed": "0",
            },
        )
        print(f"\n已写入空库（0 条折线）：{args.out}")
        print("App 侧会因此全部回退为站间直线；正式数据请跑完整管线。")
        return 0

    if not args.apply:
        print("\n未指定 --apply，仅打印计划，不联网、不写文件。")
        return 0

    legs = full.legs
    if not legs:
        print("\n没有可处理的站间段。", file=sys.stderr)
        return 1

    # 直接取类属性而不是 get_source().name：名字就是个字面量，而真去建一份源要读
    # 20s PBF、占几百 MB——多进程分支马上要把父进程这份丢掉，读了纯属白读。
    source_name = PbfRailSource.name if args.source == "pbf" else OverpassRailSource.name
    # 加载排队：同时在读 PBF 的进程数按可用内存定，避免 16 份瞬时内存同时压上来。
    slots = _load_slot_count(args.workers, _available_ram_bytes()) if args.workers > 1 else 0
    print(f"\n数据源         : {source_name}（缓存 {args.cache_dir / source_name}）")
    print(f"并发           : {args.workers} 进程，重采样 {args.step_m:.0f} m")
    if slots:
        print(f"并发读 PBF     : 最多 {slots} 个进程同时加载（其余排队，读完转入规划）")
    print()

    if args.workers > 1:
        # spawn 出来的子进程拿不到父进程那份网格（也不可 pickle），worker 会各自读一份，
        # 父进程这份留着（如果有）也就没用了，白占几百 MB。
        source = None
        init_args = _worker_initializer_args(args, multiprocessing.Semaphore(slots))
        # 逐条分发而不是分块：段与段的耗时差得很远（短腿几十毫秒、长腿几秒），分块会让
        # 某几个 worker 拖着长块跑完、其余早就空转。
        with concurrent.futures.ProcessPoolExecutor(
            max_workers=args.workers,
            initializer=_init_worker,
            initargs=init_args,
        ) as pool:
            finished = list(_progress(pool.map(_plan_leg_in_worker, legs, chunksize=1), len(legs)))
    else:
        # 单进程就在本进程里建源：不必付一次进程启动 + 重读 PBF 的钱，也不必排队。
        _init_worker(*_worker_initializer_args(args))
        finished = list(
            _progress((_plan_leg_in_worker(leg) for leg in legs), len(legs))
        )
    ok_count = sum(1 for item in finished if item.plan.ok)
    reasons: Dict[str, int] = {}
    for item in finished:
        if not item.plan.ok:
            reason = item.plan.reason.split(":")[0]
            reasons[reason] = reasons.get(reason, 0) + 1

    stations_out = station_rows(
        coordinates, legs, [name for name, _prev, _next in discarded]
    )
    split_count = sum(1 for item in finished if item.plan.ok and item.plan.split)
    meta = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "source": source_name,
        "step_m": f"{args.step_m:.0f}",
        "max_error_ratio": f"{args.max_error_ratio}",
        "error_slack_km": f"{geo.DEFAULT_ERROR_SLACK_KM}",
        "detour_ratio": f"{args.detour_ratio}",
        "workers": args.workers,
        "legs_total": len(legs),
        "legs_ok": ok_count,
        "legs_failed": len(legs) - ok_count,
        "split_legs": split_count,
        "routes_total": full.route_count,
        "stations": len(stations_out),
        "coordinate_source": coordinate_source,
        # 影响结果的取数/算法口径，记下来才能分辨两份库是哪一套跑出来的。
        "way_filter": "railway=rail；service=yard/siding 作为非 preferred 连接线保留",
        "snap_fallback": "最近吸附点不通时改试同分量的次近节点",
        "track_split": "上下行在 OSM 里明显分离（>40m 且同长）时按左行规则分写 up/down 两行",
        "station_disambiguation": (
            f"同名候选按线路 way 就近消歧（半径 {LINE_SNAP_RADIUS_KM:.0f}km），"
            f"修正 {len(fixes)} 个站的坐标"
        ),
        "station_coordinate_discards": (
            f"前后站里程异常时舍去坐标（共 {len(discarded)} 个）；"
            f"它们在 stations 表里写成坐标为 NULL 的行，App 见到即不回退 CSV"
        ),
    }

    written_ok, written_failed, total_bytes = write_database(
        args.out, finished, meta, stations_out
    )

    print("\n结果")
    print(f"  成功         : {ok_count} / {len(legs)}"
          f"（{ok_count / max(1, len(legs)) * 100:.1f}%）")
    if split_count:
        print(f"  上下行分离   : {split_count} 段（各写 up/down 两行）")
    if reasons:
        for reason, count in sorted(reasons.items(), key=lambda item: -item[1]):
            print(f"  失败 {reason:<20}: {count}")
    print(f"  折线体积     : {total_bytes / 1024 / 1024:.2f} MB（压缩后）")
    print(f"  输出         : {args.out}")
    print(f"  耗时         : {time.time() - started:.1f}s")
    if written_ok == 0:
        print("\n没有生成任何折线，请检查数据源与网络。", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
