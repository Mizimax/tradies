#ifndef DZV_STYLE_SIGNAL_ENGINE_MQH
#define DZV_STYLE_SIGNAL_ENGINE_MQH

#include <DZVStyle/IndicatorEngine.mqh>
#include <DZVStyle/RiskManager.mqh>

bool DZVSignalProcessed(const string signalId)
{
   string key = "DZVStyle.signal." + signalId;
   return GlobalVariableCheck(key);
}

void DZVMarkSignalProcessed(const string signalId)
{
   string key = "DZVStyle.signal." + signalId;
   GlobalVariableSet(key, (double)TimeCurrent());
}

string DZVBuildSignalId(const string symbol,
                        const ENUM_TIMEFRAMES entryTimeframe,
                        const datetime brokerDay,
                        const datetime signalCandle,
                        const ENUM_DZV_DIRECTION direction,
                        const int zoneIndex,
                        const ENUM_DZV_SIGNAL_MODULE module)
{
   return StringFormat("%s.%s.%I64d.%I64d.%s.Z%d.%s",
                       symbol,
                       DZVTimeframeName(entryTimeframe),
                       (long)brokerDay,
                       (long)signalCandle,
                       DZVDirectionName(direction),
                       zoneIndex + 1,
                       DZVModuleName(module));
}

double DZVZoneOuterStop(const DZVDailyZoneSet &zones,
                        const ENUM_DZV_DIRECTION direction,
                        const int zoneIndex,
                        const double fallback)
{
   if(direction == DZV_DIR_LONG)
   {
      int outer = MathMin(DZV_ZONE_COUNT - 1, zoneIndex + 1);
      return zones.lower[outer] > 0.0 ? zones.lower[outer] : fallback;
   }
   if(direction == DZV_DIR_SHORT)
   {
      int outer = MathMin(DZV_ZONE_COUNT - 1, zoneIndex + 1);
      return zones.upper[outer] > 0.0 ? zones.upper[outer] : fallback;
   }
   return fallback;
}

double DZVTargetFromMode(const string symbol,
                         const DZVDailyZoneSet &zones,
                         const ENUM_DZV_DIRECTION direction,
                         const int zoneIndex,
                         const double entry,
                         const double stopLoss,
                         const ENUM_DZV_TARGET_MODE targetMode,
                         const int selectedTargetZone,
                         const double riskReward)
{
   double risk = MathAbs(entry - stopLoss);
   if(direction == DZV_DIR_LONG)
   {
      if(targetMode == DZV_TARGET_BASE_PRICE && zones.base_price > entry)
         return DZVNormalizePrice(symbol, zones.base_price);
      if(targetMode == DZV_TARGET_NEXT_INNER_ZONE && zoneIndex > 0)
         return DZVNormalizePrice(symbol, zones.lower[zoneIndex - 1]);
      if(targetMode == DZV_TARGET_NEXT_OUTER_ZONE)
         return DZVNormalizePrice(symbol, zones.upper[MathMin(DZV_ZONE_COUNT - 1, zoneIndex + 1)]);
      if(targetMode == DZV_TARGET_SELECTED_ZONE)
      {
         int index = MathMax(0, MathMin(DZV_ZONE_COUNT - 1, selectedTargetZone - 1));
         return DZVNormalizePrice(symbol, zones.upper[index]);
      }
      return DZVNormalizePrice(symbol, entry + risk * riskReward);
   }
   if(direction == DZV_DIR_SHORT)
   {
      if(targetMode == DZV_TARGET_BASE_PRICE && zones.base_price < entry)
         return DZVNormalizePrice(symbol, zones.base_price);
      if(targetMode == DZV_TARGET_NEXT_INNER_ZONE && zoneIndex > 0)
         return DZVNormalizePrice(symbol, zones.upper[zoneIndex - 1]);
      if(targetMode == DZV_TARGET_NEXT_OUTER_ZONE)
         return DZVNormalizePrice(symbol, zones.lower[MathMin(DZV_ZONE_COUNT - 1, zoneIndex + 1)]);
      if(targetMode == DZV_TARGET_SELECTED_ZONE)
      {
         int index = MathMax(0, MathMin(DZV_ZONE_COUNT - 1, selectedTargetZone - 1));
         return DZVNormalizePrice(symbol, zones.lower[index]);
      }
      return DZVNormalizePrice(symbol, entry - risk * riskReward);
   }
   return 0.0;
}

