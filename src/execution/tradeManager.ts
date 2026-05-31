import type { BrokerClient, Direction, Env, MultiTFData } from '../broker/types';
import { calcATR } from '../indicators/atr';
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
  await refreshPlacedOrders(signal, currentPrice, broker);
  const atr = calcATR(candles.h1Candles).at(-1) ?? Math.abs(currentPrice - signal.sl);
  for (const order of signal.orders.filter((item) => item.status === 'ACTIVE')) {
    await manageActiveOrder(signal, order, currentPrice, atr, broker, env);
  }
  signal.fillCount = signal.orders.filter((order) => order.status === 'ACTIVE' || order.status === 'CLOSED').length;
  if (signal.orders.every((order) => order.status === 'CLOSED' || order.status === 'CANCELLED')) {
    signal.status = 'CLOSED';
  } else if (signal.orders.some((order) => order.status === 'ACTIVE')) {
    signal.status = signal.orders.every((order) => order.status === 'ACTIVE' || order.status === 'CLOSED' || order.status === 'CANCELLED') ? 'FULL' : 'PARTIAL';
  }
  return signal;
}

async function refreshPlacedOrders(signal: PendingSignal, currentPrice: number, broker: BrokerClient): Promise<void> {
  const positions = await broker.getOpenPositions();
  for (const order of signal.orders.filter((item) => item.status === 'PLACED')) {
    const positionMatch = order.positionId ? positions.find((position) => position.id === order.positionId) : undefined;
    const priceCrossedEntry = signal.direction === 'LONG' ? currentPrice <= order.limitPrice : currentPrice >= order.limitPrice;
    if (positionMatch || priceCrossedEntry) {
      order.status = 'ACTIVE';
    }
  }
}

async function manageActiveOrder(signal: PendingSignal, order: LadderOrder, price: number, atr: number, broker: BrokerClient, env: Env): Promise<void> {
  if (!order.positionId) return;
  if (!order.tp1Hit && priceHit(price, order.tp1, signal.direction)) {
    await broker.closePartial(order.positionId, roundVolume(order.volume * 0.5));
    await broker.modifyPosition(order.positionId, order.limitPrice, order.tp2);
    order.tp1Hit = true;
    await sendTelegram(env, `TP1 hit - ${signal.id} order ${order.id}; SL moved to breakeven`);
  }
  if (order.tp1Hit && !order.tp2Hit && priceHit(price, order.tp2, signal.direction)) {
    await broker.closePartial(order.positionId, roundVolume(order.volume * 0.3));
    const trailSL = signal.direction === 'LONG' ? price - atr : price + atr;
    await broker.modifyPosition(order.positionId, trailSL, order.tp3);
    order.tp2Hit = true;
    await sendTelegram(env, `TP2 hit - ${signal.id} order ${order.id}; trailing SL active`);
  }
  if (order.tp2Hit && !order.tp3Hit && priceHit(price, order.tp3, signal.direction)) {
    await broker.closePosition(order.positionId);
    order.tp3Hit = true;
    order.status = 'CLOSED';
    await sendTelegram(env, `TP3 hit - ${signal.id} order ${order.id} closed`);
  }
  if (priceHit(price, order.sl, signal.direction === 'LONG' ? 'SHORT' : 'LONG')) {
    order.status = 'CLOSED';
    await sendTelegram(env, `SL hit - ${signal.id} order ${order.id}`);
    for (const pending of signal.orders.filter((item) => item.status === 'PENDING' || item.status === 'PLACED')) {
      pending.status = 'CANCELLED';
    }
  }
}

function priceHit(price: number, target: number, direction: Direction): boolean {
  return direction === 'LONG' ? price >= target : price <= target;
}

function roundVolume(volume: number): number {
  return Math.max(0.01, Math.round(volume * 100) / 100);
}
