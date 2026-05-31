import type { Direction, Env } from '../broker/types';
import type { EntryZone } from './pullbackZone';
import { calcLotSize } from './riskManager';

export interface LadderOrder {
  id: 'A' | 'B' | 'C';
  limitPrice: number;
  volume: number;
  sl: number;
  tp1: number;
  tp2: number;
  tp3: number;
  status: 'PENDING' | 'PLACED' | 'ACTIVE' | 'CANCELLED' | 'CLOSED';
  positionId?: string;
  tp1Hit?: boolean;
  tp2Hit?: boolean;
  tp3Hit?: boolean;
}

export function buildOrderLadder(zone: EntryZone, direction: Direction, sl: number, equity: number, score: number, htfTargets: number[], env: Env): LadderOrder[] {
  const entries = direction === 'LONG' ? [zone.top, zone.midpoint, zone.bottom] : [zone.bottom, zone.midpoint, zone.top];
  return entries.map((entryPrice, i) => {
    const slDistance = Math.abs(entryPrice - sl);
    const tp1 = direction === 'LONG' ? entryPrice + slDistance * 1.5 : entryPrice - slDistance * 1.5;
    const tp2 = htfTargets[1] ?? (direction === 'LONG' ? entryPrice + slDistance * 2.5 : entryPrice - slDistance * 2.5);
    const tp3 = htfTargets[2] ?? (direction === 'LONG' ? entryPrice + slDistance * 4 : entryPrice - slDistance * 4);
    return { id: ['A', 'B', 'C'][i] as 'A' | 'B' | 'C', limitPrice: entryPrice, volume: calcLotSize(env, equity, score, i as 0 | 1 | 2), sl, tp1, tp2, tp3, status: 'PENDING' };
  });
}
