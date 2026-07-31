#property strict
#property version   "1.00"
#property description "BTCScalper — Aggressive Intraday EA for BTCUSD"

#include <Trade/Trade.mqh>
#include <BTCScalper/SessionTime.mqh>
#include <BTCScalper/RiskManager.mqh>
#include <BTCScalper/Indicators.mqh>
#include <BTCScalper/MeanReversion.mqh>
#include <BTCScalper/VwapReversion.mqh>
#include <BTCScalper/MomentumBreakout.mqh>
#include <BTCScalper/Allocator.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+

//--- Core
input string   InpSymbol              = "BTC";
input long     InpMagicNumber         = 26062201;    // unique magic
input double   InpRiskPerTradePct     = 2.0;         // aggressive: 2% per trade
input double   InpMinLot              = 0.01;
input double   InpMaxLot              = 10.0;
input double   InpMaxDailyLossPct     = 5.0;         // daily loss kill switch
input int      InpMaxDailyTrades      = 8;           // max filled trades/day
input int      InpMaxOpenTrades       = 3;           // max concurrent positions

//--- Session Times (UTC hours, crypto 24/7 but filtered)
input int      InpTradingStartHour    = 7;           // start scanning
input int      InpTradingEndHour      = 21;          // stop new entries
input int      InpBestSessionStart    = 7;           // MR session start (widened from 8 so MR actually fires)
input int      InpBestSessionEnd      = 21;          // MR session end (widened from 18 to match trading window)

//--- Strategy 1: Mean Reversion (BB + RSI on M15)
input bool     InpEnableMeanReversion = true;
input int      InpMrBbPeriod          = 20;
input double   InpMrBbDeviation       = 2.0;
input int      InpMrRsiPeriod         = 14;
input int      InpMrRsiOverbought     = 65;          // loosened from 70 so MR reaches allocator min-sample
input int      InpMrRsiOversold       = 35;          // loosened from 30 so MR reaches allocator min-sample
input double   InpMrSlAtrMult         = 1.5;         // SL = 1.5× ATR(14)
input int      InpMrMaxTrades         = 4;           // max MR trades/day
input bool     InpMrTrailBE           = true;        // move SL to BE at 1× ATR profit
input double   InpMrTrailBETrigger    = 1.0;

//--- Strategy 2: VWAP Reversion (M5)
input bool     InpEnableVwapReversion = true;
input int      InpVwapPeriod          = 0;           // 0 = auto session VWAP
input double   InpVwapZscoreEntry     = 2.0;         // enter when Z > ±2.0
input double   InpVwapSlAtrMult       = 1.5;
input int      InpVwapMaxTrades       = 4;
input int      InpVwapMaxHoldBars     = 12;          // exit VWAP trades after 12 bars (60m)
//--- VWAP execution improvements (all default to current behavior; ablation-tested)
input double   InpVwapTpOvershootAtr  = 0.0;         // extend TP past VWAP by N*ATR(M5) (0 = TP at VWAP)
input bool     InpVwapHoldAtrScale    = false;       // scale max-hold by ATR regime (fast=shorter, calm=longer)
input bool     InpVwapVolConfirm      = false;       // require signal-bar tick volume > avg*mult
input double   InpVwapVolMult         = 1.3;         // volume confirmation multiple
input int      InpVwapAvoidEdgeHours  = 0;           // skip entries in first/last N UTC hours (0 = off)

//--- Cost / Edge Gate (default-off; diagnostic)
input bool     InpCostGateEnabled     = false;       // require expected move to clear spread/edge floor
input double   InpCostGateK           = 2.0;         // cost multiple
input double   InpCostGateCommPerLot  = 0.0;         // tester commission model is normally zero
input double   InpCostGateMinAtrMult  = 0.0;         // optional ATR edge floor

