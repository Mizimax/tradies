# QBR v1.13 Aggressive Research

QBR v1.13 is a separate aggressive research track for `XAUUSD`, a USD 1,000
account, and 1:100 leverage. It does not change GoldBot or GoldScalper.

## Evidence contract

- Build tag: `QBR-1.13-aggressive`
- Tester model: every tick based on real ticks
- Minimum accepted history quality: 99%
- MT5 report net profit must reconcile independently with `deals.csv` and
  `baskets.csv` within USD 0.01. Deal tickets must be unique, basket exit-deal
  counts must equal the deal audit, and unique closed position identifiers must
  equal both basket totals and MT5 `Total Trades`.
- A missing native-SL basket makes the analyzer and candidate run fail.

## Compile and smoke test

```bash
bash scripts/compile-mt5-qbr.sh

WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all \
python3 scripts/run-qbr-candidate.py v113-control \
  --from-date 2026.01.01 --to-date 2026.01.07 \
  --deposit 1000 --leverage 100 --report-suffix smoke
```

Port 3000 must be free or owned by MetaTester. Do not stop an unrelated dev
server without confirming ownership first.

## Candidate ladder

Run candidates one at a time in this order. The runner enforces the evidence
dependencies: `lock40` inherits the better of `stop60`/`stop45`, Q-Sync and
confidence inherit that selected loss profile, M5 is refused when the M15
candidate already reaches 60 trades/month, and scaling is refused unless a
base-risk candidate passed the discovery gate.

```text
v113-control
v113-minlot-cap
v113-minlot-quality-hours
v113-quality-hours2
v113-quality-hours3
v113-stop60
v113-stop45
v113-lock40
v113-qsync22
v113-conf64
v113-m5-15-30
v113-m5-20-40
v113-scale100
v113-scale150
v113-scale200
```

Use `2026.01.01` through `2026.06.30` for the current Exness real-tick
window. M5 candidates keep M15/H4 regime authority and admit only closed-bar
pullback, failed-breakout, and breakout-retest triggers.

`v113-minlot-quality-hours` is an evidence-driven recovery candidate added
after the unrestricted min-lot run failed. It leaves normally risk-sized
control entries unchanged and permits the broker-minimum fallback only during
`02,03,06,10,13,16,17,18,19,20` broker hours. This is discovery evidence from
the 2026 H1 sample and must be treated as overfit until longer-window and
forward validation confirm it.

