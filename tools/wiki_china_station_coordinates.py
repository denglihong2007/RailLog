#!/usr/bin/env python3
"""Export coordinates for Chinese railway stations from Chinese Wikipedia.

The script uses the public MediaWiki API and only depends on Python's standard
library. By default it recursively walks Wikipedia's China railway-station
categories and writes an Excel-friendly UTF-8 CSV file.
"""

from __future__ import annotations

import argparse
import csv
import http.client
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import deque
from pathlib import Path
from typing import Any, Iterable, Iterator


DEFAULT_API_URL = "https://zh.wikipedia.org/w/api.php"
DEFAULT_SPARQL_URL = "https://query.wikidata.org/sparql"
DEFAULT_OUTPUT = "coordinates.csv"
USER_AGENT = (
    "ChinaRailwayStationCoordinateExporter/1.0 "
    "(educational data export; MediaWiki API client)"
)

# Railway station articles normally end with one of these terms. Parenthetical
# disambiguators are accepted, for example "东站（郑州地铁）".
STATION_TITLE_RE = re.compile(
    r"(?:站|乘降所|线路所|信号场|操车场)"
    r"(?:（[^）]+）|\s*\([^)]*\))?$"
)
WKT_POINT_RE = re.compile(r"^Point\(([-+0-9.eE]+)\s+([-+0-9.eE]+)\)$")
URBAN_RAIL_KEYWORDS = (
    "地铁",
    "地鐵",
    "轨道交通",
    "軌道交通",
    "轻轨",
    "輕軌",
    "市铁",
    "市鐵",
    "有轨电车",
    "有軌電車",
    " metro ",
    " subway ",
    " tram ",
    " light rail ",
)
URBAN_RAIL_TYPE_IDS = {"Q928830", "Q1793804", "Q2175765"}


class MediaWikiClient:
    def __init__(
        self,
        api_url: str,
        delay: float = 0.1,
        timeout: float = 30.0,
        retries: int = 4,
    ) -> None:
        self.api_url = api_url
        self.delay = delay
        self.timeout = timeout
        self.retries = retries

    def request(self, params: dict[str, Any]) -> dict[str, Any]:
        query = {
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "maxlag": "5",
            **params,
        }
        url = f"{self.api_url}?{urllib.parse.urlencode(query)}"
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})

        for attempt in range(self.retries + 1):
            try:
                if self.delay:
                    time.sleep(self.delay)
                with urllib.request.urlopen(request, timeout=self.timeout) as response:
                    return json.load(response)
            except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
                if attempt >= self.retries:
                    raise RuntimeError(f"MediaWiki API request failed: {exc}") from exc
                time.sleep(min(2**attempt, 8))

        raise AssertionError("unreachable")

    def page_links(self, title: str) -> Iterator[str]:
        continuation: dict[str, Any] = {}
        while True:
            data = self.request(
                {
                    "prop": "links",
                    "titles": title,
                    "plnamespace": "0",
                    "pllimit": "max",
                    **continuation,
                }
            )
            pages = data.get("query", {}).get("pages", [])
            if not pages or pages[0].get("missing"):
                raise RuntimeError(f"Wikipedia page does not exist: {title}")
            for link in pages[0].get("links", []):
                yield link["title"]

            continuation = data.get("continue", {})
            if not continuation:
                return

    def category_members(self, title: str) -> Iterator[dict[str, Any]]:
        continuation: dict[str, Any] = {}
        while True:
            data = self.request(
                {
                    "list": "categorymembers",
                    "cmtitle": title,
                    "cmnamespace": "0|14",
                    "cmtype": "page|subcat",
                    "cmlimit": "max",
                    **continuation,
                }
            )
            for member in data.get("query", {}).get("categorymembers", []):
                yield member

            continuation = data.get("continue", {})
            if not continuation:
                return

    def coordinates(self, titles: list[str]) -> dict[str, dict[str, Any]]:
        """Return coordinate/API metadata keyed by each requested title."""
        data = self.request(
            {
                "prop": "coordinates|info",
                "titles": "|".join(titles),
                "redirects": "1",
                "colimit": "max",
                "coprimary": "primary",
            }
        )
        query = data.get("query", {})

        # MediaWiki reports normalization and redirects separately. Build a
        # chain so a requested title can be matched to the final returned page.
        aliases: dict[str, str] = {}
        for item in query.get("normalized", []):
            aliases[item["from"]] = item["to"]
        for item in query.get("redirects", []):
            aliases[item["from"]] = item["to"]

        pages_by_title = {
            page["title"]: page for page in query.get("pages", [])
        }
        result: dict[str, dict[str, Any]] = {}
        for requested_title in titles:
            resolved_title = requested_title
            seen: set[str] = set()
            while resolved_title in aliases and resolved_title not in seen:
                seen.add(resolved_title)
                resolved_title = aliases[resolved_title]
            result[requested_title] = pages_by_title.get(
                resolved_title,
                {"title": resolved_title, "missing": True},
            )
        return result


