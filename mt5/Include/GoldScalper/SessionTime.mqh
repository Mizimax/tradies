#ifndef GOLDSCALPER_SESSION_TIME_MQH
#define GOLDSCALPER_SESSION_TIME_MQH

//+------------------------------------------------------------------+
//| SessionTime.mqh — broker-time-aware session detection             |
//| Part of GoldScalper EA                                            |
//+------------------------------------------------------------------+

string GoldScalperDayKey(const string suffix)
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   return StringFormat("GoldScalper.%04d%02d%02d.%s", t.year, t.mon, t.day, suffix);
}

bool GoldScalperParseTime(const string timeStr, int &hour, int &minute)
{
   string parts[];
   int count = StringSplit(timeStr, ':', parts);
   if(count < 2)
      return false;
   hour = (int)StringToInteger(parts[0]);
   minute = (int)StringToInteger(parts[1]);
   return true;
}

int GoldScalperServerHour()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   return t.hour;
}

int GoldScalperServerMinute()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   return t.min;
}

bool GoldScalperInHourRange(const int startHour, const int endHour)
{
   int current = GoldScalperServerHour();

   if(startHour == endHour)
      return true;

   // Handle overnight ranges (e.g., 22:00 - 05:00)
   if(startHour > endHour)
      return current >= startHour || current < endHour;

   // Normal range (e.g., 07:00 - 12:00)
   return current >= startHour && current < endHour;
}

bool GoldScalperIsAsianSession(const int asianStartHour, const int asianEndHour)
{
   return GoldScalperInHourRange(asianStartHour, asianEndHour);
}

bool GoldScalperIsLondonOpen(const int londonStartHour, const int londonEndHour)
{
   return GoldScalperInHourRange(londonStartHour, londonEndHour);
}

bool GoldScalperIsNyOverlap(const int overlapStartHour, const int overlapEndHour)
{
   return GoldScalperInHourRange(overlapStartHour, overlapEndHour);
}

bool GoldScalperIsTradingHours(const int tradingEndHour)
{
   // Trading is allowed from midnight until tradingEndHour
   int current = GoldScalperServerHour();
   return current < tradingEndHour;
}

bool GoldScalperIsNewBar(const string symbol, const ENUM_TIMEFRAMES tf)
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(symbol, tf, 0);
   if(currentBarTime == 0)
      return false;
   if(currentBarTime == lastBarTime)
      return false;
   lastBarTime = currentBarTime;
   return true;
}

// Separate new-bar tracker for M5 (used by MR and Momentum)
bool GoldScalperIsNewM5Bar(const string symbol)
{
   static datetime lastM5Bar = 0;
   datetime currentBarTime = iTime(symbol, PERIOD_M5, 0);
   if(currentBarTime == 0)
      return false;
   if(currentBarTime == lastM5Bar)
      return false;
   lastM5Bar = currentBarTime;
   return true;
}

// Separate new-bar tracker for M1 (used by Asian Breakout range building)
bool GoldScalperIsNewM1Bar(const string symbol)
{
   static datetime lastM1Bar = 0;
   datetime currentBarTime = iTime(symbol, PERIOD_M1, 0);
   if(currentBarTime == 0)
      return false;
   if(currentBarTime == lastM1Bar)
      return false;
   lastM1Bar = currentBarTime;
   return true;
}

#endif
