#ifndef GOLDSCALPER_ASIAN_BREAKOUT_MQH
#define GOLDSCALPER_ASIAN_BREAKOUT_MQH

#include <Trade/Trade.mqh>
#include <GoldScalper/SessionTime.mqh>
#include <GoldScalper/RiskManager.mqh>
#include <GoldScalper/BreakoutRegimeFilter.mqh>

//+------------------------------------------------------------------+
//| Asian Session Breakout Strategy Module                            |
//|                                                                    |
//| Strategy:                                                          |
//|   1. Track high/low range during Asian session (default 22-05)     |
//|   2. At London open (default 07:00) place Buy Stop above range     |
//|      and Sell Stop below range with configurable buffer             |
//|   3. Cancel unfilled orders after London session ends (12:00)      |
//|   4. SL on opposite side of range, TP = range × RR multiplier     |
//|   5. Optional ATR-based trailing stop on filled orders             |
//|   6. Daily trade limit via GlobalVariable                          |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Helper: Check if current server hour falls within a session       |
//| Supports overnight wrapping (e.g. 22:00 - 05:00)                 |
//+------------------------------------------------------------------+
bool GoldScalperInSession(const int currentHour, const int startHour, const int endHour)
{
   if(startHour == endHour)
      return true; // Full 24-hour session (matches GoldScalperInHourRange behavior)
   if(startHour < endHour)
      return currentHour >= startHour && currentHour < endHour;
   // Overnight wrap: e.g. startHour=22, endHour=5
   return currentHour >= startHour || currentHour < endHour;
}

string GoldScalperBreakoutStateSuffix(const string statePrefix, const string stateName)
{
   if(statePrefix == "asian")
   {
      if(stateName == "high")
         return "asianHigh";
      if(stateName == "low")
         return "asianLow";
      if(stateName == "count")
         return "breakoutCount";
      if(stateName == "placed")
         return "breakoutOrdersPlaced";
   }

   if(stateName == "high")
      return statePrefix + "High";
   if(stateName == "low")
      return statePrefix + "Low";
   if(stateName == "count")
      return statePrefix + "BreakoutCount";
   if(stateName == "placed")
      return statePrefix + "BreakoutOrdersPlaced";

   return statePrefix + stateName;
}

string GoldScalperBreakoutStateKey(const string statePrefix, const string stateName)
{
   return GoldScalperDayKey(GoldScalperBreakoutStateSuffix(statePrefix, stateName));
}


