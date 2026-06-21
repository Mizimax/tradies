#!/usr/bin/env python3
"""Run the GoldBot improvement candidate suite and write comparison artifacts."""

from __future__ import annotations

import argparse
import csv
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CANDIDATES = [
    "tp-repair-score62-risk003",
    "smc-hours-12-17-19",
    "smc-hours-7-12-15-17-19",
    "pf-long-hours-7-12-16",
    "pf-long-hours-7-12-16-ladder2only",
    "pf-long-hours-7-12-16-ladder23",
    "pf-long-hours-7-12-16-19-ladder2only",
    "pf-short-hour19-ladder2only",
    "pf-dir-hours-long7-12-16-short19",
    "pf-dir-hours-long7-12-16-short19-ladder2only",
    "smc-sequence-soft",
    "smc-sequence-soft-hours",
    "smc-htf-context-soft",
    "smc-ob-fvg-overlap",
    "smc-balanced-best-risk003",
    "tp-repair-long-only",
    "tp-repair-short-only",
    "tp-repair-ladder1",
    "tp-repair-ladder2",
    "tp-repair-be1",
    "tp-repair-fast-tp",
    "tp-repair-long-only-ladder1",
    "tp-repair-short-only-ladder1",
    "quality-adx-conf4",
    "quality-8ind-conf4",
    "quality-8ind-conf4-ladder1",
    "quality-8ind-conf4-noadx",
    "quality-8ind-conf5",
    "quality-8ind-conf5-ladder1",
    "ts-lite-8ind-conf4",
    "ts-lite-8ind-conf4-check1",
    "ts-complete-8ind-conf5",
    "ts-complete-8ind-conf5-ladder1",
    "growth-long-7-12-full",
    "growth-long-7-12-ladder23",
    "growth-long-7-12-19-ladder23",
    "growth-dir-long7-12-short19-full",
    "growth-open-cooldown8",
    "growth-open-fasttp",
]

GROWTH_LAYER1_CANDIDATES = [
    "growth-long-7-12-full",
    "growth-long-7-12-ladder23",
    "growth-long-7-12-19-ladder23",
    "growth-dir-long7-12-short19-full",
    "growth-open-cooldown8",
    "growth-open-fasttp",
]

