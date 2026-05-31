import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { Candle } from '../../src/broker/types';
import { checkEMAStack } from '../../src/indicators/ema';
import { calcLotSize } from '../../src/execution/riskManager';

function candles(count: number, start = 2000, step = 1): Candle[] {
  return Array.from({ length: count }, (_, index) => {
    const close = start + index * step;
    return { time: new Date(Date.UTC(2026, 0, 1, 0, index)).toISOString(), open: close - step * 0.5, high: close + 1, low: close - 1, close, volume: 100 };
  });
}

describe('indicator gates', () => {
  it('detects a bullish EMA stack', () => {
    const result = checkEMAStack(candles(240, 2000, 1));
    assert.equal(result.pass, true);
    assert.equal(result.direction, 'LONG');
    assert.equal(result.score, 12.5);
  });
});

describe('risk sizing', () => {
  it('uses equity proportional split lots with high conviction multiplier', () => {
    const env = { BOT_STATE: {} as KVNamespace, HIGH_CONVICTION: '88', LOT_PER_100_USD: '0.01', MIN_LOT: '0.01', MAX_LOT: '5' };
    assert.equal(calcLotSize(env, 1000, 75, 0), 0.03);
    assert.equal(calcLotSize(env, 1000, 88, 2), 0.05);
  });
});
