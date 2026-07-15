# QBR v1.13 Aggressive Research

QBR v1.13 is a separate aggressive research track for `XAUUSD`, a USD 1,000
account, and 1:100 leverage. It does not change GoldBot or GoldScalper.

## Evidence contract

- Build tag: `QBR-1.13-aggressive`
- Tester model: every tick based on real ticks
- Minimum accepted history quality: 99%
- MT5 report net profit must reconcile independently with `deals.csv` and
  `baskets.csv` within USD 0.01. Deal tickets must be unique, basket exit-deal
  counts must equal the deal audit, and unique closed position identifiers must
  equal both basket totals and MT5 `Total Trades`.
- A missing native-SL basket makes the analyzer and candidate run fail.

## Compile and smoke test

```bash
bash scripts/compile-mt5-qbr.sh

WINEDLLOVERRIDES=mmdevapi=d WINEDEBUG=-all \
python3 scripts/run-qbr-candidate.py v113-control \
  --from-date 2026.01.01 --to-date 2026.01.07 \
  --deposit 1000 --leverage 100 --report-suffix smoke
```

Port 3000 must be free or owned by MetaTester. Do not stop an unrelated dev
server without confirming ownership first.

## Candidate ladder

Run candidates one at a time in this order. The runner enforces the evidence
dependencies: `lock40` inherits the better of `stop60`/`stop45`, Q-Sync and
confidence inherit that selected loss profile, M5 is refused when the M15
candidate already reaches 60 trades/month, and scaling is refused unless a
base-risk candidate passed the discovery gate.

```text
v113-control
v113-minlot-cap
v113-minlot-quality-hours
v113-stop60
v113-stop45
v113-lock40
v113-qsync22
v113-conf64
v113-m5-15-30
v113-m5-20-40
v113-scale100
v113-scale150
v113-scale200
```

Use `2026.01.01` through `2026.06.30` for the current Exness real-tick
window. M5 candidates keep M15/H4 regime authority and admit only closed-bar
pullback, failed-breakout, and breakout-retest triggers.

`v113-minlot-quality-hours` is an evidence-driven recovery candidate added
after the unrestricted min-lot run failed. It leaves normally risk-sized
control entries unchanged and permits the broker-minimum fallback only during
`02,03,06,10,13,16,17,18,19,20` broker hours. This is discovery evidence from
the 2026 H1 sample and must be treated as overfit until longer-window and
forward validation confirm it.

## Acceptance

The analyzer writes `analysis_summary.json` and `analysis_summary.md` beside
each report. Discovery candidates require 360 trades, 70% win rate, PF 1.30,
equity DD at most 10%, and net profit above the v1.12 control. Scaled
candidates require 70% win rate, PF 1.20, equity DD at most 25%, at least four
positive months, and no permanent equity safety stop.

The 50% monthly objective is the geometric mean of calendar-month returns. Net
results are always shown as both USD and percentage of the initial deposit. If
the target is not achieved, the result is explicitly `target unmet`; no
candidate is promoted by relaxing the safety gates.

A six-month pass is still **unproven research**, not deployment evidence. The
repo's promotion rule requires materially longer 1-year and 2-year real-tick
windows before demo-forward. The current Exness cache only provides the 2026
window at the required quality, so a candidate cannot become deployment-ready
until those longer >=99% real-tick windows are available. After that it still
requires at least four demo-forward weeks and 100 closed trades before any
real-money consideration.
