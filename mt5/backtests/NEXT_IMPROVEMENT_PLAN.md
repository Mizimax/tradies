# GoldBot Real-Mode Improvement Plan

## Current Baseline

Use real MT5 broker execution only. Do not use Python parity mode for performance acceptance.

Original honest baseline:

```text
Report: mt5/backtests/reports/GoldBot-XAUUSD-M15-2023.10.01-2025.09.30-threshold62_5-maxhold.htm
Mode: Real broker execution
Window: 2023-10-01 through 2025-09-30
Deposit: 100,000 USD
Input override: InpScoreThreshold=62.5

Total trades: 812
Win rate: 31.28%
Profit factor: 0.78
Net profit: -42,270.11
Expected payoff: -52.06
Max balance drawdown: 58.24%
Max equity drawdown: 60.89%
Pending orders placed: 1028
Pending ladders placed: 454
TP1 hits: 179
TP2 hits: 4
TP3 hits: 3
Max-hold closes: 29
```

Interpretation:

- The EA is now active in real broker mode.
- `InpScoreThreshold=62.5` overtrades.
- Drawdown is far too high for demo-forward acceptance.
- TP2/TP3 are almost never reached, so the current lifecycle is too dependent on TP1 and stop/breakeven behavior.
- The previous huge profit result was invalid because positions could remain open until test end. That is now fixed by closing filled positions after `InpMaxHoldBars`.

Latest candidate after Phase 1 filters and Phase 2 risk reduction:

```text
Report: mt5/backtests/reports/GoldBot-real-soft-confirm-score62-risk003.htm
Mode: Real broker execution
Window: 2023-10-01 through 2025-09-30
Deposit: 100,000 USD
Input overrides:
  InpRequireHigherTfConfirmation=false
  InpScoreThreshold=62.5
  InpMinRealModeScore=62.5
  InpLotPer100Usd=0.003
  InpCooldownBars=24
  InpMaxOpenTrades=1
  InpMaxLaddersPerDay=2
  InpUseSessionFilterForRealMode=true

Total trades: 558
Win rate: 31.18%
Profit factor: 0.68
Net profit: -15,866.34
Expected payoff: -28.43
Max balance drawdown: 19.58%
Max equity drawdown: 20.59%
Pending orders placed: 667
Pending ladders placed: 299
TP1 hits: 124
TP2 hits: 0
TP3 hits: 0
```

Latest interpretation:

- Phase 1/2 materially reduced damage: net loss improved by about 26,403.77 versus the original honest baseline.
- Drawdown is now under the initial 25% limit, but profit factor is worse at 0.68 and the strategy is still not demo-forward ready.
- The score 68.75 test was too restrictive and produced only 3 trades, so it is not useful as a candidate.
- The main bottleneck is now exit lifecycle quality: TP1 happens, but TP2/TP3 do not meaningfully participate.
- The next improvement should repair TP levels and trailing behavior before more entry filtering.

Phase 3 TP-repair result:

```text
Report: mt5/backtests/reports/GoldBot-real-tp-repair-score62-risk003.htm
Journal: mt5/backtests/reports/GoldBot-real-tp-repair-score62-risk003.trades.csv

Total trades: 691
Win rate: 50.94%
Profit factor: 0.73
Net profit: -13,432.80
Expected payoff: -19.44
Max balance drawdown: 15.45%
Max equity drawdown: 15.59%
TP1 hits: 141
TP2 hits: 111
TP3 hits: 72
Max-hold closes: 1
```

Phase 3 interpretation:

- TP lifecycle repair worked: TP2/TP3 are now meaningful instead of zero.
- Drawdown improved from 20.59% to 15.59%.
- Win rate improved from 31.18% to 50.94%.
- Profit factor improved from 0.68 to 0.73, but still fails the 1.20 gate.
- Trade count increased to 691, above the 150-450 target.
- Next improvement is stricter real-mode quality gating, not lower risk alone.

