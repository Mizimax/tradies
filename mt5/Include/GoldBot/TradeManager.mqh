#ifndef GOLDBOT_TRADE_MANAGER_MQH
#define GOLDBOT_TRADE_MANAGER_MQH

#include <Trade/Trade.mqh>
#include <GoldBot/SMC.mqh>
#include <GoldBot/Risk.mqh>

struct EntryZone
{
   double bottom;
   double top;
   double midpoint;
   double quarterPoint;
   bool valid;
};

EntryZone GoldBotBuildEntryZone(const GoldBotZone &fvg, const GoldBotZone &ob, const double ema21, const double atr)
{
   EntryZone zone;
   zone.valid = false;
   zone.bottom = 0.0;
   zone.top = 0.0;
   zone.midpoint = 0.0;
   zone.quarterPoint = 0.0;

   double emaBottom = ema21 * 0.998;
   double emaTop = ema21 * 1.002;
   double bottoms[3];
   double tops[3];
   int zoneCount = 0;

   if(fvg.valid)
   {
      bottoms[zoneCount] = fvg.bottom;
      tops[zoneCount] = fvg.top;
      zoneCount++;
   }
   if(ob.valid)
   {
      bottoms[zoneCount] = ob.bottom;
      tops[zoneCount] = ob.top;
      zoneCount++;
   }
   bottoms[zoneCount] = emaBottom;
   tops[zoneCount] = emaTop;
   zoneCount++;

   if(zoneCount <= 1)
      return zone;

   double bottom = bottoms[0];
   double top = tops[0];
   for(int i = 1; i < zoneCount; i++)
   {
      bottom = MathMax(bottom, bottoms[i]);
      top = MathMin(top, tops[i]);
   }

   if(bottom >= top)
   {
      int widestIndex = 0;
      double widestWidth = tops[0] - bottoms[0];
      for(int i = 1; i < zoneCount; i++)
      {
         double width = tops[i] - bottoms[i];
         if(width > widestWidth)
         {
            widestWidth = width;
            widestIndex = i;
         }
      }
      if(atr > 0.0 && widestWidth > atr * 1.5)
         return zone;
      bottom = bottoms[widestIndex];
      top = tops[widestIndex];
   }

   if(bottom >= top)
      return zone;

   zone.valid = true;
   zone.bottom = bottom;
   zone.top = top;
   zone.midpoint = bottom + (top - bottom) / 2.0;
   zone.quarterPoint = bottom + (top - bottom) * 0.25;
   return zone;
}

int GoldBotCountManagedPositions(const string symbol, const long magic)
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

void GoldBotCancelPendingOrders(const string symbol, const long magic, CTrade &trade)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol || OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      trade.OrderDelete(ticket);
   }
}

void GoldBotExpirePendingOrders(const string symbol, const long magic, CTrade &trade)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol || OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      datetime expiration = (datetime)OrderGetInteger(ORDER_TIME_EXPIRATION);
      if(expiration > 0 && TimeCurrent() >= expiration)
         trade.OrderDelete(ticket);
   }
}

void GoldBotCancelPendingOnStopBreach(const string symbol, const long magic, CTrade &trade)
{
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol || OrderGetInteger(ORDER_MAGIC) != magic)
         continue;

      long type = OrderGetInteger(ORDER_TYPE);
      double sl = OrderGetDouble(ORDER_SL);
      if(sl <= 0.0)
         continue;

      bool breached = (type == ORDER_TYPE_BUY_LIMIT && bid <= sl) || (type == ORDER_TYPE_SELL_LIMIT && ask >= sl);
      if(breached)
      {
         trade.OrderDelete(ticket);
         GoldBotJournal("Pending order cancelled after stop breach");
      }
   }
}

