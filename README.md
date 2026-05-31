# Gold Trading Bot

Cloudflare Worker scaffold for an autonomous XAU/USD trading bot using:

- Smart Money Concepts gates
- EMA, RSI, VWAP, ATR, and ADX confluence
- OANDA dev/paper broker adapter
- MetaApi/MT5 production broker adapter
- Python backtesting and optimization loop

## Backtest Status

The current best 24-month cached XAU/USD 15m backtest passes the configured research goals:

- Trades: 251
- Win rate: 58.17%
- Profit factor: 2.68
- Planned R:R: 2.0
- Avg trades/day: 1.35
- Expectancy: +0.69R/trade

See `backtesting/BACKTEST_REPORT.md` and `backtesting/results/backtest_best_24m.json`.

## Commands

```bash
pnpm install
pnpm exec tsc --noEmit
pnpm test
pnpm exec wrangler deploy --dry-run
python3 -m py_compile backtesting/*.py
PYTHONPATH=backtesting python3 backtesting/run_backtest.py
```

## Notes

This is research/paper-trading software, not approval for live trading. Broker credentials, real KV namespace IDs, slippage/spread checks, paper-trade reconciliation, and live risk controls must be completed before any production use.
