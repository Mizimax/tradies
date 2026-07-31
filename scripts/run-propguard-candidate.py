#!/usr/bin/env python3
"""Run one PropGuard MT5 candidate from the candidate matrix, with report-integrity
validation (design gate G2 in mt5/backtests/PROPGUARD_DESIGN.md).

Unlike the looser BTCScalper/GoldBot runners, this script refuses to call the result
usable unless the exported report actually reflects the candidate that was requested:
the Expert name matches, every override key=value pair is literally present in the
report's Inputs: block, and the report is not malformed (0 trades / 1970 period / zero
deposit). This mirrors the discipline in scripts/run-qbr-candidate.py, the strictest
runner in the repo, scaled down to PropGuard's simpler (CSV-matrix, no evidence-lineage)
candidate model.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "mt5/backtests/reports"
CONFIG_DIR = ROOT / "mt5/backtests/config"
DEFAULT_MATRIX = ROOT / "mt5/backtests/PROPGUARD_CANDIDATES.csv"


def load_candidates(matrix: Path) -> list[dict[str, str]]:
    with matrix.open(newline="") as handle:
        return list(csv.DictReader(handle))


def find_candidate(rows: list[dict[str, str]], name: str) -> dict[str, str] | None:
    for row in rows:
        if row["name"].strip() == name:
            return row
    return None


def expand_overrides(rows: list[dict[str, str]], name: str, seen: set[str] | None = None) -> str:
    """Resolves an `@base-candidate` inheritance chain, matching the CANDIDATE_MATRIX.csv
    convention used by run-mt5-candidate.py (first line `@base` splices the base's expanded
    overrides in first; child lines win on conflicting keys via simple textual override)."""
    if seen is None:
        seen = set()
    if name in seen:
        raise ValueError(f"Cycle detected while expanding candidate overrides: {name}")
    seen.add(name)

    candidate = find_candidate(rows, name)
    if candidate is None:
        raise ValueError(f"Unknown base candidate: {name}")

    raw = candidate["overrides"].replace("\\n", "\n").strip()
    lines = raw.splitlines()
    if lines and lines[0].startswith("@"):
        base_name = lines[0][1:].strip()
        base_overrides = expand_overrides(rows, base_name, seen)
        return base_overrides.rstrip("\n") + "\n" + "\n".join(lines[1:])
    return raw


def shell_command(env: dict[str, str]) -> str:
    parts = [f"{key}={shlex.quote(value)}" for key, value in env.items()]
    parts.append("bash scripts/run-mt5-backtest.sh")
    return " ".join(parts)


def clean_artifacts(report_name: str) -> None:
    for suffix in (
        ".htm",
        ".xml",
        ".trades.csv",
        ".summary.csv",
        ".evaluation.csv",
        ".daily-growth.csv",
        ".equity-curve.csv",
        ".stability.csv",
        ".journal-summary.csv",
        ".attribution.csv",
        ".report-status.csv",
    ):
        (REPORT_DIR / f"{report_name}{suffix}").unlink(missing_ok=True)
    (CONFIG_DIR / f"{report_name}.run-stamp").unlink(missing_ok=True)


def decode_report(path: Path) -> str:
    data = path.read_bytes()
    for encoding in ("utf-16", "utf-8"):
        try:
            return data.decode(encoding, errors="ignore")
        except Exception:
            continue
    return data.decode("latin-1", errors="ignore")


def strip_tags(html: str) -> str:
    return re.sub(r"<[^>]+>", " ", html)


def validate_report(report_path: Path, overrides_text: str, symbol: str) -> list[str]:
    """Gate G2. Returns a list of problems; empty means the report is trustworthy."""
    problems: list[str] = []
    if not report_path.exists():
        return [f"report not found: {report_path}"]

    text = strip_tags(decode_report(report_path))
    # MT5's exported HTML puts substantial whitespace/newlines between a field's label and
    # its value once tags are stripped (e.g. "Expert: \r\n        PropGuard"), so every check
    # below must tolerate arbitrary \s* between label and value -- a literal substring check
    # silently never matches and turns gate G2 into a no-op.

    if not re.search(r"Expert:\s*PropGuard\b", text):
        problems.append("report does not identify Expert=PropGuard")

    if re.search(r"Period:\s*M0\b", text) or "1970.01.01" in text:
        problems.append("malformed report: Period M0 / 1970 epoch")

    if re.search(r"Initial Deposit:\s*0\b", text):
        problems.append("malformed report: Initial Deposit is 0")

    if re.search(r"Total Trades:\s*0\b", text):
        problems.append("malformed report: Total Trades is 0")

    inputs_match = re.search(r"Inputs:(.*?)(?:Result|$)", text, re.S)
    inputs_block = inputs_match.group(1) if inputs_match else text
    normalized_inputs = re.sub(r"\s+", "", inputs_block)

    for line in overrides_text.splitlines():
        line = line.strip()
        if not line or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        needle = re.sub(r"\s+", "", f"{key}={value}")
        if needle not in normalized_inputs:
            problems.append(f"override not found in report Inputs: block: {key}={value}")

    if symbol not in text:
        problems.append(f"report does not mention requested symbol {symbol}")

    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", nargs="?", help="Candidate name from the matrix")
    parser.add_argument("--matrix", type=Path, default=DEFAULT_MATRIX)
    parser.add_argument("--from-date", default="2026.01.01")
    parser.add_argument("--to-date", default="2026.06.30")
    parser.add_argument("--deposit", default="100000")
    parser.add_argument("--symbol", default="XAUUSD")
    parser.add_argument("--period", default="M15")
    parser.add_argument("--report-suffix", default="", help="Append a suffix to the MT5 report name")
    parser.add_argument("--spread-points", type=float, default=0.0,
                         help="InpStressExtraSpreadPrice cost-stress override (PROPGUARD_DESIGN.md §6)")
    parser.add_argument("--clean", action="store_true", help="Delete this candidate's report artifacts before running")
    parser.add_argument("--dry-run", action="store_true", help="Print the command without running MT5")
    parser.add_argument("--list", action="store_true", help="List available candidates")
    parser.add_argument("--skip-validation", action="store_true",
                         help="Skip gate-G2 report validation (debugging only)")
    args = parser.parse_args()

    rows = load_candidates(args.matrix)
    if args.list:
        for row in rows:
            print(f"{row['name']}: {row['description']}")
        return 0

    if not args.candidate:
        print("Candidate name is required unless --list is used.", file=sys.stderr)
        return 2

    candidate = find_candidate(rows, args.candidate)
    if candidate is None:
        print(f"Unknown candidate: {args.candidate}", file=sys.stderr)
        print("Available candidates:", file=sys.stderr)
        for row in rows:
            print(f"  {row['name']}", file=sys.stderr)
        return 2

    try:
        overrides_text = expand_overrides(rows, args.candidate)
    except ValueError as exc:
        print(f"Error expanding overrides: {exc}", file=sys.stderr)
        return 2

    if args.spread_points > 0.0:
        overrides_text = overrides_text.rstrip("\n") + f"\nInpStressExtraSpreadPrice={args.spread_points}"

    report_name = f"PropGuard-{candidate['name'].strip()}"
    if args.report_suffix:
        report_name = f"{report_name}-{args.report_suffix.strip()}"

    env = {
        "MT5_DEPOSIT": args.deposit,
        "MT5_FROM": args.from_date,
        "MT5_TO": args.to_date,
        "MT5_REPORT": report_name,
        "MT5_INPUT_OVERRIDES": overrides_text,
        "MT5_EXPERT": "PropGuard\\PropGuard.ex5",
        "MT5_PRESET": "PropGuard/ftmo-2step-p1.set",
        "MT5_PERIOD": args.period,
        "MT5_SYMBOL": args.symbol,
    }

    print(f"# {candidate['name']}: {candidate['description']}")
    print(shell_command(env))
    if args.clean:
        clean_artifacts(report_name)
    if args.dry_run:
        return 0

    run_env = os.environ.copy()
    run_env.update(env)
    rc = subprocess.call(["bash", "scripts/run-mt5-backtest.sh"], cwd=ROOT, env=run_env)
    if rc != 0:
        return rc

    if args.skip_validation:
        return 0

    report_path = REPORT_DIR / f"{report_name}.htm"
    problems = validate_report(report_path, overrides_text, args.symbol)
    if problems:
        print("Gate G2 (report integrity) FAILED:", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        return 3

    print(f"Gate G2 (report integrity) passed: {report_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
