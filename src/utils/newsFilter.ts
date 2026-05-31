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
