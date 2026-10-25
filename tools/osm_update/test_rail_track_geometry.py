"""rail_track_geometry 的单元测试（标准库 unittest，无需额外依赖）。

运行：
    cd tools && python -m unittest discover -p "test_*.py" -v
"""

from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

# 同目录平级 import：被 unittest 当包发现时（osm_update.test_xxx）也得能 import 到同目录模块。
sys.path.insert(0, str(Path(__file__).resolve().parent))

import rail_track_geometry as geo  # noqa: E402


# --------------------------------------------------------------------------
# 名称归一化：必须与 Dart 端 _stationKeys / _resolveRouteName 行为一致
# --------------------------------------------------------------------------


class StationKeyTest(unittest.TestCase):
    def test_strips_station_suffix_and_parens(self) -> None:
        self.assertEqual(geo.station_key("北京站"), "北京")
        self.assertEqual(geo.station_key("北京"), "北京")
        self.assertEqual(geo.station_key("济南西站 (中国铁路)"), "济南西")
        self.assertEqual(geo.station_key("上海虹桥站"), "上海虹桥")

    def test_keeps_intermediate_annotations(self) -> None:
        # 括号不在结尾时不去掉，与 Dart 的 replaceFirst(RegExp(r'\s*\([^)]*\)\s*$')) 一致。
        self.assertEqual(geo.station_key("（香港）红磡站"), "(香港)红磡")

    def test_normalizes_full_width_parens_and_whitespace(self) -> None:
        self.assertEqual(geo.station_key(" 天津 南站 "), "天津南")

    def test_keeps_line_junction_names(self) -> None:
        # 线路所没有「站」后缀，归一化后原样保留。
        self.assertEqual(geo.station_key("京津所"), "京津所")

    def test_empty_input(self) -> None:
        self.assertEqual(geo.station_key(""), "")


class RouteKeyTest(unittest.TestCase):
    def test_strips_line_suffix(self) -> None:
        self.assertEqual(geo.route_key("京沪高速线"), "京沪高速")
        self.assertEqual(geo.route_key("京沪高速铁路"), "京沪高速")
        # 用户填写的名字与 routes.db 的名字归一到同一个键。
        self.assertEqual(geo.route_key("京沪高速铁路"), geo.route_key("京沪高速线"))

    def test_keeps_name_without_suffix(self) -> None:
        self.assertEqual(geo.route_key("北京直通线"), "北京直通")

    def test_track_key_combines_normalized_parts(self) -> None:
        self.assertEqual(
            geo.track_key("京沪高速线", "北京南站", "廊坊站"),
            "京沪高速|北京南|廊坊",
        )


class LineMatchKeyTest(unittest.TestCase):
    """普速侧拿 route_name 去比 OSM 的 way name，用的就是这把键。

    与 `route_key` 是**两个**函数：`route_key` 是折线主键，动一个字全库 key 全变。
    """

    def test_strips_the_segment_suffix_after_the_line_name(self) -> None:
        self.assertEqual(geo.line_match_key("宁蓉线宁渝段"), "宁蓉")
        self.assertEqual(geo.line_match_key("宁西线西合段"), "宁西")
        self.assertEqual(geo.line_match_key("成昆铁路元昆段"), "成昆")

    def test_strips_a_trailing_segment_word_when_there_is_no_line_suffix(self) -> None:
        self.assertEqual(geo.line_match_key("沪宁段"), "沪宁")

    def test_keeps_line_and_railway_names_apart(self) -> None:
        # 京广线 与 京广高速线 是两条不同的物理线路，绝不能归一成同一个键。
        self.assertEqual(geo.line_match_key("京广线"), "京广")
        self.assertEqual(geo.line_match_key("京广高速线"), "京广高速")
        self.assertNotEqual(geo.line_match_key("京广线"), geo.line_match_key("京广高速线"))

    def test_aliases_map_hsr_spellings_onto_one_key(self) -> None:
        for name in ("京广高铁", "京广客专", "京广客运专线"):
            self.assertEqual(geo.line_match_key(name), "京广高速", name)

    def test_route_key_is_untouched_by_the_new_normalization(self) -> None:
        # 「宁蓉线宁渝段」尾字是「段」，route_key 按设计原样不剥——折线主键依赖它。
        self.assertEqual(geo.route_key("宁蓉线宁渝段"), "宁蓉线宁渝段")
        self.assertEqual(geo.route_key("京广高铁"), "京广高铁")

    def test_normalizes_whitespace_and_parenthetical_suffixes(self) -> None:
        self.assertEqual(geo.line_match_key(" 沪 蓉 线 (上行)"), "沪蓉")
        self.assertEqual(geo.line_match_key("沪蓉线（上行）"), "沪蓉")

    def test_empty_input(self) -> None:
        self.assertEqual(geo.line_match_key(""), "")
        self.assertEqual(geo.line_match_key("   "), "")


class LineBaseKeyTest(unittest.TestCase):
    """基本名：匹配键再去掉速度等级词，用来容忍新线路库删掉等级词的改名。

    它**故意**不区分速度等级，所以只能用在严格匹配落空之后——见
    `build_rail_tracks.line_matches`。
    """

    def test_drops_class_words_from_the_db_name(self) -> None:
        # 新线路库的写法：等级词被删掉。
        self.assertEqual(geo.line_base_key("沪宁沿江"), "沪宁沿江")
        self.assertEqual(geo.line_base_key("京包张包段"), "京包张包")
        self.assertEqual(geo.line_base_key("京港合安段"), "京港合安")

    def test_drops_class_words_from_the_osm_name(self) -> None:
        self.assertEqual(geo.line_base_key("沪宁沿江高速线"), "沪宁沿江")
        self.assertEqual(geo.line_base_key("京包客专线张包段"), "京包")
        self.assertEqual(geo.line_base_key("京广客运专线"), "京广")

    def test_meets_in_the_middle(self) -> None:
        self.assertEqual(
            geo.line_base_key("沪宁沿江"), geo.line_base_key("沪宁沿江高速线")
        )
        self.assertEqual(geo.line_base_key("沪宁沿江"), geo.line_base_key("沪宁沿江高铁"))

    def test_collapses_hsr_and_conventional_on_purpose(self) -> None:
        # 这正是不能拿基本名当匹配键的原因：两者在基本名上是同一条线。
        self.assertEqual(geo.line_base_key("京广线"), geo.line_base_key("京广高速线"))

    def test_empty_input(self) -> None:
        self.assertEqual(geo.line_base_key(""), "")
        self.assertEqual(geo.line_base_key("   "), "")


