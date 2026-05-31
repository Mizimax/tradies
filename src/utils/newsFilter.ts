export interface NewsEvent {
  time: string;
  impact: 'low' | 'medium' | 'high';
  currency: string;
  title: string;
}

export function withinHighImpactNews(now: Date, events: NewsEvent[] = [], windowMinutes = 30): boolean {
  return events.some((event) => {
    if (event.impact !== 'high') return false;
    const diff = Math.abs(new Date(event.time).getTime() - now.getTime());
    return diff <= windowMinutes * 60_000;
  });
}

export function parseNewsEvents(raw?: string): NewsEvent[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as NewsEvent[];
    return Array.isArray(parsed) ? parsed.filter((event) => event.time && event.impact && event.currency && event.title) : [];
  } catch {
    return [];
  }
}
