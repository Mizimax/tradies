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


def mt5_goldbot_sources(mt5_root: Path = DEFAULT_MT5_ROOT) -> list[Path]:
    source_roots = [
        mt5_root / "MQL5/Experts/GoldBot",
        mt5_root / "MQL5/Include/GoldBot",
    ]
    sources: list[Path] = []
    for root in source_roots:
        if root.exists():
            sources.extend(root.glob("*.mq5"))
            sources.extend(root.glob("*.mqh"))
    return sources


def latest_mtime(paths: list[Path]) -> float:
    existing = [path.stat().st_mtime for path in paths if path.exists()]
    return max(existing) if existing else 0.0


def check_fresh_mt5_artifacts(mt5_csv: Path, signal_csv: Path | None, mt5_root: Path = DEFAULT_MT5_ROOT) -> list[str]:
    messages: list[str] = []
    ex5 = mt5_root / "MQL5/Experts/GoldBot/GoldBot.ex5"
    sources = mt5_goldbot_sources(mt5_root)
    newest_source_mtime = latest_mtime(sources)

    if not ex5.exists():
        messages.append(f"compiled EA missing: {ex5}")
        return messages

    ex5_mtime = ex5.stat().st_mtime
    if newest_source_mtime > ex5_mtime:
        newest_source = max((path for path in sources if path.exists()), key=lambda path: path.stat().st_mtime, default=None)
        source_label = f" ({newest_source})" if newest_source else ""
        messages.append(f"compiled EA is older than installed source{source_label}")

    if mt5_csv.stat().st_mtime < ex5_mtime:
        messages.append("parity_trades.csv is older than the compiled EA; run Strategy Tester again")

    if signal_csv is not None and signal_csv.exists() and signal_csv.stat().st_mtime < ex5_mtime:
        messages.append("parity_signals.csv is older than the compiled EA; run Strategy Tester again")

    if newest_source_mtime and mt5_csv.stat().st_mtime < newest_source_mtime:
        messages.append("parity_trades.csv is older than installed source; compile and rerun Strategy Tester")

    if signal_csv is not None and signal_csv.exists() and newest_source_mtime and signal_csv.stat().st_mtime < newest_source_mtime:
        messages.append("parity_signals.csv is older than installed source; compile and rerun Strategy Tester")

    return messages


def find_latest_parity_csv(mt5_root: Path = DEFAULT_MT5_ROOT) -> Path | None:
    candidates = list(mt5_root.glob("Tester/Agent-*/MQL5/Files/GoldBot/parity_trades.csv"))
    candidates += list(mt5_root.glob("MQL5/Files/GoldBot/parity_trades.csv"))
    if not candidates:
        return None
    return max(candidates, key=lambda path: path.stat().st_mtime)


def find_latest_parity_signal_csv(mt5_root: Path = DEFAULT_MT5_ROOT) -> Path | None:
    candidates = list(mt5_root.glob("Tester/Agent-*/MQL5/Files/GoldBot/parity_signals.csv"))
    candidates += list(mt5_root.glob("MQL5/Files/GoldBot/parity_signals.csv"))
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


def read_mt5_signals(path: Path) -> list[dict]:
    numeric_fields = {
        "close",
        "h1_ema21",
        "h1_ema50",
        "h1_ema200",
        "rsi",
        "adx",
        "plus_di",
        "minus_di",
        "atr",
        "vwap",
        "vwap_upper",
        "vwap_lower",
    }
    bool_fields = {
        "ema_long",
        "ema_short",
        "rsi_long",
        "rsi_short",
        "adx_long",
        "adx_short",
        "atr_pass",
        "swept_low",
        "swept_high",
    }
    rows: list[dict] = []
    with path.open(newline="") as handle:
        for row in csv.DictReader(handle):
            parsed = dict(row)
            for field in numeric_fields:
                parsed[field] = float(parsed[field])
            for field in bool_fields:
                parsed[field] = parsed[field] in {"1", "true", "True", "TRUE"}
            rows.append(parsed)
    return rows


def normalize_time(value: str) -> str:
    return value.replace("T", " ").replace(":00Z", "").replace("-", ".")


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


