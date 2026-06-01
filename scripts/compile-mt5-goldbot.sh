#!/usr/bin/env bash
set -euo pipefail

APP="${MT5_APP:-$HOME/Applications/MetaTrader 5.app}"
PREFIX="${MT5_PREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
WINE="$APP/Contents/SharedSupport/wine/bin/wine"
METAEDITOR="$PREFIX/drive_c/Program Files/MetaTrader 5/metaeditor64.exe"
MT5_ROOT="$PREFIX/drive_c/Program Files/MetaTrader 5"
SOURCE="$MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.mq5"
EX5="$MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.ex5"
LOG="$MT5_ROOT/MQL5/Experts/GoldBot/compile.log"

if [[ ! -x "$WINE" ]]; then
  echo "Wine launcher not found: $WINE" >&2
  exit 1
fi

if [[ ! -f "$METAEDITOR" ]]; then
  echo "MetaEditor not found: $METAEDITOR" >&2
  exit 1
fi

before="$(stat -f '%m' "$EX5" 2>/dev/null || echo 0)"
rm -f "$LOG"

WINEPREFIX="$PREFIX" "$WINE" "$METAEDITOR" "/compile:$SOURCE" "/log:$LOG" >/tmp/goldbot-metaeditor-compile.log 2>&1 &

for _ in $(seq 1 30); do
  sleep 1
  after="$(stat -f '%m' "$EX5" 2>/dev/null || echo 0)"
  if [[ "$after" != "$before" ]]; then
    echo "GoldBot compiled: $EX5"
    exit 0
  fi
done

echo "MetaEditor command-line compile did not update GoldBot.ex5." >&2
echo "Open MetaEditor and press Compile, then rerun the backtest." >&2
echo "Source:   $SOURCE" >&2
echo "Compiled: $EX5" >&2
if [[ -f "$LOG" ]]; then
  echo "Compile log: $LOG" >&2
fi
exit 1
