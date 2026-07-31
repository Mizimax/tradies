#!/usr/bin/env python3
"""GoldBot offline AI max-return experiment runner.

This keeps XGBoost/LightGBM offline: it audits MT5 journals for ML-ready feature
snapshots, trains a local classifier, emits score/slice diagnostics, and prints
config-only candidate rows to validate later in real MT5 Strategy Tester runs.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import math
import os
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Iterable, Sequence


ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "mt5/backtests/reports"
AI_DIR = ROOT / "mt5/backtests/ai-maxret"
PARSER_PATH = ROOT / "scripts/mt5-ml-trim-analysis.py"
TRAINER_PATH = ROOT / "scripts/train-mt5-ml-filter.py"

SEEDS = {
    "daily2": "scalp-adaptive-daily2-monthlock25",
    "tg15_m1micro": "scalp-adaptive-w4vb-nocap-tg15-m1micro",
    "v2t8_w3": "scalp-adaptive-v2t8-w3",
}
WINDOWS = {
    "6m": ("2026.01.01", "2026.06.30", "ai-s1-6m-1000", 75),
    "1y": ("2025.07.01", "2026.06.30", "ai-s1-1y-1000", 100),
    "2y": ("2024.07.01", "2026.06.30", "ai-s1-2y-1000", 150),
}
FEATURE_FIELDS = (
    "spread",
    "spread_to_tp_pct",
    "adx",
    "di_gap",
    "atr",
    "atr_ratio",
    "ema21",
    "ema50",
    "vwap",
    "zone_width",
    "sl_distance",
    "lot_multiplier",
    "setup_risk_multiplier",
)


@dataclass(frozen=True)
class AuditResult:
    journal: Path
    ok: bool
    closed_trades: int
    first_time: str
    last_time: str
    feature_rich_ratio: float
    reasons: tuple[str, ...]


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    if spec.loader is None:
        raise RuntimeError(f"Cannot load module: {path}")
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def parser_module():
    return load_module(PARSER_PATH, "mt5_ml_trim_analysis")


def trainer_module():
    return load_module(TRAINER_PATH, "mt5_ml_filter_trainer")


def parse_time(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d %H:%M:%S")


def parse_date(value: str) -> datetime:
    return datetime.strptime(value, "%Y.%m.%d")


def expected_artifact(candidate: str, suffix: str) -> str:
    return f"{candidate}-{suffix}"


def expected_journal(candidate: str, suffix: str, report_dir: Path = REPORT_DIR) -> Path:
    artifact = expected_artifact(candidate, suffix)
    return report_dir / f"GoldBot-real-{artifact}.trades.csv"


def feature_rich(deal: Any) -> bool:
    return any(abs(float(getattr(deal, field, 0.0))) > 1e-12 for field in FEATURE_FIELDS)


def audit_journal(
    journal: Path,
    *,
    from_date: str,
    to_date: str,
    min_closed_trades: int,
    min_feature_rich_ratio: float = 0.80,
) -> AuditResult:
    parser = parser_module()
    reasons: list[str] = []
    if not journal.exists():
        return AuditResult(journal, False, 0, "", "", 0.0, ("missing_journal",))

    rows = parser.read_journal_rows(journal)
    times: list[datetime] = []
    for time_value, _ in rows:
        try:
            times.append(parse_time(time_value))
        except ValueError:
            continue

    first_time = min(times).strftime("%Y.%m.%d %H:%M:%S") if times else ""
    last_time = max(times).strftime("%Y.%m.%d %H:%M:%S") if times else ""
    if not times:
        reasons.append("no_journal_times")
    else:
        if min(times).date() > parse_date(from_date).date() + timedelta(days=2):
            reasons.append(f"starts_late:{first_time}")
        if max(times).date() < parse_date(to_date).date() - timedelta(days=2):
            reasons.append(f"stops_early:{last_time}")

    deals = parser.parse_closed_deals(journal)
    if len(deals) < min_closed_trades:
        reasons.append(f"closed_trades:{len(deals)}<{min_closed_trades}")
    rich_count = sum(1 for deal in deals if feature_rich(deal))
    rich_ratio = rich_count / len(deals) if deals else 0.0
    if rich_ratio < min_feature_rich_ratio:
        reasons.append(f"feature_rich_ratio:{rich_ratio:.2f}<{min_feature_rich_ratio:.2f}")

    return AuditResult(journal, not reasons, len(deals), first_time, last_time, rich_ratio, tuple(reasons))


def profit_factor(profits: Sequence[float]) -> float:
    gross_profit = sum(value for value in profits if value > 0.0)
    gross_loss = sum(value for value in profits if value < 0.0)
    if gross_loss < 0.0:
        return gross_profit / abs(gross_loss)
    return gross_profit if gross_profit > 0.0 else 0.0


def aggregate_rows(rows: Sequence[dict[str, Any]]) -> dict[str, float]:
    profits = [float(row.get("profit", 0.0)) for row in rows]
    trades = len(profits)
    wins = sum(1 for profit in profits if profit > 0.0)
    return {
        "trades": float(trades),
        "net_profit": round(sum(profits), 2),
        "profit_factor": round(profit_factor(profits), 4),
        "win_rate_pct": round((wins / trades * 100.0) if trades else 0.0, 2),
    }


def write_dicts(path: Path, rows: Sequence[dict[str, Any]], fieldnames: Sequence[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def score_bucket_rows(rows: Sequence[dict[str, Any]], probabilities: Sequence[float]) -> list[dict[str, Any]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for row, probability in zip(rows, probabilities):
        low = int(math.floor(probability * 10.0) * 10)
        if low >= 100:
            low = 90
        label = f"{low:02d}-{low + 10:02d}"
        grouped.setdefault(label, []).append(row)
    output: list[dict[str, Any]] = []
    for bucket, bucket_rows in sorted(grouped.items()):
        agg = aggregate_rows(bucket_rows)
        output.append({"score_bucket": bucket, **agg})
    return output


def slice_rows(rows: Sequence[dict[str, Any]], min_trades: int = 5) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, str, str], list[dict[str, Any]]] = {}
    for row in rows:
        key = (str(row.get("setup", "")), str(row.get("direction", "")), str(row.get("hour", "")))
        grouped.setdefault(key, []).append(row)
    output: list[dict[str, Any]] = []
    for (setup, direction, hour), bucket in grouped.items():
        if len(bucket) < min_trades:
            continue
        agg = aggregate_rows(bucket)
        label = "strong" if agg["net_profit"] > 0 and agg["profit_factor"] >= 1.30 else "weak"
        if agg["net_profit"] < 0 or agg["profit_factor"] < 1.00 or label == "strong":
            output.append({"setup": setup, "direction": direction, "hour": hour, "slice": label, **agg})
    return sorted(output, key=lambda row: (row["slice"], -abs(float(row["net_profit"])), row["setup"], row["direction"], row["hour"]))


def feature_threshold_slice_rows(rows: Sequence[dict[str, Any]], min_trades: int = 5) -> list[dict[str, Any]]:
    grouped: dict[tuple[str, str, str], list[dict[str, Any]]] = {}
    for row in rows:
        key = (str(row.get("setup", "")), str(row.get("direction", "")), str(row.get("hour", "")))
        grouped.setdefault(key, []).append(row)

    output: list[dict[str, Any]] = []
    for (setup, direction, hour), bucket in grouped.items():
        if len(bucket) < min_trades:
            continue
        for field in FEATURE_FIELDS:
            values = sorted(float(row.get(field, 0.0) or 0.0) for row in bucket)
            if not values or values[0] == values[-1]:
                continue
            threshold = values[len(values) // 2]
            partitions = (
                (f"{field}<={threshold:.4f}", [row for row in bucket if float(row.get(field, 0.0) or 0.0) <= threshold]),
                (f"{field}>{threshold:.4f}", [row for row in bucket if float(row.get(field, 0.0) or 0.0) > threshold]),
            )
            for condition, condition_rows in partitions:
                if len(condition_rows) < min_trades:
                    continue
                agg = aggregate_rows(condition_rows)
                label = "strong" if agg["net_profit"] > 0 and agg["profit_factor"] >= 1.30 else "weak"
                if agg["net_profit"] < 0 or agg["profit_factor"] < 1.00 or label == "strong":
                    output.append(
                        {
                            "setup": setup,
                            "direction": direction,
                            "hour": hour,
                            "feature": field,
                            "condition": condition,
                            "slice": label,
                            **agg,
                        }
                    )
    return sorted(
        output,
        key=lambda row: (
            row["slice"],
            -abs(float(row["net_profit"])),
            row["setup"],
            row["direction"],
            row["hour"],
            row["feature"],
            row["condition"],
        ),
    )


def feature_importance_rows(model: Any, feature_names: Sequence[str]) -> list[dict[str, Any]]:
    importances = getattr(model, "feature_importances_", None)
    if importances is None:
        return []
    rows: list[dict[str, Any]] = []
    for name, importance in zip(feature_names, importances):
        rows.append({"feature": name, "importance": float(importance)})
    return sorted(rows, key=lambda row: row["importance"], reverse=True)


def load_rows_from_journals(journals: Sequence[Path]) -> list[dict[str, Any]]:
    parser = parser_module()
    deals = []
    for journal in journals:
        deals.extend(parser.parse_closed_deals(journal))
    return parser.deals_to_ml_rows(deals)


def run_training(journals: Sequence[Path], output_dir: Path, backend_name: str) -> int:
    trainer = trainer_module()
    rows = load_rows_from_journals(journals)
    if len(rows) < 100:
        print(f"Not enough closed deals for AI experiment: {len(rows)} < 100", file=sys.stderr)
        return 1
    backend_name, backend = trainer.load_backend(backend_name)
    matrix, labels, feature_names = trainer.build_feature_matrix(rows)
    train_slice, test_slice = trainer.temporal_split(len(matrix), 0.30)
    model = trainer.train_model(backend_name, backend, matrix[train_slice], labels[train_slice])
    test_probabilities = trainer.predict_probabilities(model, matrix[test_slice])
    all_probabilities = trainer.predict_probabilities(model, matrix)
    metrics = trainer.classification_report(labels[test_slice], test_probabilities)
    metrics.update({"backend": backend_name, "train_trades": len(labels[train_slice]), "total_trades": len(labels)})

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "metrics.json").write_text(json.dumps(metrics, indent=2) + "\n")
    write_dicts(
        output_dir / "score-buckets.csv",
        score_bucket_rows(rows, all_probabilities),
        ["score_bucket", "trades", "net_profit", "profit_factor", "win_rate_pct"],
    )
    write_dicts(
        output_dir / "feature-importance.csv",
        feature_importance_rows(model, feature_names)[:40],
        ["feature", "importance"],
    )
    write_dicts(
        output_dir / "slices.csv",
        slice_rows(rows),
        ["setup", "direction", "hour", "slice", "trades", "net_profit", "profit_factor", "win_rate_pct"],
    )
    write_dicts(
        output_dir / "threshold-slices.csv",
        feature_threshold_slice_rows(rows),
        [
            "setup",
            "direction",
            "hour",
            "feature",
            "condition",
            "slice",
            "trades",
            "net_profit",
            "profit_factor",
            "win_rate_pct",
        ],
    )
    write_dicts(
        output_dir / "candidate-suggestions.csv",
        generated_candidate_rows(),
        ["name", "description", "overrides"],
    )
    print(json.dumps(metrics, indent=2))
    print(f"Wrote AI experiment artifacts to {output_dir}")
    return 0


def generated_candidate_rows() -> list[dict[str, str]]:
    return [
        {
            "name": "ai-maxret-s1-w3-debrick",
            "description": "AI S1 max-return W3 seed with debrick monthly throttle to test 2y durability",
            "overrides": "@scalp-adaptive-v2t8-w3\\nInpCompoundMaxDrawdownPct=0.0\\nInpEnableMonthlyLossThrottle=true\\nInpMonthlyLossSoftPct=1.5\\nInpMonthlyLossHardPct=6.0\\nInpMonthlyLossSoftRiskMultiplier=0.5\\nInpMonthlyLossHardBlock=true",
        },
        {
            "name": "ai-maxret-s1-w3-robust-nocap",
            "description": "AI S1 W3 debrick plus robust volatility gate without upper ATR cap",
            "overrides": "@ai-maxret-s1-w3-debrick\\nInpEnableRobustRegimeFilter=true\\nInpRobustApplyToM5=true\\nInpRobustApplyToM15=true\\nInpRobustBlockIfMonthlyLossPct=0.0\\nInpRobustMinH1Adx=0.0\\nInpRobustMinH1EmaSlopeAtr=0.0\\nInpRobustMinH1AtrRatio=0.70\\nInpRobustMaxH1AtrRatio=0.0",
        },
        {
            "name": "ai-maxret-s1-w3-tg15",
            "description": "AI S1 W3 seed with daily target raised to 15 pct for max-return capture",
            "overrides": "@scalp-adaptive-v2t8-w3\\nInpDailyTargetPct=15.0",
        },
        {
            "name": "ai-maxret-s1-w3-m1micro",
            "description": "AI S1 W3 seed with M1 micro layer added for extra opportunity density",
            "overrides": "@scalp-adaptive-v2t8-w3\\nInpEnableM1MicroScalpSetup=true",
        },
        {
            "name": "ai-maxret-s1-w3-m1micro-clean",
            "description": "AI S1 W3 M1 micro layer with weak M1 long hour 10 removed",
            "overrides": "@ai-maxret-s1-w3-m1micro\\nInpM1MicroLongHours=18",
        },
        {
            "name": "ai-maxret-s1-tg15-m1micro-riskup",
            "description": "AI S1 tg15 M1 micro with modest setup risk and micro lot increase for max-return test",
            "overrides": "@scalp-adaptive-w4vb-nocap-tg15-m1micro\\nInpBreakoutRiskMultiplier=3.3\\nInpSmcRiskMultiplier=2.9\\nInpM5ScalpRiskMultiplier=2.0\\nInpM1MicroLotMultiplier=0.25",
        },
        {
            "name": "ai-maxret-s1-daily2-w3-risk",
            "description": "AI S1 daily2 stable timing with W3-style setup risk weights",
            "overrides": "@scalp-adaptive-daily2-monthlock25\\nInpBreakoutRiskMultiplier=2.5\\nInpSmcRiskMultiplier=2.2\\nInpM5ScalpRiskMultiplier=1.5\\nInpCompoundSoftDrawdownPct=20.0\\nInpCompoundHardThrottleDrawdownPct=27.0\\nInpCompoundMonthlyProfitLockPct=40.0",
        },
        {
            "name": "ai-maxret-s1-daily2-w3-risk-m1micro",
            "description": "AI S1 daily2 W3-risk seed plus M1 micro layer for diversified max-return test",
            "overrides": "@ai-maxret-s1-daily2-w3-risk\\nInpEnableM1MicroScalpSetup=true\\nInpM1MicroLongHours=18\\nInpM1MicroShortHours=7;8;10",
        },
    ]


def generated_daily2_s3_rows() -> list[dict[str, str]]:
    return [
        {
            "name": "daily2-ai-s3-risk112",
            "description": "AI S3 gentler all-setup risk lift to recover PF/DD versus risk115",
            "overrides": "@scalp-adaptive-daily2-monthlock25\\nInpBreakoutRiskMultiplier=1.12\\nInpSmcRiskMultiplier=1.12\\nInpM5ScalpRiskMultiplier=1.08",
        },
        {
            "name": "daily2-ai-s3-m5smc115-bk105",
            "description": "AI S3 risk-by-setup allocation toward the stronger M5 and SMC slices",
            "overrides": "@scalp-adaptive-daily2-monthlock25\\nInpBreakoutRiskMultiplier=1.05\\nInpSmcRiskMultiplier=1.15\\nInpM5ScalpRiskMultiplier=1.15",
        },
        {
            "name": "daily2-ai-s3-risk115-splitclean",
            "description": "AI S3 risk115 with the persistent long12 split2 weak pocket forced out",
            "overrides": "@daily2-ai-s2-risk115\\nInpEnableHourSplitGuard=true\\nInpSplit1OnlyLongHours=12\\nInpSplit1OnlyShortHours=",
        },
        {
            "name": "daily2-ai-s3-risk115-lock20",
            "description": "AI S3 risk115 with earlier monthly profit lock for robustness",
            "overrides": "@daily2-ai-s2-risk115\\nInpCompoundMonthlyProfitLockPct=20.0",
        },
        {
            "name": "daily2-ai-s3-m5smc115-bk105-lock20",
            "description": "AI S3 risk-by-setup allocation with earlier monthly profit lock",
            "overrides": "@daily2-ai-s3-m5smc115-bk105\\nInpCompoundMonthlyProfitLockPct=20.0",
        },
    ]


def write_candidate_rows(rows: Sequence[dict[str, str]], output) -> None:
    writer = csv.DictWriter(output, fieldnames=["name", "description", "overrides"])
    writer.writeheader()
    for row in rows:
        writer.writerow(row)


def seed_run_rows() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for seed, candidate in SEEDS.items():
        for window, (from_date, to_date, suffix, _) in WINDOWS.items():
            command = (
                f"WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all python3 scripts/run-mt5-growth-candidate.py "
                f"{candidate} --from-date {from_date} --to-date {to_date} --deposit 1000 "
                f"--report-suffix {suffix} --clean"
            )
            rows.append(
                {
                    "seed": seed,
                    "candidate": candidate,
                    "window": window,
                    "from_date": from_date,
                    "to_date": to_date,
                    "deposit": "1000",
                    "report_suffix": suffix,
                    "command": command,
                }
            )
    return rows


def print_run_plan(output) -> None:
    writer = csv.DictWriter(
        output,
        fieldnames=["seed", "candidate", "window", "from_date", "to_date", "deposit", "report_suffix", "command"],
    )
    writer.writeheader()
    writer.writerows(seed_run_rows())


def candidate_run_rows() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for row in generated_candidate_rows():
        candidate = row["name"]
        for window, (from_date, to_date, suffix, _) in WINDOWS.items():
            command = (
                f"WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all python3 scripts/run-mt5-growth-candidate.py "
                f"{candidate} --from-date {from_date} --to-date {to_date} --deposit 1000 "
                f"--report-suffix {suffix} --clean"
            )
            rows.append(
                {
                    "candidate": candidate,
                    "window": window,
                    "from_date": from_date,
                    "to_date": to_date,
                    "deposit": "1000",
                    "report_suffix": suffix,
                    "command": command,
                }
            )
    return rows


def daily2_s3_run_rows() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for row in generated_daily2_s3_rows():
        candidate = row["name"]
        for window, (from_date, to_date, _suffix, _) in WINDOWS.items():
            suffix = f"ai-s3-{window}-1000"
            command = (
                f"WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all python3 scripts/run-mt5-growth-candidate.py "
                f"{candidate} --from-date {from_date} --to-date {to_date} --deposit 1000 "
                f"--report-suffix {suffix} --clean"
            )
            rows.append(
                {
                    "candidate": candidate,
                    "window": window,
                    "from_date": from_date,
                    "to_date": to_date,
                    "deposit": "1000",
                    "report_suffix": suffix,
                    "command": command,
                }
            )
    return rows


def print_candidate_run_plan(output) -> None:
    writer = csv.DictWriter(
        output,
        fieldnames=["candidate", "window", "from_date", "to_date", "deposit", "report_suffix", "command"],
    )
    writer.writeheader()
    writer.writerows(candidate_run_rows())


def print_daily2_s3_run_plan(output) -> None:
    writer = csv.DictWriter(
        output,
        fieldnames=["candidate", "window", "from_date", "to_date", "deposit", "report_suffix", "command"],
    )
    writer.writeheader()
    writer.writerows(daily2_s3_run_rows())


def run_backtest_rows(rows: Sequence[dict[str, str]], *, continue_on_failure: bool) -> int:
    status = 0
    env = os.environ.copy()
    env["WINEDLLOVERRIDES"] = "mmdevapi=d"
    env["WINEDEBUG"] = "-all"
    total = len(rows)
    for index, row in enumerate(rows, start=1):
        candidate = row["candidate"]
        print(f"[{index}/{total}] {candidate} {row['window']} {row['from_date']}..{row['to_date']}")
        command = [
            sys.executable,
            "scripts/run-mt5-growth-candidate.py",
            candidate,
            "--from-date",
            row["from_date"],
            "--to-date",
            row["to_date"],
            "--deposit",
            row["deposit"],
            "--report-suffix",
            row["report_suffix"],
            "--clean",
        ]
        result = subprocess.call(command, cwd=ROOT, env=env)
        if result != 0:
            status = result
            if not continue_on_failure:
                return result
    return status


def audit_expected(report_dir: Path, output) -> int:
    rows: list[dict[str, Any]] = []
    ok = True
    for seed, candidate in SEEDS.items():
        for window, (from_date, to_date, suffix, min_trades) in WINDOWS.items():
            journal = expected_journal(candidate, suffix, report_dir)
            result = audit_journal(journal, from_date=from_date, to_date=to_date, min_closed_trades=min_trades)
            ok = ok and result.ok
            rows.append(
                {
                    "seed": seed,
                    "candidate": candidate,
                    "window": window,
                    "journal": str(journal),
                    "ok": int(result.ok),
                    "closed_trades": result.closed_trades,
                    "first_time": result.first_time,
                    "last_time": result.last_time,
                    "feature_rich_ratio": f"{result.feature_rich_ratio:.4f}",
                    "reasons": ";".join(result.reasons),
                }
            )
    writer = csv.DictWriter(output, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    for row in rows:
        writer.writerow(row)
    return 0 if ok else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("plan-runs", help="Print clean seed backtest commands for 6m/1y/2y")
    subparsers.add_parser("plan-candidates", help="Print generated candidate backtest commands for 6m/1y/2y")
    subparsers.add_parser("candidates", help="Print generated ai-maxret-s1 candidate rows as CSV")
    subparsers.add_parser("plan-daily2-s3", help="Print generated Daily2 S3 candidate backtest commands")
    subparsers.add_parser("daily2-s3-candidates", help="Print generated Daily2 S3 candidate rows as CSV")

    run_seeds_parser = subparsers.add_parser("run-seeds", help="Run clean seed backtests sequentially")
    run_seeds_parser.add_argument("--dry-run", action="store_true")
    run_seeds_parser.add_argument("--continue-on-failure", action="store_true")

    run_candidates_parser = subparsers.add_parser("run-candidates", help="Run generated candidate backtests sequentially")
    run_candidates_parser.add_argument("--dry-run", action="store_true")
    run_candidates_parser.add_argument("--continue-on-failure", action="store_true")

    run_daily2_s3_parser = subparsers.add_parser("run-daily2-s3", help="Run generated Daily2 S3 backtests sequentially")
    run_daily2_s3_parser.add_argument("--dry-run", action="store_true")
    run_daily2_s3_parser.add_argument("--continue-on-failure", action="store_true")

    audit_parser = subparsers.add_parser("audit", help="Audit expected ML-ready seed journals")
    audit_parser.add_argument("--report-dir", type=Path, default=REPORT_DIR)

    train_parser = subparsers.add_parser("train", help="Train and write AI diagnostics from journals")
    train_parser.add_argument("journals", nargs="+", type=Path)
    train_parser.add_argument("--backend", choices=("auto", "xgboost", "lightgbm"), default="auto")
    train_parser.add_argument("--output-dir", type=Path, default=AI_DIR / "s1")

    args = parser.parse_args()
    if args.command == "plan-runs":
        print_run_plan(sys.stdout)
        return 0
    if args.command == "plan-candidates":
        print_candidate_run_plan(sys.stdout)
        return 0
    if args.command == "candidates":
        write_candidate_rows(generated_candidate_rows(), sys.stdout)
        return 0
    if args.command == "plan-daily2-s3":
        print_daily2_s3_run_plan(sys.stdout)
        return 0
    if args.command == "daily2-s3-candidates":
        write_candidate_rows(generated_daily2_s3_rows(), sys.stdout)
        return 0
    if args.command == "run-seeds":
        if args.dry_run:
            print_run_plan(sys.stdout)
            return 0
        return run_backtest_rows(seed_run_rows(), continue_on_failure=args.continue_on_failure)
    if args.command == "run-candidates":
        if args.dry_run:
            print_candidate_run_plan(sys.stdout)
            return 0
        return run_backtest_rows(candidate_run_rows(), continue_on_failure=args.continue_on_failure)
    if args.command == "run-daily2-s3":
        if args.dry_run:
            print_daily2_s3_run_plan(sys.stdout)
            return 0
        return run_backtest_rows(daily2_s3_run_rows(), continue_on_failure=args.continue_on_failure)
    if args.command == "audit":
        return audit_expected(args.report_dir, sys.stdout)
    if args.command == "train":
        return run_training(args.journals, args.output_dir, args.backend)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
