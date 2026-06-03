#!/usr/bin/env python3
"""Evaluate MT5 report/journal pairs against the GoldBot improvement gate.

Supports both the original PF/DD/trade-count gate and the growth-first
acceptance gate. Growth is evaluated on full-window daily growth, while
active-day growth remains a setup-quality diagnostic.
"""

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

_daily_growth_path = ROOT / "scripts/daily-growth-report.py"
daily_growth = load_module("daily_growth_report", _daily_growth_path) if _daily_growth_path.exists() else None


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


def evaluate(
    report: Path,
    min_pf: float,
    max_dd: float,
    min_trades: int,
    max_trades: int,
    min_daily_growth: float,
    min_positive_day: float,
    deposit: float,
    from_date: str,
    to_date: str,
) -> dict[str, str]:
    report_row = report_parser.summarize(report)
    journal = find_journal(report)
    journal_row = journal_parser.summarize(journal) if journal else {}

    profit_factor = as_float(report_row["profit_factor"])
    equity_dd = as_float(report_row["max_equity_drawdown_pct"])
    trades = as_int(report_row["total_trades"])
    tp2_hits = as_int(journal_row.get("tp2_hits", "0"))
    tp3_hits = as_int(journal_row.get("tp3_hits", "0"))
    max_hold_closes = as_int(journal_row.get("max_hold_closes", "0"))

    # --- Daily growth metrics (new) ---
    growth_row: dict[str, str] = {}
    avg_window_daily_net_pct = 0.0
    avg_active_day_net_pct = 0.0
    positive_day_pct = 0.0
    if daily_growth is not None:
        try:
            growth_row = daily_growth.summarize(report, deposit, from_date, to_date)
            avg_window_daily_net_pct = as_float(growth_row.get("avg_window_daily_net_pct", "0"))
            avg_active_day_net_pct = as_float(growth_row.get("avg_active_day_net_pct", "0"))
            positive_day_pct = as_float(growth_row.get("positive_day_pct", "0"))
        except Exception:
            pass

    checks = {
        "pf_ok": profit_factor >= min_pf,
        "dd_ok": 0.0 < equity_dd <= max_dd,
        "trade_count_ok": min_trades <= trades <= max_trades,
        "tp_lifecycle_ok": tp2_hits > 0 and tp3_hits > 0,
        "journal_present": journal is not None,
    }

    # Growth-first checks (separate from legacy gate)
    growth_base_checks = {
        "pf_ok": checks["pf_ok"],
        "dd_ok": checks["dd_ok"],
        "trade_count_ok": checks["trade_count_ok"],
        "journal_present": checks["journal_present"],
        "daily_growth_ok": avg_window_daily_net_pct >= min_daily_growth,
        "positive_day_ok": positive_day_pct >= min_positive_day,
    }
    research_checks = {
        "pf_ok": checks["pf_ok"],
        "dd_ok": checks["dd_ok"],
        "has_trades": 0 < trades <= max_trades,
        "journal_present": checks["journal_present"],
        "window_growth_positive": avg_window_daily_net_pct > 0.0,
        "positive_day_ok": positive_day_pct >= min_positive_day,
    }

    legacy_passed = all(checks.values())
    growth_passed = all(growth_base_checks.values())
    growth_research_passed = not growth_passed and all(research_checks.values())

    # A candidate passes if it meets EITHER the legacy gate OR the growth gate
    passed = legacy_passed or growth_passed or growth_research_passed

    status = "PASS"
    if not passed:
        status = "FAIL"
    elif growth_research_passed:
        status = "PASS_GROWTH_RESEARCH"
    elif growth_passed and not legacy_passed:
        status = "PASS_GROWTH"
    elif legacy_passed and not growth_passed:
        status = "PASS_LEGACY"

    all_checks = {**checks, **growth_base_checks}
    if growth_research_passed:
        all_checks = {**all_checks, **research_checks}

    return {
        "candidate": candidate_name(report),
        "status": status,
        "net_profit": report_row["net_profit"],
        "profit_factor": report_row["profit_factor"],
        "max_equity_drawdown_pct": report_row["max_equity_drawdown_pct"],
        "total_trades": report_row["total_trades"],
        "win_rate_pct": report_row["win_rate_pct"],
        "avg_daily_net_pct": growth_row.get("avg_daily_net_pct", ""),
        "avg_active_day_net_pct": growth_row.get("avg_active_day_net_pct", ""),
        "avg_window_daily_net_pct": growth_row.get("avg_window_daily_net_pct", ""),
        "median_daily_net_pct": growth_row.get("median_daily_net_pct", ""),
        "median_active_day_net_pct": growth_row.get("median_active_day_net_pct", ""),
        "median_window_daily_net_pct": growth_row.get("median_window_daily_net_pct", ""),
        "positive_day_pct": growth_row.get("positive_day_pct", ""),
        "positive_window_day_pct": growth_row.get("positive_window_day_pct", ""),
        "worst_daily_net_pct": growth_row.get("worst_daily_net_pct", ""),
        "best_daily_net_pct": growth_row.get("best_daily_net_pct", ""),
        "max_losing_days_in_row": growth_row.get("max_losing_days_in_row", ""),
        "window_days": growth_row.get("window_days", ""),
        "trades_per_trading_day": growth_row.get("trades_per_trading_day", ""),
        "trades_per_window_day": growth_row.get("trades_per_window_day", ""),
        "daily_sharpe": growth_row.get("daily_sharpe", ""),
        "window_daily_sharpe": growth_row.get("window_daily_sharpe", ""),
        "sample_status": "TOO_SMALL" if trades < min_trades else "OK",
        "tp1_hits": journal_row.get("tp1_hits", ""),
        "tp2_hits": journal_row.get("tp2_hits", ""),
        "tp3_hits": journal_row.get("tp3_hits", ""),
        "max_hold_closes": str(max_hold_closes) if journal else "",
        "journal": journal.name if journal else "",
        "failed_checks": ";".join(name for name, ok in all_checks.items() if not ok),
    }


