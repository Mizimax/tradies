# Gold XAU/USD MT5 Expert Advisor Execution Plan v3

> Strategy: Smart Money Concepts (SMC) + 5-indicator confluence  
> Broker path: MQL5 Expert Advisor -> MT5 Terminal -> Broker  
> Backtesting: MT5 Strategy Tester with Python simulator parity first, then optimizer
> Infrastructure target: $0/month, excluding spread, commission, swap, and optional VPS

## Architecture

```text
MQL5 Expert Advisor
  -> MT5 Terminal
  -> MT5 Broker
```

The bot now runs directly inside MT5 as an Expert Advisor. MetaApi, Cloudflare Workers, KV, and serverless cron are no longer the production path. The old Cloudflare/OANDA/MetaApi implementation is preserved under `legacy/cloudflare-worker/` for reference only.

OANDA remains optional for research/reference data. The first source of truth is Python simulator parity against `legacy/cloudflare-worker/backtesting/results/backtest_best_24m.json`; after parity is proven, live-style execution and optimization move to MT5 Strategy Tester on the target broker's symbol, spread, commission, and contract settings.

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
InpPythonParityMode = true
InpSessionFilter = "all"
InpLegacyParityMode = false
```

## Python Simulator Parity Baseline

Before improving strategy logic, the EA must match the Python best 24-month backtest as closely as possible:

```text
Trades: 251
Win rate: 58.17%
Profit factor: 2.68
Avg planned RR: 2.0
Expectancy: +0.69R/trade
Max drawdown: 10.30R
Avg trades/day: 1.35
```

`InpPythonParityMode=true` is the default backtest mode. It does not place broker orders. It simulates the Python candle engine inside the EA using closed M15 candles, H1 indicators aligned to the signal candle time, rolling 96-candle VWAP, Python sweep windows, next-candle-open entries, SL-first handling when SL and TP touch in the same candle, cooldown after simulated trade open, and max-hold candle exits capped between `-1R` and `+2R`.

Parity trades are written to `MQL5/Files/GoldBot/parity_trades.csv`, and the EA prints a parity summary at tester shutdown. Live/broker execution is available only when `InpPythonParityMode=false`.

## Execution Lifecycle

1. In parity mode, simulate the Python candle backtest and skip all broker order placement.
2. In live-style mode, on each new M15 bar, calculate SMC and indicator gates from closed candles only.
3. If score is below threshold or direction conflicts, skip.
4. Build the entry zone from M15 FVG, M15 order block, and EMA21 proximity.
5. Place a 3-order pending ladder:
   - Long: zone top, midpoint, bottom
   - Short: zone bottom, midpoint, top
   - Split: 33%, 33%, 34%
6. Manage positions by magic number and symbol:
   - TP1 closes 50% and moves SL to breakeven.
   - TP2 closes 30% and switches TP to TP3.
   - TP3 closes the remainder.
   - SL hit cancels remaining pending orders.
7. Expire old pending orders after `InpMaxHoldBars`.
8. Enforce cooldown, max open trades, daily loss limit, and daily target using MT5 Global Variables.

## State And Logging

- Active runtime state is held in EA memory.
- Daily equity baseline and cooldown timestamp are stored in MT5 Global Variables.
- CSV journal is written to `MQL5/Files/GoldBot/trades.csv`.
- Python parity CSV journal is written to `MQL5/Files/GoldBot/parity_trades.csv`.
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
4. Run Strategy Tester for Python parity:
   - Symbol: XAUUSD or broker's gold symbol
   - Timeframe: M15
   - `InpPythonParityMode=true`
   - Date window: 2023-10-01 through 2025-09-30 for the current comparison run
5. Compare `MQL5/Files/GoldBot/parity_trades.csv` to the Python baseline:
   `python3 scripts/compare-mt5-python-parity.py "<MT5 root>/MQL5/Files/GoldBot/parity_trades.csv"`
6. Acceptance target:
   - Trades within +/-5% of 251
   - Win rate within +/-3 percentage points of 58.17%
   - Profit factor within +/-10% of 2.68
   - Expectancy within +/-0.10R of +0.69R
7. After parity is proven, set `InpPythonParityMode=false` and run live-style Strategy Tester with broker-realistic spread/commission.
8. Run optimization over the exposed inputs.
9. Save best config to `mt5/Presets/GoldBot.optimized.set`.
10. Forward test on MT5 demo for at least 2 weeks.
11. Compare demo vs Strategy Tester before any tiny live deployment.

## Production Rules

1. Never start live until MT5 demo forward results are close to Strategy Tester results.
2. Prove Python simulator parity before improving the strategy or optimizing live-style execution.
3. Keep `InpDebugOnly=true` for first chart attachment.
4. Use a broker demo account first.
5. Daily drawdown kill switch must remain enabled.
6. Max open trades must remain enabled.
7. Use tiny live size only after demo validation.
8. Optional VPS is for uptime only; it is not required for the initial low-cost setup.
