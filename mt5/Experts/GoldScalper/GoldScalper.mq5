#property strict
#property version   "1.00"
#property description "Gold XAU/USD Multi-Strategy Scalping EA"
#property description "Asian Breakout + Mean Reversion + Momentum Continuation"

#include <Trade/Trade.mqh>
#include <GoldScalper/SessionTime.mqh>
#include <GoldScalper/RiskManager.mqh>
#include <GoldScalper/NewsFilter.mqh>
#include <GoldScalper/BreakoutRegimeFilter.mqh>
#include <GoldScalper/AsianBreakout.mqh>
#include <GoldScalper/MeanReversion.mqh>
#include <GoldScalper/MomentumContinuation.mqh>
#include <GoldScalper/RegimeDetector.mqh>

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+

//--- Core
input string          InpSymbol               = "XAUUSD";
input long            InpMagicNumber          = 26060201;
input double          InpRiskPerTradePct      = 0.5;
input double          InpMinLot               = 0.01;
input double          InpMaxLot               = 10.0;
input double          InpMaxDailyLossPct      = 3.0;
input int             InpMaxDailyTrades       = 15;
input int             InpMaxOpenTrades        = 3;

//--- Session Times (server time hours)
input int             InpAsianStartHour       = 22;
input int             InpAsianEndHour         = 5;
input int             InpLondonStartHour      = 7;
input int             InpLondonEndHour        = 12;
input int             InpNyOverlapStartHour   = 10;
input int             InpNyOverlapEndHour     = 18;
input int             InpTradingEndHour       = 20;

//--- Strategy 1: Asian Breakout
input bool            InpEnableAsianBreakout  = true;
input double          InpBreakoutBuffer       = 1.0;
input double          InpBreakoutMinRange     = 200.0;  // points (200 = $2.00 min Asian range for gold)
input double          InpBreakoutMaxRange     = 3000.0; // points (3000 = $30.00 max Asian range for gold)
input double          InpBreakoutRR           = 1.5;
input bool            InpBreakoutTrailAtr     = true;
input int             InpBreakoutMaxTrades    = 2;
input bool            InpBreakoutRegimeFilter = false;
input bool            InpBreakoutDirectionFilter = true;
input int             InpBreakoutTrendEmaPeriod = 50;
input int             InpBreakoutAdxPeriod    = 14;
input double          InpBreakoutAdxMin       = 18.0;
input double          InpBreakoutAdxMax       = 35.0;
input double          InpBreakoutRangeAtrMin  = 0.12;
input double          InpBreakoutRangeAtrMax  = 0.55;
input double          InpBreakoutPriorDayAtrMax = 1.8;
input bool            InpEnableNyBreakout     = false;
input int             InpNyBreakoutRangeStartHour = 7;
input int             InpNyBreakoutRangeEndHour = 12;
input int             InpNyBreakoutStartHour  = 13;
input int             InpNyBreakoutEndHour    = 18;
input double          InpNyBreakoutBuffer     = 0.5;
input double          InpNyBreakoutMinRange   = 200.0;
input double          InpNyBreakoutMaxRange   = 5000.0;
input double          InpNyBreakoutRR         = 1.5;
input int             InpNyBreakoutMaxTrades  = 1;
input bool            InpBreakoutRunnerEnabled = false;
input double          InpBreakoutRunnerCoreRiskShare = 0.60;
input double          InpBreakoutRunnerCoreRR = 1.5;
input double          InpBreakoutRunnerRR     = 0.0;
input double          InpBreakoutRunnerBETriggerR = 1.0;
input double          InpBreakoutRunnerTrailStartR = 1.5;
input double          InpBreakoutRunnerTrailAtrMult = 2.0;
input int             InpBreakoutRunnerMaxHoldHours = 12;
input bool            InpBreakoutRunnerProfitLock = false;
input double          InpBreakoutRunnerMfeTrailStartR = 1.5;
input double          InpBreakoutRunnerMfeLockPct = 0.55;
input double          InpBreakoutRunnerMinLockedR = 0.50;

