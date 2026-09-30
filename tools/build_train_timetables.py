"""从 skb「成果」CSV 快照构建按日期版本化的历史时刻表库。

数据源是一批 `YYYY.MM.DD.csv` 快照（UTF-8 带 BOM，列
`train_no,seq,station,arrival,departure,km`），产出是与旧 `train_timetables.db` 同构的
SQLite 库，只是把「一版本一表」的键从年份换成快照日期：`timetable_2003.11.25`。
点号在标识符里必须转义，字典序恰好等于时间序，所以 `ORDER BY name` 直接可用。

车次号归一化是这块最容易出错的地方，规则只有一条：

    车次号的每一段必然是「前导字母 + 数字」，最后一位必然是数字。

按 `^([A-Z]*)(\\d+)` 取前缀即可，多出来的都是后缀：`K43A`、`D5467B`、`1433B`、
以及括号脏数据 `K7931(空)`。实测 255 个文件 13.8M 行的每一段都能匹配，没有例外，
因此这条规则无条件下发。副作用是 `K43A`/`K43B` 会塌缩成同一个 `K43`，此时按需求
「重复/有后缀一律去后缀或者选择第一个时刻表」只保留第一块。

`train_no` 里字面含 `/` 的（`1008/1009`）是同一趟车双向两个号，拆成 TrainCode1/TrainCode2；
拆开后两段相同的（上面那个 `K7931/K7931(空)`）塌缩成单码。
注意只按字面 `/` 拆分：源 CSV 里 `7273` 和 `7274` 是两个独立车次，旧库把它们配成一对
导致 OrderID 交错重复，这里不能重蹈。

用法：

    # 干跑：只解析、归一化并报告行数，不落盘
    python tools/build_train_timetables.py --source-dir <成果> --database <out.db>

    # 真正建库（并行）
    python tools/build_train_timetables.py --source-dir <成果> --database <out.db> --apply

    # 冒烟：只建前 3 个版本
    python tools/build_train_timetables.py --source-dir <成果> --database <out.db> \\
        --limit-versions 3 --apply
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import shutil
import sqlite3
import sys
import tempfile
import time
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

TABLE_COLUMNS = (
    "TrainCode1",
    "TrainCode2",
    "OrderID",
    "TrainStation",
    "ArriveTime",
    "StartTime",
    "Mileage",
)

TABLE_SCHEMA = """
    TrainCode1 TEXT NOT NULL,
    TrainCode2 TEXT NOT NULL DEFAULT '',
    OrderID INTEGER NOT NULL,
    TrainStation TEXT NOT NULL,
    ArriveTime TEXT NOT NULL DEFAULT '',
    StartTime TEXT NOT NULL DEFAULT '',
    Mileage REAL NOT NULL DEFAULT 0
