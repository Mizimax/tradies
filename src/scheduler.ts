import type { Env, MultiTFData } from './broker/types';
import { brokerSymbol, createBrokerClient, TF_MAP } from './broker';
import { buildOrderLadder } from './execution/orderLadder';
import { appendJournal, getLastSignalTime, setLastSignalTime } from './execution/tradeJournal';
import { clearSignal, loadActiveSignal, managePendingSignal, saveSignal, type PendingSignal } from './execution/tradeManager';
import { loadDailyRiskState, maxOpenTradesAllows } from './execution/riskManager';
import { detectSession, sessionAllowed } from './utils/session';
import { cooldownBarsToMs, getStrategyConfig, holdBarsToMs } from './utils/strategyConfig';
import { sendTelegram } from './utils/telegram';
import { validate } from './validation/validator';
import { parseNewsEvents } from './utils/newsFilter';

export async function runBot(env: Env): Promise<Response> {
  const session = detectSession();
  if (!sessionAllowed(env.SESSION_FILTER, session)) {
    return Response.json({ ok: true, action: 'SKIP', reason: 'SESSION_FILTER', session });
  }
  const config = getStrategyConfig(env);
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
  const data: MultiTFData = { m5Candles, m15Candles, h1Candles, h4Candles, session, now: new Date(), newsEvents: parseNewsEvents(env.NEWS_EVENTS_JSON) };
  const currentPrice = m15Candles.at(-1)?.close;
  if (!currentPrice) throw new Error('No current price returned from broker');

  const active = await loadActiveSignal(env, symbol);
  if (active && ['WATCHING', 'CONFIRMED', 'PARTIAL', 'FULL'].includes(active.status)) {
    const managed = await managePendingSignal(active, symbol, currentPrice, data, broker, env);
    if (['CLOSED', 'EXPIRED', 'CANCELLED'].includes(managed.status)) {
      await clearSignal(env, symbol);
    } else {
      await saveSignal(env, symbol, managed);
    }
    await appendJournal(env, { id: managed.id, time: new Date().toISOString(), type: 'MANAGE', payload: managed });
    return Response.json({ ok: true, action: 'MANAGED_SIGNAL', signal: managed });
  }

  const [openPositions, dailyRisk, lastSignalAt] = await Promise.all([
    broker.getOpenPositions(),
    loadDailyRiskState(env, account, data.now),
    getLastSignalTime(env)
  ]);
  if (!dailyRisk.allowed) {
    await appendJournal(env, { id: crypto.randomUUID(), time: new Date().toISOString(), type: 'RISK', payload: { reason: 'DAILY_RISK_LIMIT', dailyRisk } });
    return Response.json({ ok: true, action: 'SKIP', reason: 'DAILY_RISK_LIMIT', dailyRisk });
  }
  if (!maxOpenTradesAllows(openPositions.length, env)) {
    await appendJournal(env, { id: crypto.randomUUID(), time: new Date().toISOString(), type: 'RISK', payload: { reason: 'MAX_OPEN_TRADES', openCount: openPositions.length } });
    return Response.json({ ok: true, action: 'SKIP', reason: 'MAX_OPEN_TRADES', openCount: openPositions.length });
  }
  const cooldownMs = cooldownBarsToMs(config);
  if (lastSignalAt && Date.now() - lastSignalAt < cooldownMs) {
    return Response.json({ ok: true, action: 'SKIP', reason: 'COOLDOWN', remainingMs: cooldownMs - (Date.now() - lastSignalAt) });
  }

  const validation = validate(data, config);
  if (validation.verdict !== 'TRADE' || !validation.direction || !validation.entryZone || !validation.stopLoss || !validation.takeProfits) {
    await appendJournal(env, { id: crypto.randomUUID(), time: new Date().toISOString(), type: 'SKIP', payload: validation });
    return Response.json({ ok: true, action: 'SKIP', validation });
  }
  const signal: PendingSignal = {
    id: crypto.randomUUID(),
    createdAt: Date.now(),
    maxWaitMs: holdBarsToMs(config),
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
  await setLastSignalTime(env, signal.createdAt);
  await appendJournal(env, { id: signal.id, time: new Date().toISOString(), type: 'SIGNAL', payload: signal });
  await sendTelegram(env, `SIGNAL DETECTED ${signal.direction} ${symbol}\nScore: ${signal.score}/100\nZone: ${signal.zone.bottom}-${signal.zone.top}`);
  return Response.json({ ok: true, action: 'SIGNAL_CREATED', signal });
}
