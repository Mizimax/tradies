# 🥇 Gold (XAU/USD) Autonomous Trading Bot — Claude Code Execution Plan v2
> **Strategy**: Smart Money Concepts (SMC) + 7-Indicator Confluence Engine
> **Broker**: OANDA (dev/backtest) → MT5 via MetaApi (production)
> **Deploy**: Cloudflare Workers (serverless, cron-triggered)
> **Target**: 5%+ per day | Min 1 order/day | 3 SMC gates + 5 indicator gates = 8 total checks

---

## 📐 Full System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                  CLOUDFLARE WORKER (Serverless)                   │
│                                                                    │
│  ┌─────────────┐    ┌──────────────────────────────────────────┐  │
│  │ Cron Trigger│    │           SIGNAL ENGINE                  │  │
│  │  */15 * * * │───▶│                                          │  │
│  └─────────────┘    │  ┌────────────┐   ┌────────────────────┐ │  │
│                     │  │ SMC Engine │   │ Indicator Confluence│ │  │
│  ┌─────────────┐    │  │ (3 gates)  │   │    Engine (5 gates) │ │  │
│  │ HTTP Routes │    │  └─────┬──────┘   └────────┬───────────┘ │  │
│  │/status      │    │        │                   │             │  │
│  │/trades      │    │        ▼                   ▼             │  │
│  │/trigger     │    │  ┌─────────────────────────────────────┐ │  │
│  └─────────────┘    │  │     VALIDATION GATE (8/8 required)  │ │  │
│                     │  │   Score 0-100 → Trade only if ≥ 75  │ │  │
│                     │  └──────────────────┬──────────────────┘ │  │
│                     └─────────────────────┼──────────────────┘  │
│                                           │                       │
│  ┌────────────────────────────────────────▼─────────────────┐    │
│  │              EXECUTION LAYER                              │    │
│  │  RiskManager → OrderManager → MT5 via MetaApi REST/WS    │    │
│  └───────────────────────────────────────────────────────────┘    │
│                                                                    │
│  ┌────────────────┐   ┌──────────────────────────────────────┐    │
│  │  Cloudflare KV │   │     Telegram Alert System            │    │
│  │  (State/Logs)  │   │  (signal, entry, TP hit, daily P&L)  │    │
│  └────────────────┘   └──────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
         ▲ price data (candles)                ▼ orders
   ┌─────────────────────────────────────────────────────┐
   │       BROKER LAYER (env-configurable)               │
   │                                                     │
   │   DEV/BACKTEST          PRODUCTION                  │
   │   ─────────────         ─────────────               │
   │   OANDA REST API  ───▶  MetaApi Cloud               │
   │   (practice acct)       + MT5 Terminal              │
   │   Python SDK            JS/TS SDK                   │
   │                         (any MT5 broker)            │
   └─────────────────────────────────────────────────────┘
```

---

## 🔌 Broker Layer: OANDA (Dev) → MT5 via MetaApi (Prod)

### Why this split?

| Layer | OANDA | MT5 via MetaApi |
|---|---|---|
| **Role** | Backtesting + paper trading | Live production |
| **Access** | Direct REST, easy Python | MetaApi cloud REST/WS |
| **Spreads** | Fixed, API-friendly | Real broker spreads |
| **Cost** | Free practice account | MetaApi ~$25-50/mo |
| **Deployment** | Python local / CI | Cloudflare Worker |
| **Why use it** | No cost, fast iteration | Works with any MT5 broker |

### MT5 Connection via MetaApi (Cloudflare-compatible)

MetaApi is the **bridge layer** — it runs a real MT5 terminal in the cloud connected to your broker, and exposes a REST + WebSocket API that works perfectly from Cloudflare Workers (no Windows dependency).

```
Your Cloudflare Worker
        │
        │  HTTPS REST / WebSocket
        ▼
  MetaApi Cloud ──── MT5 Terminal (hosted) ──── Your MT5 Broker
  (metaapi.cloud)     (any MT5 broker)          (XM, IC Markets,
                                                 Pepperstone, etc.)
```

```typescript
// src/broker/metaapi.ts — Production MT5 client
import MetaApi from 'metaapi.cloud-sdk';

export class MT5Client {
  private api: MetaApi;
  private connection: any;

  async connect(env: Env) {
    this.api = new MetaApi(env.METAAPI_TOKEN);
    const account = await this.api.metatraderAccountApi
      .getAccount(env.MT5_ACCOUNT_ID);
    this.connection = await account.connect();
    await this.connection.waitSynchronized();
  }

  async getCandles(symbol: string, tf: string, count: number) {
    // Returns OHLCV array compatible with SMC engine
    return await this.connection
      .getHistoricalCandles(symbol, tf, new Date(), count);
  }

  async placeMarketOrder(symbol: string, type: 'buy'|'sell',
    volume: number, sl: number, tp: number, comment: string) {
    return await this.connection.createMarketBuyOrder(  // or Sell
      symbol, volume, sl, tp, { comment }
    );
  }

  async modifyPosition(positionId: string, sl: number, tp: number) {
    return await this.connection.modifyPosition(positionId, sl, tp);
  }

  async closePosition(positionId: string) {
    return await this.connection.closePosition(positionId);
  }

  async getAccountInfo() {
    return await this.connection.getAccountInformation();
  }

  async getOpenPositions() {
    return await this.connection.getPositions();
  }
}
```

```typescript
// src/broker/oanda.ts — Dev/Backtest client (same interface)
export class OandaClient {
  // Identical method signatures as MT5Client
  // Swapped out via env variable: BROKER_MODE=oanda|mt5
  async getCandles(symbol, tf, count) { ... }
  async placeMarketOrder(...) { ... }
  // etc.
}
```

```typescript
// src/broker/index.ts — Broker factory (env-driven swap)
export function createBrokerClient(env: Env) {
  return env.BROKER_MODE === 'mt5'
    ? new MT5Client(env)
    : new OandaClient(env);
}
// Set BROKER_MODE=oanda for dev, mt5 for prod
// MT5 secrets set manually in Cloudflare dashboard later
```

### MT5 Symbol Mapping

```typescript
const SYMBOL_MAP = {
  oanda: 'XAU_USD',
  mt5: 'XAUUSD',  // or 'GOLD' depending on broker
};
// Timeframe map
const TF_MAP = {
  oanda: { '15m': 'M15', '1h': 'H1', '4h': 'H4' },
  mt5:   { '15m': 'PERIOD_M15', '1h': 'PERIOD_H1', '4h': 'PERIOD_H4' },
};
```

---

## 🧠 SMC Core: The 3 Structural Gates

These must ALL pass before indicators are even checked.

### Gate 1 — 4H Bias Engine
```
✓ 4H market structure defined (sequence of HH/HL or LH/LL)
✓ Price at discount zone for BUY (<50% of last range)
  OR premium zone for SELL (>50% of last range)
✓ Unmitigated 4H Order Block OR 4H Fair Value Gap present
  in direction of bias
