# GoldBot FundingPips next experiment: causal continuation shadow

Date: 2026-08-02  
Status: plan only; no source edit and no MT5 run in this planning step

## Decision

The frozen `continuation-core` candidate is **falsified at C1 H1** and is retired.
Do not run its H2 row, loosen one of its gates, or select a nearby preset.

A bounded, telemetry-only causal shadow is warranted before abandoning the
zone-less opportunity family.  An active ablation is not warranted yet, and a
new trading mechanism is not justified until the shadow proves that a coherent
continuation rule has both enough deployable opportunities and positive forward
outcomes in each 2025 train half.

This is a diagnostic experiment, not a second tuning pass on
`continuation-core`.  It must never place, modify, cancel, or reserve an order.

## What C1 actually proved

Fresh stateful H1 artifacts:

- control: `GoldBot-fundingpips-continuation-c1-h1-2025-control.manifest.json`
- candidate: `GoldBot-fundingpips-continuation-c1-h1-2025-candidate.manifest.json`
- EX5 SHA-256 for both:
  `5b1271c6e65a15a2be85f9771c543ddc702e6bc65b52b302ad7c5838474cce15`

The candidate and control are exactly behavior-equivalent:

| Metric | Control | Candidate |
|---|---:|---:|
| Net | +$3,466.51 / +6.9330% of $50,000 | +$3,466.51 / +6.9330% |
| PF | 2.444692 | 2.444692 |
| Stitched equity DD | 2.422627% | 2.422627% |
| MT5 trades | 50 | 50 |
| Deals | 79 | 79 |

The candidate saw 13 high-score, zone-less bars across 10 sessions and accepted
zero.  Every one of the 13 logged `vwap=no`, every one logged exactly
`m5Checks=1 required=2`, and two also missed continuation ADX 18.  The earlier
H2 control/shadow journals contain 17 corresponding high-score, zone-less bars,
and all 17 also log `vwap=no`.  H2 was therefore correctly skipped after the H1
gate failure.

The result does **not** estimate continuation expectancy.  It proves that the
frozen gate cannot expose the already-counted opportunity set.

## Causal defect to test, not tune around

Two reused predicates do not express the claimed mechanism:

1. `IndicatorSnapshot.vwapLong` is defined as M15 price below session VWAP and
   near/below its lower band; `vwapShort` is the inverse.  Those are
   mean-reversion predicates.  `GoldBotContinuationSetupPass` reused them as a
   required continuation gate, although a long continuation should be tested on
   the trend side of VWAP before a pullback order is staged.
2. `GoldBotPullbackConfirmed` reports one aggregate count.  Its candle and RSI
   checks use M15 data; only `microChoCH` uses M5 data.  The 13 H1 records do not
   reveal which one check passed, so changing `required=2` to `1` would be a
   blind relaxation.

Therefore the next experiment must expose raw components and future outcomes.
It must not set `InpContinuationRequireVwap=false`, reduce
`InpContinuationPullbackChecks`, change ADX/DI/EMA, change hours, or change
risk/SL/TP in response to C1.

## Primary minimal falsifiable experiment: CS1

### Frozen shadow universe

Observe exactly the bars that reach the existing no-zone branch:

- score `>=` the effective canonical threshold;
- no valid FVG/OB entry zone;
- canonical direction and canonical SMC hours (`long=7;12;18`, `short=99`);
- no parity mode;
- one immutable probe ID per `(M15 bar open time, direction)`.

The old continuation setup stays disabled.  The shadow evaluates one
predeclared causal rule, not a grid:

```text
ADX:              adx >= 18.0
directional DI:   long: plusDI-minusDI >= 4.0
                  short: minusDI-plusDI >= 4.0
EMA:              existing direction-specific emaPass
trend-side VWAP:  long: last closed M15 close > session VWAP
                  short: last closed M15 close < session VWAP
M5 confirmation:  existing microChoCH component is true
zone:             existing EMA21/VWAP continuation zone is valid
```

This rule corrects predicate meaning; it does not merely disable VWAP or accept
one of three mixed-timeframe checks.  No threshold or alternate rule may be
selected after seeing CS1.

### Exact inputs

Add only these tester-safe inputs, inert by default:

```text
InpEnableContinuationCausalShadow=false
InpContinuationCausalShadowHorizonBars=32
```

Create `GoldBot/prop-fundingpips-2step-continuation-causal-shadow.set` as the
canonical P1 preset plus only:

```text
InpEnableContinuationCausalShadow=true
InpContinuationCausalShadowHorizonBars=32
```

All causal thresholds come from the frozen rule above and existing canonical
inputs.  Do not expose them as candidate knobs.  In particular:

```text
InpEnableContinuationPullbackSetup=false
InpPropChallengeRiskPct=0.50
InpSlAtr=0.90
InpTp1R=1.65
InpTp2R=2.0
InpTp3R=2.0
InpLadderOrderCount=2
InpLadderFirstSplit=1
InpMaxHoldBars=32
InpPropMaxOpenAndPending=1
```

remain unchanged.

### Required telemetry

Emit one `Continuation causal shadow candidate` record per probe with:

- probe ID, time, direction, hour, score/threshold and confluences;
- M15 close, H1 close, EMA21/50/200, session VWAP, ATR, ADX, plusDI and
  minusDI;
- signed VWAP distance in ATR, signed directional DI gap;
- legacy `vwapPass`, trend-side VWAP pass, EMA pass, valid-zone flag and zone
  bounds;
- the three pullback components separately:
  `candlePatternM15`, `rsiShiftM15`, `microChoCHM5`, plus the legacy aggregate;
- `slotFreeAtSignal`, `causalEligible`, and the exact failed causal reasons.

Maintain a shadow-only virtual probe state which cannot touch `CTrade` or any
live/real metadata.  Use real tester ticks and the canonical mechanics:

- two virtual rungs at the same direction-specific zone top/midpoint used by
  splits 1 and 2;
- the exact canonical SL calculation;
- pending expiry 32 M15 bars from signal;
- after fill, observation horizon 32 M15 bars from fill;
- tick-ordered first touch of SL or TP1 `+1.65R`, with MFE-R and MAE-R retained;
- spread and `$7/lot` round-trip commission included in net R using the same
  broker cash conversion as prop sizing.

Only one virtual causal probe may be classified `deployable` at a time, and it
must have `slotFreeAtSignal=yes`.  Later probes while that virtual exposure is
open are still logged but classified `overlapSuppressed`.  Log any canonical
base signal/order that occurs during a deployable virtual exposure as
`wouldDisplaceBase`, including that base position's eventual realized net.

Emit one `Continuation causal shadow final` record per probe and rung with:

- eligible/deployable/suppressed state and reasons;
- virtual entry, fill timestamp or expiry, SL, risk distance and modeled risk
  cash;
- first-barrier reason/time, MFE-R, MAE-R, gross R, spread/commission R and net
  R;
- overlapping base signal ID/setup and realized base net when present.

The analyzer must fail closed on a missing final record, duplicate probe ID,
non-flat virtual state at a segment boundary, missing costs, or missing base
displacement attribution.  Virtual probe state must be exported/imported by the
stateful chain so a month boundary does not change its outcome.

### Analyzer outputs

Add a dedicated causal-shadow study, by full half and month:

- universe bars and distinct sessions;
- causal eligible, deployable, overlap-suppressed and virtual fills;
- failure counts for ADX, directional DI, EMA, trend-side VWAP, M5 ChoCH, zone
  and slot;
- rung and probe-level net, gross profit/loss, PF, win rate, average/median net
  R, MFE-R and MAE-R;
- displaced-base net and conservative incremental net
  `virtual net - positive displaced-base net`;
- counterfactual target timestamp/days using only deployable outcomes and the
  displacement deduction;
- exact control/shadow deal-signature parity, breaches, report validity and
  chain/state integrity.

The counterfactual overlay is a screening estimate only.  It cannot promote a
strategy without a later real MT5 active-candidate run.

### Minimal implementation surface

- `mt5/Experts/GoldBot/GoldBot.mq5`: add the two inert inputs, observe the
  existing no-zone branch, maintain shadow probes, and emit candidate/final
  records.  Do not alter the existing continuation decision or any order path.
- `mt5/Include/GoldBot/EntryFilters.mqh`: only if needed, expose the three
  already-computed pullback booleans to the observer; do not change their
  definitions.
- `mt5/Include/GoldBot/PropMode.mqh` and the tester-chain state schema: persist
  incomplete virtual probes across segments.  State import must fail closed
  when shadow mode requires a missing/corrupt probe record.
- `scripts/analyze-mt5-trades.py`: add a separate causal-shadow mode and the
  strict completeness/parity/displacement checks above.  Do not fold virtual
  outcomes into real trade attribution.
- `mt5/Presets/GoldBot/prop-fundingpips-2step-continuation-causal-shadow.set`:
  exact canonical copy plus the two declared shadow values.
- Replace the retired C1 execution matrix with a new CS1 matrix containing only
  the four sequential train chains and analyses.  Keep 2024/2026 rows absent
  until CS1 and CS2 earn them.
- Add focused tests for default-off behavior, exact preset diff, probe
  deduplication, segment-state round trip, conservative bid/ask barrier order,
  cost conversion, displacement deduction, missing-final fail-close, and exact
  real-deal parity.

## CS1 real-MT5 train sequence

After focused tests, install and compile with MetaEditor `0 errors`.  Terra light
runs one chain at a time with
`WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all`:

