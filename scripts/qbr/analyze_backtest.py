#!/usr/bin/env python3
"""Analyze QuantumBehavioralReplica CSV logs without conflating orders, baskets, and signals."""

from __future__ import annotations

import argparse
import csv
import html
import json
import math
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from statistics import mean, median
from typing import Iterable
from datetime import datetime, timedelta


def number(value: object, default: float = 0.0) -> float:
    try:
        result = float(str(value).strip())
        return result if math.isfinite(result) else default
    except (TypeError, ValueError):
        return default


def rows(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def report_text(path: Path) -> str:
    data = path.read_bytes()
    if data.startswith((b"\xff\xfe", b"\xfe\xff")) or data.count(b"\x00") > 100:
        source = data.decode("utf-16", errors="ignore")
    else:
        source = data.decode("utf-8", errors="ignore")
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", " ", source))).strip()


def report_metrics(path: Path) -> dict[str, float | int | str]:
    text = report_text(path)

    def metric(label: str) -> str:
        match = re.search(rf"{re.escape(label)}\s*([-+0-9., ]+)", text)
        if not match:
            raise RuntimeError(f"MT5 report missing metric: {label}")
        return match.group(1).strip().replace(" ", "").replace(",", "")

    quality = re.search(r"History Quality:\s*([0-9.]+)% real ticks", text)
    if not quality:
        raise RuntimeError("MT5 report missing real-tick history quality")
    metrics: dict[str, float | int | str] = {
        "net_profit": float(metric("Total Net Profit:")),
        "total_trades": int(float(metric("Total Trades:"))),
        "history_quality_pct": float(quality.group(1)),
    }
    identity_patterns = {
        "expert": r"Expert:\s*([^\s]+)",
        "build_tag": r"InpBuildTag=([^\s;]+)",
        "run_id": r"InpRunId=([^\s;]+)",
    }
    for key, pattern in identity_patterns.items():
        match = re.search(pattern, text)
        if match:
            metrics[key] = match.group(1)
    leverage = re.search(r"Leverage:\s*1:([0-9]+)", text)
    if leverage:
        metrics["leverage"] = int(leverage.group(1))
    optional_patterns = {
        "initial_deposit": r"Initial Deposit:\s*([-+0-9., ]+)",
        "profit_factor": r"Profit Factor:\s*([0-9.]+)",
        "win_rate_pct": r"Profit Trades \(% of total\):\s*[0-9]+\s*\(([0-9.]+)%\)",
        "equity_drawdown_pct": r"Equity Drawdown Maximal:\s*[-+0-9., ]+\s*\(([0-9.]+)%\)",
    }
    for key, pattern in optional_patterns.items():
        match = re.search(pattern, text)
        if match:
            metrics[key] = float(match.group(1).replace(" ", "").replace(",", ""))
    period = re.search(r"Period:\s*[^()]+\(([0-9.]+)\s*-\s*([0-9.]+)\)", text)
    if period:
        metrics["from_date"] = period.group(1)
        metrics["to_date"] = period.group(2)
    return metrics


def month_keys(from_date: str, to_date: str) -> list[str]:
    start = datetime.strptime(from_date, "%Y.%m.%d")
    end = datetime.strptime(to_date, "%Y.%m.%d")
    current = start.replace(day=1)
    final = end.replace(day=1)
    result: list[str] = []
    while current <= final:
        result.append(current.strftime("%Y.%m"))
        current = (current.replace(day=28) + timedelta(days=4)).replace(day=1)
    return result


def monthly_returns(
    basket_rows: list[dict[str, str]], initial_deposit: float, from_date: str, to_date: str
) -> dict[str, object]:
    pnl: dict[str, float] = {key: 0.0 for key in month_keys(from_date, to_date)}
    for row in basket_rows:
        month = str(row.get("end_time", row.get("start_time", "")))[:7]
        if month in pnl:
            pnl[month] += number(row.get("net_profit"))
    balance = initial_deposit
    returns: dict[str, float] = {}
    factors: list[float] = []
    for month in pnl:
        monthly_return = pnl[month] / balance if balance > 0 else -1.0
        returns[month] = 100.0 * monthly_return
        factors.append(max(0.0, 1.0 + monthly_return))
        balance += pnl[month]
    geometric = -100.0
    if factors and all(factor > 0.0 for factor in factors):
        geometric = 100.0 * (math.prod(factors) ** (1.0 / len(factors)) - 1.0)
    return {
        "monthly_net_profit": pnl,
        "monthly_return_pct": returns,
        "positive_months": sum(value > 0.0 for value in pnl.values()),
        "month_count": len(pnl),
        "geometric_mean_monthly_return_pct": geometric,
    }


def acceptance_result(
    report: dict[str, float | int | str], basket_rows: list[dict[str, str]], risk_rows: list[dict[str, str]]
) -> dict[str, object] | None:
    required = {"initial_deposit", "profit_factor", "win_rate_pct", "equity_drawdown_pct", "from_date", "to_date"}
    if not required.issubset(report):
        return None
    monthly = monthly_returns(
        basket_rows,
        float(report["initial_deposit"]),
        str(report["from_date"]),
        str(report["to_date"]),
    )
    run_id = basket_rows[0].get("run_id", "") if basket_rows else ""
    scaled = run_id.startswith("v113-scale")
    permanent_stops = sum(
        "Equity drawdown limit exceeded" in row.get("event", "") for row in risk_rows
    )
    checks = {
        "history_quality_at_least_99": float(report["history_quality_pct"]) >= 99.0,
        "win_rate_at_least_70": float(report["win_rate_pct"]) >= 70.0,
        "profit_factor": float(report["profit_factor"]) >= (1.20 if scaled else 1.30),
        "equity_drawdown": float(report["equity_drawdown_pct"]) <= (25.0 if scaled else 10.0),
        "positive_months": int(monthly["positive_months"]) >= 4 if scaled else True,
        "no_permanent_safety_stop": permanent_stops == 0,
    }
    if not scaled:
        checks["at_least_360_trades"] = int(report["total_trades"]) >= 360
        net_return_pct = 100.0 * float(report["net_profit"]) / float(report["initial_deposit"])
        checks["return_above_v112_control"] = net_return_pct > 6.033
    target_50 = float(monthly["geometric_mean_monthly_return_pct"]) >= 50.0
    return {
        "track": "scaled" if scaled else "discovery",
        "checks": checks,
        "safety_gate_passed": all(checks.values()),
        "target_50pct_geometric_monthly_passed": target_50,
        "target_status": "passed" if target_50 else "target unmet",
        "monthly": monthly,
        "permanent_safety_stop_count": permanent_stops,
    }


def reconcile_with_report(
    basket_rows: list[dict[str, str]], deal_rows: list[dict[str, str]], report: Path,
    tolerance: float = 0.01,
) -> dict[str, float | int | bool]:
    metrics = report_metrics(report)
    basket_net = round(sum(number(row.get("net_profit")) for row in basket_rows), 2)
    deal_net = round(sum(number(row.get("net_profit")) for row in deal_rows), 2)
    basket_closed_deals = sum(int(number(row.get("closed_deals"))) for row in basket_rows)
    basket_closed_positions = sum(int(number(row.get("closed_positions"))) for row in basket_rows)
    exit_deals = [row for row in deal_rows if str(row.get("entry", "")) in {"DEAL_ENTRY_OUT", "DEAL_ENTRY_OUT_BY", "DEAL_ENTRY_INOUT"}]
    deal_tickets = [str(row.get("deal_ticket", "")).strip() for row in deal_rows]
    if not deal_rows or any(not ticket for ticket in deal_tickets) or len(deal_tickets) != len(set(deal_tickets)):
        raise RuntimeError("QBR report/log reconciliation failed: deals.csv is missing or has duplicate deal tickets")
    exit_position_ids = {str(row.get("position_id", "")).strip() for row in exit_deals}
    exit_position_ids.discard("")
    basket_report_net_difference = round(basket_net - float(metrics["net_profit"]), 2)
    deal_report_net_difference = round(deal_net - float(metrics["net_profit"]), 2)
    basket_deal_difference = basket_closed_deals - len(exit_deals)
    basket_position_difference = basket_closed_positions - len(exit_position_ids)
    report_position_difference = basket_closed_positions - int(metrics["total_trades"])
    passed = (
        abs(basket_report_net_difference) <= tolerance
        and abs(deal_report_net_difference) <= tolerance
        and basket_deal_difference == 0
        and basket_position_difference == 0
        and report_position_difference == 0
    )
    result: dict[str, float | int | bool] = {
        "passed": passed,
        "report_net_profit": float(metrics["net_profit"]),
        "basket_net_profit": basket_net,
        "deal_net_profit": deal_net,
        "basket_report_net_difference": basket_report_net_difference,
        "deal_report_net_difference": deal_report_net_difference,
        "report_total_trades": int(metrics["total_trades"]),
        "basket_closed_deals": basket_closed_deals,
        "deal_exit_count": len(exit_deals),
        "basket_deal_difference": basket_deal_difference,
        "basket_closed_positions": basket_closed_positions,
        "deal_unique_closed_positions": len(exit_position_ids),
        "basket_position_difference": basket_position_difference,
        "report_position_difference": report_position_difference,
        "history_quality_pct": float(metrics["history_quality_pct"]),
        "tolerance": tolerance,
    }
    if not passed:
        raise RuntimeError(
            "QBR report/log reconciliation failed: "
            f"basket/report net={basket_report_net_difference:.2f}, "
            f"deal/report net={deal_report_net_difference:.2f}, "
            f"basket/deal exits={basket_deal_difference}, "
            f"basket/deal positions={basket_position_difference}, "
            f"basket/report positions={report_position_difference}"
        )
    return result


@dataclass
class LevelMetrics:
    count: int = 0
    wins: int = 0
    losses: int = 0
    breakeven: int = 0
    win_rate_pct: float = 0.0
    net_profit: float = 0.0
    gross_profit: float = 0.0
    gross_loss: float = 0.0
    profit_factor: float = 0.0
    average_winner: float = 0.0
    average_loser: float = 0.0
    largest_winner: float = 0.0
    largest_loser: float = 0.0
    payoff_ratio: float = 0.0
    average_wins_erased_by_average_loss: float = 0.0
    average_wins_erased_by_largest_loss: float = 0.0
    median_result: float = 0.0


def summarize(values: Iterable[float]) -> LevelMetrics:
    vals = [v for v in values if math.isfinite(v)]
    winners = [v for v in vals if v > 0]
    losers = [v for v in vals if v < 0]
    zero = [v for v in vals if v == 0]
    avg_win = mean(winners) if winners else 0.0
    avg_loss = mean(losers) if losers else 0.0
    gross_profit = sum(winners)
    gross_loss = sum(losers)
    return LevelMetrics(
        count=len(vals),
        wins=len(winners),
        losses=len(losers),
        breakeven=len(zero),
        win_rate_pct=100.0 * len(winners) / len(vals) if vals else 0.0,
        net_profit=sum(vals),
        gross_profit=gross_profit,
        gross_loss=gross_loss,
        profit_factor=gross_profit / abs(gross_loss) if gross_loss else (math.inf if gross_profit else 0.0),
        average_winner=avg_win,
        average_loser=avg_loss,
        largest_winner=max(winners, default=0.0),
        largest_loser=min(losers, default=0.0),
        payoff_ratio=avg_win / abs(avg_loss) if avg_loss else 0.0,
        average_wins_erased_by_average_loss=abs(avg_loss) / avg_win if avg_win else 0.0,
        average_wins_erased_by_largest_loss=abs(min(losers, default=0.0)) / avg_win if avg_win else 0.0,
        median_result=median(vals) if vals else 0.0,
    )


def deal_results(order_rows: list[dict[str, str]]) -> list[float]:
    # orders.csv intentionally records execution events but not P/L. If a future exporter
    # includes net_profit/profit, use it. Otherwise order-level P/L remains unavailable.
    results: list[float] = []
    for row in order_rows:
        for key in ("net_profit", "profit", "deal_profit"):
            if key in row and str(row[key]).strip() != "":
                results.append(number(row[key]))
                break
    return results


def signal_summary(signal_rows: list[dict[str, str]]) -> dict[str, object]:
    allowed = [r for r in signal_rows if str(r.get("entry_allowed", "0")).strip() in {"1", "true", "True"}]
    unique_ids = {(r.get("timestamp", ""), r.get("direction", ""), r.get("pattern", "")) for r in allowed}
    rejected: dict[str, int] = {}
    patterns: dict[str, int] = {}
    for row in signal_rows:
        pattern = row.get("pattern", "NONE") or "NONE"
        patterns[pattern] = patterns.get(pattern, 0) + 1
        if row not in allowed:
            reason = row.get("rejection_reason", "UNKNOWN") or "UNKNOWN"
            rejected[reason] = rejected.get(reason, 0) + 1
    return {
        "logged_decisions": len(signal_rows),
        "allowed_signal_rows": len(allowed),
        "independent_signal_keys": len(unique_ids),
        "patterns": dict(sorted(patterns.items(), key=lambda x: (-x[1], x[0]))),
        "rejections": dict(sorted(rejected.items(), key=lambda x: (-x[1], x[0]))),
    }


def drawdown_from_daily(daily_rows: list[dict[str, str]]) -> float:
    values = [number(r.get("equity")) for r in daily_rows if r.get("equity")]
    peak = 0.0
    maximum = 0.0
    for equity in values:
        peak = max(peak, equity)
        if peak > 0:
            maximum = max(maximum, 100.0 * (peak - equity) / peak)
    return maximum


def grouped_basket_metrics(
    basket_rows: list[dict[str, str]], key_fn
) -> dict[str, dict[str, float | int]]:
    grouped: dict[str, list[float]] = {}
    for row in basket_rows:
        key = str(key_fn(row) or "UNKNOWN")
        grouped.setdefault(key, []).append(number(row.get("net_profit")))
    return {key: asdict(summarize(values)) for key, values in sorted(grouped.items())}


def json_safe(value: object) -> object:
    if isinstance(value, float) and not math.isfinite(value):
        return None
    if isinstance(value, dict):
        return {key: json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [json_safe(item) for item in value]
    return value


def markdown(summary: dict[str, object]) -> str:
    basket = summary["basket_metrics"]
    order = summary["order_metrics"]
    signal = summary["signal_metrics"]
    report = summary.get("report_metrics")
    initial_deposit = float(report.get("initial_deposit", 0.0)) if isinstance(report, dict) else 0.0
    net_return_pct = 100.0 * float(basket["net_profit"]) / initial_deposit if initial_deposit > 0 else 0.0
    lines = [
        "# QuantumBehavioralReplica Analysis",
        "",
        "Order, basket, and independent-signal levels are reported separately.",
        "",
        "## Basket level",
        "",
        f"- Count: {basket['count']}",
        f"- Net profit: ${basket['net_profit']:.2f} ({net_return_pct:.2f}%)",
        f"- Win rate: {basket['win_rate_pct']:.2f}%",
        f"- Profit factor: {basket['profit_factor']}",
        f"- Average winner / loser: {basket['average_winner']:.2f} / {basket['average_loser']:.2f}",
        f"- Largest winner / loser: {basket['largest_winner']:.2f} / {basket['largest_loser']:.2f}",
        f"- Payoff ratio: {basket['payoff_ratio']:.3f}",
        f"- Average wins erased by average loss: {basket['average_wins_erased_by_average_loss']:.2f}",
        f"- Average wins erased by largest loss: {basket['average_wins_erased_by_largest_loss']:.2f}",
        "",
        "## Order level",
        "",
        f"- P/L-bearing order/deal rows found: {order['count']}",
        "- Note: the default orders.csv is an execution audit and does not itself contain deal P/L; use an MT5 deal export or baskets.csv for economic results.",
        "",
        "## Independent signals",
        "",
        f"- Logged decisions: {signal['logged_decisions']}",
        f"- Allowed rows: {signal['allowed_signal_rows']}",
        f"- Unique timestamp/direction/pattern keys: {signal['independent_signal_keys']}",
        f"- Completed initial-signal win rate (one basket = one initial signal): {basket['win_rate_pct']:.2f}%",
        "",
        f"Daily-equity maximum drawdown estimate: {summary['daily_equity_max_drawdown_pct']:.2f}%",
        "",
        "## Interpretation",
        "",
        "A child-order win rate must not be substituted for basket-level or independent-signal performance. Review costs, MAE/MFE, holding time, and stress scenarios before drawing conclusions.",
    ]
    acceptance = summary.get("acceptance")
    if isinstance(acceptance, dict):
        monthly = acceptance.get("monthly", {})
        lines.extend(
            [
                "",
                "## Aggressive acceptance",
                "",
                f"- Safety gate passed: {acceptance.get('safety_gate_passed')}",
                f"- 50% geometric monthly target: {acceptance.get('target_status')}",
                f"- Geometric monthly return: {monthly.get('geometric_mean_monthly_return_pct', 0.0):.2f}%",
            ]
        )
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--logs", type=Path, required=True, help="Directory containing QBR CSV logs")
    parser.add_argument("--out", type=Path, default=Path("analysis"), help="Output directory")
    parser.add_argument("--tester", type=Path, help="Optional MT5-exported CSV retained as provenance")
    parser.add_argument("--report", type=Path, help="MT5 HTML report required for economic reconciliation")
    parser.add_argument("--reconciliation-tolerance", type=float, default=0.01)
    args = parser.parse_args()

    basket_rows = rows(args.logs / "baskets.csv")
    deal_rows = rows(args.logs / "deals.csv")
    order_rows = rows(args.logs / "orders.csv")
    signal_rows = rows(args.logs / "signals.csv")
    daily_rows = rows(args.logs / "daily_summary.csv")
    risk_rows = rows(args.logs / "risk_events.csv")

    basket_values = [number(r.get("net_profit")) for r in basket_rows]
    basket_metrics = asdict(summarize(basket_values))
    exit_reasons = grouped_basket_metrics(basket_rows, lambda row: row.get("exit_reason"))
    entry_patterns = grouped_basket_metrics(basket_rows, lambda row: row.get("entry_pattern"))
    directions = grouped_basket_metrics(basket_rows, lambda row: row.get("direction"))
    entry_states = grouped_basket_metrics(basket_rows, lambda row: row.get("entry_state"))
    entry_hours = grouped_basket_metrics(
        basket_rows,
        lambda row: (row.get("start_time", "").split()[1][:2]
                     if len(row.get("start_time", "").split()) > 1 else "UNKNOWN"),
    )
    order_metrics = asdict(summarize(deal_results(order_rows)))
    signal_metrics = signal_summary(signal_rows)
    parsed_report = report_metrics(args.report) if args.report else None
    reconciliation = reconcile_with_report(basket_rows, deal_rows, args.report, args.reconciliation_tolerance) if args.report else None
    acceptance = acceptance_result(parsed_report, basket_rows, risk_rows) if parsed_report else None

    summary: dict[str, object] = {
        "source_directory": str(args.logs.resolve()),
        "tester_report": str(args.tester.resolve()) if args.tester else None,
        "mt5_report": str(args.report.resolve()) if args.report else None,
        "report_metrics": parsed_report,
        "basket_metrics": basket_metrics,
        "exit_reason_metrics": exit_reasons,
        "entry_pattern_metrics": entry_patterns,
        "direction_metrics": directions,
        "entry_state_metrics": entry_states,
        "entry_hour_metrics": entry_hours,
        "mt5_child_order_count": sum(int(number(row.get("child_orders"))) for row in basket_rows),
        "order_metrics": order_metrics,
        "signal_metrics": signal_metrics,
        "independent_signal_outcome_metrics": basket_metrics,
        "independent_signal_outcome_definition": "One completed basket equals one completed initial independent signal; add-on child orders are excluded.",
        "daily_equity_max_drawdown_pct": drawdown_from_daily(daily_rows),
        "risk_event_count": len(risk_rows),
        "acceptance": acceptance,
        "risk_events_by_severity": {},
        "data_quality": {
            "baskets_csv_present": (args.logs / "baskets.csv").exists(),
            "signals_csv_present": (args.logs / "signals.csv").exists(),
            "deals_csv_present": (args.logs / "deals.csv").exists(),
            "orders_csv_has_pnl": bool(deal_results(order_rows)),
            "report_reconciliation": reconciliation,
        },
    }
    severities: dict[str, int] = {}
    for row in risk_rows:
        severity = row.get("severity", "UNKNOWN") or "UNKNOWN"
        severities[severity] = severities.get(severity, 0) + 1
    summary["risk_events_by_severity"] = severities

    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "analysis_summary.json").write_text(
        json.dumps(json_safe(summary), indent=2, allow_nan=False), encoding="utf-8"
    )
    (args.out / "analysis_summary.md").write_text(markdown(summary), encoding="utf-8")
    print(f"Wrote {args.out / 'analysis_summary.json'}")
    print(f"Wrote {args.out / 'analysis_summary.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
