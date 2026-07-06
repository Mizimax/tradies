#ifndef DZV_STYLE_ZONE_ENGINE_MQH
#define DZV_STYLE_ZONE_ENGINE_MQH

#include <DZVStyle/ADRCalculator.mqh>

bool DZVValidateMultipliers(const double &upperMultipliers[],
                            const double &lowerMultipliers[],
                            string &error)
{
   error = "";
   for(int i = 0; i < DZV_ZONE_COUNT; i++)
   {
      if(upperMultipliers[i] <= 0.0 || lowerMultipliers[i] <= 0.0)
      {
         error = "Zone multipliers must be positive";
         return false;
      }
      if(i > 0)
      {
         if(upperMultipliers[i] <= upperMultipliers[i - 1])
         {
            error = "Upper zone multipliers must be strictly increasing";
            return false;
         }
         if(lowerMultipliers[i] <= lowerMultipliers[i - 1])
         {
            error = "Lower zone multipliers must be strictly increasing";
            return false;
         }
      }
   }
   return true;
}

bool DZVResolveDailyBase(const string symbol,
                         const ENUM_DZV_ZONE_BASE baseMode,
                         datetime &dayStart,
                         double &basePrice,
                         string &error)
{
   dayStart = 0;
   basePrice = 0.0;
   error = "";

   MqlRates d1[];
   ArraySetAsSeries(d1, true);
   if(CopyRates(symbol, PERIOD_D1, 0, 3, d1) < 3)
   {
      error = "Unable to copy current and previous D1 bars for base price";
      return false;
   }

   dayStart = d1[0].time;
   if(baseMode == DZV_BASE_CURRENT_DAILY_OPEN)
      basePrice = d1[0].open;
   else if(baseMode == DZV_BASE_PREVIOUS_DAILY_CLOSE)
      basePrice = d1[1].close;
   else if(baseMode == DZV_BASE_PREVIOUS_DAILY_MIDPOINT)
      basePrice = (d1[1].high + d1[1].low) / 2.0;
   else if(baseMode == DZV_BASE_PREVIOUS_TYPICAL_PRICE)
      basePrice = (d1[1].high + d1[1].low + d1[1].close) / 3.0;

   if(basePrice <= 0.0)
   {
      error = "Calculated base price is not positive";
      return false;
   }
   return true;
}

bool DZVBuildZoneSet(const string symbol,
                     const ENUM_DZV_ADR_MODE adrMode,
                     const ENUM_DZV_ZONE_BASE baseMode,
                     const int adrPeriod,
                     const int minimumRequiredDailyBars,
                     const bool excludeSundayCandle,
                     const bool excludeAbnormalDailyBars,
                     const double abnormalRangeMultiplier,
                     const double &upperMultipliers[],
                     const double &lowerMultipliers[],
                     const bool debug,
                     DZVDailyZoneSet &zoneSet)
{
   zoneSet.valid = false;
   zoneSet.error = "";
   zoneSet.day_start = 0;
   zoneSet.base_price = 0.0;
   zoneSet.adr = 0.0;
   zoneSet.average_upper_excursion = 0.0;
   zoneSet.average_lower_excursion = 0.0;
   for(int i = 0; i < DZV_ZONE_COUNT; i++)
   {
      zoneSet.upper[i] = 0.0;
      zoneSet.lower[i] = 0.0;
   }

   string error = "";
   if(!DZVValidateMultipliers(upperMultipliers, lowerMultipliers, error))
   {
      zoneSet.error = error;
      return false;
   }

   DZVADRResult adr;
   if(!DZVCalculateADR(symbol, adrMode, adrPeriod, minimumRequiredDailyBars,
                       excludeSundayCandle, excludeAbnormalDailyBars,
                       abnormalRangeMultiplier, debug, adr, error))
   {
      zoneSet.error = error;
      return false;
   }

   datetime dayStart = 0;
   double basePrice = 0.0;
   if(!DZVResolveDailyBase(symbol, baseMode, dayStart, basePrice, error))
   {
      zoneSet.error = error;
      return false;
   }

   zoneSet.day_start = dayStart;
   zoneSet.base_price = basePrice;
   zoneSet.adr = adr.adr;
   zoneSet.average_upper_excursion = adr.average_upper_excursion;
   zoneSet.average_lower_excursion = adr.average_lower_excursion;

   for(int i = 0; i < DZV_ZONE_COUNT; i++)
   {
      double upperRange = (adrMode == DZV_ADR_DIRECTIONAL_EXCURSION) ? adr.average_upper_excursion : adr.adr;
      double lowerRange = (adrMode == DZV_ADR_DIRECTIONAL_EXCURSION) ? adr.average_lower_excursion : adr.adr;
      zoneSet.upper[i] = DZVNormalizePrice(symbol, basePrice + upperRange * upperMultipliers[i]);
      zoneSet.lower[i] = DZVNormalizePrice(symbol, basePrice - lowerRange * lowerMultipliers[i]);
   }

   zoneSet.valid = true;
   return true;
}

double DZVCurrentDailyRange(const string symbol)
{
   MqlRates d1[];
   ArraySetAsSeries(d1, true);
   if(CopyRates(symbol, PERIOD_D1, 0, 1, d1) != 1)
      return 0.0;
   return MathMax(0.0, d1[0].high - d1[0].low);
}

#endif
