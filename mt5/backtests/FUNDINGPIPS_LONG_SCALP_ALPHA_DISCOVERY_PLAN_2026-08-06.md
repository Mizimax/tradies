# FundingPips Long-Scalp Alpha Discovery Plan

Date frozen: 2026-08-06

## Decision context

The accepted 0.50% FundingPips baseline is profitable and low drawdown, but no
observed 30-day or 60-day window reached the 8% Phase-1 target. Static hour
suppression and cross-day scalp pauses were rejected by consumed-history
analysis. The next experiment must add alpha rather than remove existing trades
or increase risk.

## Frozen candidates

This screen uses only long-side execution paths that already exist in GoldBot
but are disabled in the accepted preset. No new entry rule and no hour search is
introduced.

1. `m5-long`
   - `InpScalpLongHours=7;10;12;18`
   - `InpM1MicroLongHours=99`
2. `m1-long`
   - `InpScalpLongHours=99`
   - `InpM1MicroLongHours=10;18`

The hours are the code defaults that pre-date this experiment. The accepted
short-side setup, prop controls, and 0.50% challenge risk remain unchanged.
Retired mechanisms remain disabled:

- `InpEnableContinuationPullbackSetup=false`
- `InpEnableContinuationCausalShadow=false`
- `InpEnableScalpFailureExit=false`

## Discovery evidence

The candidates are compared against accepted baseline manifests for:

- H1 2024
- H2 2024
- H1 2025
- H2 2025
- H1 2026

These periods are already consumed research evidence. Candidate chains run
sequentially and use the same preset, source hashes, EX5 hash, deposit, and risk.

## Frozen gates

A candidate must pass every gate:

- at least 20 matching long-alpha closing trades combined;
- matching long-alpha PF at least 1.10;
- positive long-alpha net in at least 3 of 5 windows;
- positive total-portfolio delta in at least 3 of 5 windows;
- combined total-portfolio improvement at least 2.0% of the $50,000 deposit;
- total-portfolio PF at least 1.15;
- total-portfolio PF no more than 0.05 below baseline;
- equity-DD worsening no more than 0.75 percentage points in every window.

If both candidates pass, select the one with the larger combined portfolio
delta. DD worsening and alpha PF are fixed tie-breakers.

## Locked validation policy

The screen may select at most one candidate. Selection authorizes only a single
locked 2023 validation using the same frozen hours, preset, and risk. H1/H2 2023
must not be run before selection. A discovery failure retires both candidates;
hours and gates must not be tuned after seeing the result.

No discovery or validation pass authorizes live deployment. The surviving
portfolio must still be re-run through pass-speed and prop-rule qualification.
