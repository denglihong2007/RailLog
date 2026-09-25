"""build_rail_tracks 的单元测试（标准库 unittest，不联网、不写真实资源）。

运行：
    cd tools && python -m unittest discover -p "test_*.py" -v
"""

from __future__ import annotations

import contextlib
import gzip
import io
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

# 同目录平级 import：被 unittest 当包发现时（osm_update.test_xxx）也得能 import 到同目录模块。
sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_rail_tracks as builder  # noqa: E402
import rail_track_geometry as geo  # noqa: E402


def _write_routes_db(path: Path) -> None:
    """构造一个迷你 routes.db：含无坐标站、同坐标站名、以及线路多版本。"""
    connection = sqlite3.connect(path)
    connection.executescript(
        """
        CREATE TABLE routes (route_version_id TEXT PRIMARY KEY, route_name TEXT, datatype TEXT);
        CREATE TABLE stations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          route_version_id TEXT, station_index INTEGER, station_name TEXT, mileage REAL
        );
        """
    )
    connection.executemany(
        "INSERT INTO routes VALUES (?,?,?)",
        [
            ("1", "京沪高速线", "2026-7-15"),
            ("2", "宝成线", "2026-7-15"),
            # 旧版本：应被同名的 2026-7-15 版本取代。
            ("3", "新线", "2026-1-1"),
            ("4", "新线", "2026-8-1"),
            # 相邻两站的坐标被匹配到相隔数千公里的同名站 → 应判为不可信。
            ("5", "远线", "2026-7-15"),
        ],
    )
    connection.executemany(
        "INSERT INTO stations (route_version_id, station_index, station_name, mileage) VALUES (?,?,?,?)",
        [
            # 中间一站没有坐标（线路所），应被跳过，其前后两站直接相连。
            ("1", 1, "北京南站", 0.0),
            ("1", 2, "京津所", 30.0),
            ("1", 3, "廊坊站", 60.0),
            ("1", 4, "天津站", 120.0),
            # 同一地点两个站名 → 坐标相同 → 应合并成一个点。
            ("2", 1, "宝鸡站", 0.0),
            ("2", 2, "宝鸡站(老)", 0.0),
            ("2", 3, "凤州站", 90.0),
            # 旧版本多一站，用来验证被整版替换而不是混在一起。
            ("3", 1, "甲站", 0.0),
            ("3", 2, "乙站", 10.0),
            ("4", 1, "甲站", 0.0),
            ("4", 2, "乙站", 20.0),
            ("4", 3, "丙站", 40.0),
            # 里程 20km，但两站坐标相隔 3000km 以上 → 坐标不可信。
            ("5", 1, "近站", 0.0),
            ("5", 2, "远站", 20.0),
        ],
    )
    connection.commit()
    connection.close()


def _write_coordinates(path: Path, rows: list[tuple[str, float, float]]) -> None:
    lines = ["﻿station_name,latitude,longitude"]
    lines += [f"{name},{lat},{lon}" for name, lat, lon in rows]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


class StationCoordinateIndexTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.path = Path(self._tmp.name) / "coordinates.csv"
        _write_coordinates(
            self.path,
            [
                ("北京南站", 39.865, 116.378),
                ("上海虹桥", 31.194, 121.320),
                # 站名里含逗号，CSV 解析要从后往前找分隔符。
                ("香港, 红磡", 22.303, 114.182),
            ],
        )
        self.index = builder.StationCoordinateIndex.from_csv(self.path)

    def test_finds_station_by_raw_and_normalized_name(self) -> None:
        self.assertEqual(self.index.find("北京南站"), (39.865, 116.378))
        self.assertEqual(self.index.find("北京南"), (39.865, 116.378))
        self.assertEqual(self.index.find(" 上海虹桥站 "), (31.194, 121.320))

    def test_returns_none_for_unknown_station(self) -> None:
        self.assertIsNone(self.index.find("不存在的站"))

    def test_handles_station_name_containing_a_comma(self) -> None:
        self.assertEqual(self.index.find("香港, 红磡"), (22.303, 114.182))

    def test_bom_never_leaks_into_a_lookup_key(self) -> None:
        self.assertFalse([key for key in self.index._coordinates if "﻿" in key])

    def test_indexes_both_raw_and_normalized_keys(self) -> None:
        # 与 Dart 的 putIfAbsent 一致：'北京南站' 与 '北京南' 各占一个键；
        # '上海虹桥' 原名就已是归一化形式，只占一个键。
        self.assertIn("北京南站", self.index._coordinates)
        self.assertIn("北京南", self.index._coordinates)
        self.assertEqual(len(self.index), 5)

    def test_remove_clears_both_raw_and_normalized_keys(self) -> None:
        self.index.remove("北京南站")

        # 只删一个键的话，find 会从另一个键把同一个坐标读回来。
        self.assertIsNone(self.index.find("北京南站"))
        self.assertIsNone(self.index.find("北京南"))

    def test_remove_also_drops_another_spelling_of_the_same_station(self) -> None:
        # 同一个站可能以多种写法进了索引（CSV 一行「永乐」、OSM 节点叫「永乐站」）。
        # 只删同名键的话，另一种写法会把坐标顶回来，这个站其实没被舍去。
        path = Path(self._tmp.name) / "spelled.csv"
        _write_coordinates(
            path, [("永乐站", 39.6529, 116.7885), ("永乐店", 39.8, 116.7)]
        )
        index = builder.StationCoordinateIndex.from_csv(path)

        index.remove("永乐")

        self.assertIsNone(index.find("永乐站"))
        self.assertIsNone(index.find("永乐"))
        # 归一化后是另一个站，不能误删。
        self.assertEqual(index.find("永乐店"), (39.8, 116.7))

    def test_remove_of_an_unknown_station_is_a_no_op(self) -> None:
        before = len(self.index)

        self.index.remove("不存在的站")

        self.assertEqual(len(self.index), before)

    def test_from_sources_nudges_a_csv_station_onto_the_track(self) -> None:
        # CSV 的北京南站 (39.865,116.378) 偏了约 4km，OSM 的这个更贴轨道。
        osm = {"北京南站": ("北京南站", 39.900, 116.400)}
        index = builder.StationCoordinateIndex.from_sources(osm, self.path)

        self.assertEqual(index.find("北京南站"), (39.900, 116.400))

    def test_from_sources_fills_stations_the_csv_lacks(self) -> None:
        osm = {"郑州东": ("郑州东", 34.750, 113.770)}
        index = builder.StationCoordinateIndex.from_sources(osm, self.path)

        self.assertEqual(index.find("郑州东"), (34.750, 113.770))
        # CSV 独有的站仍要能查到——OSM 不覆盖没撞上的站。
        self.assertEqual(index.find("上海虹桥"), (31.194, 121.320))

    def test_from_sources_refuses_a_colliding_name_from_far_away(self) -> None:
        # 关键回归：'莲塘' 这类通用站名在 OSM 里有几十个同名节点（深圳、南昌……），
        # first-wins 会挑到外省那个。超出信任半径就不该覆盖 CSV。
        osm = {"北京南站": ("北京南站", 22.570, 114.170)}  # 深圳，距北京约 1950km
        index = builder.StationCoordinateIndex.from_sources(osm, self.path)

        self.assertEqual(index.find("北京南站"), (39.865, 116.378))

    def test_from_sources_accepts_just_inside_the_trust_radius(self) -> None:
        # 约 28.9km（0.26° 纬度）在 30km 内 → 采信 OSM。
        osm = {"北京南站": ("北京南站", 39.865 + 0.26, 116.378)}
        index = builder.StationCoordinateIndex.from_sources(osm, self.path)

        self.assertEqual(index.find("北京南站"), (39.865 + 0.26, 116.378))

    def test_from_sources_rejects_just_outside_the_trust_radius(self) -> None:
        # 约 33.4km（0.30° 纬度）超出 30km → 保留 CSV。
        osm = {"北京南站": ("北京南站", 39.865 + 0.30, 116.378)}
        index = builder.StationCoordinateIndex.from_sources(osm, self.path)

        self.assertEqual(index.find("北京南站"), (39.865, 116.378))

    def test_from_sources_keeps_csv_when_osm_alias_forms_differ(self) -> None:
        # OSM 只给了 '北京南'（无「站」），两个键都会撞上 CSV 的同名键；
        # 距离太远，两个键都得保住 CSV 的值。
        osm = {"北京南": ("北京南", 22.570, 114.170)}
        index = builder.StationCoordinateIndex.from_sources(osm, self.path)

        self.assertEqual(index.find("北京南站"), (39.865, 116.378))


class EnumerateLegsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        root = Path(self._tmp.name)
        self.routes_db = root / "routes.db"
        _write_routes_db(self.routes_db)
        coordinates = root / "coordinates.csv"
        _write_coordinates(
            coordinates,
            [
                ("北京南站", 39.865, 116.378),
                ("廊坊站", 39.520, 116.700),
                ("天津站", 39.135, 117.210),
                ("宝鸡站", 34.360, 107.150),
                ("凤州站", 33.950, 106.600),
                ("甲站", 30.0, 104.0),
                ("乙站", 30.2, 104.0),
                ("丙站", 30.4, 104.0),
                ("近站", 30.0, 104.0),
                # 同名异地：与近站相距约 3000km。
                ("远站", 45.8, 126.6),
            ],
        )
        self.index = builder.StationCoordinateIndex.from_csv(coordinates)

    def legs_for(self, route: str) -> list[builder.Leg]:
        stats = builder.enumerate_legs(self.routes_db, self.index, [route])
        return stats.legs

    def test_skips_stations_without_coordinates_and_bridges_across(self) -> None:
        legs = self.legs_for("京沪高速线")

        self.assertEqual([leg.from_station for leg in legs], ["北京南站", "廊坊站"])
        self.assertEqual([leg.to_station for leg in legs], ["廊坊站", "天津站"])
        # 京津所无坐标被跳过，北京南直接连到廊坊（里程取两端站点里程之差）。
        self.assertAlmostEqual(legs[0].mileage_km, 60.0)

    def test_mileage_is_absolute_difference_of_endpoints(self) -> None:
        self.assertAlmostEqual(self.legs_for("京沪高速线")[1].mileage_km, 60.0)
        self.assertAlmostEqual(self.legs_for("宝成线")[0].mileage_km, 90.0)

    def test_merges_consecutive_stations_at_the_same_coordinate(self) -> None:
        # 宝鸡站(老) 与宝鸡站 坐标相同，合并后只剩宝鸡站→凤州站一段。
        legs = self.legs_for("宝成线")

        self.assertEqual(len(legs), 1)
        self.assertEqual((legs[0].from_station, legs[0].to_station), ("宝鸡站", "凤州站"))

    def test_uses_latest_route_version(self) -> None:
        # datatype 2026-8-1 的版本有 3 站（2 段），2026-1-1 的只有 2 站（1 段）。
        legs = self.legs_for("新线")

        self.assertEqual(len(legs), 2)
        self.assertAlmostEqual(legs[1].mileage_km, 20.0)

    def test_infers_profile_from_route_name(self) -> None:
        self.assertEqual(self.legs_for("京沪高速线")[0].profile, geo.HSR)
        self.assertEqual(self.legs_for("宝成线")[0].profile, geo.CONVENTIONAL)

    def test_route_filter_accepts_name_without_line_suffix(self) -> None:
        self.assertEqual(len(self.legs_for("京沪高速")), 2)
        self.assertEqual(self.legs_for("不存在线"), [])

    def test_flags_leg_whose_coordinate_is_implausible(self) -> None:
        legs = self.legs_for("远线")

        self.assertEqual(len(legs), 1)
        self.assertEqual(legs[0].suspect_reason, "suspect_coordinate")
        # 可信的段带 None，好让调用方只判一次真值。
        self.assertIsNone(self.legs_for("宝成线")[0].suspect_reason)

    def test_counts_and_limit(self) -> None:
        stats = builder.enumerate_legs(self.routes_db, self.index)
        total = len(stats.legs)

        self.assertEqual(stats.route_count, 4)
        self.assertEqual(stats.missing_station_rows, 1)  # 京津所
        self.assertEqual(stats.collided_pairs, 1)  # 宝鸡站(老)
        self.assertEqual(stats.suspect_legs, 1)  # 远线
        self.assertEqual(total, 6)
        self.assertEqual(len(builder.enumerate_legs(self.routes_db, self.index, limit=2).legs), 2)


