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
if [[ ! -x "$WINE" && -x "$APP/Contents/SharedSupport/wine/bin/wine64" ]]; then
  WINE="$APP/Contents/SharedSupport/wine/bin/wine64"
fi
METAEDITOR="$PREFIX/drive_c/Program Files/MetaTrader 5/metaeditor64.exe"
MT5_ROOT="$PREFIX/drive_c/Program Files/MetaTrader 5"
SOURCE="$MT5_ROOT/MQL5/Experts/CodexCGrid/CodexCGrid.mq5"
SOURCE_DIR="$MT5_ROOT/MQL5/Experts/CodexCGrid"
SOURCE_FILE="CodexCGrid.mq5"
EX5="$MT5_ROOT/MQL5/Experts/CodexCGrid/CodexCGrid.ex5"
LOG="$MT5_ROOT/MQL5/Experts/CodexCGrid/CodexCGrid.log"
TMP_LOG="/tmp/codexcgrid-metaeditor-compile.log"
STOP_RUNNING="${MT5_STOP_RUNNING:-1}"

require_executable() {
  local path="$1"
  local label="$2"
  if [[ ! -x "$path" ]]; then
    echo "$label not found or not executable: $path" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  local label="$2"
  if [[ ! -f "$path" ]]; then
    echo "$label not found: $path" >&2
    exit 1
  fi
}

print_text_file() {
  local path="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$path" <<'PY'
import pathlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
for encoding in ("utf-16", "utf-8"):
    try:
        print(data.decode(encoding, errors="ignore"), end="")
        break
    except Exception:
        continue
PY
  else
    LC_ALL=C tr -d '\000' < "$path"
  fi
}

print_compile_logs() {
  echo
  echo "MetaEditor stdout/stderr log: $TMP_LOG"
  if [[ -f "$TMP_LOG" ]]; then
    print_text_file "$TMP_LOG"
  else
    echo "  missing"
  fi

  echo
  echo "MetaEditor compile log: $LOG"
  if [[ -f "$LOG" ]]; then
    print_text_file "$LOG"
  else
    echo "  missing"
  fi
}

mt5_processes() {
  ps aux | grep -Ei 'terminal64\.exe|metatester64\.exe|metaeditor64\.exe' | grep -v grep || true
}

require_executable "$WINE" "Wine launcher"
require_executable "$WINEPATH" "winepath launcher"
require_file "$METAEDITOR" "MetaEditor"

if [[ "$STOP_RUNNING" == "1" || "$STOP_RUNNING" == "true" || "$STOP_RUNNING" == "TRUE" ]]; then
  pkill -f "C:\\\\Program Files\\\\MetaTrader 5\\\\terminal64.exe" 2>/dev/null || true
  pkill -f "C:\\\\Program Files\\\\MetaTrader 5\\\\metatester64.exe" 2>/dev/null || true
  pkill -f "terminal64.exe" 2>/dev/null || true
  pkill -f "metatester64.exe" 2>/dev/null || true
  sleep 2
fi

"$ROOT_DIR/scripts/install-mt5-source.sh" >/dev/null
require_file "$SOURCE" "CodexCGrid source"

rm -f "$LOG" "$TMP_LOG"
before="$(stat -f '%m' "$EX5" 2>/dev/null || echo 0)"

# install-mt5-source.sh preserves repo mtimes; force MetaEditor to rebuild.
touch "$SOURCE"

(
  cd "$SOURCE_DIR"
  WINEPREFIX="$PREFIX" "$WINE" "$METAEDITOR" "/compile:$SOURCE_FILE" /log
) >"$TMP_LOG" 2>&1 &
metaeditor_pid=$!

echo "Compiling CodexCGrid..."
for _ in $(seq 1 60); do
  sleep 1
  after="$(stat -f '%m' "$EX5" 2>/dev/null || echo 0)"
  if [[ "$after" != "0" && "$after" != "$before" && -f "$EX5" ]]; then
    echo "CodexCGrid compiled: $EX5"
    if [[ -f "$LOG" ]]; then print_text_file "$LOG"; fi
    exit 0
  fi
  if ! kill -0 "$metaeditor_pid" 2>/dev/null; then
    echo "MetaEditor exited without updating CodexCGrid.ex5." >&2
    echo "Source:   $SOURCE" >&2
    echo "Compiled: $EX5" >&2
    running_mt5="$(mt5_processes)"
    if [[ -n "$running_mt5" ]]; then
      echo >&2
      echo "Running MT5 processes detected; close them before command-line compile:" >&2
      echo "$running_mt5" >&2
    fi
    print_compile_logs >&2
    exit 1
  fi
done

echo "MetaEditor command-line compile did not update CodexCGrid.ex5." >&2
echo "Source:   $SOURCE" >&2
echo "Compiled: $EX5" >&2
running_mt5="$(mt5_processes)"
if [[ -n "$running_mt5" ]]; then
  echo >&2
  echo "Running MT5 processes detected; close them before command-line compile:" >&2
  echo "$running_mt5" >&2
fi
print_compile_logs >&2
exit 1
