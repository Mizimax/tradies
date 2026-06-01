#ifndef GOLDBOT_ENTRY_FILTERS_MQH
#define GOLDBOT_ENTRY_FILTERS_MQH

#include <GoldBot/SMC.mqh>
#include <GoldBot/TradeManager.mqh>
#include <GoldBot/Indicators.mqh>

bool GoldBotBullishEngulfing(MqlRates &rates[])
{
   if(ArraySize(rates) < 2)
      return false;
   MqlRates last = rates[0];
   MqlRates prev = rates[1];
   return prev.close < prev.open &&
          last.close > last.open &&
          last.close >= prev.open &&
          last.open <= prev.close;
}

bool GoldBotBearishEngulfing(MqlRates &rates[])
{
   if(ArraySize(rates) < 2)
      return false;
   MqlRates last = rates[0];
   MqlRates prev = rates[1];
   return prev.close > prev.open &&
          last.close < last.open &&
          last.open >= prev.close &&
          last.close <= prev.open;
}

bool GoldBotPinBar(const MqlRates &candle, const bool bullish)
{
   double body = MathAbs(candle.close - candle.open);
   double upper = candle.high - MathMax(candle.close, candle.open);
   double lower = MathMin(candle.close, candle.open) - candle.low;
   if(bullish)
      return lower > body * 2.0 && upper < body * 1.2;
   return upper > body * 2.0 && lower < body * 1.2;
}

bool GoldBotM5ChoCH(const string symbol, const GoldBotDirection direction)
{
   MqlRates m5[];
   ArraySetAsSeries(m5, true);
   if(CopyRates(symbol, PERIOD_M5, 1, 8, m5) < 8)
      return false;

   double previousHigh = m5[7].high;
   double previousLow = m5[7].low;
   for(int i = 7; i >= 3; i--)
   {
      previousHigh = MathMax(previousHigh, m5[i].high);
      previousLow = MathMin(previousLow, m5[i].low);
   }

   if(direction == DIR_LONG)
      return m5[0].close > previousHigh;
   if(direction == DIR_SHORT)
      return m5[0].close < previousLow;
   return false;
}

bool GoldBotPullbackConfirmed(
   const string symbol,
   const EntryZone &zone,
   const GoldBotDirection direction,
   const int rsiPeriod,
   const int requiredChecks,
   bool &candlePattern,
   bool &rsiShift,
   bool &microChoCH,
   int &checksHit
)
{
   candlePattern = false;
   rsiShift = false;
   microChoCH = false;
   checksHit = 0;
   if(!zone.valid || direction == DIR_NONE)
      return false;

   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   if(CopyRates(symbol, PERIOD_M15, 1, 3, m15) < 3)
      return false;

   bool inZone = m15[0].low <= zone.top && m15[0].high >= zone.bottom;
   if(direction == DIR_LONG)
      candlePattern = inZone && (GoldBotBullishEngulfing(m15) || GoldBotPinBar(m15[0], true));
   else if(direction == DIR_SHORT)
      candlePattern = inZone && (GoldBotBearishEngulfing(m15) || GoldBotPinBar(m15[0], false));

   double rsi = GoldBotRSI(symbol, PERIOD_M15, rsiPeriod, 1);
   double prevRsi = GoldBotRSI(symbol, PERIOD_M15, rsiPeriod, 2);
   if(rsi != EMPTY_VALUE && prevRsi != EMPTY_VALUE)
   {
      if(direction == DIR_LONG)
         rsiShift = prevRsi < 40.0 && rsi >= 40.0;
      else if(direction == DIR_SHORT)
         rsiShift = prevRsi > 60.0 && rsi <= 60.0;
   }

   microChoCH = GoldBotM5ChoCH(symbol, direction);
   checksHit = (candlePattern ? 1 : 0) + (rsiShift ? 1 : 0) + (microChoCH ? 1 : 0);
   int needed = MathMax(1, MathMin(3, requiredChecks));
   return checksHit >= needed;
}

string GoldBotNormalizedEventTime(string rawTime)
{
   StringReplace(rawTime, "T", " ");
   StringReplace(rawTime, "Z", "");
   StringReplace(rawTime, "-", ".");
   int dot = StringFind(rawTime, ".");
   if(dot > 0)
   {
      int lastDot = StringFind(rawTime, ".", dot + 1);
      if(lastDot > 0)
      {
         int millisDot = StringFind(rawTime, ".", lastDot + 1);
         if(millisDot > 0)
            rawTime = StringSubstr(rawTime, 0, millisDot);
      }
   }
   return rawTime;
}

