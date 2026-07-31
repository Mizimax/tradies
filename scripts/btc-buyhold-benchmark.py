#!/usr/bin/env python3
"""Compute a buy-and-hold benchmark from broker-exported BTC candles."""

from __future__ import annotations

import argparse
import csv
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
import re


@dataclass(frozen=True)
class Bar:
    time: datetime
    close: float


def parse_time(value: str) -> datetime:
    value = value.strip()
    for fmt in ("%Y.%m.%d %H:%M:%S", "%Y.%m.%d %H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y.%m.%d", "%Y-%m-%d"):
        try:
            return datetime.strptime(value, fmt)
        except ValueError:
            pass
    raise ValueError(f"Unsupported datetime format: {value!r}")


def parse_bound(value: str, *, is_end: bool) -> datetime:
    if is_end and re.fullmatch(r"\d{4}[.-]\d{2}[.-]\d{2}", value.strip()):
        value = f"{value.strip()} 23:59:59"
    return parse_time(value)


def normalized_header(name: str) -> str:
    return name.strip().lower().replace("<", "").replace(">", "").replace(" ", "_")


def load_bars(path: Path) -> list[Bar]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        if reader.fieldnames is None:
            raise SystemExit(f"{path}: CSV has no header row")

        field_map = {normalized_header(name): name for name in reader.fieldnames}
        datetime_key = field_map.get("datetime")
        time_key = field_map.get("time")
        date_key = field_map.get("date")
        close_key = field_map.get("close")
        if close_key is None:
            raise SystemExit(f"{path}: no close column found")
        if datetime_key is None and time_key is None and date_key is None:
            raise SystemExit(f"{path}: no time/datetime or date column found")

        bars: list[Bar] = []
        for line_no, row in enumerate(reader, start=2):
            try:
                if datetime_key is not None:
                    stamp = parse_time(row[datetime_key])
                elif date_key is not None:
                    raw_time = row[time_key] if time_key is not None else "00:00:00"
                    stamp = parse_time(f"{row[date_key]} {raw_time}")
                else:
                    stamp = parse_time(row[time_key])
                close = float(row[close_key])
            except (KeyError, TypeError, ValueError) as exc:
                raise SystemExit(f"{path}:{line_no}: invalid bar: {exc}") from exc
            bars.append(Bar(stamp, close))

    bars.sort(key=lambda bar: bar.time)
    return bars


def max_drawdown_pct(equity: list[float]) -> float:
    peak = equity[0]
    max_dd = 0.0
    for value in equity:
        if value > peak:
            peak = value
        if peak > 0:
            max_dd = max(max_dd, (peak - value) / peak * 100.0)
    return max_dd


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rates", type=Path, required=True, help="Broker candle CSV with time/date and close columns")
    parser.add_argument("--from-date", required=True, help="Inclusive start date, e.g. 2024.06.01")
    parser.add_argument("--to-date", required=True, help="Inclusive end date, e.g. 2026.05.31")
    parser.add_argument("--deposit", type=float, default=100000.0)
    args = parser.parse_args()

    start = parse_bound(args.from_date, is_end=False)
    end = parse_bound(args.to_date, is_end=True)
    bars = [bar for bar in load_bars(args.rates) if start <= bar.time <= end]
    if len(bars) < 2:
        raise SystemExit("Need at least two bars inside the requested window")

    first = bars[0].close
    if first <= 0:
        raise SystemExit("First close must be positive")

    equity = [args.deposit * (bar.close / first) for bar in bars]
    final_equity = equity[-1]
    net_profit = final_equity - args.deposit
    net_pct = net_profit / args.deposit * 100.0
    dd_pct = max_drawdown_pct(equity)

    print("metric,value")
    print(f"rates,{args.rates}")
    print(f"from,{bars[0].time:%Y-%m-%d %H:%M:%S}")
    print(f"to,{bars[-1].time:%Y-%m-%d %H:%M:%S}")
    print(f"bars,{len(bars)}")
    print(f"start_close,{first:.8f}")
    print(f"end_close,{bars[-1].close:.8f}")
    print(f"deposit,{args.deposit:.2f}")
    print(f"final_equity,{final_equity:.2f}")
    print(f"net_profit,{net_profit:.2f}")
    print(f"net_return_pct,{net_pct:.4f}")
    print(f"close_to_close_max_dd_pct,{dd_pct:.4f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