class ProfileTest(unittest.TestCase):
    def test_infers_hsr_from_route_name(self) -> None:
        for name in ("京沪高速线", "京津城际线", "安六客专线", "包银高铁"):
            self.assertEqual(geo.infer_profile(name), geo.HSR, name)

    def test_infers_conventional_from_route_name(self) -> None:
        for name in ("宝成线", "滨洲线", "北同蒲线", "安庆联络线"):
            self.assertEqual(geo.infer_profile(name), geo.CONVENTIONAL, name)

    def test_matches_profile_uses_osm_tags(self) -> None:
        hsr = {"railway": "rail", "maxspeed": "350"}
        slow = {"railway": "rail", "maxspeed": "120"}
        untagged = {"railway": "rail"}
        siding = {"railway": "rail", "service": "siding"}

        self.assertTrue(geo.matches_profile(hsr, geo.HSR))
        self.assertFalse(geo.matches_profile(slow, geo.HSR))
        self.assertFalse(geo.matches_profile(untagged, geo.HSR))

        self.assertTrue(geo.matches_profile(slow, geo.CONVENTIONAL))
        # maxspeed 缺失时按普速处理，这与 TrainTrack 的行为一致。
        self.assertTrue(geo.matches_profile(untagged, geo.CONVENTIONAL))
        self.assertFalse(geo.matches_profile(hsr, geo.CONVENTIONAL))

        self.assertTrue(geo.matches_profile(untagged, geo.ALL))
        self.assertFalse(geo.matches_profile(siding, geo.ALL))

    def test_is_service_rail_spots_yards_and_sidings(self) -> None:
        for service in ("siding", "yard", "Siding", " YARD "):
            tags = {"railway": "rail", "service": service}
            self.assertTrue(geo.is_service_rail(tags), service)

    def test_is_service_rail_only_accepts_real_rail_tracks(self) -> None:
        # service 值再像，不是 railway=rail 就不是正线系统的连接线。
        self.assertFalse(geo.is_service_rail({"railway": "tram", "service": "siding"}))
        self.assertFalse(geo.is_service_rail({"railway": "subway"}))
        # 没有 service 或 service 是别的值，都不是站线。
        self.assertFalse(geo.is_service_rail({"railway": "rail"}))
        self.assertFalse(geo.is_service_rail({"railway": "rail", "service": "spur"}))
        self.assertFalse(geo.is_service_rail({}))

    def test_service_rail_is_excluded_from_both_profiles(self) -> None:
        # 连接线要留，但它不能冒充正线：两个 profile 都不该认它。
        siding = {"railway": "rail", "service": "siding"}
        is_hsr, is_conventional = geo.way_flags(siding)
        self.assertEqual((is_hsr, is_conventional), (False, False))
        self.assertTrue(geo.is_service_rail(siding))


# --------------------------------------------------------------------------
# 几何辅助
# --------------------------------------------------------------------------


class GeometryTest(unittest.TestCase):
    def test_haversine_one_degree_of_latitude(self) -> None:
        self.assertAlmostEqual(
            geo.haversine_km((30.0, 104.0), (31.0, 104.0)), 111.19, places=1
        )

    def test_resample_path_spacing(self) -> None:
        start, end = (30.0, 104.0), (30.5, 104.0)
        points = geo.resample_path([start, end], 10_000)

        self.assertEqual(points[0], start)
        self.assertEqual(points[-1], end)
        self.assertGreater(len(points), 2)
        # 总长不是步长的整数倍，因此最后一段是余量，短于一个步长；其余必须精确等距。
        for i in range(len(points) - 2):
            self.assertAlmostEqual(
                geo.haversine_km(points[i], points[i + 1]), 10.0, places=6
            )
        self.assertLessEqual(geo.haversine_km(points[-2], points[-1]), 10.0)

    def test_resample_path_respects_first_offset(self) -> None:
        start, end = (30.0, 104.0), (30.5, 104.0)
        points = geo.resample_path([start, end], 10_000, first_offset_m=3_000)

        self.assertAlmostEqual(geo.haversine_km(points[0], points[1]), 3.0, places=6)
        self.assertAlmostEqual(geo.haversine_km(points[1], points[2]), 10.0, places=6)

    def test_project_to_segment_clamps_to_endpoints(self) -> None:
        a, b = (30.0, 104.0), (30.5, 104.0)
        proj, dist = geo.project_to_segment((30.25, 104.2), a, b)

        self.assertAlmostEqual(proj[0], 30.25, places=4)
        self.assertAlmostEqual(proj[1], 104.0, places=4)
        self.assertAlmostEqual(dist, 19.2, places=0)

    def test_corridor_grows_with_leg_length_then_saturates(self) -> None:
        self.assertAlmostEqual(geo.corridor_km_for((30.0, 104.0), (30.05, 104.0)), 10.0, places=3)
        self.assertAlmostEqual(geo.corridor_km_for((30.0, 104.0), (30.5, 104.0)), 13.9, places=1)
        self.assertAlmostEqual(geo.corridor_km_for((30.0, 104.0), (35.0, 104.0)), 45.0, places=3)

    def test_bbox_for_corridor_contains_every_point_of_the_corridor(self) -> None:
        a, b = (30.0, 104.0), (30.4, 104.3)
        corridor_km = 15.0
        bbox = geo.bbox_for_corridor(a, b, corridor_km)

        # 走廊内任意一点都必须落在 bbox 里，否则取数会漏掉轨道。
        for i in range(41):
            t = i / 40.0
            point = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
            for bearing in range(0, 360, 15):
                rad = math.radians(bearing)
                lat = point[0] + corridor_km * math.cos(rad) / geo.KM_PER_DEGREE
                lon = point[1] + corridor_km * math.sin(rad) / (
                    geo.KM_PER_DEGREE * math.cos(math.radians(point[0]))
                )
                self.assertLessEqual(geo.haversine_km(point, (lat, lon)), corridor_km + 0.2)
                self.assertGreaterEqual(lat, bbox[0])
                self.assertLessEqual(lat, bbox[2])
                self.assertGreaterEqual(lon, bbox[1])
                self.assertLessEqual(lon, bbox[3])

    def test_bbox_for_corridor_padding_matches_corridor_width_in_km(self) -> None:
        corridor_km = 15.0
        pads: list[float] = []
        for lat in (20.2, 40.2, 50.2):
            bbox = geo.bbox_for_corridor((lat - 0.2, 104.0), (lat + 0.2, 104.0), corridor_km)
            margin = geo.CORRIDOR_MARGIN_DEG

            lat_span_km = ((bbox[2] - bbox[0]) / 2 - margin - 0.2) * geo.KM_PER_DEGREE
            lon_pad_deg = (bbox[3] - bbox[1]) / 2 - margin
            lon_span_km = lon_pad_deg * geo.KM_PER_DEGREE * math.cos(math.radians(lat))

            self.assertAlmostEqual(lat_span_km, corridor_km, places=3)
            self.assertAlmostEqual(lon_span_km, corridor_km, places=3)
            pads.append(lon_pad_deg)

        # 1 度经度在高纬度更短，因此同样的走廊宽度需要更大的经度度数。
        self.assertLess(pads[0], pads[1])
        self.assertLess(pads[1], pads[2])

    def test_suspect_leg_accepts_a_plausible_leg(self) -> None:
        # 里程略长于直线（真实铁路必然如此），是正常段。
        self.assertIsNone(
            geo.suspect_leg_reason((30.0, 104.0), (30.5, 104.0), 60.0)
        )

    def test_suspect_leg_rejects_coordinate_far_off_the_line(self) -> None:
        # 里程 3km、直线 3188km：coordinates.csv 把站名匹配到了外省同名站。
        self.assertEqual(
            geo.suspect_leg_reason((22.5, 114.0), (45.8, 126.6), 3.0),
            "suspect_coordinate",
        )

    def test_suspect_leg_tolerates_a_long_detour(self) -> None:
        # 山区线路里程可达直线的 2 倍，仍在 3 倍容差内，不能误杀。
        self.assertIsNone(
            geo.suspect_leg_reason((30.0, 104.0), (30.5, 104.0), 110.0)
        )

    def test_suspect_leg_uses_absolute_cap_without_mileage(self) -> None:
        self.assertIsNone(geo.suspect_leg_reason((30.0, 104.0), (34.0, 104.0), None))
        self.assertEqual(
            geo.suspect_leg_reason((30.0, 104.0), (40.0, 104.0), None),
            "suspect_coordinate",
        )

    def test_suspect_leg_ignores_zero_mileage(self) -> None:
        # mileage 为 0 表示「无约束」（库里数据缺失），不能当成比值 0 而全部误杀。
        self.assertIsNone(geo.suspect_leg_reason((30.0, 104.0), (30.2, 104.0), 0.0))