string GoldBotJsonField(const string objectText, const string field)
{
   string key = "\"" + field + "\"";
   int keyPos = StringFind(objectText, key);
   if(keyPos < 0)
      return "";
   int colon = StringFind(objectText, ":", keyPos + StringLen(key));
   if(colon < 0)
      return "";
   int quoteStart = StringFind(objectText, "\"", colon + 1);
   if(quoteStart < 0)
      return "";
   int quoteEnd = StringFind(objectText, "\"", quoteStart + 1);
   if(quoteEnd < 0)
      return "";
   return StringSubstr(objectText, quoteStart + 1, quoteEnd - quoteStart - 1);
}

int GoldBotLastObjectStartBefore(const string text, const int position)
{
   int result = -1;
   int searchFrom = 0;
   while(true)
   {
      int found = StringFind(text, "{", searchFrom);
      if(found < 0 || found > position)
         break;
      result = found;
      searchFrom = found + 1;
   }
   return result;
}

bool GoldBotNewsEventWithinWindow(const datetime eventTime, const int blackoutSeconds, const datetime now)
{
   return eventTime > 0 && MathAbs((double)(now - eventTime)) <= blackoutSeconds;
}

bool GoldBotNewsBlocked(const string newsTimes, const int blackoutMinutes, string &matchedEvent)
{
   matchedEvent = "";
   if(StringLen(newsTimes) <= 0 || blackoutMinutes <= 0)
      return false;

   int blackoutSeconds = blackoutMinutes * 60;
   datetime now = TimeCurrent();

   int timeKeyPos = StringFind(newsTimes, "\"time\"");
   while(timeKeyPos >= 0)
   {
      int objectStart = GoldBotLastObjectStartBefore(newsTimes, timeKeyPos);
      int objectEnd = StringFind(newsTimes, "}", timeKeyPos);
      if(objectStart >= 0 && objectEnd > objectStart)
      {
         string objectText = StringSubstr(newsTimes, objectStart, objectEnd - objectStart + 1);
         string impact = GoldBotJsonField(objectText, "impact");
         string eventTimeText = GoldBotJsonField(objectText, "time");
         StringToLower(impact);
         if(impact == "high")
         {
            datetime eventTime = StringToTime(GoldBotNormalizedEventTime(eventTimeText));
            if(GoldBotNewsEventWithinWindow(eventTime, blackoutSeconds, now))
            {
               matchedEvent = eventTimeText;
               return true;
            }
         }
      }
      timeKeyPos = StringFind(newsTimes, "\"time\"", timeKeyPos + 6);
   }

   string parts[];
   int count = StringSplit(newsTimes, (ushort)StringGetCharacter(";", 0), parts);
   for(int i = 0; i < count; i++)
   {
      datetime eventTime = StringToTime(GoldBotNormalizedEventTime(parts[i]));
      if(GoldBotNewsEventWithinWindow(eventTime, blackoutSeconds, now))
      {
         matchedEvent = parts[i];
         return true;
      }
   }
   return false;
}

bool GoldBotPriceNearEntryZone(
   const string symbol,
   const EntryZone &zone,
   const GoldBotDirection direction,
   const double bufferPrice
)
{
   if(!zone.valid)
      return false;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double buffer = bufferPrice > 0.0 ? bufferPrice : MathMax(point * 50.0, 0.5);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(direction == DIR_LONG)
      return ask <= zone.top + buffer;
   if(direction == DIR_SHORT)
      return bid >= zone.bottom - buffer;
   return false;
}

int GoldBotIndicatorDirectionConflicts(
   const IndicatorSnapshot &indicators,
   const bool includeExtended,
   int &longDirections,
   int &shortDirections
)
{
   longDirections = 0;
   shortDirections = 0;

   if(indicators.emaLong)
      longDirections++;
   if(indicators.emaShort)
      shortDirections++;
   if(indicators.rsiLong)
      longDirections++;
   if(indicators.rsiShort)
      shortDirections++;
   if(indicators.vwapLong)
      longDirections++;
   if(indicators.vwapShort)
      shortDirections++;
   if(indicators.adxLong)
      longDirections++;
   if(indicators.adxShort)
      shortDirections++;

   if(includeExtended)
   {
      if(indicators.macdLong)
         longDirections++;
      if(indicators.macdShort)
         shortDirections++;
      if(indicators.bbLong)
         longDirections++;
      if(indicators.bbShort)
         shortDirections++;
      if(indicators.stochLong)
         longDirections++;
      if(indicators.stochShort)
         shortDirections++;
   }

   return longDirections > 0 && shortDirections > 0 ? 1 : 0;
}

#endif
