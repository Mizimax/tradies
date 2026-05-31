import type { Candle } from '../broker/types';

export const last = <T>(values: T[]): T | undefined => values.at(-1);

export function average(values: number[]): number {
  return values.length === 0 ? Number.NaN : values.reduce((sum, value) => sum + value, 0) / values.length;
}

export function calcEMA(values: number[] | Candle[], period: number): number[] {
  const source = values.map((value) => typeof value === 'number' ? value : value.close);
  if (source.length === 0) return [];
  const alpha = 2 / (period + 1);
  const out: number[] = [];
  let ema = source[0]!;
  for (const value of source) {
    ema = value * alpha + ema * (1 - alpha);
    out.push(ema);
  }
  return out;
}

export function calcRMA(values: number[], period: number): number[] {
  if (values.length === 0) return [];
  const out: number[] = [];
  let rma = values.slice(0, period).reduce((sum, value) => sum + value, 0) / Math.max(1, Math.min(period, values.length));
  for (let i = 0; i < values.length; i += 1) {
    rma = i < period ? average(values.slice(0, i + 1)) : (rma * (period - 1) + values[i]!) / period;
    out.push(rma);
  }
  return out;
}

export function stddev(values: number[]): number {
  const mean = average(values);
  if (!Number.isFinite(mean)) return Number.NaN;
  return Math.sqrt(average(values.map((value) => (value - mean) ** 2)));
}

export function trueRanges(candles: Candle[]): number[] {
  return candles.map((candle, index) => {
    const prevClose = candles[index - 1]?.close ?? candle.close;
    return Math.max(candle.high - candle.low, Math.abs(candle.high - prevClose), Math.abs(candle.low - prevClose));
  });
}

export function within(value: number, low: number, high: number): boolean {
  return value >= Math.min(low, high) && value <= Math.max(low, high);
}