class ParseSourceTest(unittest.TestCase):
    def test_parses_overpass_ways_with_profile_tags(self) -> None:
        payload = {
            "elements": [
                {
                    "type": "way",
                    "tags": {"railway": "rail", "maxspeed": "350"},
                    "geometry": [{"lat": 30.0, "lon": 104.0}, {"lat": 30.1, "lon": 104.0}],
                },
                {
                    "type": "way",
                    "tags": {"railway": "rail", "maxspeed": "80"},
                    "geometry": [{"lat": 30.0, "lon": 105.0}, {"lat": 30.1, "lon": 105.0}],
                },
                {
                    "type": "way",
                    "tags": {"railway": "rail", "service": "siding"},
                    "geometry": [{"lat": 30.0, "lon": 106.0}, {"lat": 30.1, "lon": 106.0}],
                },
                {"type": "node", "lat": 30.0, "lon": 104.0},
            ]
        }

        ways = builder._parse_overpass(payload)

        # 站线留着当连接线（既非高铁也非普速），node 被忽略。
        self.assertEqual(len(ways), 3)
        self.assertTrue(ways[0].is_hsr)
        self.assertFalse(ways[0].is_conventional)
        self.assertFalse(ways[1].is_hsr)
        self.assertEqual((ways[2].is_hsr, ways[2].is_conventional), (False, False))
        for profile in (geo.HSR, geo.CONVENTIONAL, geo.ALL):
            self.assertFalse(ways[2].preferred_for(profile))
        self.assertEqual(ways[0].coords, [(30.0, 104.0), (30.1, 104.0)])

    def test_parses_geojson_with_lon_lat_order(self) -> None:
        payload = {
            "features": [
                {
                    "properties": {"railway": "rail", "maxspeed": "300"},
                    "geometry": {
                        "type": "LineString",
                        "coordinates": [[104.0, 30.0], [104.0, 30.1]],
                    },
                },
                {
                    "properties": {"railway": "rail", "service": "yard"},
                    "geometry": {"type": "LineString", "coordinates": [[105.0, 30.0], [105.0, 30.1]]},
                },
            ]
        }

        ways = builder._parse_geojson(payload)

        # 站场（service=yard）现在留着当连接线，不再被丢掉。
        self.assertEqual(len(ways), 2)
        self.assertTrue(ways[0].is_hsr)
        self.assertEqual((ways[1].is_hsr, ways[1].is_conventional), (False, False))
        # GeoJSON 是 [lon, lat]，读进来必须还原成 (lat, lon)。
        self.assertEqual(ways[0].coords, [(30.0, 104.0), (30.1, 104.0)])
        self.assertEqual(ways[1].coords, [(30.0, 105.0), (30.1, 105.0)])

    def test_cache_round_trip_preserves_flags_and_coordinates(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "tile.json.gz"
            ways = [
                builder.CachedWay(True, False, [(30.0, 104.0), (30.1, 104.0)]),
                builder.CachedWay(False, True, [(31.0, 105.0), (31.1, 105.0)]),
            ]

            builder._write_cache(path, ways)
            restored = builder._read_cache(path)

        self.assertEqual([(w.is_hsr, w.is_conventional) for w in restored], [(True, False), (False, True)])
        self.assertEqual(restored[0].coords, [(30.0, 104.0), (30.1, 104.0)])

    def test_preferred_for_varies_by_profile(self) -> None:
        hsr = builder.CachedWay(True, False, [(30.0, 104.0)])
        conventional = builder.CachedWay(False, True, [(30.0, 104.0)])

        self.assertTrue(hsr.preferred_for(geo.HSR))
        self.assertFalse(hsr.preferred_for(geo.CONVENTIONAL))
        self.assertTrue(conventional.preferred_for(geo.CONVENTIONAL))
        self.assertTrue(conventional.preferred_for(geo.ALL))

    def test_quantized_bbox_snaps_adjacent_legs_to_the_same_cache_key(self) -> None:
        first = builder._quantized_bbox((30.001, 104.001, 31.002, 105.003))
        second = builder._quantized_bbox((30.019, 104.019, 31.018, 105.021))

        self.assertEqual(builder._bbox_cache_key(first), builder._bbox_cache_key(second))


class WayGridTest(unittest.TestCase):
    def _grid(self) -> builder.WayGrid:
        grid = builder.WayGrid(grid_deg=0.1)
        grid.add(builder.CachedWay(True, False, [(30.00, 104.00), (30.05, 104.05)]))
        grid.add(builder.CachedWay(False, True, [(40.00, 110.00), (40.05, 110.05)]))
        return grid

    def test_finds_only_ways_intersecting_the_bbox(self) -> None:
        grid = self._grid()

        self.assertEqual(len(grid.find((29.9, 103.9, 30.2, 104.2))), 1)
        self.assertEqual(len(grid.find((39.9, 109.9, 40.2, 110.2))), 1)
        self.assertEqual(grid.find((0.0, 0.0, 1.0, 1.0)), [])

    def test_returns_each_way_once_even_when_it_spans_many_cells(self) -> None:
        # 一条纵贯 5 个格子的长 way：格子粗筛会把下标塞进每个格子，必须去重。
        grid = builder.WayGrid(grid_deg=0.1)
        grid.add(builder.CachedWay(True, False, [(30.0, 104.0), (30.5, 104.0)]))

        found = grid.find((29.9, 103.9, 30.6, 104.1))

        self.assertEqual(len(found), 1)

    def test_excludes_ways_whose_cell_matches_but_bbox_does_not(self) -> None:
        # way 在 (30.0,104.0)~(30.05,104.05)，查询框同格但偏在格子另一角 → 不相交。
        grid = builder.WayGrid(grid_deg=0.1)
        grid.add(builder.CachedWay(True, False, [(30.00, 104.00), (30.05, 104.05)]))

        self.assertEqual(grid.find((30.06, 104.06, 30.09, 104.09)), [])

    def test_bbox_is_inclusive_at_the_edges(self) -> None:
        grid = self._grid()

        # 查询框的边正好压在 way 的端点上，仍算相交。
        self.assertEqual(len(grid.find((30.05, 104.05, 30.5, 104.5))), 1)

    def test_len_counts_registered_ways(self) -> None:
        self.assertEqual(len(self._grid()), 2)


class DisambiguateStationsTest(unittest.TestCase):
    """同名车站候选按线路几何消歧。

    这是 coordinates.csv 和 OSM 车站节点都会犯错的那一类：两者都只按站名索引，
    通用站名稳定地命中外省同名点。判据只能来自轨道本身——正确的新立屯一定紧邻
    名为「新义线」的 way，内蒙古那个村子不是。
    """

    # 真实的新立屯站在辽宁，就在新义线旁边；coordinates.csv 命中的是 826km 外
    # 内蒙古的同名村庄。
    LIAONING = ("新立屯", 42.0194891, 122.1750221)
    INNER_MONGOLIA = ("新立屯", 42.017975, 112.1711389)

    def _line_way(self, name: str, latitude: float) -> builder.CachedWay:
        """一条东西向的正线 way，大致贴着 [latitude] 这条纬线。"""
        return builder.CachedWay(
            False, True, [(latitude, 122.160), (latitude, 122.190)], name
        )

    def test_picks_the_candidate_sitting_next_to_its_own_line(self) -> None:
        grid = builder.WayGrid(grid_deg=0.1)
        # 轨道在候选点以北约 110m，跟真实车站与线路的关系相当。
        grid.add(self._line_way("新义线", 42.0205))

        resolved, fixes = builder.disambiguate_stations(
            grid,
            {"新立屯": [self.LIAONING, self.INNER_MONGOLIA]},
            {"新义线": ["新立屯", "新邱"]},
            # CSV 里是内蒙古那个错值，消歧要能推翻它。
            {"新立屯": (self.INNER_MONGOLIA[1], self.INNER_MONGOLIA[2])},
        )

        self.assertEqual(resolved["新立屯"], self.LIAONING)
        self.assertEqual(len(fixes), 1)
        self.assertEqual(fixes[0].line, "新义线")
        self.assertLess(fixes[0].distance_km, builder.LINE_SNAP_RADIUS_KM)
        # 挪了 800 多公里，这正是它值得被记录下来的原因。
        self.assertGreater(fixes[0].moved_km, 700)

    def test_keeps_the_original_value_when_no_candidate_is_near_the_line(self) -> None:
        grid = builder.WayGrid(grid_deg=0.1)
        # 新义线的 way 远在西南，两个候选谁都不挨着。
        grid.add(self._line_way("新义线", 30.0))

        resolved, fixes = builder.disambiguate_stations(
            grid,
            {"新立屯": [self.LIAONING, self.INNER_MONGOLIA]},
            {"新义线": ["新立屯", "新邱"]},
            {"新立屯": (self.INNER_MONGOLIA[1], self.INNER_MONGOLIA[2])},
        )

        # 无从判断时不硬挪——保持原值，比把车站瞬移到几百公里外好。
        self.assertEqual(resolved, {})
        self.assertEqual(fixes, [])

    def test_ignores_stations_whose_line_is_unknown(self) -> None:
        grid = builder.WayGrid(grid_deg=0.1)
        grid.add(self._line_way("新义线", 42.0205))

        resolved, fixes = builder.disambiguate_stations(
            grid,
            {"新立屯": [self.LIAONING, self.INNER_MONGOLIA]},
            {"新义线": ["新邱"]},
            {},
        )

        self.assertEqual(resolved, {})
        self.assertEqual(fixes, [])

    def test_leaves_a_single_candidate_alone(self) -> None:
        grid = builder.WayGrid(grid_deg=0.1)
        grid.add(self._line_way("新义线", 42.0205))

        resolved, fixes = builder.disambiguate_stations(
            grid,
            {"新立屯": [self.LIAONING]},
            {"新义线": ["新立屯"]},
            {"新立屯": (42.0, 122.0)},
        )

        # 只有一个候选就没什么可挑的，交给 from_sources 的守卫处理。
        self.assertEqual(resolved, {})
        self.assertEqual(fixes, [])

    def test_matches_a_way_whose_name_carries_the_line_suffix_in_another_form(self) -> None:
        grid = builder.WayGrid(grid_deg=0.1)
        # 客里表写「新义」/「新义线」并不统一，way 名比对要按归一化后的键。
        grid.add(self._line_way("新义", 42.0205))

        resolved, _ = builder.disambiguate_stations(
            grid,
            {"新立屯": [self.LIAONING, self.INNER_MONGOLIA]},
            {"新义线": ["新立屯"]},
            {},
        )

        self.assertEqual(resolved["新立屯"], self.LIAONING)


def _write_discard_routes_db(path: Path) -> None:
    """三条同构线路，站名互不相同，好分别验证「哪一条上的哪一站被舍去」。"""
    connection = sqlite3.connect(path)
    connection.executescript(
        """
        CREATE TABLE routes (route_version_id TEXT PRIMARY KEY, route_name TEXT, datatype TEXT);
        CREATE TABLE stations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          route_version_id TEXT, station_index INTEGER, station_name TEXT, mileage REAL
        );
        """
    )
    connection.executemany(
        "INSERT INTO routes VALUES (?,?,?)",
        [
            ("1", "试线", "2026-7-15"),
            ("2", "偏线", "2026-7-15"),
            ("3", "邻线", "2026-7-15"),
        ],
    )
    connection.executemany(
        "INSERT INTO stations (route_version_id, station_index, station_name, mileage) VALUES (?,?,?,?)",
        [
            (version_id, index + 1, f"{prefix}{suffix}站", float(index * 50))
            for version_id, prefix in (("1", "试"), ("2", "偏"), ("3", "邻"))
            for index, suffix in enumerate("甲乙丙丁戊")
        ],
    )
    connection.commit()
    connection.close()


def _discard_line_coordinates(prefix: str, base_longitude: float) -> list[tuple[str, float, float]]:
    """一条南北向直线上的五站，站间 50km 里程对上约 48km 直线，本身不触发异常。"""
    return [
        (f"{prefix}{suffix}站", 30.0, base_longitude + index * 0.5)
        for index, suffix in enumerate("甲乙丙丁戊")
    ]


class DiscardImplausibleStationCoordinatesTest(unittest.TestCase):
    """第二道裁判：里程桩。消歧救不回的站靠它抓。"""

    # 与线路相距数千公里，任何一段都远超 SUSPECT_STRAIGHT_KM。
    FAR_AWAY = (45.8, 126.6)

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        root = Path(self._tmp.name)
        self.routes_db = root / "routes.db"
        _write_discard_routes_db(self.routes_db)

        rows = (
            _discard_line_coordinates("试", 104.0)
            + _discard_line_coordinates("偏", 110.0)
            + _discard_line_coordinates("邻", 116.0)
        )
        # 偏线的中间站（两侧都还有邻居）飞到黑龙江；邻线的第二站也飞走——但它自己
        # 就是错的那一个。
        rows = [row for row in rows if row[0] not in ("偏丙站", "邻乙站")]
        rows += [("偏丙站", *self.FAR_AWAY), ("邻乙站", *self.FAR_AWAY)]
        coordinates = root / "coordinates.csv"
        _write_coordinates(coordinates, rows)
        self.index = builder.StationCoordinateIndex.from_csv(coordinates)

    def _discard(self) -> list[tuple[str, str, str]]:
        return builder.discard_implausible_station_coordinates(self.index, self.routes_db)

    def test_discards_an_interior_station_that_flew_to_another_province(self) -> None:
        discarded = self._discard()

        self.assertIn(("偏丙站", "偏乙站", "偏丁站"), discarded)
        self.assertIsNone(self.index.find("偏丙站"))

    def test_keeps_a_sound_station_that_merely_neighbours_a_bad_one(self) -> None:
        self._discard()

        # 邻乙站 是错的，所以它两侧都异常；邻丙站 只有一侧异常 → 它是无辜的邻居。
        self.assertIsNone(self.index.find("邻乙站"))
        self.assertIsNotNone(self.index.find("邻丙站"))

    def test_keeps_endpoints_whose_only_leg_is_implausible(self) -> None:
        self._discard()

        # 邻甲站 只连着一条异常段，端点处分不清是自己错还是邻居错，不动。
        self.assertIsNotNone(self.index.find("邻甲站"))
        self.assertIsNotNone(self.index.find("邻戊站"))

    def test_leaves_a_healthy_line_alone(self) -> None:
        discarded = {name for name, _prev, _next in self._discard()}

        for suffix in "甲乙丙丁戊":
            self.assertNotIn(f"试{suffix}站", discarded)

    def test_discarded_station_is_bridged_by_its_neighbours(self) -> None:
        self._discard()

        legs = builder.enumerate_legs(self.routes_db, self.index, ["偏线"]).legs

        # 舍去坐标后偏丙站等同于「没有坐标」，前后两站直接相连，而不是画到黑龙江。
        self.assertEqual(
            [(leg.from_station, leg.to_station) for leg in legs],
            [("偏甲站", "偏乙站"), ("偏乙站", "偏丁站"), ("偏丁站", "偏戊站")],
        )
        # 桥接段取两端站点里程之差：50km 处的偏乙站直接连到 150km 处的偏丁站。
        self.assertAlmostEqual(legs[1].mileage_km, 100.0)
        self.assertIsNone(legs[1].suspect_reason)

    def test_reports_the_station_it_sat_between(self) -> None:
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            builder.print_discarded_stations([("偏丙站", "偏乙站", "偏丁站")])

        printed = buffer.getvalue()
        self.assertIn("偏丙站", printed)
        self.assertIn("偏乙站", printed)
        self.assertIn("偏丁站", printed)


class OsmStationCacheTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.cache_dir = Path(self._tmp.name)

    def test_returns_none_when_never_written(self) -> None:
        # 「只看计划」不该为了车站坐标先去读 1.7GB 的 PBF。
        self.assertIsNone(builder.load_osm_stations(self.cache_dir))

    def test_round_trips_names_with_non_ascii(self) -> None:
        stations = {
            "北京南": ("北京南站", 39.865, 116.378),
            "郑州东": ("郑州东站", 34.750, 113.770),
        }
        verified = {"新立屯": ("新立屯", 42.0194891, 122.1750221)}

        builder.save_osm_stations(self.cache_dir, stations, verified)

        cached = builder.load_osm_stations(self.cache_dir)
        self.assertIsNotNone(cached)
        # 已验证的那份单独存放：它的可信度高于 first-wins 的兜底表。
        self.assertEqual(cached.stations, stations)
        self.assertEqual(cached.verified, verified)

    def test_old_cache_without_the_verified_flag_counts_as_unverified(self) -> None:
        # 改动前写下的三元组缓存一律当未验证，继续受 30km 守卫约束。
        path = builder._osm_stations_path(self.cache_dir)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            '{"新立屯": ["新立屯", 42.0, 122.1]}',
            encoding="utf-8",
        )

        cached = builder.load_osm_stations(self.cache_dir)
        self.assertIsNotNone(cached)
        self.assertEqual(cached.verified, {})
        self.assertEqual(cached.stations["新立屯"], ("新立屯", 42.0, 122.1))

    def test_returns_none_for_a_corrupt_cache(self) -> None:
        path = builder._osm_stations_path(self.cache_dir)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("{not json", encoding="utf-8")

        self.assertIsNone(builder.load_osm_stations(self.cache_dir))

    def test_returns_none_for_a_cache_with_the_wrong_shape(self) -> None:
        # 半个 JSON 或者结构变了的缓存都当没有：重扫 PBF 要 7 分钟，
        # 但不该让一个坏缓存把整条管线打断。
        path = builder._osm_stations_path(self.cache_dir)
        path.parent.mkdir(parents=True, exist_ok=True)

        for payload in ('{"北京南": "不是一个列表"}', '{"北京南": [1]}', "[]"):
            path.write_text(payload, encoding="utf-8")
            with self.subTest(payload=payload):
                self.assertIsNone(builder.load_osm_stations(self.cache_dir))


class StationRowsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.path = Path(self._tmp.name) / "coordinates.csv"
        _write_coordinates(
            self.path,
            [
                ("北京南站", 39.865, 116.378),
                ("廊坊站", 39.520, 116.700),
            ],
        )
        self.index = builder.StationCoordinateIndex.from_csv(self.path)

    def _leg(self, start: str, end: str) -> builder.Leg:
        return builder.Leg(
            route_name="京沪高速线",
            from_station=start,
            to_station=end,
            start=(0.0, 0.0),
            end=(1.0, 1.0),
            mileage_km=None,
            profile=geo.HSR,
        )

    def test_exports_only_stations_used_by_legs(self) -> None:
        rows = builder.station_rows(self.index, [self._leg("北京南站", "廊坊站")])

        self.assertEqual(
            sorted(rows), [("北京南站", 39.865, 116.378), ("廊坊站", 39.520, 116.700)]
        )

    def test_writes_each_station_once_across_adjacent_legs(self) -> None:
        legs = [self._leg("北京南站", "廊坊站"), self._leg("廊坊站", "北京南站")]

        self.assertEqual(len(builder.station_rows(self.index, legs)), 2)

    def test_skips_stations_that_have_no_coordinate(self) -> None:
        rows = builder.station_rows(self.index, [self._leg("北京南站", "不存在的站")])

        self.assertEqual([row[0] for row in rows], ["北京南站"])

    def test_keeps_the_raw_station_name_not_the_normalized_key(self) -> None:
        # App 会按同样的规则再归一化一次，所以这里必须写原始站名。
        rows = builder.station_rows(self.index, [self._leg("北京南", "廊坊站")])

        self.assertIn("北京南", [row[0] for row in rows])

    def test_exports_discarded_stations_with_a_null_coordinate(self) -> None:
        rows = builder.station_rows(
            self.index, [self._leg("北京南站", "廊坊站")], ["永乐"]
        )

        # NULL 行是「这个站没有可信坐标」的显式声明，App 见到就不许回退 CSV。
        self.assertIn(("永乐", None, None), rows)


