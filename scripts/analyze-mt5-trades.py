#!/usr/bin/env python3
"""Summarize GoldBot real-mode trades.csv journals from MT5 Strategy Tester."""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import Counter
from pathlib import Path


EVENTS = {
    "smc_candidates": "smc candidate",
    "pending_placed": "pending order placed",
    "pending_failed": "pending order failed",
    "ladders_placed": "pending ladder placed",
    "tp1_hits": "tp1 hit",
    "tp2_hits": "tp2 hit",
    "tp3_hits": "tp3 hit",
    "breakeven_moves": "breakeven moved",
    "deal_events": "deal event",
    "trailing_after_tp1": "trailing activated after tp1",
    "max_hold_closes": "position closed after max hold bars",
    "session_blocks": "real session filter blocked",
    "daily_ladder_blocks": "daily ladder limit blocked",
    "higher_tf_blocks": "higher timeframe confirmation blocked",
    "confluence_quality_blocks": "confluence quality blocked",
    "directional_adx_blocks": "directional adx blocked",
    "ema_trend_blocks": "ema trend blocked",
    "m5_pullback_blocks": "m5 pullback confirmation blocked",
    "m5_pullback_passes": "m5 pullback confirmation passed",
    "news_blocks": "news filter blocked",
    "direction_conflict_blocks": "direction conflict blocked",
    "direction_side_blocks": "direction side blocked",
    "near_zone_blocks": "near-zone placement blocked",
    "allowed_hour_blocks": "allowed entry hour blocked",
    "smc_sequence_blocks": "smc sequence blocked",
    "smc_liquidity_blocks": "smc liquidity sweep blocked",
    "smc_displacement_blocks": "smc displacement blocked",
    "smc_overlap_blocks": "smc ob/fvg overlap blocked",
    "htf_smc_context_blocks": "htf smc context blocked",
    "htf_tp_targets": "htf tp targets set",
    "signals_accepted": "signal accepted",
    "signal_skips": "signal skipped",
    "stop_breach_cancels": "stop breach",
}


FIELD_RE = re.compile(r"([A-Za-z][A-Za-z0-9_]*)=([^\s,]+)")


def read_rows(path: Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    with path.open(newline="", errors="ignore") as handle:
        sample = handle.read(4096)
        handle.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",\t;")
        except csv.Error:
            dialect = csv.excel_tab
        reader = csv.reader(handle, dialect)
        for row in reader:
            if not row:
                continue
            if len(row) >= 2 and row[0].strip().lower() == "time":
                continue
            time_value = row[0].strip() if row else ""
            message = " ".join(cell.strip() for cell in row[1:] if cell.strip())
            if message:
                rows.append((time_value, message))
    return rows


def summarize(path: Path) -> dict[str, str]:
    rows = read_rows(path)
    counts: Counter[str] = Counter()
    for _, message in rows:
        lower = message.lower()
        matched = False
        for name, needle in EVENTS.items():
            if needle in lower:
                counts[name] += 1
                matched = True
        if not matched:
            counts["other_events"] += 1

    ladder_times = [time for time, message in rows if "pending ladder placed" in message.lower()]
    tp_times = [time for time, message in rows if message.lower().startswith("tp")]

    summary = {
        "journal": path.name,
        "rows": str(len(rows)),
        "first_event_time": rows[0][0] if rows else "",
        "last_event_time": rows[-1][0] if rows else "",
        "first_ladder_time": ladder_times[0] if ladder_times else "",
        "last_ladder_time": ladder_times[-1] if ladder_times else "",
        "first_tp_time": tp_times[0] if tp_times else "",
        "last_tp_time": tp_times[-1] if tp_times else "",
    }
    for name in EVENTS:
        summary[name] = str(counts[name])
    summary["other_events"] = str(counts["other_events"])
    return summary


def parse_message_fields(message: str) -> dict[str, str]:
    return {match.group(1): match.group(2) for match in FIELD_RE.finditer(message)}


