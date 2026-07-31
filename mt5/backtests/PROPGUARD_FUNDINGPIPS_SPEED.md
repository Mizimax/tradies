# FundingPips 2-Step Speed Study

## Corrected verdict (2026-07-31, post-sizing-fix)

**Still effectively NO-GO at the current 0.50% preset, with one knife-edge exception.**
The `## Verdict` / `## Full sweep` sections below this one are the **original, now-stale**
study — every report they were computed from had two sizing bugs, since fixed:

1. `InpPropMonitorOnly=true` disabled `GoldBotPropCostAndSizingGate`/`GoldBotPropRawLot`
   entirely, so trades fell through to the notional, stop-distance-independent sizer
   (`mt5/Include/GoldBot/Risk.mqh:41`). Fixed by setting `InpPropMonitorOnly=false` in both
   `prop-fundingpips-2step.set` and `prop-fundingpips-2step-phase2.set`.
2. Even with monitor-only off, GoldBot's ladder/setup-multiplier plumbing
   (`GoldBotSplitLot`'s fixed ~0.33 per-leg weight, plus `InpScalpLotMultiplier` /
   `InpM1MicroLotMultiplier` / `GoldBotSetupRiskMultiplier`) multiplied the already
   risk-correct prop lot a second time, silently compressing realized per-trade risk to as
   little as ~0.04-0.09% of equity for m1_micro_scalp/m5_scalp trades instead of the
   intended 0.50%. Fixed in `mt5/Experts/GoldBot/GoldBot.mq5` (divide the setup multiplier
   back out of `effectiveLotPer100Usd` before the ladder call, at all three ladder call
   sites) and a new "Realized risk check" self-check journal line was added in
   `mt5/Include/GoldBot/TradeManager.mqh` so this class of bug is visible in the journal
   going forward without a manual audit.

Both fixes are orthogonal to entry/regime logic (nothing about signal generation changed).
All 5 base reports (`GoldBot-prop-ftmo-p1-{25000,50000}-{6m,1y[,2y]}`) were regenerated
against the fixed `.ex5` and re-swept with the same methodology as the original study
(`--bootstrap-reps 5000 --seed 7`).

**Bottom line:** at the current preset value (`InpPropChallengeRiskPct=0.50`, multiplier
1.0x), the sweep still fails the rolling-start P(pass)>=0.55 gate on 4 of 5 report/window
combinations -- same *qualitative* conclusion as the original study (0.50% is too slow to
reliably clear Phase 1+2 within the rolling-start horizon), though the *magnitude* differs
now that the underlying sizing is real. The two 6-month windows (both deposits) additionally
show an alarming bootstrap DD-breach probability of 85-98% even at the current 0.50%
baseline -- this is **not** a sizing artifact, it reflects a real negative-edge stretch in
H1 2026 (see Caveat 3 below); it is the actual thing worth investigating next, not risk%.

One single combination clears all four frozen-gate criteria: **$25k/2y at 1.5x multiplier
(0.75% implied risk)** -- rolling P(pass)=55.00% (landing exactly on the >=0.55 threshold,
not comfortably above it), rolling DD breach=0%, bootstrap P(pass)=96.86%, bootstrap DD
breach=3.14%. This is reported as a data point, not a recommendation: it is a single
(deposit, window, multiplier) cell out of 25 tested, sitting exactly on the pass/fail
boundary. `PROPGUARD_DESIGN.md`'s own plateau-requirement convention (>= 80% of
perturbed-parameter neighbours must still pass, §2) exists precisely to reject grid-edge
optima like this one -- it has not been re-tested at 1.4x/1.6x or on any other window, so
treat it as "worth another look with a wider bootstrap / neighbouring multipliers," not as
grounds to ship a `0.75%` preset.

### Full corrected sweep (25 rows: 5 reports x 5 multipliers)

