#!/usr/bin/env python3
"""Re-run the frozen hour-10 cohort analysis without repeating MT5 chains."""

from __future__ import annotations

import importlib.util
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STUDY = ROOT / "scripts/analyze-fundingpips-cohort-suppression.py"
REPORT_DIR = ROOT / "mt5/backtests/reports"
DEFAULT_PREFIX = "GoldBot-fundingpips-m1-short-hour10-shadow"


class RerunError(RuntimeError):
    """Raised when the committed study cannot be loaded safely."""


def load_study():
    spec = importlib.util.spec_from_file_location(
        "fundingpips_cohort_suppression_study", STUDY
    )
    if spec is None or spec.loader is None:
        raise RerunError(f"cannot load {STUDY}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    study = load_study()

    # The generic reader intentionally returns (timestamp, message) pairs, while
    # _position_cohorts requires (segment, timestamp, message) triples to keep
    # MT5 position IDs distinct across stitched tester processes. Use the
    # stricter continuation-manifest loader, which also verifies report/journal
    # hashes and returns segment-qualified rows.
    def strict_chain_reader(path: Path):
        manifest, rows = study.A._load_continuation_manifest(path)
        chain_name = str(manifest.get("chain_name", path.stem))
        return chain_name, rows

    study.A.read_chain_manifest = strict_chain_reader

    prefix = os.environ.get("PREFIX", DEFAULT_PREFIX)
    output_prefix = REPORT_DIR / f"{prefix}-study"
    manifests = {
        "train-h1": REPORT_DIR / f"{prefix}-train-h1-2025.manifest.json",
        "train-h2": REPORT_DIR / f"{prefix}-train-h2-2025.manifest.json",
        "validation-h1": REPORT_DIR / f"{prefix}-validation-h1-2024.manifest.json",
        "validation-h2": REPORT_DIR / f"{prefix}-validation-h2-2024.manifest.json",
    }
    missing = [str(path) for path in manifests.values() if not path.is_file()]
    if missing:
        print("Analysis rerun FAILED: required manifests are missing:", file=sys.stderr)
        for path in missing:
            print(f"- {path}", file=sys.stderr)
        return 2

    sys.argv = [
        str(STUDY),
        "--train-h1",
        str(manifests["train-h1"]),
        "--train-h2",
        str(manifests["train-h2"]),
        "--validation-h1",
        str(manifests["validation-h1"]),
        "--validation-h2",
        str(manifests["validation-h2"]),
        "--output-prefix",
        str(output_prefix),
    ]
    print("Reusing the 24 completed MT5 segments; no tester run will be repeated.")
    status = int(study.main())
    if status == 0:
        print("PASS: candidate may proceed only to a reviewed tester-only shadow gate.")
    elif status == 3:
        print("FALSIFIED: retire the m1 short hour-10 suppression hypothesis.")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
