#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEPOSIT="${DEPOSIT:-50000}"
PREFIX="${PREFIX:-GoldBot-fundingpips-long-alpha}"
REUSE_EXISTING="${REUSE_EXISTING:-1}"
REPORT_DIR="$ROOT/mt5/backtests/reports"
OUTPUT_PREFIX="$REPORT_DIR/${PREFIX}-discovery"

windows=(h1-2024 h2-2024 h1-2025 h2-2025 h1-2026)

baseline_manifest() {
  case "$1" in
    h1-2024) printf '%s\n' "$REPORT_DIR/GoldBot-fundingpips-m1-short-hour10-shadow-validation-h1-2024.manifest.json" ;;
    h2-2024) printf '%s\n' "$REPORT_DIR/GoldBot-fundingpips-m1-short-hour10-shadow-validation-h2-2024.manifest.json" ;;
    h1-2025) printf '%s\n' "$REPORT_DIR/GoldBot-fundingpips-m1-short-hour10-shadow-train-h1-2025.manifest.json" ;;
    h2-2025) printf '%s\n' "$REPORT_DIR/GoldBot-fundingpips-m1-short-hour10-shadow-train-h2-2025.manifest.json" ;;
    h1-2026) printf '%s\n' "$REPORT_DIR/GoldBot-fundingpips-p1-h1-2026-negative-window-control.manifest.json" ;;
    *) printf 'unknown window: %s\n' "$1" >&2; return 2 ;;
  esac
}

for window in "${windows[@]}"; do
  path="$(baseline_manifest "$window")"
  if [[ ! -f "$path" ]]; then
    printf 'Missing accepted baseline manifest: %s\n' "$path" >&2
    exit 2
  fi
done

run_candidate_chain() {
  local candidate="$1"
  local window="$2"
  local chain_name="${PREFIX}-${candidate}-${window}"
  local manifest="$REPORT_DIR/${chain_name}.manifest.json"
  local m5_long_hours="99"
  local m1_long_hours="99"

  case "$candidate" in
    m5-long) m5_long_hours="7;10;12;18" ;;
    m1-long) m1_long_hours="10;18" ;;
    *) printf 'Unknown candidate: %s\n' "$candidate" >&2; return 2 ;;
  esac

  if [[ "$REUSE_EXISTING" == "1" && -f "$manifest" ]]; then
    printf '\nReusing completed candidate manifest: %s\n' "$manifest"
    return 0
  fi

  printf '\n=== %s / %s ===\n' "$candidate" "$window"
  python3 scripts/run-mt5-fundingpips-chain.py \
    --window "$window" \
    --chain-name "$chain_name" \
    --deposit "$DEPOSIT" \
    --preset GoldBot/prop-fundingpips-2step.set \
    --set InpPropChallengeRiskPct=0.50 \
    --set InpEnableContinuationPullbackSetup=false \
    --set InpEnableContinuationCausalShadow=false \
    --set InpEnableScalpFailureExit=false \
    --set "InpScalpLongHours=${m5_long_hours}" \
    --set "InpM1MicroLongHours=${m1_long_hours}"
}

# Deliberately sequential. Wine/MT5 tester chains must never overlap.
for candidate in m5-long m1-long; do
  for window in "${windows[@]}"; do
    run_candidate_chain "$candidate" "$window"
  done
done

analysis=(python3 scripts/analyze-fundingpips-long-scalp-expansion.py)
for window in "${windows[@]}"; do
  analysis+=(--baseline "$window" "$(baseline_manifest "$window")")
  analysis+=(--m5-long "$window" "$REPORT_DIR/${PREFIX}-m5-long-${window}.manifest.json")
  analysis+=(--m1-long "$window" "$REPORT_DIR/${PREFIX}-m1-long-${window}.manifest.json")
done
analysis+=(--output-prefix "$OUTPUT_PREFIX")

set +e
"${analysis[@]}"
status=$?
set -e

case "$status" in
  0)
    printf '\nSELECTED: one structural long-alpha candidate may proceed to locked 2023 validation.\n'
    ;;
  3)
    printf '\nNO CANDIDATE: retire both frozen long-side scalp candidates without tuning hours.\n'
    ;;
  *)
    printf '\nLong-alpha discovery failed closed with status %s.\n' "$status" >&2
    exit "$status"
    ;;
esac

printf '\nOutputs:\n'
printf '%s\n' \
  "${OUTPUT_PREFIX}.csv" \
  "${OUTPUT_PREFIX}.gates.csv" \
  "${OUTPUT_PREFIX}.json"

exit "$status"
