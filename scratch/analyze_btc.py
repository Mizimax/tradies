import csv
import re
from collections import defaultdict
from pathlib import Path

csv_path = Path("mt5/backtests/reports/BTCScalper-tuned-v3.trades.csv")

strategies = defaultdict(lambda: {"count": 0, "profit": 0.0, "gp": 0.0, "gl": 0.0})
open_positions = {}
deals_count = 0

with csv_path.open() as f:
    reader = csv.DictReader(f)
    for row in reader:
        event = row["event"]
        if event.startswith("Deal "):
            deals_count += 1
            deal_data = {}
            for match in re.finditer(r'([a-zA-Z0-9_]+)=([^ ]+)', event):
                deal_data[match.group(1)] = match.group(2)
            
            if "position" not in deal_data:
                continue
                
            pos_id = deal_data["position"]
            entry = deal_data.get("entry")
            
            if entry == "0": # Entry
                strat = deal_data.get("strategy", "unknown")
                open_positions[pos_id] = strat
                strategies[strat]["count"] += 1
            elif entry == "1": # Exit
                profit = float(deal_data.get("profit", 0.0))
                strategy = open_positions.get(pos_id, "unknown")
                strategies[strategy]["profit"] += profit
                if profit > 0:
                    strategies[strategy]["gp"] += profit
                else:
                    strategies[strategy]["gl"] += abs(profit)

print(f"Total deals processed: {deals_count}")
for s, data in strategies.items():
    pf = data["gp"] / data["gl"] if data["gl"] > 0 else float('inf')
    print(f"Strategy: {s:15} Trades: {data['count']:4} Profit: {data['profit']:.2f} PF: {pf:.2f} GP: {data['gp']:.2f} GL: {data['gl']:.2f}")
