#ifndef GOLDSCALPER_ASIAN_BREAKOUT_MQH
#define GOLDSCALPER_ASIAN_BREAKOUT_MQH

#include <Trade/Trade.mqh>
#include <GoldScalper/SessionTime.mqh>
#include <GoldScalper/RiskManager.mqh>

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
void GoldScalperAsianBreakoutInit()
{
   // Reset today's range values to force a fresh scan
   string highKey   = GoldScalperDayKey("asianHigh");
   string lowKey    = GoldScalperDayKey("asianLow");
   string countKey  = GoldScalperDayKey("breakoutCount");
   string placedKey = GoldScalperDayKey("breakoutOrdersPlaced");

   if(GlobalVariableCheck(highKey))
      GlobalVariableDel(highKey);
   if(GlobalVariableCheck(lowKey))
      GlobalVariableDel(lowKey);
   if(GlobalVariableCheck(countKey))
      GlobalVariableDel(countKey);
   if(GlobalVariableCheck(placedKey))
      GlobalVariableDel(placedKey);

   Print("[AsianBreakout] Init: daily state reset. Keys cleared: ", highKey, ", ", lowKey, ", ", countKey, ", ", placedKey);
}

//+------------------------------------------------------------------+
//| Return number of breakout trades placed today                     |
//+------------------------------------------------------------------+
int GoldScalperAsianBreakoutDailyCount()
{
   string key = GoldScalperDayKey("breakoutCount");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

//+------------------------------------------------------------------+
//| Internal: Increment the daily breakout counter                    |
//+------------------------------------------------------------------+
void GoldScalperMarkBreakoutPlaced()
{
   string key = GoldScalperDayKey("breakoutCount");
   int current = GoldScalperAsianBreakoutDailyCount();
   GlobalVariableSet(key, (double)(current + 1));
}

//+------------------------------------------------------------------+
//| Internal: Check/set the "orders already placed today" flag        |
//+------------------------------------------------------------------+
bool GoldScalperBreakoutOrdersPlacedToday()
{
   string key = GoldScalperDayKey("breakoutOrdersPlaced");
   if(!GlobalVariableCheck(key))
      return false;
   return GlobalVariableGet(key) > 0.0;
}

void GoldScalperSetBreakoutOrdersPlaced()
{
   string key = GoldScalperDayKey("breakoutOrdersPlaced");
   GlobalVariableSet(key, 1.0);
}

//+------------------------------------------------------------------+
//| Internal: Build the Asian session range using M1 bars             |
//| Scans closed M1 bars that fall within the Asian session window    |
//+------------------------------------------------------------------+
bool GoldScalperBuildAsianRange(const string symbol, const int asianStartHour, const int asianEndHour,
                                double &asianHigh, double &asianLow)
{
   string highKey = GoldScalperDayKey("asianHigh");
   string lowKey  = GoldScalperDayKey("asianLow");

   // Return cached range if already computed today
   if(GlobalVariableCheck(highKey) && GlobalVariableCheck(lowKey))
   {
      asianHigh = GlobalVariableGet(highKey);
      asianLow  = GlobalVariableGet(lowKey);
      if(asianHigh > 0.0 && asianLow > 0.0 && asianHigh > asianLow)
         return true;
   }

   // Calculate the number of M1 bars in the Asian session
   // For a session like 22:00-05:00 that's 7 hours = 420 M1 bars
   int sessionHours;
   if(asianEndHour > asianStartHour)
      sessionHours = asianEndHour - asianStartHour;
   else
      sessionHours = (24 - asianStartHour) + asianEndHour;

   int barsNeeded = sessionHours * 60 + 60; // extra margin

   MqlRates m1[];
   ArraySetAsSeries(m1, true);
   int copied = CopyRates(symbol, PERIOD_M1, 0, barsNeeded, m1);
   if(copied < sessionHours * 60)
   {
      Print("[AsianBreakout] BuildRange: not enough M1 bars. copied=", copied,
            " needed=", sessionHours * 60);
      return false;
   }

   asianHigh = 0.0;
   asianLow  = DBL_MAX;
   int count = 0;

   for(int i = 0; i < copied; i++)
   {
      MqlDateTime barTime;
      TimeToStruct(m1[i].time, barTime);

      if(!GoldScalperInSession(barTime.hour, asianStartHour, asianEndHour))
         continue;

      // Only count bars from today's Asian session (or last night's start)
      // For overnight sessions starting at e.g. 22:00, the start portion
      // falls on the previous calendar day
      if(barTime.hour >= asianStartHour && asianStartHour > asianEndHour)
      {
         // This bar is from the "start" portion (e.g. 22:00-23:59) - could be yesterday
         // We accept it as long as it's the most recent occurrence
      }

      if(m1[i].high > asianHigh)
         asianHigh = m1[i].high;
      if(m1[i].low < asianLow)
         asianLow = m1[i].low;
      count++;
   }

   if(count < 10 || asianHigh <= 0.0 || asianLow >= DBL_MAX || asianHigh <= asianLow)
   {
      Print("[AsianBreakout] BuildRange: insufficient session bars. count=", count,
            " high=", DoubleToString(asianHigh, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)),
            " low=", DoubleToString(asianLow, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS)));
      return false;
   }

   // Cache the range
   GlobalVariableSet(highKey, asianHigh);
   GlobalVariableSet(lowKey, asianLow);

   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   Print("[AsianBreakout] Range built: high=", DoubleToString(asianHigh, digits),
         " low=", DoubleToString(asianLow, digits),
         " width=", DoubleToString(asianHigh - asianLow, digits),
         " bars=", count);

   return true;
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