//--- H1 Regime Gate (default-off; diagnostic)
input bool     InpRegimeGateEnabled    = false;       // require H1 ATR ratio within volatility band
input ENUM_TIMEFRAMES InpRegimeTf      = PERIOD_H1;   // ATR timeframe for regime-ratio gate
input double   InpRegimeMinH1AtrRatio  = 0.70;        // block if current/avg H1 ATR ratio below this (0 = no floor)
input double   InpRegimeMaxH1AtrRatio  = 0.0;         // block if ratio above this (0 = no cap)
input int      InpRegimeAtrAvgPeriod   = 100;         // H1 bars averaged for the ATR reference

//--- Strategy 3: Momentum Breakout (EMA crossover on M15)
input bool     InpEnableMomentum      = true;
input ENUM_TIMEFRAMES InpMomTf        = PERIOD_M15;   // momentum signal timeframe
input bool     InpUseGatekeeperRouting = true;        // route momentum through M15 ADX trend gate
input int      InpMomSignalMode       = 0;            // 0=EMA cross, 1=Donchian breakout
input int      InpMomEmaFast          = 9;
input int      InpMomEmaSlow          = 21;
input int      InpMomRsiPeriod        = 14;
input int      InpMomRsiLow           = 40;          // only enter when RSI 40-60
input int      InpMomRsiHigh          = 60;
input int      InpMomBreakoutLookback = 20;
input double   InpMomBreakoutBufferAtr = 0.10;
input bool     InpMomUseSessionVwapFilter = true;
input bool     InpMomUseHtfTrendFilter = true;
input ENUM_TIMEFRAMES InpMomHtfTf     = PERIOD_H1;
input int      InpMomHtfEmaPeriod     = 50;
input bool     InpMomUseAdxFilter     = false;
input double   InpMomAdxMin           = 20.0;
input int      InpMomDirectionMode    = 0;           // 0=both, 1=long-only, 2=short-only
input string   InpMomAllowedEntryHours = "";         // optional pipe/comma list, e.g. 04|12|16
input double   InpMomRR               = 2.0;         // R:R for momentum trades
input double   InpMomSlAtrMult        = 2.0;         // SL ATR multiplier for Momentum
input int      InpMomSlMode           = 0;           // 0=legacy tight swing/ATR, 1=ATR/swing bounded
input int      InpMomSwingLookback    = 5;
input double   InpMomSlMinAtrMult     = 1.5;
input double   InpMomSlMaxAtrMult     = 2.0;
input double   InpMomBETriggerR       = 1.0;
input double   InpMomTrailStartR      = 1.0;
input double   InpMomTrailAtrMult     = 1.5;
input int      InpMomMaxHoldBars      = 0;
input double   InpMomTimeStopMinR     = 0.0;
input int      InpMomMaxTrades        = 2;

//--- Regime Gatekeeper
input int      InpGatekeeperAdxPeriod = 14;
input double   InpGatekeeperAdxLevel  = 25.0;        // ADX threshold

//--- Risk Management
input bool     InpEnableDdScaling     = true;
input double   InpDdScaleHalfAtPct    = 12.0;        // halve risk at 12% DD
input double   InpDdScaleQuarterAtPct = 18.0;        // quarter risk at 18% DD
input double   InpDdStopAtPct         = 25.0;        // stop trading at 25% DD
input int      InpMaxConsecLoss       = 3;           // cooldown after 3 consecutive losses

//--- Performance-Feedback Allocation
input bool     InpEnablePerfAllocation = false;      // master switch; false = exact current baseline
input int      InpPerfWindowN          = 30;         // rolling window of last-N closed trades / strategy
input int      InpPerfMinSample        = 8;          // warmup: behave like baseline until N trades seen
input double   InpPerfPfFloor          = 0.85;       // PF below this -> probation
input double   InpPerfProbationMult    = 0.0;        // risk multiplier on probation (0 = disable)
input double   InpPerfPfBoost          = 1.50;       // PF at/above this -> boost tier
input double   InpPerfBoostMult        = 1.0;        // boost multiplier (1.0 = off / de-risk only)
input bool     InpPerfParoleEnabled    = true;       // allow 1 reduced trade/day for probation strategies
input double   InpPerfParoleMult       = 0.10;       // risk multiplier for the daily parole trade
input bool     InpPerfPersistLive      = false;      // mirror rings to GlobalVariables (live only; tester stub)

