#!/usr/bin/env python3
"""Monte-Carlo P(pass) simulator for PropGuard -- the acceptance metric for
mt5/backtests/PROPGUARD_DESIGN.md gates G3/G4/G5 is P(pass the challenge), not net profit.

Consumes a PropGuard trades journal (MQL5/Files/PropGuard/trades.csv, columns written by
mt5/Include/PropGuard/Telemetry.mqh::PropGuardJournalTrade) and replays its empirical
per-trade R-multiples through a firm's actual rule barriers (daily loss reset each calendar
day, target profit, max drawdown -- static or trailing) using three independent estimators
that must agree before a candidate is trusted (approved plan §6):

  1. rolling-start deterministic -- start a simulated challenge on every trading day in the
     sample and walk forward to pass/fail/censored (runs out of data). The most honest: it
     preserves real trade ordering, clustering, and autocorrelation exactly as it occurred.
  2. block bootstrap -- resample contiguous blocks of TRADING DAYS (not individual trades,
     so within-day trade clustering and cross-day correlation both survive resampling) to
     build synthetic full-length challenge paths. Unlike rolling-start this is never
     censored, at the cost of assuming the future resembles a reshuffled past.
  3. parametric -- the closed-form first-passage formula from the approved plan §1,
     lambda = 2e/(f*v), as a sanity check against the two empirical estimators. Uses ONLY
     the max-drawdown floor as the absorbing barrier (an approximation: the real daily-loss
     floor resets every day rather than being a fixed absorbing barrier, which the plan's
     own math shows is rarely binding at PropGuard's risk sizing -- see PROPGUARD_DESIGN.md
     §1's worst-day-vs-5%-limit table).

Sizing is decoupled from the empirical trade sample: each trade's R-multiple is replayed as
`equity *= 1 + (risk_pct/100)*r_multiple`, so the SAME historical trade sequence can be
re-scaled to test different risk_pct values without re-running MT5.
"""

from __future__ import annotations

import argparse
import csv
import math
import random
import statistics
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# ---------------------------------------------------------------------------
# Firm rule presets -- the FIRM's real published limits (not PropGuard's tighter
# internal thresholds). "Passing the challenge" is defined against these.
# ---------------------------------------------------------------------------

FIRM_PRESETS = {
    "ftmo-2step": dict(daily_loss_pct=5.0, max_dd_pct=10.0, dd_is_trailing=False,
                        phase1_target_pct=10.0, phase2_target_pct=5.0, daily_reset_hour=0),
    "fundingpips-2step": dict(daily_loss_pct=5.0, max_dd_pct=10.0, dd_is_trailing=False,
                               phase1_target_pct=8.0, phase2_target_pct=5.0, daily_reset_hour=0),
    "the5ers-highstakes": dict(daily_loss_pct=5.0, max_dd_pct=10.0, dd_is_trailing=False,
                                phase1_target_pct=10.0, phase2_target_pct=5.0, daily_reset_hour=0),
    "the5ers-hypergrowth": dict(daily_loss_pct=3.0, max_dd_pct=6.0, dd_is_trailing=False,
                                 phase1_target_pct=10.0, phase2_target_pct=0.0, daily_reset_hour=0),
}


@dataclass
class SimParams:
    daily_loss_pct: float
    max_dd_pct: float
    dd_is_trailing: bool
    phase1_target_pct: float
    phase2_target_pct: float
    daily_reset_hour: int = 0
    challenge_risk_pct: float = 1.0
    funded_risk_pct: float = 0.5
    funded_horizon_days: int = 90


# ---------------------------------------------------------------------------
# Journal loading
# ---------------------------------------------------------------------------

@dataclass
class ClosedTrade:
    time: datetime
    r_multiple: float
    engine: str


def load_closed_trades(csv_path: Path) -> list[ClosedTrade]:
    trades: list[ClosedTrade] = []
    with csv_path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            if row.get("event") != "close":
                continue
            try:
                r = float(row["r_multiple"])
                ts = datetime.strptime(row["timestamp"], "%Y.%m.%d %H:%M:%S")
            except (KeyError, ValueError):
                continue
            trades.append(ClosedTrade(time=ts, r_multiple=r, engine=row.get("engine", "")))
    trades.sort(key=lambda t: t.time)
    return trades


