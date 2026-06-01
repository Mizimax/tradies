#ifndef GOLDBOT_SMC_MQH
#define GOLDBOT_SMC_MQH

enum GoldBotDirection
{
   DIR_NONE = 0,
   DIR_LONG = 1,
   DIR_SHORT = -1
};

struct GoldBotZone
{
   double bottom;
   double top;
   bool valid;
};

struct SMCResult
{
   bool gateH4;
   bool gateH1;
   bool gateM15;
   bool allPass;
   GoldBotDirection direction;
   GoldBotZone fvg;
   GoldBotZone orderBlock;
   double score;
};

double GoldBotRangeHigh(MqlRates &rates[], const int count)
{
   double value = rates[0].high;
   for(int i = 1; i < count; i++)
      value = MathMax(value, rates[i].high);
   return value;
}

double GoldBotRangeLow(MqlRates &rates[], const int count)
{
   double value = rates[0].low;
   for(int i = 1; i < count; i++)
      value = MathMin(value, rates[i].low);
   return value;
}

GoldBotDirection GoldBotStructureDirection(MqlRates &rates[], const int lookback)
{
   if(ArraySize(rates) < lookback + 2)
      return DIR_NONE;

   double recentHigh = GoldBotRangeHigh(rates, lookback / 2);
   double recentLow = GoldBotRangeLow(rates, lookback / 2);
   double priorHigh = rates[lookback / 2].high;
   double priorLow = rates[lookback / 2].low;

   for(int i = lookback / 2; i < lookback; i++)
   {
      priorHigh = MathMax(priorHigh, rates[i].high);
      priorLow = MathMin(priorLow, rates[i].low);
   }

   if(recentHigh > priorHigh && recentLow > priorLow)
      return DIR_LONG;
   if(recentHigh < priorHigh && recentLow < priorLow)
      return DIR_SHORT;
   return DIR_NONE;
}

bool GoldBotDisplacement(MqlRates &rates[], const GoldBotDirection direction)
{
   if(ArraySize(rates) < 12)
      return false;

   double avgBody = 0.0;
   for(int i = 1; i <= 10; i++)
      avgBody += MathAbs(rates[i].close - rates[i].open);
   avgBody /= 10.0;

   double body = MathAbs(rates[0].close - rates[0].open);
   if(body < avgBody * 1.5)
      return false;

   if(direction == DIR_LONG)
      return rates[0].close > rates[0].open;
   if(direction == DIR_SHORT)
      return rates[0].close < rates[0].open;
   return false;
}

bool GoldBotLiquiditySweep(MqlRates &rates[], const GoldBotDirection direction, const int lookback)
{
   if(ArraySize(rates) < lookback + 2)
      return false;

   double keyHigh = rates[1].high;
   double keyLow = rates[1].low;
   for(int i = 1; i <= lookback; i++)
   {
      keyHigh = MathMax(keyHigh, rates[i].high);
      keyLow = MathMin(keyLow, rates[i].low);
   }

   if(direction == DIR_LONG)
      return rates[0].low < keyLow && rates[0].close > keyLow;
   if(direction == DIR_SHORT)
      return rates[0].high > keyHigh && rates[0].close < keyHigh;
   return false;
}

GoldBotZone GoldBotFindFVG(MqlRates &rates[], const GoldBotDirection direction, const int lookback)
{
   GoldBotZone zone;
   zone.valid = false;
   zone.bottom = 0.0;
   zone.top = 0.0;

   int maxIndex = MathMin(ArraySize(rates) - 3, lookback);
   for(int i = 0; i <= maxIndex; i++)
   {
      MqlRates newer = rates[i];
      MqlRates older = rates[i + 2];
      if(direction == DIR_LONG && newer.low > older.high)
      {
         zone.bottom = older.high;
         zone.top = newer.low;
         zone.valid = true;
         return zone;
      }
      if(direction == DIR_SHORT && newer.high < older.low)
      {
         zone.bottom = newer.high;
         zone.top = older.low;
         zone.valid = true;
         return zone;
      }
   }
   return zone;
}

