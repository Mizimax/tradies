#!/usr/bin/env python3
"""Analyze MT5 Strategy Tester HTML reports to reconstruct equity curves and detect drawdowns."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Sequence


# ---------------------------------------------------------------------------
# Decoding & parsing helpers
# ---------------------------------------------------------------------------

def decode_report(path: Path) -> str:
    """Read an MT5 HTML report that may be UTF-16LE (with BOM) or UTF-8."""
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")) or data.count(b"\x00") > 100:
        return data.decode("utf-16", errors="ignore")
    return data.decode("utf-8", errors="ignore")


def _parse_number(text: str) -> float:
    """Parse a number that may use spaces as thousands separators (e.g. '100 296.38')."""
    cleaned = text.replace("\xa0", "").replace(" ", "").strip()
    if not cleaned or cleaned == "-":
        return 0.0
    try:
        return float(cleaned)
    except ValueError:
        return 0.0


def _parse_timestamp(text: str) -> datetime:
    """Parse MT5 timestamp like '2024.04.01 17:49:58'."""
    return datetime.strptime(text.strip(), "%Y.%m.%d %H:%M:%S")


# ---------------------------------------------------------------------------
# Deal extraction
# ---------------------------------------------------------------------------

@dataclass
class Deal:
    """A single deal row extracted from the MT5 Deals table."""
    time: datetime
    deal_id: int
    symbol: str
    deal_type: str
    direction: str
    volume: float
    price: float
    order: int
    commission: float
    swap: float
    profit: float
    balance: float
    comment: str


def _strip_html(text: str) -> str:
    """Remove HTML tags from a string."""
    return re.sub(r"<[^>]+>", "", text).strip()


def _find_deals_table(html: str) -> str | None:
    """Locate the Deals table section in the HTML report.

    The Deals header is a ``<th>`` containing ``<b>Deals</b>``.  We return
    everything from that header through the next ``</table>`` or the next
    ``<th>`` that starts a different section.
    """
    pattern = re.compile(r"<th[^>]*>.*?<b>\s*Deals\s*</b>.*?</th>", re.IGNORECASE | re.DOTALL)
    match = pattern.search(html)
    if not match:
        return None

    start = match.end()
    # Find the end of this table section – either next <th> section header or </table>
    end_pattern = re.compile(r"<th[^>]*>.*?<b>", re.IGNORECASE | re.DOTALL)
    end_match = end_pattern.search(html, start)
    if end_match:
        return html[start:end_match.start()]
    # Fallback: rest of the document
    return html[start:]


def _parse_deal_rows(table_html: str) -> list[Deal]:
    """Extract Deal objects from the HTML rows inside the Deals table."""
    row_pattern = re.compile(r"<tr[^>]*>(.*?)</tr>", re.IGNORECASE | re.DOTALL)
    cell_pattern = re.compile(r"<td[^>]*>(.*?)</td>", re.IGNORECASE | re.DOTALL)

    deals: list[Deal] = []
    for row_match in row_pattern.finditer(table_html):
        row_html = row_match.group(1)
        cells = [_strip_html(c.group(1)) for c in cell_pattern.finditer(row_html)]
        if len(cells) < 13:
            continue
        # Skip header-like rows or empty timestamps
        time_str = cells[0].strip()
        if not time_str or not re.match(r"\d{4}\.\d{2}\.\d{2}", time_str):
            continue
        try:
            deal = Deal(
                time=_parse_timestamp(cells[0]),
                deal_id=int(_parse_number(cells[1])),
                symbol=cells[2],
                deal_type=cells[3].lower(),
                direction=cells[4].lower(),
                volume=_parse_number(cells[5]),
                price=_parse_number(cells[6]),
                order=int(_parse_number(cells[7])),
                commission=_parse_number(cells[8]),
                swap=_parse_number(cells[9]),
                profit=_parse_number(cells[10]),
                balance=_parse_number(cells[11]),
                comment=cells[12],
            )
            deals.append(deal)
        except (ValueError, IndexError):
            continue
    return deals


def extract_deals(path: Path) -> list[Deal]:
    """Extract all deals from an MT5 HTML report file."""
    html = decode_report(path)
    table_html = _find_deals_table(html)
    if table_html is None:
        return []
    return _parse_deal_rows(table_html)


# ---------------------------------------------------------------------------
# Equity curve reconstruction
# ---------------------------------------------------------------------------

@dataclass
class EquityPoint:
    """A single point on the equity curve."""
    time: datetime
    balance: float
    profit: float  # P&L of this individual deal


def build_equity_curve(deals: list[Deal]) -> list[EquityPoint]:
    """Build chronological equity curve from closing deals.

    We include deals where direction='out' (trade closings) or type='balance'
    (deposit/withdrawal events), since these are the points where the Balance
    column changes.
    """
    points: list[EquityPoint] = []
    for deal in sorted(deals, key=lambda d: d.time):
        if deal.direction == "out" or deal.deal_type == "balance":
            points.append(EquityPoint(
                time=deal.time,
                balance=deal.balance,
                profit=deal.profit,
            ))
    return points


# ---------------------------------------------------------------------------
# Drawdown detection
# ---------------------------------------------------------------------------

@dataclass
class DrawdownEvent:
    """A single peak-to-trough-to-recovery drawdown event."""
    event_num: int
    peak_date: datetime
    peak_balance: float
    trough_date: datetime
    trough_balance: float
    recovery_date: datetime | None
    depth_pct: float
    depth_dollars: float
    duration_days: float


def detect_drawdowns(curve: list[EquityPoint], min_depth_pct: float = 1.0) -> list[DrawdownEvent]:
    """Detect drawdown events exceeding *min_depth_pct* from the equity curve."""
    if len(curve) < 2:
        return []

    events: list[DrawdownEvent] = []
    peak_balance = curve[0].balance
    peak_date = curve[0].time
    trough_balance = peak_balance
    trough_date = peak_date
    in_drawdown = False
    event_num = 0

    for point in curve[1:]:
        if point.balance >= peak_balance:
            # New peak or recovery
            if in_drawdown:
                depth_pct = (peak_balance - trough_balance) / peak_balance * 100.0 if peak_balance > 0 else 0.0
                if depth_pct >= min_depth_pct:
                    event_num += 1
                    events.append(DrawdownEvent(
                        event_num=event_num,
                        peak_date=peak_date,
                        peak_balance=peak_balance,
                        trough_date=trough_date,
                        trough_balance=trough_balance,
                        recovery_date=point.time,
                        depth_pct=depth_pct,
                        depth_dollars=peak_balance - trough_balance,
                        duration_days=(point.time - peak_date).total_seconds() / 86400.0,
                    ))
                in_drawdown = False
            peak_balance = point.balance
            peak_date = point.time
            trough_balance = peak_balance
            trough_date = peak_date
        else:
            in_drawdown = True
            if point.balance < trough_balance:
                trough_balance = point.balance
                trough_date = point.time

    # Handle ongoing (unrecovered) drawdown at end of data
    if in_drawdown:
        depth_pct = (peak_balance - trough_balance) / peak_balance * 100.0 if peak_balance > 0 else 0.0
        if depth_pct >= min_depth_pct:
            event_num += 1
            events.append(DrawdownEvent(
                event_num=event_num,
                peak_date=peak_date,
                peak_balance=peak_balance,
                trough_date=trough_date,
                trough_balance=trough_balance,
                recovery_date=None,
                depth_pct=depth_pct,
                depth_dollars=peak_balance - trough_balance,
                duration_days=(curve[-1].time - peak_date).total_seconds() / 86400.0,
            ))

    return events


# ---------------------------------------------------------------------------
# Loss cluster detection
# ---------------------------------------------------------------------------

def count_loss_clusters(curve: list[EquityPoint], min_streak: int = 3) -> int:
    """Count clusters of *min_streak* or more consecutive losing deals."""
    clusters = 0
    streak = 0
    for point in curve:
        if point.profit < 0:
            streak += 1
        else:
            if streak >= min_streak:
                clusters += 1
            streak = 0
    # Check final streak
    if streak >= min_streak:
        clusters += 1
    return clusters


# ---------------------------------------------------------------------------
# Aggregate metrics
# ---------------------------------------------------------------------------

def _fmt_date(dt: datetime | None) -> str:
    return dt.strftime("%Y-%m-%d") if dt else ""


def summarize(path: Path, deposit: float = 100_000.0) -> dict[str, str]:
    """Produce aggregate equity-curve metrics for a single MT5 HTML report.

    Parameters
    ----------
    path:
        Path to an MT5 Strategy Tester HTML report.
    deposit:
        Initial deposit value.  Used for return calculations when the first
        balance entry is a deposit.

    Returns
    -------
    dict
        A flat dictionary of string values suitable for CSV output.
    """
    deals = extract_deals(path)
    curve = build_equity_curve(deals)

    if not curve:
        return {
            "report": path.name,
            "deposit": f"{deposit:.2f}",
            "final_balance": "",
            "net_profit": "",
            "net_return_pct": "",
            "max_dd_pct": "",
            "max_dd_dollars": "",
            "max_dd_start": "",
            "max_dd_trough": "",
            "max_dd_recovery": "",
            "max_dd_duration_days": "",
            "calmar_ratio": "",
            "profit_to_maxdd_ratio": "",
            "dd_events_gt5pct": "",
            "loss_cluster_count_3plus": "",
        }

    initial_balance = deposit if deposit > 0 else curve[0].balance
    final_balance = curve[-1].balance
    net_profit = final_balance - initial_balance

    # Time span for annualisation
    total_days = (curve[-1].time - curve[0].time).total_seconds() / 86400.0
    annualised_return_pct = (net_profit / initial_balance * 100.0) * (365.0 / total_days) if total_days > 0 and initial_balance > 0 else 0.0

    # Drawdown analysis
    dd_events = detect_drawdowns(curve, min_depth_pct=1.0)
    dd_events_gt5 = [e for e in dd_events if e.depth_pct >= 5.0]

    max_dd_event: DrawdownEvent | None = None
    if dd_events:
        max_dd_event = max(dd_events, key=lambda e: e.depth_pct)

    max_dd_pct = max_dd_event.depth_pct if max_dd_event else 0.0
    max_dd_dollars = max_dd_event.depth_dollars if max_dd_event else 0.0

    calmar = abs(annualised_return_pct / max_dd_pct) if max_dd_pct > 0 else 0.0
    profit_to_maxdd = abs(net_profit / max_dd_dollars) if max_dd_dollars > 0 else 0.0

    loss_clusters = count_loss_clusters(curve, min_streak=3)

    return {
        "report": path.name,
        "deposit": f"{deposit:.2f}",
        "final_balance": f"{final_balance:.2f}",
        "net_profit": f"{net_profit:.2f}",
        "net_return_pct": f"{net_profit / initial_balance * 100.0:.2f}" if initial_balance > 0 else "",
        "max_dd_pct": f"{max_dd_pct:.2f}",
        "max_dd_dollars": f"{max_dd_dollars:.2f}",
        "max_dd_start": _fmt_date(max_dd_event.peak_date) if max_dd_event else "",
        "max_dd_trough": _fmt_date(max_dd_event.trough_date) if max_dd_event else "",
        "max_dd_recovery": _fmt_date(max_dd_event.recovery_date) if max_dd_event else "",
        "max_dd_duration_days": f"{max_dd_event.duration_days:.1f}" if max_dd_event else "",
        "calmar_ratio": f"{calmar:.2f}",
        "profit_to_maxdd_ratio": f"{profit_to_maxdd:.2f}",
        "dd_events_gt5pct": str(len(dd_events_gt5)),
        "loss_cluster_count_3plus": str(loss_clusters),
    }


# ---------------------------------------------------------------------------
# Event-level output
# ---------------------------------------------------------------------------

EVENT_FIELDS: list[str] = [
    "report", "event_num", "peak_date", "trough_date", "recovery_date",
    "depth_pct", "depth_dollars", "duration_days",
]


def event_rows(path: Path) -> list[dict[str, str]]:
    """Return individual drawdown events (>1% depth) for a single report."""
    deals = extract_deals(path)
    curve = build_equity_curve(deals)
    events = detect_drawdowns(curve, min_depth_pct=1.0)

    rows: list[dict[str, str]] = []
    for event in events:
        rows.append({
            "report": path.name,
            "event_num": str(event.event_num),
            "peak_date": _fmt_date(event.peak_date),
            "trough_date": _fmt_date(event.trough_date),
            "recovery_date": _fmt_date(event.recovery_date),
            "depth_pct": f"{event.depth_pct:.2f}",
            "depth_dollars": f"{event.depth_dollars:.2f}",
            "duration_days": f"{event.duration_days:.1f}",
        })
    return rows


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

SUMMARY_FIELDS: list[str] = [
    "report", "deposit", "final_balance", "net_profit", "net_return_pct",
    "max_dd_pct", "max_dd_dollars", "max_dd_start", "max_dd_trough",
    "max_dd_recovery", "max_dd_duration_days", "calmar_ratio",
    "profit_to_maxdd_ratio", "dd_events_gt5pct", "loss_cluster_count_3plus",
]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path, help="MT5 HTML report paths")
    parser.add_argument("--deposit", type=float, default=100_000.0, help="Initial deposit (default: 100000)")
    parser.add_argument("--events", action="store_true", help="Output individual drawdown events instead of summary")
    args = parser.parse_args(argv)

    paths = [p for p in args.reports if p.exists()]
    if not paths:
        print("No readable reports found.", file=sys.stderr)
        return 1

    if args.events:
        rows: list[dict[str, str]] = []
        for path in paths:
            rows.extend(event_rows(path))
        writer = csv.DictWriter(sys.stdout, fieldnames=EVENT_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    else:
        rows = [summarize(path, args.deposit) for path in paths]
        writer = csv.DictWriter(sys.stdout, fieldnames=SUMMARY_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