def is_station_title(title: str) -> bool:
    return bool(STATION_TITLE_RE.search(title)) and not title.endswith("车站列表")


def is_urban_rail_title(title: str) -> bool:
    normalized = f" {title.casefold()} "
    return any(keyword in normalized for keyword in URBAN_RAIL_KEYWORDS)


def is_station_list_title(title: str) -> bool:
    compact = title.replace(" ", "")
    return "车站列表" in compact or "铁路车站列表" in compact


def discover_station_titles(
    client: MediaWikiClient,
    start_page: str,
    max_depth: int,
) -> tuple[set[str], dict[str, set[str]], list[str]]:
    queue: deque[tuple[str, int]] = deque([(start_page, 0)])
    visited_lists: set[str] = set()
    station_sources: dict[str, set[str]] = {}

    while queue:
        list_title, depth = queue.popleft()
        if list_title in visited_lists:
            continue
        visited_lists.add(list_title)
        print(
            f"[{len(visited_lists)}] Reading list (depth {depth}): {list_title}",
            file=sys.stderr,
        )

        for linked_title in client.page_links(list_title):
            if is_station_title(linked_title):
                station_sources.setdefault(linked_title, set()).add(list_title)
            if (
                depth < max_depth
                and linked_title not in visited_lists
                and is_station_list_title(linked_title)
            ):
                queue.append((linked_title, depth + 1))

    return set(station_sources), station_sources, sorted(visited_lists)


def discover_station_titles_from_category(
    client: MediaWikiClient,
    start_category: str,
    max_depth: int,
) -> tuple[set[str], dict[str, set[str]], list[str]]:
    if not start_category.startswith("Category:"):
        start_category = f"Category:{start_category}"

    queue: deque[tuple[str, int]] = deque([(start_category, 0)])
    visited_categories: set[str] = set()
    station_sources: dict[str, set[str]] = {}

    while queue:
        category_title, depth = queue.popleft()
        if category_title in visited_categories:
            continue
        visited_categories.add(category_title)
        print(
            f"[{len(visited_categories)}] Reading category "
            f"(depth {depth}): {category_title}",
            file=sys.stderr,
        )

        found_member = False
        for member in client.category_members(category_title):
            found_member = True
            linked_title = member["title"]
            namespace = member["ns"]
            if namespace == 0 and is_station_title(linked_title):
                station_sources.setdefault(linked_title, set()).add(category_title)
            elif (
                namespace == 14
                and depth < max_depth
                and linked_title not in visited_categories
            ):
                queue.append((linked_title, depth + 1))

        if not found_member and category_title == start_category:
            raise RuntimeError(f"Wikipedia category is empty or missing: {start_category}")

    return set(station_sources), station_sources, sorted(visited_categories)


def chunks(items: list[str], size: int) -> Iterable[list[str]]:
    for index in range(0, len(items), size):
        yield items[index : index + size]


