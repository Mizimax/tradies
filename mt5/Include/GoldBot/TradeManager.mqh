#ifndef GOLDBOT_TRADE_MANAGER_MQH
#define GOLDBOT_TRADE_MANAGER_MQH

#include <Trade/Trade.mqh>
#include <GoldBot/SMC.mqh>
#include <GoldBot/Risk.mqh>

// Forward declaration -- defined in GoldBot/PropMode.mqh, included after this file from
// GoldBot.mq5. Needed here so the realized-risk self-check below can use the same robust
// (contract-size-first, tick-value-fallback) cash-per-price-unit logic the prop sizing gate
// itself uses, instead of a raw SYMBOL_TRADE_TICK_VALUE/TICK_SIZE ratio that can be scaled
// unreliably on some brokers (e.g. tickValue=0.01 on this repo's demo XAUUSD symbol, ~100x
// off contract size 100 -- see the multiplier-leakage fix in GoldBot.mq5).
double GoldBotPropCashPerPriceUnitPerLot(const string symbol);

// Shadow-only failure-to-progress observation for the short-term scalp engines.
// The active-close branch is deliberately absent during Stage 1: enabling this
// config can write metadata/journal evidence, but cannot modify or close a trade.
struct GoldBotScalpFailureConfig
{
   bool enabled;
   bool shadowOnly;
   double checkFraction;
   double minMfeR;
   double currentR;
   int m5TimeStopSeconds;
   int m1TimeStopSeconds;
   int m5SetupCode;
   int m1SetupCode;
   double commissionPerLotUsd;
};

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

//--- Closes every open position for symbol/magic, then cancels every pending order (reuses
//--- GoldBotCancelPendingOrders above rather than duplicating the pending-cancel loop). Used
//--- by GoldBot/PropMode.mqh's intra-bar hard-breach monitor (daily hard-flatten floor or
//--- max-DD internal halt) -- the one place GoldBot needs a "flatten everything now" action.
//--- Returns the number of positions successfully closed.
int GoldBotFlattenAll(const string symbol, const long magic, CTrade &trade)
{
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol || PositionGetInteger(POSITION_MAGIC) != magic)
         continue;
      if(trade.PositionClose(ticket))
         closed++;
      else
         GoldBotJournal(StringFormat("Flatten-all position close failed ticket=%I64u retcode=%d %s",
            ticket,
            (int)trade.ResultRetcode(),
            trade.ResultRetcodeDescription()));
   }
   GoldBotCancelPendingOrders(symbol, magic, trade);
   return closed;
}

string GoldBotSignalIdFromComment(const string comment)
{
   int underscore = -1;
   int searchFrom = 0;
   while(true)
   {
      int found = StringFind(comment, "_", searchFrom);
      if(found < 0)
         break;
      underscore = found;
      searchFrom = found + 1;
   }

   if(underscore <= 0)
      return comment;
   return StringSubstr(comment, 0, underscore);
}

long GoldBotSignalCodeFromComment(const string comment)
{
   string signalId = GoldBotSignalIdFromComment(comment);
   if(StringLen(signalId) <= 0)
      return 0;
   if(StringLen(signalId) > 2 && StringSubstr(signalId, 0, 2) == "GB")
      return (long)StringToInteger(StringSubstr(signalId, 2));
   return (long)StringToInteger(signalId);
}

int GoldBotCancelSiblingPendingSplitsBySignalCode(
   const string symbol,
   const long magic,
   const long signalCode,
   const string reason,
   CTrade &trade
)
{
   if(signalCode <= 0)
      return 0;

   int cancelled = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol || OrderGetInteger(ORDER_MAGIC) != magic)
         continue;

      long type = OrderGetInteger(ORDER_TYPE);
      if(type != ORDER_TYPE_BUY_LIMIT && type != ORDER_TYPE_SELL_LIMIT)
         continue;

      string comment = OrderGetString(ORDER_COMMENT);
      if(GoldBotSignalCodeFromComment(comment) != signalCode)
         continue;

      if(trade.OrderDelete(ticket))
      {
         cancelled++;
         GoldBotJournal(StringFormat("%s ticket=%I64u signalCode=%I64d comment=%s",
            reason,
            ticket,
            signalCode,
            comment));
      }
      else
      {
         GoldBotJournal(StringFormat("%s failed ticket=%I64u signalCode=%I64d retcode=%d %s",
            reason,
            ticket,
            signalCode,
            (int)trade.ResultRetcode(),
            trade.ResultRetcodeDescription()));
      }
   }

   return cancelled;
}

