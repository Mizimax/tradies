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

//+------------------------------------------------------------------+
//| Input parameters                                                  |
//+------------------------------------------------------------------+

//--- Core
input string   InpSymbol              = "BTCUSD";
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
input int      InpBestSessionStart    = 8;           // London open
input int      InpBestSessionEnd      = 18;          // NY close

//--- Strategy 1: Mean Reversion (BB + RSI on M15)
input bool     InpEnableMeanReversion = true;
input int      InpMrBbPeriod          = 20;
input double   InpMrBbDeviation       = 2.0;
input int      InpMrRsiPeriod         = 14;
input int      InpMrRsiOverbought     = 70;
input int      InpMrRsiOversold       = 30;
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

//--- Strategy 3: Momentum Breakout (EMA crossover on M15)
input bool     InpEnableMomentum      = true;
input int      InpMomEmaFast          = 9;
input int      InpMomEmaSlow          = 21;
input int      InpMomRsiPeriod        = 14;
input int      InpMomRsiLow           = 40;          // only enter when RSI 40-60
input int      InpMomRsiHigh          = 60;
input double   InpMomRR               = 2.0;         // R:R for momentum trades
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

//--- Debug
input bool     InpDebugOnly           = false;
input bool     InpResetJournalOnInit  = true;

//--- Global Variables
CTrade trade;

//--- Forward Declarations
string BTCScalperSymbol();

//--- Effective Risk Calculation
double BTCScalperEffectiveRisk()
{
   return InpEnableDdScaling
      ? BTCScalperDrawdownScaledRisk(InpRiskPerTradePct, InpDdScaleHalfAtPct, InpDdScaleQuarterAtPct, InpDdStopAtPct)
      : InpRiskPerTradePct;
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

   // Initialize indicators
   if(!BTCScalperIndicatorsInit(symbol, InpMrBbPeriod, InpMrBbDeviation, 
                                InpMrRsiPeriod, 14, InpGatekeeperAdxPeriod, 
                                InpMomEmaFast, InpMomEmaSlow))
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
      BTCScalperVwapManage(symbol, InpMagicNumber, trade);
   if(InpEnableMomentum)
      BTCScalperMomManage(symbol, InpMagicNumber, trade);

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
                  BTCScalperMREntry(symbol, InpMagicNumber, trade, mrSig, InpMrSlAtrMult, risk, InpMinLot, InpMaxLot, InpMrMaxTrades);
               }
            }

            if(InpEnableMomentum && isTrending)
            {
               int momSig = BTCScalperMomSignal(symbol, InpMomRsiLow, InpMomRsiHigh, InpTradingEndHour);
               if(momSig != 0)
               {
                  BTCScalperMomEntry(symbol, InpMagicNumber, trade, momSig, InpMomRR, risk, InpMinLot, InpMaxLot, InpMomMaxTrades);
               }
            }
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
               int vwapSig = BTCScalperVwapSignal(symbol, InpVwapZscoreEntry, InpTradingEndHour);
               if(vwapSig != 0)
               {
                  BTCScalperVwapEntry(symbol, InpMagicNumber, trade, vwapSig, InpVwapSlAtrMult, risk, InpMinLot, InpMaxLot, InpVwapMaxTrades);
               }
            }
         }
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
   
   string strategy = "unknown";
   if(StringFind(comment, "BTC_MR_") >= 0)
      strategy = "mean_reversion";
   else if(StringFind(comment, "BTC_VWAP_") >= 0)
      strategy = "vwap_reversion";
   else if(StringFind(comment, "BTC_Mom_") >= 0)
      strategy = "momentum";

   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP);

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
