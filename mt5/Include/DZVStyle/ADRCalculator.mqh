#ifndef DZV_STYLE_ADR_CALCULATOR_MQH
#define DZV_STYLE_ADR_CALCULATOR_MQH

#include <DZVStyle/DZVTypes.mqh>

struct DZVADRResult
{
   double adr;
   double average_upper_excursion;
   double average_lower_excursion;
   int included_bars;
};

bool DZVCalculateADR(const string symbol,
                     const ENUM_DZV_ADR_MODE mode,
                     const int period,
                     const int minimumRequiredDailyBars,
                     const bool excludeSundayCandle,
                     const bool excludeAbnormalDailyBars,
                     const double abnormalRangeMultiplier,
                     const bool debug,
                     DZVADRResult &result,
                     string &error)
{
   result.adr = 0.0;
   result.average_upper_excursion = 0.0;
   result.average_lower_excursion = 0.0;
   result.included_bars = 0;
   error = "";

   if(period <= 0)
   {
      error = "ADRPeriod must be positive";
      return false;
   }
   if(minimumRequiredDailyBars < period)
   {
      error = "MinimumRequiredDailyBars must be >= ADRPeriod";
      return false;
   }
   if(!SymbolSelect(symbol, true))
   {
      error = "Unable to select symbol " + symbol;
      return false;
   }

   int barsNeeded = MathMax(minimumRequiredDailyBars + 2, period * 4 + 5);
   MqlRates d1[];
   ArraySetAsSeries(d1, true);
   int copied = CopyRates(symbol, PERIOD_D1, 1, barsNeeded, d1);
   if(copied < minimumRequiredDailyBars)
   {
      error = StringFormat("Missing D1 history copied=%d required=%d", copied, minimumRequiredDailyBars);
      return false;
   }

   double candidateRanges[];
   ArrayResize(candidateRanges, copied);
   int candidateCount = 0;
   for(int i = 0; i < copied; i++)
   {
      if(excludeSundayCandle && DZVIsSunday(d1[i].time))
         continue;
      double range = d1[i].high - d1[i].low;
      if(range <= 0.0)
         continue;
      candidateRanges[candidateCount] = range;
      candidateCount++;
   }

   if(candidateCount < period)
   {
      error = StringFormat("Not enough usable D1 bars after filters usable=%d period=%d", candidateCount, period);
      return false;
   }

   double baseAverage = 0.0;
   for(int i = 0; i < candidateCount; i++)
      baseAverage += candidateRanges[i];
   baseAverage /= candidateCount;

   double total = 0.0;
   double totalUpper = 0.0;
   double totalLower = 0.0;
   for(int i = 0; i < copied && result.included_bars < period; i++)
   {
      if(excludeSundayCandle && DZVIsSunday(d1[i].time))
         continue;

      double highLow = d1[i].high - d1[i].low;
      if(highLow <= 0.0)
         continue;

      if(excludeAbnormalDailyBars && abnormalRangeMultiplier > 0.0 && baseAverage > 0.0)
      {
         if(highLow > baseAverage * abnormalRangeMultiplier)
         {
            if(debug)
               Print("DZVStyle: excluded abnormal D1 bar ", TimeToString(d1[i].time), " range=", DoubleToString(highLow, _Digits));
            continue;
         }
      }

      double dailyValue = highLow;
      if(mode == DZV_ADR_TRUE_RANGE)
      {
         if(i + 1 >= copied)
            continue;
         double previousClose = d1[i + 1].close;
         dailyValue = MathMax(highLow, MathMax(MathAbs(d1[i].high - previousClose), MathAbs(d1[i].low - previousClose)));
      }

      double upperExcursion = MathMax(0.0, d1[i].high - d1[i].open);
      double lowerExcursion = MathMax(0.0, d1[i].open - d1[i].low);
      total += dailyValue;
      totalUpper += upperExcursion;
      totalLower += lowerExcursion;
      result.included_bars++;

      if(debug)
      {
         Print("DZVStyle: ADR include ",
               TimeToString(d1[i].time, TIME_DATE),
               " range=", DoubleToString(highLow, _Digits),
               " value=", DoubleToString(dailyValue, _Digits),
               " upper=", DoubleToString(upperExcursion, _Digits),
               " lower=", DoubleToString(lowerExcursion, _Digits));
      }
   }

   if(result.included_bars < period)
   {
      error = StringFormat("Not enough included D1 bars included=%d period=%d", result.included_bars, period);
      return false;
   }

   result.adr = total / result.included_bars;
   result.average_upper_excursion = totalUpper / result.included_bars;
   result.average_lower_excursion = totalLower / result.included_bars;
   if(result.adr <= 0.0 && mode != DZV_ADR_DIRECTIONAL_EXCURSION)
   {
      error = "Calculated ADR is not positive";
      return false;
   }
   if(mode == DZV_ADR_DIRECTIONAL_EXCURSION &&
      (result.average_upper_excursion <= 0.0 || result.average_lower_excursion <= 0.0))
   {
      error = "Directional excursion averages are not positive";
      return false;
   }
   return true;
}

#endif
