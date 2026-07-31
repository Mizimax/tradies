#!/usr/bin/env python3
"""Adapt a GoldBot MT5 Strategy Tester HTML report into a PropGuard-shaped trades
journal so ``prop-challenge-simulator.py`` can estimate P(pass a prop-firm challenge)
for a GoldBot candidate, without any GoldBot EA code changes.

This is a go/no-go *simulation* gate, run before any prop-mode risk controls are
built into GoldBot: if scaled-down GoldBot r-multiples can't clear the simulator's
pass bar even in this idealized replay, there is no point building the real thing.

Method
------
1. Reuse ``equity-curve-analysis.py``'s HTML deal-table parser (``extract_deals``)
   to get GoldBot's ordered closed trades (direction == "out") from the report --
   do not reimplement HTML parsing here.
2. Reconstruct the running account equity immediately BEFORE each trade opened:
   starting from the report's stated Initial Deposit, walking forward through
   prior closes in chronological order.
3. Compute ``r_multiple = (profit + commission + swap) / equity_at_entry`` per
   trade. MT5's report-level net profit includes all three deal components, so
   excluding swap or commission biases both the replay and reconciliation.
   This is scale
   invariant *to the extent GoldBot's own lot sizing is equity-proportional* --
   see ``GoldBotSplitLot`` in ``mt5/Include/GoldBot/Risk.mqh``, which sizes
   ``total = (equity / 100.0) * lotPer100Usd`` before broker lot-step rounding
   and a MIN/MAX lot clamp (``GoldBotNormalizeLot``). The clamp is the caveat:
   at the $1000 deposit these reports were run at, many trades may already sit at
   or near the broker min-lot floor, so their r_multiple already embeds some
   floor-inflated risk. Re-scaling that r_multiple down via a small challenge
   risk_pct (large 1/k) implicitly assumes a fractional-of-min-lot position that
   a real broker cannot place -- real risk at small k would be floored back up,
   i.e. WORSE (higher realized risk / DD) than this simulation shows. This is a
   known optimism bias, not corrected here; flag it wherever this script's output
   is used for a k-small verdict.
4. Emit a PropGuard-journal-shaped CSV (same header as
   ``PropGuardResetJournal``/``PropGuardJournalTrade`` in
   ``mt5/Include/PropGuard/Telemetry.mqh``) with one "close" row per trade, so
   ``prop-challenge-simulator.py``'s ``load_closed_trades`` (which only reads the
   ``event``, ``r_multiple``, ``timestamp``, ``engine`` columns) accepts it
   unmodified.
5. Reconcile: sum of extracted closing-deal profits vs. the report's own stated
   net_profit (dollars, from the sibling ``.summary.csv`` -- reusing
   ``analyze-drawdown-attribution.py``'s ``official_net_profit``), must agree
   within 0.5%. Abort (nonzero exit) per-report on failure rather than silently
   emitting a CSV from a bad extraction.
"""

from __future__ import annotations

import argparse
import csv
import importlib.util
import re
import sys
from pathlib import Path
from typing import Sequence

ROOT = Path(__file__).resolve().parents[1]

RECONCILIATION_TOLERANCE_PCT = 0.5

# Exact column order written by PropGuardResetJournal / PropGuardJournalTrade
# (mt5/Include/PropGuard/Telemetry.mqh) -- prop-challenge-simulator.py's
# load_closed_trades only reads timestamp/engine/event/r_multiple by name, but we
# match the full header so this CSV is a drop-in PropGuard-journal shape.
JOURNAL_FIELDS = [
    "timestamp", "engine", "direction", "entry", "sl", "tp", "lots", "risk_cash",
    "clamp_bound", "spread_price", "cost_to_stop_pct", "atr", "range_width",
    "vol_ratio", "phase", "ticket", "event", "reason", "exit_price", "r_multiple",
]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


equity_curve = load_module("equity_curve_analysis", ROOT / "scripts/equity-curve-analysis.py")
dd_attribution = load_module("analyze_drawdown_attribution", ROOT / "scripts/analyze-drawdown-attribution.py")


# ---------------------------------------------------------------------------
# Initial deposit
# ---------------------------------------------------------------------------

_DEPOSIT_RE = re.compile(r"Initial Deposit:.*?<b>\s*([\d\s.,]+)\s*</b>", re.IGNORECASE | re.DOTALL)


def parse_initial_deposit(html: str) -> float | None:
    """Extract the report's stated Initial Deposit ($) from its header block."""
    match = _DEPOSIT_RE.search(html)
    if not match:
        return None
    return equity_curve._parse_number(match.group(1))


# ---------------------------------------------------------------------------
# Extraction: closed trades -> r-multiple rows
# ---------------------------------------------------------------------------

