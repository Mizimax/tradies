export type Direction = 'LONG' | 'SHORT';
export type OrderSide = 'buy' | 'sell';
export type OrderType = 'buy_limit' | 'sell_limit' | 'buy' | 'sell';
export type Session = 'asian' | 'london' | 'ny' | 'overlap' | 'off';
export type BrokerMode = 'oanda' | 'mt5';

export interface Env {
  BOT_STATE: KVNamespace;
  BROKER_MODE?: BrokerMode;
  OANDA_API_KEY?: string;
  OANDA_ACCOUNT_ID?: string;
  OANDA_BASE_URL?: string;
  METAAPI_TOKEN?: string;
  MT5_ACCOUNT_ID?: string;
  MT5_SYMBOL?: string;
  SCORE_THRESHOLD?: string;
  HIGH_CONVICTION?: string;
  LOT_PER_100_USD?: string;
  MIN_LOT?: string;
  MAX_LOT?: string;
  MAX_DAILY_LOSS?: string;
  DAILY_TARGET?: string;
  MIN_RR?: string;
  MAX_OPEN_TRADES?: string;
  SESSION_FILTER?: 'all' | 'london_ny' | 'london' | 'ny';
  RSI_PERIOD?: string;
  RSI_LONG_MAX?: string;
  RSI_SHORT_MIN?: string;
  ADX_MIN?: string;
  SL_ATR?: string;
  MAX_HOLD_BARS?: string;
  COOLDOWN_BARS?: string;
  TELEGRAM_BOT_TOKEN?: string;
  TELEGRAM_CHAT_ID?: string;
}

export interface Candle {
  time: string;
  open: number;
  high: number;
  low: number;
  close: number;
  volume: number;
}

export interface AccountInfo {
  balance: number;
  equity: number;
  marginUsed?: number;
  currency?: string;
}

export interface Position {
  id: string;
  symbol: string;
  side: OrderSide;
  volume: number;
  openPrice: number;
  sl?: number;
  tp?: number;
  unrealizedPnL?: number;
}

export interface PlaceOrderRequest {
  symbol: string;
  type: OrderType;
  price?: number;
  volume: number;
  sl: number;
  tp: number;
  comment: string;
}

export interface BrokerClient {
  getCandles(symbol: string, timeframe: string, count: number): Promise<Candle[]>;
  placeMarketOrder(symbol: string, side: OrderSide, volume: number, sl: number, tp: number, comment: string): Promise<string>;
  placeLimitOrder(order: PlaceOrderRequest): Promise<string>;
  modifyPosition(positionId: string, sl: number, tp: number): Promise<void>;
  closePosition(positionId: string): Promise<void>;
  closePartial(positionId: string, volume: number): Promise<void>;
  getAccountInfo(): Promise<AccountInfo>;
  getOpenPositions(): Promise<Position[]>;
}

export interface MultiTFData {
  m5Candles: Candle[];
  m15Candles: Candle[];
  h1Candles: Candle[];
  h4Candles: Candle[];
  session: Session;
  now: Date;
}

export interface IndicatorResult {
  name: string;
  pass: boolean;
  direction: Direction | null;
  score: number;
  reason?: string;
  values?: Record<string, number | boolean | string | null>;
}
