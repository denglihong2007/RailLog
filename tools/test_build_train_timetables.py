"""build_train_timetables.py 的单元测试（标准库 unittest，不碰联网）。

建库这块真正容易出错的只有两件事，测试也就围着它们转：

1. **车次号归一化**。源数据里带后缀的形态比预想的多——字母后缀（`K43A`、`D5467B`）
   和括号脏数据（`K7931(空)`）都有，规则「最后一位必然是数字」必须同时覆盖。
2. **只保留第一块**。同一车次在同一个快照里可能出现多份时刻表（`seq` 重新回到 1），
   按需求丢弃后面的；而归一化让 `K43A`/`K43B` 塌缩成同一个键，这条规则也得管住它。

运行：

    cd tools && python -m unittest test_build_train_timetables -v
"""

from __future__ import annotations

import csv
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_train_timetables as builder  # noqa: E402

HEADER = ["train_no", "seq", "station", "arrival", "departure", "km"]


def write_snapshot(directory: Path, version: str, rows: list[list[str]]) -> Path:
    path = directory / f"{version}.csv"
    with path.open("w", encoding="utf-8-sig", newline="") as target:
        writer = csv.writer(target)
        writer.writerow(HEADER)
        writer.writerows(rows)
    return path


def block(train_no: str, stops: list[tuple[str, str, str, str]]) -> list[list[str]]:
    """一个时刻表块：stops 是 (station, arrival, departure, km)。"""
    return [
        [train_no, str(index), station, arrival, departure, km]
        for index, (station, arrival, departure, km) in enumerate(stops, start=1)
    ]


class NormalizeTrainCodeTest(unittest.TestCase):
    def test_keeps_plain_codes(self) -> None:
        for raw in ("K7931", "D107", "6062", "T751", "G1"):
            self.assertEqual(builder.normalize_train_code(raw), raw)

    def test_strips_letter_suffix(self) -> None:
        # 需求原话：「车次号最后一位一定是数字」，所以尾巴上的字母都是后缀。
        cases = {
            "K43A": "K43",
            "K43B": "K43",
            "K44B": "K44",
            "K375B": "K375",
            "D5467B": "D5467",
            "T98A": "T98",
            "1433B": "1433",
            "1116A": "1116",
            "G301B": "G301",
        }
        for raw, expected in cases.items():
            self.assertEqual(builder.normalize_train_code(raw), expected)

    def test_strips_parenthesised_suffix(self) -> None:
        # 2021.10.05.csv 里的脏数据，括号连内容一起截掉。
        self.assertEqual(builder.normalize_train_code("K7931(空)"), "K7931")

    def test_rejects_garbage(self) -> None:
        for raw in ("", "K", "(空)", "火车"):
            self.assertIsNone(builder.normalize_train_code(raw))


class SplitTrainCodesTest(unittest.TestCase):
    def test_splits_direction_pair(self) -> None:
        self.assertEqual(builder.split_train_codes("1008/1009"), ("1008", "1009"))
        self.assertEqual(builder.split_train_codes("1432/1433A"), ("1432", "1433"))

    def test_single_code_has_empty_second(self) -> None:
        self.assertEqual(builder.split_train_codes("K7931"), ("K7931", ""))

    def test_collapses_self_pair(self) -> None:
        # 去后缀后两段相同，应当塌缩成单码而不是自配对。
        self.assertEqual(builder.split_train_codes("K7931/K7931(空)"), ("K7931", ""))
        self.assertEqual(builder.split_train_codes("K43/K43"), ("K43", ""))

    def test_rejects_garbage(self) -> None:
        self.assertIsNone(builder.split_train_codes("(空)/(空)"))


class NormalizeValueTest(unittest.TestCase):
    def test_dash_and_blank_mean_no_time(self) -> None:
        for raw in ("-", "", "   ", "--"):
            self.assertEqual(builder.normalize_time(raw), "")

    def test_keeps_real_times(self) -> None:
        self.assertEqual(builder.normalize_time(" 07:49 "), "07:49")

    def test_mileage_defaults_to_zero(self) -> None:
        self.assertEqual(builder.normalize_mileage(""), 0.0)
        self.assertEqual(builder.normalize_mileage("-"), 0.0)
        self.assertEqual(builder.normalize_mileage("51"), 51.0)


