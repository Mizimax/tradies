#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${MT5_APP:-$HOME/Applications/MetaTrader 5.app}"
if [[ ! -d "$APP" && -d "/Applications/MetaTrader 5.app" ]]; then
  APP="/Applications/MetaTrader 5.app"
fi
PREFIX="${MT5_PREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
WINE="$APP/Contents/SharedSupport/wine/bin/wine"
WINEPATH="$APP/Contents/SharedSupport/wine/bin/winepath"
# Fallback to wine64 if wine doesn't exist
if [[ ! -x "$WINE" && -x "$APP/Contents/SharedSupport/wine/bin/wine64" ]]; then
  WINE="$APP/Contents/SharedSupport/wine/bin/wine64"
fi
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
AGENT_PORT="${MT5_AGENT_PORT:-3000}"
LOGIN="${MT5_LOGIN:-}"
SERVER="${MT5_SERVER:-}"
PASSWORD="${MT5_PASSWORD:-}"
REPORT_NAME="${MT5_REPORT:-GoldBot-${SYMBOL}-${PERIOD}-${FROM_DATE}-${TO_DATE}}"
PARITY="${MT5_PARITY:-0}"
INPUT_OVERRIDES="${MT5_INPUT_OVERRIDES:-}"
EXPERT="${MT5_EXPERT:-GoldBot\\GoldBot.ex5}"
PRESET="${MT5_PRESET:-GoldBot.optimized.set}"

# Derive the expert directory name from the path (e.g. GoldBot\GoldBot.ex5 -> GoldBot)
EXPERT_DIR="${EXPERT%%\\*}"
EXPERT_FILE="${EXPERT##*\\}"
INCLUDE_EXPERT_DIR="${MT5_INCLUDE_DIR:-$EXPERT_DIR}"

CONFIG_DIR="$PWD/mt5/backtests/config"
REPORT_DIR="$PWD/mt5/backtests/reports"
mkdir -p "$CONFIG_DIR" "$REPORT_DIR"

CONFIG="$CONFIG_DIR/${EXPERT_DIR}-${SYMBOL}-${PERIOD}.ini"
REPORT_PATH="$REPORT_DIR/$REPORT_NAME"
MT5_REPORT_PATH="reports\\$REPORT_NAME"
RUNTIME_SET_NAME="${EXPERT_DIR}.runtime.set"
RUNTIME_SET="$TESTER_PROFILE_DIR/$RUNTIME_SET_NAME"
RUN_STAMP="$CONFIG_DIR/$REPORT_NAME.run-stamp"

if [[ ! -x "$WINE" ]]; then
  echo "Wine launcher not found: $WINE" >&2
  exit 1
fi

if [[ ! -f "$TERMINAL" ]]; then
  echo "MT5 terminal not found: $TERMINAL" >&2
  exit 1
fi

"$ROOT_DIR/scripts/install-mt5-source.sh" >/dev/null

if [[ ! -f "$MT5_ROOT/MQL5/Experts/$EXPERT_DIR/$EXPERT_FILE" ]]; then
  echo "$EXPERT_FILE not found. Compile $EXPERT_DIR in MetaEditor first." >&2
  exit 1
fi

NEWER_SOURCE="$(find "$MT5_ROOT/MQL5/Experts/$EXPERT_DIR" "$MT5_ROOT/MQL5/Include/$INCLUDE_EXPERT_DIR" \( -name '*.mq5' -o -name '*.mqh' \) -newer "$MT5_ROOT/MQL5/Experts/$EXPERT_DIR/$EXPERT_FILE" -print -quit 2>/dev/null || true)"
if [[ -n "$NEWER_SOURCE" ]]; then
  echo "$EXPERT_FILE is older than the installed $EXPERT_DIR source. Compile in MetaEditor first." >&2
  echo "Changed source: $NEWER_SOURCE" >&2
  echo "Compiled: $MT5_ROOT/MQL5/Experts/$EXPERT_DIR/$EXPERT_FILE" >&2
  exit 1
fi

mkdir -p "$TESTER_PROFILE_DIR" "$MT5_REPORT_DIR"
cp "mt5/Presets/$PRESET" "$RUNTIME_SET"

if [[ "$PARITY" == "1" || "$PARITY" == "true" || "$PARITY" == "TRUE" ]]; then
  PARITY_MODE="true"
  PARITY_START="$FROM_DATE 00:00"
