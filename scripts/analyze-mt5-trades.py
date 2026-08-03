#!/usr/bin/env python3
"""Summarize GoldBot real-mode trades.csv journals from MT5 Strategy Tester."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import statistics
import sys
from collections import Counter
from datetime import date, datetime, timedelta
from pathlib import Path


EVENTS = {
    "smc_candidates": "smc candidate",
    "pending_placed": "pending order placed",
    "pending_failed": "pending order failed",
    "ladders_placed": "pending ladder placed",
    "tp1_hits": "tp1 hit",
    "tp2_hits": "tp2 hit",
    "tp3_hits": "tp3 hit",
    "breakeven_moves": "breakeven moved",
    "deal_events": "deal event",
    "trailing_after_tp1": "trailing activated after tp1",
    "max_hold_closes": "position closed after max hold bars",
    "session_blocks": "real session filter blocked",
    "daily_ladder_blocks": "daily ladder limit blocked",
    "higher_tf_blocks": "higher timeframe confirmation blocked",
    "confluence_quality_blocks": "confluence quality blocked",
    "directional_adx_blocks": "directional adx blocked",
    "ema_trend_blocks": "ema trend blocked",
    "m5_pullback_blocks": "m5 pullback confirmation blocked",
    "m5_pullback_passes": "m5 pullback confirmation passed",
    "news_blocks": "news filter blocked",
    "direction_conflict_blocks": "direction conflict blocked",
    "direction_side_blocks": "direction side blocked",
    "near_zone_blocks": "near-zone placement blocked",
    "allowed_hour_blocks": "allowed entry hour blocked",
    "smc_sequence_blocks": "smc sequence blocked",
    "smc_liquidity_blocks": "smc liquidity sweep blocked",
    "smc_displacement_blocks": "smc displacement blocked",
    "smc_overlap_blocks": "smc ob/fvg overlap blocked",
    "htf_smc_context_blocks": "htf smc context blocked",
    "regime_blocks": "regime filter blocked",
    "strict_hour_quality_blocks": "strict hour quality blocked",
    "htf_tp_targets": "htf tp targets set",
    "signals_accepted": "signal accepted",
    "signal_skips": "signal skipped",
    "stop_breach_cancels": "stop breach",
    "scalp_failure_checkpoints": "scalp failure checkpoint",
    "scalp_failure_outcomes": "scalp failure outcome",
}


FIELD_RE = re.compile(r"([A-Za-z][A-Za-z0-9_]*)=([^\s,]+)")


def read_rows(path: Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    with path.open(newline="", errors="ignore") as handle:
        sample = handle.read(4096)
        handle.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",\t;")
        except csv.Error:
            dialect = csv.excel_tab
        reader = csv.reader(handle, dialect)
        for row in reader:
            if not row:
                continue
            if len(row) >= 2 and row[0].strip().lower() == "time":
                continue
            time_value = row[0].strip() if row else ""
            message = " ".join(cell.strip() for cell in row[1:] if cell.strip())
            if message:
                rows.append((time_value, message))
    return rows


def summarize_rows(journal_name: str, rows: list[tuple[str, str]]) -> dict[str, str]:
    counts: Counter[str] = Counter()
    for _, message in rows:
        lower = message.lower()
        matched = False
        for name, needle in EVENTS.items():
            if needle in lower:
                counts[name] += 1
                matched = True
        if not matched:
            counts["other_events"] += 1

    ladder_times = [time for time, message in rows if "pending ladder placed" in message.lower()]
    tp_times = [time for time, message in rows if message.lower().startswith("tp")]

    summary = {
        "journal": journal_name,
        "rows": str(len(rows)),
        "first_event_time": rows[0][0] if rows else "",
        "last_event_time": rows[-1][0] if rows else "",
        "first_ladder_time": ladder_times[0] if ladder_times else "",
        "last_ladder_time": ladder_times[-1] if ladder_times else "",
        "first_tp_time": tp_times[0] if tp_times else "",
        "last_tp_time": tp_times[-1] if tp_times else "",
    }
    for name in EVENTS:
        summary[name] = str(counts[name])
    summary["other_events"] = str(counts["other_events"])
    return summary


def summarize(path: Path) -> dict[str, str]:
    return summarize_rows(path.name, read_rows(path))


def parse_message_fields(message: str) -> dict[str, str]:
    return {match.group(1): match.group(2) for match in FIELD_RE.finditer(message)}


def as_float(value: str | None) -> float:
    try:
        return float(value or "0")
    except ValueError:
        return 0.0


def compact_value(prefix: str, value: str | None) -> str:
    return f"{prefix}{value or 'unknown'}"


def attribution_from_rows(journal_name: str, rows: list[tuple[str, str]], until: str | None = None) -> list[dict[str, str]]:
    if until:
        rows = [(time_value, message) for time_value, message in rows if time_value <= until]
    groups: dict[tuple[str, str], Counter[str]] = {}
    sums: dict[tuple[str, str], dict[str, float]] = {}

    def add(group_type: str, group_value: str, profit: float) -> None:
        key = (group_type, group_value or "unknown")
        groups.setdefault(key, Counter())
        sums.setdefault(key, {"net_profit": 0.0, "gross_profit": 0.0, "gross_loss": 0.0})
        groups[key]["closed_deals"] += 1
        if profit > 0:
            groups[key]["wins"] += 1
            sums[key]["gross_profit"] += profit
        elif profit < 0:
            groups[key]["losses"] += 1
            sums[key]["gross_loss"] += profit
        sums[key]["net_profit"] += profit

    for _, message in rows:
        lower = message.lower()
        if "deal event" not in lower:
            continue
        fields = parse_message_fields(message)
        entry = fields.get("entry", "")
        if entry not in {"1", "2", "3"}:
            continue
        profit = as_float(fields.get("profit"))
        setup = fields.get("setup", "unknown")
        direction = fields.get("dir", "unknown")
        split = fields.get("split", "unknown")
        hour = fields.get("hour", "unknown")
        scalp_variant = fields.get("scalpVariant", "unknown")
        confluences = fields.get("confluences", "unknown").split("/", 1)[0]
        for group_type, group_value in (
            ("setup", setup),
            ("scalp_variant", scalp_variant),
            ("direction", direction),
            ("split", split),
            ("session_hour", hour),
            ("setup_direction", f"{compact_value('setup', setup)}_{compact_value('dir', direction)}"),
            ("setup_direction_hour", f"{compact_value('setup', setup)}_{compact_value('dir', direction)}_{compact_value('hour', hour)}"),
            ("setup_direction_hour_split", f"{compact_value('setup', setup)}_{compact_value('dir', direction)}_{compact_value('hour', hour)}_{compact_value('split', split)}"),
            ("setup_scalp_variant", f"{compact_value('setup', setup)}_{compact_value('variant', scalp_variant)}"),
            ("scalp_variant_direction_hour", f"{compact_value('variant', scalp_variant)}_{compact_value('dir', direction)}_{compact_value('hour', hour)}"),
            ("direction_hour", f"{compact_value('dir', direction)}_{compact_value('hour', hour)}"),
            ("direction_hour_split", f"{compact_value('dir', direction)}_{compact_value('hour', hour)}_{compact_value('split', split)}"),
            ("direction_split", f"{compact_value('dir', direction)}_{compact_value('split', split)}"),
            ("hour_split", f"{compact_value('hour', hour)}_{compact_value('split', split)}"),
            ("score_bucket", fields.get("scoreBucket", "unknown")),
            ("confluence_count", confluences),
            ("exit_reason", fields.get("reason", "unknown")),
            ("setup_exit_reason", f"{compact_value('setup', setup)}_{compact_value('reason', fields.get('reason'))}"),
            ("setup_direction_hour_exit_reason", f"{compact_value('setup', setup)}_{compact_value('dir', direction)}_{compact_value('hour', hour)}_{compact_value('reason', fields.get('reason'))}"),
        ):
            add(group_type, group_value, profit)

    output: list[dict[str, str]] = []
    for key in sorted(groups):
        group_type, group_value = key
        count = groups[key]["closed_deals"]
        wins = groups[key]["wins"]
        gross_profit = sums[key]["gross_profit"]
        gross_loss = sums[key]["gross_loss"]
        profit_factor = gross_profit / abs(gross_loss) if gross_loss < 0 else (gross_profit if gross_profit > 0 else 0.0)
        output.append({
            "journal": journal_name,
            "group": group_type,
            "value": group_value,
            "closed_deals": str(count),
            "net_profit": f"{sums[key]['net_profit']:.2f}",
            "gross_profit": f"{gross_profit:.2f}",
            "gross_loss": f"{gross_loss:.2f}",
            "profit_factor": f"{profit_factor:.2f}",
            "win_rate_pct": f"{(wins / count * 100.0) if count else 0.0:.2f}",
        })
    return output


def attribution_rows(path: Path, until: str | None = None) -> list[dict[str, str]]:
    return attribution_from_rows(path.name, read_rows(path), until)


def _yes(value: str | None) -> bool:
    return (value or "").strip().lower() in {"yes", "true", "1"}


def failure_checkpoint_metrics_from_rows(
    journal_name: str,
    rows: list[tuple[str, str]],
    until: str | None = None,
) -> list[dict[str, str]]:
    """Measure the frozen Stage-1 shadow rule from checkpoint/outcome journals.

    Outcomes, rather than checkpoints alone, form the denominator so a scalp
    that reaches its stop before the halfway checkpoint still counts against
    full-loss recall. ``positionInstance`` includes the open timestamp because
    MT5 position IDs can restart in each process of a stitched chain.
    """
    if until:
        rows = [(time_value, message) for time_value, message in rows if time_value <= until]

    checkpoints: dict[str, dict[str, str]] = {}
    outcomes: dict[str, dict[str, str]] = {}
    for _, message in rows:
        lower = message.lower()
        if "scalp failure checkpoint" not in lower and "scalp failure outcome" not in lower:
            continue
        fields = parse_message_fields(message)
        position_key = fields.get("positionInstance") or fields.get("position")
        if not position_key:
            raise ValueError("scalp failure telemetry is missing positionInstance/position")
        target = checkpoints if "scalp failure checkpoint" in lower else outcomes
        previous = target.get(position_key)
        if previous is not None and previous != fields:
            raise ValueError(f"conflicting duplicate scalp failure telemetry: {position_key}")
        target[position_key] = fields

    for position_key, outcome in outcomes.items():
        checkpoint_logged = _yes(outcome.get("checkpointLogged"))
        checkpoint = checkpoints.get(position_key)
        if checkpoint_logged and checkpoint is None:
            raise ValueError(f"outcome references missing scalp failure checkpoint: {position_key}")
        if checkpoint is not None:
            if not checkpoint_logged:
                raise ValueError(f"checkpoint exists but outcome marks it missing: {position_key}")
            if _yes(checkpoint.get("triggered")) != _yes(outcome.get("triggered")):
                raise ValueError(f"checkpoint/outcome trigger mismatch: {position_key}")

    output: list[dict[str, str]] = []
    setups = sorted({fields.get("setup", "unknown") for fields in outcomes.values()})
    for setup in [*setups, "all_scalps"]:
        selected = [
            fields
            for fields in outcomes.values()
            if setup == "all_scalps" or fields.get("setup", "unknown") == setup
        ]
        if not selected:
            continue
        checkpoint_count = sum(_yes(row.get("checkpointLogged")) for row in selected)
        triggered = [row for row in selected if _yes(row.get("triggered"))]
        # DEAL_REASON_SL (4) is not sufficient to identify a full loss: a
        # trailing or breakeven stop can close at a profit.  The Stage-1 gate
        # is specifically about trimming the negative stop-loss tail, so keep
        # profitable stop exits in the profitable/false-trigger denominator
        # and never count them as full losses.
        full_losses = [
            row
            for row in selected
            if row.get("exitReason") == "4" and as_float(row.get("netProfit")) < 0.0
        ]
        triggered_full_losses = [
            row
            for row in triggered
            if row.get("exitReason") == "4" and as_float(row.get("netProfit")) < 0.0
        ]
        profitable = [row for row in selected if as_float(row.get("netProfit")) > 0.0]
        false_profitable_triggers = [row for row in triggered if as_float(row.get("netProfit")) > 0.0]
        before_costs = sum(as_float(row.get("counterfactualCashSavedBeforeCosts")) for row in triggered)
        after_costs = sum(as_float(row.get("counterfactualCashSavedAfterCosts")) for row in triggered)
        eventual_r_sum = sum(as_float(row.get("netR")) for row in triggered)
        non_shadow = sum(not _yes(row.get("shadowOnly")) for row in selected)
        output.append(
            {
                "journal": journal_name,
                "setup": setup,
                "scalp_positions": str(len(selected)),
                "checkpoints": str(checkpoint_count),
                "triggers": str(len(triggered)),
                "full_losses": str(len(full_losses)),
                "triggered_full_losses": str(len(triggered_full_losses)),
                "trigger_to_full_loss_precision_pct": f"{(len(triggered_full_losses) / len(triggered) * 100.0) if triggered else 0.0:.2f}",
                "full_loss_recall_pct": f"{(len(triggered_full_losses) / len(full_losses) * 100.0) if full_losses else 0.0:.2f}",
                "profitable_exits": str(len(profitable)),
                "false_profitable_triggers": str(len(false_profitable_triggers)),
                "false_trigger_rate_pct": f"{(len(false_profitable_triggers) / len(profitable) * 100.0) if profitable else 0.0:.2f}",
                "average_eventual_r_triggered": f"{(eventual_r_sum / len(triggered)) if triggered else 0.0:.5f}",
                "counterfactual_cash_saved_before_costs": f"{before_costs:.2f}",
                "counterfactual_cash_saved_after_costs": f"{after_costs:.2f}",
                "positive_savings_after_costs": "yes" if after_costs > 0.0 else "no",
                "non_shadow_outcomes": str(non_shadow),
            }
        )
    return output


def failure_checkpoint_metrics(path: Path, until: str | None = None) -> list[dict[str, str]]:
    return failure_checkpoint_metrics_from_rows(path.name, read_rows(path), until)


def deduplicate_chain_deals(rows: list[tuple[str, str]]) -> list[tuple[str, str]]:
    output: list[tuple[str, str]] = []
    seen: dict[tuple[str, str, str], str] = {}
    for timestamp, message in rows:
        if "deal event" not in message.lower():
            output.append((timestamp, message))
            continue
        fields = parse_message_fields(message)
        position_id = fields.get("position")
        deal_id = fields.get("deal")
        if not position_id or not deal_id:
            if fields.get("entry") in {"1", "2", "3"}:
                raise ValueError("chain closing deal is missing position/deal ID")
            output.append((timestamp, message))
            continue
        key = (timestamp, position_id, deal_id)
        previous = seen.get(key)
        if previous is None:
            seen[key] = message
            output.append((timestamp, message))
        elif previous != message:
            raise ValueError(f"conflicting duplicate chain deal: {key}")
    return output


def read_chain_manifest(path: Path) -> tuple[str, list[tuple[str, str]]]:
    try:
        manifest = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"invalid chain manifest {path}: {exc}") from exc
    segments = manifest.get("segments")
    if manifest.get("schema_version") != 1 or not isinstance(segments, list):
        raise ValueError(f"unsupported chain manifest: {path}")
    rows: list[tuple[str, str]] = []
    previous_end = ""
    for segment in segments:
        if not segment.get("valid") or not segment.get("flat") or not segment.get("report_fresh"):
            raise ValueError(f"invalid/non-flat/stale chain segment: {path}")
        start, end = str(segment.get("start", "")), str(segment.get("end", ""))
        if previous_end and start <= previous_end:
            raise ValueError(f"overlapping or unordered chain segments: {path}")
        previous_end = end
        journal = Path(str(segment.get("journal", "")))
        if not journal.is_absolute():
            journal = path.parent / journal
        if not journal.exists():
            raise ValueError(f"chain journal missing: {journal}")
        expected_hash = str(segment.get("journal_sha256", ""))
        actual_hash = hashlib.sha256(journal.read_bytes()).hexdigest()
        if not expected_hash or actual_hash != expected_hash:
            raise ValueError(f"chain journal hash mismatch: {journal}")
        rows.extend(read_rows(journal))
    return str(manifest.get("chain_name", path.stem)), deduplicate_chain_deals(rows)


def _decode_report(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")) or data.count(b"\x00") > 100:
        return data.decode("utf-16", errors="ignore")
    return data.decode("utf-8", errors="ignore")


def _load_continuation_manifest(
    path: Path,
) -> tuple[dict[str, object], list[tuple[int, str, str]]]:
    """Load a chain with immutable preset/report/journal evidence.

    The generic chain reader remains backwards compatible with Stage-0
    manifests. Continuation qualification is stricter: it requires the preset
    hash added for this experiment and validates every report as well as every
    journal before computing a metric.
    """
    try:
        manifest = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"invalid chain manifest {path}: {exc}") from exc
    segments = manifest.get("segments")
    if manifest.get("schema_version") != 1 or not isinstance(segments, list) or not segments:
        raise ValueError(f"unsupported chain manifest: {path}")
    preset_name = str(manifest.get("preset", ""))
    preset_hash = str(manifest.get("preset_sha256", ""))
    preset_path = Path(preset_name)
    if preset_path.is_absolute() or ".." in preset_path.parts or not preset_name:
        raise ValueError(f"invalid continuation preset path in {path}")
    preset_path = Path(__file__).resolve().parents[1] / "mt5/Presets" / preset_path
    if not preset_path.is_file():
        raise ValueError(f"continuation preset missing: {preset_path}")
    actual_preset_hash = hashlib.sha256(preset_path.read_bytes()).hexdigest()
    if not preset_hash or preset_hash != actual_preset_hash:
        raise ValueError(f"continuation preset hash mismatch: {preset_path}")

    output: list[tuple[int, str, str]] = []
    previous_end = ""
    for segment_index, segment in enumerate(segments, start=1):
        if not segment.get("valid") or not segment.get("flat") or not segment.get("report_fresh"):
            raise ValueError(f"invalid/non-flat/stale chain segment: {path}")
        start, end = str(segment.get("start", "")), str(segment.get("end", ""))
        if previous_end and start <= previous_end:
            raise ValueError(f"overlapping or unordered chain segments: {path}")
        previous_end = end
        for artifact_key in ("report", "journal"):
            artifact = Path(str(segment.get(artifact_key, "")))
            if not artifact.is_absolute():
                artifact = path.parent / artifact
            if not artifact.is_file():
                raise ValueError(f"chain {artifact_key} missing: {artifact}")
            expected_hash = str(segment.get(f"{artifact_key}_sha256", ""))
            actual_hash = hashlib.sha256(artifact.read_bytes()).hexdigest()
            if not expected_hash or expected_hash != actual_hash:
                raise ValueError(f"chain {artifact_key} hash mismatch: {artifact}")
            if artifact_key == "report":
                compact = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", _decode_report(artifact)))
                if "1970.01.01" in compact or re.search(r"Period:\s*M0\b", compact):
                    raise ValueError(f"malformed continuation report: {artifact}")
                if re.search(r"Initial Deposit:\s*0(?:\.0+)?\b", compact):
                    raise ValueError(f"malformed continuation report deposit: {artifact}")
            else:
                output.extend((segment_index, timestamp, message) for timestamp, message in read_rows(artifact))
    return manifest, output


def _observed_weekdays(start: date, target: date) -> int:
    if target < start:
        return 0
    value = 0
    current = start
    while current <= target:
        if current.weekday() < 5:
            value += 1
        current += timedelta(days=1)
    return value


def _event_month(timestamp: str) -> str:
    match = re.match(r"(\d{4})\.(\d{2})", timestamp)
    return f"{match.group(1)}-{match.group(2)}" if match else "unknown"


def _required_field(fields: dict[str, str], names: tuple[str, ...], context: str) -> str:
    for name in names:
        value = fields.get(name)
        if value is not None and value != "":
            return value
    raise ValueError(f"{context} is missing required field {'/'.join(names)}")


def _strict_float(fields: dict[str, str], names: tuple[str, ...], context: str) -> float:
    value = _required_field(fields, names, context)
    try:
        parsed = float(value)
    except ValueError as exc:
        raise ValueError(f"{context} has invalid numeric field {'/'.join(names)}={value}") from exc
    if parsed != parsed or parsed in {float("inf"), float("-inf")}:
        raise ValueError(f"{context} has non-finite field {'/'.join(names)}={value}")
    return parsed


def _strict_yes_no(fields: dict[str, str], names: tuple[str, ...], context: str) -> bool:
    value = _required_field(fields, names, context).strip().lower()
    if value in {"yes", "true", "1"}:
        return True
    if value in {"no", "false", "0"}:
        return False
    raise ValueError(f"{context} has invalid boolean field {'/'.join(names)}={value}")


def _manifest_artifact(manifest_path: Path, value: object) -> Path:
    artifact = Path(str(value or ""))
    if not artifact.is_absolute():
        artifact = manifest_path.parent / artifact
    return artifact


def _report_inputs(path: Path) -> dict[str, str]:
    text = re.sub(r"<[^>]+>", "\n", _decode_report(path))
    match = re.search(r"Inputs:\s*(.*?)(?:Company:|Results?\b|$)", text, re.I | re.S)
    if not match:
        raise ValueError(f"Inputs block missing: {path}")
    inputs: dict[str, str] = {}
    for key, value in re.findall(r"\b(Inp[A-Za-z0-9_]+)\s*=\s*([^\s<]+)", match.group(1)):
        if key in inputs and inputs[key] != value:
            raise ValueError(f"duplicate conflicting report input {key}: {path}")
        inputs[key] = value
    if not inputs:
        raise ValueError(f"Inputs block contains no EA inputs: {path}")
    return inputs


def _real_deal_signatures(rows: list[tuple[int, str, str]]) -> list[tuple[int, str, str]]:
    """Return exact ordered real-deal evidence, excluding no fields.

    Shadow telemetry is required to be behavior-inert.  Comparing the complete
    journal message catches changes to order lifecycle, costs, metadata, or
    timestamp even when aggregate PnL happens to remain equal.
    """
    return [
        (segment, timestamp, message)
        for segment, timestamp, message in rows
        if "deal event" in message.lower()
    ]


def _target_lock_timestamp(rows: list[tuple[int, str, str]]) -> str:
    values = [
        timestamp
        for _, timestamp, message in rows
        if "prop phase target lock reached" in message.lower()
        and _yes(parse_message_fields(message).get("completed"))
    ]
    return min(values) if values else ""


def _validate_causal_pair(
    shadow_path: Path,
    shadow_manifest: dict[str, object],
    shadow_rows: list[tuple[int, str, str]],
    control_path: Path,
    control_manifest: dict[str, object],
    control_rows: list[tuple[int, str, str]],
) -> None:
    shadow_segments = shadow_manifest["segments"]
    control_segments = control_manifest["segments"]
    assert isinstance(shadow_segments, list) and isinstance(control_segments, list)
    shadow_windows = [(row.get("start"), row.get("end")) for row in shadow_segments]
    control_windows = [(row.get("start"), row.get("end")) for row in control_segments]
    if shadow_windows != control_windows:
        raise ValueError("control/shadow causal-study windows differ")
    if shadow_manifest.get("source_hashes") != control_manifest.get("source_hashes"):
        raise ValueError("control/shadow source hashes differ")
    if shadow_manifest.get("ex5_sha256") != control_manifest.get("ex5_sha256"):
        raise ValueError("control/shadow EX5 hashes differ")

    allowed_difference = {"InpEnableContinuationCausalShadow"}
    for index, (shadow_segment, control_segment) in enumerate(
        zip(shadow_segments, control_segments), start=1
    ):
        shadow_report = _manifest_artifact(shadow_path, shadow_segment.get("report"))
        control_report = _manifest_artifact(control_path, control_segment.get("report"))
        shadow_inputs = _report_inputs(shadow_report)
        control_inputs = _report_inputs(control_report)
        if shadow_inputs.get("InpEnableContinuationCausalShadow", "false").lower() not in {"true", "1"}:
            raise ValueError(f"causal shadow is not enabled in segment {index}")
        if control_inputs.get("InpEnableContinuationCausalShadow", "false").lower() not in {"false", "0"}:
            raise ValueError(f"causal shadow is not default-off in control segment {index}")
        if shadow_inputs.get("InpContinuationCausalShadowHorizonBars", "32") != "32":
            raise ValueError(f"causal shadow horizon drift in segment {index}")
        if control_inputs.get("InpContinuationCausalShadowHorizonBars", "32") != "32":
            raise ValueError(f"control causal shadow horizon drift in segment {index}")
        differing = {
            key
            for key in shadow_inputs.keys() | control_inputs.keys()
            if shadow_inputs.get(key) != control_inputs.get(key)
        }
        if differing != allowed_difference:
            raise ValueError(
                f"undeclared control/shadow input differences in segment {index}: {sorted(differing)}"
            )

    if _real_deal_signatures(shadow_rows) != _real_deal_signatures(control_rows):
        raise ValueError("control/shadow real deal signatures differ")
    if _target_lock_timestamp(shadow_rows) != _target_lock_timestamp(control_rows):
        raise ValueError("control/shadow target-lock timestamps differ")

    metric_keys = (
        "net_profit",
        "profit_factor",
        "stitched_equity_drawdown_pct",
        "total_trades",
        "total_deals",
    )
    shadow_stitched = shadow_manifest.get("stitched")
    control_stitched = control_manifest.get("stitched")
    if not isinstance(shadow_stitched, dict) or not isinstance(control_stitched, dict):
        raise ValueError("control/shadow stitched metrics missing")
    for key in metric_keys:
        if shadow_stitched.get(key) != control_stitched.get(key):
            raise ValueError(f"control/shadow stitched metric differs: {key}")


def _validate_causal_chain_state(manifest: dict[str, object]) -> None:
    segments = manifest.get("segments")
    if not isinstance(segments, list) or len(segments) != 6:
        raise ValueError("causal shadow chain must contain exactly six segments")
    original_balance: float | None = None
    for index, segment in enumerate(segments, start=1):
        state = segment.get("carried_state")
        if not isinstance(state, dict):
            raise ValueError(f"causal shadow state metadata missing in segment {index}")
        if str(state.get("valid", "")).lower() != "true" or str(state.get("flat", "")).lower() != "true":
            raise ValueError(f"invalid/non-flat account state in segment {index}")
        balance = as_float(str(state.get("original_challenge_balance", "0")))
        if balance <= 0.0:
            raise ValueError(f"invalid challenge anchor in segment {index}")
        if original_balance is None:
            original_balance = balance
        elif abs(balance - original_balance) > 0.005:
            raise ValueError(f"mutable challenge anchor in segment {index}")
        shadow_valid = str(state.get("causal_shadow_state_valid", "")).lower()
        if str(state.get("causal_shadow_enabled", "")).lower() != "true":
            raise ValueError(f"causal shadow state is not enabled in segment {index}")
        if str(state.get("causal_shadow_state_version", "")) != "1":
            raise ValueError(f"unsupported causal shadow state version in segment {index}")
        if "causal_shadow_last_probe_id" not in state:
            raise ValueError(f"causal shadow dedupe state missing in segment {index}")
        if shadow_valid != "true":
            raise ValueError(f"missing/invalid causal shadow state marker in segment {index}")
        shadow_complete = str(state.get("causal_shadow_state_complete", "")).lower()
        if shadow_complete != "true":
            raise ValueError(f"missing/incomplete causal shadow state in segment {index}")
        try:
            active = int(str(state.get("causal_shadow_active_probe_count", "")))
        except ValueError as exc:
            raise ValueError(f"invalid causal shadow active-probe count in segment {index}") from exc
        if active not in {0, 1}:
            raise ValueError(f"invalid causal shadow active-probe count in segment {index}: {active}")
        if active == 1 and not str(state.get("causal_shadow_probe_id", "")):
            raise ValueError(f"active causal shadow state has no probe ID in segment {index}")
        if active == 1:
            active_keys = {
                "causal_shadow_probe_id",
                "causal_shadow_signal_time",
                "causal_shadow_expiry_time",
                "causal_shadow_direction",
                "causal_shadow_sl",
                "causal_shadow_signal_spread",
                "causal_shadow_would_displace_base",
                "causal_shadow_base_resolved",
                "causal_shadow_base_signal_id",
                "causal_shadow_base_setup",
                "causal_shadow_base_signal_code",
                "causal_shadow_displaced_base_net",
            }
            active_keys.update(
                f"causal_shadow_rung_{rung}_{field}"
                for rung in (1, 2)
                for field in (
                    "filled", "terminal", "fill_time", "barrier_time", "entry",
                    "risk_distance", "lot", "risk_cash", "spread_r", "commission_r",
                    "mfe_r", "mae_r", "gross_r", "net_r", "reason",
                )
            )
            missing_active = sorted(active_keys - state.keys())
            if missing_active:
                raise ValueError(
                    f"active causal shadow state payload incomplete in segment {index}: "
                    f"{missing_active}"
                )
            for rung in (1, 2):
                for field in ("entry", "risk_distance", "lot", "risk_cash"):
                    if as_float(str(state[f"causal_shadow_rung_{rung}_{field}"])) <= 0.0:
                        raise ValueError(
                            f"active causal shadow rung state invalid in segment {index}: "
                            f"rung={rung} field={field}"
                        )
                for field in ("spread_r", "commission_r"):
                    if as_float(str(state[f"causal_shadow_rung_{rung}_{field}"])) < 0.0:
                        raise ValueError(
                            f"active causal shadow cost state invalid in segment {index}: "
                            f"rung={rung} field={field}"
                        )
        if index == len(segments) and active != 0:
            raise ValueError(f"non-flat virtual state at final segment boundary: {active}")


def _causal_gate_flags(fields: dict[str, str], context: str) -> dict[str, bool]:
    adx = _strict_float(fields, ("adx",), context)
    signed_di_gap = _strict_float(
        fields, ("signedDiGap", "directionalDiGap", "diGap"), context
    )
    return {
        "adx": _strict_yes_no(fields, ("adxPass",), context) if fields.get("adxPass") is not None else adx >= 18.0,
        "directional_di": (
            _strict_yes_no(fields, ("directionalDiPass", "diPass"), context)
            if fields.get("directionalDiPass") is not None or fields.get("diPass") is not None
            else signed_di_gap >= 4.0
        ),
        "ema": _strict_yes_no(fields, ("emaPass",), context),
        "trend_side_vwap": _strict_yes_no(fields, ("trendSideVwapPass",), context),
        "m5_choch": _strict_yes_no(fields, ("microChoCHM5",), context),
        "zone": _strict_yes_no(fields, ("validZone", "zoneValid"), context),
        "slot": _strict_yes_no(fields, ("slotFreeAtSignal",), context),
    }


def _parse_failed_reasons(value: str) -> set[str]:
    if value.lower() in {"none", "-"}:
        return set()
    aliases = {
        "di": "directional_di",
        "di_gap": "directional_di",
        "directionaldi": "directional_di",
        "vwap": "trend_side_vwap",
        "trend_vwap": "trend_side_vwap",
        "trendsidevwap": "trend_side_vwap",
        "m5": "m5_choch",
        "m5choch": "m5_choch",
        "microchoch": "m5_choch",
        "microchochm5": "m5_choch",
        "validzone": "zone",
    }
    result: set[str] = set()
    for item in re.split(r"[|;+]", value):
        normalized = item.strip().lower().replace("-", "_")
        if normalized:
            result.add(aliases.get(normalized, normalized))
    return result


def _causal_scope_metrics(
    scope: str,
    month: str | None,
    candidates: dict[str, dict[str, object]],
    finals: dict[tuple[str, int], dict[str, object]],
    real_rows: list[tuple[int, str, str]],
    start_date: date,
) -> list[dict[str, str]]:
    def in_scope(timestamp: str) -> bool:
        return month is None or _event_month(timestamp) == month

    selected_candidates = {
        probe_id: record
        for probe_id, record in candidates.items()
        if in_scope(str(record["timestamp"]))
    }
    selected_ids = set(selected_candidates)
    selected_finals = [record for (probe_id, _), record in finals.items() if probe_id in selected_ids]

    failure_counts: Counter[str] = Counter()
    sessions: set[str] = set()
    eligible_ids: set[str] = set()
    deployable_ids: set[str] = set()
    suppressed_ids: set[str] = set()
    filled_probe_ids: set[str] = set()
    first44_filled_ids: set[str] = set()
    for probe_id, record in selected_candidates.items():
        fields = record["fields"]
        assert isinstance(fields, dict)
        sessions.add(str(record["session_id"]))
        flags = record["flags"]
        assert isinstance(flags, dict)
        for reason, passed in flags.items():
            if not passed:
                failure_counts[reason] += 1
        if bool(record["eligible"]):
            eligible_ids.add(probe_id)
    for record in selected_finals:
        probe_id = str(record["probe_id"])
        if bool(record["deployable"]):
            deployable_ids.add(probe_id)
        if bool(record["suppressed"]):
            suppressed_ids.add(probe_id)
        if bool(record["filled"]):
            filled_probe_ids.add(probe_id)
            candidate_date = datetime.strptime(
                str(selected_candidates[probe_id]["timestamp"])[:10], "%Y.%m.%d"
            ).date()
            if _observed_weekdays(start_date, candidate_date) <= 44:
                first44_filled_ids.add(probe_id)

    # Displacement is a probe-level fact repeated on both rung finals.  Require
    # the two records to agree and deduct each positive displaced base outcome
    # exactly once.
    displacement_by_probe: dict[str, float] = {}
    for probe_id in selected_ids:
        probe_finals = [record for record in selected_finals if record["probe_id"] == probe_id]
        values = {(bool(record["would_displace"]), float(record["displaced_base_net"])) for record in probe_finals}
        if len(values) != 1:
            raise ValueError(f"inconsistent base displacement attribution: {probe_id}")
        would_displace, displaced_net = next(iter(values))
        displacement_by_probe[probe_id] = displaced_net if would_displace else 0.0

    aggregate_groups: list[tuple[str, str, list[list[dict[str, object]]]]] = []
    filled_by_probe = {
        probe_id: [record for record in selected_finals if record["probe_id"] == probe_id and record["filled"]]
        for probe_id in selected_ids
    }
    aggregate_groups.append(("probe", "all", [values for values in filled_by_probe.values() if values]))
    for rung in (1, 2):
        aggregate_groups.append(
            (
                "rung",
                str(rung),
                [[record] for record in selected_finals if record["rung"] == rung and record["filled"]],
            )
        )

    output: list[dict[str, str]] = []
    for aggregation, rung, groups in aggregate_groups:
        net_cash_values: list[float] = []
        net_r_values: list[float] = []
        positive_gross_r_cash: list[float] = []
        mfe_values: list[float] = []
        mae_values: list[float] = []
        for group in groups:
            risk_cash = sum(float(record["risk_cash"]) for record in group)
            net_cash = sum(float(record["net_r"]) * float(record["risk_cash"]) for record in group)
            net_cash_values.append(net_cash)
            net_r_values.append(net_cash / risk_cash if risk_cash > 0.0 else 0.0)
            positive_gross_r_cash.append(
                max(0.0, sum(float(record["gross_r"]) * float(record["risk_cash"]) for record in group))
            )
            mfe_values.append(max(float(record["mfe_r"]) for record in group))
            mae_values.append(max(float(record["mae_r"]) for record in group))
        gross_profit = sum(value for value in net_cash_values if value > 0.0)
        gross_loss = sum(value for value in net_cash_values if value < 0.0)
        pf = gross_profit / abs(gross_loss) if gross_loss < 0.0 else (float("inf") if gross_profit > 0.0 else 0.0)
        displaced_positive = sum(max(0.0, value) for value in displacement_by_probe.values())
        conservative_net = sum(net_cash_values) - displaced_positive
        concentration = (
            max(positive_gross_r_cash) / sum(positive_gross_r_cash) * 100.0
            if positive_gross_r_cash and sum(positive_gross_r_cash) > 0.0 else 0.0
        )

        target_timestamp = ""
        target_days = ""
        if aggregation == "probe":
            cash_events: list[tuple[str, float]] = []
            for _, timestamp, message in real_rows:
                if not in_scope(timestamp) or "deal event" not in message.lower():
                    continue
                fields = parse_message_fields(message)
                if fields.get("entry") in {"0", "1", "2", "3"}:
                    cash_events.append((timestamp, as_float(fields.get("profit"))))
            for probe_id, group in filled_by_probe.items():
                if not group:
                    continue
                event_time = max(str(record["outcome_time"]) for record in group)
                increment = sum(float(record["net_r"]) * float(record["risk_cash"]) for record in group)
                increment -= max(0.0, displacement_by_probe.get(probe_id, 0.0))
                cash_events.append((event_time, increment))
            cumulative = 0.0
            cash_by_timestamp: dict[str, float] = {}
            for timestamp, amount in cash_events:
                cash_by_timestamp[timestamp] = cash_by_timestamp.get(timestamp, 0.0) + amount
            for timestamp in sorted(cash_by_timestamp):
                cumulative += cash_by_timestamp[timestamp]
                if cumulative >= 50000.0 * 0.0802:
                    target_timestamp = timestamp
                    target_date = datetime.strptime(timestamp[:10], "%Y.%m.%d").date()
                    target_days = str(_observed_weekdays(start_date, target_date))
                    break

        gate_reasons: list[str] = []
        if aggregation == "probe" and month is None:
            if len(eligible_ids) < 6:
                gate_reasons.append("eligible_lt_6")
            if len(filled_probe_ids) < 5:
                gate_reasons.append("deployable_fills_lt_5")
            if len(first44_filled_ids) < 3:
                gate_reasons.append("first44_fills_lt_3")
            if pf < 1.30:
                gate_reasons.append("pf_lt_1.30")
            if sum(net_r_values) <= 0.0:
                gate_reasons.append("net_r_nonpositive")
            if not net_r_values or statistics.mean(net_r_values) <= 0.0:
                gate_reasons.append("average_net_r_nonpositive")
            if conservative_net <= 0.0:
                gate_reasons.append("incremental_net_nonpositive")
            if concentration > 60.0:
                gate_reasons.append("profit_concentration_gt_60pct")
            if not target_days or int(target_days) > 66:
                gate_reasons.append("target_later_than_66_weekdays")

        output.append(
            {
                "scope": scope,
                "aggregation": aggregation,
                "rung": rung,
                "universe_bars": str(len(selected_candidates)),
                "distinct_sessions": str(len(sessions)),
                "causal_eligible": str(len(eligible_ids)),
                "deployable": str(len(deployable_ids)),
                "overlap_suppressed": str(len(suppressed_ids)),
                "deployable_filled_probes": str(len(filled_probe_ids)),
                "virtual_filled_rungs": str(sum(bool(record["filled"]) for record in selected_finals)),
                "fills_first_44_weekdays": str(len(first44_filled_ids)),
                "failed_adx": str(failure_counts["adx"]),
                "failed_directional_di": str(failure_counts["directional_di"]),
                "failed_ema": str(failure_counts["ema"]),
                "failed_trend_side_vwap": str(failure_counts["trend_side_vwap"]),
                "failed_m5_choch": str(failure_counts["m5_choch"]),
                "failed_zone": str(failure_counts["zone"]),
                "failed_slot": str(failure_counts["slot"]),
                "outcomes": str(len(groups)),
                "net_cash": f"{sum(net_cash_values):.2f}",
                "gross_profit": f"{gross_profit:.2f}",
                "gross_loss": f"{gross_loss:.2f}",
                "profit_factor": "inf" if pf == float("inf") else f"{pf:.4f}",
                "win_rate_pct": f"{(sum(value > 0.0 for value in net_cash_values) / len(net_cash_values) * 100.0) if net_cash_values else 0.0:.2f}",
                "average_net_r": f"{statistics.mean(net_r_values) if net_r_values else 0.0:.5f}",
                "median_net_r": f"{statistics.median(net_r_values) if net_r_values else 0.0:.5f}",
                "total_net_r": f"{sum(net_r_values):.5f}",
                "average_mfe_r": f"{statistics.mean(mfe_values) if mfe_values else 0.0:.5f}",
                "median_mfe_r": f"{statistics.median(mfe_values) if mfe_values else 0.0:.5f}",
                "average_mae_r": f"{statistics.mean(mae_values) if mae_values else 0.0:.5f}",
                "median_mae_r": f"{statistics.median(mae_values) if mae_values else 0.0:.5f}",
                "displaced_base_net": f"{sum(displacement_by_probe.values()):.2f}",
                "positive_displaced_base_net": f"{displaced_positive:.2f}",
                "conservative_incremental_net": f"{conservative_net:.2f}",
                "max_positive_probe_contribution_pct": f"{concentration:.2f}",
                "counterfactual_target_timestamp": target_timestamp,
                "counterfactual_target_weekdays": target_days,
                "real_deal_signature_parity": "yes",
                "report_validity": "yes",
                "chain_state_integrity": "yes",
                "firm_or_internal_breach": "no",
                "frozen_train_gate": "pass" if aggregation == "probe" and month is None and not gate_reasons else ("fail" if aggregation == "probe" and month is None else "n/a"),
                "frozen_train_gate_reasons": "|".join(gate_reasons) if gate_reasons else "none",
            }
        )
    return output


def _validate_causal_state_round_trip(
    manifest: dict[str, object],
    candidates: dict[str, dict[str, object]],
    finals: dict[tuple[str, int], dict[str, object]],
) -> None:
    """Reconcile exported virtual state with journal lifecycle at every boundary."""
    segments = manifest["segments"]
    assert isinstance(segments, list)
    for segment_index, segment in enumerate(segments, start=1):
        expected_active = []
        for probe_id, candidate in candidates.items():
            if not bool(candidate["deployable"]) or int(candidate["segment"]) > segment_index:
                continue
            completed_rungs = {
                rung
                for rung in (1, 2)
                if (probe_id, rung) in finals
                and int(finals[(probe_id, rung)]["segment"]) <= segment_index
            }
            if completed_rungs != {1, 2}:
                expected_active.append(probe_id)
        if len(expected_active) > 1:
            raise ValueError(
                f"more than one virtual causal probe active at segment boundary {segment_index}: "
                f"{sorted(expected_active)}"
            )
        state = segment["carried_state"]
        assert isinstance(state, dict)
        actual_count = int(str(state["causal_shadow_active_probe_count"]))
        if actual_count != len(expected_active):
            raise ValueError(
                f"causal shadow state/journal active-count mismatch at segment {segment_index}: "
                f"{actual_count} vs {len(expected_active)}"
            )
        actual_probe = str(state.get("causal_shadow_probe_id", ""))
        if expected_active and actual_probe != expected_active[0]:
            raise ValueError(
                f"causal shadow state/journal probe mismatch at segment {segment_index}: "
                f"{actual_probe} vs {expected_active[0]}"
            )
        if not expected_active and actual_probe.lower() not in {"", "none"}:
            raise ValueError(
                f"flat causal shadow state retains probe ID at segment {segment_index}: {actual_probe}"
            )
        candidates_through_boundary = [
            (int(candidate["segment"]), str(candidate["timestamp"]), probe_id)
            for probe_id, candidate in candidates.items()
            if int(candidate["segment"]) <= segment_index
        ]
        expected_last = max(candidates_through_boundary)[2] if candidates_through_boundary else ""
        if str(state.get("causal_shadow_last_probe_id", "")) != expected_last:
            raise ValueError(
                f"causal shadow dedupe state/journal mismatch at segment {segment_index}: "
                f"{state.get('causal_shadow_last_probe_id', '')} vs {expected_last}"
            )
        if expected_active and segment_index < len(segments):
            probe_id = expected_active[0]
            completes_next = all(
                (probe_id, rung) in finals
                and int(finals[(probe_id, rung)]["segment"]) == segment_index + 1
                for rung in (1, 2)
            )
            next_state = segments[segment_index]["carried_state"]
            assert isinstance(next_state, dict)
            carried_next = (
                int(str(next_state["causal_shadow_active_probe_count"])) == 1
                and str(next_state.get("causal_shadow_probe_id", "")) == probe_id
            )
            if not completes_next and not carried_next:
                raise ValueError(
                    f"causal shadow state did not round-trip into segment {segment_index + 1}: {probe_id}"
                )


def continuation_causal_shadow_study_rows(
    shadow_manifest_path: Path,
    control_manifest_path: Path,
) -> list[dict[str, str]]:
    """Analyze the frozen CS1 telemetry without mixing it into real attribution."""
    shadow_manifest, shadow_rows = _load_continuation_manifest(shadow_manifest_path)
    control_manifest, control_rows = _load_continuation_manifest(control_manifest_path)
    _validate_causal_pair(
        shadow_manifest_path,
        shadow_manifest,
        shadow_rows,
        control_manifest_path,
        control_manifest,
        control_rows,
    )
    _validate_causal_chain_state(shadow_manifest)

    stitched = shadow_manifest.get("stitched")
    assert isinstance(stitched, dict)
    equity_dd = as_float(str(stitched.get("stitched_equity_drawdown_pct", "0")))
    if equity_dd > 7.5:
        raise ValueError(f"causal shadow chain exceeded 7.5% global DD stop: {equity_dd:.5f}%")
    first_segment = shadow_manifest["segments"][0]
    assert isinstance(first_segment, dict)
    first_report = _manifest_artifact(shadow_manifest_path, first_segment.get("report"))
    report_inputs = _report_inputs(first_report)
    firm_floor = as_float(report_inputs.get("InpPropFirmMaxDrawdownPct", "10"))
    internal_floor = as_float(report_inputs.get("InpPropDdHardHaltPct", "8"))
    if equity_dd >= firm_floor or equity_dd >= internal_floor:
        raise ValueError(
            f"causal shadow chain breached firm/internal DD floor: {equity_dd:.5f}%"
        )

    breach_needles = (
        "prop mode breach flatten",
        "prop_max_dd_halt",
        "prop_daily_hard_flatten",
    )
    if any(any(needle in message.lower() for needle in breach_needles) for _, _, message in shadow_rows):
        raise ValueError("firm/internal breach in causal shadow chain")

    candidates: dict[str, dict[str, object]] = {}
    tuple_ids: dict[tuple[str, str], str] = {}
    finals: dict[tuple[str, int], dict[str, object]] = {}
    for segment_index, timestamp, message in shadow_rows:
        lower = message.lower()
        fields = parse_message_fields(message)
        if "continuation causal shadow candidate" in lower:
            context = f"causal candidate at {timestamp}"
            probe_id = _required_field(fields, ("probeId",), context)
            if probe_id in candidates:
                raise ValueError(f"duplicate causal shadow probe ID: {probe_id}")
            signal_time = _required_field(fields, ("signalTime", "barTime", "time"), context)
            direction = _required_field(fields, ("dir", "direction"), context)
            tuple_key = (signal_time, direction)
            if tuple_key in tuple_ids:
                raise ValueError(
                    f"duplicate causal shadow bar/direction: {signal_time}/{direction}"
                )
            tuple_ids[tuple_key] = probe_id
            _required_field(fields, ("hour",), context)
            _strict_float(fields, ("score",), context)
            _strict_float(fields, ("threshold",), context)
            _required_field(fields, ("confluences",), context)
            session_id = _required_field(fields, ("sessionId", "session"), context)
            # Raw component values are mandatory evidence, not optional display.
            for names in (
                ("m15Close",), ("h1Close",), ("ema21",), ("ema50",), ("ema200",),
                ("sessionVwap", "vwap"), ("atr",), ("adx",), ("plusDI",), ("minusDI",),
                ("vwapDistanceAtr", "signedVwapAtr"),
                ("directionalDiGap", "signedDiGap", "diGap"),
                ("zoneBottom",), ("zoneTop",),
            ):
                _strict_float(fields, names, context)
            _strict_yes_no(fields, ("legacyVwapPass",), context)
            _strict_yes_no(fields, ("candlePatternM15",), context)
            _strict_yes_no(fields, ("rsiShiftM15",), context)
            _strict_yes_no(fields, ("legacyAggregate",), context)
            _strict_float(fields, ("legacyPullbackChecks", "legacyChecks"), context)
            flags = _causal_gate_flags(fields, context)
            eligible = _strict_yes_no(fields, ("causalEligible",), context)
            expected_eligible = all(flags[name] for name in flags if name != "slot")
            if eligible != expected_eligible:
                raise ValueError(f"causal eligibility/component mismatch: {probe_id}")
            failed = _parse_failed_reasons(
                _required_field(fields, ("failedCausalReasons", "failedReasons", "failed"), context)
            )
            expected_failed = {name for name, passed in flags.items() if not passed}
            if failed != expected_failed:
                raise ValueError(
                    f"causal failed-reason mismatch for {probe_id}: {sorted(failed)} vs {sorted(expected_failed)}"
                )
            deployable = _strict_yes_no(fields, ("deployable",), context)
            suppressed = _strict_yes_no(fields, ("overlapSuppressed",), context)
            if deployable != (eligible and flags["slot"] and not suppressed):
                raise ValueError(f"causal candidate deployability mismatch: {probe_id}")
            if suppressed and (not eligible or not flags["slot"]):
                raise ValueError(f"invalid causal candidate overlap suppression: {probe_id}")
            candidates[probe_id] = {
                "segment": segment_index,
                "timestamp": timestamp,
                "session_id": session_id,
                "fields": fields,
                "flags": flags,
                "eligible": eligible,
                "deployable": deployable,
                "suppressed": suppressed,
            }
        elif "continuation causal shadow final" in lower:
            context = f"causal final at {timestamp}"
            probe_id = _required_field(fields, ("probeId",), context)
            try:
                rung = int(_required_field(fields, ("rung",), context))
            except ValueError as exc:
                raise ValueError(f"invalid causal final rung at {timestamp}") from exc
            if rung not in {1, 2}:
                raise ValueError(f"invalid causal final rung: {probe_id}/{rung}")
            key = (probe_id, rung)
            if key in finals:
                raise ValueError(f"duplicate causal shadow final: {probe_id}/{rung}")
            eligible = _strict_yes_no(fields, ("eligible", "causalEligible"), context)
            deployable = _strict_yes_no(fields, ("deployable",), context)
            suppressed = _strict_yes_no(fields, ("overlapSuppressed", "suppressed"), context)
            filled = _strict_yes_no(fields, ("filled",), context)
            costs_included = _strict_yes_no(fields, ("costsIncluded",), context)
            if not costs_included:
                raise ValueError(f"causal shadow final omits costs: {probe_id}/{rung}")
            spread_r = _strict_float(fields, ("spreadR",), context)
            commission_r = _strict_float(fields, ("commissionR",), context)
            net_r = _strict_float(fields, ("netR",), context)
            gross_r = _strict_float(fields, ("grossR",), context)
            risk_cash = _strict_float(fields, ("modeledRiskCash", "riskCash"), context)
            mfe_r = _strict_float(fields, ("mfeR",), context)
            mae_r = _strict_float(fields, ("maeR",), context)
            would_displace = _strict_yes_no(fields, ("wouldDisplaceBase",), context)
            displaced_net = _strict_float(fields, ("displacedBaseNet",), context)
            if would_displace:
                _required_field(
                    fields,
                    ("displacedBaseSignalId", "displacedBaseSignal", "baseSignalId"),
                    context,
                )
                _required_field(fields, ("displacedBaseSetup", "baseSetup"), context)
            elif abs(displaced_net) > 0.005:
                raise ValueError(
                    f"non-displacing causal final carries base net: {probe_id}/{rung}"
                )
            if abs(net_r - (gross_r - spread_r - commission_r)) > 0.0001:
                raise ValueError(f"causal shadow cost identity mismatch: {probe_id}/{rung}")
            if not _strict_yes_no(fields, ("stateFlat",), context):
                raise ValueError(f"causal shadow final marks non-flat state: {probe_id}/{rung}")
            if not _strict_yes_no(fields, ("metadataValid",), context):
                raise ValueError(f"causal shadow final marks invalid metadata: {probe_id}/{rung}")
            if deployable and (not eligible or suppressed):
                raise ValueError(f"invalid deployable classification: {probe_id}/{rung}")
            if filled and not deployable:
                raise ValueError(f"non-deployable causal rung was filled: {probe_id}/{rung}")
            if deployable:
                _strict_float(fields, ("virtualEntry", "entry"), context)
                _strict_float(fields, ("sl",), context)
                if _strict_float(fields, ("riskDistance",), context) <= 0.0 or risk_cash <= 0.0:
                    raise ValueError(f"invalid causal risk model: {probe_id}/{rung}")
            if filled:
                _required_field(fields, ("fillTime",), context)
                _required_field(fields, ("firstBarrierReason", "barrierReason"), context)
                _required_field(
                    fields, ("firstBarrierTime", "outcomeTime", "expiryTime"), context
                )
            else:
                _required_field(
                    fields, ("firstBarrierTime", "outcomeTime", "expiryTime"), context
                )
            finals[key] = {
                "segment": segment_index,
                "probe_id": probe_id,
                "rung": rung,
                "eligible": eligible,
                "deployable": deployable,
                "suppressed": suppressed,
                "filled": filled,
                "spread_r": spread_r,
                "commission_r": commission_r,
                "net_r": net_r,
                "gross_r": gross_r,
                "risk_cash": risk_cash,
                "mfe_r": mfe_r,
                "mae_r": mae_r,
                "would_displace": would_displace,
                "displaced_base_net": displaced_net,
                "outcome_time": timestamp,
            }

    if not candidates:
        raise ValueError("causal shadow journal contains no candidate records")
    unknown_finals = sorted({probe_id for probe_id, _ in finals} - candidates.keys())
    if unknown_finals:
        raise ValueError(f"causal shadow finals reference unknown probes: {unknown_finals}")
    for probe_id, candidate in candidates.items():
        if {(pid, rung) for pid, rung in finals if pid == probe_id} != {(probe_id, 1), (probe_id, 2)}:
            raise ValueError(f"missing causal shadow final record: {probe_id}")
        probe_finals = [finals[(probe_id, 1)], finals[(probe_id, 2)]]
        for record in probe_finals:
            if bool(record["eligible"]) != bool(candidate["eligible"]):
                raise ValueError(f"candidate/final eligibility mismatch: {probe_id}")
        classifications = {
            (record["deployable"], record["suppressed"]) for record in probe_finals
        }
        if len(classifications) != 1:
            raise ValueError(f"inconsistent rung classification: {probe_id}")
        flags = candidate["flags"]
        assert isinstance(flags, dict)
        if any(bool(record["deployable"]) for record in probe_finals) and not bool(flags["slot"]):
            raise ValueError(f"deployable causal probe had no real slot at signal: {probe_id}")

    _validate_causal_state_round_trip(shadow_manifest, candidates, finals)

    start_date = datetime.strptime(str(first_segment["start"]), "%Y.%m.%d").date()
    last_segment = shadow_manifest["segments"][-1]
    assert isinstance(last_segment, dict)
    end_date = datetime.strptime(str(last_segment["end"]), "%Y.%m.%d").date()
    months: list[str] = []
    month_cursor = start_date.replace(day=1)
    while month_cursor < end_date:
        months.append(month_cursor.strftime("%Y-%m"))
        month_cursor = (
            month_cursor.replace(year=month_cursor.year + 1, month=1)
            if month_cursor.month == 12
            else month_cursor.replace(month=month_cursor.month + 1)
        )
    scopes: list[tuple[str, str | None]] = [("window", None)] + [(month, month) for month in months]
    output: list[dict[str, str]] = []
    for scope, month in scopes:
        output.extend(
            _causal_scope_metrics(
                scope, month, candidates, finals, shadow_rows, start_date
            )
        )
    return output


def _position_cohorts(
    rows: list[tuple[int, str, str]],
) -> dict[tuple[int, str], dict[str, object]]:
    positions: dict[tuple[int, str], dict[str, object]] = {}
    for segment_index, timestamp, message in rows:
        if "deal event" not in message.lower():
            continue
        fields = parse_message_fields(message)
        position_id = fields.get("position")
        if not position_id:
            continue
        key = (segment_index, position_id)
        cohort = positions.setdefault(
            key,
            {
                "fields": fields,
                "fill_time": "",
                "close_times": [],
                "profit": 0.0,
                "risk_cash": 0.0,
            },
        )
        cohort["profit"] = float(cohort["profit"]) + as_float(fields.get("profit"))
        risk_cash = as_float(fields.get("riskCash"))
        if risk_cash > 0.0:
            cohort["risk_cash"] = risk_cash
        entry = fields.get("entry")
        if entry in {"0", "2"} and not cohort["fill_time"]:
            cohort["fill_time"] = timestamp
            cohort["fields"] = fields
        if entry in {"1", "2", "3"}:
            cast_times = cohort["close_times"]
            assert isinstance(cast_times, list)
            cast_times.append(timestamp)
    return positions


def _base_position_signatures(
    rows: list[tuple[int, str, str]], cutoff: str | None = None
) -> dict[tuple[str, str], str]:
    signatures: dict[tuple[str, str], str] = {}
    for _, timestamp, message in rows:
        if cutoff and timestamp > cutoff:
            continue
        if "deal event" not in message.lower():
            continue
        fields = parse_message_fields(message)
        if fields.get("entry") not in {"0", "2"}:
            continue
        setup = fields.get("setup", "unknown")
        if setup == "continuation":
            continue
        comment = fields.get("comment", "")
        if not comment:
            raise ValueError("base position entry is missing its immutable signal comment")
        signatures[(setup, comment)] = timestamp
    return signatures


def continuation_study_rows(
    candidate_manifest_path: Path,
    control_manifest_path: Path | None = None,
) -> list[dict[str, str]]:
    manifest, rows = _load_continuation_manifest(candidate_manifest_path)
    control_rows: list[tuple[int, str, str]] = []
    if control_manifest_path is not None:
        control_manifest, control_rows = _load_continuation_manifest(control_manifest_path)
        candidate_segments = [(row.get("start"), row.get("end")) for row in manifest["segments"]]
        control_segments = [(row.get("start"), row.get("end")) for row in control_manifest["segments"]]
        if candidate_segments != control_segments:
            raise ValueError("candidate/control continuation-study windows differ")
        if manifest.get("source_hashes") != control_manifest.get("source_hashes"):
            raise ValueError("candidate/control source hashes differ")
        if manifest.get("ex5_sha256") != control_manifest.get("ex5_sha256"):
            raise ValueError("candidate/control EX5 hashes differ")

    candidate_times: set[tuple[int, str]] = set()
    accepted_times: set[tuple[int, str]] = set()
    blocked_events: list[tuple[int, str, dict[str, str]]] = []
    target_times: list[str] = []
    daily_breach_times: list[str] = []
    for segment_index, timestamp, message in rows:
        lower = message.lower()
        fields = parse_message_fields(message)
        key = (segment_index, timestamp)
        if "continuation setup accepted" in lower:
            candidate_times.add(key)
            accepted_times.add(key)
        elif "continuation setup blocked" in lower:
            candidate_times.add(key)
            blocked_events.append((segment_index, timestamp, fields))
        elif "signal skipped setup=smc" in lower and "zone=no" in lower:
            if as_float(fields.get("score")) >= as_float(fields.get("threshold")):
                candidate_times.add(key)
        if "prop phase target lock reached" in lower and _yes(fields.get("completed")):
            target_times.append(timestamp)
        if "prop mode breach flatten" in lower and "prop_daily_hard_flatten" in lower:
            daily_breach_times.append(timestamp)

    positions = _position_cohorts(rows)
    continuation_positions: dict[tuple[int, str], dict[str, object]] = {}
    deal_fields = [
        parse_message_fields(message)
        for _, _, message in rows
        if "deal event" in message.lower()
    ]
    any_unattributed_deal = any(fields.get("setupMetadata") != "yes" for fields in deal_fields)
    if any(
        fields.get("setup") == "continuation" and fields.get("setupMetadata") != "yes"
        for fields in deal_fields
    ):
        raise ValueError("continuation deal lost setup metadata")
    for key, cohort in positions.items():
        fields = cohort["fields"]
        assert isinstance(fields, dict)
        if fields.get("setup") == "continuation":
            if not cohort["fill_time"] or not cohort["close_times"]:
                raise ValueError(f"continuation position is unfilled/non-flat: {key}")
            if float(cohort["risk_cash"]) <= 0.0:
                raise ValueError(f"continuation position is missing riskCash metadata: {key}")
            continuation_positions[key] = cohort
    if accepted_times and any_unattributed_deal:
        raise ValueError("accepted continuation run contains a deal without setup metadata")

    first_target = min(target_times) if target_times else ""
    start_text = str(manifest["segments"][0]["start"])
    start_date = datetime.strptime(start_text, "%Y.%m.%d").date()
    target_days = ""
    if first_target:
        target_date = datetime.strptime(first_target[:10], "%Y.%m.%d").date()
        target_days = str(_observed_weekdays(start_date, target_date))

    candidate_base = _base_position_signatures(rows, first_target or None)
    missing_base_by_month: Counter[str] = Counter()
    if control_rows:
        control_base = _base_position_signatures(control_rows, first_target or None)
        for signature, timestamp in control_base.items():
            if signature not in candidate_base:
                missing_base_by_month[_event_month(timestamp)] += 1

    stitched = manifest.get("stitched", {})
    if not isinstance(stitched, dict):
        raise ValueError("continuation manifest stitched metrics missing")
    equity_dd = as_float(str(stitched.get("stitched_equity_drawdown_pct", "0")))
    first_report = Path(str(manifest["segments"][0]["report"]))
    if not first_report.is_absolute():
        first_report = candidate_manifest_path.parent / first_report
    report_text = re.sub(r"\s+", "", re.sub(r"<[^>]+>", "\n", _decode_report(first_report)))
    firm_match = re.search(r"InpPropFirmMaxDrawdownPct=([-\d.]+)", report_text)
    internal_match = re.search(r"InpPropDdHardHaltPct=([-\d.]+)", report_text)
    firm_floor_pct = as_float(firm_match.group(1) if firm_match else "10")
    internal_floor_pct = as_float(internal_match.group(1) if internal_match else "8")
    internal_log_times = [timestamp for _, timestamp, message in rows if "prop_max_dd_halt" in message.lower()]

    months = sorted(
        {_event_month(timestamp) for _, timestamp, _ in rows if _event_month(timestamp) != "unknown"}
    )
    scopes: list[tuple[str, str | None]] = [("window", None)] + [(month, month) for month in months]
    output: list[dict[str, str]] = []
    for scope, month in scopes:
        def in_scope(timestamp: str) -> bool:
            return month is None or _event_month(timestamp) == month

        scope_candidates = {key for key in candidate_times if in_scope(key[1])}
        scope_accepted = {key for key in accepted_times if in_scope(key[1])}
        scope_blocked = [(segment, timestamp, fields) for segment, timestamp, fields in blocked_events if in_scope(timestamp)]
        blocked_keys = {(segment, timestamp) for segment, timestamp, _ in scope_blocked}
        early_blocks = scope_candidates - scope_accepted - blocked_keys
        blocked_counts: Counter[str] = Counter()
        for _, _, fields in scope_blocked:
            if as_float(fields.get("adx")) < as_float(fields.get("minAdx")):
                blocked_counts["adx"] += 1
            if as_float(fields.get("diGap")) < as_float(fields.get("minDiGap")):
                blocked_counts["di_gap"] += 1
            if fields.get("ema") != "yes":
                blocked_counts["ema"] += 1
            if fields.get("vwap") != "yes":
                blocked_counts["vwap"] += 1
            if fields.get("zone") != "yes":
                blocked_counts["zone"] += 1
            if fields.get("m5") != "yes":
                blocked_counts["m5"] += 1

        selected = [cohort for cohort in continuation_positions.values() if in_scope(str(cohort["fill_time"]))]
        profits = [float(cohort["profit"]) for cohort in selected]
        gross_profit = sum(value for value in profits if value > 0.0)
        gross_loss = sum(value for value in profits if value < 0.0)
        pf = gross_profit / abs(gross_loss) if gross_loss < 0.0 else (float("inf") if gross_profit > 0.0 else 0.0)
        net_rs = [float(cohort["profit"]) / float(cohort["risk_cash"]) for cohort in selected]
        closing_deals = sum(
            1
            for cohort in continuation_positions.values()
            for close_time in cohort["close_times"]
            if in_scope(str(close_time))
        )
        missing_base = sum(missing_base_by_month.values()) if month is None else missing_base_by_month[month]
        daily_breach = any(in_scope(value) for value in daily_breach_times)
        internal_breach = any(in_scope(value) for value in internal_log_times)
        if month is None:
            internal_breach = internal_breach or equity_dd >= internal_floor_pct
            static_breach = equity_dd >= firm_floor_pct
        else:
            static_breach = False
        output.append(
            {
                "manifest": candidate_manifest_path.name,
                "scope": scope,
                "high_score_zoneless_candidate_bars": str(len(scope_candidates)),
                "continuation_accepted": str(len(scope_accepted)),
                "continuation_blocked": str(len(scope_blocked) + len(early_blocks)),
                "blocked_hour_or_early_gate": str(len(early_blocks)),
                "blocked_adx": str(blocked_counts["adx"]),
                "blocked_di_gap": str(blocked_counts["di_gap"]),
                "blocked_ema": str(blocked_counts["ema"]),
                "blocked_vwap": str(blocked_counts["vwap"]),
                "blocked_zone": str(blocked_counts["zone"]),
                "blocked_m5": str(blocked_counts["m5"]),
                "filled_continuation_positions": str(len(selected)),
                "continuation_closing_deals": str(closing_deals),
                "continuation_net": f"{sum(profits):.2f}",
                "continuation_gross_profit": f"{gross_profit:.2f}",
                "continuation_gross_loss": f"{gross_loss:.2f}",
                "continuation_profit_factor": "inf" if pf == float("inf") else f"{pf:.4f}",
                "continuation_win_rate_pct": f"{(sum(value > 0.0 for value in profits) / len(profits) * 100.0) if profits else 0.0:.2f}",
                "continuation_average_net_r": f"{(sum(net_rs) / len(net_rs)) if net_rs else 0.0:.5f}",
                "base_positions_displaced": str(missing_base),
                "first_target_lock_timestamp": first_target if month is None or (first_target and in_scope(first_target)) else "",
                "elapsed_observed_trading_days": target_days if month is None else "",
                "daily_loss_breach": "yes" if daily_breach else "no",
                "static_floor_breach": "yes" if static_breach else "no",
                "internal_floor_breach": "yes" if internal_breach else "no",
                "malformed_report": "no",
                "non_flat_state": "no",
            }
        )
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("journals", nargs="*", type=Path, help="GoldBot trades.csv paths")
    parser.add_argument("--chain-manifest", action="append", default=[], type=Path, help="FundingPips chain manifest JSON")
    parser.add_argument("--attribution", action="store_true", help="Group closed deal PnL by setup, direction, split, hour, setup/direction/hour/split, direction/hour/split, score, confluence, and exit reason")
    parser.add_argument("--failure-checkpoints", action="store_true", help="Report Stage-1 scalp failure checkpoint confusion/savings metrics")
    parser.add_argument(
        "--continuation-study",
        action="store_true",
        help="Report frozen FundingPips continuation metrics for exactly one chain manifest",
    )
    parser.add_argument(
        "--continuation-causal-shadow-study",
        action="store_true",
        help="Report strict CS1 causal-shadow metrics for one shadow/control chain pair",
    )
    parser.add_argument(
        "--control-chain-manifest",
        type=Path,
        help="paired fresh control manifest used to count displaced base positions",
    )
    parser.add_argument(
        "--until",
        help="Include journal events only through this MT5 timestamp (YYYY.MM.DD HH:MM:SS)",
    )
    args = parser.parse_args()

    modes = sum(
        (
            args.attribution,
            args.failure_checkpoints,
            args.continuation_study,
            args.continuation_causal_shadow_study,
        )
    )
    if modes > 1:
        parser.error(
            "--attribution, --failure-checkpoints, --continuation-study, and "
            "--continuation-causal-shadow-study are mutually exclusive"
        )

    if args.continuation_causal_shadow_study:
        if len(args.chain_manifest) != 1 or args.journals or args.control_chain_manifest is None:
            parser.error(
                "--continuation-causal-shadow-study requires exactly one --chain-manifest, "
                "one --control-chain-manifest, and no journal arguments"
            )
        try:
            rows = continuation_causal_shadow_study_rows(
                args.chain_manifest[0], args.control_chain_manifest
            )
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 2
        fieldnames = list(rows[0]) if rows else []
        writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
        return 0

    if args.continuation_study:
        if len(args.chain_manifest) != 1 or args.journals:
            parser.error("--continuation-study requires exactly one --chain-manifest and no journal arguments")
        try:
            rows = continuation_study_rows(args.chain_manifest[0], args.control_chain_manifest)
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 2
        fieldnames = list(rows[0]) if rows else []
        writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
        return 0
    if args.control_chain_manifest is not None:
        parser.error("--control-chain-manifest is valid only with --continuation-study")

    try:
        chain_inputs = [read_chain_manifest(path) for path in args.chain_manifest]
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if args.failure_checkpoints:
        try:
            rows = [row for path in args.journals if path.exists() for row in failure_checkpoint_metrics(path, args.until)]
            rows.extend(
                row
                for name, chain_rows in chain_inputs
                for row in failure_checkpoint_metrics_from_rows(f"{name}::stitched", chain_rows, args.until)
            )
        except ValueError as exc:
            print(str(exc), file=sys.stderr)
            return 2
        fieldnames = [
            "journal", "setup", "scalp_positions", "checkpoints", "triggers",
            "full_losses", "triggered_full_losses", "trigger_to_full_loss_precision_pct",
            "full_loss_recall_pct", "profitable_exits", "false_profitable_triggers",
            "false_trigger_rate_pct", "average_eventual_r_triggered",
            "counterfactual_cash_saved_before_costs", "counterfactual_cash_saved_after_costs",
            "positive_savings_after_costs", "non_shadow_outcomes",
        ]
    elif args.attribution:
        rows = [row for path in args.journals if path.exists() for row in attribution_rows(path, args.until)]
        rows.extend(row for name, chain_rows in chain_inputs for row in attribution_from_rows(f"{name}::stitched", chain_rows, args.until))
        fieldnames = ["journal", "group", "value", "closed_deals", "net_profit", "gross_profit", "gross_loss", "profit_factor", "win_rate_pct"]
    else:
        rows = [summarize(path) for path in args.journals if path.exists()]
        rows.extend(summarize_rows(f"{name}::stitched", chain_rows) for name, chain_rows in chain_inputs)
        fieldnames = list(rows[0].keys()) if rows else []

    if not rows:
        if args.attribution or args.failure_checkpoints:
            writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
            writer.writeheader()
            return 0
        print("No readable trades.csv journal rows found.", file=sys.stderr)
        return 1

    writer = csv.DictWriter(sys.stdout, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
