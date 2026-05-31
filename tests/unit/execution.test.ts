import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import type { Env } from '../../src/broker/types';
import { buildOrderLadder } from '../../src/execution/orderLadder';
import type { EntryZone } from '../../src/execution/pullbackZone';

describe('order ladder', () => {
  it('builds long entries from top to bottom', () => {
    const env = { BOT_STATE: {} as KVNamespace, LOT_PER_100_USD: '0.01', MIN_LOT: '0.01', MAX_LOT: '5' } satisfies Partial<Env> as Env;
    const zone: EntryZone = { top: 2350, bottom: 2340, midpoint: 2345, quarterPoint: 2342.5, source: ['FVG', 'EMA21'], confidence: 'MEDIUM' };
    const orders = buildOrderLadder(zone, 'LONG', 2330, 1000, 75, [2365, 2385, 2420], env);
    assert.deepEqual(orders.map((order) => order.limitPrice), [2350, 2345, 2340]);
    assert.equal(orders[0]?.tp1, 2380);
  });
});