## Improvement Goal

Find a real-mode configuration and code path that is stable enough for demo-forward testing.

Initial target:

```text
Profit factor: >= 1.20
Max equity drawdown: <= 25%
Trades over 24 months: 150-450
TP2/TP3 lifecycle: non-zero and explainable
No end-of-test profit dependency
No stale open positions older than InpMaxHoldBars
```

This is not the final trading goal. It is the next quality gate before deeper optimization.

## Hypotheses

1. Trade frequency is too high because M15-only SMC entries are allowed when H4/H1 are both false.
2. Lot sizing is too aggressive for a strategy that places up to three pending orders per signal.
3. TP2/TP3 are too far or the trailing lifecycle activates too late.
4. The score threshold should not be lowered alone; it should be paired with stronger confirmation.
5. Some losses come from repeated entries in the same local structure before cooldown meaningfully separates signals.
6. Current real-mode entries can pass without directional ADX or enough indicator confluence, causing high trade count and weak profit factor.
7. Entry quality should use all available 5+ indicators, not just the original EMA/RSI/VWAP/ATR/ADX set.

## Phase 1: Add Real-Mode Filter Controls

Status: implemented in the EA and preset; validated by Strategy Tester runs.

Add inputs:

```text
InpRequireHigherTfConfirmation = true
InpMinRealModeScore = 68.75
InpMaxLaddersPerDay = 3
InpUseSessionFilterForRealMode = true
InpRealSessionStartHour = 7
InpRealSessionEndHour = 22
```

Behavior:

- Require M15 SMC trigger as today.
- When `InpRequireHigherTfConfirmation=true`, require `gateH4 || gateH1`.
- Keep H4/H1 as score contributors.
- Limit new ladders per broker day.
- Block new ladders outside the configured server-time session.

Acceptance:

- Strategy Tester still places broker-native pending limit orders.
- `trades.csv` logs specific block reasons:
  - higher timeframe confirmation blocked
  - daily ladder limit blocked
  - real session blocked
- No parity file is used.

Result:

- Hard higher-timeframe confirmation with score 68.75 was too strict and produced only 3 trades.
- Soft confirmation with score 62.5, lower risk, max open trade 1, and max ladders/day 2 produced enough activity to evaluate, but remained unprofitable.

## Phase 2: Risk Reduction

Status: partially tested. Lower size and stricter limits reduced drawdown, but did not improve profit factor enough.

Test lower size first, before changing TP/SL logic:

```bash
MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 \
MT5_REPORT=GoldBot-real-score68-risk003 \
MT5_INPUT_OVERRIDES=$'InpScoreThreshold=68.75\nInpLotPer100Usd=0.003' \
bash scripts/run-mt5-backtest.sh
```

Grid:

```text
InpScoreThreshold: 68.75, 70, 75
InpLotPer100Usd: 0.002, 0.003, 0.005
InpCooldownBars: 16, 24, 32
InpMaxOpenTrades: 1, 2
InpMaxLaddersPerDay: 1, 2, 3
```

Acceptance:

- Max equity drawdown falls below 25%.
- Trade count stays above 150 over 24 months.
- Profit factor improves compared with 0.78.

Result:

- Max equity drawdown passed at 20.59%.
- Trade count passed at 558, though still higher than the 150-450 target.
- Profit factor failed at 0.68.
- Continue risk grid only after Phase 3 gives winners a realistic path beyond TP1.

## Phase 3: TP Lifecycle Repair

Status: implemented and validated. TP2/TP3 lifecycle is now alive, but the candidate still fails profit factor and trade-count gates.

Current TP evidence:

```text
TP1 hits: 179
TP2 hits: 4
TP3 hits: 3
```

Latest TP evidence after Phase 1/2:

```text
TP1 hits: 124
TP2 hits: 0
TP3 hits: 0
```