# --------------------------------------------------------------------------
# 寻路
# --------------------------------------------------------------------------


def _straight_way() -> list[tuple[float, float]]:
    """A→B 的直线轨道，逐点密集化以模拟 OSM way 的节点密度。"""
    return [(30.0 + 0.005 * i, 104.0) for i in range(101)]


def _detour_way() -> list[tuple[float, float]]:
    """绕到东侧的替代线路，明显更长。"""
    outbound = [(30.0 + 0.005 * i, 104.0 + 0.006 * i) for i in range(51)]
    inbound = [(30.25 + 0.005 * i, 104.3 - 0.006 * i) for i in range(51)]
    return [*outbound, *inbound]


class PathSearchTest(unittest.TestCase):
    def setUp(self) -> None:
        self.start = (30.0, 104.0)
        self.end = (30.5, 104.0)
        self.projection = geo.Projection(30.25)

    def _search(
        self, rail: geo.RailData, start=None, end=None, **kwargs
    ) -> tuple[list[geo.PathCandidate], str | None]:
        graph = geo.build_graph(rail.lines, rail.preferred)
        return geo.search_paths(
            graph,
            start or self.start,
            end or self.end,
            self.projection,
            **kwargs,
        )

    def test_finds_path_along_a_single_way(self) -> None:
        rail = geo.RailData(lines=[_straight_way()], preferred=[True])

        candidates, reason = self._search(rail)

        self.assertIsNone(reason)
        self.assertEqual(len(candidates), 1)
        self.assertAlmostEqual(candidates[0].length_km, 55.6, delta=1.0)
        self.assertEqual(candidates[0].preferred_ratio, 1.0)

    def test_reports_snap_failure_when_too_far(self) -> None:
        line = [(30.0 + 0.005 * i, 108.0) for i in range(101)]  # 几百公里外
        rail = geo.RailData(lines=[line], preferred=[True])

        candidates, reason = self._search(rail)

        self.assertEqual(candidates, [])
        self.assertEqual(reason, "snap_failed")

    def test_snaps_to_segment_when_no_node_is_near_enough(self) -> None:
        # 极稀疏的 way：只有两端有节点，站点落在中段，需要投影拆段接入。
        rail = geo.RailData(lines=[[(30.0, 104.0), (30.5, 104.0)]], preferred=[True])

        candidates, reason = self._search(
            rail, start=(30.25, 104.0), end=(30.4, 104.0)
        )

        self.assertIsNone(reason)
        self.assertTrue(candidates)
        self.assertAlmostEqual(candidates[0].length_km, 16.7, delta=1.0)

    def test_falls_back_when_the_nearest_node_sits_on_an_isolated_spur(self) -> None:
        # 站场里除了正线还有一条与它不通的孤立侧线，而站坐标离侧线更近。
        # 只看最近节点时整段「找不到路」——全量生成里 101 段就是这样从成功变失败的。
        spur = [(30.0005, 104.0005), (30.0005, 104.0100)]
        rail = geo.RailData(lines=[_straight_way(), spur], preferred=[True, False])

        candidates, reason = self._search(rail, start=(30.0005, 104.0005))

        self.assertIsNone(reason)
        self.assertTrue(candidates)
        self.assertAlmostEqual(candidates[0].length_km, 55.6, delta=1.0)
        # 接在主线的节点上，而不是那条侧线上。
        self.assertEqual(candidates[0].path[0], (30.0, 104.0))

    def test_also_offers_the_target_lines_snap_when_the_other_is_nearer(self) -> None:
        # 站坐标更贴近并行的那条线（离主线 555m、离它 111m），主锚点因此落在**别人的
        # 线**上。这时目标 profile 那条线的锚点也要算出来一起摆着，否则这一段只剩
        # 「沿别人的线走」一种解法，画出来就是辆车在别人的轨道上。
        parallel = [(30.0 + 0.005 * i, 104.005) for i in range(101)]
        rail = geo.RailData(lines=[_straight_way(), parallel], preferred=[True, False])

        candidates, reason = self._search(
            rail,
            start=(30.0, 104.006),
            end=(30.5, 104.006),
            extra_snaps=2,
        )

        self.assertIsNone(reason)
        # 主锚点在另一条线上：最短的那条是别人家的线（preferred 0.0，55.8km）。
        self.assertEqual(candidates[0].preferred_ratio, 0.0)
        self.assertAlmostEqual(candidates[0].length_km, 55.8, delta=1.0)
        # 目标 profile 那条线（主线 55.6km + 两端各 0.555km 的吸附空隙）也摆上来了，
        # 评分才有得选。
        on_target = [item for item in candidates if item.preferred_ratio == 1.0]
        self.assertTrue(on_target)
        self.assertAlmostEqual(
            min(item.length_km for item in on_target), 56.7, delta=1.0
        )

    def test_skips_the_extra_snaps_when_the_primary_looks_right(self) -> None:
        # 主锚点既贴里程又全在目标 profile 的边上，就不该再多算——每个成功的段都多付
        # 一次 Yen 枚举不值，这也是「不会把本来对的段改坏」的前提。
        rail = geo.RailData(lines=[_straight_way()], preferred=[True])

        candidates, reason = self._search(rail, extra_snaps=2)

        self.assertIsNone(reason)
        self.assertEqual(len(candidates), 1)

    def test_retries_the_snaps_when_the_nearest_node_sits_on_a_long_loop(self) -> None:
        """最近节点落在环线/死端上时，几何判据要触发备用吸附。

        站坐标离环线起点 5m、离正线起点 333m。主吸附对只能沿环线绕一大圈，
        直线距离 55.6km、环线 150km；没有里程预算之后，只有「最短候选超过直线
        1.2 倍」这条纯几何判据能把正线那条直路摆进候选。实测成灌线 犀浦→红光镇
        （16.94 vs 3.65km）、珠机城际线 珠海长隆→井湾（15.81 vs 6.19km）同形。
        """
        straight = [(30.0, 104.003), (30.5, 104.003)]
        loop = [
            (30.0, 104.00005),
            (30.0, 104.5),
            (30.2, 104.5),
            (30.2, 104.00005),
            (30.5, 104.00005),
            (30.5, 104.003),
        ]
        rail = geo.RailData(lines=[straight, loop], preferred=[True, True])

        candidates, reason = self._search(
            rail,
            start=(30.0, 104.0),
            end=(30.5, 104.003),
            extra_snaps=2,
        )

        self.assertIsNone(reason)
        lengths = sorted(item.length_km for item in candidates)
        # 正线那条（55.6km + 333m 吸附空隙）必须出现在候选里，并且是最短的。
        self.assertAlmostEqual(lengths[0], 55.9, delta=1.0)
        self.assertGreater(max(lengths), 140.0)

    def test_widens_the_snap_pool_when_one_end_is_crowded_with_throat_nodes(self) -> None:
        """一端节点密集时，交叉积取前 N 对会把这一端的纵深挤掉。

        复现达成线 保平所→成都：站坐标落在站场咽喉里，最近的十几个节点全在一条
        环线上，真正接正路的节点排在第 13 位。只按「吸附距离之和」取前几对时，
        每一对都从咽喉进环线（约 152km，直线 55.6km）；把每个起始节点都和最近的
        终点节点配一遍，第 13 位那个（145m 外）才带着 55.7km 的直路进来。实测
        原库这一段画成 14.9km 的环线，直线只有 6.3km、里程 6km。
        """
        throat = [(30.0, 104.0005 + 0.0001 * i) for i in range(12)]
        loop = [
            *throat,
            (30.0, 104.5),
            (30.5, 104.5),
            (30.5, 104.0),
        ]
        mainline = [(30.0, 104.002), (30.5, 104.0)]
        rail = geo.RailData(lines=[loop, mainline], preferred=[False, True])

        candidates, reason = self._search(
            rail,
            start=(30.0, 104.0005),
            end=(30.5, 104.0),
            extra_snaps=2,
        )

        self.assertIsNone(reason)
        lengths = sorted(item.length_km for item in candidates)
        self.assertAlmostEqual(lengths[0], 55.7, delta=1.0)
        self.assertGreater(max(lengths), 140.0)

    def test_keeps_trying_alternative_snaps_until_the_geometry_makes_sense(self) -> None:
        """主吸附对不通时，换过去的第一对也可能是环线，要接着往下试。

        起点最近的节点在这条与正线不通的短侧线上，所以主吸附对直接失败。备用对按
        吸附距离排序，第一对落在环线上（132km），第二对才是正线（55.6km）。收手太早
        就会把环线当成唯一解。实测广深港高速线 虎门→光明城 的主吸附对就是不通的，
        换过去的第一条是 53.29km 的绕行线，正解 37.19km。
        """
        spur = [(30.0, 104.00002), (30.0, 104.01)]
        straight = [(30.0, 104.002), (30.5, 104.002)]
        loop = [
            (30.0, 104.0005),
            (30.0, 104.4),
            (30.2, 104.4),
            (30.2, 104.0005),
            (30.5, 104.0005),
            (30.5, 104.002),
        ]
        rail = geo.RailData(
            lines=[spur, straight, loop], preferred=[False, True, True]
        )

        candidates, reason = self._search(
            rail, start=(30.0, 104.0), end=(30.5, 104.002)
        )

        self.assertIsNone(reason)
        lengths = sorted(item.length_km for item in candidates)
        self.assertAlmostEqual(lengths[0], 55.8, delta=1.0)
        self.assertGreater(max(lengths), 120.0)

    def test_picks_the_target_lines_path_over_a_nearer_other_line(self) -> None:
        """复现真实故障的形状：锚点落在另一条线上，于是只能绕远。

        宝成线 昭化→江油 实测就是如此：站坐标离西成客专的江油节点 140m、离宝成自己
        233m，锚到客专后唯一走得通的是「先沿宝成到广元、再上客专往南」151km，而宝成
        自己 136km 的那条就在旁边——只按最短会选到绕行的那条。

        这里用同样的拓扑：主线（preferred）直连；另一条线（非 preferred）从同一端出发
        绕东侧一大圈到终点附近，终点坐标离它的端点更近，两条线的终点节点互不相通。
        修法不是让吸附去猜哪条线是自己的（那样会把「另一条线更近」的段一律改锚，实测
        全网 216 段反而变差），而是把两种锚法的候选合并、按贴线程度与长度一起评。
        """
        mainline = _straight_way()  # (30.0,104.0) → (30.5,104.0)，55.6km
        bypass = [  # 同一端出发、绕东侧 4.8km 再往南、最后向西拐回，64.7km
            (30.0, 104.0),
            (30.0, 104.05),
            (30.5, 104.05),
            (30.5, 104.004),
        ]
        rail = geo.RailData(
            lines=[mainline, bypass], preferred=[True, False]
        )

        plan = geo.plan_leg(
            (30.0, 104.0),
            (30.5, 104.0033),
            rail,
            geo.CONVENTIONAL,
        )

        self.assertTrue(plan.ok, plan.reason)
        # 取主线那条（55.6km、ratio 1.0），而不是绕过那条（64.7km、ratio 0.0）。
        self.assertAlmostEqual(plan.length_km, 55.6, delta=1.0)
        self.assertEqual(plan.preferred_ratio, 1.0)

    def test_reports_no_path_when_no_candidate_pair_connects(self) -> None:
        # 起点只够得着孤立侧线、终点在另一条孤立线上：换哪对吸附点都不通。
        spur = [(30.0005, 104.0005), (30.0005, 104.0100)]
        island = [(30.5, 104.5), (30.5, 104.6)]
        rail = geo.RailData(
            lines=[_straight_way(), spur, island], preferred=[True, False, False]
        )

        candidates, reason = self._search(
            rail, start=(30.0005, 104.0005), end=(30.5, 104.5)
        )

        self.assertEqual(candidates, [])
        self.assertEqual(reason, "no_path")

    def test_enumerates_parallel_lines_in_length_order(self) -> None:
        # 同一对站点之间有两条线路：Yen 必须两条都能给出，否则里程无从消歧。
        rail = geo.RailData(
            lines=[_straight_way(), _detour_way()], preferred=[True, False]
        )

        candidates, reason = self._search(rail, k=6)

        self.assertIsNone(reason)
        self.assertGreaterEqual(len(candidates), 2)
        lengths = [candidate.length_km for candidate in candidates]
        self.assertEqual(lengths, sorted(lengths))
        self.assertAlmostEqual(lengths[0], 55.6, delta=1.0)
        self.assertAlmostEqual(lengths[1], 80.1, delta=1.0)
        # preferred_ratio 要能区分高铁线与普速线，作为长度相近时的取舍依据。
        self.assertEqual(candidates[0].preferred_ratio, 1.0)
        self.assertEqual(candidates[1].preferred_ratio, 0.0)

    def test_respects_max_length_budget(self) -> None:
        rail = geo.RailData(
            lines=[_straight_way(), _detour_way()], preferred=[True, False]
        )

        candidates, reason = self._search(rail, k=6, max_length_km=60.0)

        self.assertIsNone(reason)
        self.assertEqual(len(candidates), 1)
        self.assertAlmostEqual(candidates[0].length_km, 55.6, delta=1.0)