def day_start(ts: datetime, reset_hour: int) -> datetime:
    """Mirrors PropGuardDayStart (mt5/Include/PropGuard/PropRules.mqh)."""
    midnight = ts.replace(hour=0, minute=0, second=0, microsecond=0)
    candidate = midnight + timedelta(hours=reset_hour)
    if candidate > ts:
        candidate -= timedelta(days=1)
    return candidate


@dataclass
class TradingDay:
    day: datetime
    r_multiples: list[float] = field(default_factory=list)


def group_into_days(trades: list[ClosedTrade], reset_hour: int) -> list[TradingDay]:
    buckets: dict[datetime, TradingDay] = {}
    for t in trades:
        d = day_start(t.time, reset_hour)
        if d not in buckets:
            buckets[d] = TradingDay(day=d)
        buckets[d].r_multiples.append(t.r_multiple)
    return [buckets[k] for k in sorted(buckets)]


# ---------------------------------------------------------------------------
# Challenge walk-forward simulation (shared by rolling-start and bootstrap)
# ---------------------------------------------------------------------------

FAIL_DAILY = "fail_daily"
FAIL_DD = "fail_dd"
PASS = "pass"
CENSORED = "censored"


def simulate_from(days: list[TradingDay], start_idx: int, params: SimParams,
                   day_supplier=None) -> dict:
    """Walk forward through `days[start_idx:]` (or an infinite `day_supplier()` generator
    for the bootstrap path) simulating P1 -> P2 -> FUNDED. Returns a result dict with the
    terminal `status`, how many trading days were consumed, and which phase was reached.

    `day_supplier`, if given, is called to fetch additional TradingDay objects once the
    fixed `days` list is exhausted -- this is how the bootstrap estimator avoids censoring.
    """
    equity = 1.0
    initial_balance = 1.0
    peak_equity = 1.0
    phase = "P1"
    trading_days_used = 0
    idx = start_idx

    def current_target_pct():
        return params.phase1_target_pct if phase == "P1" else params.phase2_target_pct

    def risk_pct():
        return params.funded_risk_pct if phase == "FUNDED" else params.challenge_risk_pct

    funded_days = 0

    while True:
        if idx < len(days):
            td = days[idx]
        elif day_supplier is not None:
            td = day_supplier()
        else:
            return {"status": CENSORED, "trading_days_used": trading_days_used, "phase_reached": phase}
        idx += 1
        trading_days_used += 1
        day_baseline = equity

        for r in td.r_multiples:
            equity = equity * (1.0 + (risk_pct() / 100.0) * r)
            if equity > peak_equity:
                peak_equity = equity

            dd_anchor = peak_equity if params.dd_is_trailing else initial_balance
            dd_floor = dd_anchor * (1.0 - params.max_dd_pct / 100.0)
            if equity <= dd_floor:
                return {"status": FAIL_DD, "trading_days_used": trading_days_used, "phase_reached": phase}

            daily_floor = day_baseline * (1.0 - params.daily_loss_pct / 100.0)
            if equity <= daily_floor:
                return {"status": FAIL_DAILY, "trading_days_used": trading_days_used, "phase_reached": phase}

            if phase != "FUNDED":
                target_level = initial_balance * (1.0 + current_target_pct() / 100.0)
                if equity >= target_level:
                    if phase == "P1":
                        phase = "P2"
                        initial_balance = equity
                        peak_equity = equity
                    else:  # P2 -> FUNDED
                        phase = "FUNDED"
                        initial_balance = equity
                        peak_equity = equity
                        return {"status": PASS, "trading_days_used": trading_days_used,
                                "phase_reached": phase, "funded_equity_path_start": equity}

        if phase == "FUNDED":
            funded_days += 1
            if funded_days >= params.funded_horizon_days:
                return {"status": "funded_survived_horizon", "trading_days_used": trading_days_used,
                        "phase_reached": phase, "funded_days_survived": funded_days}


# ---------------------------------------------------------------------------
# Estimator 1: rolling-start deterministic
# ---------------------------------------------------------------------------

def run_rolling_start(days: list[TradingDay], params: SimParams) -> dict:
    if not days:
        return {"n": 0}
    outcomes = [simulate_from(days, i, params) for i in range(len(days))]
    return _summarize_outcomes(outcomes)


# ---------------------------------------------------------------------------
# Estimator 2: block bootstrap (never censored -- resamples indefinitely)
# ---------------------------------------------------------------------------

