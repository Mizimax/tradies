import type { Direction, IndicatorResult, MultiTFData } from '../broker/types';
import { latestUnmitigatedFVG } from '../analysis/fairValueGap';
import { latestUnmitigatedOrderBlock } from '../analysis/orderBlocks';
import { calcEMA } from '../indicators/math';
import { buildEntryZone, type EntryZone } from '../execution/pullbackZone';
import { runIndicatorGates, type IndicatorGateResults } from './indicatorGates';
import { runSMCGates, type SMCGateResult } from './smcGates';

export interface MasterValidation {
  totalScore: number;
  smc: SMCGateResult;
  indicators: IndicatorGateResults;
  verdict: 'TRADE' | 'SKIP';
  direction: Direction | null;
  entryZone: EntryZone | null;
  stopLoss: number | null;
  takeProfits: [number, number, number] | null;
  confidence: number;
  reason?: string;
}

export function validate(data: MultiTFData, threshold = 75): MasterValidation {
  const smc = runSMCGates(data);
  const emptyIndicators = runIndicatorGates(data);
  if (!smc.allPass || !smc.direction) {
    return baseResult(smc.score, smc, emptyIndicators, 'SKIP', null, null, null, null, smc.reason);
  }
  const indicators = emptyIndicators;
  const directions = [indicators.ema, indicators.rsi, indicators.vwap, indicators.adx]
    .filter((indicator): indicator is IndicatorResult & { direction: Direction } => indicator.pass && Boolean(indicator.direction))
    .map((indicator) => indicator.direction);
  const consistent = directions.length === 0 || new Set(directions).size === 1;
  if (!consistent) {
    return baseResult(smc.score, smc, indicators, 'SKIP', smc.direction, null, null, null, 'DIRECTION_CONFLICT');
  }
  const indicatorScore = Object.values(indicators).reduce((sum, indicator) => sum + indicator.score, 0);
  const totalScore = smc.score + indicatorScore;
  const atr = Number(indicators.atr.values?.atr ?? 0);
  const ema21 = calcEMA(data.h1Candles, 21).at(-1) ?? data.h1Candles.at(-1)?.close ?? 0;
  const zone = buildEntryZone(
    latestUnmitigatedFVG(data.m15Candles, smc.direction),
    latestUnmitigatedOrderBlock(data.m15Candles, smc.direction),
    ema21,
    smc.direction,
    atr
  );
  if (!zone) return baseResult(totalScore, smc, indicators, 'SKIP', smc.direction, null, null, null, 'NO_ENTRY_ZONE_OVERLAP');
  const latest = data.m15Candles.at(-1)!.close;
  const stopLoss = smc.direction === 'LONG' ? Math.min(zone.bottom, latest - atr * 1.5) : Math.max(zone.top, latest + atr * 1.5);
  const risk = Math.abs(latest - stopLoss);
  const takeProfits: [number, number, number] = smc.direction === 'LONG'
    ? [latest + risk * 1.5, latest + risk * 2.5, latest + risk * 4]
    : [latest - risk * 1.5, latest - risk * 2.5, latest - risk * 4];
  return baseResult(totalScore, smc, indicators, totalScore >= threshold ? 'TRADE' : 'SKIP', smc.direction, zone, stopLoss, takeProfits, totalScore >= threshold ? undefined : 'SCORE_BELOW_THRESHOLD');
}

function baseResult(totalScore: number, smc: SMCGateResult, indicators: IndicatorGateResults, verdict: 'TRADE' | 'SKIP', direction: Direction | null, entryZone: EntryZone | null, stopLoss: number | null, takeProfits: [number, number, number] | null, reason?: string): MasterValidation {
  return {
    totalScore,
    smc,
    indicators,
    verdict,
    direction,
    entryZone,
    stopLoss,
    takeProfits,
    confidence: totalScore,
    ...(reason === undefined ? {} : { reason })
  };
}