| Report | Mult | Input risk | R pass | R DD breach | B pass | B DD breach | Gate |
|---|---:|---:|---:|---:|---:|---:|---|
| $25k/6m | 1.0x | 0.50% | 0.0000 | 0.0000 | 0.0142 | 0.9858 | fail (R pass, B DD) |
| $25k/6m | 1.5x | 0.75% | 0.0000 | 0.0000 | 0.0534 | 0.9466 | fail |
| $25k/6m | 2.0x | 1.00% | 0.0000 | 0.0000 | 0.0918 | 0.9082 | fail |
| $25k/6m | 2.5x | 1.25% | 0.0000 | 0.0556 | 0.1230 | 0.8770 | fail |
| $25k/6m | 3.0x | 1.50% | 0.0000 | 0.1667 | 0.1476 | 0.8524 | fail |
| $25k/1y | 1.0x | 0.50% | 0.0000 | 0.0000 | 0.9870 | 0.0130 | fail (R pass) |
| $25k/1y | 1.5x | 0.75% | 0.1628 | 0.0000 | 0.9364 | 0.0636 | fail (R pass, B DD) |
| $25k/1y | 2.0x | 1.00% | 0.3721 | 0.0000 | 0.8698 | 0.1302 | fail |
| $25k/1y | 2.5x | 1.25% | 0.4651 | 0.0000 | 0.8046 | 0.1954 | fail |
| $25k/1y | 3.0x | 1.50% | 0.5116 | 0.0698 | 0.7326 | 0.2674 | fail |
| $25k/2y | 1.0x | 0.50% | 0.2938 | 0.0000 | 0.9948 | 0.0052 | fail (R pass) |
| **$25k/2y** | **1.5x** | **0.75%** | **0.5500** | **0.0000** | **0.9686** | **0.0314** | **PASS (knife-edge)** |
| $25k/2y | 2.0x | 1.00% | 0.6625 | 0.0000 | 0.9100 | 0.0900 | fail (B DD) |
| $25k/2y | 2.5x | 1.25% | 0.7125 | 0.0000 | 0.8588 | 0.1412 | fail (B DD) |
| $25k/2y | 3.0x | 1.50% | 0.7375 | 0.0375 | 0.8100 | 0.1900 | fail (B DD) |
| $50k/6m | 1.0x | 0.50% | 0.0000 | 0.0000 | 0.0168 | 0.9832 | fail |
| $50k/6m | 1.5x | 0.75% | 0.0000 | 0.0000 | 0.0622 | 0.9378 | fail |
| $50k/6m | 2.0x | 1.00% | 0.0000 | 0.0000 | 0.1044 | 0.8956 | fail |
| $50k/6m | 2.5x | 1.25% | 0.0000 | 0.0556 | 0.1352 | 0.8648 | fail |
| $50k/6m | 3.0x | 1.50% | 0.0000 | 0.1667 | 0.1558 | 0.8442 | fail |
| $50k/1y | 1.0x | 0.50% | 0.0000 | 0.0000 | 0.9892 | 0.0108 | fail (R pass) |
| $50k/1y | 1.5x | 0.75% | 0.1628 | 0.0000 | 0.9472 | 0.0528 | fail (B DD marginally) |
| $50k/1y | 2.0x | 1.00% | 0.3953 | 0.0000 | 0.8838 | 0.1162 | fail |
| $50k/1y | 2.5x | 1.25% | 0.4651 | 0.0000 | 0.8198 | 0.1802 | fail |
| $50k/1y | 3.0x | 1.50% | 0.5116 | 0.0465 | 0.7520 | 0.2480 | fail (R pass) |

Machine-readable: `mt5/backtests/reports/GoldBot-fundingpips-speed-sweep-multifix.csv`.

### Caveats specific to this correction

1. **`goldbot-prop-simulate.py`'s documented min-lot optimism bias still applies** (see
   PROPGUARD_GOLDBOT_SIM.md §3/§8 and the script's own docstring): `GoldBotNormalizeLot`
   floors small raw lots up to the broker minimum, so any trade whose SL-aware target lot
   sits near that floor realizes *higher* actual risk than its r_multiple implies. Flagged
   again here per the standing instruction to note it wherever this study's numbers are
   quoted.
2. **`$25k/2y` required a workaround and is a synthetic chain, not one continuous MT5 run.**
   Three consecutive attempts at a single continuous 2024.07.01-2026.06.30 tester run hit an
   identical, reproducible failure: `Tester: automatic testing started` -> ~16 minutes of
   real progress -> `Network: connection to FundingPips-Trial lost` -> `last test passed
   with result "some error after pass finished"` -> blank M0/1970 report. This is a genuine
   mid-run broker/demo-session disconnect (not the documented local port-3000-collision
   pattern, which fails within seconds of test start, not after 16 minutes of real
   progress), and is not resolved by killing stray processes or freeing port 3000 -- both
   were confirmed clean before each retry. Per the workaround, the window was split into two
   continuous ~1-year runs (2024.07.01-2025.06.30 and 2025.07.01-2026.06.30, the latter
   identical to and reused from the `$25k/1y` report) that each completed cleanly, and their
   `.propguard-sim.csv` r_multiple sequences were concatenated in chronological order into
   `GoldBot-prop-ftmo-p1-25000-2y.propguard-sim.csv` for the sweep. This is a reasonable
   approximation (GoldBot's SL-aware prop sizing targets a fixed *percentage* risk per
   trade, so each segment's r_multiple sequence is already close to equity-scale-invariant
   independent of the other segment's compounding path -- the same assumption the original
   5-report study already relied on to combine evidence across non-continuous windows), but
   it is not identical to one continuous backtest and should be re-verified with a real
   continuous run if the environment issue is ever resolved.
