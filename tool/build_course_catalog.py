#!/usr/bin/env python3
"""Build the app's compact course index and copy its state tee files."""

import argparse
import csv
from datetime import date
import json
from pathlib import Path

DATA_COLUMNS = [
    "course_id",
    "state",
    "tee_name",
    "gender",
    "par",
    "course_rating",
    "bogey_rating",
    "slope_rating",
    "rating_f9",
    "rating_b9",
    "front9_rating",
    "front9_slope",
    "back9_rating",
    "back9_slope",
    "bogey_f9",
    "bogey_b9",
    "front9_raw",
    "back9_raw",
]
INDEX_COLUMNS = {"facility_name", "course_name", "city"}


def display_name(facility: str, course: str) -> str:
    prefix = f"{facility} - "
    if course.casefold().startswith(prefix.casefold()):
        course = course[len(prefix) :].strip()
    return course or facility


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path, help="Directory containing tees_STATE.csv files")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/course_catalog"),
        help="App asset directory",
    )
    args = parser.parse_args()

    files = sorted(args.source.glob("tees_*.csv"))
    if not files:
        raise SystemExit(f"No tees_STATE.csv files found under {args.source}")

    state_files: dict[str, str] = {}
    courses: dict[tuple[str, str], tuple[str, str, str]] = {}
    total_rows = 0
    args.output.mkdir(parents=True, exist_ok=True)

    for source_file in files:
        with source_file.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            columns = set(reader.fieldnames or [])
            missing = set(DATA_COLUMNS) | INDEX_COLUMNS
            missing -= columns
            if missing:
                raise SystemExit(
                    f"{source_file.name} is missing columns: {', '.join(sorted(missing))}"
                )
            destination = args.output / source_file.name
            with destination.open("w", newline="", encoding="utf-8") as output:
                writer = csv.DictWriter(output, fieldnames=DATA_COLUMNS)
                writer.writeheader()
                for row in reader:
                    writer.writerow(
                        {name: row.get(name) or "" for name in DATA_COLUMNS}
                    )
                    state = (row.get("state") or "").strip().upper()
                    course_id = (row.get("course_id") or "").strip()
                    facility = (row.get("facility_name") or "").strip()
                    course = display_name(
                        facility, (row.get("course_name") or "").strip()
                    )
                    city = (row.get("city") or "").strip()
                    if not all((state, course_id, facility, course)):
                        continue
                    previous_file = state_files.setdefault(state, source_file.name)
                    if previous_file != source_file.name:
                        raise SystemExit(
                            f"State {state} appears in both {previous_file} and "
                            f"{source_file.name}"
                        )
                    key = (state, course_id)
                    metadata = (facility, course, city)
                    previous = courses.setdefault(key, metadata)
                    if previous != metadata:
                        raise SystemExit(
                            f"Conflicting course metadata for {state} / {course_id}"
                        )
                    total_rows += 1

    payload = {
        "source": "USGA National Course Rating Database",
        "generatedAt": date.today().isoformat(),
        "teeRecordCount": total_rows,
        "stateFiles": dict(sorted(state_files.items())),
        "courses": [
            [state, course_id, *metadata]
            for (state, course_id), metadata in sorted(
                courses.items(), key=lambda item: (item[0][0], item[1][1].casefold())
            )
        ],
    }
    index_path = args.output / "index.json"
    index_path.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        f"Built {len(courses):,} course records and copied {len(files)} state files "
        f"({total_rows:,} tee rows) to {args.output}"
    )


if __name__ == "__main__":
    main()
