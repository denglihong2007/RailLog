"""量「线路名 → OSM way 名」的匹配率：偏好集为空的段有哪些。

只读，不写任何文件。用途：

1. 给「偏好集以线路名为准」一个实际影响的定量——名字对不上的段只按里程判定，
   这份清单就是「哪些段没有偏好信号」。
2. 将来某条线又被画错时的入口：先在清单里找它，再决定是补别名还是查 OSM。

匹配是三档递进的（见 `build_rail_tracks.line_matches`）：严格同名 → 去掉速度等级词
后同名 → way 的基本名是线路基本名的前缀。第 2、3 档命中说明两个库的命名分叉了，
逐条核对一下是不是真的同一条线。

    python tools/osm_update/probe_line_match.py
    python tools/osm_update/probe_line_match.py --route 宁蓉线宁渝段 --verbose

读一遍 PBF（约 25s，和管线同一个两遍套路）取全部 `railway=rail` 的 way 名，
再拿 routes.db 的每个 line_name 去比。
"""

from __future__ import annotations

import argparse
import sqlite3
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_rail_tracks as builder  # noqa: E402
import rail_track_geometry as geo  # noqa: E402

# 别名表里能被归一化掉的命名差异；真名不同（宁蓉线 vs 沪蓉线）只能靠别名，见下。
ALIAS_HINT = "真名不同（如 宁蓉线 vs 沪蓉线）只能往 LINE_ALIASES 补，归一化规则救不了"

# 三档的名字与统计顺序。
STAGES = ("strict", "base", "prefix")


def _scan_names(pbf: Path) -> Tuple[Set[Tuple[str, str]], Set[str], int]:
    """一遍 PBF 取全部铁路 way 的 (匹配键, 基本名) 集合、原始名字集合、way 总数。"""
    import osmium

    keys: Set[Tuple[str, str]] = set()
    names: Set[str] = set()
    total = 0

    class Collector(osmium.SimpleHandler):
        def way(self, w: "osmium.osm.Way") -> None:
            nonlocal total
            if w.tags.get("railway") != "rail":
                return
            total += 1
            name = geo.way_name(w.tags)
            if not name:
                return
            names.add(name)
            key = geo.line_match_key(name)
            if key:
                keys.add((key, geo.line_base_key(name)))

    Collector().apply_file(
        str(pbf), locations=False, filters=[osmium.filter.KeyFilter("railway")]
    )
    return keys, names, total


def main(argv: Optional[List[str]] = None) -> int:
    builder._utf8_stdout()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--routes-db", type=Path, default=builder.DEFAULT_ROUTES_DB)
    parser.add_argument("--pbf", type=Path, default=builder.DEFAULT_PBF)
    parser.add_argument(
        "--route", action="append", dest="routes", metavar="NAME",
        help="只看这几条线路（可重复）",
    )
    parser.add_argument(
        "--verbose", action="store_true",
        help="逐条列出（默认只列对不上的）",
    )
    args = parser.parse_args(argv)

    if not args.pbf.exists():
        print(f"找不到 PBF：{args.pbf}", file=sys.stderr)
        return 1

    print(f"读 PBF……（{args.pbf.name}）", file=sys.stderr)
    started = time.time()
    keys, names, way_total = _scan_names(args.pbf)
    print(
        f"  {way_total} 条铁路 way、{len(names)} 个不同名字、"
        f"{len(keys)} 个去重后的匹配键，用时 {time.time() - started:.0f}s",
        file=sys.stderr,
    )
    key_list = sorted(keys)

    wanted = {geo.route_key(name) for name in args.routes} if args.routes else None
    groups: Dict[str, List[Tuple[str, Optional[str]]]] = {}

    connection = sqlite3.connect(f"file:{args.routes_db}?mode=ro", uri=True)
    try:
        rows = builder._pick_routes(connection)
    finally:
        connection.close()

    for route_name, _line_id in rows:
        if wanted is not None and geo.route_key(route_name) not in wanted:
            continue
        profile = geo.infer_profile(route_name)
        stage = builder.line_match_stage(key_list, route_name)
        groups.setdefault(profile, []).append((route_name, stage))

    for profile in (geo.HSR, geo.CONVENTIONAL):
        entries = groups.get(profile, [])
        if not entries:
            continue
        misses = [item for item in entries if item[1] is None]
        counts = {stage: 0 for stage in STAGES}
        for _name, stage in entries:
            if stage is not None:
                counts[stage] += 1
        label = "高铁" if profile == geo.HSR else "普速"
        print(
            f"\n{label}：{len(entries)} 条线路，对不上 {len(misses)} 条"
            f"（严格同名 {counts['strict']} / 基本名 {counts['base']}"
            f" / 前缀 {counts['prefix']}）"
        )
        if profile == geo.CONVENTIONAL and misses:
            print(f"  这些段偏好集为空、只按里程与绕行倍率判定。{ALIAS_HINT}")
        for route_name, stage in entries if args.verbose else misses:
            mark = "  " if stage else "✗ "
            print(f"    {mark}{route_name}  →  {stage or '(对不上)'}")

    if args.verbose:
        print(f"\nPBF 里 {len(names)} 个 way 名的归一化结果")
        for name in sorted(names):
            print(
                f"    {name}  →  {geo.line_match_key(name)}"
                f"（基本名 {geo.line_base_key(name)}）"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
