#!/usr/bin/env python3
"""Extract black-box behavior evidence from C+ MT5 HTML reports."""

from __future__ import annotations

import argparse
import csv
import html.parser
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path


DATETIME_FMT = "%Y.%m.%d %H:%M:%S"


def decode_report(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith(b"\xff\xfe") or data[:200].count(b"\x00") > 50:
        return data.decode("utf-16", errors="ignore")
    return data.decode("utf-8", errors="ignore")


class RowParser(html.parser.HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self._cell: list[str] | None = None
        self._row: list[str] = []
        self.rows: list[list[str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() in {"td", "th"}:
            self._cell = []

    def handle_data(self, data: str) -> None:
        if self._cell is not None:
            self._cell.append(data)

    def handle_endtag(self, tag: str) -> None:
        tag = tag.lower()
        if tag in {"td", "th"} and self._cell is not None:
            self._row.append(" ".join("".join(self._cell).split()))
            self._cell = None
        elif tag == "tr":
            if self._row:
                self.rows.append(self._row)
            self._row = []


@dataclass
class ReportTables:
    orders: list[dict[str, str]]
    deals: list[dict[str, str]]


def clean_number(value: str) -> float:
    value = value.replace(" ", "").replace(",", "")
    if not value:
        return 0.0
    return float(value)


def parse_rows(report: Path) -> ReportTables:
    parser = RowParser()
    parser.feed(decode_report(report))

    orders: list[dict[str, str]] = []
    deals: list[dict[str, str]] = []
    section = ""

    for row in parser.rows:
        joined = " ".join(row)
        if "Orders" == joined:
            section = "orders"
            continue
        if "Deals" == joined:
            section = "deals"
            continue
        if not row or not re.match(r"^\d{4}\.\d{2}\.\d{2} \d{2}:\d{2}:\d{2}$", row[0]):
            continue

        if section == "orders" and len(row) >= 11:
            orders.append(
                {
                    "open_time": row[0],
                    "order": row[1],
                    "symbol": row[2],
                    "type": row[3],
                    "volume": row[4].split("/")[0].strip(),
                    "price": row[5],
                    "sl": row[6],
                    "tp": row[7],
                    "time": row[8],
                    "state": row[9],
                    "comment": row[10] if len(row) == 11 else row[-1],
                }
            )
        elif section == "deals" and len(row) >= 13:
            deals.append(
                {
                    "time": row[0],
                    "deal": row[1],
                    "symbol": row[2],
                    "type": row[3],
                    "direction": row[4],
                    "volume": row[5],
                    "price": row[6],
                    "order": row[7],
                    "commission": row[8],
                    "swap": row[9],
                    "profit": row[10],
                    "balance": row[11],
                    "comment": row[12],
                }
            )

    return ReportTables(orders=orders, deals=deals)


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    if not rows:
        return
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def summarize(report_name: str, tables: ReportTables) -> str:
    trade_deals = [d for d in tables.deals if d["direction"] in {"in", "out"}]
    entry_deals = [d for d in trade_deals if d["direction"] == "in"]
    exit_deals = [d for d in trade_deals if d["direction"] == "out"]
    exit_profit = [clean_number(d["profit"]) for d in exit_deals]
    entry_times = [datetime.strptime(d["time"], DATETIME_FMT) for d in entry_deals]
    exit_times = [datetime.strptime(d["time"], DATETIME_FMT) for d in exit_deals]

    by_type = Counter(d["type"] for d in entry_deals)
    lots = Counter(d["volume"] for d in entry_deals)
    comments = Counter(d["comment"] for d in trade_deals)
    entry_hours = Counter(t.hour for t in entry_times)
    simultaneous = Counter(d["time"] for d in trade_deals)
    basket_like = [(time, count) for time, count in simultaneous.items() if count >= 3]

    exit_wins = sum(1 for p in exit_profit if p > 0)
    exit_losses = sum(1 for p in exit_profit if p < 0)
    avg_win = sum(p for p in exit_profit if p > 0) / exit_wins if exit_wins else 0.0
    avg_loss = sum(p for p in exit_profit if p < 0) / exit_losses if exit_losses else 0.0
    total_pnl = sum(exit_profit)

    gaps: list[float] = []
    for prev, cur in zip(entry_times, entry_times[1:]):
        gaps.append((cur - prev).total_seconds() / 60.0)
    avg_gap = sum(gaps) / len(gaps) if gaps else 0.0

    lines = [
        f"# C+ Behavior Profile: {report_name}",
        "",
        "## Extracted Evidence",
        f"- orders: {len(tables.orders)}",
        f"- trade deals: {len(trade_deals)}",
        f"- entry deals: {len(entry_deals)}",
        f"- exit deals: {len(exit_deals)}",
        f"- exit pnl from deal table: {total_pnl:.2f}",
        f"- exit wins/losses: {exit_wins}/{exit_losses}",
        f"- average win/loss: {avg_win:.2f}/{avg_loss:.2f}",
        f"- average minutes between entries: {avg_gap:.1f}",
        "",
        "## Entry Shape",
        f"- direction mix: {dict(by_type)}",
        f"- lots used: {dict(sorted(lots.items(), key=lambda kv: clean_number(kv[0])))}",
        f"- busiest entry hours: {dict(entry_hours.most_common(8))}",
        "",
        "## Comments",
        f"- top comments: {dict(comments.most_common(10))}",
        "",
        "## Basket/Cluster Clues",
        f"- timestamps with >=3 trade deals: {len(basket_like)}",
    ]
    for time, count in basket_like[:12]:
        lines.append(f"- {time}: {count} trade deals")
    lines.extend(
        [
            "",
            "## Inferred Clone Targets",
            "- entry signal must allow both buy and sell on the same day, often alternating quickly",
            "- base lot is 0.01 and ladder expansion reaches 0.02 in these samples",
            "- many exits are broker-side/EA-modified stop comments, but profitable closes imply trailing or synthetic basket exit behavior",
            "- simultaneous multi-deal timestamps are important; our clone needs basket close and immediate re-entry handling",
        ]
    )
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("reports", nargs="+", type=Path)
    ap.add_argument("--out-dir", type=Path, default=Path("mt5/backtests/cplus-behavior"))
    args = ap.parse_args()

    args.out_dir.mkdir(parents=True, exist_ok=True)
    for report in args.reports:
        tables = parse_rows(report)
        stem = report.stem
        write_csv(args.out_dir / f"{stem}.orders.csv", tables.orders)
        write_csv(args.out_dir / f"{stem}.deals.csv", tables.deals)
        (args.out_dir / f"{stem}.profile.md").write_text(
            summarize(report.name, tables),
            encoding="utf-8",
        )
        print(f"{report.name}: orders={len(tables.orders)} deals={len(tables.deals)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
