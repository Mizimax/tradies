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
  "$MT5_ROOT/MQL5/Experts/BTCScalper" \
  "$MT5_ROOT/MQL5/Include/BTCScalper" \
  "$MT5_ROOT/MQL5/Experts/CodexCGrid" \
  "$MT5_ROOT/MQL5/Experts/DZV_Style_ADR" \
  "$MT5_ROOT/MQL5/Indicators" \
  "$MT5_ROOT/MQL5/Scripts/DZVStyle" \
  "$MT5_ROOT/MQL5/Include/DZVStyle" \
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
for preset_file in "$ROOT_DIR"/mt5/Presets/GoldBot*.set; do
  cp "$preset_file" "$MT5_ROOT/MQL5/Profiles/Tester/$(basename "$preset_file")"
done

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

# BTCScalper
if [[ -f "$ROOT_DIR/mt5/Experts/BTCScalper/BTCScalper.mq5" ]]; then
  install_source "$ROOT_DIR/mt5/Experts/BTCScalper/BTCScalper.mq5" "$MT5_ROOT/MQL5/Experts/BTCScalper/BTCScalper.mq5"
  for source_file in "$ROOT_DIR"/mt5/Include/BTCScalper/*.mqh; do
    install_source "$source_file" "$MT5_ROOT/MQL5/Include/BTCScalper/$(basename "$source_file")"
  done
  if [[ -f "$ROOT_DIR/mt5/Presets/BTCScalper.optimized.set" ]]; then
    cp "$ROOT_DIR/mt5/Presets/BTCScalper.optimized.set" "$MT5_ROOT/MQL5/Profiles/Tester/BTCScalper.optimized.set"
  fi
  echo "Installed BTCScalper source into $MT5_ROOT/MQL5"
fi

# CodexCGrid
if [[ -f "$ROOT_DIR/mt5/Experts/CodexCGrid/CodexCGrid.mq5" ]]; then
  install_source "$ROOT_DIR/mt5/Experts/CodexCGrid/CodexCGrid.mq5" "$MT5_ROOT/MQL5/Experts/CodexCGrid/CodexCGrid.mq5"
  for preset_file in "$ROOT_DIR"/mt5/Presets/CodexCGrid*.set; do
    [[ -f "$preset_file" ]] || continue
    cp "$preset_file" "$MT5_ROOT/MQL5/Profiles/Tester/$(basename "$preset_file")"
  done
  echo "Installed CodexCGrid source into $MT5_ROOT/MQL5"
fi

# DZV_Style_ADR
if [[ -f "$ROOT_DIR/mt5/Experts/DZV_Style_ADR/DZV_Style_ADR_EA.mq5" ]]; then
  install_source "$ROOT_DIR/mt5/Experts/DZV_Style_ADR/DZV_Style_ADR_EA.mq5" "$MT5_ROOT/MQL5/Experts/DZV_Style_ADR/DZV_Style_ADR_EA.mq5"
  install_source "$ROOT_DIR/mt5/Indicators/DZV_Style_ADR_Indicator.mq5" "$MT5_ROOT/MQL5/Indicators/DZV_Style_ADR_Indicator.mq5"
  install_source "$ROOT_DIR/mt5/Scripts/DZVStyle/DZV_Style_ADR_SelfTest.mq5" "$MT5_ROOT/MQL5/Scripts/DZVStyle/DZV_Style_ADR_SelfTest.mq5"
  for source_file in "$ROOT_DIR"/mt5/Include/DZVStyle/*.mqh; do
    install_source "$source_file" "$MT5_ROOT/MQL5/Include/DZVStyle/$(basename "$source_file")"
  done
  if [[ -f "$ROOT_DIR/mt5/Presets/DZV_Style_ADR.signal.set" ]]; then
    cp "$ROOT_DIR/mt5/Presets/DZV_Style_ADR.signal.set" "$MT5_ROOT/MQL5/Profiles/Tester/DZV_Style_ADR.signal.set"
  fi
  echo "Installed DZV_Style_ADR source into $MT5_ROOT/MQL5"
fi

echo "Installed GoldBot source into $MT5_ROOT/MQL5"
