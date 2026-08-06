#!/usr/bin/env python3
"""Diagnose GoldBot FundingPips regime instability without changing trading logic."""

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
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
BASE_ANALYZER = ROOT / "scripts/analyze-mt5-trades.py"


class DiagnosticError(RuntimeError):
    """Raised when evidence cannot be reconciled safely."""


def load_module():
    spec = importlib.util.spec_from_file_location("goldbot_trade_analyzer", BASE_ANALYZER)
    if spec is None or spec.loader is None:
        raise DiagnosticError(f"cannot load {BASE_ANALYZER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


A = load_module()


def as_float(value: object, context: str) -> float:
    try:
        parsed = float(value)
    except (TypeError, ValueError) as exc:
        raise DiagnosticError(f"invalid {context}: {value!r}") from exc
    if not math.isfinite(parsed):
        raise DiagnosticError(f"non-finite {context}: {value!r}")
    return parsed


def profit_factor(values: Iterable[float]) -> float:
    values = list(values)
    gross_profit = sum(value for value in values if value > 0)
    gross_loss = sum(value for value in values if value < 0)
    if gross_loss < 0:
        return gross_profit / abs(gross_loss)
    return gross_profit if gross_profit > 0 else 0.0


def month_of(timestamp: str) -> str:
    try:
        return datetime.strptime(timestamp[:10], "%Y.%m.%d").strftime("%Y-%m")
    except ValueError as exc:
        raise DiagnosticError(f"invalid MT5 timestamp: {timestamp}") from exc


def closing_trade_ledger(
    label: str, rows: list[tuple[int, str, str]]
) -> tuple[list[dict[str, object]], int]:
    """Return one causally ordered record per closing trade."""
    output: list[dict[str, object]] = []
    pending_open_cost = 0.0
    current_segment: int | None = None
    journal_deals = 0

    for segment, timestamp, message in rows:
        if current_segment is None:
            current_segment = segment
        elif segment != current_segment:
            if abs(pending_open_cost) > 0.005:
                raise DiagnosticError(
                    f"{label}: segment {current_segment} ended with unmatched "
                    f"opening cost {pending_open_cost:.2f}"
                )
            pending_open_cost = 0.0
            current_segment = segment

        if "deal event" not in message.lower():
            continue
        fields = A.parse_message_fields(message)
        entry = fields.get("entry", "")
        if entry not in {"0", "1", "2", "3"}:
            continue
        journal_deals += 1
        deal_profit = as_float(fields.get("profit", "0"), f"{label} deal profit")

        if entry == "0":
            pending_open_cost += deal_profit
            continue

        net_profit = deal_profit + pending_open_cost
        pending_open_cost = 0.0
        output.append(
            {
                "window": label,
                "segment": segment,
                "timestamp": timestamp,
                "month": month_of(timestamp),
                "deal": fields.get("deal", ""),
                "position": fields.get("position", ""),
                "setup": fields.get("setup", "unknown"),
                "direction": fields.get("dir", "unknown"),
                "hour": fields.get("hour", "unknown"),
                "exit_reason": fields.get("reason", "unknown"),
                "profit": net_profit,
            }
        )

    if abs(pending_open_cost) > 0.005:
        raise DiagnosticError(
            f"{label}: final segment has unmatched opening cost {pending_open_cost:.2f}"
        )
    return output, journal_deals


def load_window(label: str, path: Path) -> tuple[dict[str, object], list[dict[str, object]]]:
    try:
        manifest, rows = A._load_continuation_manifest(path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        raise DiagnosticError(f"{label}: {exc}") from exc

    stitched = manifest.get("stitched")
    if not isinstance(stitched, dict):
        raise DiagnosticError(f"{label}: stitched metrics missing")

    trades, journal_deals = closing_trade_ledger(label, rows)
    expected_trades = int(stitched.get("total_trades", -1))
    expected_deals = int(stitched.get("total_deals", -1))
    if expected_trades >= 0 and len(trades) != expected_trades:
        raise DiagnosticError(
            f"{label}: closing-trade mismatch {len(trades)} != {expected_trades}"
        )
    if expected_deals >= 0 and journal_deals != expected_deals:
        raise DiagnosticError(
            f"{label}: deal-count mismatch {journal_deals} != {expected_deals}"
        )

    expected_net = as_float(stitched.get("net_profit"), f"{label} net profit")
    actual_net = sum(float(row["profit"]) for row in trades)
    if abs(actual_net - expected_net) > 0.05:
        raise DiagnosticError(
            f"{label}: trade P&L does not reconcile {actual_net:.2f} != {expected_net:.2f}"
        )

    metadata = {
        "window": label,
        "manifest": str(path),
        "initial_balance": as_float(
            stitched.get("initial_balance"), f"{label} initial balance"
        ),
        "net_profit": expected_net,
        "profit_factor": stitched.get("profit_factor"),
        "equity_drawdown_pct": stitched.get("stitched_equity_drawdown_pct"),
        "closed_trades": len(trades),
        "journal_deals": journal_deals,
    }
    return metadata, trades

def summarize_monthly(trades: list[dict[str, object]]) -> list[dict[str, object]]:
    groups: dict[tuple[str, str, str, str], list[float]] = defaultdict(list)
    for row in trades:
        key = (
            str(row["window"]),
            str(row["month"]),
            str(row["setup"]),
            str(row["direction"]),
        )
        groups[key].append(float(row["profit"]))

    output: list[dict[str, object]] = []
    for (window, month, setup, direction), values in sorted(groups.items()):
        output.append(
            {
                "window": window,
                "month": month,
                "setup": setup,
                "direction": direction,
                "trades": len(values),
                "net_profit": round(sum(values), 2),
                "profit_factor": round(profit_factor(values), 6),
                "win_rate_pct": round(
                    sum(value > 0 for value in values) / len(values) * 100.0, 6
                ),
                "average_trade": round(sum(values) / len(values), 2),
            }
        )
    return output


def summarize_stability(
    window_labels: list[str], trades: list[dict[str, object]]
) -> list[dict[str, object]]:
    per_window: dict[tuple[str, str], dict[str, list[float]]] = defaultdict(
        lambda: defaultdict(list)
    )
    for row in trades:
        key = (str(row["setup"]), str(row["direction"]))
        per_window[key][str(row["window"])].append(float(row["profit"]))

    output: list[dict[str, object]] = []
    for (setup, direction), windows in sorted(per_window.items()):
        window_nets = {
            label: round(sum(windows.get(label, [])), 2) for label in window_labels
        }
        all_values = [
            value for label in window_labels for value in windows.get(label, [])
        ]
        positive = sum(net > 0 for net in window_nets.values())
        negative = sum(net < 0 for net in window_nets.values())
        output.append(
            {
                "setup": setup,
                "direction": direction,
                "total_trades": len(all_values),
                "total_net_profit": round(sum(all_values), 2),
                "profit_factor": round(profit_factor(all_values), 6),
                "positive_windows": positive,
                "negative_windows": negative,
                "zero_windows": len(window_labels) - positive - negative,
                "worst_window": min(window_nets, key=window_nets.get),
                "worst_window_net": min(window_nets.values()),
                "best_window": max(window_nets, key=window_nets.get),
                "best_window_net": max(window_nets.values()),
                "sign_stable": "yes" if positive == 0 or negative == 0 else "no",
                **{f"net_{label}": window_nets[label] for label in window_labels},
            }
        )
    return output


def worst_rolling(values: list[float], size: int) -> float | None:
    if len(values) < size:
        return None
    return min(
        sum(values[index : index + size])
        for index in range(len(values) - size + 1)
    )


def summarize_clusters(trades: list[dict[str, object]]) -> list[dict[str, object]]:
    groups: dict[tuple[str, str, str], list[dict[str, object]]] = defaultdict(list)
    for row in trades:
        groups[
            (str(row["window"]), str(row["setup"]), str(row["direction"]))
        ].append(row)

    output: list[dict[str, object]] = []
    for (window, setup, direction), rows in sorted(groups.items()):
        rows.sort(key=lambda row: (str(row["timestamp"]), str(row["deal"])))
        values = [float(row["profit"]) for row in rows]
        longest = current = 0
        for value in values:
            current = current + 1 if value < 0 else 0
            longest = max(longest, current)
        worst_three = worst_rolling(values, 3)
        worst_five = worst_rolling(values, 5)
        output.append(
            {
                "window": window,
                "setup": setup,
                "direction": direction,
                "trades": len(values),
                "net_profit": round(sum(values), 2),
                "max_consecutive_losses": longest,
                "worst_3_trade_net": (
                    round(worst_three, 2) if worst_three is not None else ""
                ),
                "worst_5_trade_net": (
                    round(worst_five, 2) if worst_five is not None else ""
                ),
            }
        )
    return output


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        raise DiagnosticError(f"refusing to write empty output: {path}")
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--window",
        nargs=2,
        action="append",
        metavar=("LABEL", "MANIFEST"),
        required=True,
        help="repeat for each chronological half-year evidence window",
    )
    parser.add_argument("--output-prefix", required=True, type=Path)
    args = parser.parse_args()

    labels: list[str] = []
    metadata: list[dict[str, object]] = []
    trades: list[dict[str, object]] = []
    try:
        for label, raw_path in args.window:
            if label in labels:
                raise DiagnosticError(f"duplicate window label: {label}")
            labels.append(label)
            window_metadata, window_trades = load_window(label, Path(raw_path))
            metadata.append(window_metadata)
            trades.extend(window_trades)

        monthly = summarize_monthly(trades)
        stability = summarize_stability(labels, trades)
        clusters = summarize_clusters(trades)

        prefix = args.output_prefix
        prefix.parent.mkdir(parents=True, exist_ok=True)
        write_csv(prefix.with_name(prefix.name + ".monthly.csv"), monthly)
        write_csv(prefix.with_name(prefix.name + ".stability.csv"), stability)
        write_csv(prefix.with_name(prefix.name + ".clusters.csv"), clusters)
        payload = {
            "schema_version": 1,
            "created_at_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "purpose": "diagnostic_only_no_trading_rule_promotion",
            "retired_family": "static hour suppression from a single discovery window",
            "windows": metadata,
            "interpretation_rules": [
                "Do not promote a filter from one month or one half-year.",
                "Mixed-sign setup/direction rows indicate regime instability, not a removable bad cohort.",
                "Use this output to define one causal mechanism before testing new untouched history.",
            ],
            "most_negative_monthly_rows": sorted(
                monthly, key=lambda row: float(row["net_profit"])
            )[:10],
            "stability": stability,
            "clusters": clusters,
        }
        prefix.with_suffix(".json").write_text(json.dumps(payload, indent=2) + "\n")
    except DiagnosticError as exc:
        print(f"Regime diagnostic FAILED: {exc}", file=sys.stderr)
        return 2

    print("Regime diagnostic complete; no MT5 run was performed.")
    print(f"Outputs: {args.output_prefix}.monthly.csv")
    print(f"         {args.output_prefix}.stability.csv")
    print(f"         {args.output_prefix}.clusters.csv")
    print(f"         {args.output_prefix}.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