//--- Debug
input bool     InpDebugOnly           = false;
input bool     InpResetJournalOnInit  = true;

//--- Global Variables
CTrade trade;
static datetime g_btcLastMomBar = 0;

//--- Forward Declarations
string BTCScalperSymbol();

//--- Effective Risk Calculation
double BTCScalperEffectiveRisk()
{
   return InpEnableDdScaling
      ? BTCScalperDrawdownScaledRisk(InpRiskPerTradePct, InpDdScaleHalfAtPct, InpDdScaleQuarterAtPct, InpDdStopAtPct)
      : InpRiskPerTradePct;
}

//--- Per-strategy performance-feedback risk multiplier
//    Returns 1.0 (baseline) when allocation is off or during warmup.
//    Consumes one daily parole credit when granting a probation strategy a trade.
double BTCScalperStrategyRiskMult(const BTCStrategyId sid)
{
   if(!InpEnablePerfAllocation)
      return 1.0;

   double m = BTCScalperAllocMultiplier(sid, InpPerfMinSample, InpPerfPfFloor,
                                        InpPerfPfBoost, InpPerfProbationMult, InpPerfBoostMult);

   // Parole: keep a probation strategy's window alive with one reduced trade/day.
   if(m <= 0.0 && InpPerfParoleEnabled && BTCScalperPerfParoleAvailable(sid))
   {
      BTCScalperPerfParoleConsume(sid);
      m = InpPerfParoleMult;
   }
   return m;
}

//--- Final per-strategy risk. The ceiling is the configured base risk scaled by the
//    boost multiplier, so a strategy promoted to the boost tier may exceed base risk
//    (concentration) up to base*InpPerfBoostMult. With InpPerfBoostMult=1.0 (default)
//    this is identical to the old hard base-risk cap (strictly de-risking).
double BTCScalperStrategyRisk(const BTCStrategyId sid, const double baseEffectiveRisk)
{
   double r = baseEffectiveRisk * BTCScalperStrategyRiskMult(sid);
   double ceiling = InpRiskPerTradePct * MathMax(1.0, InpPerfBoostMult);
   return MathMin(r, ceiling);
}

bool BTCScalperMomHourAllowed()
{
   if(StringLen(InpMomAllowedEntryHours) == 0)
      return true;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   string allowed = InpMomAllowedEntryHours;
   StringReplace(allowed, ",", "|");
   StringReplace(allowed, ";", "|");
   StringReplace(allowed, " ", "");

   string haystack = "|" + allowed + "|";
   string padded = StringFormat("|%02d|", now.hour);
   string plain = StringFormat("|%d|", now.hour);
   return StringFind(haystack, padded) >= 0 || StringFind(haystack, plain) >= 0;
}

