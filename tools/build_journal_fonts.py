"""把手账用的中文全字库压成两个子集，产出 app/assets/fonts/journal_*.ttf。

为什么要子集：dart_pdf 会把嵌入的字体按「实际用到的字形」二次子集化，所以
打进安装包的字库大小只影响 App 体积，不影响 PDF 体积；反过来，字库越大
App 越臃肿。手账只印站点名、线路名和固定提示语，GB2312 全覆盖就够了。

为什么必须是 glyf 轮廓的 TrueType：dart_pdf 的 TtfParser 不认 CFF/OTF。
用 Google Fonts 直接下的 NotoSansSC.otf、思源黑体 OTF 都会解析失败。
本脚本会先验一遍，遇到 CFF 直接退出，不会产出坏文件。

用法：
    python -m pip install fonttools brotli
    python tools/build_journal_fonts.py \\
        --wenkai /path/to/LXGWWenKai-Regular.ttf \\
        --xihei  /path/to/LXGWNeoXiHei.ttf

字体来源（都必须与 OFL 兼容）：
    复古车票簿  LXGW WenKai   https://github.com/lxgw/LxgwWenKai/releases
    简约方格本  LXGW Neo XiHei https://github.com/lxgw/LxgwNeoXiHei/releases

已知取舍：字符集只到 GB2312（6763 汉字）。GBK 独有的生僻字——「甪」「滘」
这类——会缺，印出来是 --notdef-outline 画出的空框，看得见而不是静默空白。
要补就把 build_charset() 里的 'gb2312' 换成 'gbk'，两个文件会从约 4MB
涨到 8-12MB。
"""

from __future__ import annotations

import argparse
import csv
import pathlib
import sqlite3
import sys
from fontTools import subset
from fontTools.ttLib import TTFont

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
APP_DIR = REPO_ROOT / "app"
DB_DIR = APP_DIR / "assets" / "db"
OUT_DIR = APP_DIR / "assets" / "fonts"

# Windows 控制台默认是 GBK，印中文和缺字样本会直接 UnicodeEncodeError。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# 只在 GB2312 之外、但手账代码里真的会用到（或可能用到）的字符。
# '¥' 是半角日元符号，GB2312 收的是全角 '￥'，两个都要留着。
EXTRA_CHARS = "¥￥·—…→←↑↓□■○●◎◇◆△▲※°№§¶"

# 每个 (字体文件, 输出文件, 用途) 三元组。
TARGETS = [
    ("wenkai", "journal_kai.ttf", "复古车票簿（衬线/楷体）"),
    ("xihei", "journal_hei.ttf", "简约方格本（黑体）"),
]

# pyftsubset 的等价参数，走 Python API 而不是命令行，
# 免得 Windows 上 pyftsubset.exe 不在 PATH 里又得让人去翻 Scripts 目录。
OPTIONS_KWARGS = dict(
    layout_features=[],  # 丢掉 GSUB/GPOS：手账没有连字和字距调整
    hinting=False,
    desubroutinize=True,
    notdef_glyph=True,
    notdef_outline=True,  # 缺字画看得见的空框，而不是一片空白
    recommended_glyphs=True,
    name_IDs=["*"],  # dart_pdf 取字体名要用 name 表
    name_legacy=True,
    name_languages=["*"],
    recalc_bounds=True,
)


def build_charset() -> set[str]:
    """GB2312 全字集 + ASCII + 补充标点 + 库里出现过的所有汉字。"""
    chars: set[str] = set()

    # GB2312：两字节，两个字节都在 0xA1-0xFE 之间，合法的就是 6763 汉字 + 符号。
    for high in range(0xA1, 0xFA):
        for low in range(0xA1, 0xFF):
            try:
                chars.add(bytes([high, low]).decode("gb2312"))
            except UnicodeDecodeError:
                continue

    chars.update(chr(code) for code in range(0x20, 0x7F))
    chars.update(EXTRA_CHARS)
    chars.update(collect_db_chars())
    return chars


