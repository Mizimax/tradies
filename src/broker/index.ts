import type { BrokerClient, Env } from './types';
import { MetaApiClient } from './metaapi';
import { OandaClient } from './oanda';

export const SYMBOL_MAP = {
  oanda: 'XAU_USD',
  mt5: 'XAUUSD'
} as const;

export const TF_MAP = {
  oanda: { m5: 'M5', m15: 'M15', h1: 'H1', h4: 'H4' },
  mt5: { m5: '5m', m15: '15m', h1: '1h', h4: '4h' }
} as const;

export function createBrokerClient(env: Env): BrokerClient {
  return env.BROKER_MODE === 'mt5'
    ? new MetaApiClient(env.METAAPI_TOKEN ?? '', env.MT5_ACCOUNT_ID ?? '')
    : new OandaClient(env.OANDA_API_KEY ?? '', env.OANDA_ACCOUNT_ID ?? '', env.OANDA_BASE_URL);
}

export function brokerSymbol(env: Env): string {
  return env.BROKER_MODE === 'mt5' ? env.MT5_SYMBOL ?? SYMBOL_MAP.mt5 : SYMBOL_MAP.oanda;
}
