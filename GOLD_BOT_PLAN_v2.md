# Gold XAU/USD Real MT5 Expert Advisor Plan v4

> Strategy: Smart Money Concepts (SMC) + 5+ indicator confluence
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
- M15 for entry trigger, VWAP, RSI, Bollinger Bands, Stochastic, FVG/OB zones
- M5 is reserved for future micro-confirmation work

SMC is scored instead of treated as a brittle all-or-nothing filter:

1. H4 bias: market structure, discount/premium, and H4 FVG or order block.
2. H1 confirmation: aligned structure or BOS/CHoCH, liquidity sweep, and displacement.
3. M15 trigger: FVG or order block plus BOS/CHoCH. This is the required real-mode execution gate.

Research-backed SMC recovery candidates can optionally require a more professional sequence without changing the default workflow:

- M15 liquidity sweep happened recently.
- Displacement or BOS/CHoCH followed the sweep.
- A valid M15 FVG/order-block zone exists.
- OB/FVG overlap and H4/H1 context can be promoted from journaled evidence to hard gates per candidate.
- A semicolon-separated `InpAllowedEntryHours` filter can restrict entries to empirically stronger server hours.

Entry should be determined by SMC plus a configurable 5+ indicator confluence layer. The current EA supports 8 indicator gates:

1. EMA stack
2. RSI pullback
3. VWAP discount/premium
4. ATR volatility regime
5. ADX/DI directional trend strength
6. MACD momentum
7. Bollinger Band discount/premium
8. Stochastic pullback/turn

The confluence score keeps the 100-point system:

- M15 SMC trigger: 25
- H4 SMC bias confirmation: 6.25
- H1 SMC confirmation: 6.25
- Indicator confluence block: 62.5 total, distributed across enabled indicators.

