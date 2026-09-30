"""查清 `mileage_mismatch` 的失败段到底是「里程不对」还是「OSM 拓扑断裂」。

`plan_leg` 把两种完全不同的情况归成同一个 reason：

  1. 找到路了，但长度超过里程的 1.35 倍        → 多半是选错了平行线路或里程有误；
  2. 在里程给的预算内**根本没找到路**          → 多半是 OSM 里两条 way 看着相接、
     其实没共用节点（拓扑断裂），跟里程无关。

两者的修法完全不同，所以这里对每个失败段问三个问题：

  * 把长度上限拿掉后能不能找到路？（能 → 是里程/预算的问题，拓扑是通的）
  * 起点和终点各吸附到哪个连通分量？（不同分量 → 拓扑断裂）
  * 两个分量之间最近差多远？（几十米 → 端点没接上，值得加桥接）

**里程是客运运价里程，不是轨道实长**，所以「长度超里程」这一桶内部还要再分一次：
记下「最短路径长度 / 里程」的比值，看它是刚过阈值（1.35–1.6，多半是运价里程与
实长的正常出入、阈值定紧了）还是成倍（>1.6，多半是走廊里缺了那条更直的线，被迫
绕行）。两者一个调阈值、一个补数据，混在一起看不出该动哪个。

    python tools/osm_update/diagnose_failures.py [--db tools/.test_out/tracks.db]

要读一遍 PBF，所以一次把全部失败段都算完再打印。
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

import build_rail_tracks as builder
import rail_track_geometry as geo


def _load_failures(db: Path) -> list[tuple[str, str, str, str]]:
    connection = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        return [
            (row[0], row[1], row[2], row[3])
            for row in connection.execute(
                "SELECT route_name, from_station, to_station, reason FROM failures"
            )
        ]
    finally:
        connection.close()


def _components(graph: geo.RailGraph) -> list[set]:
    """把图拆成连通分量（无向看待：铁路两个方向都能走）。"""
    seen: set = set()
    components: list[set] = []
    for start in graph.adjacency:
        if start in seen:
            continue
        stack = [start]
        component = set()
        while stack:
            current = stack.pop()
            if current in component:
                continue
            component.add(current)
            for neighbor, _ in graph.adjacency.get(current, ()):
                if neighbor not in component:
                    stack.append(neighbor)
        seen |= component
        components.append(component)
    return components


# 两个分量两两比距离是 O(n·m)。走廊里的分量一般只有几百个点，但万一撞上几千个，
# 纯 Python 的双重循环会卡住。超过这个乘积就等距抽样：断裂点的距离量级是「几十米」
# 还是「几十公里」，抽样完全分得开，不影响结论。
_GAP_PAIR_BUDGET = 4_000_000


def _min_gap_km(
    first: set, second: set, projection: geo.Projection
) -> tuple[float, geo.Coord, geo.Coord]:
    """两个点集之间的最小平面距离（km）及取到它的那对点，必要时等距抽样。"""
    left, right = list(first), list(second)
    if len(left) * len(right) > _GAP_PAIR_BUDGET:
        limit = max(1, int((_GAP_PAIR_BUDGET / max(1, len(right))) ** 0.5))
        stride = max(1, len(left) // limit)
        left = left[::stride]
        stride = max(1, len(right) // limit)
        right = right[::stride]

    best = float("inf")
    closest: tuple[geo.Coord, geo.Coord] = (left[0], right[0])
    for a in left:
        for b in right:
            distance = projection.distance_km(a, b)
            if distance < best:
                best = distance
                closest = (a, b)
    return best, closest[0], closest[1]


def _profile_membership(corridor: geo.RailData) -> dict:
    """坐标 → 落在它上面的 way 是不是「匹配目标 profile」。

    图的节点坐标是 quantize 过的，所以键也要 quantize 才能对上。
    """
    members: dict = {}
    for line, is_preferred in zip(corridor.lines, corridor.preferred):
        for coord in line:
            members.setdefault(geo.quantize(coord), set()).add(bool(is_preferred))
    return members


def _classify_gap(
    graph: geo.RailGraph, members: dict, a: geo.Coord, b: geo.Coord
) -> str:
    """给「相隔最近的那对节点」定性，判断该不该桥接。

    只看距离分不出两种情况，而它们的修法正好相反：

      * 两条 way 视觉上相接、其实没共用节点（中位 17m）→ 桥接就对了；
      * 两条**真正并行**的线路（高铁贴着普速）相距也就几十米 → 桥接会把它们焊死，
        里程消歧就此失效，本来能分开的京沪高铁/京沪铁路会连成一张网。

    区分靠 way 的 profile：图里的 preferred 是按目标 profile 算的，所以一端只属于
    匹配 profile 的 way、另一端只属于不匹配的 way，那就是并行线路的界面。
    再叠一层「两端都是悬空端点（度为 1）」——断口在 way 的两头才是接缝。

    抽样过的分量算出来的不一定是真最近的那对，所以置位 sampled 让汇总能扣掉。
    """
    first, second = members.get(a), members.get(b)
    if not first or not second:
        return "unknown"
    dangling = (
        len(graph.adjacency.get(a, ())) <= 1 and len(graph.adjacency.get(b, ())) <= 1
    )
    if first.isdisjoint(second):
        return "cross_dangling" if dangling else "cross_through"
    return "same_dangling" if dangling else "same_through"


def main(argv: list[str] | None = None) -> int:
    builder._utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__)
    # 默认看调试库；找不到就由调用方显式 --db 指点。相对路径按敲命令的目录算。
    parser.add_argument("--db", type=Path,
                        default=builder.TOOLS_DIR / ".test_out" / "tracks.db")
    parser.add_argument("--routes-db", type=Path, default=builder.DEFAULT_ROUTES_DB)
    parser.add_argument("--coordinates", type=Path, default=builder.DEFAULT_COORDINATES)
    parser.add_argument("--cache-dir", type=Path, default=builder.DEFAULT_CACHE)
    parser.add_argument("--pbf", type=Path, default=builder.DEFAULT_PBF)
    parser.add_argument("--detail", type=int, default=15,
                        help="打印前几个失败段的逐段详情；汇总永远打印全量")
    args = parser.parse_args(argv)

    failures = _load_failures(args.db)
    if not failures:
        print("这个库里没有失败段。")
        return 0

    stations = builder.load_osm_stations(args.cache_dir)
    index, _ = builder.build_coordinates(args, stations)

    routes = sorted({row[0] for row in failures})
    stats = builder.enumerate_legs(args.routes_db, index, routes)
    by_key = {(leg.route_name, leg.from_station, leg.to_station): leg for leg in stats.legs}

    source = builder.PbfRailSource(args.cache_dir, args.pbf)

    print(f"失败段 {len(failures)} 个，开始逐个诊断\n")
    reachable_without_budget = 0
    split_components = 0

    gaps: list[float] = []
    ratios: list[float] = []
    slack_cases: list[tuple[float, float]] = []
    counts = {"budget": 0, "snap": 0, "split": 0, "same_component": 0, "missing": 0}
    kinds: dict = {}

    for index, (route_name, from_station, to_station, reason) in enumerate(failures):
        leg = by_key.get((route_name, from_station, to_station))
        verbose = index < args.detail
        if leg is None:
            counts["missing"] += 1
            if verbose:
                print(f"— {route_name} {from_station} → {to_station}（{reason}）")
                print("  枚举里找不到这个段，跳过\n")
            continue

        rail = builder.rail_data_for_leg(source, leg)
        corridor = geo.corridor_filter(rail, leg.start, leg.end)
        projection = geo.Projection((leg.start[0] + leg.end[0]) / 2.0)

        if verbose:
            print(f"— {route_name} {from_station} → {to_station}（{reason}）")
            print(f"  走廊 way {len(corridor.lines)}、"
                  f"图 {len(geo.build_graph(corridor.lines, corridor.preferred).adjacency)} 节点")

        # 关键一问：拿掉里程预算后还找不到路吗？
        graph = geo.build_graph(corridor.lines, corridor.preferred)
        unbounded, unbounded_reason = geo.search_paths(
            graph, leg.start, leg.end, projection, k=1
        )
        if unbounded:
            counts["budget"] += 1
            if leg.mileage_km and leg.mileage_km > 0:
                ratios.append(unbounded[0].length_km / leg.mileage_km)
                slack_cases.append((leg.mileage_km, unbounded[0].length_km))
            if verbose:
                print(f"  去掉里程预算后找到了路：{unbounded[0].length_km:.1f} km"
                      f"（里程 {leg.mileage_km:.1f} km，"
                      f"{unbounded[0].length_km / leg.mileage_km:.2f} 倍）")
                print("  → 拓扑是通的，问题在里程或选线\n")
            continue

        # _snap_node 会把命中的边拆开插点，所以必须在**新的**图上做，
        # 否则分量会在上一轮调用改过的图上算。
        graph = geo.build_graph(corridor.lines, corridor.preferred)
        start_node, start_dist = geo._snap_node(graph, leg.start, projection, 5.0)
        end_node, end_dist = geo._snap_node(graph, leg.end, projection, 5.0)
        if start_node is None or end_node is None:
            counts["snap"] += 1
            if verbose:
                print(f"  端点没吸附到图上（{unbounded_reason}）："
                      f"起点{'已吸附' if start_node else '未吸附'}、"
                      f"终点{'已吸附' if end_node else '未吸附'}")
                print("  → 走廊里缺这条线的轨道数据\n")
            continue

        components = _components(graph)
        start_component = next((c for c in components if start_node in c), set())
        end_component = next((c for c in components if end_node in c), set())
        if start_component is not end_component:
            counts["split"] += 1
            gap, gap_a, gap_b = _min_gap_km(start_component, end_component, projection)
            gaps.append(gap)
            kind = _classify_gap(graph, _profile_membership(corridor), gap_a, gap_b)
            kinds[kind] = kinds.get(kind, 0) + 1
            if verbose:
                print(f"  {len(components)} 个连通分量；起终点分属不同分量，"
                      f"最近相距 {gap:.3f} km（吸附 {start_dist:.3f}/{end_dist:.3f} km）")
                print(f"  → 拓扑断裂，最近那对是 {kind}\n")
        else:
            counts["same_component"] += 1
            if verbose:
                print(f"  同分量但搜不到路（{unbounded_reason}）"
                      f"——多半是吸附阈值内没有图节点\n")

    total = len(failures)
    print(f"=== 汇总（共 {total} 个失败段）===")
    print(f"  里程/选线问题（去掉预算就能找到路）: {counts['budget']}")
    print(f"  拓扑断裂（起终点不在同一连通分量）: {counts['split']}")
    print(f"  同分量但搜不到路                  : {counts['same_component']}")
    print(f"  端点吸附失败                      : {counts['snap']}")
    print(f"  枚举里找不到                      : {counts['missing']}")

    if gaps:
        import statistics

        gaps.sort()
        print(f"\n=== 拓扑断裂的缺口分布（n={len(gaps)}）===")
        for high, label in (
            (0.05, "≤50m   "),
            (0.2, "≤200m  "),
            (1.0, "≤1km   "),
            (5.0, "≤5km   "),
            (float("inf"), ">5km   "),
        ):
            low = {0.05: 0, 0.2: 0.05, 1.0: 0.2, 5.0: 1.0, float("inf"): 5.0}[high]
            count = sum(1 for g in gaps if low <= g < high)
            print(f"  {label}: {count:5d}  ({100 * count / len(gaps):5.1f}%)")
        print(f"  中位缺口 {statistics.median(gaps):.3f} km")
        bridgeable = sum(1 for g in gaps if g <= 0.1)
        print(f"  缺口 ≤100m（端点桥接就能接上）: {bridgeable}"
              f"  = 全部失败段的 {100 * bridgeable / total:.1f}%")

    if kinds:
        print(f"\n=== 最近那对节点的性质（n={sum(kinds.values())}）===")
        for key, label in (
            ("same_dangling", "同 profile、两端都悬空 → 真接缝，桥接该修的就是它"),
            ("same_through", "同 profile、有一端是过路点 → 可疑，桥接可能改错走向"),
            ("cross_dangling", "跨 profile、两端都悬空 → 并行线路界面，**不能**桥接"),
            ("cross_through", "跨 profile、有过路点 → 并行线路界面，**不能**桥接"),
            ("unknown", "坐标不在走廊 way 上 → 定性不了"),
        ):
            count = kinds.get(key, 0)
            if count:
                print(f"  {label}: {count}")

    if ratios:
        import statistics

        ratios.sort()
        print(f"\n=== 「最短路径 / 运价里程」比值分布（n={len(ratios)}）===")
        for high, label in (
            (1.0, "<1.00  "),
            (1.35, "1.0–1.35"),
            (1.6, "1.35–1.6（阈值刚过）"),
            (2.5, "1.6–2.5 "),
            (float("inf"), ">2.5   "),
        ):
            low = {1.0: 0.0, 1.35: 1.0, 1.6: 1.35, 2.5: 1.6, float("inf"): 2.5}[high]
            count = sum(1 for r in ratios if low <= r < high)
            print(f"  {label}: {count:5d}  ({100 * count / len(ratios):5.1f}%)")
        print(f"  中位比值 {statistics.median(ratios):.2f}"
              f"；运价里程短于实长（比值>1）的占"
              f" {100 * sum(1 for r in ratios if r > 1.0) / len(ratios):.1f}%")
        near = sum(1 for r in ratios if r <= 1.6)
        print(f"  比值 ≤1.6（放宽 max_error_ratio 就能救回）: {near}"
              f"  = 全部失败段的 {100 * near / total:.1f}%")

    if slack_cases:
        # plan_leg 的长度上限给了 mileage*1.35 + 5km 的绝对余量，接受判据却只有
        # 35% 的相对余量——短段因此特别容易栽：2km 的段偏 1km 就是 1.5 倍，可这
        # 1km 里既有运价里程取整的成分，也有站址偏差。这一栏量一下把判据补成
        # max(35%, 绝对余量) 能救回多少。
        print("\n=== 给接受判据加绝对余量能救回多少（当前只有 35% 相对余量）===")
        for slack in (0.0, 1.0, 2.0, 3.0, 5.0):
            rescued = sum(
                1
                for mileage, length in slack_cases
                if abs(length - mileage) <= max(mileage * 0.35, slack)
            )
            print(f"  绝对余量 {slack:.0f}km: 接受 {rescued:5d}"
                  f"  = 全部失败段的 {100 * rescued / total:.1f}%")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
