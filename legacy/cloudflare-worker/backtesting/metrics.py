from __future__ import annotations


PASS_CRITERIA = {
    "win_rate": 0.55,
    "profit_factor": 1.80,
    "max_drawdown": 0.15,
    "avg_rr": 2.0,
    "avg_trades_day": 1.0,
    "min_test_months": 3,
    "min_trades": 80,
}


def summarize(trades: list[dict]) -> dict:
    wins = [trade for trade in trades if trade.get("pnl", 0) > 0]
    losses = [trade for trade in trades if trade.get("pnl", 0) < 0]
    gross_win = sum(trade["pnl"] for trade in wins)
    gross_loss = abs(sum(trade["pnl"] for trade in losses))
    equity = 0.0
    peak = 0.0
    max_drawdown = 0.0
    days = {trade.get("entry_time", "")[:10] for trade in trades if trade.get("entry_time")}
    for trade in trades:
        equity += trade.get("pnl", 0)
        peak = max(peak, equity)
        max_drawdown = max(max_drawdown, peak - equity)
    return {
        "trades": len(trades),
        "win_rate": len(wins) / len(trades) if trades else 0,
        "profit_factor": gross_win / gross_loss if gross_loss else float("inf"),
        "avg_rr": sum(trade.get("planned_rr", trade.get("rr", 0)) for trade in trades) / len(trades) if trades else 0,
        "expectancy_r": sum(trade.get("rr", 0) for trade in trades) / len(trades) if trades else 0,
        "max_drawdown_r": max_drawdown,
        "avg_trades_day": len(trades) / max(1, len(days)),
    }


def passes(summary: dict) -> bool:
    return (
        summary.get("win_rate", 0) >= PASS_CRITERIA["win_rate"]
        and summary.get("profit_factor", 0) >= PASS_CRITERIA["profit_factor"]
        and summary.get("avg_rr", 0) >= PASS_CRITERIA["avg_rr"]
        and summary.get("trades", 0) >= PASS_CRITERIA["min_trades"]
        and summary.get("avg_trades_day", 0) >= PASS_CRITERIA["avg_trades_day"]
    )