bool DZVBuildStopsAndTarget(const string symbol,
                            const DZVDailyZoneSet &zones,
                            const MqlRates &signalCandle,
                            const ENUM_DZV_DIRECTION direction,
                            const int zoneIndex,
                            const double entry,
                            const ENUM_DZV_STOP_MODE stopMode,
                            const ENUM_DZV_TARGET_MODE targetMode,
                            const int selectedTargetZone,
                            const double stopBufferPoints,
                            const double volatilityStopAdrFraction,
                            const double riskReward,
                            double &stopLoss,
                            double &takeProfit)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return false;
   double buffer = stopBufferPoints * point;
   double rawStop = 0.0;

   if(direction == DZV_DIR_LONG)
   {
      if(stopMode == DZV_STOP_BEYOND_SIGNAL_CANDLE)
         rawStop = signalCandle.low - buffer;
      else if(stopMode == DZV_STOP_BEYOND_SIGNAL_ZONE)
         rawStop = zones.lower[zoneIndex] - buffer;
      else if(stopMode == DZV_STOP_AT_NEXT_OUTER_ZONE)
         rawStop = DZVZoneOuterStop(zones, direction, zoneIndex, signalCandle.low) - buffer;
      else
         rawStop = entry - zones.adr * volatilityStopAdrFraction;
   }
   else if(direction == DZV_DIR_SHORT)
   {
      if(stopMode == DZV_STOP_BEYOND_SIGNAL_CANDLE)
         rawStop = signalCandle.high + buffer;
      else if(stopMode == DZV_STOP_BEYOND_SIGNAL_ZONE)
         rawStop = zones.upper[zoneIndex] + buffer;
      else if(stopMode == DZV_STOP_AT_NEXT_OUTER_ZONE)
         rawStop = DZVZoneOuterStop(zones, direction, zoneIndex, signalCandle.high) + buffer;
      else
         rawStop = entry + zones.adr * volatilityStopAdrFraction;
   }
   else
      return false;

   stopLoss = DZVNormalizePrice(symbol, rawStop);
   takeProfit = DZVTargetFromMode(symbol, zones, direction, zoneIndex, entry, stopLoss,
                                  targetMode, selectedTargetZone, riskReward);
   return stopLoss > 0.0 && takeProfit > 0.0;
}