//+------------------------------------------------------------------+
//| Helper: Calculate lot size from equity-percentage risk             |
//+------------------------------------------------------------------+
double GoldScalperABCalcLotSize(const string symbol, const double entryPrice, const double slPrice,
                              const double riskPct, const double minLot, const double maxLot)
{
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmount = equity * riskPct / 100.0;
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double slDistance = MathAbs(entryPrice - slPrice);

   if(slDistance <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0)
   {
      Print("[AsianBreakout] CalcLotSize: invalid params slDist=", slDistance,
            " tickVal=", tickValue, " tickSz=", tickSize);
      return 0.0;
   }

   double rawLot = (riskAmount * tickSize) / (slDistance * tickValue);
   double lot = GoldScalperNormalizeLot(symbol, rawLot, minLot, maxLot);

   Print("[AsianBreakout] LotCalc: equity=", DoubleToString(equity, 2),
         " risk%=", DoubleToString(riskPct, 2),
         " riskAmt=", DoubleToString(riskAmount, 2),
         " slDist=", DoubleToString(slDistance, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
         " rawLot=", DoubleToString(rawLot, 4),
         " lot=", DoubleToString(lot, 2));

   return lot;
}


//+------------------------------------------------------------------+
//| Init: Reset daily range tracking at EA start                      |
//+------------------------------------------------------------------+
void GoldScalperSessionBreakoutInit(const string statePrefix, const string label)
{
   string highKey   = GoldScalperBreakoutStateKey(statePrefix, "high");
   string lowKey    = GoldScalperBreakoutStateKey(statePrefix, "low");
   string countKey  = GoldScalperBreakoutStateKey(statePrefix, "count");
   string placedKey = GoldScalperBreakoutStateKey(statePrefix, "placed");

   if(GlobalVariableCheck(highKey))
      GlobalVariableDel(highKey);
   if(GlobalVariableCheck(lowKey))
      GlobalVariableDel(lowKey);
   if(GlobalVariableCheck(countKey))
      GlobalVariableDel(countKey);
   if(GlobalVariableCheck(placedKey))
      GlobalVariableDel(placedKey);

   Print("[", label, "] Init: daily state reset. Keys cleared: ", highKey, ", ", lowKey, ", ", countKey, ", ", placedKey);
}

void GoldScalperAsianBreakoutInit()
{
   GoldScalperSessionBreakoutInit("asian", "AsianBreakout");
}

void GoldScalperNyBreakoutInit()
{
   GoldScalperSessionBreakoutInit("ny", "NYBreakout");
}

//+------------------------------------------------------------------+
//| Return number of breakout trades placed today                     |
//+------------------------------------------------------------------+
int GoldScalperSessionBreakoutDailyCount(const string statePrefix)
{
   string key = GoldScalperBreakoutStateKey(statePrefix, "count");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

int GoldScalperAsianBreakoutDailyCount()
{
   return GoldScalperSessionBreakoutDailyCount("asian");
}

int GoldScalperNyBreakoutDailyCount()
{
   return GoldScalperSessionBreakoutDailyCount("ny");
}

//+------------------------------------------------------------------+
//| Internal: Increment the daily breakout counter                    |
//+------------------------------------------------------------------+
void GoldScalperMarkSessionBreakoutPlaced(const string statePrefix)
{
   string key = GoldScalperBreakoutStateKey(statePrefix, "count");
   int current = GoldScalperSessionBreakoutDailyCount(statePrefix);
   GlobalVariableSet(key, (double)(current + 1));
}

void GoldScalperMarkBreakoutPlaced()
{
   GoldScalperMarkSessionBreakoutPlaced("asian");
}

//+------------------------------------------------------------------+
//| Internal: Check/set the "orders already placed today" flag        |
//+------------------------------------------------------------------+
bool GoldScalperSessionBreakoutOrdersPlacedToday(const string statePrefix)
{
   string key = GoldScalperBreakoutStateKey(statePrefix, "placed");
   if(!GlobalVariableCheck(key))
      return false;
   return GlobalVariableGet(key) > 0.0;
}

bool GoldScalperBreakoutOrdersPlacedToday()
{
   return GoldScalperSessionBreakoutOrdersPlacedToday("asian");
}

bool GoldScalperNyBreakoutOrdersPlacedToday()
{
   return GoldScalperSessionBreakoutOrdersPlacedToday("ny");
}

void GoldScalperSetSessionBreakoutOrdersPlaced(const string statePrefix)
{
   string key = GoldScalperBreakoutStateKey(statePrefix, "placed");
   GlobalVariableSet(key, 1.0);
}

void GoldScalperSetBreakoutOrdersPlaced()
{
   GoldScalperSetSessionBreakoutOrdersPlaced("asian");
}

//+------------------------------------------------------------------+
//| Internal: Build a session range using M1 bars                     |
//| Scans closed M1 bars that fall within the configured window       |
//+------------------------------------------------------------------+
bool GoldScalperBuildSessionRange(const string symbol,
                                  const int rangeStartHour,
                                  const int rangeEndHour,
                                  const string statePrefix,
                                  const string label,
                                  double &sessionHigh,
                                  double &sessionLow)
{
   string highKey = GoldScalperBreakoutStateKey(statePrefix, "high");
   string lowKey  = GoldScalperBreakoutStateKey(statePrefix, "low");

   // Return cached range if already computed today
   if(GlobalVariableCheck(highKey) && GlobalVariableCheck(lowKey))
   {
      sessionHigh = GlobalVariableGet(highKey);
      sessionLow  = GlobalVariableGet(lowKey);
      if(sessionHigh > 0.0 && sessionLow > 0.0 && sessionHigh > sessionLow)
         return true;
   }

   // Calculate the number of M1 bars in the range session
   // For a session like 22:00-05:00 that's 7 hours = 420 M1 bars
   int sessionHours;
   if(rangeEndHour > rangeStartHour)
      sessionHours = rangeEndHour - rangeStartHour;
   else
      sessionHours = (24 - rangeStartHour) + rangeEndHour;

   int barsNeeded = sessionHours * 60 + 60; // extra margin

   MqlRates m1[];
   ArraySetAsSeries(m1, true);
   int copied = CopyRates(symbol, PERIOD_M1, 0, barsNeeded, m1);
   if(copied < sessionHours * 60)
   {
      Print("[", label, "] BuildRange: not enough M1 bars. copied=", copied,
            " needed=", sessionHours * 60);
      return false;
   }

   sessionHigh = 0.0;
   sessionLow  = DBL_MAX;
   int count = 0;

   for(int i = 0; i < copied; i++)
   {
      MqlDateTime barTime;
      TimeToStruct(m1[i].time, barTime);

      if(!GoldScalperInSession(barTime.hour, rangeStartHour, rangeEndHour))
         continue;

      // Only count bars from today's range session (or last night's start)
      // For overnight sessions starting at e.g. 22:00, the start portion
      // falls on the previous calendar day
      if(barTime.hour >= rangeStartHour && rangeStartHour > rangeEndHour)
      {
         // This bar is from the "start" portion (e.g. 22:00-23:59) - could be yesterday
         // We accept it as long as it's the most recent occurrence
      }

      if(m1[i].high > sessionHigh)
         sessionHigh = m1[i].high;
      if(m1[i].low < sessionLow)
         sessionLow = m1[i].low;
      count++;
   }

   if(count < 10 || sessionHigh <= 0.0 || sessionLow >= DBL_MAX || sessionHigh <= sessionLow)
   {
      Print("[", label, "] BuildRange: insufficient session bars. count=", count,
            " high=", DoubleToString(sessionHigh, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
            " low=", DoubleToString(sessionLow, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)));
      return false;
   }

   // Cache the range
   GlobalVariableSet(highKey, sessionHigh);
   GlobalVariableSet(lowKey, sessionLow);

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   Print("[", label, "] Range built: high=", DoubleToString(sessionHigh, digits),
         " low=", DoubleToString(sessionLow, digits),
         " width=", DoubleToString(sessionHigh - sessionLow, digits),
         " bars=", count);

   return true;
}

bool GoldScalperBuildAsianRange(const string symbol, const int asianStartHour, const int asianEndHour,
                                double &asianHigh, double &asianLow)
{
   return GoldScalperBuildSessionRange(symbol, asianStartHour, asianEndHour, "asian", "AsianBreakout", asianHigh, asianLow);
}

bool GoldScalperBuildNyRange(const string symbol, const int rangeStartHour, const int rangeEndHour,
                             double &rangeHigh, double &rangeLow)
{
   return GoldScalperBuildSessionRange(symbol, rangeStartHour, rangeEndHour, "ny", "NYBreakout", rangeHigh, rangeLow);
}

//+------------------------------------------------------------------+
//| Internal: Cancel all pending orders for this symbol/magic         |
//+------------------------------------------------------------------+
void GoldScalperCancelPendingOrders(const string symbol, const long magic, CTrade &trade)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol || OrderGetInteger(ORDER_MAGIC) != magic)
         continue;

      if(trade.OrderDelete(ticket))
         Print("[AsianBreakout] Pending order cancelled: ticket=", ticket);
      else
         Print("[AsianBreakout] Failed to cancel order: ticket=", ticket,
               " retcode=", (int)trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
}

string GoldScalperBreakoutCommentRoot(const string commentPrefix)
{
   int len = StringLen(commentPrefix);
   if(len > 0 && StringSubstr(commentPrefix, len - 1, 1) == "_")
      return StringSubstr(commentPrefix, 0, len - 1);
   return commentPrefix;
}

bool GoldScalperBreakoutCommentMatchesSession(const string comment, const string commentPrefix)
{
   if(StringFind(comment, commentPrefix) >= 0)
      return true;

   string root = GoldScalperBreakoutCommentRoot(commentPrefix);
   return root != "" && StringFind(comment, root) >= 0;
}

bool GoldScalperBreakoutCommentIsAny(const string comment)
{
   return StringFind(comment, "ABrk") >= 0 || StringFind(comment, "NYBrk") >= 0;
}

bool GoldScalperBreakoutCommentIsRunner(const string comment)
{
   return StringFind(comment, "ABrkRun_") >= 0 || StringFind(comment, "NYBrkRun_") >= 0;
}

string GoldScalperBreakoutRunnerRiskKey(const ulong ticket)
{
   return "GoldScalper_runnerRisk_" + IntegerToString((long)ticket);
}

string GoldScalperBreakoutRunnerMfeKey(const ulong ticket)
{
   return "GoldScalper_runnerMfeR_" + IntegerToString((long)ticket);
}

void GoldScalperBreakoutRunnerClearState(const ulong ticket)
{
   string riskKey = GoldScalperBreakoutRunnerRiskKey(ticket);
   if(GlobalVariableCheck(riskKey))
      GlobalVariableDel(riskKey);

   string mfeKey = GoldScalperBreakoutRunnerMfeKey(ticket);
   if(GlobalVariableCheck(mfeKey))
      GlobalVariableDel(mfeKey);
}

double GoldScalperBreakoutRunnerRiskDistance(const ulong ticket,
                                             const double openPrice,
                                             const double currentSL,
                                             const double point)
{
   string riskKey = GoldScalperBreakoutRunnerRiskKey(ticket);
   if(GlobalVariableCheck(riskKey))
   {
      double storedRisk = GlobalVariableGet(riskKey);
      if(storedRisk > point)
         return storedRisk;
   }

   double riskDistance = MathAbs(openPrice - currentSL);
   if(riskDistance > point)
      GlobalVariableSet(riskKey, riskDistance);
   return riskDistance;
}

double GoldScalperBreakoutRunnerUpdateMfeR(const ulong ticket, const double rMultiple)
{
   double currentMfe = MathMax(0.0, rMultiple);
   string mfeKey = GoldScalperBreakoutRunnerMfeKey(ticket);
   if(GlobalVariableCheck(mfeKey))
      currentMfe = MathMax(currentMfe, GlobalVariableGet(mfeKey));
   GlobalVariableSet(mfeKey, currentMfe);
   return currentMfe;
}

bool GoldScalperModifyPositionByTicket(const ulong ticket,
                                       const string symbol,
                                       const double sl,
                                       const double tp)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = symbol;
   request.sl = sl;
   request.tp = tp;

   if(!OrderSend(request, result))
      return false;

   return result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED;
}

