#ifndef GOLDSCALPER_MEAN_REVERSION_MQH
#define GOLDSCALPER_MEAN_REVERSION_MQH

//+------------------------------------------------------------------+
//| MeanReversion.mqh — Bollinger Band + RSI mean reversion scalping  |
//| Part of GoldScalper EA                                            |
//|                                                                    |
//| Entry Logic (M5):                                                  |
//|   BUY  — close < lower BB  AND  RSI(14) < oversold (30)           |
//|   SELL — close > upper BB  AND  RSI(14) > overbought (70)         |
//|                                                                    |
//| Trend Filter (M15):                                                |
//|   BUY  only if M15 close > EMA(50) on M15                         |
//|   SELL only if M15 close < EMA(50) on M15                         |
//|                                                                    |
//| Take Profit:  middle Bollinger Band (20 SMA) on M5                 |
//| Stop Loss:    InpMrSlAtr × ATR(14) on M5 from entry               |
//| Session:      NY overlap hours (default 12:00-16:00 server time)   |
//| Daily Limit:  capped via GlobalVariable                            |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
#include <GoldScalper/SessionTime.mqh>

//--- Static indicator handles (created once in Init, released in Deinit)
static int s_mrBbHandle     = INVALID_HANDLE;
static int s_mrRsiHandle    = INVALID_HANDLE;
static int s_mrEmaHandle    = INVALID_HANDLE;
static int s_mrAtrHandle    = INVALID_HANDLE;
static int s_mrAdxHandle    = INVALID_HANDLE;

//--- Cached parameters used when creating handles
static string s_mrSymbol    = "";
static int    s_mrBbPeriod  = 0;
static double s_mrBbDev     = 0.0;
static int    s_mrRsiPeriod = 0;
static int    s_mrEmaPeriod = 0;

//+------------------------------------------------------------------+
//| Helper — read a single value from an indicator buffer              |
//+------------------------------------------------------------------+
double GoldScalperMRBufferValue(const int handle, const int buffer, const int shift)
{
   if(handle == INVALID_HANDLE)
      return EMPTY_VALUE;
   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1)
      return EMPTY_VALUE;
   return values[0];
}