# --------------------------------------------------------------------------
# 折线拆段（哪几条线、各多少公里）
# --------------------------------------------------------------------------


class LineRunsTest(unittest.TestCase):
    def setUp(self) -> None:
        # 一条直线上四个节点，三个 way 首尾相接（共点节点在图上自然连通）。
        self.c0 = (30.0, 104.0)
        self.c1 = (30.0, 104.1)
        self.c2 = (30.0, 104.2)
        self.c3 = (30.0, 104.3)

    def _graph(self, names: list[str | None]):
        lines = [
            [self.c0, self.c1],
            [self.c1, self.c2],
            [self.c2, self.c3],
        ]
        return geo.build_graph(lines, [True, True, True], names)

    def test_keeps_the_switch_and_does_not_merge_the_two_ends(self) -> None:
        # 京广→沪蓉→京广：同名的首尾两段隔着别的线，绝不能跨着合并——那会把「在
        # 哪儿换的线」抹掉，而这正是这张表存在的理由。
        graph = self._graph(["京广线", "沪蓉线", "京广线"])

        runs = geo.line_runs([self.c0, self.c1, self.c2, self.c3], graph)

        self.assertEqual([name for name, _ in runs], ["京广线", "沪蓉线", "京广线"])

    def test_merges_adjacent_same_named_segments(self) -> None:
        graph = self._graph(["京广线", "沪蓉线", "沪蓉线"])

        runs = geo.line_runs([self.c0, self.c1, self.c2, self.c3], graph)

        self.assertEqual([name for name, _ in runs], ["京广线", "沪蓉线"])
        _, second_km = runs[1]
        self.assertAlmostEqual(
            second_km, geo.haversine_km(self.c1, self.c3), delta=1e-5
        )

    def test_unnamed_way_gets_the_sentinel_label(self) -> None:
        graph = self._graph(["京广线", None, "京广线"])

        runs = geo.line_runs([self.c0, self.c1, self.c2, self.c3], graph)

        self.assertEqual([name for name, _ in runs], ["京广线", geo.UNNAMED_LINE, "京广线"])

    def test_unknown_edges_are_reported_as_unnamed_not_dropped(self) -> None:
        # 路径上出现图里没有的边（理论上不该有）时宁可记为「未命名」，也别把里程吞掉。
        graph = self._graph(["京广线", "京广线", "京广线"])

        runs = geo.line_runs([self.c0, (30.05, 104.05), self.c1], graph)

        self.assertEqual([name for name, _ in runs], [geo.UNNAMED_LINE])
        self.assertAlmostEqual(
            runs[0][1], geo.path_length_km([self.c0, (30.05, 104.05), self.c1]), places=6
        )

    def test_split_edge_keeps_its_way_attribution(self) -> None:
        # 稀疏 way 被站坐标切段接入后，两条新半边必须还认得出原来是哪条线。
        graph = geo.build_graph([[self.c0, self.c3]], [True], ["京广线"])
        projection = geo.Projection(30.0)
        off_line = (30.002, 104.1)  # 离正线约 0.22km，阈值内、投影点落在两节点之间

        node, distance = geo._snap_node(graph, off_line, projection, 0.25)

        self.assertIsNotNone(node)
        self.assertGreater(distance, 0.0)
        self.assertNotIn(self.c3, [neighbor for neighbor, _ in graph.adjacency[self.c0]])
        runs = geo.line_runs([self.c0, node, self.c3], graph)
        self.assertEqual([name for name, _ in runs], ["京广线"])

    def test_runs_cover_the_whole_path(self) -> None:
        graph = self._graph(["京广线", "沪蓉线", "京广线"])
        path = [self.c0, self.c1, self.c2, self.c3]

        runs = geo.line_runs(path, graph)

        self.assertAlmostEqual(
            sum(km for _, km in runs), geo.path_length_km(path), places=6
        )

    def test_empty_path(self) -> None:
        self.assertEqual(geo.line_runs([], self._graph(["京广线"] * 3)), [])


