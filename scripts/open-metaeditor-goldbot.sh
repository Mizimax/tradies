#!/usr/bin/env bash
set -euo pipefail

APP="$HOME/Applications/MetaTrader 5.app"
PREFIX="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5"
WINE="$APP/Contents/SharedSupport/wine/bin/wine"
METAEDITOR="$PREFIX/drive_c/Program Files/MetaTrader 5/metaeditor64.exe"
GOLDBOT="C:\\Program Files\\MetaTrader 5\\MQL5\\Experts\\GoldBot\\GoldBot.mq5"

if [[ ! -x "$WINE" ]]; then
  echo "Wine launcher not found: $WINE" >&2
  exit 1
fi

if [[ ! -f "$METAEDITOR" ]]; then
  echo "MetaEditor not found: $METAEDITOR" >&2
  exit 1
fi

WINEPREFIX="$PREFIX" "$WINE" "$METAEDITOR" "$GOLDBOT" >/tmp/goldbot-metaeditor.log 2>&1 &
echo "Opening MetaEditor for GoldBot.mq5..."
echo "If a macOS or Wine first-run prompt appears, accept it, then click Compile in MetaEditor."