def fetch_wikidata_rows(
    endpoint: str,
    timeout: float = 180.0,
    retries: int = 3,
) -> list[dict[str, Any]]:
    # Q55488 is "railway station" and Q148 is China. The subclass path also
    # includes more specific types such as high-speed railway stations.
    sparql = """
SELECT DISTINCT ?station ?stationLabel ?coord ?article ?type WHERE {
  ?station wdt:P31/wdt:P279* wd:Q55488;
           wdt:P17 wd:Q148;
           wdt:P625 ?coord.
  ?station wdt:P31 ?type.
  OPTIONAL {
    ?article schema:about ?station;
             schema:isPartOf <https://zh.wikipedia.org/>.
  }
  SERVICE wikibase:label {
    bd:serviceParam wikibase:language "zh-hans,zh,en".
  }
}
ORDER BY ?station
""".strip()
    query = urllib.parse.urlencode({"query": sparql, "format": "json"})
    request = urllib.request.Request(
        f"{endpoint}?{query}",
        headers={
            "Accept": "application/sparql-results+json",
            "User-Agent": USER_AGENT,
        },
    )

    data: dict[str, Any] | None = None
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                data = json.load(response)
            break
        except (
            urllib.error.URLError,
            http.client.HTTPException,
            TimeoutError,
            json.JSONDecodeError,
        ) as exc:
            if attempt >= retries:
                raise RuntimeError(f"Wikidata SPARQL request failed: {exc}") from exc
            time.sleep(min(2**attempt, 8))

    if data is None:
        raise AssertionError("unreachable")

    by_entity: dict[str, dict[str, Any]] = {}
    urban_entities: set[str] = set()
    bindings = data.get("results", {}).get("bindings", [])
    for binding in bindings:
        entity_url = binding["station"]["value"]
        qid = entity_url.rsplit("/", 1)[-1]
        type_id = binding.get("type", {}).get("value", "").rsplit("/", 1)[-1]
        if type_id in URBAN_RAIL_TYPE_IDS:
            urban_entities.add(qid)
        match = WKT_POINT_RE.match(binding["coord"]["value"])
        if not match:
            continue
        longitude, latitude = map(float, match.groups())
        article_url = binding.get("article", {}).get("value", "")
        article_title = ""
        if article_url:
            article_title = urllib.parse.unquote(article_url.rsplit("/wiki/", 1)[-1])
            article_title = article_title.replace("_", " ")
        station_name = binding.get("stationLabel", {}).get("value", qid)
        if is_urban_rail_title(station_name) or is_urban_rail_title(article_title):
            urban_entities.add(qid)
            continue

        row = by_entity.setdefault(
            qid,
            {
                "station_name": station_name,
                "resolved_title": article_title or station_name,
                "latitude": latitude,
                "longitude": longitude,
                "coordinate_source": "Wikidata",
                "status": "ok",
                "source_pages": entity_url,
                "wikipedia_url": article_url,
            },
        )
        # DISTINCT can still produce two rows when one item has several
        # coordinates or sitelinks. Prefer the row with a Chinese article.
        if article_url and not row["wikipedia_url"]:
            row["resolved_title"] = article_title
            row["wikipedia_url"] = article_url

    rows = (row for qid, row in by_entity.items() if qid not in urban_entities)
    return sorted(rows, key=lambda row: (row["station_name"], row["resolved_title"]))