//--- Strategy 2: Mean Reversion
input bool            InpEnableMeanReversion  = true;
input int             InpBbPeriod             = 20;
input double          InpBbDeviation          = 2.0;
input int             InpRsiPeriod            = 14;
input int             InpRsiOverbought        = 70;
input int             InpRsiOversold          = 30;
input int             InpMrTrendEma           = 50;
input double          InpMrSlAtr              = 2.0;   // ATR multiplier for SL (was 1.5, widened for gold volatility)
input int             InpMrMaxTrades          = 6;
input int             InpMrAdxPeriod          = 14;    // ADX period for regime filter
input double          InpMrAdxMax             = 25.0;  // Max ADX for MR (0=disabled, <25=range-bound only)
input double          InpMrBbMinWidth         = 0.3;   // Min BB bandwidth % (0=disabled, skip squeeze)
input bool            InpMrRegimeFilter       = true;  // Use D1 EMA macro regime filter
input bool            InpMrTrailBE            = true;  // Trailing stop to breakeven
input double          InpMrTrailBETrigger     = 1.0;   // Trail to BE when profit > 1.0x ATR
input int             InpMaxConsecLoss        = 2;     // Pause after N consecutive losses (0=disabled)
input bool            InpEnableDdScaling      = true;  // Scale risk down as drawdown increases
input double          InpDdScaleHalfAtPct     = 10.0;
input double          InpDdScaleQuarterAtPct  = 15.0;
input double          InpDdStopAtPct          = 20.0;
input bool            InpDdClosePositionsOnStop = false;
input bool            InpDdCloseRunnerOnly    = true;

//--- Strategy 3: Momentum Continuation
input bool            InpEnableMomentum       = true;
input int             InpMomPullbackEma       = 9;
input int             InpMomRsiPeriod         = 10;
input int             InpMomRsiLow            = 40;
input int             InpMomRsiHigh           = 60;
input double          InpMomRR                = 2.0;
input int             InpMomMaxTrades         = 2;

//--- Dynamic Strategy Allocation (Gatekeeper)
input bool            InpDynamicAllocation    = true;
input int             InpGatekeeperAdxPeriod  = 14;
input double          InpGatekeeperAdxLevel   = 25.0;

//--- News Filter
input bool            InpEnableNewsFilter     = true;
input int             InpNewsBlackoutMinutes  = 30;
input string          InpHighImpactNewsTimes  = "";

//--- Debug
input bool            InpDebugOnly            = false;
input bool            InpResetJournalOnInit   = true;

//+------------------------------------------------------------------+
//| Global variables                                                  |
//+------------------------------------------------------------------+
CTrade trade;
int s_gatekeeperAdxHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Shared risk and attribution helpers                              |
//+------------------------------------------------------------------+
double GoldScalperEffectiveRisk()
{
   return InpEnableDdScaling
      ? GoldScalperDrawdownScaledRisk(InpRiskPerTradePct, InpDdScaleHalfAtPct, InpDdScaleQuarterAtPct, InpDdStopAtPct)
      : InpRiskPerTradePct;
}

bool GoldScalperEntryRiskAllowed(const string symbol,
                                 const long magic,
                                 const double maxDailyLossPct,
                                 const int maxDailyTrades,
                                 const int maxOpenTrades,
                                 const int tradingEndHour,
                                 const double effectiveRiskPct,
                                 string &reason,
                                 bool &cancelPending)
{
   reason = "";
   cancelPending = false;

   if(effectiveRiskPct <= 0.0)
   {
      reason = "drawdown_stop";
      cancelPending = true;
      return false;
   }

   if(!GoldScalperDailyLossAllowed(maxDailyLossPct))
   {
      reason = "daily_loss";
      cancelPending = true;
      return false;
   }

   if(!GoldScalperDailyTradeAllowed(maxDailyTrades))
   {
      reason = "daily_trade_limit";
      cancelPending = true;
      return false;
   }

   if(!GoldScalperMaxOpenAllowed(symbol, magic, maxOpenTrades))
   {
      reason = "max_open_trades";
      return false;
   }

   if(!GoldScalperIsTradingHours(tradingEndHour))
   {
      reason = "trading_end";
      return false;
   }

   return true;
}

