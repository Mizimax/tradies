#ifndef GOLDSCALPER_BREAKOUT_REGIME_FILTER_MQH
#define GOLDSCALPER_BREAKOUT_REGIME_FILTER_MQH

//+------------------------------------------------------------------+
//| BreakoutRegimeFilter.mqh                                         |
//| Optional quality gate for Asian Breakout order placement.         |
//+------------------------------------------------------------------+

enum ENUM_GS_BREAKOUT_DECISION
{
   GS_BREAKOUT_SKIP      = 0,
   GS_BREAKOUT_BOTH      = 1,
   GS_BREAKOUT_BUY_ONLY  = 2,
   GS_BREAKOUT_SELL_ONLY = 3
};

static int    s_breakoutD1EmaHandle = INVALID_HANDLE;
static int    s_breakoutH4EmaHandle = INVALID_HANDLE;
static int    s_breakoutM15AdxHandle = INVALID_HANDLE;
static int    s_breakoutD1AtrHandle = INVALID_HANDLE;
static string s_breakoutRegimeSymbol = "";

//+------------------------------------------------------------------+
//| Initialize indicator handles                                      |
//+------------------------------------------------------------------+
bool GoldScalperBreakoutRegimeInit(const string symbol,
                                   const int emaPeriod,
                                   const int adxPeriod)
{
   s_breakoutRegimeSymbol = symbol;

   s_breakoutD1EmaHandle = iMA(symbol, PERIOD_D1, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   s_breakoutH4EmaHandle = iMA(symbol, PERIOD_H4, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   s_breakoutM15AdxHandle = iADX(symbol, PERIOD_M15, adxPeriod);
   s_breakoutD1AtrHandle = iATR(symbol, PERIOD_D1, 14);

   bool ok = s_breakoutD1EmaHandle != INVALID_HANDLE
      && s_breakoutH4EmaHandle != INVALID_HANDLE
      && s_breakoutM15AdxHandle != INVALID_HANDLE
      && s_breakoutD1AtrHandle != INVALID_HANDLE;

   if(!ok)
   {
      Print("[BreakoutRegime] ERROR: indicator init failed",
         " D1EMA=", s_breakoutD1EmaHandle,
         " H4EMA=", s_breakoutH4EmaHandle,
         " M15ADX=", s_breakoutM15AdxHandle,
         " D1ATR=", s_breakoutD1AtrHandle);
      return false;
   }

   Print("[BreakoutRegime] Init complete for ", symbol,
      " emaPeriod=", emaPeriod,
      " adxPeriod=", adxPeriod);
   return true;
}

//+------------------------------------------------------------------+
//| Release indicator handles                                         |
//+------------------------------------------------------------------+
void GoldScalperBreakoutRegimeDeinit()
{
   if(s_breakoutD1EmaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(s_breakoutD1EmaHandle);
      s_breakoutD1EmaHandle = INVALID_HANDLE;
   }
   if(s_breakoutH4EmaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(s_breakoutH4EmaHandle);
      s_breakoutH4EmaHandle = INVALID_HANDLE;
   }
   if(s_breakoutM15AdxHandle != INVALID_HANDLE)
   {
      IndicatorRelease(s_breakoutM15AdxHandle);
      s_breakoutM15AdxHandle = INVALID_HANDLE;
   }
   if(s_breakoutD1AtrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(s_breakoutD1AtrHandle);
      s_breakoutD1AtrHandle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Helpers                                                           |
//+------------------------------------------------------------------+
double GoldScalperBreakoutBufferValue(const int handle, const int buffer, const int shift)
{
   if(handle == INVALID_HANDLE)
      return EMPTY_VALUE;

   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1)
      return EMPTY_VALUE;
   return values[0];
}

string GoldScalperBreakoutDecisionName(const ENUM_GS_BREAKOUT_DECISION decision)
{
   if(decision == GS_BREAKOUT_BUY_ONLY)
      return "buy_only";
   if(decision == GS_BREAKOUT_SELL_ONLY)
      return "sell_only";
   if(decision == GS_BREAKOUT_BOTH)
      return "both";
   return "skip";
}

int GoldScalperBreakoutTrendDirection(const string symbol,
                                      const ENUM_TIMEFRAMES timeframe,
                                      const int emaHandle)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, timeframe, 1, 1, rates) != 1)
      return 0;

   double ema = GoldScalperBreakoutBufferValue(emaHandle, 0, 1);
   if(ema == EMPTY_VALUE)
      return 0;

   if(rates[0].close > ema)
      return 1;
   if(rates[0].close < ema)
      return -1;
   return 0;
}

bool GoldScalperBreakoutAdxAllowed(const double adxMin,
                                   const double adxMax,
                                   double &adxValue,
                                   string &reason)
{
   adxValue = 0.0;
   if(adxMin <= 0.0 && adxMax <= 0.0)
      return true;

   adxValue = GoldScalperBreakoutBufferValue(s_breakoutM15AdxHandle, 0, 1);
   if(adxValue == EMPTY_VALUE)
   {
      reason = "adx_unavailable";
      return false;
   }

   if(adxMin > 0.0 && adxValue < adxMin)
   {
      reason = StringFormat("adx_low adx=%.2f min=%.2f", adxValue, adxMin);
      return false;
   }

   if(adxMax > 0.0 && adxValue > adxMax)
   {
      reason = StringFormat("adx_high adx=%.2f max=%.2f", adxValue, adxMax);
      return false;
   }

   return true;
}