`v113-quality-hours2` refines the min-lot allowed-hours filter to
`02,10,13,16,17,18,19,20` (dropping hours `03` and `06` from
`v113-minlot-quality-hours`'s set). The drop is evidence-driven: hour `03`
and hour `06` were net losers in two independent 2026 H1 runs (incremental
net vs `v113-control`: hour 03 -$11.45 and -$8.55; hour 06 -$18.87 and
-$7.52 across the `v113-minlot-quality-hours` and `v113-stop60` runs
respectively), while the rest of the allowed-hours set was net positive in
both runs. This is a **second round** of hour-set fitting on the same 2026
H1 sample (the first round produced `v113-minlot-quality-hours` itself) —
even with two independent runs agreeing on hours 03/06, this remains
in-sample evidence and must not be promoted without out-of-sample or
forward-demo confirmation.

`v113-quality-hours3` is identical to `v113-quality-hours2` but additionally
sets `InpEnableBreakoutRetest=false`, disabling the `BREAKOUT_AND_RETEST`
entry pattern entirely. Motivation: an architecture review (see "Architecture
review" section below) found this pattern is a net drag (11 trades, PF 0.51,
net -$13.39 in the `v113-quality-hours2` H1 run) that also steals
higher-confidence entry slots from the much better-performing
`TREND_PULLBACK` pattern (123 trades, PF 1.51, net +$76.45), because the
EA's pattern selector picks by hardcoded confidence score rather than
historical performance. Status: candidate defined and smoke-tested clean
(100% real ticks, reconciliation passed); the full H1 run has not yet
completed — see "Known issue: Wine/MT5 session reliability" below.

`v113-stop60` and `v113-stop45` in the ladder above are likewise redefined to
carry the same `InpMinLotAllowedHours=02,03,06,10,13,16,17,18,19,20`
quality-hours filter as `v113-minlot-quality-hours`, rather than the original
"min-lot every hour" definition, since that base config already proved a
loser (`v113-minlot-cap`: -$49.69).

## Results (2026 H1, 2026.01.01-2026.06.30)

All results below are from 100% real-tick MT5 Strategy Tester reports,
`XAUUSD` M15, reconciled within USD 0.01 between the MT5 report,
`deals.csv`, and `baskets.csv`.

| Candidate | Net | Trades | WR | PF | DD |
|---|---|---|---|---|---|
| `v113-control` | +$40.01 | 88 | 70.45% | 1.35 | 2.78% |
| `v113-minlot-cap` (min-lot every hour, no filter) | -$49.69 | 144 | 60.42% | 0.81 | 7.95% |
| `v113-minlot-quality-hours` | +$39.80 | 169 | 70.41% | 1.16 | 6.04% |
| `v113-stop60` (quality-hours filter + `InpBasketHardStopPct=0.60`) | +$38.69 | 165 | 67.27% | 1.17 | 5.59% (report) / 4.97% (daily equity) |

`v113-minlot-quality-hours` passes the win-rate bar (70.41%) but fails
discovery on PF (1.16 < 1.30) and net profit does not clear `v113-control`.

`v113-stop60` basket-level detail (`analysis_summary.json` `basket_metrics`
in
`mt5/backtests/reports/QBR-v113-stop60-XAUUSD-M15-2026.01.01-2026.06.30-2026h1-stop60q1.qbr-analysis/`):
average_winner $2.46, average_loser -$4.34 (vs quality-hours' average_winner
$2.49, average_loser -$5.13).

Tightening the hard stop from 0.75% to 0.60% did shrink average loss size as
intended ($5.13 -> $4.34), but it also cut win rate from 70.41% to 67.27%
(trades that would have recovered got stopped out early), which erased
essentially all of the PF benefit (1.16 -> 1.17, functionally flat) and net
profit actually dropped slightly ($39.80 -> $38.69). `v113-stop60` fails the
discovery gate (WR<70%, PF<1.30, net<control) and is not an improvement over
quality-hours alone. Per the ladder's own decision rule, this is a "got
worse, not better" outcome (not a "close but short" outcome), so the
stop-tightening branch was halted here rather than cascading to
`v113-stop45` -- a further 0.60%->0.45% tightening would plausibly compress
average loss further but is expected to cut win rate even more for the same
whipsaw reason, not likely to reach PF 1.30. **`v113-stop45` was not run.**

### v113-quality-hours2 (2026 H1)

| Candidate | Net | Trades | WR | PF | DD |
|---|---|---|---|---|---|
| `v113-quality-hours2` | +$63.73 | 166 | 71.08% | 1.27 | 2.83% |

100% real ticks, reconciled within $0.01 (basket/deal/report net profit all
agree exactly at $63.73). This is the best-performing candidate to date: net
profit is +59% over `v113-control` ($40.01), win rate clears the 70% bar
(71.08%), and equity drawdown (2.83%) is close to control's (2.78%) despite
the much higher trade count (166 vs 88). It still fails the discovery gate
strictly on two counts: profit factor (1.27 vs required 1.30 — a 0.03 gap)
and trade count (166 vs required 360). It fully clears the **scaled track**
quality bar instead (win rate >=70%, PF >=1.20, DD <=25% all pass), which is
why the scaled track was opened on this base (see "Scaled track" below).

Per-hour instability observed: comparing `v113-quality-hours2`'s hour-level
breakdown against the earlier `v113-minlot-quality-hours` run on the same
window, hours outside the min-lot filter's control (i.e. normal risk-sized
entries firing every hour regardless of the filter) showed large swings
between runs — e.g. hour 07 went from a minor contributor to net -$22.31,
and hour 16 to net -$14.38, despite unchanged normal-entry logic. At ~166
trades over ~20 active hours (roughly 8 trades/hour over 6 months), per-hour
attribution carries wide sampling noise and should not be over-read as
stable structure.