→ Score: +12.5 pts
```

### Gate 2 — 1H Confirmation
```
✓ 1H structure aligns with 4H bias (BOS or CHoCH confirmed)
✓ Liquidity sweep has occurred at key 1H level
  (equal highs/lows, PDH/PDL, session boundary)
✓ Displacement candle visible post-sweep
  (strong bodied candle, closes beyond structure)
→ Score: +12.5 pts
```

### Gate 3 — 15M Entry Trigger
```
✓ Price pulled back INTO 15M FVG or 15M Order Block
✓ 15M CHoCH confirms reversal in entry direction
✓ NOT within 30min of high-impact news event
→ Score: +12.5 pts
```

**SMC gates max: 37.5 pts. All 3 must pass (no partial credit).**

---

## 📊 Indicator Confluence Engine: 5 Additional Gates

These run IN PARALLEL with SMC and add to a weighted score.
Each indicator is chosen for a **different purpose** — no overlapping signals.

```
┌─────────────────────────────────────────────────────────┐
│         INDICATOR LAYER (5 gates = 62.5 pts max)        │
│                                                         │
│  IND-1: EMA Stack      → TREND direction         12.5  │
│  IND-2: RSI Divergence → MOMENTUM + exhaustion   12.5  │
│  IND-3: VWAP Position  → INSTITUTIONAL fair value 12.5 │
│  IND-4: ATR Regime     → VOLATILITY filter        12.5 │
│  IND-5: ADX Strength   → TREND strength filter   12.5  │
│                                                   ─────  │
│         Total possible:                          62.5   │
└─────────────────────────────────────────────────────────┘
```

---

### IND-1: EMA Stack (Trend Alignment) — 12.5 pts

**Why**: EMAs reveal the trend hierarchy. When EMA-21 > EMA-50 > EMA-200, institutional money is accumulated on the long side. This aligns the bot with the dominant flow.

```
EMAs calculated on 1H candles:
  - EMA-21   (short-term momentum)
  - EMA-50   (mid-term trend)
  - EMA-200  (institutional trend baseline)

BULLISH STACK: price > EMA-21 > EMA-50 > EMA-200  → +12.5 pts
BEARISH STACK: price < EMA-21 < EMA-50 < EMA-200  → +12.5 pts
MIXED:  any out-of-order configuration             → 0 pts (skip trade)

Bonus check: Is price currently pulling BACK to EMA-21?
  → Confirms this is a pullback entry, not chasing price
```

```typescript
function checkEMAStack(candles: Candle[]): IndicatorResult {
  const ema21  = calcEMA(candles, 21);
  const ema50  = calcEMA(candles, 50);
  const ema200 = calcEMA(candles, 200);
  const price  = candles.at(-1).close;

  const bullStack = price > ema21 && ema21 > ema50 && ema50 > ema200;
  const bearStack = price < ema21 && ema21 < ema50 && ema50 < ema200;

  const pullbackToBias = bullStack
    ? price <= ema21 * 1.002  // within 0.2% of EMA-21
    : bearStack
      ? price >= ema21 * 0.998
      : false;

  return {
    pass: bullStack || bearStack,
    direction: bullStack ? 'LONG' : bearStack ? 'SHORT' : null,
    pullbackConfirmed: pullbackToBias,
    score: (bullStack || bearStack) ? 12.5 : 0,
  };
}
```

---

### IND-2: RSI Divergence + Zone Filter (Momentum) — 12.5 pts

**Why**: RSI divergence is one of the most powerful leading signals. When price makes a new low but RSI makes a higher low (bullish divergence), smart money is quietly accumulating — the exact condition that precedes SMC reversals.

```
RSI (14) on 15M chart:

BULLISH conditions (any 2 of 3 = pass):
  ① RSI crosses above 30 from oversold (recovery signal)
  ② Bullish divergence: price LL, RSI HL in last 20 bars
  ③ RSI is between 40-60 (pullback zone, not exhausted)

BEARISH conditions (any 2 of 3 = pass):
  ① RSI crosses below 70 from overbought
  ② Bearish divergence: price HH, RSI LH in last 20 bars
  ③ RSI is between 40-60 (pullback zone)

