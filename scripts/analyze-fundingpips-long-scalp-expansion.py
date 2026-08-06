#!/usr/bin/env python3
"""Frozen consumed-history screen for GoldBot's existing long scalp paths."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGIME_PATH = ROOT / "scripts/analyze-fundingpips-regime-instability.py"

CANDIDATES = {
    "m5-long": ("m5_scalp", "7;10;12;18", "99"),
    "m1-long": ("m1_micro_scalp", "99", "10;18"),
}
COMMON_INPUTS = {
    "InpPropChallengeRiskPct": "0.50",
    "InpEnableContinuationPullbackSetup": "false",
    "InpEnableContinuationCausalShadow": "false",
    "InpEnableScalpFailureExit": "false",
}
BASELINE_HOURS = ("99", "99")
MIN_TRADES, MIN_ALPHA_PF = 20, 1.10
MIN_POSITIVE_ALPHA_WINDOWS = MIN_POSITIVE_PORTFOLIO_WINDOWS = 3
MIN_DELTA_PCT, MAX_DD_DELTA = 2.0, 0.75
MIN_PORTFOLIO_PF, MAX_PF_DEGRADATION = 1.15, 0.05


class ScreenError(RuntimeError):
    pass


def load_regime():
    spec = importlib.util.spec_from_file_location("fundingpips_regime", REGIME_PATH)
    if spec is None or spec.loader is None:
        raise ScreenError(f"cannot load {REGIME_PATH}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


R = load_regime()
A = R.A


def number(value, context: str) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise ScreenError(f"invalid {context}: {value!r}") from exc
    if not math.isfinite(parsed):
        raise ScreenError(f"non-finite {context}: {value!r}")
    return parsed


def pf(values: list[float]) -> float:
    gains = sum(value for value in values if value > 0)
    losses = sum(value for value in values if value < 0)
    return gains / abs(losses) if losses < 0 else (gains if gains > 0 else 0.0)


def read_manifest(path: Path) -> dict:
    try:
        payload = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ScreenError(f"invalid manifest {path}: {exc}") from exc
    if payload.get("schema_version") != 1 or not payload.get("segments"):
        raise ScreenError(f"unsupported/empty manifest: {path}")
    return payload


def report_path(manifest_path: Path, payload: dict) -> Path:
    report = Path(str(payload["segments"][0].get("report", "")))
    return report if report.is_absolute() else manifest_path.parent / report


def verify_inputs(path: Path, m5_hours: str, m1_hours: str, context: str) -> None:
    payload = read_manifest(path)
    try:
        inputs = A._report_inputs(report_path(path, payload))
    except (OSError, ValueError) as exc:
        raise ScreenError(f"{context}: {exc}") from exc
    expected = {
        **COMMON_INPUTS,
        "InpScalpLongHours": m5_hours,
        "InpM1MicroLongHours": m1_hours,
    }
    for key, wanted in expected.items():
        actual = inputs.get(key)
        if actual is None:
            raise ScreenError(f"{context}: input missing {key}")
        if key == "InpPropChallengeRiskPct":
            ok = abs(number(actual, key) - number(wanted, key)) <= 1e-9
        else:
            ok = actual.lower() == wanted.lower()
        if not ok:
            raise ScreenError(f"{context}: {key}={actual!r}, expected {wanted!r}")


def verify_pair(base_path: Path, candidate_path: Path, label: str, candidate: str) -> None:
    base, variant = read_manifest(base_path), read_manifest(candidate_path)
    for key in ("preset", "preset_sha256", "source_hashes", "ex5_sha256"):
        if base.get(key) != variant.get(key):
            raise ScreenError(f"{label}/{candidate}: {key} differs from baseline")
    verify_inputs(base_path, *BASELINE_HOURS, f"{label}/baseline")
    _, m5_hours, m1_hours = CANDIDATES[candidate]
    verify_inputs(candidate_path, m5_hours, m1_hours, f"{label}/{candidate}")


def load_row(label: str, base_path: Path, candidate_path: Path, candidate: str) -> dict:
    verify_pair(base_path, candidate_path, label, candidate)
    try:
        base_meta, base_trades = R.load_window(label, base_path)
        variant_meta, variant_trades = R.load_window(label, candidate_path)
    except R.DiagnosticError as exc:
        raise ScreenError(str(exc)) from exc
    initial = number(base_meta["initial_balance"], f"{label} baseline deposit")
    if abs(initial - number(variant_meta["initial_balance"], f"{label} variant deposit")) > 0.005:
        raise ScreenError(f"{label}/{candidate}: deposit mismatch")
    setup, _, _ = CANDIDATES[candidate]
    base_values = [float(row["profit"]) for row in base_trades]
    variant_values = [float(row["profit"]) for row in variant_trades]
    alpha = [
        float(row["profit"])
        for row in variant_trades
        if row["setup"] == setup and row["direction"] == "1"
    ]
    base_net, variant_net = sum(base_values), sum(variant_values)
    base_dd = number(base_meta["equity_drawdown_pct"], f"{label} baseline DD")
    variant_dd = number(variant_meta["equity_drawdown_pct"], f"{label} variant DD")
    return {
        "window": label,
        "candidate": candidate,
        "initial_balance": round(initial, 2),
        "baseline_trades": len(base_values),
        "candidate_trades": len(variant_values),
        "alpha_trades": len(alpha),
        "alpha_net_profit": round(sum(alpha), 2),
        "alpha_profit_factor": round(pf(alpha), 6),
        "alpha_win_rate_pct": round(sum(v > 0 for v in alpha) / len(alpha) * 100 if alpha else 0, 6),
        "baseline_net_profit": round(base_net, 2),
        "candidate_net_profit": round(variant_net, 2),
        "portfolio_delta": round(variant_net - base_net, 2),
        "baseline_profit_factor": round(pf(base_values), 6),
        "candidate_profit_factor": round(pf(variant_values), 6),
        "baseline_equity_dd_pct": round(base_dd, 6),
        "candidate_equity_dd_pct": round(variant_dd, 6),
        "dd_delta_pct_points": round(variant_dd - base_dd, 6),
        "baseline_manifest": str(base_path),
        "candidate_manifest": str(candidate_path),
        "_alpha": alpha,
        "_base": base_values,
        "_variant": variant_values,
    }


def combine(candidate: str, rows: list[dict]) -> dict:
    alpha = [v for row in rows for v in row["_alpha"]]
    base = [v for row in rows for v in row["_base"]]
    variant = [v for row in rows for v in row["_variant"]]
    deposits = {float(row["initial_balance"]) for row in rows}
    if len(deposits) != 1:
        raise ScreenError(f"{candidate}: discovery deposits differ")
    initial = deposits.pop()
    delta = sum(variant) - sum(base)
    return {
        "window": "discovery-combined",
        "candidate": candidate,
        "initial_balance": initial,
        "baseline_trades": len(base),
        "candidate_trades": len(variant),
        "alpha_trades": len(alpha),
        "alpha_net_profit": round(sum(alpha), 2),
        "alpha_profit_factor": round(pf(alpha), 6),
        "alpha_win_rate_pct": round(sum(v > 0 for v in alpha) / len(alpha) * 100 if alpha else 0, 6),
        "baseline_net_profit": round(sum(base), 2),
        "candidate_net_profit": round(sum(variant), 2),
        "portfolio_delta": round(delta, 2),
        "portfolio_delta_pct": round(delta / initial * 100, 6),
        "baseline_profit_factor": round(pf(base), 6),
        "candidate_profit_factor": round(pf(variant), 6),
        "baseline_equity_dd_pct": "",
        "candidate_equity_dd_pct": "",
        "dd_delta_pct_points": max(float(row["dd_delta_pct_points"]) for row in rows),
        "positive_alpha_windows": sum(float(row["alpha_net_profit"]) > 0 for row in rows),
        "positive_portfolio_windows": sum(float(row["portfolio_delta"]) > 0 for row in rows),
        "baseline_manifest": ";".join(str(row["baseline_manifest"]) for row in rows),
        "candidate_manifest": ";".join(str(row["candidate_manifest"]) for row in rows),
    }


def evaluate(candidate: str, rows: list[dict], total: dict) -> tuple[list[dict], bool]:
    checks: list[dict] = []

    def add(name: str, ok: bool, actual, required: str) -> None:
        checks.append({"candidate": candidate, "gate": name, "passed": ok, "actual": actual, "required": required})

    add("alpha_sample", total["alpha_trades"] >= MIN_TRADES, total["alpha_trades"], f">={MIN_TRADES}")
    add("alpha_pf", total["alpha_profit_factor"] >= MIN_ALPHA_PF, total["alpha_profit_factor"], f">={MIN_ALPHA_PF}")
    add("positive_alpha_windows", total["positive_alpha_windows"] >= MIN_POSITIVE_ALPHA_WINDOWS, total["positive_alpha_windows"], f">={MIN_POSITIVE_ALPHA_WINDOWS}")
    add("positive_portfolio_windows", total["positive_portfolio_windows"] >= MIN_POSITIVE_PORTFOLIO_WINDOWS, total["positive_portfolio_windows"], f">={MIN_POSITIVE_PORTFOLIO_WINDOWS}")
    add("portfolio_delta_materiality", total["portfolio_delta_pct"] >= MIN_DELTA_PCT, total["portfolio_delta_pct"], f">={MIN_DELTA_PCT}% of deposit")
    add("portfolio_pf", total["candidate_profit_factor"] >= MIN_PORTFOLIO_PF, total["candidate_profit_factor"], f">={MIN_PORTFOLIO_PF}")
    floor = total["baseline_profit_factor"] - MAX_PF_DEGRADATION
    add("portfolio_pf_preservation", total["candidate_profit_factor"] >= floor, total["candidate_profit_factor"], f">=baseline-{MAX_PF_DEGRADATION} ({floor:.6f})")
    for row in rows:
        add(f"{row['window']}:dd", row["dd_delta_pct_points"] <= MAX_DD_DELTA, row["dd_delta_pct_points"], f"<={MAX_DD_DELTA} pct points")
    return checks, all(bool(row["passed"]) for row in checks)


def pairs(values: list[list[str]], name: str) -> dict[str, Path]:
    result: dict[str, Path] = {}
    for label, raw in values:
        if label in result:
            raise ScreenError(f"duplicate {name} window: {label}")
        result[label] = Path(raw)
    return result


def write_csv(path: Path, rows: list[dict]) -> None:
    clean = [{k: v for k, v in row.items() if not k.startswith("_")} for row in rows]
    fields: list[str] = []
    for row in clean:
        for key in row:
            if key not in fields:
                fields.append(key)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(clean)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("baseline", "m5-long", "m1-long"):
        parser.add_argument(f"--{name}", nargs=2, action="append", required=True, metavar=("LABEL", "MANIFEST"))
    parser.add_argument("--output-prefix", required=True, type=Path)
    args = parser.parse_args()
    try:
        baseline = pairs(args.baseline, "baseline")
        variants = {"m5-long": pairs(args.m5_long, "m5-long"), "m1-long": pairs(args.m1_long, "m1-long")}
        labels = list(baseline)
        if len(labels) < 3 or any(set(paths) != set(labels) for paths in variants.values()):
            raise ScreenError("candidate and baseline discovery windows must match")
        all_rows: list[dict] = []
        gates: list[dict] = []
        totals: dict[str, dict] = {}
        passed: dict[str, bool] = {}
        for candidate in CANDIDATES:
            rows = [load_row(label, baseline[label], variants[candidate][label], candidate) for label in labels]
            total = combine(candidate, rows)
            candidate_gates, ok = evaluate(candidate, rows, total)
            all_rows.extend(rows + [total])
            gates.extend(candidate_gates)
            totals[candidate], passed[candidate] = total, ok
        survivors = [name for name, ok in passed.items() if ok]
        winner = None if not survivors else max(survivors, key=lambda name: (totals[name]["portfolio_delta"], -totals[name]["dd_delta_pct_points"], totals[name]["alpha_profit_factor"]))
        result = f"SELECT_{winner.upper().replace('-', '_')}_FOR_LOCKED_2023_VALIDATION" if winner else "NO_CANDIDATE"
        prefix = args.output_prefix
        prefix.parent.mkdir(parents=True, exist_ok=True)
        write_csv(prefix.with_suffix(".csv"), all_rows)
        write_csv(prefix.with_name(prefix.name + ".gates.csv"), gates)
        payload = {
            "schema_version": 1,
            "created_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "result": result,
            "winner": winner,
            "candidate_definitions": CANDIDATES,
            "frozen_gates": {"min_trades": MIN_TRADES, "min_alpha_pf": MIN_ALPHA_PF, "min_positive_alpha_windows": MIN_POSITIVE_ALPHA_WINDOWS, "min_positive_portfolio_windows": MIN_POSITIVE_PORTFOLIO_WINDOWS, "min_portfolio_delta_pct": MIN_DELTA_PCT, "max_dd_delta_pct_points": MAX_DD_DELTA, "min_portfolio_pf": MIN_PORTFOLIO_PF, "max_pf_degradation": MAX_PF_DEGRADATION},
            "rows": [{k: v for k, v in row.items() if not k.startswith("_")} for row in all_rows],
            "gate_checks": gates,
            "interpretation": "Selection permits only one frozen locked-2023 validation; it does not authorize live use.",
        }
        prefix.with_suffix(".json").write_text(json.dumps(payload, indent=2) + "\n")
    except ScreenError as exc:
        print(f"Long-alpha screen FAILED: {exc}", file=sys.stderr)
        return 2
    print(f"Long-alpha discovery decision: {result}")
    print(f"Winner: {winner or 'none'}")
    print(f"Outputs: {args.output_prefix}.csv, {args.output_prefix}.gates.csv, {args.output_prefix}.json")
    return 0 if winner else 3


if __name__ == "__main__":
    raise SystemExit(main())
