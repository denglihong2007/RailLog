"""打印舍去坐标后仍然被判「坐标不可信」的段，供逐条定性。

跑：
    cd tools && python osm_update/probe_remaining_suspect.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_rail_tracks as builder  # noqa: E402


def main() -> int:
    builder._utf8_stdout()
    args = builder.parse_args(["--source", "pbf"])
    stations = builder.load_osm_stations(args.cache_dir)
    coordinates, _ = builder.build_coordinates(args, stations)
    builder.discard_implausible_station_coordinates(coordinates, args.routes_db)

    stats = builder.enumerate_legs(args.routes_db, coordinates)
    print(f"站间段 {len(stats.legs)}，其中坐标不可信 {stats.suspect_legs}：")
    for leg in stats.legs:
        if leg.suspect_reason is None:
            continue
        straight = builder.geo.haversine_km(leg.start, leg.end)
        print(
            f"  {leg.route_name:12} {leg.from_station} → {leg.to_station}"
            f"  里程 {leg.mileage_km}km，直线 {straight:.0f}km"
            f"  {leg.start} / {leg.end}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
