import type { Candle, Direction } from '../broker/types';

export interface SwingPoint {
  index: number;
  price: number;
  type: 'HIGH' | 'LOW';
  time: string;
}

export interface StructureResult {
  direction: Direction | null;
  swings: SwingPoint[];
  bos: boolean;
  choch: boolean;
  rangeHigh: number;
  rangeLow: number;
  inDiscount: boolean;
  inPremium: boolean;
}

export function findSwings(candles: Candle[], length = 3): SwingPoint[] {
  const swings: SwingPoint[] = [];
  for (let i = length; i < candles.length - length; i += 1) {
    const candle = candles[i]!;
    const left = candles.slice(i - length, i);
    const right = candles.slice(i + 1, i + 1 + length);
    if (left.every((c) => candle.high > c.high) && right.every((c) => candle.high >= c.high)) {
      swings.push({ index: i, price: candle.high, type: 'HIGH', time: candle.time });
    }
    if (left.every((c) => candle.low < c.low) && right.every((c) => candle.low <= c.low)) {
      swings.push({ index: i, price: candle.low, type: 'LOW', time: candle.time });
    }
  }
  return swings;
}

export function analyzeMarketStructure(candles: Candle[], swingLength = 3): StructureResult {
  const swings = findSwings(candles, swingLength);
  const highs = swings.filter((s) => s.type === 'HIGH').slice(-3);
  const lows = swings.filter((s) => s.type === 'LOW').slice(-3);
  const latest = candles.at(-1);
  const rangeHigh = Math.max(...candles.slice(-80).map((c) => c.high));
  const rangeLow = Math.min(...candles.slice(-80).map((c) => c.low));
  const midpoint = rangeLow + (rangeHigh - rangeLow) / 2;
  const bullish = highs.length >= 2 && lows.length >= 2 && highs.at(-1)!.price > highs.at(-2)!.price && lows.at(-1)!.price > lows.at(-2)!.price;
  const bearish = highs.length >= 2 && lows.length >= 2 && highs.at(-1)!.price < highs.at(-2)!.price && lows.at(-1)!.price < lows.at(-2)!.price;
  const previousHigh = highs.at(-1)?.price ?? rangeHigh;
  const previousLow = lows.at(-1)?.price ?? rangeLow;
  return {
    direction: bullish ? 'LONG' : bearish ? 'SHORT' : null,
    swings,
    bos: latest ? latest.close > previousHigh || latest.close < previousLow : false,
    choch: latest ? (bullish && latest.close < previousLow) || (bearish && latest.close > previousHigh) : false,
    rangeHigh,
    rangeLow,
    inDiscount: latest ? latest.close < midpoint : false,
    inPremium: latest ? latest.close > midpoint : false
  };
}
