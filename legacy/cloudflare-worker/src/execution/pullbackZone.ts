import type { Direction } from '../broker/types';
import type { FVGResult } from '../analysis/fairValueGap';
import type { OrderBlockResult } from '../analysis/orderBlocks';

export interface EntryZone {
  top: number;
  bottom: number;
  midpoint: number;
  quarterPoint: number;
  source: Array<'FVG' | 'OB' | 'EMA21'>;
  confidence: 'HIGH' | 'MEDIUM';
}

export function buildEntryZone(fvg: FVGResult | null, ob: OrderBlockResult | null, ema21: number, _direction: Direction, atr: number): EntryZone | null {
  const zones: Array<[number, number]> = [];
  const sources: EntryZone['source'] = [];
  if (fvg) {
    zones.push([fvg.bottom, fvg.top]);
    sources.push('FVG');
  }
  if (ob) {
    zones.push([ob.low, ob.high]);
    sources.push('OB');
  }
  zones.push([ema21 * 0.998, ema21 * 1.002]);
  sources.push('EMA21');
  const overlapTop = Math.min(...zones.map((zone) => zone[1]));
  const overlapBottom = Math.max(...zones.map((zone) => zone[0]));
  if (overlapBottom >= overlapTop) {
    const widest = zones.reduce((a, b) => b[1] - b[0] > a[1] - a[0] ? b : a);
    if (widest[1] - widest[0] > atr * 1.5) return null;
    return zoneObject(widest[0], widest[1], sources, 'MEDIUM');
  }
  return zoneObject(overlapBottom, overlapTop, sources, sources.length === 3 ? 'HIGH' : 'MEDIUM');
}

function zoneObject(bottom: number, top: number, source: EntryZone['source'], confidence: EntryZone['confidence']): EntryZone {
  const range = top - bottom;
  return { top, bottom, midpoint: bottom + range * 0.5, quarterPoint: bottom + range * 0.25, source, confidence };
}
