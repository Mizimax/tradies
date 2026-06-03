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
    "growth-fasttp-hours12-15-16-19-full",
    "growth-fasttp-hours12-15-16-19-split12",
    "growth-fasttp-hours12-15-16-17-19-full",
    "growth-fasttp-hours12-15-16-17-19-split12",
    "growth-fasttp-dir-long12-15-16-short19-full",
    "growth-fasttp-dir-long12-15-16-short19-split12",
]


def load_candidate_names(matrix: Path) -> set[str]:
    with matrix.open(newline="") as handle:
        return {row["name"].strip() for row in csv.DictReader(handle)}


def report_path(candidate: str) -> Path:
    return ROOT / "mt5/backtests/reports" / f"GoldBot-real-{candidate}.htm"


def journal_path(candidate: str) -> Path:
    return ROOT / "mt5/backtests/reports" / f"GoldBot-real-{candidate}.trades.csv"


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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidates", nargs="*", help="Candidate names to run. Defaults to Phase 3B/3C + growth candidates.")
    parser.add_argument("--matrix", type=Path, default=ROOT / "mt5/backtests/CANDIDATE_MATRIX.csv")
    parser.add_argument("--from-date", default="2024.06.01")
    parser.add_argument("--to-date", default="2026.05.31")
    parser.add_argument("--deposit", default="100000")
    parser.add_argument("--symbol", default="")
    parser.add_argument("--period", default="")
    parser.add_argument("--skip-existing", action="store_true", help="Skip candidates whose HTML report already exists.")
    parser.add_argument("--clean", action="store_true", help="Delete selected candidate reports before running.")
    parser.add_argument("--dry-run", action="store_true", help="Print candidate commands without launching MT5.")
    parser.add_argument("--continue-on-fail", action="store_true", help="Continue suite if one MT5 run fails.")
    parser.add_argument("--growth-only", action="store_true", help="Run only growth Layer 1 candidates.")
    parser.add_argument("--layer2", action="store_true", help="Include Layer 2 risk-scaled candidates.")
    args = parser.parse_args()

    known = load_candidate_names(args.matrix)
    if args.growth_only:
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
            for path in (report_path(candidate), journal_path(candidate), report_path(candidate).with_suffix(".xml")):
                path.unlink(missing_ok=True)

    for candidate in candidates:
        if args.skip_existing and report_path(candidate).exists():
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

    reports = [report_path(candidate) for candidate in candidates if report_path(candidate).exists()]
    journals = [journal_path(candidate) for candidate in candidates if journal_path(candidate).exists()]
    if not reports:
        print("No candidate reports found after suite run.", file=sys.stderr)
        return 1

    output_dir = ROOT / "mt5/backtests/reports"
    output_dir.mkdir(parents=True, exist_ok=True)
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
