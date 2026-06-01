# Gold XAU/USD Real MT5 Expert Advisor Plan v4

> Strategy: Smart Money Concepts (SMC) + 5-indicator confluence
> Broker path: MQL5 Expert Advisor -> MT5 Terminal -> Broker
> Backtesting: MT5 Strategy Tester real broker execution first
> Infrastructure target: $0/month, excluding spread, commission, swap, and optional VPS

## Architecture

```text
MQL5 Expert Advisor
  -> MT5 Terminal
  -> MT5 Broker
```

The bot runs directly inside MT5 as an Expert Advisor. MetaApi, Cloudflare Workers, KV, and serverless cron are not the production path. The old Cloudflare/OANDA/MetaApi implementation remains under `legacy/cloudflare-worker/` for reference only.

OANDA can remain optional research/reference data, but it is not the primary execution or validation path. Real MT5 Strategy Tester results, broker-style order behavior, and demo-forward testing are the source of truth.

## Strategy Rules

The live EA runs on newly closed M15 bars and reads multi-timeframe data from MT5 native series APIs:

- H4 for structural bias
- H1 for confirmation, EMA, ATR, and ADX
- M15 for entry trigger, VWAP, RSI, FVG/OB zones
- M5 is reserved for future micro-confirmation work

All 3 SMC gates must pass:

1. H4 bias: market structure, discount/premium, and H4 FVG or order block.
2. H1 confirmation: aligned structure or BOS/CHoCH, liquidity sweep, and displacement.
3. M15 trigger: FVG or order block plus BOS/CHoCH.

The confluence score keeps the 100-point system:

- SMC gates: 37.5 fixed points when all pass
- EMA stack: 12.5
- RSI pullback: 12.5
- VWAP discount/premium: 12.5
- ATR regime: 12.5
- ADX strength: 12.5

Default trade threshold: `75`.

## Expert Advisor Defaults

Real broker execution is the default:

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
InpPythonParityMode = false
InpSessionFilter = "all"
InpPythonParityStart = ""
InpLegacyParityMode = false
```

`InpPythonParityMode=true` is diagnostic-only. It does not place broker orders and should be used only with `MT5_PARITY=1` when intentionally investigating the old Python simulator behavior.

## Execution Lifecycle

1. On each new M15 bar, calculate SMC and indicator gates from closed candles only.
2. Enforce daily loss/target, cooldown, and max-open-trades gates.
3. If SMC gates fail, log gate state and skip.
4. If score is below threshold or no valid entry zone exists, log the skip reason.
5. Build the entry zone from M15 FVG, M15 order block, and EMA21 proximity.
6. Place a 3-order broker-native pending limit ladder:
   - Long: zone top, midpoint, bottom
   - Short: zone bottom, midpoint, top
   - Split: 33%, 33%, 34%
7. Manage positions by magic number and symbol:
   - TP1 closes 50% and moves SL to breakeven.
   - TP2 closes 30% and enables ATR trailing.
   - TP3 closes the remainder.
   - Pending orders expire after `InpMaxHoldBars`.
   - Pending orders are cancelled if their stop is breached before fill.

## State And Logging

- Active runtime state is held in EA memory.
- Daily equity baseline and cooldown timestamp use MT5 Global Variables.
- Real execution journal writes to `MQL5/Files/GoldBot/trades.csv`.
- Journal entries include gate blocks, skipped signals, pending order success/failure, and TP lifecycle events.
- Strategy Tester HTML/XML reports are the primary performance artifacts.
- `parity_trades.csv` is ignored for real-mode acceptance.

## MT5 Strategy Tester Flow

1. Install the current repo source:
   `bash scripts/install-mt5-source.sh`
2. Compile `GoldBot.mq5` in MetaEditor with zero errors.
3. Run real-mode Strategy Tester:
   `MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 bash scripts/run-mt5-backtest.sh`
4. Inspect fresh tester report under `mt5/backtests/reports/`.
5. Inspect real execution journal under `MQL5/Files/GoldBot/trades.csv` or the Strategy Tester agent `MQL5/Files/GoldBot/trades.csv`.
6. Optimize exposed real-mode inputs in MT5 Strategy Tester.
7. Save the best real-mode config to `mt5/Presets/GoldBot.optimized.set`.
8. Forward test on MT5 demo for at least 2 weeks.
9. Compare demo fills, skipped signals, drawdown, trade frequency, and journal events against Strategy Tester before any tiny live deployment.

Optional parity diagnostic:

```bash
MT5_PARITY=1 MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 bash scripts/run-mt5-backtest.sh
python3 scripts/compare-mt5-python-parity.py --from-date 2023-10-01 --to-date 2025-09-30 --diff-trades --diff-signals
```

## Production Rules

1. Never start live until MT5 demo forward results are close enough to Strategy Tester behavior.
2. Real broker execution is judged by Strategy Tester reports, `trades.csv`, and demo-forward behavior.
3. Keep daily drawdown kill switch enabled.
4. Keep max open trades enabled.
5. Use tiny live size only after demo validation.
6. Optional VPS is for uptime only; it is not required for the initial low-cost setup.
