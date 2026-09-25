"""探查 china.osm.pbf 里铁路数据的规模，用来决定管线的内存方案。

跑一次就知道：铁路 way 有多少条、坐标点总数、车站节点多少、单遍读取要多久、
常驻内存多大。这些数字决定了「整网读进内存 + 网格索引」是否可行。

    python tools/osm_update/probe_pbf.py
"""

from __future__ import annotations

import argparse
import ctypes
import sys
import time
from collections import Counter
from pathlib import Path

import osmium

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_rail_tracks import DEFAULT_PBF  # noqa: E402  （路径口径只有一处）


def _rss_mb() -> float:
    """当前进程常驻内存（MB）。

    `resource` 只有 Unix 有，这里直接用 Windows 的 GetProcessMemoryInfo；拿不到
    就退回 0，不影响其余统计。
    """
    try:
        class _Counters(ctypes.Structure):
            _fields_ = [
                ("cb", ctypes.c_ulong),
                ("PageFaultCount", ctypes.c_ulong),
                ("PeakWorkingSetSize", ctypes.c_size_t),
                ("WorkingSetSize", ctypes.c_size_t),
                ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPagedPoolUsage", ctypes.c_size_t),
                ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                ("PagefileUsage", ctypes.c_size_t),
                ("PeakPagefileUsage", ctypes.c_size_t),
            ]

        counters = _Counters()
        counters.cb = ctypes.sizeof(counters)
        handle = ctypes.windll.kernel32.GetCurrentProcess()
        if not ctypes.windll.psapi.GetProcessMemoryInfo(
            handle, ctypes.byref(counters), counters.cb
        ):
            return 0.0
        return counters.PeakWorkingSetSize / 1024.0 / 1024.0
    except Exception:
        return 0.0


class Probe(osmium.SimpleHandler):
    """只统计、不保留几何，用来量规模。"""

    def __init__(self) -> None:
        super().__init__()
        self.ways = 0
        self.way_nodes = 0
        self.by_railway: Counter[str] = Counter()
        self.stations = 0
        self.named_stations = 0
        self.first_point: tuple[float, float] | None = None
        self.last_point: tuple[float, float] | None = None

    def way(self, w: osmium.osm.Way) -> None:
        railway = w.tags.get("railway")
        if railway is None:
            return
        self.ways += 1
        self.by_railway[railway] += 1
        n = len(w.nodes)
        self.way_nodes += n
        if n:
            first = w.nodes[0].location
            last = w.nodes[-1].location
            if first.valid():
                point = (first.lat, first.lon)
                if self.first_point is None:
                    self.first_point = point
                self.last_point = point

    def node(self, n: osmium.osm.Node) -> None:
        if n.tags.get("railway") in ("station", "halt"):
            self.stations += 1
            if n.tags.get("name"):
                self.named_stations += 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pbf", type=Path, default=DEFAULT_PBF)
    args = parser.parse_args(argv)

    if not args.pbf.exists():
        print(f"找不到 {args.pbf}", file=sys.stderr)
        return 1
    size_gb = args.pbf.stat().st_size / 1024**3
    print(f"PBF          : {args.pbf}  ({size_gb:.2f} GB)")

    handler = Probe()
    started = time.time()
    # 只读 way 与 node，跳过 relation，省掉不需要的解析。
    handler.apply_file(str(args.pbf), locations=False, idx="flex_mem")
    elapsed = time.time() - started

    print(f"单遍耗时     : {elapsed:.1f}s")
    print(f"峰值内存     : {_rss_mb():.0f} MB")
    print(f"railway=* way: {handler.ways}（节点引用 {handler.way_nodes}）")
    print(f"车站节点     : {handler.stations}（有 name 的 {handler.named_stations}）")
    print("按 railway 值分布：")
    for value, count in handler.by_railway.most_common(12):
        print(f"  {value:12s} {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