def python_trades_for_window(data_path: Path, from_date: str, to_date: str) -> list[dict]:
    sys.path.insert(0, str(BACKTESTING_DIR))
    from indicators import adx, atr, ema, rsi
    from run_backtest import Params, load_csv, parse_time, resample, signal_at, simulate_trade

    start = parse_date(from_date)
    end = parse_date(to_date, end_of_day=True)
    candles = [candle for candle in load_csv(data_path) if start <= parse_time(candle.time) <= end]
    h1 = resample(candles, 60)
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
    h1_times = [parse_time(candle.time) for candle in h1]
    h1_closes = [candle.close for candle in h1]
    adx_values, plus_di, minus_di = adx(h1)
    precomputed = {
        "h1_close": h1_closes,
        "ema_fast": ema(h1_closes, params.ema_fast),
        "ema_mid": ema(h1_closes, params.ema_mid),
        "ema_slow": ema(h1_closes, params.ema_slow),
        "adx": adx_values,
        "plus_di": plus_di,
        "minus_di": minus_di,
        "atr": atr(h1),
        "rsi": rsi(candles, params.rsi_period),
    }

    trades: list[dict] = []
    cooldown_until = 0
    h1_index = 0
    for index in range(900, len(candles) - params.max_hold_bars - 2):
        if index < cooldown_until:
            continue
        current_time = parse_time(candles[index].time)
        while h1_index + 1 < len(h1_times) and h1_times[h1_index + 1] <= current_time:
            h1_index += 1
        direction = signal_at(candles, index, h1_index, precomputed, params)
        if not direction:
            continue
        trade = simulate_trade(candles, index, direction, precomputed["atr"][h1_index], params)
        if trade:
            trades.append(trade)
            cooldown_until = index + params.cooldown_bars
    return trades


def python_signals_for_window(data_path: Path, from_date: str, to_date: str) -> list[dict]:
    sys.path.insert(0, str(BACKTESTING_DIR))
    from indicators import adx, atr, ema, rsi, vwap
    from run_backtest import Params, load_csv, parse_time, resample, signal_at, simulate_trade

    start = parse_date(from_date)
    end = parse_date(to_date, end_of_day=True)
    candles = [candle for candle in load_csv(data_path) if start <= parse_time(candle.time) <= end]
    h1 = resample(candles, 60)
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
    h1_times = [parse_time(candle.time) for candle in h1]
    h1_closes = [candle.close for candle in h1]
    adx_values, plus_di, minus_di = adx(h1)
    precomputed = {
        "h1_close": h1_closes,
        "ema_fast": ema(h1_closes, params.ema_fast),
        "ema_mid": ema(h1_closes, params.ema_mid),
        "ema_slow": ema(h1_closes, params.ema_slow),
        "adx": adx_values,
        "plus_di": plus_di,
        "minus_di": minus_di,
        "atr": atr(h1),
        "rsi": rsi(candles, params.rsi_period),
    }

    signals: list[dict] = []
    cooldown_until = 0
    h1_index = 0
    for index in range(900, len(candles) - params.max_hold_bars - 2):
        if index < cooldown_until:
            continue
        current_time = parse_time(candles[index].time)
        while h1_index + 1 < len(h1_times) and h1_times[h1_index + 1] <= current_time:
            h1_index += 1

        direction = signal_at(candles, index, h1_index, precomputed, params)
        if not direction:
            continue

        session_vwap, upper, lower = vwap(candles[max(0, index - 95) : index + 1])
        close = candles[index].close
        recent_low = min(c.low for c in candles[index - 11 : index + 1])
        recent_high = max(c.high for c in candles[index - 11 : index + 1])
        previous_low = min(c.low for c in candles[index - 35 : index - 11])
        previous_high = max(c.high for c in candles[index - 35 : index - 11])
        swept_low = recent_low < previous_low and close > previous_low
        swept_high = recent_high > previous_high and close < previous_high
        ema_long = precomputed["h1_close"][h1_index] > precomputed["ema_fast"][h1_index] > precomputed["ema_mid"][h1_index] > precomputed["ema_slow"][h1_index]
        ema_short = precomputed["h1_close"][h1_index] < precomputed["ema_fast"][h1_index] < precomputed["ema_mid"][h1_index] < precomputed["ema_slow"][h1_index]
        row = {
            "signal_time": normalize_time(candles[index].time),
            "direction": direction,
            "close": close,
            "h1_ema21": precomputed["ema_fast"][h1_index],
            "h1_ema50": precomputed["ema_mid"][h1_index],
            "h1_ema200": precomputed["ema_slow"][h1_index],
            "rsi": precomputed["rsi"][index],
            "adx": precomputed["adx"][h1_index],
            "plus_di": precomputed["plus_di"][h1_index],
            "minus_di": precomputed["minus_di"][h1_index],
            "atr": precomputed["atr"][h1_index],
            "vwap": session_vwap,
            "vwap_upper": upper,
            "vwap_lower": lower,
            "ema_long": ema_long,
            "ema_short": ema_short,
            "rsi_long": precomputed["rsi"][index] <= params.rsi_long_max,
            "rsi_short": precomputed["rsi"][index] >= params.rsi_short_min,
            "adx_long": precomputed["adx"][h1_index] >= params.adx_min and precomputed["plus_di"][h1_index] > precomputed["minus_di"][h1_index],
            "adx_short": precomputed["adx"][h1_index] >= params.adx_min and precomputed["minus_di"][h1_index] > precomputed["plus_di"][h1_index],
            "atr_pass": params.atr_min <= precomputed["atr"][h1_index] <= params.atr_max,
            "swept_low": swept_low,
            "swept_high": swept_high,
        }
        signals.append(row)

        trade = simulate_trade(candles, index, direction, precomputed["atr"][h1_index], params)
        if trade:
            cooldown_until = index + params.cooldown_bars
    return signals


