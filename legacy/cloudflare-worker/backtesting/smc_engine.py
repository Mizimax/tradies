from __future__ import annotations

from dataclasses import dataclass

from indicators import Candle


@dataclass
class Structure:
    direction: str | None
    range_high: float
    range_low: float
    in_discount: bool
    in_premium: bool


def market_structure(candles: list[Candle], lookback: int = 80) -> Structure:
    window = candles[-lookback:]
    range_high = max(c.high for c in window)
    range_low = min(c.low for c in window)
    midpoint = range_low + (range_high - range_low) / 2
    closes = [c.close for c in window]
    direction = "LONG" if closes[-1] > closes[0] else "SHORT" if closes[-1] < closes[0] else None
    return Structure(direction, range_high, range_low, closes[-1] < midpoint, closes[-1] > midpoint)


def liquidity_sweep(candles: list[Candle], direction: str, lookback: int = 24) -> bool:
    if len(candles) < lookback + 1:
        return False
    last = candles[-1]
    prior = candles[-lookback - 1 : -1]
    key_high = max(c.high for c in prior)
    key_low = min(c.low for c in prior)
    return last.low < key_low < last.close if direction == "LONG" else last.high > key_high > last.close


def displacement(candles: list[Candle], direction: str) -> bool:
    if len(candles) < 12:
        return False
    last = candles[-1]
    avg_body = sum(abs(c.close - c.open) for c in candles[-11:-1]) / 10
    body = abs(last.close - last.open)
    return body > avg_body * 1.5 and (last.close > last.open if direction == "LONG" else last.close < last.open)
