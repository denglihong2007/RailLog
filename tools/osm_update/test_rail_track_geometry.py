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
            mileage_km=56.0,
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

        candidates, reason = self._search(rail, mileage_km=56.0, extra_snaps=2)

        self.assertIsNone(reason)
        self.assertEqual(len(candidates), 1)

    def test_picks_the_target_lines_path_over_a_nearer_other_line(self) -> None:
        """复现真实故障的形状：锚点落在另一条线上，于是只能绕远。

        宝成线 昭化→江油 实测就是如此：站坐标离西成客专的江油节点 140m、离宝成自己
        233m，锚到客专后唯一走得通的是「先沿宝成到广元、再上客专往南」151km，而宝成
        自己 136km 的那条就在旁边——里程 135km 对这种偏差毫无办法（35% 容差里）。

        这里用同样的拓扑：主线（preferred）直连；另一条线（非 preferred）从同一端出发
        绕东侧一大圈到终点附近，终点坐标离它的端点更近，两条线的终点节点互不相通。
        修法不是让吸附去猜哪条线是自己的（那样会把「另一条线更近」的段一律改锚，实测
        全网 216 段反而变差），而是把两种锚法的候选合并、由里程误差加 preferred 一起评。
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
            mileage_km=58.0,
        )

        self.assertTrue(plan.ok, plan.reason)
        # 取主线那条（55.6km，误差 2.4km），而不是绕过那条（64.7km，误差 6.7km）。
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
# 里程约束消歧：本功能相对 TrainTrack 纯最短路的核心增益
# --------------------------------------------------------------------------


class MileageDisambiguationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.start = (30.0, 104.0)
        self.end = (30.5, 104.0)
        self.straight = _straight_way()
        self.detour = _detour_way()
        # 直线是高铁（有 maxspeed），绕行线是普速。
        self.rail_hsr = geo.RailData(
            lines=[self.straight, self.detour], preferred=[True, False]
        )
        self.straight_km = geo.path_length_km(self.straight)
        self.detour_km = geo.path_length_km(self.detour)

    def test_geometry_lengths_are_well_separated(self) -> None:
        # 前提：两条候选线路长度差异足够大，消歧才有意义。
        self.assertAlmostEqual(self.straight_km, 55.6, delta=1.0)
        self.assertAlmostEqual(self.detour_km, 80.1, delta=1.0)

    def test_matching_mileage_selects_each_parallel_line(self) -> None:
        straight_plan = geo.plan_leg(
            self.start,
            self.end,
            self.rail_hsr,
            geo.HSR,
            mileage_km=self.straight_km,
        )
        detour_plan = geo.plan_leg(
            self.start,
            self.end,
            self.rail_hsr,
            geo.HSR,
            mileage_km=self.detour_km,
        )

        self.assertTrue(straight_plan.ok, straight_plan.reason)
        self.assertTrue(detour_plan.ok, detour_plan.reason)
        self.assertAlmostEqual(straight_plan.length_km, self.straight_km, delta=1.0)
        self.assertAlmostEqual(detour_plan.length_km, self.detour_km, delta=1.0)
        # 几何最短路永远是那条直线；只有里程能把绕行线选出来。
        self.assertGreater(detour_plan.length_km, straight_plan.length_km + 20)

    def test_mileage_does_not_override_a_clearly_matching_short_line(self) -> None:
        # 里程指向直线时不应被 preferred_ratio 拽到绕行线上。
        plan = geo.plan_leg(
            self.start, self.end, self.rail_hsr, geo.HSR, mileage_km=self.straight_km
        )

        self.assertTrue(plan.ok, plan.reason)
        self.assertEqual(plan.preferred_ratio, 1.0)
        self.assertLessEqual(plan.mileage_error_ratio, 0.05)

    def test_without_mileage_falls_back_to_geometry(self) -> None:
        # 里程缺失时只能信几何，取最短；同长度才看 profile。
        plan = geo.plan_leg(self.start, self.end, self.rail_hsr, geo.HSR)

        self.assertTrue(plan.ok, plan.reason)
        self.assertAlmostEqual(plan.length_km, self.straight_km, delta=1.0)
        self.assertIsNone(plan.mileage_error_km)

    def test_rejects_leg_when_no_candidate_matches_mileage(self) -> None:
        plan = geo.plan_leg(
            self.start,
            self.end,
            self.rail_hsr,
            geo.HSR,
            mileage_km=self.straight_km * 3,
            max_error_ratio=0.35,
        )

        self.assertFalse(plan.ok)
        self.assertEqual(plan.reason, "mileage_mismatch")
        self.assertGreater(plan.mileage_error_ratio, 0.35)

    def test_rejects_leg_when_mileage_is_far_below_any_route(self) -> None:
        # 里程小到长度上限之内根本没有路径，同样算里程不匹配。
        plan = geo.plan_leg(self.start, self.end, self.rail_hsr, geo.HSR, mileage_km=1.0)

        self.assertFalse(plan.ok)
        self.assertEqual(plan.reason, "mileage_mismatch")


class ShortLegSlackTest(unittest.TestCase):
    """短腿的绝对余量：运价里程对线路所/联络线只是名义值，别把折线判掉。

    余量同时会放进一类「一节点路径」（两端吸附到同一节点），那不是一个折线，
    所以在同一个判据里一起挡掉——见下面 `test_rejects_a_leg_whose_endpoints_...`。
    """

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
        # 相对误差 60% 远超 35%：接受的唯一理由是绝对余量。
        self.assertGreater(plan.mileage_error_ratio, 0.35)
        self.assertLessEqual(plan.mileage_error_km, geo.DEFAULT_ERROR_SLACK_KM)

    def test_rejects_the_same_leg_without_the_slack(self) -> None:
        plan = geo.plan_leg(
            self.start,
            self.end,
            self.rail,
            geo.CONVENTIONAL,
            mileage_km=1.0,
            error_slack_km=0.0,
        )

        self.assertFalse(plan.ok)
        self.assertEqual(plan.reason, "mileage_mismatch")

    def test_rejects_a_leg_whose_endpoints_snap_to_one_node(self) -> None:
        # 两站都在同一条 way 的同一个节点附近（相距 0.56km）：吸附后「路径」只有那个
        # 节点，长度全是吸附空隙、几何上是个点。里程几乎为 0 的误差会让它被接受，但
        # 画出来只有一个点，所以必须判失败、让 App 回退直线。
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

    def test_slack_is_a_floor_not_an_allowance_on_top(self) -> None:
        # 55.6km 的线、里程 39.7km：相对误差 40% 刚过阈值，绝对误差 15.9km 远超余量。
        # 余量只该在里程足够小时接管判据，不该把长腿的阈值放大成 35%+2km。
        long_line = _straight_way()
        rail = geo.RailData(lines=[long_line], preferred=[True])

        plan = geo.plan_leg(
            (30.0, 104.0),
            (30.5, 104.0),
            rail,
            geo.HSR,
            mileage_km=geo.path_length_km(long_line) / 1.4,
        )

        self.assertFalse(plan.ok)
        self.assertEqual(plan.reason, "mileage_mismatch")


# --------------------------------------------------------------------------
# 上下行分离：OSM 里画成两条分开的轨道时，别把上下行画成同一条线
# --------------------------------------------------------------------------

_SPLIT_LAT0 = 30.0
_METERS_PER_LON_DEGREE = 111_000.0 * math.cos(math.radians(_SPLIT_LAT0))


def _parallel_tracks(separation_m: float) -> list[list[tuple[float, float]]]:
    """A→B 之间上下行两条平行轨道，两端各有渡线连通（现实里的站端咽喉）。

    行走方向 A→B 朝北，因此按左行规则上行线在西侧（lon 104.0 一侧）、下行线在东侧。
    """
    offset = separation_m / _METERS_PER_LON_DEGREE
    up = [(30.0 + 0.005 * i, 104.0) for i in range(101)]
    down = [(30.0 + 0.005 * i, 104.0 + offset) for i in range(101)]
    throat_a = [(30.0, 104.0), (30.0, 104.0 + offset)]
    throat_b = [(30.5, 104.0 + offset), (30.5, 104.0)]
    return [up, down, throat_a, throat_b]


class TrackSplitTest(unittest.TestCase):
    def setUp(self) -> None:
        self.start = (30.0, 104.0)
        self.end = (30.5, 104.0)
        # 上行线贴着站点走（lon 104.0），全长约 55.6km，就用它当里程。
        self.mileage = 55.6

    def _plan(
        self, separation_m: float, mileage_km: float | None = None, **kwargs
    ) -> geo.LegPlan:
        lines = _parallel_tracks(separation_m)
        rail = geo.RailData(lines=lines, preferred=[True] * len(lines))
        return geo.plan_leg(
            self.start,
            self.end,
            rail,
            geo.CONVENTIONAL,
            mileage_km=mileage_km if mileage_km is not None else self.mileage,
            step_m=0,
            **kwargs,
        )

    def test_separated_tracks_produce_both_lines(self) -> None:
        plan = self._plan(300.0)

        self.assertTrue(plan.ok, plan.reason)
        self.assertTrue(plan.split)
        self.assertTrue(plan.down_polyline)
        # 上行线在行走方向的左手边——A→B 朝北，左手边即西侧，lon 更小。
        mid = len(plan.polyline) // 2
        down_mid = len(plan.down_polyline) // 2
        self.assertLess(plan.polyline[mid][1], plan.down_polyline[down_mid][1])
        self.assertAlmostEqual(
            plan.down_polyline[down_mid][1] - plan.polyline[mid][1],
            300.0 / _METERS_PER_LON_DEGREE,
            places=5,
        )

    def test_both_lines_run_from_start_to_end(self) -> None:
        plan = self._plan(300.0)

        # 两条都要按站点顺序出发、到达，否则 App 侧拼不上相邻区段。
        for polyline in (plan.polyline, plan.down_polyline):
            self.assertEqual(polyline[0], (round(self.start[0], 6), 104.0))
            self.assertEqual(polyline[-1], (round(self.end[0], 6), 104.0))

    def test_tracks_drawn_together_are_not_split(self) -> None:
        # 20m 间距在 OSM 里就是画在一起的一条线，没有分离可言。
        plan = self._plan(20.0)

        self.assertTrue(plan.ok, plan.reason)
        self.assertFalse(plan.split)
        self.assertEqual(plan.down_polyline, [])

    def test_lines_further_apart_than_the_cap_are_a_different_route(self) -> None:
        # 3km 之外不是同一走廊的上下行，而是另一条线路，不能当上下行拆开。
        plan = self._plan(3_000.0)

        self.assertTrue(plan.ok, plan.reason)
        self.assertFalse(plan.split)

    def test_parallel_route_of_different_length_is_not_split(self) -> None:
        # 长度差很大的并行线（新老线、普速与高铁）与里程桩只对得上一条，
        # 不该被当成上下行拆开。
        lines = [
            [(30.0 + 0.005 * i, 104.0) for i in range(101)],
            [(30.0 + 0.005 * i, 104.003) for i in range(101)],  # 约 290m 外的并行线
        ]
        rail = geo.RailData(lines=lines, preferred=[True, True])

        plan = geo.plan_leg(
            self.start, self.end, rail, geo.CONVENTIONAL, mileage_km=70.0, step_m=0
        )

        self.assertTrue(plan.ok, plan.reason)
        self.assertFalse(plan.split)

    def test_no_split_without_a_mileage_to_check_against(self) -> None:
        # 里程 0/缺失时没有「两条都贴近里程」这回事，只能按几何取最短那条。
        plan = self._plan(300.0, mileage_km=0.0)

        self.assertTrue(plan.ok, plan.reason)
        self.assertFalse(plan.split)


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
            mileage_km=self.length,
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
            mileage_km=self.length,
            detour_ratio=10.0,
        )

        self.assertTrue(plan.ok, plan.reason)
        self.assertFalse(plan.split)

    def test_a_long_but_real_mountain_route_is_kept(self) -> None:
        # 1.44 倍的绕行是真盘山线路的常态，不该被护栏误伤。
        detour = _detour_way()
        rail = geo.RailData(lines=[detour], preferred=[True])

        plan = geo.plan_leg(
            self.start,
            self.end,
            rail,
            geo.CONVENTIONAL,
            mileage_km=geo.path_length_km(detour),
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
