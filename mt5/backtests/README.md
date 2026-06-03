# MT5 Real-Mode Strategy Tester Guide

Use MT5 Strategy Tester real broker execution as the source of truth for this EA.

## Install And Compile

Install the current repo copy into the MT5 data folder:

```bash
bash scripts/install-mt5-source.sh
```

Compile `GoldBot.mq5` in MetaEditor. The helper can try command-line compile and verifies whether `GoldBot.ex5` changed:

```bash
bash scripts/compile-mt5-goldbot.sh
```

If command-line compile does not update `GoldBot.ex5`, open MetaEditor and press `F7` / Compile manually. The EA must compile with `0 errors`.

## Real-Mode Backtest

Default mode is real broker execution:

```bash
MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 bash scripts/run-mt5-backtest.sh
```

Current Phase 2/3 candidate defaults are saved in `mt5/Presets/GoldBot.optimized.set`:

```text
InpScoreThreshold=62.5
InpMinRealModeScore=62.5
InpLotPer100Usd=0.003
InpCooldownBars=24
InpMaxOpenTrades=1
InpMaxLaddersPerDay=2
InpTp1R=1.5
InpTp2R=2.0
InpTp3R=3.0
InpTrailAfterTp1=true
InpResetJournalOnInit=true
InpMinRealConfluences=5
InpRequireDirectionalAdx=true
InpRequireEmaTrend=false
InpUseMacdConfluence=true
InpUseBollingerConfluence=true
InpUseStochasticConfluence=true
InpRequireM5PullbackConfirmation=true
InpPullbackConfirmChecks=2
InpEnableNewsFilter=false
InpBlockIndicatorDirectionConflicts=true
InpUseExtendedDirectionConflict=true
InpUseHtfTargetsForTp2Tp3=true
InpRequireNearZoneBeforeLadder=true
InpNearZoneBuffer=0.5
InpRequireSmcSequence=false
InpRequireLiquiditySweepForSmc=false
InpRequireDisplacementForSmc=false
InpRequireObFvgOverlap=false
InpRequireHtfSmcContext=false
InpAllowedEntryHours=
InpAllowedLongEntryHours=
InpAllowedShortEntryHours=
InpLadderFirstSplit=1
```

The helper installs current source, checks that `GoldBot.ex5` is newer than installed `.mq5/.mqh` files, writes a temporary tester config under `mt5/backtests/config/`, launches MT5 with `/config`, and copies generated reports back to `mt5/backtests/reports/`. It also copies the latest real-mode `trades.csv` journal to `mt5/backtests/reports/<report-name>.trades.csv`.

Useful overrides:

```bash
MT5_SYMBOL=GOLD MT5_FROM=2025.01.01 MT5_TO=2025.12.31 bash scripts/run-mt5-backtest.sh
MT5_LOGIN=12345678 MT5_SERVER="Broker-Demo" MT5_PASSWORD="password" bash scripts/run-mt5-backtest.sh
```

Do not commit generated config files; they may contain account details.

## Real-Mode Outputs

Check these artifacts after each run:

- Fresh MT5 HTML/XML report under `mt5/backtests/reports/`
- Real execution journal copied beside the report as `<report-name>.trades.csv`
- Pending order success/failure entries in `trades.csv`
- Gate/skip logs in the MT5 tester journal
- SMC candidate entries showing H4/H1/M15 gate state and score
- Real-mode block reasons for higher-timeframe confirmation, SMC sequence, allowed entry hour, session window, and daily ladder limit
- Old TypeScript filter restoration events: M5 pullback confirmation, near-zone placement, direction-conflict blocks, optional news blocks, and HTF TP target selection
- Signal skip entries with the effective real-mode score threshold

Real-mode acceptance is based on Strategy Tester reports, broker-style order behavior, and `trades.csv`. `parity_trades.csv` is not a real-mode acceptance artifact.

## Optional Parity Diagnostic

Python parity mode is disabled by default. Use it only when intentionally debugging the old Python simulator:

```bash
MT5_PARITY=1 MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 bash scripts/run-mt5-backtest.sh
python3 scripts/compare-mt5-python-parity.py --from-date 2023-10-01 --to-date 2025-09-30 --diff-trades --diff-signals
```

`MT5_PARITY=1` sets `InpPythonParityMode=true` and injects `InpPythonParityStart` from `MT5_FROM`. Without `MT5_PARITY=1`, the run script forces real mode.

## Optimization

Optimize real-mode behavior first with broker-realistic spread, commission, contract size, and tick data. Start with:

- `InpRsiLongMax`
- `InpRsiShortMin`
- `InpAdxMin`
- `InpSlAtr`
- `InpMinRR`
- `InpMaxHoldBars`
- `InpCooldownBars`
- `InpTp1R`
- `InpTp2R`
- `InpTp3R`
- `InpTrailAfterTp1`
- `InpMinRealConfluences`
- `InpRequireDirectionalAdx`
- `InpRequireEmaTrend`
- `InpUseMacdConfluence`
- `InpUseBollingerConfluence`
- `InpUseStochasticConfluence`
- `InpRequireM5PullbackConfirmation`
- `InpPullbackConfirmChecks`
- `InpBlockIndicatorDirectionConflicts`
- `InpUseExtendedDirectionConflict`
- `InpUseHtfTargetsForTp2Tp3`
- `InpRequireNearZoneBeforeLadder`
- `InpNearZoneBuffer`
- `InpRequireSmcSequence`
- `InpRequireLiquiditySweepForSmc`
- `InpRequireDisplacementForSmc`
- `InpRequireObFvgOverlap`
- `InpRequireHtfSmcContext`
- `InpAllowedEntryHours`
- `InpAllowedLongEntryHours`
- `InpAllowedShortEntryHours`
- `InpLadderFirstSplit`

