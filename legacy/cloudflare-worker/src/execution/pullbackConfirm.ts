import type { Candle, Direction } from '../broker/types';
import type { EntryZone } from './pullbackZone';

export interface PullbackConfirmation {
  confirmed: boolean;
  signals: { candlePattern: boolean; rsiShift: boolean; microChoCH: boolean };
  checksHit: number;
}

export function confirmPullback(m15Candles: Candle[], m5Candles: Candle[], zone: EntryZone, direction: Direction, rsiValues: number[]): PullbackConfirmation {
  const last = m15Candles.at(-1);
  const inZone = Boolean(last && last.low <= zone.top && last.high >= zone.bottom);
  const candlePattern = inZone && (direction === 'LONG'
    ? isBullishEngulfing(m15Candles) || isPinBar(last!, 'bullish')
    : isBearishEngulfing(m15Candles) || isPinBar(last!, 'bearish'));
  const rsi = rsiValues.at(-1);
  const prevRsi = rsiValues.at(-2);
  const rsiShift = direction === 'LONG' ? (prevRsi ?? 100) < 40 && (rsi ?? 0) >= 40 : (prevRsi ?? 0) > 60 && (rsi ?? 100) <= 60;
  const microChoCH = detect5MChoCH(m5Candles, direction);
  const checksHit = [candlePattern, rsiShift, microChoCH].filter(Boolean).length;
  return { confirmed: checksHit >= 2, signals: { candlePattern, rsiShift, microChoCH }, checksHit };
}

function isBullishEngulfing(candles: Candle[]): boolean {
  const prev = candles.at(-2);
  const last = candles.at(-1);
  return Boolean(prev && last && prev.close < prev.open && last.close > last.open && last.close >= prev.open && last.open <= prev.close);
}

function isBearishEngulfing(candles: Candle[]): boolean {
  const prev = candles.at(-2);
  const last = candles.at(-1);
  return Boolean(prev && last && prev.close > prev.open && last.close < last.open && last.open >= prev.close && last.close <= prev.open);
}

function isPinBar(candle: Candle, type: 'bullish' | 'bearish'): boolean {
  const body = Math.abs(candle.close - candle.open);
  const upper = candle.high - Math.max(candle.close, candle.open);
  const lower = Math.min(candle.close, candle.open) - candle.low;
  return type === 'bullish' ? lower > body * 2 && upper < body * 1.2 : upper > body * 2 && lower < body * 1.2;
}

function detect5MChoCH(candles: Candle[], direction: Direction): boolean {
  if (candles.length < 8) return false;
  const recent = candles.slice(-8);
  const previousHigh = Math.max(...recent.slice(0, 5).map((c) => c.high));
  const previousLow = Math.min(...recent.slice(0, 5).map((c) => c.low));
  const last = recent.at(-1)!;
  return direction === 'LONG' ? last.close > previousHigh : last.close < previousLow;
}
