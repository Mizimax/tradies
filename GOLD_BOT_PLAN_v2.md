# Gold XAU/USD MT5 Expert Advisor Execution Plan v3

> Strategy: Smart Money Concepts (SMC) + 5-indicator confluence  
> Broker path: MQL5 Expert Advisor -> MT5 Terminal -> Broker  
> Backtesting: MT5 Strategy Tester and optimizer  
> Infrastructure target: $0/month, excluding spread, commission, swap, and optional VPS

## Architecture

```text
MQL5 Expert Advisor
  -> MT5 Terminal
  -> MT5 Broker
```

The bot now runs directly inside MT5 as an Expert Advisor. MetaApi, Cloudflare Workers, KV, and serverless cron are no longer the production path. The old Cloudflare/OANDA/MetaApi implementation is preserved under `legacy/cloudflare-worker/` for reference only.

OANDA remains optional for research/reference data, but the source of truth for execution and optimization is MT5 Strategy Tester on the target broker's symbol, spread, commission, and contract settings.

## Strategy Rules

The EA runs only on newly closed M15 bars and reads multi-timeframe data from MT5 native series APIs:

- H4 for structural bias
- H1 for confirmation, EMA, ATR, and ADX
- M15 for entry trigger, VWAP, RSI, FVG/OB zones
- M5 for micro CHoCH pullback confirmation

### SMC Gates

All 3 SMC gates must pass:

1. H4 bias
   - Market structure is bullish or bearish.
   - Longs require discount; shorts require premium.
   - Unmitigated H4 FVG or order block exists in bias direction.
2. H1 confirmation
   - Structure aligns with H4 bias or shows BOS/CHoCH.
   - Liquidity sweep detected.
   - Displacement candle confirms post-sweep intent.
3. M15 entry trigger
   - Price pulls into M15 FVG or order block.
   - M15 BOS/CHoCH confirms direction.
   - News block is disabled by default and can be handled manually before running live.

### Indicator Gates

The confluence score keeps the 100-point system:

- SMC gates: 37.5 fixed points when all pass
- EMA stack: 12.5
- RSI pullback/divergence: 12.5
- VWAP discount/premium: 12.5
- ATR regime: 12.5
- ADX strength: 12.5

Default trade threshold: `75`.

## Expert Advisor Inputs

Defaults match the tuned research parameters:

```text
InpSymbol = "XAUUSD"
InpMagicNumber = 26053101
InpRiskMode = EQUITY_LOT_RATIO
InpLotPer100Usd = 0.01
InpMinLot = 0.01
InpMaxLot = 5.0
InpScoreThreshold = 75
InpHighConvictionScore = 88
InpRsiPeriod = 10
InpRsiLongMax = 38
InpRsiShortMin = 40
InpAdxMin = 14
InpAtrMin = 1.0
InpAtrMax = 35.0
InpSlAtr = 0.8
InpMinRR = 2.0
InpMaxHoldBars = 48
InpCooldownBars = 16
InpMaxOpenTrades = 2
InpMaxDailyLossPct = 3.0
InpDailyTargetPct = 5.0
InpEnableTelegram = false
InpDebugOnly = false
```

## Execution Lifecycle

1. On each new M15 bar, calculate SMC and indicator gates from closed candles only.
2. If score is below threshold or direction conflicts, skip.
3. Build the entry zone from M15 FVG, M15 order block, and EMA21 proximity.
4. Place a 3-order pending ladder:
   - Long: zone top, midpoint, bottom
   - Short: zone bottom, midpoint, top
   - Split: 33%, 33%, 34%
5. Manage positions by magic number and symbol:
   - TP1 closes 50% and moves SL to breakeven.
   - TP2 closes 30% and switches TP to TP3.
   - TP3 closes the remainder.
   - SL hit cancels remaining pending orders.
6. Expire old pending orders after `InpMaxHoldBars`.
7. Enforce cooldown, max open trades, daily loss limit, and daily target using MT5 Global Variables.

## State And Logging

- Active runtime state is held in EA memory.
- Daily equity baseline and cooldown timestamp are stored in MT5 Global Variables.
- CSV journal is written to `MQL5/Files/GoldBot/trades.csv`.
- Debug mode prints full gate state, score, zone, SL, and TP levels without placing orders.

## Repository Structure

```text
mt5/
  Experts/GoldBot/GoldBot.mq5
  Include/GoldBot/Indicators.mqh
  Include/GoldBot/SMC.mqh
  Include/GoldBot/Risk.mqh
  Include/GoldBot/TradeManager.mqh
  Presets/GoldBot.optimized.set
  backtests/README.md

legacy/cloudflare-worker/
  previous TypeScript Cloudflare/OANDA/MetaApi implementation
```

## MT5 Strategy Tester Flow

1. Copy `mt5/Experts/GoldBot/GoldBot.mq5` into `MQL5/Experts/GoldBot/`.
2. Copy `mt5/Include/GoldBot/*.mqh` into `MQL5/Include/GoldBot/`.
3. Compile in MetaEditor.
4. Run Strategy Tester:
   - Symbol: XAUUSD or broker's gold symbol
   - Timeframe: M15
   - Model: every tick based on real ticks when available
   - Spread/commission: broker-realistic
5. Run optimization over the exposed inputs.
6. Save best config to `mt5/Presets/GoldBot.optimized.set`.
7. Forward test on MT5 demo for at least 2 weeks.
8. Compare demo vs Strategy Tester before any tiny live deployment.

## Production Rules

1. Never start live until MT5 demo forward results are close to Strategy Tester results.
2. Keep `InpDebugOnly=true` for first chart attachment.
3. Use a broker demo account first.
4. Daily drawdown kill switch must remain enabled.
5. Max open trades must remain enabled.
6. Use tiny live size only after demo validation.
7. Optional VPS is for uptime only; it is not required for the initial low-cost setup.
