import type { Candle, Direction } from '../broker/types';

export function detectLiquiditySweep(candles: Candle[], direction: Direction, lookback = 24): boolean {
  if (candles.length < lookback + 2) return false;
  const last = candles.at(-1)!;
  const prior = candles.slice(-lookback - 1, -1);
  const keyHigh = Math.max(...prior.map((c) => c.high));
  const keyLow = Math.min(...prior.map((c) => c.low));
  return direction === 'LONG'
    ? last.low < keyLow && last.close > keyLow
    : last.high > keyHigh && last.close < keyHigh;
}

export function hasDisplacement(candles: Candle[], direction: Direction): boolean {
  if (candles.length < 12) return false;
  const last = candles.at(-1)!;
  const avgBody = candles.slice(-11, -1).reduce((sum, c) => sum + Math.abs(c.close - c.open), 0) / 10;
  const body = Math.abs(last.close - last.open);
  return body > avgBody * 1.5 && (direction === 'LONG' ? last.close > last.open : last.close < last.open);
}
