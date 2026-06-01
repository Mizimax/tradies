#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path


DEFAULT_BASELINE = Path("legacy/cloudflare-worker/backtesting/results/backtest_best_24m.json")


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


def pct_diff(actual: float, expected: float) -> float:
    if expected == 0:
        return 0.0 if actual == 0 else float("inf")
    return (actual - expected) / expected


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare MT5 parity_trades.csv against the Python backtest baseline.")
    parser.add_argument("mt5_csv", type=Path, help="Path to MQL5/Files/GoldBot/parity_trades.csv")
    parser.add_argument("--baseline", type=Path, default=DEFAULT_BASELINE)
    args = parser.parse_args()

    baseline = json.loads(args.baseline.read_text())
    mt5_summary = summarize(read_mt5_trades(args.mt5_csv))

    checks = [
        ("trades", mt5_summary["trades"], baseline["trades"], abs(pct_diff(mt5_summary["trades"], baseline["trades"])) <= 0.05),
        ("win_rate", mt5_summary["win_rate"], baseline["win_rate"], abs(mt5_summary["win_rate"] - baseline["win_rate"]) <= 0.03),
        ("profit_factor", mt5_summary["profit_factor"], baseline["profit_factor"], abs(pct_diff(mt5_summary["profit_factor"], baseline["profit_factor"])) <= 0.10),
        ("expectancy_r", mt5_summary["expectancy_r"], baseline["expectancy_r"], abs(mt5_summary["expectancy_r"] - baseline["expectancy_r"]) <= 0.10),
    ]

    print("MT5 parity summary")
    print(json.dumps(mt5_summary, indent=2))
    print("\nPython baseline")
    print(json.dumps({key: baseline[key] for key in mt5_summary}, indent=2))
    print("\nAcceptance checks")
    for name, actual, expected, ok in checks:
        status = "PASS" if ok else "FAIL"
        print(f"{status} {name}: actual={actual:.6g} expected={expected:.6g}")

    return 0 if all(ok for *_, ok in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
