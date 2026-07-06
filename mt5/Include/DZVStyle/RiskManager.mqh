#ifndef DZV_STYLE_RISK_MANAGER_MQH
#define DZV_STYLE_RISK_MANAGER_MQH

#include <DZVStyle/DZVTypes.mqh>

double DZVSpreadPoints(const string symbol)
{
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0 || ask <= 0.0 || bid <= 0.0)
      return 0.0;
   return (ask - bid) / point;
}

bool DZVTradingSessionAllowed(const int startHour, const int endHour)
{
   if(startHour == endHour)
      return true;
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(), parts);
   int start = MathMax(0, MathMin(23, startHour));
   int end = MathMax(0, MathMin(24, endHour));
   if(end == 24)
      end = 0;
   if(start < end)
      return parts.hour >= start && parts.hour < end;
   return parts.hour >= start || parts.hour < end;
}

bool DZVFridayCutoffAllowed(const bool enabled, const int cutoffHour)
{
   if(!enabled)
      return true;
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(), parts);
   if(parts.day_of_week != 5)
      return true;
   return parts.hour < cutoffHour;
}

int DZVCountOpenProjectPositions(const string symbol, const long magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      count++;
   }
   return count;
}

bool DZVStopsValid(const string symbol,
                   const ENUM_DZV_DIRECTION direction,
                   const double entry,
                   const double stopLoss,
                   const double takeProfit,
                   const double minimumStopPoints,
                   const double maximumStopPoints,
                   string &reason)
{
   reason = "";
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
   {
      reason = "invalid_point";
      return false;
   }

   double stopDistancePoints = MathAbs(entry - stopLoss) / point;
   if(stopDistancePoints < minimumStopPoints)
   {
      reason = "stop_too_small";
      return false;
   }
   if(maximumStopPoints > 0.0 && stopDistancePoints > maximumStopPoints)
   {
      reason = "stop_too_large";
      return false;
   }

   int stopsLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel > 0 && stopDistancePoints < stopsLevel)
   {
      reason = "broker_stop_level";
      return false;
   }

   if(direction == DZV_DIR_LONG)
   {
      if(stopLoss >= entry)
      {
         reason = "long_sl_wrong_side";
         return false;
      }
      if(takeProfit > 0.0 && takeProfit <= entry)
      {
         reason = "long_tp_wrong_side";
         return false;
      }
   }
   else if(direction == DZV_DIR_SHORT)
   {
      if(stopLoss <= entry)
      {
         reason = "short_sl_wrong_side";
         return false;
      }
      if(takeProfit > 0.0 && takeProfit >= entry)
      {
         reason = "short_tp_wrong_side";
         return false;
      }
   }
   return true;
}

double DZVCalculateLot(const string symbol,
                       const ENUM_DZV_LOT_MODE lotMode,
                       const double fixedLot,
                       const double riskPercent,
                       const double entry,
                       const double stopLoss,
                       const double minimumLot,
                       const double maximumLot)
{
   if(lotMode == DZV_LOT_FIXED)
      return DZVNormalizeVolume(symbol, fixedLot, minimumLot, maximumLot);

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskCash = equity * riskPercent / 100.0;
   if(riskCash <= 0.0)
      return 0.0;

   double profitAtOneLot = 0.0;
   ENUM_ORDER_TYPE orderType = (entry >= stopLoss) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(orderType, symbol, 1.0, entry, stopLoss, profitAtOneLot))
   {
      double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double distance = MathAbs(entry - stopLoss);
      if(tickValue <= 0.0 || tickSize <= 0.0 || distance <= 0.0)
         return 0.0;
      double rawFallback = (riskCash * tickSize) / (distance * tickValue);
      return DZVNormalizeVolume(symbol, rawFallback, minimumLot, maximumLot);
   }

   double oneLotRisk = MathAbs(profitAtOneLot);
   if(oneLotRisk <= 0.0)
      return 0.0;
   return DZVNormalizeVolume(symbol, riskCash / oneLotRisk, minimumLot, maximumLot);
}

#endif