def python_summary_for_window(data_path: Path, from_date: str, to_date: str) -> dict:
    return summarize([
        {
            **trade,
            "rr": float(trade["rr"]),
            "planned_rr": float(trade["planned_rr"]),
        }
        for trade in python_trades_for_window(data_path, from_date, to_date)
    ])


def print_trade_diff(python_trades: list[dict], mt5_trades: list[dict], limit: int) -> None:
    python_by_time = {normalize_time(trade["entry_time"]): trade for trade in python_trades}
    mt5_by_time = {normalize_time(trade["entry_time"]): trade for trade in mt5_trades}
    python_times = list(python_by_time)
    mt5_times = list(mt5_by_time)
    common = set(python_times) & set(mt5_times)
    missing = [time for time in python_times if time not in common]
    extra = [time for time in mt5_times if time not in common]

    print("\nTrade timestamp diff")
    print(f"common={len(common)} missing_from_mt5={len(missing)} extra_in_mt5={len(extra)}")
    if missing:
        print("missing_from_mt5:")
        for time in missing[:limit]:
            trade = python_by_time[time]
            print(f"  {time} {trade['direction']} rr={float(trade['rr']):.4f}")
    if extra:
        print("extra_in_mt5:")
        for time in extra[:limit]:
            trade = mt5_by_time[time]
            print(f"  {time} {trade['direction']} rr={float(trade['rr']):.4f}")

    outcome_mismatches = []
    for time in python_times:
        if time not in common:
            continue
        py_trade = python_by_time[time]
        mt_trade = mt5_by_time[time]
        if py_trade["direction"] != mt_trade["direction"] or abs(float(py_trade["rr"]) - float(mt_trade["rr"])) > 0.0001:
            outcome_mismatches.append((time, py_trade, mt_trade))

    if outcome_mismatches:
        print("outcome_mismatches:")
        for time, py_trade, mt_trade in outcome_mismatches[:limit]:
            print(
                f"  {time} py={py_trade['direction']} {float(py_trade['rr']):.4f} "
                f"mt5={mt_trade['direction']} {float(mt_trade['rr']):.4f}"
            )


