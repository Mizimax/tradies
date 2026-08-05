#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEPOSIT="${DEPOSIT:-50000}"
PREFIX="${PREFIX:-GoldBot-fundingpips-m1-short-hour10-shadow}"
REPORT_DIR="$ROOT/mt5/backtests/reports"

run_control_chain() {
  local window="$1"
  local suffix="$2"
  local chain_name="${PREFIX}-${suffix}"

  python3 scripts/run-mt5-fundingpips-chain.py \
    --window "$window" \
    --chain-name "$chain_name" \
    --deposit "$DEPOSIT" \
    --preset GoldBot/prop-fundingpips-2step.set \
    --set InpPropChallengeRiskPct=0.50 \
    --set InpEnableContinuationPullbackSetup=false \
    --set InpEnableContinuationCausalShadow=false \
    --set InpEnableScalpFailureExit=false
}

# Qualification order is deliberate and sequential:
# 1) consumed 2025 train halves, 2) untouched locked 2024 halves.
# Do not parallelize Wine/MT5 runs.
run_control_chain h1-2025 train-h1-2025
run_control_chain h2-2025 train-h2-2025
run_control_chain h1-2024 validation-h1-2024
run_control_chain h2-2024 validation-h2-2024

OUTPUT_PREFIX="$REPORT_DIR/${PREFIX}-study"

set +e
python3 scripts/analyze-fundingpips-cohort-suppression.py \
  --train-h1 "$REPORT_DIR/${PREFIX}-train-h1-2025.manifest.json" \
  --train-h2 "$REPORT_DIR/${PREFIX}-train-h2-2025.manifest.json" \
  --validation-h1 "$REPORT_DIR/${PREFIX}-validation-h1-2024.manifest.json" \
  --validation-h2 "$REPORT_DIR/${PREFIX}-validation-h2-2024.manifest.json" \
  --output-prefix "$OUTPUT_PREFIX"
status=$?
set -e

case "$status" in
  0)
    printf '\nPASS: cohort survived the frozen screen.\n'
    printf '%s\n' 'This authorizes only a separately reviewed tester-only shadow gate.'
    ;;
  3)
    printf '\nFALSIFIED: do not implement or tune the hour-10 suppression hypothesis.\n'
    ;;
  *)
    printf '\nStudy failed closed with status %s.\n' "$status" >&2
    exit "$status"
    ;;
esac

printf '\nOutputs:\n'
printf '%s\n' \
  "${OUTPUT_PREFIX}.csv" \
  "${OUTPUT_PREFIX}.gates.csv" \
  "${OUTPUT_PREFIX}.json"

exit "$status"
