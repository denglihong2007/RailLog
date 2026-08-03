import argparse
from collections import Counter
import json
import sqlite3
from pathlib import Path
from typing import Any


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


def find_year_file(directory: Path, year: int) -> Path:
    matches = list(directory.glob(f"*_{year}-*.json"))
    if len(matches) != 1:
        raise ValueError(
            f"Expected one JSON file for {year} in {directory}, found {len(matches)}"
        )
    return matches[0]


def text(value: Any) -> str:
    return "" if value is None else str(value).strip()


def load_rows(path: Path) -> tuple[list[tuple[Any, ...]], int]:
    with path.open(encoding="utf-8") as source:
        data = json.load(source)
    if not isinstance(data, dict):
        raise ValueError(f"{path.name}: top-level JSON value must be an object")

    rows: list[tuple[Any, ...]] = []
    for key, train in data.items():
        if not isinstance(train, dict):
            raise ValueError(f"{path.name}: train {key!r} must be an object")
        train_code = text(key).upper()
        if not train_code:
            raise ValueError(f"{path.name}: train code cannot be empty")
        declared_code = text(train.get("train_no")).upper()
        if declared_code != train_code:
            raise ValueError(
                f"{path.name}: key {train_code!r} does not match train_no {declared_code!r}"
            )
        stops = train.get("stop_list")
        if not isinstance(stops, list):
            raise ValueError(f"{path.name}: stop_list for {train_code} must be a list")

        for order_id, stop in enumerate(stops, start=1):
            if not isinstance(stop, dict):
                raise ValueError(
                    f"{path.name}: stop {order_id} for {train_code} must be an object"
                )
            station = text(stop.get("stop_name"))
            if not station:
                raise ValueError(
                    f"{path.name}: stop {order_id} for {train_code} has no name"
                )
            mileage_value = stop.get("mile_estimate", 0)
            try:
                mileage = float(mileage_value or 0)
            except (TypeError, ValueError) as error:
                raise ValueError(
                    f"{path.name}: invalid mileage for {train_code} stop {order_id}"
                ) from error
            rows.append(
                (
                    train_code,
                    "",
                    order_id,
                    station,
                    "" if order_id == 1 else text(stop.get("arrive_time")),
                    ""
                    if order_id == len(stops)
                    else text(stop.get("start_time")),
                    mileage,
                )
            )
    return rows, len(data)


def table_name(year: int) -> str:
    return f"timetable_{year}"


def quote(identifier: str) -> str:
    return '"' + identifier.replace('"', '""') + '"'


def create_table(connection: sqlite3.Connection, name: str) -> None:
    connection.execute(f"CREATE TABLE {quote(name)} ({TABLE_SCHEMA})")


def validate_table(
    connection: sqlite3.Connection, name: str, expected_rows: int
) -> None:
    columns = tuple(
        row[1] for row in connection.execute(f"PRAGMA table_info({quote(name)})")
    )
    if columns != TABLE_COLUMNS:
        raise ValueError(f"Unexpected schema for {name}: {columns}")
    actual_rows = connection.execute(
        f"SELECT COUNT(*) FROM {quote(name)}"
    ).fetchone()[0]
    if actual_rows != expected_rows:
        raise ValueError(
            f"Unexpected row count for {name}: {actual_rows}, expected {expected_rows}"
        )
    invalid_first_stops = connection.execute(
        f"SELECT COUNT(*) FROM {quote(name)} "
        "WHERE OrderID = 1 AND ArriveTime <> ''"
    ).fetchone()[0]
    invalid_last_stops = connection.execute(
        f"""
        SELECT COUNT(*)
        FROM {quote(name)} AS timetable
        JOIN (
            SELECT TrainCode1, MAX(OrderID) AS last_order
            FROM {quote(name)}
            GROUP BY TrainCode1
        ) AS bounds
          ON bounds.TrainCode1 = timetable.TrainCode1
         AND bounds.last_order = timetable.OrderID
        WHERE timetable.StartTime <> ''
        """
    ).fetchone()[0]
    if invalid_first_stops or invalid_last_stops:
        raise ValueError(
            f"Invalid endpoint times for {name}: "
            f"first={invalid_first_stops}, last={invalid_last_stops}"
        )


def validate_indexes(connection: sqlite3.Connection, year: int) -> None:
    target = table_name(year)
    actual = {
        row[0]
        for row in connection.execute(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ?",
            (target,),
        )
    }
    expected = {f"idx_{year}_traincode1", f"idx_{year}_traincode2"}
    if actual != expected:
        raise ValueError(f"Unexpected indexes for {target}: {sorted(actual)}")


