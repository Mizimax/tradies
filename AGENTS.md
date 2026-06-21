# Agent Notes

This repo is now primarily an MT5/MQL5 gold trading research project. Treat real MT5 Strategy Tester execution and demo-forward validation as the source of truth.

## Current Direction

- Main strategy: `GoldBot`, an MQL5 Expert Advisor for `XAUUSD`.
- Active experiment track: `GoldScalper`, a separate MT5 EA for scalping/dynamic allocation research.
- Primary path: `MQL5 Expert Advisor -> MT5 Terminal -> Broker`.
- Monthly infrastructure target: `0 USD`, excluding spread, commission, swap, and optional VPS.
- Real-mode MT5 backtests are official. Python parity is diagnostic-only.
- Old Cloudflare/OANDA/MetaApi/TypeScript work is archived under `legacy/cloudflare-worker/` for reference, not production.

Do not optimize toward the old Python/TypeScript simulator metrics. Real MT5 results differ because of spread, bid/ask, tick order, pending fills, broker contract settings, slippage, and position lifecycle behavior.

Keep `GoldBot` and `GoldScalper` changes separate. Do not mix strategy logic, candidate matrices, reports, or conclusions between them unless the user explicitly asks.

## Important Files

- `GOLD_BOT_PLAN_v2.md`: high-level product and architecture plan.
- `mt5/Experts/GoldBot/GoldBot.mq5`: main EA.
- `mt5/Include/GoldBot/Indicators.mqh`: indicator helpers.
- `mt5/Include/GoldBot/SMC.mqh`: SMC detection.
- `mt5/Include/GoldBot/Risk.mqh`: sizing and risk helpers.
- `mt5/Include/GoldBot/TradeManager.mqh`: trade lifecycle helpers.
- `mt5/Include/GoldBot/EntryFilters.mqh`: restored TypeScript-style entry filters.
- `mt5/Presets/GoldBot.optimized.set`: current working MT5 preset.
- `mt5/backtests/CANDIDATE_MATRIX.csv`: named candidate overrides.
- `mt5/backtests/NEXT_IMPROVEMENT_PLAN.md`: current research plan and evidence.
- `mt5/backtests/README.md`: MT5 compile/backtest workflow.
- `scripts/run-mt5-backtest.sh`: base Strategy Tester runner.
- `scripts/run-mt5-candidate.py`: run one normal candidate.
- `scripts/run-mt5-growth-candidate.py`: run one growth candidate and refresh per-candidate artifacts.
- `scripts/run-mt5-improvement-suite.py`: run candidate groups.
- `scripts/analyze-mt5-trades.py`: journal attribution.
- `scripts/daily-growth-report.py`: active-day and full-window daily growth metrics.
- `scripts/equity-curve-analysis.py`: drawdown and equity metrics.
- `scripts/rolling-stability-check.py`: monthly and rolling stability.
- `scripts/evaluate-mt5-candidates.py`: acceptance/evaluation CSVs.
- `mt5/Experts/GoldScalper/GoldScalper.mq5`: GoldScalper EA.
- `mt5/Include/GoldScalper/*.mqh`: GoldScalper modules, including regime detection and strategy modules.
- `mt5/Presets/GoldScalper.optimized.set`: GoldScalper tester preset.
- `mt5/backtests/GOLDSCALPER_CANDIDATES.csv`: GoldScalper candidate matrix. Keep every candidate on one CSV row with escaped `\n` overrides.
- `scripts/compile-mt5-goldscalper.sh`: command-line MetaEditor compile helper for GoldScalper.
- `scripts/run-goldscalper-candidate.py`: run one GoldScalper candidate and support report suffixes.

GoldScalper files are separate experiments. Do not mix GoldScalper changes into GoldBot commits unless the user asks.

## Default Workflow

### GoldBot

Install current source into the MT5 data folder:

```bash
bash scripts/install-mt5-source.sh
```

Compile GoldBot:

```bash
bash scripts/compile-mt5-goldbot.sh
```

If the helper cannot update `GoldBot.ex5`, open MetaEditor and compile `GoldBot.mq5` manually with `F7`. The required result is `0 errors`.

Run a real-mode baseline backtest:

```bash
MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 bash scripts/run-mt5-backtest.sh
```

