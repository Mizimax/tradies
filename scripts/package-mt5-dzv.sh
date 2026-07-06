#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
PACKAGE_DIR="$DIST_DIR/DZV_Style_ADR-MT5"
ZIP_FILE="$DIST_DIR/DZV_Style_ADR-MT5.zip"

rm -rf "$PACKAGE_DIR" "$ZIP_FILE"
mkdir -p "$PACKAGE_DIR/MQL5/Experts/DZV_Style_ADR"
mkdir -p "$PACKAGE_DIR/MQL5/Indicators"
mkdir -p "$PACKAGE_DIR/MQL5/Scripts/DZVStyle"
mkdir -p "$PACKAGE_DIR/MQL5/Include/DZVStyle"
mkdir -p "$PACKAGE_DIR/MQL5/Profiles/Tester"

cp "$ROOT_DIR/mt5/Experts/DZV_Style_ADR/DZV_Style_ADR_EA.mq5" "$PACKAGE_DIR/MQL5/Experts/DZV_Style_ADR/"
cp "$ROOT_DIR/mt5/Indicators/DZV_Style_ADR_Indicator.mq5" "$PACKAGE_DIR/MQL5/Indicators/"
cp "$ROOT_DIR/mt5/Scripts/DZVStyle/DZV_Style_ADR_SelfTest.mq5" "$PACKAGE_DIR/MQL5/Scripts/DZVStyle/"
cp "$ROOT_DIR"/mt5/Include/DZVStyle/*.mqh "$PACKAGE_DIR/MQL5/Include/DZVStyle/"
cp "$ROOT_DIR/mt5/Presets/DZV_Style_ADR.signal.set" "$PACKAGE_DIR/MQL5/Profiles/Tester/"
cp "$ROOT_DIR/docs/DZV_Style_ADR_System.md" "$PACKAGE_DIR/README.md"

(
  cd "$DIST_DIR"
  zip -qr "DZV_Style_ADR-MT5.zip" "DZV_Style_ADR-MT5"
)

echo "Created $ZIP_FILE"
