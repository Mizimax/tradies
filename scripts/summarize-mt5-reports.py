#!/usr/bin/env python3
"""Summarize MT5 Strategy Tester HTML reports for GoldBot candidate comparison."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from html import unescape
from pathlib import Path


METRICS = {
    "total_net_profit": "Total Net Profit:",
    "profit_factor": "Profit Factor:",
    "expected_payoff": "Expected Payoff:",
    "total_trades": "Total Trades:",
    "profit_trades": "Profit Trades (% of total):",
    "loss_trades": "Loss Trades (% of total):",
    "balance_dd": "Balance Drawdown Maximal:",
    "equity_dd": "Equity Drawdown Maximal:",
    "gross_profit": "Gross Profit:",
    "gross_loss": "Gross Loss:",
}


def decode_report(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")) or data.count(b"\x00") > 100:
        return data.decode("utf-16", errors="ignore")
    return data.decode("utf-8", errors="ignore")


def html_cells(report_text: str) -> list[str]:
    cells: list[str] = []
    for match in re.finditer(r"<td[^>]*>(.*?)</td>", report_text, flags=re.IGNORECASE | re.DOTALL):
        cell = re.sub(r"<[^>]+>", "", match.group(1))
        normalized = unescape(" ".join(cell.split()))
        if normalized:
            cells.append(normalized)
    return cells


def metric_after(cells: list[str], label: str) -> str:
    for index, value in enumerate(cells):
        if value == label and index + 1 < len(cells):
            return cells[index + 1]
    return ""


def parse_number(value: str) -> str:
    match = re.search(r"-?[\d ]+(?:\.\d+)?", value)
    if not match:
        return ""
    return match.group(0).replace(" ", "")


def parse_percent(value: str) -> str:
    match = re.search(r"\(([-\d.]+)%\)|([-\d.]+)%", value)
    if not match:
        return ""
    return match.group(1) or match.group(2)


def parse_count_percent(value: str) -> tuple[str, str]:
    count = parse_number(value)
    pct = parse_percent(value)
    return count, pct


def summarize(path: Path) -> dict[str, str]:
    cells = html_cells(decode_report(path))
    raw = {name: metric_after(cells, label) for name, label in METRICS.items()}
    profit_count, win_rate = parse_count_percent(raw["profit_trades"])
    loss_count, loss_rate = parse_count_percent(raw["loss_trades"])

    return {
        "report": path.name,
        "net_profit": parse_number(raw["total_net_profit"]),
        "profit_factor": parse_number(raw["profit_factor"]),
        "expected_payoff": parse_number(raw["expected_payoff"]),
        "total_trades": parse_number(raw["total_trades"]),
        "win_rate_pct": win_rate,
        "loss_rate_pct": loss_rate,
        "profit_trades": profit_count,
        "loss_trades": loss_count,
        "max_balance_drawdown_pct": parse_percent(raw["balance_dd"]),
        "max_equity_drawdown_pct": parse_percent(raw["equity_dd"]),
        "gross_profit": parse_number(raw["gross_profit"]),
        "gross_loss": parse_number(raw["gross_loss"]),
    }


def summarize_chain_manifest(path: Path) -> list[dict[str, str]]:
    try:
        manifest = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"invalid chain manifest {path}: {exc}") from exc
    if manifest.get("schema_version") != 1 or not isinstance(manifest.get("segments"), list):
        raise ValueError(f"unsupported chain manifest: {path}")

    rows: list[dict[str, str]] = []
    previous_end = ""
    for segment in manifest["segments"]:
        if not segment.get("valid") or not segment.get("flat") or not segment.get("report_fresh"):
            raise ValueError(f"chain manifest contains invalid/non-flat/stale segment: {path}")
        start, end = str(segment.get("start", "")), str(segment.get("end", ""))
        if previous_end and start <= previous_end:
            raise ValueError(f"chain manifest segments overlap or are unordered: {path}")
        previous_end = end
        report = Path(str(segment.get("report", "")))
        if not report.is_absolute():
            report = path.parent / report
        if not report.exists():
            raise ValueError(f"chain report missing: {report}")
        expected_hash = str(segment.get("report_sha256", ""))
        actual_hash = hashlib.sha256(report.read_bytes()).hexdigest()
        if not expected_hash or actual_hash != expected_hash:
            raise ValueError(f"chain report hash mismatch: {report}")
        rows.append(summarize(report))

    stitched = manifest.get("stitched")
    if not isinstance(stitched, dict):
        raise ValueError(f"stitched metrics missing: {path}")
    stitched_total_trades = stitched.get("total_trades")
    if stitched_total_trades is None:
        # Legacy manifests mislabeled Deals-table balance points (including one
        # deposit per segment) as trades. Segment reports remain authoritative.
        stitched_total_trades = sum(int(row["total_trades"] or 0) for row in rows)
    rows.append(
        {
            "report": f"{manifest.get('chain_name', path.stem)}::stitched",
            "net_profit": str(stitched.get("net_profit", "")),
            "profit_factor": str(stitched.get("profit_factor", "")),
            "expected_payoff": "",
            "total_trades": str(stitched_total_trades),
            "win_rate_pct": "",
            "loss_rate_pct": "",
            "profit_trades": "",
            "loss_trades": "",
            "max_balance_drawdown_pct": str(stitched.get("stitched_equity_drawdown_pct", "")),
            "max_equity_drawdown_pct": str(stitched.get("stitched_equity_drawdown_pct", "")),
            "gross_profit": str(stitched.get("gross_profit", "")),
            "gross_loss": str(stitched.get("gross_loss", "")),
        }
    )
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="*", type=Path, help="MT5 HTML report paths")
    parser.add_argument("--chain-manifest", action="append", default=[], type=Path, help="FundingPips chain manifest JSON")
    args = parser.parse_args()

    rows = [summarize(path) for path in args.reports if path.exists()]
    try:
        for manifest in args.chain_manifest:
            rows.extend(summarize_chain_manifest(manifest))
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    if not rows:
        print("No readable reports found.", file=sys.stderr)
        return 1

    writer = csv.DictWriter(sys.stdout, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