int GoldBotCancelLongPendingAfterSessionEnd(
   const string symbol,
   const long magic,
   const int longSessionEndHour,
   CTrade &trade
)
{
   if(longSessionEndHour <= 0)
      return 0;

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   int cutoff = MathMax(0, MathMin(23, longSessionEndHour));
   if(nowParts.hour < cutoff)
      return 0;

   int cancelled = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol || OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      if(OrderGetInteger(ORDER_TYPE) != ORDER_TYPE_BUY_LIMIT)
         continue;

      string comment = OrderGetString(ORDER_COMMENT);
      if(trade.OrderDelete(ticket))
      {
         cancelled++;
         GoldBotJournal(StringFormat("long_session_pending_cancel ticket=%I64u hour=%d cutoff=%d comment=%s",
            ticket,
            nowParts.hour,
            cutoff,
            comment));
      }
      else
      {
         GoldBotJournal(StringFormat("long_session_pending_cancel failed ticket=%I64u hour=%d cutoff=%d retcode=%d %s",
            ticket,
            nowParts.hour,
            cutoff,
            (int)trade.ResultRetcode(),
            trade.ResultRetcodeDescription()));
      }
   }

   return cancelled;
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
   const int setupCode,
   const string setupName,
   const int setupVariantCode,
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
   const int pendingExpirySeconds,
   const int maxHoldSeconds,
   const double positionTp1R,
   const double positionTp2R,
   const double positionTp3R,
   const int positionTrailAfterTp1,
   const double positionBreakEvenAtR,
   const double positionTrailStartR,
   const double lotMultiplier,
   CTrade &trade,
   const double featureSpread = 0.0,
   const double featureSpreadToTpPct = 0.0,
   const double featureAdx = 0.0,
   const double featureDiGap = 0.0,
   const double featureAtr = 0.0,
   const double featureAtrRatio = 0.0,
   const double featureEma21 = 0.0,
   const double featureEma50 = 0.0,
   const double featureVwap = 0.0,
   const double featureZoneBottom = 0.0,
   const double featureZoneTop = 0.0,
   const double featureSlDistance = 0.0,
   const double featureLotMultiplier = 0.0,
   const double featureSetupRiskMultiplier = 0.0,
   const double stressExtraSpreadPrice = 0.0
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

   int expirySeconds = pendingExpirySeconds > 0 ? pendingExpirySeconds : maxHoldBars * PeriodSeconds(PERIOD_M15);
   datetime expiration = TimeCurrent() + expirySeconds;
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
      double lot = GoldBotSplitLot(symbol, equity, score, entryIndex, lotPer100Usd * MathMax(0.01, lotMultiplier), minLot, maxLot, highConvictionScore);
      double risk = MathAbs(entries[entryIndex] - sl);
      if(risk <= 0.0 || lot <= 0.0)
         continue;

      // Use the same broker-normalized cash conversion as the prop sizing gate. Some
      // XAUUSD feeds expose tick value at a scale that makes riskCash about 100x too small;
      // a normal stop then records roughly -100R and incorrectly halts short-term setups.
      double propCashPerPriceUnit = GoldBotPropCashPerPriceUnitPerLot(symbol);
      double riskCash = 0.0;
      if(propCashPerPriceUnit > 0.0)
         riskCash = risk * propCashPerPriceUnit * lot;
      else
      {
         // Preserve the legacy calculation only as a last-resort broker-data fallback.
         double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
         double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
         if(tickSize > 0.0 && tickValue > 0.0)
            riskCash = (risk / tickSize) * tickValue * lot;
      }

      // Self-check: makes setup-multiplier leakage (lotMultiplier/setupRiskMultiplier
      // stacking on top of an already risk-correct prop lot) visible in the journal without
      // a manual audit -- compare this realizedRiskPct against the "Prop sizing gate ...
      // throttledPct=" line logged a few lines earlier in the same signal's journal entries.
      // The self-check and the stored risk basis intentionally share riskCash so the
      // journal, short-term R control, and rolling governor all use one cash scale.
      double realizedRiskPct = equity > 0.0 ? (riskCash / equity) * 100.0 : 0.0;
      GoldBotJournal(StringFormat("Realized risk check signalId=%s split=%d lot=%.2f riskCash=%.2f equity=%.2f realizedRiskPct=%.4f",
         signalId, splitNumber, lot, riskCash, equity, realizedRiskPct));

      string comment = StringFormat("%s_%d", signalId, splitNumber);
      double brokerTp = 0.0; // TP is managed by the EA so TP1 can be a partial close.

      // Spread-stress testing: widen the broker-side SL by the extra spread so a stop-out
      // realizes a bigger loss and EA-managed TP1/TP2/TP3 (computed off the real position SL
      // in GoldBotManagePositions) require a proportionally larger move. Lot sizing/riskCash
      // above still use the original technical sl, so position sizing intent is unchanged.
      // stressExtraSpreadPrice == 0.0 (default) leaves stressedSl identical to sl.
      double stressedSl = sl;
      if(stressExtraSpreadPrice > 0.0)
         stressedSl = direction == DIR_LONG ? sl - stressExtraSpreadPrice : sl + stressExtraSpreadPrice;

      bool ok = false;
      if(direction == DIR_LONG)
         ok = trade.BuyLimit(lot, entries[entryIndex], symbol, stressedSl, brokerTp, ORDER_TIME_SPECIFIED, expiration, comment);
      else
         ok = trade.SellLimit(lot, entries[entryIndex], symbol, stressedSl, brokerTp, ORDER_TIME_SPECIFIED, expiration, comment);

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
         GlobalVariableSet(orderKey + ".setup", (double)setupCode);
         GlobalVariableSet(orderKey + ".scalpVariant", (double)setupVariantCode);
         GlobalVariableSet(orderKey + ".signalCode", (double)GoldBotSignalCodeFromComment(comment));
         if(maxHoldSeconds > 0)
            GlobalVariableSet(orderKey + ".maxHoldSeconds", (double)maxHoldSeconds);
         if(positionTp1R > 0.0)
            GlobalVariableSet(orderKey + ".tp1R", positionTp1R);
         if(positionTp2R > 0.0)
            GlobalVariableSet(orderKey + ".tp2R", positionTp2R);
         if(positionTp3R > 0.0)
            GlobalVariableSet(orderKey + ".tp3R", positionTp3R);
         if(positionTrailAfterTp1 >= 0)
            GlobalVariableSet(orderKey + ".trailAfterTp1Setting", (double)positionTrailAfterTp1);
         if(positionBreakEvenAtR > 0.0)
            GlobalVariableSet(orderKey + ".breakEvenAtR", positionBreakEvenAtR);
         if(positionTrailStartR > 0.0)
            GlobalVariableSet(orderKey + ".trailStartR", positionTrailStartR);
         if(riskCash > 0.0)
            GlobalVariableSet(orderKey + ".riskCash", riskCash);
         GlobalVariableSet(orderKey + ".spread", featureSpread);
         GlobalVariableSet(orderKey + ".spreadToTpPct", featureSpreadToTpPct);
         GlobalVariableSet(orderKey + ".adx", featureAdx);
         GlobalVariableSet(orderKey + ".diGap", featureDiGap);
         GlobalVariableSet(orderKey + ".atr", featureAtr);
         GlobalVariableSet(orderKey + ".atrRatio", featureAtrRatio);
         GlobalVariableSet(orderKey + ".ema21", featureEma21);
         GlobalVariableSet(orderKey + ".ema50", featureEma50);
         GlobalVariableSet(orderKey + ".vwap", featureVwap);
         GlobalVariableSet(orderKey + ".zoneBottom", featureZoneBottom);
         GlobalVariableSet(orderKey + ".zoneTop", featureZoneTop);
         GlobalVariableSet(orderKey + ".zoneWidth", MathAbs(featureZoneTop - featureZoneBottom));
         GlobalVariableSet(orderKey + ".slDistance", featureSlDistance > 0.0 ? featureSlDistance : risk);
         GlobalVariableSet(orderKey + ".lotMultiplier", featureLotMultiplier > 0.0 ? featureLotMultiplier : lotMultiplier);
         GlobalVariableSet(orderKey + ".setupRiskMultiplier", featureSetupRiskMultiplier);
         GoldBotJournal(StringFormat("Pending order placed signalId=%s setup=%s split=%d dir=%d entry=%.2f sl=%.2f lot=%.2f order=%I64u scoreBucket=%d confluences=%d/%d hour=%d",
            signalId,
            setupName,
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
         GoldBotJournal(StringFormat("Pending order failed signalId=%s setup=%s split=%d dir=%d entry=%.2f sl=%.2f lot=%.2f retcode=%d %s",
            signalId,
            setupName,
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
   const GoldBotScalpFailureConfig &failureCfg,
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
      int effectiveMaxHoldSeconds = maxHoldBars > 0 ? maxHoldBars * PeriodSeconds(PERIOD_M15) : 0;
      if(GlobalVariableCheck(baseKey + ".maxHoldSeconds"))
         effectiveMaxHoldSeconds = (int)GlobalVariableGet(baseKey + ".maxHoldSeconds");
      if(effectiveMaxHoldSeconds > 0 && openTime > 0 && TimeCurrent() - openTime >= effectiveMaxHoldSeconds)
      {
         if(trade.PositionClose(ticket))
         {
            GoldBotJournal(StringFormat("Position closed after max hold seconds=%d", effectiveMaxHoldSeconds));
            GlobalVariableDel(baseKey + ".risk");
            GlobalVariableDel(baseKey + ".tp1");
            GlobalVariableDel(baseKey + ".tp2");
            GlobalVariableDel(baseKey + ".be");
            GlobalVariableDel(baseKey + ".trailAfterTp1");
            GlobalVariableDel(baseKey + ".tp2Price");
            GlobalVariableDel(baseKey + ".tp3Price");
            GlobalVariableDel(baseKey + ".maxHoldSeconds");
            GlobalVariableDel(baseKey + ".tp1R");
            GlobalVariableDel(baseKey + ".tp2R");
            GlobalVariableDel(baseKey + ".tp3R");
            GlobalVariableDel(baseKey + ".trailAfterTp1Setting");
            GlobalVariableDel(baseKey + ".breakEvenAtR");
            GlobalVariableDel(baseKey + ".trailStartR");
            GlobalVariableDel(baseKey + ".riskCash");
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

      // Stage 1 telemetry is strictly observational. It is limited to positions
      // whose copied order metadata identifies an M5/M1 scalp setup, and it never
      // calls PositionClose/PositionModify regardless of the trigger result.
      if(failureCfg.enabled)
      {
         long positionId = PositionGetInteger(POSITION_IDENTIFIER);
         if(positionId <= 0)
            positionId = (long)ticket;
         string posKey = StringFormat("GoldBot.pos.%I64d", positionId);
         int setupCode = (int)(GlobalVariableCheck(posKey + ".setup") ? GlobalVariableGet(posKey + ".setup") : 0.0);
         bool isM5Scalp = setupCode == failureCfg.m5SetupCode;
         bool isM1Scalp = setupCode == failureCfg.m1SetupCode;
         if(isM5Scalp || isM1Scalp)
         {
            double riskDistance = GlobalVariableCheck(posKey + ".failureRiskDistance")
               ? GlobalVariableGet(posKey + ".failureRiskDistance")
               : (GlobalVariableCheck(posKey + ".slDistance") ? GlobalVariableGet(posKey + ".slDistance") : MathAbs(openPrice - sl));
            if(riskDistance > 0.0)
            {
               if(!GlobalVariableCheck(posKey + ".failureRiskDistance"))
                  GlobalVariableSet(posKey + ".failureRiskDistance", riskDistance);
               if(!GlobalVariableCheck(posKey + ".failureOpenTime"))
                  GlobalVariableSet(posKey + ".failureOpenTime", (double)openTime);

               double grossR = type == POSITION_TYPE_BUY
                  ? (price - openPrice) / riskDistance
                  : (openPrice - price) / riskDistance;
               double riskCash = GlobalVariableCheck(posKey + ".riskCash") ? GlobalVariableGet(posKey + ".riskCash") : 0.0;
               if(riskCash <= 0.0)
               {
                  double cashPerPriceUnit = GoldBotPropCashPerPriceUnitPerLot(symbol);
                  if(cashPerPriceUnit > 0.0)
                     riskCash = riskDistance * cashPerPriceUnit * volume;
               }
               double commissionR = riskCash > 0.0
                  ? MathMax(0.0, failureCfg.commissionPerLotUsd) * volume / riskCash
                  : 0.0;
               double swapR = riskCash > 0.0 ? PositionGetDouble(POSITION_SWAP) / riskCash : 0.0;
               double netR = grossR - commissionR + swapR;

               double mfeR = GlobalVariableCheck(posKey + ".mfeR")
                  ? MathMax(GlobalVariableGet(posKey + ".mfeR"), netR)
                  : netR;
               double maeR = GlobalVariableCheck(posKey + ".maeR")
                  ? MathMin(GlobalVariableGet(posKey + ".maeR"), netR)
                  : netR;
               GlobalVariableSet(posKey + ".mfeR", mfeR);
               GlobalVariableSet(posKey + ".maeR", maeR);

               bool checkpointLogged = GlobalVariableCheck(posKey + ".failureCheckpointLogged") &&
                  GlobalVariableGet(posKey + ".failureCheckpointLogged") > 0.5;
               int timeStopSeconds = isM5Scalp ? failureCfg.m5TimeStopSeconds : failureCfg.m1TimeStopSeconds;
               int checkpointSeconds = (int)MathCeil((double)MathMax(1, timeStopSeconds) * failureCfg.checkFraction);
               int ageSeconds = openTime > 0 ? (int)(TimeCurrent() - openTime) : 0;
               if(!checkpointLogged && ageSeconds >= checkpointSeconds)
               {
                  bool triggered = mfeR < failureCfg.minMfeR && netR <= failureCfg.currentR;
                  GlobalVariableSet(posKey + ".failureCheckpointLogged", 1.0);
                  GlobalVariableSet(posKey + ".failureCheckpointR", netR);
                  GlobalVariableSet(posKey + ".failureCheckpointGrossR", grossR);
                  GlobalVariableSet(posKey + ".failureTriggered", triggered ? 1.0 : 0.0);
                  long storedOpenTime = (long)GlobalVariableGet(posKey + ".failureOpenTime");
                  string positionInstance = StringFormat("%I64d_%I64d", positionId, storedOpenTime);
                  GoldBotJournal(StringFormat("Scalp failure checkpoint position=%I64d positionInstance=%s setup=%s dir=%d ageSeconds=%d timeStopSeconds=%d riskDistance=%.5f riskCash=%.2f mfeR=%.5f maeR=%.5f checkpointGrossR=%.5f checkpointR=%.5f triggered=%s thresholdMfeR=%.5f thresholdCurrentR=%.5f shadowOnly=%s",
                     positionId,
                     positionInstance,
                     isM5Scalp ? "m5_scalp" : "m1_micro_scalp",
                     type == POSITION_TYPE_BUY ? 1 : -1,
                     ageSeconds,
                     timeStopSeconds,
                     riskDistance,
                     riskCash,
                     mfeR,
                     maeR,
                     grossR,
                     netR,
                     triggered ? "yes" : "no",
                     failureCfg.minMfeR,
                     failureCfg.currentR,
                     failureCfg.shadowOnly ? "yes" : "no"));
               }
            }
         }
      }

      double configuredTp1R = GlobalVariableCheck(baseKey + ".tp1R") ? GlobalVariableGet(baseKey + ".tp1R") : tp1R;
      double configuredTp2R = GlobalVariableCheck(baseKey + ".tp2R") ? GlobalVariableGet(baseKey + ".tp2R") : tp2R;
      double configuredTp3R = GlobalVariableCheck(baseKey + ".tp3R") ? GlobalVariableGet(baseKey + ".tp3R") : tp3R;
      double configuredBreakEvenAtR = GlobalVariableCheck(baseKey + ".breakEvenAtR") ? GlobalVariableGet(baseKey + ".breakEvenAtR") : breakEvenAtR;
      double configuredTrailStartR = GlobalVariableCheck(baseKey + ".trailStartR") ? GlobalVariableGet(baseKey + ".trailStartR") : 0.0;
      bool effectiveTrailAfterTp1 = GlobalVariableCheck(baseKey + ".trailAfterTp1Setting") ? GlobalVariableGet(baseKey + ".trailAfterTp1Setting") > 0.5 : trailAfterTp1;
      double effectiveTp1R = MathMax(configuredTp1R, 0.1);
      double effectiveTp2R = MathMax(configuredTp2R, effectiveTp1R);
      double effectiveTp3R = MathMax(configuredTp3R, effectiveTp2R);
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

      if(!breakEvenMoved && configuredBreakEvenAtR > 0.0)
      {
         double breakEvenTrigger = type == POSITION_TYPE_BUY ? openPrice + risk * configuredBreakEvenAtR : openPrice - risk * configuredBreakEvenAtR;
         bool hitBreakEvenTrigger = type == POSITION_TYPE_BUY ? price >= breakEvenTrigger : price <= breakEvenTrigger;
         bool improvesToBreakEven = type == POSITION_TYPE_BUY ? openPrice > sl + point : (sl <= 0.0 || openPrice < sl - point);
         if(hitBreakEvenTrigger && improvesToBreakEven && trade.PositionModify(ticket, openPrice, 0.0))
         {
            GlobalVariableSet(baseKey + ".be", 1.0);
            breakEvenMoved = true;
            sl = openPrice;
            GoldBotJournal(StringFormat("Breakeven moved r=%.2f ticket=%I64u price=%.2f sl=%.2f", configuredBreakEvenAtR, ticket, price, openPrice));
         }
      }

      if(effectiveTrailAfterTp1 && configuredTrailStartR > 0.0 && !trailLogged && atr > 0.0)
      {
         double trailTrigger = type == POSITION_TYPE_BUY ? openPrice + risk * configuredTrailStartR : openPrice - risk * configuredTrailStartR;
         bool hitTrailTrigger = type == POSITION_TYPE_BUY ? price >= trailTrigger : price <= trailTrigger;
         if(hitTrailTrigger)
         {
            double trailSl = type == POSITION_TYPE_BUY ? price - atr : price + atr;
            double protectedSl = type == POSITION_TYPE_BUY ? MathMax(openPrice, trailSl) : MathMin(openPrice, trailSl);
            bool improves = type == POSITION_TYPE_BUY ? protectedSl > sl + point : (sl <= 0.0 || protectedSl < sl - point);
            if(improves && trade.PositionModify(ticket, protectedSl, 0.0))
            {
               GlobalVariableSet(baseKey + ".trailAfterTp1", 1.0);
               trailLogged = true;
               sl = protectedSl;
               GoldBotJournal(StringFormat("Trailing activated by setup trail start r=%.2f ticket=%I64u sl=%.2f price=%.2f", configuredTrailStartR, ticket, protectedSl, price));
            }
         }
      }

      if(!tp1Hit && hitTp1)
      {
         trade.PositionClosePartial(ticket, GoldBotNormalizeLot(symbol, volume * 0.5, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN), volume));
         double nextSl = openPrice;
         if(effectiveTrailAfterTp1 && atr > 0.0)
         {
            double trailSl = type == POSITION_TYPE_BUY ? price - atr : price + atr;
            nextSl = type == POSITION_TYPE_BUY ? MathMax(openPrice, trailSl) : MathMin(openPrice, trailSl);
         }
         trade.PositionModify(ticket, nextSl, 0.0);
         GlobalVariableSet(baseKey + ".tp1", 1.0);
         tp1Hit = true;
         if(effectiveTrailAfterTp1)
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
            GlobalVariableDel(baseKey + ".breakEvenAtR");
            GlobalVariableDel(baseKey + ".trailStartR");
            GlobalVariableDel(baseKey + ".riskCash");
         }
      }

      if(effectiveTrailAfterTp1 && tp1Hit && !tp2Hit && atr > 0.0)
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