//--- Momentum signal, filters, allocation, and execution
void BTCScalperTryMomentumEntry(const string symbol, const double baseEffectiveRisk, const string regimeLabel)
{
   if(!BTCScalperMomHourAllowed())
      return;

   int momSig = BTCScalperMomSignal(symbol, InpMomRsiLow, InpMomRsiHigh, InpTradingEndHour,
                                    InpMomTf, InpMomSignalMode, InpMomBreakoutLookback,
                                    InpMomBreakoutBufferAtr, InpMomUseSessionVwapFilter,
                                    InpMomUseHtfTrendFilter, InpMomHtfTf, InpMomUseAdxFilter,
                                    InpMomAdxMin, InpMomDirectionMode);
   if(momSig != 0)
   {
      if(InpCostGateEnabled)
      {
         double atrRef = BTCScalperGetBufferValue(g_btcMomAtrHandle, 0, 1);
         double expectedMove = (atrRef == EMPTY_VALUE) ? 0.0 : atrRef * InpMomSlAtrMult * InpMomRR;
         if(atrRef == EMPTY_VALUE ||
            !BTCScalperCostGatePass(symbol, expectedMove, atrRef, InpCostGateK, InpCostGateCommPerLot, InpCostGateMinAtrMult))
            momSig = 0;
      }
   }
   if(momSig != 0 && InpRegimeGateEnabled)
   {
      if(!BTCScalperRegimeGatePass(g_btcRegimeAtrHandle, InpRegimeAtrAvgPeriod, InpRegimeMinH1AtrRatio, InpRegimeMaxH1AtrRatio))
         momSig = 0;
   }
   if(momSig != 0)
   {
      double momRisk = BTCScalperStrategyRisk(BTC_STRAT_MOM, baseEffectiveRisk);
      if(momRisk > 0.0)
      {
         if(InpEnablePerfAllocation)
            BTCScalperJournal(StringFormat("AllocDecision strategy=momentum regime=%s mult=%.3f risk=%.4f",
               regimeLabel, momRisk / MathMax(baseEffectiveRisk, 1e-9), momRisk));
         BTCScalperMomEntry(symbol, InpMagicNumber, trade, momSig, InpMomSlAtrMult, InpMomRR,
                            momRisk, InpMinLot, InpMaxLot, InpMomMaxTrades, InpMomTf,
                            InpMomSlMode, InpMomSwingLookback, InpMomSlMinAtrMult, InpMomSlMaxAtrMult);
      }
   }
}

//--- Global Risk Gate
bool BTCScalperEntryRiskAllowed(
   const string symbol,
   const long magic,
   const double maxDailyLossPct,
   const int maxDailyTrades,
   const int maxOpenTrades,
   const int tradingEndHour,
   const double effectiveRiskPct,
   string &reason,
   bool &cancelPending
)
{
   reason = "";
   cancelPending = false;

   if(effectiveRiskPct <= 0.0)
   {
      reason = "drawdown_stop";
      cancelPending = true;
      return false;
   }

   if(!BTCScalperDailyLossAllowed(maxDailyLossPct))
   {
      reason = "daily_loss";
      cancelPending = true;
      return false;
   }

   if(!BTCScalperDailyTradeAllowed(maxDailyTrades))
   {
      reason = "daily_trade_limit";
      cancelPending = true;
      return false;
   }

   if(!BTCScalperMaxOpenAllowed(symbol, magic, maxOpenTrades))
   {
      reason = "max_open_trades";
      return false;
   }

   if(!BTCScalperIsTradingHours(tradingEndHour))
   {
      reason = "trading_end";
      return false;
   }

   return true;
}

