from __future__ import annotations

from indicators import Candle, atr, ema, rsi
from smc_engine import displacement, liquidity_sweep, market_structure


def validate(m15: list[Candle], h1: list[Candle], h4: list[Candle], threshold: float = 75) -> dict:
    h4_structure = market_structure(h4)
    direction = h4_structure.direction
    if not direction:
        return {"verdict": "SKIP", "score": 0, "reason": "NO_4H_BIAS"}

    gate1 = (direction == "LONG" and h4_structure.in_discount) or (direction == "SHORT" and h4_structure.in_premium)
    gate2 = liquidity_sweep(h1, direction) and displacement(h1, direction)
    gate3 = displacement(m15, direction)
    if not (gate1 and gate2 and gate3):
        return {"verdict": "SKIP", "score": 0, "reason": "SMC_GATE_FAILED"}

    score = 37.5
    closes_h1 = [c.close for c in h1]
    ema21, ema50, ema200 = ema(closes_h1, 21)[-1], ema(closes_h1, 50)[-1], ema(closes_h1, 200)[-1]
    price = closes_h1[-1]
    if direction == "LONG" and price > ema21 > ema50 > ema200:
        score += 12.5
    if direction == "SHORT" and price < ema21 < ema50 < ema200:
        score += 12.5

    latest_rsi = rsi(m15)[-1]
    if 40 <= latest_rsi <= 60:
        score += 12.5

    latest_atr = atr(h1)[-1]
    if 3 <= latest_atr <= 25:
        score += 12.5

    return {"verdict": "TRADE" if score >= threshold else "SKIP", "score": score, "direction": direction}
