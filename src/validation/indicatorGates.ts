import type { IndicatorResult, MultiTFData } from '../broker/types';
import { checkADX } from '../indicators/adx';
import { checkATR } from '../indicators/atr';
import { checkEMAStack } from '../indicators/ema';
import { checkRSI } from '../indicators/rsi';
import { checkVWAP } from '../indicators/vwap';

export interface IndicatorGateResults {
  ema: IndicatorResult;
  rsi: IndicatorResult;
  vwap: IndicatorResult;
  atr: IndicatorResult;
  adx: IndicatorResult;
}

export function runIndicatorGates(data: MultiTFData): IndicatorGateResults {
  return {
    ema: checkEMAStack(data.h1Candles),
    rsi: checkRSI(data.m15Candles),
    vwap: checkVWAP(data.m15Candles),
    atr: checkATR(data.h1Candles, data.session),
    adx: checkADX(data.h1Candles)
  };
}