def _write_pbf(path: Path) -> None:
    """写一个迷你 .osm.pbf：两条铁路 way + 三个车站节点，供 PbfRailSource 读。

    真的走 pyosmium 的读写路径（而不是打桩），才能验证 way_flags 过滤、节点坐标
    回填、车站别名归一化这几处只有真数据才暴露的问题。
    """
    import osmium

    writer = osmium.SimpleWriter(str(path))
    # 高铁（maxspeed=350）、普速（maxspeed=80）、以及一条站线（当连接线留着）。
    nodes = {
        1: (30.00, 104.00), 2: (30.10, 104.00),
        3: (30.00, 105.00), 4: (30.10, 105.00),
        5: (30.00, 106.00), 6: (30.10, 106.00),
        7: (30.00, 104.00), 8: (30.05, 105.00),
    }
    for node_id, (latitude, longitude) in sorted(nodes.items()):
        writer.add_node(
            osmium.osm.mutable.Node(
                id=node_id, location=(longitude, latitude), tags={}
            )
        )
    for station_id, name in ((7, "甲站"), (8, "乙站")):
        writer.add_node(
            osmium.osm.mutable.Node(
                id=station_id,
                location=(
                    nodes[station_id][1],
                    nodes[station_id][0],
                ),
                tags={"railway": "station", "name": name},
            )
        )
    # 别名齐全的站：name 是英文、name:zh 是中文、old_name 是旧名。客里表用的可能
    # 是其中任何一个，所以每个别名都得能查到（曾经只登记第一个，英文名会把整个站
    # 弄成查不到）。不挂 way：车站节点本来就是轨道旁的独立点。
    writer.add_node(
        osmium.osm.mutable.Node(
            id=9,
            location=(107.00, 30.20),
            tags={
                "railway": "station",
                "name": "Gamma Station",
                "name:zh": "丙站",
                "old_name": "丙旧站",
            },
        )
    )
    # 「甲站」在全国的第二个同名节点，远在深圳。first-wins 只会留下先扫到的那个，
    # 而消歧必须在两个候选里挑——所以候选表要两个都收。
    writer.add_node(
        osmium.osm.mutable.Node(
            id=10,
            location=(114.17, 22.57),
            tags={"railway": "station", "name": "甲站"},
        )
    )
    writer.add_way(osmium.osm.mutable.Way(
        id=101, nodes=[1, 2], tags={"railway": "rail", "maxspeed": "350"},
    ))
    writer.add_way(osmium.osm.mutable.Way(
        id=102, nodes=[3, 4], tags={"railway": "rail", "maxspeed": "80"},
    ))
    writer.add_way(osmium.osm.mutable.Way(
        id=103, nodes=[5, 6], tags={"railway": "rail", "service": "siding"},
    ))
    writer.close()


