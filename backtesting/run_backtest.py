from __future__ import annotations

import json
import csv
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

from indicators import Candle, adx, atr, ema, rsi, vwap
from metrics import passes, summarize


@dataclass
class Params:
    ema_fast: int = 21
    ema_mid: int = 50
    ema_slow: int = 200
    rsi_period: int = 14
    rsi_long_max: float = 58
    rsi_short_min: float = 42
    adx_min: float = 18
    atr_min: float = 1.0
    atr_max: float = 35.0
    sl_atr: float = 1.2
    rr: float = 2.0
    max_hold_bars: int = 96
    cooldown_bars: int = 8
    session_filter: str = "all"


def parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def load_csv(path: Path) -> list[Candle]:
    with path.open() as handle:
        return [
            Candle(row["time"], float(row["open"]), float(row["high"]), float(row["low"]), float(row["close"]), float(row.get("volume") or 1))
            for row in csv.DictReader(handle)
        ]


def resample(candles: list[Candle], minutes: int) -> list[Candle]:
    buckets: dict[int, list[Candle]] = {}
    for candle in candles:
        timestamp = int(parse_time(candle.time).timestamp())
        bucket = timestamp - timestamp % (minutes * 60)
        buckets.setdefault(bucket, []).append(candle)
    out: list[Candle] = []
    for bucket in sorted(buckets):
        group = buckets[bucket]
        out.append(
            Candle(
                datetime.fromtimestamp(bucket, timezone.utc).isoformat().replace("+00:00", "Z"),
                group[0].open,
                max(c.high for c in group),
                min(c.low for c in group),
                group[-1].close,
                sum(c.volume for c in group),
            )
        )
    return out


def in_session(time_value: str, session_filter: str) -> bool:
    if session_filter == "all":
        return True
    hour = parse_time(time_value).hour
    london = 7 <= hour < 12
    overlap = 12 <= hour < 16
    ny = 16 <= hour < 21
    if session_filter == "london_ny":
        return london or overlap or ny
    if session_filter == "london":
        return london
    if session_filter == "ny":
        return ny or overlap
    return True


def signal_at(
    candles: list[Candle],
    index: int,
    h1_index: int,
    precomputed: dict[str, list[float]],
    params: Params,
) -> str | None:
    if index < 220 or h1_index < 220:
        return None
    if not in_session(candles[index].time, params.session_filter):
        return None

    fast = precomputed["ema_fast"][h1_index]
    mid = precomputed["ema_mid"][h1_index]
    slow = precomputed["ema_slow"][h1_index]
    price = precomputed["h1_close"][h1_index]
    trend_long = price > fast > mid > slow
    trend_short = price < fast < mid < slow

    if precomputed["adx"][h1_index] < params.adx_min:
        return None

    atr_value = precomputed["atr"][h1_index]
    if not (params.atr_min <= atr_value <= params.atr_max):
        return None

    latest_rsi = precomputed["rsi"][index]
    session_vwap, upper, lower = vwap(candles[max(0, index - 95) : index + 1])
    close = candles[index].close
    recent_low = min(c.low for c in candles[index - 11 : index + 1])
    recent_high = max(c.high for c in candles[index - 11 : index + 1])
    previous_low = min(c.low for c in candles[index - 35 : index - 11])
    previous_high = max(c.high for c in candles[index - 35 : index - 11])
    swept_low = recent_low < previous_low and close > previous_low
    swept_high = recent_high > previous_high and close < previous_high

    if trend_long and precomputed["plus_di"][h1_index] > precomputed["minus_di"][h1_index] and latest_rsi <= params.rsi_long_max and close <= session_vwap and (close <= lower * 1.003 or swept_low):
        return "LONG"
    if trend_short and precomputed["minus_di"][h1_index] > precomputed["plus_di"][h1_index] and latest_rsi >= params.rsi_short_min and close >= session_vwap and (close >= upper * 0.997 or swept_high):
        return "SHORT"
    return None


def simulate_trade(candles: list[Candle], entry_index: int, direction: str, atr_value: float, params: Params) -> dict | None:
    if entry_index + 1 >= len(candles):
        return None
    entry_candle = candles[entry_index + 1]
    entry = entry_candle.open
    risk = atr_value * params.sl_atr
    sl = entry - risk if direction == "LONG" else entry + risk
    tp = entry + risk * params.rr if direction == "LONG" else entry - risk * params.rr
    end = min(len(candles), entry_index + 1 + params.max_hold_bars)
    for exit_index in range(entry_index + 1, end):
        candle = candles[exit_index]
        hit_sl = candle.low <= sl if direction == "LONG" else candle.high >= sl
        hit_tp = candle.high >= tp if direction == "LONG" else candle.low <= tp
        if hit_sl and hit_tp:
            pnl = -1.0
        elif hit_sl:
            pnl = -1.0
        elif hit_tp:
            pnl = params.rr
        else:
            continue
        return {
            "entry_time": entry_candle.time,
            "exit_time": candle.time,
            "direction": direction,
            "entry": entry,
            "sl": sl,
            "tp": tp,
            "pnl": pnl,
            "rr": pnl,
            "planned_rr": params.rr,
        }
    final = candles[end - 1]
    raw = (final.close - entry) / risk if direction == "LONG" else (entry - final.close) / risk
    pnl = max(-1.0, min(params.rr, raw))
    return {
        "entry_time": entry_candle.time,
        "exit_time": final.time,
        "direction": direction,
        "entry": entry,
        "sl": sl,
        "tp": tp,
        "pnl": pnl,
        "rr": pnl,
        "planned_rr": params.rr,
    }


def run_loaded(candles: list[Candle], h1: list[Candle], params: Params = Params()) -> dict:
    h1_times = [parse_time(candle.time) for candle in h1]
    h1_closes = [c.close for c in h1]
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
        atr_value = precomputed["atr"][h1_index]
        trade = simulate_trade(candles, index, direction, atr_value, params)
        if trade:
            trades.append(trade)
            cooldown_until = index + params.cooldown_bars
    summary = summarize(trades)
    summary["pass"] = passes(summary)
    summary["params"] = asdict(params)
    summary["sample_trades"] = trades[:5]
    return summary


def prepare_data(data_path: Path = Path("backtesting/results/xauusd_m15.csv"), months: int = 24) -> tuple[list[Candle], list[Candle]]:
    candles = load_csv(data_path)
    if months > 0:
        candles = candles[-months * 30 * 24 * 4 :]
    h1 = resample(candles, 60)
    return candles, h1


def run(data_path: Path = Path("backtesting/results/xauusd_m15.csv"), params: Params = Params(), months: int = 24) -> dict:
    candles, h1 = prepare_data(data_path, months)
    return run_loaded(candles, h1, params)


if __name__ == "__main__":
    result = run()
    Path("backtesting/results").mkdir(parents=True, exist_ok=True)
    Path("backtesting/results/backtest_latest.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))
