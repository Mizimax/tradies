#!/usr/bin/env bash
set -euo pipefail

APP="${MT5_APP:-$HOME/Applications/MetaTrader 5.app}"
PREFIX="${MT5_PREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
WINE="$APP/Contents/SharedSupport/wine/bin/wine"
WINEPATH="$APP/Contents/SharedSupport/wine/bin/winepath"
TERMINAL="$PREFIX/drive_c/Program Files/MetaTrader 5/terminal64.exe"
MT5_ROOT="$PREFIX/drive_c/Program Files/MetaTrader 5"
TESTER_PROFILE_DIR="$MT5_ROOT/MQL5/Profiles/Tester"
MT5_REPORT_DIR="$MT5_ROOT/reports"

SYMBOL="${MT5_SYMBOL:-XAUUSD}"
PERIOD="${MT5_PERIOD:-M15}"
FROM_DATE="${MT5_FROM:-2025.01.01}"
TO_DATE="${MT5_TO:-2026.05.31}"
DEPOSIT="${MT5_DEPOSIT:-1000}"
LEVERAGE="${MT5_LEVERAGE:-100}"
MODEL="${MT5_MODEL:-4}"
LOGIN="${MT5_LOGIN:-}"
SERVER="${MT5_SERVER:-}"
PASSWORD="${MT5_PASSWORD:-}"
REPORT_NAME="${MT5_REPORT:-GoldBot-${SYMBOL}-${PERIOD}-${FROM_DATE}-${TO_DATE}}"

CONFIG_DIR="$PWD/mt5/backtests/config"
REPORT_DIR="$PWD/mt5/backtests/reports"
mkdir -p "$CONFIG_DIR" "$REPORT_DIR"

CONFIG="$CONFIG_DIR/goldbot-${SYMBOL}-${PERIOD}.ini"
REPORT_PATH="$REPORT_DIR/$REPORT_NAME"
MT5_REPORT_PATH="reports\\$REPORT_NAME"

if [[ ! -x "$WINE" ]]; then
  echo "Wine launcher not found: $WINE" >&2
  exit 1
fi

if [[ ! -f "$TERMINAL" ]]; then
  echo "MT5 terminal not found: $TERMINAL" >&2
  exit 1
fi

if [[ ! -f "$MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.ex5" ]]; then
  echo "GoldBot.ex5 not found. Compile GoldBot in MetaEditor first." >&2
  exit 1
fi

if [[ "$MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.mq5" -nt "$MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.ex5" ]]; then
  echo "GoldBot.ex5 is older than GoldBot.mq5. Compile GoldBot in MetaEditor first." >&2
  echo "Source:   $MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.mq5" >&2
  echo "Compiled: $MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.ex5" >&2
  exit 1
fi

mkdir -p "$TESTER_PROFILE_DIR" "$MT5_REPORT_DIR"
cp mt5/Presets/GoldBot.optimized.set "$TESTER_PROFILE_DIR/GoldBot.optimized.set"

{
if [[ -n "$LOGIN" || -n "$SERVER" || -n "$PASSWORD" ]]; then
  echo "[Common]"
  [[ -n "$LOGIN" ]] && echo "Login=$LOGIN"
  [[ -n "$SERVER" ]] && echo "Server=$SERVER"
  [[ -n "$PASSWORD" ]] && echo "Password=$PASSWORD"
  echo "KeepPrivate=1"
  echo
fi

cat <<INI
[Tester]
Expert=GoldBot\\GoldBot.ex5
ExpertParameters=GoldBot.optimized.set
Symbol=$SYMBOL
Period=$PERIOD
Optimization=0
Model=$MODEL
FromDate=$FROM_DATE
ToDate=$TO_DATE
ForwardMode=0
Deposit=$DEPOSIT
Currency=USD
Leverage=1:$LEVERAGE
ExecutionMode=0
Visual=0
Report=$MT5_REPORT_PATH
ReplaceReport=1
ShutdownTerminal=1
INI
} > "$CONFIG"

if [[ -n "$LOGIN" ]]; then
  printf 'Login=%s\n' "$LOGIN" >> "$CONFIG"
fi

echo "Launching MT5 Strategy Tester"
echo "Config: $CONFIG"
echo "Report: $REPORT_PATH.htm or $REPORT_PATH.xml"
echo "MT5 report target: $MT5_ROOT/$MT5_REPORT_PATH.htm"
echo
echo "Tip: override settings with env vars, e.g.:"
echo "  MT5_SYMBOL=GOLD MT5_FROM=2025.01.01 MT5_TO=2025.12.31 bash scripts/run-mt5-backtest.sh"
echo

if [[ -x "$WINEPATH" ]]; then
  CONFIG_ARG="$(WINEPREFIX="$PREFIX" "$WINEPATH" -w "$CONFIG")"
else
  CONFIG_ARG="$CONFIG"
fi

if [[ "${MT5_STOP_RUNNING:-1}" == "1" ]]; then
  pkill -f "C:\\\\Program Files\\\\MetaTrader 5\\\\terminal64.exe" 2>/dev/null || true
  pkill -f "terminal64.exe" 2>/dev/null || true
  sleep 2
fi

WINEPREFIX="$PREFIX" "$WINE" "$TERMINAL" "/config:$CONFIG_ARG"

if [[ -f "$MT5_ROOT/reports/$REPORT_NAME.htm" ]]; then
  cp "$MT5_ROOT/reports/$REPORT_NAME.htm" "$REPORT_DIR/$REPORT_NAME.htm"
fi

if [[ -f "$MT5_ROOT/reports/$REPORT_NAME.xml" ]]; then
  cp "$MT5_ROOT/reports/$REPORT_NAME.xml" "$REPORT_DIR/$REPORT_NAME.xml"
fi