This means exits are not balanced. Phase 1 and 2 reduced drawdown enough to expose the next problem clearly. Test:

```text
TP1: 1.5R instead of 2.0R
TP2: 2.0R instead of 2.5R
TP3: 3.0R instead of 4.0R
ATR trailing after TP1 instead of after TP2
```

Added inputs:

```text
InpTp1R = 1.5
InpTp2R = 2.0
InpTp3R = 3.0
InpTrailAfterTp1 = true
```

Acceptance:

- TP2 and TP3 are reached more than a token amount.
- Profit factor does not rely on a few end-of-test exits.
- Max-hold closes are still logged and do not dominate profit.

Result:

- Passed TP lifecycle: TP2 `111`, TP3 `72`.
- Passed drawdown: max equity drawdown `15.59%`.
- Failed profit factor: `0.73`.
- Failed trade count: `691`.

## Phase 3B: Real-Mode Quality Gate

Status: implemented in the EA and candidate matrix; expanded to 8 indicator gates; next step is MetaEditor compile and Strategy Tester validation.

Added inputs:

```text
InpMinRealConfluences = 5
InpRequireDirectionalAdx = true
InpRequireEmaTrend = false
InpUseMacdConfluence = true
InpUseBollingerConfluence = true
InpUseStochasticConfluence = true
```

Behavior:

- Count EMA, RSI, VWAP, ATR, directional ADX, MACD, Bollinger Bands, and Stochastic confluences.
- Block real-mode entries below `InpMinRealConfluences`.
- Optionally require directional ADX.
- Optionally require EMA trend alignment.
- Journal quality block reasons and accepted signal confluence states.

Next target candidates:

```bash
python3 scripts/run-mt5-candidate.py quality-8ind-conf5
python3 scripts/run-mt5-candidate.py quality-8ind-conf6
python3 scripts/run-mt5-candidate.py quality-8ind-conf5-ladder1
```

## Phase 3C: Restore Old TypeScript Entry Guards

Status: implemented in the EA and candidate matrix; next step is MetaEditor compile and Strategy Tester validation.

Restored from the archived Cloudflare/TypeScript path:

- M5/M15 pullback confirmation before placing the pending ladder.
- Optional high-impact news blackout from the old JSON-style event payload or semicolon-separated timestamps.
- Direction-conflict blocking across indicator direction votes.
- Exact TypeScript-style entry-zone overlap/fallback between FVG, order block, and EMA21.
- Near-zone placement guard before creating the broker-native pending ladder.
- HTF target-based TP2/TP3 using H1/H4 structure targets when available, with R-multiple fallback.

Added inputs:

```text
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
```

Next target candidates:

```bash
python3 scripts/run-mt5-candidate.py ts-complete-8ind-conf5
python3 scripts/run-mt5-candidate.py ts-complete-8ind-conf5-ladder1
```

Next target command after implementation:

```bash
MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 \
MT5_REPORT=GoldBot-real-tp-repair-score62-risk003 \
MT5_INPUT_OVERRIDES=$'InpRequireHigherTfConfirmation=false\nInpScoreThreshold=62.5\nInpMinRealModeScore=62.5\nInpLotPer100Usd=0.003\nInpCooldownBars=24\nInpMaxOpenTrades=1\nInpMaxLaddersPerDay=2\nInpUseSessionFilterForRealMode=true\nInpTp1R=1.5\nInpTp2R=2.0\nInpTp3R=3.0\nInpTrailAfterTp1=true' \
bash scripts/run-mt5-backtest.sh
```

## Phase 4: Compare Candidate Reports

Status: implemented with `scripts/summarize-mt5-reports.py`, `scripts/analyze-mt5-trades.py`, `scripts/print-mt5-candidate-commands.py`, `scripts/evaluate-mt5-candidates.py`, `scripts/run-mt5-improvement-suite.py`, and `scripts/apply-mt5-best-candidate.py`.

