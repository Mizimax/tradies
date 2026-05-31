import type { Env } from '../broker/types';
import { envNumber } from '../execution/riskManager';

export interface StrategyConfig {
  scoreThreshold: number;
  highConviction: number;
  rsiPeriod: number;
  rsiLongMax: number;
  rsiShortMin: number;
  adxMin: number;
  atrMin: number;
  atrMax: number;
  slAtr: number;
  minRR: number;
  maxHoldBars: number;
  cooldownBars: number;
}

export function getStrategyConfig(env: Env): StrategyConfig {
  return {
    scoreThreshold: envNumber(env, 'SCORE_THRESHOLD', 75),
    highConviction: envNumber(env, 'HIGH_CONVICTION', 88),
    rsiPeriod: envNumber(env, 'RSI_PERIOD', 10),
    rsiLongMax: envNumber(env, 'RSI_LONG_MAX', 38),
    rsiShortMin: envNumber(env, 'RSI_SHORT_MIN', 40),
    adxMin: envNumber(env, 'ADX_MIN', 14),
    atrMin: envNumber(env, 'ATR_MIN', 1.0),
    atrMax: envNumber(env, 'ATR_MAX', 35.0),
    slAtr: envNumber(env, 'SL_ATR', 0.8),
    minRR: envNumber(env, 'MIN_RR', 2.0),
    maxHoldBars: envNumber(env, 'MAX_HOLD_BARS', 48),
    cooldownBars: envNumber(env, 'COOLDOWN_BARS', 16)
  };
}

export function holdBarsToMs(config: StrategyConfig, barMinutes = 15): number {
  return config.maxHoldBars * barMinutes * 60_000;
}

export function cooldownBarsToMs(config: StrategyConfig, barMinutes = 15): number {
  return config.cooldownBars * barMinutes * 60_000;
}