bool GoldScalperClosePositionByTicket(const ulong ticket,
                                      const string symbol,
                                      const long type,
                                      const double volume,
                                      const double price,
                                      const long magic)
{
   MqlTradeRequest request;
   MqlTradeResult result;
   ZeroMemory(request);
   ZeroMemory(result);

   request.action = TRADE_ACTION_DEAL;
   request.position = ticket;
   request.symbol = symbol;
   request.volume = volume;
   request.magic = magic;
   request.type = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   request.price = price;
   request.deviation = 30;
   request.type_filling = ORDER_FILLING_IOC;

   if(!OrderSend(request, result))
      return false;

   return result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED;
}

int GoldScalperCloseBreakoutPositionsForRisk(const string symbol,
                                             const long magic,
                                             const bool runnerOnly,
                                             const string reason)
{
   int closed = 0;
   int attempted = 0;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol || PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      string comment = PositionGetString(POSITION_COMMENT);
      bool isRunner = GoldScalperBreakoutCommentIsRunner(comment);
      if(runnerOnly && !isRunner)
         continue;
      if(!runnerOnly && !GoldScalperBreakoutCommentIsAny(comment))
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double price = type == POSITION_TYPE_BUY
         ? SymbolInfoDouble(symbol, SYMBOL_BID)
         : SymbolInfoDouble(symbol, SYMBOL_ASK);

      attempted++;
      if(GoldScalperClosePositionByTicket(ticket, symbol, type, volume, price, magic))
      {
         closed++;
         if(isRunner)
            GoldScalperBreakoutRunnerClearState(ticket);
         GoldScalperJournal("DD hard close: ticket=" + IntegerToString((long)ticket)
            + " runner=" + IntegerToString(isRunner ? 1 : 0)
            + " reason=" + reason
            + " price=" + DoubleToString(price, digits));
      }
      else
      {
         GoldScalperJournal("DD hard close FAILED: ticket=" + IntegerToString((long)ticket)
            + " runner=" + IntegerToString(isRunner ? 1 : 0)
            + " reason=" + reason);
      }
   }

   if(attempted > 0)
      GoldScalperJournal("DD hard close summary: attempted=" + IntegerToString(attempted)
         + " closed=" + IntegerToString(closed)
         + " runnerOnly=" + IntegerToString(runnerOnly ? 1 : 0)
         + " reason=" + reason);

   return closed;
}

