#ifndef DZV_STYLE_DAILY_STATE_MQH
#define DZV_STYLE_DAILY_STATE_MQH

#include <DZVStyle/ZoneEngine.mqh>

struct DZVDailyState
{
   DZVDailyZoneSet zone_set;
   datetime cached_day_start;
};

void DZVDailyStateReset(DZVDailyState &state)
{
   state.cached_day_start = 0;
   state.zone_set.valid = false;
   state.zone_set.error = "not initialized";
}

bool DZVDailyStateEnsure(const string symbol,
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
                         DZVDailyState &state)
{
   datetime dayStart = DZVDayStart(symbol);
   if(dayStart == 0)
   {
      state.zone_set.valid = false;
      state.zone_set.error = "Unable to resolve current broker day";
      return false;
   }

   if(state.zone_set.valid && state.cached_day_start == dayStart)
      return true;

   bool ok = DZVBuildZoneSet(symbol, adrMode, baseMode, adrPeriod, minimumRequiredDailyBars,
                             excludeSundayCandle, excludeAbnormalDailyBars,
                             abnormalRangeMultiplier, upperMultipliers, lowerMultipliers,
                             debug, state.zone_set);
   state.cached_day_start = ok ? state.zone_set.day_start : dayStart;
   if(!ok)
      Print("DZVStyle: zone build failed: ", state.zone_set.error);
   return ok;
}

#endif
