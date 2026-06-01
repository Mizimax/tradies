#!/usr/bin/env python3
"""Summarize MT5 Strategy Tester HTML reports for GoldBot candidate comparison."""

from __future__ import annotations

import argparse
import csv
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="+", type=Path, help="MT5 HTML report paths")
    args = parser.parse_args()

    rows = [summarize(path) for path in args.reports if path.exists()]
    if not rows:
        print("No readable reports found.", file=sys.stderr)
        return 1

    writer = csv.DictWriter(sys.stdout, fieldnames=list(rows[0].keys()))
    writer.writeheader()
    writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
