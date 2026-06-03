#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${MT5_PREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
MT5_ROOT="$PREFIX/drive_c/Program Files/MetaTrader 5"

mkdir -p \
  "$MT5_ROOT/MQL5/Experts/GoldBot" \
  "$MT5_ROOT/MQL5/Include/GoldBot" \
  "$MT5_ROOT/MQL5/Experts/GoldScalper" \
  "$MT5_ROOT/MQL5/Include/GoldScalper" \
  "$MT5_ROOT/MQL5/Profiles/Tester"

install_source() {
  local src="$1"
  local dst="$2"

  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    touch -r "$src" "$dst"
    return
  fi

  cp -p "$src" "$dst"
}

# GoldBot
install_source "$ROOT_DIR/mt5/Experts/GoldBot/GoldBot.mq5" "$MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.mq5"
for source_file in "$ROOT_DIR"/mt5/Include/GoldBot/*.mqh; do
  install_source "$source_file" "$MT5_ROOT/MQL5/Include/GoldBot/$(basename "$source_file")"
done
cp "$ROOT_DIR/mt5/Presets/GoldBot.optimized.set" "$MT5_ROOT/MQL5/Profiles/Tester/GoldBot.optimized.set"

# GoldScalper
if [[ -f "$ROOT_DIR/mt5/Experts/GoldScalper/GoldScalper.mq5" ]]; then
  install_source "$ROOT_DIR/mt5/Experts/GoldScalper/GoldScalper.mq5" "$MT5_ROOT/MQL5/Experts/GoldScalper/GoldScalper.mq5"
  for source_file in "$ROOT_DIR"/mt5/Include/GoldScalper/*.mqh; do
    install_source "$source_file" "$MT5_ROOT/MQL5/Include/GoldScalper/$(basename "$source_file")"
  done
  if [[ -f "$ROOT_DIR/mt5/Presets/GoldScalper.optimized.set" ]]; then
    cp "$ROOT_DIR/mt5/Presets/GoldScalper.optimized.set" "$MT5_ROOT/MQL5/Profiles/Tester/GoldScalper.optimized.set"
  fi
  echo "Installed GoldScalper source into $MT5_ROOT/MQL5"
fi

echo "Installed GoldBot source into $MT5_ROOT/MQL5"