void GoldScalperCancelPendingOrdersForRisk(const string symbol,
                                           const long magic,
                                           const string reason)
{
   int pendingCount = GoldScalperCountPendingOrders(symbol, magic);
   if(pendingCount <= 0)
      return;

   GoldScalperCancelPendingOrders(symbol, magic, trade);
   GoldScalperJournal(StringFormat("Global risk cancelled %d pending orders reason=%s",
      pendingCount, reason));
}

void GoldScalperApplyRiskStopActions(const string symbol,
                                     const long magic,
                                     const string reason)
{
   GoldScalperCancelPendingOrdersForRisk(symbol, magic, reason);

   if(reason == "drawdown_stop" && InpDdClosePositionsOnStop)
      GoldScalperCloseBreakoutPositionsForRisk(symbol, magic, InpDdCloseRunnerOnly, reason);
}

string GoldScalperStrategyFromComment(const string comment)
{
   if(StringFind(comment, "ABrk") >= 0 || StringFind(comment, "NYBrk") >= 0)
      return "breakout";
   if(StringFind(comment, "GoldScalper_MR_") >= 0)
      return "mean_reversion";
   if(StringFind(comment, "GS_Mom_") >= 0 || StringFind(comment, "GoldScalper_Mom_") >= 0)
      return "momentum";
   return "unknown";
}

string GoldScalperEntryStrategyForPosition(const ulong positionId)
{
   if(positionId == 0)
      return "unknown";

   datetime toTime = TimeCurrent() + 60;
   if(!HistorySelect(0, toTime))
      return "unknown";

   int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0)
         continue;
      if((ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) != positionId)
         continue;
      if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != GoldScalperSymbol())
         continue;
      if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != InpMagicNumber)
         continue;

      long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_IN && entryType != DEAL_ENTRY_INOUT)
         continue;

      string strategy = GoldScalperStrategyFromComment(HistoryDealGetString(dealTicket, DEAL_COMMENT));
      if(strategy != "unknown")
         return strategy;
   }

   return "unknown";
}

