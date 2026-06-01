# MT5 Real-Mode Strategy Tester Guide

Use MT5 Strategy Tester real broker execution as the source of truth for this EA.

## Install And Compile

Install the current repo copy into the MT5 data folder:

```bash
bash scripts/install-mt5-source.sh
```

Compile `GoldBot.mq5` in MetaEditor. The helper can try command-line compile and verifies whether `GoldBot.ex5` changed:

```bash
bash scripts/compile-mt5-goldbot.sh
```

If command-line compile does not update `GoldBot.ex5`, open MetaEditor and press `F7` / Compile manually. The EA must compile with `0 errors`.

## Real-Mode Backtest

Default mode is real broker execution:

```bash
MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 bash scripts/run-mt5-backtest.sh
```

The helper installs current source, checks that `GoldBot.ex5` is newer than installed `.mq5/.mqh` files, writes a temporary tester config under `mt5/backtests/config/`, launches MT5 with `/config`, and copies generated reports back to `mt5/backtests/reports/`.

Useful overrides:

```bash
MT5_SYMBOL=GOLD MT5_FROM=2025.01.01 MT5_TO=2025.12.31 bash scripts/run-mt5-backtest.sh
MT5_LOGIN=12345678 MT5_SERVER="Broker-Demo" MT5_PASSWORD="password" bash scripts/run-mt5-backtest.sh
```

Do not commit generated config files; they may contain account details.

## Real-Mode Outputs

Check these artifacts after each run:

- Fresh MT5 HTML/XML report under `mt5/backtests/reports/`
- Real execution journal: `MQL5/Files/GoldBot/trades.csv`, usually under the Strategy Tester agent folder
- Pending order success/failure entries in `trades.csv`
- Gate/skip logs in the MT5 tester journal
- SMC candidate entries showing H4/H1/M15 gate state and score

Real-mode acceptance is based on Strategy Tester reports, broker-style order behavior, and `trades.csv`. `parity_trades.csv` is not a real-mode acceptance artifact.

## Optional Parity Diagnostic

Python parity mode is disabled by default. Use it only when intentionally debugging the old Python simulator:

```bash
MT5_PARITY=1 MT5_DEPOSIT=100000 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 bash scripts/run-mt5-backtest.sh
python3 scripts/compare-mt5-python-parity.py --from-date 2023-10-01 --to-date 2025-09-30 --diff-trades --diff-signals
```

`MT5_PARITY=1` sets `InpPythonParityMode=true` and injects `InpPythonParityStart` from `MT5_FROM`. Without `MT5_PARITY=1`, the run script forces real mode.

## Optimization

Optimize real-mode behavior first with broker-realistic spread, commission, contract size, and tick data. Start with:

- `InpRsiLongMax`
- `InpRsiShortMin`
- `InpAdxMin`
- `InpSlAtr`
- `InpMinRR`
- `InpMaxHoldBars`
- `InpCooldownBars`

Keep daily loss, daily target, max open trades, and magic number fixed during initial optimization.

## Demo Forward Test

Before live money:

- Run on an MT5 demo account for at least 2 weeks.
- Compare demo fills, skipped signals, drawdown, and trade frequency against Strategy Tester.
- Confirm daily loss and daily target block new entries.
- Confirm max open trades blocks new signals.
- Confirm pending ladder expiry.
- Confirm filled positions close after max hold bars.
- Confirm TP1/TP2/TP3 journal transitions.
