#!/usr/bin/env python3
"""Diagnose BTCScalper momentum trade journals by paired position outcomes."""

from __future__ import annotations

import argparse
import csv
import math
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


DEAL_RE = re.compile(
    r"Deal deal=(?P<deal>\d+) position=(?P<position>\d+) entry=(?P<entry>\d+) "
    r"strategy=(?P<strategy>\S+) profit=(?P<profit>-?\d+(?:\.\d+)?) comment=(?P<comment>.*)"
)


@dataclass
class Trade:
    candidate: str
    position: str
    direction: str
    entry_time: datetime
    exit_time: datetime
    profit: float
    exit_reason: str

    @property
    def hold_hours(self) -> float:
        return max(0.0, (self.exit_time - self.entry_time).total_seconds() / 3600.0)


def parse_time(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d %H:%M:%S")


def candidate_name(path: Path) -> str:
    stem = path.name
    for suffix in (".trades.csv", ".csv"):
        if stem.endswith(suffix):
            stem = stem[: -len(suffix)]
    return stem.replace("BTCScalper-", "")


def exit_reason(comment: str) -> str:
    comment = comment.strip().lower()
    if comment.startswith("tp"):
        return "tp"
    if comment.startswith("sl"):
        return "sl"
    if comment:
        return comment.split()[0]
    return "other"


def load_trades(path: Path) -> list[Trade]:
    entries: dict[str, tuple[datetime, str]] = {}
    trades: list[Trade] = []
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            match = DEAL_RE.fullmatch(row["event"])
            if not match:
                continue
            if match.group("strategy") != "momentum":
                continue

            pos = match.group("position")
            stamp = parse_time(row["timestamp"])
            entry_type = int(match.group("entry"))
            comment = match.group("comment")
            if entry_type == 0:
                if "BTC_Mom_BUY" in comment:
                    entries[pos] = (stamp, "long")
                elif "BTC_Mom_SELL" in comment:
                    entries[pos] = (stamp, "short")
            elif entry_type in (1, 3) and pos in entries:
                entry_time, direction = entries.pop(pos)
                trades.append(
                    Trade(
                        candidate=candidate_name(path),
                        position=pos,
                        direction=direction,
                        entry_time=entry_time,
                        exit_time=stamp,
                        profit=float(match.group("profit")),
                        exit_reason=exit_reason(comment),
                    )
                )
    return trades


def hold_bucket(hours: float) -> str:
    if hours < 6:
        return "<6h"
    if hours < 24:
        return "6-24h"
    if hours < 72:
        return "1-3d"
    return "3d+"


def profit_factor(values: list[float]) -> float:
    gross_profit = sum(v for v in values if v > 0)
    gross_loss = -sum(v for v in values if v < 0)
    if gross_loss == 0:
        return math.inf if gross_profit > 0 else 0.0
    return gross_profit / gross_loss


def summarize(trades: list[Trade], group: str, bucket: str) -> dict[str, str]:
    profits = [trade.profit for trade in trades]
    wins = sum(1 for value in profits if value > 0)
    avg_hold = sum(trade.hold_hours for trade in trades) / len(trades) if trades else 0.0
    pf = profit_factor(profits)
    return {
        "candidate": trades[0].candidate if trades else "",
        "group": group,
        "bucket": bucket,
        "trades": str(len(trades)),
        "net_profit": f"{sum(profits):.2f}",
        "avg_profit": f"{(sum(profits) / len(profits)):.2f}" if profits else "0.00",
        "win_rate_pct": f"{(wins / len(profits) * 100.0):.2f}" if profits else "0.00",
        "profit_factor": "inf" if math.isinf(pf) else f"{pf:.2f}",
        "avg_hold_hours": f"{avg_hold:.2f}",
    }


def emit_group(rows: list[dict[str, str]], trades: list[Trade], group: str, key_fn) -> None:
    buckets: dict[str, list[Trade]] = defaultdict(list)
    for trade in trades:
        buckets[key_fn(trade)].append(trade)
    for bucket in sorted(buckets):
        rows.append(summarize(buckets[bucket], group, bucket))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("journals", nargs="+", type=Path)
    args = parser.parse_args()

    rows: list[dict[str, str]] = []
    for journal in args.journals:
        trades = load_trades(journal)
        if not trades:
            continue
        rows.append(summarize(trades, "all", "all"))
        emit_group(rows, trades, "direction", lambda trade: trade.direction)
        emit_group(rows, trades, "entry_hour", lambda trade: f"{trade.entry_time.hour:02d}")
        emit_group(rows, trades, "entry_month", lambda trade: trade.entry_time.strftime("%Y-%m"))
        emit_group(rows, trades, "exit_reason", lambda trade: trade.exit_reason)
        emit_group(rows, trades, "hold_time", lambda trade: hold_bucket(trade.hold_hours))

    if not rows:
        return 1

    writer = csv.DictWriter(
        sys.stdout,
        fieldnames=[
            "candidate",
            "group",
            "bucket",
            "trades",
            "net_profit",
            "avg_profit",
            "win_rate_pct",
            "profit_factor",
            "avg_hold_hours",
        ],
    )
    writer.writeheader()
    writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