//+------------------------------------------------------------------+
//| Main: Called on each new M1 bar                                   |
//| Handles range building, order placement, and order management     |
//+------------------------------------------------------------------+
void GoldScalperAsianBreakoutOnNewBar(const string symbol, const long magic, CTrade &trade,
   const int asianStartHour, const int asianEndHour,
   const int londonStartHour, const int londonEndHour,
   const double breakoutBuffer, const double minRange, const double maxRange,
   const double breakoutRR, const bool trailAtr,
   const int maxTrades, const double riskPct, const double minLot, const double maxLot)
{
   trade.SetExpertMagicNumber(magic);

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);
   int currentHour = now.hour;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.01;

   //--- Phase 1: During Asian session, build the range
   if(GoldScalperInSession(currentHour, asianStartHour, asianEndHour))
   {
      // Range is being built on-the-fly using M1 bars
      // The actual build happens when we need it (lazy via BuildAsianRange)
      // During the session, invalidate any stale cached range
      // so it gets rebuilt fresh once the session ends
      string highKey = GoldScalperDayKey("asianHigh");
      string lowKey  = GoldScalperDayKey("asianLow");

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

   //--- Phase 2: At London open, place pending breakout orders
   if(currentHour == londonStartHour && !GoldScalperBreakoutOrdersPlacedToday())
   {
      // Check daily trade limit
      int dailyCount = GoldScalperAsianBreakoutDailyCount();
      if(maxTrades > 0 && dailyCount >= maxTrades)
      {
         Print("[AsianBreakout] Daily limit reached: count=", dailyCount, " max=", maxTrades);
         GoldScalperSetBreakoutOrdersPlaced(); // prevent further attempts
         return;
      }

      // Build/retrieve the Asian range
      double asianHigh = 0.0, asianLow = 0.0;
      if(!GoldScalperBuildAsianRange(symbol, asianStartHour, asianEndHour, asianHigh, asianLow))
      {
         Print("[AsianBreakout] Cannot build Asian range - skipping order placement");
         return;
      }

      double rangeWidth = asianHigh - asianLow;
      double rangeWidthPoints = rangeWidth / point;

      Print("[AsianBreakout] Range check: width=", DoubleToString(rangeWidth, digits),
            " widthPts=", DoubleToString(rangeWidthPoints, 1),
            " min=", DoubleToString(minRange, 1),
            " max=", DoubleToString(maxRange, 1));

      // Validate range width
      if(rangeWidthPoints < minRange || rangeWidthPoints > maxRange)
      {
         Print("[AsianBreakout] Range width ", DoubleToString(rangeWidthPoints, 1),
               " points outside [", DoubleToString(minRange, 1), "-",
               DoubleToString(maxRange, 1), "] - skipping this bar (will retry)");
         // NOTE: Do NOT call GoldScalperSetBreakoutOrdersPlaced() here.
         // Allow the EA to retry on the next M1 bar within the London open hour.
         return;
      }

      // Calculate entry prices
      double bufferPrice = breakoutBuffer * point;
      double buyEntry  = NormalizeDouble(asianHigh + bufferPrice, digits);
      double sellEntry = NormalizeDouble(asianLow - bufferPrice, digits);

      // SL: opposite side of range
      double buySL  = NormalizeDouble(asianLow - bufferPrice, digits);
      double sellSL = NormalizeDouble(asianHigh + bufferPrice, digits);

      // TP: range width × RR multiplier
      double tpDistance = rangeWidth * breakoutRR;
      double buyTP  = NormalizeDouble(buyEntry + tpDistance, digits);
      double sellTP = NormalizeDouble(sellEntry - tpDistance, digits);

      // Calculate lot sizes
      double buyLot  = GoldScalperABCalcLotSize(symbol, buyEntry, buySL, riskPct, minLot, maxLot);
      double sellLot = GoldScalperABCalcLotSize(symbol, sellEntry, sellSL, riskPct, minLot, maxLot);

      // Expiration: London session end
      MqlDateTime expDt;
      TimeToStruct(TimeCurrent(), expDt);
      expDt.hour = londonEndHour;
      expDt.min  = 0;
      expDt.sec  = 0;
      datetime expiration = StructToTime(expDt);
      if(expiration <= TimeCurrent())
         expiration = TimeCurrent() + (londonEndHour - currentHour) * 3600;

      bool anyPlaced = false;

      // Place Buy Stop
      if(buyLot > 0.0)
      {
         string buyComment = StringFormat("ABrk_Buy_%s", TimeToString(TimeCurrent(), TIME_DATE));
         Print("[AsianBreakout] Placing Buy Stop: entry=", DoubleToString(buyEntry, digits),
               " sl=", DoubleToString(buySL, digits),
               " tp=", DoubleToString(buyTP, digits),
               " lot=", DoubleToString(buyLot, 2),
               " exp=", TimeToString(expiration, TIME_DATE | TIME_SECONDS));

         if(trade.BuyStop(buyLot, buyEntry, symbol, buySL, buyTP, ORDER_TIME_SPECIFIED, expiration, buyComment))
         {
            ulong orderTicket = trade.ResultOrder();
            Print("[AsianBreakout] Buy Stop placed successfully: ticket=", orderTicket);
            GoldScalperMarkBreakoutPlaced();
            GoldScalperJournal(StringFormat("Buy Stop placed: entry=%.2f sl=%.2f tp=%.2f lot=%.2f ticket=%I64u",
               buyEntry, buySL, buyTP, buyLot, orderTicket));
            anyPlaced = true;
         }
         else
         {
            Print("[AsianBreakout] Buy Stop FAILED: retcode=", (int)trade.ResultRetcode(),
                  " ", trade.ResultRetcodeDescription());
            GoldScalperJournal(StringFormat("Buy Stop FAILED: entry=%.2f sl=%.2f tp=%.2f lot=%.2f retcode=%d %s",
               buyEntry, buySL, buyTP, buyLot, (int)trade.ResultRetcode(), trade.ResultRetcodeDescription()));
         }
      }

      // Place Sell Stop
      if(sellLot > 0.0)
      {
         string sellComment = StringFormat("ABrk_Sell_%s", TimeToString(TimeCurrent(), TIME_DATE));
         Print("[AsianBreakout] Placing Sell Stop: entry=", DoubleToString(sellEntry, digits),
               " sl=", DoubleToString(sellSL, digits),
               " tp=", DoubleToString(sellTP, digits),
               " lot=", DoubleToString(sellLot, 2),
               " exp=", TimeToString(expiration, TIME_DATE | TIME_SECONDS));

         if(trade.SellStop(sellLot, sellEntry, symbol, sellSL, sellTP, ORDER_TIME_SPECIFIED, expiration, sellComment))
         {
            ulong orderTicket = trade.ResultOrder();
            Print("[AsianBreakout] Sell Stop placed successfully: ticket=", orderTicket);
            GoldScalperMarkBreakoutPlaced();
            GoldScalperJournal(StringFormat("Sell Stop placed: entry=%.2f sl=%.2f tp=%.2f lot=%.2f ticket=%I64u",
               sellEntry, sellSL, sellTP, sellLot, orderTicket));
            anyPlaced = true;
         }
         else
         {
            Print("[AsianBreakout] Sell Stop FAILED: retcode=", (int)trade.ResultRetcode(),
                  " ", trade.ResultRetcodeDescription());
            GoldScalperJournal(StringFormat("Sell Stop FAILED: entry=%.2f sl=%.2f tp=%.2f lot=%.2f retcode=%d %s",
               sellEntry, sellSL, sellTP, sellLot, (int)trade.ResultRetcode(), trade.ResultRetcodeDescription()));
         }
      }

      GoldScalperSetBreakoutOrdersPlaced();

      if(anyPlaced)
         Print("[AsianBreakout] Breakout orders placed. Daily count=", GoldScalperAsianBreakoutDailyCount());
      else
         Print("[AsianBreakout] No breakout orders could be placed this session");

      return;
   }

   //--- Phase 3: After London session ends, cancel unfilled pending orders
   if(currentHour >= londonEndHour && !GoldScalperInSession(currentHour, londonStartHour, londonEndHour))
   {
      int pendingCount = GoldScalperABCountPendingOrders(symbol, magic);
      if(pendingCount > 0)
      {
         Print("[AsianBreakout] London session ended (hour=", currentHour,
               "). Cancelling ", pendingCount, " unfilled pending orders.");
         GoldScalperCancelPendingOrders(symbol, magic, trade);
         GoldScalperJournal(StringFormat("Cancelled %d unfilled pending orders after London close", pendingCount));
      }
   }
}

//+------------------------------------------------------------------+
//| Manage trailing stops on filled breakout orders (called per tick) |
//| Uses ATR(M5, 14) × 1.5 as trailing distance                      |
//+------------------------------------------------------------------+
void GoldScalperAsianBreakoutManage(const string symbol, const long magic, CTrade &trade, const bool trailAtr)
{
   if(!trailAtr)
      return;

   trade.SetExpertMagicNumber(magic);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.01;
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   // Get ATR(M5, 14) for trailing distance
   int atrHandle = iATR(symbol, PERIOD_M5, 14);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("[AsianBreakout] Manage: ATR handle invalid");
      return;
   }

   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) != 1)
   {
      IndicatorRelease(atrHandle);
      return;
   }
   double atrValue = atrBuffer[0];
   IndicatorRelease(atrHandle);

   if(atrValue <= 0.0)
      return;

   double trailDistance = atrValue * 1.5;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol || PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      // Only trail positions that have breakout-style comments
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "ABrk_") < 0)
         continue;

      long type       = PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      double price = type == POSITION_TYPE_BUY
         ? SymbolInfoDouble(symbol, SYMBOL_BID)
         : SymbolInfoDouble(symbol, SYMBOL_ASK);

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
