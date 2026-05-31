from __future__ import annotations

import argparse
import csv
import json
import os
import urllib.request
from pathlib import Path


def fetch_oanda(instrument: str, granularity: str, count: int, output: Path) -> None:
    token = os.environ.get("OANDA_API_KEY")
    base_url = os.environ.get("OANDA_BASE_URL", "https://api-fxpractice.oanda.com")
    if not token:
        raise SystemExit("Set OANDA_API_KEY before fetching data")
    url = f"{base_url}/v3/instruments/{instrument}/candles?price=M&granularity={granularity}&count={count}"
    request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(request) as response:
        payload = json.loads(response.read().decode("utf-8"))
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["time", "open", "high", "low", "close", "volume"])
        writer.writeheader()
        for candle in payload["candles"]:
            mid = candle["mid"]
            writer.writerow({"time": candle["time"], "open": mid["o"], "high": mid["h"], "low": mid["l"], "close": mid["c"], "volume": candle["volume"]})


def fetch_huggingface(output: Path, max_rows: int | None = None) -> None:
    url = "https://huggingface.co/datasets/ZombitX64/xauusd-gold-price-historical-data-2004-2025/resolve/main/XAU_15m_data.jsonl?download=true"
    request = urllib.request.Request(url, headers={"User-Agent": "gold-trading-bot-backtester/0.1"})
    output.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict] = []
    with urllib.request.urlopen(request, timeout=120) as response:
        for raw in response:
            item = json.loads(raw.decode("utf-8"))
            rows.append(
                {
                    "time": item["Date"].replace(".", "-", 2).replace(" ", "T") + ":00Z",
                    "open": item["Open"],
                    "high": item["High"],
                    "low": item["Low"],
                    "close": item["Close"],
                    "volume": item.get("Volume", 1),
                }
            )
            if max_rows and len(rows) >= max_rows:
                break
    with output.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["time", "open", "high", "low", "close", "volume"])
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", choices=["auto", "oanda", "hf"], default="auto")
    parser.add_argument("--instrument", default="XAU_USD")
    parser.add_argument("--granularity", default="M15")
    parser.add_argument("--count", type=int, default=5000)
    parser.add_argument("--output", default="backtesting/results/xauusd_m15.csv")
    parser.add_argument("--max-rows", type=int)
    args = parser.parse_args()
    source = "oanda" if args.source == "auto" and os.environ.get("OANDA_API_KEY") else "hf" if args.source == "auto" else args.source
    if source == "oanda":
        fetch_oanda(args.instrument, args.granularity, args.count, Path(args.output))
    else:
        fetch_huggingface(Path(args.output), args.max_rows)
