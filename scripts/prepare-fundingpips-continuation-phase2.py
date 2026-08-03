#!/usr/bin/env python3
"""Derive the frozen Phase-2 continuation preset after Stage C2 passes."""

from __future__ import annotations

import argparse
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mt5/Presets/GoldBot/prop-fundingpips-2step-phase2.set"
DEFAULT_OUTPUT = ROOT / "mt5/Presets/GoldBot/prop-fundingpips-2step-phase2-continuation-core.set"
FROZEN = {
    "InpEnableContinuationPullbackSetup": "true",
    "InpContinuationLongHours": "7;12;18",
    "InpContinuationShortHours": "99",
}


def effective_inputs(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line_number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith(";"):
            continue
        if "=" not in line:
            raise ValueError(f"malformed preset line {line_number}")
        key, value = line.split("=", 1)
        if key in result:
            raise ValueError(f"duplicate preset input: {key}")
        result[key] = value
    return result


def derive(source: Path, output: Path) -> None:
    source_text = source.read_text()
    source_inputs = effective_inputs(source_text)
    if source_inputs.get("InpPropPhaseTargetPct") != "5.0":
        raise ValueError("Phase-2 canonical preset target is not 5.0%")
    missing = sorted(set(FROZEN) - source_inputs.keys())
    if missing:
        raise ValueError(f"Phase-2 canonical preset is missing: {', '.join(missing)}")

    lines: list[str] = []
    for raw in source_text.splitlines():
        stripped = raw.strip()
        if "=" in stripped and not stripped.startswith(";"):
            key = stripped.split("=", 1)[0]
            if key in FROZEN:
                raw = f"{key}={FROZEN[key]}"
        lines.append(raw)
    derived_text = "\n".join(lines) + "\n"
    derived_inputs = effective_inputs(derived_text)
    changed = {
        key: value
        for key, value in derived_inputs.items()
        if source_inputs.get(key) != value
    }
    if set(source_inputs) != set(derived_inputs) or changed != FROZEN:
        raise ValueError(f"Phase-2 derived preset escaped frozen diff: {changed}")
    if output.exists() and output.read_text() != derived_text:
        raise ValueError(f"refusing to overwrite different preset: {output}")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(derived_text)
    print(output)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    try:
        derive(args.source, args.output)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
