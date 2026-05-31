import type { Candle, IndicatorResult } from '../broker/types';
import { calcRMA } from './math';

export function calcADX(candles: Candle[], period = 14): { adx: number[]; plusDI: number[]; minusDI: number[] } {
  const tr: number[] = [];
  const plusDM: number[] = [];
  const minusDM: number[] = [];
  for (let i = 0; i < candles.length; i += 1) {
    const current = candles[i]!;
    const prev = candles[i - 1] ?? current;
    const upMove = current.high - prev.high;
    const downMove = prev.low - current.low;
    tr.push(Math.max(current.high - current.low, Math.abs(current.high - prev.close), Math.abs(current.low - prev.close)));
    plusDM.push(upMove > downMove && upMove > 0 ? upMove : 0);
    minusDM.push(downMove > upMove && downMove > 0 ? downMove : 0);
  }
  const atr = calcRMA(tr, period);
  const plus = calcRMA(plusDM, period).map((value, index) => 100 * value / Math.max(atr[index]!, 1e-9));
  const minus = calcRMA(minusDM, period).map((value, index) => 100 * value / Math.max(atr[index]!, 1e-9));
  const dx = plus.map((value, index) => 100 * Math.abs(value - minus[index]!) / Math.max(value + minus[index]!, 1e-9));
  return { adx: calcRMA(dx, period), plusDI: plus, minusDI: minus };
}

export function checkADX(candles: Candle[]): IndicatorResult {
  if (candles.length < 35) return { name: 'adx', pass: false, direction: null, score: 0, reason: 'INSUFFICIENT_CANDLES' };
  const { adx, plusDI, minusDI } = calcADX(candles, 14);
  const latest = adx.at(-1)!;
  const prev = adx.at(-3) ?? latest;
  const bullDI = plusDI.at(-1)! > minusDI.at(-1)!;
  const bearDI = minusDI.at(-1)! > plusDI.at(-1)!;
  const score = latest >= 25 ? 12.5 : latest >= 20 ? 8.0 : 0;
  return {
    name: 'adx',
    pass: latest >= 20,
    direction: bullDI ? 'LONG' : bearDI ? 'SHORT' : null,
    score,
    values: { adx: latest, plusDI: plusDI.at(-1)!, minusDI: minusDI.at(-1)!, rising: latest > prev }
  };
}