def print_signal_diff(python_signals: list[dict], mt5_signals: list[dict], signal_csv: Path, limit: int) -> None:
    mt5_times = [normalize_time(row["signal_time"]) for row in mt5_signals]
    duplicate_times = sorted({time for time in mt5_times if mt5_times.count(time) > 1})
    chronological_violations = sum(
        1 for previous, current in zip(mt5_times, mt5_times[1:]) if current < previous
    )
    python_by_key = {(row["signal_time"], row["direction"]): row for row in python_signals}
    mt5_by_key = {(normalize_time(row["signal_time"]), row["direction"]): row for row in mt5_signals}
    python_keys = list(python_by_key)
    mt5_keys = list(mt5_by_key)
    common = set(python_keys) & set(mt5_keys)
    missing = [key for key in python_keys if key not in common]
    extra = [key for key in mt5_keys if key not in common]

    print(f"\nMT5 signal CSV: {signal_csv}")
    print("Signal diagnostics")
    print(
        f"python_signals={len(python_signals)} mt5_rows={len(mt5_signals)} "
        f"mt5_unique={len(mt5_by_key)} duplicates={len(duplicate_times)} "
        f"chronological_violations={chronological_violations}"
    )
    if duplicate_times:
        print("duplicate_signal_times:")
        for time in duplicate_times[:limit]:
            print(f"  {time}")
    print(f"common={len(common)} missing_from_mt5={len(missing)} extra_in_mt5={len(extra)}")
    if missing:
        print("missing_signals_from_mt5:")
        for time, direction in missing[:limit]:
            print(f"  {time} {direction}")
    if extra:
        print("extra_signals_in_mt5:")
        for time, direction in extra[:limit]:
            print(f"  {time} {direction}")

    numeric_fields = [
        "close",
        "h1_ema21",
        "h1_ema50",
        "h1_ema200",
        "rsi",
        "adx",
        "plus_di",
        "minus_di",
        "atr",
        "vwap",
        "vwap_upper",
        "vwap_lower",
    ]
    bool_fields = [
        "ema_long",
        "ema_short",
        "rsi_long",
        "rsi_short",
        "adx_long",
        "adx_short",
        "atr_pass",
        "swept_low",
        "swept_high",
    ]
    mismatches: list[str] = []
    for key in python_keys:
        if key not in common:
            continue
        py_row = python_by_key[key]
        mt5_row = mt5_by_key[key]
        bad_fields: list[str] = []
        for field in numeric_fields:
            if abs(float(py_row[field]) - float(mt5_row[field])) > 0.01:
                bad_fields.append(f"{field}:py={float(py_row[field]):.5f},mt5={float(mt5_row[field]):.5f}")
        for field in bool_fields:
            if bool(py_row[field]) != bool(mt5_row[field]):
                bad_fields.append(f"{field}:py={int(bool(py_row[field]))},mt5={int(bool(mt5_row[field]))}")
        if bad_fields:
            mismatches.append(f"  {key[0]} {key[1]} " + "; ".join(bad_fields[:6]))

    if mismatches:
        print("signal_value_mismatches:")
        for line in mismatches[:limit]:
            print(line)


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
    parser.add_argument("--diff-trades", action="store_true", help="Print timestamp/outcome differences against Python trades.")
    parser.add_argument("--diff-signals", action="store_true", help="Print timestamp/gate differences against Python parity signals.")
    parser.add_argument("--signal-csv", type=Path, help="Path to MQL5/Files/GoldBot/parity_signals.csv")
    parser.add_argument("--allow-stale", action="store_true", help="Allow comparison against CSVs older than installed source/EX5.")
    parser.add_argument("--diff-limit", type=int, default=20)
    args = parser.parse_args()

    mt5_csv = args.mt5_csv or find_latest_parity_csv()
    if mt5_csv is None:
        print(f"No parity_trades.csv found under {DEFAULT_MT5_ROOT}")
        print("Run MT5 Strategy Tester with InpPythonParityMode=true first.")
        return 2

    signal_csv = args.signal_csv or find_latest_parity_signal_csv()
    if not args.allow_stale:
        freshness_messages = check_fresh_mt5_artifacts(mt5_csv, signal_csv)
        if freshness_messages:
            print("Stale MT5 parity artifacts detected:")
            for message in freshness_messages:
                print(f"- {message}")
            print()
            print("Compile GoldBot.mq5 in MetaEditor, rerun Strategy Tester, then rerun this comparison.")
            print("Use --allow-stale only when intentionally inspecting old CSVs.")
            return 2

    if args.from_date and args.to_date:
        python_trades = python_trades_for_window(args.python_data, args.from_date, args.to_date)
        baseline = summarize(python_trades)
        baseline_label = f"Python baseline ({args.from_date} -> {args.to_date})"
    else:
        python_trades = []
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

    if args.diff_trades:
        if not python_trades:
            print("\nTrade diff requires --from-date and --to-date.")
        else:
            print_trade_diff(python_trades, mt5_trades, args.diff_limit)

    if args.diff_signals:
        if not args.from_date or not args.to_date:
            print("\nSignal diff requires --from-date and --to-date.")
        else:
            if signal_csv is None:
                print(f"\nNo parity_signals.csv found under {DEFAULT_MT5_ROOT}")
            else:
                print_signal_diff(
                    python_signals_for_window(args.python_data, args.from_date, args.to_date),
                    read_mt5_signals(signal_csv),
                    signal_csv,
                    args.diff_limit,
                )

    return 0 if all(ok for *_, ok in checks) else 1


if __name__ == "__main__":
    raise SystemExit(main())