class PbfRailSourceTest(unittest.TestCase):
    def setUp(self) -> None:
        try:
            import osmium  # noqa: F401
        except ImportError:
            self.skipTest("未安装 pyosmium")
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.root = Path(self._tmp.name)
        self.pbf = self.root / "mini.osm.pbf"
        _write_pbf(self.pbf)
        self.cache_dir = self.root / "cache"
        self.source = builder.PbfRailSource(self.cache_dir, self.pbf)

    def test_keeps_sidings_as_non_preferred_connectors(self) -> None:
        ways = self.source.ways((29.9, 103.9, 30.2, 106.1))

        self.assertEqual(len(ways), 3)
        # 站线不再是「直接丢掉」：车站咽喉就是 service=siding，丢掉它等于把正线在
        # 每个车站处切断，而车站正是每段行程的起终点。留着当连接线，但不给偏好。
        siding = [way for way in ways if way.coords[0] == (30.0, 106.0)]
        self.assertEqual(len(siding), 1)
        self.assertFalse(siding[0].is_hsr)
        self.assertFalse(siding[0].is_conventional)
        for profile in (geo.HSR, geo.CONVENTIONAL, geo.ALL):
            self.assertFalse(siding[0].preferred_for(profile))

    def test_recovers_way_flags_from_tags(self) -> None:
        ways = self.source.ways((29.9, 103.9, 30.2, 106.1))

        # 排序后再比：三条 way 落在三个网格里，返回顺序不该成为测试的隐含依赖。
        flags = sorted((w.is_hsr, w.is_conventional) for w in ways)
        self.assertEqual(flags, [(False, False), (False, True), (True, False)])

    def test_reads_node_coordinates_in_lat_lon_order(self) -> None:
        ways = self.source.ways((29.9, 103.9, 30.2, 104.1))

        self.assertEqual(ways[0].coords, [(30.0, 104.0), (30.1, 104.0)])

    def test_bbox_query_excludes_distant_ways(self) -> None:
        self.assertEqual(self.source.ways((39.9, 119.9, 40.2, 120.2)), [])
        self.assertEqual(len(self.source.ways((29.9, 104.9, 30.2, 105.1))), 1)

    def test_collects_station_coordinates_keyed_by_normalized_name(self) -> None:
        stations = self.source.station_coordinates()

        self.assertEqual(stations["甲"], ("甲站", 30.0, 104.0))
        self.assertEqual(stations["乙站"], ("乙站", 30.05, 105.0))

    def test_registers_every_alias_a_station_node_carries(self) -> None:
        stations = self.source.station_coordinates()

        # 一个节点的三个别名各自成键，指向同一个坐标：车站名带「站」后缀时归一化会
        # 再剥一层，所以「丙站」也登记了「丙」。
        self.assertEqual(stations["gamma station"], ("Gamma Station", 30.20, 107.00))
        self.assertEqual(stations["丙"], ("丙站", 30.20, 107.00))
        self.assertEqual(stations["丙旧"], ("丙旧站", 30.20, 107.00))

    def test_keeps_every_same_named_node_as_a_candidate(self) -> None:
        candidates = self.source.station_candidates()

        # 消歧要的是全部同名候选；first-wins 的 _stations 只留先扫到的那个。
        # 「甲站」在 OSM 里有两个节点（30.0/104.0 与深圳 22.57/114.17），
        # 两个都得进候选表，否则消歧无从挑。
        self.assertEqual(
            sorted(candidates["甲"]),
            sorted([("甲站", 30.0, 104.0), ("甲站", 22.57, 114.17)]),
        )
        # 兜底表仍是 first-wins，用法与改动前一致。
        self.assertEqual(
            self.source.station_coordinates()["甲"], ("甲站", 30.0, 104.0)
        )

    def test_writes_the_station_cache_so_later_runs_skip_the_pbf(self) -> None:
        # 这是「看计划不必先读 1.7GB PBF」的关键：读完 PBF 必须落盘车站坐标。
        cached = builder.load_osm_stations(self.cache_dir)

        self.assertIsNotNone(cached)
        self.assertEqual(cached.stations["甲"], ("甲站", 30.0, 104.0))

    def test_missing_pbf_is_a_clear_error(self) -> None:
        with self.assertRaises(RuntimeError):
            builder.PbfRailSource(self.cache_dir, self.root / "不存在.osm.pbf")