GROWTH_LAYER2_CANDIDATES = [
    "growth-best-risk006",
    "growth-best-risk010",
    "growth-full-risk006",
    "growth-full-risk010",
    "growth-full-risk015",
    "growth-full-risk010-cooldown12",
    "growth-full-risk010-fasttp",
    "growth-fasttp-hour12-only",
    "growth-fasttp-hour12-split1",
    "growth-fasttp-hour12-split12",
    "growth-fasttp-hours12-16-full",
    "growth-fasttp-hours12-16-split12",
    "growth-fasttp-hours12-16-split1",
    "growth-freq-12-16-split12-cd12",
    "growth-freq-12-16-split12-cd8",
    "growth-freq-long12-14-16-18-split12",
    "growth-freq-long12-14-16-18-split12-cd8",
    "growth-freq-long12-14-16-18-split1",
    "growth-freq-dir-l12-14-16-18-s7-10-12-15-split12",
    "growth-freq-dir-l12-14-16-18-s10-12-15-split12",
    "growth-freq-dir-l12-14-16-18-s7-8-10-12-15-21-split12-cd8",
    "growth-fasttp-hour16-only-full",
    "growth-fasttp-hour16-only-split12",
    "growth-fasttp-hours12-15-16-19-full",
    "growth-fasttp-hours12-15-16-19-split12",
    "growth-fasttp-hours12-15-16-17-19-full",
    "growth-fasttp-hours12-15-16-17-19-split12",
    "growth-fasttp-dir-long12-15-16-short19-full",
    "growth-fasttp-dir-long12-15-16-short19-split12",
]
GROWTH_RECENT_YEAR_CANDIDATES = [
    "recent-l12-14-16-18-split1-cd8",
    "recent-l12-14-16-18-split12-cd8",
    "recent-l12-14-16-18-split1-cd6",
    "recent-l12-14-16-18-split1-cd4",
    "recent-l12-14-16-18-split1-maxopen3",
    "recent-l12-14-16-18-split1-maxladder20",
    "recent-dir-l12-14-16-18-s7-8-10-21-split12-cd8",
    "recent-dir-l12-14-16-18-s7-8-10-21-split1-cd8",
    "recent-freq-dir-split12-cd4",
    "recent-freq-dir-split12-maxladder20",
    "recent-freq-dir-split12-maxopen3",
    "recent-freq-dir-split123-cd8",
    "recent-freq-dir-split123-maxopen3",
    "recent-freq-dir-long7-split12-cd8",
    "recent-freq-dir-long7-split123-cd8",
    "recent-freq-dir-score60-split12-cd8",
    "recent-regime-ext3",
    "recent-regime-ext25",
    "recent-regime-slope015-ext3",
    "recent-regime-slope015-ext25",
    "recent-regime-h1dir-ext3",
]
GROWTH_PROFIT_CORE_CANDIDATES = [
    "profit-core-l12-18-shorts-split12",
    "profit-core-l12-18-shorts-split1",
    "profit-core-l12-shorts-split12",
    "profit-core-l18-shorts-split12",
    "profit-core-no-long16-split12",
    "profit-core-l12-18-shorts-split12-cd4",
    "profit-core-l12-18-shorts-split12-maxopen3",
    "profit-core-freq-no-long16-split123",
    "profit-core-freq-no-long16-cd4",
    "profit-core-freq-no-long16-maxopen3",
    "profit-core-freq-no-long16-score60",
    "profit-core-freq-no-long16-short12",
    "profit-core-freq-no-long16-short12-15",
    "profit-core-freq-add-long16-split12",
    "profit-core-freq-add-long16-split1",
]
GROWTH_FREQ80_CANDIDATES = [
    "freq80-core-short12-cd4-maxopen3",
    "freq80-long10-20-short12",
    "freq80-long10-16-20-short12",
    "freq80-long10-16-20-short12-14-16",
    "freq80-wide-no15",
    "freq80-wide-no15-strict-added",
    "freq80-wide-no15-strict-vwap",
    "freq80-wide-no15-strict-m5",
]
GROWTH_FREQ100_CANDIDATES = [
    "freq100-wide-no15-cd2",
    "freq100-wide-no15-maxopen4",
    "freq100-wide-no15-split123",
    "freq100-splitguard-wide-no15",
    "freq100-splitguard-cd2-maxopen4",
    "freq100-strict-vwap-weakonly",
    "freq100-strict-vwap-weakonly-cd2-maxopen4",
    "freq100-continuation-core",
    "freq100-continuation-wide-splitguard",
    "freq100-continuation-wide-strict-vwap",
]
GROWTH_FREQ100B_CANDIDATES = [
    "freq100b-splitguard-cd1-maxopen4",
    "freq100b-splitguard-cd2-maxopen4-maxladder30",
    "freq100b-splitguard-cd1-maxopen4-maxladder30",
    "freq100b-splitguard-cd2-maxopen5",
    "freq100b-strict-vwap-cd1-maxopen4",
    "freq100b-strict-vwap-cd2-maxopen5",
    "freq100b-strict-vwap-cd1-maxopen5",
    "freq100b-strict-vwap-score60-cd2-maxopen4",
    "freq100b-strict-vwap-long14-open-cd2-maxopen4",
    "freq100b-strict-vwap-long14-open-cd1-maxopen4",
]
GROWTH_FREQ100C_CANDIDATES = [
    "freq100c-splitguard-cd1-no-short12",
    "freq100c-splitguard-cd1-no-short12-score60",
    "freq100c-splitguard-cd1-no-short12-long14-open",
    "freq100c-splitguard-cd1-no-short12-maxopen5",
    "freq100c-strict-vwap-cd1-score60-rerun",
    "freq100c-strict-vwap-cd1-long14-open-rerun",
]
GROWTH_FREQ100D_CANDIDATES = [
    "freq100d-no-short12-split123",
    "freq100d-no-short12-split123-maxopen5",
    "freq100d-no-short12-no-long16-split123",
    "freq100d-no-short12-open-short16-split12",
    "freq100d-no-short12-continuation-safe",
    "freq100d-no-short12-continuation-safe-split123",
]
GROWTH_FREQ100E_CANDIDATES = [
    "freq100e-breakout-core",
    "freq100e-breakout-core-split123",
    "freq100e-breakout-loose-body",
    "freq100e-breakout-no-vwap",
    "freq100e-breakout-no-h1trend",
    "freq100e-breakout-quality",
]
GROWTH_FREQ100F_CANDIDATES = [
    "freq100f-breakout-no-vwap-no-long18",
    "freq100f-breakout-no-vwap-no-long18-split123",
    "freq100f-breakout-no-vwap-long12-only",
]
GROWTH_FREQ100G_CANDIDATES = [
    "freq100g-streak-cooldown",
    "freq100g-streak-monthly",
    "freq100g-streak-monthly-body",
    "freq100g-breakout-no-vwap-no-long18-jan-guard",
]
GROWTH_FREQ100H_CANDIDATES = [
    "freq100h-cancel-siblings-sl",
    "freq100h-ladder-gap4",
    "freq100h-long-session19",
    "freq100h-long-session20",
    "freq100h-gap4-session19",
    "freq100h-gap4-session20",
]
GROWTH_FREQ100I_CANDIDATES = [
    "freq100i-session20-score60",
    "freq100i-session20-split123",
    "freq100i-session20-maxopen5",
    "freq100i-session20-short12",
    "freq100i-session20-breakout-short16",
    "freq100i-session20-breakout-long10",
    "freq100i-session20-breakout-wide-quality",
    "freq100i-session20-score60-short12",
]
GROWTH_FREQ100J_CANDIDATES = [
    "freq100j-ath15",
    "freq100j-ath10",
    "freq100j-ath20",
    "freq100j-h4rsi72",
    "freq100j-h4rsi75",
    "freq100j-ath15-h4rsi72",
    "freq100j-ath15-h4rsi72-freqfloor",
    "freq100j-ath20-h4rsi75-freqfloor",
]
GROWTH_FREQ100K_CANDIDATES = [
    "freq100k-breakout-only",
    "freq100k-breakout-only-score60",
    "freq100k-breakout-plus-smc-short7",
    "freq100k-breakout-plus-smc-short7-long12-18",
    "freq100k-breakout-plus-smc-no-hour8",
    "freq100k-breakout-plus-smc-htf-context",
    "freq100k-breakout-plus-smc-score75",
]
GROWTH_FREQ100L_CANDIDATES = [
    "freq100l-no-breakout-short10",
    "freq100l-no-breakout-long7",
    "freq100l-no-breakout-short10-long7",
]


