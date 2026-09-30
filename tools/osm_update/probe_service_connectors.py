"""验一个假设：拓扑断裂是不是因为我们把 `service=yard/siding` 的 way 整条丢掉了。

`_railway_service_excluded` 让 `service in {yard, siding}` 的 way 既不算高铁也不算
普速，于是 `_collect_ways` 只保留 `is_hsr or is_conventional` 的 way 时，它们连图都
进不去。而中国 OSM 里车站咽喉、连接两条正线的渡线经常就标 `service=siding`。
把它们丢掉，图的断口正好落在每个车站的咽喉上——也就是每一段行程的起点和终点。

`diagnose_failures.py` 给出的线索与此吻合：1241 个断裂段里，最近的那对节点有 740 个
「同 profile，但有一端是过路点」，只有 85 个是「两端都悬空」的真接缝。连接线被整条
丢掉，留下的断口自然在正线的过路点上，而不是在 way 的尽头。

这个探针只回答一件事：把这些 way 加回图里，那些断裂段能不能找到路。做法是最小
复现——对同一批段各跑一次 `plan_leg`，一次用现在的口径，一次带上 service way。

    python tools/osm_update/probe_service_connectors.py [--legs 60]

要读两遍 PBF，但两遍都挂了 C++ 过滤器，几十秒的事。
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import build_rail_tracks as builder
import diagnose_failures as diagnosis
import rail_track_geometry as geo


def _way_bbox(coords: list) -> tuple[float, float, float, float]:
    latitudes = [c[0] for c in coords]
    longitudes = [c[1] for c in coords]
    return min(latitudes), min(longitudes), max(latitudes), max(longitudes)


def _bbox_hits(
    first: tuple[float, float, float, float], second: tuple[float, float, float, float]
) -> bool:
    return not (
        first[2] < second[0]
        or first[0] > second[2]
        or first[3] < second[1]
        or first[1] > second[3]
    )


def _scan_pbf(pbf: Path, bboxes: list) -> list:
    """收集与目标 bbox 相交的铁路 way（含 service），返回 [(service, coords)]。

    两遍，跟生产管线同一个套路：一遍 KeyFilter 收 way 的**节点号**，一遍 IdFilter 取
    这些节点的坐标。第一遍读不了 way 引用节点的坐标（那需要 pyosmium 建位置索引，
    正是生产代码要避开的开销），所以 bbox 剪枝只能放到坐标解析之后。
    """
    import osmium

    raw: list = []
    wanted: set = set()

    class Collector(osmium.SimpleHandler):
        def way(self, w: osmium.osm.Way) -> None:
            if w.tags.get("railway") != "rail":
                return
            node_ids = [node.ref for node in w.nodes]
            if len(node_ids) < 2:
                return
            is_hsr, is_conventional = geo.way_flags(w.tags)
            raw.append(
                (
                    str(w.tags.get("service", "")).lower(),
                    is_hsr,
                    is_conventional,
                    node_ids,
                )
            )
            wanted.update(node_ids)

    Collector().apply_file(
        str(pbf), locations=False, filters=[osmium.filter.KeyFilter("railway")]
    )

    locations: dict = {}

    class Nodes(osmium.SimpleHandler):
        def node(self, n: osmium.osm.Node) -> None:
            location = n.location
            if location.valid():
                locations[n.id] = (location.lat, location.lon)

    Nodes().apply_file(
        str(pbf), locations=False, filters=[osmium.filter.IdFilter(wanted)]
    )

    kept: list = []
    for service, is_hsr, is_conventional, node_ids in raw:
        coords = [locations[node_id] for node_id in node_ids if node_id in locations]
        if len(coords) < 2:
            continue
        if not any(_bbox_hits(_way_bbox(coords), target) for target in bboxes):
            continue
        kept.append((service, is_hsr, is_conventional, coords))
    return kept


def main(argv: list[str] | None = None) -> int:
    builder._utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", type=Path, default=builder.DEFAULT_OUT)
    parser.add_argument("--routes-db", type=Path, default=builder.DEFAULT_ROUTES_DB)
    parser.add_argument("--coordinates", type=Path, default=builder.DEFAULT_COORDINATES)
    parser.add_argument("--cache-dir", type=Path, default=builder.DEFAULT_CACHE)
    parser.add_argument("--pbf", type=Path, default=builder.DEFAULT_PBF)
    parser.add_argument("--legs", type=int, default=60, help="抽样多少段来比")
    parser.add_argument("--detail", type=int, default=15)
    parser.add_argument(
        "--service-kinds",
        default="yard,siding",
        help="哪些 service 值算连接线，逗号分隔；用来分别量 yard 和 siding 各值多少",
    )
    args = parser.parse_args(argv)
    kinds = {value.strip().lower() for value in args.service_kinds.split(",") if value.strip()}


    failures = diagnosis._load_failures(args.db)
    if not failures:
        print("这个库里没有失败段。")
        return 0

    stations = builder.load_osm_stations(args.cache_dir)
    index, _ = builder.build_coordinates(args, stations)
    routes = sorted({row[0] for row in failures})
    stats = builder.enumerate_legs(args.routes_db, index, routes)
    by_key = {(leg.route_name, leg.from_station, leg.to_station): leg for leg in stats.legs}

    # 均匀抽样，避免只看到某一条线路的毛病。
    total = len(failures)
    stride = max(1, total // args.legs)
    sample = failures[::stride][: args.legs]

    legs = []
    bboxes = []
    for route_name, from_station, to_station, _reason in sample:
        leg = by_key.get((route_name, from_station, to_station))
        if leg is None or not leg.mileage_km:
            continue
        corridor_km = geo.corridor_km_for(leg.start, leg.end)
        bbox = geo.bbox_for_corridor(leg.start, leg.end, corridor_km)
        legs.append(leg)
        bboxes.append(bbox)

    print(f"抽样 {len(legs)} 段，开始读 PBF……", file=sys.stderr)
    started = time.time()
    resolved = _scan_pbf(args.pbf, bboxes)
    service_ways = sum(1 for service, _, _, _ in resolved if service in kinds)
    print(
        f"  命中 {len(resolved)} 条 way（其中 service∈{sorted(kinds)} {service_ways} 条、"
        f"正线 {len(resolved) - service_ways} 条），用时 {time.time() - started:.0f}s",
        file=sys.stderr,
    )

    outcomes = {"both_ok": 0, "only_service": 0, "both_fail": 0, "regressed": 0}

    for index_number, leg in enumerate(legs):
        corridor_km = geo.corridor_km_for(leg.start, leg.end)
        bbox = geo.bbox_for_corridor(leg.start, leg.end, corridor_km)

        baseline_lines, baseline_preferred = [], []
        service_lines, service_preferred = [], []
        for service, is_hsr, is_conventional, coords in resolved:
            if not _bbox_hits(_way_bbox(coords), bbox):
                continue
            # 基线永远不含任何 service way——不然 --service-kinds 会一并改掉基线，
            # 三次运行比的就不是同一个基准了（这个坑踩过：60% 的增益被算成了 0%）。
            if service in {"yard", "siding"}:
                if service in kinds:
                    # service way 算不上任何 profile，只能当非 preferred 的连接线用。
                    service_lines.append(coords)
                    service_preferred.append(False)
                continue
            baseline_lines.append(coords)
            baseline_preferred.append(
                builder.CachedWay(is_hsr, is_conventional, coords).preferred_for(
                    leg.profile
                )
            )

        with_service = geo.RailData(
            lines=[*baseline_lines, *service_lines],
            preferred=[*baseline_preferred, *service_preferred],
        )
        without = geo.RailData(lines=baseline_lines, preferred=baseline_preferred)

        before = geo.plan_leg(
            leg.start, leg.end, without, leg.profile, mileage_km=leg.mileage_km
        )
        after = geo.plan_leg(
            leg.start, leg.end, with_service, leg.profile, mileage_km=leg.mileage_km
        )

        if after.ok and not before.ok:
            outcomes["only_service"] += 1
        elif after.ok and before.ok:
            outcomes["both_ok"] += 1
        elif before.ok and not after.ok:
            # 加进去反而画错了，这个信号很重要，必须单独数。
            outcomes["regressed"] += 1
        else:
            outcomes["both_fail"] += 1

        if index_number < args.detail:
            print(f"— {leg.route_name} {leg.from_station} → {leg.to_station}"
                  f"（{leg.mileage_km:.0f}km、走廊内 service way {len(service_lines)} 条）")
            print(f"  不带 service: {before.reason or '成功'} "
                  f"{f'{before.length_km:.1f}km' if before.length_km else ''}")
            print(f"  带上 service: {after.reason or '成功'} "
                  f"{f'{after.length_km:.1f}km' if after.length_km else ''}\n")

    print(f"=== 结果（{len(legs)} 段）===")
    print(f"  本来就行、加了也还行          : {outcomes['both_ok']}")
    print(f"  本来断裂、加上 service 才通    : {outcomes['only_service']}")
    print(f"  加了反而从成功变失败          : {outcomes['regressed']}")
    print(f"  加了还是不行                  : {outcomes['both_fail']}")
    if legs:
        print(f"  → 假设成立的话，可救回 {100 * outcomes['only_service'] / len(legs):.1f}% 的抽样段")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
