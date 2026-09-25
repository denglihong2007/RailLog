#!/usr/bin/env python3
"""下载全国 OSM 数据（Geofabrik 的 china-latest.osm.pbf）到管线缓存目录。

只用标准库 urllib：仓库的 Python 侧没有第三方依赖，一次性的 1.6GB 下载不值得为它
引入一个 HTTP 库。

支持断点续传——Geofabrik 返回 `Accept-Ranges: bytes`，所以下到一半中断（断网、
Ctrl-C）后再跑一次会从 `.part` 的当前长度接着下，不必重头再来。下满了才原子改名成
正式文件，中途失败不会留下一个看着像好文件的半成品。

    python tools/osm_update/download.py

    # 换镜像源
    python tools/osm_update/download.py --mirror https://mirror.example/china.osm.pbf
"""

from __future__ import annotations

import argparse
import http.client
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from build_rail_tracks import DEFAULT_PBF, USER_AGENT, _utf8_stdout  # noqa: E402

# Geofabrik 的亚洲分区里中国是一个单独的文件，每日更新。
DEFAULT_URL = "https://download.geofabrik.de/asia/china-latest.osm.pbf"

CHUNK_BYTES = 1 << 20  # 1MB
TIMEOUT_SECONDS = 60


def _request(url: str, *, offset: int = 0, method: str = "GET") -> urllib.request.Request:
    headers = {"User-Agent": USER_AGENT}
    if offset:
        headers["Range"] = f"bytes={offset}-"
    return urllib.request.Request(url, headers=headers, method=method)


def remote_info(url: str) -> tuple[int | None, str | None]:
    """远端文件的 (大小, 最后修改时间)。

    有些镜像不支持 HEAD，那就返回 (None, None)——照样能下，只是没法提前知道大小、
    也没法判断本地那份是否已经是最新。
    """
    try:
        with urllib.request.urlopen(
            _request(url, method="HEAD"), timeout=TIMEOUT_SECONDS
        ) as response:
            length = response.headers.get("Content-Length")
            return (
                int(length) if length else None,
                response.headers.get("Last-Modified"),
            )
    except (urllib.error.URLError, OSError, ValueError):
        return None, None


def _format_progress(written: int, total: int | None, started: float) -> str:
    elapsed = max(1e-6, time.time() - started)
    speed = written / elapsed / 1e6  # MB/s
    if total:
        ratio = written / total * 100
        return (
            f"  {written / 1e9:.2f}/{total / 1e9:.2f} GB"
            f"（{ratio:.1f}%） {speed:.1f} MB/s"
        )
    return f"  {written / 1e9:.2f} GB {speed:.1f} MB/s"


def download(url: str, target: Path, *, force: bool = False) -> bool:
    """把 [url] 下到 [target]；本地已经是最新时什么都不做。成功返回 True。"""
    target.parent.mkdir(parents=True, exist_ok=True)
    remote_size, last_modified = remote_info(url)
    if remote_size:
        print(f"远端           : {remote_size / 1e9:.2f} GB，{last_modified or '未知时间'}")
    if (
        not force
        and target.exists()
        and remote_size is not None
        and target.stat().st_size == remote_size
    ):
        print(f"已是最新       : {target}")
        return True

    part = target.with_name(target.name + ".part")
    if force and part.exists():
        part.unlink()
    offset = part.stat().st_size if part.exists() else 0
    if remote_size is not None and offset >= remote_size:
        # 本地残片比远端还长：远端换过文件，残片不能再续，只能重下。
        part.unlink()
        offset = 0

    total: int | None = remote_size
    interrupted: str | None = None
    try:
        with urllib.request.urlopen(
            _request(url, offset=offset), timeout=TIMEOUT_SECONDS
        ) as response:
            resuming = offset > 0 and response.status == 206
            if offset and not resuming:
                print("镜像不支持断点续传，从头下载。", file=sys.stderr)
            written = offset if resuming else 0
            length_header = response.headers.get("Content-Length")
            remaining = int(length_header) if length_header else 0
            total = (written + remaining) if remaining else remote_size
            if resuming:
                print(f"续传           : 已有 {written / 1e9:.2f} GB")

            started = time.time()
            reported = 0.0
            with open(part, "ab" if resuming else "wb") as handle:
                while True:
                    chunk = response.read(CHUNK_BYTES)
                    if not chunk:
                        break
                    handle.write(chunk)
                    written += len(chunk)
                    if time.time() - reported >= 1.0:
                        reported = time.time()
                        print(f"\r{_format_progress(written, total, started)}",
                              end="", flush=True)
            print(f"\r{_format_progress(written, total, started)}")
    except (http.client.HTTPException, ConnectionError, TimeoutError) as error:
        # 中途断网/超时：已经写进 .part 的部分算数，下次从断点接着下。
        interrupted = f"{type(error).__name__}: {error}"

    size = part.stat().st_size
    if interrupted or (total is not None and size != total):
        detail = interrupted or f"{size} 字节，应为 {total}"
        print(f"\r下载中断       : {detail}", file=sys.stderr)
        print(f"已保留 {size / 1e9:.2f} GB，重跑同一条命令即可续传。", file=sys.stderr)
        return False
    part.replace(target)
    print(f"完成           : {target}（{size / 1e9:.2f} GB）")
    return True


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="下载全国 OSM 数据到管线缓存目录",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--url", "--mirror", dest="url", default=DEFAULT_URL,
                        help="下载源；国内网络慢的话换一个镜像")
    parser.add_argument("--out", type=Path, default=DEFAULT_PBF, help="目标文件")
    parser.add_argument("--force", action="store_true",
                        help="忽略已有文件重新下载（残片会一起丢掉）")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    _utf8_stdout()
    args = parse_args(argv)
    try:
        return 0 if download(args.url, args.out, force=args.force) else 1
    except urllib.error.URLError as error:
        print(f"下载失败       : {error}", file=sys.stderr)
        print("网络不通或镜像不可用时，可以用 --url 换一个源；已下载的部分会保留。",
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