## Architecture review

An independent architecture study (not a backtest — code + evidence review)
was run against the `v113-quality-hours2` H1 result to answer: is there a
structural lever (not just position-size scaling) that could materially lift
risk-adjusted edge? Findings:

1. **Native-SL drag is structural, not a management bug.** 25 of 166 baskets
   exit via `UNOBSERVED_EXTERNAL_EXIT` (the broker-native hard stop, not a
   basket-managed exit) for -$201.38 gross loss — nearly as large as total
   gross profit ($297.13). Root cause: this candidate runs
   `InpRiskPerBasketPct == InpBasketHardStopPct == 0.75`, so the pattern
   invalidation swing and the broker-native stop sit at the same price by
   construction, and the software invalidation check is bar-close gated while
   the broker stop is tick-level — the broker stop always wins the race on a
   shared price level. Closing this "gap" would save only pennies of
   spread per trade; **not a material lever.**

2. **`BREAKOUT_AND_RETEST` filtering is a cheap, plausible win.** This pattern
   is thin-sample (11 trades) but structurally weak (PF 0.51, net -$13.39)
   and it also **outranks and steals slots from** `TREND_PULLBACK` (the
   dominant, best-performing pattern: 123 trades, PF 1.51, net +$76.45)
   because the pattern selector picks by hardcoded confidence, not
   performance. In-sample estimate: disabling it could lift net toward ~$77
   (+~20%). This produced the `v113-quality-hours3` candidate above — result
   pending.

3. **No large architecture lever exists; the frontier is mostly
   position-scaling.** PF is fundamentally bounded by win-rate x payoff, and
   win rate (71%) is the load-bearing variable — tightening the loss side
   further (as `v113-stop60` already showed) is not productive. The one
   higher-value-but-unbuilt idea: replace the flat fixed-money profit target
   with a partial-bank-plus-trailing-runner so some winners can ride past the
   current $2.52-average/$3.52-max cap without adding losers. This would be a
   real code change (new logic in `QuantumBehavioralReplica.mq5`
   `ManageOpenBasket`), not a `.set` override, and has not been built or
   tested.

4. **Numeric estimates for the user's DD 20-30% risk envelope** (grounded in
   the DD/risk relationship implied by `v113-quality-hours2`'s 2.83% DD at
   0.75% basket risk, extrapolated — not empirically measured, see "Known
   issue" below for why): pure position-size scaling to a 20-30% DD budget is
   estimated at roughly **35-60% net return over a 6-month window**
   (**not** 50%/month — scaling this edge to 50%/month linearly would require
   a ~50x risk multiplier and is mathematically certain to hit ruin first).
   If the `BREAKOUT_AND_RETEST` filter and/or the trailing-runner idea pan
   out, a further **+20-40% relative return at the same DD budget** is a
   defensible (not guaranteed) upside on top of that.

## Scaled track

The user's risk envelope for this track: accept 20-30% max drawdown,
targeting the best return achievable within that budget (not a literal
50%/month — see the architecture review's numeric estimates above for why
that specific target is unreachable by scaling this edge).

`scripts/run-qbr-candidate.py` was extended with an explicit `--scale-base
<candidate>` flag so a scale candidate (`v113-scale100/150/200/agg`) can be
rebased on any evidence-backed non-scale candidate (e.g.
`v113-quality-hours2`) instead of only the auto-selected candidate that
clears the unscaled discovery gate's 360-trade requirement (which nothing
has reached yet, capping out at 166 trades). The flag still requires real,
reconciled evidence for the named base — it does not bypass evidence
validation, only the 360-trade/discovery-gate requirement specific to
scaling eligibility.

