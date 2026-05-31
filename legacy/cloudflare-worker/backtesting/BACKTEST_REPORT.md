# Gold Bot Backtest Report

Dataset: `backtesting/results/xauusd_m15.csv`

Source: Hugging Face dataset `ZombitX64/xauusd-gold-price-historical-data-2004-2025`, file `XAU_15m_data.jsonl`.

Validation window: last 24 months of cached 15-minute XAUUSD candles.

Current best parameters:

| Parameter | Value |
|---|---:|
| EMA stack | 21 / 50 / 200 |
| RSI period | 10 |
| Long RSI max | 38 |
| Short RSI min | 40 |
| ADX min | 14 |
| ATR stop multiplier | 0.8 |
| Reward:risk | 2.0 |
| Max hold | 48 bars |
| Cooldown | 16 bars |
| Session filter | all |

Current best result:

| Metric | Result | Goal | Pass |
|---|---:|---:|---|
| Trades | 251 | >= 80 | yes |
| Win rate | 58.17% | >= 55% | yes |
| Profit factor | 2.68 | >= 1.8 | yes |
| Planned avg R:R | 2.0 | >= 2.0 | yes |
| Avg trades/day | 1.35 | >= 1.0 | yes |
| Expectancy | +0.69R/trade | > 0 | yes |
| Max drawdown | 10.30R | monitor | yes |

Notes:

- The simulator is intentionally conservative when stop and target are both touched in one candle: it counts the stop first.
- Open trades that do not hit SL/TP within `max_hold_bars` close at the final bar's close, capped to the original SL/TP R range.
- This is a research backtest, not approval for live trading. Paper trading should still compare broker fills, spread, slippage, and missed entries against the simulation.