Run one normal candidate:

```bash
python3 scripts/run-mt5-candidate.py tp-repair-score62-risk003
```

Run one growth candidate:

```bash
python3 scripts/run-mt5-growth-candidate.py growth-fasttp-hour12-only --clean
```

List candidates:

```bash
python3 scripts/run-mt5-candidate.py --list
python3 scripts/run-mt5-growth-candidate.py --list
```

Dry-run a candidate before launching MT5:

```bash
python3 scripts/run-mt5-growth-candidate.py growth-fasttp-hour12-only --dry-run
```

The MT5 runner blocks parallel tester processes by default. If another `terminal64.exe` or `metatester64.exe` is running, stop it first unless parallel MT5 testing is intentional. Use `--allow-parallel-mt5` only deliberately.

### GoldScalper

Compile GoldScalper:

```bash
bash scripts/compile-mt5-goldscalper.sh
```

Expected compile result is `0 errors`; current known warnings are global `trade` shadowing warnings in strategy modules. The compile helper installs source, checks include files, runs MetaEditor from the installed source directory, and verifies `GoldScalper.ex5` mtime changes.

List GoldScalper candidates:

```bash
python3 scripts/run-goldscalper-candidate.py --list
```

Dry-run before launching MT5:

```bash
python3 scripts/run-goldscalper-candidate.py dynamic-balanced --report-suffix 2024-2026 --dry-run
```

Run one GoldScalper candidate:

```bash
WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all \
python3 scripts/run-goldscalper-candidate.py dynamic-conservative \
  --from-date 2024.06.01 --to-date 2026.05.31 \
  --deposit 100000 --report-suffix 2024-2026
```

Use `--report-suffix` for windowed studies so bull and bear reports do not overwrite each other. Report names are `GoldScalper-<candidate>-<suffix>`.

Useful validation windows:

- Bull/gold uptrend: `2024.06.01` to `2026.05.31`, suffix `2024-2026`.
- Bear/choppy window: `2022.06.01` to `2024.05.31`, suffix `2022-2024`.

When Wine/MT5 is unstable, prefer single-candidate runs with `WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all`.

## Report Artifacts

Generated reports live in `mt5/backtests/reports/`.

Useful files:

- `<name>.htm`: MT5 Strategy Tester report.
- `<name>.trades.csv`: copied real-mode journal from `MQL5/Files/<ExpertDir>/trades.csv`.
- `<name>.summary.csv`: parsed MT5 report summary.
- `<name>.evaluation.csv`: candidate acceptance result.
- `<name>.daily-growth.csv`: active-day and full-window growth metrics.
- `<name>.equity-curve.csv`: drawdown/equity metrics.
- `<name>.stability.csv`: monthly/rolling stability.
- `<name>.attribution.csv`: PnL grouped by direction, hour, ladder split, exit reason, score bucket, confluence count, and combinations.
- `<name>.journal-summary.csv`: journal-derived summary.
- `<name>.report-status.csv`: present when the MT5 HTML report is missing or malformed but journal-only artifacts were recovered.

If an `.htm` report shows `Period: M0 (1970.01.01 - 1970.01.01)`, `Initial Deposit: 0`, or `Total Trades: 0` despite a real run, treat it as malformed. Use journal-only artifacts only as partial evidence and rerun when full metrics are needed.

## Analysis Commands

Summarize MT5 reports:

```bash
python3 scripts/summarize-mt5-reports.py mt5/backtests/reports/*.htm
```

Analyze journals:

```bash
python3 scripts/analyze-mt5-trades.py mt5/backtests/reports/*.trades.csv
```

Analyze one journal attribution:

```bash
python3 scripts/analyze-mt5-trades.py --attribution mt5/backtests/reports/GoldBot-real-growth-fasttp-hour12-only.trades.csv
```

Evaluate candidates:

```bash
python3 scripts/evaluate-mt5-candidates.py mt5/backtests/reports/*.htm
```

Refresh the improvement suite from existing reports:

```bash
python3 scripts/run-mt5-improvement-suite.py --skip-existing
```

Run growth-only suite:

```bash
python3 scripts/run-mt5-improvement-suite.py --growth-only
```

