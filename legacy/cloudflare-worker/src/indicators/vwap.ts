import type { Candle, IndicatorResult } from '../broker/types';
import { stddev } from './math';

export function calcVWAP(candles: Candle[]): { vwap: number; upperBand: number; lowerBand: number } {
  const latestDay = candles.at(-1)?.time.slice(0, 10);
  const session = candles.filter((candle) => candle.time.slice(0, 10) === latestDay);
  let pv = 0;
  let volume = 0;
  const typicals: number[] = [];
  for (const candle of session.length ? session : candles) {
    const typical = (candle.high + candle.low + candle.close) / 3;
    const vol = Math.max(1, candle.volume);
    pv += typical * vol;
    volume += vol;
    typicals.push(typical);
  }
  const vwap = pv / Math.max(1, volume);
  const dev = stddev(typicals);
  return { vwap, upperBand: vwap + dev, lowerBand: vwap - dev };
}

export function checkVWAP(candles: Candle[]): IndicatorResult {
  if (candles.length < 10) return { name: 'vwap', pass: false, direction: null, score: 0, reason: 'INSUFFICIENT_CANDLES' };
  const { vwap, upperBand, lowerBand } = calcVWAP(candles);
  const price = candles.at(-1)!.close;
  const longSetup = price < vwap && price <= lowerBand * 1.001;
  const shortSetup = price > vwap && price >= upperBand * 0.999;
  return {
    name: 'vwap',
    pass: longSetup || shortSetup,
    direction: longSetup ? 'LONG' : shortSetup ? 'SHORT' : null,
    score: longSetup || shortSetup ? 12.5 : 0,
    values: { vwap, upperBand, lowerBand, price }
  };
}