With all 8 indicators enabled, each indicator contributes `7.8125` points. With only the original 5 enabled, each contributes `12.5` points.

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
InpMacdFast = 12
InpMacdSlow = 26
InpMacdSignal = 9
InpBbPeriod = 20
InpBbDeviation = 2.0
InpStochKPeriod = 14
InpStochDPeriod = 3
InpStochSlowing = 3
InpStochLongMax = 35
InpStochShortMin = 65
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
InpResetJournalOnInit = true
InpPythonParityMode = false
InpSessionFilter = "all"
InpPythonParityStart = ""
InpLegacyParityMode = false
InpRequireHigherTfConfirmation = true
InpMinRealModeScore = 68.75
InpMaxLaddersPerDay = 3
InpUseSessionFilterForRealMode = true
InpRealSessionStartHour = 7
InpRealSessionEndHour = 22
InpTp1R = 1.5
InpTp2R = 2.0
InpTp3R = 3.0
InpBreakEvenAtR = 0.0
InpTrailAfterTp1 = true
InpLadderOrderCount = 3
InpLadderFirstSplit = 1
InpMinRealConfluences = 5
InpRequireDirectionalAdx = true
InpRequireEmaTrend = false
InpUseMacdConfluence = true
InpUseBollingerConfluence = true
InpUseStochasticConfluence = true
InpRequireM5PullbackConfirmation = true
InpPullbackConfirmChecks = 2
InpEnableNewsFilter = false
InpNewsBlackoutMinutes = 30
InpHighImpactNewsTimes = ""
InpBlockIndicatorDirectionConflicts = true
InpUseExtendedDirectionConflict = true
InpUseHtfTargetsForTp2Tp3 = true
InpRequireNearZoneBeforeLadder = true
InpNearZoneBuffer = 0.5
InpRequireSmcSequence = false
InpRequireLiquiditySweepForSmc = false
InpRequireDisplacementForSmc = false
InpRequireObFvgOverlap = false
InpRequireHtfSmcContext = false
InpAllowedEntryHours = ""
InpAllowedLongEntryHours = ""
InpAllowedShortEntryHours = ""
InpAllowLong = true
InpAllowShort = true
```

`InpPythonParityMode=true` is diagnostic-only. It does not place broker orders and should be used only with `MT5_PARITY=1` when intentionally investigating the old Python simulator behavior.

`mt5/Presets/GoldBot.optimized.set` may carry the current evidence-based Strategy Tester candidate, which can be more conservative than the raw EA defaults.

## Execution Lifecycle

1. On each new M15 bar, calculate SMC and indicator gates from closed candles only.
2. Enforce daily loss/target, cooldown, and max-open-trades gates.
3. If the M15 SMC execution trigger fails, log gate state and skip.
4. If enabled, require H4 or H1 confirmation before a real-mode entry.
5. If enabled, require research-backed SMC sequence gates: recent sweep, displacement/BOS, OB/FVG overlap, or HTF context.
6. If configured, block entries outside `InpAllowedEntryHours`, then apply direction-specific hour filters from `InpAllowedLongEntryHours` / `InpAllowedShortEntryHours`.
7. If enabled, enforce the real-mode server-hour session window.
8. If enabled, enforce the max ladders per broker day limit.
9. If enabled, block entries during manually supplied high-impact news blackout windows.
10. If enabled, block direction-conflict states across EMA, RSI, VWAP, ADX, MACD, Bollinger Bands, and Stochastic direction votes.
11. If enabled, require the configured real-mode 5+ indicator confluence count, directional ADX, and EMA trend quality gates.
12. If score is below threshold or no valid entry zone exists, log the skip reason.
13. Build the entry zone from M15 FVG, M15 order block, and EMA21 proximity.
14. If enabled, require M5/M15 pullback confirmation before order placement:
   - M15 candle pattern or pin bar inside the entry zone
   - M15 RSI shift
   - M5 change-of-character confirmation
   - Default requirement: 2 of 3 checks
15. If enabled, require price to be near the entry zone before placing the broker ladder, matching the old TypeScript near-level guard.
16. Place a configurable broker-native pending limit ladder:
   - Long: zone top, midpoint, bottom
   - Short: zone bottom, midpoint, top
   - `InpLadderOrderCount=1..3` controls how many ladder levels are placed.
   - `InpLadderFirstSplit=1..3` controls whether candidates start from the closest pullback split, midpoint split, or deepest split.
17. Manage positions by magic number and symbol:
   - If `InpBreakEvenAtR > 0`, move SL to breakeven once that R threshold is reached.
   - TP1 closes 50%, moves SL to breakeven, and can enable ATR trailing.
   - TP2 closes 30% using the nearest H1 target beyond the configured R multiple when available.
   - TP3 closes the remainder using the nearest H4 target beyond the configured R multiple when available.
   - Pending orders expire after `InpMaxHoldBars`.
   - Filled positions are closed after `InpMaxHoldBars`.
   - Pending orders are cancelled if their stop is breached before fill.

## State And Logging

- Active runtime state is held in EA memory.
- Daily equity baseline, cooldown timestamp, and daily ladder count use MT5 Global Variables.
- Real execution journal writes to `MQL5/Files/GoldBot/trades.csv`.
- The backtest helper copies the latest journal to `mt5/backtests/reports/<report-name>.trades.csv`.
- Journal entries include gate blocks, skipped signals, pending order success/failure, and TP lifecycle events.
- Attribution reports group closed PnL by direction, hour, ladder split, direction/hour, direction/split, hour/split, score bucket, confluence count, and exit reason.
- Strategy Tester HTML/XML reports are the primary performance artifacts.
- `parity_trades.csv` is ignored for real-mode acceptance.

## MT5 Strategy Tester Flow

1. Install the current repo source:
   `bash scripts/install-mt5-source.sh`
2. Compile `GoldBot.mq5` in MetaEditor with zero errors.
3. Run real-mode Strategy Tester:
   `MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 bash scripts/run-mt5-backtest.sh`
4. Or run a named candidate:
   `python3 scripts/run-mt5-candidate.py tp-repair-score62-risk003`
5. Inspect fresh tester report under `mt5/backtests/reports/`.
6. Inspect copied real execution journal under `mt5/backtests/reports/<report-name>.trades.csv`.
7. Summarize reports:
   `python3 scripts/summarize-mt5-reports.py mt5/backtests/reports/*.htm`
8. Summarize journals:
   `python3 scripts/analyze-mt5-trades.py mt5/backtests/reports/*.trades.csv`
9. Evaluate candidates:
   `python3 scripts/evaluate-mt5-candidates.py mt5/backtests/reports/*.htm`
10. Optimize exposed real-mode inputs in MT5 Strategy Tester.
11. Save the best real-mode config to `mt5/Presets/GoldBot.optimized.set`.
12. Forward test on MT5 demo for at least 2 weeks.
13. Compare demo fills, skipped signals, drawdown, trade frequency, and journal events against Strategy Tester before any tiny live deployment.

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

## Next Improvement Plan

The next implementation plan is tracked in `mt5/backtests/NEXT_IMPROVEMENT_PLAN.md`.
