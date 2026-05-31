from __future__ import annotations

import csv
import json
import subprocess
import sys
from itertools import product
from pathlib import Path

from run_backtest import Params, prepare_data, run_loaded


PARAM_GRID = {
    "rsi_period": [10, 14],
    "rsi_long_max": [45, 52, 60],
    "rsi_short_min": [40, 48, 55],
    "adx_min": [14, 20],
    "sl_atr": [0.8, 1.2],
    "rr": [2.0, 2.5, 3.0],
    "max_hold_bars": [48, 96],
    "cooldown_bars": [8, 16, 32],
    "session_filter": ["all", "london_ny"],
}


def grid_rows() -> list[dict]:
    keys = list(PARAM_GRID)
    return [dict(zip(keys, values)) for values in product(*(PARAM_GRID[key] for key in keys))]


if __name__ == "__main__":
    data_path = Path("backtesting/results/xauusd_m15.csv")
    if not data_path.exists():
        subprocess.run([sys.executable, "backtesting/fetch_data.py", "--source", "hf", "--output", str(data_path)], check=True)
    candles, h1 = prepare_data(data_path, months=6)
    output = Path("backtesting/results/optimization_grid.csv")
    output.parent.mkdir(parents=True, exist_ok=True)
    rows = grid_rows()
    best: dict | None = None
    with output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(PARAM_GRID) + ["trades", "win_rate", "profit_factor", "avg_rr", "avg_trades_day", "score", "pass"])
        writer.writeheader()
        for index, row in enumerate(rows, start=1):
            params = Params(**row)
            summary = run_loaded(candles, h1, params)
            score = (
                min(summary["win_rate"] / 0.55, 1.5)
                + min(summary["profit_factor"] / 1.8, 1.5)
                + min(summary["avg_rr"] / 2.0, 1.5)
                + max(summary.get("expectancy_r", 0), -1)
                + min(summary["trades"] / 80, 1.5)
                + min(summary["avg_trades_day"] / 1.0, 1.5)
            )
            result = {**row, **{key: summary[key] for key in ["trades", "win_rate", "profit_factor", "avg_rr", "avg_trades_day", "pass"]}, "score": score}
            writer.writerow(result)
            if best is None or score > best["score"]:
                best = {**result, "params": row}
            if summary["pass"]:
                best = {**result, "params": row}
                break
            if index % 50 == 0:
                print(f"checked {index}/{len(rows)} best_score={best['score']:.3f} trades={best['trades']} pf={best['profit_factor']:.2f}")
    Path("backtesting/results/optimization_best.json").write_text(json.dumps(best, indent=2))
    print(json.dumps(best, indent=2))
