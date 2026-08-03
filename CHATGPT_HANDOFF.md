# GoldBot / FundingPips research handoff

Date: 2026-08-03  
Repository: `Mizimax/tradies`  
Scope: `GoldBot` on XAUUSD only (do not mix in `GoldScalper` work)

## The question

Find a **real MT5-tested** configuration for the FundingPips 2-Step challenge
(Phase 1: +8%, Phase 2: +5%, daily loss 5%, static max loss 10%) that can
finish in roughly 1--2 months without relying on raw risk scaling or a
single-window overfit.

The source of truth is MT5 Strategy Tester under the actual broker contract.
Python analysis is attribution/screening only.

## Current state

There is **no deployable fast FundingPips preset yet**. The current canonical
P1 risk remains 0.50%. Do not infer a recommendation to raise it from this
work.

The branch contains a substantial research harness:

- a deterministic six-segment stateful MT5 challenge-chain runner;
- immutable challenge-balance / daily and static-DD state carry;
- chain manifests that pin source, EX5, and preset hashes;
- real-deal stitching and fail-closed analysis;
- shadow-only telemetry for two falsified entry/exit ideas.

All added shadow mechanisms are default-off and tester-only. They neither
place, modify, cancel, nor reserve real orders.

## Verified benchmark evidence

Fresh stateful P1 controls ($50,000) reconcile exactly to their continuous
controls, which validates the chain runner:

| Window | Net | PF | Equity DD | Trades |
|---|---:|---:|---:|---:|
| 2025-01-01 to 2025-07-01 | +$3,466.51 (+6.93%) | 2.4447 | 2.42% | 50 |
| 2025-07-01 to 2026-01-01 | +$4,019.89 (+8.04%) | 1.9849 | 4.62% | 52 |

This is encouraging quality, but it is not evidence of a repeatable 1--2
month pass: the trade cadence is too sparse and uneven.

## Completed, falsified hypotheses

### 1. Scalp failure-to-progress exit (shadow only)

The H1/H2 2025 shadow chains were behavior-identical to controls. Corrected
results: 40 scalp positions, 23 actual negative full losses, only 2 triggers,
100% precision, 7.41% recall, and +$179.71 theoretical saving after costs.

It fails the predeclared minimum trigger and recall gates. H2 also has only 15
scalps, below the 20-position minimum. Do **not** tune its thresholds or make
the exit active.

Evidence: `mt5/backtests/PROPGUARD_FUNDINGPIPS_SPEED.md`.

### 2. Active continuation-pullback candidate

The frozen candidate changed only three flags (continuation enabled, long
hours `7;12;18`, shorts disabled) while keeping 0.50% risk. In H1 2025 its
result was exactly identical to control because all 13 opportunity bars were
blocked by the reused VWAP and M5 filters; it created zero fills. H2 was
correctly skipped.

Do **not** loosen its VWAP/M5/ADX/check-count/hour/risk values and rerun it.

### 3. Causal continuation shadow

The follow-up fixed the semantic defect above in telemetry only: trend-side
VWAP, directional DI, EMA, ADX 18, and actual M5 micro-ChoCH. H1 2025 showed
real virtual quality: 11 eligible episodes, 8 deployable, 6 virtual fills,
PF 2.3079, total net R 2.953, and conservative incremental +$800.11.

It nevertheless reached the overlay target on day 83, failing the frozen
maximum of 66 days. Per the plan, this falsifies the full continuation family;
H2 must not be used to tune or rescue it.

Evidence: `mt5/backtests/FUNDINGPIPS_NEXT_CAUSAL_SHADOW_PLAN_2026-08-02.md`
and generated CS1 manifests in `mt5/backtests/reports/` (ignored by git).

## Important correctness fixes included in this commit

- Prop `riskCash` now uses the broker cash-per-price-unit conversion; the
  legacy tick calculation could report absurd short R values.
- The chain runner uses state import/export from segment 2 onward, preserves
  the original $50k anchor, and checks source/EX5/preset hashes.
- Deal/trade/balance-point counts are separate; never call balance points
  “trades”.
- Failure-exit analysis treats an SL reason as a loss only if its net P&L is
  negative; profitable trailing stops were previously misclassified.
- Journal entries now include exact risk-cash and setup-metadata provenance.

## Constraints that should not be violated

1. Do not optimize raw risk or loosen global gates first. Past evidence says
   targeted negative-set trimming is safer, and the prop speed sweep does not
   validate a broadly safe faster multiplier.
2. Every proposed 6-month winner must pass a materially longer locked window;
   do not report a dollar P&L as a percent without dividing by deposit.
3. Keep MT5 work sequential. Wine/MT5 frequently fails under parallel tests.
4. Keep `InpPythonParityMode=false`, `InpLegacyParityMode=false`, and do not
   promote telemetry-only inputs to active trading without their gates.
5. Reports are generated/ignored evidence; do not commit them. Never commit
   broker login, password, or server details.

## Best next discussion / research decision

The three recent families have been retired without changing live entry logic.
Before implementing another mechanism, answer this causal question from the
existing journals:

> Is the 1--2 month target feasible at the accepted risk and DD envelope given
> the empirical setup cadence, or must the objective explicitly trade off
> speed, risk, or strategy diversification?

If pursuing another experiment, it must be genuinely independent of the
retired failure-exit and continuation families. Define its mechanism and
falsification gates *before* a new MT5 run, use H1/H2 2025 as consumed train
windows, then validate untouched 2024/2026 windows. A useful candidate should
increase expected daily return through a distinct positive-expectancy trade
set or safely remove a distinct negative set; merely admitting more blocked
continuations is not acceptable.

## Useful files and commands

- Main EA: `mt5/Experts/GoldBot/GoldBot.mq5`
- Prop state helpers: `mt5/Include/GoldBot/PropMode.mqh`
- Risk/trade lifecycle: `mt5/Include/GoldBot/TradeManager.mqh`
- Chain runner: `scripts/run-mt5-fundingpips-chain.py`
- Journal analyzers: `scripts/analyze-mt5-trades.py`,
  `scripts/summarize-mt5-reports.py`
- Research log: `mt5/backtests/PROPGUARD_FUNDINGPIPS_SPEED.md`
- Latest causal plan: `mt5/backtests/FUNDINGPIPS_NEXT_CAUSAL_SHADOW_PLAN_2026-08-02.md`
- Candidate/run matrix: `mt5/backtests/FUNDINGPIPS_CONTINUATION_RUN_MATRIX.csv`

Compile and source-install are documented in `AGENTS.md` and
`mt5/backtests/README.md`. The real compile gate is MetaEditor with **0
errors**; current expected warnings are eight existing `TradeManager` shadow
warnings.

## Verification already performed for this worktree

- MetaEditor compile: 0 errors, 8 pre-existing warnings.
- Python/unit tests across the incremental implementations: latest full
  discovery reported 125 passing tests; causal-shadow focused tests reported
  44 passing tests.
- Python compilation, shell syntax checks, and `git diff --check` passed at
  implementation time.

Use fresh MT5 reports/manifests rather than older files with similar names.
