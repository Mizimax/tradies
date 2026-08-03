# GoldBot FundingPips next experiment: frozen continuation recovery

Date: 2026-08-02  
Status: implemented and compile/test verified; fresh C1 MT5 controls/candidates not yet run

## Decision

Stop the scalp failure-to-progress direction.  Do not change its checkpoint,
MFE-R, current-R, sample-size, or acceptance thresholds.  Keep its code inert and
do not create an active failure-exit preset.

The next single mechanism is the existing **continuation pullback setup**, enabled
with its already-implemented quality checks and the canonical SMC hours.  This is
an entry-opportunity recovery experiment, not another loss-exit threshold, global
risk increase, concurrency change, hour search, or regime filter.

The hypothesis is:

> A high-score SMC candidate that has no valid FVG/OB entry zone can still be a
> valid continuation entry when direction, EMA, VWAP, ADX/DI, and a two-check M5
> pullback all re-confirm it.  These opportunities occur before the baseline's
> late profit clusters, so a positive continuation cohort can improve time to
> target rather than merely increase end-of-window profit.

The rule is frozen before running a candidate.  If it fails either 2025 train
half, do not tune it on those results.

## Evidence and baseline

The corrected stateful controls are the only baseline for this experiment:

| Window | Net | Net % of $50k | PF | Stitched equity DD | MT5 trades | P1 target |
|---|---:|---:|---:|---:|---:|---|
| 2025-01-01--2025-07-01 | +$3,466.51 | +6.9330% | 2.4447 | 2.4226% | 50 | not reached in 129 weekdays |
| 2025-07-01--2026-01-01 | +$4,019.89 | +8.0398% | 1.9849 | 4.6200% | 52 | reached 2025-12-31, weekday 132 |

Artifacts:

- `GoldBot-fundingpips-p1-h1-2025-control.manifest.json`
- `GoldBot-fundingpips-p1-h2-2025-control.manifest.json`

Both use EX5 SHA-256
`459de14116987531968ef0241adeabe7a88904e9ed19b462f2a4c90c16ed25f6`.

The control journals contain a cross-window supply of high-score, zone-less SMC
candidates before the main profit clusters:

| Window | Exact candidate bars | Distinct sessions | Where they occur |
|---|---:|---:|---|
| H1 2025 | 13 | 10 | Jan, Feb, Mar, Jun |
| H2 2025 | 17 | 10 | Jul, Aug, Sep |

Each counted bar has `score >= threshold`, `zone=no`, and
`continuation=disabled`; all are long candidates under this preset.  They are
opportunity evidence, not outcome evidence.  The continuation quality checks
must still accept them and real MT5 must establish expectancy.

Why this is preferable to setup-risk scaling now: replaying the existing deals
with a hypothetical 1.5x structural multiplier still reaches 8% only around
2025-04-25 in H1 and 2025-12-26 in H2.  That cannot demonstrate the requested
one-to-two-month completion.  More size does not repair the long stretches with
too few entries.

## Frozen candidate

Create `mt5/Presets/GoldBot/prop-fundingpips-2step-continuation-core.set` as an
exact copy of the canonical P1 preset with only these effective differences:

```text
InpEnableContinuationPullbackSetup=true
InpContinuationLongHours=7;12;18
InpContinuationShortHours=99
```

The following continuation values already exist in the canonical preset and
must remain unchanged:

```text
InpContinuationMinAdx=18.0
InpContinuationMinDiGap=4.0
InpContinuationRequireVwap=true
InpContinuationRequireEma=true
InpContinuationRequireM5Pullback=true
InpContinuationPullbackChecks=2
InpContinuationZoneAtr=0.35
```

`7;12;18` is copied from `InpSmcAllowedLongHours`; `99` preserves the canonical
disabled SMC-short side.  It is not selected from an hour grid.  Do not enable
the global `InpRequireM5PullbackConfirmation`, change base risk from 0.50%, alter
setup multipliers, allow concurrent prop positions, or change any other entry,
exit, target, or governor input.

The continuation setup must continue to use the same prop sizing path, one
open-or-pending cap, static $50,000 firm floor, 8% P1 target, and target lock.

## Minimal implementation

### 1. Candidate integrity

- Generate the P1 candidate by copying the canonical preset and applying only
  the three frozen differences above.
- Add a preset-diff test which fails if any other effective input differs.
- Extend the chain runner's manifest with the candidate preset SHA-256 if it is
  not already recorded.  Existing source/EX5/input hashes and flat-state checks
  remain mandatory.
- Do not change `GoldBot.mq5` trading logic.  The continuation branch and its
  quality gates already exist at `GoldBotContinuationSetupPass`.

### 2. Evidence extraction

Extend `scripts/analyze-mt5-trades.py` with a continuation-study output for a
chain manifest.  It must report, by whole window and calendar month:

- high-score zone-less candidate bars;
- `Continuation setup accepted` and each blocked reason;
- filled continuation positions and closing deals;
- continuation net, gross profit/loss, PF, win rate, and average net R;
- base-setup trades displaced by slot contention;
- first `Prop phase target lock reached` timestamp and elapsed observed trading
  days from the manifest start;
