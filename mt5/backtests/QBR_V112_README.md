# QBR v1.12 Reliability Research

QBR v1.12 fixes the permanent consecutive-loss lock, persists profit-lock arming,
caps aggregate add-on risk, installs a broker-native catastrophe stop, and exposes
pattern-level research controls. It is isolated from GoldBot and GoldScalper.

## Compile

```bash
bash scripts/compile-mt5-qbr.sh
```

Acceptance is `0 errors`. The helper installs the repository source and verifies
that `QuantumBehavioralReplica.ex5` receives a fresh modification time.

## Run

```bash
python3 scripts/run-qbr-candidate.py v112-control --dry-run
python3 scripts/run-qbr-candidate.py v112-control \
  --from-date 2025.07.01 --to-date 2025.09.30
```

Available first-stage candidates:

- `v112-control`
- `tp-trend-state-only`
- `no-trend-pullback`
- `profit-lock-40`
- `stop-risk-60`
- `stop-risk-45`

The runner accepts only reports whose Expert is `QuantumBehavioralReplica`, whose
inputs contain `InpBuildTag=QBR-1.12-reliability`, and whose real-tick history
quality is at least 99%. Each report gets a fresh candidate-specific CSV folder.

## Current blocker

The Exness `XAUUSD` smoke report for 2025-07-01 through 2025-07-07 completed, but
reported `0% real ticks`. Its three-basket performance is diagnostic only and must
not be used to select a candidate. Use an account/data source that supplies at
least 99% real-tick history before running the candidate matrix.