"""

# 快照文件名即版本号，形如 2003.11.25。
VERSION_PATTERN = re.compile(r"^\d{4}\.\d{2}\.\d{2}$")

# 「前导字母 + 数字」，多出来的部分一律是后缀。
TRAIN_CODE_PATTERN = re.compile(r"^([A-Z]*)(\d+)")

HEADER = ["train_no", "seq", "station", "arrival", "departure", "km"]

# 大库写入：构建期不需要持久性保证，关掉 journal 能省掉大量 fsync。
BUILD_PRAGMAS = (
    "PRAGMA journal_mode = OFF",
    "PRAGMA synchronous = OFF",
    "PRAGMA temp_store = MEMORY",
    "PRAGMA cache_size = -262144",
)


def quote(identifier: str) -> str:
    """SQLite 标识符转义。表名带点，必须走这里。"""
    return '"' + identifier.replace('"', '""') + '"'


def version_of(path: Path) -> str | None:
    """从 `2003.11.25.csv` 取出 `2003.11.25`；不符合命名的返回 None。"""
    if path.suffix.lower() != ".csv":
        return None
    stem = path.stem
    return stem if VERSION_PATTERN.fullmatch(stem) else None


def table_name(version: str) -> str:
    return f"timetable_{version}"


def normalize_train_code(part: str) -> str | None:
    """取「前导字母 + 数字」，截掉后缀。匹配不上返回 None。"""
    match = TRAIN_CODE_PATTERN.match(part)
    if match is None:
        return None
    return f"{match.group(1)}{match.group(2)}"


def split_train_codes(raw: str) -> tuple[str, str] | None:
    """`1008/1009` → (1008, 1009)；两段相同则第二段留空。"""
    parts = [normalize_train_code(part) for part in raw.split("/")]
    if not parts or parts[0] is None:
        return None
    first = parts[0]
    second = parts[1] if len(parts) > 1 and parts[1] is not None else ""
    if second == first:
        second = ""
    return first, second


def normalize_time(value: str) -> str:
    """`-` 和空白都表示「无时刻」，统一成空串；其余保留原文。"""
    text = (value or "").strip()
    if not text or set(text) <= {"-"}:
        return ""
    return text


def normalize_mileage(value: str) -> float:
    text = (value or "").strip()
    if not text or text == "-":
        return 0.0
    try:
        return float(text)
    except ValueError as error:
        raise ValueError(f"invalid mileage {value!r}") from error


def read_csv_rows(path: Path):
    """流式产出数据行，跳过表头与空行。"""
    with path.open(encoding="utf-8-sig", newline="") as source:
        reader = csv.reader(source)
        header = next(reader, None)
        if header is None:
            raise ValueError(f"{path.name}: empty file")
        if [column.strip() for column in header] != HEADER:
            raise ValueError(f"{path.name}: unexpected header {header!r}")
        for row in reader:
            if row and any(field.strip() for field in row):
                yield row


def load_version(path: Path) -> tuple[list[tuple], dict[str, int]]:
    """解析一个快照，返回 (行元组, 统计)。只保留每个车次的第一块。

    块边界靠 `seq` 连续递增判断：`seq` 重新回到 1 就说明同一车次的第二份时刻表开始了，
    按需求丢弃。归一化让 `K43A`/`K43B` 变成同一个键，所以这条同时覆盖了「去后缀后重复」。
    """
    blocks: dict[tuple[str, str], list[tuple]] = {}
    finished: set[tuple[str, str]] = set()
    rows: list[tuple] = []
    stats = {"trains": 0, "extra_blocks": 0, "extra_rows": 0}

    for row in read_csv_rows(path):
        if len(row) < 6:
            raise ValueError(f"{path.name}: expected 6 columns, got {row!r}")
        codes = split_train_codes(row[0].strip().upper())
        if codes is None:
            raise ValueError(f"{path.name}: unrecognised train code {row[0]!r}")
        key = codes
        if key in finished:
            stats["extra_rows"] += 1
            continue

        block = blocks.get(key)
        if block is None:
            blocks[key] = [row]
            continue

        # 同一键的行是连续的，seq 递增即还在同一块内；回退说明新块开始。
        try:
            seq = int(row[1])
        except ValueError:
            seq = len(block) + 1
        if seq == len(block) + 1:
            block.append(row)
        else:
            finished.add(key)
            stats["extra_blocks"] += 1
            stats["extra_rows"] += 1

    for (code1, code2), block in blocks.items():
        stats["trains"] += 1
        for order_id, row in enumerate(block, start=1):
            station = row[2].strip()
            if not station:
                raise ValueError(f"{path.name}: {code1} stop {order_id} has no station")
            arrive = "" if order_id == 1 else normalize_time(row[3])
            start = "" if order_id == len(block) else normalize_time(row[4])
            rows.append(
                (
                    code1,
                    code2,
                    order_id,
                    station,
                    arrive,
                    start,
                    normalize_mileage(row[5]),
                )
            )

    return rows, stats


def create_table(connection: sqlite3.Connection, name: str) -> None:
    connection.execute(f"CREATE TABLE {quote(name)} ({TABLE_SCHEMA})")


def insert_rows(
    connection: sqlite3.Connection, name: str, rows: list[tuple], batch: int = 10_000
) -> None:
    columns = ", ".join(quote(column) for column in TABLE_COLUMNS)
    placeholders = ", ".join("?" * len(TABLE_COLUMNS))
    statement = f"INSERT INTO {quote(name)} ({columns}) VALUES ({placeholders})"
    for offset in range(0, len(rows), batch):
        connection.executemany(statement, rows[offset : offset + batch])


def create_indexes(connection: sqlite3.Connection, version: str, name: str) -> None:
    connection.execute(
        f"CREATE INDEX {quote(f'idx_{version}_traincode1')} "
        f"ON {quote(name)} ({quote('TrainCode1')}, {quote('OrderID')})"
    )
    connection.execute(
        f"CREATE INDEX {quote(f'idx_{version}_traincode2')} "
        f"ON {quote(name)} ({quote('TrainCode2')}, {quote('OrderID')})"
    )


def build_part(payload: tuple[str, list[tuple[str, str, int]]]):
    """worker：把自己分到的版本写进独立 part 库（只建表，索引留到最后统一建）。"""
    part_path, versions = payload
    counts: dict[str, int] = {}
    stats = {"extra_blocks": 0, "extra_rows": 0}
    with sqlite3.connect(part_path) as connection:
        for pragma in BUILD_PRAGMAS:
            connection.execute(pragma)
        connection.execute("BEGIN")
        for version, source, _size in versions:
            rows, version_stats = load_version(Path(source))
            stats["extra_blocks"] += version_stats["extra_blocks"]
            stats["extra_rows"] += version_stats["extra_rows"]
            name = table_name(version)
            create_table(connection, name)
            insert_rows(connection, name, rows)
            counts[version] = len(rows)
        connection.commit()
    return part_path, counts, stats


def chunk_versions(
    versions: list[tuple[str, Path]], jobs: int
) -> list[list[tuple[str, str, int]]]:
    """按文件大小做贪心装箱，让各 worker 的活尽量一样重。"""
    jobs = max(1, min(jobs, len(versions)))
    sized = sorted(versions, key=lambda item: item[1].stat().st_size, reverse=True)
    buckets: list[list[tuple[str, str, int]]] = [[] for _ in range(jobs)]
    loads = [0] * jobs
    for version, path in sized:
        target = loads.index(min(loads))
        size = path.stat().st_size
        buckets[target].append((version, str(path), size))
        loads[target] += size
    return [bucket for bucket in buckets if bucket]


def existing_versions(database: Path) -> set[str]:
    if not database.exists():
        return set()
    with sqlite3.connect(database) as connection:
        names = [
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            )
        ]
    return {
        name.removeprefix("timetable_")
        for name in names
        if name.startswith("timetable_")
    }


def merge_parts(database: Path, parts: list[str]) -> None:
    """把各 part 库的表整表搬进最终库。先插后建索引远快于边插边维护索引。"""
    if not parts:
        return
    with sqlite3.connect(database) as connection:
        for pragma in BUILD_PRAGMAS:
            connection.execute(pragma)
        for index, part in enumerate(parts):
            alias = f"part{index}"
            connection.execute(f"ATTACH DATABASE ? AS {alias}", (part,))
            names = [
                row[0]
                for row in connection.execute(
                    f"SELECT name FROM {alias}.sqlite_master "
                    "WHERE type = 'table' AND name LIKE 'timetable_%'"
                )
            ]
            for name in names:
                connection.execute(
                    f"INSERT INTO main.{quote(name)} SELECT * FROM {alias}.{quote(name)}"
                )
            connection.commit()
            connection.execute(f"DETACH DATABASE {alias}")


def validate_database(database: Path, expected: dict[str, int]) -> None:
    with sqlite3.connect(database) as connection:
        for version, count in expected.items():
            name = table_name(version)
            columns = tuple(
                row[1] for row in connection.execute(f"PRAGMA table_info({quote(name)})")
            )
            if columns != TABLE_COLUMNS:
                raise ValueError(f"Unexpected schema for {name}: {columns}")
            actual = connection.execute(
                f"SELECT COUNT(*) FROM {quote(name)}"
            ).fetchone()[0]
            if actual != count:
                raise ValueError(
                    f"Unexpected row count for {name}: {actual}, expected {count}"
                )
            bad_first = connection.execute(
                f"SELECT COUNT(*) FROM {quote(name)} "
                "WHERE OrderID = 1 AND ArriveTime <> ''"
            ).fetchone()[0]
            bad_last = connection.execute(
                f"""
                SELECT COUNT(*)
                FROM {quote(name)} AS timetable
                JOIN (
                    SELECT TrainCode1, TrainCode2, MAX(OrderID) AS last_order
                    FROM {quote(name)}
                    GROUP BY TrainCode1, TrainCode2
                ) AS bounds
                  ON bounds.TrainCode1 = timetable.TrainCode1
                 AND bounds.TrainCode2 = timetable.TrainCode2
                 AND bounds.last_order = timetable.OrderID
                WHERE timetable.StartTime <> ''
                """
            ).fetchone()[0]
            if bad_first or bad_last:
                raise ValueError(
                    f"Invalid endpoint times for {name}: "
                    f"first={bad_first}, last={bad_last}"
                )
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise ValueError(f"SQLite integrity check failed: {integrity}")


def collect_versions(source_dir: Path, limit: int | None) -> list[tuple[str, Path]]:
    versions: list[tuple[str, Path]] = []
    for path in sorted(source_dir.glob("*.csv")):
        version = version_of(path)
        if version is not None:
            versions.append((version, path))
    versions.sort(key=lambda item: item[0])
    if limit is not None:
        versions = versions[:limit]
    if not versions:
        raise ValueError(f"No YYYY.MM.DD.csv snapshots found in {source_dir}")
    return versions


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build date-versioned timetable tables from 成果 CSV snapshots."
    )
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument(
        "--jobs",
        type=int,
        default=min(255, os.cpu_count() or 1),
        help="并行 worker 数，默认 min(255, CPU 核数)",
    )
    parser.add_argument("--limit-versions", type=int, default=None)
    parser.add_argument(
        "--replace",
        action="store_true",
        help="覆盖已存在的版本表；默认跳过，便于只补新增快照",
    )
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    source_dir: Path = args.source_dir
    if not source_dir.is_dir():
        raise SystemExit(f"source directory not found: {source_dir}")
    database: Path = args.database

    versions = collect_versions(source_dir, args.limit_versions)
    print(f"{len(versions)} 个快照，范围 {versions[0][0]} → {versions[-1][0]}")

    present = set() if args.replace else existing_versions(database)
    pending = [item for item in versions if item[0] not in present]
    if present:
        print(f"已存在 {len(present)} 个版本，跳过（--replace 可覆盖）")
    if not pending:
        print("没有需要构建的版本。")
        return

    if not args.apply:
        started = time.perf_counter()
        total_rows = 0
        total_trains = 0
        extra_blocks = 0
        extra_rows = 0
        for _version, path in pending:
            rows, stats = load_version(path)
            total_rows += len(rows)
            total_trains += stats["trains"]
            extra_blocks += stats["extra_blocks"]
            extra_rows += stats["extra_rows"]
        elapsed = time.perf_counter() - started
        print(
            f"干跑完成：{len(pending)} 个版本，{total_trains} 个车次块，{total_rows} 行"
            f"（{elapsed:.1f}s）"
        )
        print(
            f"归一化+去重丢弃：{extra_blocks} 个重复块 / {extra_rows} 行"
        )
        print("数据库未改动；加 --apply 才会建库。")
        return

    scratch = Path(tempfile.mkdtemp(prefix="timetable_parts_"))
    try:
        buckets = chunk_versions(pending, args.jobs)
        print(f"并行构建：{len(buckets)} 个 worker")
        started = time.perf_counter()
        counts: dict[str, int] = {}
        extra_blocks = 0
        extra_rows = 0
        with ProcessPoolExecutor(max_workers=len(buckets)) as pool:
            payloads = [
                (str(scratch / f"part_{index}.db"), bucket)
                for index, bucket in enumerate(buckets)
            ]
            for part_path, part_counts, part_stats in pool.map(build_part, payloads):
                counts.update(part_counts)
                extra_blocks += part_stats["extra_blocks"]
                extra_rows += part_stats["extra_rows"]
        build_elapsed = time.perf_counter() - started
        print(
            f"阶段 1 解析+写 part：{build_elapsed:.1f}s，{len(counts)} 个版本，"
            f"丢弃 {extra_blocks} 个重复块 / {extra_rows} 行"
        )

        database.parent.mkdir(parents=True, exist_ok=True)
        started = time.perf_counter()
        with sqlite3.connect(database) as connection:
            for pragma in BUILD_PRAGMAS:
                connection.execute(pragma)
            for version, _path in pending:
                name = table_name(version)
                # --replace 时旧表还在，先删掉再建。
                connection.execute(f"DROP TABLE IF EXISTS {quote(name)}")
                create_table(connection, name)
            connection.commit()
        merge_parts(database, [str(scratch / f"part_{index}.db") for index in range(len(buckets))])
        merge_elapsed = time.perf_counter() - started
        print(f"阶段 2 合并：{merge_elapsed:.1f}s")

        started = time.perf_counter()
        with sqlite3.connect(database) as connection:
            for pragma in BUILD_PRAGMAS:
                connection.execute(pragma)
            for version, _ in pending:
                name = table_name(version)
                # --replace 时旧索引还在，同名 CREATE INDEX 会冲突。
                connection.execute(f"DROP INDEX IF EXISTS {quote(f'idx_{version}_traincode1')}")
                connection.execute(f"DROP INDEX IF EXISTS {quote(f'idx_{version}_traincode2')}")
                create_indexes(connection, version, name)
            connection.commit()
        index_elapsed = time.perf_counter() - started
        print(f"阶段 3 建索引：{index_elapsed:.1f}s")
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    final_counts = {version: counts[version] for version, _ in pending}
    started = time.perf_counter()
    validate_database(database, final_counts)
    print(f"校验通过（{time.perf_counter() - started:.1f}s）")

    total = sum(final_counts.values())
    size_mb = database.stat().st_size / 1024 / 1024
    print(f"完成：{len(final_counts)} 个版本，{total} 行，{size_mb:.0f}MB → {database}")


if __name__ == "__main__":
    sys.exit(main())