Run the default Phase 3B/3C suite after compiling in MetaEditor:

```bash
python3 scripts/run-mt5-improvement-suite.py
```

## Phase 5: Research-Backed SMC Recovery

Status: implemented in the EA and candidate matrix; next step is MetaEditor compile and Strategy Tester validation.

Rationale:

- The latest attribution shows weak server hours are a major loss source.
- SMC research supports sequencing entries around liquidity sweep, displacement/BOS, OB/FVG zone quality, first retest, and higher-timeframe context.
- The next candidates keep default behavior unchanged and test opt-in SMC/hour filters against real MT5 reports.

Added inputs:

```text
InpRequireSmcSequence = false
InpRequireLiquiditySweepForSmc = false
InpRequireDisplacementForSmc = false
InpRequireObFvgOverlap = false
InpRequireHtfSmcContext = false
InpAllowedEntryHours = ""
```

Next target candidates:

```bash
python3 scripts/run-mt5-candidate.py smc-hours-12-17-19
python3 scripts/run-mt5-candidate.py smc-hours-7-12-15-17-19
python3 scripts/run-mt5-candidate.py smc-sequence-soft
python3 scripts/run-mt5-candidate.py smc-sequence-soft-hours
python3 scripts/run-mt5-candidate.py smc-htf-context-soft
python3 scripts/run-mt5-candidate.py smc-ob-fvg-overlap
python3 scripts/run-mt5-candidate.py smc-balanced-best-risk003
```

Use `--clean` after matrix/default changes so old reports do not get mixed into the new comparison:

```bash
python3 scripts/run-mt5-improvement-suite.py --clean
```

## Phase 6: Max-PF Direction And Session Discovery

Status: implemented in the EA and candidate matrix; next step is MetaEditor compile and Strategy Tester validation.

Rationale:

- `smc-hours-7-12-15-17-19` improved to PF `0.94`, but attribution showed the edge is not symmetric.
- Long trades around server hours `7`, `12`, and `16` were materially stronger than most shorts.
- Short hour `19` showed promise but needs a standalone sample check.
- This phase intentionally accepts low trade count as discovery only; passing candidates below `150` trades are not demo-ready.

Added inputs:

```text
InpAllowedLongEntryHours = ""
InpAllowedShortEntryHours = ""
InpLadderFirstSplit = 1
```

Next target candidates:

```bash
python3 scripts/run-mt5-candidate.py pf-long-hours-7-12-16
python3 scripts/run-mt5-candidate.py pf-long-hours-7-12-16-ladder2only
python3 scripts/run-mt5-candidate.py pf-long-hours-7-12-16-ladder23
python3 scripts/run-mt5-candidate.py pf-long-hours-7-12-16-19-ladder2only
python3 scripts/run-mt5-candidate.py pf-short-hour19-ladder2only
python3 scripts/run-mt5-candidate.py pf-dir-hours-long7-12-16-short19
python3 scripts/run-mt5-candidate.py pf-dir-hours-long7-12-16-short19-ladder2only
```

Discovery acceptance:

- PF `>= 1.20`
- equity drawdown `<= 15%`
- trades `>= 40`
- no Python parity mode
- candidates under `40` trades are marked as too small sample

This runs:

```text
tp-repair-score62-risk003
tp-repair-long-only
tp-repair-short-only
tp-repair-ladder1
tp-repair-ladder2
tp-repair-be1
tp-repair-fast-tp
tp-repair-long-only-ladder1
tp-repair-short-only-ladder1
quality-adx-conf4
quality-8ind-conf4
quality-8ind-conf4-ladder1
quality-8ind-conf4-noadx
quality-8ind-conf5
quality-8ind-conf5-ladder1
ts-lite-8ind-conf4
ts-lite-8ind-conf4-check1
ts-complete-8ind-conf5
ts-complete-8ind-conf5-ladder1
```