bool DZVBuildRejectionSignal(const string symbol,
                             const ENUM_TIMEFRAMES entryTimeframe,
                             const DZVDailyZoneSet &zones,
                             const DZVIndicatorSnapshot &entrySnapshot,
                             const DZVIndicatorSnapshot &trendSnapshot,
                             const double rsiLongMax,
                             const double rsiShortMin,
                             const double stochOversold,
                             const double stochOverbought,
                             const double maxDailyAdrUsagePct,
                             const ENUM_DZV_STOP_MODE stopMode,
                             const ENUM_DZV_TARGET_MODE targetMode,
                             const int selectedTargetZone,
                             const double stopBufferPoints,
                             const double volatilityStopAdrFraction,
                             const double riskReward,
                             DZVSignal &signal)
{
   signal.valid = false;
   signal.reason = "no_rejection";
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, entryTimeframe, 1, 3, rates) < 3)
   {
      signal.reason = "rates_unavailable";
      return false;
   }

   double currentRange = DZVCurrentDailyRange(symbol);
   if(zones.adr > 0.0 && maxDailyAdrUsagePct > 0.0 && currentRange / zones.adr * 100.0 > maxDailyAdrUsagePct)
   {
      signal.reason = "daily_adr_usage";
      return false;
   }

   for(int i = 0; i < DZV_ZONE_COUNT; i++)
   {
      if(rates[0].low <= zones.lower[i] && rates[0].close > zones.lower[i])
      {
         if(entrySnapshot.rsi > rsiLongMax)
         {
            signal.reason = "long_rsi";
            continue;
         }
         if(entrySnapshot.stoch_k > stochOversold && rates[1].close <= zones.lower[i])
         {
            signal.reason = "long_stoch";
            continue;
         }
         if(!(entrySnapshot.stoch_k > entrySnapshot.stoch_d))
         {
            signal.reason = "long_stoch_cross";
            continue;
         }
         if(trendSnapshot.ready && trendSnapshot.trend == DZV_TREND_DOWN)
         {
            signal.reason = "long_trend_down";
            continue;
         }

         signal.valid = true;
         signal.direction = DZV_DIR_LONG;
         signal.module = DZV_SIGNAL_REJECTION;
         signal.zone_index = i;
         signal.broker_day = zones.day_start;
         signal.candle_time = rates[0].time;
         signal.zone_price = zones.lower[i];
         signal.entry_price = rates[0].close;
         DZVBuildStopsAndTarget(symbol, zones, rates[0], signal.direction, i, signal.entry_price,
                                stopMode, targetMode, selectedTargetZone, stopBufferPoints,
                                volatilityStopAdrFraction, riskReward, signal.stop_loss, signal.take_profit);
         signal.risk_points = MathAbs(signal.entry_price - signal.stop_loss) / SymbolInfoDouble(symbol, SYMBOL_POINT);
         signal.id = DZVBuildSignalId(symbol, entryTimeframe, zones.day_start, rates[0].time, signal.direction, i, signal.module);
         signal.reason = "long_rejection";
         return true;
      }

      if(rates[0].high >= zones.upper[i] && rates[0].close < zones.upper[i])
      {
         if(entrySnapshot.rsi < rsiShortMin)
         {
            signal.reason = "short_rsi";
            continue;
         }
         if(entrySnapshot.stoch_k < stochOverbought && rates[1].close >= zones.upper[i])
         {
            signal.reason = "short_stoch";
            continue;
         }
         if(!(entrySnapshot.stoch_k < entrySnapshot.stoch_d))
         {
            signal.reason = "short_stoch_cross";
            continue;
         }
         if(trendSnapshot.ready && trendSnapshot.trend == DZV_TREND_UP)
         {
            signal.reason = "short_trend_up";
            continue;
         }

         signal.valid = true;
         signal.direction = DZV_DIR_SHORT;
         signal.module = DZV_SIGNAL_REJECTION;
         signal.zone_index = i;
         signal.broker_day = zones.day_start;
         signal.candle_time = rates[0].time;
         signal.zone_price = zones.upper[i];
         signal.entry_price = rates[0].close;
         DZVBuildStopsAndTarget(symbol, zones, rates[0], signal.direction, i, signal.entry_price,
                                stopMode, targetMode, selectedTargetZone, stopBufferPoints,
                                volatilityStopAdrFraction, riskReward, signal.stop_loss, signal.take_profit);
         signal.risk_points = MathAbs(signal.entry_price - signal.stop_loss) / SymbolInfoDouble(symbol, SYMBOL_POINT);
         signal.id = DZVBuildSignalId(symbol, entryTimeframe, zones.day_start, rates[0].time, signal.direction, i, signal.module);
         signal.reason = "short_rejection";
         return true;
      }
   }
   return false;
}

