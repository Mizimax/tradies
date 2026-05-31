import type { Candle, IndicatorResult } from '../broker/types';
import { calcRMA } from './math';

export function calcRSI(candles: Candle[], period = 14): number[] {
  const gains: number[] = [];
  const losses: number[] = [];
  for (let i = 0; i < candles.length; i += 1) {
    const diff = i === 0 ? 0 : candles[i]!.close - candles[i - 1]!.close;
    gains.push(Math.max(diff, 0));
    losses.push(Math.max(-diff, 0));
  }
  const avgGain = calcRMA(gains, period);
  const avgLoss = calcRMA(losses, period);
  return candles.map((_, index) => {
    if ((avgLoss[index] ?? 0) === 0) return 100;
    const rs = avgGain[index]! / avgLoss[index]!;
    return 100 - 100 / (1 + rs);
  });
}

export function detectDivergence(candles: Candle[], oscillator: number[], type: 'bullish' | 'bearish', lookback = 20): boolean {
  const start = Math.max(2, candles.length - lookback);
  const window = candles.slice(start);
  const oscWindow = oscillator.slice(start);
  if (window.length < 6) return false;
  const mid = Math.floor(window.length / 2);
  const first = window.slice(0, mid);
  const second = window.slice(mid);
  const firstOsc = oscWindow.slice(0, mid);
  const secondOsc = oscWindow.slice(mid);
  if (type === 'bullish') {
    return Math.min(...second.map((c) => c.low)) < Math.min(...first.map((c) => c.low))
      && Math.min(...secondOsc) > Math.min(...firstOsc);
  }
  return Math.max(...second.map((c) => c.high)) > Math.max(...first.map((c) => c.high))
    && Math.max(...secondOsc) < Math.max(...firstOsc);
}

export interface RSIOptions {
  period?: number;
  longMax?: number;
  shortMin?: number;
  divergenceLookback?: number;
}

export function checkRSI(candles: Candle[], options: RSIOptions = {}): IndicatorResult {
  const period = options.period ?? 14;
  if (candles.length < period + 21) return { name: 'rsi', pass: false, direction: null, score: 0, reason: 'INSUFFICIENT_CANDLES' };
  const rsi = calcRSI(candles, period);
  const latest = rsi.at(-1)!;
  const prev = rsi.at(-2)!;
  if (latest > 80) return { name: 'rsi', pass: false, direction: null, score: 0, reason: 'LONG_OVERBOUGHT_BLOCK', values: { rsi: latest } };
  if (latest < 20) return { name: 'rsi', pass: false, direction: null, score: 0, reason: 'SHORT_OVERSOLD_BLOCK', values: { rsi: latest } };
  const crossedAbove30 = prev < 30 && latest >= 30;
  const crossedBelow70 = prev > 70 && latest <= 70;
  const inPullbackZone = latest >= 40 && latest <= 60;
  const bullDiv = detectDivergence(candles, rsi, 'bullish', options.divergenceLookback ?? 20);
  const bearDiv = detectDivergence(candles, rsi, 'bearish', options.divergenceLookback ?? 20);
  const tunedLongPullback = latest <= (options.longMax ?? -Infinity);
  const tunedShortPullback = latest >= (options.shortMin ?? Infinity);
  const bullScore = [crossedAbove30, bullDiv, inPullbackZone].filter(Boolean).length;
  const bearScore = [crossedBelow70, bearDiv, inPullbackZone].filter(Boolean).length;
  const longPass = bullScore >= 2 || tunedLongPullback;
  const shortPass = bearScore >= 2 || tunedShortPullback;
  const pass = longPass || shortPass;
  return {
    name: 'rsi',
    pass,
    direction: pass ? (longPass && !shortPass ? 'LONG' : shortPass && !longPass ? 'SHORT' : bullScore >= bearScore ? 'LONG' : 'SHORT') : null,
    score: pass ? 12.5 : 0,
    values: { rsi: latest, period, crossedAbove30, crossedBelow70, inPullbackZone, bullDiv, bearDiv, tunedLongPullback, tunedShortPullback }
  };
}