class LoadVersionTest(unittest.TestCase):
    def setUp(self) -> None:
        self._scratch = tempfile.TemporaryDirectory()
        self.directory = Path(self._scratch.name)

    def tearDown(self) -> None:
        self._scratch.cleanup()

    def load(self, rows: list[list[str]]):
        path = write_snapshot(self.directory, "2005.03.20", rows)
        return builder.load_version(path)

    def test_keeps_first_block_only(self) -> None:
        # 6062 在 2005.03.20.csv 里有两份时刻表：44 站的交路在前，5 站的在后。
        rows = block(
            "6062", [("甲", "-", "07:42", "0"), ("乙", "08:00", "08:02", "7")]
        ) + block("6062", [("丙", "-", "08:03", "0")])
        loaded, stats = self.load(rows)
        self.assertEqual([row[3] for row in loaded], ["甲", "乙"])
        self.assertEqual(stats["extra_blocks"], 1)
        self.assertEqual(stats["extra_rows"], 1)
        self.assertEqual(stats["trains"], 1)

    def test_suffixed_duplicate_collapses_to_first_block(self) -> None:
        # K7931 与 K7931/K7931(空) 归一化后是同一个键，保留第一块。
        rows = block("K7931", [("甲", "-", "07:30", "0")]) + block(
            "K7931/K7931(空)", [("乙", "-", "07:30", "0")]
        )
        loaded, stats = self.load(rows)
        self.assertEqual([row[3] for row in loaded], ["甲"])
        self.assertEqual(loaded[0][0], "K7931")
        self.assertEqual(loaded[0][1], "")
        self.assertEqual(stats["extra_blocks"], 1)

    def test_ab_suffix_pair_collapses(self) -> None:
        # K43A/K43B 去后缀后同为 K43，只留第一块。
        rows = block("K43A", [("甲", "-", "08:00", "0")]) + block(
            "K43B", [("乙", "-", "09:00", "0")]
        )
        loaded, stats = self.load(rows)
        self.assertEqual([row[3] for row in loaded], ["甲"])
        self.assertEqual(loaded[0][0], "K43")
        self.assertEqual(stats["extra_blocks"], 1)

    def test_distinct_trains_are_not_paired(self) -> None:
        # 旧库把 7273/7274 配成一对导致 OrderID 交错；源 CSV 里它们是两个独立车次。
        rows = block("7273", [("甲", "-", "07:50", "0")]) + block(
            "7274", [("乙", "-", "12:09", "0")]
        )
        loaded, _stats = self.load(rows)
        self.assertEqual([(row[0], row[1], row[3]) for row in loaded], [
            ("7273", "", "甲"),
            ("7274", "", "乙"),
        ])

    def test_direction_pair_shares_one_row_set(self) -> None:
        rows = block("1008/1009", [("甲", "-", "17:45", "0"), ("乙", "18:11", "-", "27")])
        loaded, _stats = self.load(rows)
        self.assertEqual([(row[0], row[1]) for row in loaded], [
            ("1008", "1009"),
            ("1008", "1009"),
        ])

    def test_renumbers_order_and_clears_endpoint_times(self) -> None:
        rows = block(
            "K1",
            [("甲", "-", "07:00", "0"), ("乙", "08:00", "08:05", "10"), ("丙", "09:00", "-", "20")],
        )
        loaded, _stats = self.load(rows)
        self.assertEqual([row[2] for row in loaded], [1, 2, 3])
        # 首站无到达、末站无出发，与旧库约定一致。
        self.assertEqual(loaded[0][4], "")
        self.assertEqual(loaded[-1][5], "")

    def test_blank_cells_become_empty(self) -> None:
        rows = [["K1", "1", "甲", "", "", ""], ["K1", "2", "乙", "08:00", "", ""]]
        loaded, _stats = self.load(rows)
        self.assertEqual(loaded[0][4], "")
        self.assertEqual(loaded[0][6], 0.0)

    def test_rejects_unexpected_header(self) -> None:
        path = self.directory / "2005.03.20.csv"
        path.write_text("a,b,c\n1,2,3\n", encoding="utf-8-sig")
        with self.assertRaises(ValueError):
            builder.load_version(path)

    def test_rejects_short_row(self) -> None:
        with self.assertRaises(ValueError):
            self.load([["K1", "1", "甲"]])

    def test_rejects_unrecognised_code(self) -> None:
        with self.assertRaises(ValueError):
            self.load([["(空)", "1", "甲", "-", "07:00", "0"]])


class VersionDiscoveryTest(unittest.TestCase):
    def setUp(self) -> None:
        self._scratch = tempfile.TemporaryDirectory()
        self.directory = Path(self._scratch.name)

    def tearDown(self) -> None:
        self._scratch.cleanup()

    def test_only_dated_csv_files_are_versions(self) -> None:
        write_snapshot(self.directory, "2003.11.25", [["K1", "1", "甲", "-", "07:00", "0"]])
        write_snapshot(self.directory, "2026.09.25", [["K1", "1", "甲", "-", "07:00", "0"]])
        (self.directory / "notes.csv").write_text("x\n1\n", encoding="utf-8")
        (self.directory / "README.md").write_text("hi\n", encoding="utf-8")

        found = builder.collect_versions(self.directory, None)
        self.assertEqual([version for version, _ in found], ["2003.11.25", "2026.09.25"])

    def test_versions_sort_chronologically(self) -> None:
        # 字典序必须等于时间序，服务端靠 ORDER BY name 取版本列表。
        for version in ("2004.10.03", "2003.11.25", "2026.09.25", "2009.07.01"):
            write_snapshot(self.directory, version, [["K1", "1", "甲", "-", "07:00", "0"]])
        found = builder.collect_versions(self.directory, None)
        self.assertEqual(
            [version for version, _ in found],
            ["2003.11.25", "2004.10.03", "2009.07.01", "2026.09.25"],
        )

    def test_limit_versions_takes_earliest(self) -> None:
        for version in ("2004.10.03", "2003.11.25"):
            write_snapshot(self.directory, version, [["K1", "1", "甲", "-", "07:00", "0"]])
        found = builder.collect_versions(self.directory, 1)
        self.assertEqual([version for version, _ in found], ["2003.11.25"])

    def test_empty_directory_is_an_error(self) -> None:
        with self.assertRaises(ValueError):
            builder.collect_versions(self.directory, None)

    def test_table_name_is_quoted(self) -> None:
        # 表名带点，不转义会被 SQLite 当成 schema 分隔符。
        self.assertEqual(builder.table_name("2003.11.25"), "timetable_2003.11.25")
        self.assertEqual(builder.quote("timetable_2003.11.25"), '"timetable_2003.11.25"')


if __name__ == "__main__":
    unittest.main()