# --------------------------------------------------------------------------
# 名字对不上的普速腿：额外吸附兜底必须还能救场
# --------------------------------------------------------------------------


class ExtraSnapWithoutProfileTest(unittest.TestCase):
    """偏好集为空的普速腿也必须吃得到额外吸附兜底。

    回归护栏：为省掉「ratio 恒 < 阈值」带来的无谓枚举，曾用
    `if not graph.preferred_edges: return []` 把整个兜底挡在门外——本意只针对 ratio
    那条判据，结果把**里程误差**那条判据一起废了。而名字对不上的腿恰恰只剩误差这一条
    线索（ratio 恒为 0）。实测 新靖线新海段 盐城→东台：主吸附对所在分量里两点之间只有
    一条 82.27km 的绕行路（运价 63km，误差 19.27），挪几百米换一对锚点就有 61.86km 的
    正路（误差 1.14）；护栏一挡，这段就从「准」变成「差 19km」，全国约 30 段从误差
    <2km 劣化到 >2km。
    """

    def setUp(self) -> None:
        self.start = (30.0, 104.0)
        self.end = (30.0, 104.3)
        self.projection = geo.Projection(30.0)
        # 三段拼成一个连通图：绕行侧、直行侧、以及在终点附近把两侧接起来的一小截。
        # 起点站最近的锚点落在绕行侧，稍远 0.44km 处才有直行侧的锚点。
        self.lines = [
            [(30.0, 104.0), (29.9, 104.0), (29.9, 104.3), (30.0, 104.3)],
            [(30.004, 104.0), (30.004, 104.3)],
            [(30.0, 104.3), (30.004, 104.3)],
        ]
        self.preferred = [False, False, False]

    def _graph(self) -> geo.RailGraph:
        return geo.build_graph(self.lines, self.preferred)

    def test_primary_pair_really_is_the_detour(self) -> None:
        # 前提校验：主吸附对（最近的两个锚点）之间只有那条绕行路，否则本用例没有意义。
        graph = self._graph()
        start_node, start_dist = geo._snap_node(graph, self.start, self.projection, 1.0)
        end_node, end_dist = geo._snap_node(graph, self.end, self.projection, 1.0)
        primary = geo._plan_attempt(
            graph, self.projection, start_node, start_dist, end_node, end_dist,
            k=5, max_length_km=None,
        )

        self.assertTrue(primary)
        self.assertGreater(min(item.length_km for item in primary), 40.0)

    def test_empty_preference_set_still_gets_extra_snaps(self) -> None:
        graph = self._graph()
        self.assertFalse(graph.preferred_edges)  # 前提：一条偏好边都没有

        start_node, start_dist = geo._snap_node(graph, self.start, self.projection, 1.0)
        end_node, end_dist = geo._snap_node(graph, self.end, self.projection, 1.0)
        primary = geo._plan_attempt(
            graph, self.projection, start_node, start_dist, end_node, end_dist,
            k=5, max_length_km=None,
        )
        detour_km = min(item.length_km for item in primary)

        extra = geo._extra_snap_candidates(
            graph,
            self.start,
            self.end,
            self.projection,
            1.0,
            primary,
            k=5,
            max_length_km=None,
            extra_snaps=8,
            skip=(start_node, end_node),
        )

        self.assertTrue(extra, "偏好集为空时额外吸附不该被整个挡掉")
        self.assertLess(min(item.length_km for item in extra), detour_km - 1.0)


