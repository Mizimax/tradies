# MT5 Strategy Tester Guide

Use MT5 Strategy Tester as the source of truth for this EA.

## Install

Copy:

- `mt5/Experts/GoldBot/GoldBot.mq5` to `MQL5/Experts/GoldBot/GoldBot.mq5`
- `mt5/Include/GoldBot/*.mqh` to `MQL5/Include/GoldBot/*.mqh`
- `mt5/Presets/GoldBot.optimized.set` to `MQL5/Presets/GoldBot.optimized.set`

Compile `GoldBot.mq5` in MetaEditor.

## First Test

- Symbol: broker gold symbol, usually `XAUUSD` or `GOLD`
- Timeframe: M15
- Model: every tick based on real ticks when available
- Deposit/currency: match intended account
- Spread/commission: realistic broker settings
- Preset: `GoldBot.optimized.set`
- Start with `InpDebugOnly=true`

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