else
  PARITY_MODE="false"
  PARITY_START=""
fi

if [[ "$EXPERT_DIR" == "GoldBot" ]]; then
awk -v parity_mode="$PARITY_MODE" -v parity_start="$PARITY_START" '
  BEGIN { seen_parity = 0; seen_start = 0 }
  /^InpPythonParityMode=/ {
    print "InpPythonParityMode=" parity_mode
    seen_parity = 1
    next
  }
  /^InpPythonParityStart=/ {
    print "InpPythonParityStart=" parity_start
    seen_start = 1
    next
  }
  { print }
  END {
    if (!seen_parity)
      print "InpPythonParityMode=" parity_mode
    if (!seen_start)
      print "InpPythonParityStart=" parity_start
  }
' "$RUNTIME_SET" > "$RUNTIME_SET.tmp"
mv "$RUNTIME_SET.tmp" "$RUNTIME_SET"
fi

if [[ -n "$INPUT_OVERRIDES" ]]; then
  while IFS= read -r override; do
    [[ -z "$override" ]] && continue
    if [[ "$override" != *=* ]]; then
      echo "Invalid MT5_INPUT_OVERRIDES entry: $override" >&2
      exit 1
    fi
    key="${override%%=*}"
    value="${override#*=}"
    if grep -q "^${key}=" "$RUNTIME_SET"; then
      awk -v key="$key" -v value="$value" '
        index($0, key "=") == 1 { print key "=" value; next }
        { print }
      ' "$RUNTIME_SET" > "$RUNTIME_SET.tmp"
      mv "$RUNTIME_SET.tmp" "$RUNTIME_SET"
    else
      printf '%s=%s\n' "$key" "$value" >> "$RUNTIME_SET"
    fi
  done <<< "$INPUT_OVERRIDES"
fi

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
Expert=$EXPERT
ExpertParameters=$RUNTIME_SET_NAME
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
echo "Mode: $([[ "$PARITY_MODE" == "true" ]] && echo "Python parity diagnostic" || echo "Real broker execution")"
echo
echo "Tip: override settings with env vars, e.g.:"
echo "  MT5_SYMBOL=GOLD MT5_FROM=2025.01.01 MT5_TO=2025.12.31 bash scripts/run-mt5-backtest.sh"
echo "  MT5_PARITY=1 MT5_FROM=2023.10.01 MT5_TO=2025.09.30 bash scripts/run-mt5-backtest.sh"
echo

if [[ -x "$WINEPATH" ]]; then
  CONFIG_ARG="$(WINEPREFIX="$PREFIX" "$WINEPATH" -w "$CONFIG")"
else
  CONFIG_ARG="$CONFIG"
fi

# Prevent malformed-report recovery from copying a stale journal from a previous
# tester run. The EA normally resets its journal on init, but if MT5 exits early
# or exports a blank report, stale files under Tester/MQL5/Files can otherwise
# look like fresh evidence.
find "$MT5_ROOT/Tester" "$MT5_ROOT/MQL5/Files" -path "*/$EXPERT_DIR/trades.csv" -type f -delete 2>/dev/null || true
touch "$RUN_STAMP"

if [[ "${MT5_STOP_RUNNING:-1}" == "1" ]]; then
  # Kill the terminal only. If a valid MetaTester listener is already present,
  # the guard below will reuse it; otherwise the terminal starts its local tester agent.
  pkill -f "C:\\\\Program Files\\\\MetaTrader 5\\\\terminal64.exe" 2>/dev/null || true
  pkill -f "terminal64.exe" 2>/dev/null || true
  sleep 2
fi

# Guard the local tester agent port before launching MT5. The terminal owns
# starting its registered local MetaTester agent; if another process has this
# port, MT5 can connect Core 1 to the wrong listener and export a blank report.
metatester_listener_pids() {
  lsof -nP -iTCP:"$AGENT_PORT" -sTCP:LISTEN -t 2>/dev/null || true
}

is_metatester_pid() {
  local pid="$1"
  ps -p "$pid" -o command= 2>/dev/null | grep -qi 'metatester64\.exe'
}