# --------------------------------------------------------------------------
# 登乘跳：站场与目标正线拓扑断开时的跨分量吸附
# --------------------------------------------------------------------------


def _parallel_named_lines():
    """站场稠密的普速线 + 0.4km 外并行的目标正线，两套几何互不共点。

    普速线的节点密到 25m 一个，于是「离站最近的 16 个节点」全被它占满、正线节点一个
    也进不去——这正是广州北的实测情形（121m 半径内全是咽喉股道），也正是旧的
    `_extra_snap_candidates` 兜底失效的原因。只有登乘跳能救。
    """
    lat_offset = 0.0036  # ≈0.4km
    step = 0.00025  # ≈24m
    count = int(0.3 / step) + 1
    conventional = [(30.0, 104.0 + step * i) for i in range(count)]
    target = [(30.0 + lat_offset, 104.0 + step * i) for i in range(count)]
    return conventional, target


def _half_preferred_detour():
    """主吸附对走得通、但只有约七成压在偏好线上的「绕行线」。

    对应京广高铁 广州北→广州南 的形态：站坐标吸附在普速站场的线上（非偏好），两端
    同分量、路是通的，但那条走法借道另一条也带 highspeed 标签的线，整段 ratio 刚过
    0.5 却远不到 0.9——于是旧的 0.5 门槛被压过去，登乘跳一次都不触发。

    三截首尾共点拼成一条：非偏好段、偏好段、非偏好段。两端锚点都落在非偏好段上，
    与实测一致（广州北吸附在京广线上，离京广高速线 417m）。
    """
    step = 0.00025  # ≈24m
    count = 1201
    first, second = 180, 1020  # 偏好段占 (1020-180)/1200 = 70%
    yard_a = [(30.0, 104.0 + step * i) for i in range(first + 1)]
    fast_mid = [(30.0, 104.0 + step * i) for i in range(first, second + 1)]
    yard_b = [(30.0, 104.0 + step * i) for i in range(second, count)]
    return yard_a, fast_mid, yard_b


class JumpSnapTest(unittest.TestCase):
    def setUp(self) -> None:
        self.start = (30.0, 104.0)
        self.end = (30.0, 104.3)
        self.projection = geo.Projection(30.0)
        self.conventional, self.target = _parallel_named_lines()
        self.rail = geo.RailData(
            lines=[self.conventional, self.target],
            preferred=[False, True],
            names=["宁西线", "沪蓉线"],
        )

    def _search(self, rail=None, **kwargs):
        rail = rail or self.rail
        graph = geo.build_graph(rail.lines, rail.preferred, rail.names_padded())
        return geo.search_paths(graph, self.start, self.end, self.projection, **kwargs)

    def _detour_rail(self) -> geo.RailData:
        """一段能走通、但只有七成压在偏好线上的绕行线 + 0.4km 外的目标正线。"""
        yard_a, fast_mid, yard_b = _half_preferred_detour()
        return geo.RailData(
            lines=[yard_a, fast_mid, yard_b, self.target],
            preferred=[False, True, False, True],
            names=["京广线", "南广线", "京广线", "京广高速线"],
        )

    def test_jumps_onto_the_target_line_when_the_yard_crowds_out_its_nodes(self) -> None:
        candidates, reason = self._search()

        self.assertIsNone(reason)
        jumped = [item for item in candidates if item.board_jump_km > 0]
        self.assertTrue(jumped, "没有产生任何登乘跳候选")
        self.assertEqual(max(item.preferred_ratio for item in jumped), 1.0)

    def test_plan_lands_on_the_target_line_and_records_the_jump(self) -> None:
        target_km = geo.path_length_km(self.target)

        plan = geo.plan_leg(
            self.start,
            self.end,
            self.rail,
            geo.CONVENTIONAL,
        )

        self.assertTrue(plan.ok, plan.reason)
        self.assertEqual(plan.line_runs[0][0], "沪蓉线")
        # 两端各跳 ~0.4km，折线长度里含这两段直线。
        self.assertAlmostEqual(plan.board_jump_km, 0.8, delta=0.05)
        self.assertAlmostEqual(plan.length_km, target_km + plan.board_jump_km, delta=0.05)

    def test_no_jump_without_a_preference_set(self) -> None:
        # 偏好集为空 = 没有信号可跳，也不能拿 preferred 边去建池子（那正是 D1 之后
        # 每个 name-miss 的普速腿都会走的路径，不拦住就是全量重算）。
        rail = geo.RailData(
            lines=[self.conventional, self.target],
            preferred=[False, False],
            names=["宁西线", "沪蓉线"],
        )

        candidates, reason = self._search(rail)

        self.assertIsNone(reason)
        self.assertEqual([item for item in candidates if item.board_jump_km > 0], [])

    def test_no_jump_when_the_station_sits_on_the_target_line(self) -> None:
        # 站上本来就有同分量的目标线节点：主吸附的 ratio 必然达标，不该再跳。
        rail = geo.RailData(lines=[self.target], preferred=[True], names=["沪蓉线"])

        candidates, reason = self._search(rail)

        self.assertIsNone(reason)
        self.assertTrue(candidates)
        self.assertEqual([item for item in candidates if item.board_jump_km > 0], [])
        self.assertEqual(candidates[0].preferred_ratio, 1.0)

    def test_a_half_preferred_detour_does_not_block_the_jump(self) -> None:
        # 「通了、但只有七成压在偏好线上」不能当成答对了——那正是京广高铁 广州北→广州南
        # 被画到绕行线上的原因（ratio 0.5004 压过旧门槛 0.5，跳线永不触发）。
        rail = self._detour_rail()

        candidates, reason = self._search(rail)

        self.assertIsNone(reason)
        # 前提：主对确实走得通，且它的 ratio 落在「过半但远不到 0.9」这个区间。
        best_plain = max(
            item.preferred_ratio for item in candidates if item.board_jump_km == 0
        )
        self.assertGreater(best_plain, geo.EXTRA_SNAP_PROFILE_FLOOR)
        self.assertLess(best_plain, geo.JUMP_PROFILE_FLOOR)
        # 结论：跳过那道门槛，登乘跳仍然被放行，并且拿得到贴满目标线的那条。
        jumped = [item for item in candidates if item.board_jump_km > 0]
        self.assertTrue(jumped, "过半偏好不该被当成答对了")
        self.assertEqual(max(item.preferred_ratio for item in jumped), 1.0)

    def test_plan_prefers_the_jumped_target_line_over_the_half_preferred_detour(
        self,
    ) -> None:
        rail = self._detour_rail()
        target_km = geo.path_length_km(self.target)

        plan = geo.plan_leg(self.start, self.end, rail, geo.CONVENTIONAL)

        self.assertTrue(plan.ok, plan.reason)
        self.assertEqual(plan.line_runs[0][0], "京广高速线")
        self.assertGreater(plan.preferred_ratio, geo.JUMP_PROFILE_FLOOR)

    def test_no_jump_beyond_the_radius(self) -> None:
        # 目标线在 0.4km 外，半径收到 0.2km 就够不着了。
        candidates, reason = self._search(jump_radius_km=0.2)

        self.assertIsNone(reason)
        self.assertEqual([item for item in candidates if item.board_jump_km > 0], [])

    def test_radius_zero_disables_the_jump(self) -> None:
        # 这是一条回滚杠杆：不动代码、只把这个参数置 0 就能退回老行为。
        candidates, reason = self._search(jump_radius_km=0.0)

        self.assertIsNone(reason)
        self.assertEqual([item for item in candidates if item.board_jump_km > 0], [])


