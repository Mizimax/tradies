import type { Candle, IndicatorResult } from '../broker/types';
import { calcEMA } from './math';

export function checkEMAStack(candles: Candle[]): IndicatorResult {
  if (candles.length < 200) return { name: 'ema', pass: false, direction: null, score: 0, reason: 'INSUFFICIENT_CANDLES' };
  const ema21 = calcEMA(candles, 21).at(-1)!;
  const ema50 = calcEMA(candles, 50).at(-1)!;
  const ema200 = calcEMA(candles, 200).at(-1)!;
  const price = candles.at(-1)!.close;
  const bullStack = price > ema21 && ema21 > ema50 && ema50 > ema200;
  const bearStack = price < ema21 && ema21 < ema50 && ema50 < ema200;
  const pullbackConfirmed = bullStack ? price <= ema21 * 1.002 : bearStack ? price >= ema21 * 0.998 : false;
  return {
    name: 'ema',
    pass: bullStack || bearStack,
    direction: bullStack ? 'LONG' : bearStack ? 'SHORT' : null,
    score: bullStack || bearStack ? 12.5 : 0,
    values: { ema21, ema50, ema200, price, pullbackConfirmed }
  };
}
