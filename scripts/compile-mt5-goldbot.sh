#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${MT5_APP:-$HOME/Applications/MetaTrader 5.app}"
PREFIX="${MT5_PREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
WINE="$APP/Contents/SharedSupport/wine/bin/wine"
WINEPATH="$APP/Contents/SharedSupport/wine/bin/winepath"
METAEDITOR="$PREFIX/drive_c/Program Files/MetaTrader 5/metaeditor64.exe"
MT5_ROOT="$PREFIX/drive_c/Program Files/MetaTrader 5"
SOURCE="$MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.mq5"
EX5="$MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.ex5"
LOG="$MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.log"

if [[ ! -x "$WINE" ]]; then
  echo "Wine launcher not found: $WINE" >&2
  exit 1
fi

if [[ ! -x "$WINEPATH" ]]; then
  echo "winepath launcher not found: $WINEPATH" >&2
  exit 1
fi

if [[ ! -f "$METAEDITOR" ]]; then
  echo "MetaEditor not found: $METAEDITOR" >&2
  exit 1
fi

"$ROOT_DIR/scripts/install-mt5-source.sh" >/dev/null

before="$(stat -f '%m' "$EX5" 2>/dev/null || echo 0)"
rm -f "$LOG"

SOURCE_WIN="$(WINEPREFIX="$PREFIX" "$WINEPATH" -w "$SOURCE")"
INCLUDE_WIN="$(WINEPREFIX="$PREFIX" "$WINEPATH" -w "$MT5_ROOT/MQL5")"

WINEPREFIX="$PREFIX" "$WINE" "$METAEDITOR" "/compile:$SOURCE_WIN" "/include:$INCLUDE_WIN" /log >/tmp/goldbot-metaeditor-compile.log 2>&1 &

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
