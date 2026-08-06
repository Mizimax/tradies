#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CHAIN_NAME="${CHAIN_NAME:-GoldBot-fundingpips-p1-h1-2026-negative-window-control}"
DEPOSIT="${DEPOSIT:-50000}"
REPORT_DIR="$ROOT/mt5/backtests/reports"
MANIFEST="$REPORT_DIR/${CHAIN_NAME}.manifest.json"
ATTRIBUTION="$REPORT_DIR/${CHAIN_NAME}.attribution.csv"
SHORTLIST="$REPORT_DIR/${CHAIN_NAME}.negative-cohorts.csv"

# This is a control/attribution run only. It must not enable retired continuation
# or failure-exit mechanisms, and it must retain the canonical 0.50% P1 risk.
python3 scripts/run-mt5-fundingpips-chain.py \
  --window h1-2026 \
  --chain-name "$CHAIN_NAME" \
  --deposit "$DEPOSIT" \
  --preset GoldBot/prop-fundingpips-2step.set \
  --set InpPropChallengeRiskPct=0.50 \
  --set InpEnableContinuationPullbackSetup=false \
  --set InpEnableContinuationCausalShadow=false \
  --set InpEnableScalpFailureExit=false

python3 scripts/analyze-mt5-trades.py \
  --attribution \
  --chain-manifest "$MANIFEST" > "$ATTRIBUTION"

python3 - "$ATTRIBUTION" "$SHORTLIST" <<'PY'
from __future__ import annotations

import csv
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])

# These rows are hypotheses for a later locked-window shadow test, not trading
# rules. Requiring at least five closed deals avoids elevating one-off losses.
allowed_groups = {
    "setup",
    "setup_direction",
    "direction_hour",
    "setup_direction_hour",
    "scalp_variant_direction_hour",
}

with source.open(newline="") as handle:
    rows = list(csv.DictReader(handle))

candidates = []
for row in rows:
    if row.get("group") not in allowed_groups:
        continue
    deals = int(row.get("closed_deals") or 0)
    net = float(row.get("net_profit") or 0.0)
    pf = float(row.get("profit_factor") or 0.0)
    if deals < 5 or net >= 0.0 or pf >= 0.90:
        continue
    candidates.append(row)

candidates.sort(
    key=lambda row: (
        float(row.get("net_profit") or 0.0),
        -int(row.get("closed_deals") or 0),
        row.get("group", ""),
        row.get("value", ""),
    )
)

fieldnames = [
    "journal",
    "group",
    "value",
    "closed_deals",
    "net_profit",
    "gross_profit",
    "gross_loss",
    "profit_factor",
    "win_rate_pct",
]
with target.open("w", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(candidates)

print(f"Attribution: {source}")
print(f"Negative-cohort shortlist: {target}")
print(f"Qualified hypothesis rows: {len(candidates)}")
PY

printf '\nResearch interpretation rules:\n'
printf '%s\n' '- Do not disable or down-weight a cohort from H1 2026 alone.'
printf '%s\n' '- Pick at most one economically coherent cohort, define a shadow-only mechanism and gates first.'
printf '%s\n' '- H1/H2 2025 are consumed train windows; validate any promoted mechanism on untouched 2024 and 2026 windows.'
