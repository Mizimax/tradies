import type { AccountInfo, BrokerClient, Candle, PlaceOrderRequest, Position } from './types';

export class MetaApiClient implements BrokerClient {
  private readonly baseUrl = 'https://mt-client-api-v1.agiliumtrade.agiliumtrade.ai';
  constructor(private readonly token: string, private readonly accountId: string) {}

  async getCandles(symbol: string, timeframe: string, count: number): Promise<Candle[]> {
    const candles = await this.request<Array<{ time: string; open: number; high: number; low: number; close: number; tickVolume?: number }>>(`/users/current/accounts/${this.accountId}/historical-market-data/symbols/${symbol}/timeframes/${timeframe}/candles?limit=${count}`);
    return candles.map((candle) => ({ time: candle.time, open: candle.open, high: candle.high, low: candle.low, close: candle.close, volume: candle.tickVolume ?? 1 }));
  }

  async placeMarketOrder(symbol: string, side: 'buy' | 'sell', volume: number, sl: number, tp: number, comment: string): Promise<string> {
    const data = await this.trade({ actionType: side === 'buy' ? 'ORDER_TYPE_BUY' : 'ORDER_TYPE_SELL', symbol, volume, stopLoss: sl, takeProfit: tp, comment });
    return data.orderId ?? crypto.randomUUID();
  }

  async placeLimitOrder(order: PlaceOrderRequest): Promise<string> {
    const data = await this.trade({ actionType: order.type === 'buy_limit' ? 'ORDER_TYPE_BUY_LIMIT' : 'ORDER_TYPE_SELL_LIMIT', symbol: order.symbol, volume: order.volume, openPrice: order.price, stopLoss: order.sl, takeProfit: order.tp, comment: order.comment });
    return data.orderId ?? crypto.randomUUID();
  }

  async modifyPosition(positionId: string, sl: number, tp: number): Promise<void> {
    await this.trade({ actionType: 'POSITION_MODIFY', positionId, stopLoss: sl, takeProfit: tp });
  }

  async closePosition(positionId: string): Promise<void> {
    await this.trade({ actionType: 'POSITION_CLOSE_ID', positionId });
  }

  async closePartial(positionId: string, volume: number): Promise<void> {
    await this.trade({ actionType: 'POSITION_PARTIAL', positionId, volume });
  }

  async getAccountInfo(): Promise<AccountInfo> {
    const account = await this.request<{ balance: number; equity: number; margin?: number; currency?: string }>(`/users/current/accounts/${this.accountId}/account-information`);
    return {
      balance: account.balance,
      equity: account.equity,
      ...(account.margin === undefined ? {} : { marginUsed: account.margin }),
      ...(account.currency === undefined ? {} : { currency: account.currency })
    };
  }

  async getOpenPositions(): Promise<Position[]> {
    const positions = await this.request<Array<{ id: string; symbol: string; type: string; volume: number; openPrice: number; stopLoss?: number; takeProfit?: number; unrealizedProfit?: number }>>(`/users/current/accounts/${this.accountId}/positions`);
    return positions.map((position) => ({
      id: position.id,
      symbol: position.symbol,
      side: position.type.includes('BUY') ? 'buy' : 'sell',
      volume: position.volume,
      openPrice: position.openPrice,
      ...(position.stopLoss === undefined ? {} : { sl: position.stopLoss }),
      ...(position.takeProfit === undefined ? {} : { tp: position.takeProfit }),
      ...(position.unrealizedProfit === undefined ? {} : { unrealizedPnL: position.unrealizedProfit })
    }));
  }

  private async trade(body: Record<string, unknown>): Promise<{ orderId?: string }> {
    return this.request(`/users/current/accounts/${this.accountId}/trade`, { method: 'POST', body: JSON.stringify(body) });
  }

  private async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    if (!this.token || !this.accountId) throw new Error('MetaApi credentials are required');
    const response = await fetch(`${this.baseUrl}${path}`, { ...init, headers: { 'auth-token': this.token, 'content-type': 'application/json', ...init.headers } });
    if (!response.ok) throw new Error(`MetaApi request failed ${response.status}: ${await response.text()}`);
    return await response.json() as T;
  }
}
