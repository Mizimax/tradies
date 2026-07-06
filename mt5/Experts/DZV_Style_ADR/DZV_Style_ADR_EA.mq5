#property strict
#property version   "1.00"
#property description "Clean-room ADR daily-zone signal and simulation EA"

#include <Trade/Trade.mqh>
#include <DZVStyle/DailyState.mqh>
#include <DZVStyle/SignalEngine.mqh>
#include <DZVStyle/TradeExecutor.mqh>
#include <DZVStyle/ChartRenderer.mqh>
#include <DZVStyle/CalibrationEngine.mqh>
#include <DZVStyle/AlertManager.mqh>

input string                 InpSymbol = "XAUUSD";
input long                   InpMagicNumber = 26070101;
input ENUM_DZV_SYSTEM_MODE   InpSystemMode = DZV_MODE_SIGNAL_ONLY;
input bool                   InpAllowLiveOrderExecution = false;
input ENUM_TIMEFRAMES        InpEntryTimeframe = PERIOD_M15;
input ENUM_TIMEFRAMES        InpTrendFilterTimeframe = PERIOD_H1;
input ENUM_DZV_SIGNAL_MODULE InpSignalModule = DZV_SIGNAL_BOTH;

input ENUM_DZV_ADR_MODE      InpADRMode = DZV_ADR_HIGH_LOW;
input int                    InpADRPeriod = 14;
input int                    InpMinimumRequiredDailyBars = 30;
input bool                   InpExcludeSundayCandle = true;
input bool                   InpExcludeAbnormalDailyBars = false;
input double                 InpAbnormalRangeMultiplier = 3.0;
input ENUM_DZV_ZONE_BASE     InpZoneBase = DZV_BASE_CURRENT_DAILY_OPEN;

input double                 InpZ1UpperMultiplier = 0.25;
input double                 InpZ2UpperMultiplier = 0.50;
input double                 InpZ3UpperMultiplier = 0.75;
input double                 InpZ4UpperMultiplier = 1.00;
input double                 InpZ5UpperMultiplier = 1.25;
input double                 InpZ6UpperMultiplier = 1.50;
input double                 InpZ7UpperMultiplier = 1.75;
input double                 InpZ1LowerMultiplier = 0.25;
input double                 InpZ2LowerMultiplier = 0.50;
input double                 InpZ3LowerMultiplier = 0.75;
input double                 InpZ4LowerMultiplier = 1.00;
input double                 InpZ5LowerMultiplier = 1.25;
input double                 InpZ6LowerMultiplier = 1.50;
input double                 InpZ7LowerMultiplier = 1.75;

input int                    InpEmaPeriod = 50;
input int                    InpRsiPeriod = 14;
input double                 InpRsiSidewaysLower = 45.0;
input double                 InpRsiSidewaysUpper = 55.0;
input double                 InpRsiOverbought = 70.0;
input double                 InpRsiOversold = 30.0;
input double                 InpRsiLongMax = 45.0;
input double                 InpRsiShortMin = 55.0;
input int                    InpStochKPeriod = 14;
input int                    InpStochDPeriod = 3;
input int                    InpStochSlowing = 3;
input double                 InpStochOverbought = 80.0;
input double                 InpStochOversold = 20.0;

input ENUM_DZV_STOP_MODE     InpStopMode = DZV_STOP_BEYOND_SIGNAL_CANDLE;
input ENUM_DZV_TARGET_MODE   InpTargetMode = DZV_TARGET_RISK_REWARD;
input int                    InpSelectedTargetZone = 1;
input double                 InpRiskReward = 1.5;
input double                 InpStopBufferPoints = 50.0;
input double                 InpVolatilityStopAdrFraction = 0.25;
input double                 InpMinimumAllowedStopPoints = 50.0;
input double                 InpMaximumAllowedStopPoints = 3000.0;

input ENUM_DZV_LOT_MODE      InpLotMode = DZV_LOT_RISK_PERCENT;
input double                 InpFixedLot = 0.01;
input double                 InpRiskPercent = 0.25;
input double                 InpMinimumLot = 0.01;
input double                 InpMaximumLot = 5.0;