string GoldScalperStrategyForDeal(const long dealEntry,
                                  const string comment,
                                  const ulong positionId)
{
   string strategy = GoldScalperStrategyFromComment(comment);
   if(strategy != "unknown")
      return strategy;

   if(dealEntry != DEAL_ENTRY_IN && dealEntry != DEAL_ENTRY_INOUT)
      strategy = GoldScalperEntryStrategyForPosition(positionId);

   return strategy;
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   string symbol = GoldScalperSymbol();
   if(!SymbolSelect(symbol, true))
   {
      Print("GoldScalper: Unable to select symbol ", symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);

   if(InpResetJournalOnInit)
      GoldScalperResetJournal();

   GoldScalperResetTesterRiskState();

   // Initialize strategy modules
   if(InpEnableAsianBreakout)
      GoldScalperAsianBreakoutInit();
   if(InpEnableNyBreakout)
      GoldScalperNyBreakoutInit();
   if((InpEnableAsianBreakout || InpEnableNyBreakout) && InpBreakoutRegimeFilter)
   {
      if(!GoldScalperBreakoutRegimeInit(symbol, InpBreakoutTrendEmaPeriod, InpBreakoutAdxPeriod))
         return INIT_FAILED;
   }

   if(InpEnableMeanReversion)
   {
      GoldScalperMeanReversionInit(symbol, InpBbPeriod, InpBbDeviation,
                                    InpRsiPeriod, InpMrTrendEma, InpMrAdxPeriod);
      if(InpMrRegimeFilter)
         GoldScalperRegimeInit(symbol, 50);
   }

   if(InpEnableMomentum)
      GoldScalperMomentumInit(symbol, InpMomPullbackEma, InpMomRsiPeriod);

   if(InpDynamicAllocation)
      s_gatekeeperAdxHandle = iADX(symbol, PERIOD_M15, InpGatekeeperAdxPeriod);

   Print("GoldScalper initialized for ", symbol, " magic=", InpMagicNumber);
   Print("  Strategies: AsianBreakout=", InpEnableAsianBreakout ? "ON" : "OFF",
         " NYBreakout=", InpEnableNyBreakout ? "ON" : "OFF",
         " MeanReversion=", InpEnableMeanReversion ? "ON" : "OFF",
         " Momentum=", InpEnableMomentum ? "ON" : "OFF");
   Print("  Risk: ", DoubleToString(InpRiskPerTradePct, 1), "% per trade",
         " MaxDailyLoss=", DoubleToString(InpMaxDailyLossPct, 1), "%",
         " MaxTrades=", InpMaxDailyTrades,
         " MaxOpen=", InpMaxOpenTrades);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if((InpEnableAsianBreakout || InpEnableNyBreakout) && InpBreakoutRegimeFilter)
      GoldScalperBreakoutRegimeDeinit();

   if(InpEnableMeanReversion)
   {
      GoldScalperMeanReversionDeinit();
      if(InpMrRegimeFilter)
         GoldScalperRegimeDeinit();
   }

   if(InpEnableMomentum)
      GoldScalperMomentumDeinit();

   if(s_gatekeeperAdxHandle != INVALID_HANDLE)
      IndicatorRelease(s_gatekeeperAdxHandle);

   Print("GoldScalper deinitialized. Reason=", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   string symbol = GoldScalperSymbol();

   bool breakoutEnabled = (InpEnableAsianBreakout || InpEnableNyBreakout);

   //--- Always manage existing positions (trailing, etc.)
   if(breakoutEnabled)
      GoldScalperAsianBreakoutManage(
         symbol, InpMagicNumber, trade, InpBreakoutTrailAtr,
         InpBreakoutRunnerEnabled,
         InpBreakoutRunnerBETriggerR,
         InpBreakoutRunnerTrailStartR,
         InpBreakoutRunnerTrailAtrMult,
         InpBreakoutRunnerMaxHoldHours,
         InpBreakoutRunnerProfitLock,
         InpBreakoutRunnerMfeTrailStartR,
         InpBreakoutRunnerMfeLockPct,
         InpBreakoutRunnerMinLockedR);

   if(InpEnableMeanReversion)
      GoldScalperMeanReversionManage(symbol, InpMagicNumber, trade, InpMrTrailBE, InpMrTrailBETrigger);

   //--- Check for new M1 bar (Asian Breakout range building + order placement)
   if(GoldScalperIsNewM1Bar(symbol))
   {
      if(breakoutEnabled)
      {
         double breakoutRisk = GoldScalperEffectiveRisk();
         string breakoutRiskReason = "";
         bool breakoutCancelPending = false;
         bool breakoutAllowed = GoldScalperEntryRiskAllowed(
            symbol, InpMagicNumber,
            InpMaxDailyLossPct, InpMaxDailyTrades, InpMaxOpenTrades,
            InpTradingEndHour, breakoutRisk,
            breakoutRiskReason, breakoutCancelPending);

         MqlDateTime now;
         TimeToStruct(TimeCurrent(), now);
         bool asianPlacementAttempt = InpEnableAsianBreakout
            && now.hour == InpLondonStartHour
            && !GoldScalperBreakoutOrdersPlacedToday();
         bool nyPlacementAttempt = InpEnableNyBreakout
            && now.hour == InpNyBreakoutStartHour
            && !GoldScalperNyBreakoutOrdersPlacedToday();
         bool breakoutPlacementAttempt = (asianPlacementAttempt || nyPlacementAttempt);

         if(!breakoutAllowed && breakoutCancelPending)
            GoldScalperApplyRiskStopActions(symbol, InpMagicNumber, breakoutRiskReason);

         if(breakoutPlacementAttempt && !breakoutAllowed)
         {
            GoldScalperJournal(StringFormat("Breakout entry blocked asian=%d ny=%d reason=%s risk=%.3f",
               asianPlacementAttempt ? 1 : 0,
               nyPlacementAttempt ? 1 : 0,
               breakoutRiskReason,
               breakoutRisk));
         }
         else
         {
            if(InpEnableAsianBreakout)
            {
               GoldScalperAsianBreakoutOnNewBar(
                  symbol, InpMagicNumber, trade,
                  InpAsianStartHour, InpAsianEndHour,
                  InpLondonStartHour, InpLondonEndHour,
                  InpBreakoutBuffer, InpBreakoutMinRange, InpBreakoutMaxRange,
                  InpBreakoutRR, InpBreakoutTrailAtr,
                  InpBreakoutMaxTrades, breakoutRisk, InpMinLot, InpMaxLot,
                  InpBreakoutRegimeFilter, InpBreakoutDirectionFilter,
                  InpBreakoutAdxMin, InpBreakoutAdxMax,
                  InpBreakoutRangeAtrMin, InpBreakoutRangeAtrMax,
                  InpBreakoutPriorDayAtrMax,
                  InpBreakoutRunnerEnabled, InpBreakoutRunnerCoreRiskShare,
                  InpBreakoutRunnerCoreRR, InpBreakoutRunnerRR);
            }

            if(InpEnableNyBreakout)
            {
               GoldScalperNyBreakoutOnNewBar(
                  symbol, InpMagicNumber, trade,
                  InpNyBreakoutRangeStartHour, InpNyBreakoutRangeEndHour,
                  InpNyBreakoutStartHour, InpNyBreakoutEndHour,
                  InpNyBreakoutBuffer, InpNyBreakoutMinRange, InpNyBreakoutMaxRange,
                  InpNyBreakoutRR, InpBreakoutTrailAtr,
                  InpNyBreakoutMaxTrades, breakoutRisk, InpMinLot, InpMaxLot,
                  InpBreakoutRegimeFilter, InpBreakoutDirectionFilter,
                  InpBreakoutAdxMin, InpBreakoutAdxMax,
                  InpBreakoutRangeAtrMin, InpBreakoutRangeAtrMax,
                  InpBreakoutPriorDayAtrMax,
                  InpBreakoutRunnerEnabled, InpBreakoutRunnerCoreRiskShare,
                  InpBreakoutRunnerCoreRR, InpBreakoutRunnerRR);
            }
         }
      }
   }

   //--- Check for new M5 bar (Mean Reversion + Momentum signals)
   if(GoldScalperIsNewM5Bar(symbol))
   {
      //--- Global risk gates (only block entries, not position management above)
      double m5Risk = GoldScalperEffectiveRisk();
      string m5RiskReason = "";
      bool m5CancelPending = false;
      bool m5Allowed = GoldScalperEntryRiskAllowed(
         symbol, InpMagicNumber,
         InpMaxDailyLossPct, InpMaxDailyTrades, InpMaxOpenTrades,
         InpTradingEndHour, m5Risk,
         m5RiskReason, m5CancelPending);

      if(m5Allowed)
      {
         //--- News filter
         bool newsBlocked = false;
         if(InpEnableNewsFilter)
         {
            string matchedEvent = "";
            if(GoldScalperNewsBlocked(InpHighImpactNewsTimes, InpNewsBlackoutMinutes, matchedEvent))
            {
               GoldScalperJournal("News blackout blocked. Event=" + matchedEvent);
               newsBlocked = true;
            }
         }

         if(!newsBlocked)
         {
            bool allowMREntry = InpEnableMeanReversion;
            bool allowMomEntry = InpEnableMomentum;

            if(InpDynamicAllocation && s_gatekeeperAdxHandle != INVALID_HANDLE)
            {
               double adxValues[];
               ArraySetAsSeries(adxValues, true);
               if(CopyBuffer(s_gatekeeperAdxHandle, 0, 1, 1, adxValues) == 1)
               {
                  if(adxValues[0] >= InpGatekeeperAdxLevel)
                     allowMREntry = false; // Trend: Disable MR
                  else
                     allowMomEntry = false; // Range: Disable Momentum
               }
            }

            //--- Strategy 2: Mean Reversion (during NY overlap)
            if(allowMREntry && !InpDebugOnly && GoldScalperCooldownAllowed(InpMaxConsecLoss))
            {
               ENUM_REGIME currentRegime = REGIME_RANGE;
               if(InpMrRegimeFilter)
                  currentRegime = GoldScalperDetectRegime();

               int mrSignal = GoldScalperMeanReversionSignal(
                  symbol,
                  InpBbPeriod, InpBbDeviation, InpRsiPeriod,
                  InpRsiOverbought, InpRsiOversold,
                  InpMrTrendEma, InpNyOverlapStartHour, InpNyOverlapEndHour,
                  InpMrAdxMax, InpMrBbMinWidth, currentRegime);

               if(mrSignal != 0)
               {
                  if(m5Risk > 0.0)
                  {
                     GoldScalperMeanReversionEntry(
                        symbol, InpMagicNumber, trade,
                        mrSignal, InpBbPeriod, InpBbDeviation,
                        InpMrSlAtr, InpRsiPeriod,
                        m5Risk, InpMinLot, InpMaxLot,
                        InpMrMaxTrades);
                  }
                  else
                  {
                     GoldScalperJournal("MR signal skipped: DD scaling returned 0 risk");
                  }
               }
            }

            //--- Strategy 3: Momentum Continuation (breakout-direction bias or EMA trend fallback)
            if(allowMomEntry && !InpDebugOnly)
            {
               int momSignal = GoldScalperMomentumSignal(
                  symbol,
                  InpMomPullbackEma, InpMomRsiPeriod,
                  InpMomRsiLow, InpMomRsiHigh,
                  InpLondonStartHour, InpNyOverlapEndHour);

               if(momSignal != 0)
               {
                  GoldScalperMomentumEntry(
                     symbol, InpMagicNumber, trade,
                     momSignal, InpMomRR,
                     m5Risk, InpMinLot, InpMaxLot,
                     InpMomMaxTrades);
               }
            }
         }
      }
      else
      {
         if(m5CancelPending)
            GoldScalperApplyRiskStopActions(symbol, InpMagicNumber, m5RiskReason);
      }
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                         |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(symbol != GoldScalperSymbol() || magic != InpMagicNumber)
      return;

   long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   string strategy = GoldScalperStrategyForDeal(dealEntry, comment, positionId);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP);

   GoldScalperJournal(StringFormat("Deal deal=%I64u position=%I64u entry=%d strategy=%s profit=%.2f comment=%s",
      trans.deal, positionId, dealEntry, strategy, profit, comment));

   if(dealEntry == DEAL_ENTRY_IN || dealEntry == DEAL_ENTRY_INOUT)
   {
      GoldScalperIncrementDailyTradeCount();
      GoldScalperJournal(StringFormat("Daily filled trade count=%d strategy=%s position=%I64u",
         GoldScalperDailyTradeCount(), strategy, positionId));

      if(!GoldScalperDailyTradeAllowed(InpMaxDailyTrades))
         GoldScalperApplyRiskStopActions(symbol, InpMagicNumber, "daily_trade_limit");
   }

   if((dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY) && InpEnableMeanReversion)
   {
      if(strategy == "mean_reversion")
         GoldScalperRecordTradeResult(profit > 0.0);
   }

   if((dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY) && profit > 0.0)
   {
      if(strategy == "breakout")
      {
         // Determine direction from the deal type
         long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
         // For a closing deal: SELL close = was LONG, BUY close = was SHORT
         int dir = (dealType == DEAL_TYPE_SELL) ? 1 : -1;
         GoldScalperMarkBreakoutTpHit(dir);
         GoldScalperJournal(StringFormat("Breakout TP hit. Direction=%d Profit=%.2f", dir, profit));
      }
   }

   if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY)
   {
      if(!GoldScalperDailyLossAllowed(InpMaxDailyLossPct))
         GoldScalperApplyRiskStopActions(symbol, InpMagicNumber, "daily_loss");
      if(GoldScalperEffectiveRisk() <= 0.0)
         GoldScalperApplyRiskStopActions(symbol, InpMagicNumber, "drawdown_stop");
   }
}

//+------------------------------------------------------------------+
//| Helper                                                            |
//+------------------------------------------------------------------+
string GoldScalperSymbol()
{
   return InpSymbol == "" ? _Symbol : InpSymbol;
}