def make_block_bootstrap_supplier(days: list[TradingDay], block_size: int, rng: random.Random):
    """Returns a zero-arg callable that yields TradingDay objects forever, drawn from
    resampled contiguous blocks of `days` (preserves within-block autocorrelation)."""
    if not days:
        raise ValueError("cannot bootstrap from zero trading days")
    buffer: list[TradingDay] = []

    def supplier() -> TradingDay:
        nonlocal buffer
        if not buffer:
            max_start = max(0, len(days) - block_size)
            start = rng.randint(0, max_start)
            buffer = list(days[start:start + block_size]) or list(days[:1])
        return buffer.pop(0)

    return supplier


def run_block_bootstrap(days: list[TradingDay], params: SimParams, n_reps: int,
                         block_size: int, rng: random.Random,
                         max_trading_days_per_rep: int = 20_000) -> dict:
    if not days:
        return {"n": 0}
    outcomes = []
    for _ in range(n_reps):
        supplier = make_block_bootstrap_supplier(days, block_size, rng)
        result = simulate_from([], 0, params, day_supplier=supplier)
        if result["status"] == CENSORED and result["trading_days_used"] >= max_trading_days_per_rep:
            pass  # extremely unlikely with a real edge; keep as censored rather than loop forever
        outcomes.append(result)
    return _summarize_outcomes(outcomes)


# ---------------------------------------------------------------------------
# Estimator 3: parametric closed-form (sanity check only)
# ---------------------------------------------------------------------------

def parametric_estimate(r_multiples: list[float], params: SimParams) -> dict:
    if len(r_multiples) < 2:
        return {"e": None, "v": None, "note": "insufficient trades for parametric estimate"}
    e = statistics.mean(r_multiples)
    v = statistics.pvariance(r_multiples)
    if v <= 0:
        return {"e": e, "v": v, "note": "zero variance -- parametric estimate undefined"}

    def p_pass(f_pct: float, target_pct: float, floor_pct: float) -> float | None:
        f = f_pct / 100.0
        a = target_pct / 100.0
        b = floor_pct / 100.0
        lam = 2.0 * e / (f * v)
        if abs(lam) < 1e-12:
            return b / (a + b) if (a + b) > 0 else None
        try:
            numerator = 1.0 - math.exp(lam * b)
            denominator = math.exp(-lam * a) - math.exp(lam * b)
            if abs(denominator) < 1e-15:
                return None
            return numerator / denominator
        except OverflowError:
            return 1.0 if lam > 0 else 0.0

    p1 = p_pass(params.challenge_risk_pct, params.phase1_target_pct, params.max_dd_pct)
    p2 = p_pass(params.challenge_risk_pct, params.phase2_target_pct, params.max_dd_pct)
    p_both = (p1 * p2) if (p1 is not None and p2 is not None) else None

    return {
        "e_per_trade_R": e,
        "v_per_trade_R": v,
        "sharpe_like_e_over_sqrt_v": (e / math.sqrt(v)) if v > 0 else None,
        "p_pass_phase1_vs_maxdd_floor_only": p1,
        "p_pass_phase2_vs_maxdd_floor_only": p2,
        "p_pass_both_vs_maxdd_floor_only": p_both,
        "note": "approximation: uses max-DD floor as the sole absorbing barrier, ignores "
                "the daily-reset floor (plan §1 shows it is rarely binding at this sizing)",
    }


# ---------------------------------------------------------------------------
# Aggregation
# ---------------------------------------------------------------------------

