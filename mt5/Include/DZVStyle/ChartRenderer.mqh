#ifndef DZV_STYLE_CHART_RENDERER_MQH
#define DZV_STYLE_CHART_RENDERER_MQH

#include <DZVStyle/ZoneEngine.mqh>
#include <DZVStyle/IndicatorEngine.mqh>

string DZVObjectPrefix(const string symbol)
{
   return StringFormat("DZVStyle.%s.%I64d.", symbol, ChartID());
}

bool DZVEnsureHLine(const string name,
                    const double price,
                    const color lineColor,
                    const int lineWidth,
                    const ENUM_LINE_STYLE lineStyle)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
         return false;
   }
   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, lineColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, lineWidth);
   ObjectSetInteger(0, name, OBJPROP_STYLE, lineStyle);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   return true;
}

bool DZVEnsureLabel(const string name,
                    const string text,
                    const int corner,
                    const int x,
                    const int y,
                    const color textColor,
                    const int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0))
         return false;
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   return true;
}

void DZVDeleteChartObjects(const string symbol)
{
   string prefix = DZVObjectPrefix(symbol);
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, prefix) == 0)
         ObjectDelete(0, name);
   }
}

void DZVRenderZoneSet(const string symbol,
                      const DZVDailyZoneSet &zones,
                      const ENUM_DZV_ADR_MODE adrMode,
                      const ENUM_DZV_ZONE_BASE baseMode,
                      const bool showLabels,
                      const bool compactDashboard,
                      const int visibleZoneCount,
                      const int labelOffset,
                      const int fontSize,
                      const color baseColor,
                      const color upperColor,
                      const color lowerColor,
                      const color dashboardColor,
                      const int lineWidth,
                      const ENUM_LINE_STYLE lineStyle)
{
   string prefix = DZVObjectPrefix(symbol);
   if(!zones.valid)
   {
      DZVEnsureLabel(prefix + "error", "DZVStyle: " + zones.error, CORNER_LEFT_UPPER, 10, 22, clrTomato, fontSize);
      return;
   }
   ObjectDelete(0, prefix + "error");

   DZVEnsureHLine(prefix + "base", zones.base_price, baseColor, lineWidth, lineStyle);
   int count = MathMax(1, MathMin(DZV_ZONE_COUNT, visibleZoneCount));
   for(int i = 0; i < count; i++)
   {
      DZVEnsureHLine(prefix + StringFormat("U%d", i + 1), zones.upper[i], upperColor, lineWidth, lineStyle);
      DZVEnsureHLine(prefix + StringFormat("L%d", i + 1), zones.lower[i], lowerColor, lineWidth, lineStyle);
   }
   for(int i = count; i < DZV_ZONE_COUNT; i++)
   {
      ObjectDelete(0, prefix + StringFormat("U%d", i + 1));
      ObjectDelete(0, prefix + StringFormat("L%d", i + 1));
   }

   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double currentRange = DZVCurrentDailyRange(symbol);
   double nearestUpper = 0.0;
   double nearestLower = 0.0;
   for(int i = 0; i < DZV_ZONE_COUNT; i++)
   {
      if(zones.upper[i] > bid && (nearestUpper == 0.0 || zones.upper[i] < nearestUpper))
         nearestUpper = zones.upper[i];
      if(zones.lower[i] < bid && (nearestLower == 0.0 || zones.lower[i] > nearestLower))
         nearestLower = zones.lower[i];
   }
   double upperDistance = (nearestUpper > 0.0 && point > 0.0) ? (nearestUpper - bid) / point : 0.0;
   double lowerDistance = (nearestLower > 0.0 && point > 0.0) ? (bid - nearestLower) / point : 0.0;
   double adrUsage = zones.adr > 0.0 ? currentRange / zones.adr * 100.0 : 0.0;

   string dashboard = compactDashboard
      ? StringFormat("DZV %s ADR %.1f%% U %.0f L %.0f", DZVTimeframeName((ENUM_TIMEFRAMES)Period()), adrUsage, upperDistance, lowerDistance)
      : StringFormat("DZVStyle %s\nDay: %s\nBase: %.5f\nADR: %.5f %s\nRange: %.5f (%.1f%% ADR)\nRoom Up: %.0f pts\nRoom Down: %.0f pts\nBase mode: %s",
                     symbol,
                     TimeToString(zones.day_start, TIME_DATE),
                     zones.base_price,
                     zones.adr,
                     DZVAdrModeName(adrMode),
                     currentRange,
                     adrUsage,
                     upperDistance,
                     lowerDistance,
                     DZVBaseModeName(baseMode));
   DZVEnsureLabel(prefix + "dashboard", dashboard, CORNER_RIGHT_UPPER, labelOffset, 20, dashboardColor, fontSize);

   if(showLabels)
   {
      for(int i = 0; i < count; i++)
      {
         DZVEnsureLabel(prefix + StringFormat("labelU%d", i + 1),
                        StringFormat("U%d %.5f", i + 1, zones.upper[i]),
                        CORNER_RIGHT_UPPER, labelOffset, 120 + i * (fontSize + 8), upperColor, fontSize);
         DZVEnsureLabel(prefix + StringFormat("labelL%d", i + 1),
                        StringFormat("L%d %.5f", i + 1, zones.lower[i]),
                        CORNER_RIGHT_UPPER, labelOffset, 120 + (i + count) * (fontSize + 8), lowerColor, fontSize);
      }
   }
}

void DZVRenderTfDashboard(const string symbol,
                          const DZVIndicatorHandles &handles,
                          const double rsiSidewaysLower,
                          const double rsiSidewaysUpper,
                          const int labelOffset,
                          const int startY,
                          const color textColor,
                          const int fontSize)
{
   string prefix = DZVObjectPrefix(symbol);
   string text = "TF  Trend  RSI  Stoch\n";
   for(int i = 0; i < handles.count; i++)
   {
      DZVIndicatorSnapshot snap;
      DZVIndicatorSnapshotAt(handles, i, rsiSidewaysLower, rsiSidewaysUpper, snap);
      string trend = "NA";
      if(snap.trend == DZV_TREND_UP)
         trend = "UP";
      else if(snap.trend == DZV_TREND_DOWN)
         trend = "DOWN";
      else if(snap.trend == DZV_TREND_SIDEWAY)
         trend = "SIDE";
      text += StringFormat("%s  %s  %.1f  %.1f/%.1f\n",
                           DZVTimeframeName(handles.timeframes[i]),
                           trend,
                           snap.ready ? snap.rsi : 0.0,
                           snap.ready ? snap.stoch_k : 0.0,
                           snap.ready ? snap.stoch_d : 0.0);
   }
   DZVEnsureLabel(prefix + "tf_dashboard", text, CORNER_RIGHT_UPPER, labelOffset, startY, textColor, fontSize);
}

#endif