- daily-loss, static-floor, internal-floor, malformed-report, and non-flat-state
  flags.

Use `setup=continuation` from position/deal metadata as the attribution key.
Fail closed if accepted continuation orders lose that metadata.  Do not infer a
continuation fill merely from a nearby SMC log line.

### 3. Verification before MT5

Sol high runs the focused Python tests, `py_compile`, preset-diff test,
`git diff --check`, installs source, and compiles with MetaEditor `0 errors`.
There is no reason to change MQL5 for this experiment; if an attribution defect
forces a logging-only MQL5 edit, recompile and regenerate both candidate chains.

## Real-MT5 sequence and gates

Terra light runs one chain at a time with
`WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all` and remains quiet while MT5 runs.
Never run candidates in parallel.

### Stage C1: two frozen train runs

Run the P1 continuation candidate with the qualified stateful harness on:

1. Train A: `2025.01.01--2025.07.01`
2. Train B: `2025.07.01--2026.01.01`

Use the existing controls above; do not rerun them unless source/EX5 or a
load-bearing input changes.

The mechanism passes C1 only if **each half independently** satisfies all of:

- at least 5 filled continuation positions and at least 8 accepted continuation
  candidates;
- continuation PF `>= 1.30`, continuation net `> 0`, and average net R `> 0`;
- whole-window PF `>= 1.30` and candidate net no worse than control by more than
  $125 (0.25 percentage point);
- stitched equity DD `<= 5.5%` and no daily/static/internal-floor breach;
- no more than one missing base position after accounting for target-lock
  truncation; and
- P1 reaches the 8% target plus lock buffer in both halves, with at least one
  half reaching it within 44 observed trading days and the other within 66.

The 44/66-day gate prevents promoting a merely profitable addition that does not
materially address speed.  A target-lock run is compared by target day, not by
post-target net, because the EA correctly stops after completion.

If either half fails, mark continuation recovery **falsified**.  Do not change
ADX, DI gap, VWAP/EMA requirements, pullback checks, zone ATR, hours, TP/SL, or
risk in response.  Return accepted/blocked/fill/outcome telemetry to the next
planner.

### Stage C2: locked validation

Only after C1 passes, freeze the preset and source hashes.  Run one fresh control
and then the frozen candidate once on each untouched validation half:

1. `2024.01.01--2024.07.01`
2. `2024.07.01--2025.01.01`
3. stress: `2026.01.01--2026.07.01`

Do not inspect a candidate result and then change the preset.  Any change sends
the experiment back to C1 and permanently consumes these windows as holdouts.

C2 passes only if:

- continuation PF `>= 1.20` and continuation net `> 0` in every half with at
  least 5 fills;
- whole-window PF `>= 1.20`, stitched equity DD `<= 6.0%`, no breach, and no
  half regresses versus its fresh control by more than $125;
- P1 reaches target within 44 observed trading days in at least two of the three
  windows, including at least one 2024 locked half; and
- the median P1 completion among completed validation windows is `<= 44` days.

Failure kills the candidate; do not select a looser continuation sibling from
validation results.

### Stage C3: Phase 2, spread, and distribution

Only after C2 passes:

1. Derive `prop-fundingpips-2step-phase2-continuation-core.set` from the canonical
   P2 preset with the same three differences and `InpPropPhaseTargetPct=5.0`.
2. Run P2 on the same three locked validation halves.  Require target plus lock
   buffer within 44 observed trading days on at least two of three, including a
   2024 half; PF `>=1.20`, DD `<=6%`, and no breach.
3. Run frozen P1 and P2 at 1.5x the control median spread.  Require the same
   two-of-three speed result, PF `>=1.20`, DD `<=6%`, and no breach.
4. Regenerate PropGuard-shaped sequences from the stateful candidate chains and
   run `scripts/fundingpips-speed-sweep.py --bootstrap-reps 5000 --seed 7` only
   at the actual fixed 0.50% risk.  Require rolling and bootstrap P(pass)
   `>=55%`, daily-breach `<1%`, and max-DD breach `<5%`.
5. Only then install the P1/P2 candidate on a FundingPips trial and reconcile EA
   floors/targets with the dashboard for five trading days before any paid use.

## Global aborts

Abort and reject on any firm-rule breach, equity DD above 7.5%, malformed or
stale report used as evidence, chain reconciliation failure, missing continuation
metadata, changed control behavior, or any holdout regression beyond the frozen
limits.

The requested one-to-two-month result remains unproven until both P1 and P2 pass
the speed/safety/distribution gates.  A good continuation PF by itself is not
completion evidence.

## Rollback

If falsified, remove only the two unpromoted continuation candidate presets and
any candidate-only matrix row.  Keep generic analyzer support, stateful-chain
fixes, `riskCash` correction, and inert failure-exit telemetry.  Canonical P1/P2
presets and live/demo defaults remain unchanged throughout this experiment.