bool GoldBotPlaceLadder(
   const string symbol,
   const long magic,
   const GoldBotDirection direction,
   const EntryZone &zone,
   const double sl,
   const double score,
   const string signalId,
   const int ladderOrderCount,
   const int ladderFirstSplit,
   const int confluenceCount,
   const int enabledConfluences,
   const double lotPer100Usd,
   const double minLot,
   const double maxLot,
   const double highConvictionScore,
   const double minRR,
   const int maxHoldBars,
   CTrade &trade
)
{
   if(!zone.valid)
      return false;

   trade.SetExpertMagicNumber(magic);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double entries[3];
   if(direction == DIR_LONG)
   {
      entries[0] = zone.top;
      entries[1] = zone.midpoint;
      entries[2] = zone.bottom;
   }
   else
   {
      entries[0] = zone.bottom;
      entries[1] = zone.midpoint;
      entries[2] = zone.top;
   }

   datetime expiration = TimeCurrent() + maxHoldBars * PeriodSeconds(PERIOD_M15);
   bool anyPlaced = false;
   int ordersToPlace = ladderOrderCount;
   int startSplit = ladderFirstSplit;
   if(startSplit < 1)
      startSplit = 1;
   else if(startSplit > 3)
      startSplit = 3;
   if(ordersToPlace < 1)
      ordersToPlace = 1;
   else if(ordersToPlace > 4 - startSplit)
      ordersToPlace = 4 - startSplit;
   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   int scoreBucket = (int)MathFloor(score / 10.0) * 10;

   for(int i = 0; i < ordersToPlace; i++)
   {
      int splitNumber = startSplit + i;
      int entryIndex = splitNumber - 1;
      double lot = GoldBotSplitLot(symbol, equity, score, entryIndex, lotPer100Usd, minLot, maxLot, highConvictionScore);
      double risk = MathAbs(entries[entryIndex] - sl);
      if(risk <= 0.0 || lot <= 0.0)
         continue;

      string comment = StringFormat("%s_%d", signalId, splitNumber);
      double brokerTp = 0.0; // TP is managed by the EA so TP1 can be a partial close.

      bool ok = false;
      if(direction == DIR_LONG)
         ok = trade.BuyLimit(lot, entries[entryIndex], symbol, sl, brokerTp, ORDER_TIME_SPECIFIED, expiration, comment);
      else
         ok = trade.SellLimit(lot, entries[entryIndex], symbol, sl, brokerTp, ORDER_TIME_SPECIFIED, expiration, comment);

      if(ok)
      {
         ulong orderTicket = trade.ResultOrder();
         string orderKey = StringFormat("GoldBot.order.%I64u", orderTicket);
         GlobalVariableSet(orderKey + ".dir", (double)direction);
         GlobalVariableSet(orderKey + ".split", (double)splitNumber);
         GlobalVariableSet(orderKey + ".hour", (double)nowParts.hour);
         GlobalVariableSet(orderKey + ".scoreBucket", (double)scoreBucket);
         GlobalVariableSet(orderKey + ".confluences", (double)confluenceCount);
         GlobalVariableSet(orderKey + ".enabledConfluences", (double)enabledConfluences);
         GoldBotJournal(StringFormat("Pending order placed signalId=%s split=%d dir=%d entry=%.2f sl=%.2f lot=%.2f order=%I64u scoreBucket=%d confluences=%d/%d hour=%d",
            signalId,
            splitNumber,
            direction,
            entries[entryIndex],
            sl,
            lot,
            orderTicket,
            scoreBucket,
            confluenceCount,
            enabledConfluences,
            nowParts.hour));
      }
      else
      {
         GoldBotJournal(StringFormat("Pending order failed signalId=%s split=%d dir=%d entry=%.2f sl=%.2f lot=%.2f retcode=%d %s",
            signalId,
            splitNumber,
            direction,
            entries[entryIndex],
            sl,
            lot,
            (int)trade.ResultRetcode(),
            trade.ResultRetcodeDescription()));
      }

      anyPlaced = anyPlaced || ok;
   }

   if(anyPlaced)
      GoldBotMarkSignalTime();
   return anyPlaced;
}

void GoldBotJournal(const string message)
{
   string folder = "GoldBot";
   FolderCreate(folder);
   int handle = FileOpen(folder + "\\trades.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;
   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), message);
   FileClose(handle);
}

