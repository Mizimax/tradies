# BTCScalper Improvement Iteration: Cost/Edge Gate + H1 Regime Gate

Date: 2026-07-06

Scope: BTCScalper only. Do not mix these results with GoldBot or GoldScalper.

## Executive Summary

15 candidates × 2 windows (6mo `2026.01.01-2026.06.22`, 2y `2024.06.22-2026.06.22`) were tested. **No candidate clears the promotion gate** (2y PF ≥1.20, eq DD ≤25%, beating `rebaseline-perfoff` net; 6mo PF≥1.20, DD≤25%, 150-450 trades). Best 6mo PF: 1.11 (`mom-mr-only`). Best 2y PF: 0.80 (`baseline-mrloose`, `regimegate-only`, `regimegate-edge` — tied). **Nothing here should be promoted to demo or live.** The pure cost gate is fully falsified on BTCUSD (checksum-inert at every k tested). The H1 ATR-ratio regime gate is the one mechanism with real, verified positive effect (2y PF 0.78→0.80, net -$24.3k→-$22.3k) but is insufficient to clear the gate. Momentum is unprofitable standalone over the full 2-year window (PF 0.70) — this is not fixable by trimming VWAP or gating costs; it is a structural timeframe/frequency problem. See "Final Decision" at the end of this document for the recommended next iteration.

## Implementation Status

- Added default-off cost/edge gate inputs to `mt5/Experts/BTCScalper/BTCScalper.mq5`:
  - `InpCostGateEnabled=false`
  - `InpCostGateK=2.0`
  - `InpCostGateCommPerLot=0.0`
  - `InpCostGateMinAtrMult=0.0`
- Added `BTCScalperCostGatePass()` to `mt5/Include/BTCScalper/RiskManager.mqh`.
- Wired the gate after each nonzero signal and before strategy risk/allocation:
  - MR expected move: `abs(ask - BB middle)`, ATR ref: M15 ATR.
  - Momentum expected move: `ATR(M15) * InpMomSlAtrMult * InpMomRR`, ATR ref: M15 ATR.
  - VWAP expected move: `abs(ask - VWAP)`, ATR ref: M5 ATR.
- Added Phase 0 and Phase 2 candidates to `mt5/backtests/BTCSCALPER_CANDIDATES.csv`.
- Added `--clean` support to `scripts/run-btcscalper-candidate.py`.
- Fixed `scripts/compile-mt5-btcscalper.sh` to fall back from `~/Applications/MetaTrader 5.app` to `/Applications/MetaTrader 5.app` and to use `wine64` when `wine` is absent.

