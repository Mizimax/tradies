#!/usr/bin/env python3
"""Analyze MT5 Strategy Tester HTML reports for rolling-window stability of daily P&L."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import defaultdict
from datetime import date, timedelta
from html import unescape
from pathlib import Path


# ---------------------------------------------------------------------------
# MT5 HTML report decoding & parsing
# ---------------------------------------------------------------------------

def decode_report(path: Path) -> str:
    """Decode an MT5 HTML report that may be UTF-16LE with BOM."""
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")) or data.count(b"\x00") > 100:
        return data.decode("utf-16", errors="ignore")
    return data.decode("utf-8", errors="ignore")


def _parse_number(text: str) -> float:
    """Parse a number string that may use spaces as thousands separators."""
    cleaned = text.replace("\u00a0", "").replace(" ", "").strip()
    if not cleaned:
        return 0.0
    try:
        return float(cleaned)
    except ValueError:
        return 0.0


def _extract_deals_table(html: str) -> str:
    """Return the portion of *html* that contains the Deals table rows."""
    # The Deals section is marked by a <th> containing <b>Deals</b>
    pattern = re.compile(
        r"<th[^>]*>.*?<b>\s*Deals\s*</b>.*?</th>",
        re.IGNORECASE | re.DOTALL,
    )
    match = pattern.search(html)
    if not match:
        return ""
    # Everything after the Deals header up to the next section header or end
    start = match.end()
    # Look for the next <th> header (Positions, Orders, etc.) or end of file
    next_header = re.search(r"<th[^>]*>.*?<b>", html[start:], re.IGNORECASE | re.DOTALL)
    end = start + next_header.start() if next_header else len(html)
    return html[start:end]


def _parse_deal_rows(deals_html: str) -> list[dict[str, str]]:
    """Parse <tr> rows from the Deals table section into dicts."""
    row_re = re.compile(r"<tr[^>]*>(.*?)</tr>", re.IGNORECASE | re.DOTALL)
    cell_re = re.compile(r"<td[^>]*>(.*?)</td>", re.IGNORECASE | re.DOTALL)
    tag_re = re.compile(r"<[^>]+>")

    columns = [
        "time", "deal", "symbol", "type", "direction", "volume",
        "price", "order", "commission", "swap", "profit", "balance", "comment",
    ]

    rows: list[dict[str, str]] = []
    for row_match in row_re.finditer(deals_html):
        cells = cell_re.findall(row_match.group(1))
        if len(cells) < len(columns):
            continue
        values = [unescape(tag_re.sub("", c)).strip() for c in cells]
        row_dict = dict(zip(columns, values))
        rows.append(row_dict)
    return rows


def parse_closed_deals(path: Path) -> list[dict[str, str]]:
    """Return closed-deal rows (direction == 'out') from an MT5 HTML report."""
    html = decode_report(path)
    deals_html = _extract_deals_table(html)
    all_rows = _parse_deal_rows(deals_html)
    return [r for r in all_rows if r.get("direction", "").lower() == "out"]


# ---------------------------------------------------------------------------
# Daily P&L aggregation
# ---------------------------------------------------------------------------

def _deal_date(deal: dict[str, str]) -> date:
    """Extract the calendar date from a deal's time field (YYYY.MM.DD ...)."""
    parts = deal["time"].split()
    if not parts:
        raise ValueError(f"Cannot parse time: {deal['time']}")
    ymd = parts[0].replace(".", "-")
    return date.fromisoformat(ymd)


def daily_pnl(deals: list[dict[str, str]]) -> list[tuple[date, float, int]]:
    """Return sorted list of (date, net_pnl, trade_count) from closed deals."""
    by_day: dict[date, tuple[float, int]] = defaultdict(lambda: (0.0, 0))
    for deal in deals:
        d = _deal_date(deal)
        commission = _parse_number(deal.get("commission", "0"))
        swap = _parse_number(deal.get("swap", "0"))
        profit = _parse_number(deal.get("profit", "0"))
        net = commission + swap + profit
        prev_pnl, prev_count = by_day[d]
        by_day[d] = (prev_pnl + net, prev_count + 1)
    return sorted((d, pnl, cnt) for d, (pnl, cnt) in by_day.items())


# ---------------------------------------------------------------------------
# Monthly breakdown
# ---------------------------------------------------------------------------

def _month_key(d: date) -> str:
    return f"{d.year}-{d.month:02d}"


def monthly_breakdown(
    days: list[tuple[date, float, int]],
    deposit: float,
) -> list[dict[str, str]]:
    """Compute monthly statistics from daily P&L list."""
    months: dict[str, list[tuple[date, float, int]]] = defaultdict(list)
    for d, pnl, cnt in days:
        months[_month_key(d)].append((d, pnl, cnt))

    equity = deposit
    results: list[dict[str, str]] = []
    for month_label in sorted(months):
        month_days = months[month_label]
        trading_days = len(month_days)
        trades = sum(cnt for _, _, cnt in month_days)
        net_pnl = sum(pnl for _, pnl, _ in month_days)

        # Compounding net_pct: each day's % relative to equity at start of day
        month_start_equity = equity
        net_pct = 0.0
        if month_start_equity > 0:
            # Compute compounding: product of (1 + day_pnl / equity_at_start_of_day)
            compound = 1.0
            running_equity = month_start_equity
            for _, day_pnl, _ in month_days:
                if running_equity > 0:
                    compound *= 1.0 + day_pnl / running_equity
                running_equity += day_pnl
            net_pct = (compound - 1.0) * 100.0
        equity += net_pnl

        if net_pnl > 0:
            status = "POSITIVE"
        elif net_pnl < 0:
            status = "NEGATIVE"
        else:
            status = "ZERO"

        results.append({
            "month": month_label,
            "trading_days": str(trading_days),
            "trades": str(trades),
            "net_pnl": f"{net_pnl:.2f}",
            "net_pct": f"{net_pct:.2f}",
            "status": status,
        })
    return results


