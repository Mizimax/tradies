# GoldBot Demo-Forward Checklist

Use this only after a real-mode Strategy Tester candidate passes the current quality gate:

```text
Profit factor >= 1.20
Max equity drawdown <= 25%
Trades over 24 months: 150-450
TP2/TP3 lifecycle is non-zero and explainable
No stale max-hold violations
No parity mode
No dependency on end-of-test forced close
```

## Setup

- Compile `GoldBot.mq5` in MetaEditor with `0 errors`.
- Attach the EA to an MT5 demo account chart for `XAUUSD` / `M15`.
- Load the selected `GoldBot.optimized.set` preset.
- Confirm these are disabled for production-style demo behavior:
  - `InpPythonParityMode=false`
  - `InpLegacyParityMode=false`
  - `InpDebugOnly=false`
- Decide whether to keep `InpResetJournalOnInit=true` for clean evaluation or set it to `false` when preserving a long-running demo journal matters more.
- Confirm Algo Trading is enabled in MT5.

## Daily Checks

- Export or inspect the demo account history.
- Save `MQL5/Files/GoldBot/trades.csv`.
- Record current balance, equity, open positions, and pending orders.
- Confirm pending orders use the configured magic number and symbol.
- Confirm no position is older than `InpMaxHoldBars` unless market closure prevented management.

## Behavior Checks

- Pending ladders are broker-native limit orders.
- Max open trades blocks new entries when the limit is reached.
- Max ladders per day blocks repeated entries after the configured count.
- Daily loss gate stops new entries after `InpMaxDailyLossPct`.
- Daily target gate stops new entries after `InpDailyTargetPct`.
- Session filter blocks entries outside configured server hours when enabled.
- TP1 closes partial volume and moves/protects SL.
- TP2 closes partial volume.
- TP3 closes remaining volume.
- ATR trailing starts after TP1 when `InpTrailAfterTp1=true`.
- Pending orders expire after `InpMaxHoldBars`.
- Pending orders are cancelled when their stop is breached before fill.

## Comparison Against Strategy Tester

After at least 2 weeks:

- Compare trade count per week.
- Compare long/short split.
- Compare skipped signal reasons from `trades.csv`.
- Compare average spread and visible slippage during entries.
- Compare drawdown path and worst daily loss.
- Compare TP1/TP2/TP3 event frequencies.
- Compare pending order fill rate.

## Decision

Demo-forward passes only if:

- Real fills are close enough to Strategy Tester assumptions.
- Drawdown remains inside the accepted test range.
- No risk gate fails open.
- No order-management event repeats unexpectedly.
- Journal evidence is complete enough to explain every open and closed trade.

Do not move to tiny live size until this checklist is complete.