# --------------------------------------------------------------------------
# 按线路名选路：本功能相对 TrainTrack 纯最短路的核心增益
# --------------------------------------------------------------------------


class LineNameChoiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.start = (30.0, 104.0)
        self.end = (30.5, 104.0)
        self.straight = _straight_way()
        self.detour = _detour_way()
        # 直线在目标线上，绕行线不是。
        self.rail = geo.RailData(
            lines=[self.straight, self.detour], preferred=[True, False]
        )
        self.straight_km = geo.path_length_km(self.straight)
        self.detour_km = geo.path_length_km(self.detour)

    def test_geometry_lengths_are_well_separated(self) -> None:
        # 前提：两条候选线路长度差异足够大，消歧才有意义。
        self.assertAlmostEqual(self.straight_km, 55.6, delta=1.0)
        self.assertAlmostEqual(self.detour_km, 80.1, delta=1.0)

    def test_picks_the_on_line_candidate_over_a_shorter_other_line(self) -> None:
        # 直线也贴线、绕行线不贴线，代价函数把绕行线按离线里程加重，选直的那条。
        plan = geo.plan_leg(self.start, self.end, self.rail, geo.HSR)

        self.assertTrue(plan.ok, plan.reason)
        self.assertAlmostEqual(plan.length_km, self.straight_km, delta=1.0)
        self.assertEqual(plan.preferred_ratio, 1.0)

    def test_mileage_no_longer_selects_the_parallel_line(self) -> None:
        # 里程指向绕行线时，选路也不动摇：里程只记录、不参与选择。
        plan = geo.plan_leg(
            self.start, self.end, self.rail, geo.HSR, mileage_km=self.detour_km
        )

        self.assertTrue(plan.ok, plan.reason)
        self.assertAlmostEqual(plan.length_km, self.straight_km, delta=1.0)
        self.assertEqual(plan.preferred_ratio, 1.0)
        # 误差如实记录，供查库时核对里程表本身。
        self.assertGreater(plan.mileage_error_km, 20)

    def test_mileage_far_off_does_not_reject_the_leg(self) -> None:
        plan = geo.plan_leg(
            self.start, self.end, self.rail, geo.HSR, mileage_km=1.0
        )

        self.assertTrue(plan.ok, plan.reason)
        self.assertAlmostEqual(plan.length_km, self.straight_km, delta=1.0)
        self.assertGreater(plan.mileage_error_ratio, 1.0)

    def test_without_mileage_records_no_error(self) -> None:
        plan = geo.plan_leg(self.start, self.end, self.rail, geo.HSR)

        self.assertTrue(plan.ok, plan.reason)
        self.assertAlmostEqual(plan.length_km, self.straight_km, delta=1.0)
        self.assertIsNone(plan.mileage_error_km)


class OffNamePenaltyTest(unittest.TestCase):
    """代价函数：离线里程按 OFF_NAME_PENALTY 折成长度，短但走错线的候选会输。"""

    def test_prefers_a_slightly_longer_on_line_path_over_an_off_line_shortcut(self) -> None:
        start, end = (30.0, 104.0), (30.5, 104.0)
        # 目标线：比直线长 4km 的弧线；捷径：直线，但整段不贴线。
        on_line = [(30.0, 104.0), (30.25, 104.08), (30.5, 104.0)]
        shortcut = [(30.0, 104.0), (30.5, 104.0)]
        on_line_km = geo.path_length_km(on_line)
        shortcut_km = geo.path_length_km(shortcut)
        self.assertGreater(on_line_km, shortcut_km)
        self.assertLess(on_line_km - shortcut_km, geo.OFF_NAME_PENALTY * shortcut_km)

        rail = geo.RailData(lines=[shortcut, on_line], preferred=[False, True])
        plan = geo.plan_leg(start, end, rail, geo.CONVENTIONAL)

        self.assertTrue(plan.ok, plan.reason)
        self.assertEqual(plan.preferred_ratio, 1.0)
        self.assertAlmostEqual(plan.length_km, on_line_km, delta=0.5)


