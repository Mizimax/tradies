#!/usr/bin/env python3
"""Attribute MT5 equity-curve drawdown episodes to journal setups/hours/direction/split/exit-reason.

Reconstructs drawdown episodes from an MT5 Strategy Tester `.htm` report
(reusing ``detect_drawdowns`` from ``equity-curve-analysis.py``) and joins
each episode's peak-to-trough window against the EA journal
(``<stem>.trades.csv``) to attribute the losses inside that episode by
setup, session hour, direction, ladder split, and exit reason (stop-loss vs
take-profit/managed exit). Also detects the longest consecutive
stop-loss-exit streaks.

CSV rows are written to stdout (redirect to ``<stem>.dd-attribution.csv``,
matching the convention used by ``equity-curve-analysis.py`` and
``rolling-stability-check.py``). The readable console summary — top
DD-contributing setups/hours and longest SL streaks — is written to stderr
so it never lands inside a redirected CSV.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Sequence


ROOT = Path(__file__).resolve().parents[1]

MATCH_TOLERANCE_SECONDS = 5.0
SL_EXIT_CODE = "4"
GROUP_FIELDS = ("setup", "hour", "direction", "split", "exit_reason")


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    # Register before exec so dataclasses (e.g. equity-curve-analysis.py's
    # Deal/EquityPoint/DrawdownEvent) can resolve their own module via
    # sys.modules while their class bodies execute.
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


equity_curve = load_module("equity_curve_analysis", ROOT / "scripts/equity-curve-analysis.py")
journal_parser = load_module("analyze_mt5_trades", ROOT / "scripts/analyze-mt5-trades.py")


# ---------------------------------------------------------------------------
# Journal closing-event parsing
# ---------------------------------------------------------------------------

@dataclass
class JournalClose:
    """A single closing 'Deal event' parsed from the EA journal."""
    time: datetime
    profit: float
    setup: str
    direction: str
    split: str
    hour: str
    exit_code: str
    is_sl: bool


def parse_journal_closes(path: Path) -> list[JournalClose]:
    """Extract closing (entry=1) 'Deal event' rows from a trades.csv journal."""
    rows = journal_parser.read_rows(path)
    closes: list[JournalClose] = []
    for time_str, message in rows:
        if "deal event" not in message.lower():
            continue
        fields = journal_parser.parse_message_fields(message)
        if fields.get("entry") != "1":
            continue
        try:
            time = datetime.strptime(time_str.strip(), "%Y.%m.%d %H:%M:%S")
        except ValueError:
            continue
        exit_code = fields.get("reason", "unknown")
        closes.append(JournalClose(
            time=time,
            profit=journal_parser.as_float(fields.get("profit")),
            setup=fields.get("setup", "unknown"),
            direction=fields.get("dir", "unknown"),
            split=fields.get("split", "unknown"),
            hour=fields.get("hour", "unknown"),
            exit_code=exit_code,
            is_sl=(exit_code == SL_EXIT_CODE),
        ))
    closes.sort(key=lambda c: c.time)
    return closes


# ---------------------------------------------------------------------------
# Matching report deals to journal closes
# ---------------------------------------------------------------------------

@dataclass
class MatchedTrade:
    """An htm closing deal joined (when possible) to its journal close event."""
    time: datetime
    profit: float
    journal: JournalClose | None


def match_trades(deals: list, journal_closes: list[JournalClose]) -> tuple[list[MatchedTrade], int]:
    """Join htm 'out' deals to journal closing events by nearest timestamp.

    Both sequences are chronological with normally equal counts (one journal
    'Deal event entry=1' line per htm closing deal, verified 1:1 on the
    winner/baseline reports checked while building this script). Returns the
    matched trades plus the count of journal close events left unused
    (should be 0 when the journal covers the same run as the report).
    """
    htm_closes = sorted((d for d in deals if d.direction == "out"), key=lambda d: d.time)
    used = [False] * len(journal_closes)
    matched: list[MatchedTrade] = []
    pointer = 0
    for deal in htm_closes:
        best_idx = None
        best_diff = None
        k = pointer
        while k < len(journal_closes):
            diff = (journal_closes[k].time - deal.time).total_seconds()
            if diff > MATCH_TOLERANCE_SECONDS:
                break
            if not used[k] and abs(diff) <= MATCH_TOLERANCE_SECONDS:
                if best_diff is None or abs(diff) < best_diff:
                    best_diff = abs(diff)
                    best_idx = k
            k += 1
        journal_close = None
        if best_idx is not None:
            used[best_idx] = True
            journal_close = journal_closes[best_idx]
            pointer = best_idx
        matched.append(MatchedTrade(time=deal.time, profit=deal.profit, journal=journal_close))
    unmatched_journal = sum(1 for flag in used if not flag)
    return matched, unmatched_journal


# ---------------------------------------------------------------------------
# Episode attribution
# ---------------------------------------------------------------------------

def group_value(field: str, journal: JournalClose | None) -> str:
    if journal is None:
        return "unmatched"
    if field == "setup":
        return journal.setup
    if field == "hour":
        return journal.hour
    if field == "direction":
        return journal.direction
    if field == "split":
        return journal.split
    if field == "exit_reason":
        return "sl" if journal.is_sl else "tp_or_manage"
    raise ValueError(field)


def episode_window_trades(episode, matched: list[MatchedTrade]) -> list[MatchedTrade]:
    """Trades strictly after the peak, up to and including the trough.

    The point *at* peak_date is itself the closing deal that set the new
    high-water mark (a winning trade, by construction of detect_drawdowns) —
    it belongs to the prior recovery, not to this episode's losses, so it is
    excluded. Including it would double-count a win as part of the drawdown.
    """
    return [m for m in matched if episode.peak_date < m.time <= episode.trough_date]


def attribute_episode(episode, window_trades: list[MatchedTrade], report_name: str) -> list[dict[str, str]]:
    groups: dict[tuple[str, str], list[MatchedTrade]] = {}
    for trade in window_trades:
        for field in GROUP_FIELDS:
            key = (field, group_value(field, trade.journal))
            groups.setdefault(key, []).append(trade)

    rows: list[dict[str, str]] = []
    for (field, value), trades in sorted(groups.items()):
        profits = [t.profit for t in trades]
        wins = sum(1 for p in profits if p > 0)
        losses = sum(1 for p in profits if p < 0)
        rows.append({
            "report": report_name,
            "episode_num": str(episode.event_num),
            "peak_date": episode.peak_date.strftime("%Y-%m-%d"),
            "trough_date": episode.trough_date.strftime("%Y-%m-%d"),
            "recovery_date": episode.recovery_date.strftime("%Y-%m-%d") if episode.recovery_date else "",
            "depth_pct": f"{episode.depth_pct:.2f}",
            "depth_dollars": f"{episode.depth_dollars:.2f}",
            "duration_days": f"{episode.duration_days:.1f}",
            "group": field,
            "value": value,
            "trades": str(len(trades)),
            "wins": str(wins),
            "losses": str(losses),
            "net_profit": f"{sum(profits):.2f}",
        })
    return rows


# ---------------------------------------------------------------------------
# SL streak detection
# ---------------------------------------------------------------------------

@dataclass
class SlStreak:
    length: int
    start: datetime
    end: datetime
    total_loss: float


def detect_sl_streaks(matched: list[MatchedTrade]) -> list[SlStreak]:
    """Find every run of consecutive stop-loss exits, longest first.

    Trades with no journal match are treated as a break in the streak (their
    exit reason is unknown, so they cannot be assumed to be SL exits).
    """
    streaks: list[SlStreak] = []
    current: list[MatchedTrade] = []

    def flush() -> None:
        if len(current) >= 2:
            streaks.append(SlStreak(
                length=len(current),
                start=current[0].time,
                end=current[-1].time,
                total_loss=sum(t.profit for t in current),
            ))
        current.clear()

    for trade in matched:
        if trade.journal is not None and trade.journal.is_sl:
            current.append(trade)
        else:
            flush()
    flush()

    streaks.sort(key=lambda s: s.length, reverse=True)
    return streaks


# ---------------------------------------------------------------------------
# Reconciliation
# ---------------------------------------------------------------------------

def official_net_profit(report_path: Path) -> float | None:
    """Read net_profit from the sibling .summary.csv if present, else None."""
    summary_path = report_path.with_suffix(".summary.csv")
    if not summary_path.exists():
        return None
    with summary_path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if row.get("report") == report_path.name:
                try:
                    return float(row["net_profit"])
                except (KeyError, ValueError):
                    return None
    return None


# ---------------------------------------------------------------------------
# Per-report processing
# ---------------------------------------------------------------------------

def process_report(path: Path, min_depth_pct: float, top_n: int) -> list[dict[str, str]]:
    deals = equity_curve.extract_deals(path)
    if not deals:
        print(f"WARNING: no deals extracted from {path.name}; skipping", file=sys.stderr)
        return []

    curve = equity_curve.build_equity_curve(deals)
    episodes = equity_curve.detect_drawdowns(curve, min_depth_pct=min_depth_pct)

    journal_path = path.with_suffix(".trades.csv")
    journal_closes: list[JournalClose] = []
    if journal_path.exists():
        journal_closes = parse_journal_closes(journal_path)
    else:
        print(f"WARNING: journal {journal_path.name} not found; exit-reason/setup attribution unavailable", file=sys.stderr)

    matched, unmatched_journal = match_trades(deals, journal_closes)

    # --- reconciliation ---------------------------------------------------
    htm_total = sum(t.profit for t in matched)
    matched_count = sum(1 for t in matched if t.journal is not None)
    report_net_profit = official_net_profit(path)
    print(f"\n=== {path.name} ===", file=sys.stderr)
    print(f"Reconciliation: htm closing deals={len(matched)}, journal close events={len(journal_closes)}, "
          f"matched={matched_count}, unmatched journal events={unmatched_journal}", file=sys.stderr)
    print(f"Sum of htm closing-deal profit: {htm_total:.2f}", file=sys.stderr)
    if report_net_profit is not None:
        diff = htm_total - report_net_profit
        diff_pct = (diff / report_net_profit * 100.0) if report_net_profit else 0.0
        status = "OK" if abs(diff_pct) <= 1.0 or abs(diff) < 1.0 else "MISMATCH"
        print(f"Report net_profit (.summary.csv): {report_net_profit:.2f}  diff={diff:.2f} ({diff_pct:.2f}%)  [{status}]", file=sys.stderr)
    else:
        print("Report net_profit: no sibling .summary.csv found, skipping cross-check", file=sys.stderr)

    # --- per-episode attribution -------------------------------------------
    rows: list[dict[str, str]] = []
    setup_totals: dict[str, float] = {}
    hour_totals: dict[str, float] = {}

    for episode in episodes:
        window_trades = episode_window_trades(episode, matched)
        episode_rows = attribute_episode(episode, window_trades, path.name)
        rows.extend(episode_rows)

        computed_loss = sum(t.profit for t in window_trades)
        expected_loss = -episode.depth_dollars
        ep_diff = computed_loss - expected_loss
        print(
            f"  Episode {episode.event_num}: peak {episode.peak_date:%Y-%m-%d} -> "
            f"trough {episode.trough_date:%Y-%m-%d} (depth {episode.depth_pct:.2f}% / ${episode.depth_dollars:.2f}, "
            f"{len(window_trades)} trades in window, attributed P/L ${computed_loss:.2f}, "
            f"expected ~${expected_loss:.2f}, diff ${ep_diff:.2f})",
            file=sys.stderr,
        )

        for r in episode_rows:
            if r["group"] == "setup":
                setup_totals[r["value"]] = setup_totals.get(r["value"], 0.0) + float(r["net_profit"])
            if r["group"] == "hour":
                hour_totals[r["value"]] = hour_totals.get(r["value"], 0.0) + float(r["net_profit"])

    if not episodes:
        print(f"  No drawdown episodes >= {min_depth_pct:.1f}% found.", file=sys.stderr)

    # --- console summary: top DD-contributing setups/hours -----------------
    print(f"  Top DD-contributing setups (net P/L inside all episode windows, most negative first):", file=sys.stderr)
    for setup, total in sorted(setup_totals.items(), key=lambda kv: kv[1])[:top_n]:
        print(f"    {setup:<20s} {total:>10.2f}", file=sys.stderr)
    print(f"  Top DD-contributing hours (net P/L inside all episode windows, most negative first):", file=sys.stderr)
    for hour, total in sorted(hour_totals.items(), key=lambda kv: kv[1])[:top_n]:
        print(f"    hour={hour:<6s} {total:>10.2f}", file=sys.stderr)

    # --- SL streaks ----------------------------------------------------------
    streaks = detect_sl_streaks(matched)
    print(f"  Longest consecutive stop-loss-exit streaks:", file=sys.stderr)
    if not streaks:
        print("    (none — no 2+ consecutive SL exits found)", file=sys.stderr)
    for streak in streaks[:top_n]:
        print(
            f"    length={streak.length:<3d} {streak.start:%Y-%m-%d %H:%M} -> {streak.end:%Y-%m-%d %H:%M}  "
            f"total_loss=${streak.total_loss:.2f}",
            file=sys.stderr,
        )

    return rows


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

FIELDNAMES = [
    "report", "episode_num", "peak_date", "trough_date", "recovery_date",
    "depth_pct", "depth_dollars", "duration_days", "group", "value",
    "trades", "wins", "losses", "net_profit",
]


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path, help="MT5 HTML report paths (sibling .trades.csv is auto-located)")
    parser.add_argument("--min-depth-pct", type=float, default=2.0, help="Minimum drawdown depth to treat as an episode (default: 2.0)")
    parser.add_argument("--top-n", type=int, default=5, help="Number of top setups/hours/streaks to print (default: 5)")
    args = parser.parse_args(argv)

    paths = [p for p in args.reports if p.exists()]
    if not paths:
        print("No readable reports found.", file=sys.stderr)
        return 1

    rows: list[dict[str, str]] = []
    for path in paths:
        rows.extend(process_report(path, args.min_depth_pct, args.top_n))

    writer = csv.DictWriter(sys.stdout, fieldnames=FIELDNAMES)
    writer.writeheader()
    writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
