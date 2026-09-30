#!/usr/bin/env python3
"""一键更新铁路底图：下载最新 OSM → 重建 rail_tracks.db。

三步：拉 Geofabrik 的 china-latest.osm.pbf（断点续传）→ 跑 build_rail_tracks.py
全量生成折线 → 从库里读回 meta 和失败分布打一份小结。

    python tools/osm_update/update.py

    # 先看看新数据长什么样，不写正式库
    python tools/osm_update/update.py --out tools/.test_out/tracks.db

    # 只更新数据、不重建
    python tools/osm_update/update.py --download-only

    # 不联网，用缓存里的 PBF 重建
    python tools/osm_update/update.py --skip-download
"""

from __future__ import annotations

import argparse
import sqlite3
import subprocess
import sys
import time
from pathlib import Path

# 同目录平级 import：既能当脚本跑，也能被当包 import。
MODULE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(MODULE_DIR))

from build_rail_tracks import DEFAULT_OUT, DEFAULT_PBF, _utf8_stdout  # noqa: E402

BUILD_SCRIPT = MODULE_DIR / "build_rail_tracks.py"
PROBE_SCRIPT = MODULE_DIR / "probe_pbf.py"
DOWNLOAD_SCRIPT = MODULE_DIR / "download.py"

# 小结里想看的 meta 键，按关心的顺序排。
META_KEYS = (
    "generated_at",
    "source",
    "workers",
    "detour_ratio",
    "legs_total",
    "legs_ok",
    "legs_failed",
    "split_legs",
    "track_split",
    "stations",
    # 坐标侧的两道处理：同名异地消歧、以及消歧救不回的站按里程舍去。
    # 它们改了哪些站的坐标/有没有坐标，直接决定地图上画在哪。
    "station_disambiguation",
    "station_coordinate_discards",
)


def _run(script: Path, args: list[str]) -> int:
    """用当前解释器跑同目录的一个脚本，回传退出码。

    不改子进程的工作目录：脚本自己的默认路径都锚死了，而用户显式传的相对路径
    （比如 `--out tools/.test_out/x.db`）应该按他敲命令时所在的目录解释。
    """
    command = [sys.executable, str(script), *args]
    print(f"\n$ {' '.join(command)}\n", flush=True)
    return subprocess.run(command).returncode


def summarize(database: Path) -> None:
    """把生成结果从库里读回来打一份小结——比翻日志快。"""
    if not database.exists():
        print(f"\n没有生成数据库：{database}", file=sys.stderr)
        return
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        meta = dict(connection.execute("SELECT key, value FROM meta"))
        counts = connection.execute("SELECT COUNT(*) FROM tracks").fetchone()[0]
        failures = connection.execute(
            "SELECT reason, COUNT(*) FROM failures GROUP BY reason ORDER BY 2 DESC"
        ).fetchall()
    finally:
        connection.close()

    print(f"\n{'=' * 46}")
    print(f"输出           : {database}（{database.stat().st_size / 1e6:.1f} MB）")
    print(f"折线行数       : {counts}")
    for key in META_KEYS:
        if key in meta:
            print(f"{key:<15}: {meta[key]}")
    if failures:
        print("失败分布       :")
        for reason, count in failures:
            # reason 里 ": 细节" 的部分是给 failures 表看的，按主因聚拢。
            print(f"  {reason.split(':')[0]:<22} {count}")
    print(f"{'=' * 46}")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="下载最新 OSM 数据并重建 rail_tracks.db",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--skip-download", action="store_true",
                        help="不下载，直接用缓存里的 PBF")
    parser.add_argument("--download-only", action="store_true",
                        help="只下载数据，不重建数据库")
    parser.add_argument("--force-download", action="store_true",
                        help="忽略本地已有文件重新下载")
    parser.add_argument("--url", "--mirror", dest="url", default=None,
                        help="下载源；缺省用 Geofabrik")
    parser.add_argument("--probe", action="store_true",
                        help="下载后先跑 probe_pbf.py 校验，能读到铁路数据才继续"
                             "（完整重建前多花几分钟，网络不稳时值得）")
    parser.add_argument("--pbf", type=Path, default=DEFAULT_PBF,
                        help="OSM 数据文件；同时是下载目标与重建的输入")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT,
                        help="输出的 rail_tracks.db")
    parser.add_argument("--workers", type=int, default=16,
                        help="重建时的并行进程数（每个进程各读一份 PBF）")
    parser.add_argument("--route", action="append", dest="routes", metavar="NAME",
                        help="只重建指定线路（可重复；调试用）")
    parser.add_argument("--limit", type=int, help="只重建前 N 段（调试用）")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    _utf8_stdout()
    args = parse_args(argv)
    started = time.time()

    if not args.skip_download:
        download_args = ["--out", str(args.pbf)]
        if args.url:
            download_args += ["--url", args.url]
        if args.force_download:
            download_args.append("--force")
        if _run(DOWNLOAD_SCRIPT, download_args):
            print("\n下载失败，中止。", file=sys.stderr)
            return 1
    else:
        print(f"跳过下载       : 用 {args.pbf}")
        if not args.pbf.exists():
            print(f"缓存里没有 {args.pbf}，去掉 --skip-download 先下数据。", file=sys.stderr)
            return 1

    if args.download_only:
        print(f"\n只下载，未重建（耗时 {time.time() - started:.0f}s）。")
        return 0

    if args.probe and _run(PROBE_SCRIPT, ["--pbf", str(args.pbf)]):
        print("\n探针在 PBF 里没读到预期数据，中止；文件可能损坏，重下即可。", file=sys.stderr)
        return 1

    build_args = [
        "--source", "pbf",
        "--pbf", str(args.pbf),
        "--out", str(args.out),
        "--workers", str(args.workers),
        "--apply",
    ]
    for route in args.routes or []:
        build_args += ["--route", route]
    if args.limit:
        build_args += ["--limit", str(args.limit)]
    if _run(BUILD_SCRIPT, build_args):
        print("\n重建失败，数据库未更新。", file=sys.stderr)
        return 1

    summarize(args.out)
    print(f"总耗时         : {time.time() - started:.0f}s")
    if args.out == DEFAULT_OUT and not args.routes and not args.limit:
        print("app/assets/db/rail_tracks.db 已更新，重新构建 App 即生效。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
