#!/usr/bin/env python3
"""Compute daily growth metrics from MT5 Strategy Tester HTML reports.

Extracts the Deals table, groups closed-deal P&L by trading day, and
computes compounding daily growth statistics for GoldBot candidate
comparison.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import defaultdict
from datetime import date, datetime, timedelta
from html import unescape
from pathlib import Path
from statistics import mean, median, stdev


# ---------------------------------------------------------------------------
# HTML parsing helpers (matches summarize-mt5-reports.py conventions)
# ---------------------------------------------------------------------------


def decode_report(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")) or data.count(b"\x00") > 100:
        return data.decode("utf-16", errors="ignore")
    return data.decode("utf-8", errors="ignore")


def parse_number(value: str) -> float:
    """Parse an MT5-formatted number (spaces as thousands separators)."""
    cleaned = value.replace("\xa0", "").replace(" ", "").strip()
    match = re.search(r"-?[\d]+(?:\.[\d]+)?", cleaned)
    if not match:
        return 0.0
    return float(match.group(0))


def strip_tags(html: str) -> str:
    return unescape(re.sub(r"<[^>]+>", "", html)).strip()


# ---------------------------------------------------------------------------
# Deal table extraction
# ---------------------------------------------------------------------------


def extract_deals(report_text: str) -> list[dict[str, str]]:
    """Extract rows from the Deals table in an MT5 Strategy Tester HTML report.

    Returns a list of dicts with keys:
        time, deal, symbol, type, direction, volume, price, order,
        commission, swap, profit, balance, comment
    """
    # Find the Deals section header
    deals_header = re.search(
        r"<th[^>]*>.*?<b>Deals</b>.*?</th>",
        report_text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if not deals_header:
        return []

    # Get everything after the Deals header
    after_header = report_text[deals_header.end():]

    # Skip the column-header row (Time, Deal, Symbol, ...)
    header_row = re.search(r"<tr[^>]*>.*?</tr>", after_header, flags=re.DOTALL)
    if not header_row:
        return []

    after_columns = after_header[header_row.end():]

    # Extract all data rows until the next section or end of table
    columns = [
        "time", "deal", "symbol", "type", "direction",
        "volume", "price", "order", "commission", "swap",
        "profit", "balance", "comment",
    ]

    deals: list[dict[str, str]] = []
    for row_match in re.finditer(r"<tr[^>]*>(.*?)</tr>", after_columns, flags=re.IGNORECASE | re.DOTALL):
        cells = re.findall(r"<td[^>]*>(.*?)</td>", row_match.group(1), flags=re.IGNORECASE | re.DOTALL)
        if len(cells) < 11:
            break  # Hit the end of the deals table
        values = [strip_tags(cell) for cell in cells]
        row = {}
        for i, col in enumerate(columns):
            row[col] = values[i] if i < len(values) else ""
        deals.append(row)

    return deals


# ---------------------------------------------------------------------------
# Daily P&L aggregation with compounding equity
# ---------------------------------------------------------------------------


def compute_daily_pnl(
    deals: list[dict[str, str]],
    deposit: float,
) -> list[tuple[date, float, float, int]]:
    """Aggregate deal P&L by trading day using compounding equity.

    Returns sorted list of (date, daily_pnl, daily_pct, trade_count).
    daily_pct is relative to equity at the start of that day (compounding).
    """
    # Collect P&L per day from closing deals (direction = out) or balance operations
    day_pnl: dict[date, float] = defaultdict(float)
    day_trades: dict[date, int] = defaultdict(int)

    for deal in deals:
        deal_type = deal.get("type", "").lower().strip()
        direction = deal.get("direction", "").lower().strip()

        # Skip the initial balance deposit
        if deal_type == "balance":
            continue

        # Only count closing deals (direction = out)
        if direction != "out":
            continue

        time_str = deal.get("time", "").strip()
        if not time_str:
            continue

        try:
            dt = datetime.strptime(time_str, "%Y.%m.%d %H:%M:%S")
        except ValueError:
            continue

        profit = parse_number(deal.get("profit", "0"))
        commission = parse_number(deal.get("commission", "0"))
        swap = parse_number(deal.get("swap", "0"))

        net = profit + commission + swap
        day_pnl[dt.date()] += net
        day_trades[dt.date()] += 1

    # Sort by date and compute compounding daily %
    sorted_days = sorted(day_pnl.keys())
    result: list[tuple[date, float, float, int]] = []
    equity = deposit

    for d in sorted_days:
        pnl = day_pnl[d]
        pct = (pnl / equity * 100.0) if equity > 0 else 0.0
        trades = day_trades[d]
        result.append((d, pnl, pct, trades))
        equity += pnl

    return result


# ---------------------------------------------------------------------------
# Daily growth metrics
# ---------------------------------------------------------------------------


def max_consecutive(values: list[float], predicate) -> int:
    """Count maximum consecutive elements matching predicate."""
    max_run = 0
    current = 0
    for v in values:
        if predicate(v):
            current += 1
            max_run = max(max_run, current)
        else:
            current = 0
    return max_run


def parse_window_date(value: str | None) -> date | None:
    if not value:
        return None
    for fmt in ("%Y.%m.%d", "%Y-%m-%d"):
        try:
            return datetime.strptime(value, fmt).date()
        except ValueError:
            continue
    raise ValueError(f"Invalid date {value!r}; expected YYYY.MM.DD or YYYY-MM-DD")


def daily_pct_series(
    daily: list[tuple[date, float, float, int]],
    from_date: date | None,
    to_date: date | None,
) -> tuple[list[float], int]:
    """Return full-window daily pct series, including zero-pct no-trade days."""
    if not daily:
        if from_date is None or to_date is None or to_date < from_date:
            return [], 0
        days = (to_date - from_date).days + 1
        return [0.0] * days, days

    by_day = {d: pct for d, _, pct, _ in daily}
    start = from_date or min(by_day)
    end = to_date or max(by_day)
    if end < start:
        return [], 0

    pcts: list[float] = []
    current = start
    while current <= end:
        pcts.append(by_day.get(current, 0.0))
        current += timedelta(days=1)
    return pcts, len(pcts)


def compute_metrics(
    daily: list[tuple[date, float, float, int]],
    deposit: float,
    from_date: date | None = None,
    to_date: date | None = None,
) -> dict[str, str]:
    """Compute active-day and full-window daily-growth metrics."""
    if not daily:
        window_pcts, window_days = daily_pct_series(daily, from_date, to_date)
        avg_window_pct = mean(window_pcts) if window_pcts else 0.0
        return {
            "trading_days": "0",
            "active_days": "0",
            "window_days": str(window_days),
            "total_trades": "0",
            "avg_daily_net_pct": f"{avg_window_pct:.4f}" if window_pcts else "",
            "avg_active_day_net_pct": "",
            "avg_window_daily_net_pct": f"{avg_window_pct:.4f}" if window_pcts else "",
            "median_daily_net_pct": f"{median(window_pcts):.4f}" if window_pcts else "",
            "median_active_day_net_pct": "",
            "median_window_daily_net_pct": f"{median(window_pcts):.4f}" if window_pcts else "",
            "positive_day_pct": "",
            "positive_window_day_pct": "0.00" if window_pcts else "",
            "worst_daily_net_pct": "",
            "worst_window_daily_net_pct": f"{min(window_pcts):.4f}" if window_pcts else "",
            "best_daily_net_pct": "",
            "best_window_daily_net_pct": f"{max(window_pcts):.4f}" if window_pcts else "",
            "max_losing_days_in_row": "",
            "max_window_losing_days_in_row": str(max_consecutive(window_pcts, lambda x: x < 0)) if window_pcts else "",
            "trades_per_trading_day": "",
            "trades_per_window_day": "0.00" if window_pcts else "",
            "daily_sharpe": "",
            "window_daily_sharpe": "",
            "total_net_pnl": "",
            "final_equity": "",
        }

    active_pcts = [pct for _, _, pct, _ in daily]
    window_pcts, window_days = daily_pct_series(daily, from_date, to_date)
    total_trades = sum(tc for _, _, _, tc in daily)
    total_pnl = sum(pnl for _, pnl, _, _ in daily)
    final_equity = deposit + total_pnl
    positive_days = sum(1 for p in active_pcts if p > 0)
    positive_window_days = sum(1 for p in window_pcts if p > 0)

    avg_active_pct = mean(active_pcts)
    avg_window_pct = mean(window_pcts) if window_pcts else 0.0
    active_std_pct = stdev(active_pcts) if len(active_pcts) > 1 else 0.0
    window_std_pct = stdev(window_pcts) if len(window_pcts) > 1 else 0.0
    active_sharpe = (avg_active_pct / active_std_pct) if active_std_pct > 0 else 0.0
    window_sharpe = (avg_window_pct / window_std_pct) if window_std_pct > 0 else 0.0

    return {
        "trading_days": str(len(daily)),
        "active_days": str(len(daily)),
        "window_days": str(window_days),
        "total_trades": str(total_trades),
        "avg_daily_net_pct": f"{avg_window_pct:.4f}",
        "avg_active_day_net_pct": f"{avg_active_pct:.4f}",
        "avg_window_daily_net_pct": f"{avg_window_pct:.4f}",
        "median_daily_net_pct": f"{median(window_pcts):.4f}",
        "median_active_day_net_pct": f"{median(active_pcts):.4f}",
        "median_window_daily_net_pct": f"{median(window_pcts):.4f}",
        "positive_day_pct": f"{(positive_days / len(daily) * 100.0):.2f}",
        "positive_window_day_pct": f"{(positive_window_days / window_days * 100.0):.2f}" if window_days else "",
        "worst_daily_net_pct": f"{min(window_pcts):.4f}",
        "worst_window_daily_net_pct": f"{min(window_pcts):.4f}",
        "best_daily_net_pct": f"{max(window_pcts):.4f}",
        "best_window_daily_net_pct": f"{max(window_pcts):.4f}",
        "max_losing_days_in_row": str(max_consecutive(active_pcts, lambda x: x < 0)),
        "max_window_losing_days_in_row": str(max_consecutive(window_pcts, lambda x: x < 0)),
        "trades_per_trading_day": f"{(total_trades / len(daily)):.2f}",
        "trades_per_window_day": f"{(total_trades / window_days):.2f}" if window_days else "",
        "daily_sharpe": f"{window_sharpe:.4f}",
        "active_day_sharpe": f"{active_sharpe:.4f}",
        "window_daily_sharpe": f"{window_sharpe:.4f}",
        "total_net_pnl": f"{total_pnl:.2f}",
        "final_equity": f"{final_equity:.2f}",
    }


# ---------------------------------------------------------------------------
# Public API (importable by other scripts)
# ---------------------------------------------------------------------------


def summarize(
    path: Path,
    deposit: float = 100000.0,
    from_date: date | str | None = None,
    to_date: date | str | None = None,
) -> dict[str, str]:
    """Compute daily growth metrics for a single MT5 HTML report."""
    text = decode_report(path)
    deals = extract_deals(text)
    daily = compute_daily_pnl(deals, deposit)
    if isinstance(from_date, str):
        from_date = parse_window_date(from_date)
    if isinstance(to_date, str):
        to_date = parse_window_date(to_date)
    metrics = compute_metrics(daily, deposit, from_date, to_date)
    metrics["report"] = path.name
    return metrics


def daily_detail(path: Path, deposit: float = 100000.0) -> list[dict[str, str]]:
    """Return per-day detail rows for a single MT5 HTML report."""
    text = decode_report(path)
    deals = extract_deals(text)
    daily = compute_daily_pnl(deals, deposit)

    rows: list[dict[str, str]] = []
    equity = deposit
    for d, pnl, pct, trades in daily:
        rows.append({
            "report": path.name,
            "date": d.isoformat(),
            "equity_start": f"{equity:.2f}",
            "daily_pnl": f"{pnl:.2f}",
            "daily_pct": f"{pct:.4f}",
            "trades": str(trades),
        })
        equity += pnl
    return rows


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


SUMMARY_FIELDS = [
    "report", "trading_days", "active_days", "window_days", "total_trades",
    "avg_daily_net_pct", "avg_active_day_net_pct", "avg_window_daily_net_pct",
    "median_daily_net_pct", "median_active_day_net_pct", "median_window_daily_net_pct",
    "positive_day_pct", "positive_window_day_pct", "worst_daily_net_pct",
    "worst_window_daily_net_pct", "best_daily_net_pct", "best_window_daily_net_pct",
    "max_losing_days_in_row", "max_window_losing_days_in_row",
    "trades_per_trading_day", "trades_per_window_day", "daily_sharpe",
    "active_day_sharpe", "window_daily_sharpe", "total_net_pnl", "final_equity",
]

DETAIL_FIELDS = [
    "report", "date", "equity_start", "daily_pnl", "daily_pct", "trades",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path, help="MT5 HTML report paths")
    parser.add_argument("--deposit", type=float, default=100000.0, help="Starting deposit (default: 100000)")
    parser.add_argument("--from-date", default="", help="Full-window start date, YYYY.MM.DD or YYYY-MM-DD")
    parser.add_argument("--to-date", default="", help="Full-window end date, YYYY.MM.DD or YYYY-MM-DD")
    parser.add_argument("--daily", action="store_true", help="Output per-day detail instead of summary")
    args = parser.parse_args()

    from_date = parse_window_date(args.from_date)
    to_date = parse_window_date(args.to_date)

    if args.daily:
        rows: list[dict[str, str]] = []
        for path in args.reports:
            if path.exists():
                rows.extend(daily_detail(path, args.deposit))
        if not rows:
            print("No readable deals found.", file=sys.stderr)
            return 1
        writer = csv.DictWriter(sys.stdout, fieldnames=DETAIL_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    else:
        rows = [summarize(path, args.deposit, from_date, to_date) for path in args.reports if path.exists()]
        if not rows:
            print("No readable reports found.", file=sys.stderr)
            return 1
        writer = csv.DictWriter(sys.stdout, fieldnames=SUMMARY_FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