bool GoldScalperBreakoutRangeAllowed(const double asianRange,
                                     const double rangeAtrMin,
                                     const double rangeAtrMax,
                                     double &rangeAtrRatio,
                                     string &reason)
{
   rangeAtrRatio = 0.0;
   if(rangeAtrMin <= 0.0 && rangeAtrMax <= 0.0)
      return true;

   double d1Atr = GoldScalperBreakoutBufferValue(s_breakoutD1AtrHandle, 0, 1);
   if(d1Atr == EMPTY_VALUE || d1Atr <= 0.0)
   {
      reason = "d1_atr_unavailable";
      return false;
   }

   rangeAtrRatio = asianRange / d1Atr;

   if(rangeAtrMin > 0.0 && rangeAtrRatio < rangeAtrMin)
   {
      reason = StringFormat("range_atr_low ratio=%.3f min=%.3f", rangeAtrRatio, rangeAtrMin);
      return false;
   }

   if(rangeAtrMax > 0.0 && rangeAtrRatio > rangeAtrMax)
   {
      reason = StringFormat("range_atr_high ratio=%.3f max=%.3f", rangeAtrRatio, rangeAtrMax);
      return false;
   }

   return true;
}

bool GoldScalperBreakoutPriorDayAllowed(const string symbol,
                                        const double priorDayAtrMax,
                                        double &priorDayAtrRatio,
                                        string &reason)
{
   priorDayAtrRatio = 0.0;
   if(priorDayAtrMax <= 0.0)
      return true;

   double d1Atr = GoldScalperBreakoutBufferValue(s_breakoutD1AtrHandle, 0, 1);
   if(d1Atr == EMPTY_VALUE || d1Atr <= 0.0)
   {
      reason = "d1_atr_unavailable";
      return false;
   }

   MqlRates d1[];
   ArraySetAsSeries(d1, true);
   if(CopyRates(symbol, PERIOD_D1, 1, 1, d1) != 1)
   {
      reason = "prior_day_unavailable";
      return false;
   }

   double priorRange = d1[0].high - d1[0].low;
   priorDayAtrRatio = priorRange / d1Atr;
   if(priorDayAtrRatio > priorDayAtrMax)
   {
      reason = StringFormat("prior_day_shock ratio=%.3f max=%.3f", priorDayAtrRatio, priorDayAtrMax);
      return false;
   }

   return true;
}

ENUM_GS_BREAKOUT_DECISION GoldScalperBreakoutRegimeEvaluate(
   const string symbol,
   const bool enableFilter,
   const bool directionFilter,
   const double asianRange,
   const double adxMin,
   const double adxMax,
   const double rangeAtrMin,
   const double rangeAtrMax,
   const double priorDayAtrMax,
   string &reason)
{
   reason = "filter_disabled";
   if(!enableFilter)
      return GS_BREAKOUT_BOTH;

   reason = "";
   double adxValue = 0.0;
   double rangeAtrRatio = 0.0;
   double priorDayAtrRatio = 0.0;

   if(!GoldScalperBreakoutAdxAllowed(adxMin, adxMax, adxValue, reason))
      return GS_BREAKOUT_SKIP;

   if(!GoldScalperBreakoutRangeAllowed(asianRange, rangeAtrMin, rangeAtrMax, rangeAtrRatio, reason))
      return GS_BREAKOUT_SKIP;

   if(!GoldScalperBreakoutPriorDayAllowed(symbol, priorDayAtrMax, priorDayAtrRatio, reason))
      return GS_BREAKOUT_SKIP;

   ENUM_GS_BREAKOUT_DECISION decision = GS_BREAKOUT_BOTH;
   int d1Trend = 0;
   int h4Trend = 0;

   if(directionFilter)
   {
      d1Trend = GoldScalperBreakoutTrendDirection(symbol, PERIOD_D1, s_breakoutD1EmaHandle);
      h4Trend = GoldScalperBreakoutTrendDirection(symbol, PERIOD_H4, s_breakoutH4EmaHandle);

      if(d1Trend > 0 && h4Trend > 0)
         decision = GS_BREAKOUT_BUY_ONLY;
      else if(d1Trend < 0 && h4Trend < 0)
         decision = GS_BREAKOUT_SELL_ONLY;
      else
      {
         reason = StringFormat("trend_mixed d1=%d h4=%d", d1Trend, h4Trend);
         return GS_BREAKOUT_SKIP;
      }
   }

   reason = StringFormat("pass decision=%s d1=%d h4=%d adx=%.2f rangeAtr=%.3f priorDayAtr=%.3f",
      GoldScalperBreakoutDecisionName(decision),
      d1Trend,
      h4Trend,
      adxValue,
      rangeAtrRatio,
      priorDayAtrRatio);

   return decision;
}

#endif