void GoldScalperCancelPendingOrdersByPrefix(const string symbol,
                                            const long magic,
                                            CTrade &trade,
                                            const string commentPrefix)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol || OrderGetInteger(ORDER_MAGIC) != magic)
         continue;

      string comment = OrderGetString(ORDER_COMMENT);
      if(!GoldScalperBreakoutCommentMatchesSession(comment, commentPrefix))
         continue;

      if(trade.OrderDelete(ticket))
         Print("[AsianBreakout] Pending order cancelled: ticket=", ticket);
      else
         Print("[AsianBreakout] Failed to cancel order: ticket=", ticket,
               " retcode=", (int)trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Internal: Count active pending orders for this symbol/magic       |
//+------------------------------------------------------------------+
int GoldScalperABCountPendingOrders(const string symbol, const long magic)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) == symbol && OrderGetInteger(ORDER_MAGIC) == magic)
         count++;
   }
   return count;
}

int GoldScalperABCountPendingOrdersByPrefix(const string symbol,
                                            const long magic,
                                            const string commentPrefix)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol || OrderGetInteger(ORDER_MAGIC) != magic)
         continue;

      string comment = OrderGetString(ORDER_COMMENT);
      if(GoldScalperBreakoutCommentMatchesSession(comment, commentPrefix))
         count++;
   }
   return count;
}


//+------------------------------------------------------------------+
//| Internal: Count active positions for this symbol/magic            |
//+------------------------------------------------------------------+
int GoldScalperCountPositions(const string symbol, const long magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) == symbol && PositionGetInteger(POSITION_MAGIC) == magic)
         count++;
   }
   return count;
}

bool GoldScalperPlaceBreakoutStop(CTrade &trade,
                                  const string symbol,
                                  const string journalLabel,
                                  const string orderCommentPrefix,
                                  const string journalRole,
                                  const bool isBuy,
                                  const double lot,
                                  const double entry,
                                  const double sl,
                                  const double tp,
                                  const datetime expiration,
                                  const int digits)
{
   if(lot <= 0.0)
      return false;

   string direction = isBuy ? "Buy" : "Sell";
   string roleText = journalRole == "" ? "" : journalRole + " ";
   string comment = StringFormat("%s%s_%s", orderCommentPrefix, direction, TimeToString(TimeCurrent(), TIME_DATE));

   Print("[", journalLabel, "] Placing ", roleText, direction, " Stop: entry=", DoubleToString(entry, digits),
         " sl=", DoubleToString(sl, digits),
         " tp=", DoubleToString(tp, digits),
         " lot=", DoubleToString(lot, 2),
         " exp=", TimeToString(expiration, TIME_DATE | TIME_SECONDS));

   bool ok = isBuy
      ? trade.BuyStop(lot, entry, symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration, comment)
      : trade.SellStop(lot, entry, symbol, sl, tp, ORDER_TIME_SPECIFIED, expiration, comment);

   if(ok)
   {
      ulong orderTicket = trade.ResultOrder();
      Print("[", journalLabel, "] ", roleText, direction, " Stop placed successfully: ticket=", orderTicket);
      GoldScalperJournal(StringFormat("%s %s%s Stop placed: entry=%.2f sl=%.2f tp=%.2f lot=%.2f ticket=%I64u",
         journalLabel, roleText, direction, entry, sl, tp, lot, orderTicket));
      return true;
   }

   Print("[", journalLabel, "] ", roleText, direction, " Stop FAILED: retcode=", (int)trade.ResultRetcode(),
         " ", trade.ResultRetcodeDescription());
   GoldScalperJournal(StringFormat("%s %s%s Stop FAILED: entry=%.2f sl=%.2f tp=%.2f lot=%.2f retcode=%d %s",
      journalLabel, roleText, direction, entry, sl, tp, lot, (int)trade.ResultRetcode(), trade.ResultRetcodeDescription()));
   return false;
}

