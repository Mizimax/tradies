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

    report_name = f"GoldBot-real-{candidate['name'].strip()}"
    env = {
        "MT5_DEPOSIT": args.deposit,
        "MT5_FROM": args.from_date,
        "MT5_TO": args.to_date,
        "MT5_REPORT": report_name,
        "MT5_INPUT_OVERRIDES": candidate["overrides"].replace("\\n", "\n").strip(),
    }
    if args.symbol:
        env["MT5_SYMBOL"] = args.symbol
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
