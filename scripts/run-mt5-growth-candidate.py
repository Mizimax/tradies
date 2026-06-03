#!/usr/bin/env python3
"""Run one GoldBot growth candidate and refresh growth analysis artifacts."""

from __future__ import annotations

import argparse
import csv
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "mt5/backtests/reports"
MATRIX = ROOT / "mt5/backtests/CANDIDATE_MATRIX.csv"
LAYER1 = [
    "growth-long-7-12-full",
    "growth-long-7-12-ladder23",
    "growth-long-7-12-19-ladder23",
    "growth-dir-long7-12-short19-full",
    "growth-open-cooldown8",
    "growth-open-fasttp",
]
LAYER2 = [
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


def load_candidates() -> dict[str, dict[str, str]]:
    with MATRIX.open(newline="") as handle:
        return {row["name"].strip(): row for row in csv.DictReader(handle)}


def run(command: list[str], *, allow: set[int] = {0}) -> int:
    result = subprocess.run(command, cwd=ROOT, check=False)
    if result.returncode not in allow:
        return result.returncode
    return 0


def write_output(command: list[str], output_path: Path, *, allow: set[int] = {0}) -> int:
    result = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    output_path.write_text(result.stdout or "")
    if result.returncode not in allow:
        sys.stderr.write(result.stdout or "")
        return result.returncode
    return 0


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
    result = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode not in (0, 1, 2):
        return {}
    return csv_first_row(result.stdout or "")


def as_int(value: str) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return 0


def active_mt5_processes() -> list[str]:
    result = subprocess.run(
        ["ps", "ax", "-o", "pid=,args="],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    processes: list[str] = []
    for line in (result.stdout or "").splitlines():
        lower = line.lower()
        if "terminal64.exe" in lower or "metatester64.exe" in lower:
            processes.append(line.strip())
    return processes


def write_report_status(candidate: str, artifact_mode: str, reason: str, report: Path, journal: Path) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    path = REPORT_DIR / f"GoldBot-real-{candidate}.report-status.csv"
    with path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["candidate", "artifact_mode", "reason", "report", "journal"])
        writer.writeheader()
        writer.writerow({
            "candidate": candidate,
            "artifact_mode": artifact_mode,
            "reason": reason,
            "report": report.name,
            "journal": journal.name if journal.exists() else "",
        })


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


def report_path(candidate: str) -> Path:
    return REPORT_DIR / f"GoldBot-real-{candidate}.htm"


def journal_path(candidate: str) -> Path:
    return REPORT_DIR / f"GoldBot-real-{candidate}.trades.csv"


def write_journal_only_artifacts(candidate: str, report: Path, journal: Path, reason: str) -> int:
    status = 0
    status |= write_output(
        [sys.executable, "scripts/analyze-mt5-trades.py", str(journal)],
        REPORT_DIR / f"GoldBot-real-{candidate}.journal-summary.csv",
    )
    status |= write_output(
        [sys.executable, "scripts/analyze-mt5-trades.py", "--attribution", str(journal)],
        REPORT_DIR / f"GoldBot-real-{candidate}.attribution.csv",
        allow={0, 1},
    )
    write_report_status(candidate, "journal-only", reason, report, journal)
    print(f"Wrote journal-only artifacts for {candidate} in {REPORT_DIR}")
    return status or 1


def refresh_artifacts(candidate: str, deposit: str, from_date: str, to_date: str) -> int:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    report = report_path(candidate)
    journal = journal_path(candidate)
    if not report.exists():
        print(f"Missing report after run: {report}", file=sys.stderr)
        if journal.exists():
            print(f"Report is missing, but journal exists: {journal}", file=sys.stderr)
            return write_journal_only_artifacts(candidate, report, journal, "missing-report")
        return 1

    if report_is_malformed(report, journal):
        print(f"Malformed report after run: {report}", file=sys.stderr)
        print(f"Journal exists and has deals: {journal}", file=sys.stderr)
        return write_journal_only_artifacts(candidate, report, journal, "malformed-report")

    status = 0
    status |= write_output(
        [sys.executable, "scripts/summarize-mt5-reports.py", str(report)],
        REPORT_DIR / f"GoldBot-real-{candidate}.summary.csv",
    )
    status |= write_output(
        [
            sys.executable, "scripts/evaluate-mt5-candidates.py",
            "--deposit", deposit,
            "--from-date", from_date,
            "--to-date", to_date,
            str(report),
        ],
        REPORT_DIR / f"GoldBot-real-{candidate}.evaluation.csv",
        allow={0, 2},
    )
    status |= write_output(
        [
            sys.executable, "scripts/daily-growth-report.py",
            "--deposit", deposit,
            "--from-date", from_date,
            "--to-date", to_date,
            str(report),
        ],
        REPORT_DIR / f"GoldBot-real-{candidate}.daily-growth.csv",
        allow={0, 1},
    )
    status |= write_output(
        [sys.executable, "scripts/equity-curve-analysis.py", "--deposit", deposit, str(report)],
        REPORT_DIR / f"GoldBot-real-{candidate}.equity-curve.csv",
        allow={0, 1},
    )
    status |= write_output(
        [sys.executable, "scripts/rolling-stability-check.py", "--deposit", deposit, str(report)],
        REPORT_DIR / f"GoldBot-real-{candidate}.stability.csv",
        allow={0, 1},
    )
    if journal.exists():
        status |= write_output(
            [sys.executable, "scripts/analyze-mt5-trades.py", str(journal)],
            REPORT_DIR / f"GoldBot-real-{candidate}.journal-summary.csv",
        )
        status |= write_output(
            [sys.executable, "scripts/analyze-mt5-trades.py", "--attribution", str(journal)],
            REPORT_DIR / f"GoldBot-real-{candidate}.attribution.csv",
            allow={0, 1},
        )

    print(f"Wrote per-candidate artifacts for {candidate} in {REPORT_DIR}")
    return status


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", nargs="?", help="One growth candidate name.")
    parser.add_argument("--from-date", default="2024.06.01")
    parser.add_argument("--to-date", default="2026.05.31")
    parser.add_argument("--deposit", default="100000")
    parser.add_argument("--symbol", default="")
    parser.add_argument("--period", default="")
    parser.add_argument("--clean", action="store_true", help="Delete this candidate's report artifacts before running.")
    parser.add_argument("--dry-run", action="store_true", help="Print the underlying command without launching MT5.")
    parser.add_argument("--list", action="store_true", help="List growth candidates.")
    parser.add_argument("--allow-parallel-mt5", action="store_true", help="Allow running even when MT5 tester processes are active.")
    args = parser.parse_args()

    candidates = load_candidates()
    growth_candidates = LAYER1 + LAYER2

    if args.list:
        for name in growth_candidates:
            description = candidates.get(name, {}).get("description", "")
            print(f"{name}: {description}")
        return 0

    if not args.candidate:
        print("Candidate name is required unless --list is used.", file=sys.stderr)
        return 2
    if args.candidate not in growth_candidates:
        print(f"Not a known growth candidate: {args.candidate}", file=sys.stderr)
        print("Run with --list to see valid growth candidates.", file=sys.stderr)
        return 2
    if args.candidate not in candidates:
        print(f"Candidate is missing from matrix: {args.candidate}", file=sys.stderr)
        return 2

    if not args.dry_run and not args.allow_parallel_mt5:
        active = active_mt5_processes()
        if active:
            print("MT5 tester/terminal process is already running. Stop it first, or pass --allow-parallel-mt5.", file=sys.stderr)
            for process in active:
                print(f"  {process}", file=sys.stderr)
            return 3

    if args.clean:
        for suffix in (".htm", ".xml", ".trades.csv", ".summary.csv", ".evaluation.csv", ".daily-growth.csv", ".equity-curve.csv", ".stability.csv", ".journal-summary.csv", ".attribution.csv", ".report-status.csv"):
            (REPORT_DIR / f"GoldBot-real-{args.candidate}{suffix}").unlink(missing_ok=True)

    command = [
        sys.executable,
        "scripts/run-mt5-candidate.py",
        args.candidate,
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

    status = run(command)
    if status != 0 or args.dry_run:
        return status
    return refresh_artifacts(args.candidate, args.deposit, args.from_date, args.to_date)


if __name__ == "__main__":
    raise SystemExit(main())
