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

bool BTCScalperMomDirectionAllowed(const int signal, const int directionMode)
{
   if(directionMode == 1 && signal < 0)
      return false;
   if(directionMode == 2 && signal > 0)
      return false;
   return true;
}

int BTCScalperMomDonchianSignal(
   const string symbol,
   const ENUM_TIMEFRAMES timeframe,
   const int lookback,
   const double bufferAtr)
{
   if(lookback <= 1)
      return 0;

   double close1 = iClose(symbol, timeframe, 1);
   double atr = BTCScalperGetBufferValue(g_btcMomAtrHandle, 0, 1);
   if(close1 <= 0.0 || atr == EMPTY_VALUE || atr <= 0.0)
      return 0;

   int highIdx = iHighest(symbol, timeframe, MODE_HIGH, lookback, 2);
   int lowIdx = iLowest(symbol, timeframe, MODE_LOW, lookback, 2);
   if(highIdx < 0 || lowIdx < 0)
      return 0;

   double priorHigh = iHigh(symbol, timeframe, highIdx);
   double priorLow = iLow(symbol, timeframe, lowIdx);
   double buffer = atr * MathMax(0.0, bufferAtr);

   if(close1 > priorHigh + buffer)
      return +1;
   if(close1 < priorLow - buffer)
      return -1;
   return 0;
}

