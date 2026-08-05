# FundingPips M1 Short Hour-10 Shadow-Suppression Plan

Date: 2026-08-06  
Scope: `GoldBot` on XAUUSD, FundingPips 2-Step Phase 1, canonical risk 0.50%

## Status

This plan freezes a single negative-set trimming hypothesis before any
qualification runs. It does not change live or tester order behavior.

## Discovery evidence

The H1 2026 attribution control found two setup/direction/hour cohorts that
passed the preliminary sample/PF screen:

| Cohort | Closed positions | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| `m1_micro_scalp`, short, hour 10 | 11 | -$363.86 | 0.67 | 54.55% |
| `m5_scalp`, short, hour 8 | 14 | -$125.28 | 0.89 | 64.29% |

The first cohort is frozen because it has the larger loss and materially lower
PF. H1 2026 is discovery evidence only and is consumed; it cannot qualify the
hypothesis.

## Frozen hypothesis

Counterfactually suppress complete positions whose immutable entry metadata is:

- `setup=m1_micro_scalp`
- `dir=-1`
- `hour=10`

The analysis includes every deal attached to each matched position, including
entry costs and all closing legs. It must reconcile complete-position P&L and
trade counts to the stitched chain manifest.

## Design

This stage is analyzer-only and shadow-only:

1. Run fresh stateful controls at the canonical 0.50% P1 risk.
2. Preserve the current EA order path.
3. Reconstruct complete position P&L from the journals.
4. Compare the real closed-position balance path with a counterfactual path
   that omits the frozen cohort.
5. Fail closed on missing journals, hash mismatch, non-flat state, trade-count
   mismatch, P&L reconciliation failure, or metadata drift.

The counterfactual does not model changed downstream sizing or slot occupancy.
Passing therefore authorizes only a later tester-only shadow implementation,
not an active filter.

## Frozen windows

Train/consistency:

- H1 2025
- H2 2025

Locked validation:

- H1 2024
- H2 2024

H1/H2 2025 are already consumed research windows. Both 2024 halves remain
locked until this command is run. MT5 runs must remain sequential.

## Frozen falsification gates

Every gate must pass:

### Per train half

- at least 4 matched complete positions;
- cohort net P&L below zero.

### Combined train 2025

- at least 10 matched complete positions;
- cohort PF no greater than 0.95.

### Per locked-validation half

- at least 4 matched complete positions;
- cohort net P&L no greater than zero, so suppression does not harm either half;
- counterfactual closed-balance drawdown may worsen by no more than 0.05
  percentage points.

### Combined locked validation 2024

- at least 10 matched complete positions;
- cohort PF no greater than 0.95;
- counterfactual benefit at least 0.25% of the $50,000 challenge deposit.

## Decisions

- `FALSIFIED`: retire the hypothesis. Do not tune its hour, PF threshold,
  direction, setup, sample gate, or windows.
- `PASS_SHADOW_IMPLEMENTATION_ONLY`: implement a separately reviewed
  tester-only shadow gate and compare it with fresh behavior-identical controls.
  Do not create an active preset yet.

## Command

```bash
bash scripts/run-fundingpips-m1-short-hour10-shadow-study.sh
```

Optional naming/deposit override:

```bash
DEPOSIT=50000 \
PREFIX=GoldBot-fundingpips-m1-short-hour10-shadow \
bash scripts/run-fundingpips-m1-short-hour10-shadow-study.sh
```

Outputs are written under `mt5/backtests/reports/` as study CSV, gate CSV, and
decision JSON. Generated reports remain ignored and must not be committed.
