#!/usr/bin/env python3
"""Audit GoldBot's existing day-scoped short-term scalp controller."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import math
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGIME_ANALYZER = ROOT / "scripts/analyze-fundingpips-regime-instability.py"
BASE_ANALYZER = ROOT / "scripts/analyze-mt5-trades.py"
SCALP_SETUPS = {"m1_micro_scalp", "m5_scalp"}
MT5_TIME = "%Y.%m.%d %H:%M:%S"


class AuditError(RuntimeError):
    """Raised when completed tester evidence cannot be audited safely."""


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise AuditError(f"cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


REGIME = load_module("fundingpips_regime_instability", REGIME_ANALYZER)
A = load_module("goldbot_trade_analyzer", BASE_ANALYZER)


def parse_time(value: str) -> datetime:
    try:
        return datetime.strptime(value, MT5_TIME)
    except ValueError as exc:
        raise AuditError(f"invalid MT5 timestamp: {value!r}") from exc


def as_float(value: object, context: str) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise AuditError(f"invalid {context}: {value!r}") from exc
    if not math.isfinite(parsed):
        raise AuditError(f"non-finite {context}: {value!r}")
    return parsed


def summarize_sequence(window: str, setup: str, direction: str, rows: list[dict[str, object]]) -> dict[str, object]:
    ordered = sorted(
        rows,
        key=lambda row: (parse_time(str(row["timestamp"])), int(str(row.get("deal") or "0"))),
    )
    cross_day_streak = 0
    max_cross_day_streak = 0
    same_day_streak = 0
    max_same_day_streak = 0
    previous_day = ""
    previous_loss_time: datetime | None = None
    cross_day_loss_transitions = 0
    max_loss_gap_hours = 0.0
    losses_by_day: dict[str, int] = defaultdict(int)

    for row in ordered:
        timestamp = parse_time(str(row["timestamp"]))
        day = timestamp.strftime("%Y-%m-%d")
        profit = as_float(row["profit"], f"{window} trade profit")

        if day != previous_day:
            same_day_streak = 0
            previous_day = day

        if profit < 0.0:
            cross_day_streak += 1
            same_day_streak += 1
            losses_by_day[day] += 1
            max_cross_day_streak = max(max_cross_day_streak, cross_day_streak)
            max_same_day_streak = max(max_same_day_streak, same_day_streak)
            if previous_loss_time is not None:
                gap_hours = (timestamp - previous_loss_time).total_seconds() / 3600.0
                max_loss_gap_hours = max(max_loss_gap_hours, gap_hours)
                if timestamp.date() != previous_loss_time.date():
                    cross_day_loss_transitions += 1
            previous_loss_time = timestamp
        elif profit > 0.0:
            cross_day_streak = 0
            same_day_streak = 0
            previous_loss_time = None

    values = [as_float(row["profit"], f"{window} trade profit") for row in ordered]
    return {
        "window": window,
        "setup": setup,
        "direction": direction,
        "trades": len(ordered),
        "net_profit": round(sum(values), 2),
        "loss_trades": sum(value < 0.0 for value in values),
        "loss_days": len(losses_by_day),
        "days_with_2plus_losses": sum(count >= 2 for count in losses_by_day.values()),
        "days_with_3plus_losses": sum(count >= 3 for count in losses_by_day.values()),
        "max_cross_day_consecutive_losses": max_cross_day_streak,
        "max_same_day_consecutive_losses": max_same_day_streak,
        "cross_day_loss_transitions": cross_day_loss_transitions,
        "max_gap_hours_inside_loss_streak": round(max_loss_gap_hours, 3),
    }


def day_aware_rows(trades: list[dict[str, object]]) -> list[dict[str, object]]:
    grouped: dict[tuple[str, str, str], list[dict[str, object]]] = defaultdict(list)
    combined: dict[str, list[dict[str, object]]] = defaultdict(list)

    for row in trades:
        setup = str(row["setup"])
        if setup not in SCALP_SETUPS:
            continue
        window = str(row["window"])
        direction = str(row["direction"])
        grouped[(window, setup, direction)].append(row)
        combined[window].append(row)

    output: list[dict[str, object]] = []
    for (window, setup, direction), rows in sorted(grouped.items()):
        output.append(summarize_sequence(window, setup, direction, rows))
    for window, rows in sorted(combined.items()):
        output.append(summarize_sequence(window, "all_short_term_scalps", "all", rows))
    return output


def control_telemetry(label: str, manifest_path: Path) -> dict[str, object]:
    try:
        _, rows = A._load_continuation_manifest(manifest_path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        raise AuditError(f"{label}: {exc}") from exc

    pause_activations = 0
    m1_blocks = 0
    m5_blocks = 0
    max_pause_losses = 0
    max_block_losses = 0
    min_pause_daily_r = 0.0
    min_block_daily_r = 0.0

    for _, _, message in rows:
        lower = message.lower()
        fields = A.parse_message_fields(message)
        if "short-term scalp pause activated" in lower:
            pause_activations += 1
            losses = int(as_float(fields.get("losses", 0), f"{label} pause losses"))
            daily_r = as_float(fields.get("dailyR", 0), f"{label} pause dailyR")
            max_pause_losses = max(max_pause_losses, losses)
            min_pause_daily_r = min(min_pause_daily_r, daily_r)
        elif "m1 micro scalp blocked shorttermcontrol" in lower:
            m1_blocks += 1
            losses = int(as_float(fields.get("losses", 0), f"{label} M1 block losses"))
            daily_r = as_float(fields.get("dailyR", 0), f"{label} M1 block dailyR")
            max_block_losses = max(max_block_losses, losses)
            min_block_daily_r = min(min_block_daily_r, daily_r)
        elif "m5 scalp blocked shorttermcontrol" in lower:
            m5_blocks += 1
            losses = int(as_float(fields.get("losses", 0), f"{label} M5 block losses"))
            daily_r = as_float(fields.get("dailyR", 0), f"{label} M5 block dailyR")
            max_block_losses = max(max_block_losses, losses)
            min_block_daily_r = min(min_block_daily_r, daily_r)

    return {
        "window": label,
        "pause_activations": pause_activations,
        "m1_short_term_blocks": m1_blocks,
        "m5_short_term_blocks": m5_blocks,
        "total_short_term_blocks": m1_blocks + m5_blocks,
        "max_logged_pause_losses": max_pause_losses,
        "max_logged_block_losses": max_block_losses,
        "worst_logged_pause_daily_r": round(min_pause_daily_r, 6),
        "worst_logged_block_daily_r": round(min_block_daily_r, 6),
    }


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        raise AuditError(f"refusing to write empty output: {path}")
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--window", nargs=2, action="append", metavar=("LABEL", "MANIFEST"), required=True)
    parser.add_argument("--output-prefix", required=True, type=Path)
    args = parser.parse_args()

    labels: list[str] = []
    all_trades: list[dict[str, object]] = []
    controls: list[dict[str, object]] = []
    try:
        for label, raw_path in args.window:
            if label in labels:
                raise AuditError(f"duplicate window label: {label}")
            labels.append(label)
            path = Path(raw_path)
            _, trades = REGIME.load_window(label, path)
            all_trades.extend(trades)
            controls.append(control_telemetry(label, path))

        clusters = day_aware_rows(all_trades)
        prefix = args.output_prefix
        prefix.parent.mkdir(parents=True, exist_ok=True)
        clusters_path = prefix.with_name(prefix.name + ".day-aware-clusters.csv")
        controls_path = prefix.with_name(prefix.name + ".controls.csv")
        json_path = prefix.with_suffix(".json")
        write_csv(clusters_path, clusters)
        write_csv(controls_path, controls)
        payload = {
            "schema_version": 1,
            "created_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "purpose": "audit_existing_day_scoped_short_term_controller",
            "controller_contract": {
                "scope": "combined M1 and M5 scalp closing deals",
                "state_key_scope": "server day via GoldBotDayKey",
                "configured_max_consecutive_losses": 2,
                "configured_pause_minutes": 120,
                "configured_max_daily_loss_r": 1.5,
            },
            "interpretation_rules": [
                "Compare the live controller with max_same_day_consecutive_losses, not the cross-day streak.",
                "Cross-day streaks are descriptive because the existing controller resets its loss counter at each server-day boundary.",
                "Do not add a persistent cross-day pause unless the current controller is verified and one frozen causal counterfactual passes a separate screen.",
            ],
            "clusters": clusters,
            "controls": controls,
        }
        json_path.write_text(json.dumps(payload, indent=2) + "\n")
    except (AuditError, REGIME.DiagnosticError) as exc:
        print(f"Day-aware scalp-control audit FAILED: {exc}", file=sys.stderr)
        return 2

    print("Day-aware scalp-control audit complete; no MT5 run was performed.")
    print(f"Outputs: {clusters_path}")
    print(f"         {controls_path}")
    print(f"         {json_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
