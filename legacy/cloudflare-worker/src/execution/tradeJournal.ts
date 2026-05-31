import type { Env } from '../broker/types';

export interface JournalEntry {
  id: string;
  time: string;
  type: 'SIGNAL' | 'ORDER' | 'CLOSE' | 'SKIP' | 'ERROR' | 'MANAGE' | 'RISK';
  payload: unknown;
}

export async function appendJournal(env: Env, entry: JournalEntry): Promise<void> {
  const key = `journal:${entry.time.slice(0, 10)}`;
  const current = await env.BOT_STATE.get<JournalEntry[]>(key, 'json') ?? [];
  current.push(entry);
  await env.BOT_STATE.put(key, JSON.stringify(current.slice(-250)));
}

export async function recentJournal(env: Env): Promise<JournalEntry[]> {
  const today = new Date().toISOString().slice(0, 10);
  return await env.BOT_STATE.get<JournalEntry[]>(`journal:${today}`, 'json') ?? [];
}

export async function getLastSignalTime(env: Env): Promise<number | null> {
  const value = await env.BOT_STATE.get('signal:lastCreatedAt');
  return value ? Number(value) : null;
}

export async function setLastSignalTime(env: Env, timestamp: number): Promise<void> {
  await env.BOT_STATE.put('signal:lastCreatedAt', String(timestamp));
}
