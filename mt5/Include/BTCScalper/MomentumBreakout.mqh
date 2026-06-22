#ifndef BTCSCALPER_MOMENTUM_BREAKOUT_MQH
#define BTCSCALPER_MOMENTUM_BREAKOUT_MQH

//+------------------------------------------------------------------+
//| MomentumBreakout.mqh — EMA cross + VWAP momentum on M15          |
//| Part of BTCScalper EA                                            |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
#include <BTCScalper/SessionTime.mqh>
#include <BTCScalper/Indicators.mqh>
#include <BTCScalper/RiskManager.mqh>

//--- Daily Momentum trade count tracking
int BTCScalperMomDailyCount()
{
   string key = BTCScalperDayKey("momCount");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

void BTCScalperMomMarkTradePlaced()
{
   string key = BTCScalperDayKey("momCount");
   int current = BTCScalperMomDailyCount();
   GlobalVariableSet(key, (double)(current + 1));
}

//--- Signal Generator (runs on completed M15 bar, shift=1)
int BTCScalperMomSignal(
   const string symbol,
   const int rsiLow,
   const int rsiHigh,
   const int tradingEndHour
)
{
   //--- 1. Session Filter
   if(!BTCScalperIsTradingHours(tradingEndHour))
   {
      return 0;
   }

   //--- 2. Get EMA values (shift = 1)
   double emaFast = BTCScalperGetBufferValue(g_btcEmaFast, 0, 1);
   double emaSlow = BTCScalperGetBufferValue(g_btcEmaSlow, 0, 1);
   double ema50   = BTCScalperGetBufferValue(g_btcEma50, 0, 1);
   if(emaFast == EMPTY_VALUE || emaSlow == EMPTY_VALUE || ema50 == EMPTY_VALUE)
   {
      return 0;
   }

   //--- 3. Get VWAP Value
   double vwap = BTCScalperVwapValue();
   if(vwap <= 0.0)
   {
      return 0;
   }

   //--- 4. Get RSI M15 (shift = 1)
   double rsi = BTCScalperGetBufferValue(g_btcRsiHandle, 0, 1);
   if(rsi == EMPTY_VALUE)
   {
      return 0;
   }

   //--- 5. Get M15 Close (shift = 1)
   double m15Close = iClose(symbol, PERIOD_M15, 1);

   //--- 6. Get H1 Trend Alignment (shift = 1)
   double h1Close = iClose(symbol, PERIOD_H1, 1);
   double h1Ema   = BTCScalperGetBufferValue(g_btcH1EmaHandle, 0, 1);
   bool h1Up = (h1Ema != EMPTY_VALUE && h1Close > h1Ema);
   bool h1Down = (h1Ema != EMPTY_VALUE && h1Close < h1Ema);

   //--- Evaluate Signals
   if(emaFast > emaSlow && m15Close > ema50 && m15Close > vwap && rsi >= rsiLow && h1Up)
   {
      Print("[Mom-Signal] BUY signal on M15: Close=", DoubleToString(m15Close, 2),
            " EMA9=", DoubleToString(emaFast, 2), " EMA21=", DoubleToString(emaSlow, 2), 
            " EMA50=", DoubleToString(ema50, 2), " VWAP=", DoubleToString(vwap, 2), " RSI=", DoubleToString(rsi, 2), " H1Up=1");
      return +1;
   }
   if(emaFast < emaSlow && m15Close < ema50 && m15Close < vwap && rsi <= rsiHigh && h1Down)
   {
      Print("[Mom-Signal] SELL signal on M15: Close=", DoubleToString(m15Close, 2),
            " EMA9=", DoubleToString(emaFast, 2), " EMA21=", DoubleToString(emaSlow, 2), 
            " EMA50=", DoubleToString(ema50, 2), " VWAP=", DoubleToString(vwap, 2), " RSI=", DoubleToString(rsi, 2), " H1Down=1");
      return -1;
   }

   return 0;
}

//--- Entry execution
bool BTCScalperMomEntry(
   const string symbol,
   const long magic,
   CTrade &trade,
   const int signal,
   const double slAtrMult,
   const double rewardRiskRatio,
   const double riskPct,
   const double minLot,
   const double maxLot,
   const int maxDailyTrades
)
{
   if(signal == 0)
      return false;

   // Check daily limit
   int dailyCount = BTCScalperMomDailyCount();
   if(maxDailyTrades > 0 && dailyCount >= maxDailyTrades)
   {
      Print("[Mom-Entry] Strategy daily limit reached: ", dailyCount, "/", maxDailyTrades);
      return false;
   }

   // Read ATR(14) on M15 (shift = 1) for baseline SL distance
   double atr = BTCScalperGetBufferValue(g_btcAtrHandle, 0, 1);
   if(atr == EMPTY_VALUE || atr <= 0.0)
   {
      Print("[Mom-Entry] ATR is empty or <= 0");
      return false;
   }
   double baseSl = atr * slAtrMult;

   // Find recent swing high/low of last 5 M15 bars (shift 1 to 5)
   double slDistance = baseSl;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

   if(signal == +1)
   {
      int lowestIdx = iLowest(symbol, PERIOD_M15, MODE_LOW, 5, 1);
      if(lowestIdx >= 0)
      {
         double swingLow = iLow(symbol, PERIOD_M15, lowestIdx);
         double swingDist = ask - swingLow;
         if(swingDist > 0.0)
         {
            slDistance = MathMin(swingDist, baseSl);
         }
      }
   }
   else if(signal == -1)
   {
      int highestIdx = iHighest(symbol, PERIOD_M15, MODE_HIGH, 5, 1);
      if(highestIdx >= 0)
      {
         double swingHigh = iHigh(symbol, PERIOD_M15, highestIdx);
         double swingDist = swingHigh - bid;
         if(swingDist > 0.0)
         {
            slDistance = MathMin(swingDist, baseSl);
         }
      }
   }

   // Floor SL distance at 1.5 * ATR to prevent extremely tight stops
   if(slDistance < atr * 1.5)
      slDistance = atr * 1.5;

   trade.SetExpertMagicNumber(magic);

   // Calculate lots
   double lot = BTCScalperCalculateLot(symbol, ask, ask - slDistance, riskPct, minLot, maxLot);
   if(lot <= 0.0)
   {
      Print("[Mom-Entry] Calculated lot size is 0.0");
      return false;
   }

   bool ok = false;
   if(signal == +1)
   {
      double sl = NormalizeDouble(ask - slDistance, digits);
      double tp = NormalizeDouble(ask + (slDistance * rewardRiskRatio), digits);

      Print("[Mom-Entry] BUY attempt: ask=", ask, " sl=", sl, " tp=", tp, " lot=", lot);
      ok = trade.Buy(lot, symbol, ask, sl, tp, "BTC_Mom_BUY");
   }
   else if(signal == -1)
   {
      double sl = NormalizeDouble(bid + slDistance, digits);
      double tp = NormalizeDouble(bid - (slDistance * rewardRiskRatio), digits);

      Print("[Mom-Entry] SELL attempt: bid=", bid, " sl=", sl, " tp=", tp, " lot=", lot);
      ok = trade.Sell(lot, symbol, bid, sl, tp, "BTC_Mom_SELL");
   }

   if(ok)
   {
      BTCScalperMomMarkTradePlaced();
   }
   return ok;
}

//--- Trailing stop management
void BTCScalperMomManage(
   const string symbol,
   const long magic,
   CTrade &trade
)
{
   // Read ATR(14) on M15 (shift 1) for trailing distance
   double atr = BTCScalperGetBufferValue(g_btcAtrHandle, 0, 1);
   if(atr == EMPTY_VALUE || atr <= 0.0)
      return;

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
      if(StringFind(comment, "BTC_Mom_") < 0)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSl = PositionGetDouble(POSITION_SL);
      double currentTp = PositionGetDouble(POSITION_TP);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);

      double originalSlDist = MathAbs(openPrice - currentSl);
      // If no SL was set originally, default to 2 * ATR
      if(currentSl == 0.0)
         originalSlDist = atr * 2.0;

      double newSl = currentSl;
      bool modify = false;

      if(type == POSITION_TYPE_BUY)
      {
         // 1. Move SL to BE at 1x R (profit >= originalSlDist)
         if(currentPrice - openPrice >= originalSlDist)
         {
            double beSl = NormalizeDouble(openPrice + spread + point, digits);
            if(currentSl < beSl || currentSl == 0.0)
            {
               newSl = beSl;
               modify = true;
            }
         }
         // 2. Trail SL at 1.5x ATR once price moves further
         if(newSl >= openPrice) // already at or above BE
         {
            double trailSl = NormalizeDouble(currentPrice - (atr * 1.5), digits);
            if(trailSl > newSl)
            {
               newSl = trailSl;
               modify = true;
            }
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         // 1. Move SL to BE at 1x R (profit >= originalSlDist)
         if(openPrice - currentPrice >= originalSlDist)
         {
            double beSl = NormalizeDouble(openPrice - spread - point, digits);
            if(currentSl > beSl || currentSl == 0.0)
            {
               newSl = beSl;
               modify = true;
            }
         }
         // 2. Trail SL at 1.5x ATR
         if(newSl <= openPrice && newSl != 0.0) // already at or below BE
         {
            double trailSl = NormalizeDouble(currentPrice + (atr * 1.5), digits);
            if(trailSl < newSl || newSl == 0.0)
            {
               newSl = trailSl;
               modify = true;
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