//+------------------------------------------------------------------+
//| Main: Called on each new M1 bar                                   |
//| Handles range building, order placement, and order management     |
//+------------------------------------------------------------------+
void GoldScalperSessionBreakoutOnNewBar(const string symbol, const long magic, CTrade &trade,
   const string journalLabel, const string statePrefix, const string commentPrefix,
   const int rangeStartHour, const int rangeEndHour,
   const int breakoutStartHour, const int breakoutEndHour,
   const double breakoutBuffer, const double minRange, const double maxRange,
   const double breakoutRR, const bool trailAtr,
   const int maxTrades, const double riskPct, const double minLot, const double maxLot,
   const bool regimeFilter, const bool directionFilter,
   const double regimeAdxMin, const double regimeAdxMax,
   const double regimeRangeAtrMin, const double regimeRangeAtrMax,
   const double regimePriorDayAtrMax,
   const bool runnerEnabled, const double runnerCoreRiskShare,
   const double runnerCoreRR, const double runnerRR)
{
   trade.SetExpertMagicNumber(magic);

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int currentHour = now.hour;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.01;

   //--- Phase 1: During range session, build the range
   if(GoldScalperInSession(currentHour, rangeStartHour, rangeEndHour))
   {
      // Range is being built on-the-fly using M1 bars
      // The actual build happens when we need it (lazy via BuildAsianRange)
      // During the session, invalidate any stale cached range
      // so it gets rebuilt fresh once the session ends
      string highKey = GoldScalperBreakoutStateKey(statePrefix, "high");
      string lowKey  = GoldScalperBreakoutStateKey(statePrefix, "low");

      // Continuously update range during the session
      MqlRates m1[];
      ArraySetAsSeries(m1, true);
      if(CopyRates(symbol, PERIOD_M1, 0, 1, m1) < 1)
         return;

      double currentHigh = m1[0].high;
      double currentLow  = m1[0].low;

      if(GlobalVariableCheck(highKey))
      {
         double storedHigh = GlobalVariableGet(highKey);
         if(currentHigh > storedHigh)
            GlobalVariableSet(highKey, currentHigh);
      }
      else
         GlobalVariableSet(highKey, currentHigh);

      if(GlobalVariableCheck(lowKey))
      {
         double storedLow = GlobalVariableGet(lowKey);
         if(currentLow < storedLow)
            GlobalVariableSet(lowKey, currentLow);
      }
      else
         GlobalVariableSet(lowKey, currentLow);

      return; // Nothing else to do during Asian session
   }

   //--- Phase 2: At breakout open, place pending breakout orders
   if(currentHour == breakoutStartHour && !GoldScalperSessionBreakoutOrdersPlacedToday(statePrefix))
   {
      // Check daily trade limit
      int dailyCount = GoldScalperSessionBreakoutDailyCount(statePrefix);
      if(maxTrades > 0 && dailyCount >= maxTrades)
      {
         Print("[", journalLabel, "] Daily limit reached: count=", dailyCount, " max=", maxTrades);
         GoldScalperSetSessionBreakoutOrdersPlaced(statePrefix); // prevent further attempts
         return;
      }

      // Build/retrieve the range
      double rangeHigh = 0.0, rangeLow = 0.0;
      if(!GoldScalperBuildSessionRange(symbol, rangeStartHour, rangeEndHour, statePrefix, journalLabel, rangeHigh, rangeLow))
      {
         Print("[", journalLabel, "] Cannot build range - skipping order placement");
         return;
      }

      double rangeWidth = rangeHigh - rangeLow;
      double rangeWidthPoints = rangeWidth / point;

      Print("[", journalLabel, "] Range check: width=", DoubleToString(rangeWidth, digits),
            " widthPts=", DoubleToString(rangeWidthPoints, 1),
            " min=", DoubleToString(minRange, 1),
            " max=", DoubleToString(maxRange, 1));

      // Validate range width
      if(rangeWidthPoints < minRange || rangeWidthPoints > maxRange)
      {
         Print("[", journalLabel, "] Range width ", DoubleToString(rangeWidthPoints, 1),
               " points outside [", DoubleToString(minRange, 1), "-",
               DoubleToString(maxRange, 1), "] - skipping this bar (will retry)");
         // NOTE: Do NOT mark orders placed here.
         // Allow the EA to retry on the next M1 bar within the breakout open hour.
         return;
      }

      string regimeReason = "";
      ENUM_GS_BREAKOUT_DECISION regimeDecision = GoldScalperBreakoutRegimeEvaluate(
         symbol,
         regimeFilter,
         directionFilter,
         rangeWidth,
         regimeAdxMin,
         regimeAdxMax,
         regimeRangeAtrMin,
         regimeRangeAtrMax,
         regimePriorDayAtrMax,
         regimeReason);

      if(regimeDecision == GS_BREAKOUT_SKIP)
      {
         Print("[", journalLabel, "] Regime filter skipped breakout: ", regimeReason);
         GoldScalperJournal(StringFormat("%s regime skip reason=%s", journalLabel, regimeReason));
         GoldScalperSetSessionBreakoutOrdersPlaced(statePrefix);
         return;
      }

      bool allowBuy = (regimeDecision == GS_BREAKOUT_BOTH || regimeDecision == GS_BREAKOUT_BUY_ONLY);
      bool allowSell = (regimeDecision == GS_BREAKOUT_BOTH || regimeDecision == GS_BREAKOUT_SELL_ONLY);
      if(regimeFilter)
      {
         Print("[", journalLabel, "] Regime filter pass: ", regimeReason);
         GoldScalperJournal(StringFormat("%s regime pass %s", journalLabel, regimeReason));
      }

      // Calculate entry prices
      double bufferPrice = breakoutBuffer * point;
      double buyEntry  = NormalizeDouble(rangeHigh + bufferPrice, digits);
      double sellEntry = NormalizeDouble(rangeLow - bufferPrice, digits);

      // SL: opposite side of range
      double buySL  = NormalizeDouble(rangeLow - bufferPrice, digits);
      double sellSL = NormalizeDouble(rangeHigh + bufferPrice, digits);

      bool useRunner = runnerEnabled;
      double coreRiskShare = MathMax(0.0, MathMin(runnerCoreRiskShare, 1.0));
      double runnerRiskShare = 1.0 - coreRiskShare;
      if(!useRunner || coreRiskShare <= 0.0 || runnerRiskShare <= 0.0)
      {
         useRunner = false;
         coreRiskShare = 1.0;
         runnerRiskShare = 0.0;
      }

      double coreRR = (useRunner && runnerCoreRR > 0.0) ? runnerCoreRR : breakoutRR;
      double coreTpDistance = rangeWidth * coreRR;
      double buyCoreTP  = NormalizeDouble(buyEntry + coreTpDistance, digits);
      double sellCoreTP = NormalizeDouble(sellEntry - coreTpDistance, digits);

      double buyRunnerTP = 0.0;
      double sellRunnerTP = 0.0;
      if(useRunner && runnerRR > 0.0)
      {
         double runnerTpDistance = rangeWidth * runnerRR;
         buyRunnerTP = NormalizeDouble(buyEntry + runnerTpDistance, digits);
         sellRunnerTP = NormalizeDouble(sellEntry - runnerTpDistance, digits);
      }

      double buyCoreLot  = allowBuy ? GoldScalperABCalcLotSize(symbol, buyEntry, buySL, riskPct * coreRiskShare, minLot, maxLot) : 0.0;
      double sellCoreLot = allowSell ? GoldScalperABCalcLotSize(symbol, sellEntry, sellSL, riskPct * coreRiskShare, minLot, maxLot) : 0.0;
      double buyRunnerLot  = (allowBuy && useRunner) ? GoldScalperABCalcLotSize(symbol, buyEntry, buySL, riskPct * runnerRiskShare, minLot, maxLot) : 0.0;
      double sellRunnerLot = (allowSell && useRunner) ? GoldScalperABCalcLotSize(symbol, sellEntry, sellSL, riskPct * runnerRiskShare, minLot, maxLot) : 0.0;

      // Expiration: London session end
      MqlDateTime expDt;
      TimeToStruct(TimeCurrent(), expDt);
      expDt.hour = breakoutEndHour;
      expDt.min  = 0;
      expDt.sec  = 0;
      datetime expiration = StructToTime(expDt);
      if(expiration <= TimeCurrent())
         expiration = TimeCurrent() + (breakoutEndHour - currentHour) * 3600;

      bool anyPlaced = false;

      string sessionRoot = GoldScalperBreakoutCommentRoot(commentPrefix);
      string corePrefix = useRunner ? sessionRoot + "Core_" : commentPrefix;
      string runnerPrefix = sessionRoot + "Run_";

      if(allowBuy)
      {
         if(GoldScalperPlaceBreakoutStop(trade, symbol, journalLabel, corePrefix, useRunner ? "Core" : "",
               true, buyCoreLot, buyEntry, buySL, buyCoreTP, expiration, digits))
         {
            GoldScalperMarkSessionBreakoutPlaced(statePrefix);
            anyPlaced = true;
         }

         if(useRunner && GoldScalperPlaceBreakoutStop(trade, symbol, journalLabel, runnerPrefix, "Runner",
               true, buyRunnerLot, buyEntry, buySL, buyRunnerTP, expiration, digits))
         {
            GoldScalperMarkSessionBreakoutPlaced(statePrefix);
            anyPlaced = true;
         }
      }

      if(allowSell)
      {
         if(GoldScalperPlaceBreakoutStop(trade, symbol, journalLabel, corePrefix, useRunner ? "Core" : "",
               false, sellCoreLot, sellEntry, sellSL, sellCoreTP, expiration, digits))
         {
            GoldScalperMarkSessionBreakoutPlaced(statePrefix);
            anyPlaced = true;
         }

         if(useRunner && GoldScalperPlaceBreakoutStop(trade, symbol, journalLabel, runnerPrefix, "Runner",
               false, sellRunnerLot, sellEntry, sellSL, sellRunnerTP, expiration, digits))
         {
            GoldScalperMarkSessionBreakoutPlaced(statePrefix);
            anyPlaced = true;
         }
      }

      GoldScalperSetSessionBreakoutOrdersPlaced(statePrefix);

      if(anyPlaced)
         Print("[", journalLabel, "] Breakout orders placed. Daily count=", GoldScalperSessionBreakoutDailyCount(statePrefix));
      else
         Print("[", journalLabel, "] No breakout orders could be placed this session");

      return;
   }

   //--- Phase 3: After breakout session ends, cancel unfilled pending orders
   if(currentHour >= breakoutEndHour && !GoldScalperInSession(currentHour, breakoutStartHour, breakoutEndHour))
   {
      int pendingCount = GoldScalperABCountPendingOrdersByPrefix(symbol, magic, commentPrefix);
      if(pendingCount > 0)
      {
         Print("[", journalLabel, "] Breakout session ended (hour=", currentHour,
               "). Cancelling ", pendingCount, " unfilled pending orders.");
         GoldScalperCancelPendingOrdersByPrefix(symbol, magic, trade, commentPrefix);
         GoldScalperJournal(StringFormat("%s cancelled %d unfilled pending orders after session close",
            journalLabel, pendingCount));
      }
   }
}

