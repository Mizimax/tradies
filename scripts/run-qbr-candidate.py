#!/usr/bin/env python3
"""Run and validate one QuantumBehavioralReplica MT5 candidate."""

from __future__ import annotations

import argparse
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field


ROOT = Path(__file__).resolve().parents[1]
PRESET_DIR = ROOT / "mt5" / "Presets" / "QBR"
REPORT_DIR = ROOT / "mt5" / "backtests" / "reports"
BUILD_TAG = "QBR-1.13-aggressive"
BASE_PRESET = "aggressive.set"


@dataclass(frozen=True)
class Candidate:
    overrides: dict[str, str] = field(default_factory=dict)


def candidate(run_id: str, log_name: str, **overrides: object) -> Candidate:
    values = {
        "InpRunId": run_id,
        "InpLogFolder": log_name,
        **{key: str(value).lower() if isinstance(value, bool) else str(value) for key, value in overrides.items()},
    }
    return Candidate(values)


QUALITY_HOURS = "02,03,06,10,13,16,17,18,19,20"
QUALITY_HOURS_V2 = "02,10,13,16,17,18,19,20"

COMMON_MINLOT = {
    "InpAllowMinLotWithNativeRiskCap": True,
    "InpPostExitCooldownBars": 1,
}
STOP60 = {**COMMON_MINLOT, "InpMinLotAllowedHours": QUALITY_HOURS,
          "InpBasketHardStopPct": 0.60, "InpMaxLossTargetRatio": 2.0}
STOP45 = {**COMMON_MINLOT, "InpMinLotAllowedHours": QUALITY_HOURS,
          "InpBasketHardStopPct": 0.45, "InpMaxLossTargetRatio": 1.5}
LOCK40 = {"InpProfitLockFloorFraction": 0.40}
QSYNC22 = {"InpLongThreshold": 0.22, "InpShortThreshold": -0.22}
CONF64 = {"InpMinPatternConfidence": 64}
M5_BASE = {"InpEnableM5ScalpLayer": True}
SCALED_SAFETY = {
    "InpMaxDailyLossPct": 4.0,
    "InpMaxWeeklyLossPct": 8.0,
    "InpMaxEquityDrawdownPct": 25.0,
    "InpMaxFloatingLossPct": 2.5,
    "InpMaxConsecutiveLosses": 3,
}

