# MT5 Strategy Tester Guide

Use MT5 Strategy Tester as the source of truth for this EA.

## Install

Copy:

- `mt5/Experts/GoldBot/GoldBot.mq5` to `MQL5/Experts/GoldBot/GoldBot.mq5`
- `mt5/Include/GoldBot/*.mqh` to `MQL5/Include/GoldBot/*.mqh`
- `mt5/Presets/GoldBot.optimized.set` to `MQL5/Presets/GoldBot.optimized.set`

Compile `GoldBot.mq5` in MetaEditor.

## Command-Line Backtest

This repo includes a macOS/Wine helper for the installed MetaTrader 5 app:

```bash
bash scripts/run-mt5-backtest.sh
```

It writes a temporary tester config under `mt5/backtests/config/`, copies the set file into `MQL5/Profiles/Tester`, launches MT5 with `/config`, and copies generated reports back to `mt5/backtests/reports/`.

MetaTrader requires a tester account. If MT5 already has a demo/broker account saved, the script can use it. Otherwise pass account details as environment variables:

```bash
MT5_LOGIN=12345678 MT5_SERVER="Broker-Demo" MT5_PASSWORD="password" bash scripts/run-mt5-backtest.sh
```

Do not commit generated config files; they may contain account details.

## First Test

- Symbol: broker gold symbol, usually `XAUUSD` or `GOLD`
- Timeframe: M15
- Model: every tick based on real ticks when available
- Deposit/currency: match intended account
- Spread/commission: realistic broker settings
- Preset: `GoldBot.optimized.set`
- For Python backtest parity, use `InpPythonParityMode=true`. This mode does not place broker orders; it simulates the Python candle backtest internally and writes `MQL5/Files/GoldBot/parity_trades.csv`.
- For live-style broker testing, use `InpPythonParityMode=false`.
- Compare the parity CSV with the Python baseline. In Strategy Tester, MT5 writes this file under `Tester/Agent-*/MQL5/Files/GoldBot/parity_trades.csv`, so the helper auto-detects the latest one:
  `python3 scripts/compare-mt5-python-parity.py`

## Optimization

Optimize only these parameters first:

- `InpRsiLongMax`
- `InpRsiShortMin`
- `InpAdxMin`
- `InpSlAtr`
- `InpMinRR`
- `InpMaxHoldBars`
- `InpCooldownBars`

Keep daily loss, daily target, max open trades, and magic number fixed during initial optimization.

## Acceptance

Before demo forward testing:

- No compile errors
- No lookahead behavior; trades occur only after closed M15 bars
- Daily loss gate blocks new entries
- Daily target gate blocks new entries
- Max open trades blocks new entries
- Pending ladder expires
- TP1/TP2/TP3 transitions appear in journal
