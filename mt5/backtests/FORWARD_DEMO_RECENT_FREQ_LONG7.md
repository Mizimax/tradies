# GoldBot Forward Demo Runbook

## Candidate

Use this model for demo-forward validation:

```text
recent-freq-dir-long7-split12-cd8
```

Preset:

```text
mt5/Presets/GoldBot.forward-demo.recent-freq-dir-long7-split12-cd8.set
```

This is an exact-match preset for the current best forward-test candidate. It keeps `InpLotPer100Usd=0.010` so demo results are comparable to the MT5 Strategy Tester research results.

## Latest Evidence

Recent-year window:

```text
2025.06.01 to 2026.05.31
Trades: 84
PF: 2.30
DD: 25.31%
Net: +85,041.99 on 100,000 deposit
```

Six-month checks:

```text
2024-H2: FAIL, PF 0.76, 17 trades
2025-H1: PF 1.32, 25 trades
2026-H1: PF 2.44, 37 trades
```

Conclusion: good enough for demo-forward, not live-ready. The weak 2024-H2 window means a regime filter is still needed before any real-money rollout.

## Install And Compile

Install the current EA source and presets into the MT5 data folder:

```bash
bash scripts/install-mt5-source.sh
```

Compile:

```bash
bash scripts/compile-mt5-goldbot.sh
```

If command-line compile does not update `GoldBot.ex5`, open MetaEditor, open `MQL5/Experts/GoldBot/GoldBot.mq5`, and compile with `F7`. Required result: `0 errors`.

## MT5 Demo Setup

1. Open MT5 demo account.
2. Open `XAUUSD` on `M15`.
3. Attach `GoldBot` Expert Advisor.
4. Load preset:

```text
GoldBot.forward-demo.recent-freq-dir-long7-split12-cd8.set
```

5. Confirm:

```text
Algo Trading: enabled
InpPythonParityMode=false
InpLegacyParityMode=false
InpDebugOnly=false
InpSymbol=XAUUSD
InpAllowedLongEntryHours=7;12;14;16;18
InpAllowedShortEntryHours=7;8;10;21
InpTp1R=1.0
InpTp2R=1.5
InpTp3R=2.0
InpLadderFirstSplit=1
InpLadderOrderCount=2
InpMaxOpenTrades=2
InpMaxLaddersPerDay=10
```

## Stop Rules

Stop demo-forward and review if any happens:

```text
Equity drawdown reaches 10%
3 losing trading days in a row
Spread during entries is materially worse than tester assumptions
Pending orders fill very differently from Strategy Tester behavior
EA logs repeated order placement failures
```

## Weekly Review

Every week, export/copy:

```text
MQL5/Files/GoldBot/trades.csv
Account history report from MT5
Screenshots of open/closed positions if anything looks unusual
```

Review:

```text
signals accepted
pending orders placed
filled vs missed pending orders
TP1/TP2/TP3 hits
max-hold exits
drawdown
spread/slippage around entries
trade count per week
```

Expected rough pace from recent tests:

```text
About 84 trades/year
About 7 trades/month
About 1-2 trades/week on average
```