Prefer single-candidate runs when Wine/MT5 is unstable.

Summarize explicit GoldScalper validation reports:

```bash
python3 scripts/summarize-mt5-reports.py \
  mt5/backtests/reports/GoldScalper-mr-v3-2024-2026.htm \
  mt5/backtests/reports/GoldScalper-mr-v4-safe-2024-2026.htm \
  mt5/backtests/reports/GoldScalper-dynamic-balanced-2024-2026.htm \
  mt5/backtests/reports/GoldScalper-dynamic-conservative-2024-2026.htm \
  mt5/backtests/reports/GoldScalper-mr-v3-2022-2024.htm \
  mt5/backtests/reports/GoldScalper-mr-v4-safe-2022-2024.htm \
  mt5/backtests/reports/GoldScalper-dynamic-balanced-2022-2024.htm \
  mt5/backtests/reports/GoldScalper-dynamic-conservative-2022-2024.htm
```

## Verification Before Finishing Changes

Run these checks after script or candidate-matrix edits:

```bash
python3 -m py_compile scripts/run-mt5-candidate.py scripts/run-mt5-growth-candidate.py scripts/run-goldscalper-candidate.py scripts/run-mt5-improvement-suite.py scripts/daily-growth-report.py scripts/evaluate-mt5-candidates.py scripts/equity-curve-analysis.py scripts/rolling-stability-check.py scripts/analyze-mt5-trades.py scripts/summarize-mt5-reports.py
bash -n scripts/run-mt5-backtest.sh scripts/install-mt5-source.sh scripts/compile-mt5-goldbot.sh scripts/compile-mt5-goldscalper.sh
git diff --check
```

After MQL5 edits, the real compile gate is MetaEditor/MT5 with `0 errors`. Local shell syntax checks cannot prove MQL5 correctness.

GoldScalper candidate CSV check:

```bash
python3 - <<'PY'
import csv
from pathlib import Path

rows = list(csv.DictReader(Path("mt5/backtests/GOLDSCALPER_CANDIDATES.csv").open(newline="")))
required = {"mr-v3", "mr-v4-safe", "dynamic-balanced", "dynamic-conservative"}
errors = []
for i, row in enumerate(rows, start=2):
    if any(value is None for value in row.values()):
        errors.append(f"row {i}: None field")
    if row["name"].startswith("Inp"):
        errors.append(f"row {i}: candidate name starts with Inp")
missing = sorted(required - {row["name"] for row in rows})
if missing:
    errors.append(f"missing required candidates: {missing}")
if errors:
    raise SystemExit("\n".join(errors))
print(f"CSV validation passed: {len(rows)} rows")
PY
```

After installing source, compare GoldScalper installed files against repo before assuming MT5 is running current code:

```bash
scripts/install-mt5-source.sh >/tmp/install-mt5-source-verify.log
MT5_ROOT="${MT5_PREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}/drive_c/Program Files/MetaTrader 5"
cmp -s mt5/Experts/GoldScalper/GoldScalper.mq5 "$MT5_ROOT/MQL5/Experts/GoldScalper/GoldScalper.mq5"
for f in mt5/Include/GoldScalper/*.mqh; do cmp -s "$f" "$MT5_ROOT/MQL5/Include/GoldScalper/$(basename "$f")"; done
```

## Strategy Behavior To Preserve

Real mode should default to broker-native execution:

- `InpPythonParityMode=false`
- `InpLegacyParityMode=false`
- `InpDebugOnly=false`
- SMC gates plus confluence score
- 8 available indicator gates: EMA, RSI, VWAP, ATR, ADX/DI, MACD, Bollinger Bands, Stochastic
- Pending limit ladder via `CTrade`
- Magic number and symbol filtering for all order/position management
- Daily loss/target kill switch
- Cooldown
- Max open trades
- Max ladders per day
- Pending order expiry
- Max-hold close for filled positions
- TP1/TP2/TP3 lifecycle
- Optional breakeven at R
- Optional M5 pullback confirmation
- Optional manual news blackout
- Optional direction-conflict filter
- Optional HTF target-based TP2/TP3
- Optional SMC sequence/context filters
- Global and direction-specific entry-hour filters

Do not make parity mode the default. `MT5_PARITY=1` is only for old Python simulator diagnostics.

