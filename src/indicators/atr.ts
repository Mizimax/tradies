import type { Candle, IndicatorResult, Session } from '../broker/types';
import { calcRMA, trueRanges } from './math';

export function calcATR(candles: Candle[], period = 14): number[] {
  return calcRMA(trueRanges(candles), period);
}

export interface ATROptions {
  minATR?: number;
  maxATR?: number;
  slAtr?: number;
}

export function checkATR(candles: Candle[], session: Session, options: ATROptions = {}): IndicatorResult {
  if (candles.length < 20) return { name: 'atr', pass: false, direction: null, score: 0, reason: 'INSUFFICIENT_CANDLES' };
  const atrValues = calcATR(candles, 14);
  const atr = atrValues.at(-1)!;
  const prevAtr = atrValues.at(-6) ?? atr;
  const minATR = options.minATR ?? (session === 'asian' ? 1.5 : 3.0);
  const maxATR = options.maxATR ?? 25.0;
  const slAtr = options.slAtr ?? 1.5;
  const inRange = atr >= minATR && atr <= maxATR;
  return {
    name: 'atr',
    pass: inRange,
    direction: null,
    score: inRange ? 12.5 : 0,
    values: { atr, expanding: atr > prevAtr, suggestedSL: atr * slAtr, suggestedTP: atr * slAtr * 2, minATR, maxATR, slAtr }
  };
}
