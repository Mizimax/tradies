#!/usr/bin/env python3
"""Cross-tabulate GoldBot journal closed-trade P&L by calendar month x setup.

Reads EA journal (``trades.csv``) closing ('Deal event' with ``entry=1``)
rows and buckets net P/L by (month, setup), to answer "which setup caused
the loss in the bad months" alongside ``.stability.csv``'s monthly
consistency numbers.

CSV rows are written to stdout (redirect to ``<stem>.monthly-setup.csv``,
where ``<stem>`` is the journal filename with the trailing ``.trades.csv``
removed). A readable month x setup table is written to stderr.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import sys
from collections import defaultdict
from pathlib import Path
from typing import Sequence


ROOT = Path(__file__).resolve().parents[1]

ALL_SETUPS = "ALL_SETUPS"
ALL_MONTHS = "ALL_MONTHS"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


journal_parser = load_module("analyze_mt5_trades", ROOT / "scripts/analyze-mt5-trades.py")


def journal_stem(path: Path) -> str:
    """Strip a trailing '.trades.csv' to recover the shared candidate stem."""
    name = path.name
    if name.endswith(".trades.csv"):
        return name[: -len(".trades.csv")]
    return path.stem


def month_bucket(time_str: str) -> str:
    """'2024.07.05 09:53:16' -> '2024-07'."""
    parts = time_str.strip().split(" ", 1)[0].split(".")
    if len(parts) < 2:
        return "unknown"
    return f"{parts[0]}-{parts[1]}"


def collect_closes(path: Path) -> list[tuple[str, str, float]]:
    """Return (month, setup, profit) for every closing 'Deal event' row."""
    rows = journal_parser.read_rows(path)
    closes: list[tuple[str, str, float]] = []
    for time_str, message in rows:
        if "deal event" not in message.lower():
            continue
        fields = journal_parser.parse_message_fields(message)
        if fields.get("entry") != "1":
            continue
        month = month_bucket(time_str)
        setup = fields.get("setup", "unknown")
        profit = journal_parser.as_float(fields.get("profit"))
        closes.append((month, setup, profit))
    return closes


def build_rows(path: Path) -> tuple[list[dict[str, str]], list[str], list[str], dict[tuple[str, str], list[float]]]:
    """Build the flat CSV rows plus the raw (month, setup) -> profits map for the console table."""
    stem = journal_stem(path)
    closes = collect_closes(path)

    cells: dict[tuple[str, str], list[float]] = defaultdict(list)
    for month, setup, profit in closes:
        cells[(month, setup)].append(profit)
        cells[(month, ALL_SETUPS)].append(profit)
        cells[(ALL_MONTHS, setup)].append(profit)
        cells[(ALL_MONTHS, ALL_SETUPS)].append(profit)

    months = sorted({m for m, _s, _p in closes})
    setups = sorted({s for _m, s, _p in closes})

    rows: list[dict[str, str]] = []
    for month in months + [ALL_MONTHS]:
        for setup in setups + [ALL_SETUPS]:
            profits = cells.get((month, setup), [])
            if not profits:
                continue
            wins = sum(1 for p in profits if p > 0)
            gross_profit = sum(p for p in profits if p > 0)
            gross_loss = sum(p for p in profits if p < 0)
            rows.append({
                "journal": path.name,
                "month": month,
                "setup": setup,
                "closed_deals": str(len(profits)),
                "net_profit": f"{sum(profits):.2f}",
                "gross_profit": f"{gross_profit:.2f}",
                "gross_loss": f"{gross_loss:.2f}",
                "win_rate_pct": f"{(wins / len(profits) * 100.0):.2f}",
            })
    return rows, months, setups, cells


def print_table(path: Path, months: list[str], setups: list[str], cells: dict[tuple[str, str], list[float]]) -> None:
    print(f"\n=== {path.name}: monthly net P/L by setup ($) ===", file=sys.stderr)
    header = ["month"] + setups + ["TOTAL"]
    col_width = max(10, max((len(s) for s in setups), default=10) + 2)
    print("".join(f"{h:>{col_width}s}" for h in header), file=sys.stderr)
    for month in months:
        line = [f"{month:>{col_width}s}"]
        for setup in setups:
            total = sum(cells.get((month, setup), []))
            line.append(f"{total:>{col_width}.2f}")
        month_total = sum(cells.get((month, ALL_SETUPS), []))
        line.append(f"{month_total:>{col_width}.2f}")
        marker = "  <-- LOSING MONTH" if month_total < 0 else ""
        print("".join(line) + marker, file=sys.stderr)
    footer = [f"{'TOTAL':>{col_width}s}"]
    for setup in setups:
        footer.append(f"{sum(cells.get((ALL_MONTHS, setup), [])):>{col_width}.2f}")
    footer.append(f"{sum(cells.get((ALL_MONTHS, ALL_SETUPS), [])):>{col_width}.2f}")
    print("".join(footer), file=sys.stderr)

    losing_months = sorted(
        ((m, sum(cells.get((m, ALL_SETUPS), []))) for m in months),
        key=lambda kv: kv[1],
    )
    losing_months = [(m, total) for m, total in losing_months if total < 0]
    if losing_months:
        print("Losing months and the setup that drove each one negative:", file=sys.stderr)
        for month, total in losing_months:
            worst_setup, worst_total = min(
                ((s, sum(cells.get((month, s), []))) for s in setups),
                key=lambda kv: kv[1],
            )
            print(f"  {month}: total {total:.2f}, worst setup = {worst_setup} ({worst_total:.2f})", file=sys.stderr)
    else:
        print("No losing months in this window.", file=sys.stderr)


FIELDNAMES = ["journal", "month", "setup", "closed_deals", "net_profit", "gross_profit", "gross_loss", "win_rate_pct"]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("journals", nargs="+", type=Path, help="GoldBot trades.csv journal paths")
    args = parser.parse_args(argv)

    paths = [p for p in args.journals if p.exists()]
    if not paths:
        print("No readable trades.csv journal paths found.", file=sys.stderr)
        return 1

    all_rows: list[dict[str, str]] = []
    for path in paths:
        rows, months, setups, cells = build_rows(path)
        all_rows.extend(rows)
        print_table(path, months, setups, cells)

    writer = csv.DictWriter(sys.stdout, fieldnames=FIELDNAMES)
    writer.writeheader()
    writer.writerows(all_rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