GoldScalper dynamic allocation behavior to preserve:

- Legacy/non-dynamic candidates should set `InpDynamicAllocation=false`.
- Dynamic candidates should set `InpDynamicAllocation=true`.
- Current dynamic gatekeeper inputs: `InpGatekeeperAdxPeriod=14`, `InpGatekeeperAdxLevel=25.0`.
- Dynamic gatekeeper intent: allow MR in range, allow breakout/momentum in trend.
- Do not change `GoldScalper.mq5` trading logic during compile/report/matrix-only tasks.
- Candidate matrix overrides must stay escaped as `\n` inside one CSV row per candidate.

## Research Lessons So Far

The old Python/TypeScript backtest looked much better because it was a simulator, not real broker execution. Do not chase exact old metrics.

Observed real-mode progression:

- Original honest real baseline overtraded and lost badly.
- TP lifecycle repair improved win rate and made TP2/TP3 meaningful, but PF stayed below acceptance.
- More indicators and stricter filters reduced trades but did not reliably improve PF.
- Direction/session quality helped more than adding filters.
- `smc-hours-7-12-15-17-19` reached roughly PF `0.94`, better than early repair candidates but still not demo-ready.
- Growth Layer 1 broad-frequency candidates had many trades but no edge:
  - `growth-open-fasttp`: about 296 trades, PF around `1.00`, near flat.
  - `growth-open-cooldown8`: about 308 trades, PF around `0.91`, losing.
- Full-ladder seed `growth-long-7-12-full` had better sample size than split-only seeds:
  - about 57 trades, PF around `1.14`, avg full-window daily growth far below the 3-5% research target.
- Fast-TP hour-12 isolation was very strong but too small:
  - `growth-fasttp-hour12-only`: about 14 trades, very high PF, low DD, but `TOO_SMALL`.
- In the fast-TP frequency restoration pass, hour 12 remained strong and hour 16 looked potentially useful; hours 15, 17, and 19 damaged the full long-only candidate.

Current likely next research direction:

- Test fast-TP hour `12+16` only.
- Compare full ladder, split `1+2`, and split `1` only.
- Optionally isolate hour `16` alone.
- Keep hour `7` out of fast-TP candidates unless a specific result justifies retesting it.
- Treat short hour `19` as suspicious until attribution proves it helps.

The daily growth goal of `3-5%` average per day is a research target, not a live deployment promise. Full-window daily growth is the official growth metric; active-day growth is only setup-quality diagnostics.

GoldScalper lessons from the dynamic allocation validation:

- `mr-v3` and `mr-v4-safe` were repaired from broken multiline CSV rows into valid escaped `\n` rows.
- `mr-v3-2024-2026` produced `0` trades after repair, so it is not evidence of profitability.
- `mr-v4-safe` MR-only remained negative in both windows.
- Dynamic allocation improved survival versus repaired MR-only candidates in both tested windows.
- `dynamic-balanced-2024-2026`: net `36774.12`, PF `1.14`, trades `247`, equity DD `36.44%`.
- `dynamic-conservative-2024-2026`: net `23282.92`, PF `1.18`, trades `247`, equity DD `20.83%`.
- `dynamic-balanced-2022-2024`: net `28979.04`, PF `1.07`, trades `425`, equity DD `45.72%`.
- `dynamic-conservative-2022-2024`: net `4551.85`, PF `1.02`, trades `425`, equity DD `33.19%`.
- Dynamic allocation is promising but not robust yet: PF is thin and drawdown is still high.
- Conservative dynamic allocation is safer by drawdown but gives up much of the return.
- Riskguard pass added filled-entry daily trade accounting, strategy attribution by position ID, global risk gates for Asian Breakout/MR/Momentum, pending-order cancellation on hard risk blocks, and DD-scaled risk for all strategies.
- Riskguard journal attribution reached `100%` for closed deals across the four validation reports, but all closed deals attributed to `breakout`; current dynamic settings are effectively breakout-only in these windows.
- `dynamic-riskguard-balanced-2024-2026`: net `15338.28`, PF `1.09`, trades `233`, equity DD `20.15%`.
- `dynamic-riskguard-conservative-2024-2026`: net `39883.45`, PF `1.34`, trades `230`, equity DD `10.52%`.
- `dynamic-riskguard-balanced-2022-2024`: net `-9318.37`, PF `0.87`, trades `116`, equity DD `20.22%`.
- `dynamic-riskguard-conservative-2022-2024`: net `-6272.97`, PF `0.95`, trades `286`, equity DD `20.13%`.
- Riskguard improved survival materially, especially in the bull window, but did not survive profitably across the 2022-2024 bear/choppy window.
- Next useful GoldScalper direction is breakout quality/regime filtering for the bear/choppy window, not re-expanding MR-only.

