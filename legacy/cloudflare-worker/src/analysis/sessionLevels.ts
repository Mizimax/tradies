import type { Candle } from '../broker/types';

export function previousDayLevels(candles: Candle[]): { high: number; low: number } | null {
  const latestDay = candles.at(-1)?.time.slice(0, 10);
  const previous = candles.filter((candle) => candle.time.slice(0, 10) !== latestDay).slice(-96);
  if (previous.length === 0) return null;
  return { high: Math.max(...previous.map((c) => c.high)), low: Math.min(...previous.map((c) => c.low)) };
}
