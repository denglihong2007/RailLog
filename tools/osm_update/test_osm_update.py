"""osm_update/download.py 的单元测试（标准库 unittest，只连本机回环）。

断点续传这套逻辑的坑都在「服务器到底认不认 Range」和「中途断了算不算数」上，所以
用一个可配置的小 HTTP 服务器把这些情形都演一遍：

    cd tools && python -m unittest discover -p "test_*.py" -v
"""

from __future__ import annotations

import http.server
import sys
import tempfile
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import download as downloader  # noqa: E402


class _Handler(http.server.BaseHTTPRequestHandler):
    """按类属性配置行为的极简服务器：支持 HEAD / Range，可关掉 Range、HEAD。"""

    payload = b""
    last_modified = "Mon, 01 Jan 2026 00:00:00 GMT"
    ignore_range = False
    head_fails = False
    truncate = 0
    # 依次收到的 Range 头（没带就是 None），用来断言续传请求确实从断点开始。
    ranges: list[str | None] = []

    def log_message(self, *args) -> None:  # 测试输出别被访问日志淹了
        pass

    def do_HEAD(self) -> None:
        if self.head_fails:
            self.send_error(503)
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(self.payload)))
        self.send_header("Last-Modified", self.last_modified)
        self.end_headers()

    def do_GET(self) -> None:
        range_header = self.headers.get("Range")
        type(self).ranges.append(range_header)
        start = 0
        if range_header and not self.ignore_range:
            start = int(range_header.partition("=")[2].partition("-")[0])
            self.send_response(206)
            self.send_header(
                "Content-Range",
                f"bytes {start}-{len(self.payload) - 1}/{len(self.payload)}",
            )
        else:
            self.send_response(200)
        body = self.payload[start:]
        # 声明原始长度却只发一部分：客户端会看到连接提前关闭。
        self.send_header("Content-Length", str(len(body) + self.truncate))
        self.end_headers()
        self.wfile.write(body)


class DownloadTest(unittest.TestCase):
    def setUp(self) -> None:
        self.payload = bytes(range(256)) * 64  # 16KB
        _Handler.payload = self.payload
        _Handler.last_modified = "Mon, 01 Jan 2026 00:00:00 GMT"
        _Handler.ignore_range = False
        _Handler.head_fails = False
        _Handler.truncate = 0
        _Handler.ranges = []
        self.server = http.server.HTTPServer(("127.0.0.1", 0), _Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

        def stop_server() -> None:
            self.server.shutdown()
            self.server.server_close()

        self.addCleanup(stop_server)
        self.url = f"http://127.0.0.1:{self.server.server_port}/china.osm.pbf"
        self.directory = Path(tempfile.mkdtemp())
        self.addCleanup(lambda: __import__("shutil").rmtree(self.directory, True))
        self.target = self.directory / "china.osm.pbf"

    def part(self) -> Path:
        return self.directory / "china.osm.pbf.part"

    def test_downloads_a_fresh_file(self) -> None:
        self.assertTrue(downloader.download(self.url, self.target))
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertFalse(self.part().exists())
        self.assertEqual(_Handler.ranges, [None])

    def test_skips_an_up_to_date_file(self) -> None:
        self.target.write_bytes(self.payload)
        self.assertTrue(downloader.download(self.url, self.target))
        self.assertEqual(_Handler.ranges, [])  # 没再下
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_resumes_from_the_partial_file(self) -> None:
        half = len(self.payload) // 2
        self.part().write_bytes(self.payload[:half])
        self.assertTrue(downloader.download(self.url, self.target))
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertFalse(self.part().exists())
        self.assertEqual(_Handler.ranges, [f"bytes={half}-"])

    def test_restarts_when_the_server_ignores_range(self) -> None:
        # 服务器对 Range 视而不见、回了整个文件：这时绝不能往残片后面接。
        _Handler.ignore_range = True
        self.part().write_bytes(self.payload[: len(self.payload) // 2])
        self.assertTrue(downloader.download(self.url, self.target))
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_keeps_the_partial_file_when_the_transfer_breaks(self) -> None:
        _Handler.truncate = 1  # 声明长度比实际发送多 1 字节
        self.assertFalse(downloader.download(self.url, self.target))
        self.assertFalse(self.target.exists())
        self.assertTrue(self.part().exists())
        # 断点留着，网络恢复了重跑一次就能补齐。
        _Handler.truncate = 0
        self.assertTrue(downloader.download(self.url, self.target))
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_discards_a_partial_longer_than_the_remote_file(self) -> None:
        # 远端换过文件（变小了）：残片没法再续，得重下。
        self.part().write_bytes(self.payload + b"stale tail")
        self.assertTrue(downloader.download(self.url, self.target))
        self.assertEqual(self.target.read_bytes(), self.payload)
        self.assertEqual(_Handler.ranges, [None])

    def test_downloads_without_head_support(self) -> None:
        _Handler.head_fails = True
        self.assertTrue(downloader.download(self.url, self.target))
        self.assertEqual(self.target.read_bytes(), self.payload)

    def test_force_redownloads(self) -> None:
        self.target.write_bytes(self.payload)
        self.assertTrue(downloader.download(self.url, self.target, force=True))
        self.assertEqual(_Handler.ranges, [None])


if __name__ == "__main__":
    unittest.main()
