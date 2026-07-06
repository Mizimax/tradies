#!/usr/bin/env bash
# Pull GoldBot's live demo journal and summarize against DEMO_FORWARD_CHECKLIST.md
set -euo pipefail
MT5_ROOT="${MT5_PREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}/drive_c/Program Files/MetaTrader 5"
SRC="$MT5_ROOT/MQL5/Files/GoldBot/trades.csv"
DEST="mt5/backtests/reports/GoldBot-demo-forward-live.trades.csv"
if [[ ! -f "$SRC" ]]; then
  echo "No live journal found yet at: $SRC"
  echo "EA may not be attached/running, or no events logged yet."
  exit 1
fi
cp "$SRC" "$DEST"
echo "Copied live journal -> $DEST ($(wc -l < "$DEST") lines)"
echo ""
python3 scripts/analyze-mt5-trades.py "$DEST"
echo ""
python3 scripts/analyze-mt5-trades.py --attribution "$DEST" 2>/dev/null | head -20 || true