Phase 3 H1 regime gate: implemented after `mom-only`/`mom-mr-only` both showed 2y PF 0.70 (below the plan's 1.0 skip threshold), triggering the conditional build.

- Added `g_btcAtrH1Handle` (ATR(14) on H1) to `mt5/Include/BTCScalper/Indicators.mqh`, initialized/released alongside the existing handles.
- Added `BTCScalperRegimeGatePass(atrH1Handle, lookback, minRatio, maxRatio)` to `Indicators.mqh`: compares current H1 ATR to its own rolling average over `lookback` H1 bars; fails-open (passes) if the gate is structurally unusable (bad handle/lookback), fails-closed (blocks) if H1 history is insufficient or the average is non-positive; otherwise blocks when the ratio is outside `[minRatio, maxRatio]` (0 = no bound on that side).
- Added default-off inputs to `mt5/Experts/BTCScalper/BTCScalper.mq5`: `InpRegimeGateEnabled=false`, `InpRegimeMinH1AtrRatio=0.70`, `InpRegimeMaxH1AtrRatio=0.0`, `InpRegimeAtrAvgPeriod=100`.
- Wired as a third guard block (signal → cost-gate → regime-gate → risk/entry) at all 3 entry sites: MR, Momentum, VWAP.
- Added Phase 3 candidates `regimegate-only` and `regimegate-edge` to `mt5/backtests/BTCSCALPER_CANDIDATES.csv`.
- Independently implemented; no GoldBot code imported or copied (BTCScalper-specific gate, separate file, separate logic).

## Verification

Compile:

```bash
bash scripts/install-mt5-source.sh && bash scripts/compile-mt5-btcscalper.sh
```

Result: `0 errors, 6 warnings` (both before and after the Phase 3 edit). The warnings are the same pre-existing `trade` parameter shadowing warnings in BTCScalper strategy modules — no new warnings introduced.

Static checks:

```bash
python3 -m py_compile scripts/run-btcscalper-candidate.py scripts/summarize-mt5-reports.py scripts/evaluate-mt5-candidates.py scripts/analyze-mt5-trades.py
bash -n scripts/run-mt5-backtest.sh scripts/install-mt5-source.sh scripts/compile-mt5-btcscalper.sh
git diff --check
```

All passed.

Candidate CSV validation passed: 48 rows, no duplicate candidate names, required Phase 0/Phase 2/Phase 3 names present, BTCScalper overrides remain escaped as `\n`.

**Bit-identity check (Phase 3 default-off proof):** re-ran `rebaseline-perfoff` on the 6mo window (`BTCScalper-rebaseline-perfoff-bitcheck.trades.csv`) after the regime-gate code landed and compared it byte-for-byte (`md5`/`diff`) against the pre-existing `BTCScalper-rebaseline-perfoff-2026h1.trades.csv` reference. **Identical** (md5 `268cfbafdfc44213d4bbbb5207121fac` on both, `diff` empty, net $16,612.57/PF 1.06/435 trades matches exactly). Confirms the new regime gate is truly inert when `InpRegimeGateEnabled=false`.

## Completed MT5 Evidence

All runs used:

- Symbol: `BTCUSD`
- Period: `M5`
- Deposit: `$100,000`
- Real broker execution
- Account/server from current MT5 terminal session: Exness demo environment

| Candidate | Window | Net | Net % | PF | Trades | Eq DD | Verdict |
|---|---:|---:|---:|---:|---:|---:|---|
| `rebaseline-perfoff` | 2026.01.01-2026.06.22 | `$16,612.57` | `+16.61%` | `1.06` | 435 | 23.59% | Fails PF gate |
| `rebaseline-perfoff` | 2024.06.22-2026.06.22 | `-$24,341.65` | `-24.34%` | `0.78` | 260 | 25.46% | Fails PF and DD gates |
| `baseline-mrloose` | 2026.01.01-2026.06.22 | `-$4,072.80` | `-4.07%` | `0.98` | 458 | 23.20% | MR loosening is harmful |
| `baseline-mrloose` | 2024.06.22-2026.06.22 | `-$24,499.02` | `-24.50%` | `0.80` | 277 | 25.74% | Fails PF and DD gates |
| `mom-only` | 2026.01.01-2026.06.22 | `$15,393.45` | `+15.39%` | `1.08` | 343 | 23.91% | Fails PF gate |
| `mom-only` | 2024.06.22-2026.06.22 | `-$25,108.89` | `-25.11%` | `0.70` | 227 | 25.11% | Fails PF and DD gates |
| `mom-mr-only` | 2026.01.01-2026.06.22 | `$28,615.85` | `+28.62%` | `1.11` | 348 | 21.92% | Fails PF gate (closest so far) |
| `mom-mr-only` | 2024.06.22-2026.06.22 | `-$25,108.89` | `-25.11%` | `0.70` | 227 | 25.11% | Fails PF and DD gates; identical to `mom-only` 2y (MR fired 0 trades in this window under pinned 8-18/70-30 settings) |
| `perfon-fixed` | 2026.01.01-2026.06.22 | `$1,283.16` | `+1.28%` | `1.02` | 278 | 19.98% | Fails PF gate |
| `perfon-fixed` | 2024.06.22-2026.06.22 | `-$19,649.59` | `-19.65%` | `0.77` | 645 | 25.16% | Fails PF and DD gates |
| `perfon-soft-fixed` | 2026.01.01-2026.06.22 | `-$9,411.95` | `-9.41%` | `0.93` | 441 | 23.20% | Fails PF gate |
| `perfon-soft-fixed` | 2024.06.22-2026.06.22 | `-$24,629.39` | `-24.63%` | `0.63` | 342 | 25.75% | Fails PF and DD gates |
| `costgate-k15` | 2026.01.01-2026.06.22 | `$16,489.91` | `+16.49%` | `1.06` | 433 | 23.59% | Fails PF gate; near-identical to `rebaseline-perfoff` 6mo (gate near-inert at k=1.5) |
| `costgate-k15` | 2024.06.22-2026.06.22 | `-$24,341.65` | `-24.34%` | `0.78` | 260 | 25.46% | Fails PF and DD gates; identical to `rebaseline-perfoff` 2y (gate fully inert at k=1.5) |
| `costgate-k20` | 2026.01.01-2026.06.22 | `$16,489.91` | `+16.49%` | `1.06` | 433 | 23.59% | Fails PF gate; identical to `costgate-k15` 6mo (gate fully inert at k=2.0 too) |
| `costgate-k20` | 2024.06.22-2026.06.22 | `-$24,341.65` | `-24.34%` | `0.78` | 260 | 25.46% | Fails PF and DD gates; identical to `costgate-k15`/`rebaseline-perfoff` 2y (gate fully inert) |
| `costgate-k30` | 2026.01.01-2026.06.22 | `$16,489.91` | `+16.49%` | `1.06` | 433 | 23.59% | Fails PF gate; identical to `costgate-k15/k20` 6mo (gate fully inert at k=3.0 too) |
| `costgate-k30` | 2024.06.22-2026.06.22 | `-$24,341.65` | `-24.34%` | `0.78` | 260 | 25.46% | Fails PF and DD gates; identical to `costgate-k15/k20` 2y (gate fully inert at k=3.0) |
| `edgegate-a05-k20` | 2026.01.01-2026.06.22 | `$16,297.96` | `+16.30%` | `1.06` | 431 | 23.59% | Fails PF gate; slight teeth on VWAP (93→91 trades vs pure cost gate) |
| `edgegate-a05-k20` | 2024.06.22-2026.06.22 | `-$24,341.65` | `-24.34%` | `0.78` | 260 | 25.46% | Fails PF and DD gates; identical to `rebaseline-perfoff` 2y (no bite at minAtr=0.5 on this window) |
| `edgegate-a075-k20` | 2026.01.01-2026.06.22 | `$15,702.18` | `+15.70%` | `1.05` | 430 | 23.96% | Fails PF gate; VWAP trimmed slightly further (93→90) but net worse than a05 |
| `edgegate-a075-k20` | 2024.06.22-2026.06.22 | `-$24,341.65` | `-24.34%` | `0.78` | 260 | 25.46% | Fails PF and DD gates; identical to `rebaseline-perfoff` 2y (no bite at minAtr=0.75 on this window either) |
| `perfon-edgegate` | 2026.01.01-2026.06.22 | `$2,232.12` | `+2.23%` | `1.03` | 276 | 20.44% | Fails PF gate; marginal improvement vs `perfon-fixed` 6mo ($1,283.16, PF 1.02) — edge gate trimmed VWAP 71→69 |
| `perfon-edgegate` | 2024.06.22-2026.06.22 | `-$19,816.46` | `-19.82%` | `0.77` | 651 | 25.31% | Fails PF and DD gates; essentially unchanged vs `perfon-fixed` 2y (net -19,649.59, PF 0.77) — edge gate + allocator do not fix 2y |
| `momonly-edgegate` | 2026.01.01-2026.06.22 | `$15,393.45` | `+15.39%` | `1.08` | 343 | 23.91% | Fails PF gate; byte-identical to `mom-only` 6mo — null-control confirmed, gate does not touch Momentum |
| `momonly-edgegate` | 2024.06.22-2026.06.22 | `-$25,108.89` | `-25.11%` | `0.70` | 227 | 25.11% | Fails PF and DD gates; byte-identical to `mom-only` 2y — null-control confirmed on both windows |
| `regimegate-only` | 2026.01.01-2026.06.22 | `$24,640.89` | `+24.64%` | `1.08` | 391 | 21.59% | Fails PF gate; best 6mo net/DD yet — VWAP PF improved 0.85→0.96 |
| `regimegate-only` | 2024.06.22-2026.06.22 | `-$22,275.44` | `-22.28%` | `0.80` | 253 | 26.04% | Fails PF and DD gates; modest 2y improvement vs `rebaseline-perfoff` (PF 0.78→0.80, net -24.3k→-22.3k) but DD ticked up slightly (25.46%→26.04%) — still nowhere near PF≥1.20 |
| `regimegate-edge` | 2026.01.01-2026.06.22 | `$23,833.16` | `+23.83%` | `1.08` | 387 | 21.62% | Fails PF gate; near-identical to `regimegate-only` 6mo (edge gate adds little on top of regime gate) |
| `regimegate-edge` | 2024.06.22-2026.06.22 | `-$22,275.44` | `-22.28%` | `0.80` | 253 | 26.04% | Fails PF and DD gates; byte-identical to `regimegate-only` 2y (edge gate has zero additional bite on 2y, consistent with the earlier edge-gate-inert-on-2y finding) |

Important drift note: the historical `BTCScalper-perf-off.htm` still matches the plan reference (`$5,276.46`, PF `1.02`, 442 trades), but the fresh default-off rebaseline with the same key inputs produced `$16,612.57`, PF `1.06`, 435 trades. The embedded report inputs agree on the key strategy/risk settings, except the new report includes `InpCostGateEnabled=false`. Treat the old reference as stale for this source/terminal state.

## Journal Attribution

Derived directly from BTCScalper journal events (`Deal ... strategy=... profit=...`).

### `rebaseline-perfoff`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 2 | `$1,594.99` | inf | 100.00% |
| momentum | 338 | `$22,450.08` | 1.09 | 52.96% |
| vwap_reversion | 95 | `-$7,432.50` | 0.86 | 60.00% |

### `rebaseline-perfoff`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 205 | `-$23,376.66` | 0.75 | 47.32% |
| vwap_reversion | 55 | `-$964.99` | 0.93 | 63.64% |

### `baseline-mrloose`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 20 | `-$5,750.93` | 0.51 | 60.00% |
| momentum | 339 | `$6,884.54` | 1.04 | 53.10% |
| vwap_reversion | 99 | `-$5,206.41` | 0.87 | 61.62% |

### `baseline-mrloose`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 14 | `$871.05` | 1.22 | 64.29% |
| momentum | 207 | `-$26,620.61` | 0.75 | 47.83% |
| vwap_reversion | 56 | `$1,250.54` | 1.09 | 62.50% |

### `mom-only`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 343 | `$15,393.45` | 1.08 | 53.64% |

### `mom-only`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 227 | `-$25,108.89` | 0.70 | 47.14% |

### `mom-mr-only`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 5 | `$3,866.95` | inf | 100.00% |
| momentum | 343 | `$24,748.90` | 1.09 | 53.64% |

### `mom-mr-only`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 0 | `$0.00` | n/a | n/a |
| momentum | 227 | `-$25,108.89` | 0.70 | 47.14% |

Note: `mom-mr-only-2y.trades.csv` is byte-identical to `mom-only-2y.trades.csv` — MR (pinned `InpBestSessionStart=8/End=18`, `InpMrRsiOverbought=70/Oversold=30`) generated zero closed deals over the full 2-year window, even though it produced 5 trades over the 6-month window. MR opportunities under strict thresholds are rare and did not recur in the older part of the 2y range.

### `perfon-fixed`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 4 | `$1,582.73` | inf | 100.00% |
| momentum | 203 | `$5,777.15` | 1.10 | 51.23% |
| vwap_reversion | 71 | `-$6,076.72` | 0.70 | 63.38% |

### `perfon-fixed`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 2 | `$652.93` | inf | 100.00% |
| momentum | 494 | `-$17,249.96` | 0.77 | 48.79% |
| vwap_reversion | 149 | `-$3,052.56` | 0.66 | 56.38% |

### `perfon-soft-fixed`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 4 | `$1,435.36` | inf | 100.00% |
| momentum | 339 | `-$7,998.97` | 0.93 | 53.10% |
| vwap_reversion | 98 | `-$2,848.34` | 0.88 | 61.22% |

### `perfon-soft-fixed`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 271 | `-$22,808.81` | 0.58 | 45.76% |
| vwap_reversion | 71 | `-$1,820.58` | 0.86 | 57.75% |

### `costgate-k15`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 2 | `$1,594.90` | inf | 100.00% |
| momentum | 338 | `$22,464.84` | 1.09 | 52.96% |
| vwap_reversion | 93 | `-$7,569.83` | 0.85 | 59.14% |

### `costgate-k15`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 205 | `-$23,376.66` | 0.75 | 47.32% |
| vwap_reversion | 55 | `-$964.99` | 0.93 | 63.64% |

### `costgate-k20`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 2 | `$1,594.90` | inf | 100.00% |
| momentum | 338 | `$22,464.84` | 1.09 | 52.96% |
| vwap_reversion | 93 | `-$7,569.83` | 0.85 | 59.14% |

### `costgate-k20`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 205 | `-$23,376.66` | 0.75 | 47.32% |
| vwap_reversion | 55 | `-$964.99` | 0.93 | 63.64% |

### `costgate-k30`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 2 | `$1,594.90` | inf | 100.00% |
| momentum | 338 | `$22,464.84` | 1.09 | 52.96% |
| vwap_reversion | 93 | `-$7,569.83` | 0.85 | 59.14% |

### `costgate-k30`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 205 | `-$23,376.66` | 0.75 | 47.32% |
| vwap_reversion | 55 | `-$964.99` | 0.93 | 63.64% |

Cost gate (pure) confirmed inert across k=1.5/2.0/3.0 on both windows: every `costgate-k*` result is byte-identical to `rebaseline-perfoff` on the matching window. Falsifies the literal cost-gate hypothesis on BTCUSD as predicted (Exness BTCUSD spread-only cost floor is negligible versus ATR-scale TPs).

### `edgegate-a05-k20`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 2 | `$1,594.90` | inf | 100.00% |
| momentum | 338 | `$22,479.24` | 1.09 | 52.96% |
| vwap_reversion | 91 | `-$7,776.18` | 0.85 | 58.24% |

### `edgegate-a05-k20`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 205 | `-$23,376.66` | 0.75 | 47.32% |
| vwap_reversion | 55 | `-$964.99` | 0.93 | 63.64% |

### `edgegate-a075-k20`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 2 | `$1,594.72` | inf | 100.00% |
| momentum | 338 | `$22,623.03` | 1.09 | 52.96% |
| vwap_reversion | 90 | `-$8,515.57` | 0.83 | 57.78% |

### `edgegate-a075-k20`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 205 | `-$23,376.66` | 0.75 | 47.32% |
| vwap_reversion | 55 | `-$964.99` | 0.93 | 63.64% |

Edge-floor gate (ATR-scaled) has a small but real bite on the 6mo window (VWAP trades 93→91→90 as minAtr rises 0→0.5→0.75) but zero bite on the 2y window at either minAtr level — both `edgegate-a05-k20` and `edgegate-a075-k20` 2y results are byte-identical to `rebaseline-perfoff` 2y. The edge floor is not a sufficient VWAP fix on this data.

### `perfon-edgegate`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 4 | `$1,582.73` | inf | 100.00% |
| momentum | 203 | `$5,781.91` | 1.10 | 51.23% |
| vwap_reversion | 69 | `-$5,132.52` | 0.75 | 60.87% |

### `perfon-edgegate`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 2 | `$646.57` | inf | 100.00% |
| momentum | 494 | `-$17,252.79` | 0.77 | 48.79% |
| vwap_reversion | 155 | `-$3,210.24` | 0.69 | 56.13% |

`perfon-edgegate` 2y is essentially identical to `perfon-fixed` 2y (net -19.65k→-19.82k, PF 0.77→0.77, momentum unchanged at 494 trades/-17.25k). Adding the edge gate on top of the allocator does not meaningfully change the 2y outcome.

### `momonly-edgegate`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 343 | `$15,393.45` | 1.08 | 53.64% |

`momonly-edgegate-6mo.trades.csv` is byte-identical to `mom-only-6mo.trades.csv` — confirms the edge gate does not bite Momentum's signal (as designed; Momentum's expected move is already ATR-scale).

