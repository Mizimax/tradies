import type { BrokerClient, Direction, PlaceOrderRequest } from '../broker/types';
import type { LadderOrder } from './orderLadder';

export async function placeLadder(symbol: string, direction: Direction, orders: LadderOrder[], broker: BrokerClient): Promise<LadderOrder[]> {
  for (const order of orders) {
    if (order.status !== 'PENDING') continue;
    const request: PlaceOrderRequest = {
      symbol,
      type: direction === 'LONG' ? 'buy_limit' : 'sell_limit',
      price: order.limitPrice,
      volume: order.volume,
      sl: order.sl,
      tp: order.tp1,
      comment: `GOLD_SMC_${order.id}`
    };
    order.positionId = await broker.placeLimitOrder(request);
    order.status = 'PLACED';
  }
  return orders;
}

export async function cancelUnfilled(orders: LadderOrder[]): Promise<LadderOrder[]> {
  return orders.map((order) => order.status === 'PENDING' || order.status === 'PLACED' ? { ...order, status: 'CANCELLED' as const } : order);
}