class FakeSource(builder.RailSource):
    """内存数据源：两条并行线路，直线是高铁、绕行线是普速。"""

    name = "fake"

    def __init__(self, cache_dir: Path) -> None:
        super().__init__(cache_dir)
        self.queries: list[tuple[float, float, float, float]] = []
        self.straight = [(30.0 + 0.005 * i, 104.0) for i in range(101)]
        self.detour = [
            *[(30.0 + 0.005 * i, 104.0 + 0.006 * i) for i in range(51)],
            *[(30.25 + 0.005 * i, 104.3 - 0.006 * i) for i in range(51)],
        ]

    def ways(self, bbox):  # type: ignore[override]
        self.queries.append(bbox)
        return [
            builder.CachedWay(True, False, self.straight),
            builder.CachedWay(False, True, self.detour),
        ]


class PlanLegWithSourceTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.cache_dir = Path(self._tmp.name)
        self.source = FakeSource(self.cache_dir)
        self.leg = builder.Leg(
            route_name="测试线",
            from_station="甲站",
            to_station="乙站",
            start=(30.0, 104.0),
            end=(30.5, 104.0),
            mileage_km=None,
            profile=geo.HSR,
        )

    def test_uses_mileage_to_pick_the_longer_parallel_line(self) -> None:
        straight_km = geo.path_length_km(self.source.straight)
        detour_km = geo.path_length_km(self.source.detour)

        near = builder.plan_leg_with_source(self.source, self.leg, 400.0, 0.35)
        far = builder.plan_leg_with_source(
            self.source,
            builder.Leg(**{**self.leg.__dict__, "mileage_km": detour_km}),
            400.0,
            0.35,
        )

        self.assertTrue(near.plan.ok, near.plan.reason)
        self.assertAlmostEqual(near.plan.length_km, straight_km, delta=1.0)
        self.assertTrue(far.plan.ok, far.plan.reason)
        self.assertAlmostEqual(far.plan.length_km, detour_km, delta=1.0)

    def test_fetch_failure_is_reported_not_raised(self) -> None:
        class Broken(FakeSource):
            name = "broken"

            def ways(self, bbox):  # type: ignore[override]
                raise RuntimeError("网络不可达")

        result = builder.plan_leg_with_source(Broken(self.cache_dir), self.leg, 400.0, 0.35)

        self.assertFalse(result.plan.ok)
        self.assertTrue(result.plan.reason.startswith("fetch_failed"), result.plan.reason)

    def test_suspect_coordinate_skips_the_fetch_entirely(self) -> None:
        leg = builder.Leg(**{**self.leg.__dict__, "suspect_reason": "suspect_coordinate"})

        result = builder.plan_leg_with_source(self.source, leg, 400.0, 0.35)

        self.assertFalse(result.plan.ok)
        self.assertEqual(result.plan.reason, "suspect_coordinate")
        # 关键：坐标不可信的段绝不能去取数，否则走廊覆盖半个国家、必然超时。
        self.assertEqual(self.source.queries, [])

    def test_requested_bbox_is_tight_around_the_leg(self) -> None:
        builder.plan_leg_with_source(self.source, self.leg, 400.0, 0.35)

        (south, west, north, east) = self.source.queries[0]
        # 0.5° 长的区段，走廊半宽 13.9km ≈ 0.125° + margin。
        self.assertAlmostEqual(south, 30.0 - 0.145, places=2)
        self.assertAlmostEqual(north, 30.5 + 0.145, places=2)
        self.assertGreater(east, 104.0)
        self.assertLess(north - south, 0.85)
        self.assertLess(east - west, 0.4)
        # 早期版本按 adaptive_padding 取 ±0.6°，高度会是 1.7°。
        self.assertLess(north - south, 1.7 / 2)


class WriteDatabaseTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.out = Path(self._tmp.name) / "rail_tracks.db"

    def _leg(self, mileage=None) -> builder.Leg:
        return builder.Leg(
            route_name="京沪高速线",
            from_station="北京南站",
            to_station="廊坊站",
            start=(39.865, 116.378),
            end=(39.520, 116.700),
            mileage_km=mileage,
            profile=geo.HSR,
        )

    def test_writes_tracks_and_failures_separately(self) -> None:
        ok = builder.LegResult(
            self._leg(60.0),
            geo.LegPlan(
                ok=True,
                polyline=[(39.865, 116.378), (39.7, 116.5), (39.520, 116.700)],
                length_km=58.0,
                mileage_km=60.0,
                mileage_error_km=2.0,
            ),
        )
        failed = builder.LegResult(
            self._leg(None),
            geo.LegPlan(ok=False, reason="snap_failed", mileage_km=None),
        )

        ok_count, failed_count, total_bytes = builder.write_database(
            self.out, [ok, failed], {"source": "fake", "step_m": "400"}
        )

        self.assertEqual((ok_count, failed_count), (1, 1))
        self.assertGreater(total_bytes, 0)

        connection = sqlite3.connect(self.out)
        try:
            row = connection.execute(
                "SELECT route_name, from_station, profile, direction, polyline,"
                " point_count FROM tracks"
            ).fetchone()
            failure = connection.execute("SELECT route_name, reason FROM failures").fetchone()
            meta = dict(connection.execute("SELECT key, value FROM meta"))
        finally:
            connection.close()

        (route_name, from_station, profile, direction, polyline, point_count) = row
        self.assertEqual(route_name, "京沪高速线")
        self.assertEqual(from_station, "北京南站")
        self.assertEqual(profile, geo.HSR)
        # 未分离的段只有一行，direction 留空。
        self.assertEqual(direction, "")
        self.assertEqual(point_count, 3)
        self.assertEqual(failure, ("京沪高速线", "snap_failed"))
        self.assertEqual(meta["source"], "fake")

        # polyline 是 gzip(JSON([[lat,lon], ...]))，App 侧按同样格式解。
        points = json.loads(gzip.decompress(polyline).decode("utf-8"))
        self.assertEqual(points[0], [39.865, 116.378])
        self.assertEqual(len(points), 3)

    def test_writes_up_and_down_rows_for_a_split_leg(self) -> None:
        up = [(39.865, 116.378), (39.7, 116.499), (39.520, 116.700)]
        down = [(39.865, 116.378), (39.7, 116.506), (39.520, 116.700)]
        split = builder.LegResult(
            self._leg(60.0),
            geo.LegPlan(
                ok=True,
                split=True,
                polyline=up,
                length_km=58.0,
                down_polyline=down,
                down_length_km=58.2,
                mileage_km=60.0,
            ),
        )

        builder.write_database(self.out, [split], {"source": "fake"})

        connection = sqlite3.connect(self.out)
        try:
            rows = connection.execute(
                "SELECT direction, polyline, length_km FROM tracks ORDER BY direction"
            ).fetchall()
        finally:
            connection.close()

        self.assertEqual([row[0] for row in rows], ["down", "up"])
        by_direction = {row[0]: row for row in rows}
        self.assertAlmostEqual(by_direction["up"][2], 58.0)
        self.assertAlmostEqual(by_direction["down"][2], 58.2)
        # 两条各自独立编码，端点仍是精确的站点坐标。
        for direction, expected in (("up", up), ("down", down)):
            points = json.loads(gzip.decompress(by_direction[direction][1]).decode("utf-8"))
            self.assertEqual(points, [[lat, lon] for lat, lon in expected])

    def test_rewrites_existing_database_from_scratch(self) -> None:
        self.out.write_bytes(b"not a database")
        builder.write_database(self.out, [], {"source": "fake"})

        connection = sqlite3.connect(self.out)
        try:
            tables = {row[0] for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            )}
        finally:
            connection.close()
        self.assertEqual(tables, {"meta", "tracks", "failures", "stations"})

    def test_encode_polyline_round_trips_and_rounds_coordinates(self) -> None:
        encoded = builder.encode_polyline([(30.123456789, 104.987654321)])

        self.assertEqual(json.loads(gzip.decompress(encoded)), [[30.12346, 104.98765]])

    def test_writes_station_coordinates_for_the_app(self) -> None:
        stations = [("北京南站", 39.865, 116.378), ("廊坊站", 39.520, 116.700)]

        builder.write_database(self.out, [], {"source": "fake"}, stations)

        connection = sqlite3.connect(self.out)
        try:
            rows = sorted(connection.execute(
                "SELECT station_name, latitude, longitude FROM stations"
            ))
        finally:
            connection.close()
        self.assertEqual(
            rows, [("北京南站", 39.865, 116.378), ("廊坊站", 39.520, 116.700)]
        )

    def test_writes_a_null_coordinate_for_a_discarded_station(self) -> None:
        # 被舍去的站要留一行、坐标为 NULL：App 靠这一行知道「别再退回 CSV」。
        stations = [("北京南站", 39.865, 116.378), ("永乐", None, None)]

        builder.write_database(self.out, [], {"source": "fake"}, stations)

        connection = sqlite3.connect(self.out)
        try:
            rows = sorted(
                connection.execute(
                    "SELECT station_name, latitude, longitude FROM stations"
                )
            )
        finally:
            connection.close()
        self.assertEqual(rows, [("北京南站", 39.865, 116.378), ("永乐", None, None)])

    def test_station_table_is_empty_when_none_are_supplied(self) -> None:
        builder.write_database(self.out, [], {"source": "fake"})

        connection = sqlite3.connect(self.out)
        try:
            count = connection.execute("SELECT COUNT(*) FROM stations").fetchone()[0]
        finally:
            connection.close()
        self.assertEqual(count, 0)


class CliTest(unittest.TestCase):
    def _run(self, extra: list[str]) -> tuple[int, str, bool]:
        """跑一次 main（dry run），返回 (退出码, stdout, 输出文件是否被创建)。

        缓存目录指向临时空目录：否则会读到开发机上真实的 osm_stations.json /
        osm_station_fixes.json——站名被真实坐标顶掉、还会打印几百行真实修正，
        段的条数就不再由这个夹具决定。
        """
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            routes_db = root / "routes.db"
            _write_routes_db(routes_db)
            coordinates = root / "coordinates.csv"
            _write_coordinates(
                coordinates,
                [
                    ("北京南站", 39.865, 116.378),
                    ("廊坊站", 39.520, 116.700),
                    ("天津站", 39.100, 117.200),
                    ("宝鸡站", 34.360, 107.150),
                    ("凤州站", 33.940, 106.600),
                ],
            )
            out = root / "out.db"
            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                code = builder.main(
                    [
                        "--routes-db", str(routes_db),
                        "--coordinates", str(coordinates),
                        "--cache-dir", str(root / "cache"),
                        "--out", str(out),
                    ]
                    + extra
                )
            return code, buffer.getvalue(), out.exists()

    def test_dry_run_does_not_touch_the_output_file(self) -> None:
        code, _, out_existed = self._run([])

        self.assertEqual(code, 0)
        self.assertFalse(out_existed)

    def test_limit_truncates_the_legs_actually_reported(self) -> None:
        code, output, _ = self._run(["--limit", "1"])

        self.assertEqual(code, 0)
        # --limit 曾被解析、写进帮助文本，却从未传给 enumerate_legs：整个跑下来一段
        # 都没截断，调试用的短跑实际是全量跑。
        self.assertIn("已按 --limit 截断", output)

    def test_without_limit_reports_every_leg(self) -> None:
        code, output, _ = self._run([])

        self.assertEqual(code, 0)
        self.assertNotIn("已按 --limit 截断", output)


if __name__ == "__main__":
    unittest.main()
