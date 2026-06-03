#ifndef GOLDSCALPER_NEWS_FILTER_MQH
#define GOLDSCALPER_NEWS_FILTER_MQH

//+------------------------------------------------------------------+
//| NewsFilter.mqh — high-impact news blackout filter                 |
//| Part of GoldScalper EA                                            |
//| Reuses the same approach as GoldBot's news filter.                |
//+------------------------------------------------------------------+

bool GoldScalperNewsBlocked(
   const string newsTimes,
   const int blackoutMinutes,
   string &matchedEvent)
{
   if(StringLen(newsTimes) <= 0 || blackoutMinutes <= 0)
      return false;

   // Parse semicolon-separated list of UTC times "HH:MM;HH:MM;..."
   string entries[];
   int count = StringSplit(newsTimes, ';', entries);
   if(count <= 0)
      return false;

   datetime now = TimeCurrent();
   MqlDateTime nowParts;
   TimeToStruct(now, nowParts);

   for(int i = 0; i < count; i++)
   {
      string trimmed = entries[i];
      StringTrimLeft(trimmed);
      StringTrimRight(trimmed);
      if(StringLen(trimmed) < 3)
         continue;

      string timeParts[];
      int tCount = StringSplit(trimmed, ':', timeParts);
      if(tCount < 2)
         continue;

      int eventHour = (int)StringToInteger(timeParts[0]);
      int eventMin  = (int)StringToInteger(timeParts[1]);

      // Build today's event time
      MqlDateTime eventParts;
      eventParts.year = nowParts.year;
      eventParts.mon  = nowParts.mon;
      eventParts.day  = nowParts.day;
      eventParts.hour = eventHour;
      eventParts.min  = eventMin;
      eventParts.sec  = 0;
      datetime eventTime = StructToTime(eventParts);

      // Check if we're within the blackout window (before or after)
      int secondsBefore = blackoutMinutes * 60;
      int secondsAfter  = blackoutMinutes * 60;

      if(now >= eventTime - secondsBefore && now <= eventTime + secondsAfter)
      {
         matchedEvent = trimmed;
         Print("GoldScalper: News blackout active. Event=", trimmed,
               " Blackout=", blackoutMinutes, " min");
         return true;
      }
   }
   return false;
}

#endif