def replace_tables(
    database: Path,
    year_rows: dict[int, list[tuple[Any, ...]]],
    remove_years: list[int],
) -> None:
    staging_names = {year: f"{table_name(year)}_staging" for year in year_rows}
    with sqlite3.connect(database) as connection:
        connection.execute("BEGIN IMMEDIATE")
        try:
            for year, rows in year_rows.items():
                staging = staging_names[year]
                connection.execute(f"DROP TABLE IF EXISTS {quote(staging)}")
                create_table(connection, staging)
                connection.executemany(
                    f"""
                    INSERT INTO {quote(staging)}
                    ({', '.join(quote(column) for column in TABLE_COLUMNS)})
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    rows,
                )
                validate_table(connection, staging, len(rows))

            for year in {*remove_years, *year_rows.keys()}:
                connection.execute(
                    f"DROP TABLE IF EXISTS {quote(table_name(year))}"
                )

            for year, staging in staging_names.items():
                target = table_name(year)
                connection.execute(
                    f"ALTER TABLE {quote(staging)} RENAME TO {quote(target)}"
                )
                connection.execute(
                    f"CREATE INDEX {quote(f'idx_{year}_traincode1')} "
                    f"ON {quote(target)} ({quote('TrainCode1')}, {quote('OrderID')})"
                )
                connection.execute(
                    f"CREATE INDEX {quote(f'idx_{year}_traincode2')} "
                    f"ON {quote(target)} ({quote('TrainCode2')}, {quote('OrderID')})"
                )
                validate_table(connection, target, len(year_rows[year]))
                validate_indexes(connection, year)

            integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
            if integrity != "ok":
                raise ValueError(f"SQLite integrity check failed: {integrity}")
            connection.commit()
        except BaseException:
            connection.rollback()
            raise
        connection.execute("VACUUM")


def database_summary(database: Path) -> list[tuple[int, int]]:
    with sqlite3.connect(database) as connection:
        result = []
        for (name,) in connection.execute(
            """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name LIKE 'timetable_%'
            ORDER BY name
            """
        ):
            year = int(name.removeprefix("timetable_"))
            count = connection.execute(
                f"SELECT COUNT(*) FROM {quote(name)}"
            ).fetchone()[0]
            result.append((year, count))
        return result


def inspect_endpoint_convention(database: Path, years: list[int]) -> None:
    with sqlite3.connect(database) as connection:
        for year in years:
            name = table_name(year)
            rows = connection.execute(
                f"""
                SELECT TrainCode1, ArriveTime, StartTime
                FROM {quote(name)}
                ORDER BY TrainCode1, OrderID, rowid
                """
            )
            first_arrivals: Counter[str] = Counter()
            last_departures: Counter[str] = Counter()
            previous_code = None
            previous_departure = ""
            for train_code, arrival, departure in rows:
                if train_code != previous_code:
                    if previous_code is not None:
                        last_departures[previous_departure] += 1
                    first_arrivals[arrival] += 1
                    previous_code = train_code
                previous_departure = departure
            if previous_code is not None:
                last_departures[previous_departure] += 1
            print(
                f"{year} first ArriveTime: {first_arrivals.most_common(10)}"
            )
            print(
                f"{year} last StartTime: {last_departures.most_common(10)}"
            )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Replace annual timetable tables from RailGo JSON exports."
    )
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--data-directory", type=Path, required=True)
    parser.add_argument("--years", type=int, nargs="+", required=True)
    parser.add_argument("--remove-years", type=int, nargs="*", default=[])
    parser.add_argument("--inspect-endpoints", type=int, nargs="*", default=[])
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    if args.inspect_endpoints:
        inspect_endpoint_convention(args.database, args.inspect_endpoints)

    year_rows = {}
    for year in args.years:
        source = find_year_file(args.data_directory, year)
        rows, train_count = load_rows(source)
        year_rows[year] = rows
        print(f"{year}: {source.name}, trains={train_count}, rows={len(rows)}")

    if not args.apply:
        print("Validation complete; database was not changed (pass --apply to update).")
        return

    replace_tables(args.database, year_rows, args.remove_years)
    print("Database updated:")
    for year, count in database_summary(args.database):
        print(f"  {year}: {count} rows")


if __name__ == "__main__":
    main()