1. fresh current-EX5 control, `2025.01.01--2025.07.01`;
2. causal shadow, same H1 window;
3. fresh current-EX5 control, `2025.07.01--2026.01.01`;
4. causal shadow, same H2 window.

Run both train halves even if the first half has poor signal outcomes; these are
already-consumed train windows and the second half distinguishes a structural
failure from one regime.  Stop immediately only for instrumentation, chain, or
firm-safety invalidity.

### Integrity gate

Before looking at shadow expectancy, each control/shadow pair must have:

- identical source/EX5 hashes within the pair, no input difference outside the
  declared shadow namespace, and only `InpEnableContinuationCausalShadow` has a
  non-default effective value;
- identical real deal signatures, net, PF, DD, trade count and target-lock
  timestamp;
- six valid flat segments, immutable $50,000 challenge anchor, no malformed
  report and no daily/static/internal-floor breach.

Any mismatch means the shadow implementation is invalid.  Repair telemetry only
and rerun both members of the affected pair; do not interpret outcomes.

### Frozen train gate

The causal family may proceed to an active implementation only if **each half
independently** has all of:

- at least 6 causal-eligible distinct probe episodes;
- at least 5 deployable virtual fills and at least 3 fills in the first 44
  observed weekdays;
- probe-level net PF `>=1.30`, total net R `>0`, average net R `>0`, and
  conservative incremental net after displacement `>0`;
- no single probe contributes more than 60% of that half's positive gross R;
- the conservative overlay reaches 8.02% within 66 observed weekdays in both
  halves, and within 44 weekdays in at least one half;
- no shadow safety or integrity abort.

These density gates are load-bearing: a profitable two-trade anecdote cannot
support a one-to-two-month completion claim.

### Exact falsification outcomes

The causal continuation hypothesis is falsified if either half has:

- fewer than 6 eligible episodes or fewer than 5 deployable fills;
- fewer than 3 fills by weekday 44;
- PF below 1.30, non-positive total/average net R, or non-positive conservative
  incremental net;
- target overlay later than weekday 66 or no target;
- one-probe profit concentration above 60%; or
- any unexplained base displacement, missing telemetry, non-flat state, report
  invalidity, or firm/internal breach.

Do not respond by changing `18`, `4`, the VWAP relation, M5 ChoCH, 32 bars,
hours, zone ATR, ladder entries, risk, SL or TP.  Do not test a `microChoCH=false`
sibling or revive `requiredChecks=1`.  Failure means this opportunity family is
closed and the next planner must propose an entirely new mechanism from fresh
cross-window evidence.

## CS2 active confirmation, only after CS1 passes

Sol high may then implement one active causal-continuation branch using exactly
the CS1 eligibility rule and canonical order/sizing/lifecycle paths.  The active
P1 preset may differ from the canonical P1 preset only by enabling that branch;
the old continuation branch remains disabled.

Run fresh current-source control and active candidate on both 2025 halves.  Each
half must have at least 5 real causal-continuation fills, causal PF `>=1.30`,
causal net and average net R `>0`, whole-window PF `>=1.30`, stitched DD
`<=5.5%`, no breach, and candidate net no worse than control by more than $125.
It must reach 8.02% within 66 observed weekdays in both halves and within 44 in
at least one.  More than one unexplained missing base position is an abort.

Failure kills the mechanism.  Do not tune the active rule against the difference
between virtual and real outcomes.

## Locked holdouts and Phase 2

Only after CS2 passes, freeze source, EX5 and preset hashes before opening:

1. `2024.01.01--2024.07.01`;
2. `2024.07.01--2025.01.01`;
3. stress `2026.01.01--2026.07.01`.

For each, run a fresh control once and the frozen active candidate once.  Require
causal PF `>=1.20` and causal net `>0` with at least 5 fills, whole-window PF
`>=1.20`, DD `<=6%`, no breach, and regression no worse than $125.  P1 must reach
8.02% within 44 observed weekdays in at least two of three windows, including a
2024 half, with completed-window median `<=44` days.

Only then derive P2 by changing the canonical target to 5% and enabling the same
single branch.  On the same locked windows require 5.02% within 44 days on at
least two of three including a 2024 half, PF `>=1.20`, DD `<=6%`, and no breach.
Then run the previously defined 1.5x-spread and 5,000-replicate distribution
gates at fixed 0.50% risk before any trial-forward recommendation.

## Global stop rules

- Never run MT5 jobs in parallel.
- Never use H2/holdout results to alter a threshold or select a sibling.
- Abort on equity DD above 7.5%, any firm-rule breach, stale/malformed evidence,
  chain reconciliation failure, source/preset drift or non-flat state.
- The previous failure-exit, raw-risk, concurrency, M5-long, ATR/regime and hour
  grid directions remain closed.
- The requested one-to-two-month result is still unproven until real P1 and P2,
  locked holdouts, spread stress, distribution checks and trial forward all
  pass.