//--- Signal Generator (runs on completed momentum-TF bar, shift=1)
int BTCScalperMomSignal(
   const string symbol,
   const int rsiLow,
   const int rsiHigh,
   const int tradingEndHour,
   const ENUM_TIMEFRAMES timeframe = PERIOD_M15,
   const int signalMode = 0,
   const int breakoutLookback = 20,
   const double breakoutBufferAtr = 0.10,
   const bool useVwapSideFilter = true,
   const bool useHtfTrendFilter = true,
   const ENUM_TIMEFRAMES htfTimeframe = PERIOD_H1,
   const bool useAdxFilter = false,
   const double adxMin = 20.0,
   const int directionMode = 0
)
{
   //--- 1. Session Filter
   if(!BTCScalperIsTradingHours(tradingEndHour))
   {
      return 0;
   }

   //--- 2. Get EMA values (shift = 1)
   double emaFast = BTCScalperGetBufferValue(g_btcMomEmaFast, 0, 1);
   double emaSlow = BTCScalperGetBufferValue(g_btcMomEmaSlow, 0, 1);
   double ema50   = BTCScalperGetBufferValue(g_btcMomEma50, 0, 1);
   if(emaFast == EMPTY_VALUE || emaSlow == EMPTY_VALUE || ema50 == EMPTY_VALUE)
   {
      return 0;
   }

   //--- 3. Get VWAP Value when the legacy side filter is active
   double vwap = BTCScalperVwapValue();
   if(useVwapSideFilter && vwap <= 0.0)
   {
      return 0;
   }

   //--- 4. Get RSI on the momentum timeframe (shift = 1)
   double rsi = BTCScalperGetBufferValue(g_btcMomRsiHandle, 0, 1);
   if(rsi == EMPTY_VALUE)
   {
      return 0;
   }

   //--- 5. Get momentum-TF Close (shift = 1)
   double momClose = iClose(symbol, timeframe, 1);
   if(momClose <= 0.0)
      return 0;

   //--- 6. Get higher-timeframe trend alignment (shift = 1)
   double htfClose = iClose(symbol, htfTimeframe, 1);
   double htfEma = BTCScalperGetBufferValue(g_btcMomHtfEmaHandle, 0, 1);
   bool htfUp = (!useHtfTrendFilter || (htfEma != EMPTY_VALUE && htfClose > htfEma));
   bool htfDown = (!useHtfTrendFilter || (htfEma != EMPTY_VALUE && htfClose < htfEma));

   if(useAdxFilter)
   {
      double adx = BTCScalperGetBufferValue(g_btcMomAdxHandle, 0, 1);
      if(adx == EMPTY_VALUE || adx < adxMin)
         return 0;
   }

   int rawSignal = 0;
   if(signalMode == 1)
   {
      rawSignal = BTCScalperMomDonchianSignal(symbol, timeframe, breakoutLookback, breakoutBufferAtr);
   }
   else
   {
      bool vwapLongOk = (!useVwapSideFilter || momClose > vwap);
      bool vwapShortOk = (!useVwapSideFilter || momClose < vwap);
      if(emaFast > emaSlow && momClose > ema50 && vwapLongOk)
         rawSignal = +1;
      else if(emaFast < emaSlow && momClose < ema50 && vwapShortOk)
         rawSignal = -1;
   }

   if(rawSignal == 0 || !BTCScalperMomDirectionAllowed(rawSignal, directionMode))
      return 0;

   //--- Evaluate Signals
   if(rawSignal > 0 && rsi >= rsiLow && htfUp)
   {
      Print("[Mom-Signal] BUY signal: TF=", EnumToString(timeframe), " Close=", DoubleToString(momClose, 2),
            " EMA9=", DoubleToString(emaFast, 2), " EMA21=", DoubleToString(emaSlow, 2), 
            " EMA50=", DoubleToString(ema50, 2), " RSI=", DoubleToString(rsi, 2), " HTFUp=1");
      return +1;
   }
   if(rawSignal < 0 && rsi <= rsiHigh && htfDown)
   {
      Print("[Mom-Signal] SELL signal: TF=", EnumToString(timeframe), " Close=", DoubleToString(momClose, 2),
            " EMA9=", DoubleToString(emaFast, 2), " EMA21=", DoubleToString(emaSlow, 2), 
            " EMA50=", DoubleToString(ema50, 2), " RSI=", DoubleToString(rsi, 2), " HTFDown=1");
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
   const int maxDailyTrades,
   const ENUM_TIMEFRAMES timeframe = PERIOD_M15,
   const int slMode = 0,
   const int swingLookback = 5,
   const double slMinAtrMult = 1.5,
   const double slMaxAtrMult = 2.0
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

   // Read ATR(14) on the momentum timeframe (shift = 1) for baseline SL distance
   double atr = BTCScalperGetBufferValue(g_btcMomAtrHandle, 0, 1);
   if(atr == EMPTY_VALUE || atr <= 0.0)
   {
      Print("[Mom-Entry] ATR is empty or <= 0");
      return false;
   }
   double baseSl = atr * slAtrMult;

   // Find recent swing high/low of recent momentum-TF bars
   double slDistance = baseSl;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

   if(signal == +1)
   {
      int lowestIdx = iLowest(symbol, timeframe, MODE_LOW, swingLookback, 1);
      if(lowestIdx >= 0)
      {
         double swingLow = iLow(symbol, timeframe, lowestIdx);
         double swingDist = ask - swingLow;
         if(swingDist > 0.0)
         {
            if(slMode == 1)
               slDistance = MathMax(swingDist, atr * slMinAtrMult);
            else
               slDistance = MathMin(swingDist, baseSl);
         }
      }
   }
   else if(signal == -1)
   {
      int highestIdx = iHighest(symbol, timeframe, MODE_HIGH, swingLookback, 1);
      if(highestIdx >= 0)
      {
         double swingHigh = iHigh(symbol, timeframe, highestIdx);
         double swingDist = swingHigh - bid;
         if(swingDist > 0.0)
         {
            if(slMode == 1)
               slDistance = MathMax(swingDist, atr * slMinAtrMult);
            else
               slDistance = MathMin(swingDist, baseSl);
         }
      }
   }

   // Floor SL distance to prevent extremely tight stops
   if(slDistance < atr * slMinAtrMult)
      slDistance = atr * slMinAtrMult;
   if(slMode == 1 && slMaxAtrMult > 0.0 && slDistance > atr * slMaxAtrMult)
      slDistance = atr * slMaxAtrMult;

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
   CTrade &trade,
   const ENUM_TIMEFRAMES timeframe = PERIOD_M15,
   const double beTriggerR = 1.0,
   const double trailStartR = 1.0,
   const double trailAtrMult = 1.5,
   const int maxHoldBars = 0,
   const double timeStopMinR = 0.0
)
{
   // Read ATR(14) on the momentum timeframe (shift 1) for trailing distance
   double atr = BTCScalperGetBufferValue(g_btcMomAtrHandle, 0, 1);
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
      double currentR = 0.0;

      if(type == POSITION_TYPE_BUY)
      {
         currentR = (originalSlDist > 0.0) ? (currentPrice - openPrice) / originalSlDist : 0.0;
         // 1. Move SL to BE at 1x R (profit >= originalSlDist)
         if(currentR >= beTriggerR)
         {
            double beSl = NormalizeDouble(openPrice + spread + point, digits);
            if(currentSl < beSl || currentSl == 0.0)
            {
               newSl = beSl;
               modify = true;
            }
         }
         // 2. Trail SL after configured R threshold
         if(currentR >= trailStartR && newSl >= openPrice)
         {
            double trailSl = NormalizeDouble(currentPrice - (atr * trailAtrMult), digits);
            if(trailSl > newSl)
            {
               newSl = trailSl;
               modify = true;
            }
         }
      }
      else if(type == POSITION_TYPE_SELL)
      {
         currentR = (originalSlDist > 0.0) ? (openPrice - currentPrice) / originalSlDist : 0.0;
         // 1. Move SL to BE at 1x R (profit >= originalSlDist)
         if(currentR >= beTriggerR)
         {
            double beSl = NormalizeDouble(openPrice - spread - point, digits);
            if(currentSl > beSl || currentSl == 0.0)
            {
               newSl = beSl;
               modify = true;
            }
         }
         // 2. Trail SL after configured R threshold
         if(currentR >= trailStartR && newSl <= openPrice && newSl != 0.0)
         {
            double trailSl = NormalizeDouble(currentPrice + (atr * trailAtrMult), digits);
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

      if(maxHoldBars > 0)
      {
         datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
         int seconds = PeriodSeconds(timeframe);
         if(seconds > 0 && openTime > 0)
         {
            int barsHeld = (int)((TimeCurrent() - openTime) / seconds);
            if(barsHeld >= maxHoldBars && currentR < timeStopMinR)
               trade.PositionClose(ticket);
         }
      }
   }
}

#endif
