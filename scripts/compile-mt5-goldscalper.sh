#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${MT5_APP:-$HOME/Applications/MetaTrader 5.app}"
PREFIX="${MT5_PREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
WINE="$APP/Contents/SharedSupport/wine/bin/wine"
WINEPATH="$APP/Contents/SharedSupport/wine/bin/winepath"
METAEDITOR="$PREFIX/drive_c/Program Files/MetaTrader 5/metaeditor64.exe"
MT5_ROOT="$PREFIX/drive_c/Program Files/MetaTrader 5"
SOURCE="$MT5_ROOT/MQL5/Experts/GoldScalper/GoldScalper.mq5"
EX5="$MT5_ROOT/MQL5/Experts/GoldScalper/GoldScalper.ex5"
LOG="$MT5_ROOT/MQL5/Experts/GoldScalper/GoldScalper.log"

"$ROOT_DIR/scripts/install-mt5-source.sh" >/dev/null

before="$(stat -f '%m' "$EX5" 2>/dev/null || echo 0)"
rm -f "$LOG"

SOURCE_WIN="$(WINEPREFIX="$PREFIX" "$WINEPATH" -w "$SOURCE")"
INCLUDE_WIN="$(WINEPREFIX="$PREFIX" "$WINEPATH" -w "$MT5_ROOT/MQL5")"

WINEPREFIX="$PREFIX" "$WINE" "$METAEDITOR" "/compile:$SOURCE_WIN" "/include:$INCLUDE_WIN" /log >/tmp/goldscalper-metaeditor-compile.log 2>&1 &

echo "Compiling GoldScalper..."
for _ in $(seq 1 30); do
  sleep 1
  after="$(stat -f '%m' "$EX5" 2>/dev/null || echo 0)"
  if [[ "$after" != "$before" ]]; then
    echo "GoldScalper compiled: $EX5"
    if [[ -f "$LOG" ]]; then cat "$LOG"; fi
    exit 0
  fi
done
echo "Compile failed."
if [[ -f "$LOG" ]]; then cat "$LOG"; fi
exit 1
