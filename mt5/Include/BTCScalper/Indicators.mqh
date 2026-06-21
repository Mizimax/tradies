#ifndef BTCSCALPER_INDICATORS_MQH
#define BTCSCALPER_INDICATORS_MQH

//+------------------------------------------------------------------+
//| Indicators.mqh — central indicator handle manager & VWAP         |
//| Part of BTCScalper EA                                            |
//+------------------------------------------------------------------+

//--- Global Indicator Handles
int g_btcBbHandle     = INVALID_HANDLE;  // BB(20, 2.0) on M15
int g_btcRsiHandle    = INVALID_HANDLE;  // RSI(14) on M15
int g_btcAtrHandle    = INVALID_HANDLE;  // ATR(14) on M15
int g_btcAdxHandle    = INVALID_HANDLE;  // ADX(14) on M15
int g_btcEmaFast      = INVALID_HANDLE;  // EMA(9) on M15
int g_btcEmaSlow      = INVALID_HANDLE;  // EMA(21) on M15
int g_btcEma50        = INVALID_HANDLE;  // EMA(50) on M15
int g_btcAtrM5Handle  = INVALID_HANDLE;  // ATR(14) on M5 (for VWAP SL sizing)
int g_btcRsiM5Handle  = INVALID_HANDLE;  // RSI(14) on M5 (for VWAP verification)

//--- VWAP Static State
static double s_vwap = 0.0;
static double s_stddev = 0.0;
static double s_zscore = 0.0;

//--- Helper to read buffer values
double BTCScalperGetBufferValue(const int handle, const int buffer, const int shift)
{
   if(handle == INVALID_HANDLE)
      return EMPTY_VALUE;
   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1)
      return EMPTY_VALUE;
   return values[0];
}

//--- Initialize all indicator handles
bool BTCScalperIndicatorsInit(
   const string symbol,
   const int bbPeriod,
   const double bbDev,
   const int rsiPeriod,
   const int atrPeriod,
   const int adxPeriod,
   const int emaFast,
   const int emaSlow
)
{
   g_btcBbHandle = iBands(symbol, PERIOD_M15, bbPeriod, 0, bbDev, PRICE_CLOSE);
   g_btcRsiHandle = iRSI(symbol, PERIOD_M15, rsiPeriod, PRICE_CLOSE);
   g_btcAtrHandle = iATR(symbol, PERIOD_M15, atrPeriod);
   g_btcAdxHandle = iADX(symbol, PERIOD_M15, adxPeriod);
   g_btcEmaFast = iMA(symbol, PERIOD_M15, emaFast, 0, MODE_EMA, PRICE_CLOSE);
   g_btcEmaSlow = iMA(symbol, PERIOD_M15, emaSlow, 0, MODE_EMA, PRICE_CLOSE);
   g_btcEma50 = iMA(symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   g_btcAtrM5Handle = iATR(symbol, PERIOD_M5, atrPeriod);
   g_btcRsiM5Handle = iRSI(symbol, PERIOD_M5, rsiPeriod, PRICE_CLOSE);

   if(g_btcBbHandle == INVALID_HANDLE || g_btcRsiHandle == INVALID_HANDLE ||
      g_btcAtrHandle == INVALID_HANDLE || g_btcAdxHandle == INVALID_HANDLE ||
      g_btcEmaFast == INVALID_HANDLE || g_btcEmaSlow == INVALID_HANDLE ||
      g_btcEma50 == INVALID_HANDLE || g_btcAtrM5Handle == INVALID_HANDLE ||
      g_btcRsiM5Handle == INVALID_HANDLE)
   {
      Print("BTCScalper: Failed to create one or more indicator handles.");
      return false;
   }
   return true;
}

//--- Release all handles
void BTCScalperIndicatorsDeinit()
{
   if(g_btcBbHandle != INVALID_HANDLE) { IndicatorRelease(g_btcBbHandle); g_btcBbHandle = INVALID_HANDLE; }
   if(g_btcRsiHandle != INVALID_HANDLE) { IndicatorRelease(g_btcRsiHandle); g_btcRsiHandle = INVALID_HANDLE; }
   if(g_btcAtrHandle != INVALID_HANDLE) { IndicatorRelease(g_btcAtrHandle); g_btcAtrHandle = INVALID_HANDLE; }
   if(g_btcAdxHandle != INVALID_HANDLE) { IndicatorRelease(g_btcAdxHandle); g_btcAdxHandle = INVALID_HANDLE; }
   if(g_btcEmaFast != INVALID_HANDLE) { IndicatorRelease(g_btcEmaFast); g_btcEmaFast = INVALID_HANDLE; }
   if(g_btcEmaSlow != INVALID_HANDLE) { IndicatorRelease(g_btcEmaSlow); g_btcEmaSlow = INVALID_HANDLE; }
   if(g_btcEma50 != INVALID_HANDLE) { IndicatorRelease(g_btcEma50); g_btcEma50 = INVALID_HANDLE; }
   if(g_btcAtrM5Handle != INVALID_HANDLE) { IndicatorRelease(g_btcAtrM5Handle); g_btcAtrM5Handle = INVALID_HANDLE; }
   if(g_btcRsiM5Handle != INVALID_HANDLE) { IndicatorRelease(g_btcRsiM5Handle); g_btcRsiM5Handle = INVALID_HANDLE; }
}

//--- VWAP Reset
void BTCScalperVwapReset()
{
   s_vwap = 0.0;
   s_stddev = 0.0;
   s_zscore = 0.0;
}

//--- Live daily-session VWAP calculation from M5 bars
bool BTCScalperVwapUpdate(const string symbol)
{
   datetime current_time = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(current_time, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime day_start = StructToTime(dt);

   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int copied = CopyRates(symbol, PERIOD_M5, day_start, current_time, rates);
   if(copied <= 0)
      return false;

   double cumVolume = 0;
   double cumTPV = 0;
   double cumTPV2 = 0;

   for(int i = 0; i < copied; i++)
   {
      double typicalPrice = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      double vol = (double)rates[i].tick_volume;
      if(vol <= 0.0)
         vol = 1.0; // fallback if tick volume is zero

      cumVolume += vol;
      cumTPV += typicalPrice * vol;
      cumTPV2 += typicalPrice * typicalPrice * vol;
   }

   if(cumVolume > 0.0)
   {
      s_vwap = cumTPV / cumVolume;
      double meanTP2 = cumTPV2 / cumVolume;
      double variance = meanTP2 - (s_vwap * s_vwap);
      s_stddev = (variance > 0.0) ? MathSqrt(variance) : 0.0;
      
      // Calculate Z-score for the latest close (shift = 0 of the current M5 bar)
      double lastClose = rates[copied - 1].close;
      if(s_stddev > 0.0)
         s_zscore = (lastClose - s_vwap) / s_stddev;
      else
         s_zscore = 0.0;
   }
   else
   {
      s_vwap = rates[copied-1].close;
      s_stddev = 0.0;
      s_zscore = 0.0;
   }
   return true;
}

double BTCScalperVwapValue()
{
   return s_vwap;
}

double BTCScalperVwapZscore()
{
   return s_zscore;
}

#endif