# ---------------------------------------------------------------------------
# Weekly consecutive-negative helper
# ---------------------------------------------------------------------------

def _iso_week_key(d: date) -> str:
    iso = d.isocalendar()
    return f"{iso[0]}-W{iso[1]:02d}"


def max_consecutive_negative_weeks(
    days: list[tuple[date, float, int]],
) -> int:
    """Compute the maximum run of consecutive ISO weeks with negative net P&L."""
    weeks: dict[str, float] = defaultdict(float)
    for d, pnl, _ in days:
        weeks[_iso_week_key(d)] += pnl

    if not weeks:
        return 0

    sorted_weeks = sorted(weeks)
    max_run = 0
    current_run = 0
    for wk in sorted_weeks:
        if weeks[wk] < 0:
            current_run += 1
            max_run = max(max_run, current_run)
        else:
            current_run = 0
    return max_run


# ---------------------------------------------------------------------------
# Rolling window metrics (informational, computed but used for flag logic)
# ---------------------------------------------------------------------------

def rolling_negative_periods(
    days: list[tuple[date, float, int]],
    deposit: float,
    window: int,
) -> int:
    """Count how many rolling windows of *window* days have avg daily growth < 0%."""
    if len(days) < window:
        return 0

    # Build equity curve
    equity_curve: list[float] = []
    equity = deposit
    for _, pnl, _ in days:
        equity_curve.append(equity)
        equity += pnl

    negative_count = 0
    for i in range(len(days) - window + 1):
        start_eq = equity_curve[i]
        end_eq = equity_curve[i + window - 1] + days[i + window - 1][1]
        if start_eq > 0 and end_eq < start_eq:
            negative_count += 1
    return negative_count


# ---------------------------------------------------------------------------
# Aggregate summary
# ---------------------------------------------------------------------------

def summarize(path: Path, deposit: float = 100_000.0) -> dict[str, str]:
    """Produce aggregate stability metrics for one MT5 HTML report."""
    deals = parse_closed_deals(path)
    days = daily_pnl(deals)

    if not days:
        return {
            "report": path.name,
            "total_months": "0",
            "profitable_months": "0",
            "month_consistency_pct": "0.00",
            "worst_month_pct": "0.00",
            "best_month_pct": "0.00",
            "max_negative_months_in_row": "0",
            "max_negative_weeks_in_row": "0",
            "stability_status": "INSUFFICIENT_DATA",
        }

    months = monthly_breakdown(days, deposit)
    total_months = len(months)
    profitable_months = sum(1 for m in months if m["status"] == "POSITIVE")
    consistency_pct = (profitable_months / total_months * 100.0) if total_months else 0.0

    pcts = [float(m["net_pct"]) for m in months]
    worst_month_pct = min(pcts) if pcts else 0.0
    best_month_pct = max(pcts) if pcts else 0.0

    # Max consecutive negative months
    max_neg_months = 0
    current_neg = 0
    for m in months:
        if m["status"] == "NEGATIVE":
            current_neg += 1
            max_neg_months = max(max_neg_months, current_neg)
        else:
            current_neg = 0

    max_neg_weeks = max_consecutive_negative_weeks(days)

    # Stability status
    if total_months < 3:
        status = "INSUFFICIENT_DATA"
    elif consistency_pct >= 55.0 and max_neg_months <= 3:
        status = "STABLE"
    else:
        status = "UNSTABLE"

    return {
        "report": path.name,
        "total_months": str(total_months),
        "profitable_months": str(profitable_months),
        "month_consistency_pct": f"{consistency_pct:.2f}",
        "worst_month_pct": f"{worst_month_pct:.2f}",
        "best_month_pct": f"{best_month_pct:.2f}",
        "max_negative_months_in_row": str(max_neg_months),
        "max_negative_weeks_in_row": str(max_neg_weeks),
        "stability_status": status,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

AGGREGATE_FIELDS = [
    "report",
    "total_months",
    "profitable_months",
    "month_consistency_pct",
    "worst_month_pct",
    "best_month_pct",
    "max_negative_months_in_row",
    "max_negative_weeks_in_row",
    "stability_status",
]

MONTHLY_FIELDS = [
    "report",
    "month",
    "trading_days",
    "trades",
    "net_pnl",
    "net_pct",
    "status",
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path, help="MT5 HTML report paths")
    parser.add_argument(
        "--deposit",
        type=float,
        default=100_000.0,
        help="Starting deposit (default: 100000)",
    )
    parser.add_argument(
        "--monthly",
        action="store_true",
        help="Output monthly breakdown instead of aggregate summary",
    )
    args = parser.parse_args()

    if args.monthly:
        rows: list[dict[str, str]] = []
        for path in args.reports:
            if not path.exists():
                continue
            deals = parse_closed_deals(path)
            days = daily_pnl(deals)
            for month_row in monthly_breakdown(days, args.deposit):
                month_row["report"] = path.name
                rows.append(month_row)
        if not rows:
            print("No readable reports found.", file=sys.stderr)
            return 1
        writer = csv.DictWriter(sys.stdout, fieldnames=MONTHLY_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    else:
        rows = [
            summarize(path, args.deposit)
            for path in args.reports
            if path.exists()
        ]
        if not rows:
            print("No readable reports found.", file=sys.stderr)
            return 1
        writer = csv.DictWriter(sys.stdout, fieldnames=AGGREGATE_FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
