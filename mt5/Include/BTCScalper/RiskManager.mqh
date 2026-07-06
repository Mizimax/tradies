#ifndef BTCSCALPER_RISK_MANAGER_MQH
#define BTCSCALPER_RISK_MANAGER_MQH

//+------------------------------------------------------------------+
//| RiskManager.mqh — equity-percentage position sizing & daily limits|
//| Part of BTCScalper EA                                            |
//+------------------------------------------------------------------+

#include <BTCScalper/SessionTime.mqh>

//--- Position sizing based on equity percentage risk
double BTCScalperNormalizeLot(const string symbol, const double rawLot, const double minLot, const double maxLot)
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

double BTCScalperCalculateLot(
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
      Print("BTCScalper: Invalid tick value/size for ", symbol);
      return 0.0;
   }

   double slDistance = MathAbs(entryPrice - slPrice);
   if(slDistance <= 0.0)
   {
      Print("BTCScalper: SL distance is zero");
      return 0.0;
   }

   double rawLot = (riskAmount * tickSize) / (slDistance * tickValue);
   return BTCScalperNormalizeLot(symbol, rawLot, minLot, maxLot);
}

bool BTCScalperCostGatePass(
   const string symbol,
   const double expectedMovePrice,
   const double atrRef,
   const double k,
   const double commPerLot,
   const double minAtrMult)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(point <= 0.0 || tickSize <= 0.0)
      return false;

   double spreadPrice = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;
   double commPrice = (tickValue > 0.0) ? commPerLot * tickSize / tickValue : 0.0;
   double costFloor = MathMax(0.0, k) * (spreadPrice + MathMax(0.0, commPrice));
   double atrFloor = 0.0;
   if(atrRef > 0.0 && minAtrMult > 0.0)
      atrFloor = minAtrMult * atrRef;

   return expectedMovePrice >= MathMax(costFloor, atrFloor);
}

//--- Daily loss tracking
double BTCScalperDailyStartEquity()
{
   string key = BTCScalperDayKey("startEquity");
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!GlobalVariableCheck(key))
      GlobalVariableSet(key, equity);
   return GlobalVariableGet(key);
}

double BTCScalperDailyPnlPct()
{
   double startEquity = BTCScalperDailyStartEquity();
   if(startEquity <= 0.0)
      return 0.0;
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   return ((currentEquity - startEquity) / startEquity) * 100.0;
}

bool BTCScalperDailyLossAllowed(const double maxDailyLossPct)
{
   double pnlPct = BTCScalperDailyPnlPct();
   if(pnlPct <= -maxDailyLossPct)
   {
      Print("BTCScalper: Daily loss limit hit. PnL%=", DoubleToString(pnlPct, 2));
      return false;
   }
   return true;
}

//--- Daily trade count tracking
int BTCScalperDailyTradeCount()
{
   string key = BTCScalperDayKey("totalTrades");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

void BTCScalperIncrementDailyTradeCount()
{
   string key = BTCScalperDayKey("totalTrades");
   int current = BTCScalperDailyTradeCount();
   GlobalVariableSet(key, (double)(current + 1));
}

bool BTCScalperDailyTradeAllowed(const int maxDailyTrades)
{
   if(maxDailyTrades <= 0)
      return true;
   int count = BTCScalperDailyTradeCount();
   if(count >= maxDailyTrades)
   {
      Print("BTCScalper: Daily trade limit hit. Count=", count, " Max=", maxDailyTrades);
      return false;
   }
   return true;
}

//--- Max open trades check
int BTCScalperCountOpenPositions(const string symbol, const long magic)
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

bool BTCScalperMaxOpenAllowed(const string symbol, const long magic, const int maxOpen)
{
   int openCount = BTCScalperCountOpenPositions(symbol, magic);
   if(openCount >= maxOpen)
   {
      Print("BTCScalper: Max open positions reached. Open=", openCount, " Max=", maxOpen);
      return false;
   }
   return true;
}

//--- Count pending orders for this EA
int BTCScalperCountPendingOrders(const string symbol, const long magic)
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
int BTCScalperConsecutiveLosses()
{
   string key = BTCScalperDayKey("consecLoss");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

void BTCScalperRecordTradeResult(bool isWin)
{
   string key = BTCScalperDayKey("consecLoss");
   if(isWin)
      GlobalVariableSet(key, 0.0);
   else
   {
      int current = BTCScalperConsecutiveLosses();
      GlobalVariableSet(key, (double)(current + 1));
      Print("BTCScalper: Consecutive losses incremented to ", current + 1);
   }
}

bool BTCScalperCooldownAllowed(const int maxConsecLoss)
{
   if(maxConsecLoss <= 0)
      return true;
   int consec = BTCScalperConsecutiveLosses();
   if(consec >= maxConsecLoss)
   {
      Print("BTCScalper: Cooldown active. ", consec, " consecutive losses >= limit ", maxConsecLoss);
      return false;
   }
   return true;
}

//--- Drawdown-scaled position sizing
double BTCScalperPeakEquity()
{
   string key = "BTCScalper_peakEquity";
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

void BTCScalperResetTesterRiskState()
{
   if(!MQLInfoInteger(MQL_TESTER))
      return;

   GlobalVariableSet("BTCScalper_peakEquity", AccountInfoDouble(ACCOUNT_EQUITY));
}

double BTCScalperDrawdownScaledRisk(const double baseRiskPct,
                                     const double scaleHalfAtPct = 12.0,
                                     const double scaleQuarterAtPct = 18.0,
                                     const double stopAtPct = 25.0)
{
   double peak = BTCScalperPeakEquity();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (peak > 0) ? (peak - equity) / peak * 100.0 : 0.0;

   // Scale down risk as drawdown increases
   if(stopAtPct > 0.0 && dd >= stopAtPct)
   {
      Print("BTCScalper: DD=", DoubleToString(dd, 2), "% >= ",
            DoubleToString(stopAtPct, 2), "%. STOP trading.");
      return 0.0;
   }
   if(scaleQuarterAtPct > 0.0 && dd >= scaleQuarterAtPct)
   {
      double scaled = baseRiskPct * 0.25;
      Print("BTCScalper: DD=", DoubleToString(dd, 2), "% >= ",
            DoubleToString(scaleQuarterAtPct, 2), "%. Risk scaled to ",
            DoubleToString(scaled, 3), "%");
      return scaled;
   }
   if(scaleHalfAtPct > 0.0 && dd >= scaleHalfAtPct)
   {
      double scaled = baseRiskPct * 0.50;
      Print("BTCScalper: DD=", DoubleToString(dd, 2), "% >= ",
            DoubleToString(scaleHalfAtPct, 2), "%. Risk scaled to ",
            DoubleToString(scaled, 3), "%");
      return scaled;
   }
   return baseRiskPct;
}

//--- Journal logging
void BTCScalperJournal(const string message)
{
   int handle = FileOpen("BTCScalper/trades.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return;
   FileSeek(handle, 0, SEEK_END);
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   string timestamp = StringFormat("%04d.%02d.%02d %02d:%02d:%02d", t.year, t.mon, t.day, t.hour, t.min, t.sec);
   FileWrite(handle, timestamp, message);
   FileClose(handle);
}

void BTCScalperResetJournal()
{
   int handle = FileOpen("BTCScalper/trades.csv", FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return;
   FileWrite(handle, "timestamp", "event");
   FileClose(handle);
}

#endif