BLOCKED conditions (hard filter, 0 pts):
  → RSI > 80 for LONG (extreme overbought — don't buy)
  → RSI < 20 for SHORT (extreme oversold — don't sell)
```

```typescript
function checkRSI(candles: Candle[]): IndicatorResult {
  const rsi = calcRSI(candles, 14);
  const latest = rsi.at(-1);
  const prev   = rsi.at(-2);

  // Hard block
  if (latest > 80 || latest < 20) return { pass: false, score: 0 };

  const crossedAbove30 = prev < 30 && latest >= 30;
  const crossedBelow70 = prev > 70 && latest <= 70;
  const inPullbackZone = latest >= 40 && latest <= 60;
  const bullDiv = detectDivergence(candles, rsi, 'bullish', 20);
  const bearDiv = detectDivergence(candles, rsi, 'bearish', 20);

  const bullScore = [crossedAbove30, bullDiv, inPullbackZone]
    .filter(Boolean).length;
  const bearScore = [crossedBelow70, bearDiv, inPullbackZone]
    .filter(Boolean).length;

  return {
    pass: bullScore >= 2 || bearScore >= 2,
    direction: bullScore >= bearScore ? 'LONG' : 'SHORT',
    score: (bullScore >= 2 || bearScore >= 2) ? 12.5 : 0,
  };
}
```

---

### IND-3: VWAP Position (Institutional Fair Value) — 12.5 pts

**Why**: VWAP is used by every institutional desk to measure intraday value. Price below VWAP = discount; above = premium. For Gold specifically, combining VWAP with SMC zones creates high-precision entries that align with institutional order flow.

```
VWAP calculated intraday (resets at 00:00 UTC)
VWAP Bands = ± 1.0 × VWAP_StdDev (like Bollinger)

LONG setup:
  ① Price is below VWAP (discount) → pullback into value
  ② Price is approaching VWAP lower band (support zone)
  ③ Bias is bullish (confirmed by Gate 1)
  → Score: +12.5 pts

SHORT setup:
  ① Price is above VWAP (premium)
  ② Price approaching VWAP upper band (resistance zone)
  ③ Bias is bearish
  → Score: +12.5 pts

BONUS: Anchored VWAP from last swing high/low also calculated
  → If anchored VWAP aligns with session VWAP: +confidence bonus
```

```typescript
function checkVWAP(candles: Candle[]): IndicatorResult {
  const { vwap, upperBand, lowerBand } = calcVWAP(candles);
  const price = candles.at(-1).close;

  const nearLowerBand = price <= lowerBand * 1.001;
  const nearUpperBand = price >= upperBand * 0.999;
  const belowVWAP     = price < vwap;
  const aboveVWAP     = price > vwap;

  const longSetup  = belowVWAP && nearLowerBand;
  const shortSetup = aboveVWAP && nearUpperBand;

  return {
    pass: longSetup || shortSetup,
    direction: longSetup ? 'LONG' : shortSetup ? 'SHORT' : null,
    score: (longSetup || shortSetup) ? 12.5 : 0,
    vwap, upperBand, lowerBand,
  };
}
```

---

### IND-4: ATR Volatility Regime Filter — 12.5 pts

**Why**: ATR filters out two deadly scenarios: (1) dead markets where spreads eat your edge, and (2) extreme volatility spikes (news events) where price is erratic. Gold needs ATR in the "sweet spot" to form clean SMC patterns.

```
ATR (14) on 1H candles

Minimum ATR: $3.00 (Gold must be moving — avoid dead sessions)
Maximum ATR: $25.00 (avoid news spikes / extreme volatility)

ATR Trend check:
  - Current ATR > ATR 5 bars ago = expanding volatility = GOOD
  - Current ATR < ATR 5 bars ago = contracting = CAUTION

Session ATR Multiplier:
  - Asian session:  ATR min drops to $1.50 (less activity expected)
  - London/NY:      Full ATR range applies

Stop Loss sizing rule from ATR:
  - SL must be ≥ 1.0 × ATR (no tighter — will be stopped out)
  - SL must be ≤ 2.5 × ATR (no wider — destroys R:R)
  → Calculated here, passed to RiskManager
```

```typescript
function checkATR(candles: Candle[], session: Session): IndicatorResult {
  const atrValues = calcATR(candles, 14);
  const atr = atrValues.at(-1);
  const prevAtr = atrValues.at(-6);

  const minATR = session === 'asian' ? 1.5 : 3.0;
  const maxATR = 25.0;

  const inRange    = atr >= minATR && atr <= maxATR;
  const expanding  = atr > prevAtr;

  return {
    pass: inRange,
    expanding,
    atr,
    suggestedSL: atr * 1.5,      // 1.5× ATR for SL
    suggestedTP: atr * 1.5 * 2,  // 2× SL for TP1
    score: inRange ? 12.5 : 0,
  };
}
```

---

### IND-5: ADX Trend Strength Filter — 12.5 pts

**Why**: ADX measures the STRENGTH of a trend, not its direction. The biggest SMC trap is trading "breakouts" in a ranging, choppy market. ADX > 20 confirms there's genuine institutional momentum behind the move.

```
ADX (14) with +DI / -DI on 1H candles

TRENDING MARKET (take trades):
  ① ADX > 20: trend is present and strong
  ② ADX > 25: strong trend → high conviction entries
  ③ ADX rising: trend is accelerating (best entries)

DIRECTIONAL FILTER:
  → LONG: +DI > -DI (buyers dominating)
  → SHORT: -DI > +DI (sellers dominating)

RANGING FILTER (no trade):
  → ADX < 15: market is choppy — SMC patterns unreliable
  → ADX < 20 AND ADX falling: momentum fading

SCORE:
  ADX > 25 with correct DI cross: 12.5 pts (full)
  ADX 20-25 with correct DI:      8.0 pts (partial — still trade)
  ADX < 20:                        0 pts (skip trade)
```

```typescript
function checkADX(candles: Candle[]): IndicatorResult {
  const { adx, plusDI, minusDI } = calcADX(candles, 14);
  const latest = adx.at(-1);
  const prev   = adx.at(-3);

  const rising = latest > prev;
  const bullDI = plusDI.at(-1) > minusDI.at(-1);
  const bearDI = minusDI.at(-1) > plusDI.at(-1);

  let score = 0;
  if (latest >= 25)                     score = 12.5;
  else if (latest >= 20)                score = 8.0;

  return {
    pass: latest >= 20,
    direction: bullDI ? 'LONG' : 'SHORT',
    score,
    adx: latest,
    rising,
  };
}
```

---

## 🎯 Master Validation Gate (Score System)

```typescript
// src/validation/validator.ts

interface MasterValidation {
  totalScore: number;         // 0–100
  smc: {
    gate1_4H: boolean;        // structural bias
    gate2_1H: boolean;        // confirmation + sweep
    gate3_15M: boolean;       // entry trigger
    allPass: boolean;
  };
  indicators: {
    ema: IndicatorResult;     // 12.5 pts
    rsi: IndicatorResult;     // 12.5 pts
    vwap: IndicatorResult;    // 12.5 pts
    atr: IndicatorResult;     // 12.5 pts
    adx: IndicatorResult;     // 12.5 pts
  };
  verdict: 'TRADE' | 'SKIP';
  direction: 'LONG' | 'SHORT' | null;
  entryZone: { top: number; bottom: number };
  stopLoss: number;
  takeProfits: [number, number, number];  // TP1, TP2, TP3
  confidence: number;
}

function validate(data: MultiTFData): MasterValidation {
  // Step 1: SMC gates (all 3 required — binary hard filter)
  const smcGates = runSMCGates(data);
  if (!smcGates.allPass) return { verdict: 'SKIP', ...smcGates };

  // Step 2: Score = SMC (37.5 fixed) + Indicators (variable)
  const smcScore = 37.5;  // all 3 gates passed
  const ema  = checkEMAStack(data.h1Candles);
  const rsi  = checkRSI(data.m15Candles);
  const vwap = checkVWAP(data.m15Candles);
  const atr  = checkATR(data.h1Candles, data.session);
  const adx  = checkADX(data.h1Candles);

  // Direction consistency check — all passing indicators
  // must agree on direction
  const directions = [ema, rsi, vwap, adx]
    .filter(i => i.pass && i.direction)
    .map(i => i.direction);
  const consistent = new Set(directions).size === 1;
  if (!consistent) return { verdict: 'SKIP', reason: 'DIRECTION_CONFLICT' };

  const indicatorScore = ema.score + rsi.score + vwap.score
                       + atr.score + adx.score;
  const totalScore = smcScore + indicatorScore;

  // Require minimum 75/100 to trade
  // This means: all 3 SMC gates (37.5) + at least 3 indicators (37.5)
  const verdict = totalScore >= 75 ? 'TRADE' : 'SKIP';

  // SL/TP from ATR result + SMC zone
  const { stopLoss, takeProfits, entryZone } = calcExecutionLevels(
    data, smcGates, atr
  );

  return {
    totalScore,
    smc: smcGates,
    indicators: { ema, rsi, vwap, atr, adx },
    verdict,
    direction: smcGates.direction,
    entryZone,
    stopLoss,
    takeProfits,
    confidence: totalScore,
  };
}
```

### Score Thresholds

| Score | Action | Meaning |
|---|---|---|
| `< 37.5` | **HARD SKIP** | SMC gates didn't all pass |
| `37.5–74` | **SKIP** | SMC passed but indicators weak |
| `75–87` | **TRADE** (normal size) | All SMC + 3 indicators agree |
| `88–100` | **TRADE** (1.5× size) | All SMC + all 5 indicators agree |

---

## 📁 Updated Project Structure

```
gold-trading-bot/
├── wrangler.toml
├── package.json                     # metaapi.cloud-sdk, typescript
│
├── src/
│   ├── index.ts                     # CF Worker entry
│   ├── scheduler.ts                 # Main bot orchestrator
│   │
│   ├── broker/
│   │   ├── index.ts                 # Factory: createBrokerClient(env)
│   │   ├── oanda.ts                 # OANDA REST (dev/backtest)
│   │   ├── metaapi.ts               # MT5 via MetaApi (production)
│   │   └── types.ts                 # Shared: Candle, Order, Position
│   │
│   ├── analysis/
│   │   ├── marketStructure.ts       # Swing H/L, BOS, CHoCH
│   │   ├── orderBlocks.ts           # OB detection + mitigation check
│   │   ├── fairValueGap.ts          # FVG + mitigation
│   │   ├── liquiditySweep.ts        # Stop hunt detection
│   │   └── sessionLevels.ts         # PDH/PDL, Asian range
│   │
│   ├── indicators/
│   │   ├── ema.ts                   # EMA-21/50/200 stack
│   │   ├── rsi.ts                   # RSI(14) + divergence
│   │   ├── vwap.ts                  # Session VWAP + bands
│   │   ├── atr.ts                   # ATR(14) + regime filter
│   │   ├── adx.ts                   # ADX(14) + DI lines
│   │   └── math.ts                  # Shared: EMA/RMA calc helpers
│   │
│   ├── validation/
│   │   ├── validator.ts             # Master 8-gate validator
│   │   ├── smcGates.ts              # Gates 1-3 (structural)
│   │   └── indicatorGates.ts        # Gates 4-8 (indicators)
│   │
│   ├── execution/
│   │   ├── pullbackZone.ts          # FVG+OB+EMA21 overlap zone builder
│   ├── pullbackConfirm.ts       # Candle+RSI+5M CHoCH confirmation
│   ├── orderLadder.ts           # 3-split limit order builder
│   ├── tradeManager.ts          # Signal lifecycle state machine
│   ├── orderManager.ts          # Place, modify, close orders
│   │   ├── riskManager.ts           # Size, SL, TP, drawdown limits
│   │   └── tradeJournal.ts          # KV-based trade log
│   │
│   └── utils/
│       ├── newsFilter.ts            # Economic calendar blocklist
│       ├── telegram.ts              # Alert notifications
│       └── session.ts               # Detect current session
│
├── backtesting/                     # Python — run locally first
│   ├── fetch_data.py                # OANDA historical data download
│   ├── smc_engine.py                # SMC logic mirror (Python)
│   ├── indicators.py                # All 5 indicators in Python
│   ├── validator.py                 # 8-gate validator in Python
│   ├── run_backtest.py              # Bar-by-bar simulation
│   ├── metrics.py                   # Stats: winrate, PF, drawdown
│   ├── optimizer.py                 # Parameter sweep
│   └── results/
│       ├── backtest_YYYYMM.json
│       └── optimization_grid.csv
│
└── tests/
    ├── unit/
    │   ├── smc.test.ts
    │   └── indicators.test.ts
    └── integration/
        └── signal.test.ts
```

---

## 🔑 Environment Variables

```bash
# ──── BROKER MODE ────────────────────────────────────────
BROKER_MODE=oanda          # "oanda" for dev, "mt5" for prod

# ──── OANDA (Dev / Backtest) ─────────────────────────────
OANDA_API_KEY=             # Set when developing locally
OANDA_ACCOUNT_ID=          # Practice account ID
OANDA_BASE_URL=https://api-fxpractice.oanda.com

# ──── MT5 via MetaApi (Production) ───────────────────────
# Set manually in Cloudflare dashboard → Workers → Settings → Secrets
METAAPI_TOKEN=             # MetaApi cloud API token
MT5_ACCOUNT_ID=            # MetaApi account ID (linked to your broker)
MT5_SYMBOL=XAUUSD          # Or GOLD depending on broker naming

# ──── RISK PARAMETERS ────────────────────────────────────
# Lot sizing: $100 equity = 0.01 lot (auto-scales with equity)
LOT_PER_100_USD=0.01       # Base ratio — adjust to be more/less aggressive
MIN_LOT=0.01               # Broker minimum
MAX_LOT=5.00               # Hard cap on any single signal
MAX_DAILY_LOSS=0.03        # Stop at -3% equity drawdown per day
DAILY_TARGET=0.05          # Stop new entries at +5% equity per day
MIN_RR=2.0                 # Minimum 1:2 R:R
MAX_OPEN_TRADES=2

# ──── SIGNAL THRESHOLDS ──────────────────────────────────
SCORE_THRESHOLD=75         # Min score to trade (0-100)
HIGH_CONVICTION=88         # Score for 1.5× position size

# ──── NOTIFICATIONS ──────────────────────────────────────
TELEGRAM_BOT_TOKEN=        # Optional
TELEGRAM_CHAT_ID=          # Optional

# ──── SESSION FILTER ─────────────────────────────────────
SESSION_FILTER=london_ny   # "all" | "london_ny" | "london" | "ny"
```

```toml
# wrangler.toml
name = "gold-trading-bot"
main = "src/index.ts"
compatibility_date = "2025-01-01"
node_compat = true           # Required for MetaApi SDK

[triggers]
crons = ["*/15 * * * *"]     # Every 15 minutes

[[kv_namespaces]]
binding = "BOT_STATE"
id = "YOUR_KV_NAMESPACE_ID"

# Non-secret vars (secrets go in dashboard)
[vars]
BROKER_MODE = "oanda"
SESSION_FILTER = "london_ny"
SCORE_THRESHOLD = "75"
```

---

## 📦 Dynamic Lot Sizing (Equity-Proportional)

The base rule: **$100 equity = 0.01 lot**. Lot size scales linearly with account equity and is recalculated live before every signal. No manual adjustments ever needed.

```
Equity:   $100  →  0.01 lot  (1 micro lot)
Equity:   $500  →  0.05 lots
Equity:  $1000  →  0.10 lots
Equity:  $5000  →  0.50 lots
Equity: $10000  →  1.00 lot
```

```typescript
// src/execution/riskManager.ts

const LOT_PER_100_USD = 0.01;    // Base ratio — never change this constant
const MIN_LOT         = 0.01;    // Broker minimum (1 micro lot)
const MAX_LOT         = 5.00;    // Hard cap — prevents runaway sizing
const LOT_STEP        = 0.01;    // MT5 lot precision (round to nearest)

/**
 * Core lot sizing formula:
 *   totalLot = (equity / 100) × 0.01
 *
 * Then split 33/33/34 across the 3 ladder orders.
 * High-conviction trades (score ≥ 88) get 1.5× multiplier.
 */
function calcLotSize(
  equity: number,
  score: number,
  splitIndex: 0 | 1 | 2   // which ladder order: A=0, B=1, C=2
): number {
  // Step 1: Raw total lot for this equity
  const rawTotal = (equity / 100) * LOT_PER_100_USD;

  // Step 2: High-conviction multiplier (score ≥ 88 → 1.5×)
  const multiplier = score >= 88 ? 1.5 : 1.0;
  const adjustedTotal = rawTotal * multiplier;

  // Step 3: Per-order split weight (33% / 33% / 34%)
  const splitWeights = [0.33, 0.33, 0.34];
  const orderLot = adjustedTotal * splitWeights[splitIndex];

  // Step 4: Clamp to broker limits and round to lot step
  const clamped = Math.min(Math.max(orderLot, MIN_LOT), MAX_LOT);
  return Math.round(clamped / LOT_STEP) * LOT_STEP;
}

// Full lot table at runtime (logged to Telegram on each signal):
function lotSummary(equity: number, score: number) {
  return {
    equity,
    baseLot:    calcLotSize(equity, score, 0) +
                calcLotSize(equity, score, 1) +
                calcLotSize(equity, score, 2),
    orderA:     calcLotSize(equity, score, 0),
    orderB:     calcLotSize(equity, score, 1),
    orderC:     calcLotSize(equity, score, 2),
    multiplier: score >= 88 ? '1.5× (high conviction)' : '1.0×',
  };
}
```

### Live Sizing Examples

| Equity | Score | Order A | Order B | Order C | Total |
|---|---|---|---|---|---|
| $100 | 75 | 0.01 | 0.01 | 0.01 | **0.03** |
| $100 | 88+ | 0.01 | 0.01 | 0.01 | **0.03** *(min floor)* |
| $500 | 75 | 0.02 | 0.02 | 0.02 | **0.05** |
| $1,000 | 75 | 0.03 | 0.03 | 0.04 | **0.10** |
| $1,000 | 88+ | 0.05 | 0.05 | 0.05 | **0.15** |
| $5,000 | 75 | 0.17 | 0.17 | 0.17 | **0.50** |
| $5,000 | 88+ | 0.25 | 0.25 | 0.25 | **0.75** |
| $10,000 | 75 | 0.33 | 0.33 | 0.34 | **1.00** |
| $10,000 | 88+ | 0.50 | 0.50 | 0.50 | **1.50** |

> **Note on min floor**: At $100 equity and small accounts, every order rounds up to the 0.01 minimum. That's fine — the lot step clamp prevents sub-minimum orders being rejected by the broker.

### Equity Fetched Live Before Every Signal

```typescript
// src/scheduler.ts — called at the start of every cron tick

async function run(env: Env) {
  const broker  = createBrokerClient(env);
  const account = await broker.getAccountInfo();

  // Always use EQUITY (not balance) — accounts for floating P&L
  const equity  = account.equity;

  // Pass equity into validation + lot sizing
  const signal  = await runValidation(candles, env);
  if (signal.verdict === 'TRADE') {
    const orders = buildOrderLadder(
      signal.zone,
      signal.direction,
      signal.stopLoss,
      equity,        // ← live equity injected here
      signal.score,
      signal.htfTargets
    );
    await placeLadder(orders, broker, env);
  }
}
```

### Drawdown Auto-Reduce

If the account takes a drawdown, lot sizes shrink automatically because equity shrinks — no extra code needed. This is the natural compounding property of equity-based sizing.

```
Start:   $1,000 equity → 0.10 lot total
Drawdown:  $800 equity → 0.08 lot total  (auto-reduced)
Recovery: $1,100 equity → 0.11 lot total (auto-scaled up)
```

### Updated `buildOrderLadder` Signature

```typescript
// orderLadder.ts — updated to accept equity + score instead of hardcoded volume

function buildOrderLadder(
  zone: EntryZone,
  direction: 'LONG' | 'SHORT',
  sl: number,
  equity: number,          // ← from live account
  score: number,           // ← for high-conviction multiplier
  htfTargets: number[]
): LadderOrder[] {
  return [0, 1, 2].map((i) => {
    const volume = calcLotSize(equity, score, i as 0|1|2);
    const entryPrice = getEntryPrice(zone, direction, i);
    const slDist = Math.abs(entryPrice - sl);
    // ... build order as before
  });
}
```

---

## 📊 Python Backtesting Pipeline

### Minimum pass criteria before any live trading:

```python
PASS_CRITERIA = {
    'win_rate':        0.55,    # ≥55%
    'profit_factor':   1.80,    # ≥1.8
    'max_drawdown':    0.15,    # ≤15%
    'avg_rr':          2.0,     # ≥2:1
    'avg_trades_day':  1.0,     # ≥1 per day
    'min_test_months': 3,       # tested on 3+ months
    'min_trades':      80,      # enough statistical confidence
}
```

### Optimization Parameters to Sweep

```python
PARAM_GRID = {
    'swing_length':        [2, 3, 4, 5],
    'ob_lookback':         [3, 5, 7, 10],
    'fvg_min_size_pct':    [0.05, 0.10, 0.20],
    'ema_periods':         [(21,50,200), (20,50,100)],
    'rsi_period':          [14, 21],
    'rsi_divergence_bars': [15, 20, 25],
    'adx_min':             [18, 20, 25],
    'atr_period':          [14],
    'score_threshold':     [70, 75, 80],
    'session_filter':      ['all', 'london_ny'],
}
# Use scipy or optuna for intelligent search vs brute-force grid
```

---

## 🎯 Pullback Detection + Multi-Order Entry Engine

After all 8 gates pass, the bot enters a **PENDING state** — it does NOT fire immediately.
It watches for price to pull back into the optimal zone, then ladders in with up to 3 split orders.

```
8 Gates Pass
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│              PULLBACK WATCH STATE                           │
│                                                             │
│  Bot saves signal to KV:                                    │
│  { direction, entryZone, sl, tps, expiry, orders: [] }      │
│                                                             │
│  Every 15min cron tick → checks if price is in zone         │
│  Signal expires after: MAX_WAIT = 4H (configurable)         │
└───────────────────────────┬─────────────────────────────────┘
                            │
          ┌─────────────────┴──────────────────┐
          │                                    │
          ▼                                    ▼
  Price enters zone                    Expiry reached
  → Start order ladder                 → Cancel signal, log MISS
          │
          ▼
┌─────────────────────────────────────────────────────────────┐
│              3-ORDER LADDER EXECUTION                       │
│                                                             │
│  Order A  →  Entry at zone TOP     (33% of total size)      │
│  Order B  →  Entry at zone MID     (33% of total size)      │
│  Order C  →  Entry at zone BOTTOM  (34% of total size)      │
│                                                             │
│  Each order has SAME SL, but DIFFERENT TPs                  │
│  Unfilled orders auto-cancel if price breaks SL level        │
└─────────────────────────────────────────────────────────────┘
```

---

### Pullback Zone Definition

The entry zone is built from **3 confluent layers** found during SMC analysis. The bot uses whichever layer is most precise (narrowest overlap):

```
LAYER 1 — 15M FVG
  Bullish: zone = [FVG bottom, FVG top]
  → Price must retrace INTO this gap before entry

LAYER 2 — 15M / 1H Order Block
  zone = [OB low, OB high]  (last bearish candle before bullish BOS)
  → High-probability bounce zone

LAYER 3 — EMA-21 Proximity (from IND-1)
  zone = [EMA21 × 0.998, EMA21 × 1.002]
  → Dynamic support for pullback entries

FINAL ZONE = intersection of all present layers
  → If all 3 overlap: tight high-conviction zone
  → If only 2 overlap: wider zone, use ATR to set min size
  → If no overlap: do NOT enter (zone conflict = skip)
```

```typescript
// src/execution/pullbackZone.ts

interface EntryZone {
  top: number;
  bottom: number;
  midpoint: number;
  quarterPoint: number;   // 25% from bottom (deep pullback)
  source: ('FVG' | 'OB' | 'EMA21')[];
  confidence: 'HIGH' | 'MEDIUM';  // HIGH = all 3 overlap
}

function buildEntryZone(
  fvg: FVGResult | null,
  ob: OrderBlockResult | null,
  ema21: number,
  direction: 'LONG' | 'SHORT',
  atr: number
): EntryZone | null {

  const zones: [number, number][] = [];
  const sources: EntryZone['source'] = [];

  if (fvg) {
    zones.push([fvg.bottom, fvg.top]);
    sources.push('FVG');
  }
  if (ob) {
    zones.push([ob.low, ob.high]);
    sources.push('OB');
  }

  // EMA21 zone: ±0.2% band around EMA
  const emaZone: [number, number] = [ema21 * 0.998, ema21 * 1.002];
  zones.push(emaZone);
  sources.push('EMA21');

  // Find overlap of all zones
  const overlapTop = Math.min(...zones.map(z => z[1]));
  const overlapBot = Math.max(...zones.map(z => z[0]));

  if (overlapBot >= overlapTop) {
    // No overlap — zones are spread apart
    // Fall back: use widest zone if ≤ 1.5× ATR wide
    const widest = zones.reduce((a, b) =>
      (b[1] - b[0]) > (a[1] - a[0]) ? b : a);
    if (widest[1] - widest[0] > atr * 1.5) return null; // too wide
    return buildZoneObject(widest[0], widest[1], sources, 'MEDIUM');
  }

  return buildZoneObject(overlapBot, overlapTop, sources, 'HIGH');
}

function buildZoneObject(
  bottom: number, top: number,
  source: EntryZone['source'],
  confidence: EntryZone['confidence']
): EntryZone {
  const range = top - bottom;
  return {
    top, bottom,
    midpoint:     bottom + range * 0.5,
    quarterPoint: bottom + range * 0.25,
    source,
    confidence,
  };
}
```

---

### Pullback Confirmation Signal

Entering the zone is **not enough** — the bot also needs a micro-confirmation that price is reversing INSIDE the zone (not falling through it):

```
PULLBACK CONFIRMATION CHECKLIST (need 2 of 3):

  ✓ CANDLE PATTERN: Bullish engulfing / pin bar / hammer
    inside the zone on the 15M chart
    (shows rejection at the zone)

  ✓ MOMENTUM SHIFT: RSI crosses back above 40 (for longs)
    from below, while price is in zone

  ✓ MICRO CHoCH: On 5M chart, a small Change of Character
    confirms buyers stepped in at the zone level

→ If 2/3 present: proceed to order ladder
→ If 0/1 present: wait one more candle, recheck
→ If price exits zone bottom (long) / top (short): cancel signal
```

```typescript
// src/execution/pullbackConfirm.ts

interface PullbackConfirmation {
  confirmed: boolean;
  signals: {
    candlePattern: boolean;   // engulfing/pin/hammer in zone
    rsiShift: boolean;        // RSI crossing back
    microChoCH: boolean;      // 5M structure shift
  };
  checksHit: number;          // 0, 1, 2, or 3
}

function confirmPullback(
  m15Candles: Candle[],
  m5Candles: Candle[],
  zone: EntryZone,
  direction: 'LONG' | 'SHORT',
  rsiValues: number[]
): PullbackConfirmation {

  const lastCandle = m15Candles.at(-1);
  const inZone = lastCandle.low <= zone.top
               && lastCandle.high >= zone.bottom;

  // Check 1: Rejection candle pattern
  const candlePattern = inZone && (
    direction === 'LONG'
      ? isBullishEngulfing(m15Candles) || isPinBar(lastCandle, 'bullish')
      : isBearishEngulfing(m15Candles) || isPinBar(lastCandle, 'bearish')
  );

  // Check 2: RSI momentum shift
  const rsi = rsiValues.at(-1);
  const prevRsi = rsiValues.at(-2);
  const rsiShift = direction === 'LONG'
    ? prevRsi < 40 && rsi >= 40
    : prevRsi > 60 && rsi <= 60;

  // Check 3: 5M CHoCH (micro structure flip)
  const microChoCH = detect5MChoCH(m5Candles, direction);

  const checksHit = [candlePattern, rsiShift, microChoCH]
    .filter(Boolean).length;

  return {
    confirmed: checksHit >= 2,
    signals: { candlePattern, rsiShift, microChoCH },
    checksHit,
  };
}
```

---

### Multi-Order Ladder (3 Split Orders)

Once pullback is confirmed, the bot places **3 limit orders** at different depths inside the zone. This achieves a better average entry than a single order and captures more of the move.

```
BULLISH EXAMPLE (zone = $2,340 – $2,350, SL = $2,330):
──────────────────────────────────────────────────────────

  $2,355 ──────────────────────── (above zone — displacement)
  $2,350 ── ZONE TOP ──────────── Order A placed here (33%)
  $2,345 ── ZONE MID ──────────── Order B placed here (33%)
  $2,340 ── ZONE BOT ──────────── Order C placed here (34%)
  $2,337 ── QUARTER POINT ─────── Extra buffer if needed
  $2,330 ── STOP LOSS ──────────── All orders share same SL

  Take Profits (per order):
  Order A:  TP1=$2,365  TP2=$2,380  TP3=$2,400  (closest entry → smallest TP)
  Order B:  TP1=$2,368  TP2=$2,385  TP3=$2,408  (slightly better entry)
  Order C:  TP1=$2,372  TP2=$2,392  TP3=$2,420  (deepest → biggest reward)

  Average Entry: ~$2,345
  Average TP2:   ~$2,386
  Average R:R:   ~2.6:1 (better than single entry at top of zone)
```

```typescript
// src/execution/orderLadder.ts

interface LadderOrder {
  id: string;           // 'A' | 'B' | 'C'
  limitPrice: number;   // where to place limit
  volume: number;       // lots
  sl: number;
  tp1: number;
  tp2: number;
  tp3: number;
  status: 'PENDING' | 'FILLED' | 'CANCELLED';
  positionId?: string;  // MT5 position ID once filled
}

function buildOrderLadder(
  zone: EntryZone,
  direction: 'LONG' | 'SHORT',
  sl: number,
  totalVolume: number,   // e.g. 0.03 lots total
  htfTargets: number[]   // [tp1, tp2, tp3] from SMC analysis
): LadderOrder[] {

  // Split zone into 3 entry levels
  const entries = direction === 'LONG'
    ? [zone.top, zone.midpoint, zone.bottom]          // fill as price drops
    : [zone.bottom, zone.midpoint, zone.top];          // fill as price rises

  // Volume split: 33% / 33% / 34%
  const splits = [
    Math.round(totalVolume * 0.33 * 100) / 100,
    Math.round(totalVolume * 0.33 * 100) / 100,
    Math.round(totalVolume * 0.34 * 100) / 100,
  ];

  return entries.map((entryPrice, i) => {
    // Each deeper entry gets proportionally larger TP targets
    // because the SL distance from a deeper entry is smaller
    // → R:R improves the deeper you get filled
    const slDistance = Math.abs(entryPrice - sl);
    const tp1 = direction === 'LONG'
      ? entryPrice + slDistance * 1.5
      : entryPrice - slDistance * 1.5;
    const tp2 = htfTargets[1] ?? (direction === 'LONG'
      ? entryPrice + slDistance * 2.5
      : entryPrice - slDistance * 2.5);
    const tp3 = htfTargets[2] ?? (direction === 'LONG'
      ? entryPrice + slDistance * 4.0
      : entryPrice - slDistance * 4.0);

    return {
      id: ['A', 'B', 'C'][i],
      limitPrice: entryPrice,
      volume: splits[i],
      sl,
      tp1, tp2, tp3,
      status: 'PENDING',
    };
  });
}
```

---

### Order Lifecycle State Machine

Each ladder order follows a strict lifecycle managed via KV state:

```
PENDING_SIGNAL
     │
     │ (price enters zone + 2/3 pullback confirms)
     ▼
ORDERS_PLACED  ←─────────────────────────────────────────┐
     │                                                    │
     │ (every 15min cron tick)                            │
     ├── Order A fills → A: ACTIVE                        │
     ├── Order B fills → B: ACTIVE                        │
     ├── Order C fills → C: ACTIVE                        │
     │                                                    │
     │ MANAGEMENT RULES (per position):                   │
     │  • TP1 hit → close 50% of that position            │
     │              move SL to breakeven                  │
     │  • TP2 hit → close remaining 30%                   │
     │              trail SL by 1× ATR                    │
     │  • TP3 hit → close last 20%, log full trade        │
     │  • SL hit  → cancel all PENDING orders for signal  │
     │              log loss, do not re-enter             │
     │                                                    │
     │ EXPIRY: if NOT all filled within MAX_WAIT (4H):    │
     └── Cancel all PENDING orders → state: EXPIRED       │
                                                          │
     If score re-validates on next cron → restart loop ───┘
```

```typescript
// src/execution/tradeManager.ts

async function managePendingSignal(
  signal: PendingSignal,
  currentPrice: number,
  candles: MultiTFCandles,
  env: Env
): Promise<void> {

  // 1. Check expiry
  const age = Date.now() - signal.createdAt;
  if (age > signal.maxWaitMs) {
    await cancelSignal(signal, 'EXPIRED', env);
    return;
  }

  // 2. Price has blown through SL level → cancel everything
  const slBreached = signal.direction === 'LONG'
    ? currentPrice < signal.sl - 1.0  // 1 pip buffer
    : currentPrice > signal.sl + 1.0;
  if (slBreached) {
    await cancelSignal(signal, 'SL_BREACH_BEFORE_FILL', env);
    return;
  }

  // 3. For each PENDING order: place it if price is at/near that level
  for (const order of signal.orders.filter(o => o.status === 'PENDING')) {
    const nearLevel = signal.direction === 'LONG'
      ? currentPrice <= order.limitPrice + 0.50   // within $0.50
      : currentPrice >= order.limitPrice - 0.50;

    // Re-confirm pullback before firing
    const confirm = confirmPullback(
      candles.m15, candles.m5,
      signal.zone, signal.direction, candles.rsi
    );

    if (nearLevel && confirm.confirmed) {
      const posId = await broker.placeLimitOrder({
        symbol: 'XAUUSD',
        type: signal.direction === 'LONG' ? 'buy_limit' : 'sell_limit',
        price: order.limitPrice,
        volume: order.volume,
        sl: order.sl,
        tp: order.tp1,           // Initial TP = TP1
        comment: `GOLD_SMC_${signal.id}_${order.id}`,
      });
      order.status = 'PLACED';
      order.positionId = posId;
    }
  }

  // 4. Manage already-ACTIVE positions
  const activeOrders = signal.orders.filter(o => o.status === 'ACTIVE');
  for (const order of activeOrders) {
    await manageActivePosition(order, currentPrice, candles.atr, env);
  }

  await saveSignal(signal, env); // persist state to KV
}

async function manageActivePosition(
  order: LadderOrder,
  price: number,
  atr: number,
  env: Env
): Promise<void> {

  // TP1 hit: close half, move SL to breakeven
  if (!order.tp1Hit && priceHit(price, order.tp1, order)) {
    await broker.closePartial(order.positionId, order.volume * 0.5);
    await broker.modifyPosition(order.positionId, order.limitPrice, order.tp2);
    order.tp1Hit = true;
    await sendAlert(`🎯 TP1 hit — Order ${order.id} — SL to breakeven`);
  }

  // TP2 hit: close another 30%, trail SL by ATR
  if (order.tp1Hit && !order.tp2Hit && priceHit(price, order.tp2, order)) {
    await broker.closePartial(order.positionId, order.volume * 0.3);
    const trailSL = order.direction === 'LONG'
      ? price - atr * 1.0
      : price + atr * 1.0;
    await broker.modifyPosition(order.positionId, trailSL, order.tp3);
    order.tp2Hit = true;
    await sendAlert(`🎯 TP2 hit — Order ${order.id} — trailing SL active`);
  }

  // TP3 hit: close remainder
  if (order.tp2Hit && priceHit(price, order.tp3, order)) {
    await broker.closePosition(order.positionId);
    order.status = 'CLOSED';
    order.tp3Hit = true;
    await sendAlert(`✅ TP3 hit — Order ${order.id} fully closed`);
  }
}
```

---

### KV State Schema for Active Signal

```typescript
// Stored in Cloudflare KV under key: "signal:XAUUSD:active"
interface PendingSignal {
  id: string;                    // unique signal ID
  createdAt: number;             // unix ms
  maxWaitMs: number;             // default: 4H = 14_400_000
  direction: 'LONG' | 'SHORT';
  score: number;                 // validation score (75-100)
  zone: EntryZone;
  sl: number;
  htfTargets: [number, number, number];
  orders: LadderOrder[];         // A, B, C
  status: 'WATCHING'             // waiting for pullback
        | 'CONFIRMED'            // pullback confirmed, placing orders
        | 'PARTIAL'              // some orders filled
        | 'FULL'                 // all 3 filled
        | 'CLOSED'               // all TP/SL resolved
        | 'EXPIRED'              // timed out
        | 'CANCELLED';           // SL breached before fill
  fillCount: number;             // 0-3
  realizedPnL: number;
}
```

---

### Telegram Alert Messages (Full Lifecycle)

```
📡 SIGNAL DETECTED — Watching for pullback
   Direction: LONG XAU/USD
   Zone: $2,340 – $2,350
   SL: $2,330 | Targets: $2,365 / $2,385 / $2,420
   Score: 88/100 | Session: NY Open
   Waiting... expires in 4H

⚡ PULLBACK CONFIRMED — Placing orders
   Checks: Engulfing ✓ | RSI shift ✓ | 5M CHoCH ✓
   Order A @ $2,350 → 0.01 lots
   Order B @ $2,345 → 0.01 lots
   Order C @ $2,340 → 0.01 lots
   Avg Entry: ~$2,345 | Total: 0.03 lots

✅ ORDER A FILLED @ $2,350
✅ ORDER B FILLED @ $2,344
⏳ ORDER C pending @ $2,340...

🎯 TP1 HIT — Order A @ $2,365
   Closed 50% | SL → $2,350 (breakeven)

🎯 TP1 HIT — Order B @ $2,365
   Closed 50% | SL → $2,345 (breakeven)

🎯 TP2 HIT — Orders A+B @ $2,385
   Trailing SL active | Riding to TP3

✅ TRADE CLOSED — All orders resolved
   Realized: +$127.50 | R achieved: 2.8R
   Daily P&L: +2.3%
```

---

## 🚀 Build Order for Claude Code (28 Tasks)

### Phase 0 — Scaffold
- [ ] **T1** `wrangler init gold-trading-bot --ts` + install deps
- [ ] **T2** Create shared `types.ts` (Candle, Order, Position, Signal interfaces)
- [ ] **T3** Create KV namespace + test read/write
- [ ] **T4** Create Python backtest venv + install deps

### Phase 1 — Broker Layer
- [ ] **T5** Build `oanda.ts` client (dev candles + orders)
- [ ] **T6** Build `metaapi.ts` client (prod MT5 bridge)
- [ ] **T7** Build broker factory `index.ts` + env-switch tests
- [ ] **T8** Build `session.ts` + `newsFilter.ts`

### Phase 2 — SMC Engine
- [ ] **T9**  `marketStructure.ts` + Python mirror
- [ ] **T10** `orderBlocks.ts` + Python mirror
- [ ] **T11** `fairValueGap.ts` + Python mirror
- [ ] **T12** `liquiditySweep.ts` + Python mirror
- [ ] **T13** `sessionLevels.ts` + Python mirror

### Phase 3 — Indicator Engine
- [ ] **T14** `math.ts` (EMA/RMA/Std helpers) + Python mirror
- [ ] **T15** `ema.ts` (stack detector) + Python mirror
- [ ] **T16** `rsi.ts` (divergence detector) + Python mirror
- [ ] **T17** `vwap.ts` (session + anchored) + Python mirror
- [ ] **T18** `atr.ts` (regime filter) + Python mirror
- [ ] **T19** `adx.ts` (strength filter) + Python mirror

### Phase 4 — Backtest Loop ← RUN BEFORE CONTINUING
- [ ] **T20** `fetch_data.py` (download 6mo OANDA M15/H1/H4)
- [ ] **T21** `run_backtest.py` (bar-by-bar, no lookahead)
- [ ] **T22** `metrics.py` (winrate, PF, Sharpe, drawdown)
- [ ] **T23** **RUN BACKTEST** → check pass criteria
- [ ] **T24** `optimizer.py` → sweep params
- [ ] **T25** **OPTIMIZE** until all criteria pass

### Phase 5 — Execution Layer
- [ ] **T26** `validator.ts` (8-gate, score system)
- [ ] **T27** `pullbackZone.ts` (FVG + OB + EMA21 overlap builder)
- [ ] **T28** `pullbackConfirm.ts` (candle pattern + RSI shift + 5M CHoCH)
- [ ] **T29** `orderLadder.ts` (3-split limit order builder)
- [ ] **T30** `tradeManager.ts` (signal lifecycle state machine)
- [ ] **T31** `riskManager.ts` (sizing, SL, daily limits)
- [ ] **T32** `tradeJournal.ts` + `telegram.ts` (full alert lifecycle)
- [ ] **T33** `scheduler.ts` (orchestrator) + `index.ts`

### Phase 6 — Deploy + Paper Trade
- [ ] **T34** `wrangler deploy` → live on Cloudflare
- [ ] **T35** Set `BROKER_MODE=oanda` → paper trade 2 weeks
- [ ] **T36** Compare paper vs backtest results
- [ ] **T37** Set `BROKER_MODE=mt5` → add MetaApi + MT5 secrets
- [ ] **T38** Live trade small size (0.01 lots) for 2 weeks
- [ ] **T39** Scale up size once live ≈ backtest ±15%

---

## 🔁 Improvement Loop Logic

```
LOOP until production-ready:

  run_backtest.py
      │
      ├─ FAIL criteria ──▶ optimizer.py ──▶ update params ──▶ loop
      │
      └─ PASS criteria
              │
              ▼
         Update TypeScript with optimal params
              │
              ▼
         wrangler deploy → paper trade 2 weeks
              │
              ├─ Paper >> Backtest by >20% ──▶ overfitting, re-optimize
              ├─ Paper << Backtest by >20% ──▶ execution issues, fix broker client
              └─ Paper ≈ Backtest (±15%)
                      │
                      ▼
                 BROKER_MODE=mt5, live small size
```

---

## 🚨 Production Rules

```
1. NEVER touch BROKER_MODE=mt5 secrets until paper trading passes
2. ATR gate is a hard blocker — never bypass, it prevents news traps
3. Direction conflict = no trade. All passing indicators must agree
4. Score 75+ required. Lowering threshold below 70 = gambling
5. Max 2 open trades simultaneously — Gold can reverse hard
6. Move SL to breakeven when TP1 hits (1:1 R) — protect capital
7. Kill switch: if daily P&L < -3% → bot stops until next session
```

---

## 📈 Expected Performance (After Optimization)

| Metric | Minimum | Target |
|---|---|---|
| Win Rate | 55% | 60–65% |
| Profit Factor | 1.8 | 2.2+ |
| Max Drawdown | ≤15% | ≤10% |
| Avg R:R | 2:1 | 2.5:1 |
| Daily Trades | 1 | 1–2 |
| Score of trades | 75–100 | 80–100 |

> **On the 5%/day target**: Requires 1-2 trades hitting 2.5-3R with 1% risk each. Achievable on high-conviction days. The bot should produce zero trades on days where the 8-gate system finds no qualifying setup — that discipline is what protects the account.

---

*v2 — Updated: MT5 via MetaApi for prod, OANDA for dev/backtest, 5-indicator confluence layer (EMA stack, RSI divergence, VWAP, ATR regime, ADX strength), 8-gate total validation, score-based trade sizing.*
