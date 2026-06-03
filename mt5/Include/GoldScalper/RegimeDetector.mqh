#ifndef GOLDSCALPER_REGIME_DETECTOR_MQH
#define GOLDSCALPER_REGIME_DETECTOR_MQH

//+------------------------------------------------------------------+
//| RegimeDetector.mqh — Higher-timeframe macro regime classification  |
//| Part of GoldScalper EA                                             |
//|                                                                    |
//| Uses D1 EMA(50) to classify the macro trend:                       |
//|   BULL  — D1 close > D1 EMA(50) AND EMA slope is rising           |
//|   BEAR  — D1 close < D1 EMA(50) AND EMA slope is falling          |
//|   RANGE — Everything else (flat EMA, price near EMA)               |
//|                                                                    |
//| Purpose: Controls which MR trade directions are allowed.           |
//|   BULL  → Only BUY signals (buy the dip in uptrends)               |
//|   BEAR  → Only SELL signals (sell rallies in downtrends)           |
//|   RANGE → Both directions (mean reversion works best here)         |
//+------------------------------------------------------------------+

//--- Regime enumeration
enum ENUM_REGIME
{
   REGIME_BULL  = 1,    // Macro uptrend: only BUY allowed
   REGIME_BEAR  = -1,   // Macro downtrend: only SELL allowed
   REGIME_RANGE = 0     // Range-bound: both directions allowed
};

//--- Static indicator handles
static int    s_regimeEmaHandle = INVALID_HANDLE;
static int    s_regimeAtrHandle = INVALID_HANDLE;
static string s_regimeSymbol    = "";