input double                 InpMaximumSpreadPoints = 250.0;
input int                    InpMaxOpenProjectPositions = 1;
input int                    InpMaxSignalsPerDay = 10;
input int                    InpMaxTradesPerDay = 5;
input int                    InpTradingStartHour = 0;
input int                    InpTradingEndHour = 24;
input bool                   InpEnableFridayCutoff = true;
input int                    InpFridayCutoffHour = 20;
input double                 InpMinimumADR = 0.0;
input double                 InpMaximumADR = 0.0;
input double                 InpMaximumDailyAdrUsagePct = 120.0;
input double                 InpMinimumRemainingTargetPoints = 50.0;

input bool                   InpUseZoneBandOrders = false;
input int                    InpZoneBandNumber = 2;
input double                 InpZoneBandStopPriceDistance = 10.0;
input double                 InpZoneBandTargetPriceDistance = 15.0;
input bool                   InpZoneBandAllowLong = true;
input bool                   InpZoneBandAllowShort = true;
input bool                   InpZoneBandAllowLongEdge1 = true;
input bool                   InpZoneBandAllowLongEdge2 = true;
input bool                   InpZoneBandAllowShortEdge1 = true;
input bool                   InpZoneBandAllowShortEdge2 = true;
input bool                   InpZoneBandUseTrendFilter = false;
input bool                   InpZoneBandUseAdrUsageFilter = false;
input double                 InpZoneBandMaximumDailyAdrUsagePct = 100.0;
input bool                   InpZoneBandUseReversalFilter = false;
input double                 InpZoneBandLongMinRsi = 30.0;
input double                 InpZoneBandShortMaxRsi = 70.0;
input bool                   InpZoneBandRequireStochTurn = true;

input bool                   InpShowChartObjects = true;
input bool                   InpShowLabels = true;
input bool                   InpCompactDashboard = false;
input int                    InpVisibleZoneCount = 7;
input int                    InpLabelOffset = 220;
input int                    InpFontSize = 9;
input color                  InpBaseColor = clrGold;
input color                  InpUpperColor = clrDeepSkyBlue;
input color                  InpLowerColor = clrTomato;
input color                  InpDashboardColor = clrWhite;
input int                    InpLineWidth = 1;
input ENUM_LINE_STYLE        InpLineStyle = STYLE_DOT;

input bool                   InpTerminalAlerts = false;
input bool                   InpPushNotifications = false;
input bool                   InpEmailNotifications = false;
input bool                   InpExportCalibration = false;
input bool                   InpCompareCalibrationFile = false;
input bool                   InpResetJournalOnInit = true;
input bool                   InpDebugMode = false;

CTrade g_dzvTrade;
DZVDailyState g_dzvState;
DZVIndicatorHandles g_dzvIndicators;
DZVSimTrade g_dzvSimTrade;
DZVZoneBandOrder g_dzvBandOrders[4];
datetime g_dzvLastCompletedBar = 0;
datetime g_dzvLastBandDay = 0;
string g_dzvSymbol = "";

void DZVFillMultipliers(double &upper[], double &lower[])
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

