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
   GoldBotDirection h4Direction;
   GoldBotDirection h1Direction;
   GoldBotDirection m15Direction;
   GoldBotZone fvg;
   GoldBotZone orderBlock;
   GoldBotZone h4Fvg;
   GoldBotZone h4OrderBlock;
   GoldBotZone h1Fvg;
   GoldBotZone h1OrderBlock;
   bool h4PremiumDiscount;
   bool h4LiquiditySweep;
   bool h4Displacement;
   bool h4BosChoCh;
   bool h4ObFvgOverlap;
   bool h1Aligned;
   bool h1LiquiditySweep;
   bool h1Displacement;
   bool h1BosChoCh;
   bool h1ObFvgOverlap;
   bool m15LiquiditySweep;
   bool m15RecentSweep;
   bool m15Displacement;
   bool m15BosChoCh;
   bool m15HasZone;
   bool m15ObFvgOverlap;
   bool m15RetestingZone;
   bool m15SequenceOk;
   double score;
};

void GoldBotInitZone(GoldBotZone &zone)
{
   zone.bottom = 0.0;
   zone.top = 0.0;
   zone.valid = false;
}

void GoldBotResetSMC(SMCResult &out)
{
   out.gateH4 = false;
   out.gateH1 = false;
   out.gateM15 = false;
   out.allPass = false;
   out.direction = DIR_NONE;
   out.h4Direction = DIR_NONE;
   out.h1Direction = DIR_NONE;
   out.m15Direction = DIR_NONE;
   GoldBotInitZone(out.fvg);
   GoldBotInitZone(out.orderBlock);
   GoldBotInitZone(out.h4Fvg);
   GoldBotInitZone(out.h4OrderBlock);
   GoldBotInitZone(out.h1Fvg);
   GoldBotInitZone(out.h1OrderBlock);
   out.h4PremiumDiscount = false;
   out.h4LiquiditySweep = false;
   out.h4Displacement = false;
   out.h4BosChoCh = false;
   out.h4ObFvgOverlap = false;
   out.h1Aligned = false;
   out.h1LiquiditySweep = false;
   out.h1Displacement = false;
   out.h1BosChoCh = false;
   out.h1ObFvgOverlap = false;
   out.m15LiquiditySweep = false;
   out.m15RecentSweep = false;
   out.m15Displacement = false;
   out.m15BosChoCh = false;
   out.m15HasZone = false;
   out.m15ObFvgOverlap = false;
   out.m15RetestingZone = false;
   out.m15SequenceOk = false;
   out.score = 0.0;
}

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

bool GoldBotLiquiditySweepAt(MqlRates &rates[], const GoldBotDirection direction, const int index, const int lookback)
{
   if(index < 0 || ArraySize(rates) < index + lookback + 2)
      return false;

   double keyHigh = rates[index + 1].high;
   double keyLow = rates[index + 1].low;
   for(int i = index + 1; i <= index + lookback; i++)
   {
      keyHigh = MathMax(keyHigh, rates[i].high);
      keyLow = MathMin(keyLow, rates[i].low);
   }

   if(direction == DIR_LONG)
      return rates[index].low < keyLow && rates[index].close > keyLow;
   if(direction == DIR_SHORT)
      return rates[index].high > keyHigh && rates[index].close < keyHigh;
   return false;
}

bool GoldBotLiquiditySweep(MqlRates &rates[], const GoldBotDirection direction, const int lookback)
{
   return GoldBotLiquiditySweepAt(rates, direction, 0, lookback);
}

bool GoldBotRecentLiquiditySweep(MqlRates &rates[], const GoldBotDirection direction, const int lookback, const int maxBars)
{
   if(maxBars <= 0)
      return false;

   int limit = maxBars;
   int available = ArraySize(rates) - lookback - 1;
   if(limit > available)
      limit = available;
   for(int i = 0; i < limit; i++)
   {
      if(GoldBotLiquiditySweepAt(rates, direction, i, lookback))
         return true;
   }
   return false;
}