void GoldScalperAsianBreakoutOnNewBar(const string symbol, const long magic, CTrade &trade,
   const int asianStartHour, const int asianEndHour,
   const int londonStartHour, const int londonEndHour,
   const double breakoutBuffer, const double minRange, const double maxRange,
   const double breakoutRR, const bool trailAtr,
   const int maxTrades, const double riskPct, const double minLot, const double maxLot,
   const bool regimeFilter, const bool directionFilter,
   const double regimeAdxMin, const double regimeAdxMax,
   const double regimeRangeAtrMin, const double regimeRangeAtrMax,
   const double regimePriorDayAtrMax,
   const bool runnerEnabled, const double runnerCoreRiskShare,
   const double runnerCoreRR, const double runnerRR)
{
   GoldScalperSessionBreakoutOnNewBar(
      symbol, magic, trade,
      "Asian Breakout", "asian", "ABrk_",
      asianStartHour, asianEndHour,
      londonStartHour, londonEndHour,
      breakoutBuffer, minRange, maxRange,
      breakoutRR, trailAtr,
      maxTrades, riskPct, minLot, maxLot,
      regimeFilter, directionFilter,
      regimeAdxMin, regimeAdxMax,
      regimeRangeAtrMin, regimeRangeAtrMax,
      regimePriorDayAtrMax,
      runnerEnabled, runnerCoreRiskShare, runnerCoreRR, runnerRR);
}

