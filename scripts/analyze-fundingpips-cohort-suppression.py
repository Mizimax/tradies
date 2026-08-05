#!/usr/bin/env python3
"""Frozen shadow screen for GoldBot m1_micro_scalp short entries at hour 10."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANALYZER = ROOT / "scripts/analyze-mt5-trades.py"

SETUP, DIRECTION, HOUR = "m1_micro_scalp", "-1", "10"
MIN_HALF, MIN_COMBINED = 4, 10
MAX_PF, MIN_VALIDATION_BENEFIT_PCT = 0.95, 0.25
MAX_DD_WORSENING = 0.05


class StudyError(RuntimeError):
    pass


def load_analyzer():
    spec = importlib.util.spec_from_file_location("goldbot_trade_analyzer", ANALYZER)
    if spec is None or spec.loader is None:
        raise StudyError(f"cannot load {ANALYZER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


A = load_analyzer()


def as_float(value, context: str) -> float:
    try:
        return float(value)
    except (TypeError, ValueError) as exc:
        raise StudyError(f"invalid {context}: {value!r}") from exc


def load_window(label: str, role: str, path: Path) -> dict[str, object]:
    try:
        manifest = json.loads(path.read_text())
        _, rows = A.read_chain_manifest(path)
        positions = A._position_cohorts(rows)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        raise StudyError(f"{label}: {exc}") from exc

    stitched = manifest.get("stitched")
    if not isinstance(stitched, dict):
        raise StudyError(f"{label}: stitched metrics missing")
    initial = as_float(stitched.get("initial_balance"), f"{label} initial balance")
    base_net = as_float(stitched.get("net_profit"), f"{label} net profit")
    expected = int(stitched.get("total_trades", -1))

    complete = []
    for cohort in positions.values():
        close_times = cohort.get("close_times")
        fields = cohort.get("fields")
        if not isinstance(close_times, list) or not close_times or not isinstance(fields, dict):
            continue
        complete.append(
            {
                "close": max(str(value) for value in close_times),
                "profit": as_float(cohort.get("profit", 0), f"{label} position profit"),
                "match": (
                    fields.get("setup") == SETUP
                    and fields.get("dir") == DIRECTION
                    and fields.get("hour") == HOUR
                ),
            }
        )
    complete.sort(key=lambda row: str(row["close"]))
    if expected >= 0 and len(complete) != expected:
        raise StudyError(f"{label}: position/trade mismatch {len(complete)} != {expected}")
    position_net = sum(float(row["profit"]) for row in complete)
    if abs(position_net - base_net) > 0.05:
        raise StudyError(
            f"{label}: position P&L does not reconcile {position_net:.2f} != {base_net:.2f}"
        )

    cohort = [row for row in complete if bool(row["match"])]
    values = [float(row["profit"]) for row in cohort]
    gross_profit = sum(value for value in values if value > 0)
    gross_loss = sum(value for value in values if value < 0)
    pf = gross_profit / abs(gross_loss) if gross_loss < 0 else gross_profit

    def dd(suppress: bool) -> float:
        balance = peak = initial
        worst = 0.0
        for row in complete:
            if suppress and bool(row["match"]):
                continue
            balance += float(row["profit"])
            peak = max(peak, balance)
            worst = max(worst, (peak - balance) / peak * 100 if peak else 0.0)
        return worst

    cohort_net = sum(values)
    base_dd, shadow_dd = dd(False), dd(True)
    return {
        "label": label,
        "role": role,
        "manifest": str(path),
        "initial_balance": round(initial, 2),
        "base_net_profit": round(base_net, 2),
        "complete_positions": len(complete),
        "cohort_positions": len(cohort),
        "cohort_net_profit": round(cohort_net, 2),
        "cohort_profit_factor": round(pf, 6),
        "cohort_win_rate_pct": round(
            sum(value > 0 for value in values) / len(values) * 100 if values else 0, 6
        ),
        "counterfactual_net_profit": round(base_net - cohort_net, 2),
        "counterfactual_benefit": round(-cohort_net, 2),
        "counterfactual_benefit_pct": round(-cohort_net / initial * 100, 6),
        "base_closed_balance_dd_pct": round(base_dd, 6),
        "counterfactual_closed_balance_dd_pct": round(shadow_dd, 6),
        "closed_balance_dd_delta_pct_points": round(shadow_dd - base_dd, 6),
        "_cohort_values": values,
    }


def combine(label: str, role: str, halves: list[dict[str, object]]) -> dict[str, object]:
    deposits = {float(row["initial_balance"]) for row in halves}
    if len(deposits) != 1:
        raise StudyError(f"{label}: deposits differ")
    initial = deposits.pop()
    values = [
        float(value)
        for row in halves
        for value in row["_cohort_values"]  # type: ignore[index]
    ]
    gross_profit = sum(value for value in values if value > 0)
    gross_loss = sum(value for value in values if value < 0)
    net = sum(values)
    return {
        "label": label,
        "role": role,
        "manifest": ";".join(str(row["manifest"]) for row in halves),
        "initial_balance": initial,
        "base_net_profit": round(sum(float(row["base_net_profit"]) for row in halves), 2),
        "complete_positions": sum(int(row["complete_positions"]) for row in halves),
        "cohort_positions": len(values),
        "cohort_net_profit": round(net, 2),
        "cohort_profit_factor": round(
            gross_profit / abs(gross_loss) if gross_loss < 0 else gross_profit, 6
        ),
        "cohort_win_rate_pct": round(
            sum(value > 0 for value in values) / len(values) * 100 if values else 0, 6
        ),
        "counterfactual_net_profit": round(
            sum(float(row["base_net_profit"]) for row in halves) - net, 2
        ),
        "counterfactual_benefit": round(-net, 2),
        "counterfactual_benefit_pct": round(-net / initial * 100, 6),
        "base_closed_balance_dd_pct": "",
        "counterfactual_closed_balance_dd_pct": "",
        "closed_balance_dd_delta_pct_points": "",
        "_cohort_values": values,
    }


def evaluate(train: list[dict[str, object]], validation: list[dict[str, object]]):
    train_all = combine("train-2025", "train_combined", train)
    valid_all = combine("validation-2024", "validation_combined", validation)
    gates: list[dict[str, object]] = []

    def gate(name: str, passed: bool, actual, required: str):
        gates.append({"gate": name, "passed": passed, "actual": actual, "required": required})

    for row in train:
        gate(f"{row['label']}:sample", int(row["cohort_positions"]) >= MIN_HALF,
             row["cohort_positions"], f">={MIN_HALF}")
        gate(f"{row['label']}:negative", float(row["cohort_net_profit"]) < 0,
             row["cohort_net_profit"], "<0")
    gate("train:sample", int(train_all["cohort_positions"]) >= MIN_COMBINED,
         train_all["cohort_positions"], f">={MIN_COMBINED}")
    gate("train:pf", float(train_all["cohort_profit_factor"]) <= MAX_PF,
         train_all["cohort_profit_factor"], f"<={MAX_PF}")

    for row in validation:
        gate(f"{row['label']}:sample", int(row["cohort_positions"]) >= MIN_HALF,
             row["cohort_positions"], f">={MIN_HALF}")
        gate(f"{row['label']}:non_profitable", float(row["cohort_net_profit"]) <= 0,
             row["cohort_net_profit"], "<=0")
        gate(f"{row['label']}:dd", float(row["closed_balance_dd_delta_pct_points"]) <= MAX_DD_WORSENING,
             row["closed_balance_dd_delta_pct_points"], f"<={MAX_DD_WORSENING} pct points")
    gate("validation:sample", int(valid_all["cohort_positions"]) >= MIN_COMBINED,
         valid_all["cohort_positions"], f">={MIN_COMBINED}")
    gate("validation:pf", float(valid_all["cohort_profit_factor"]) <= MAX_PF,
         valid_all["cohort_profit_factor"], f"<={MAX_PF}")
    gate("validation:benefit", float(valid_all["counterfactual_benefit_pct"]) >= MIN_VALIDATION_BENEFIT_PCT,
         valid_all["counterfactual_benefit_pct"], f">={MIN_VALIDATION_BENEFIT_PCT}%")
    return train_all, valid_all, gates, all(bool(row["passed"]) for row in gates)


def write_csv(path: Path, rows: list[dict[str, object]]):
    clean = [{k: v for k, v in row.items() if not k.startswith("_")} for row in rows]
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(clean[0]))
        writer.writeheader()
        writer.writerows(clean)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("train-h1", "train-h2", "validation-h1", "validation-h2"):
        parser.add_argument(f"--{name}", required=True, type=Path)
    parser.add_argument("--output-prefix", required=True, type=Path)
    args = parser.parse_args()
    try:
        train = [
            load_window("h1-2025", "train", args.train_h1),
            load_window("h2-2025", "train", args.train_h2),
        ]
        validation = [
            load_window("h1-2024", "locked_validation", args.validation_h1),
            load_window("h2-2024", "locked_validation", args.validation_h2),
        ]
        train_all, valid_all, gates, passed = evaluate(train, validation)
    except StudyError as exc:
        print(f"Cohort study FAILED: {exc}", file=sys.stderr)
        return 2

    rows = train + [train_all] + validation + [valid_all]
    prefix = args.output_prefix
    prefix.parent.mkdir(parents=True, exist_ok=True)
    write_csv(prefix.with_suffix(".csv"), rows)
    write_csv(prefix.with_name(prefix.name + ".gates.csv"), gates)
    payload = {
        "schema_version": 1,
        "created_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "frozen_cohort": {"setup": SETUP, "direction": DIRECTION, "hour": HOUR},
        "result": "PASS_SHADOW_IMPLEMENTATION_ONLY" if passed else "FALSIFIED",
        "rows": [{k: v for k, v in row.items() if not k.startswith("_")} for row in rows],
        "gate_checks": gates,
        "interpretation": "Passing permits only a reviewed tester-only shadow gate.",
    }
    prefix.with_suffix(".json").write_text(json.dumps(payload, indent=2) + "\n")
    print(f"Frozen cohort: {SETUP} / dir={DIRECTION} / hour={HOUR}")
    print(f"Decision: {payload['result']}")
    print(f"Outputs: {prefix}.csv, {prefix}.gates.csv, {prefix}.json")
    return 0 if passed else 3


if __name__ == "__main__":
    raise SystemExit(main())
