# ML/AI Models for Short-Term Trading — Deep Research Report (2026-07-06)

**Question:** Which ML/AI prediction model families demonstrably work for short-term trading (intraday–few days) with an edge that survives 6-12 months, deployable by a retail trader with a $1,000 aggressive MT5 account?

**Verification caveat:** The adversarial 3-vote verification layer failed twice on session limits, so every claim below is *as extracted (with quotes) from the primary source by a reader agent* but not independently cross-checked. Numbers are "as reported by the paper." Sources are predominantly peer-reviewed/primary (SSRN, arXiv, Springer, JFE).

---

## Headline conclusions

1. **Transaction cost is the single deciding variable, not model architecture.** Every study that looks intraday finds the gross edge is real but tiny per trade; whether it survives depends entirely on cost per trade vs edge per trade.
   - PPO deep-RL intraday futures model: walk-forward OOS Sharpe 2.759, 18.1% ann. (2013-2021) — but dies once round-trip cost exceeds **0.16 basis points**. Retail XAUUSD/BTCUSD spread is 1-3+ bps → **minute-frequency ML scalping does not transfer to retail** ([Springer](https://link.springer.com/article/10.1007/s12530-024-09593-6)).
   - Hourly BTC/USDT: XGBoost long-only 73.5% ann. gross → **-64% after 10 bps costs**; iTransformer 181.8% → -98.6% ([arXiv 2606.00060](https://arxiv.org/html/2606.00060)).
   - Same paper: a **cost-aware execution filter** (trade only when predicted return > λ=2.0 × round-trip cost) rescues XGBoost to **65.4% ann., Sharpe 1.09 net**, cutting trades 10,619 → 251. This is the highest-value single mechanism found.
   - Even then, the best cost-aware strategy did *not* statistically beat BTC buy-and-hold (56.3% ann., Sharpe 0.82) after multiple-testing correction.

2. **Model-family scorecard (evidence-weighted):**
   | Family | Verdict | Evidence |
   |---|---|---|
   | Gradient boosting (XGBoost/LightGBM/CatBoost) on engineered features | ✅ best all-rounder; needs trade filter (fee drag from overtrading is its failure mode) | beats TSFMs (CatBoost Sharpe 6.79 pre-cost long-short); LightGBM died to fees when unfiltered (136 trades → below B&H) |
   | LSTM direction classifier (daily bars) | ✅ repeatedly the cost-survivor | Only strategy beating BTC B&H after 0.1% fees (53.2% vs 42.3%, OOS Apr-Dec 2024, arXiv 2511.00665); best family net-of-cost in US anomaly study (1.42%/mo net, t=3.99, SSRN 4702406) |
   | Ensembles of simple models (linear/RF/SVM + agreement gate) | ✅ robustness mechanism | 5-model-agreement ensemble net-positive after 0.5% round-trip for ~11 months OOS incl. bear regime (ETH 9.6% ann. Sharpe 0.80); 5/18 individual models were below coin-flip OOS — ensembling rescued it |
   | Regularized linear + tree models on cross-sectional lagged returns | ✅ (institutional setting) | 5-min equity predictability, Sharpe 0.98 after costs; deep nets did NOT add value there |
   | Time-series foundation models (Chronos, TimesFM, Moirai, TimeGPT) zero-shot/fine-tuned | ❌ not alpha generators | negative OOS R², ~50-51% directional accuracy, lose to CatBoost; fine-tuning mostly makes it worse (arXiv 2511.18578, 2606.27100) |
   | Deep RL (PPO) | ❌ at retail costs | edge ceiling 0.16 bps round-trip |
   | Single unensembled models of any kind | ⚠️ high decay risk | frequent sub-50% OOS accuracy |

3. **Honest expectations:**
   - Published ML backtests overstate live-forward by **~1.5-3×** (realistic = ⅓–⅔ of backtest) — SSRN 4702406.
   - Directional accuracy of good models is **~51-55%**, not 60%+. Profit comes from risk management + cost control layered on a thin edge (Bank Nifty study: acc. 0.53, headline 10× growth came from the risk overlay, with 47-57% max drawdowns that would kill a $1k account).
   - Realistic net target at daily frequency on crypto: **Sharpe ~0.8-1.1, annualized net in the 10-60% range depending on aggression**, with the honest benchmark being buy-and-hold BTC.

4. **Market choice for a $1k account:** BTCUSD at daily/H4 frequency is the clearest fit — 24/7 data, free exchange data for training, volatility large enough that per-trade edge can exceed retail costs. Gold M1-M5 ML scalping is the worst fit (spread 1-3 bps vs per-trade edges measured in ~0.04 bps in the RL study). This matches the repo's own experience: BTCScalper M-timeframe scalping sits at PF ≈ 1.02.

## Recommended builds (1+1)

**Build A (primary): LightGBM/XGBoost direction classifier, BTCUSD H4/D1, cost-aware**
- Features: engineered (returns at multiple lags, ATR/vol regime, RSI/MACD-family, day-of-week/session, rolling skew) — this family beats fancy architectures at this data scale.
- **Execution filter: only trade when predicted move > 2× round-trip cost** (spread+commission+slippage measured at your broker).
- Walk-forward: retrain monthly on a rolling 2-3 y window; never touch test data.
- Ensemble gate: require agreement of ≥2 of {GBM, LSTM, logistic baseline} before entering.

**Build B (second vote / comparison): LSTM daily direction classifier on BTC** — the one family that repeatedly survives fees at daily frequency. Use as the second ensemble vote rather than a standalone.

**Deployment on Mac + MT5:** train/score in Python on macOS; the official `MetaTrader5` Python package is Windows-only, so bridge via file/socket into the EA (EA reads a signal file each bar), or precompute signal thresholds into EA inputs. (Sources include mql5 Python docs and an Apple-Silicon MT5 setup repo.)

## Edge-decay monitoring (kill-switch criteria)
- Rolling 60-90 day directional accuracy: alarm < 51%, kill < 50%.
- Rolling net PF < 1.0 over the same window, or expectancy per trade < measured round-trip cost.
- Compare live fills vs backtest assumptions (slippage drift is a silent killer).
- Expect to retrain monthly; expect the feature set to need revisiting within 6-12 months (post-publication/post-discovery decay is well documented).

## Sources (primary unless noted)
- SSRN 4702406 — Azevedo, Hoegner & Velikov, *Expected Returns on Machine-Learning Strategies* (net-of-cost survival, 1.5-3× backtest haircut)
- JFE — *Intraday market predictability: a machine learning approach* (5-min equity, Sharpe 0.98 net)
- Springer s12530-024-09593-6 — PPO intraday RL on futures (cost fragility 0.16 bps)
- arXiv 2511.00665 — LSTM vs LightGBM vs TA on daily BTC with fees
- Springer 978-981-96-6839-7_10 — crypto ensemble surviving 0.5% costs, ~11 mo OOS incl. bear regime
- arXiv 2511.18578 — *(Re)Visiting Time Series Foundation Models in Finance* (TSFM vs CatBoost)
- arXiv 2606.00060 — hourly BTC futures, cost-aware execution filter (λ×cost)
- arXiv 2606.27100 — TSFM benchmark vs random walk (2/10 tasks significant)
- ResearchGate 404737916 — LSTM/XGBoost Bank Nifty risk-framework study (acc. ~0.53, DD 47-57%)
- GARP — López de Prado, *10 Reasons Most ML Funds Fail*; Robot Wealth ML writeups (blog, practitioner)
