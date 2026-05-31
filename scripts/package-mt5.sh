#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$DIST_DIR/GoldBot-MT5"
ZIP_FILE="$DIST_DIR/GoldBot-MT5.zip"

rm -rf "$PACKAGE_DIR" "$ZIP_FILE"
mkdir -p "$PACKAGE_DIR/MQL5/Experts/GoldBot"
mkdir -p "$PACKAGE_DIR/MQL5/Include/GoldBot"
mkdir -p "$PACKAGE_DIR/MQL5/Presets"

cp "$ROOT_DIR/mt5/Experts/GoldBot/GoldBot.mq5" "$PACKAGE_DIR/MQL5/Experts/GoldBot/GoldBot.mq5"
cp "$ROOT_DIR/mt5/Include/GoldBot/"*.mqh "$PACKAGE_DIR/MQL5/Include/GoldBot/"
cp "$ROOT_DIR/mt5/Presets/GoldBot.optimized.set" "$PACKAGE_DIR/MQL5/Presets/GoldBot.optimized.set"
cp "$ROOT_DIR/mt5/backtests/README.md" "$PACKAGE_DIR/STRATEGY_TESTER_README.md"

(
  cd "$DIST_DIR"
  zip -qr "GoldBot-MT5.zip" "GoldBot-MT5"
)

echo "Created $ZIP_FILE"
echo "Copy the MQL5 folder contents into your MetaTrader 5 data folder, then compile GoldBot.mq5 in MetaEditor."