def collect_db_chars() -> set[str]:
    """并上路网库与坐标表里出现过的字。

    防的是生僻站名：某个站的三字名里有一个字不在 GB2312，手账就会印出空框，
    而它明明就在我们自己的库里。

    只收 isprintable() 的字：CSV 的 BOM 会以 U+FEFF 的形式混进来，
    它是个不可见的格式字符，收进去只会让「缺字」报告凭空多一条。
    """
    chars: set[str] = set()

    def take(value: object) -> None:
        if isinstance(value, str):
            chars.update(char for char in value if char.isprintable())

    for db_name, queries in (
        (
            "routes.db",
            [
                "SELECT route_name FROM routes",
                "SELECT station_name FROM stations",
            ],
        ),
        (
            "rail_tracks.db",
            [
                "SELECT route_name FROM tracks",
                "SELECT from_station FROM tracks",
                "SELECT to_station FROM tracks",
                "SELECT station_name FROM stations",
            ],
        ),
    ):
        path = DB_DIR / db_name
        if not path.exists():
            print(f"  ! 跳过 {db_name}：文件不在")
            continue
        connection = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            for query in queries:
                for (value,) in connection.execute(query):
                    take(value)
        finally:
            connection.close()

    csv_path = DB_DIR / "coordinates.csv"
    if csv_path.exists():
        with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
            for row in csv.reader(handle):
                for cell in row:
                    take(cell)

    return chars


def assert_true_type(font_path: pathlib.Path) -> None:
    """dart_pdf 只吃 glyf 轮廓。CFF/OTF 会让导出在运行期炸，这里先拦下来。"""
    with TTFont(font_path, lazy=True) as font:
        tables = set(font.keys())
    if "glyf" not in tables or "loca" not in tables:
        raise SystemExit(
            f"{font_path.name} 不是 glyf 轮廓的 TrueType"
            f"（有的表：{sorted(t for t in tables if t in ('glyf', 'loca', 'CFF ', 'CFF2'))}）。\n"
            "换一个 TTF 版本的字体；OTF/CFF 的 dart_pdf 解析不了。"
        )


def subset_font(source: pathlib.Path, output: pathlib.Path, chars: set[str]) -> None:
    options = subset.Options(**OPTIONS_KWARGS)
    if "DSIG" not in options.drop_tables:
        options.drop_tables.append("DSIG")

    font = subset.load_font(str(source), options)
    try:
        subsetter = subset.Subsetter(options=options)
        subsetter.populate(unicodes={ord(char) for char in chars})
        subsetter.subset(font)
        subset.save_font(font, str(output), options)
    finally:
        font.close()


def report_coverage(output: pathlib.Path, chars: set[str]) -> set[str]:
    """回读产出，报出请求了但源字体里没有的字。"""
    with TTFont(output, lazy=True) as font:
        codepoints: set[int] = set()
        for table in font["cmap"].tables:
            codepoints.update(table.cmap.keys())
        glyph_count = font["maxp"].numGlyphs

    missing = {char for char in chars if ord(char) not in codepoints}
    size_mb = output.stat().st_size / 1024 / 1024
    print(f"    {output.name}: {size_mb:.2f} MB, {glyph_count} 字形")
    if missing:
        sample = "".join(sorted(missing)[:40])
        print(f"    ! 源字体缺 {len(missing)} 个字符，例如：{sample}")
    return missing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--wenkai", type=pathlib.Path, required=True, help="LXGWWenKai-Regular.ttf")
    parser.add_argument("--xihei", type=pathlib.Path, required=True, help="LXGWNeoXiHei.ttf")
    parser.add_argument("--out-dir", type=pathlib.Path, default=OUT_DIR)
    args = parser.parse_args()

    sources = {"wenkai": args.wenkai, "xihei": args.xihei}
    for key, path in sources.items():
        if not path.exists():
            raise SystemExit(f"找不到 {key} 源字体：{path}")

    print("收集字符集…")
    chars = build_charset()
    print(f"  {len(chars)} 个字符")

    args.out_dir.mkdir(parents=True, exist_ok=True)
    total_missing: set[str] = set()

    for key, output_name, purpose in TARGETS:
        source = sources[key]
        output = args.out_dir / output_name
        print(f"子集化 {source.name} → {output_name}（{purpose}）")
        assert_true_type(source)
        subset_font(source, output, chars)
        total_missing |= report_coverage(output, chars)

    if total_missing:
        print(f"\n完成，但有 {len(total_missing)} 个字符源字体里没有，印出来是空框。")
        print("这是 GB2312 之外的生僻字，属已知取舍；要全覆盖就把字符集切到 GBK。")
    else:
        print("\n完成，字符集全覆盖。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
