"""量一下 OSM 车站坐标能覆盖 routes.db 里多少站。

这是「要不要把坐标主源从 coordinates.csv 换成 OSM」的决策依据：覆盖率决定
OSM 能不能当主源，还是只能做兜底。结果写到 tools/.test_out/osm_stations.json，
后续管线可以直接复用，不用重扫 PBF。

    python tools/osm_update/probe_stations.py
"""

from __future__ import annotations

import json
import sqlite3
import sys
import time
from pathlib import Path

import osmium

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_rail_tracks as builder  # noqa: E402

PBF = builder.DEFAULT_PBF
OUT = builder.TOOLS_DIR / ".test_out" / "osm_stations.json"


class StationCollector(osmium.SimpleHandler):
    """收集 railway=station/halt 的节点坐标，按归一化站名建索引。"""

    def __init__(self) -> None:
        super().__init__()
        self.stations: dict[str, list] = {}
        self.total = 0
        self.named = 0

    def node(self, n: osmium.osm.Node) -> None:
        if n.tags.get("railway") not in ("station", "halt"):
            return
        self.total += 1
        name = n.tags.get("name")
        if not name:
            return
        self.named += 1
        location = n.location
        if not location.valid():
            return
        # 同一站名可能有多个节点（站台/多个 halt），首个为准。
        aliases = [name, n.tags.get("name:zh"), n.tags.get("alt_name"), n.tags.get("old_name")]
        for alias in aliases:
            if not alias:
                continue
            for key in builder._station_keys(alias):
                self.stations.setdefault(key, [alias, location.lat, location.lon])


def main() -> int:
    if not PBF.exists():
        print(f"找不到 {PBF}", file=sys.stderr)
        return 1

    collector = StationCollector()
    started = time.time()
    collector.apply_file(str(PBF), locations=True, idx="flex_mem")
    print(f"单遍耗时     : {time.time() - started:.1f}s")
    print(f"车站节点     : {collector.total}（有 name {collector.named}）")
    print(f"归一化站名键 : {len(collector.stations)}")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(
        json.dumps(collector.stations, ensure_ascii=False), encoding="utf-8"
    )

    conn = sqlite3.connect(f"file:{builder.DEFAULT_ROUTES_DB}?mode=ro", uri=True)
    names = sorted({row[0] for row in conn.execute("SELECT DISTINCT station_name FROM stations")})
    conn.close()

    csv_index = builder.StationCoordinateIndex.from_csv(builder.DEFAULT_COORDINATES)

    def matched(name: str) -> bool:
        return any(key in collector.stations for key in builder._station_keys(name))

    in_csv = [n for n in names if csv_index.find(n) is not None]
    miss_csv = [n for n in names if csv_index.find(n) is None]

    hit_both = [n for n in in_csv if matched(n)]
    osm_only = [n for n in miss_csv if matched(n)]
    neither = [n for n in miss_csv if not matched(n)]

    print()
    print(f"routes.db 去重站名     : {len(names)}")
    print(f"  已有 CSV 坐标        : {len(in_csv)}")
    print(f"     其中 OSM 也命中   : {len(hit_both)}"
          f"  ({100 * len(hit_both) / max(1, len(in_csv)):.1f}%)")
    print(f"  CSV 无坐标           : {len(miss_csv)}")
    print(f"     OSM 能补上        : {len(osm_only)}")
    print(f"     OSM 也没有        : {len(neither)}")
    print(f"  合计可用 OSM 坐标    : {len(hit_both) + len(osm_only)} / {len(names)}"
          f"  ({100 * (len(hit_both) + len(osm_only)) / len(names):.1f}%)")
    print(f"  OSM 无匹配示例       : {neither[:15]}")
    print(f"\n已缓存 {OUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
