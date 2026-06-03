#ifndef GOLDSCALPER_RISK_MANAGER_MQH
#define GOLDSCALPER_RISK_MANAGER_MQH

//+------------------------------------------------------------------+
//| RiskManager.mqh — equity-percentage position sizing & daily limits|
//| Part of GoldScalper EA                                            |
//+------------------------------------------------------------------+

#include <GoldScalper/SessionTime.mqh>

//--- Position sizing based on equity percentage risk
double GoldScalperCalculateLot(
   const string symbol,
   const double entryPrice,
   const double slPrice,
   const double riskPct,
   const double minLot,
   const double maxLot)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * riskPct / 100.0;

   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickValue <= 0.0 || tickSize <= 0.0)
   {
      Print("GoldScalper: Invalid tick value/size for ", symbol);
      return 0.0;
   }

   double slDistance = MathAbs(entryPrice - slPrice);
   if(slDistance <= 0.0)
   {
      Print("GoldScalper: SL distance is zero");
      return 0.0;
   }

   double rawLot = (riskAmount * tickSize) / (slDistance * tickValue);
   return GoldScalperNormalizeLot(symbol, rawLot, minLot, maxLot);
}

double GoldScalperNormalizeLot(const string symbol, const double rawLot, const double minLot, const double maxLot)
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

//--- Daily loss tracking
double GoldScalperDailyStartEquity()
{
   string key = GoldScalperDayKey("startEquity");
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, equity);
   return GlobalVariableGet(key);
}

double GoldScalperDailyPnlPct()
{
   double startEquity = GoldScalperDailyStartEquity();
   if(startEquity <= 0.0)
      return 0.0;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   return ((currentEquity - startEquity) / startEquity) * 100.0;
}

bool GoldScalperDailyLossAllowed(const double maxDailyLossPct)
{
   double pnlPct = GoldScalperDailyPnlPct();
   if(pnlPct <= -maxDailyLossPct)
   {
      Print("GoldScalper: Daily loss limit hit. PnL%=", DoubleToString(pnlPct, 2));
      return false;
   }
   return true;
}

//--- Daily trade count tracking
int GoldScalperDailyTradeCount()
{
   string key = GoldScalperDayKey("totalTrades");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

void GoldScalperIncrementDailyTradeCount()
{
   string key = GoldScalperDayKey("totalTrades");
   int current = GoldScalperDailyTradeCount();
   GlobalVariableSet(key, (double)(current + 1));
}

bool GoldScalperDailyTradeAllowed(const int maxDailyTrades)
{
   if(maxDailyTrades <= 0)
      return true;
   int count = GoldScalperDailyTradeCount();
   if(count >= maxDailyTrades)
   {
      Print("GoldScalper: Daily trade limit hit. Count=", count, " Max=", maxDailyTrades);
      return false;
   }
   return true;
}

//--- Max open trades check
int GoldScalperCountOpenPositions(const string symbol, const long magic)
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

bool GoldScalperMaxOpenAllowed(const string symbol, const long magic, const int maxOpen)
{
   int openCount = GoldScalperCountOpenPositions(symbol, magic);
   if(openCount >= maxOpen)
   {
      Print("GoldScalper: Max open positions reached. Open=", openCount, " Max=", maxOpen);
      return false;
   }
   return true;
}

//--- Count pending orders for this EA
int GoldScalperCountPendingOrders(const string symbol, const long magic)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      count++;
   }
   return count;
}

//--- Consecutive loss tracking for cooldown
int GoldScalperConsecutiveLosses()
{
   string key = GoldScalperDayKey("consecLoss");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

void GoldScalperRecordTradeResult(bool isWin)
{
   string key = GoldScalperDayKey("consecLoss");
   if(isWin)
      GlobalVariableSet(key, 0.0);
   else
   {
      int current = GoldScalperConsecutiveLosses();
      GlobalVariableSet(key, (double)(current + 1));
      Print("GoldScalper: Consecutive losses incremented to ", current + 1);
   }
}

bool GoldScalperCooldownAllowed(const int maxConsecLoss)
{
   if(maxConsecLoss <= 0)
      return true;
   int consec = GoldScalperConsecutiveLosses();
   if(consec >= maxConsecLoss)
   {
      Print("GoldScalper: Cooldown active. ", consec, " consecutive losses >= limit ", maxConsecLoss);
      return false;
   }
   return true;
}

//--- Drawdown-scaled position sizing
double GoldScalperPeakEquity()
{
   string key = "GoldScalper_peakEquity";
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!GlobalVariableCheck(key))
   {
      GlobalVariableSet(key, equity);
      return equity;
   }
   double peak = GlobalVariableGet(key);
   if(equity > peak)
   {
      GlobalVariableSet(key, equity);
      return equity;
   }
   return peak;
}

double GoldScalperDrawdownScaledRisk(const double baseRiskPct)
{
   double peak = GoldScalperPeakEquity();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (peak > 0) ? (peak - equity) / peak * 100.0 : 0.0;

   // Scale down risk as drawdown increases
   if(dd >= 20.0)
   {
      Print("GoldScalper: DD=", DoubleToString(dd, 2), "% >= 20%. STOP trading.");
      return 0.0;
   }
   if(dd >= 15.0)
   {
      double scaled = baseRiskPct * 0.25;
      Print("GoldScalper: DD=", DoubleToString(dd, 2), "% >= 15%. Risk scaled to ", DoubleToString(scaled, 3), "%");
      return scaled;
   }
   if(dd >= 10.0)
   {
      double scaled = baseRiskPct * 0.50;
      Print("GoldScalper: DD=", DoubleToString(dd, 2), "% >= 10%. Risk scaled to ", DoubleToString(scaled, 3), "%");
      return scaled;
   }
   return baseRiskPct;
}

//--- Journal logging
void GoldScalperJournal(const string message)
{
   int handle = FileOpen("GoldScalper/trades.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return;
   FileSeek(handle, 0, SEEK_END);
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   string timestamp = StringFormat("%04d.%02d.%02d %02d:%02d:%02d", t.year, t.mon, t.day, t.hour, t.min, t.sec);
   FileWrite(handle, timestamp, message);
   FileClose(handle);
}

void GoldScalperResetJournal()
{
   int handle = FileOpen("GoldScalper/trades.csv", FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return;
   FileWrite(handle, "timestamp", "event");
   FileClose(handle);
}

#endif