def as_float(value: str | None) -> float:
    try:
        return float(value or "0")
    except ValueError:
        return 0.0


def compact_value(prefix: str, value: str | None) -> str:
    return f"{prefix}{value or 'unknown'}"


def attribution_rows(path: Path) -> list[dict[str, str]]:
    rows = read_rows(path)
    groups: dict[tuple[str, str], Counter[str]] = {}
    sums: dict[tuple[str, str], dict[str, float]] = {}

    def add(group_type: str, group_value: str, profit: float) -> None:
        key = (group_type, group_value or "unknown")
        groups.setdefault(key, Counter())
        sums.setdefault(key, {"net_profit": 0.0, "gross_profit": 0.0, "gross_loss": 0.0})
        groups[key]["closed_deals"] += 1
        if profit > 0:
            groups[key]["wins"] += 1
            sums[key]["gross_profit"] += profit
        elif profit < 0:
            groups[key]["losses"] += 1
            sums[key]["gross_loss"] += profit
        sums[key]["net_profit"] += profit

    for _, message in rows:
        lower = message.lower()
        if "deal event" not in lower:
            continue
        fields = parse_message_fields(message)
        entry = fields.get("entry", "")
        if entry not in {"1", "2", "3"}:
            continue
        profit = as_float(fields.get("profit"))
        direction = fields.get("dir", "unknown")
        split = fields.get("split", "unknown")
        hour = fields.get("hour", "unknown")
        confluences = fields.get("confluences", "unknown").split("/", 1)[0]
        for group_type, group_value in (
            ("direction", direction),
            ("split", split),
            ("session_hour", hour),
            ("direction_hour", f"{compact_value('dir', direction)}_{compact_value('hour', hour)}"),
            ("direction_split", f"{compact_value('dir', direction)}_{compact_value('split', split)}"),
            ("hour_split", f"{compact_value('hour', hour)}_{compact_value('split', split)}"),
            ("score_bucket", fields.get("scoreBucket", "unknown")),
            ("confluence_count", confluences),
            ("exit_reason", fields.get("reason", "unknown")),
        ):
            add(group_type, group_value, profit)

    output: list[dict[str, str]] = []
    for key in sorted(groups):
        group_type, group_value = key
        count = groups[key]["closed_deals"]
        wins = groups[key]["wins"]
        gross_profit = sums[key]["gross_profit"]
        gross_loss = sums[key]["gross_loss"]
        profit_factor = gross_profit / abs(gross_loss) if gross_loss < 0 else (gross_profit if gross_profit > 0 else 0.0)
        output.append({
            "journal": path.name,
            "group": group_type,
            "value": group_value,
            "closed_deals": str(count),
            "net_profit": f"{sums[key]['net_profit']:.2f}",
            "gross_profit": f"{gross_profit:.2f}",
            "gross_loss": f"{gross_loss:.2f}",
            "profit_factor": f"{profit_factor:.2f}",
            "win_rate_pct": f"{(wins / count * 100.0) if count else 0.0:.2f}",
        })
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("journals", nargs="+", type=Path, help="GoldBot trades.csv paths")
    parser.add_argument("--attribution", action="store_true", help="Group closed deal PnL by direction, split, hour, direction/hour, direction/split, hour/split, score, confluence, and exit reason")
    args = parser.parse_args()

    if args.attribution:
        rows = [row for path in args.journals if path.exists() for row in attribution_rows(path)]
        fieldnames = ["journal", "group", "value", "closed_deals", "net_profit", "gross_profit", "gross_loss", "profit_factor", "win_rate_pct"]
    else:
        rows = [summarize(path) for path in args.journals if path.exists()]
        fieldnames = list(rows[0].keys()) if rows else []

    if not rows:
        if args.attribution:
            writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
            writer.writeheader()
            return 0
        print("No readable trades.csv journal rows found.", file=sys.stderr)
        return 1

    writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