void GoldScalperNyBreakoutOnNewBar(const string symbol, const long magic, CTrade &trade,
   const int rangeStartHour, const int rangeEndHour,
   const int breakoutStartHour, const int breakoutEndHour,
   const double breakoutBuffer, const double minRange, const double maxRange,
   const double breakoutRR, const bool trailAtr,
   const int maxTrades, const double riskPct, const double minLot, const double maxLot,
   const bool regimeFilter, const bool directionFilter,
   const double regimeAdxMin, const double regimeAdxMax,
   const double regimeRangeAtrMin, const double regimeRangeAtrMax,
   const double regimePriorDayAtrMax,
   const bool runnerEnabled, const double runnerCoreRiskShare,
   const double runnerCoreRR, const double runnerRR)
{
   GoldScalperSessionBreakoutOnNewBar(
      symbol, magic, trade,
      "NY Breakout", "ny", "NYBrk_",
      rangeStartHour, rangeEndHour,
      breakoutStartHour, breakoutEndHour,
      breakoutBuffer, minRange, maxRange,
      breakoutRR, trailAtr,
      maxTrades, riskPct, minLot, maxLot,
      regimeFilter, directionFilter,
      regimeAdxMin, regimeAdxMax,
      regimeRangeAtrMin, regimeRangeAtrMax,
      regimePriorDayAtrMax,
      runnerEnabled, runnerCoreRiskShare, runnerCoreRR, runnerRR);
}