class MileageRecordingTest(unittest.TestCase):
    """短腿的运价里程只是名义值：以前它会把段判失败，现在只记录误差。"""

    def setUp(self) -> None:
        self.start = (30.0, 104.0)
        # 0.00144° ≈ 0.16km，10 段共 1.6km：模拟「里程 1.0km、轨道实长 1.6km」的情形。
        self.short = [(30.0 + 0.00144 * i, 104.0) for i in range(11)]
        self.end = self.short[-1]
        self.rail = geo.RailData(lines=[self.short], preferred=[True])

    def test_accepts_a_short_leg_whose_track_is_longer_than_its_tariff_mileage(self) -> None:
        plan = geo.plan_leg(
            self.start, self.end, self.rail, geo.CONVENTIONAL, mileage_km=1.0
        )

        self.assertTrue(plan.ok, plan.reason)
        # 相对误差 60%：现在只写进诊断列，不再据此判失败。
        self.assertGreater(plan.mileage_error_ratio, 0.35)
        self.assertAlmostEqual(plan.mileage_error_km, 0.6, delta=0.1)

    def test_rejects_a_leg_whose_endpoints_snap_to_one_node(self) -> None:
        # 两站都在同一条 way 的同一个节点附近（相距 0.56km）：吸附后「路径」只有那个
        # 节点，长度全是吸附空隙、几何上是个点。画出来只有一个点，所以必须判失败、
        # 让 App 回退直线——这条与里程无关。
        line = [(30.0, 104.0), (30.2, 104.0)]
        rail = geo.RailData(lines=[line], preferred=[True])

        plan = geo.plan_leg(
            (30.0, 104.0), (30.005, 104.0), rail, geo.CONVENTIONAL, mileage_km=0.56
        )

        self.assertFalse(plan.ok)

    def test_single_node_candidate_is_what_gets_filtered(self) -> None:
        # 上一条的前提：`search_paths` 确实会给出这种 1 节点候选，过滤是 `plan_leg`
        # 的责任，不是 Yen 的。
        line = [(30.0, 104.0), (30.2, 104.0)]
        rail = geo.RailData(lines=[line], preferred=[True])
        graph = geo.build_graph(rail.lines, rail.preferred)

        candidates, reason = geo.search_paths(
            graph, (30.0, 104.0), (30.005, 104.0), geo.Projection(30.0), k=6
        )

        self.assertIsNone(reason)
        self.assertEqual([len(item.path) for item in candidates], [1])
        self.assertAlmostEqual(candidates[0].length_km, 0.56, delta=0.05)


# --------------------------------------------------------------------------
# 绕路护栏：客里表站坐标失真导致的绕大圈，宁可不画
# --------------------------------------------------------------------------


def _switchback_way() -> list[tuple[float, float]]:
    """绕到东侧很远再折返的线路，实长约为起终点直线距离的 7 倍。"""
    return [(30.0, 104.0), (30.25, 106.0), (30.5, 104.0)]


class DetourGuardTest(unittest.TestCase):
    def setUp(self) -> None:
        self.start = (30.0, 104.0)
        self.end = (30.5, 104.0)
        self.way = _switchback_way()
        self.rail = geo.RailData(lines=[self.way], preferred=[True])
        self.length = geo.path_length_km(self.way)

    def test_circuitous_leg_is_rejected(self) -> None:
        plan = geo.plan_leg(
            self.start,
            self.end,
            self.rail,
            geo.CONVENTIONAL,
        )

        self.assertFalse(plan.ok)
        self.assertEqual(plan.reason, "circuitous")
        self.assertAlmostEqual(plan.length_km, self.length, delta=0.1)

    def test_the_ratio_is_the_only_thing_rejecting_it(self) -> None:
        plan = geo.plan_leg(
            self.start,
            self.end,
            self.rail,
            geo.CONVENTIONAL,
            detour_ratio=10.0,
        )

        self.assertTrue(plan.ok, plan.reason)

    def test_a_long_but_real_mountain_route_is_kept(self) -> None:
        # 1.44 倍的绕行是真盘山线路的常态，不该被护栏误伤。
        detour = _detour_way()
        rail = geo.RailData(lines=[detour], preferred=[True])

        plan = geo.plan_leg(
            self.start,
            self.end,
            rail,
            geo.CONVENTIONAL,
        )

        self.assertTrue(plan.ok, plan.reason)


# --------------------------------------------------------------------------
# 输出形态
# --------------------------------------------------------------------------


class PlanOutputTest(unittest.TestCase):
    def test_endpoints_are_exact_station_coordinates(self) -> None:
        short_start, short_end = (30.0, 104.0), (30.2, 104.0)
        line = [(30.0 + 0.005 * i, 104.0 + 0.0002) for i in range(41)]
        rail = geo.RailData(lines=[line], preferred=[True])

        plan = geo.plan_leg(short_start, short_end, rail, geo.HSR)

        self.assertTrue(plan.ok, plan.reason)
        # 端点必须精确等于站点坐标，否则 App 侧相邻区段无法拼接。
        self.assertEqual(
            plan.polyline[0], (round(short_start[0], 6), round(short_start[1], 6))
        )
        self.assertEqual(
            plan.polyline[-1], (round(short_end[0], 6), round(short_end[1], 6))
        )

    def test_polyline_is_resampled_and_coordinates_are_rounded(self) -> None:
        short_start, short_end = (30.0, 104.0), (30.3, 104.0)
        line = [(30.0 + 0.003 * i, 104.0) for i in range(101)]
        rail = geo.RailData(lines=[line], preferred=[True])

        plan = geo.plan_leg(short_start, short_end, rail, geo.HSR, step_m=5_000)

        self.assertTrue(plan.ok, plan.reason)
        self.assertGreater(len(plan.polyline), 3)
        for lat, lon in plan.polyline:
            self.assertEqual(lat, round(lat, 5))
            self.assertEqual(lon, round(lon, 5))
        for i in range(len(plan.polyline) - 1):
            self.assertLessEqual(
                geo.haversine_km(plan.polyline[i], plan.polyline[i + 1]), 8.0
            )

    def test_empty_rail_data_fails_fast(self) -> None:
        plan = geo.plan_leg((30.0, 104.0), (30.5, 104.0), geo.RailData(), geo.HSR)
        self.assertFalse(plan.ok)
        self.assertEqual(plan.reason, "no_rail_data")

    def test_corridor_filter_keeps_parallel_lines_and_drops_far_ones(self) -> None:
        near = _straight_way()
        far = [(30.0 + 0.005 * i, 106.0) for i in range(101)]  # 约 190km 外
        rail = geo.RailData(lines=[near, far], preferred=[True, True])

        filtered = geo.corridor_filter(rail, (30.0, 104.0), (30.5, 104.0))

        self.assertEqual(len(filtered.lines), 1)
        self.assertEqual(filtered.lines[0], near)


if __name__ == "__main__":
    unittest.main()
