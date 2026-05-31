import type { BrokerClient, Direction, Env, MultiTFData } from '../broker/types';
import { calcRSI } from '../indicators/rsi';
import { sendTelegram } from '../utils/telegram';
import { confirmPullback } from './pullbackConfirm';
import type { EntryZone } from './pullbackZone';
import type { LadderOrder } from './orderLadder';

export interface PendingSignal {
  id: string;
  createdAt: number;
  maxWaitMs: number;
  direction: Direction;
  score: number;
  zone: EntryZone;
  sl: number;
  htfTargets: [number, number, number];
  orders: LadderOrder[];
  status: 'WATCHING' | 'CONFIRMED' | 'PARTIAL' | 'FULL' | 'CLOSED' | 'EXPIRED' | 'CANCELLED';
  fillCount: number;
  realizedPnL: number;
}

export async function loadActiveSignal(env: Env, symbol: string): Promise<PendingSignal | null> {
  return await env.BOT_STATE.get<PendingSignal>(`signal:${symbol}:active`, 'json');
}

export async function saveSignal(env: Env, symbol: string, signal: PendingSignal): Promise<void> {
  await env.BOT_STATE.put(`signal:${symbol}:active`, JSON.stringify(signal));
}

export async function clearSignal(env: Env, symbol: string): Promise<void> {
  await env.BOT_STATE.delete(`signal:${symbol}:active`);
}

export async function managePendingSignal(signal: PendingSignal, symbol: string, currentPrice: number, candles: MultiTFData, broker: BrokerClient, env: Env): Promise<PendingSignal> {
  if (Date.now() - signal.createdAt > signal.maxWaitMs) {
    signal.status = 'EXPIRED';
    await sendTelegram(env, `Signal expired ${signal.id}`);
    return signal;
  }
  const slBreached = signal.direction === 'LONG' ? currentPrice < signal.sl - 1 : currentPrice > signal.sl + 1;
  if (slBreached) {
    signal.status = 'CANCELLED';
    await sendTelegram(env, `Signal cancelled before fill ${signal.id}: SL breached`);
    return signal;
  }
  const rsi = calcRSI(candles.m15Candles);
  for (const order of signal.orders.filter((item) => item.status === 'PENDING')) {
    const nearLevel = signal.direction === 'LONG' ? currentPrice <= order.limitPrice + 0.5 : currentPrice >= order.limitPrice - 0.5;
    const confirm = confirmPullback(candles.m15Candles, candles.m5Candles, signal.zone, signal.direction, rsi);
    if (nearLevel && confirm.confirmed) {
      order.positionId = await broker.placeLimitOrder({
        symbol,
        type: signal.direction === 'LONG' ? 'buy_limit' : 'sell_limit',
        price: order.limitPrice,
        volume: order.volume,
        sl: order.sl,
        tp: order.tp1,
        comment: `GOLD_SMC_${signal.id}_${order.id}`
      });
      order.status = 'PLACED';
      signal.status = 'CONFIRMED';
    }
  }
  return signal;
}
