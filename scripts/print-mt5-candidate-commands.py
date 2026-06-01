#!/usr/bin/env python3
"""Print reproducible MT5 backtest commands from a candidate matrix CSV."""

from __future__ import annotations

import argparse
import csv
import shlex
from pathlib import Path


def shell_assign(name: str, value: str) -> str:
    return f"{name}={shlex.quote(value)}"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--matrix", type=Path, default=Path("mt5/backtests/CANDIDATE_MATRIX.csv"))
    parser.add_argument("--from-date", default="2023.10.01")
    parser.add_argument("--to-date", default="2025.09.30")
    parser.add_argument("--deposit", default="100000")
    parser.add_argument("--symbol", default="")
    parser.add_argument("--period", default="")
    args = parser.parse_args()

    with args.matrix.open(newline="") as handle:
        for row in csv.DictReader(handle):
            name = row["name"].strip()
            overrides = row["overrides"].replace("\\n", "\n").strip()
            report = f"GoldBot-real-{name}"
            env = [
                shell_assign("MT5_DEPOSIT", args.deposit),
                shell_assign("MT5_FROM", args.from_date),
                shell_assign("MT5_TO", args.to_date),
                shell_assign("MT5_REPORT", report),
                shell_assign("MT5_INPUT_OVERRIDES", overrides),
            ]
            if args.symbol:
                env.insert(0, shell_assign("MT5_SYMBOL", args.symbol))
            if args.period:
                env.insert(0, shell_assign("MT5_PERIOD", args.period))

            print(f"# {name}: {row['description'].strip()}")
            print(" ".join(env) + " bash scripts/run-mt5-backtest.sh")
            print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
