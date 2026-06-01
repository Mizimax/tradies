#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFIX="${MT5_PREFIX:-$HOME/Library/Application Support/net.metaquotes.wine.metatrader5}"
MT5_ROOT="$PREFIX/drive_c/Program Files/MetaTrader 5"

mkdir -p \
  "$MT5_ROOT/MQL5/Experts/GoldBot" \
  "$MT5_ROOT/MQL5/Include/GoldBot" \
  "$MT5_ROOT/MQL5/Profiles/Tester"

cp "$ROOT_DIR/mt5/Experts/GoldBot/GoldBot.mq5" "$MT5_ROOT/MQL5/Experts/GoldBot/GoldBot.mq5"
cp "$ROOT_DIR"/mt5/Include/GoldBot/*.mqh "$MT5_ROOT/MQL5/Include/GoldBot/"
cp "$ROOT_DIR/mt5/Presets/GoldBot.optimized.set" "$MT5_ROOT/MQL5/Profiles/Tester/GoldBot.optimized.set"

echo "Installed GoldBot source into $MT5_ROOT/MQL5"