def load_candidate_names(matrix: Path) -> set[str]:
    with matrix.open(newline="") as handle:
        return {row["name"].strip() for row in csv.DictReader(handle)}


def artifact_name(candidate: str, report_suffix: str = "") -> str:
    report_suffix = report_suffix.strip()
    if report_suffix:
        return f"{candidate}-{report_suffix}"
    return candidate


def report_path(candidate: str, report_suffix: str = "") -> Path:
    return ROOT / "mt5/backtests/reports" / f"GoldBot-real-{artifact_name(candidate, report_suffix)}.htm"


def journal_path(candidate: str, report_suffix: str = "") -> Path:
    return ROOT / "mt5/backtests/reports" / f"GoldBot-real-{artifact_name(candidate, report_suffix)}.trades.csv"


def run_command(command: list[str], *, capture: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture else None,
        check=False,
    )


def write_command_output(command: list[str], output_path: Path, allow_statuses: set[int]) -> int:
    result = run_command(command, capture=True)
    output_path.write_text(result.stdout or "")
    if result.returncode not in allow_statuses:
        sys.stderr.write(result.stdout or "")
    return result.returncode


def csv_first_row(output: str) -> dict[str, str]:
    lines = [line for line in output.splitlines() if line.strip()]
    if not lines:
        return {}
    try:
        rows = list(csv.DictReader(lines))
    except csv.Error:
        return {}
    return rows[0] if rows else {}


def command_csv_row(command: list[str]) -> dict[str, str]:
    result = run_command(command, capture=True)
    if result.returncode not in (0, 1, 2):
        return {}
    return csv_first_row(result.stdout or "")


def as_int(value: str) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return 0


def journal_has_deals(journal: Path) -> bool:
    if not journal.exists():
        return False
    row = command_csv_row([sys.executable, "scripts/analyze-mt5-trades.py", str(journal)])
    return as_int(row.get("deal_events", "0")) > 0


