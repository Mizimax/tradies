#!/usr/bin/env python3
"""Run one GoldBot MT5 candidate from the candidate matrix."""

from __future__ import annotations

import argparse
import csv
import os
import shlex
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_candidates(matrix: Path) -> list[dict[str, str]]:
    with matrix.open(newline="") as handle:
        return list(csv.DictReader(handle))


def find_candidate(rows: list[dict[str, str]], name: str) -> dict[str, str] | None:
    for row in rows:
        if row["name"].strip() == name:
            return row
    return None


def expanded_overrides(rows: list[dict[str, str]], candidate: dict[str, str], seen: set[str] | None = None) -> str:
    if seen is None:
        seen = set()

    name = candidate["name"].strip()
    if name in seen:
        raise ValueError(f"Candidate override cycle detected at {name}")
    seen.add(name)

    overrides = candidate["overrides"].replace("\\n", "\n").strip()
    if not overrides:
        return ""

    lines = overrides.splitlines()
    first = lines[0].strip()
    if first.startswith("@"):
        base_name = first[1:].strip()
        if not base_name:
            raise ValueError(f"Candidate {name} has an empty base override reference")
        base = find_candidate(rows, base_name)
        if base is None:
            raise ValueError(f"Candidate {name} references unknown base candidate {base_name}")
        base_overrides = expanded_overrides(rows, base, seen).strip()
        child_overrides = "\n".join(line for line in lines[1:] if line.strip()).strip()
        if base_overrides and child_overrides:
            return base_overrides + "\n" + child_overrides
        return base_overrides or child_overrides

    return overrides


def shell_command(env: dict[str, str]) -> str:
    parts = [f"{key}={shlex.quote(value)}" for key, value in env.items()]
    parts.append("bash scripts/run-mt5-backtest.sh")
    return " ".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", nargs="?", help="Candidate name from the matrix")
    parser.add_argument("--matrix", type=Path, default=ROOT / "mt5/backtests/CANDIDATE_MATRIX.csv")
    parser.add_argument("--from-date", default="2023.10.01")
    parser.add_argument("--to-date", default="2025.09.30")
    parser.add_argument("--deposit", default="100000")
    parser.add_argument("--symbol", default="")
    parser.add_argument("--period", default="")
    parser.add_argument("--report-suffix", default="", help="Append a suffix to the MT5 report name, e.g. recent-12m")
    parser.add_argument("--spread-points", type=float, default=None, help="Stress-test extra spread (raw price units) widened into every ladder SL via InpStressExtraSpreadPrice. 0/omitted = no change.")
    parser.add_argument("--dry-run", action="store_true", help="Print the command without running MT5")
    parser.add_argument("--list", action="store_true", help="List available candidates")
    args = parser.parse_args()

    rows = load_candidates(args.matrix)
    if args.list:
        for row in rows:
            print(f"{row['name']}: {row['description']}")
        return 0

    if not args.candidate:
        print("Candidate name is required unless --list is used.", file=sys.stderr)
        return 2

    candidate = find_candidate(rows, args.candidate)
    if candidate is None:
        print(f"Unknown candidate: {args.candidate}", file=sys.stderr)
        print("Available candidates:", file=sys.stderr)
        for row in rows:
            print(f"  {row['name']}", file=sys.stderr)
        return 2

    candidate_name = candidate["name"].strip()
    report_suffix = args.report_suffix.strip()
    report_name = f"GoldBot-real-{candidate_name}"
    if report_suffix:
        report_name = f"{report_name}-{report_suffix}"
    try:
        overrides = expanded_overrides(rows, candidate)
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if args.spread_points is not None:
        overrides = overrides + ("\n" if overrides else "") + f"InpStressExtraSpreadPrice={args.spread_points}"

    env = {
        "MT5_DEPOSIT": args.deposit,
        "MT5_FROM": args.from_date,
        "MT5_TO": args.to_date,
        "MT5_REPORT": report_name,
        "MT5_INPUT_OVERRIDES": overrides,
    }
    if args.symbol:
        env["MT5_SYMBOL"] = args.symbol
        env["MT5_INPUT_OVERRIDES"] = overrides + ("\n" if overrides else "") + f"InpSymbol={args.symbol}"
    if args.period:
        env["MT5_PERIOD"] = args.period

    print(f"# {candidate['name']}: {candidate['description']}")
    print(shell_command(env))
    if args.dry_run:
        return 0

    run_env = os.environ.copy()
    run_env.update(env)
    return subprocess.call(["bash", "scripts/run-mt5-backtest.sh"], cwd=ROOT, env=run_env)


if __name__ == "__main__":
    raise SystemExit(main())
