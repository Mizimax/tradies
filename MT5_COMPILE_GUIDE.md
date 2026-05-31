# Compile GoldBot In MetaTrader 5

This repo is on macOS Apple Silicon. There is no local `MetaEditor` or Wine executable available here, so compilation must happen inside a MetaTrader 5 installation.

## Option A: Official MetaTrader 5 On macOS

MetaQuotes provides a macOS package for MetaTrader 5. Their macOS article says modern macOS versions and Apple processors are supported, and the official download page provides the desktop installer.

1. Install MetaTrader 5 from the official desktop download page or your broker's MT5 download page.
2. Open MT5.
3. In MT5, open `File -> Open Data Folder`.
4. Copy files from this repo:
   - `mt5/Experts/GoldBot/GoldBot.mq5` -> `MQL5/Experts/GoldBot/GoldBot.mq5`
   - `mt5/Include/GoldBot/*.mqh` -> `MQL5/Include/GoldBot/*.mqh`
   - `mt5/Presets/GoldBot.optimized.set` -> `MQL5/Presets/GoldBot.optimized.set`
5. Open MetaEditor from MT5: `Tools -> MetaQuotes Language Editor`.
6. In MetaEditor, open `MQL5/Experts/GoldBot/GoldBot.mq5`.
7. Click `Compile`.
8. Fix any compiler errors shown in the Toolbox panel.

## Option B: Package Zip For Manual Copy

Run:

```bash
bash scripts/package-mt5.sh
```

This creates:

```text
dist/GoldBot-MT5.zip
```

Unzip it and copy the contained `MQL5` folders into the MT5 data folder.

## Already Installed On This Mac

On this machine, MetaTrader 5 was installed at:

```text
/Users/tammanoonjomjaturong/Applications/MetaTrader 5.app
```

Rosetta 2 was also installed because the official macOS bundle runs an x86_64 Wine wrapper.

The EA files were copied into:

```text
/Users/tammanoonjomjaturong/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5/
```

To open MetaEditor directly on `GoldBot.mq5`, run:

```bash
bash scripts/open-metaeditor-goldbot.sh
```

Then click `Compile` inside MetaEditor.

## Option C: Windows VPS Or VM

This is often the cleanest path for MT5 automation:

1. Install broker-provided MT5 on Windows.
2. Copy the same files into the MT5 data folder.
3. Compile in MetaEditor.
4. Run Strategy Tester on XAUUSD M15.

## First Compile Settings

Use the preset:

```text
MQL5/Presets/GoldBot.optimized.set
```

Start with:

```text
InpDebugOnly=true
```

That lets the EA log signals without placing orders.

## After Compile

Run Strategy Tester:

- Expert: `GoldBot`
- Symbol: your broker's gold symbol, usually `XAUUSD` or `GOLD`
- Timeframe: `M15`
- Model: `Every tick based on real ticks` if available
- Preset: `GoldBot.optimized.set`

Check:

- No compile errors
- EA logs on closed M15 bars only
- Daily risk gate works
- Pending ladder appears only when `InpDebugOnly=false`
- Journal writes to `MQL5/Files/GoldBot/trades.csv`

## Sources

- Official MetaTrader 5 desktop download: <https://www.metatrader.com/en/download/desktop>
- MetaQuotes MT5 product page: <https://www.metaquotes.com/en/metatrader5>
- MetaQuotes macOS installation article: <https://www.mql5.com/en/articles/619>
