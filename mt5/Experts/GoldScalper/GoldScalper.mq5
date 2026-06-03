#property strict
#property version   "1.00"
#property description "Gold XAU/USD Multi-Strategy Scalping EA"
#property description "Asian Breakout + Mean Reversion + Momentum Continuation"

#include <Trade/Trade.mqh>
#include <GoldScalper/SessionTime.mqh>
#include <GoldScalper/RiskManager.mqh>
#include <GoldScalper/NewsFilter.mqh>
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

   // Initialize strategy modules
   GoldScalperAsianBreakoutInit();

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
   Print("  Strategies: Breakout=", InpEnableAsianBreakout ? "ON" : "OFF",
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

   //--- Always manage existing positions (trailing, etc.)
   if(InpEnableAsianBreakout)
      GoldScalperAsianBreakoutManage(symbol, InpMagicNumber, trade, InpBreakoutTrailAtr);

   if(InpEnableMeanReversion)
      GoldScalperMeanReversionManage(symbol, InpMagicNumber, trade, InpMrTrailBE, InpMrTrailBETrigger);

   //--- Check for new M1 bar (Asian Breakout range building + order placement)
   if(GoldScalperIsNewM1Bar(symbol))
   {
      if(InpEnableAsianBreakout)
      {
         GoldScalperAsianBreakoutOnNewBar(
            symbol, InpMagicNumber, trade,
            InpAsianStartHour, InpAsianEndHour,
            InpLondonStartHour, InpLondonEndHour,
            InpBreakoutBuffer, InpBreakoutMinRange, InpBreakoutMaxRange,
            InpBreakoutRR, InpBreakoutTrailAtr,
            InpBreakoutMaxTrades, InpRiskPerTradePct, InpMinLot, InpMaxLot);
      }
   }

   //--- Check for new M5 bar (Mean Reversion + Momentum signals)
   if(GoldScalperIsNewM5Bar(symbol))
   {
      //--- Global risk gates (only block M5 strategies, not position management above)
      bool m5Allowed = GoldScalperDailyLossAllowed(InpMaxDailyLossPct) &&
                       GoldScalperDailyTradeAllowed(InpMaxDailyTrades) &&
                       GoldScalperMaxOpenAllowed(symbol, InpMagicNumber, InpMaxOpenTrades) &&
                       GoldScalperIsTradingHours(InpTradingEndHour) &&
                       GoldScalperCooldownAllowed(InpMaxConsecLoss);

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
            if(allowMREntry && !InpDebugOnly)
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
                  // Apply drawdown-scaled risk if enabled
                  double effectiveRisk = InpEnableDdScaling
                     ? GoldScalperDrawdownScaledRisk(InpRiskPerTradePct)
                     : InpRiskPerTradePct;

                  if(effectiveRisk > 0.0)
                  {
                     GoldScalperMeanReversionEntry(
                        symbol, InpMagicNumber, trade,
                        mrSignal, InpBbPeriod, InpBbDeviation,
                        InpMrSlAtr, InpRsiPeriod,
                        effectiveRisk, InpMinLot, InpMaxLot,
                        InpMrMaxTrades);
                  }
                  else
                  {
                     GoldScalperJournal("MR signal skipped — DD scaling returned 0 risk");
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
                     InpRiskPerTradePct, InpMinLot, InpMaxLot,
                     InpMomMaxTrades);
               }
            }
         }
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
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP);

   GoldScalperJournal(StringFormat("Deal deal=%I64u entry=%d profit=%.2f comment=%s",
      trans.deal, dealEntry, profit, comment));

   // Track consecutive wins/losses for MR cooldown
   // When a deal closes (DEAL_ENTRY_OUT), record win/loss for the cooldown counter.
   // In MR-only mode, all exits are MR trades.
   // In mixed mode, we check the position comment for "GoldScalper_MR_" prefix.
   // Note: MT5 broker may change the comment on exit (e.g. "sl 2345" or "tp 2367"),
   // so we also need to look up the original position comment via the position ticket.
   if(dealEntry == DEAL_ENTRY_OUT && InpEnableMeanReversion)
   {
      bool isMrTrade = false;
      
      // If only MR is enabled, all trades are MR trades
      if(!InpEnableAsianBreakout && !InpEnableMomentum)
         isMrTrade = true;
      else
      {
         // Check comment for MR prefix (covers opening deal comment)
         if(StringFind(comment, "GoldScalper_MR_") >= 0)
            isMrTrade = true;
         // For SL/TP closes, broker replaces comment — check position history
         // Since we only have the deal, check if it's NOT a breakout or momentum trade
         if(!isMrTrade && StringFind(comment, "ABrk_") < 0 && StringFind(comment, "GoldScalper_Mom_") < 0)
            isMrTrade = true;  // Default to MR if not identifiable as other strategies
      }
      
      if(isMrTrade)
         GoldScalperRecordTradeResult(profit > 0.0);
   }

   // If a breakout trade hit TP, mark it for momentum continuation
   // Note: Asian Breakout comments use prefix "ABrk_" (e.g. "ABrk_Buy_2024.06.01")
   if(dealEntry == DEAL_ENTRY_OUT && profit > 0.0)
   {
      if(StringFind(comment, "ABrk_") >= 0)
      {
         // Determine direction from the deal type
         long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
         // For a closing deal: SELL close = was LONG, BUY close = was SHORT
         int dir = (dealType == DEAL_TYPE_SELL) ? 1 : -1;
         GoldScalperMarkBreakoutTpHit(dir);
         GoldScalperJournal(StringFormat("Breakout TP hit. Direction=%d Profit=%.2f", dir, profit));
      }
   }
}

//+------------------------------------------------------------------+
//| Helper                                                            |
//+------------------------------------------------------------------+
string GoldScalperSymbol()
{
   return InpSymbol == "" ? _Symbol : InpSymbol;
}
