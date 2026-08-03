#!/usr/bin/env python3
"""Run continuation-safe sequential FundingPips MT5 segments and stitch evidence."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from html import unescape
from pathlib import Path
from typing import Iterable, Sequence


ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "mt5/backtests/reports"
LAUNCHER = ROOT / "scripts/run-mt5-backtest.sh"
DEFAULT_PRESET = "GoldBot/prop-fundingpips-2step.set"
STATE_RELATIVE = Path("GoldBot/fundingpips-chain-state.csv")
DEFAULT_SEGMENTS = (
    ("2025.07.01", "2025.08.03"),
    ("2025.08.04", "2025.08.31"),
    ("2025.09.01", "2025.10.05"),
    ("2025.10.06", "2025.11.02"),
    ("2025.11.03", "2025.11.30"),
    # MT5's ToDate is an exclusive upper bound in the emitted journal. Use
    # 2026.01.01 so the final qualification day, 2025.12.31, is exercised.
    ("2025.12.01", "2026.01.01"),
)
H1_2025_SEGMENTS = (
    ("2025.01.01", "2025.02.02"),
    ("2025.02.03", "2025.03.02"),
    ("2025.03.03", "2025.04.06"),
    ("2025.04.07", "2025.05.04"),
    ("2025.05.05", "2025.06.01"),
    # Exclusive upper bound includes the final requested trading day, June 30.
    ("2025.06.02", "2025.07.01"),
)
H1_2024_SEGMENTS = (
    ("2024.01.01", "2024.02.04"),
    ("2024.02.05", "2024.03.03"),
    ("2024.03.04", "2024.04.07"),
    ("2024.04.08", "2024.05.05"),
    ("2024.05.06", "2024.06.02"),
    ("2024.06.03", "2024.07.01"),
)
H2_2024_SEGMENTS = (
    ("2024.07.01", "2024.08.04"),
    ("2024.08.05", "2024.09.01"),
    ("2024.09.02", "2024.10.06"),
    ("2024.10.07", "2024.11.03"),
    ("2024.11.04", "2024.12.01"),
    ("2024.12.02", "2025.01.01"),
)
H1_2026_SEGMENTS = (
    ("2026.01.01", "2026.02.01"),
    ("2026.02.02", "2026.03.01"),
    ("2026.03.02", "2026.04.05"),
    ("2026.04.06", "2026.05.03"),
    ("2026.05.04", "2026.05.31"),
    ("2026.06.01", "2026.07.01"),
)
WINDOW_SEGMENTS = {
    "h1-2024": H1_2024_SEGMENTS,
    "h2-2024": H2_2024_SEGMENTS,
    "h1-2025": H1_2025_SEGMENTS,
    "h2-2025": DEFAULT_SEGMENTS,
    "h1-2026": H1_2026_SEGMENTS,
}
REQUIRED_STATE_KEYS = {
    "schema_version",
    "valid",
    "flat",
    "original_challenge_balance",
    "ending_balance",
    "ending_equity",
    "next_start_balance",
    "equity_peak",
    "phase_target_completed",
    "segment_end_timestamp",
    "compound_peak_equity",
    "compound_month",
    "compound_month_start_equity",
    "compound_month_profit_lock",
    "monthly_loss_month",
    "monthly_loss_start_equity",
    "monthly_loss_halt",
    "completed_trade_month",
    "completed_trade_count",
    "streak_cooldown_end",
    "streak_consecutive_losses",
    "rolling_count",
    "rolling_index",
    "rolling_fail_streak",
    "rolling_pause_until",
    "rolling_lookback",
}
CAUSAL_SHADOW_STATE_KEYS = {
    "causal_shadow_enabled",
    "causal_shadow_state_version",
    "causal_shadow_state_valid",
    "causal_shadow_state_complete",
    "causal_shadow_active_probe_count",
    "causal_shadow_last_probe_id",
}
CAUSAL_SHADOW_ACTIVE_STATE_KEYS = {
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
    *{
        f"causal_shadow_rung_{rung}_{field}"
        for rung in (1, 2)
        for field in (
            "filled", "terminal", "fill_time", "barrier_time", "entry",
            "risk_distance", "lot", "risk_cash", "spread_r", "commission_r",
            "mfe_r", "mae_r", "gross_r", "net_r", "reason",
        )
    },
}


class ChainError(RuntimeError):
    """A fail-closed chain qualification error."""


@dataclass(frozen=True)
class Segment:
    start: date
    end: date

    @classmethod
    def parse(cls, start: str, end: str) -> "Segment":
        return cls(
            datetime.strptime(start, "%Y.%m.%d").date(),
            datetime.strptime(end, "%Y.%m.%d").date(),
        )

    def mt5_start(self) -> str:
        return self.start.strftime("%Y.%m.%d")

    def mt5_end(self) -> str:
        return self.end.strftime("%Y.%m.%d")


def default_segments() -> list[Segment]:
    return [Segment.parse(start, end) for start, end in DEFAULT_SEGMENTS]


def named_window_segments(window: str) -> list[Segment]:
    try:
        raw_segments = WINDOW_SEGMENTS[window]
    except KeyError as exc:
        raise ChainError(f"unsupported chain window: {window}") from exc
    return [Segment.parse(start, end) for start, end in raw_segments]


def validate_weekend_boundaries(segments: Sequence[Segment]) -> None:
    if not segments:
        raise ChainError("chain must contain at least one segment")
    for index, segment in enumerate(segments):
        if segment.start > segment.end:
            raise ChainError(f"segment {index + 1} starts after it ends")
        if index:
            previous = segments[index - 1]
            if segment.start != previous.end + timedelta(days=1):
                raise ChainError(f"segment {index + 1} is not contiguous")
            if previous.end.weekday() != 6 or segment.start.weekday() != 0:
                raise ChainError(
                    f"boundary {previous.end} -> {segment.start} is not Sunday-to-Monday"
                )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def preset_path(preset: str) -> Path:
    path = Path(preset)
    if path.is_absolute() or ".." in path.parts:
        raise ChainError(f"preset must be relative to mt5/Presets: {preset}")
    resolved = ROOT / "mt5/Presets" / path
    if not resolved.is_file():
        raise ChainError(f"preset missing: {resolved}")
    return resolved


def preset_inputs(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line_number, raw in enumerate(path.read_text(errors="strict").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        if "=" not in line:
            raise ChainError(f"malformed preset line {line_number}: {path}")
        key, value = line.split("=", 1)
        if key in values:
            raise ChainError(f"duplicate preset input {key}: {path}")
        values[key] = value
    return values


def decode_report(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")) or data.count(b"\x00") > 100:
        return data.decode("utf-16", errors="ignore")
    return data.decode("utf-8", errors="ignore")


def strip_tags(value: str) -> str:
    return unescape(re.sub(r"<[^>]+>", " ", value))


def normalized_inputs_block(path: Path, exclude_tester_chain: bool = False) -> str:
    text = strip_tags(decode_report(path))
    match = re.search(
        r"Inputs:\s*(.*?)(?:Company:|Results?\b|$)",
        text,
        flags=re.DOTALL | re.IGNORECASE,
    )
    if not match:
        raise ChainError(f"Inputs block missing: {path}")
    lines = [re.sub(r"\s+", "", line) for line in match.group(1).splitlines()]
    inputs = [line for line in lines if re.match(r"^Inp[A-Za-z0-9_]+=", line)]
    if exclude_tester_chain:
        allowed = {
            "InpTesterChainMode",
            "InpTesterChainStateFile",
            "InpTesterChainRequireState",
        }
        inputs = [line for line in inputs if line.split("=", 1)[0] not in allowed]
    if not inputs:
        raise ChainError(f"Inputs block contains no EA inputs: {path}")
    return "\n".join(inputs)


def inputs_hash(path: Path) -> str:
    return hashlib.sha256(normalized_inputs_block(path).encode()).hexdigest()


def strategy_inputs_hash(path: Path) -> str:
    """Hash strategy inputs while excluding exactly the three chain-only controls."""
    return hashlib.sha256(normalized_inputs_block(path, exclude_tester_chain=True).encode()).hexdigest()


def validate_report(path: Path, started_at: float, expected_inputs: dict[str, str]) -> str:
    if not path.exists():
        raise ChainError(f"report missing: {path}")
    if path.stat().st_mtime + 1.0 < started_at:
        raise ChainError(f"stale report: {path}")
    compact = re.sub(r"\s+", " ", strip_tags(decode_report(path)))
    if "1970.01.01" in compact or re.search(r"Period:\s*M0\b", compact):
        raise ChainError(f"malformed report period: {path}")
    if re.search(r"Initial Deposit:\s*0(?:\.0+)?\b", compact):
        raise ChainError(f"malformed report deposit: {path}")
    normalized = normalized_inputs_block(path)
    squashed = re.sub(r"\s+", "", normalized)
    for key, value in expected_inputs.items():
        if f"{key}={value}" not in squashed:
            raise ChainError(f"input mismatch in {path.name}: {key}={value}")
    return hashlib.sha256(normalized.encode()).hexdigest()


def parse_state(path: Path, started_at: float | None = None) -> dict[str, str]:
    if not path.exists():
        raise ChainError(f"state export missing: {path}")
    if started_at is not None and path.stat().st_mtime + 1.0 < started_at:
        raise ChainError(f"stale state export: {path}")
    state: dict[str, str] = {}
    with path.open(newline="", errors="strict") as handle:
        for row_number, row in enumerate(csv.reader(handle), start=1):
            if len(row) != 2 or not row[0]:
                raise ChainError(f"malformed state row {row_number}: {path}")
            if row[0] in state:
                raise ChainError(f"duplicate state key {row[0]}: {path}")
            state[row[0]] = row[1]
    missing = sorted(REQUIRED_STATE_KEYS - state.keys())
    if missing:
        raise ChainError(f"state missing keys: {', '.join(missing)}")
    if state["schema_version"] != "1":
        raise ChainError("unsupported state schema")
    if state["valid"].lower() != "true" or state["flat"].lower() != "true":
        raise ChainError("segment state is invalid/non-flat")
    for key in (
        "original_challenge_balance",
        "ending_balance",
        "ending_equity",
        "equity_peak",
    ):
        try:
            if float(state[key]) <= 0:
                raise ValueError
        except ValueError as exc:
            raise ChainError(f"invalid positive state value: {key}") from exc
    try:
        if int(state["segment_end_timestamp"]) <= 0:
            raise ValueError
    except ValueError as exc:
        raise ChainError("invalid segment_end_timestamp") from exc
    return state


def validate_original_challenge_balance(
    state: dict[str, str], initial_deposit: float
) -> None:
    carried = float(state["original_challenge_balance"])
    if abs(carried - initial_deposit) > 0.005:
        raise ChainError(
            f"original challenge balance anchor changed: {carried:.2f} vs {initial_deposit:.2f}"
        )


def validate_causal_shadow_state(state: dict[str, str], *, final_segment: bool) -> None:
    missing = sorted(CAUSAL_SHADOW_STATE_KEYS - state.keys())
    if missing:
        raise ChainError(f"causal shadow state missing keys: {', '.join(missing)}")
    if state["causal_shadow_enabled"].lower() != "true":
        raise ChainError("causal shadow state does not identify the enabled observer")
    if state["causal_shadow_state_version"] != "1":
        raise ChainError("unsupported causal shadow state version")
    if state["causal_shadow_state_valid"].lower() != "true" or state["causal_shadow_state_complete"].lower() != "true":
        raise ChainError("causal shadow state is invalid/incomplete")
    try:
        active_count = int(state["causal_shadow_active_probe_count"])
    except ValueError as exc:
        raise ChainError("invalid causal shadow active probe count") from exc
    if active_count not in {0, 1}:
        raise ChainError("causal shadow active probe count is outside 0..1")
    if active_count:
        missing_active = sorted(CAUSAL_SHADOW_ACTIVE_STATE_KEYS - state.keys())
        if missing_active:
            raise ChainError(
                f"active causal shadow state missing keys: {', '.join(missing_active)}"
            )
    if final_segment and active_count:
        raise ChainError("causal shadow final segment ended with an incomplete virtual probe")


def expected_chain_inputs(
    segment_index: int, extra_inputs: dict[str, str] | None = None
) -> dict[str, str]:
    if segment_index < 1:
        raise ChainError("segment index must be positive")
    values = {
        "InpTesterChainMode": "true",
        "InpTesterChainStateFile": STATE_RELATIVE.as_posix(),
        "InpTesterChainRequireState": "true" if segment_index > 1 else "false",
    }
    values.update(extra_inputs or {})
    return values


def mt5_root() -> Path:
    prefix = Path(
        os.environ.get(
            "MT5_PREFIX",
            str(Path.home() / "Library/Application Support/net.metaquotes.wine.metatrader5"),
        )
    )
    return prefix / "drive_c/Program Files/MetaTrader 5"


def common_state_path(root: Path) -> Path:
    override = os.environ.get("MT5_COMMON_FILES")
    if override:
        return Path(override) / STATE_RELATIVE
    drive_c = root.parents[1]
    candidates = sorted(
        (drive_c / "users").glob(
            "*/AppData/Roaming/MetaQuotes/Terminal/Common/Files"
        )
    )
    candidates = [path for path in candidates if path.is_dir()]
    preferred = [path for path in candidates if path.parents[5].name == Path.home().name]
    if len(preferred) == 1:
        candidates = preferred
    if len(candidates) != 1:
        raise ChainError(
            f"expected one MT5 Common/Files directory, found {len(candidates)}; set MT5_COMMON_FILES"
        )
    return candidates[0] / STATE_RELATIVE


def state_sandboxes(root: Path) -> list[Path]:
    bases = sorted(root.glob("Tester/Agent-*/MQL5/Files"))
    bases.append(root / "MQL5/Files")
    return [base / STATE_RELATIVE for base in bases]


def clear_state_sandboxes(root: Path) -> None:
    for path in state_sandboxes(root):
        path.unlink(missing_ok=True)
    common = common_state_path(root)
    common.parent.mkdir(parents=True, exist_ok=True)
    common.unlink(missing_ok=True)


def seed_state_sandboxes(root: Path, source: Path) -> None:
    destination = common_state_path(root)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def newest_exported_state(root: Path, started_at: float) -> Path:
    path = common_state_path(root)
    if not path.exists() or path.stat().st_mtime + 1.0 < started_at:
        raise ChainError("no fresh tester chain state found in MT5 Common/Files")
    return path


DEAL_FIELD_RE = re.compile(r"([A-Za-z][A-Za-z0-9_]*)=([^\s,]+)")


def journal_rows(path: Path) -> list[tuple[str, str]]:
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
            if not row or row[0].strip().lower() == "time":
                continue
            message = " ".join(cell.strip() for cell in row[1:] if cell.strip())
            if message:
                rows.append((row[0].strip(), message))
    return rows


def stitched_metrics(journals: Sequence[Path], initial_balance: float) -> dict[str, object]:
    deals: dict[tuple[str, str, str], float] = {}
    for journal in journals:
        for timestamp, message in journal_rows(journal):
            if "deal event" not in message.lower():
                continue
            fields = {match.group(1): match.group(2) for match in DEAL_FIELD_RE.finditer(message)}
            if fields.get("entry") not in {"1", "2", "3"}:
                continue
            if not fields.get("position") or not fields.get("deal"):
                raise ChainError(f"closing deal missing IDs in {journal}")
            key = (timestamp, fields["position"], fields["deal"])
            profit = float(fields.get("profit", "0"))
            if key in deals and abs(deals[key] - profit) > 0.005:
                raise ChainError(f"conflicting duplicate deal {key}")
            deals[key] = profit

    ordered = sorted(deals.items(), key=lambda item: (item[0][0], int(item[0][2])))
    balance = initial_balance
    peak = initial_balance
    max_drawdown = 0.0
    gross_profit = 0.0
    gross_loss = 0.0
    series: list[dict[str, object]] = []
    for (timestamp, position_id, deal_id), profit in ordered:
        balance += profit
        peak = max(peak, balance)
        drawdown = ((peak - balance) / peak * 100.0) if peak > 0 else 0.0
        max_drawdown = max(max_drawdown, drawdown)
        gross_profit += max(0.0, profit)
        gross_loss += min(0.0, profit)
        series.append(
            {
                "time": timestamp,
                "position_id": position_id,
                "deal_id": deal_id,
                "profit": round(profit, 2),
                "balance": round(balance, 2),
                "drawdown_pct": round(drawdown, 6),
            }
        )
    pf = gross_profit / abs(gross_loss) if gross_loss < 0 else None
    return {
        "initial_balance": round(initial_balance, 2),
        "ending_balance": round(balance, 2),
        "net_profit": round(balance - initial_balance, 2),
        "gross_profit": round(gross_profit, 2),
        "gross_loss": round(gross_loss, 2),
        "profit_factor": round(pf, 6) if pf is not None else None,
        "stitched_equity_drawdown_pct": round(max_drawdown, 6),
        "curve_basis": "deduplicated closing-deal net PnL",
        "deal_count": len(ordered),
        "series": series,
    }


def _number(value: str) -> float:
    cleaned = value.replace("\xa0", "").replace(" ", "").strip()
    match = re.search(r"-?[\d.]+", cleaned)
    return float(match.group(0)) if match else 0.0


def _report_cells(path: Path) -> list[str]:
    return [
        " ".join(strip_tags(match.group(1)).split())
        for match in re.finditer(r"<td[^>]*>(.*?)</td>", decode_report(path), re.I | re.S)
    ]


def _metric_text(path: Path, label: str) -> str:
    cells = _report_cells(path)
    for index, value in enumerate(cells[:-1]):
        if value == label:
            return cells[index + 1]
    raise ChainError(f"report metric missing {label}: {path}")


def _metric_value(path: Path, label: str) -> float:
    return _number(_metric_text(path, label))


def _metric_percent(path: Path, label: str) -> float:
    match = re.search(r"\(([-\d.]+)%\)|([-\d.]+)%", _metric_text(path, label))
    if not match:
        raise ChainError(f"report metric percent missing {label}: {path}")
    return float(match.group(1) or match.group(2))


def report_balance_points(path: Path) -> list[tuple[str, int, float]]:
    html = decode_report(path)
    header = re.search(r"<th[^>]*>.*?<b>\s*Deals\s*</b>.*?</th>", html, re.I | re.S)
    if not header:
        raise ChainError(f"Deals table missing: {path}")
    section = html[header.end() :]
    next_header = re.search(r"<th[^>]*>.*?<b>", section, re.I | re.S)
    if next_header:
        section = section[: next_header.start()]
    points: list[tuple[str, int, float]] = []
    for row in re.finditer(r"<tr[^>]*>(.*?)</tr>", section, re.I | re.S):
        cells = [" ".join(strip_tags(cell.group(1)).split()) for cell in re.finditer(r"<td[^>]*>(.*?)</td>", row.group(1), re.I | re.S)]
        if len(cells) < 12 or not re.match(r"\d{4}\.\d{2}\.\d{2}", cells[0]):
            continue
        deal_id = int(_number(cells[1]))
        balance = _number(cells[11])
        if balance > 0:
            points.append((cells[0], deal_id, balance))
    if not points:
        raise ChainError(f"no balance points in Deals table: {path}")
    return points


def stitched_report_metrics(
    reports: Sequence[Path],
    initial_balance: float,
    expected_ending_balance: float,
    balance_offsets: Sequence[float] | None = None,
) -> dict[str, object]:
    if balance_offsets is None:
        balance_offsets = [0.0] * len(reports)
    if len(balance_offsets) != len(reports):
        raise ChainError("report/offset count mismatch")
    points_by_report: list[list[tuple[str, int, float]]] = []
    equity_excursions: list[tuple[float, float, float]] = []
    gross_profit = 0.0
    gross_loss = 0.0
    total_trades = 0
    total_deals = 0
    for report, offset in zip(reports, balance_offsets):
        points_by_report.append(
            [(timestamp, deal_id, balance + offset) for timestamp, deal_id, balance in report_balance_points(report)]
        )
        gross_profit += _metric_value(report, "Gross Profit:")
        gross_loss += _metric_value(report, "Gross Loss:")
        total_trades += int(_metric_value(report, "Total Trades:"))
        total_deals += int(_metric_value(report, "Total Deals:"))
        equity_dd_dollars = _metric_value(report, "Equity Drawdown Maximal:")
        equity_dd_pct = _metric_percent(report, "Equity Drawdown Maximal:")
        if equity_dd_dollars < 0 or equity_dd_pct < 0:
            raise ChainError(f"invalid equity drawdown metric: {report}")
        local_peak = equity_dd_dollars / (equity_dd_pct / 100.0) if equity_dd_pct > 0 else 0.0
        local_trough = local_peak - equity_dd_dollars if local_peak > 0 else 0.0
        equity_excursions.append((local_peak + offset, local_trough + offset, equity_dd_pct))

    peak = initial_balance
    previous = initial_balance
    max_drawdown = 0.0
    series: list[dict[str, object]] = []
    balance_point_count = 0
    for report_points, (local_peak, local_trough, local_dd_pct) in zip(points_by_report, equity_excursions):
        prior_chain_peak = peak
        # MT5 gives each segment's maximal floating-equity drawdown in dollars
        # and percent.  Reconstruct its absolute peak/trough and compare that
        # trough with the chain's prior peak; this is portfolio stitching, not
        # the invalid shortcut of taking the largest segment percentage.
        if local_peak > 0:
            stitched_peak = max(prior_chain_peak, local_peak)
            excursion_dd = ((stitched_peak - local_trough) / stitched_peak * 100.0) if stitched_peak > 0 else 0.0
            max_drawdown = max(max_drawdown, excursion_dd)
        for timestamp, deal_id, balance in sorted(report_points, key=lambda point: (point[0], point[1])):
            peak = max(peak, balance)
            drawdown = ((peak - balance) / peak * 100.0) if peak > 0 else 0.0
            max_drawdown = max(max_drawdown, drawdown)
            series.append(
                {
                    "time": timestamp,
                    "deal_id": deal_id,
                    "profit": round(balance - previous, 2),
                    "balance": round(balance, 2),
                    "drawdown_pct": round(drawdown, 6),
                }
            )
            previous = balance
            balance_point_count += 1
        peak = max(peak, local_peak)
    if abs(previous - expected_ending_balance) > 0.10:
        raise ChainError(
            f"report/state ending balance mismatch: {previous:.2f} vs {expected_ending_balance:.2f}"
        )
    pf = gross_profit / abs(gross_loss) if gross_loss < 0 else None
    return {
        "initial_balance": round(initial_balance, 2),
        "ending_balance": round(expected_ending_balance, 2),
        "net_profit": round(expected_ending_balance - initial_balance, 2),
        "gross_profit": round(gross_profit, 2),
        "gross_loss": round(gross_loss, 2),
        "profit_factor": round(pf, 6) if pf is not None else None,
        "stitched_equity_drawdown_pct": round(max_drawdown, 6),
        "curve_basis": "chronological MT5 Deals balances plus absolute floating-equity peak/trough excursions",
        # MT5 reports deposits as balance points, but excludes them from Total
        # Deals. Keep the three counters explicit so downstream summaries never
        # mislabel six segment deposits as trades.
        "total_trades": total_trades,
        "total_deals": total_deals,
        "deal_count": total_deals,
        "balance_point_count": balance_point_count,
        "series": series,
    }


def source_hashes() -> dict[str, str]:
    paths = [ROOT / "mt5/Experts/GoldBot/GoldBot.mq5"]
    paths.extend(sorted((ROOT / "mt5/Include/GoldBot").glob("*.mqh")))
    return {str(path.relative_to(ROOT)): sha256_file(path) for path in paths}


def clean_artifacts(report_name: str) -> None:
    for suffix in (".htm", ".xml", ".trades.csv"):
        (REPORT_DIR / f"{report_name}{suffix}").unlink(missing_ok=True)


def run_chain(
    segments: Sequence[Segment],
    chain_name: str,
    initial_deposit: float,
    extra_overrides: Sequence[str] = (),
    dry_run: bool = False,
    preset: str = DEFAULT_PRESET,
) -> Path:
    validate_weekend_boundaries(segments)
    selected_preset = preset_path(preset)
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    root = mt5_root()
    ex5 = root / "MQL5/Experts/GoldBot/GoldBot.ex5"
    if not ex5.exists():
        raise ChainError(f"compiled GoldBot missing: {ex5}")
    newest_source = max(path.stat().st_mtime for path in [ROOT / "mt5/Experts/GoldBot/GoldBot.mq5", *sorted((ROOT / "mt5/Include/GoldBot").glob("*.mqh"))])
    if ex5.stat().st_mtime < newest_source:
        raise ChainError("GoldBot.ex5 is stale relative to source")

    extra_expected_inputs: dict[str, str] = {}
    for override in extra_overrides:
        if "=" not in override:
            raise ChainError(f"invalid override: {override}")
        key, value = override.split("=", 1)
        if key.startswith("InpTesterChain"):
            raise ChainError(f"tester-chain control cannot be overridden: {key}")
        extra_expected_inputs[key] = value
    effective_inputs = preset_inputs(selected_preset)
    effective_inputs.update(extra_expected_inputs)
    causal_shadow_enabled = (
        effective_inputs.get("InpEnableContinuationCausalShadow", "false").lower()
        == "true"
    )

    if dry_run:
        for index, segment in enumerate(segments, start=1):
            print(f"{index}: [{segment.mt5_start()}, {segment.mt5_end()})")
        return REPORT_DIR / f"{chain_name}.manifest.json"

    clear_state_sandboxes(root)
    canonical_state = REPORT_DIR / f"{chain_name}.state.csv"
    canonical_state.unlink(missing_ok=True)
    current_deposit = initial_deposit
    manifest_segments: list[dict[str, object]] = []
    journals: list[Path] = []
    reports: list[Path] = []
    segment_input_hashes: list[str] = []
    common_strategy_inputs_hash: str | None = None
    logical_balance = initial_deposit
    report_balance_offsets: list[float] = []

    for index, segment in enumerate(segments, start=1):
        expected_inputs = expected_chain_inputs(index, extra_expected_inputs)
        override_lines = [f"{key}={value}" for key, value in expected_inputs.items()]
        if index > 1:
            seed_state_sandboxes(root, canonical_state)
        report_name = f"{chain_name}-s{index:02d}"
        clean_artifacts(report_name)
        started_at = time.time()
        env = os.environ.copy()
        env.update(
            {
                "MT5_DEPOSIT": f"{current_deposit:.2f}",
                "MT5_FROM": segment.mt5_start(),
                "MT5_TO": segment.mt5_end(),
                "MT5_REPORT": report_name,
                "MT5_INPUT_OVERRIDES": "\n".join(override_lines),
                "MT5_EXPERT": r"GoldBot\GoldBot.ex5",
                "MT5_PRESET": preset,
                "MT5_PERIOD": "M15",
                "MT5_SYMBOL": "XAUUSD",
                "WINEDLLOVERRIDES": "mmdevapi=d",
                "WINEDEBUG": "-all",
            }
        )
        completed = subprocess.run(["bash", str(LAUNCHER)], cwd=ROOT, env=env, check=False)
        if completed.returncode != 0:
            raise ChainError(f"MT5 segment {index} failed with status {completed.returncode}")

        report = REPORT_DIR / f"{report_name}.htm"
        journal = REPORT_DIR / f"{report_name}.trades.csv"
        segment_inputs_hash = validate_report(report, started_at, expected_inputs)
        segment_strategy_inputs_hash = strategy_inputs_hash(report)
        segment_input_hashes.append(segment_inputs_hash)
        if common_strategy_inputs_hash is None:
            common_strategy_inputs_hash = segment_strategy_inputs_hash
        elif segment_strategy_inputs_hash != common_strategy_inputs_hash:
            raise ChainError(f"Strategy Inputs block hash changed at segment {index}")
        if not journal.exists() or journal.stat().st_mtime + 1.0 < started_at:
            raise ChainError(f"fresh journal missing at segment {index}")

        exported_state = newest_exported_state(root, started_at)
        state = parse_state(exported_state, started_at)
        if causal_shadow_enabled:
            validate_causal_shadow_state(state, final_segment=index == len(segments))
        validate_original_challenge_balance(state, initial_deposit)
        report_initial_deposit = _metric_value(report, "Initial Deposit:")
        report_net_profit = _metric_value(report, "Total Net Profit:")
        if abs(report_initial_deposit - current_deposit) > 0.005:
            raise ChainError(
                f"report start/deposit carry mismatch: {report_initial_deposit:.2f} vs {current_deposit:.2f}"
            )
        ending_balance = float(state["ending_balance"])
        report_implied_ending = report_initial_deposit + report_net_profit
        if abs(ending_balance - report_implied_ending) > 0.02:
            raise ChainError(
                f"state/report ending balance mismatch: {ending_balance:.2f} vs {report_implied_ending:.2f}"
            )
        next_start_balance = float(state["next_start_balance"])
        if abs(next_start_balance - float(int(ending_balance))) > 0.005:
            raise ChainError("state next-start balance does not match MT5 whole-dollar deposit contract")
        logical_start_balance = logical_balance
        logical_end_balance = logical_start_balance + report_net_profit
        report_balance_offsets.append(logical_start_balance - report_initial_deposit)
        shutil.copy2(exported_state, canonical_state)
        manifest_segments.append(
            {
                "index": index,
                "start": segment.mt5_start(),
                "end": segment.mt5_end(),
                "start_balance": round(current_deposit, 2),
                "end_balance": round(ending_balance, 2),
                "logical_start_balance": round(logical_start_balance, 2),
                "logical_end_balance": round(logical_end_balance, 2),
                "next_start_balance": round(next_start_balance, 2),
                "deposit_carry_adjustment": round(next_start_balance - ending_balance, 2),
                "report": report.name,
                "journal": journal.name,
                "report_sha256": sha256_file(report),
                "journal_sha256": sha256_file(journal),
                "inputs_sha256": segment_inputs_hash,
                "strategy_inputs_sha256": segment_strategy_inputs_hash,
                "report_fresh": True,
                "flat": True,
                "valid": True,
                "carried_state": state,
            }
        )
        journals.append(journal)
        reports.append(report)
        current_deposit = next_start_balance
        logical_balance = logical_end_balance

    stitched = stitched_report_metrics(
        reports, initial_deposit, logical_balance, report_balance_offsets
    )
    manifest = {
        "schema_version": 1,
        "chain_name": chain_name,
        "created_at_utc": datetime.utcnow().isoformat(timespec="seconds") + "Z",
        "preset": preset,
        "preset_sha256": sha256_file(selected_preset),
        "state_file": STATE_RELATIVE.as_posix(),
        "source_hashes": source_hashes(),
        "ex5_path": str(ex5),
        "ex5_sha256": sha256_file(ex5),
        "inputs_sha256_by_segment": segment_input_hashes,
        "strategy_inputs_sha256": common_strategy_inputs_hash,
        "segments": manifest_segments,
        "stitched": stitched,
    }
    manifest_path = REPORT_DIR / f"{chain_name}.manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"Chain manifest: {manifest_path}")
    return manifest_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chain-name", default="GoldBot-fundingpips-p1-h2-2025-chain")
    parser.add_argument("--window", choices=sorted(WINDOW_SEGMENTS), default="h2-2025")
    parser.add_argument("--deposit", type=float, default=50_000.0)
    parser.add_argument(
        "--preset",
        default=DEFAULT_PRESET,
        help="preset path relative to mt5/Presets",
    )
    parser.add_argument("--set", dest="overrides", action="append", default=[], help="extra KEY=VALUE override")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        run_chain(
            named_window_segments(args.window),
            args.chain_name,
            args.deposit,
            args.overrides,
            args.dry_run,
            args.preset,
        )
    except ChainError as exc:
        print(f"FundingPips chain FAILED: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
