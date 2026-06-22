#ifndef BTCSCALPER_MEAN_REVERSION_MQH
#define BTCSCALPER_MEAN_REVERSION_MQH

//+------------------------------------------------------------------+
//| MeanReversion.mqh — Bollinger Band + RSI mean reversion on M15   |
//| Part of BTCScalper EA                                            |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
#include <BTCScalper/SessionTime.mqh>
#include <BTCScalper/Indicators.mqh>
#include <BTCScalper/RiskManager.mqh>

//--- Daily MR trade count tracking
int BTCScalperMRDailyCount()
{
   string key = BTCScalperDayKey("mrCount");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

void BTCScalperMRMarkTradePlaced()
{
   string key = BTCScalperDayKey("mrCount");
   int current = BTCScalperMRDailyCount();
   GlobalVariableSet(key, (double)(current + 1));
}

//--- Signal Generator (runs on completed M15 bar, shift=1)
int BTCScalperMRSignal(
   const string symbol,
   const int rsiOverbought,
   const int rsiOversold,
   const int sessionStartHour,
   const int sessionEndHour
)
{
   //--- 1. Session Filter
   if(!BTCScalperInHourRange(sessionStartHour, sessionEndHour))
   {
      return 0;
   }

   //--- 2. Get BB values (shift = 1)
   double bbUpper = BTCScalperGetBufferValue(g_btcBbHandle, 1, 1);  // Upper
   double bbLower = BTCScalperGetBufferValue(g_btcBbHandle, 2, 1);  // Lower
   double bbMiddle = BTCScalperGetBufferValue(g_btcBbHandle, 0, 1); // Middle
   if(bbUpper == EMPTY_VALUE || bbLower == EMPTY_VALUE || bbMiddle == EMPTY_VALUE)
   {
      return 0;
   }

   //--- 3. Get RSI value (shift = 1)
   double rsi = BTCScalperGetBufferValue(g_btcRsiHandle, 0, 1);
   if(rsi == EMPTY_VALUE)
   {
      return 0;
   }

   //--- 4. Get M15 Close, Open, Low, High (shift = 1)
   double m15Close = iClose(symbol, PERIOD_M15, 1);
   double m15Open  = iOpen(symbol, PERIOD_M15, 1);
   double m15Low   = iLow(symbol, PERIOD_M15, 1);
   double m15High  = iHigh(symbol, PERIOD_M15, 1);

   //--- Evaluate Signals
   if(m15Low < bbLower && m15Close > m15Open && rsi < rsiOversold)
   {
      Print("[MR-Signal] BUY signal with confirmation on M15: Low=", DoubleToString(m15Low, 2),
            " Close=", DoubleToString(m15Close, 2), " LowerBB=", DoubleToString(bbLower, 2), " RSI=", DoubleToString(rsi, 2));
      return +1;
   }
   if(m15High > bbUpper && m15Close < m15Open && rsi > rsiOverbought)
   {
      Print("[MR-Signal] SELL signal with confirmation on M15: High=", DoubleToString(m15High, 2),
            " Close=", DoubleToString(m15Close, 2), " UpperBB=", DoubleToString(bbUpper, 2), " RSI=", DoubleToString(rsi, 2));
      return -1;
   }

   return 0;
}

//--- Entry execution
bool BTCScalperMREntry(
   const string symbol,
   const long magic,
   CTrade &trade,
   const int signal,
   const double slAtrMult,
   const double riskPct,
   const double minLot,
   const double maxLot,
   const int maxDailyTrades
)
{
   if(signal == 0)
      return false;

   // Check strategy daily trades limit
   int dailyCount = BTCScalperMRDailyCount();
   if(maxDailyTrades > 0 && dailyCount >= maxDailyTrades)
   {
      Print("[MR-Entry] Strategy daily limit reached: ", dailyCount, "/", maxDailyTrades);
      return false;
   }

   // Read ATR(14) on M15 (shift = 1)
   double atr = BTCScalperGetBufferValue(g_btcAtrHandle, 0, 1);
   if(atr == EMPTY_VALUE || atr <= 0.0)
   {
      Print("[MR-Entry] ATR is empty or <= 0");
      return false;
   }
   double slDistance = atr * slAtrMult;

   // Read Middle BB for TP (shift = 1)
   double bbMiddle = BTCScalperGetBufferValue(g_btcBbHandle, 0, 1);
   if(bbMiddle == EMPTY_VALUE)
   {
      Print("[MR-Entry] BB middle is empty");
      return false;
   }

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   trade.SetExpertMagicNumber(magic);

   // Calculate lots
   double lot = BTCScalperCalculateLot(symbol, SymbolInfoDouble(symbol, SYMBOL_ASK), 
                                       SymbolInfoDouble(symbol, SYMBOL_ASK) - slDistance, 
                                       riskPct, minLot, maxLot);
   if(lot <= 0.0)
   {
      Print("[MR-Entry] Calculated lot size is 0.0");
      return false;
   }

   bool ok = false;
   if(signal == +1)
   {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - slDistance, digits);
      double tp  = NormalizeDouble(bbMiddle, digits);

      if(tp <= ask)
      {
         Print("[MR-Entry] BUY TP <= ask, skipping. tp=", tp, " ask=", ask);
         return false;
      }

      ok = trade.Buy(lot, symbol, ask, sl, tp, "BTC_MR_BUY");
   }
   else if(signal == -1)
   {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + slDistance, digits);
      double tp  = NormalizeDouble(bbMiddle, digits);

      if(tp >= bid)
      {
         Print("[MR-Entry] SELL TP >= bid, skipping. tp=", tp, " bid=", bid);
         return false;
      }

      ok = trade.Sell(lot, symbol, bid, sl, tp, "BTC_MR_SELL");
   }

   if(ok)
   {
      BTCScalperMRMarkTradePlaced();
   }
   return ok;
}