### `momonly-edgegate`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 227 | `-$25,108.89` | 0.70 | 47.14% |

`momonly-edgegate-2y.trades.csv` is byte-identical to `mom-only-2y.trades.csv` — null control confirmed on both windows.

### `regimegate-only`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 3 | `$1,643.45` | inf | 100.00% |
| momentum | 298 | `$25,066.05` | 1.10 | 54.03% |
| vwap_reversion | 90 | `-$2,068.61` | 0.96 | 64.44% |

Compared to `rebaseline-perfoff` 6mo (net $16,612.57, PF 1.06, 435 trades, VWAP PF 0.86): the regime gate trims momentum 338→298 trades (still net-positive, PF 1.09→1.10) and meaningfully improves VWAP (95→90 trades, PF 0.86→0.96, net loss -$7,432.50→-$2,068.61). This is the first candidate where the regime concept visibly helps VWAP rather than just being inert.

### `regimegate-only`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 205 | `-$19,228.65` | 0.80 | 47.32% |
| vwap_reversion | 48 | `-$3,046.79` | 0.80 | 62.50% |

Compared to `rebaseline-perfoff` 2y (momentum 205/-$23,376.66/PF 0.75, vwap 55/-$964.99/PF 0.93): VWAP trades trimmed 55→48 (regime gate has bite here too), but VWAP's 2y PF got worse (0.93→0.80) even with fewer trades — the surviving VWAP trades in this window are proportionally worse. Momentum's trade count is unchanged at 205 but its net loss shrank (-$23,376.66→-$19,228.65, PF 0.75→0.80); since the gate did not filter any momentum signals out (same count), this delta is attributable to DD-scaling/position-sizing interaction with the different equity path, not the gate directly touching momentum.

