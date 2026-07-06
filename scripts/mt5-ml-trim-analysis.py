#!/usr/bin/env python3
"""Offline ML-style trim analysis for GoldBot MT5 journals.

This is the first local-AI step: keep the trading EA deterministic, mine weak
trade pockets from real MT5 journals, and emit candidate trim rules to validate
with the Strategy Tester later. It can also export deal-level feature rows for
offline XGBoost/LightGBM training once GoldBot journals include feature snapshots.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence


FIELD_RE = re.compile(r"([A-Za-z][A-Za-z0-9_]*)=([^\s,]+)")
DEFAULT_GROUP = ("setup", "direction", "hour")
ML_FEATURE_FIELDS = (
    "direction",
    "hour",
    "scalp_variant",
    "confluences",
    "score_bucket",
    "spread",
    "spread_to_tp_pct",
    "adx",
    "di_gap",
    "atr",
    "atr_ratio",
    "ema21",
    "ema50",
    "vwap",
    "zone_width",
    "sl_distance",
    "lot_multiplier",
    "setup_risk_multiplier",
)


@dataclass(frozen=True)
class Deal:
    time: str
    setup: str
    direction: str
    hour: str
    scalp_variant: str
    confluences: str
    score_bucket: str
    profit: float
    spread: float = 0.0
    spread_to_tp_pct: float = 0.0
    adx: float = 0.0
    di_gap: float = 0.0
    atr: float = 0.0
    atr_ratio: float = 0.0
    ema21: float = 0.0
    ema50: float = 0.0
    vwap: float = 0.0
    zone_width: float = 0.0
    sl_distance: float = 0.0
    lot_multiplier: float = 0.0
    setup_risk_multiplier: float = 0.0

    @property
    def is_win(self) -> bool:
        return self.profit > 0.0


@dataclass(frozen=True)
class TrimRule:
    key: tuple[str, ...]
    trades: int
    net_profit: float
    gross_profit: float
    gross_loss: float
    profit_factor: float
    win_rate_pct: float
    saved_loss_if_trimmed: float


def parse_message_fields(message: str) -> dict[str, str]:
    return {match.group(1): match.group(2) for match in FIELD_RE.finditer(message)}


def as_float(value: str | None) -> float:
    try:
        return float(value or "0")
    except ValueError:
        return 0.0


def feature_float(fields: dict[str, str], name: str, fallback: float = 0.0) -> float:
    return as_float(fields.get(name)) if name in fields else fallback


def read_journal_rows(path: Path) -> list[tuple[str, str]]:
    rows: list[tuple[str, str]] = []
    with path.open(newline="", errors="ignore") as handle:
        sample = handle.read(4096)
        handle.seek(0)
        try:
            dialect = csv.Sniffer().sniff(sample, delimiters=",\t;")
        except csv.Error:
            dialect = csv.excel_tab
        reader = csv.reader(handle, dialect)
        for row in reader:
            if not row:
                continue
            if len(row) >= 2 and row[0].strip().lower() == "time":
                continue
            time_value = row[0].strip()
            message = " ".join(cell.strip() for cell in row[1:] if cell.strip())
            if message:
                rows.append((time_value, message))
    return rows


def parse_closed_deals(path: Path) -> list[Deal]:
    deals: list[Deal] = []
    for time_value, message in read_journal_rows(path):
        if "deal event" not in message.lower():
            continue
        fields = parse_message_fields(message)
        if fields.get("entry") not in {"1", "2", "3"}:
            continue
        zone_width = feature_float(fields, "zoneWidth")
        if zone_width == 0.0 and "zoneTop" in fields and "zoneBottom" in fields:
            zone_width = abs(as_float(fields.get("zoneTop")) - as_float(fields.get("zoneBottom")))
        deals.append(
            Deal(
                time=time_value,
                setup=fields.get("setup", "unknown"),
                direction=fields.get("dir", "unknown"),
                hour=fields.get("hour", "unknown"),
                scalp_variant=fields.get("scalpVariant", "unknown"),
                confluences=fields.get("confluences", "unknown").split("/", 1)[0],
                score_bucket=fields.get("scoreBucket", "unknown"),
                profit=as_float(fields.get("profit")),
                spread=feature_float(fields, "spread"),
                spread_to_tp_pct=feature_float(fields, "spreadToTpPct"),
                adx=feature_float(fields, "adx"),
                di_gap=feature_float(fields, "diGap"),
                atr=feature_float(fields, "atr"),
                atr_ratio=feature_float(fields, "atrRatio"),
                ema21=feature_float(fields, "ema21"),
                ema50=feature_float(fields, "ema50"),
                vwap=feature_float(fields, "vwap"),
                zone_width=zone_width,
                sl_distance=feature_float(fields, "slDistance"),
                lot_multiplier=feature_float(fields, "lotMultiplier"),
                setup_risk_multiplier=feature_float(fields, "setupRiskMultiplier"),
            )
        )
    return deals


def deal_value(deal: Deal, field: str) -> str:
    if field == "setup":
        return deal.setup
    if field == "direction":
        return deal.direction
    if field == "hour":
        return deal.hour
    if field == "scalp_variant":
        return deal.scalp_variant
    if field == "confluences":
        return deal.confluences
    if field == "score_bucket":
        return deal.score_bucket
    raise ValueError(f"Unsupported group field: {field}")


def profit_factor(gross_profit: float, gross_loss: float) -> float:
    if gross_loss < 0.0:
        return gross_profit / abs(gross_loss)
    return gross_profit if gross_profit > 0.0 else 0.0


def summarize_group(key: tuple[str, ...], profits: Sequence[float]) -> TrimRule:
    trades = len(profits)
    wins = sum(1 for profit in profits if profit > 0.0)
    gross_profit = sum(profit for profit in profits if profit > 0.0)
    gross_loss = sum(profit for profit in profits if profit < 0.0)
    net_profit = gross_profit + gross_loss
    return TrimRule(
        key=key,
        trades=trades,
        net_profit=round(net_profit, 2),
        gross_profit=round(gross_profit, 2),
        gross_loss=round(gross_loss, 2),
        profit_factor=round(profit_factor(gross_profit, gross_loss), 2),
        win_rate_pct=round((wins / trades * 100.0) if trades else 0.0, 2),
        saved_loss_if_trimmed=round(abs(net_profit), 2) if net_profit < 0.0 else 0.0,
    )


def mine_trim_rules(
    deals: Iterable[Deal],
    group_fields: Sequence[str] = DEFAULT_GROUP,
    min_trades: int = 5,
    max_pf: float = 1.0,
    max_net: float = 0.0,
    focus_setup: str = "",
) -> list[TrimRule]:
    groups: dict[tuple[str, ...], list[float]] = defaultdict(list)
    for deal in deals:
        if focus_setup and deal.setup != focus_setup:
            continue
        key = tuple(deal_value(deal, field) for field in group_fields)
        groups[key].append(deal.profit)

    rules: list[TrimRule] = []
    for key, profits in groups.items():
        if len(profits) < min_trades:
            continue
        row = summarize_group(key, profits)
        if row.net_profit <= max_net and row.profit_factor <= max_pf:
            rules.append(row)

    return sorted(rules, key=lambda row: (-row.saved_loss_if_trimmed, row.profit_factor, row.key))


def deals_to_ml_rows(deals: Iterable[Deal]) -> list[dict[str, str | int | float]]:
    rows: list[dict[str, str | int | float]] = []
    for deal in deals:
        rows.append(
            {
                "time": deal.time,
                "setup": deal.setup,
                "profit": deal.profit,
                "label_win": 1 if deal.is_win else 0,
                "direction": deal.direction,
                "hour": deal.hour,
                "scalp_variant": deal.scalp_variant,
                "confluences": deal.confluences,
                "score_bucket": deal.score_bucket,
                "spread": deal.spread,
                "spread_to_tp_pct": deal.spread_to_tp_pct,
                "adx": deal.adx,
                "di_gap": deal.di_gap,
                "atr": deal.atr,
                "atr_ratio": deal.atr_ratio,
                "ema21": deal.ema21,
                "ema50": deal.ema50,
                "vwap": deal.vwap,
                "zone_width": deal.zone_width,
                "sl_distance": deal.sl_distance,
                "lot_multiplier": deal.lot_multiplier,
                "setup_risk_multiplier": deal.setup_risk_multiplier,
            }
        )
    return rows


def optional_ml_backend_status() -> str:
    available: list[str] = []
    missing: list[str] = []
    for module_name in ("xgboost", "lightgbm", "sklearn"):
        try:
            __import__(module_name)
            available.append(module_name)
        except Exception:
            missing.append(module_name)
    if available:
        return "available:" + ",".join(available)
    return "unavailable:" + ",".join(missing)


def write_rules(rules: Sequence[TrimRule], group_fields: Sequence[str], output) -> None:
    fieldnames = [
        *group_fields,
        "trades",
        "net_profit",
        "gross_profit",
        "gross_loss",
        "profit_factor",
        "win_rate_pct",
        "saved_loss_if_trimmed",
    ]
    writer = csv.DictWriter(output, fieldnames=fieldnames)
    writer.writeheader()
    for rule in rules:
        row = {field: value for field, value in zip(group_fields, rule.key)}
        row.update(
            {
                "trades": rule.trades,
                "net_profit": f"{rule.net_profit:.2f}",
                "gross_profit": f"{rule.gross_profit:.2f}",
                "gross_loss": f"{rule.gross_loss:.2f}",
                "profit_factor": f"{rule.profit_factor:.2f}",
                "win_rate_pct": f"{rule.win_rate_pct:.2f}",
                "saved_loss_if_trimmed": f"{rule.saved_loss_if_trimmed:.2f}",
            }
        )
        writer.writerow(row)


def write_ml_rows(rows: Sequence[dict[str, str | int | float]], output) -> None:
    fieldnames = [
        "time",
        "setup",
        "profit",
        "label_win",
        *ML_FEATURE_FIELDS,
    ]
    writer = csv.DictWriter(output, fieldnames=fieldnames)
    writer.writeheader()
    for row in rows:
        writer.writerow(row)


def parse_group_fields(value: str) -> tuple[str, ...]:
    fields = tuple(part.strip() for part in value.split(",") if part.strip())
    if not fields:
        raise argparse.ArgumentTypeError("group must include at least one field")
    for field in fields:
        if field not in {"setup", "direction", "hour", "scalp_variant", "confluences", "score_bucket"}:
            raise argparse.ArgumentTypeError(f"unsupported group field: {field}")
    return fields


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("journals", nargs="+", type=Path, help="GoldBot *.trades.csv journal files")
    parser.add_argument("--group", type=parse_group_fields, default=DEFAULT_GROUP, help="Comma-separated group fields")
    parser.add_argument("--min-trades", type=int, default=5)
    parser.add_argument("--max-pf", type=float, default=1.0)
    parser.add_argument("--max-net", type=float, default=0.0)
    parser.add_argument("--focus-setup", default="", help="Only mine rules for this setup, e.g. m1_micro_scalp")
    parser.add_argument("--backend-status", action="store_true", help="Print optional ML backend availability to stderr")
    parser.add_argument("--ml-dataset", action="store_true", help="Write deal-level ML feature rows instead of trim rules")
    args = parser.parse_args()

    deals: list[Deal] = []
    missing = [str(path) for path in args.journals if not path.exists()]
    if missing:
        print("Missing journal(s): " + ", ".join(missing), file=sys.stderr)
        return 1
    for path in args.journals:
        deals.extend(parse_closed_deals(path))

    if args.backend_status:
        print("ml_backend=" + optional_ml_backend_status(), file=sys.stderr)

    if args.ml_dataset:
        write_ml_rows(deals_to_ml_rows(deals), sys.stdout)
        return 0

    rules = mine_trim_rules(
        deals,
        group_fields=args.group,
        min_trades=args.min_trades,
        max_pf=args.max_pf,
        max_net=args.max_net,
        focus_setup=args.focus_setup,
    )
    write_rules(rules, args.group, sys.stdout)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
