#property strict
#property script_show_inputs

#include <DZVStyle/ZoneEngine.mqh>

input string InpSymbol = "XAUUSD";

void OnStart()
{
   string symbol = InpSymbol == "" ? _Symbol : InpSymbol;
   double upper[DZV_ZONE_COUNT] = {0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 1.75};
   double lower[DZV_ZONE_COUNT] = {0.25, 0.50, 0.75, 1.00, 1.25, 1.50, 1.75};
   string error = "";
   if(!DZVValidateMultipliers(upper, lower, error))
   {
      Print("DZV self-test failed multiplier validation: ", error);
      return;
   }

   DZVDailyZoneSet zones;
   if(!DZVBuildZoneSet(symbol, DZV_ADR_HIGH_LOW, DZV_BASE_CURRENT_DAILY_OPEN, 14, 30,
                       true, false, 3.0, upper, lower, true, zones))
   {
      Print("DZV self-test failed zone build: ", zones.error);
      return;
   }

   if(!zones.valid || zones.day_start <= 0 || zones.base_price <= 0.0 || zones.adr <= 0.0)
   {
      Print("DZV self-test failed invalid zone values");
      return;
   }
   for(int i = 1; i < DZV_ZONE_COUNT; i++)
   {
      if(zones.upper[i] <= zones.upper[i - 1] || zones.lower[i] >= zones.lower[i - 1])
      {
         Print("DZV self-test failed zone ordering");
         return;
      }
   }

   Print("DZV self-test passed for ", symbol,
         " day=", TimeToString(zones.day_start, TIME_DATE),
         " base=", DoubleToString(zones.base_price, _Digits),
         " adr=", DoubleToString(zones.adr, _Digits));
}
