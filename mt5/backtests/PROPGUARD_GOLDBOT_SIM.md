# GoldBot Prop-Firm Pass Simulation (go/no-go gate, no EA code touched)

Purpose: before building any prop-mode risk controls into GoldBot, check whether scaling
down GoldBot's own position sizing (candidate `daily2-ai-s5-slwide-smcnorm`, PF ~3.2, win
~65% on the 2y window) could plausibly pass an FTMO/FundingPips/The5ers-style challenge, in
an idealized Monte-Carlo replay of its own historical trade sequence. This is a simulation
gate, not a real forward test -- see the caveats in §5.

## 1. Method

1. `scripts/goldbot-prop-simulate.py` (new) reads a GoldBot MT5 Strategy Tester `.htm`
   report, reuses `equity-curve-analysis.py::extract_deals`/`decode_report` to get the
   ordered closing deals (`direction == "out"`), and walks them chronologically starting
   from the report's own stated Initial Deposit to reconstruct the account equity
   immediately before each trade opened.
2. Per trade: `r_multiple = profit / equity_at_entry`. This is the trade's own percentage
   return on the account, i.e. GoldBot's *own* backtested risk-taking at $1000 deposit,
   expressed scale-invariantly.
3. Rows are written in the exact column shape of `PropGuardResetJournal` /
   `PropGuardJournalTrade` (`mt5/Include/PropGuard/Telemetry.mqh`) so
   `prop-challenge-simulator.py::load_closed_trades` (which reads `event`, `r_multiple`,
   `timestamp`, `engine`) accepts the CSV unmodified. Sibling file:
   `<report-stem>.propguard-sim.csv`.
4. Reconciliation: sum of extracted closing-deal profits vs. the report's own `net_profit`
   (dollars, from the sibling `.summary.csv`, reusing
   `analyze-drawdown-attribution.py::official_net_profit`) must agree within 0.5%. The
   script prints PASS/FAIL per report to stderr and exits nonzero (aborting CSV emission
   for that report) on failure -- see §2, all 6 reports passed.

## 2. Reconciliation check (all 6 source reports)

| Report (stem, `.htm`) | Deposit | Trades | Extracted profit | Report net_profit | Diff | Diff % | Status |
|---|---|---|---|---|---|---|---|
| `GoldBot-real-daily2-ai-s5-slwide-smcnorm-ai-s5-6m` | 1000.00 | 130 | 3636.32 | 3632.00 | 4.32 | 0.119% | PASS |
| `GoldBot-real-daily2-ai-s5-slwide-smcnorm-ai-s5-1y` | 1000.00 | 239 | 5558.88 | 5549.29 | 9.59 | 0.173% | PASS |
| `GoldBot-real-daily2-ai-s5-slwide-smcnorm-ai-s5-2y` | 1000.00 | 394 | 5572.73 | 5558.35 | 14.38 | 0.259% | PASS |
| `GoldBot-real-scalp-adaptive-daily2-monthlock25-ai-s1-6m-1000` | 1000.00 | 124 | 3234.69 | 3230.19 | 4.50 | 0.139% | PASS |
| `GoldBot-real-scalp-adaptive-daily2-monthlock25-ai-s1-1y-1000` | 1000.00 | 226 | 3888.73 | 3880.22 | 8.51 | 0.219% | PASS |
| `GoldBot-real-scalp-adaptive-daily2-monthlock25-ai-s1-2y-1000` | 1000.00 | 383 | 3870.78 | 3859.28 | 11.50 | 0.298% | PASS |

