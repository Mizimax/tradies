#ifndef BTCSCALPER_SESSION_TIME_MQH
#define BTCSCALPER_SESSION_TIME_MQH

//+------------------------------------------------------------------+
//| SessionTime.mqh — session/hour helpers                           |
//| Part of BTCScalper EA                                            |
//+------------------------------------------------------------------+

//--- Build a GlobalVariable key scoped to today's date
string BTCScalperDayKey(const string suffix)
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   return StringFormat("BTCScalper_%04d%02d%02d_%s", now.year, now.mon, now.day, suffix);
}

//--- True if current server hour is within [startHour, endHour)
//    Supports overnight wrap-around (e.g. 22 → 5)
bool BTCScalperInHourRange(const int startHour, const int endHour)
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int h = now.hour;

   if(startHour <= endHour)
      return h >= startHour && h < endHour;
   else
      return h >= startHour || h < endHour;   // overnight wrap
}

//--- True if current server hour is before tradingEndHour (new entries allowed)
bool BTCScalperIsTradingHours(const int tradingEndHour)
{
   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   return now.hour < tradingEndHour;
}

//--- Generic new-bar detection using caller-owned state
bool BTCScalperIsNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe, datetime &lastSeen)
{
   datetime barTime = iTime(symbol, timeframe, 0);
   if(barTime <= 0)
      return false;
   if(barTime != lastSeen)
   {
      lastSeen = barTime;
      return true;
   }
   return false;
}

//--- New M5 bar detection (static last-seen datetime per symbol)
bool BTCScalperIsNewM5Bar(const string symbol)
{
   static datetime s_lastM5 = 0;
   return BTCScalperIsNewBar(symbol, PERIOD_M5, s_lastM5);
}

//--- New M15 bar detection (static last-seen datetime per symbol)
bool BTCScalperIsNewM15Bar(const string symbol)
{
   static datetime s_lastM15 = 0;
   return BTCScalperIsNewBar(symbol, PERIOD_M15, s_lastM15);
}

#endif
