#ifndef BTCSCALPER_VWAP_REVERSION_MQH
#define BTCSCALPER_VWAP_REVERSION_MQH

//+------------------------------------------------------------------+
//| VwapReversion.mqh — VWAP Z-score reversion on M5                 |
//| Part of BTCScalper EA                                            |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
#include <BTCScalper/SessionTime.mqh>
#include <BTCScalper/Indicators.mqh>
#include <BTCScalper/RiskManager.mqh>

//--- Daily VWAP trade count tracking
int BTCScalperVwapDailyCount()
{
   string key = BTCScalperDayKey("vwapCount");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

void BTCScalperVwapMarkTradePlaced()
{
   string key = BTCScalperDayKey("vwapCount");
   int current = BTCScalperVwapDailyCount();
   GlobalVariableSet(key, (double)(current + 1));
}

//--- Signal Generator (runs on completed M5 bar, shift=1)
int BTCScalperVwapSignal(
   const string symbol,
   const double zscoreEntry,
   const int tradingEndHour
)
{
   //--- 1. Session Filter (trading hours check)
   if(!BTCScalperIsTradingHours(tradingEndHour))
   {
      return 0;
   }

   //--- 2. Get VWAP Z-score (which is updated live or at completed M5 bar)
   // Z-score is calculated from M5 close of completed bar or current.
   // To be consistent with completed bar (shift 1), let's ensure we read the zscore computed for shift 1.
   // Wait, the Z-score calculation in BTCScalperVwapUpdate computes Z-score using rates[copied - 1].close.
   // If it is called on each new tick or new bar, the last element rate is the current forming bar (shift 0).
   // If we want the Z-score at shift 1 (completed bar), we should calculate it using rates[copied-2].close
   // or we can compute it on rates[copied-2].close.
   // Let's modify BTCScalperVwapUpdate or compute Z-score for a specific shift.
   // Wait, let's look at the VWAP Z-score calculation in Indicators.mqh:
   // Z-score = (close - VWAP) / stddev
   // We can compute the Z-score for shift 1 directly in this function using the current VWAP and current stddev:
   double vwap = BTCScalperVwapValue();
   // Wait, stddev can be calculated or we can just read the live Z-score.
   // Since the signal runs on completed bar (shift = 1), let's check:
   double m5Close = iClose(symbol, PERIOD_M5, 1);
   // Let's calculate standard deviation and zscore for shift 1:
   // Wait, in Indicators.mqh, s_vwap and s_stddev are computed using all M5 bars of the day.
   // So s_vwap and s_stddev at shift 1 (which was the end of previous bar) are very close to s_vwap and s_stddev.
   // Let's use the live s_vwap and s_stddev to get Z-score at shift 1:
   double zscoreShift1 = 0.0;
   if(s_stddev > 0.0)
      zscoreShift1 = (m5Close - s_vwap) / s_stddev;

   //--- 3. Get M5 RSI (shift = 1) from g_btcRsiM5Handle
   double rsi = BTCScalperGetBufferValue(g_btcRsiM5Handle, 0, 1);
   if(rsi == EMPTY_VALUE)
   {
      return 0;
   }

   //--- 4. Get H1 Trend Alignment (shift = 1)
   double h1Close = iClose(symbol, PERIOD_H1, 1);
   double h1Ema   = BTCScalperGetBufferValue(g_btcH1EmaHandle, 0, 1);
   bool h1Up = (h1Ema != EMPTY_VALUE && h1Close > h1Ema);
   bool h1Down = (h1Ema != EMPTY_VALUE && h1Close < h1Ema);

   //--- Evaluate Signals
   if(zscoreShift1 < -zscoreEntry && rsi < 35.0 && h1Up)
   {
      Print("[VWAP-Signal] BUY signal on M5 (Trend Aligned): Close=", DoubleToString(m5Close, 2),
            " VWAP=", DoubleToString(s_vwap, 2), " Z-score=", DoubleToString(zscoreShift1, 2), " RSI=", DoubleToString(rsi, 2), " H1Up=1");
      return +1;
   }
   if(zscoreShift1 > zscoreEntry && rsi > 65.0 && h1Down)
   {
      Print("[VWAP-Signal] SELL signal on M5 (Trend Aligned): Close=", DoubleToString(m5Close, 2),
            " VWAP=", DoubleToString(s_vwap, 2), " Z-score=", DoubleToString(zscoreShift1, 2), " RSI=", DoubleToString(rsi, 2), " H1Down=1");
      return -1;
   }

   return 0;
}

//--- Entry execution
bool BTCScalperVwapEntry(
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

   // Check daily limit
   int dailyCount = BTCScalperVwapDailyCount();
   if(maxDailyTrades > 0 && dailyCount >= maxDailyTrades)
   {
      Print("[VWAP-Entry] Strategy daily limit reached: ", dailyCount, "/", maxDailyTrades);
      return false;
   }

   // Read ATR(14) on M5 (shift = 1)
   double atr = BTCScalperGetBufferValue(g_btcAtrM5Handle, 0, 1);
   if(atr == EMPTY_VALUE || atr <= 0.0)
   {
      Print("[VWAP-Entry] ATR M5 is empty or <= 0");
      return false;
   }
   double slDistance = atr * slAtrMult;

   // Read current VWAP value
   double vwap = BTCScalperVwapValue();
   if(vwap <= 0.0)
   {
      Print("[VWAP-Entry] VWAP value is empty or 0");
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
      Print("[VWAP-Entry] Calculated lot size is 0.0");
      return false;
   }

   bool ok = false;
   if(signal == +1)
   {
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double sl  = NormalizeDouble(ask - slDistance, digits);
      double tp  = NormalizeDouble(vwap, digits);

      if(tp <= ask)
      {
         Print("[VWAP-Entry] BUY TP <= ask, skipping. tp=", tp, " ask=", ask);
         return false;
      }

      ok = trade.Buy(lot, symbol, ask, sl, tp, "BTC_VWAP_BUY");
   }
   else if(signal == -1)
   {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double sl  = NormalizeDouble(bid + slDistance, digits);
      double tp  = NormalizeDouble(vwap, digits);

      if(tp >= bid)
      {
         Print("[VWAP-Entry] SELL TP >= bid, skipping. tp=", tp, " bid=", bid);
         return false;
      }

      ok = trade.Sell(lot, symbol, bid, sl, tp, "BTC_VWAP_SELL");
   }

   if(ok)
   {
      BTCScalperVwapMarkTradePlaced();
   }
   return ok;
}

//--- Manage active VWAP reversion positions
void BTCScalperVwapManage(
   const string symbol,
   const long magic,
   CTrade &trade,
   const int maxHoldBars
)
{
   double vwap = BTCScalperVwapValue();
   if(vwap <= 0.0)
      return;

   // Read ATR(14) on M5 (shift 1) for BE trigger
   double atr = BTCScalperGetBufferValue(g_btcAtrM5Handle, 0, 1);
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
      if(StringFind(comment, "BTC_VWAP_") < 0)
         continue;

      // 1. Time-in-trade exit check
      if(maxHoldBars > 0)
      {
         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         if(TimeCurrent() - openTime >= maxHoldBars * 300) // 5 minutes per bar
         {
            Print("[VWAP-Manage] Max hold time reached (", maxHoldBars, " bars). Closing position ticket=", ticket);
            trade.PositionClose(ticket);
            continue;
         }
      }

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSl = PositionGetDouble(POSITION_SL);
      double currentTp = PositionGetDouble(POSITION_TP);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

      double newTp = NormalizeDouble(vwap, digits);
      double newSl = currentSl;
      bool modify = false;

      // 2. Update TP to live VWAP
      if(MathAbs(newTp - currentTp) > point * 2.0)
      {
         if((type == POSITION_TYPE_BUY && newTp > openPrice) ||
            (type == POSITION_TYPE_SELL && newTp < openPrice))
         {
            currentTp = newTp;
            modify = true;
         }
      }

      // 3. Trailing Breakeven at 1.0 * ATR
      if(hasAtr)
      {
         double triggerDist = atr * 1.0;
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