CANDIDATES = {
    "v113-control": candidate("v113-control", "QBR_Logs_v113_control"),
    "v113-minlot-cap": candidate("v113-minlot-cap", "QBR_Logs_v113_minlot_cap", **COMMON_MINLOT),
    "v113-minlot-quality-hours": candidate(
        "v113-minlot-quality-hours",
        "QBR_Logs_v113_minlot_quality_hours",
        **COMMON_MINLOT,
        InpMinLotAllowedHours=QUALITY_HOURS,
    ),
    "v113-quality-hours2": candidate(
        "v113-quality-hours2",
        "QBR_Logs_v113_quality_hours2",
        **COMMON_MINLOT,
        InpMinLotAllowedHours=QUALITY_HOURS_V2,
    ),
    "v113-quality-hours3": candidate(
        "v113-quality-hours3",
        "QBR_Logs_v113_quality_hours3",
        **COMMON_MINLOT,
        InpMinLotAllowedHours=QUALITY_HOURS_V2,
        InpEnableBreakoutRetest=False,
    ),
    "v113-stop60": candidate("v113-stop60", "QBR_Logs_v113_stop60", **STOP60),
    "v113-stop45": candidate("v113-stop45", "QBR_Logs_v113_stop45", **STOP45),
    "v113-lock40": candidate("v113-lock40", "QBR_Logs_v113_lock40", **LOCK40),
    "v113-qsync22": candidate("v113-qsync22", "QBR_Logs_v113_qsync22", **QSYNC22),
    "v113-conf64": candidate("v113-conf64", "QBR_Logs_v113_conf64", **CONF64),
    "v113-m5-15-30": candidate(
        "v113-m5-15-30", "QBR_Logs_v113_m5_15_30", **M5_BASE,
        InpM5TargetPct=0.15, InpM5HardStopPct=0.30,
    ),
    "v113-m5-20-40": candidate(
        "v113-m5-20-40", "QBR_Logs_v113_m5_20_40", **M5_BASE,
        InpM5TargetPct=0.20, InpM5HardStopPct=0.40,
    ),
    "v113-scale100": candidate(
        "v113-scale100", "QBR_Logs_v113_scale100", **{**SCALED_SAFETY,
        "InpRiskPerBasketPct": 1.0, "InpBasketTargetValue": 0.50, "InpBasketHardStopPct": 1.0,
        "InpM5TargetPct": 0.50, "InpM5HardStopPct": 1.0, "InpMaxLossTargetRatio": 2.0},
    ),
    "v113-scale150": candidate(
        "v113-scale150", "QBR_Logs_v113_scale150", **{**SCALED_SAFETY,
        "InpRiskPerBasketPct": 1.5, "InpBasketTargetValue": 0.75, "InpBasketHardStopPct": 1.5,
        "InpM5TargetPct": 0.75, "InpM5HardStopPct": 1.5, "InpMaxLossTargetRatio": 2.0},
    ),
    "v113-scale200": candidate(
        "v113-scale200", "QBR_Logs_v113_scale200", **{**SCALED_SAFETY,
        "InpRiskPerBasketPct": 2.0, "InpBasketTargetValue": 1.0, "InpBasketHardStopPct": 2.0,
        "InpM5TargetPct": 1.0, "InpM5HardStopPct": 2.0, "InpMaxLossTargetRatio": 2.0},
    ),
    "v113-scale-agg": candidate(
        "v113-scale-agg", "QBR_Logs_v113_scale_agg", **{
            "InpMaxDailyLossPct": 12.0,
            "InpMaxWeeklyLossPct": 20.0,
            "InpMaxEquityDrawdownPct": 25.0,
            "InpMaxFloatingLossPct": 7.5,
            "InpMaxConsecutiveLosses": 3,
            "InpRiskPerBasketPct": 6.0, "InpBasketTargetValue": 2.40, "InpBasketHardStopPct": 6.0,
            "InpM5TargetPct": 2.40, "InpM5HardStopPct": 6.0, "InpMaxLossTargetRatio": 2.0,
        },
    ),
}


