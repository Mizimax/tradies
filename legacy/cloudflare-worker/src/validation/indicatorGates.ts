import type { IndicatorResult, MultiTFData } from '../broker/types';
import { checkADX } from '../indicators/adx';
import { checkATR } from '../indicators/atr';
import { checkEMAStack } from '../indicators/ema';
import { checkRSI } from '../indicators/rsi';
import { checkVWAP } from '../indicators/vwap';
import type { StrategyConfig } from '../utils/strategyConfig';

export interface IndicatorGateResults {
  ema: IndicatorResult;
  rsi: IndicatorResult;
  vwap: IndicatorResult;
  atr: IndicatorResult;
  adx: IndicatorResult;
}

export function runIndicatorGates(data: MultiTFData, config?: StrategyConfig): IndicatorGateResults {
  const rsiOptions = config ? { period: config.rsiPeriod, longMax: config.rsiLongMax, shortMin: config.rsiShortMin } : {};
  const atrOptions = config ? { minATR: config.atrMin, maxATR: config.atrMax, slAtr: config.slAtr } : {};
  return {
    ema: checkEMAStack(data.h1Candles),
    rsi: checkRSI(data.m15Candles, rsiOptions),
    vwap: checkVWAP(data.m15Candles),
    atr: checkATR(data.h1Candles, data.session, atrOptions),
    adx: checkADX(data.h1Candles, config?.adxMin)
  };
}
