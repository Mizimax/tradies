#ifndef PROPGUARD_RISKBUDGET_MQH
#define PROPGUARD_RISKBUDGET_MQH

//+------------------------------------------------------------------+
//| RiskBudget.mqh -- anti-ruin position-sizing invariant             |
//| Part of PropGuard EA. See mt5/backtests/PROPGUARD_DESIGN.md §3    |
//| and the approved plan §5a.                                        |
//+------------------------------------------------------------------+

//--- Never risk more than basePct of equity, nor more than 1/dailyDivisor of the remaining
//--- daily budget, nor more than 1/totalDivisor of the remaining max-drawdown budget, on a
//--- single trade. All three clamps are evaluated every trade; the tightest wins.
double PropGuardRiskCash(const double equity,
                          const double basePct,
                          const double dailyFloor,
                          const double hardFloor,
                          const int dailyDivisor=3,
                          const int totalDivisor=8)
  {
   double byBase  = equity*basePct/100.0;
   double byDaily = (dailyDivisor>0) ? (equity-dailyFloor)/dailyDivisor : DBL_MAX;
   double byTotal = (totalDivisor>0) ? (equity-hardFloor)/totalDivisor : DBL_MAX;
   double riskCash = MathMin(byBase, MathMin(byDaily, byTotal));
   return (riskCash>0.0 ? riskCash : 0.0);
  }

double PropGuardNormalizeLot(const string symbol,const double rawLot,const double minLot,const double maxLot)
  {
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double brokerMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double brokerMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(step<=0.0) step=0.01;
   double low = MathMax(minLot, brokerMin);
   double high = MathMin(maxLot, brokerMax);
   double clamped = MathMax(low, MathMin(rawLot, high));
   return NormalizeDouble(MathRound(clamped/step)*step, 2);
  }

//--- Stop-distance-aware sizing (the property GoldBot's InpLotPer100Usd lacks). Takes
//--- riskCash directly -- callers compute riskCash via PropGuardRiskCash() above first, so
//--- this function stays a pure unit conversion. Adapted from
//--- mt5/Include/GoldScalper/RiskManager.mqh:12-41 (GoldScalperCalculateLot).
double PropGuardCalculateLot(const string symbol,
                              const double entryPrice,
                              const double slPrice,
                              const double riskCash,
                              const double minLot,
                              const double maxLot)
  {
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue<=0.0 || tickSize<=0.0 || riskCash<=0.0)
      return 0.0;
   double slDistance = MathAbs(entryPrice-slPrice);
   if(slDistance<=0.0)
      return 0.0;
   double rawLot = (riskCash*tickSize)/(slDistance*tickValue);
   return PropGuardNormalizeLot(symbol, rawLot, minLot, maxLot);
  }

#endif
