#!/usr/bin/env python3
"""Apply the best passing GoldBot candidate overrides to the MT5 preset."""

from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def normalize_candidate_name(value: str) -> str:
    for prefix in ("GoldBot-real-", "GoldBot-"):
        if value.startswith(prefix):
            return value[len(prefix) :]
    return value


def load_matrix(path: Path) -> dict[str, dict[str, str]]:
    with path.open(newline="") as handle:
        return {row["name"].strip(): row for row in csv.DictReader(handle)}


def load_evaluation(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as handle:
        return list(csv.DictReader(handle))


def parse_overrides(value: str) -> dict[str, str]:
    overrides: dict[str, str] = {}
    for line in value.replace("\\n", "\n").splitlines():
        line = line.strip()
        if not line:
            continue
        if "=" not in line:
            raise ValueError(f"Invalid override line: {line}")
        key, raw_value = line.split("=", 1)
        overrides[key] = raw_value
    return overrides


def read_preset(path: Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    if not path.exists():
        return rows
    for line in path.read_text().splitlines():
        if not line.strip() or "=" not in line:
            continue
        key, value = line.split("=", 1)
        rows.append((key, value))
    return rows


def write_preset(path: Path, rows: list[tuple[str, str]], overrides: dict[str, str]) -> None:
    seen: set[str] = set()
    output: list[str] = []
    for key, value in rows:
        if key in overrides:
            output.append(f"{key}={overrides[key]}")
            seen.add(key)
        else:
            output.append(f"{key}={value}")
            seen.add(key)
    for key, value in overrides.items():
        if key not in seen:
            output.append(f"{key}={value}")
    path.write_text("\n".join(output) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evaluation", type=Path, default=ROOT / "mt5/backtests/reports/improvement-evaluation.csv")
    parser.add_argument("--matrix", type=Path, default=ROOT / "mt5/backtests/CANDIDATE_MATRIX.csv")
    parser.add_argument("--preset", type=Path, default=ROOT / "mt5/Presets/GoldBot.optimized.set")
    parser.add_argument("--allow-best-fail", action="store_true", help="Apply the top-ranked candidate even if no row passed.")
    args = parser.parse_args()

    matrix = load_matrix(args.matrix)
    rows = load_evaluation(args.evaluation)
    if not rows:
        print(f"No evaluation rows found in {args.evaluation}", file=sys.stderr)
        return 1

    passing = [row for row in rows if row.get("status") == "PASS"]
    if passing:
        selected = passing[0]
    elif args.allow_best_fail:
        selected = rows[0]
    else:
        print("No PASS candidate found. Rerun with --allow-best-fail to apply the top-ranked failed candidate.", file=sys.stderr)
        return 2

    name = normalize_candidate_name(selected["candidate"])
    if name not in matrix:
        print(f"Evaluation candidate is not in matrix: {selected['candidate']}", file=sys.stderr)
        return 1

    overrides = parse_overrides(matrix[name]["overrides"])
    preset_rows = read_preset(args.preset)
    write_preset(args.preset, preset_rows, overrides)
    print(f"Applied candidate {name} to {args.preset}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
