# DZV_Style_ADR_System

Clean-room MT5 ADR daily-zone research system for this repo.

This project is inspired only by publicly observable ADR/daily-zone concepts. It does not claim formula identity with any protected, private, invite-only, or closed-source Daily Zone Volatility indicator.

## Existing-Resource Audit

| Reference | Location | License | Useful concepts | Reuse decision |
| --- | --- | --- | --- | --- |
| MQL5 `CopyRates` documentation | https://www.mql5.com/en/docs/series/copyrates | MetaQuotes docs | Correct D1/rate-copy API usage and return-value checks | Rewrite clean-room using documented APIs |
| MQL5 `CopyBuffer` documentation | https://www.mql5.com/en/docs/series/copybuffer | MetaQuotes docs | Indicator-buffer validation and completed-candle reads | Rewrite clean-room using documented APIs |
| MQL5 `CTrade` documentation | https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade | MetaQuotes docs | Trade request wrapper and retcode inspection | Rewrite clean-room using documented APIs |
| MQL5 object functions | https://www.mql5.com/en/docs/objects | MetaQuotes docs | Chart-object creation, updates, and deletion | Rewrite clean-room using documented APIs |
| Existing repo GoldBot/GoldScalper workflow | `scripts/install-mt5-source.sh`, `scripts/run-mt5-backtest.sh` | Project source | MT5/Wine install, compile, report, and journal conventions | Adapt workflow only; do not reuse strategy logic |

No protected indicator code, decompiled source, scraped formulas, martingale/grid/recovery logic, or closed-source implementation details are used.

## Architecture

```text
mt5/Include/DZVStyle/*.mqh
  Shared ADR, zone, indicator snapshot, signal, risk, chart, calibration, and execution helpers

mt5/Indicators/DZV_Style_ADR_Indicator.mq5
  Visual chart indicator for base price, Z1-Z7 zones, ADR/range statistics, and labels

mt5/Experts/DZV_Style_ADR/DZV_Style_ADR_EA.mq5
  Signal-only, simulated-trading, and explicitly gated live-trading EA

scripts/compile-mt5-dzv.sh
scripts/run-dzv-candidate.py
  Repo-native MT5 compile and Strategy Tester helpers
```

GoldBot, GoldScalper, and BTCScalper strategy logic remains separate.

## Safety Defaults

- `InpSystemMode=DZV_MODE_SIGNAL_ONLY`
- `InpAllowLiveOrderExecution=false`
- No real trade can be sent unless both live mode and the explicit live-order flag are enabled.
- Signals and simulated trades are written to `MQL5/Files/DZV_Style_ADR/trades.csv`, which the repo runner copies beside MT5 reports.
- Duplicate signal IDs are persisted with MT5 GlobalVariables.
- Other Magic Numbers and manual positions are not closed or modified.

## Installation

Install into the local MT5 data folder:

```bash
bash scripts/install-mt5-source.sh
```

Compile the EA:

```bash
bash scripts/compile-mt5-dzv.sh
```

Manual files:

```text
mt5/Experts/DZV_Style_ADR/DZV_Style_ADR_EA.mq5 -> MQL5/Experts/DZV_Style_ADR/
mt5/Indicators/DZV_Style_ADR_Indicator.mq5     -> MQL5/Indicators/
mt5/Scripts/DZVStyle/DZV_Style_ADR_SelfTest.mq5 -> MQL5/Scripts/DZVStyle/
mt5/Include/DZVStyle/*.mqh                      -> MQL5/Include/DZVStyle/
mt5/Presets/DZV_Style_ADR.signal.set            -> MQL5/Profiles/Tester/
```

## Indicator Usage

Attach `DZV_Style_ADR_Indicator` to a chart. It calculates zones from completed D1 candles, keeps today’s anchor stable through the broker day, and updates chart objects in place.

Important inputs:

- `InpADRMode`: high-low, true range, or directional excursion.
- `InpZoneBase`: current daily open, previous close, previous midpoint, or previous typical price.
- `InpZ1...InpZ7` multipliers: must be positive and strictly increasing.
- `InpVisibleZoneCount`, `InpShowLabels`, `InpCompactDashboard`: visual display controls.

## EA Usage

Use `DZV_Style_ADR.signal.set` for first Strategy Tester runs. It is signal-only and cannot place live orders.

Run a dry-run candidate command:

```bash
python3 scripts/run-dzv-candidate.py signal-default --dry-run
```

Run signal-only XAUUSD M15:

```bash
WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all \
python3 scripts/run-dzv-candidate.py signal-default \
  --from-date 2024.06.01 --to-date 2026.05.31 \
  --deposit 100000 --report-suffix 2024-2026
```

Run simulation mode:

```bash
WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all \
python3 scripts/run-dzv-candidate.py sim-default \
  --from-date 2024.06.01 --to-date 2026.05.31 \
  --deposit 100000 --report-suffix 2024-2026
```

Run Z2 support/resistance band simulation with fixed dollar-style distances:

```bash
WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all \
python3 scripts/run-dzv-candidate.py z2-band-tp15 \
  --from-date 2026.01.01 --to-date 2026.06.30 \
  --deposit 100000 --report-suffix 2026h1
```

`z2-band-tp15` places simulated pending orders once per broker day at both edges of the Z2 support/resistance band:

- Buy limits at lower Z1 and lower Z2.
- Sell limits at upper Z1 and upper Z2.
- Stop distance: `10.0` price units.
- Target distance: `15.0` price units.

`z2-band-tp20` uses the same entries with a `20.0` price-unit target. These are simulation-only research candidates; live broker pending orders are not enabled for this mode.

## Calibration

To export calculated zones, set:

```text
InpExportCalibration=true
```

The EA writes:

```text
MQL5/Files/DZVStyle/calibration-output.csv
```

To compare manually recorded observed zones, place this file:

```text
MQL5/Files/DZVStyle/calibration.csv
```

Expected CSV columns:

```text
Date,Symbol,ObservedBase,U1,U2,U3,U4,U5,U6,U7,L1,L2,L3,L4,L5,L6,L7
```

Then set:

```text
InpCompareCalibrationFile=true
```

Output:

```text
MQL5/Files/DZVStyle/calibration-comparison.csv
```

## Testing

Static checks after script edits:

```bash
python3 -m py_compile scripts/run-dzv-candidate.py
bash -n scripts/install-mt5-source.sh scripts/compile-mt5-dzv.sh scripts/package-mt5-dzv.sh
git diff --check
```

MQL5 compile is the real gate:

```bash
bash scripts/compile-mt5-dzv.sh
```

Optional self-test script inside MT5:

```text
Scripts/DZVStyle/DZV_Style_ADR_SelfTest
```

Acceptance checks:

- EA and indicator produce matching daily zones.
- Current incomplete D1 candle is excluded from ADR.
- Entry logic uses completed candles.
- Historical objects are not repainted with future ADR values.
- Signal-only and simulated modes do not place real orders.
- Live mode still blocks orders unless `InpAllowLiveOrderExecution=true`.
- Invalid zones, invalid indicator buffers, invalid stops, or excessive spread block entries safely.

## Known Limitations

- The v1 simulation supports one open simulated DZV position per attached EA instance.
- The visual indicator renders the current broker day; historical-zone rendering is intentionally deferred.
- Live execution is present but should remain disabled until signal and simulation behavior is validated by Strategy Tester and demo-forward testing.
- Profitability is unknown; this implementation is for correctness, calibration, and research evidence.