3. **The 6-month windows' bootstrap DD-breach rate (85-98%) is a real finding, not a sizing
   bug.** Both `$25k/6m` and `$50k/6m` cover 2026.01.01-2026.06.30 and show a small net
   *loss* at the current 0.50% preset (net -$182.47 / PF 0.97 at $25k... see the GoldBot
   verification run `GoldBot-prop-ftmo-p1-25000-6m-multifix`; -$368.83 / PF 0.91 at $50k).
   Bootstrap-resampling a negative-drift 6-month sample into full-length synthetic challenge
   paths concentrates that bad luck, producing near-certain DD breach. This is evidence the
   strategy's edge is not uniformly positive across recent history, not an artifact of the
   sizing fix -- consistent with this doc's original "improve or gate the negative-expectancy
   trade set first" recommendation below, now with a concrete recent window to point at.
4. **A separate, unrelated bug in `goldbot-prop-simulate.py` itself was found and fixed
   during this correction**: the adapter only summed `profit+commission+swap` over closing
   ("out") deals, silently dropping commission charged on the *opening* ("in") deal -- real
   on this repo's FundingPips/FTMO demo accounts, which charge round-trip commission
   entirely at entry. Fixed by folding each entry deal's cost into the very next closing
   deal (exact, since these presets all set `InpPropMaxOpenAndPending=1` -- never more than
   one position open at a time). Verified this improves (does not regress) reconciliation on
   the original 6 PROPGUARD_GOLDBOT_SIM.md sample reports, which now reconcile to 0.000%
   instead of their previously-documented ~0.1-0.3%.

## Original verdict (pre-fix, superseded -- monitor-only + ladder-undersized reports)

**NO-GO.** None of the tested risk multipliers clears the frozen G3/G4 gates on the
verified real prop-mode evidence. There is therefore no winning multiplier, no
`prop-fundingpips-2step-fast.set` preset, and no real-MT5 confirmation run. Step 3 was
intentionally skipped because its prerequisite was not met.

The closest result by rolling-start pass probability is the 3.0x multiplier
(`InpPropChallengeRiskPct=1.50`) on the $25k/2y report, but it reaches only 18.37% rolling
P(pass), far below the required 55%. Its bootstrap max-DD breach probability is 13.92%,
also far above the allowed 5%. Increasing risk produced faster paths but did not produce a
fast **and** safe configuration.

## Method (historical, pre-fix)

Five existing real MT5 prop-mode reports at `InpPropChallengeRiskPct=0.50` were adapted to
PropGuard-shaped journals. The adapter now uses each closing deal's full net P&L:

```text
net deal P&L = profit + commission + swap
```

This fixed a 2y reconciliation discrepancy: the missing amount was exactly `-7.18` of swap.
All five reports now reconcile to their MT5 summary net profit to the cent.

Because each adapter `r_multiple` is actually the already-realized fractional account return,
the simulator's `challenge_risk_pct=100` replays the source 0.50% report as-is. Values
150/200/250/300 apply 1.5x/2x/2.5x/3x to that return sequence and correspond to proposed
GoldBot inputs 0.75%/1.00%/1.25%/1.50%.

Each combination used:

- Firm: `fundingpips-2step` (8% P1, 5% P2, 5% daily loss, 10% static max DD)
- Rolling-start deterministic estimator (primary)
- 5,000 block-bootstrap paths, 10 trading-day blocks, seed 7 (secondary)
- Frozen gate: P(pass) >= 0.55 in both estimators, daily breach < 0.01, max-DD breach < 0.05

## Full sweep (historical, pre-fix)

`R pass/daily/DD/cens` are rolling probabilities. `B pass/daily/DD` are bootstrap
probabilities. Days are trading days to complete P1 and P2; `--` means no rolling path
passed before the historical sample ended.