A `v113-scale-agg` candidate scaffold was added (currently placeholder
risk/target/stop values: `InpRiskPerBasketPct=6.0`,
`InpBasketTargetValue=2.40`, `InpBasketHardStopPct=6.0`, with
proportionally-scaled daily/weekly/floating-loss safety caps and a fixed
`InpMaxEquityDrawdownPct=25.0` brake) — sized only as a rough placeholder,
not yet tuned from a measured DD-per-unit-risk coefficient.

**Status: empirical scale-track validation is blocked, not abandoned.** See
"Known issue" immediately below.

## Known issue: Wine/MT5 session reliability

During this research session, four independent MT5/Wine backtest runs failed
for environment reasons unrelated to candidate configuration:

1. An early `v113-stop60` run produced a corrupted empty-shell report
   (`Expert:` blank, `Period: M0 (1970.01.01 - 1970.01.01)`, 0 trades) with no
   error raised by MT5 — the tester silently produced garbage.
2. A `v113-scale200` full-H1 run (rebased on `v113-quality-hours2` via
   `--scale-base`) hung mid-run: `AutoTesting` progress in the MT5 log
   advanced normally to ~45-49% then went silent, `metatester64.exe` pinned
   at 0% CPU, no error.
3. A retry of the same run hit a literal `wineserver crashed` fatal error at
   a similar progress point, confirmed via the runner's captured stdout.
4. A shorter 2026 Q1 (3-month) `v113-quality-hours2` run, tried specifically
   to see if the issue was duration-related, instead hit failure mode #1
   again (empty-shell report) due to two mid-run `Network 'connection to
   Exness-MT5Trial14 lost'` events. A subsequent full-H1 `v113-quality-hours3`
   run (smoke-tested clean, similar compute cost to the `v113-quality-hours2`
   run that completed successfully earlier in the same session) then hung at
   78% progress with no crash, no completion.

None of these correlate with candidate configuration — `v113-quality-hours2`
and `v113-stop60` both completed cleanly full-H1 earlier in the same session,
and `v113-quality-hours3` (near-identical compute cost to
`v113-quality-hours2`) failed later in the session on a hang. The pattern
points to **cumulative Wine/session degradation** from several hours of
sustained backtest load rather than anything fixable from the candidate-config
side.

**Before the next research round**, restart the Wine session (or the host
machine) rather than immediately retrying live runs. After a restart, use the
existing smoke-test-first workflow (2026.01.01-2026.01.07) to confirm the
environment is healthy before committing to another full 6-month real-tick
run. Pending work once the environment is confirmed healthy:
- `v113-quality-hours3` full H1 (BREAKOUT_AND_RETEST-disabled variant)
- `v113-scale200 --scale-base v113-quality-hours2` full H1 (to measure the
  DD-per-unit-risk scaling coefficient and size `v113-scale-agg` from it)
- `v113-scale-agg` once sized from the measurement above
- Out-of-sample validation (2025 H2 window) for whichever candidate ends up
  as the leading base

## Acceptance

The analyzer writes `analysis_summary.json` and `analysis_summary.md` beside
each report. Discovery candidates require 360 trades, 70% win rate, PF 1.30,
equity DD at most 10%, and net profit above the v1.12 control. Scaled
candidates require 70% win rate, PF 1.20, equity DD at most 25%, at least four
positive months, and no permanent equity safety stop.

The 50% monthly objective is the geometric mean of calendar-month returns. Net
results are always shown as both USD and percentage of the initial deposit. If
the target is not achieved, the result is explicitly `target unmet`; no
candidate is promoted by relaxing the safety gates.

A six-month pass is still **unproven research**, not deployment evidence. The
repo's promotion rule requires materially longer 1-year and 2-year real-tick
windows before demo-forward. The current Exness cache only provides the 2026
window at the required quality, so a candidate cannot become deployment-ready
until those longer >=99% real-tick windows are available. After that it still
requires at least four demo-forward weeks and 100 closed trades before any
real-money consideration.