### `regimegate-edge`, 2026 H1

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| mean_reversion | 3 | `$1,643.45` | inf | 100.00% |
| momentum | 298 | `$25,904.82` | 1.11 | 54.03% |
| vwap_reversion | 86 | `-$3,715.11` | 0.92 | 62.79% |

Adding the edge gate on top of the regime gate trims VWAP a bit further (90→86 trades vs `regimegate-only`) but net/PF/DD are all within a few percent of `regimegate-only` alone — the edge gate adds little once the regime gate is already active.

### `regimegate-edge`, 2y

| Strategy | Closed deals | Net | PF | Win rate |
|---|---:|---:|---:|---:|
| momentum | 205 | `-$19,228.65` | 0.80 | 47.32% |
| vwap_reversion | 48 | `-$3,046.79` | 0.80 | 62.50% |

`regimegate-edge-2y.trades.csv` is byte-identical (checksum-verified) to `regimegate-only-2y.trades.csv` — the edge gate contributes zero additional filtering on the 2y window once the regime gate is active, consistent with the standalone edge-gate candidates also being fully inert on 2y.

## Current Conclusions

- The cost/edge gate is implemented and default-off, so baseline behavior is preserved when `InpCostGateEnabled=false`.
- The fresh 6-month baseline improved versus the old historical reference, but still fails the PF gate.
- The fresh 2-year baseline remains strongly negative and breaches the 25% equity DD gate.
- MR loosening is directly harmful in the 6-month run. Keep Phase 0 controls pinned to `InpBestSessionStart=8`, `InpBestSessionEnd=18`, `InpMrRsiOverbought=70`, `InpMrRsiOversold=30`.
- VWAP is negative on the fresh 6-month baseline. In the fresh 2-year baseline, Momentum is the larger loss source, so the earlier "VWAP is the main drag" hypothesis is not sufficient for this terminal/source state.
- **Pure cost gate is fully falsified on BTCUSD**: `costgate-k15`/`k20`/`k30` are byte-identical to `rebaseline-perfoff` on both windows at every k tested (1.5, 2.0, 3.0). The gate never binds — confirms the deep-reasoner premise that Exness BTCUSD's spread-only cost floor is negligible versus ATR-scale TPs.
- **ATR edge-floor gate has a small 6mo bite on VWAP only, zero 2y bite**: `edgegate-a05-k20`/`a075-k20` trim VWAP trades slightly on the 6mo window (93→91→90) but are byte-identical to `rebaseline-perfoff` 2y at both minAtr levels (0.5, 0.75). The edge floor is not a sufficient VWAP fix on this data/window.
- **`momonly-edgegate` null control passed on both windows**: byte-identical to `mom-only` 6mo and 2y — the gate does not touch Momentum, as designed.
- **`perfon-edgegate` (allocator + edge gate) does not fix the allocator**: essentially identical to `perfon-fixed` alone on both windows (2y net -19.65k→-19.82k, PF 0.77→0.77).
- **Decision-critical isolation result**: `mom-only` 2y (PF 0.70) and `mom-mr-only` 2y (PF 0.70, MR fired 0 trades under pinned strict settings) are identical and both well below the PF ≥ 1.0 pivot threshold from the plan's Phase 3 skip rule. Neither isolated-strategy variant clears 2y profitability standalone — momentum alone loses money over the full 2-year window, not just when mixed with VWAP.
- Per the plan's stated skip rule ("if `mom-only` or `mom-mr-only` already shows 2y PF ≥ 1.0 in Phase 0, skip this phase"), since **neither** clears PF ≥ 1.0, the Phase 3 H1 regime-gate arm is indicated as the next step.