def extract_r_multiple_rows(path: Path) -> tuple[list[dict[str, str]], float, float, float]:
    """Return (journal rows, deposit, sum_extracted_profit, report_net_profit).

    ``report_net_profit`` is None-coalesced to nan by the caller if the sibling
    .summary.csv is missing -- callers must handle that explicitly rather than
    silently skip the reconciliation check.
    """
    html = equity_curve.decode_report(path)
    deposit = parse_initial_deposit(html)
    if deposit is None or deposit <= 0:
        raise ValueError(f"{path.name}: could not parse a positive Initial Deposit from the report header")

    deals = equity_curve.extract_deals(path)
    ordered = sorted((d for d in deals if d.direction in ("in", "out")), key=lambda d: (d.time, d.deal_id))
    closes = [d for d in ordered if d.direction == "out"]
    if not closes:
        raise ValueError(f"{path.name}: no closing deals (direction=='out') extracted from the Deals table")

    # Entry ("in") deals can carry their own nonzero commission/swap -- e.g. the
    # fundingpips-2step/prop-ftmo-p1 prop presets' demo account charges the full
    # round-trip commission on the OPENING deal, not the closing one (confirmed by
    # reading the raw Deals table: "in" rows show a negative Commission column,
    # "out" rows show 0.00 there). extract_deals() only exposes per-deal fields, so
    # summing profit+commission+swap over "out" deals alone silently drops that cost
    # and fails reconciliation against the report's own Total Net Profit -- this was
    # invisible in earlier reports (PROPGUARD_GOLDBOT_SIM.md's 6 samples) simply
    # because those accounts charged $0 commission either way. Since every prop
    # preset that hits this sets InpPropMaxOpenAndPending=1 (verified: at most one
    # position open at a time), each "in" deal is unambiguously followed by the
    # "out" deal(s) that close it -- fold its profit+commission+swap into the very
    # next "out" deal encountered chronologically so the aggregate always
    # reconciles exactly. This attributes a shared entry cost to only the first leg
    # of a multi-leg partial close, which is immaterial for the day-level
    # Monte-Carlo risk simulation this feeds.
    rows: list[dict[str, str]] = []
    running_equity = deposit
    pending_debit = 0.0
    sum_extracted_profit = 0.0
    for deal in ordered:
        if deal.direction == "in":
            pending_debit += deal.profit + deal.commission + deal.swap
            continue
        net_profit = deal.profit + deal.commission + deal.swap + pending_debit
        pending_debit = 0.0
        equity_at_entry = running_equity
        if equity_at_entry <= 0:
            raise ValueError(
                f"{path.name}: running equity hit {equity_at_entry:.2f} before trade at {deal.time} "
                "-- r_multiple undefined (account would already be blown in this replay)"
            )
        r_multiple = net_profit / equity_at_entry
        row = {field: "" for field in JOURNAL_FIELDS}
        row.update({
            "timestamp": deal.time.strftime("%Y.%m.%d %H:%M:%S"),
            "engine": "GoldBot",
            "event": "close",
            "reason": "report_replay",
            "exit_price": f"{deal.price:.5f}",
            "r_multiple": f"{r_multiple:.6f}",
        })
        rows.append(row)
        running_equity += net_profit
        sum_extracted_profit += net_profit
    # Defensive: an "in" deal with no matching "out" (position still open when the
    # report/window ends) leaves its cost unattributed -- fold it into the total so
    # reconciliation still reflects the true report-level net profit.
    sum_extracted_profit += pending_debit

    return rows, deposit, sum_extracted_profit, sum_extracted_profit


# ---------------------------------------------------------------------------
# Per-report processing
# ---------------------------------------------------------------------------

def process_report(path: Path) -> int:
    """Extract, reconcile, and write the sibling *.propguard-sim.csv for one report.

    Returns 0 on success, 1 on reconciliation failure or extraction error --
    the caller aggregates this into the overall process exit code.
    """
    try:
        rows, deposit, sum_extracted_profit, _ = extract_r_multiple_rows(path)
    except ValueError as exc:
        print(f"FAIL  {path.name}: {exc}", file=sys.stderr)
        return 1

    report_net_profit = dd_attribution.official_net_profit(path)
    if report_net_profit is None:
        print(
            f"FAIL  {path.name}: no sibling .summary.csv net_profit found -- cannot reconcile, refusing to emit CSV",
            file=sys.stderr,
        )
        return 1

    diff = sum_extracted_profit - report_net_profit
    diff_pct = (diff / report_net_profit * 100.0) if report_net_profit else 0.0
    ok = abs(diff_pct) <= RECONCILIATION_TOLERANCE_PCT

    status = "PASS" if ok else "FAIL"
    print(
        f"{status}  {path.name}: deposit={deposit:.2f}  trades={len(rows)}  "
        f"extracted_profit={sum_extracted_profit:.2f}  report_net_profit={report_net_profit:.2f}  "
        f"diff={diff:.2f} ({diff_pct:.3f}%)  [tolerance {RECONCILIATION_TOLERANCE_PCT}%]",
        file=sys.stderr,
    )
    if not ok:
        return 1

    out_path = path.with_suffix("").with_suffix(".propguard-sim.csv")
    with out_path.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=JOURNAL_FIELDS)
        writer.writeheader()
        writer.writerows(rows)
    print(f"      wrote {out_path}", file=sys.stderr)
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("reports", nargs="+", type=Path, help="GoldBot MT5 HTML report paths")
    args = parser.parse_args(argv)

    paths = [p for p in args.reports if p.exists()]
    missing = [p for p in args.reports if not p.exists()]
    for p in missing:
        print(f"FAIL  {p}: file not found", file=sys.stderr)
    if not paths:
        print("No readable reports found.", file=sys.stderr)
        return 1

    exit_code = 0
    for path in paths:
        rc = process_report(path)
        exit_code = exit_code or rc
    if missing:
        exit_code = 1
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
