#ifndef GOLDBOT_RISK_MQH
#define GOLDBOT_RISK_MQH

enum GoldBotRiskMode
{
   EQUITY_LOT_RATIO = 0
};

string GoldBotDayKey(const string suffix)
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   return StringFormat("GoldBot.%04d%02d%02d.%s", t.year, t.mon, t.day, suffix);
}

double GoldBotNormalizeLot(const string symbol, const double rawLot, const double minLot, const double maxLot)
{
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double brokerMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double brokerMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      step = 0.01;

   double low = MathMax(minLot, brokerMin);
   double high = MathMin(maxLot, brokerMax);
   double clamped = MathMax(low, MathMin(rawLot, high));
   return NormalizeDouble(MathRound(clamped / step) * step, 2);
}

double GoldBotSplitLot(
   const string symbol,
   const double equity,
   const double score,
   const int splitIndex,
   const double lotPer100Usd,
   const double minLot,
   const double maxLot,
   const double highConvictionScore
)
{
   double total = (equity / 100.0) * lotPer100Usd;
   if(score >= highConvictionScore)
      total *= 1.5;

   double weight = splitIndex == 2 ? 0.34 : 0.33;
   return GoldBotNormalizeLot(symbol, total * weight, minLot, maxLot);
}

bool GoldBotDailyRiskAllowed(const double maxDailyLossPct, const double dailyTargetPct, double &pnlPct)
{
   string key = GoldBotDayKey("startEquity");
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, equity);

   double startEquity = GlobalVariableGet(key);
   if(startEquity <= 0.0)
   {
      GlobalVariableSet(key, equity);
      startEquity = equity;
   }

   pnlPct = ((equity - startEquity) / startEquity) * 100.0;
   return pnlPct > -maxDailyLossPct && pnlPct < dailyTargetPct;
}

bool GoldBotCooldownAllowed(const int cooldownBars)
{
   string key = "GoldBot.lastSignalTime";
   if(!GlobalVariableCheck(key))
      return true;
   datetime lastTime = (datetime)GlobalVariableGet(key);
   return TimeCurrent() - lastTime >= cooldownBars * PeriodSeconds(PERIOD_M15);
}

void GoldBotMarkSignalTime()
{
   GlobalVariableSet("GoldBot.lastSignalTime", (double)TimeCurrent());
}

bool GoldBotServerHourAllowed(const bool enabled, const int startHour, const int endHour)
{
   if(!enabled)
      return true;

   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int start = MathMax(0, MathMin(23, startHour));
   int end = MathMax(0, MathMin(23, endHour));

   if(start == end)
      return true;
   if(start < end)
      return t.hour >= start && t.hour < end;
   return t.hour >= start || t.hour < end;
}

int GoldBotDailyLadderCount()
{
   string key = GoldBotDayKey("ladderCount");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

bool GoldBotDailyLadderAllowed(const int maxLaddersPerDay, int &currentCount)
{
   currentCount = GoldBotDailyLadderCount();
   if(maxLaddersPerDay <= 0)
      return true;
   return currentCount < maxLaddersPerDay;
}

void GoldBotMarkLadderPlaced()
{
   string key = GoldBotDayKey("ladderCount");
   int currentCount = GoldBotDailyLadderCount();
   GlobalVariableSet(key, (double)(currentCount + 1));
}

#endif