int DZVDailyCounter(const string suffix)
{
   string key = StringFormat("%s.%I64d.%s.%I64d", DZVGlobalPrefix(g_dzvSymbol, InpMagicNumber), (long)DZVDayStart(g_dzvSymbol), suffix, InpMagicNumber);
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

void DZVIncrementDailyCounter(const string suffix)
{
   string key = StringFormat("%s.%I64d.%s.%I64d", DZVGlobalPrefix(g_dzvSymbol, InpMagicNumber), (long)DZVDayStart(g_dzvSymbol), suffix, InpMagicNumber);
   int current = GlobalVariableCheck(key) ? (int)GlobalVariableGet(key) : 0;
   GlobalVariableSet(key, (double)(current + 1));
}

bool DZVEntryRiskAllowed(const DZVDailyZoneSet &zones, string &reason)
{
   reason = "";
   if(!zones.valid)
   {
      reason = "invalid_zones";
      return false;
   }
   if(InpMinimumADR > 0.0 && zones.adr < InpMinimumADR)
   {
      reason = "adr_too_low";
      return false;
   }
   if(InpMaximumADR > 0.0 && zones.adr > InpMaximumADR)
   {
      reason = "adr_too_high";
      return false;
   }
   if(InpMaximumSpreadPoints > 0.0 && DZVSpreadPoints(g_dzvSymbol) > InpMaximumSpreadPoints)
   {
      reason = "spread";
      return false;
   }
   if(!DZVTradingSessionAllowed(InpTradingStartHour, InpTradingEndHour))
   {
      reason = "session";
      return false;
   }
   if(!DZVFridayCutoffAllowed(InpEnableFridayCutoff, InpFridayCutoffHour))
   {
      reason = "friday_cutoff";
      return false;
   }
   if(InpMaxSignalsPerDay > 0 && DZVDailyCounter("signals") >= InpMaxSignalsPerDay)
   {
      reason = "signal_limit";
      return false;
   }
   if(InpMaxTradesPerDay > 0 && DZVDailyCounter("trades") >= InpMaxTradesPerDay)
   {
      reason = "trade_limit";
      return false;
   }
   if(InpMaxOpenProjectPositions > 0 && DZVCountOpenProjectPositions(g_dzvSymbol, InpMagicNumber) >= InpMaxOpenProjectPositions)
   {
      reason = "max_open_positions";
      return false;
   }
   return true;
}

double DZVCurrentDailyAdrUsagePct(const string symbol, const DZVDailyZoneSet &zones)
{
   if(!zones.valid || zones.adr <= 0.0)
      return 0.0;

   MqlRates d1[];
   ArraySetAsSeries(d1, true);
   if(CopyRates(symbol, PERIOD_D1, 0, 1, d1) != 1)
      return 0.0;

   return MathAbs(d1[0].high - d1[0].low) / zones.adr * 100.0;
}

bool DZVZoneBandEntryAllowed(const ENUM_DZV_DIRECTION direction,
                             const DZVDailyZoneSet &zones,
                             string &reason)
{
   reason = "";
   if(!zones.valid)
   {
      reason = "invalid_zones";
      return false;
   }

   if(InpZoneBandUseAdrUsageFilter && InpZoneBandMaximumDailyAdrUsagePct > 0.0)
   {
      double adrUsagePct = DZVCurrentDailyAdrUsagePct(g_dzvSymbol, zones);
      if(adrUsagePct > InpZoneBandMaximumDailyAdrUsagePct)
      {
         reason = StringFormat("adr_usage,usage=%.1f,max=%.1f", adrUsagePct, InpZoneBandMaximumDailyAdrUsagePct);
         return false;
      }
   }

   DZVIndicatorSnapshot entrySnapshot;
   DZVIndicatorSnapshot trendSnapshot;
   bool hasEntry = DZVIndicatorSnapshotForTf(g_dzvIndicators, InpEntryTimeframe,
                                             InpRsiSidewaysLower, InpRsiSidewaysUpper,
                                             entrySnapshot);
   bool hasTrend = DZVIndicatorSnapshotForTf(g_dzvIndicators, InpTrendFilterTimeframe,
                                             InpRsiSidewaysLower, InpRsiSidewaysUpper,
                                             trendSnapshot);

   if(InpZoneBandUseTrendFilter)
   {
      if(!hasTrend || !trendSnapshot.ready)
      {
         reason = "trend_unavailable";
         return false;
      }
      if(direction == DZV_DIR_LONG && trendSnapshot.close < trendSnapshot.ema50)
      {
         reason = StringFormat("trend_down,tf=%s,close=%.5f,ema=%.5f",
                               DZVTimeframeName(InpTrendFilterTimeframe),
                               trendSnapshot.close, trendSnapshot.ema50);
         return false;
      }
      if(direction == DZV_DIR_SHORT && trendSnapshot.close > trendSnapshot.ema50)
      {
         reason = StringFormat("trend_up,tf=%s,close=%.5f,ema=%.5f",
                               DZVTimeframeName(InpTrendFilterTimeframe),
                               trendSnapshot.close, trendSnapshot.ema50);
         return false;
      }
   }

   if(InpZoneBandUseReversalFilter)
   {
      if(!hasEntry || !entrySnapshot.ready)
      {
         reason = "entry_indicators_unavailable";
         return false;
      }

      if(direction == DZV_DIR_LONG)
      {
         if(entrySnapshot.rsi < InpZoneBandLongMinRsi)
         {
            reason = StringFormat("long_rsi_low,rsi=%.1f,min=%.1f", entrySnapshot.rsi, InpZoneBandLongMinRsi);
            return false;
         }
         if(InpZoneBandRequireStochTurn && entrySnapshot.stoch_k < entrySnapshot.stoch_d)
         {
            reason = StringFormat("long_stoch_not_turning,k=%.1f,d=%.1f", entrySnapshot.stoch_k, entrySnapshot.stoch_d);
            return false;
         }
      }
      else if(direction == DZV_DIR_SHORT)
      {
         if(entrySnapshot.rsi > InpZoneBandShortMaxRsi)
         {
            reason = StringFormat("short_rsi_high,rsi=%.1f,max=%.1f", entrySnapshot.rsi, InpZoneBandShortMaxRsi);
            return false;
         }
         if(InpZoneBandRequireStochTurn && entrySnapshot.stoch_k > entrySnapshot.stoch_d)
         {
            reason = StringFormat("short_stoch_not_turning,k=%.1f,d=%.1f", entrySnapshot.stoch_k, entrySnapshot.stoch_d);
            return false;
         }
      }
   }

   return true;
}

int OnInit()
{
   g_dzvSymbol = InpSymbol == "" ? _Symbol : InpSymbol;
   if(!SymbolSelect(g_dzvSymbol, true))
   {
      Print("DZVStyle: unable to select symbol ", g_dzvSymbol);
      return INIT_FAILED;
   }

   DZVDailyStateReset(g_dzvState);
   DZVSimTradeReset(g_dzvSimTrade);
   for(int i = 0; i < ArraySize(g_dzvBandOrders); i++)
      DZVZoneBandOrderReset(g_dzvBandOrders[i]);
   if(InpResetJournalOnInit)
      DZVResetJournal();

   ENUM_TIMEFRAMES timeframes[DZV_MAX_TF_COUNT] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
   if(!DZVIndicatorHandlesInit(g_dzvIndicators, g_dzvSymbol, timeframes, DZV_MAX_TF_COUNT,
                               InpEmaPeriod, InpRsiPeriod, InpStochKPeriod, InpStochDPeriod, InpStochSlowing))
      return INIT_FAILED;

   EventSetTimer(5);
   DZVJournal("init,mode=" + EnumToString(InpSystemMode) + ",symbol=" + g_dzvSymbol);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   DZVIndicatorHandlesRelease(g_dzvIndicators);
   DZVDeleteChartObjects(g_dzvSymbol);
}

void OnTimer()
{
   double upper[DZV_ZONE_COUNT];
   double lower[DZV_ZONE_COUNT];
   DZVFillMultipliers(upper, lower);
   DZVDailyStateEnsure(g_dzvSymbol, InpADRMode, InpZoneBase, InpADRPeriod, InpMinimumRequiredDailyBars,
                       InpExcludeSundayCandle, InpExcludeAbnormalDailyBars, InpAbnormalRangeMultiplier,
                       upper, lower, InpDebugMode, g_dzvState);
   if(InpShowChartObjects)
   {
      DZVRenderZoneSet(g_dzvSymbol, g_dzvState.zone_set, InpADRMode, InpZoneBase, InpShowLabels,
                       InpCompactDashboard, InpVisibleZoneCount, InpLabelOffset, InpFontSize,
                       InpBaseColor, InpUpperColor, InpLowerColor, InpDashboardColor,
                       InpLineWidth, InpLineStyle);
      DZVRenderTfDashboard(g_dzvSymbol, g_dzvIndicators, InpRsiSidewaysLower, InpRsiSidewaysUpper,
                           InpLabelOffset, 260, InpDashboardColor, InpFontSize);
   }
   if(g_dzvState.zone_set.valid && InpExportCalibration)
      DZVExportCalibrationRow(g_dzvSymbol, g_dzvState.zone_set, "current");
   if(g_dzvState.zone_set.valid && InpCompareCalibrationFile)
      DZVCompareCalibrationFile(g_dzvSymbol, g_dzvState.zone_set);
}

void OnTick()
{
   double upper[DZV_ZONE_COUNT];
   double lower[DZV_ZONE_COUNT];
   DZVFillMultipliers(upper, lower);
   if(!DZVDailyStateEnsure(g_dzvSymbol, InpADRMode, InpZoneBase, InpADRPeriod, InpMinimumRequiredDailyBars,
                           InpExcludeSundayCandle, InpExcludeAbnormalDailyBars, InpAbnormalRangeMultiplier,
                           upper, lower, InpDebugMode, g_dzvState))
   {
      DZVEmitAlert("invalid_zones", "DZVStyle invalid zone configuration: " + g_dzvState.zone_set.error,
                   InpTerminalAlerts, InpPushNotifications, InpEmailNotifications);
      return;
   }

   if(InpSystemMode == DZV_MODE_SIMULATED_TRADING)
   {
         if(InpUseZoneBandOrders)
         {
         if(g_dzvState.zone_set.valid && g_dzvLastBandDay != g_dzvState.zone_set.day_start)
         {
            DZVZoneBandPlaceDaily(g_dzvBandOrders, g_dzvSymbol, g_dzvState.zone_set,
                                  InpZoneBandNumber,
                                  InpZoneBandStopPriceDistance,
                                  InpZoneBandTargetPriceDistance,
                                  InpZoneBandAllowLong,
                                  InpZoneBandAllowShort,
                                  InpZoneBandAllowLongEdge1,
                                  InpZoneBandAllowLongEdge2,
                                  InpZoneBandAllowShortEdge1,
                                  InpZoneBandAllowShortEdge2);
            g_dzvLastBandDay = g_dzvState.zone_set.day_start;
         }
         string longBlockReason = "";
         string shortBlockReason = "";
         bool allowLongFill = DZVZoneBandEntryAllowed(DZV_DIR_LONG, g_dzvState.zone_set, longBlockReason);
         bool allowShortFill = DZVZoneBandEntryAllowed(DZV_DIR_SHORT, g_dzvState.zone_set, shortBlockReason);
         DZVZoneBandManage(g_dzvBandOrders, g_dzvSymbol,
                           allowLongFill, allowShortFill,
                           longBlockReason, shortBlockReason);
         return;
      }
      DZVSimManage(g_dzvSimTrade, g_dzvSymbol);
   }

   if(InpSystemMode == DZV_MODE_INDICATOR_ONLY)
      return;

   if(!DZVIsNewCompletedBar(g_dzvSymbol, InpEntryTimeframe, g_dzvLastCompletedBar))
      return;

   DZVIndicatorSnapshot entrySnapshot;
   DZVIndicatorSnapshot trendSnapshot;
   if(!DZVIndicatorSnapshotForTf(g_dzvIndicators, InpEntryTimeframe, InpRsiSidewaysLower, InpRsiSidewaysUpper, entrySnapshot))
   {
      DZVJournal("block,indicator_entry," + entrySnapshot.status);
      return;
   }
   DZVIndicatorSnapshotForTf(g_dzvIndicators, InpTrendFilterTimeframe, InpRsiSidewaysLower, InpRsiSidewaysUpper, trendSnapshot);

   string blockReason = "";
   if(!DZVEntryRiskAllowed(g_dzvState.zone_set, blockReason))
   {
      DZVJournal("block," + blockReason);
      return;
   }

   DZVSignal signal;
   signal.valid = false;
   bool found = false;
   if(InpSignalModule == DZV_SIGNAL_REJECTION || InpSignalModule == DZV_SIGNAL_BOTH)
   {
      found = DZVBuildRejectionSignal(g_dzvSymbol, InpEntryTimeframe, g_dzvState.zone_set,
                                      entrySnapshot, trendSnapshot, InpRsiLongMax, InpRsiShortMin,
                                      InpStochOversold, InpStochOverbought, InpMaximumDailyAdrUsagePct,
                                      InpStopMode, InpTargetMode, InpSelectedTargetZone,
                                      InpStopBufferPoints, InpVolatilityStopAdrFraction,
                                      InpRiskReward, signal);
   }
   if(!found && (InpSignalModule == DZV_SIGNAL_BREAKOUT || InpSignalModule == DZV_SIGNAL_BOTH))
   {
      found = DZVBuildBreakoutSignal(g_dzvSymbol, InpEntryTimeframe, g_dzvState.zone_set,
                                     entrySnapshot, trendSnapshot, InpRsiSidewaysUpper, InpRsiSidewaysLower,
                                     InpRsiOverbought, InpRsiOversold, 0.0, InpStopMode,
                                     InpTargetMode, InpSelectedTargetZone, InpStopBufferPoints,
                                     InpVolatilityStopAdrFraction, InpRiskReward, signal);
   }
   if(!found || !signal.valid)
   {
      if(InpDebugMode)
         DZVJournal("skip," + signal.reason);
      return;
   }
   if(DZVSignalProcessed(signal.id))
   {
      DZVJournal("skip,duplicate," + signal.id);
      return;
   }

   string stopReason = "";
   if(!DZVStopsValid(g_dzvSymbol, signal.direction, signal.entry_price, signal.stop_loss, signal.take_profit,
                     InpMinimumAllowedStopPoints, InpMaximumAllowedStopPoints, stopReason))
   {
      DZVJournal("block,invalid_stops," + stopReason + ",id=" + signal.id);
      DZVMarkSignalProcessed(signal.id);
      return;
   }

   double point = SymbolInfoDouble(g_dzvSymbol, SYMBOL_POINT);
   double targetDistance = point > 0.0 ? MathAbs(signal.take_profit - signal.entry_price) / point : 0.0;
   if(InpMinimumRemainingTargetPoints > 0.0 && targetDistance < InpMinimumRemainingTargetPoints)
   {
      DZVJournal("block,target_too_close,id=" + signal.id);
      DZVMarkSignalProcessed(signal.id);
      return;
   }

   DZVMarkSignalProcessed(signal.id);
   DZVIncrementDailyCounter("signals");
   DZVJournal(StringFormat("signal,id=%s,module=%s,dir=%s,zone=Z%d,entry=%.5f,sl=%.5f,tp=%.5f,risk_points=%.1f",
                           signal.id, DZVModuleName(signal.module), DZVDirectionName(signal.direction),
                           signal.zone_index + 1, signal.entry_price, signal.stop_loss, signal.take_profit,
                           signal.risk_points));

   if(InpSystemMode == DZV_MODE_SIGNAL_ONLY)
      return;
   if(InpSystemMode == DZV_MODE_SIMULATED_TRADING)
   {
      if(DZVSimOpen(g_dzvSimTrade, signal))
         DZVIncrementDailyCounter("trades");
      return;
   }
   if(InpSystemMode == DZV_MODE_LIVE_TRADING)
   {
      if(!InpAllowLiveOrderExecution)
      {
         DZVJournal("block,live_flag_disabled,id=" + signal.id);
         return;
      }
      double volume = DZVCalculateLot(g_dzvSymbol, InpLotMode, InpFixedLot, InpRiskPercent,
                                      signal.entry_price, signal.stop_loss, InpMinimumLot, InpMaximumLot);
      string result = "";
      if(DZVExecuteLive(g_dzvTrade, g_dzvSymbol, InpMagicNumber, 20, signal, volume, result))
         DZVIncrementDailyCounter("trades");
   }
}