| Deposit/window | Mult | Input risk | R pass | R daily | R DD | R cens | R mean days | R median days | B pass | B daily | B DD | B mean days | B median days |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| $25k/6m | 1.0x | 0.50% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 106.0 | 105 |
| $25k/6m | 1.5x | 0.75% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 71.3 | 71 |
| $25k/6m | 2.0x | 1.00% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 53.8 | 53 |
| $25k/6m | 2.5x | 1.25% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 43.3 | 43 |
| $25k/6m | 3.0x | 1.50% | 0.1250 | 0 | 0 | 0.8750 | 35.8 | 36 | 1.0000 | 0 | 0 | 36.4 | 36 |
| $25k/1y | 1.0x | 0.50% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 224.9 | 216 |
| $25k/1y | 1.5x | 0.75% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 152.3 | 144 |
| $25k/1y | 2.0x | 1.00% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 115.6 | 108 |
| $25k/1y | 2.5x | 1.25% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 93.4 | 85 |
| $25k/1y | 3.0x | 1.50% | 0.1558 | 0 | 0 | 0.8442 | 44.6 | 38.5 | 0.9998 | 0 | 0.0002 | 79.0 | 71 |
| $25k/2y | 1.0x | 0.50% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 0.9992 | 0 | 0.0008 | 845.8 | 755 |
| $25k/2y | 1.5x | 0.75% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 0.9824 | 0 | 0.0176 | 558.2 | 474.5 |
| $25k/2y | 2.0x | 1.00% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 0.9458 | 0 | 0.0542 | 400.6 | 336 |
| $25k/2y | 2.5x | 1.25% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 0.9046 | 0 | 0.0954 | 302.7 | 248 |
| $25k/2y | 3.0x | 1.50% | 0.1837 | 0 | 0 | 0.8163 | 60.9 | 67 | 0.8608 | 0 | 0.1392 | 235.9 | 193 |
| $50k/6m | 1.0x | 0.50% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 119.3 | 118 |
| $50k/6m | 1.5x | 0.75% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 80.1 | 79 |
| $50k/6m | 2.0x | 1.00% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 60.4 | 60 |
| $50k/6m | 2.5x | 1.25% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 48.6 | 48 |
| $50k/6m | 3.0x | 1.50% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 40.7 | 40 |
| $50k/1y | 1.0x | 0.50% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 256.6 | 248 |
| $50k/1y | 1.5x | 0.75% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 173.0 | 165 |
| $50k/1y | 2.0x | 1.00% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 130.8 | 122 |
| $50k/1y | 2.5x | 1.25% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 105.6 | 98 |
| $50k/1y | 3.0x | 1.50% | 0.0000 | 0 | 0 | 1.0000 | -- | -- | 1.0000 | 0 | 0 | 88.8 | 81 |

The machine-readable table is in
`mt5/backtests/reports/GoldBot-fundingpips-speed-sweep.csv`.

## Interpretation (historical, pre-fix)

The short windows look excellent under bootstrap because repeatedly resampling their favorable
blocks eventually reaches both targets. Rolling-start asks the stricter question: whether the
actual remaining historical sequence from each possible start reaches P1 and P2 before the
evidence ends. Nearly all paths are censored. This is not counted as a pass under the frozen
gate.

On the more important 2y evidence, bootstrap shows the speed/safety trade-off directly:

| Input risk | Bootstrap P(pass) | Bootstrap P(DD breach) | Median days P1+P2 | Gate result |
|---:|---:|---:|---:|---|
| 0.50% | 99.92% | 0.08% | 755 | Fail rolling P(pass) |
| 0.75% | 98.24% | 1.76% | 474.5 | Fail rolling P(pass) |
| 1.00% | 94.58% | 5.42% | 336 | Fail rolling and DD |
| 1.25% | 90.46% | 9.54% | 248 | Fail rolling and DD |
| 1.50% | 86.08% | 13.92% | 193 | Fail rolling and DD |

No proposed value can be recommended as a validated fast setting. The existing 0.50% preset
should remain unchanged for research continuity, but it is **not** promoted by this study as a
challenge-ready configuration.

## Time-limit constraint

The local `fundingpips-2step` firm model contains no hard time-limit field, consistent with the
prior design study's assumption of no limit. A live-rule verification was attempted on
2026-07-28, but FundingPips' official site returned a Vercel Security Checkpoint instead of its
rule content. Therefore the current live time-limit rule is **not verified** here and must be
checked in the FundingPips dashboard/rulebook immediately before purchasing a challenge.

## Reproducibility and next useful experiment

Run:

```bash
python3 scripts/goldbot-prop-simulate.py \
  mt5/backtests/reports/GoldBot-prop-ftmo-p1-25000-{6m,1y,2y}.htm \
  mt5/backtests/reports/GoldBot-prop-ftmo-p1-50000-{6m,1y}.htm
python3 scripts/fundingpips-speed-sweep.py \
  --bootstrap-reps 5000 --seed 7 \
  --output mt5/backtests/reports/GoldBot-fundingpips-speed-sweep.csv
```

The next useful strategy experiment is not another global risk increase. Improve or gate the
negative-expectancy trade set first, then repeat this exact sweep. That follows the repository's
validated lesson that targeted trimming has been more robust than global risk scaling.
