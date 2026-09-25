"""查清「加了 service way 之后反而失败的 101 段」到底为什么失败。

全量对比显示：折线 4089 → 4821、失败 1707 → 975，但其中 833 段是新增的、101 段是
**原本成功、现在失败**的。这 101 段旧误差中位只有 4.5%（25.0/25.0、43.0/43.0 这种
精度），所以它们不是垃圾，是真丢了。

最像的原因：`plan_leg` 只枚举前 6 条最短路（k_paths=6）。站场里的平行股道会把
「同一个走向、差几十米」的走法排成一串，把 6 个名额占满，于是真正与运价里程吻合的
那条走法排在 7 名开外、根本没进候选。若是这个原因，把 k 调大就能把 101 段救回来。

这个探针就量这一件事：对丢失的每一段，分别用 k=6/12/24 跑 `plan_leg`，看救回多少、
救回的质量如何。

    python tools/osm_update/probe_lost_legs.py --old app/assets/db/rail_tracks.db \
        --new tools/.test_out/tracks_service.db
"""

from __future__ import annotations

import argparse
import sqlite3
import statistics
import sys
import time
from pathlib import Path

import build_rail_tracks as builder
import rail_track_geometry as geo


def _tracks(db: Path) -> dict:
    connection = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    try:
        return {
            (row[0], row[1], row[2]): row[3]
            for row in connection.execute(
                "SELECT route_name, from_station, to_station, length_km FROM tracks"
            )
        }
    finally:
        connection.close()


def main(argv: list[str] | None = None) -> int:
    builder._utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--old", type=Path, required=True)
    parser.add_argument("--new", type=Path, required=True)
    parser.add_argument("--routes-db", type=Path, default=builder.DEFAULT_ROUTES_DB)
    parser.add_argument("--coordinates", type=Path, default=builder.DEFAULT_COORDINATES)
    parser.add_argument("--cache-dir", type=Path, default=builder.DEFAULT_CACHE)
    parser.add_argument("--pbf", type=Path, default=builder.DEFAULT_PBF)
    parser.add_argument("--steps", default="6,12,24", help="要试的 k_paths，逗号分隔")
    parser.add_argument("--detail", type=int, default=12)
    args = parser.parse_args(argv)
    step_sizes = [int(value) for value in args.steps.split(",") if value.strip()]

    old_lengths = _tracks(args.old)
    new_keys = _tracks(args.new)
    lost = sorted(set(old_lengths) - set(new_keys))
    if not lost:
        print("没有「原本成功、现在失败」的段。")
        return 0

    stations = builder.load_osm_stations(args.cache_dir)
    index, _ = builder.build_coordinates(args, stations)
    routes = sorted({row[0] for row in lost})
    stats = builder.enumerate_legs(args.routes_db, index, routes)
    by_key = {(leg.route_name, leg.from_station, leg.to_station): leg for leg in stats.legs}

    print(f"丢失 {len(lost)} 段，开始读 PBF……", file=sys.stderr)
    started = time.time()
    source = builder.PbfRailSource(args.cache_dir, args.pbf)
    print(f"  读入用时 {time.time() - started:.0f}s", file=sys.stderr)

    # 走廊数据与 k 无关，取一次就够了。
    corridors: dict = {}
    missing = 0
    for key in lost:
        leg = by_key.get(key)
        if leg is None:
            missing += 1
            continue
        try:
            corridors[key] = (leg, builder.rail_data_for_leg(source, leg))
        except Exception as exc:  # noqa: BLE001 - 诊断脚本，取数失败就当这跳过
            print(f"  取数失败 {key}: {exc}", file=sys.stderr)
            missing += 1
    if missing:
        print(f"  （{missing} 段在枚举里找不到或取数失败，跳过）", file=sys.stderr)

    results: dict = {size: [] for size in step_sizes}
    for index_number, (key, (leg, rail)) in enumerate(corridors.items()):
        line = [f"— {leg.route_name} {leg.from_station} → {leg.to_station}"
                f"（{leg.mileage_km:.0f}km）"] if index_number < args.detail else []
        for size in step_sizes:
            plan = geo.plan_leg(
                leg.start,
                leg.end,
                rail,
                leg.profile,
                mileage_km=leg.mileage_km,
                k_paths=size,
            )
            results[size].append(plan)
            if line:
                detail = (
                    f"{plan.length_km:.1f}km"
                    if plan.ok
                    else (plan.reason or "失败")
                )
                line.append(f"  k={size:<3} {detail}")
        if line:
            # 拿掉里程预算后的最短路：它才是「图里到底还有没有一条像样的路」。
            # 若它已远长于旧库当年拿到的长度，说明变的是吸附点/图，而不是选路。
            corridor = geo.corridor_filter(rail, leg.start, leg.end)
            graph = geo.build_graph(corridor.lines, corridor.preferred)
            projection = geo.Projection((leg.start[0] + leg.end[0]) / 2.0)
            free, _ = geo.search_paths(graph, leg.start, leg.end, projection, k=1)
            free_length = f"{free[0].length_km:.1f}km" if free else "搜不到"
            # _snap_node 会改图，所以吸附距离必须在**新图**上量，且放在最后。
            graph = geo.build_graph(corridor.lines, corridor.preferred)
            _, start_dist = geo._snap_node(graph, leg.start, projection, 5.0)
            graph = geo.build_graph(corridor.lines, corridor.preferred)
            _, end_dist = geo._snap_node(graph, leg.end, projection, 5.0)
            line.append(
                f"  （旧库 {old_lengths[key]:.1f}km、无预算最短路 {free_length}、"
                f"吸附 {start_dist * 1000:.0f}m/{end_dist * 1000:.0f}m）"
            )
            print("\n".join(line) + "\n")

    total = len(corridors)
    print(f"=== 按 k_paths 救回多少（共 {total} 段丢失段）===")
    for size in step_sizes:
        plans = results[size]
        ok = [p for p in plans if p.ok]
        if ok:
            rel = sorted(
                abs(p.length_km - p.mileage_km) / p.mileage_km
                for p in ok
                if p.mileage_km
            )
            quality = (
                f"中位误差 {100 * statistics.median(rel):.2f}%"
                if rel
                else "误差未知"
            )
        else:
            quality = ""
        print(
            f"  k={size:<3} 成功 {len(ok):3d} / {total}"
            f"（{100 * len(ok) / total:.1f}%）  {quality}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
