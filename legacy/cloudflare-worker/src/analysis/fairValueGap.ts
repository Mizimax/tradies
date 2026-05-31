import type { Candle, Direction } from '../broker/types';

export interface FVGResult {
  direction: Direction;
  top: number;
  bottom: number;
  index: number;
  mitigated: boolean;
}

export function findFairValueGaps(candles: Candle[], minSizePct = 0.0005): FVGResult[] {
  const gaps: FVGResult[] = [];
  for (let i = 2; i < candles.length; i += 1) {
    const a = candles[i - 2]!;
    const c = candles[i]!;
    if (c.low > a.high) {
      const size = (c.low - a.high) / c.close;
      if (size >= minSizePct) gaps.push({ direction: 'LONG', bottom: a.high, top: c.low, index: i, mitigated: isMitigated(candles, i, a.high, c.low) });
    }
    if (c.high < a.low) {
      const size = (a.low - c.high) / c.close;
      if (size >= minSizePct) gaps.push({ direction: 'SHORT', bottom: c.high, top: a.low, index: i, mitigated: isMitigated(candles, i, c.high, a.low) });
    }
  }
  return gaps;
}

export function latestUnmitigatedFVG(candles: Candle[], direction: Direction): FVGResult | null {
  return findFairValueGaps(candles).filter((gap) => gap.direction === direction && !gap.mitigated).at(-1) ?? null;
}

function isMitigated(candles: Candle[], index: number, bottom: number, top: number): boolean {
  return candles.slice(index + 1).some((candle) => candle.low <= top && candle.high >= bottom);
}
