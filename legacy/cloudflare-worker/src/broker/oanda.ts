import type { AccountInfo, BrokerClient, Candle, PlaceOrderRequest, Position } from './types';

export class OandaClient implements BrokerClient {
  private readonly baseUrl: string;
  constructor(private readonly token: string, private readonly accountId: string, baseUrl = 'https://api-fxpractice.oanda.com') {
    this.baseUrl = baseUrl.replace(/\/$/, '');
  }

  async getCandles(symbol: string, timeframe: string, count: number): Promise<Candle[]> {
    const params = new URLSearchParams({ granularity: timeframe, count: String(count), price: 'M' });
    const data = await this.request<{ candles: Array<{ time: string; volume: number; mid: { o: string; h: string; l: string; c: string } }> }>(`/v3/instruments/${symbol}/candles?${params}`);
    return data.candles.map((candle) => ({ time: candle.time, open: Number(candle.mid.o), high: Number(candle.mid.h), low: Number(candle.mid.l), close: Number(candle.mid.c), volume: candle.volume }));
  }

  async placeMarketOrder(symbol: string, side: 'buy' | 'sell', volume: number, sl: number, tp: number, comment: string): Promise<string> {
    const units = side === 'buy' ? volume : -volume;
    const data = await this.createOrder({ instrument: symbol, units: String(units), type: 'MARKET', stopLossOnFill: { price: String(sl) }, takeProfitOnFill: { price: String(tp) }, clientExtensions: { comment } });
    return data.orderCreateTransaction?.id ?? crypto.randomUUID();
  }

  async placeLimitOrder(order: PlaceOrderRequest): Promise<string> {
    const units = order.type === 'buy_limit' ? order.volume : -order.volume;
    const data = await this.createOrder({ instrument: order.symbol, units: String(units), type: 'LIMIT', price: String(order.price), stopLossOnFill: { price: String(order.sl) }, takeProfitOnFill: { price: String(order.tp) }, clientExtensions: { comment: order.comment } });
    return data.orderCreateTransaction?.id ?? crypto.randomUUID();
  }

  async modifyPosition(_positionId: string, _sl: number, _tp: number): Promise<void> {}
  async closePosition(positionId: string): Promise<void> {
    const [instrument, side] = positionId.split(':');
    if (!instrument || !side) return;
    await this.request(`/v3/accounts/${this.accountId}/positions/${instrument}/close`, {
      method: 'PUT',
      body: JSON.stringify(side === 'long' ? { longUnits: 'ALL' } : { shortUnits: 'ALL' })
    });
  }

  async closePartial(positionId: string, volume: number): Promise<void> {
    const [instrument, side] = positionId.split(':');
    if (!instrument || !side) return;
    await this.request(`/v3/accounts/${this.accountId}/positions/${instrument}/close`, {
      method: 'PUT',
      body: JSON.stringify(side === 'long' ? { longUnits: String(volume) } : { shortUnits: String(volume) })
    });
  }

  async getAccountInfo(): Promise<AccountInfo> {
    const data = await this.request<{ account: { balance: string; NAV: string; currency: string } }>(`/v3/accounts/${this.accountId}`);
    return { balance: Number(data.account.balance), equity: Number(data.account.NAV), currency: data.account.currency };
  }

  async getOpenPositions(): Promise<Position[]> {
    const data = await this.request<{ positions: Array<{ instrument: string; long: { units: string; averagePrice?: string }; short: { units: string; averagePrice?: string } }> }>(`/v3/accounts/${this.accountId}/openPositions`);
    return data.positions.flatMap((position) => {
      const out: Position[] = [];
      if (Number(position.long.units) > 0) out.push({ id: `${position.instrument}:long`, symbol: position.instrument, side: 'buy', volume: Number(position.long.units), openPrice: Number(position.long.averagePrice ?? 0) });
      if (Number(position.short.units) < 0) out.push({ id: `${position.instrument}:short`, symbol: position.instrument, side: 'sell', volume: Math.abs(Number(position.short.units)), openPrice: Number(position.short.averagePrice ?? 0) });
      return out;
    });
  }

  private async createOrder(order: Record<string, unknown>): Promise<{ orderCreateTransaction?: { id: string } }> {
    return this.request(`/v3/accounts/${this.accountId}/orders`, { method: 'POST', body: JSON.stringify({ order }) });
  }

  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    if (!this.token || !this.accountId) throw new Error('OANDA credentials are required');
    const response = await fetch(`${this.baseUrl}${path}`, { ...init, headers: { authorization: `Bearer ${this.token}`, 'content-type': 'application/json', ...init.headers } });
    if (!response.ok) throw new Error(`OANDA request failed ${response.status}: ${await response.text()}`);
    return await response.json() as T;
  }
}