def fetch_station_rows(
    client: MediaWikiClient,
    station_titles: set[str],
    station_sources: dict[str, set[str]],
) -> list[dict[str, Any]]:
    titles = sorted(station_titles)
    rows: list[dict[str, Any]] = []
    batch_count = (len(titles) + 49) // 50

    for batch_number, batch in enumerate(chunks(titles, 50), start=1):
        print(
            f"Fetching coordinates: batch {batch_number}/{batch_count}",
            file=sys.stderr,
        )
        pages = client.coordinates(batch)
        for requested_title in batch:
            page = pages[requested_title]
            coordinates = page.get("coordinates", [])
            coordinate = coordinates[0] if coordinates else None
            resolved_title = page.get("title", requested_title)
            if is_urban_rail_title(requested_title) or is_urban_rail_title(
                resolved_title
            ):
                continue
            page_url = ""
            if not page.get("missing"):
                page_url = (
                    "https://zh.wikipedia.org/wiki/"
                    + urllib.parse.quote(resolved_title.replace(" ", "_"), safe="()")
                )

            rows.append(
                {
                    "station_name": requested_title,
                    "resolved_title": resolved_title,
                    "latitude": coordinate.get("lat") if coordinate else None,
                    "longitude": coordinate.get("lon") if coordinate else None,
                    "coordinate_source": coordinate.get("source", "") if coordinate else "",
                    "status": (
                        "page_missing"
                        if page.get("missing")
                        else "ok" if coordinate else "coordinates_missing"
                    ),
                    "source_pages": "; ".join(sorted(station_sources[requested_title])),
                    "wikipedia_url": page_url,
                }
            )

    return rows


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    fieldnames = [
        "station_name",
        "resolved_title",
        "latitude",
        "longitude",
        "coordinate_source",
        "status",
        "source_pages",
        "wikipedia_url",
    ]
    with path.open("w", encoding="utf-8-sig", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def write_json(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8") as output_file:
        json.dump(rows, output_file, ensure_ascii=False, indent=2)
        output_file.write("\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export coordinates of Chinese railway stations from Wikipedia."
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=Path(DEFAULT_OUTPUT),
        help=f"output path (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--format",
        choices=("csv", "json"),
        default="csv",
        help="export format (default: csv)",
    )
    source_group = parser.add_mutually_exclusive_group()
    source_group.add_argument(
        "--start-category",
        help="use a specific Wikipedia category instead of the nationwide Wikidata query",
    )
    source_group.add_argument(
        "--start-page",
        help="use a specific Wikipedia station-list article instead of categories",
    )
    parser.add_argument(
        "--max-depth",
        type=int,
        default=3,
        help="maximum category/list recursion depth (default: 3)",
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.1,
        help="delay before each API request in seconds (default: 0.1)",
    )
    parser.add_argument("--api-url", default=DEFAULT_API_URL, help=argparse.SUPPRESS)
    parser.add_argument(
        "--sparql-url", default=DEFAULT_SPARQL_URL, help=argparse.SUPPRESS
    )
    args = parser.parse_args()
    if args.max_depth < 0:
        parser.error("--max-depth must be at least 0")
    if args.delay < 0:
        parser.error("--delay must be at least 0")
    return args


def main() -> int:
    args = parse_args()
    client = MediaWikiClient(api_url=args.api_url, delay=args.delay)

    try:
        if args.start_page:
            titles, station_sources, source_pages = discover_station_titles(
                client,
                start_page=args.start_page,
                max_depth=args.max_depth,
            )
            if not titles:
                raise RuntimeError("No station articles were found from the selected list page")
            print(
                f"Discovered {len(titles)} stations from "
                f"{len(source_pages)} source pages.",
                file=sys.stderr,
            )
            rows = fetch_station_rows(client, titles, station_sources)
        elif args.start_category:
            titles, station_sources, source_pages = (
                discover_station_titles_from_category(
                    client,
                    start_category=args.start_category,
                    max_depth=args.max_depth,
                )
            )
            if not titles:
                raise RuntimeError("No station articles were found from the selected category")
            print(
                f"Discovered {len(titles)} stations from "
                f"{len(source_pages)} source pages.",
                file=sys.stderr,
            )
            rows = fetch_station_rows(client, titles, station_sources)
        else:
            print("Querying Wikidata for railway stations in China...", file=sys.stderr)
            rows = fetch_wikidata_rows(args.sparql_url)
            if not rows:
                raise RuntimeError("The Wikidata query returned no stations")
    except (RuntimeError, urllib.error.URLError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.format == "json":
        write_json(args.output, rows)
    else:
        write_csv(args.output, rows)

    found = sum(row["status"] == "ok" for row in rows)
    missing = len(rows) - found
    print(
        f"Exported {len(rows)} stations to {args.output} "
        f"({found} with coordinates, {missing} without coordinates)."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