def report_is_malformed(report: Path, journal: Path) -> bool:
    if not report.exists() or not journal.exists():
        return False
    row = command_csv_row([sys.executable, "scripts/summarize-mt5-reports.py", str(report)])
    total_trades = as_int(row.get("total_trades", "0"))
    net_profit = row.get("net_profit", "")
    return (total_trades <= 0 or net_profit == "") and journal_has_deals(journal)


def write_report_status(candidate: str, artifact_mode: str, reason: str, report: Path, journal: Path) -> None:
    status_path = report.with_suffix(".report-status.csv")
    with status_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["candidate", "artifact_mode", "reason", "report", "journal"])
        writer.writeheader()
        writer.writerow({
            "candidate": artifact_name(candidate, ""),
            "artifact_mode": artifact_mode,
            "reason": reason,
            "report": report.name,
            "journal": journal.name if journal.exists() else "",
        })


def write_journal_only_artifacts(candidate: str, journal: Path, output_dir: Path) -> None:
    if not journal.exists():
        return
    artifact = artifact_name(candidate, "")
    write_command_output(
        [sys.executable, "scripts/analyze-mt5-trades.py", str(journal)],
        output_dir / f"GoldBot-real-{artifact}.journal-summary.csv",
        {0},
    )
    write_command_output(
        [sys.executable, "scripts/analyze-mt5-trades.py", "--attribution", str(journal)],
        output_dir / f"GoldBot-real-{artifact}.attribution.csv",
        {0, 1},
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidates", nargs="*", help="Candidate names to run. Defaults to Phase 3B/3C + growth candidates.")
    parser.add_argument("--matrix", type=Path, default=ROOT / "mt5/backtests/CANDIDATE_MATRIX.csv")
    parser.add_argument("--from-date", default="2024.06.01")
    parser.add_argument("--to-date", default="2026.05.31")
    parser.add_argument("--deposit", default="100000")
    parser.add_argument("--symbol", default="")
    parser.add_argument("--period", default="")
    parser.add_argument("--report-suffix", default="", help="Append a suffix to report artifacts, e.g. recent-12m.")
    parser.add_argument("--skip-existing", action="store_true", help="Skip candidates whose HTML report already exists.")
    parser.add_argument("--clean", action="store_true", help="Delete selected candidate reports before running.")
    parser.add_argument("--dry-run", action="store_true", help="Print candidate commands without launching MT5.")
    parser.add_argument("--continue-on-fail", action="store_true", help="Continue suite if one MT5 run fails.")
    parser.add_argument("--growth-only", action="store_true", help="Run only growth Layer 1 candidates.")
    parser.add_argument("--layer2", action="store_true", help="Include Layer 2 risk-scaled candidates.")
    parser.add_argument("--recent-year", action="store_true", help="Run only recent-year growth candidates unless names are provided.")
    parser.add_argument("--profit-core", action="store_true", help="Run only profit-core candidates unless names are provided.")
    parser.add_argument("--freq80", action="store_true", help="Run only GoldBot 80-150 trade frequency candidates unless names are provided.")
    parser.add_argument("--freq100", action="store_true", help="Run only GoldBot frequency-100 recovery candidates unless names are provided.")
    parser.add_argument("--freq100b", action="store_true", help="Run only GoldBot last-6-month frequency-100B candidates unless names are provided.")
    parser.add_argument("--freq100c", action="store_true", help="Run only GoldBot last-6-month frequency-100C candidates unless names are provided.")
    parser.add_argument("--freq100d", action="store_true", help="Run only GoldBot last-6-month frequency-100D candidates unless names are provided.")
    parser.add_argument("--freq100e", action="store_true", help="Run only GoldBot breakout-retest frequency-100E candidates unless names are provided.")
    parser.add_argument("--freq100f", action="store_true", help="Run only GoldBot breakout no-VWAP cleanup frequency-100F candidates unless names are provided.")
    parser.add_argument("--freq100g", action="store_true", help="Run only GoldBot January-guard frequency-100G candidates unless names are provided.")
    parser.add_argument("--freq100h", action="store_true", help="Run only GoldBot ladder/session January recovery frequency-100H candidates unless names are provided.")
    parser.add_argument("--freq100i", action="store_true", help="Run only GoldBot session20 frequency-restoration frequency-100I candidates unless names are provided.")
    parser.add_argument("--freq100j", action="store_true", help="Run only GoldBot contextual-regime frequency-100J candidates unless names are provided.")
    parser.add_argument("--freq100k", action="store_true", help="Run only GoldBot setup-allocation frequency-100K candidates unless names are provided.")
    parser.add_argument("--freq100l", action="store_true", help="Run only GoldBot weak-breakout-slice frequency-100L candidates unless names are provided.")
    args = parser.parse_args()

    known = load_candidate_names(args.matrix)
    if args.freq100l:
        candidates = args.candidates or GROWTH_FREQ100L_CANDIDATES
    elif args.freq100k:
        candidates = args.candidates or GROWTH_FREQ100K_CANDIDATES
    elif args.freq100j:
        candidates = args.candidates or GROWTH_FREQ100J_CANDIDATES
    elif args.freq100i:
        candidates = args.candidates or GROWTH_FREQ100I_CANDIDATES
    elif args.freq100h:
        candidates = args.candidates or GROWTH_FREQ100H_CANDIDATES
    elif args.freq100g:
        candidates = args.candidates or GROWTH_FREQ100G_CANDIDATES
    elif args.freq100f:
        candidates = args.candidates or GROWTH_FREQ100F_CANDIDATES
    elif args.freq100e:
        candidates = args.candidates or GROWTH_FREQ100E_CANDIDATES
    elif args.freq100d:
        candidates = args.candidates or GROWTH_FREQ100D_CANDIDATES
    elif args.freq100c:
        candidates = args.candidates or GROWTH_FREQ100C_CANDIDATES
    elif args.freq100b:
        candidates = args.candidates or GROWTH_FREQ100B_CANDIDATES
    elif args.freq100:
        candidates = args.candidates or GROWTH_FREQ100_CANDIDATES
    elif args.freq80:
        candidates = args.candidates or GROWTH_FREQ80_CANDIDATES
    elif args.profit_core:
        candidates = args.candidates or GROWTH_PROFIT_CORE_CANDIDATES
    elif args.recent_year:
        candidates = args.candidates or GROWTH_RECENT_YEAR_CANDIDATES
    elif args.growth_only:
        candidates = args.candidates or GROWTH_LAYER1_CANDIDATES
    elif args.candidates:
        candidates = args.candidates
    else:
        candidates = DEFAULT_CANDIDATES

    if args.layer2:
        candidates = list(candidates) + GROWTH_LAYER2_CANDIDATES

    unknown = [name for name in candidates if name not in known]
    if unknown:
        print("Unknown candidates: " + ", ".join(unknown), file=sys.stderr)
        return 2

    if args.clean:
        for candidate in candidates:
            for path in (
                report_path(candidate, args.report_suffix),
                journal_path(candidate, args.report_suffix),
                report_path(candidate, args.report_suffix).with_suffix(".xml"),
                report_path(candidate, args.report_suffix).with_suffix(".summary.csv"),
                report_path(candidate, args.report_suffix).with_suffix(".evaluation.csv"),
                report_path(candidate, args.report_suffix).with_suffix(".daily-growth.csv"),
                report_path(candidate, args.report_suffix).with_suffix(".equity-curve.csv"),
                report_path(candidate, args.report_suffix).with_suffix(".stability.csv"),
                report_path(candidate, args.report_suffix).with_suffix(".journal-summary.csv"),
                report_path(candidate, args.report_suffix).with_suffix(".attribution.csv"),
                report_path(candidate, args.report_suffix).with_suffix(".report-status.csv"),
            ):
                path.unlink(missing_ok=True)

    for candidate in candidates:
        if args.skip_existing and report_path(candidate, args.report_suffix).exists():
            print(f"Skipping existing report for {candidate}")
            continue

        command = [
            sys.executable,
            "scripts/run-mt5-candidate.py",
            candidate,
            "--from-date",
            args.from_date,
            "--to-date",
            args.to_date,
            "--deposit",
            args.deposit,
        ]
        if args.symbol:
            command.extend(["--symbol", args.symbol])
        if args.period:
            command.extend(["--period", args.period])
        if args.report_suffix:
            command.extend(["--report-suffix", args.report_suffix])
        if args.dry_run:
            command.append("--dry-run")

        print(f"\n=== Running {candidate} ===")
        result = run_command(command)
        if result.returncode != 0:
            if args.continue_on_fail:
                print(f"Candidate failed with exit code {result.returncode}: {candidate}", file=sys.stderr)
                continue
            return result.returncode

    if args.dry_run:
        return 0

    output_dir = ROOT / "mt5/backtests/reports"
    output_dir.mkdir(parents=True, exist_ok=True)

    reports: list[Path] = []
    journals: list[Path] = []
    malformed_reports: list[Path] = []
    for candidate in candidates:
        report = report_path(candidate, args.report_suffix)
        journal = journal_path(candidate, args.report_suffix)
        artifact = artifact_name(candidate, args.report_suffix)
        if journal.exists():
            journals.append(journal)
        if not report.exists():
            continue
        if report_is_malformed(report, journal):
            malformed_reports.append(report)
            write_report_status(artifact, "journal-only", "malformed-report", report, journal)
            write_journal_only_artifacts(artifact, journal, output_dir)
            print(f"Excluded malformed report from ranking: {report.name}", file=sys.stderr)
            continue
        reports.append(report)

    if not reports:
        if journals:
            write_command_output(
                [sys.executable, "scripts/analyze-mt5-trades.py", *map(str, journals)],
                output_dir / "improvement-journal-summary.csv",
                {0},
            )
            write_command_output(
                [sys.executable, "scripts/analyze-mt5-trades.py", "--attribution", *map(str, journals)],
                output_dir / "improvement-attribution.csv",
                {0, 1},
            )
        print("No clean candidate reports found after suite run.", file=sys.stderr)
        return 1
    summarize_path = output_dir / "improvement-summary.csv"
    evaluation_path = output_dir / "improvement-evaluation.csv"
    journal_path_out = output_dir / "improvement-journal-summary.csv"
    attribution_path = output_dir / "improvement-attribution.csv"

    write_command_output(
        [sys.executable, "scripts/summarize-mt5-reports.py", *map(str, reports)],
        summarize_path,
        {0},
    )
    evaluation_status = write_command_output(
        [
            sys.executable, "scripts/evaluate-mt5-candidates.py",
            "--from-date", args.from_date,
            "--to-date", args.to_date,
            "--deposit", args.deposit,
            *map(str, reports),
        ],
        evaluation_path,
        {0, 2},
    )
    if journals:
        write_command_output(
            [sys.executable, "scripts/analyze-mt5-trades.py", *map(str, journals)],
            journal_path_out,
            {0},
        )
        write_command_output(
            [sys.executable, "scripts/analyze-mt5-trades.py", "--attribution", *map(str, journals)],
            attribution_path,
            {0, 1},
        )

    print(f"\nWrote {summarize_path}")
    print(f"Wrote {evaluation_path}")
    if journals:
        print(f"Wrote {journal_path_out}")
        print(f"Wrote {attribution_path}")

    # Daily growth report
    daily_growth_script = ROOT / "scripts/daily-growth-report.py"
    if daily_growth_script.exists():
        daily_growth_path = output_dir / "improvement-daily-growth.csv"
        write_command_output(
            [
                sys.executable, str(daily_growth_script),
                "--deposit", args.deposit,
                "--from-date", args.from_date,
                "--to-date", args.to_date,
                *map(str, reports),
            ],
            daily_growth_path,
            {0, 1},
        )
        print(f"Wrote {daily_growth_path}")

    # Equity curve analysis
    equity_curve_script = ROOT / "scripts/equity-curve-analysis.py"
    if equity_curve_script.exists():
        equity_curve_path = output_dir / "improvement-equity-curve.csv"
        write_command_output(
            [sys.executable, str(equity_curve_script), "--deposit", args.deposit, *map(str, reports)],
            equity_curve_path,
            {0, 1},
        )
        print(f"Wrote {equity_curve_path}")

    # Rolling stability check
    stability_script = ROOT / "scripts/rolling-stability-check.py"
    if stability_script.exists():
        stability_path = output_dir / "improvement-stability.csv"
        write_command_output(
            [sys.executable, str(stability_script), "--deposit", args.deposit, *map(str, reports)],
            stability_path,
            {0, 1},
        )
        print(f"Wrote {stability_path}")

    if evaluation_status == 2:
        print("No candidate passed the improvement gate yet.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
