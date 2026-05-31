# Gold MT5 Expert Advisor

Primary architecture:

```text
MQL5 Expert Advisor -> MT5 Terminal -> Broker
```

This repo has been pivoted away from Cloudflare/OANDA/MetaApi production execution. The old TypeScript implementation is archived under `legacy/cloudflare-worker/`.

## Current MT5 Files

- `mt5/Experts/GoldBot/GoldBot.mq5`
- `mt5/Include/GoldBot/Indicators.mqh`
- `mt5/Include/GoldBot/SMC.mqh`
- `mt5/Include/GoldBot/Risk.mqh`
- `mt5/Include/GoldBot/TradeManager.mqh`
- `mt5/Presets/GoldBot.optimized.set`
- `mt5/backtests/README.md`

## Install Into MT5

Copy files into your MT5 data folder:

```text
mt5/Experts/GoldBot/GoldBot.mq5       -> MQL5/Experts/GoldBot/GoldBot.mq5
mt5/Include/GoldBot/*.mqh             -> MQL5/Include/GoldBot/*.mqh
mt5/Presets/GoldBot.optimized.set     -> MQL5/Presets/GoldBot.optimized.set
```

Then open MetaEditor and compile `GoldBot.mq5`.

For detailed macOS/Windows compile steps, see `MT5_COMPILE_GUIDE.md`.

To create a ready-to-copy zip:

```bash
bash scripts/package-mt5.sh
```

## Backtesting

Use MT5 Strategy Tester as the source of truth:

- Expert: `GoldBot`
- Symbol: broker gold symbol, usually `XAUUSD` or `GOLD`
- Timeframe: M15
- Model: every tick based on real ticks when available
- Preset: `GoldBot.optimized.set`

See `mt5/backtests/README.md`.

## Safety

Start with `InpDebugOnly=true`, then demo forward test before any live trading. This is research software, not financial advice.