GoldBotZone GoldBotFindOrderBlock(MqlRates &rates[], const GoldBotDirection direction, const int lookback)
{
   GoldBotZone zone;
   zone.valid = false;
   zone.bottom = 0.0;
   zone.top = 0.0;

   int maxIndex = MathMin(ArraySize(rates) - 2, lookback);
   for(int i = 1; i <= maxIndex; i++)
   {
      MqlRates candle = rates[i];
      MqlRates next = rates[i - 1];
      double body = MathAbs(candle.close - candle.open);
      double nextBody = MathAbs(next.close - next.open);

      bool bullishOB = direction == DIR_LONG && candle.close < candle.open && next.close > next.open && nextBody > body * 1.2;
      bool bearishOB = direction == DIR_SHORT && candle.close > candle.open && next.close < next.open && nextBody > body * 1.2;
      if(bullishOB || bearishOB)
      {
         zone.bottom = candle.low;
         zone.top = candle.high;
         zone.valid = true;
         return zone;
      }
   }
   return zone;
}

bool GoldBotBOSOrCHoCH(MqlRates &rates[], const GoldBotDirection direction, const int lookback)
{
   if(ArraySize(rates) < lookback + 2)
      return false;

   double priorHigh = rates[1].high;
   double priorLow = rates[1].low;
   for(int i = 1; i <= lookback; i++)
   {
      priorHigh = MathMax(priorHigh, rates[i].high);
      priorLow = MathMin(priorLow, rates[i].low);
   }

   if(direction == DIR_LONG)
      return rates[0].close > priorHigh;
   if(direction == DIR_SHORT)
      return rates[0].close < priorLow;
   return false;
}

bool GoldBotRunSMC(const string symbol, SMCResult &out)
{
   MqlRates h4[];
   MqlRates h1[];
   MqlRates m15[];
   ArraySetAsSeries(h4, true);
   ArraySetAsSeries(h1, true);
   ArraySetAsSeries(m15, true);

   if(CopyRates(symbol, PERIOD_H4, 1, 120, h4) < 80)
      return false;
   if(CopyRates(symbol, PERIOD_H1, 1, 120, h1) < 80)
      return false;
   if(CopyRates(symbol, PERIOD_M15, 1, 160, m15) < 100)
      return false;

   out.direction = GoldBotStructureDirection(h4, 40);
   if(out.direction == DIR_NONE)
      return false;

   double h4High = GoldBotRangeHigh(h4, 40);
   double h4Low = GoldBotRangeLow(h4, 40);
   double midpoint = h4Low + (h4High - h4Low) / 2.0;
   bool zoneOk = out.direction == DIR_LONG ? h4[0].close < midpoint : h4[0].close > midpoint;
   GoldBotZone h4Fvg = GoldBotFindFVG(h4, out.direction, 40);
   GoldBotZone h4Ob = GoldBotFindOrderBlock(h4, out.direction, 40);
   out.gateH4 = zoneOk && (h4Fvg.valid || h4Ob.valid);

   GoldBotDirection h1Direction = GoldBotStructureDirection(h1, 32);
   bool h1Align = h1Direction == out.direction || GoldBotBOSOrCHoCH(h1, out.direction, 24);
   out.gateH1 = h1Align && GoldBotLiquiditySweep(h1, out.direction, 24) && GoldBotDisplacement(h1, out.direction);

   out.fvg = GoldBotFindFVG(m15, out.direction, 60);
   out.orderBlock = GoldBotFindOrderBlock(m15, out.direction, 60);
   out.gateM15 = (out.fvg.valid || out.orderBlock.valid) && GoldBotBOSOrCHoCH(m15, out.direction, 24);

   out.allPass = out.gateM15;
   out.score = 0.0;
   if(out.gateM15)
      out.score += 25.0;
   if(out.gateH4)
      out.score += 6.25;
   if(out.gateH1)
      out.score += 6.25;
   return true;
}

#endif