//--- Cancel Pending Orders
void BTCScalperCancelPendingOrders(const string symbol, const long magic)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      trade.OrderDelete(ticket);
   }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   string symbol = BTCScalperSymbol();
   if(!SymbolSelect(symbol, true))
   {
      Print("BTCScalper: Unable to select symbol ", symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);

   if(InpResetJournalOnInit)
      BTCScalperResetJournal();

   BTCScalperResetTesterRiskState();
   BTCScalperVwapReset();
   BTCScalperPerfReset();

   // Initialize indicators
   if(!BTCScalperIndicatorsInit(symbol, InpMrBbPeriod, InpMrBbDeviation, 
                                InpMrRsiPeriod, 14, InpGatekeeperAdxPeriod, 
                                InpMomEmaFast, InpMomEmaSlow, InpMomTf,
                                InpMomHtfTf, InpMomHtfEmaPeriod, InpRegimeTf))
   {
      return INIT_FAILED;
   }

   Print("BTCScalper initialized successfully for ", symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   BTCScalperIndicatorsDeinit();
   Print("BTCScalper deinitialized. Reason=", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   string symbol = BTCScalperSymbol();

   // 1. Manage active positions on every tick
   if(InpEnableMeanReversion)
      BTCScalperMRManage(symbol, InpMagicNumber, trade, InpMrTrailBE, InpMrTrailBETrigger);
   if(InpEnableVwapReversion)
      BTCScalperVwapManage(symbol, InpMagicNumber, trade, InpVwapMaxHoldBars, InpVwapTpOvershootAtr, InpVwapHoldAtrScale);
   if(InpEnableMomentum)
      BTCScalperMomManage(symbol, InpMagicNumber, trade, InpMomTf, InpMomBETriggerR,
                          InpMomTrailStartR, InpMomTrailAtrMult, InpMomMaxHoldBars,
                          InpMomTimeStopMinR);

   // 2. Live VWAP update
   BTCScalperVwapUpdate(symbol);

   // 3. New M15 Bar signals
   if(BTCScalperIsNewM15Bar(symbol))
   {
      double risk = BTCScalperEffectiveRisk();
      string reason = "";
      bool cancelPending = false;
      bool allowed = BTCScalperEntryRiskAllowed(symbol, InpMagicNumber, InpMaxDailyLossPct, 
                                               InpMaxDailyTrades, InpMaxOpenTrades, 
                                               InpTradingEndHour, risk, reason, cancelPending);

      if(!allowed)
      {
         if(cancelPending)
            BTCScalperCancelPendingOrders(symbol, InpMagicNumber);
      }
      else if(!InpDebugOnly && BTCScalperCooldownAllowed(InpMaxConsecLoss))
      {
         double adxVal = BTCScalperGetBufferValue(g_btcAdxHandle, 0, 1);
         if(adxVal != EMPTY_VALUE)
         {
            bool isTrending = (adxVal >= InpGatekeeperAdxLevel);

            if(InpEnableMeanReversion && !isTrending)
            {
               int mrSig = BTCScalperMRSignal(symbol, InpMrRsiOverbought, InpMrRsiOversold, InpBestSessionStart, InpBestSessionEnd);
               if(mrSig != 0)
               {
                  if(InpCostGateEnabled)
                  {
                     double bbMiddle = BTCScalperGetBufferValue(g_btcBbHandle, 0, 1);
                     double atrRef = BTCScalperGetBufferValue(g_btcAtrHandle, 0, 1);
                     double expectedMove = MathAbs(SymbolInfoDouble(symbol, SYMBOL_ASK) - bbMiddle);
                     if(bbMiddle == EMPTY_VALUE || atrRef == EMPTY_VALUE ||
                        !BTCScalperCostGatePass(symbol, expectedMove, atrRef, InpCostGateK, InpCostGateCommPerLot, InpCostGateMinAtrMult))
                        mrSig = 0;
                  }
               }
               if(mrSig != 0 && InpRegimeGateEnabled)
               {
                  if(!BTCScalperRegimeGatePass(g_btcRegimeAtrHandle, InpRegimeAtrAvgPeriod, InpRegimeMinH1AtrRatio, InpRegimeMaxH1AtrRatio))
                     mrSig = 0;
               }
               if(mrSig != 0)
               {
                  double mrRisk = BTCScalperStrategyRisk(BTC_STRAT_MR, risk);
                  if(mrRisk > 0.0)
                  {
                     if(InpEnablePerfAllocation)
                        BTCScalperJournal(StringFormat("AllocDecision strategy=mean_reversion regime=range mult=%.3f risk=%.4f",
                           mrRisk / MathMax(risk, 1e-9), mrRisk));
                     BTCScalperMREntry(symbol, InpMagicNumber, trade, mrSig, InpMrSlAtrMult, mrRisk, InpMinLot, InpMaxLot, InpMrMaxTrades);
                  }
               }
            }

            if(InpEnableMomentum && InpMomTf == PERIOD_M15 && (!InpUseGatekeeperRouting || isTrending))
               BTCScalperTryMomentumEntry(symbol, risk, isTrending ? "trend" : "ungated");
         }
      }
   }

   // 4. New M5 Bar signals
   if(BTCScalperIsNewM5Bar(symbol))
   {
      double risk = BTCScalperEffectiveRisk();
      string reason = "";
      bool cancelPending = false;
      bool allowed = BTCScalperEntryRiskAllowed(symbol, InpMagicNumber, InpMaxDailyLossPct, 
                                               InpMaxDailyTrades, InpMaxOpenTrades, 
                                               InpTradingEndHour, risk, reason, cancelPending);

      if(!allowed)
      {
         if(cancelPending)
            BTCScalperCancelPendingOrders(symbol, InpMagicNumber);
      }
      else if(!InpDebugOnly && BTCScalperCooldownAllowed(InpMaxConsecLoss))
      {
         double adxVal = BTCScalperGetBufferValue(g_btcAdxHandle, 0, 1);
         if(adxVal != EMPTY_VALUE)
         {
            bool isTrending = (adxVal >= InpGatekeeperAdxLevel);

            if(InpEnableVwapReversion && !isTrending)
            {
               int vwapSig = BTCScalperVwapSignal(symbol, InpVwapZscoreEntry, InpTradingEndHour, InpVwapVolConfirm, InpVwapVolMult, InpVwapAvoidEdgeHours);
               if(vwapSig != 0)
               {
                  if(InpCostGateEnabled)
                  {
                     double vwap = BTCScalperVwapValue();
                     double atrRef = BTCScalperGetBufferValue(g_btcAtrM5Handle, 0, 1);
                     double expectedMove = MathAbs(SymbolInfoDouble(symbol, SYMBOL_ASK) - vwap);
                     if(vwap <= 0.0 || atrRef == EMPTY_VALUE ||
                        !BTCScalperCostGatePass(symbol, expectedMove, atrRef, InpCostGateK, InpCostGateCommPerLot, InpCostGateMinAtrMult))
                        vwapSig = 0;
                  }
               }
               if(vwapSig != 0 && InpRegimeGateEnabled)
               {
                  if(!BTCScalperRegimeGatePass(g_btcRegimeAtrHandle, InpRegimeAtrAvgPeriod, InpRegimeMinH1AtrRatio, InpRegimeMaxH1AtrRatio))
                     vwapSig = 0;
               }
               if(vwapSig != 0)
               {
                  double vwapRisk = BTCScalperStrategyRisk(BTC_STRAT_VWAP, risk);
                  if(vwapRisk > 0.0)
                  {
                     if(InpEnablePerfAllocation)
                        BTCScalperJournal(StringFormat("AllocDecision strategy=vwap_reversion regime=range mult=%.3f risk=%.4f",
                           vwapRisk / MathMax(risk, 1e-9), vwapRisk));
                     BTCScalperVwapEntry(symbol, InpMagicNumber, trade, vwapSig, InpVwapSlAtrMult, vwapRisk, InpMinLot, InpMaxLot, InpVwapMaxTrades, InpVwapTpOvershootAtr);
                  }
               }
            }
         }
      }
   }

   // 5. Configurable-TF momentum signals (H4 research path; skipped for legacy M15)
   if(InpEnableMomentum && InpMomTf != PERIOD_M15 && BTCScalperIsNewBar(symbol, InpMomTf, g_btcLastMomBar))
   {
      double risk = BTCScalperEffectiveRisk();
      string reason = "";
      bool cancelPending = false;
      bool allowed = BTCScalperEntryRiskAllowed(symbol, InpMagicNumber, InpMaxDailyLossPct,
                                               InpMaxDailyTrades, InpMaxOpenTrades,
                                               InpTradingEndHour, risk, reason, cancelPending);

      if(!allowed)
      {
         if(cancelPending)
            BTCScalperCancelPendingOrders(symbol, InpMagicNumber);
      }
      else if(!InpDebugOnly && BTCScalperCooldownAllowed(InpMaxConsecLoss))
      {
         bool routed = true;
         if(InpUseGatekeeperRouting)
         {
            double adxVal = BTCScalperGetBufferValue(g_btcAdxHandle, 0, 1);
            routed = (adxVal != EMPTY_VALUE && adxVal >= InpGatekeeperAdxLevel);
         }
         if(routed)
            BTCScalperTryMomentumEntry(symbol, risk, InpUseGatekeeperRouting ? "trend" : "ungated");
      }
   }
}

//+------------------------------------------------------------------+
//| Trade Transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(symbol != BTCScalperSymbol() || magic != InpMagicNumber)
      return;

   long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);

   // ORDERING IS LOAD-BEARING: read this deal's realized P/L BEFORE any
   // HistorySelect* call below. HistorySelectByPosition() reselects the history
   // pool and makes HistoryDealGetDouble(trans.deal, ...) return 0.00, which
   // silently feeds the performance allocator and the consec-loss tracker zeros.
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP);

   string strategy = "unknown";
   if(StringFind(comment, "BTC_MR_") >= 0)
      strategy = "mean_reversion";
   else if(StringFind(comment, "BTC_VWAP_") >= 0)
      strategy = "vwap_reversion";
   else if(StringFind(comment, "BTC_Mom_") >= 0)
      strategy = "momentum";

   // Exit deals carry SL/TP price as comment, not the strategy tag.
   // Look up the strategy from the entry deal of the same position.
   // (Runs after the profit read above so it can't clobber it.)
   if(strategy == "unknown" && HistorySelectByPosition(positionId))
   {
      int nd = HistoryDealsTotal();
      for(int _i = 0; _i < nd; _i++)
      {
         ulong _d = HistoryDealGetTicket(_i);
         if((long)HistoryDealGetInteger(_d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         string _c = HistoryDealGetString(_d, DEAL_COMMENT);
         if(StringFind(_c, "BTC_MR_") >= 0)        { strategy = "mean_reversion"; break; }
         else if(StringFind(_c, "BTC_VWAP_") >= 0) { strategy = "vwap_reversion"; break; }
         else if(StringFind(_c, "BTC_Mom_") >= 0)  { strategy = "momentum";       break; }
      }
   }

   BTCScalperJournal(StringFormat("Deal deal=%I64u position=%I64u entry=%d strategy=%s profit=%.2f comment=%s",
      trans.deal, positionId, dealEntry, strategy, profit, comment));

   // Entry deal filled
   if(dealEntry == DEAL_ENTRY_IN || dealEntry == DEAL_ENTRY_INOUT)
   {
      BTCScalperIncrementDailyTradeCount();
      BTCScalperJournal(StringFormat("Daily filled trade count=%d strategy=%s position=%I64u",
         BTCScalperDailyTradeCount(), strategy, positionId));

      if(!BTCScalperDailyTradeAllowed(InpMaxDailyTrades))
         BTCScalperCancelPendingOrders(symbol, InpMagicNumber);
   }

   // Exit deal filled
   if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY)
   {
      BTCScalperRecordTradeResult(profit > 0.0);

      if(InpEnablePerfAllocation)
      {
         BTCStrategyId sid = BTCScalperStrategyIdFromName(strategy);
         if(sid != BTC_STRAT_COUNT)
         {
            BTCScalperPerfRecord(sid, profit, InpPerfWindowN);
            BTCPerfMetrics m = BTCScalperPerfMetrics(sid);
            double pfLog = (m.profitFactor == DBL_MAX) ? 9999.0 : m.profitFactor;
            BTCScalperJournal(StringFormat("PerfRecord strategy=%s profit=%.2f n=%d winrate=%.3f pf=%.3f net=%.2f",
               strategy, profit, m.n, m.winRate, pfLog, m.netPnl));
         }
      }

      if(!BTCScalperDailyLossAllowed(InpMaxDailyLossPct))
         BTCScalperCancelPendingOrders(symbol, InpMagicNumber);
      if(BTCScalperEffectiveRisk() <= 0.0)
         BTCScalperCancelPendingOrders(symbol, InpMagicNumber);
   }
}

//+------------------------------------------------------------------+
//| Symbol Helper                                                    |
//+------------------------------------------------------------------+
string BTCScalperSymbol()
{
   return InpSymbol == "" ? _Symbol : InpSymbol;
}