void GoldBotResetJournal()
{
   string folder = "GoldBot";
   FolderCreate(folder);
   FileDelete(folder + "\\trades.csv");
   int handle = FileOpen(folder + "\\trades.csv", FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;
   FileWrite(handle, "time", "message");
   FileClose(handle);
}

bool GoldBotHtfTargetPrice(
   const string symbol,
   const long type,
   const ENUM_TIMEFRAMES timeframe,
   const int lookback,
   const double minimumTarget,
   double &target
)
{
   target = 0.0;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int bars = lookback < 10 ? 10 : lookback;
   int copied = CopyRates(symbol, timeframe, 1, bars, rates);
   if(copied <= 0)
      return false;

   bool found = false;
   for(int i = 0; i < copied; i++)
   {
      double candidate = type == POSITION_TYPE_BUY ? rates[i].high : rates[i].low;
      bool validTarget = type == POSITION_TYPE_BUY ? candidate >= minimumTarget : candidate <= minimumTarget;
      if(!validTarget)
         continue;

      if(!found)
      {
         target = candidate;
         found = true;
      }
      else if(type == POSITION_TYPE_BUY)
      {
         if(candidate < target)
            target = candidate;
      }
      else if(candidate > target)
      {
         target = candidate;
      }
   }

   return found;
}

void GoldBotManagePositions(
   const string symbol,
   const long magic,
   const double atr,
   const int maxHoldBars,
   const double tp1R,
   const double tp2R,
   const double tp3R,
   const double breakEvenAtR,
   const bool trailAfterTp1,
   const bool useHtfTargets,
   CTrade &trade
)
{
   trade.SetExpertMagicNumber(magic);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.01;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol || PositionGetInteger(POSITION_MAGIC) != magic)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double sl = PositionGetDouble(POSITION_SL);
      long type = PositionGetInteger(POSITION_TYPE);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      string baseKey = StringFormat("GoldBot.%I64u", ticket);
      if(maxHoldBars > 0 && openTime > 0 && TimeCurrent() - openTime >= maxHoldBars * PeriodSeconds(PERIOD_M15))
      {
         if(trade.PositionClose(ticket))
         {
            GoldBotJournal("Position closed after max hold bars");
            GlobalVariableDel(baseKey + ".risk");
            GlobalVariableDel(baseKey + ".tp1");
            GlobalVariableDel(baseKey + ".tp2");
            GlobalVariableDel(baseKey + ".be");
            GlobalVariableDel(baseKey + ".trailAfterTp1");
            GlobalVariableDel(baseKey + ".tp2Price");
            GlobalVariableDel(baseKey + ".tp3Price");
         }
         else
            GoldBotJournal(StringFormat("Position max-hold close failed ticket=%I64u retcode=%d %s",
               ticket,
               (int)trade.ResultRetcode(),
               trade.ResultRetcodeDescription()));
         continue;
      }

      double price = type == POSITION_TYPE_BUY ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
      double risk = GlobalVariableCheck(baseKey + ".risk") ? GlobalVariableGet(baseKey + ".risk") : MathAbs(openPrice - sl);
      if(risk <= 0.0)
         continue;
      if(!GlobalVariableCheck(baseKey + ".risk"))
         GlobalVariableSet(baseKey + ".risk", risk);

      double effectiveTp1R = MathMax(tp1R, 0.1);
      double effectiveTp2R = MathMax(tp2R, effectiveTp1R);
      double effectiveTp3R = MathMax(tp3R, effectiveTp2R);
      double tp1 = type == POSITION_TYPE_BUY ? openPrice + risk * effectiveTp1R : openPrice - risk * effectiveTp1R;
      double tp2 = type == POSITION_TYPE_BUY ? openPrice + risk * effectiveTp2R : openPrice - risk * effectiveTp2R;
      double tp3 = type == POSITION_TYPE_BUY ? openPrice + risk * effectiveTp3R : openPrice - risk * effectiveTp3R;

      if(useHtfTargets)
      {
         string tp2Key = baseKey + ".tp2Price";
         string tp3Key = baseKey + ".tp3Price";
         if(GlobalVariableCheck(tp2Key))
            tp2 = GlobalVariableGet(tp2Key);
         else
         {
            double htfTp2 = 0.0;
            if(GoldBotHtfTargetPrice(symbol, type, PERIOD_H1, 96, tp2, htfTp2))
               tp2 = htfTp2;
            GlobalVariableSet(tp2Key, tp2);
         }

         if(GlobalVariableCheck(tp3Key))
            tp3 = GlobalVariableGet(tp3Key);
         else
         {
            double htfTp3 = 0.0;
            if(GoldBotHtfTargetPrice(symbol, type, PERIOD_H4, 120, tp3, htfTp3))
               tp3 = htfTp3;
            GlobalVariableSet(tp3Key, tp3);
            GoldBotJournal(StringFormat("HTF TP targets set ticket=%I64u tp2=%.2f tp3=%.2f fallbackR2=%.2f fallbackR3=%.2f",
               ticket,
               tp2,
               tp3,
               effectiveTp2R,
               effectiveTp3R));
         }
      }

      bool tp1Hit = GlobalVariableCheck(baseKey + ".tp1");
      bool tp2Hit = GlobalVariableCheck(baseKey + ".tp2");
      bool breakEvenMoved = GlobalVariableCheck(baseKey + ".be");
      bool trailLogged = GlobalVariableCheck(baseKey + ".trailAfterTp1");
      bool hitTp1 = type == POSITION_TYPE_BUY ? price >= tp1 : price <= tp1;
      bool hitTp2 = type == POSITION_TYPE_BUY ? price >= tp2 : price <= tp2;
      bool hitTp3 = type == POSITION_TYPE_BUY ? price >= tp3 : price <= tp3;

      if(!breakEvenMoved && breakEvenAtR > 0.0)
      {
         double breakEvenTrigger = type == POSITION_TYPE_BUY ? openPrice + risk * breakEvenAtR : openPrice - risk * breakEvenAtR;
         bool hitBreakEvenTrigger = type == POSITION_TYPE_BUY ? price >= breakEvenTrigger : price <= breakEvenTrigger;
         bool improvesToBreakEven = type == POSITION_TYPE_BUY ? openPrice > sl + point : (sl <= 0.0 || openPrice < sl - point);
         if(hitBreakEvenTrigger && improvesToBreakEven && trade.PositionModify(ticket, openPrice, 0.0))
         {
            GlobalVariableSet(baseKey + ".be", 1.0);
            breakEvenMoved = true;
            sl = openPrice;
            GoldBotJournal(StringFormat("Breakeven moved r=%.2f ticket=%I64u price=%.2f sl=%.2f", breakEvenAtR, ticket, price, openPrice));
         }
      }

      if(!tp1Hit && hitTp1)
      {
         trade.PositionClosePartial(ticket, GoldBotNormalizeLot(symbol, volume * 0.5, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN), volume));
         double nextSl = openPrice;
         if(trailAfterTp1 && atr > 0.0)
         {
            double trailSl = type == POSITION_TYPE_BUY ? price - atr : price + atr;
            nextSl = type == POSITION_TYPE_BUY ? MathMax(openPrice, trailSl) : MathMin(openPrice, trailSl);
         }
         trade.PositionModify(ticket, nextSl, 0.0);
         GlobalVariableSet(baseKey + ".tp1", 1.0);
         tp1Hit = true;
         if(trailAfterTp1)
         {
            GlobalVariableSet(baseKey + ".trailAfterTp1", 1.0);
            trailLogged = true;
            GoldBotJournal(StringFormat("TP1 hit r=%.2f price=%.2f sl=%.2f; trailing active", effectiveTp1R, price, nextSl));
         }
         else
         {
            GoldBotJournal(StringFormat("TP1 hit r=%.2f price=%.2f; SL moved to breakeven", effectiveTp1R, price));
         }
      }
      else if(tp1Hit && !tp2Hit && hitTp2)
      {
         trade.PositionClosePartial(ticket, GoldBotNormalizeLot(symbol, volume * 0.6, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN), volume));
         GlobalVariableSet(baseKey + ".tp2", 1.0);
         tp2Hit = true;
         GoldBotJournal(StringFormat("TP2 hit r=%.2f price=%.2f", effectiveTp2R, price));
      }
      else if(tp2Hit && hitTp3)
      {
         if(trade.PositionClose(ticket))
         {
            GoldBotJournal(StringFormat("TP3 hit r=%.2f price=%.2f; position closed", effectiveTp3R, price));
            GlobalVariableDel(baseKey + ".risk");
            GlobalVariableDel(baseKey + ".tp1");
            GlobalVariableDel(baseKey + ".tp2");
            GlobalVariableDel(baseKey + ".be");
            GlobalVariableDel(baseKey + ".trailAfterTp1");
            GlobalVariableDel(baseKey + ".tp2Price");
            GlobalVariableDel(baseKey + ".tp3Price");
         }
      }

      if(trailAfterTp1 && tp1Hit && !tp2Hit && atr > 0.0)
      {
         double trailSl = type == POSITION_TYPE_BUY ? price - atr : price + atr;
         double protectedSl = type == POSITION_TYPE_BUY ? MathMax(openPrice, trailSl) : MathMin(openPrice, trailSl);
         bool improves = type == POSITION_TYPE_BUY ? protectedSl > sl + point : (sl <= 0.0 || protectedSl < sl - point);
         if(improves && trade.PositionModify(ticket, protectedSl, 0.0))
         {
            if(!trailLogged)
            {
               GlobalVariableSet(baseKey + ".trailAfterTp1", 1.0);
               GoldBotJournal(StringFormat("Trailing activated after TP1 ticket=%I64u sl=%.2f", ticket, protectedSl));
            }
         }
      }
   }
}

#endif