void GoldScalperManageBreakoutRunnerPosition(const string symbol,
                                             CTrade &trade,
                                             const ulong ticket,
                                             const long magic,
                                             const long type,
                                             const double openPrice,
                                             const double volume,
                                             double currentSL,
                                             const double currentTP,
                                             const double price,
                                             const double atrValue,
                                             const double point,
                                             const int digits,
                                             const double beTriggerR,
                                             const double trailStartR,
                                             const double trailAtrMult,
                                             const int maxHoldHours,
                                             const bool profitLock,
                                             const double mfeTrailStartR,
                                             const double mfeLockPct,
                                             const double minLockedR)
{
   double riskDistance = GoldScalperBreakoutRunnerRiskDistance(ticket, openPrice, currentSL, point);
   if(riskDistance <= point)
      return;

   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
   if(maxHoldHours > 0 && openTime > 0 && TimeCurrent() - openTime >= maxHoldHours * 3600)
   {
      if(GoldScalperClosePositionByTicket(ticket, symbol, type, volume, price, magic))
      {
         GoldScalperBreakoutRunnerClearState(ticket);
         GoldScalperJournal("Runner max-hold close: ticket=" + IntegerToString((long)ticket)
            + " holdHours=" + IntegerToString(maxHoldHours)
            + " price=" + DoubleToString(price, digits));
      }
      return;
   }

   double profitDistance = (type == POSITION_TYPE_BUY) ? price - openPrice : openPrice - price;
   double rMultiple = profitDistance / riskDistance;
   double mfeR = GoldScalperBreakoutRunnerUpdateMfeR(ticket, rMultiple);

   if(beTriggerR > 0.0 && rMultiple >= beTriggerR)
   {
      double beSL = NormalizeDouble(openPrice, digits);
      bool shouldMoveBE = (type == POSITION_TYPE_BUY)
         ? (currentSL <= 0.0 || currentSL < beSL - point)
         : (currentSL <= 0.0 || currentSL > beSL + point);

      if(shouldMoveBE && GoldScalperModifyPositionByTicket(ticket, symbol, beSL, currentTP))
      {
         currentSL = beSL;
         GoldScalperJournal("Runner BE moved: ticket=" + IntegerToString((long)ticket)
            + " newSL=" + DoubleToString(beSL, digits)
            + " r=" + DoubleToString(rMultiple, 2));
      }
   }

   if(profitLock && mfeTrailStartR > 0.0 && mfeLockPct > 0.0 && mfeR >= mfeTrailStartR)
   {
      double lockedR = MathMax(minLockedR, mfeR * mfeLockPct);
      double lockSL = 0.0;
      bool shouldLock = false;

      if(type == POSITION_TYPE_BUY)
      {
         double rawSL = openPrice + riskDistance * lockedR;
         lockSL = NormalizeDouble(MathMin(rawSL, price - point), digits);
         shouldLock = lockSL > openPrice && (currentSL <= 0.0 || lockSL > currentSL + point);
      }
      else
      {
         double rawSL = openPrice - riskDistance * lockedR;
         lockSL = NormalizeDouble(MathMax(rawSL, price + point), digits);
         shouldLock = lockSL < openPrice && (currentSL <= 0.0 || lockSL < currentSL - point);
      }

      if(shouldLock && GoldScalperModifyPositionByTicket(ticket, symbol, lockSL, currentTP))
      {
         currentSL = lockSL;
         GoldScalperJournal("Runner MFE profit-lock: ticket=" + IntegerToString((long)ticket)
            + " newSL=" + DoubleToString(lockSL, digits)
            + " mfeR=" + DoubleToString(mfeR, 2)
            + " lockedR=" + DoubleToString(lockedR, 2));
      }
   }

   if(trailStartR <= 0.0 || rMultiple < trailStartR || atrValue <= 0.0 || trailAtrMult <= 0.0)
      return;

   double trailDistance = atrValue * trailAtrMult;
   double newSL = 0.0;
   bool shouldTrail = false;

   if(type == POSITION_TYPE_BUY)
   {
      newSL = NormalizeDouble(price - trailDistance, digits);
      shouldTrail = newSL > openPrice && (currentSL <= 0.0 || newSL > currentSL + point);
   }
   else
   {
      newSL = NormalizeDouble(price + trailDistance, digits);
      shouldTrail = newSL < openPrice && (currentSL <= 0.0 || newSL < currentSL - point);
   }

   if(shouldTrail && GoldScalperModifyPositionByTicket(ticket, symbol, newSL, currentTP))
   {
      GoldScalperJournal("Runner ATR trail: ticket=" + IntegerToString((long)ticket)
         + " newSL=" + DoubleToString(newSL, digits)
         + " atr=" + DoubleToString(atrValue, digits)
         + " r=" + DoubleToString(rMultiple, 2));
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stops on filled breakout orders (called per tick) |
//| Uses ATR(M5, 14) × 1.5 as trailing distance                      |
//+------------------------------------------------------------------+
void GoldScalperAsianBreakoutManage(const string symbol,
                                    const long magic,
                                    CTrade &trade,
                                    const bool trailAtr,
                                    const bool runnerEnabled,
                                    const double runnerBETriggerR,
                                    const double runnerTrailStartR,
                                    const double runnerTrailAtrMult,
                                    const int runnerMaxHoldHours,
                                    const bool runnerProfitLock,
                                    const double runnerMfeTrailStartR,
                                    const double runnerMfeLockPct,
                                    const double runnerMinLockedR)
{
   if(!trailAtr && !runnerEnabled)
      return;

   trade.SetExpertMagicNumber(magic);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.01;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   // Get ATR(M5, 14) for trailing distance
   int atrHandle = iATR(symbol, PERIOD_M5, 14);
   double atrValue = 0.0;
   if(atrHandle == INVALID_HANDLE)
   {
      Print("[AsianBreakout] Manage: ATR handle invalid");
   }
   else
   {
      double atrBuffer[];
      ArraySetAsSeries(atrBuffer, true);
      if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) == 1)
         atrValue = atrBuffer[0];
      IndicatorRelease(atrHandle);
   }

   bool canTrailAtr = trailAtr && atrValue > 0.0;
   if(!canTrailAtr && !runnerEnabled)
      return;

   double trailDistance = canTrailAtr ? atrValue * 1.5 : 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol || PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      // Only trail positions that have breakout-style comments
      string comment = PositionGetString(POSITION_COMMENT);
      if(!GoldScalperBreakoutCommentIsAny(comment))
         continue;

      long type       = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume    = PositionGetDouble(POSITION_VOLUME);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      double price = type == POSITION_TYPE_BUY
         ? SymbolInfoDouble(symbol, SYMBOL_BID)
         : SymbolInfoDouble(symbol, SYMBOL_ASK);

      if(GoldScalperBreakoutCommentIsRunner(comment))
      {
         if(runnerEnabled)
            GoldScalperManageBreakoutRunnerPosition(
               symbol, trade, ticket, magic, type, openPrice, volume, currentSL, currentTP,
               price, atrValue, point, digits,
               runnerBETriggerR, runnerTrailStartR, runnerTrailAtrMult,
               runnerMaxHoldHours,
               runnerProfitLock, runnerMfeTrailStartR,
               runnerMfeLockPct, runnerMinLockedR);
         continue;
      }

      if(!canTrailAtr)
         continue;

      // Calculate new trailing SL
      double newSL;
      if(type == POSITION_TYPE_BUY)
      {
         newSL = NormalizeDouble(price - trailDistance, digits);
         // Only trail if position is in profit and new SL improves
         if(newSL <= openPrice)
            continue; // Not yet in enough profit to trail
         if(currentSL > 0.0 && newSL <= currentSL + point)
            continue; // New SL doesn't improve
      }
      else // POSITION_TYPE_SELL
      {
         newSL = NormalizeDouble(price + trailDistance, digits);
         // Only trail if position is in profit and new SL improves
         if(newSL >= openPrice)
            continue;
         if(currentSL > 0.0 && newSL >= currentSL - point)
            continue;
      }

      if(trade.PositionModify(ticket, newSL, currentTP))
      {
         Print("[AsianBreakout] Trail SL moved: ticket=", ticket,
               " type=", (type == POSITION_TYPE_BUY ? "BUY" : "SELL"),
               " price=", DoubleToString(price, digits),
               " oldSL=", DoubleToString(currentSL, digits),
               " newSL=", DoubleToString(newSL, digits),
               " atr=", DoubleToString(atrValue, digits),
               " trailDist=", DoubleToString(trailDistance, digits));
         GoldScalperJournal(StringFormat("Trail SL: ticket=%I64u newSL=%.2f atr=%.2f", ticket, newSL, atrValue));
      }
   }
}

#endif