bool DZVBuildBreakoutSignal(const string symbol,
                            const ENUM_TIMEFRAMES entryTimeframe,
                            const DZVDailyZoneSet &zones,
                            const DZVIndicatorSnapshot &entrySnapshot,
                            const DZVIndicatorSnapshot &trendSnapshot,
                            const double rsiSidewaysUpper,
                            const double rsiSidewaysLower,
                            const double rsiOverbought,
                            const double rsiOversold,
                            const double minBodyPoints,
                            const ENUM_DZV_STOP_MODE stopMode,
                            const ENUM_DZV_TARGET_MODE targetMode,
                            const int selectedTargetZone,
                            const double stopBufferPoints,
                            const double volatilityStopAdrFraction,
                            const double riskReward,
                            DZVSignal &signal)
{
   signal.valid = false;
   signal.reason = "no_breakout";
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, entryTimeframe, 1, 3, rates) < 3)
   {
      signal.reason = "rates_unavailable";
      return false;
   }

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return false;
   double bodyPoints = MathAbs(rates[0].close - rates[0].open) / point;
   if(minBodyPoints > 0.0 && bodyPoints < minBodyPoints)
   {
      signal.reason = "body_too_small";
      return false;
   }

   for(int i = 0; i < DZV_ZONE_COUNT; i++)
   {
      if(rates[1].close <= zones.upper[i] && rates[0].close > zones.upper[i])
      {
         if(entrySnapshot.trend != DZV_TREND_UP || (trendSnapshot.ready && trendSnapshot.trend != DZV_TREND_UP))
         {
            signal.reason = "long_breakout_trend";
            continue;
         }
         if(entrySnapshot.rsi <= rsiSidewaysUpper || entrySnapshot.rsi >= rsiOverbought)
         {
            signal.reason = "long_breakout_rsi";
            continue;
         }
         if(entrySnapshot.stoch_k <= entrySnapshot.stoch_d)
         {
            signal.reason = "long_breakout_stoch";
            continue;
         }
         signal.valid = true;
         signal.direction = DZV_DIR_LONG;
         signal.module = DZV_SIGNAL_BREAKOUT;
         signal.zone_index = i;
         signal.broker_day = zones.day_start;
         signal.candle_time = rates[0].time;
         signal.zone_price = zones.upper[i];
         signal.entry_price = rates[0].close;
         DZVBuildStopsAndTarget(symbol, zones, rates[0], signal.direction, i, signal.entry_price,
                                stopMode, targetMode, selectedTargetZone, stopBufferPoints,
                                volatilityStopAdrFraction, riskReward, signal.stop_loss, signal.take_profit);
         signal.risk_points = MathAbs(signal.entry_price - signal.stop_loss) / point;
         signal.id = DZVBuildSignalId(symbol, entryTimeframe, zones.day_start, rates[0].time, signal.direction, i, signal.module);
         signal.reason = "long_breakout";
         return true;
      }

      if(rates[1].close >= zones.lower[i] && rates[0].close < zones.lower[i])
      {
         if(entrySnapshot.trend != DZV_TREND_DOWN || (trendSnapshot.ready && trendSnapshot.trend != DZV_TREND_DOWN))
         {
            signal.reason = "short_breakout_trend";
            continue;
         }
         if(entrySnapshot.rsi >= rsiSidewaysLower || entrySnapshot.rsi <= rsiOversold)
         {
            signal.reason = "short_breakout_rsi";
            continue;
         }
         if(entrySnapshot.stoch_k >= entrySnapshot.stoch_d)
         {
            signal.reason = "short_breakout_stoch";
            continue;
         }
         signal.valid = true;
         signal.direction = DZV_DIR_SHORT;
         signal.module = DZV_SIGNAL_BREAKOUT;
         signal.zone_index = i;
         signal.broker_day = zones.day_start;
         signal.candle_time = rates[0].time;
         signal.zone_price = zones.lower[i];
         signal.entry_price = rates[0].close;
         DZVBuildStopsAndTarget(symbol, zones, rates[0], signal.direction, i, signal.entry_price,
                                stopMode, targetMode, selectedTargetZone, stopBufferPoints,
                                volatilityStopAdrFraction, riskReward, signal.stop_loss, signal.take_profit);
         signal.risk_points = MathAbs(signal.entry_price - signal.stop_loss) / point;
         signal.id = DZVBuildSignalId(symbol, entryTimeframe, zones.day_start, rates[0].time, signal.direction, i, signal.module);
         signal.reason = "short_breakout";
         return true;
      }
   }
   return false;
}

#endif