## Acceptance Gates

Use the gate that matches the current research phase.

General real-mode quality gate:

- PF `>= 1.20`
- Equity DD `<= 25%`
- Trades `150..450`
- TP2 and TP3 nonzero
- No Python parity mode
- Fresh report and journal

Max-PF discovery gate:

- PF `>= 1.20`
- Equity DD `<= 15%`
- Trades `>= 40`
- No Python parity mode

Growth research gate:

- Full-window average daily net growth positive
- PF `>= 1.20`
- Equity DD `<= 25%`
- Trades `>= 40`
- Positive active-day rate `>= 55%`

Strong growth research:

- Trades `>= 75`
- PF `>= 1.30`
- Full-window daily growth improves over the current seed
- No added hour has PF `< 1.00`

Still not demo-ready until trades are near `150+`, monthly stability is acceptable, and demo-forward confirms fills/drawdown.

## Common Problems

- Wine/MT5 sometimes emits `mmdevapi` assertion errors after a tester run. Check whether report/journal artifacts were still produced before rerunning.
- For repeated GoldScalper backtests on macOS Wine, prefix runs with `WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all` to avoid the observed `mmdevapi` assertion crash.
- MT5 can export a malformed blank report. Look for `report-status.csv` and journal-only artifacts.
- If `GoldBot.ex5 is older than the installed GoldBot source`, compile in MetaEditor or with `scripts/compile-mt5-goldbot.sh`.
- If GoldScalper include resolution fails, use `bash scripts/compile-mt5-goldscalper.sh` first; it compiles from the installed source directory and verifies include files under `MQL5/Include/GoldScalper`.
- If a candidate appears to have no trades, verify whether the report is stale, malformed, or from the wrong period.
- Use `--clean` when rerunning a candidate whose inputs changed.
- Do not run multiple MT5 tester jobs unless intentional.
- Do not commit MT5 config files with login/password/server details.
- Do not commit generated reports unless the user explicitly wants evidence snapshots.
- `scripts/compile-mt5-goldscalper.sh` stops running MT5/tester processes by default via `MT5_STOP_RUNNING=1`; use `MT5_STOP_RUNNING=0` only when you know no compile conflict exists.

## Git Hygiene

- Keep GoldBot changes separate from GoldScalper experiments.
- Commit source, scripts, candidate matrix, and docs together when they represent one coherent GoldBot change.
- Commit GoldScalper script/matrix/docs changes separately from GoldBot strategy changes when practical.
- Leave generated backtest outputs uncommitted unless requested.
- Be careful with dirty user files. Do not revert files you did not change.
- Update this `AGENTS.md` when a new MT5/Wine workflow or validated strategy lesson would save the next agent time.

## Good Skill Candidates

These repo workflows are reusable enough to become Codex skills:

- `mt5-wine-compile-backtest`: macOS Wine MT5 compile/backtest workflow, process cleanup, `mmdevapi` workaround, report-copy verification, and log decoding.
- `mt5-candidate-matrix-validation`: validate escaped-override CSV matrices, dry-run candidate commands, ensure report suffixes, and catch broken multiline rows.
- `mt5-report-evidence-review`: summarize MT5 `.htm` reports, detect malformed/blank reports, compare PF/DD/trades/win rate across windows, and write a short empirical conclusion.

Created personal skill: `~/.codex/skills/mt5-wine-compile-backtest`.

The strongest first skill is now `mt5-wine-compile-backtest` because it captures the most environment-specific knowledge and prevents the most expensive reruns.

Recent useful commit in this branch:

```text
2513151 Add GoldBot MT5 growth candidate tooling
```
