# GoldBot Real-Mode Improvement Plan

## Current Baseline

Use real MT5 broker execution only. Do not use Python parity mode for performance acceptance.

Latest honest baseline:

```text
Report: mt5/backtests/reports/GoldBot-XAUUSD-M15-2023.10.01-2025.09.30-threshold62_5-maxhold.htm
Mode: Real broker execution
Window: 2023-10-01 through 2025-09-30
Deposit: 100,000 USD
Input override: InpScoreThreshold=62.5

Total trades: 812
Win rate: 31.28%
Profit factor: 0.78
Net profit: -42,270.11
Expected payoff: -52.06
Max balance drawdown: 58.24%
Max equity drawdown: 60.89%
Pending orders placed: 1028
Pending ladders placed: 454
TP1 hits: 179
TP2 hits: 4
TP3 hits: 3
Max-hold closes: 29
```

Interpretation:

- The EA is now active in real broker mode.
- `InpScoreThreshold=62.5` overtrades.
- Drawdown is far too high for demo-forward acceptance.
- TP2/TP3 are almost never reached, so the current lifecycle is too dependent on TP1 and stop/breakeven behavior.
- The previous huge profit result was invalid because positions could remain open until test end. That is now fixed by closing filled positions after `InpMaxHoldBars`.

## Improvement Goal

Find a real-mode configuration and code path that is stable enough for demo-forward testing.

Initial target:

```text
Profit factor: >= 1.20
Max equity drawdown: <= 25%
Trades over 24 months: 150-450
TP2/TP3 lifecycle: non-zero and explainable
No end-of-test profit dependency
No stale open positions older than InpMaxHoldBars
```

This is not the final trading goal. It is the next quality gate before deeper optimization.

## Hypotheses

1. Trade frequency is too high because M15-only SMC entries are allowed when H4/H1 are both false.
2. Lot sizing is too aggressive for a strategy that places up to three pending orders per signal.
3. TP2/TP3 are too far or the trailing lifecycle activates too late.
4. The score threshold should not be lowered alone; it should be paired with stronger confirmation.
5. Some losses come from repeated entries in the same local structure before cooldown meaningfully separates signals.

## Phase 1: Add Real-Mode Filter Controls

Add inputs:

```text
InpRequireHigherTfConfirmation = true
InpMinRealModeScore = 68.75
InpMaxLaddersPerDay = 3
InpUseSessionFilterForRealMode = true
InpRealSessionStartHour = 7
InpRealSessionEndHour = 22
```

Behavior:

- Require M15 SMC trigger as today.
- When `InpRequireHigherTfConfirmation=true`, require `gateH4 || gateH1`.
- Keep H4/H1 as score contributors.
- Limit new ladders per broker day.
- Block new ladders outside the configured server-time session.

Acceptance:

- Strategy Tester still places broker-native pending limit orders.
- `trades.csv` logs specific block reasons:
  - higher timeframe confirmation blocked
  - daily ladder limit blocked
  - real session blocked
- No parity file is used.

## Phase 2: Risk Reduction

Test lower size first, before changing TP/SL logic:

```bash
MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 \
MT5_REPORT=GoldBot-real-score68-risk003 \
MT5_INPUT_OVERRIDES=$'InpScoreThreshold=68.75\nInpLotPer100Usd=0.003' \
bash scripts/run-mt5-backtest.sh
```

Grid:

```text
InpScoreThreshold: 68.75, 70, 75
InpLotPer100Usd: 0.002, 0.003, 0.005
InpCooldownBars: 16, 24, 32
InpMaxOpenTrades: 1, 2
InpMaxLaddersPerDay: 1, 2, 3
```

Acceptance:

- Max equity drawdown falls below 25%.
- Trade count stays above 150 over 24 months.
- Profit factor improves compared with 0.78.

## Phase 3: TP Lifecycle Repair

Current TP evidence:

```text
TP1 hits: 179
TP2 hits: 4
TP3 hits: 3
```

This means exits are not balanced. After Phase 1 and 2 reduce noise, test:

```text
TP1: 1.5R instead of 2.0R
TP2: 2.0R instead of 2.5R
TP3: 3.0R instead of 4.0R
ATR trailing after TP1 instead of after TP2
```

Add inputs before testing:

```text
InpTp1R = 1.5
InpTp2R = 2.0
InpTp3R = 3.0
InpTrailAfterTp1 = true
```

Acceptance:

- TP2 and TP3 are reached more than a token amount.
- Profit factor does not rely on a few end-of-test exits.
- Max-hold closes are still logged and do not dominate profit.

## Phase 4: Compare Candidate Reports

Create a small parser to compare reports:

```bash
python3 scripts/summarize-mt5-reports.py mt5/backtests/reports/*.htm
```

Required columns:

```text
report
net_profit
profit_factor
expected_payoff
total_trades
win_rate
max_balance_drawdown_pct
max_equity_drawdown_pct
gross_profit
gross_loss
```

Acceptance:

- The best candidate is chosen from comparable real-mode reports.
- The chosen preset is copied into `mt5/Presets/GoldBot.optimized.set`.
- The report and input overrides are documented in this file.

## Phase 5: Demo-Forward Candidate

Only after a candidate passes:

```text
Profit factor >= 1.20
Max equity drawdown <= 25%
No stale max-hold violations
No parity mode
No dependency on end-of-test forced close
```

Then run MT5 demo for at least 2 weeks.

Demo checklist:

- Compare fills against Strategy Tester assumptions.
- Confirm pending ladders are broker-native.
- Confirm daily loss stops new entries.
- Confirm daily target stops new entries.
- Confirm max open trades blocks new entries.
- Confirm max-hold closes positions.
- Confirm TP1/TP2/TP3 journal events.

## Immediate Next Implementation

Implement Phase 1 first:

1. Add higher-timeframe confirmation input.
2. Add max ladders per day input and MT5 Global Variable counter.
3. Add real-mode session filter inputs.
4. Log each new block reason to `trades.csv`.
5. Compile in MetaEditor.
6. Run the first comparison:

```bash
MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 \
MT5_REPORT=GoldBot-real-confirmed-score68 \
MT5_INPUT_OVERRIDES=$'InpScoreThreshold=68.75\nInpLotPer100Usd=0.003\nInpCooldownBars=24\nInpMaxOpenTrades=1' \
bash scripts/run-mt5-backtest.sh
```