Keep daily loss, daily target, max open trades, and magic number fixed during initial optimization.

The current evidence-based improvement plan is in `mt5/backtests/NEXT_IMPROVEMENT_PLAN.md`.

Compare reports after each candidate run:

```bash
python3 scripts/summarize-mt5-reports.py mt5/backtests/reports/*.htm
```

Compare real-mode journals after each candidate run:

```bash
python3 scripts/analyze-mt5-trades.py mt5/backtests/reports/*.trades.csv
```

Print the next Phase 2/3 candidate commands from the matrix:

```bash
python3 scripts/print-mt5-candidate-commands.py
python3 scripts/run-mt5-candidate.py pf-long-hours-7-12-16-ladder2only
```

Run the implemented improvement suite and produce comparison CSVs:

```bash
python3 scripts/run-mt5-improvement-suite.py
cat mt5/backtests/reports/improvement-evaluation.csv
```

The default suite now starts with Max-PF direction/session discovery candidates, then keeps the TP-repair baseline, research-backed SMC/hour candidates, long-only/short-only direction isolation, ladder-count reduction, breakeven protection, faster TP levels, 4-of-8 quality candidates, 5-of-8 quality candidates, TS-lite candidates, and TS-complete candidates. This round uses a discovery gate of PF `>=1.20`, equity DD `<=15%`, and at least `40` trades.

For loss attribution after running a candidate:

```bash
python3 scripts/analyze-mt5-trades.py --attribution mt5/backtests/reports/GoldBot-real-pf-long-hours-7-12-16-ladder2only.trades.csv
```

When candidate inputs change, remove stale reports for the selected candidates before rerunning:

```bash
python3 scripts/run-mt5-improvement-suite.py --clean
```

If the evaluation has a `PASS` row, apply the top-ranked passing candidate to the MT5 preset:

```bash
python3 scripts/apply-mt5-best-candidate.py
```

For planning only, print the suite commands without launching MT5:

```bash
python3 scripts/run-mt5-improvement-suite.py --dry-run
```

List or run a single candidate by name:

```bash
python3 scripts/run-mt5-candidate.py --list
python3 scripts/run-mt5-candidate.py tp-repair-score62-risk003
```

Run a single growth candidate with the growth test window and per-candidate growth reports:

```bash
python3 scripts/run-mt5-growth-candidate.py --list
python3 scripts/run-mt5-growth-candidate.py growth-open-fasttp
```

Run the full-ladder Layer 2 growth scaling candidates one by one:

```bash
python3 scripts/run-mt5-growth-candidate.py growth-full-risk006
python3 scripts/run-mt5-growth-candidate.py growth-full-risk010
python3 scripts/run-mt5-growth-candidate.py growth-full-risk015
python3 scripts/run-mt5-growth-candidate.py growth-full-risk010-cooldown12
python3 scripts/run-mt5-growth-candidate.py growth-full-risk010-fasttp
```

Check `growth-full-risk010` before running `growth-full-risk015`; skip `risk015` if `risk010` has DD over `20%` or PF below `1.10`.

Run the hour-12 fast-TP isolation candidates one by one:

```bash
python3 scripts/run-mt5-growth-candidate.py growth-fasttp-hour12-only
python3 scripts/run-mt5-growth-candidate.py growth-fasttp-hour12-split1
python3 scripts/run-mt5-growth-candidate.py growth-fasttp-hour12-split12
```

Run the fast-TP frequency restoration candidates one by one. These keep hour `7` excluded and use full-window daily growth as the primary growth metric:

```bash
python3 scripts/run-mt5-growth-candidate.py growth-fasttp-hours12-15-16-19-full --clean
python3 scripts/run-mt5-growth-candidate.py growth-fasttp-hours12-15-16-19-split12 --clean
python3 scripts/run-mt5-growth-candidate.py growth-fasttp-hours12-15-16-17-19-full --clean
python3 scripts/run-mt5-growth-candidate.py growth-fasttp-hours12-15-16-17-19-split12 --clean
python3 scripts/run-mt5-growth-candidate.py growth-fasttp-dir-long12-15-16-short19-full --clean
python3 scripts/run-mt5-growth-candidate.py growth-fasttp-dir-long12-15-16-short19-split12 --clean
```

If another MT5 tester or terminal is intentionally running, add `--allow-parallel-mt5`; otherwise stop the other run first.

Evaluate reports against the improvement gate:

```bash
python3 scripts/evaluate-mt5-candidates.py mt5/backtests/reports/*.htm
```

The evaluator prints a leaderboard sorted by pass status, profit factor, drawdown, and net profit. It returns exit code `0` when at least one candidate passes and `2` when reports were readable but no candidate passed.

## Demo Forward Test

Before live money:

- Run on an MT5 demo account for at least 2 weeks.
- Compare demo fills, skipped signals, drawdown, and trade frequency against Strategy Tester.
- Confirm daily loss and daily target block new entries.
- Confirm max open trades blocks new signals.
- Confirm pending ladder expiry.
- Confirm filled positions close after max hold bars.
- Confirm TP1/TP2/TP3 journal transitions.

Use `mt5/backtests/DEMO_FORWARD_CHECKLIST.md` for the detailed daily checklist and pass/fail criteria.
