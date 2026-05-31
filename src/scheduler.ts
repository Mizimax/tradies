import type { Env, MultiTFData } from './broker/types';
import { brokerSymbol, createBrokerClient, TF_MAP } from './broker';
import { buildOrderLadder } from './execution/orderLadder';
import { appendJournal } from './execution/tradeJournal';
import { loadActiveSignal, managePendingSignal, saveSignal, type PendingSignal } from './execution/tradeManager';
import { envNumber } from './execution/riskManager';
import { detectSession, sessionAllowed } from './utils/session';
import { sendTelegram } from './utils/telegram';
import { validate } from './validation/validator';

export async function runBot(env: Env): Promise<Response> {
  const session = detectSession();
  if (!sessionAllowed(env.SESSION_FILTER, session)) {
    return Response.json({ ok: true, action: 'SKIP', reason: 'SESSION_FILTER', session });
  }
  const broker = createBrokerClient(env);
  const symbol = brokerSymbol(env);
  const mode = env.BROKER_MODE === 'mt5' ? 'mt5' : 'oanda';
  const tf = TF_MAP[mode];
  const [account, m5Candles, m15Candles, h1Candles, h4Candles] = await Promise.all([
    broker.getAccountInfo(),
    broker.getCandles(symbol, tf.m5, 120),
    broker.getCandles(symbol, tf.m15, 220),
    broker.getCandles(symbol, tf.h1, 260),
    broker.getCandles(symbol, tf.h4, 180)
  ]);
  const data: MultiTFData = { m5Candles, m15Candles, h1Candles, h4Candles, session, now: new Date() };
  const currentPrice = m15Candles.at(-1)?.close;
  if (!currentPrice) throw new Error('No current price returned from broker');

  const active = await loadActiveSignal(env, symbol);
  if (active && ['WATCHING', 'CONFIRMED', 'PARTIAL', 'FULL'].includes(active.status)) {
    const managed = await managePendingSignal(active, symbol, currentPrice, data, broker, env);
    await saveSignal(env, symbol, managed);
    return Response.json({ ok: true, action: 'MANAGED_SIGNAL', signal: managed });
  }

  const validation = validate(data, envNumber(env, 'SCORE_THRESHOLD', 75));
  if (validation.verdict !== 'TRADE' || !validation.direction || !validation.entryZone || !validation.stopLoss || !validation.takeProfits) {
    await appendJournal(env, { id: crypto.randomUUID(), time: new Date().toISOString(), type: 'SKIP', payload: validation });
    return Response.json({ ok: true, action: 'SKIP', validation });
  }
  const signal: PendingSignal = {
    id: crypto.randomUUID(),
    createdAt: Date.now(),
    maxWaitMs: 14_400_000,
    direction: validation.direction,
    score: validation.totalScore,
    zone: validation.entryZone,
    sl: validation.stopLoss,
    htfTargets: validation.takeProfits,
    orders: buildOrderLadder(validation.entryZone, validation.direction, validation.stopLoss, account.equity, validation.totalScore, validation.takeProfits, env),
    status: 'WATCHING',
    fillCount: 0,
    realizedPnL: 0
  };
  await saveSignal(env, symbol, signal);
  await appendJournal(env, { id: signal.id, time: new Date().toISOString(), type: 'SIGNAL', payload: signal });
  await sendTelegram(env, `SIGNAL DETECTED ${signal.direction} ${symbol}\nScore: ${signal.score}/100\nZone: ${signal.zone.bottom}-${signal.zone.top}`);
  return Response.json({ ok: true, action: 'SIGNAL_CREATED', signal });
}
