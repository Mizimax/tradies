#!/usr/bin/env python3
"""Evaluate MT5 report/journal pairs against the GoldBot improvement gate."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


report_parser = load_module("summarize_mt5_reports", ROOT / "scripts/summarize-mt5-reports.py")
journal_parser = load_module("analyze_mt5_trades", ROOT / "scripts/analyze-mt5-trades.py")


def as_float(value: str) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def as_int(value: str) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return 0


def candidate_name(path: Path) -> str:
    name = path.name
    for suffix in (".htm", ".html", ".xml"):
        if name.endswith(suffix):
            return name[: -len(suffix)]
    return path.stem


def find_journal(report: Path) -> Path | None:
    base = candidate_name(report)
    candidate = report.with_name(base + ".trades.csv")
    if candidate.exists():
        return candidate
    return None


def evaluate(report: Path, min_pf: float, max_dd: float, min_trades: int, max_trades: int) -> dict[str, str]:
    report_row = report_parser.summarize(report)
    journal = find_journal(report)
    journal_row = journal_parser.summarize(journal) if journal else {}

    profit_factor = as_float(report_row["profit_factor"])
    equity_dd = as_float(report_row["max_equity_drawdown_pct"])
    trades = as_int(report_row["total_trades"])
    tp2_hits = as_int(journal_row.get("tp2_hits", "0"))
    tp3_hits = as_int(journal_row.get("tp3_hits", "0"))
    max_hold_closes = as_int(journal_row.get("max_hold_closes", "0"))

    checks = {
        "pf_ok": profit_factor >= min_pf,
        "dd_ok": 0.0 < equity_dd <= max_dd,
        "trade_count_ok": min_trades <= trades <= max_trades,
        "tp_lifecycle_ok": tp2_hits > 0 and tp3_hits > 0,
        "journal_present": journal is not None,
    }
    passed = all(checks.values())

    return {
        "candidate": candidate_name(report),
        "status": "PASS" if passed else "FAIL",
        "net_profit": report_row["net_profit"],
        "profit_factor": report_row["profit_factor"],
        "max_equity_drawdown_pct": report_row["max_equity_drawdown_pct"],
        "total_trades": report_row["total_trades"],
        "win_rate_pct": report_row["win_rate_pct"],
        "sample_status": "TOO_SMALL" if trades < min_trades else "OK",
        "tp1_hits": journal_row.get("tp1_hits", ""),
        "tp2_hits": journal_row.get("tp2_hits", ""),
        "tp3_hits": journal_row.get("tp3_hits", ""),
        "max_hold_closes": str(max_hold_closes) if journal else "",
        "journal": journal.name if journal else "",
        "failed_checks": ";".join(name for name, ok in checks.items() if not ok),
    }


def sort_key(row: dict[str, str]) -> tuple[int, float, float, float]:
    passed_rank = 0 if row["status"] == "PASS" else 1
    profit_factor = as_float(row["profit_factor"])
    drawdown = as_float(row["max_equity_drawdown_pct"])
    net_profit = as_float(row["net_profit"])
    return (passed_rank, -profit_factor, drawdown, -net_profit)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path, help="MT5 HTML report paths")
    parser.add_argument("--min-profit-factor", type=float, default=1.20)
    parser.add_argument("--max-equity-dd-pct", type=float, default=15.0)
    parser.add_argument("--min-trades", type=int, default=40)
    parser.add_argument("--max-trades", type=int, default=450)
    parser.add_argument("--unsorted", action="store_true", help="Keep input order instead of leaderboard order")
    args = parser.parse_args()

    rows = [evaluate(path, args.min_profit_factor, args.max_equity_dd_pct, args.min_trades, args.max_trades) for path in args.reports if path.exists()]
    if not rows:
        print("No readable reports found.", file=sys.stderr)
        return 1
    if not args.unsorted:
        rows.sort(key=sort_key)

    writer = csv.DictWriter(sys.stdout, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)
    return 0 if any(row["status"] == "PASS" for row in rows) else 2


if __name__ == "__main__":
    raise SystemExit(main())
