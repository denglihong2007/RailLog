"""核对「舍去坐标」的每一站：真错还是里程数据坑的？

对每个被舍去的站，打印它所在线路、前后站的里程桩、它到前后站的直线距离，
以及它在舍去前的坐标。判据：前后站里程差应当很小（确实相邻），而被舍去的
坐标到它们的直线距离应当远超这个里程——否则就是误舍。

跑：
    cd tools && python osm_update/probe_discards.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_rail_tracks as builder  # noqa: E402
import rail_track_geometry as geo  # noqa: E402


def main() -> int:
    builder._utf8_stdout()
    args = builder.parse_args(["--source", "pbf"])
    stations = builder.load_osm_stations(args.cache_dir)
    coordinates, _ = builder.build_coordinates(args, stations)

    before = dict(coordinates._coordinates)
    discarded = builder.discard_implausible_station_coordinates(
        coordinates, args.routes_db
    )
    names = {name for name, _prev, _next in discarded}

    # 找出每个被舍去的站出现在哪些线路的哪一段上：只有两侧里程差小、
    # 而坐标到两端直线距离远大于该里程，才算舍对了。
    import sqlite3

    connection = sqlite3.connect(f"file:{args.routes_db}?mode=ro", uri=True)
    try:
        for route_name, version_id in builder._pick_route_versions(connection):
            rows = connection.execute(
                "SELECT station_index, station_name, mileage FROM stations"
                " WHERE route_version_id = ? ORDER BY station_index",
                (version_id,),
            ).fetchall()
            for index, (_station_index, name, _mileage) in enumerate(rows):
                if name not in names:
                    continue
                prev_row = rows[index - 1] if index else None
                next_row = rows[index + 1] if index + 1 < len(rows) else None
                old = before.get(builder._station_keys(name)[0])
                print(f"\n{name}  @ {route_name}")
                print(f"  原坐标     : {old}")
                for label, row in (("前站", prev_row), ("后站", next_row)):
                    if row is None:
                        print(f"  {label}       : （无——端点站）")
                        continue
                    mileage = row[2]
                    gap = (
                        geo.haversine_km(old, _coord(before, row[1]))
                        if old
                        else float("nan")
                    )
                    print(
                        f"  {label}       : {row[1]}（里程 {mileage}）"
                        f" 直线 {gap:.0f}km"
                    )
                if prev_row and next_row and prev_row[2] is not None and next_row[2] is not None:
                    print(f"  前后里程差 : {abs(next_row[2] - prev_row[2]):.1f}km")
    finally:
        connection.close()
    return 0


def _coord(index: dict, name: str):
    for key in builder._station_keys(name):
        if key in index:
            return index[key]
    return None


if __name__ == "__main__":
    raise SystemExit(main())