def sort_key(row: dict[str, str]) -> tuple[int, float, float, float, float]:
    """Sort: passed first, then by full-window growth (desc), PF (desc), DD (asc), net profit (desc)."""
    status = row["status"]
    if status.startswith("PASS"):
        passed_rank = 0
    else:
        passed_rank = 1
    avg_growth = as_float(row.get("avg_window_daily_net_pct", row.get("avg_daily_net_pct", "0")))
    profit_factor = as_float(row["profit_factor"])
    drawdown = as_float(row["max_equity_drawdown_pct"])
    net_profit = as_float(row["net_profit"])
    return (passed_rank, -avg_growth, -profit_factor, drawdown, -net_profit)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path, help="MT5 HTML report paths")
    parser.add_argument("--min-profit-factor", type=float, default=1.20)
    parser.add_argument("--max-equity-dd-pct", type=float, default=35.0)
    parser.add_argument("--min-trades", type=int, default=40)
    parser.add_argument("--max-trades", type=int, default=450)
    parser.add_argument("--min-daily-growth-pct", type=float, default=3.0, help="Min avg daily net %% for growth gate")
    parser.add_argument("--min-positive-day-pct", type=float, default=55.0, help="Min %% of positive days for growth gate")
    parser.add_argument("--deposit", type=float, default=100000.0, help="Starting deposit for daily growth calculation")
    parser.add_argument("--from-date", default="", help="Full-window start date passed to daily growth")
    parser.add_argument("--to-date", default="", help="Full-window end date passed to daily growth")
    parser.add_argument("--unsorted", action="store_true", help="Keep input order instead of leaderboard order")
    args = parser.parse_args()

    rows = [
        evaluate(
            path, args.min_profit_factor, args.max_equity_dd_pct,
            args.min_trades, args.max_trades,
            args.min_daily_growth_pct, args.min_positive_day_pct,
            args.deposit, args.from_date, args.to_date,
        )
        for path in args.reports if path.exists()
    ]
    if not rows:
        print("No readable reports found.", file=sys.stderr)
        return 1
    if not args.unsorted:
        rows.sort(key=sort_key)

    writer = csv.DictWriter(sys.stdout, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)
    return 0 if any(row["status"].startswith("PASS") for row in rows) else 2


if __name__ == "__main__":
    raise SystemExit(main())
