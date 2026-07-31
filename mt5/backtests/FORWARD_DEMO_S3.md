# GoldBot Forward-Demo Tracking: daily2-ai-s5-slwide-smcnorm vs daily2-monthlock25

Date: 2026-07-16 (updated; supersedes the 2026-07-10 version, which tracked the older S3 winner)

Scope: GoldBot only. Two candidates run side by side on separate demo accounts (or separate magic numbers on one account) so results are never mixed.

## Data quality caveat — read this first

The S1-S5 backtest tuning program that produced the aggressive candidate below is now closed out. Before trusting any number in this document, understand how much (or little) confidence the backtest figures deserve:

- **Every S1-S5 selection round — including the numbers below — was built on training-window (2024.07.01-2026.06.30) MT5 Strategy Tester runs with only ~24% real-tick `History Quality`.** The remaining ~76% of price action inside those backtests is interpolated from M1 OHLC bars, not real broker tick history. This was true of every 6m/1y/2y run used to pick every S1 through S5 winner, not just this final one.
- **A historical out-of-sample validation attempt on 2023.07.01-2024.06.30 (a window no S1-S5 round had touched) was abandoned** because that window's `History Quality` came back at **0% real ticks** — no usable broker tick history reaches back that far. The one report that did complete on that window also failed htm/journal reconciliation by 15.18% (vs. 0.12%-0.31% on every training-window run), consistent with the tick data being unreliable. See `mt5/backtests/ai-maxret/S5_OOS_VALIDATION.md` for the full writeup. No further historical OOS attempts are planned — there is no older window with usable data.
- **Net effect: the 2y/1y/6m return, PF, and drawdown figures quoted below (e.g. 555.84% 2y return) carry meaningfully more uncertainty than the raw numbers suggest.** They are a reasonable basis for picking *between* candidates (the same tick-quality noise applies to both sides of every comparison), but they should not be read as a forecast of live/demo performance.
- **This is exactly why forward demo trading is the primary validation mechanism for this handoff, not a confirmatory afterthought.** The stop-conditions below are tightened relative to the original S3 handoff specifically because of this finding — see "Stop / pause conditions".

- **Aggressive primary**: `daily2-ai-s5-slwide-smcnorm`, preset `mt5/Presets/GoldBot.daily2-ai-s5-slwide-smcnorm.set`. Winner of the S5 SL-widening + risk-normalization round (`mt5/backtests/ai-maxret/S5_RESULTS.md`): best 2y AND 1y return among all candidates that pass the relaxed balance-DD gate (<25% on all three windows), with essentially the same PF/win-rate/consistency profile as its S4-slwide parent — a strict improvement on return with no DD cost. Override chain: `@daily2-ai-s4-slwide` (`InpScalpSlAtr=0.45`, `InpSlAtr=0.90`, inherited from `@daily2-ai-s3-risk115-splitclean` → `@daily2-ai-s2-risk115` → `@scalp-adaptive-daily2-monthlock25`) plus `InpSmcRiskMultiplier=1.0` (reset from the inherited 1.15x). Still not risk-free: balance DD is 22.72% at 2y (vs 8.54% equity DD), and 2y month consistency is 62.50% with a worst month of -8.39% and up to 2 consecutive negative months.
- **Conservative reference**: `daily2-monthlock25`, preset `mt5/Presets/GoldBot.forward-demo.scalp-adaptive-daily2-monthlock25.set`. Unchanged from the prior version of this doc — same base engine, 1.0x setup risk multipliers, no SL-widening or SMC-risk changes.