//+------------------------------------------------------------------+
//| Initialize indicator handles                                       |
//+------------------------------------------------------------------+
void GoldScalperMeanReversionInit(const string symbol,
                                   const int bbPeriod,
                                   const double bbDev,
                                   const int rsiPeriod,
                                   const int trendEmaPeriod,
                                   const int adxPeriod = 14)
{
   // Cache parameters for later validation / re-creation
   s_mrSymbol    = symbol;
   s_mrBbPeriod  = bbPeriod;
   s_mrBbDev     = bbDev;
   s_mrRsiPeriod = rsiPeriod;
   s_mrEmaPeriod = trendEmaPeriod;

   // --- Bollinger Bands on M5 ---
   s_mrBbHandle = iBands(symbol, PERIOD_M5, bbPeriod, 0, bbDev, PRICE_CLOSE);
   if(s_mrBbHandle == INVALID_HANDLE)
      Print("[MR-Init] ERROR: iBands handle creation failed for ", symbol,
            " period=", bbPeriod, " dev=", bbDev);
   else
      Print("[MR-Init] BB handle created: ", s_mrBbHandle,
            " symbol=", symbol, " period=", bbPeriod, " dev=", bbDev);

   // --- RSI on M5 ---
   s_mrRsiHandle = iRSI(symbol, PERIOD_M5, rsiPeriod, PRICE_CLOSE);
   if(s_mrRsiHandle == INVALID_HANDLE)
      Print("[MR-Init] ERROR: iRSI handle creation failed for ", symbol,
            " period=", rsiPeriod);
   else
      Print("[MR-Init] RSI handle created: ", s_mrRsiHandle,
            " symbol=", symbol, " period=", rsiPeriod);

   // --- Trend EMA on M15 ---
   s_mrEmaHandle = iMA(symbol, PERIOD_M15, trendEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(s_mrEmaHandle == INVALID_HANDLE)
      Print("[MR-Init] ERROR: iMA (EMA) handle creation failed for ", symbol,
            " period=", trendEmaPeriod);
   else
      Print("[MR-Init] EMA handle created: ", s_mrEmaHandle,
            " symbol=", symbol, " period=", trendEmaPeriod);

   // --- ATR(14) on M5 for stop-loss sizing ---
   s_mrAtrHandle = iATR(symbol, PERIOD_M5, 14);
   if(s_mrAtrHandle == INVALID_HANDLE)
      Print("[MR-Init] ERROR: iATR handle creation failed for ", symbol);
   else
      Print("[MR-Init] ATR handle created: ", s_mrAtrHandle, " symbol=", symbol);

   // --- ADX on M5 for regime filtering ---
   s_mrAdxHandle = iADX(symbol, PERIOD_M5, adxPeriod);
   if(s_mrAdxHandle == INVALID_HANDLE)
      Print("[MR-Init] ERROR: iADX handle creation failed for ", symbol,
            " period=", adxPeriod);
   else
      Print("[MR-Init] ADX handle created: ", s_mrAdxHandle,
            " symbol=", symbol, " period=", adxPeriod);

   Print("[MR-Init] Mean Reversion module initialised for ", symbol);
}

//+------------------------------------------------------------------+
//| Release indicator handles                                          |
//+------------------------------------------------------------------+
void GoldScalperMeanReversionDeinit()
{
   if(s_mrBbHandle != INVALID_HANDLE)
   {
      IndicatorRelease(s_mrBbHandle);
      Print("[MR-Deinit] BB handle released: ", s_mrBbHandle);
      s_mrBbHandle = INVALID_HANDLE;
   }
   if(s_mrRsiHandle != INVALID_HANDLE)
   {
      IndicatorRelease(s_mrRsiHandle);
      Print("[MR-Deinit] RSI handle released: ", s_mrRsiHandle);
      s_mrRsiHandle = INVALID_HANDLE;
   }
   if(s_mrEmaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(s_mrEmaHandle);
      Print("[MR-Deinit] EMA handle released: ", s_mrEmaHandle);
      s_mrEmaHandle = INVALID_HANDLE;
   }
   if(s_mrAtrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(s_mrAtrHandle);
      Print("[MR-Deinit] ATR handle released: ", s_mrAtrHandle);
      s_mrAtrHandle = INVALID_HANDLE;
   }
   if(s_mrAdxHandle != INVALID_HANDLE)
   {
      IndicatorRelease(s_mrAdxHandle);
      Print("[MR-Deinit] ADX handle released: ", s_mrAdxHandle);
      s_mrAdxHandle = INVALID_HANDLE;
   }
   Print("[MR-Deinit] Mean Reversion module de-initialised");
}

//+------------------------------------------------------------------+
//| Return number of MR trades placed today via GlobalVariable         |
//+------------------------------------------------------------------+
int GoldScalperMeanReversionDailyCount()
{
   string key = GoldScalperDayKey("mrCount");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

//+------------------------------------------------------------------+
//| Increment the daily MR trade counter                               |
//+------------------------------------------------------------------+
void GoldScalperMRMarkTradePlaced()
{
   string key = GoldScalperDayKey("mrCount");
   int current = GoldScalperMeanReversionDailyCount();
   GlobalVariableSet(key, (double)(current + 1));
   Print("[MR-Count] Daily MR trade count incremented to ", current + 1);
}

//+------------------------------------------------------------------+
//| Signal generator                                                   |
//| Returns: +1 BUY, -1 SELL, 0 no signal                             |
//| Checks: BB crossover, RSI extremes, M15 trend filter, session     |
//+------------------------------------------------------------------+
int GoldScalperMeanReversionSignal(const string symbol,
                                    const int bbPeriod,
                                    const double bbDev,
                                    const int rsiPeriod,
                                    const int rsiOverbought,
                                    const int rsiOversold,
                                    const int trendEmaPeriod,
                                    const int overlapStartHour,
                                    const int overlapEndHour,
                                    const double adxMax = 0.0,
                                    const double bbMinWidth = 0.0)
{
   //--- 1. Session filter: only trade during NY overlap
   if(!GoldScalperInHourRange(overlapStartHour, overlapEndHour))
   {
      Print("[MR-Signal] Outside session window (",
            overlapStartHour, ":00-", overlapEndHour, ":00). No signal.");
      return 0;
   }

   //--- 2. ADX regime filter: skip when market is trending
   if(adxMax > 0.0 && s_mrAdxHandle != INVALID_HANDLE)
   {
      double adxValue = GoldScalperMRBufferValue(s_mrAdxHandle, 0, 1); // ADX main line
      if(adxValue == EMPTY_VALUE)
      {
         Print("[MR-Signal] ERROR: ADX value unavailable");
         return 0;
      }
      if(adxValue >= adxMax)
      {
         Print("[MR-Signal] ADX=", DoubleToString(adxValue, 2),
               " >= ", DoubleToString(adxMax, 2), " — trending, skip MR signal.");
         return 0;
      }
      Print("[MR-Signal] ADX=", DoubleToString(adxValue, 2),
            " < ", DoubleToString(adxMax, 2), " — range-bound, OK.");
   }

   //--- 3. Read M5 close price (last completed bar = shift 1)
   MqlRates m5[];
   ArraySetAsSeries(m5, true);
   if(CopyRates(symbol, PERIOD_M5, 1, 2, m5) < 2)
   {
      Print("[MR-Signal] ERROR: Cannot copy M5 rates for ", symbol);
      return 0;
   }
   double m5Close = m5[0].close;

   //--- 4. Read Bollinger Bands (shift 1 = last completed M5 bar)
   double bbUpper = GoldScalperMRBufferValue(s_mrBbHandle, 1, 1);  // upper band
   double bbLower = GoldScalperMRBufferValue(s_mrBbHandle, 2, 1);  // lower band
   double bbMiddle = GoldScalperMRBufferValue(s_mrBbHandle, 0, 1); // middle band (SMA)
   if(bbUpper == EMPTY_VALUE || bbLower == EMPTY_VALUE || bbMiddle == EMPTY_VALUE)
   {
      Print("[MR-Signal] ERROR: BB indicator values unavailable");
      return 0;
   }

   //--- 4b. BB squeeze filter: skip when bandwidth is too narrow (imminent breakout)
   if(bbMinWidth > 0.0 && bbMiddle > 0.0)
   {
      double bbWidth = (bbUpper - bbLower) / bbMiddle * 100.0;
      if(bbWidth < bbMinWidth)
      {
         Print("[MR-Signal] BB squeeze detected. Width=", DoubleToString(bbWidth, 3),
               "% < min ", DoubleToString(bbMinWidth, 3), "%. Skip.");
         return 0;
      }
      Print("[MR-Signal] BB width=", DoubleToString(bbWidth, 3),
            "% >= min ", DoubleToString(bbMinWidth, 3), "% — OK.");
   }

   //--- 4. Read RSI (shift 1)
   double rsi = GoldScalperMRBufferValue(s_mrRsiHandle, 0, 1);
   if(rsi == EMPTY_VALUE)
   {
      Print("[MR-Signal] ERROR: RSI indicator value unavailable");
      return 0;
   }

   //--- 5. Read M15 close and EMA for trend filter
   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   if(CopyRates(symbol, PERIOD_M15, 1, 2, m15) < 2)
   {
      Print("[MR-Signal] ERROR: Cannot copy M15 rates for ", symbol);
      return 0;
   }
   double m15Close = m15[0].close;

   double emaValue = GoldScalperMRBufferValue(s_mrEmaHandle, 0, 1);
   if(emaValue == EMPTY_VALUE)
   {
      Print("[MR-Signal] ERROR: EMA(", trendEmaPeriod, ") indicator value unavailable on M15");
      return 0;
   }

   //--- 6. Evaluate BUY signal
   bool bbBuyCondition  = m5Close < bbLower;
   bool rsiBuyCondition = rsi < (double)rsiOversold;
   bool trendBuyFilter  = m15Close > emaValue;

   //--- 7. Evaluate SELL signal
   bool bbSellCondition  = m5Close > bbUpper;
   bool rsiSellCondition = rsi > (double)rsiOverbought;
   bool trendSellFilter  = m15Close < emaValue;

   Print("[MR-Signal] M5 close=", DoubleToString(m5Close, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " BBu=", DoubleToString(bbUpper, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " BBm=", DoubleToString(bbMiddle, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " BBl=", DoubleToString(bbLower, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " RSI=", DoubleToString(rsi, 2),
         " M15close=", DoubleToString(m15Close, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " EMA=", DoubleToString(emaValue, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)));

   if(bbBuyCondition && rsiBuyCondition && trendBuyFilter)
   {
      Print("[MR-Signal] BUY signal: M5 close below lower BB, RSI=",
            DoubleToString(rsi, 2), " < ", rsiOversold,
            ", M15 trend bullish (close > EMA)");
      return +1;
   }

   if(bbSellCondition && rsiSellCondition && trendSellFilter)
   {
      Print("[MR-Signal] SELL signal: M5 close above upper BB, RSI=",
            DoubleToString(rsi, 2), " > ", rsiOverbought,
            ", M15 trend bearish (close < EMA)");
      return -1;
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Equity-percentage position sizing (same approach as AsianBreakout) |
//+------------------------------------------------------------------+
double GoldScalperMRCalcLot(const string symbol,
                             const double riskPct,
                             const double slDistance,
                             const double minLot,
                             const double maxLot)
{
   if(slDistance <= 0.0)
      return 0.0;

   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * riskPct / 100.0;

   // tick_value = monetary value of 1 tick per 1 lot
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0)
      return 0.0;

   double rawLot = riskMoney / (slDistance / tickSize * tickValue);

   // Normalise to broker constraints
   double step      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double brokerMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double brokerMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      step = 0.01;

   double low     = MathMax(minLot, brokerMin);
   double high    = MathMin(maxLot, brokerMax);
   double clamped = MathMax(low, MathMin(rawLot, high));
   double lot     = NormalizeDouble(MathRound(clamped / step) * step, 2);

   Print("[MR-Lot] equity=", DoubleToString(equity, 2),
         " risk%=", DoubleToString(riskPct, 2),
         " riskMoney=", DoubleToString(riskMoney, 2),
         " slDist=", DoubleToString(slDistance, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " rawLot=", DoubleToString(rawLot, 4),
         " lot=", DoubleToString(lot, 2));
   return lot;
}

//+------------------------------------------------------------------+
//| Place market order with SL (ATR-based) and TP (middle BB)          |
//+------------------------------------------------------------------+
bool GoldScalperMeanReversionEntry(const string symbol,
                                    const long magic,
                                    CTrade &trade,
                                    const int signal,
                                    const int bbPeriod,
                                    const double bbDev,
                                    const double slAtrMultiple,
                                    const int rsiPeriod,
                                    const double riskPct,
                                    const double minLot,
                                    const double maxLot,
                                    const int maxTrades)
{
   if(signal == 0)
      return false;

   //--- 1. Check daily limit
   int dailyCount = GoldScalperMeanReversionDailyCount();
   if(maxTrades > 0 && dailyCount >= maxTrades)
   {
      Print("[MR-Entry] Daily MR trade limit reached: ", dailyCount, "/", maxTrades);
      return false;
   }

   //--- 2. Read ATR for stop loss
   double atr = GoldScalperMRBufferValue(s_mrAtrHandle, 0, 1);
   if(atr == EMPTY_VALUE || atr <= 0.0)
   {
      Print("[MR-Entry] ERROR: ATR value unavailable or zero");
      return false;
   }
   double slDistance = atr * slAtrMultiple;

   //--- 3. Read middle BB for take profit
   double bbMiddle = GoldScalperMRBufferValue(s_mrBbHandle, 0, 1);
   if(bbMiddle == EMPTY_VALUE)
   {
      Print("[MR-Entry] ERROR: BB middle value unavailable");
      return false;
   }

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   trade.SetExpertMagicNumber(magic);

   //--- 4. Calculate lot size
   double lot = GoldScalperMRCalcLot(symbol, riskPct, slDistance, minLot, maxLot);
   if(lot <= 0.0)
   {
      Print("[MR-Entry] ERROR: Calculated lot size is zero");
      return false;
   }

   bool ok = false;

   if(signal == +1)
   {
      double ask   = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double sl    = NormalizeDouble(ask - slDistance, digits);
      double tp    = NormalizeDouble(bbMiddle, digits);

      // Sanity: TP must be above entry for a BUY
      if(tp <= ask)
      {
         Print("[MR-Entry] BUY skipped: TP (", DoubleToString(tp, digits),
               ") <= entry (", DoubleToString(ask, digits), ")");
         return false;
      }

      Print("[MR-Entry] BUY attempt: ask=", DoubleToString(ask, digits),
            " sl=", DoubleToString(sl, digits),
            " tp=", DoubleToString(tp, digits),
            " lot=", DoubleToString(lot, 2),
            " ATR=", DoubleToString(atr, digits),
            " slMult=", DoubleToString(slAtrMultiple, 2));

      ok = trade.Buy(lot, symbol, ask, sl, tp, "GoldScalper_MR_BUY");
   }
   else if(signal == -1)
   {
      double bid   = SymbolInfoDouble(symbol, SYMBOL_BID);
      double sl    = NormalizeDouble(bid + slDistance, digits);
      double tp    = NormalizeDouble(bbMiddle, digits);

      // Sanity: TP must be below entry for a SELL
      if(tp >= bid)
      {
         Print("[MR-Entry] SELL skipped: TP (", DoubleToString(tp, digits),
               ") >= entry (", DoubleToString(bid, digits), ")");
         return false;
      }

      Print("[MR-Entry] SELL attempt: bid=", DoubleToString(bid, digits),
            " sl=", DoubleToString(sl, digits),
            " tp=", DoubleToString(tp, digits),
            " lot=", DoubleToString(lot, 2),
            " ATR=", DoubleToString(atr, digits),
            " slMult=", DoubleToString(slAtrMultiple, 2));

      ok = trade.Sell(lot, symbol, bid, sl, tp, "GoldScalper_MR_SELL");
   }

   if(ok)
   {
      ulong ticket = trade.ResultOrder();
      Print("[MR-Entry] Order placed successfully, ticket=", ticket);
      GoldScalperMRMarkTradePlaced();
   }
   else
   {
      Print("[MR-Entry] Order FAILED: retcode=", (int)trade.ResultRetcode(),
            " desc=", trade.ResultRetcodeDescription());
   }

   return ok;
}

//+------------------------------------------------------------------+
//| Manage existing MR positions — update TP to current middle BB      |
//| The middle BB moves as new bars form, so we keep the TP in sync.   |
//+------------------------------------------------------------------+
void GoldScalperMeanReversionManage(const string symbol,
                                     const long magic,
                                     CTrade &trade)
{
   // Read the current middle BB on M5 (shift 0 = current forming bar)
   double bbMiddle = GoldScalperMRBufferValue(s_mrBbHandle, 0, 0);
   if(bbMiddle == EMPTY_VALUE)
      return;

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
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

      // Only manage positions opened by this module (check comment prefix)
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "GoldScalper_MR_") < 0)
         continue;

      long   type      = PositionGetInteger(POSITION_TYPE);
      double currentTp = PositionGetDouble(POSITION_TP);
      double currentSl = PositionGetDouble(POSITION_SL);
      double newTp     = NormalizeDouble(bbMiddle, digits);

      // Only modify if TP has moved meaningfully (> 1 point)
      if(MathAbs(newTp - currentTp) < point * 2.0)
         continue;

      // Validate direction
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(type == POSITION_TYPE_BUY && newTp <= openPrice)
         continue;   // TP must be above entry for BUY
      if(type == POSITION_TYPE_SELL && newTp >= openPrice)
         continue;   // TP must be below entry for SELL

      if(trade.PositionModify(ticket, currentSl, newTp))
      {
         Print("[MR-Manage] TP updated for ticket=", ticket,
               " oldTP=", DoubleToString(currentTp, digits),
               " newTP=", DoubleToString(newTp, digits),
               " bbMiddle=", DoubleToString(bbMiddle, digits));
      }
      else
      {
         Print("[MR-Manage] TP modify FAILED for ticket=", ticket,
               " retcode=", (int)trade.ResultRetcode(),
               " desc=", trade.ResultRetcodeDescription());
      }
   }
}

#endif