All 6 reconcile within tolerance. `daily2-monthlock25`'s exact baseline stems were confirmed
against `mt5/backtests/FORWARD_DEMO_S3.md` §"Conservative reference", which explicitly names
the stem pattern `GoldBot-real-scalp-adaptive-daily2-monthlock25-ai-s1-<window>-1000` (the
"ai-s1" suffix is FORWARD_DEMO_S3.md's own label for the "unmodified `@scalp-adaptive-daily2-monthlock25`
base" -- there is no report literally stemmed `...monthlock25-6m` on disk).

**Tolerance discrepancy note:** the task brief specified "0.5%, matching the tolerance
already used in `analyze-drawdown-attribution.py`" -- but that script's actual reconciliation
check uses `abs(diff_pct) <= 1.0 or abs(diff) < 1.0` (1%, or $1), not 0.5%. This adapter
implements the stricter 0.5% figure as explicitly specified. It happens not to matter here:
all 6 reports pass at 0.5% anyway (worst case 0.298%).

## 3. Scale-invariance of GoldBot's own lot sizing -- verified, with a caveat

`GoldBotSplitLot` (`mt5/Include/GoldBot/Risk.mqh`):

```
total = (equity / 100.0) * lotPer100Usd;
if (score >= highConvictionScore) total *= 1.5;
return GoldBotNormalizeLot(symbol, total * weight, minLot, maxLot);
```

`total` is linear in `equity` -- confirms the task's assumption that GoldBot's own sizing is
equity-proportional, so `r_multiple = profit/equity_at_entry` is a legitimate scale-invariant
per-trade return **in principle**.

**Caveat found:** `GoldBotNormalizeLot` clamps the raw lot to `[max(minLot, brokerMin),
min(maxLot, brokerMax)]` before rounding to the broker's volume step:

```
double clamped = MathMax(low, MathMin(rawLot, high));
```

At the $1000 deposit these 6 reports were backtested at, GoldBot's computed lot per split is
frequently at or near this min-lot floor (small equity -> small raw lot). That means the
recorded `r_multiple` sequence already embeds some floor-inflated risk relative to a purely
linear formula. When this simulation re-scales that same r_multiple sequence down by a small
`k` (large 1/k) to emulate cautious prop-firm sizing, it implicitly assumes a fractional-of
-min-lot position that a real broker cannot place -- the real lot would be floored back up to
`minLot`, meaning **actual realized risk at small k on a real account would be higher than
this simulation's k implies**, not lower. This is a one-directional optimism bias that gets
worse, not better, as k shrinks (i.e. it is most concerning at the k=1/6, k=1/8 rows in §4).
It is not corrected in this simulation and should be confirmed with a real re-run (proper lot
sizing against a $25k-$200k account, not a rescaled r-multiple) before committing capital to a
real challenge fee. Flagged again in §6.

## 4. Risk-scaling mapping (k -> `--challenge-risk-pct`)

From `prop-challenge-simulator.py`'s own replay step (`simulate_from`):
`equity = equity * (1.0 + (risk_pct/100.0) * r)`.

Since `r_multiple` here is already GoldBot's own as-backtested per-trade return (i.e. `k=1`
should exactly reproduce the original backtest's compounding), the correct mapping is:

```
challenge_risk_pct = 100.0 * k
```

(`funded_risk_pct` was set to `challenge_risk_pct / 2` for every run, mirroring the
simulator's own default 1.0/0.5 ratio -- but note it has **no effect on any of the P(pass)
metrics reported here**: `simulate_from` returns `PASS` immediately on the P2->FUNDED
transition, before any funded-phase day is simulated, so `funded_risk_pct` only matters for
the separate `funded_survived_horizon` metric this report does not use.)

k values swept: `{1, 1/2, 1/3, 1/4, 1/6, 1/8}` -> `challenge_risk_pct` = `{100%, 50%, 33.3%,
25%, 16.7%, 12.5%}`.

## 5. Full results table (2 candidates x 3 windows x 6 k x 4 firms = 144 combos)

Both `--method rolling` (primary) and `--method bootstrap` (secondary, reps=2000,
block_days=10, seed=1234) were run for every combo; `--method parametric` was also run (see
§6 for its per-report e/v, which do not vary by k or firm -- see note above table).

| Candidate | Window | k | risk% | Firm | Rolling P(pass) | Rolling P(pass\|resolved) | Rolling P(daily breach) | Rolling P(DD breach) | Boot P(pass) | Boot P(DD breach) | Rolling median days-to-pass |
|---|---|---|---|---|---|---|---|---|---|---|---|
| daily2-ai-s5-slwide-smcnorm | 6m | 1.0000 | 100.0% | ftmo-2step | 0.767 | 0.917 | 0.070 | 0.000 | 0.915 | 0.000 | 5 |
| daily2-ai-s5-slwide-smcnorm | 6m | 1.0000 | 100.0% | fundingpips-2step | 0.791 | 0.944 | 0.047 | 0.000 | 0.951 | 0.000 | 4 |
| daily2-ai-s5-slwide-smcnorm | 6m | 1.0000 | 100.0% | the5ers-highstakes | 0.767 | 0.917 | 0.070 | 0.000 | 0.915 | 0.000 | 5 |
| daily2-ai-s5-slwide-smcnorm | 6m | 1.0000 | 100.0% | the5ers-hypergrowth | 0.744 | 0.842 | 0.140 | 0.000 | 0.847 | 0.000 | 4 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.5000 | 50.0% | ftmo-2step | 0.721 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 8 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.5000 | 50.0% | fundingpips-2step | 0.744 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 8 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.5000 | 50.0% | the5ers-highstakes | 0.721 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 8 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.5000 | 50.0% | the5ers-hypergrowth | 0.767 | 0.971 | 0.023 | 0.000 | 0.981 | 0.000 | 6 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.3333 | 33.3% | ftmo-2step | 0.581 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 12 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.3333 | 33.3% | fundingpips-2step | 0.674 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 11 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.3333 | 33.3% | the5ers-highstakes | 0.581 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 12 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.3333 | 33.3% | the5ers-hypergrowth | 0.721 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 8 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.2500 | 25.0% | ftmo-2step | 0.419 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 13 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.2500 | 25.0% | fundingpips-2step | 0.558 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 16 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.2500 | 25.0% | the5ers-highstakes | 0.419 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 13 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.2500 | 25.0% | the5ers-hypergrowth | 0.651 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 12 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.1667 | 16.7% | ftmo-2step | 0.326 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 18 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.1667 | 16.7% | fundingpips-2step | 0.372 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 18 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.1667 | 16.7% | the5ers-highstakes | 0.326 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 18 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.1667 | 16.7% | the5ers-hypergrowth | 0.419 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 15 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.1250 | 12.5% | ftmo-2step | 0.186 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 24 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.1250 | 12.5% | fundingpips-2step | 0.233 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 18 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.1250 | 12.5% | the5ers-highstakes | 0.186 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 24 |
| daily2-ai-s5-slwide-smcnorm | 6m | 0.1250 | 12.5% | the5ers-hypergrowth | 0.372 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 20 |
| daily2-ai-s5-slwide-smcnorm | 1y | 1.0000 | 100.0% | ftmo-2step | 0.723 | 0.789 | 0.072 | 0.120 | 0.762 | 0.134 | 6 |
| daily2-ai-s5-slwide-smcnorm | 1y | 1.0000 | 100.0% | fundingpips-2step | 0.723 | 0.789 | 0.072 | 0.120 | 0.765 | 0.139 | 6 |
| daily2-ai-s5-slwide-smcnorm | 1y | 1.0000 | 100.0% | the5ers-highstakes | 0.723 | 0.789 | 0.072 | 0.120 | 0.762 | 0.134 | 6 |
| daily2-ai-s5-slwide-smcnorm | 1y | 1.0000 | 100.0% | the5ers-hypergrowth | 0.639 | 0.679 | 0.193 | 0.108 | 0.656 | 0.115 | 5 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.5000 | 50.0% | ftmo-2step | 0.843 | 0.986 | 0.000 | 0.012 | 0.968 | 0.033 | 12 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.5000 | 50.0% | fundingpips-2step | 0.855 | 0.986 | 0.000 | 0.012 | 0.967 | 0.034 | 11 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.5000 | 50.0% | the5ers-highstakes | 0.843 | 0.986 | 0.000 | 0.012 | 0.968 | 0.033 | 12 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.5000 | 50.0% | the5ers-hypergrowth | 0.783 | 0.878 | 0.024 | 0.084 | 0.884 | 0.086 | 8 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.3333 | 33.3% | ftmo-2step | 0.783 | 1.000 | 0.000 | 0.000 | 0.994 | 0.006 | 19 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.3333 | 33.3% | fundingpips-2step | 0.831 | 1.000 | 0.000 | 0.000 | 0.995 | 0.005 | 16 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.3333 | 33.3% | the5ers-highstakes | 0.783 | 1.000 | 0.000 | 0.000 | 0.994 | 0.006 | 19 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.3333 | 33.3% | the5ers-hypergrowth | 0.723 | 0.845 | 0.133 | 0.000 | 0.845 | 0.028 | 11 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.2500 | 25.0% | ftmo-2step | 0.699 | 1.000 | 0.000 | 0.000 | 0.999 | 0.001 | 22 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.2500 | 25.0% | fundingpips-2step | 0.747 | 1.000 | 0.000 | 0.000 | 0.999 | 0.001 | 22 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.2500 | 25.0% | the5ers-highstakes | 0.699 | 1.000 | 0.000 | 0.000 | 0.999 | 0.001 | 22 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.2500 | 25.0% | the5ers-hypergrowth | 0.759 | 0.913 | 0.000 | 0.072 | 0.985 | 0.015 | 15 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.1667 | 16.7% | ftmo-2step | 0.651 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 29 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.1667 | 16.7% | fundingpips-2step | 0.675 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 27 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.1667 | 16.7% | the5ers-highstakes | 0.651 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 29 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.1667 | 16.7% | the5ers-hypergrowth | 0.699 | 1.000 | 0.000 | 0.000 | 0.998 | 0.002 | 22 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.1250 | 12.5% | ftmo-2step | 0.578 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 38 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.1250 | 12.5% | fundingpips-2step | 0.602 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 33 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.1250 | 12.5% | the5ers-highstakes | 0.578 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 38 |
| daily2-ai-s5-slwide-smcnorm | 1y | 0.1250 | 12.5% | the5ers-hypergrowth | 0.675 | 1.000 | 0.000 | 0.000 | 0.999 | 0.001 | 27 |
| daily2-ai-s5-slwide-smcnorm | 2y | 1.0000 | 100.0% | ftmo-2step | 0.433 | 0.452 | 0.323 | 0.201 | 0.631 | 0.195 | 7 |
| daily2-ai-s5-slwide-smcnorm | 2y | 1.0000 | 100.0% | fundingpips-2step | 0.433 | 0.452 | 0.323 | 0.201 | 0.648 | 0.189 | 7 |
| daily2-ai-s5-slwide-smcnorm | 2y | 1.0000 | 100.0% | the5ers-highstakes | 0.433 | 0.452 | 0.323 | 0.201 | 0.631 | 0.195 | 7 |
| daily2-ai-s5-slwide-smcnorm | 2y | 1.0000 | 100.0% | the5ers-hypergrowth | 0.396 | 0.409 | 0.232 | 0.341 | 0.562 | 0.209 | 5 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.5000 | 50.0% | ftmo-2step | 0.921 | 0.993 | 0.000 | 0.006 | 0.920 | 0.080 | 33 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.5000 | 50.0% | fundingpips-2step | 0.927 | 0.993 | 0.000 | 0.006 | 0.929 | 0.070 | 28 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.5000 | 50.0% | the5ers-highstakes | 0.921 | 0.993 | 0.000 | 0.006 | 0.920 | 0.080 | 33 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.5000 | 50.0% | the5ers-hypergrowth | 0.463 | 0.490 | 0.311 | 0.171 | 0.702 | 0.133 | 9 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.3333 | 33.3% | ftmo-2step | 0.890 | 1.000 | 0.000 | 0.000 | 0.981 | 0.019 | 41 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.3333 | 33.3% | fundingpips-2step | 0.915 | 1.000 | 0.000 | 0.000 | 0.980 | 0.021 | 36 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.3333 | 33.3% | the5ers-highstakes | 0.890 | 1.000 | 0.000 | 0.000 | 0.981 | 0.019 | 41 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.3333 | 33.3% | the5ers-hypergrowth | 0.835 | 0.901 | 0.073 | 0.018 | 0.809 | 0.061 | 33 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.2500 | 25.0% | ftmo-2step | 0.848 | 1.000 | 0.000 | 0.000 | 0.994 | 0.006 | 60 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.2500 | 25.0% | fundingpips-2step | 0.872 | 1.000 | 0.000 | 0.000 | 0.994 | 0.006 | 46 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.2500 | 25.0% | the5ers-highstakes | 0.848 | 1.000 | 0.000 | 0.000 | 0.994 | 0.006 | 60 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.2500 | 25.0% | the5ers-hypergrowth | 0.835 | 0.919 | 0.000 | 0.073 | 0.964 | 0.036 | 37 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.1667 | 16.7% | ftmo-2step | 0.823 | 1.000 | 0.000 | 0.000 | 1.000 | 0.001 | 63 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.1667 | 16.7% | fundingpips-2step | 0.835 | 1.000 | 0.000 | 0.000 | 1.000 | 0.001 | 61 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.1667 | 16.7% | the5ers-highstakes | 0.823 | 1.000 | 0.000 | 0.000 | 1.000 | 0.001 | 63 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.1667 | 16.7% | the5ers-hypergrowth | 0.848 | 1.000 | 0.000 | 0.000 | 0.994 | 0.006 | 60 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.1250 | 12.5% | ftmo-2step | 0.787 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 73 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.1250 | 12.5% | fundingpips-2step | 0.799 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 67 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.1250 | 12.5% | the5ers-highstakes | 0.787 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 73 |
| daily2-ai-s5-slwide-smcnorm | 2y | 0.1250 | 12.5% | the5ers-hypergrowth | 0.835 | 1.000 | 0.000 | 0.000 | 0.999 | 0.001 | 61 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 1.0000 | 100.0% | ftmo-2step | 0.756 | 0.969 | 0.024 | 0.000 | 0.979 | 0.001 | 5 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 1.0000 | 100.0% | fundingpips-2step | 0.780 | 0.970 | 0.024 | 0.000 | 0.980 | 0.000 | 5 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 1.0000 | 100.0% | the5ers-highstakes | 0.756 | 0.969 | 0.024 | 0.000 | 0.979 | 0.001 | 5 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 1.0000 | 100.0% | the5ers-hypergrowth | 0.659 | 0.818 | 0.146 | 0.000 | 0.818 | 0.000 | 3 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.5000 | 50.0% | ftmo-2step | 0.610 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 8 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.5000 | 50.0% | fundingpips-2step | 0.683 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 8 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.5000 | 50.0% | the5ers-highstakes | 0.610 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 8 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.5000 | 50.0% | the5ers-hypergrowth | 0.707 | 0.967 | 0.024 | 0.000 | 0.973 | 0.000 | 7 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.3333 | 33.3% | ftmo-2step | 0.439 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 10 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.3333 | 33.3% | fundingpips-2step | 0.488 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 10 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.3333 | 33.3% | the5ers-highstakes | 0.439 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 10 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.3333 | 33.3% | the5ers-hypergrowth | 0.634 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 8 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.2500 | 25.0% | ftmo-2step | 0.390 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 12 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.2500 | 25.0% | fundingpips-2step | 0.439 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 12 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.2500 | 25.0% | the5ers-highstakes | 0.390 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 12 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.2500 | 25.0% | the5ers-hypergrowth | 0.488 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 10 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.1667 | 16.7% | ftmo-2step | 0.220 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 13 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.1667 | 16.7% | fundingpips-2step | 0.244 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 10 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.1667 | 16.7% | the5ers-highstakes | 0.220 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 13 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.1667 | 16.7% | the5ers-hypergrowth | 0.390 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 12 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.1250 | 12.5% | ftmo-2step | 0.195 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 19 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.1250 | 12.5% | fundingpips-2step | 0.195 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 15 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.1250 | 12.5% | the5ers-highstakes | 0.195 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 19 |
| daily2-monthlock25 (ai-s1 baseline) | 6m | 0.1250 | 12.5% | the5ers-hypergrowth | 0.244 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 10 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 1.0000 | 100.0% | ftmo-2step | 0.684 | 0.771 | 0.114 | 0.089 | 0.758 | 0.114 | 7 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 1.0000 | 100.0% | fundingpips-2step | 0.709 | 0.789 | 0.114 | 0.076 | 0.768 | 0.106 | 7 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 1.0000 | 100.0% | the5ers-highstakes | 0.684 | 0.771 | 0.114 | 0.089 | 0.758 | 0.114 | 7 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 1.0000 | 100.0% | the5ers-hypergrowth | 0.544 | 0.606 | 0.241 | 0.114 | 0.610 | 0.113 | 4 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.5000 | 50.0% | ftmo-2step | 0.772 | 0.953 | 0.000 | 0.038 | 0.962 | 0.038 | 15 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.5000 | 50.0% | fundingpips-2step | 0.797 | 0.940 | 0.000 | 0.051 | 0.956 | 0.044 | 13 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.5000 | 50.0% | the5ers-highstakes | 0.772 | 0.953 | 0.000 | 0.038 | 0.962 | 0.038 | 15 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.5000 | 50.0% | the5ers-hypergrowth | 0.595 | 0.691 | 0.228 | 0.038 | 0.710 | 0.044 | 8 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.3333 | 33.3% | ftmo-2step | 0.709 | 1.000 | 0.000 | 0.000 | 0.995 | 0.005 | 20 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.3333 | 33.3% | fundingpips-2step | 0.747 | 1.000 | 0.000 | 0.000 | 0.994 | 0.006 | 20 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.3333 | 33.3% | the5ers-highstakes | 0.709 | 1.000 | 0.000 | 0.000 | 0.995 | 0.005 | 20 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.3333 | 33.3% | the5ers-hypergrowth | 0.785 | 0.954 | 0.000 | 0.038 | 0.961 | 0.040 | 16 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.2500 | 25.0% | ftmo-2step | 0.684 | 1.000 | 0.000 | 0.000 | 1.000 | 0.001 | 24 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.2500 | 25.0% | fundingpips-2step | 0.709 | 1.000 | 0.000 | 0.000 | 1.000 | 0.001 | 22 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.2500 | 25.0% | the5ers-highstakes | 0.684 | 1.000 | 0.000 | 0.000 | 1.000 | 0.001 | 24 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.2500 | 25.0% | the5ers-hypergrowth | 0.734 | 1.000 | 0.000 | 0.000 | 0.988 | 0.012 | 20 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.1667 | 16.7% | ftmo-2step | 0.608 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 32 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.1667 | 16.7% | fundingpips-2step | 0.633 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 30 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.1667 | 16.7% | the5ers-highstakes | 0.608 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 32 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.1667 | 16.7% | the5ers-hypergrowth | 0.684 | 1.000 | 0.000 | 0.000 | 0.998 | 0.002 | 24 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.1250 | 12.5% | ftmo-2step | 0.582 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 43 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.1250 | 12.5% | fundingpips-2step | 0.582 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 36 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.1250 | 12.5% | the5ers-highstakes | 0.582 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 43 |
| daily2-monthlock25 (ai-s1 baseline) | 1y | 0.1250 | 12.5% | the5ers-hypergrowth | 0.633 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 30 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 1.0000 | 100.0% | ftmo-2step | 0.414 | 0.439 | 0.350 | 0.178 | 0.620 | 0.164 | 9 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 1.0000 | 100.0% | fundingpips-2step | 0.427 | 0.450 | 0.350 | 0.172 | 0.630 | 0.160 | 8 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 1.0000 | 100.0% | the5ers-highstakes | 0.414 | 0.439 | 0.350 | 0.178 | 0.620 | 0.164 | 9 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 1.0000 | 100.0% | the5ers-hypergrowth | 0.344 | 0.362 | 0.363 | 0.242 | 0.501 | 0.223 | 5 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.5000 | 50.0% | ftmo-2step | 0.879 | 0.979 | 0.000 | 0.019 | 0.932 | 0.068 | 34 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.5000 | 50.0% | fundingpips-2step | 0.898 | 0.972 | 0.000 | 0.025 | 0.928 | 0.072 | 30 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.5000 | 50.0% | the5ers-highstakes | 0.879 | 0.979 | 0.000 | 0.019 | 0.932 | 0.068 | 34 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.5000 | 50.0% | the5ers-hypergrowth | 0.376 | 0.404 | 0.471 | 0.083 | 0.589 | 0.085 | 11 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.3333 | 33.3% | ftmo-2step | 0.854 | 1.000 | 0.000 | 0.000 | 0.979 | 0.021 | 47 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.3333 | 33.3% | fundingpips-2step | 0.873 | 1.000 | 0.000 | 0.000 | 0.980 | 0.021 | 42 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.3333 | 33.3% | the5ers-highstakes | 0.854 | 1.000 | 0.000 | 0.000 | 0.979 | 0.021 | 47 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.3333 | 33.3% | the5ers-hypergrowth | 0.885 | 0.979 | 0.000 | 0.019 | 0.920 | 0.080 | 34 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.2500 | 25.0% | ftmo-2step | 0.841 | 1.000 | 0.000 | 0.000 | 0.996 | 0.004 | 58 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.2500 | 25.0% | fundingpips-2step | 0.854 | 1.000 | 0.000 | 0.000 | 0.997 | 0.003 | 58 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.2500 | 25.0% | the5ers-highstakes | 0.841 | 1.000 | 0.000 | 0.000 | 0.996 | 0.004 | 58 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.2500 | 25.0% | the5ers-hypergrowth | 0.866 | 1.000 | 0.000 | 0.000 | 0.966 | 0.035 | 43 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.1667 | 16.7% | ftmo-2step | 0.803 | 1.000 | 0.000 | 0.000 | 1.000 | 0.001 | 65 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.1667 | 16.7% | fundingpips-2step | 0.815 | 1.000 | 0.000 | 0.000 | 1.000 | 0.001 | 62 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.1667 | 16.7% | the5ers-highstakes | 0.803 | 1.000 | 0.000 | 0.000 | 1.000 | 0.001 | 65 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.1667 | 16.7% | the5ers-hypergrowth | 0.841 | 1.000 | 0.000 | 0.000 | 0.993 | 0.007 | 58 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.1250 | 12.5% | ftmo-2step | 0.790 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 72 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.1250 | 12.5% | fundingpips-2step | 0.790 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 68 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.1250 | 12.5% | the5ers-highstakes | 0.790 | 1.000 | 0.000 | 0.000 | 1.000 | 0.000 | 72 |
| daily2-monthlock25 (ai-s1 baseline) | 2y | 0.1250 | 12.5% | the5ers-hypergrowth | 0.815 | 1.000 | 0.000 | 0.000 | 0.999 | 0.002 | 62 |

`n_closed_trades`/`n_trading_days` per report (constant across k/firm): ai-s5 6m=130/43,
1y=239/83, 2y=394/164; ai-s1 6m=124/41, 1y=226/79, 2y=383/157. `Rolling P(daily breach)` =
`p_fail_daily`; `Rolling P(DD breach)` = `p_fail_dd` from `_summarize_outcomes`.

## 6. Per-trade expectancy (parametric estimate, unscaled -- constant across k and firm)

`e_per_trade_R`/`v_per_trade_R` come from `parametric_estimate`'s raw `r_multiples` list,
which is loaded once per report and is **not** rescaled by `risk_pct` -- hence identical
across every k/firm row for a given (candidate, window) above.

| Candidate | Window | n trades | e (per-trade R) | v (per-trade R) | 95% CI on e* | Excludes zero? |
|---|---|---|---|---|---|---|
| daily2-ai-s5-slwide-smcnorm | 6m | 130 | 0.01207 | 0.000407 | [0.00860, 0.01554] | yes |
| daily2-ai-s5-slwide-smcnorm | 1y | 239 | 0.00810 | 0.000409 | [0.00554, 0.01066] | yes |
| daily2-ai-s5-slwide-smcnorm | 2y | 394 | 0.00494 | 0.000301 | [0.00322, 0.00665] | yes |
| daily2-monthlock25 (ai-s1) | 6m | 124 | 0.01193 | 0.000453 | [0.00818, 0.01568] | yes |
| daily2-monthlock25 (ai-s1) | 1y | 226 | 0.00721 | 0.000327 | [0.00485, 0.00957] | yes |
| daily2-monthlock25 (ai-s1) | 2y | 383 | 0.00426 | 0.000242 | [0.00270, 0.00582] | yes |

\* `prop-challenge-simulator.py --method parametric` reports only the point estimate `e` and
population variance `v`, no CI. The CI column here is computed by this report (normal
approximation, `e +/- 1.96*sqrt(v/n)`), not by the simulator -- shown because it directly
speaks to the design doc's own G5 gate framing ("95% CI on e excludes zero"). All 6 CIs
exclude zero.

## 7. Verdict: **GO**

Applying the specified rule (rolling-start primary, bootstrap secondary; P(pass) >= 0.55 AND
P(DD breach) < 0.05): **97 of 144 combinations clear the bar.** This is not a marginal or
knife-edge result.

**Best and most consistent winner** (clears the bar in ALL 3 windows -- 6m, 1y, AND 2y --
simultaneously): `daily2-ai-s5-slwide-smcnorm` at **k=1/3 (challenge_risk_pct=33.3%), firm
`fundingpips-2step`**:

| Window | Rolling P(pass) | Rolling P(DD breach) | Boot P(pass) | Boot P(DD breach) |
|---|---|---|---|---|
| 6m | 0.674 | 0.000 | 1.000 | 0.000 |
| 1y | 0.831 | 0.000 | 0.995 | 0.005 |
| 2y | 0.915 | 0.000 | 0.980 | 0.021 |

`k=1/3` at `ftmo-2step` and `the5ers-highstakes` (identical daily/DD rules to each other)
clear the bar consistently too, at slightly lower P(pass) (0.581/0.783/0.890). `k=1/2` also
clears the bar in all 3 windows for `ftmo-2step`/`fundingpips-2step`/`the5ers-highstakes` on
the aggressive candidate, with even higher P(pass) at 1y/2y (0.843-0.927) but a small nonzero
rolling P(DD breach) at 1y/2y (0.012/0.006 -- still comfortably under the 0.05 bar).
`the5ers-hypergrowth` (the tightest firm: 3% daily / 6% max-DD) is consistently the weakest
across every k, as expected from its tighter barriers, but still clears the bar at k=1/3 in
all 3 windows (0.721/0.723/0.835).

The baseline candidate `daily2-monthlock25` also clears the all-3-windows bar at several
(k, firm) pairs (e.g. k=1/2 `ftmo-2step`: 0.610/0.772/0.879), but consistently underperforms
the aggressive `daily2-ai-s5-slwide-smcnorm` candidate at matched (k, firm) -- consistent with
the aggressive candidate's higher raw expectancy per trade (see §6: e roughly 1.0-1.6x the
baseline's at every window).

**k=1 (no scaling) does NOT reliably clear the bar** beyond the 6m window: at 1y and
especially 2y, full un-scaled GoldBot risk breaches the 10% static max-DD floor too often
(rolling P(DD breach) 0.12-0.20 at 1y, 0.20-0.34 at 2y) -- this is exactly the risk-taking
level GoldBot was tuned for on its own $1000-deposit backtest, well above what a static-DD
prop firm barrier tolerates over a longer sample. Scaling down is necessary, not optional.

**Directional pattern across all 144 rows:** P(pass) tends to rise, and P(DD breach) tends to
fall, as k shrinks from 1 down to about 1/3-1/4, then P(pass) starts falling again at 1/6-1/8
(risk is now low enough that hitting the challenge's fixed +10%/+5% profit targets before the
sample runs out becomes the binding constraint rather than the DD floor -- visible in rising
`rolling_p_censored`, i.e. runs out of data before resolving, most acute on the 6m window).
The sweet spot is k roughly 1/4 to 1/2, with k=1/3 the standout for consistency across all 3
windows and all firms simultaneously.

## 8. Caveats (read before acting on this GO)

1. **Scale-invariance / min-lot floor bias (§3).** This simulation assumes GoldBot's own lot
   sizing scales perfectly linearly with equity and risk fraction. In reality,
   `GoldBotNormalizeLot`'s min-lot floor means trades that were already floor-bound in the
   $1000-deposit source backtests would, at small k on a real (much larger) prop account,
   floor back up to a higher realized risk than k implies. This is a one-directional
   optimism bias in this simulation's favor, worst at the smallest k rows (1/6, 1/8) --
   though note the winning k=1/3 to 1/2 combos are not the smallest-k rows, so this bias is
   somewhat less concerning for the recommended operating point, but has not been quantified
   and should be checked with a real re-run at prop-account-scale lot sizing before spending
   a challenge fee.
2. **This is a Monte-Carlo replay of ~130-394 historical trades, not a fresh forward test.**
   Both candidates' r-multiple sequences come from the same underlying market history
   (overlapping 6m/1y/2y windows of the same instrument/period) -- the 3 "windows" are not 3
   independent samples, so treat the "consistent across all 3 windows" claim as internal
   consistency of one history, not out-of-sample confirmation across unrelated periods.
3. **No spread/cost stress applied.** `PROPGUARD_DESIGN.md`'s own G3 gate calls for testing
   "at 1.5x spread stress"; this simulation replays the trades' historical r-multiples
   as-is, with no adverse-cost stress layered on top. A real prop account may have
   different spread/commission than the backtest broker.
4. **Time-to-pass grows sharply at small k.** Median days-to-pass at k=1/8 on the 2y sample
   is 61-73 trading days (vs. 4-9 at k=1). The GO/NO-GO rule as specified does not gate on
   time-to-pass, and none of the 4 modeled firms are stated to have a hard time limit in
   `FIRM_PRESETS`/`PROPGUARD_DESIGN.md`'s table (FTMO: "Time limit: none") -- but if a real
   firm's actual rulebook (checked at G7, not yet done) imposes one, the very-small-k
   combinations could be at risk even though this simulator shows them passing.
5. **`funded_risk_pct` is inert for every number in this report** -- see §4 -- because
   `simulate_from` returns PASS at the instant Phase 2's target is hit, before any funded-
   phase day is simulated. If a future study wants P(survive N funded days), that metric
   would need to be computed separately and is not part of this report.

## Files produced

- `scripts/goldbot-prop-simulate.py` (new) -- the htm-report -> PropGuard-journal-shaped CSV
  adapter described in §1.
- `mt5/backtests/reports/*.propguard-sim.csv` (6 new, siblings of the 6 source `.htm`
  reports) -- the extracted r-multiple journals actually fed into
  `prop-challenge-simulator.py` for this sweep.
- This file.
