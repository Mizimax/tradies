#ifndef GOLDBOT_INDICATORS_MQH
#define GOLDBOT_INDICATORS_MQH

struct IndicatorSnapshot
{
   double ema21;
   double ema50;
   double ema200;
   double rsi;
   double vwap;
   double vwapUpper;
   double vwapLower;
   double atr;
   double adx;
   double plusDI;
   double minusDI;
   double macdMain;
   double macdSignal;
   double bbUpper;
   double bbMiddle;
   double bbLower;
   double stochK;
   double stochD;
   bool emaLong;
   bool emaShort;
   bool rsiLong;
   bool rsiShort;
   bool vwapLong;
   bool vwapShort;
   bool atrPass;
   bool adxLong;
   bool adxShort;
   bool macdLong;
   bool macdShort;
   bool bbLong;
   bool bbShort;
   bool stochLong;
   bool stochShort;
};

double GoldBotBufferValue(const int handle, const int buffer, const int shift)
{
   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1)
      return EMPTY_VALUE;
   return values[0];
}

double GoldBotMA(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const int shift)
{
   int handle = iMA(symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return EMPTY_VALUE;
   double value = GoldBotBufferValue(handle, 0, shift);
   IndicatorRelease(handle);
   return value;
}

double GoldBotRSI(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const int shift)
{
   int handle = iRSI(symbol, tf, period, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return EMPTY_VALUE;
   double value = GoldBotBufferValue(handle, 0, shift);
   IndicatorRelease(handle);
   return value;
}

double GoldBotATR(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const int shift)
{
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE)
      return EMPTY_VALUE;
   double value = GoldBotBufferValue(handle, 0, shift);
   IndicatorRelease(handle);
   return value;
}

bool GoldBotADX(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const int shift, double &adx, double &plusDI, double &minusDI)
{
   int handle = iADX(symbol, tf, period);
   if(handle == INVALID_HANDLE)
      return false;
   adx = GoldBotBufferValue(handle, 0, shift);
   plusDI = GoldBotBufferValue(handle, 1, shift);
   minusDI = GoldBotBufferValue(handle, 2, shift);
   IndicatorRelease(handle);
   return adx != EMPTY_VALUE && plusDI != EMPTY_VALUE && minusDI != EMPTY_VALUE;
}

bool GoldBotMACD(
   const string symbol,
   const ENUM_TIMEFRAMES tf,
   const int fastPeriod,
   const int slowPeriod,
   const int signalPeriod,
   const int shift,
   double &mainValue,
   double &signalValue
)
{
   int handle = iMACD(symbol, tf, fastPeriod, slowPeriod, signalPeriod, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return false;
   mainValue = GoldBotBufferValue(handle, 0, shift);
   signalValue = GoldBotBufferValue(handle, 1, shift);
   IndicatorRelease(handle);
   return mainValue != EMPTY_VALUE && signalValue != EMPTY_VALUE;
}

bool GoldBotBands(
   const string symbol,
   const ENUM_TIMEFRAMES tf,
   const int period,
   const double deviation,
   const int shift,
   double &upper,
   double &middle,
   double &lower
)
{
   int handle = iBands(symbol, tf, period, 0, deviation, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return false;
   middle = GoldBotBufferValue(handle, 0, shift);
   upper = GoldBotBufferValue(handle, 1, shift);
   lower = GoldBotBufferValue(handle, 2, shift);
   IndicatorRelease(handle);
   return upper != EMPTY_VALUE && middle != EMPTY_VALUE && lower != EMPTY_VALUE;
}

bool GoldBotStochastic(
   const string symbol,
   const ENUM_TIMEFRAMES tf,
   const int kPeriod,
   const int dPeriod,
   const int slowing,
   const int shift,
   double &kValue,
   double &dValue
)
{
   int handle = iStochastic(symbol, tf, kPeriod, dPeriod, slowing, MODE_SMA, STO_LOWHIGH);
   if(handle == INVALID_HANDLE)
      return false;
   kValue = GoldBotBufferValue(handle, 0, shift);
   dValue = GoldBotBufferValue(handle, 1, shift);
   IndicatorRelease(handle);
   return kValue != EMPTY_VALUE && dValue != EMPTY_VALUE;
}

bool GoldBotSessionVWAP(const string symbol, const ENUM_TIMEFRAMES tf, const int bars, double &vwap, double &upper, double &lower)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, tf, 1, bars, rates);
   if(copied < 10)
      return false;

   MqlDateTime latest;
   TimeToStruct(rates[0].time, latest);

   double pv = 0.0;
   double vol = 0.0;
   double typicals[];
   ArrayResize(typicals, copied);
   int used = 0;

   for(int i = 0; i < copied; i++)
   {
      MqlDateTime t;
      TimeToStruct(rates[i].time, t);
      if(t.year != latest.year || t.mon != latest.mon || t.day != latest.day)
         continue;

      double typical = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      long tickVolume = rates[i].tick_volume;
      double volume = (double)(tickVolume > 0 ? tickVolume : 1);
      pv += typical * volume;
      vol += volume;
      typicals[used] = typical;
      used++;
   }

   if(used < 5 || vol <= 0.0)
      return false;

   vwap = pv / vol;
   double variance = 0.0;
   for(int i = 0; i < used; i++)
      variance += MathPow(typicals[i] - vwap, 2.0);

   double stdev = MathSqrt(variance / used);
   upper = vwap + stdev;
   lower = vwap - stdev;
   return true;
}

bool GoldBotIndicatorSnapshot(
   const string symbol,
   const double rsiLongMax,
   const double rsiShortMin,
   const double adxMin,
   const double atrMin,
   const double atrMax,
   const int rsiPeriod,
   const int macdFast,
   const int macdSlow,
   const int macdSignal,
   const int bbPeriod,
   const double bbDeviation,
   const int stochKPeriod,
   const int stochDPeriod,
   const int stochSlowing,
   const double stochLongMax,
   const double stochShortMin,
   IndicatorSnapshot &out
)
{
   MqlRates h1[];
   MqlRates m15[];
   ArraySetAsSeries(h1, true);
   ArraySetAsSeries(m15, true);
   if(CopyRates(symbol, PERIOD_H1, 1, 260, h1) < 220)
      return false;
   if(CopyRates(symbol, PERIOD_M15, 1, 120, m15) < 80)
      return false;

   out.ema21 = GoldBotMA(symbol, PERIOD_H1, 21, 1);
   out.ema50 = GoldBotMA(symbol, PERIOD_H1, 50, 1);
   out.ema200 = GoldBotMA(symbol, PERIOD_H1, 200, 1);
   out.rsi = GoldBotRSI(symbol, PERIOD_M15, rsiPeriod, 1);
   out.atr = GoldBotATR(symbol, PERIOD_H1, 14, 1);

   if(out.ema21 == EMPTY_VALUE || out.ema50 == EMPTY_VALUE || out.ema200 == EMPTY_VALUE || out.rsi == EMPTY_VALUE || out.atr == EMPTY_VALUE)
      return false;
   if(!GoldBotADX(symbol, PERIOD_H1, 14, 1, out.adx, out.plusDI, out.minusDI))
      return false;
   if(!GoldBotSessionVWAP(symbol, PERIOD_M15, 96, out.vwap, out.vwapUpper, out.vwapLower))
      return false;
   if(!GoldBotMACD(symbol, PERIOD_H1, macdFast, macdSlow, macdSignal, 1, out.macdMain, out.macdSignal))
      return false;
   if(!GoldBotBands(symbol, PERIOD_M15, bbPeriod, bbDeviation, 1, out.bbUpper, out.bbMiddle, out.bbLower))
      return false;
   if(!GoldBotStochastic(symbol, PERIOD_M15, stochKPeriod, stochDPeriod, stochSlowing, 1, out.stochK, out.stochD))
      return false;

   double price = h1[0].close;
   double m15Close = m15[0].close;
   out.emaLong = price > out.ema21 && out.ema21 > out.ema50 && out.ema50 > out.ema200;
   out.emaShort = price < out.ema21 && out.ema21 < out.ema50 && out.ema50 < out.ema200;
   out.rsiLong = out.rsi <= rsiLongMax;
   out.rsiShort = out.rsi >= rsiShortMin;
   out.vwapLong = m15Close < out.vwap && m15Close <= out.vwapLower * 1.003;
   out.vwapShort = m15Close > out.vwap && m15Close >= out.vwapUpper * 0.997;
   out.atrPass = out.atr >= atrMin && out.atr <= atrMax;
   out.adxLong = out.adx >= adxMin && out.plusDI > out.minusDI;
   out.adxShort = out.adx >= adxMin && out.minusDI > out.plusDI;
   out.macdLong = out.macdMain > out.macdSignal;
   out.macdShort = out.macdMain < out.macdSignal;
   out.bbLong = m15Close <= out.bbLower * 1.003;
   out.bbShort = m15Close >= out.bbUpper * 0.997;
   out.stochLong = out.stochK <= stochLongMax && out.stochK >= out.stochD;
   out.stochShort = out.stochK >= stochShortMin && out.stochK <= out.stochD;
   return true;
}

#endif