def _summarize_outcomes(outcomes: list[dict]) -> dict:
    n = len(outcomes)
    if n == 0:
        return {"n": 0}
    n_pass = sum(1 for o in outcomes if o["status"] in (PASS, "funded_survived_horizon"))
    n_fail_daily = sum(1 for o in outcomes if o["status"] == FAIL_DAILY)
    n_fail_dd = sum(1 for o in outcomes if o["status"] == FAIL_DD)
    n_censored = sum(1 for o in outcomes if o["status"] == CENSORED)
    n_resolved = n_pass + n_fail_daily + n_fail_dd

    pass_days = [o["trading_days_used"] for o in outcomes if o["status"] in (PASS, "funded_survived_horizon")]

    return {
        "n": n,
        "n_pass": n_pass,
        "n_fail_daily": n_fail_daily,
        "n_fail_dd": n_fail_dd,
        "n_censored": n_censored,
        "n_resolved": n_resolved,
        "p_pass_unconditional": n_pass / n,
        "p_pass_conditional_on_resolved": (n_pass / n_resolved) if n_resolved > 0 else None,
        "p_fail_daily": n_fail_daily / n,
        "p_fail_dd": n_fail_dd / n,
        "p_censored": n_censored / n,
        "mean_trading_days_to_pass": statistics.mean(pass_days) if pass_days else None,
        "median_trading_days_to_pass": statistics.median(pass_days) if pass_days else None,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_params(firm: str, deposit: float, challenge_risk_pct: float,
                  funded_risk_pct: float, funded_horizon_days: int) -> SimParams:
    if firm not in FIRM_PRESETS:
        raise ValueError(f"unknown firm preset: {firm}. Choices: {', '.join(sorted(FIRM_PRESETS))}")
    preset = dict(FIRM_PRESETS[firm])
    preset["challenge_risk_pct"] = challenge_risk_pct
    preset["funded_risk_pct"] = funded_risk_pct
    preset["funded_horizon_days"] = funded_horizon_days
    return SimParams(**preset)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("trades_csv", type=Path, help="PropGuard *.trades.csv journal")
    parser.add_argument("--firm", default="ftmo-2step", choices=sorted(FIRM_PRESETS))
    parser.add_argument("--deposit", type=float, default=100_000.0, help="Display only -- simulation works in equity fractions")
    parser.add_argument("--method", default="rolling,bootstrap,parametric",
                         help="Comma list of: rolling,bootstrap,parametric")
    parser.add_argument("--challenge-risk-pct", type=float, default=1.0)
    parser.add_argument("--funded-risk-pct", type=float, default=0.5)
    parser.add_argument("--funded-horizon-days", type=int, default=90)
    parser.add_argument("--bootstrap-reps", type=int, default=2000)
    parser.add_argument("--bootstrap-block-days", type=int, default=10)
    parser.add_argument("--seed", type=int, default=1234)
    args = parser.parse_args(argv)

    if not args.trades_csv.exists():
        print(f"Trades journal not found: {args.trades_csv}", file=sys.stderr)
        return 2

    trades = load_closed_trades(args.trades_csv)
    if not trades:
        print("No closed trades with a valid r_multiple found in the journal.", file=sys.stderr)
        return 2

    params = build_params(args.firm, args.deposit, args.challenge_risk_pct,
                           args.funded_risk_pct, args.funded_horizon_days)
    days = group_into_days(trades, params.daily_reset_hour)
    r_multiples = [t.r_multiple for t in trades]

    methods = {m.strip() for m in args.method.split(",") if m.strip()}

    print(f"Firm: {args.firm}  |  closed trades: {len(trades)}  |  trading days: {len(days)}")
    print(f"Risk: challenge={args.challenge_risk_pct}%  funded={args.funded_risk_pct}%")
    print()

    if "rolling" in methods:
        result = run_rolling_start(days, params)
        print("== Rolling-start deterministic ==")
        _print_result(result)
        print()

    if "bootstrap" in methods:
        rng = random.Random(args.seed)
        result = run_block_bootstrap(days, params, args.bootstrap_reps, args.bootstrap_block_days, rng)
        print(f"== Block bootstrap (reps={args.bootstrap_reps}, block_days={args.bootstrap_block_days}) ==")
        _print_result(result)
        print()

    if "parametric" in methods:
        result = parametric_estimate(r_multiples, params)
        print("== Parametric closed-form (sanity check only) ==")
        for k, v in result.items():
            print(f"  {k}: {v}")
        print()

    return 0


def _print_result(result: dict) -> None:
    if result.get("n", 0) == 0:
        print("  no data")
        return
    for key in ("n", "n_pass", "n_fail_daily", "n_fail_dd", "n_censored", "n_resolved",
                "p_pass_unconditional", "p_pass_conditional_on_resolved",
                "p_fail_daily", "p_fail_dd", "p_censored",
                "mean_trading_days_to_pass", "median_trading_days_to_pass"):
        val = result.get(key)
        if isinstance(val, float):
            print(f"  {key}: {val:.4f}")
        else:
            print(f"  {key}: {val}")


if __name__ == "__main__":
    raise SystemExit(main())
