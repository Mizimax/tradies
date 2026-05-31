import type { Env } from '../broker/types';

export function envNumber(env: Env, key: keyof Env, fallback: number): number {
  const raw = env[key];
  const parsed = typeof raw === 'string' ? Number(raw) : Number.NaN;
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function calcLotSize(env: Env, equity: number, score: number, splitIndex: 0 | 1 | 2): number {
  const lotPer100 = envNumber(env, 'LOT_PER_100_USD', 0.01);
  const minLot = envNumber(env, 'MIN_LOT', 0.01);
  const maxLot = envNumber(env, 'MAX_LOT', 5);
  const highConviction = envNumber(env, 'HIGH_CONVICTION', 88);
  const rawTotal = (equity / 100) * lotPer100;
  const adjustedTotal = rawTotal * (score >= highConviction ? 1.5 : 1);
  const splitWeights = [0.33, 0.33, 0.34] as const;
  const orderLot = adjustedTotal * splitWeights[splitIndex];
  const clamped = Math.min(Math.max(orderLot, minLot), maxLot);
  return Math.round(clamped / 0.01) * 0.01;
}

export function lotSummary(env: Env, equity: number, score: number) {
  const orderA = calcLotSize(env, equity, score, 0);
  const orderB = calcLotSize(env, equity, score, 1);
  const orderC = calcLotSize(env, equity, score, 2);
  return { equity, baseLot: orderA + orderB + orderC, orderA, orderB, orderC, multiplier: score >= envNumber(env, 'HIGH_CONVICTION', 88) ? '1.5x' : '1.0x' };
}

export function dailyRiskAllowsTrading(dailyPnlPct: number, env: Env): boolean {
  return dailyPnlPct > -envNumber(env, 'MAX_DAILY_LOSS', 0.03) && dailyPnlPct < envNumber(env, 'DAILY_TARGET', 0.05);
}
