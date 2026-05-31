from __future__ import annotations

from dataclasses import dataclass
from math import sqrt


@dataclass
class Candle:
    time: str
    open: float
    high: float
    low: float
    close: float
    volume: float = 1.0


def ema(values: list[float], period: int) -> list[float]:
    if not values:
        return []
    alpha = 2 / (period + 1)
    out: list[float] = []
    current = values[0]
    for value in values:
        current = value * alpha + current * (1 - alpha)
        out.append(current)
    return out


def rma(values: list[float], period: int) -> list[float]:
    out: list[float] = []
    current = sum(values[:period]) / max(1, min(period, len(values)))
    for index, value in enumerate(values):
        current = sum(values[: index + 1]) / (index + 1) if index < period else (current * (period - 1) + value) / period
        out.append(current)
    return out


def atr(candles: list[Candle], period: int = 14) -> list[float]:
    ranges: list[float] = []
    for index, candle in enumerate(candles):
        prev_close = candles[index - 1].close if index else candle.close
        ranges.append(max(candle.high - candle.low, abs(candle.high - prev_close), abs(candle.low - prev_close)))
    return rma(ranges, period)


def adx(candles: list[Candle], period: int = 14) -> tuple[list[float], list[float], list[float]]:
    trs: list[float] = []
    plus_dm: list[float] = []
    minus_dm: list[float] = []
    for index, candle in enumerate(candles):
        prev = candles[index - 1] if index else candle
        up_move = candle.high - prev.high
        down_move = prev.low - candle.low
        trs.append(max(candle.high - candle.low, abs(candle.high - prev.close), abs(candle.low - prev.close)))
        plus_dm.append(up_move if up_move > down_move and up_move > 0 else 0)
        minus_dm.append(down_move if down_move > up_move and down_move > 0 else 0)
    atr_values = rma(trs, period)
    plus_di = [100 * value / max(atr_values[index], 1e-9) for index, value in enumerate(rma(plus_dm, period))]
    minus_di = [100 * value / max(atr_values[index], 1e-9) for index, value in enumerate(rma(minus_dm, period))]
    dx = [100 * abs(p - m) / max(p + m, 1e-9) for p, m in zip(plus_di, minus_di)]
    return rma(dx, period), plus_di, minus_di


def rsi(candles: list[Candle], period: int = 14) -> list[float]:
    gains: list[float] = []
    losses: list[float] = []
    for index, candle in enumerate(candles):
        diff = 0 if index == 0 else candle.close - candles[index - 1].close
        gains.append(max(diff, 0))
        losses.append(max(-diff, 0))
    avg_gain = rma(gains, period)
    avg_loss = rma(losses, period)
    return [100 if loss == 0 else 100 - 100 / (1 + gain / loss) for gain, loss in zip(avg_gain, avg_loss)]


def stddev(values: list[float]) -> float:
    if not values:
        return 0.0
    mean = sum(values) / len(values)
    return sqrt(sum((value - mean) ** 2 for value in values) / len(values))


def vwap(candles: list[Candle]) -> tuple[float, float, float]:
    pv = 0.0
    volume = 0.0
    typicals: list[float] = []
    for candle in candles:
        typical = (candle.high + candle.low + candle.close) / 3
        vol = max(candle.volume, 1)
        pv += typical * vol
        volume += vol
        typicals.append(typical)
    current = pv / max(volume, 1)
    dev = stddev(typicals)
    return current, current + dev, current - dev