LISTENER_PIDS="$(metatester_listener_pids)"
if [[ -n "$LISTENER_PIDS" ]]; then
  HAS_METATESTER_LISTENER=0
  while IFS= read -r pid; do
    [[ -z "$pid" ]] && continue
    if is_metatester_pid "$pid"; then HAS_METATESTER_LISTENER=1; fi
  done <<< "$LISTENER_PIDS"

  # Wine exposes the same listening socket through both wineserver and the
  # metatester process on macOS. The short lsof command name can also appear as
  # "metateste". Trust the full ps command line when any owning PID is the
  # registered MetaTester; otherwise treat the port as a real collision.
  if [[ "$HAS_METATESTER_LISTENER" != "1" ]]; then
    echo "Port $AGENT_PORT is already used by a non-MetaTester process:" >&2
    lsof -nP -iTCP:"$AGENT_PORT" -sTCP:LISTEN >&2 || true
    echo "Stop that process before running MT5; the terminal needs this port for its local tester agent." >&2
    exit 1
  fi

  echo "MetaTester already running on port $AGENT_PORT — reusing session"
else
  echo "MetaTester port $AGENT_PORT is free; MT5 terminal will start its local tester agent"
fi

set +e
WINEPREFIX="$PREFIX" "$WINE" "$TERMINAL" "/config:$CONFIG_ARG"
WINE_STATUS=$?
set -e

if [[ "$WINE_STATUS" != "0" ]]; then
  echo "Warning: MT5/Wine exited with status $WINE_STATUS; attempting artifact recovery." >&2
fi

REPORT_COPIED=0
ARTIFACT_COPIED=0
COPIED_REPORT=""
if [[ -f "$MT5_ROOT/reports/$REPORT_NAME.htm" ]]; then
  cp "$MT5_ROOT/reports/$REPORT_NAME.htm" "$REPORT_DIR/$REPORT_NAME.htm"
  REPORT_COPIED=1
  ARTIFACT_COPIED=1
  COPIED_REPORT="$REPORT_DIR/$REPORT_NAME.htm"
fi

if [[ -f "$MT5_ROOT/reports/$REPORT_NAME.xml" ]]; then
  cp "$MT5_ROOT/reports/$REPORT_NAME.xml" "$REPORT_DIR/$REPORT_NAME.xml"
  REPORT_COPIED=1
  ARTIFACT_COPIED=1
  COPIED_REPORT="${COPIED_REPORT:-$REPORT_DIR/$REPORT_NAME.xml}"
fi

if [[ "$REPORT_COPIED" == "0" ]]; then
  echo "Warning: MT5 finished, but no HTML/XML report was exported for $REPORT_NAME." >&2
  echo "Expected: $MT5_ROOT/reports/$REPORT_NAME.htm or .xml" >&2
fi

LATEST_TRADES_CSV="$(
  find "$MT5_ROOT/Tester" "$MT5_ROOT/MQL5/Files" -path "*/$EXPERT_DIR/trades.csv" -type f -newer "$RUN_STAMP" -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | head -1 || true
)"

if [[ -n "$LATEST_TRADES_CSV" && -f "$LATEST_TRADES_CSV" ]]; then
  cp "$LATEST_TRADES_CSV" "$REPORT_DIR/$REPORT_NAME.trades.csv"
  echo "Copied journal: $REPORT_DIR/$REPORT_NAME.trades.csv"
  ARTIFACT_COPIED=1
fi

if [[ "$REPORT_COPIED" == "1" && "${MT5_FAIL_ON_MALFORMED_REPORT:-1}" == "1" ]]; then
  if ! python3 - "$COPIED_REPORT" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = path.read_bytes()
if data.startswith((b"\xff\xfe", b"\xfe\xff")) or data.count(b"\x00") > 100:
    text = data.decode("utf-16", errors="ignore")
else:
    text = data.decode("utf-8", errors="ignore")

compact = re.sub(r"\s+", " ", text)
malformed = (
    "1970.01.01" in compact
    or "Period: M0" in compact
    or ">M0<" in compact
    or "Initial Deposit: 0" in compact
)
if malformed:
    print(f"Malformed MT5 report exported: {path}", file=sys.stderr)
    print("Report has blank/default tester markers such as M0/1970/deposit 0.", file=sys.stderr)
    raise SystemExit(1)
PY
  then
    echo "MT5 exported a malformed report for $REPORT_NAME." >&2
    echo "Inspect terminal and tester logs under: $MT5_ROOT/logs and $MT5_ROOT/Tester/logs" >&2
    exit 1
  fi
fi

if [[ "$WINE_STATUS" != "0" && "$ARTIFACT_COPIED" == "0" ]]; then
  exit "$WINE_STATUS"
fi