//--- Trailing BE and TP management
void BTCScalperMRManage(
   const string symbol,
   const long magic,
   CTrade &trade,
   const bool trailBE,
   const double trailBETrigger
)
{
   // Read M15 Middle BB (shift 0) for live TP target
   double bbMiddle = BTCScalperGetBufferValue(g_btcBbHandle, 0, 0);
   if(bbMiddle == EMPTY_VALUE)
      return;

   // Read ATR(14) on M15 (shift 1) for BE trigger
   double atr = BTCScalperGetBufferValue(g_btcAtrHandle, 0, 1);
   bool hasAtr = (atr != EMPTY_VALUE && atr > 0.0);

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;

   trade.SetExpertMagicNumber(magic);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "BTC_MR_") < 0)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSl = PositionGetDouble(POSITION_SL);
      double currentTp = PositionGetDouble(POSITION_TP);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

      double newTp = NormalizeDouble(bbMiddle, digits);
      double newSl = currentSl;
      bool modify = false;

      // 1. Update TP
      if(MathAbs(newTp - currentTp) > point * 2.0)
      {
         if((type == POSITION_TYPE_BUY && newTp > openPrice) ||
            (type == POSITION_TYPE_SELL && newTp < openPrice))
         {
            currentTp = newTp;
            modify = true;
         }
      }

      // 2. Trailing Breakeven
      if(trailBE && hasAtr)
      {
         double triggerDist = atr * trailBETrigger;
         if(type == POSITION_TYPE_BUY)
         {
            if(currentPrice - openPrice >= triggerDist)
            {
               double beSl = NormalizeDouble(openPrice + spread + point, digits);
               if(currentSl < beSl || currentSl == 0.0)
               {
                  newSl = beSl;
                  modify = true;
               }
            }
         }
         else if(type == POSITION_TYPE_SELL)
         {
            if(openPrice - currentPrice >= triggerDist)
            {
               double beSl = NormalizeDouble(openPrice - spread - point, digits);
               if(currentSl > beSl || currentSl == 0.0)
               {
                  newSl = beSl;
                  modify = true;
               }
            }
         }
      }

      if(modify)
      {
         trade.PositionModify(ticket, newSl, currentTp);
      }
   }
}

#endif