The suite intentionally includes a baseline, long-only/short-only direction isolation, ladder-count reduction, breakeven protection, faster TP levels, and middle-layer candidates. The first strict 8-indicator pass showed that 5-of-8 produced only 13 trades and TS-complete produced zero trades, so 4-of-8 and TS-lite variants are now part of the default comparison.

Current next recovery candidates:

```bash
python3 scripts/run-mt5-candidate.py tp-repair-ladder1
python3 scripts/run-mt5-candidate.py tp-repair-ladder2
python3 scripts/run-mt5-candidate.py tp-repair-be1
python3 scripts/run-mt5-candidate.py tp-repair-fast-tp
python3 scripts/run-mt5-candidate.py tp-repair-long-only-ladder1
python3 scripts/run-mt5-candidate.py tp-repair-short-only-ladder1
```

It writes:

```text
mt5/backtests/reports/improvement-summary.csv
mt5/backtests/reports/improvement-evaluation.csv
mt5/backtests/reports/improvement-journal-summary.csv
```

If at least one candidate passes the gate, apply the top-ranked passing candidate to `mt5/Presets/GoldBot.optimized.set`:

```bash
python3 scripts/apply-mt5-best-candidate.py
```

Compare reports:

```bash
python3 scripts/summarize-mt5-reports.py mt5/backtests/reports/*.htm
```

Compare real-mode journals:

```bash
python3 scripts/analyze-mt5-trades.py mt5/backtests/reports/*.trades.csv
```

Print the candidate grid commands:

```bash
python3 scripts/print-mt5-candidate-commands.py
```

Run a single candidate by name:

```bash
python3 scripts/run-mt5-candidate.py --list
python3 scripts/run-mt5-candidate.py tp-repair-score62-risk003
```

Evaluate candidates against the improvement gate:

```bash
python3 scripts/evaluate-mt5-candidates.py mt5/backtests/reports/*.htm
```

Required columns:

```text
report
net_profit
profit_factor
expected_payoff
total_trades
win_rate
max_balance_drawdown_pct
max_equity_drawdown_pct
gross_profit
gross_loss
```

Acceptance:

- The best candidate is chosen from comparable real-mode reports.
- The chosen preset is copied into `mt5/Presets/GoldBot.optimized.set`.
- The report and input overrides are documented in this file.
- The matching copied `<report-name>.trades.csv` confirms TP1/TP2/TP3, max-hold, and block-event behavior.
- The evaluator returns `PASS` only when profit factor, drawdown, trade count, journal presence, and TP lifecycle checks all pass.

## Phase 5: Demo-Forward Candidate

Status: checklist implemented in `mt5/backtests/DEMO_FORWARD_CHECKLIST.md`; waiting for `scripts/evaluate-mt5-candidates.py` to show a `PASS` candidate.

Only after a candidate passes:

```text
Profit factor >= 1.20
Max equity drawdown <= 25%
No stale max-hold violations
No parity mode
No dependency on end-of-test forced close
```

Then run MT5 demo for at least 2 weeks.

Demo checklist:

- Compare fills against Strategy Tester assumptions.
- Confirm pending ladders are broker-native.
- Confirm daily loss stops new entries.
- Confirm daily target stops new entries.
- Confirm max open trades blocks new entries.
- Confirm max-hold closes positions.
- Confirm TP1/TP2/TP3 journal events.

## Immediate Next Validation

Compile and test the full implemented improvement suite next:

1. Compile in MetaEditor.
2. Run the default suite:

```bash
python3 scripts/run-mt5-improvement-suite.py
```
3. Read the generated comparison:

```bash
cat mt5/backtests/reports/improvement-evaluation.csv
```
4. If a candidate passes, apply it to the preset:

```bash
python3 scripts/apply-mt5-best-candidate.py
```
5. If none passes, test the top-ranked failed candidate manually or adjust the next matrix row:

```bash
python3 scripts/apply-mt5-best-candidate.py --allow-best-fail
```