All numbers below are re-derived from `mt5/backtests/reports/*.summary.csv`, `*.evaluation.csv`, and `*.stability.csv` for the existing 6m/1y/2y windows (aggressive-primary figures cross-checked against `mt5/backtests/ai-maxret/S5_RESULTS.md`'s results table) — not copied blind from any prior write-up. **`net_profit` in these files is DOLLARS on a $1000 deposit; return % = net_profit / 1000 * 100.**

## Expected stats per window

### Aggressive primary — `daily2-ai-s5-slwide-smcnorm` (stem `GoldBot-real-daily2-ai-s5-slwide-smcnorm-ai-s5-<window>`)

| Window | Return % | PF | Equity DD % | Balance DD % | Trades | Win rate % | Month consistency % | Worst month % | Max consecutive neg months |
|---|---|---|---|---|---|---|---|---|---|
| 6m  | 363.20% | 4.84 | 9.04% | 5.72%  | 130 | 79.23% | 100.00% | +12.43% | 0 |
| 1y  | 554.93% | 3.86 | 8.55% | 22.85% | 239 | 74.06% | 75.00%  | -8.45%  | 2 |
| 2y  | 555.84% | 3.21 | 8.54% | 22.72% | 394 | 65.48% | 62.50%  | -8.39%  | 2 |

Unlike the old S3 winner (whose 2y net profit was *lower* than its 1y figure), this candidate's return keeps climbing from 1y to 2y (554.93% → 555.84%, essentially flat, not a reversal) while balance DD stays roughly flat too (22.85% → 22.72%). That is a more stable-looking shape than the S3 handoff had — but remember the data-quality caveat above applies to all of these numbers equally, so treat this as a *less bad* backtest signal, not a confirmed live edge.

### Conservative reference — `daily2-monthlock25` (stem `GoldBot-real-scalp-adaptive-daily2-monthlock25-ai-s1-<window>-1000`, unmodified `@scalp-adaptive-daily2-monthlock25` base)

| Window | Net profit ($) | Return % | PF | Equity DD % | Balance DD % | Trades | Win rate % | Trades/week | Stability |
|---|---|---|---|---|---|---|---|---|---|
| 6m  | 3230.19 | 323.02% | 4.65 | 10.20% | 4.83%  | 124 | 79.84% | 4.83 | STABLE (100% month consistency, worst month +7.78%, 0 consecutive negative months) |
| 1y  | 3880.22 | 388.02% | 3.49 | 9.87%  | 20.84% | 226 | 75.22% | 4.34 | STABLE (75.00% month consistency, worst month -7.74%, max 2 consecutive negative months) |
| 2y  | 3859.28 | 385.93% | 2.85 | 9.89%  | 20.96% | 383 | 67.62% | 3.64 | **UNSTABLE** (62.50% month consistency, worst month -7.79%, max 4 consecutive negative months) |

The baseline shows the same general shape (front-loaded gains, later-window softening, balance DD roughly quadrupling from 6m to 2y) but the gap to the aggressive build is narrower than it was for the old S3 winner: baseline still has a lower 2y balance DD (20.96% vs 22.72%) and fewer max consecutive negative months (4 vs 2 — note the aggressive build is actually *better* on this specific metric now), but a deeper worst month (-7.79% vs -8.39% for the aggressive build, i.e. the aggressive build's single worst month is larger). Net: the S5 `-slwide-smcnorm` overrides buy a large return lift (555.84% vs 385.93% at 2y) for a smaller, more mixed tail-risk cost than the old S3 build carried — but "smaller cost in the backtest" still needs demo confirmation given the tick-quality caveat above.

## Evaluation window

- Minimum before any verdict: **2–4 weeks of demo trading AND at least 30–50 closed trades**, whichever is later. At ~3.4–4.7 trades/week (2y-window pace), 30 trades takes roughly 6–9 weeks; do not shortcut this using the 6m-window pace (~4.7–4.8/week) since that window is the unrepresentative early-stable period.
- Track both candidates on the same calendar dates so market regime is comparable between them.
- Do not re-optimize or swap presets mid-window — a verdict requires a clean, unmodified run over the full evaluation period.

## Stop / pause conditions

**These are tighter than the original S3 handoff, specifically because of the tick-quality finding above** (24% real-tick training data, 0% real-tick OOS data) — confidence in the backtest numbers is lower than a normal SOFT-FAIL-free handoff, so the demo needs to catch trouble earlier rather than trusting the historical maxima as the effective ceiling.

Apply per candidate independently. Any one of the following triggers a **pause and review**, not necessarily a kill:

- Balance drawdown from demo start exceeds **10%** (tightened from the prior handoff's 15% threshold; well inside the 22.72%/20.96% 2y balance-DD range both candidates have shown historically, but now sized to catch trouble much earlier given the backtest numbers themselves are less trustworthy).
- Rolling profit factor drops below **1.5** after at least 30 closed trades.
- **3 consecutive losing weeks** (net P/L < 0 for the week).
- Any single week's loss exceeds the historical worst-month magnitude scaled to a week (~2% of balance) — early warning, not an automatic pause, but log it.

**Reassessment cadence: weekly**, not only at the 30-50 trade mark (tightened from the prior handoff, which only checked in at that milestone). Every week, re-derive running PF and max balance DD from the log table below and compare against the stop conditions above, even if no trigger has fired — the goal is to catch a developing problem within days, not to wait for a trade-count threshold to accumulate. The overall 30-50 trades / 2-4 week target window for a final verdict (see "Evaluation window" above) is unchanged; the weekly check-in is an earlier-warning layer on top of that, not a replacement for it.

On trigger: stop new entries (or flatten, if drawdown-triggered), do not resume until the log below and `.trades.csv`/`.htm` exports for the paused window have been reviewed against Phase 1 diagnostics (`mt5/backtests/ai-maxret/S3_RISK_DIAGNOSTICS.md`) to check whether the same setups/hours/exit patterns are repeating.

## Log table template

One row per calendar week per candidate. Running PF and max DD are cumulative from demo start.

| Date (week start) | Candidate | Trades this week | Net P/L ($) | Running PF | Max balance DD so far (%) | Notes |
|---|---|---|---|---|---|---|
| YYYY-MM-DD | daily2-ai-s5-slwide-smcnorm | | | | | |
| YYYY-MM-DD | daily2-monthlock25 | | | | | |

Fill "Notes" with anything that matches a known failure pattern from `mt5/backtests/ai-maxret/S3_RISK_DIAGNOSTICS.md` (e.g. "SL streak on m5_scalp hour 8", "long12 split2 losses recurring").