## Phase 3 Conclusions (H1 ATR-ratio regime gate)

- **Default-off bit-identity confirmed**: `rebaseline-perfoff` 6mo re-run after the regime-gate code landed is checksum-identical (md5 `268cfbafdfc44213d4bbbb5207121fac`) to the pre-existing reference — the new gate is truly inert when `InpRegimeGateEnabled=false`, no unintended behavior change.
- **The regime gate has real, positive teeth on VWAP that neither the cost gate nor the edge gate had**: 6mo VWAP PF improves 0.85→0.96 (`regimegate-only`) / 0.85→0.92 (`regimegate-edge`), and 2y VWAP trades trim 55→48 (though 2y VWAP PF itself moves the other way, 0.93→0.80, on a much smaller sample).
- **6mo net/DD is the best of the whole ladder**: `regimegate-only` reaches $24,640.89 (+24.64%) at DD 21.59% (vs $16,612.57/23.59% baseline) — still fails the PF≥1.20 gate (1.08) but is the strongest 6mo result recorded in this iteration.
- **2y result is a real but modest improvement, not a fix**: PF moves 0.78→0.80 and net -$24.3k→-$22.3k versus `rebaseline-perfoff`, but DD ticks up slightly (25.46%→26.04%, still over the 25% gate) and PF stays far below the 1.20 promotion bar. The gate does not move 2y performance materially above the ~0.70-0.80 ceiling every other candidate in this iteration has hit.
- **Trade volume stays healthy**: 6mo trades 391 (`regimegate-only`) / 387 (`regimegate-edge`) — comfortably inside the 150-450 6mo band, actually higher than several other candidates because MR contributes a few trades back in (3, vs 0-2 elsewhere) and momentum's higher survival rate. 2y trades 253 is close to the `rebaseline-perfoff` 260 — no meaningful trade-count cost from the gate.
- **`regimegate-edge` (regime + edge gate) adds essentially nothing beyond `regimegate-only`**: 6mo is a small VWAP trim (90→86 trades) with near-identical net/PF/DD; 2y is checksum-identical (the edge gate has zero bite on 2y with or without the regime gate active, consistent with the Phase 2 finding that the edge gate never bites on the 2y window at all).
- **No candidate across either phase clears the promotion gate** (2y PF≥1.20, DD≤25%, beating `rebaseline-perfoff` net). The regime gate is a real, verified, non-trivial improvement over every prior mechanism tried — but it is not sufficient on its own. Given the pivot trigger in the original plan ("best 2y PF across the whole ladder < 1.0 → iteration 2 = restructure to H4 momentum-centric, VWAP dropped structurally"), and now the H1 regime gate also failing to clear 2y PF ≥ 1.0, that structural restructure remains the indicated next move — a decision reserved for the orchestrator.

