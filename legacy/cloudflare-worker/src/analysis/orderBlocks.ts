import type { Candle, Direction } from '../broker/types';

export interface OrderBlockResult {
  direction: Direction;
  high: number;
  low: number;
  index: number;
  mitigated: boolean;
}

export function findOrderBlocks(candles: Candle[], direction: Direction, lookback = 20): OrderBlockResult[] {
  const out: OrderBlockResult[] = [];
  const start = Math.max(1, candles.length - lookback);
  for (let i = start; i < candles.length - 1; i += 1) {
    const candle = candles[i]!;
    const next = candles[i + 1]!;
    const body = Math.abs(candle.close - candle.open);
    const nextBody = Math.abs(next.close - next.open);
    const bullishOB = direction === 'LONG' && candle.close < candle.open && next.close > next.open && nextBody > body * 1.2;
    const bearishOB = direction === 'SHORT' && candle.close > candle.open && next.close < next.open && nextBody > body * 1.2;
    if (bullishOB || bearishOB) {
      out.push({ direction, high: candle.high, low: candle.low, index: i, mitigated: isMitigated(candles, i, candle.low, candle.high) });
    }
  }
  return out;
}

export function latestUnmitigatedOrderBlock(candles: Candle[], direction: Direction): OrderBlockResult | null {
  return findOrderBlocks(candles, direction, 80).filter((block) => !block.mitigated).at(-1) ?? null;
}

function isMitigated(candles: Candle[], index: number, low: number, high: number): boolean {
  return candles.slice(index + 2).some((candle) => candle.low <= high && candle.high >= low);
}
