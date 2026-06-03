#!/usr/bin/env bash
APP="${MT5_APP:-$HOME/Applications/MetaTrader 5.app}"
PREFIX="${MT5_PREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
WINE="$APP/Contents/SharedSupport/wine/bin/wine"
MT5_ROOT="$PREFIX/drive_c/Program Files/MetaTrader 5"

WINEPREFIX="$PREFIX" "$WINE" "$MT5_ROOT/metaeditor64.exe" /compile:"$MT5_ROOT/MQL5/Experts/GoldScalper/GoldScalper.mq5" /log:"$MT5_ROOT/MQL5/Experts/GoldScalper/compile.log" || true
cat "$MT5_ROOT/MQL5/Experts/GoldScalper/compile.log" || echo "No log found"
