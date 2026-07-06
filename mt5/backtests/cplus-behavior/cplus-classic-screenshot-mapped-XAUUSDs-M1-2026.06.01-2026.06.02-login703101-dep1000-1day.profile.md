# C+ Behavior Profile: cplus-classic-screenshot-mapped-XAUUSDs-M1-2026.06.01-2026.06.02-login703101-dep1000-1day.htm

## Extracted Evidence
- orders: 80
- trade deals: 80
- entry deals: 40
- exit deals: 40
- exit pnl from deal table: 138.85
- exit wins/losses: 30/10
- average win/loss: 6.55/-5.77
- average minutes between entries: 33.5

## Entry Shape
- direction mix: {'buy': 16, 'sell': 24}
- lots used: {'0.01': 32, '0.02': 8}
- busiest entry hours: {13: 4, 3: 3, 5: 3, 7: 3, 15: 3, 17: 3, 1: 2, 4: 2}

## Comments
- top comments: {'Libra C+': 32, '0.0': 8, '': 4, 'sl 4524.37': 3, 'sl 4535.71': 2, 'sl 4463.64': 2, 'sl 4464.15': 2, 'sl 4481.27': 2, 'end of test': 2, 'sl 4539.39': 1}

## Basket/Cluster Clues
- timestamps with >=3 trade deals: 3
- 2026.06.01 04:22:18: 3 trade deals
- 2026.06.01 08:49:59: 3 trade deals
- 2026.06.01 13:48:00: 5 trade deals

## Inferred Clone Targets
- entry signal must allow both buy and sell on the same day, often alternating quickly
- base lot is 0.01 and ladder expansion reaches 0.02 in these samples
- many exits are broker-side/EA-modified stop comments, but profitable closes imply trailing or synthetic basket exit behavior
- simultaneous multi-deal timestamps are important; our clone needs basket close and immediate re-entry handling
