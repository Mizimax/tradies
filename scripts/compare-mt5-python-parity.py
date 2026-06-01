#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_BASELINE = Path("legacy/cloudflare-worker/backtesting/results/backtest_best_24m.json")
DEFAULT_MT5_ROOT = Path.home() / "Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5"
DEFAULT_PYTHON_DATA = Path("legacy/cloudflare-worker/backtesting/results/xauusd_m15.csv")
BACKTESTING_DIR = Path("legacy/cloudflare-worker/backtesting")


def find_latest_parity_csv(mt5_root: Path = DEFAULT_MT5_ROOT) -> Path | None:
    candidates = list(mt5_root.glob("Tester/Agent-*/MQL5/Files/GoldBot/parity_trades.csv"))
    candidates += list(mt5_root.glob("MQL5/Files/GoldBot/parity_trades.csv"))
    if not candidates:
        return None
    return max(candidates, key=lambda path: path.stat().st_mtime)


def read_mt5_trades(path: Path) -> list[dict]:
    with path.open(newline="") as handle:
        return [
            {
                **row,
                "rr": float(row["rr"]),
                "planned_rr": float(row.get("planned_rr") or 0),
            }
            for row in csv.DictReader(handle)
        ]


def trade_window(trades: list[dict]) -> tuple[str, str]:
    if not trades:
        return "", ""
    return trades[0].get("entry_time", ""), trades[-1].get("exit_time", "")


def summarize(trades: list[dict]) -> dict:
    wins = [trade for trade in trades if trade.get("rr", 0.0) > 0.0]
    losses = [trade for trade in trades if trade.get("rr", 0.0) < 0.0]
    gross_win = sum(trade["rr"] for trade in wins)
    gross_loss = abs(sum(trade["rr"] for trade in losses))
    equity = 0.0
    peak = 0.0
    max_drawdown = 0.0
    days = {trade.get("entry_time", "")[:10] for trade in trades if trade.get("entry_time")}

    for trade in trades:
        equity += trade.get("rr", 0.0)
        peak = max(peak, equity)
        max_drawdown = max(max_drawdown, peak - equity)

    return {
        "trades": len(trades),
        "win_rate": len(wins) / len(trades) if trades else 0.0,
        "profit_factor": gross_win / gross_loss if gross_loss else float("inf"),
        "avg_rr": sum(trade.get("planned_rr", trade.get("rr", 0.0)) for trade in trades) / len(trades) if trades else 0.0,
        "expectancy_r": sum(trade.get("rr", 0.0) for trade in trades) / len(trades) if trades else 0.0,
        "max_drawdown_r": max_drawdown,
        "avg_trades_day": len(trades) / max(1, len(days)),
    }


def parse_date(value: str, end_of_day: bool = False) -> datetime:
    if "T" not in value:
        suffix = "T23:59:59+00:00" if end_of_day else "T00:00:00+00:00"
        value = value + suffix
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def python_summary_for_window(data_path: Path, from_date: str, to_date: str) -> dict:
    sys.path.insert(0, str(BACKTESTING_DIR))
    from run_backtest import Params, load_csv, parse_time, resample, run_loaded

    start = parse_date(from_date)
    end = parse_date(to_date, end_of_day=True)
    candles = [candle for candle in load_csv(data_path) if start <= parse_time(candle.time) <= end]
    params = Params(
        rsi_period=10,
        rsi_long_max=38,
        rsi_short_min=40,
        adx_min=14,
        atr_min=1.0,
        atr_max=35.0,
        sl_atr=0.8,
        rr=2.0,
        max_hold_bars=48,
        cooldown_bars=16,
        session_filter="all",
    )
    result = run_loaded(candles, resample(candles, 60), params)
    return {key: result[key] for key in ["trades", "win_rate", "profit_factor", "avg_rr", "expectancy_r", "max_drawdown_r", "avg_trades_day"]}


def pct_diff(actual: float, expected: float) -> float:
    if expected == 0:
        return 0.0 if actual == 0 else float("inf")
    return (actual - expected) / expected


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare MT5 parity_trades.csv against the Python backtest baseline.")
    parser.add_argument("mt5_csv", type=Path, nargs="?", help="Path to MQL5/Files/GoldBot/parity_trades.csv")
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    parser.add_argument("--python-data", type=Path, default=DEFAULT_PYTHON_DATA)
    parser.add_argument("--from-date", dest="from_date", help="Build Python baseline from this UTC date, e.g. 2023-10-01")
    parser.add_argument("--to-date", dest="to_date", help="Build Python baseline through this UTC date, e.g. 2025-09-30")
    args = parser.parse_args()

    mt5_csv = args.mt5_csv or find_latest_parity_csv()
    if mt5_csv is None:
        print(f"No parity_trades.csv found under {DEFAULT_MT5_ROOT}")
        print("Run MT5 Strategy Tester with InpPythonParityMode=true first.")
        return 2

    if args.from_date and args.to_date:
        baseline = python_summary_for_window(args.python_data, args.from_date, args.to_date)
        baseline_label = f"Python baseline ({args.from_date} -> {args.to_date})"
    else:
        baseline = json.loads(args.baseline.read_text())
        baseline_label = f"Python baseline ({args.baseline})"

    mt5_trades = read_mt5_trades(mt5_csv)
    mt5_summary = summarize(mt5_trades)
    first_trade, last_trade = trade_window(mt5_trades)

    checks: list[tuple[str, float, float, bool]] = [
        ("trades", mt5_summary["trades"], baseline["trades"], abs(pct_diff(mt5_summary["trades"], baseline["trades"])) <= 0.05),
        ("win_rate", mt5_summary["win_rate"], baseline["win_rate"], abs(mt5_summary["win_rate"] - baseline["win_rate"]) <= 0.03),
        ("profit_factor", mt5_summary["profit_factor"], baseline["profit_factor"], abs(pct_diff(mt5_summary["profit_factor"], baseline["profit_factor"])) <= 0.10),
        ("expectancy_r", mt5_summary["expectancy_r"], baseline["expectancy_r"], abs(mt5_summary["expectancy_r"] - baseline["expectancy_r"]) <= 0.10),
    ]

    print(f"MT5 CSV: {mt5_csv}")
    if first_trade or last_trade:
        print(f"MT5 trade window: {first_trade} -> {last_trade}")
    print()
    print("MT5 parity summary")
    print(json.dumps(mt5_summary, indent=2))
    print(f"\n{baseline_label}")
    print(json.dumps({key: baseline[key] for key in mt5_summary}, indent=2))
    print("\nAcceptance checks")
    for name, actual, expected, ok in checks:
        status = "PASS" if ok else "FAIL"
        print(f"{status} {name}: actual={actual:.6g} expected={expected:.6g}")

    return 0 if all(ok for *_, ok in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