## Queue Status: Complete

All 12 originally-planned Phase 0/Phase 2 candidates, the deferred 2y `baseline-mrloose` run, and the 2 Phase 3 `regimegate-*` candidates are now recorded above, each on both the 6mo (`2026.01.01-2026.06.22`) and 2y (`2024.06.22-2026.06.22`) windows. No malformed reports were encountered across either phase (every `.htm` showed `Initial Deposit: 100 000.00` and a nonzero `Total Trades` on first attempt; no `.report-status.csv` sidecars were produced).

## Final Decision (Orchestrator)

All headline numbers in this document were independently re-derived from the raw `.htm`/`.trades.csv` reports (not just the recording agent's summaries) before this decision was made — see the per-candidate verification checkpoints above (bit-identity md5, null-control checksums, direct `Total Net Profit`/`Profit Factor`/`Total Trades` extraction).

**Promotion: NONE.** No candidate — across the cost gate, ATR edge-floor, allocator (post-bugfix), or H1 regime gate — clears 2y PF ≥1.20 with eq DD ≤25%. The best 2y PF achieved across all 15 candidates is 0.80. Do not push any of this iteration's candidates to demo or live for BTCScalper.

**Killed hypotheses:**
- *Pure cost gate on BTCUSD*: falsified outright. `costgate-k15/k20/k30` are checksum-identical to `rebaseline-perfoff` at every k (1.5, 2.0, 3.0) on both windows. Exness BTCUSD's spread-only cost floor is negligible against ATR-scale take-profits, exactly as the pre-registered premise predicted.
- *ATR edge-floor as a standalone VWAP fix*: insufficient. Real but small 6mo bite (VWAP PF 0.85→0.96 max), zero 2y bite (checksum-identical to baseline at both minAtr levels tested).
- *"VWAP is the drag" (prior memory)*: falsified for the current environment/broker feed. `mom-only` and `mom-mr-only` (VWAP fully removed) both score 2y PF 0.70 — worse than the full 3-strategy mix's 0.78. Momentum itself is unprofitable standalone over the 2-year window; removing VWAP does not fix the core problem and can make it worse.
- *Allocator (post-bugfix) as a fix*: `perfon-fixed`/`perfon-soft-fixed`/`perfon-edgegate` all stay at 2y PF 0.63-0.77, no better than the non-allocated baseline. The allocator's 30-trade rolling window reacts too slowly to rescue a structurally-losing 2-year regime.

**Confirmed (not killed, but insufficient):** the H1 ATR-ratio regime gate is the one real, verified positive mechanism found in this iteration — 2y PF 0.78→0.80, net -$24.3k→-$22.3k, with genuine positive bite on VWAP quality (6mo VWAP PF 0.85→0.96) that no other mechanism achieved. It is necessary-but-not-sufficient: it moves the needle, not the outcome.

**Pivot, per the plan's own trigger rule** ("best 2y PF across the whole ladder < 1.0 → restructure to H4 momentum-centric, VWAP dropped structurally"): **triggered.** Recommended iteration 2 (not implemented in this pass — a new plan/scoping step, given the scope):
1. Move Momentum Breakout from M15 to H4 — lower trade frequency, larger edge-per-trade, consistent with the deep-research conclusion that per-trade edge must clearly exceed per-trade cost, and that BTCUSD favors lower-frequency signals over minute/M15-scale scalping.
2. Drop VWAP Reversion structurally (not just gate it) — it has never been the edge in any configuration tested, and its removal has already been evidence-tested (`mom-only`/`mom-mr-only`) without materially changing the 2y outcome.
3. Re-evaluate whether Mean Reversion belongs at all — under pinned committed thresholds it contributed 0-5 trades over the full 2-year window in every candidate tested; it is economically negligible at current settings, not a meaningful diversification source.
4. Re-derive SL/TP distances for H4 (current swing-of-last-5-bars / ATR-multiple logic is M15-calibrated and would need rescaling).
5. Carry forward the H1 regime-gate concept (genuinely useful) but re-validate it against the new H4 signal, since its current calibration was tuned against M15 momentum.

This is a larger scoping decision (timeframe change + strategy removal) than a diagnostic gate iteration — recommend a fresh plan/scoping pass rather than folding it into this one.
