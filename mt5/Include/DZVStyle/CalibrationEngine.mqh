#ifndef DZV_STYLE_CALIBRATION_ENGINE_MQH
#define DZV_STYLE_CALIBRATION_ENGINE_MQH

#include <DZVStyle/ZoneEngine.mqh>

void DZVExportCalibrationRow(const string symbol,
                             const DZVDailyZoneSet &zones,
                             const string sampleName)
{
   int handle = FileOpen("DZVStyle/calibration-output.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return;
   if(FileSize(handle) == 0)
   {
      FileWrite(handle, "sample", "symbol", "day_start", "base_price", "adr",
                "u1", "u2", "u3", "u4", "u5", "u6", "u7",
                "l1", "l2", "l3", "l4", "l5", "l6", "l7");
   }
   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, sampleName, symbol, TimeToString(zones.day_start, TIME_DATE), zones.base_price, zones.adr,
             zones.upper[0], zones.upper[1], zones.upper[2], zones.upper[3], zones.upper[4], zones.upper[5], zones.upper[6],
             zones.lower[0], zones.lower[1], zones.lower[2], zones.lower[3], zones.lower[4], zones.lower[5], zones.lower[6]);
   FileClose(handle);
}

void DZVCompareCalibrationFile(const string symbol, const DZVDailyZoneSet &zones)
{
   int inputHandle = FileOpen("DZVStyle/calibration.csv", FILE_READ | FILE_CSV | FILE_SHARE_READ | FILE_ANSI, ',');
   if(inputHandle == INVALID_HANDLE)
      return;

   int output = FileOpen("DZVStyle/calibration-comparison.csv", FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_ANSI, ',');
   if(output == INVALID_HANDLE)
   {
      FileClose(inputHandle);
      return;
   }
   FileWrite(output, "date", "symbol", "zone", "observed", "calculated", "abs_diff", "points_diff", "pct_adr");

   bool firstRow = true;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   while(!FileIsEnding(inputHandle))
   {
      string dateText = FileReadString(inputHandle);
      if(FileIsEnding(inputHandle))
         break;
      string rowSymbol = FileReadString(inputHandle);
      double observedBase = FileReadNumber(inputHandle);
      double observedUpper[DZV_ZONE_COUNT];
      double observedLower[DZV_ZONE_COUNT];
      for(int i = 0; i < DZV_ZONE_COUNT; i++)
         observedUpper[i] = FileReadNumber(inputHandle);
      for(int i = 0; i < DZV_ZONE_COUNT; i++)
         observedLower[i] = FileReadNumber(inputHandle);

      if(firstRow && StringFind(dateText, "Date") >= 0)
      {
         firstRow = false;
         continue;
      }
      firstRow = false;

      double diffBase = MathAbs(observedBase - zones.base_price);
      FileWrite(output, dateText, rowSymbol, "base", observedBase, zones.base_price, diffBase,
                point > 0.0 ? diffBase / point : 0.0,
                zones.adr > 0.0 ? diffBase / zones.adr * 100.0 : 0.0);
      for(int i = 0; i < DZV_ZONE_COUNT; i++)
      {
         double du = MathAbs(observedUpper[i] - zones.upper[i]);
         double dl = MathAbs(observedLower[i] - zones.lower[i]);
         FileWrite(output, dateText, rowSymbol, StringFormat("U%d", i + 1), observedUpper[i], zones.upper[i], du,
                   point > 0.0 ? du / point : 0.0, zones.adr > 0.0 ? du / zones.adr * 100.0 : 0.0);
         FileWrite(output, dateText, rowSymbol, StringFormat("L%d", i + 1), observedLower[i], zones.lower[i], dl,
                   point > 0.0 ? dl / point : 0.0, zones.adr > 0.0 ? dl / zones.adr * 100.0 : 0.0);
      }
   }

   FileClose(output);
   FileClose(inputHandle);
}

#endif
