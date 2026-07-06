# C+ Behavior Profile: cplus-classic-screenshot-mapped-XAUUSDs-M1-2026.06.20-2026.06.23-login703101-dep1000-20to23.htm

## Extracted Evidence
- orders: 82
- trade deals: 82
- entry deals: 41
- exit deals: 41
- exit pnl from deal table: 81.79
- exit wins/losses: 33/8
- average win/loss: 5.36/-11.88
- average minutes between entries: 33.9

## Entry Shape
- direction mix: {'sell': 21, 'buy': 20}
- lots used: {'0.01': 34, '0.02': 6, '0.03': 1}
- busiest entry hours: {3: 5, 17: 5, 2: 4, 5: 3, 16: 3, 1: 2, 4: 2, 9: 2}

## Comments
- top comments: {'Libra C+': 34, '0.0': 7, '': 5, 'sl 4189.61': 3, 'sl 4150.14': 2, 'sl 4201.69': 2, 'end of test': 2, 'sl 4151.82': 1, 'sl 4150.23': 1, 'sl 4158.16': 1}

## Basket/Cluster Clues
- timestamps with >=3 trade deals: 2
- 2026.06.22 04:49:29: 5 trade deals
- 2026.06.22 16:26:04: 3 trade deals

## Inferred Clone Targets
- entry signal must allow both buy and sell on the same day, often alternating quickly
- base lot is 0.01 and ladder expansion reaches 0.02 in these samples
- many exits are broker-side/EA-modified stop comments, but profitable closes imply trailing or synthetic basket exit behavior
- simultaneous multi-deal timestamps are important; our clone needs basket close and immediate re-entry handling