bool GoldBotZonesOverlap(const GoldBotZone &a, const GoldBotZone &b, GoldBotZone &overlap)
{
   GoldBotInitZone(overlap);
   if(!a.valid || !b.valid)
      return false;

   double bottom = MathMax(a.bottom, b.bottom);
   double top = MathMin(a.top, b.top);
   if(bottom >= top)
      return false;

   overlap.bottom = bottom;
   overlap.top = top;
   overlap.valid = true;
   return true;
}

bool GoldBotZoneTouchedByCandle(const GoldBotZone &zone, const MqlRates &candle)
{
   return zone.valid && candle.low <= zone.top && candle.high >= zone.bottom;
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
   GoldBotResetSMC(out);

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

   out.h4Direction = GoldBotStructureDirection(h4, 40);
   out.direction = out.h4Direction;
   if(out.direction == DIR_NONE)
      return false;

   double h4High = GoldBotRangeHigh(h4, 40);
   double h4Low = GoldBotRangeLow(h4, 40);
   double midpoint = h4Low + (h4High - h4Low) / 2.0;
   out.h4PremiumDiscount = out.direction == DIR_LONG ? h4[0].close < midpoint : h4[0].close > midpoint;
   out.h4Fvg = GoldBotFindFVG(h4, out.direction, 40);
   out.h4OrderBlock = GoldBotFindOrderBlock(h4, out.direction, 40);
   GoldBotZone h4Overlap;
   out.h4ObFvgOverlap = GoldBotZonesOverlap(out.h4Fvg, out.h4OrderBlock, h4Overlap);
   out.h4LiquiditySweep = GoldBotRecentLiquiditySweep(h4, out.direction, 12, 8);
   out.h4Displacement = GoldBotDisplacement(h4, out.direction);
   out.h4BosChoCh = GoldBotBOSOrCHoCH(h4, out.direction, 24);
   out.gateH4 = out.h4PremiumDiscount && (out.h4Fvg.valid || out.h4OrderBlock.valid);

   out.h1Direction = GoldBotStructureDirection(h1, 32);
   out.h1BosChoCh = GoldBotBOSOrCHoCH(h1, out.direction, 24);
   out.h1Aligned = out.h1Direction == out.direction || out.h1BosChoCh;
   out.h1LiquiditySweep = GoldBotRecentLiquiditySweep(h1, out.direction, 16, 8);
   out.h1Displacement = GoldBotDisplacement(h1, out.direction);
   out.h1Fvg = GoldBotFindFVG(h1, out.direction, 40);
   out.h1OrderBlock = GoldBotFindOrderBlock(h1, out.direction, 40);
   GoldBotZone h1Overlap;
   out.h1ObFvgOverlap = GoldBotZonesOverlap(out.h1Fvg, out.h1OrderBlock, h1Overlap);
   out.gateH1 = out.h1Aligned && out.h1LiquiditySweep && out.h1Displacement;

   out.fvg = GoldBotFindFVG(m15, out.direction, 60);
   out.orderBlock = GoldBotFindOrderBlock(m15, out.direction, 60);
   out.m15Direction = GoldBotStructureDirection(m15, 32);
   out.m15LiquiditySweep = GoldBotLiquiditySweep(m15, out.direction, 16);
   out.m15RecentSweep = GoldBotRecentLiquiditySweep(m15, out.direction, 16, 12);
   out.m15Displacement = GoldBotDisplacement(m15, out.direction);
   out.m15BosChoCh = GoldBotBOSOrCHoCH(m15, out.direction, 24);
   out.m15HasZone = out.fvg.valid || out.orderBlock.valid;
   GoldBotZone m15Overlap;
   out.m15ObFvgOverlap = GoldBotZonesOverlap(out.fvg, out.orderBlock, m15Overlap);
   out.m15RetestingZone = GoldBotZoneTouchedByCandle(out.fvg, m15[0]) || GoldBotZoneTouchedByCandle(out.orderBlock, m15[0]);
   out.m15SequenceOk = out.m15RecentSweep && (out.m15Displacement || out.m15BosChoCh) && out.m15HasZone;
   out.gateM15 = out.m15HasZone && out.m15BosChoCh;

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
