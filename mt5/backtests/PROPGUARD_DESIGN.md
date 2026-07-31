# PropGuard — Pre-Registration Design Doc

Frozen 2026-07-27, before any PropGuard code exists and before any backtest is run.
Per the parameter-budget discipline in the approved plan (`~/.claude/plans/you-are-an-elite-linear-parnas.md`
§7): selection-inflated null expectancy is `e_null = sqrt(2*ln(C)) * sqrt(v/N)`. On the
125-trade real-tick window, keeping `e_null <= 0.10R` caps the search at **C <= 8 configurations,
8 free parameters, one round, no exceptions.** Everything not listed in §2 below is a **rule**,
fixed by the barrier structure, not tunable.

If this document and the shipped code ever disagree, the code is wrong — fix the code, do not
edit this document to match it. The only legitimate edits after backtesting begins are (a) recording
the outcome of the frozen search in §5, and (b) documented amendments dated and justified in §6.

## 0. Objective

Maximize P(pass FTMO 2-Step Phase 1 -> Phase 2 -> funded), not net profit. Acceptance metric is
`prop-challenge-simulator.py` output, not MT5's own profit/PF numbers. Full derivation in the plan
doc §1; the operative formula:

```
P(hit +a before -b) = (1 - e^(lambda*b)) / (e^(-lambda*a) - e^(lambda*b)),   lambda = 2e / (f*v)
```

## 1. Firm contract (FTMO 2-Step, primary target)

| Field | Value |
|---|---|
| Phase 1 target | +10% of initial balance |
| Phase 2 target | +5% of initial balance |
| Daily loss limit | 5% of `max(day-start balance, day-start equity)`, includes floating P/L |
| Daily reset | 00:00 CE(S)T (server-configurable, see `InpDailyResetServerHour`) |
| Max drawdown | 10% **static** from initial balance (not trailing) |
| Min trading days | 4 (tracked, never forced) |
| Time limit | none |
| Consistency rule | none |
| News restriction (eval) | none required by firm; PropGuard applies one anyway (§3) |

Other firm presets (FundingPips 2-Step, The5ers Hyper Growth) are supported via the same
`InpMaxDailyLossPct` / `InpMaxDrawdownPct` / `InpDrawdownIsTrailing` inputs, set through
`.set` files in `mt5/Presets/PropGuard/`, not through code branches.

## 2. The 8 frozen search parameters

Search happens **once**, on the 2024.07.01-2026.06.30 window (~24% real ticks, N approx 394,
`e_null approx 0.117R`), coarse grid, <= 8 total configurations, no genetic optimizer. Then
`2026.01.01-2026.06.30` (100% real ticks) is spent exactly once as a zero-tuning confirmation.

| # | Parameter | Input name | Search grid | Baseline |
|---|---|---|---|---|
| 1 | Asian range start hour (server time) | `InpAsianStartHour` | {23, 0, 1} | 0 |
| 2 | Asian range end / entry-window length (hours) | `InpAsianEndHour` | {6, 7, 8} | 7 |
| 3 | Breakout buffer `k` (× ATR) | `InpBreakoutBufferAtr` | {0.15, 0.25, 0.35} | 0.25 |
| 4 | Stop ATR multiple | `InpStopAtrMult` | {0.8, 1.0, 1.2} | 1.0 |
| 5 | Target R multiple | `InpTargetR` | {1.25, 1.5, 1.75} | 1.5 |
| 6 | Volatility band width (× median range) | `InpVolBandLow` / `InpVolBandHigh` | {0.5-1.5, 0.6-1.4} | 0.5 / 1.5 |
| 7 | NY range window start hour | `InpNyRangeStartHour` | {12, 13} | 12 |
| 8 | NY entry-window length (hours) | `InpNyEntryWindowHours` | {3, 4, 5} | 4 |

Parameters 3-6 are **shared** between Engine A (London) and Engine B (NY) — this is why Engine B
costs only 2 new parameters (7, 8), not 6, per the plan §4.

**Plateau requirement:** perturb each parameter ±1 grid step; >= 80% of neighbours must still
pass G3/G4 (plan §7 point 6, §8). A configuration that only passes at its exact grid point is
rejected as a knife-edge optimum regardless of its headline P(pass).

## 3. Rules — fixed, never tuned

These come from the barrier structure (plan §1, §5), not from the data, and are identical across
every candidate ever run:

- `InpMaxOpenTrades = 1` — absolute. Engine B is skipped if Engine A holds a position.
- No pending orders, no ladders, no partials, no trailing. Market order at M15 close, hard SL
  attached at send, fixed target, session-end time stop.
- No re-entry after a stop-out within the same session window.
- Risk sizing: `RiskBudget.mqh` anti-ruin invariant (plan §5a) —
  `riskCash = MIN(basePct*equity, (equity-dailyFloor)/3, (equity-hardFloor)/8)`.
- `basePct`: **1.00%** in Challenge P1/P2, **0.50%** Funded (plan §5b). Not swept — a rule about
  which risk regime applies to which phase, not a free parameter.
- Internal daily soft halt at -2.0%, hard flatten at -2.5% (vs firm's 5%).
- Internal max-DD hard halt at 92% of initial (8% of the 10% static budget consumed).
- Daily profit cap: halt new entries after +2.5% in a day (give-back prevention).
- Flat by session end (Engine A: `InpLondonEndHour`=13 CET; Engine B: `InpNyFlatHour`=20 CET).
- Flat by Friday close (`InpFridayCloseHour`); no weekend holding.
- No entries 21:00-23:00 CET (documented 17:00 EST rollover spread blowout).
- News blackout +/-5 min around listed high-impact events, on by default.
- Cost gate: reject entry if `(spread+commission)/stopDistance > 8%`.
- Pre-trade projection guard: reject if
  `equity - (stopLoss+spread+commission+swapEstimate+currentFloatingLoss) < max(dailyFloor, hardFloor)`.
- Target-proximity throttle: within 1.5% of the phase target, halve `basePct`.

## 4. Acceptance gates (plan §8, restated as the frozen bar)

| Gate | Requirement |
|---|---|
| G0 | Rule-engine synthetic tests pass every guard at its exact threshold |
| G1 | `compile-mt5-propguard.sh` -> 0 errors, `.ex5` mtime advances |
| G2 | Report integrity: `Expert:` matches, all 8 overrides present in report `Inputs:` block, no `Period: M0` / `Initial Deposit: 0`, htm<->journal net profit reconciles within $0.01 |
| G3 | `prop-challenge-simulator.py`: P(pass both phases) >= 0.55 on rolling-start AND block-bootstrap, at 1.5x spread stress |
| G4 | P(daily-loss breach) < 1%, P(max-DD breach) < 5% across simulated challenges |
| G5 | 95% CI on `e` (per-trade R expectancy) excludes zero on the 2-year window |
| G6 | 3-month FTMO free-trial demo forward, >= 40 closed trades, daily floor reconciliation vs FTMO dashboard for first 5 days |
| G7 | Written compliance checklist per firm, signed off against the live rulebook at purchase time |

No paid challenge fee is spent until G0-G7 all pass. If G5 fails, the candidate is published as
"no promotable candidate" — not relaxed and re-run (repo precedent: `BTCSCALPER_IMPROVEMENT_PLAN.md`,
`QBR_V113_AGGRESSIVE.md`).

## 5. Search log (filled in as the frozen round executes — not before)

| Candidate | Params (1-8) | Window | P(pass) both | P(DD breach) | 95% CI on e | Verdict |
|---|---|---|---|---|---|---|
| _(pending)_ | | | | | | |

## 6. Amendments

- **2026-07-27, during initial implementation (before any backtest ran).** Parameter #8
  ("NY entry-window length") grid changed from `{3.5, 4.5}` to `{3, 4, 5}` hours, baseline
  4.0. Reason: the hour-boundary logic (`PropGuardHourInRange`, `PropGuardBuildSessionRange`
  in `mt5/Include/PropGuard/Engines.mqh`) operates at whole-server-hour granularity,
  consistent with every other session filter in this repo (GoldBot, GoldScalper). A
  half-hour grid value cannot be represented without a deeper refactor of the hour-window
  primitives repo-wide; whole hours were chosen over that refactor. Also clarified that the
  NY range duration (12:00→range-end) is itself a fixed rule, `InpNyRangeHours=3.0`, not a
  swept parameter — it was never listed as one of the 8 in the original table, but the first
  implementation pass accidentally computed range-end from the entry-window parameter
  instead, conflating range duration, entry-window duration, and the (separate, fixed)
  position flatten hour. Fixed before any candidate was ever run.
