# C+ Behavior Clone Gap v1

This is a black-box behavior profile from MT5 reports. No C+ EX5 code was decompiled or copied.

## Evidence Reports

- `cplus-classic-screenshot-mapped-XAUUSDs-M1-2026.06.01-2026.06.02-login703101-dep1000-1day.htm`
- `cplus-classic-screenshot-mapped-XAUUSDs-M1-2026.06.20-2026.06.23-login703101-dep1000-20to23.htm`

## Observed C+ Behavior

- Opens both buy and sell, sometimes close together.
- Base lot is `0.01`.
- Ladder lots reached `0.02` in the 1-day sample and `0.03` in the 20-23 Jun sample.
- Entry cadence averages roughly `34` minutes between entries in both valid samples.
- Many exits use `sl <price>` comments but are profitable, which points to EA-managed trailing stop or synthetic stop movement.
- Basket-like clusters exist where 3-5 trade deals occur at the exact same timestamp.
- Original screenshot/profile inputs use MA `20/50/100`, Stochastic `8/16/21`, levels `40/60`, distance `1200`, max lot `0.10`, max order `10`.

## CodexCGrid v1 Match

- Has original source code we control.
- Supports buy/sell, capped martingale, distance grid, money close, basket close, trailing stop, daily profit stop, DD guard.
- New preset `mt5/Presets/CodexCGrid.cplus-profile-v1-usd1000.set` maps the screenshot values into CodexCGrid inputs.

## Known Gaps

- Entry signal is not confirmed to match C+. CodexCGrid currently uses a simple MA/Stochastic rule.
- C+ can close and immediately re-enter at the same timestamp; CodexCGrid may be less aggressive depending on tick/bar gating.
- C+ comments show `Libra C+`, `0.0`, blank comments, and `sl <price>`; CodexCGrid comments differ.
- Step1/Step2 higher-timeframe order rules from C+ screenshots are not implemented in CodexCGrid yet.
- C+ may use hidden DLL/licensing/state logic. That behavior is not reproduced.

## Next Test

Run CodexCGrid with `CodexCGrid.cplus-profile-v1-usd1000.set` on the same 1-day window:

- symbol: `XAUUSD.s`
- period: `M1`
- date: `2026.06.01` to `2026.06.02`
- deposit: `1000`

Target comparison:

- C+ reference: net `138.85`, PF `3.40`, trades `40`, equity DD `4.39%`
- CodexCGrid clone-v1 should be evaluated by trade count, lot distribution, entry cadence, PF, and DD.

## 2026-07-01 Adjustment

The first `XAUUSD` test window with usable bars was `2026.06.29` to `2026.06.30`.

- `CodexCGrid.cplus-profile-v1-usd1000.set`: net `8.74`, trades `3`, equity DD `0.52%`.
- `cross-only` diagnostic (`MA_USE=false`, `STO_USE=false`, `STO_MA_USE=true`): net `-8.93`, PF `0.96`, trades `68`, equity DD `13.28%`.
- `CodexCGrid.cplus-profile-v2-usd1000.set` (`MA_USE=false`, `STO_USE=true`, `STO_MA_USE=true`): net `80.84`, PF `2.03`, trades `45`, equity DD `13.27%`.

The v2 preset is closer to the C+ behavior profile by trade count and cadence. It is not yet an exact clone because the hidden C+ Step1/Step2 and close/re-entry logic are still unknown.
