import { recentJournal } from './execution/tradeJournal';
import { runBot } from './scheduler';
import type { Env } from './broker/types';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === '/status') return Response.json({ ok: true, service: 'gold-trading-bot', time: new Date().toISOString() });
    if (url.pathname === '/trades') return Response.json({ ok: true, journal: await recentJournal(env) });
    if (url.pathname === '/trigger') return runBot(env);
    return new Response('Not found', { status: 404 });
  },

  async scheduled(_event: ScheduledEvent, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(runBot(env));
  }
};
