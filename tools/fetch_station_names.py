"""下载 12306 的车站字典，写进 App 的 assets 作为离线兜底。

App 启动时先读 app/assets/db/station_name.js（勾子里的站名 → 电报码、站名 →
所属城市），网络可用时再在后台拉一份线上字典覆盖。内置副本只在 12306 不可达
时生效，但站名和城市会随新线开通变化，发版前顺手跑一遍即可。

用法：
    python tools/fetch_station_names.py

来源：https://kyfw.12306.cn/otn/resources/js/framework/station_name.js
格式：var station_names ='@电报码小写|站名|电报码|拼音|拼音缩写|序号|城市码|城市|...@...';
"""

from __future__ import annotations

import pathlib
import sys
import urllib.request

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT_PATH = REPO_ROOT / "app" / "assets" / "db" / "station_name.js"
URL = "https://kyfw.12306.cn/otn/resources/js/framework/station_name.js"

# 线上字典目前约 3400 条；低于这个数说明下到的是错误页或半截文件。
MIN_ENTRIES = 3000

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    ),
    "Referer": "https://kyfw.12306.cn/otn/leftTicket/init",
    "Accept": "*/*",
}


def fetch() -> str:
    request = urllib.request.Request(URL, headers=HEADERS)
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8")


def parse(source: str) -> tuple[dict[str, str], dict[str, str]]:
    codes: dict[str, str] = {}
    cities: dict[str, str] = {}
    for entry in source.split("@")[1:]:
        fields = entry.split("|")
        if len(fields) < 3:
            continue
        name = fields[1].strip()
        telecode = fields[2].strip().upper()
        if name and telecode:
            codes[name] = telecode
        if len(fields) >= 8:
            city = fields[7].strip()
            if name and city:
                cities[name] = city
    return codes, cities


def main() -> int:
    source = fetch()
    if not source.startswith("var station_names"):
        print("12306 返回的内容不是车站字典脚本，放弃写入", file=sys.stderr)
        return 1

    codes, cities = parse(source)
    if len(codes) < MIN_ENTRIES or len(cities) < MIN_ENTRIES:
        print(
            f"解析结果不完整（电报码 {len(codes)} 条、城市 {len(cities)} 条），放弃写入",
            file=sys.stderr,
        )
        return 1

    OUT_PATH.write_text(source, encoding="utf-8", newline="")
    print(f"已写入 {OUT_PATH}")
    print(f"车站 {len(codes)} 条，城市 {len(cities)} 条")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
