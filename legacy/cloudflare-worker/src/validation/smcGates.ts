import type { Direction, MultiTFData } from '../broker/types';
import { latestUnmitigatedFVG } from '../analysis/fairValueGap';
import { detectLiquiditySweep, hasDisplacement } from '../analysis/liquiditySweep';
import { analyzeMarketStructure } from '../analysis/marketStructure';
import { latestUnmitigatedOrderBlock } from '../analysis/orderBlocks';
import { withinHighImpactNews } from '../utils/newsFilter';

export interface SMCGateResult {
  gate1_4H: boolean;
  gate2_1H: boolean;
  gate3_15M: boolean;
  allPass: boolean;
  direction: Direction | null;
  score: number;
  reason?: string;
}

export function runSMCGates(data: MultiTFData): SMCGateResult {
  const h4 = analyzeMarketStructure(data.h4Candles, 2);
  const direction = h4.direction;
  if (!direction) return fail('NO_4H_BIAS');
  const h4ZoneOk = direction === 'LONG' ? h4.inDiscount : h4.inPremium;
  const h4Imbalance = latestUnmitigatedOrderBlock(data.h4Candles, direction) || latestUnmitigatedFVG(data.h4Candles, direction);
  const gate1_4H = h4ZoneOk && Boolean(h4Imbalance);

  const h1 = analyzeMarketStructure(data.h1Candles, 2);
  const h1Align = h1.direction === direction || h1.bos || h1.choch;
  const gate2_1H = h1Align && detectLiquiditySweep(data.h1Candles, direction) && hasDisplacement(data.h1Candles, direction);

  const m15Fvg = latestUnmitigatedFVG(data.m15Candles, direction);
  const m15Ob = latestUnmitigatedOrderBlock(data.m15Candles, direction);
  const m15 = analyzeMarketStructure(data.m15Candles, 2);
  const gate3_15M = Boolean(m15Fvg || m15Ob) && (m15.choch || m15.bos) && !withinHighImpactNews(data.now, data.newsEvents);
  const allPass = gate1_4H && gate2_1H && gate3_15M;
  return {
    gate1_4H,
    gate2_1H,
    gate3_15M,
    allPass,
    direction,
    score: allPass ? 37.5 : 0,
    ...(allPass ? {} : { reason: 'SMC_GATE_FAILED' })
  };
}

function fail(reason: string): SMCGateResult {
  return { gate1_4H: false, gate2_1H: false, gate3_15M: false, allPass: false, direction: null, score: 0, reason };
}