def preset_values(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith(";") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def report_text(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")) or data.count(b"\x00") > 100:
        source = data.decode("utf-16", errors="ignore")
    else:
        source = data.decode("utf-8", errors="ignore")
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", source)))


def validate_report(
    path: Path,
    build_tag: str,
    minimum_quality: float,
    expected_inputs: dict[str, str] | None = None,
) -> float:
    text = report_text(path)
    if "Expert: QuantumBehavioralReplica" not in text:
        raise RuntimeError("report is not QuantumBehavioralReplica")
    if f"InpBuildTag={build_tag}" not in text:
        raise RuntimeError(f"report does not contain build tag {build_tag}")
    for key, value in (expected_inputs or {}).items():
        if f"{key}={value}" not in text:
            raise RuntimeError(f"report does not contain expected input {key}={value}")
    quality_match = re.search(r"History Quality:\s*([0-9.]+)% real ticks", text)
    if not quality_match:
        raise RuntimeError("report has no real-tick history-quality marker")
    quality = float(quality_match.group(1))
    if quality < minimum_quality:
        raise RuntimeError(
            f"real-tick history quality {quality:.2f}% is below required {minimum_quality:.2f}%"
        )
    return quality


def copy_logs(mt5_root: Path, folder: str, destination: Path) -> None:
    matches = sorted(
        mt5_root.glob(f"Tester/Agent-*/MQL5/Files/{folder}"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not matches:
        raise RuntimeError(f"fresh QBR log folder not found: {folder}")
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(matches[0], destination)


def clear_logs(mt5_root: Path, folder: str) -> None:
    for path in mt5_root.glob(f"Tester/Agent-*/MQL5/Files/{folder}"):
        shutil.rmtree(path)
    common = mt5_root / "MQL5" / "Files" / folder
    if common.exists():
        shutil.rmtree(common)


def process_commands() -> list[str]:
    result = subprocess.run(
        ["ps", "-axww", "-o", "command="], capture_output=True, text=True, check=False
    )
    return [line.strip() for line in result.stdout.splitlines()]


def configured_terminal_running(config_name: str) -> bool:
    for command in process_commands():
        lowered = command.lower()
        if "terminal64.exe" in lowered and config_name.lower() in lowered:
            return True
        # macOS ps may truncate metatester64.exe to metateste.
        if "metateste" in lowered:
            return True
    return False


def evidence_summary(candidate_name: str, symbol: str, from_date: str, to_date: str) -> dict[str, object]:
    pattern = (
        f"QBR-{candidate_name}-{symbol}-M15-{from_date}-{to_date}*"
        ".qbr-analysis/analysis_summary.json"
    )
    matches = sorted(REPORT_DIR.glob(pattern), key=lambda path: path.stat().st_mtime, reverse=True)
    if not matches:
        raise RuntimeError(f"missing prerequisite evidence for {candidate_name}: {pattern}")
    summary = json.loads(matches[0].read_text())
    report = summary.get("report_metrics", {})
    quality = summary.get("data_quality", {})
    reconciliation = quality.get("report_reconciliation", {}) if isinstance(quality, dict) else {}
    required = {
        "expert": "QuantumBehavioralReplica",
        "build_tag": BUILD_TAG,
        "run_id": candidate_name,
        "initial_deposit": 1000.0,
        "leverage": 100,
    }
    failures: list[str] = []
    if not isinstance(report, dict):
        failures.append("missing report_metrics")
    else:
        for key, expected in required.items():
            if report.get(key) != expected:
                failures.append(f"{key}={report.get(key)!r}, expected {expected!r}")
        if float(report.get("history_quality_pct", 0.0)) < 99.0:
            failures.append("history quality below 99% real ticks")
    if not isinstance(reconciliation, dict) or reconciliation.get("passed") is not True:
        failures.append("report/deal/basket reconciliation did not pass")
    if failures:
        raise RuntimeError(
            f"invalid prerequisite evidence for {candidate_name}: " + "; ".join(failures)
        )
    return summary


def discovery_score(summary: dict[str, object]) -> tuple[bool, bool, bool, float, float]:
    report = summary.get("report_metrics", {})
    if not isinstance(report, dict):
        raise RuntimeError("prerequisite analysis has no report_metrics")
    deposit = float(report.get("initial_deposit", 0.0))
    net_return = 100.0 * float(report.get("net_profit", 0.0)) / deposit if deposit > 0 else -1e9
    win_rate = float(report.get("win_rate_pct", 0.0))
    profit_factor = float(report.get("profit_factor", 0.0))
    drawdown = float(report.get("equity_drawdown_pct", 100.0))
    return (win_rate >= 70.0, profit_factor >= 1.30, drawdown <= 10.0, net_return, profit_factor)


def best_loss_candidate(symbol: str, from_date: str, to_date: str) -> str:
    names = ("v113-stop60", "v113-stop45")
    summaries = {name: evidence_summary(name, symbol, from_date, to_date) for name in names}
    return max(names, key=lambda name: discovery_score(summaries[name]))


def calendar_month_count(from_date: str, to_date: str) -> int:
    start_year, start_month, _ = map(int, from_date.split("."))
    end_year, end_month, _ = map(int, to_date.split("."))
    return (end_year - start_year) * 12 + end_month - start_month + 1


def resolved_candidate(
    name: str, symbol: str, from_date: str, to_date: str, scale_base: str | None = None
) -> tuple[Candidate, list[str]]:
    own = CANDIDATES[name].overrides
    lineage: list[str] = []
    base: dict[str, str] = {}
    if name in {"v113-lock40", "v113-qsync22", "v113-conf64", "v113-m5-15-30", "v113-m5-20-40"}:
        loss_name = best_loss_candidate(symbol, from_date, to_date)
        base.update(CANDIDATES[loss_name].overrides)
        lineage.append(loss_name)
        if name in {"v113-qsync22", "v113-conf64", "v113-m5-15-30", "v113-m5-20-40"}:
            evidence_summary("v113-lock40", symbol, from_date, to_date)
            base.update(LOCK40)
            lineage.append("v113-lock40")
        if name in {"v113-conf64", "v113-m5-15-30", "v113-m5-20-40"}:
            evidence_summary("v113-qsync22", symbol, from_date, to_date)
            base.update(QSYNC22)
            lineage.append("v113-qsync22")
        if name in {"v113-m5-15-30", "v113-m5-20-40"}:
            base.update(CONF64)
            lineage.append("v113-conf64")
            conf = evidence_summary("v113-conf64", symbol, from_date, to_date)
            report = conf.get("report_metrics", {})
            trades = int(report.get("total_trades", 0)) if isinstance(report, dict) else 0
            monthly_frequency = trades / calendar_month_count(from_date, to_date)
            if monthly_frequency >= 60.0:
                raise RuntimeError(
                    f"M5 layer is forbidden: v113-conf64 already has {monthly_frequency:.2f} trades/month"
                )
    elif name.startswith("v113-scale"):
        if scale_base is not None:
            if scale_base not in CANDIDATES or scale_base.startswith("v113-scale"):
                raise RuntimeError(f"invalid --scale-base: {scale_base}")
            evidence_summary(scale_base, symbol, from_date, to_date)  # still requires real, reconciled evidence
            base_name = scale_base
        else:
            eligible: list[tuple[str, dict[str, object]]] = []
            for candidate_name in CANDIDATES:
                if candidate_name.startswith("v113-scale"):
                    continue
                try:
                    summary = evidence_summary(candidate_name, symbol, from_date, to_date)
                except RuntimeError:
                    continue
                acceptance = summary.get("acceptance", {})
                if isinstance(acceptance, dict) and acceptance.get("safety_gate_passed") is True:
                    eligible.append((candidate_name, summary))
            if not eligible:
                raise RuntimeError("scaling is forbidden: no base-risk candidate passed the discovery edge gate")
            base_name, _ = max(eligible, key=lambda item: discovery_score(item[1]))
        resolved_base, base_lineage = resolved_candidate(base_name, symbol, from_date, to_date, scale_base)
        base.update(resolved_base.overrides)
        lineage.extend([*base_lineage, base_name])
    base.update(own)
    # The selected candidate always owns its audit identity even after inheriting a base.
    base["InpRunId"] = own["InpRunId"]
    base["InpLogFolder"] = own["InpLogFolder"]
    return Candidate(base), lineage


def wait_for_report(path: Path, config_name: str, timeout_seconds: int) -> None:
    deadline = time.monotonic() + timeout_seconds
    stable_since: float | None = None
    last_signature: tuple[int, int] | None = None
    while time.monotonic() < deadline:
        if path.exists():
            stat = path.stat()
            signature = (stat.st_size, stat.st_mtime_ns)
            if signature == last_signature:
                stable_since = stable_since or time.monotonic()
            else:
                last_signature = signature
                stable_since = None
            if (
                stable_since is not None
                and time.monotonic() - stable_since >= 3.0
                and not configured_terminal_running(config_name)
            ):
                return
        time.sleep(1)
    raise RuntimeError(f"timed out waiting for stable MT5 report: {path}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("candidate", choices=sorted(CANDIDATES))
    parser.add_argument("--from-date", default="2026.01.01")
    parser.add_argument("--to-date", default="2026.06.30")
    parser.add_argument("--symbol", default="XAUUSD")
    parser.add_argument("--deposit", type=float, default=1000.0)
    parser.add_argument("--leverage", type=int, default=100)
    parser.add_argument("--report-suffix", default="")
    parser.add_argument("--min-real-tick-quality", type=float, default=99.0)
    parser.add_argument("--timeout-seconds", type=int, default=7200)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--scale-base", default=None)
    args = parser.parse_args()

    if args.deposit != 1000.0 or args.leverage != 100:
        raise RuntimeError("QBR v1.13 research contract requires deposit=1000 and leverage=100")
    if args.min_real_tick_quality < 99.0:
        raise RuntimeError("QBR v1.13 prerequisite quality cannot be relaxed below 99% real ticks")

    spec, lineage = resolved_candidate(args.candidate, args.symbol, args.from_date, args.to_date, args.scale_base)
    preset_name = BASE_PRESET
    preset_path = PRESET_DIR / preset_name
    values = preset_values(preset_path)
    build_tag = values.get("InpBuildTag", "")
    log_folder = spec.overrides["InpLogFolder"]
    if build_tag != BUILD_TAG or not log_folder:
        raise RuntimeError(f"invalid QBR v1.13 preset: {preset_path}")

    suffix = f"-{args.report_suffix}" if args.report_suffix else ""
    report_name = (
        f"QBR-{args.candidate}-{args.symbol}-M15-"
        f"{args.from_date}-{args.to_date}{suffix}"
    )
    env = os.environ.copy()
    env.update(
        {
            "MT5_EXPERT": r"QuantumBehavioralReplica\QuantumBehavioralReplica.ex5",
            "MT5_INCLUDE_DIR": "QBR",
            "MT5_PRESET": f"QBR/{preset_name}",
            "MT5_SYMBOL": args.symbol,
            "MT5_PERIOD": "M15",
            "MT5_FROM": args.from_date,
            "MT5_TO": args.to_date,
            "MT5_DEPOSIT": str(args.deposit),
            "MT5_LEVERAGE": str(args.leverage),
            "MT5_MODEL": "4",
            "MT5_REPORT": report_name,
            "MT5_INPUT_OVERRIDES": "\n".join(
                f"{key}={value}" for key, value in spec.overrides.items()
            ),
            "WINEDLLOVERRIDES": "mmdevapi=d",
            "WINEDEBUG": "-all",
        }
    )
    command = ["bash", str(ROOT / "scripts" / "run-mt5-backtest.sh")]
    print("Candidate:", args.candidate)
    print("Preset:", preset_path)
    print("Build tag:", build_tag)
    print("Report:", REPORT_DIR / f"{report_name}.htm")
    print("Command:", " ".join(command))
    print("Overrides:")
    if lineage:
        print("Evidence lineage:", " -> ".join(lineage))
    for key, value in spec.overrides.items():
        print(f"  {key}={value}")
    if args.dry_run:
        return 0

    report_path = REPORT_DIR / f"{report_name}.htm"
    mt5_root = (
        Path(env.get("MT5_PREFIX", str(Path.home() / "Library/Application Support/net.metaquotes.wine.metatrader5")))
        / "drive_c/Program Files/MetaTrader 5"
    )
    mt5_report_path = mt5_root / "reports" / f"{report_name}.htm"
    report_path.unlink(missing_ok=True)
    mt5_report_path.unlink(missing_ok=True)
    clear_logs(mt5_root, log_folder)
    subprocess.run(command, cwd=ROOT, env=env, check=True)
    config_name = f"QuantumBehavioralReplica-{args.symbol}-M15.ini"
    wait_for_report(mt5_report_path, config_name, args.timeout_seconds)
    if not mt5_report_path.exists():
        raise RuntimeError(f"MT5 finished without report: {mt5_report_path}")
    shutil.copy2(mt5_report_path, report_path)
    copy_logs(
        mt5_root,
        log_folder,
        REPORT_DIR / f"{report_name}.qbr-logs",
    )
    expected_inputs = {
        "InpRunId": spec.overrides["InpRunId"],
        "InpLogFolder": spec.overrides["InpLogFolder"],
    }
    if "InpMinLotAllowedHours" in spec.overrides:
        expected_inputs["InpMinLotAllowedHours"] = spec.overrides["InpMinLotAllowedHours"]
    quality = validate_report(
        report_path,
        build_tag,
        args.min_real_tick_quality,
        expected_inputs,
    )
    analysis_dir = REPORT_DIR / f"{report_name}.qbr-analysis"
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts/qbr/analyze_backtest.py"),
            "--logs",
            str(REPORT_DIR / f"{report_name}.qbr-logs"),
            "--report",
            str(report_path),
            "--out",
            str(analysis_dir),
        ],
        cwd=ROOT,
        check=True,
    )
    (analysis_dir / "run_manifest.json").write_text(
        json.dumps(
            {
                "candidate": args.candidate,
                "build_tag": build_tag,
                "symbol": args.symbol,
                "from_date": args.from_date,
                "to_date": args.to_date,
                "deposit": args.deposit,
                "leverage": args.leverage,
                "minimum_real_tick_quality_pct": args.min_real_tick_quality,
                "evidence_lineage": lineage,
                "overrides": spec.overrides,
            },
            indent=2,
        ) + "\n"
    )
    print(f"Validated report: {report_path} ({quality:.2f}% real ticks)")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"QBR run failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
