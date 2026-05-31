import type { Session } from '../broker/types';

export function detectSession(date = new Date()): Session {
  const hour = date.getUTCHours();
  if (hour >= 0 && hour < 7) return 'asian';
  if (hour >= 7 && hour < 12) return 'london';
  if (hour >= 12 && hour < 16) return 'overlap';
  if (hour >= 16 && hour < 21) return 'ny';
  return 'off';
}

export function sessionAllowed(filter: string | undefined, session: Session): boolean {
  if (!filter || filter === 'all') return true;
  if (filter === 'london_ny') return session === 'london' || session === 'overlap' || session === 'ny';
  return filter === session;
}
