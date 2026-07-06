#property strict
#property version   "1.00"
#property indicator_chart_window
#property indicator_plots 0
#property description "Clean-room ADR daily zone visual indicator"

#include <DZVStyle/DailyState.mqh>
#include <DZVStyle/ChartRenderer.mqh>

input string              InpSymbol = "";
input ENUM_DZV_ADR_MODE   InpADRMode = DZV_ADR_HIGH_LOW;
input int                 InpADRPeriod = 14;
input int                 InpMinimumRequiredDailyBars = 30;
input bool                InpExcludeSundayCandle = true;
input bool                InpExcludeAbnormalDailyBars = false;
input double              InpAbnormalRangeMultiplier = 3.0;
input ENUM_DZV_ZONE_BASE  InpZoneBase = DZV_BASE_CURRENT_DAILY_OPEN;

input double              InpZ1UpperMultiplier = 0.25;
input double              InpZ2UpperMultiplier = 0.50;
input double              InpZ3UpperMultiplier = 0.75;
input double              InpZ4UpperMultiplier = 1.00;
input double              InpZ5UpperMultiplier = 1.25;
input double              InpZ6UpperMultiplier = 1.50;
input double              InpZ7UpperMultiplier = 1.75;
input double              InpZ1LowerMultiplier = 0.25;
input double              InpZ2LowerMultiplier = 0.50;
input double              InpZ3LowerMultiplier = 0.75;
input double              InpZ4LowerMultiplier = 1.00;
input double              InpZ5LowerMultiplier = 1.25;
input double              InpZ6LowerMultiplier = 1.50;
input double              InpZ7LowerMultiplier = 1.75;

input bool                InpShowLabels = true;
input bool                InpCompactDashboard = false;
input int                 InpVisibleZoneCount = 7;
input int                 InpLabelOffset = 220;
input int                 InpFontSize = 9;
input color               InpBaseColor = clrGold;
input color               InpUpperColor = clrDeepSkyBlue;
input color               InpLowerColor = clrTomato;
input color               InpDashboardColor = clrWhite;
input int                 InpLineWidth = 1;
input ENUM_LINE_STYLE     InpLineStyle = STYLE_DOT;
input bool                InpDebugMode = false;

DZVDailyState g_indicatorState;
string g_indicatorSymbol = "";

void DZVIndicatorFillMultipliers(double &upper[], double &lower[])
{
   upper[0] = InpZ1UpperMultiplier;
   upper[1] = InpZ2UpperMultiplier;
   upper[2] = InpZ3UpperMultiplier;
   upper[3] = InpZ4UpperMultiplier;
   upper[4] = InpZ5UpperMultiplier;
   upper[5] = InpZ6UpperMultiplier;
   upper[6] = InpZ7UpperMultiplier;
   lower[0] = InpZ1LowerMultiplier;
   lower[1] = InpZ2LowerMultiplier;
   lower[2] = InpZ3LowerMultiplier;
   lower[3] = InpZ4LowerMultiplier;
   lower[4] = InpZ5LowerMultiplier;
   lower[5] = InpZ6LowerMultiplier;
   lower[6] = InpZ7LowerMultiplier;
}

int OnInit()
{
   g_indicatorSymbol = InpSymbol == "" ? _Symbol : InpSymbol;
   DZVDailyStateReset(g_indicatorState);
   EventSetTimer(5);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DZVDeleteChartObjects(g_indicatorSymbol);
}

void DZVRenderIndicator()
{
   double upper[DZV_ZONE_COUNT];
   double lower[DZV_ZONE_COUNT];
   DZVIndicatorFillMultipliers(upper, lower);
   DZVDailyStateEnsure(g_indicatorSymbol, InpADRMode, InpZoneBase, InpADRPeriod, InpMinimumRequiredDailyBars,
                       InpExcludeSundayCandle, InpExcludeAbnormalDailyBars, InpAbnormalRangeMultiplier,
                       upper, lower, InpDebugMode, g_indicatorState);
   DZVRenderZoneSet(g_indicatorSymbol, g_indicatorState.zone_set, InpADRMode, InpZoneBase,
                    InpShowLabels, InpCompactDashboard, InpVisibleZoneCount, InpLabelOffset,
                    InpFontSize, InpBaseColor, InpUpperColor, InpLowerColor, InpDashboardColor,
                    InpLineWidth, InpLineStyle);
}

void OnTimer()
{
   DZVRenderIndicator();
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   DZVRenderIndicator();
   return rates_total;
}
