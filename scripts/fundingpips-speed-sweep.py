#!/usr/bin/env python3
"""Sweep FundingPips risk multipliers over verified GoldBot prop-mode reports.

The adapter journals store each trade as an already-realized fractional account
return. Therefore ``challenge_risk_pct=100`` replays the source report as-is;
150, 200, 250, and 300 apply 1.5x, 2x, 2.5x, and 3x respectively.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import random
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_REPORTS = (
    "GoldBot-prop-ftmo-p1-25000-6m",
    "GoldBot-prop-ftmo-p1-25000-1y",
    "GoldBot-prop-ftmo-p1-25000-2y",
    "GoldBot-prop-ftmo-p1-50000-6m",
    "GoldBot-prop-ftmo-p1-50000-1y",
)
MULTIPLIERS = (1.0, 1.5, 2.0, 2.5, 3.0)
FIELDS = (
    "report", "deposit", "window", "multiplier", "implied_risk_pct",
    "rolling_p_pass", "rolling_p_daily_breach", "rolling_p_dd_breach",
    "rolling_p_censored", "rolling_mean_days", "rolling_median_days",
    "bootstrap_p_pass", "bootstrap_p_daily_breach", "bootstrap_p_dd_breach",
    "bootstrap_mean_days", "bootstrap_median_days",
)


def load_simulator():
    path = ROOT / "scripts" / "prop-challenge-simulator.py"
    spec = importlib.util.spec_from_file_location("prop_challenge_simulator", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def fmt(value):
    if value is None:
        return ""
    if isinstance(value, float):
        return f"{value:.6f}"
    return value


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reports-dir", type=Path, default=ROOT / "mt5/backtests/reports")
    parser.add_argument("--bootstrap-reps", type=int, default=5000)
    parser.add_argument("--bootstrap-block-days", type=int, default=10)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)

    simulator = load_simulator()
    rows = []
    for stem in DEFAULT_REPORTS:
        journal = args.reports_dir / f"{stem}.propguard-sim.csv"
        if not journal.exists():
            raise SystemExit(f"missing verified adapter journal: {journal}")
        trades = simulator.load_closed_trades(journal)
        days = simulator.group_into_days(trades, reset_hour=0)
        parts = stem.split("-")
        deposit = parts[-2]
        window = parts[-1]

        for multiplier in MULTIPLIERS:
            params = simulator.build_params(
                "fundingpips-2step",
                float(deposit),
                challenge_risk_pct=100.0 * multiplier,
                funded_risk_pct=0.5,
                funded_horizon_days=90,
            )
            rolling = simulator.run_rolling_start(days, params)
            bootstrap = simulator.run_block_bootstrap(
                days,
                params,
                args.bootstrap_reps,
                args.bootstrap_block_days,
                random.Random(args.seed),
            )
            row = {
                "report": stem,
                "deposit": deposit,
                "window": window,
                "multiplier": multiplier,
                "implied_risk_pct": 0.5 * multiplier,
                "rolling_p_pass": rolling.get("p_pass_unconditional"),
                "rolling_p_daily_breach": rolling.get("p_fail_daily"),
                "rolling_p_dd_breach": rolling.get("p_fail_dd"),
                "rolling_p_censored": rolling.get("p_censored"),
                "rolling_mean_days": rolling.get("mean_trading_days_to_pass"),
                "rolling_median_days": rolling.get("median_trading_days_to_pass"),
                "bootstrap_p_pass": bootstrap.get("p_pass_unconditional"),
                "bootstrap_p_daily_breach": bootstrap.get("p_fail_daily"),
                "bootstrap_p_dd_breach": bootstrap.get("p_fail_dd"),
                "bootstrap_mean_days": bootstrap.get("mean_trading_days_to_pass"),
                "bootstrap_median_days": bootstrap.get("median_trading_days_to_pass"),
            }
            rows.append({key: fmt(row[key]) for key in FIELDS})

    handle = args.output.open("w", newline="") if args.output else sys.stdout
    try:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    finally:
        if args.output:
            handle.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
