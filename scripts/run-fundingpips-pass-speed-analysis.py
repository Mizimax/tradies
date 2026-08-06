#!/usr/bin/env python3
"""Run the FundingPips 30/60-day pass-speed diagnostic from completed chains."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT_DIR = ROOT / "mt5/backtests/reports"
ANALYZER = ROOT / "scripts/analyze-fundingpips-pass-speed.py"

DEFAULT_MANIFESTS = (
    ("h1-2024", "GoldBot-fundingpips-m1-short-hour10-shadow-validation-h1-2024.manifest.json"),
    ("h2-2024", "GoldBot-fundingpips-m1-short-hour10-shadow-validation-h2-2024.manifest.json"),
    ("h1-2025", "GoldBot-fundingpips-m1-short-hour10-shadow-train-h1-2025.manifest.json"),
    ("h2-2025", "GoldBot-fundingpips-m1-short-hour10-shadow-train-h2-2025.manifest.json"),
    ("h1-2026", "GoldBot-fundingpips-p1-h1-2026-negative-window-control.manifest.json"),
)


def main() -> int:
    output_name = os.environ.get(
        "OUTPUT_PREFIX", "GoldBot-fundingpips-pass-speed"
    )
    output_prefix = REPORT_DIR / output_name
    command = [
        sys.executable,
        str(ANALYZER),
        "--initial-balance",
        os.environ.get("INITIAL_BALANCE", "50000"),
        "--target-pct",
        os.environ.get("TARGET_PCT", "8"),
    ]
    missing: list[Path] = []
    for label, filename in DEFAULT_MANIFESTS:
        path = REPORT_DIR / filename
        if not path.is_file():
            missing.append(path)
        else:
            command.extend(["--window", label, str(path)])
    command.extend(["--output-prefix", str(output_prefix)])

    if missing:
        print("Pass-speed diagnostic FAILED: required manifests are missing:", file=sys.stderr)
        for path in missing:
            print(f"- {path}", file=sys.stderr)
        return 2

    print("Reusing completed 2024, 2025, and H1 2026 chains; no MT5 run will occur.")
    return subprocess.run(command, cwd=ROOT, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