//+------------------------------------------------------------------+
//| Initialize regime detection indicators                             |
//+------------------------------------------------------------------+
void GoldScalperRegimeInit(const string symbol, const int emaPeriod = 50)
{
   s_regimeSymbol = symbol;

   // D1 EMA for trend direction
   s_regimeEmaHandle = iMA(symbol, PERIOD_D1, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(s_regimeEmaHandle == INVALID_HANDLE)
      Print("[Regime-Init] ERROR: D1 EMA(", emaPeriod, ") handle creation failed");
   else
      Print("[Regime-Init] D1 EMA(", emaPeriod, ") handle created: ", s_regimeEmaHandle);

   // D1 ATR for slope threshold calibration
   s_regimeAtrHandle = iATR(symbol, PERIOD_D1, 14);
   if(s_regimeAtrHandle == INVALID_HANDLE)
      Print("[Regime-Init] ERROR: D1 ATR(14) handle creation failed");
   else
      Print("[Regime-Init] D1 ATR(14) handle created: ", s_regimeAtrHandle);

   Print("[Regime-Init] Regime detection module initialised for ", symbol);
}

//+------------------------------------------------------------------+
//| Release indicator handles                                          |
//+------------------------------------------------------------------+
void GoldScalperRegimeDeinit()
{
   if(s_regimeEmaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(s_regimeEmaHandle);
      Print("[Regime-Deinit] D1 EMA handle released: ", s_regimeEmaHandle);
      s_regimeEmaHandle = INVALID_HANDLE;
   }
   if(s_regimeAtrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(s_regimeAtrHandle);
      Print("[Regime-Deinit] D1 ATR handle released: ", s_regimeAtrHandle);
      s_regimeAtrHandle = INVALID_HANDLE;
   }
   Print("[Regime-Deinit] Regime detection module de-initialised");
}

//+------------------------------------------------------------------+
//| Helper — read a single value from an indicator buffer              |
//+------------------------------------------------------------------+
double GoldScalperRegimeBufferValue(const int handle, const int buffer, const int shift)
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
//| Detect current macro regime                                        |
//|                                                                    |
//| Algorithm:                                                         |
//|   1. Read D1 close and EMA(50) on the last completed daily bar     |
//|   2. Calculate EMA slope = EMA[1] - EMA[6] (5-day change)          |
//|   3. Read D1 ATR for threshold calibration                         |
//|   4. Classify:                                                     |
//|      BULL  = close > EMA AND slope > slopeThresh * ATR             |
//|      BEAR  = close < EMA AND slope < -slopeThresh * ATR            |
//|      RANGE = everything else                                       |
//|                                                                    |
//| slopeThreshFactor: How many ATR fractions the slope must exceed.    |
//|   Default 0.1 = EMA must move at least 10% of D1 ATR in 5 days    |
//|   to be considered trending. This avoids false classification       |
//|   during flat-but-above-EMA periods.                               |
//+------------------------------------------------------------------+
ENUM_REGIME GoldScalperDetectRegime(const double slopeThreshFactor = 0.1)
{
   if(s_regimeEmaHandle == INVALID_HANDLE || s_regimeAtrHandle == INVALID_HANDLE)
   {
      Print("[Regime] Handles not initialised, defaulting to RANGE");
      return REGIME_RANGE;
   }

   //--- Read D1 close (last completed bar = shift 1)
   MqlRates d1[];
   ArraySetAsSeries(d1, true);
   if(CopyRates(s_regimeSymbol, PERIOD_D1, 1, 1, d1) < 1)
   {
      Print("[Regime] ERROR: Cannot copy D1 rates");
      return REGIME_RANGE;
   }
   double d1Close = d1[0].close;

   //--- Read EMA values: current (shift 1) and 5 bars ago (shift 6)
   double emaCurrent = GoldScalperRegimeBufferValue(s_regimeEmaHandle, 0, 1);
   double emaPast    = GoldScalperRegimeBufferValue(s_regimeEmaHandle, 0, 6);
   if(emaCurrent == EMPTY_VALUE || emaPast == EMPTY_VALUE)
   {
      Print("[Regime] ERROR: EMA values unavailable");
      return REGIME_RANGE;
   }

   //--- Read D1 ATR for threshold calibration
   double d1Atr = GoldScalperRegimeBufferValue(s_regimeAtrHandle, 0, 1);
   if(d1Atr == EMPTY_VALUE || d1Atr <= 0.0)
   {
      Print("[Regime] ERROR: D1 ATR unavailable");
      return REGIME_RANGE;
   }

   //--- Calculate slope and threshold
   double emaSlope     = emaCurrent - emaPast;
   double slopeThresh  = slopeThreshFactor * d1Atr;

   //--- Classify regime
   ENUM_REGIME regime = REGIME_RANGE;

   if(d1Close > emaCurrent && emaSlope > slopeThresh)
      regime = REGIME_BULL;
   else if(d1Close < emaCurrent && emaSlope < -slopeThresh)
      regime = REGIME_BEAR;

   //--- Log
   string regimeStr = (regime == REGIME_BULL)  ? "BULL" :
                       (regime == REGIME_BEAR)  ? "BEAR" : "RANGE";
   int digits = (int)SymbolInfoInteger(s_regimeSymbol, SYMBOL_DIGITS);

   Print("[Regime] ", regimeStr,
         " | D1 close=", DoubleToString(d1Close, digits),
         " EMA=", DoubleToString(emaCurrent, digits),
         " slope=", DoubleToString(emaSlope, digits),
         " thresh=±", DoubleToString(slopeThresh, digits),
         " ATR=", DoubleToString(d1Atr, digits));

   return regime;
}

//+------------------------------------------------------------------+
//| Check if a signal direction is allowed given the current regime     |
//|                                                                    |
//| signal: +1 BUY, -1 SELL                                            |
//| Returns true if the signal is compatible with the regime            |
//+------------------------------------------------------------------+
bool GoldScalperRegimeAllowsSignal(const ENUM_REGIME regime, const int signal)
{
   if(regime == REGIME_RANGE)
      return true;   // Both directions allowed in range

   if(regime == REGIME_BULL && signal == +1)
      return true;   // BUY allowed in bull

   if(regime == REGIME_BEAR && signal == -1)
      return true;   // SELL allowed in bear

   // Signal conflicts with regime
   string sigStr = (signal == +1) ? "BUY" : "SELL";
   string regStr = (regime == REGIME_BULL) ? "BULL" : "BEAR";
   Print("[Regime] ", sigStr, " signal BLOCKED by ", regStr, " regime");
   return false;
}

#endif
