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
   bool valid;
};

EntryZone GoldBotBuildEntryZone(const GoldBotZone &fvg, const GoldBotZone &ob, const double ema21, const double atr)
{
   EntryZone zone;
   zone.valid = false;
   zone.bottom = 0.0;
   zone.top = 0.0;
   zone.midpoint = 0.0;

   double bottom = ema21 * 0.998;
   double top = ema21 * 1.002;

   if(fvg.valid)
   {
      bottom = MathMax(bottom, fvg.bottom);
      top = MathMin(top, fvg.top);
   }
   if(ob.valid)
   {
      bottom = MathMax(bottom, ob.bottom);
      top = MathMin(top, ob.top);
   }

   if(bottom >= top || top - bottom > atr * 1.5)
      return zone;

   zone.valid = true;
   zone.bottom = bottom;
   zone.top = top;
   zone.midpoint = bottom + (top - bottom) / 2.0;
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

   for(int i = 0; i < 3; i++)
   {
      double lot = GoldBotSplitLot(symbol, equity, score, i, lotPer100Usd, minLot, maxLot, highConvictionScore);
      double risk = MathAbs(entries[i] - sl);
      if(risk <= 0.0 || lot <= 0.0)
         continue;

      string comment = StringFormat("GoldBot_%d", i + 1);
      double brokerTp = 0.0; // TP is managed by the EA so TP1 can be a partial close.

      bool ok = false;
      if(direction == DIR_LONG)
         ok = trade.BuyLimit(lot, entries[i], symbol, sl, brokerTp, ORDER_TIME_SPECIFIED, expiration, comment);
      else
         ok = trade.SellLimit(lot, entries[i], symbol, sl, brokerTp, ORDER_TIME_SPECIFIED, expiration, comment);

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

void GoldBotManagePositions(const string symbol, const long magic, const double atr, CTrade &trade)
{
   trade.SetExpertMagicNumber(magic);
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
      double tp = PositionGetDouble(POSITION_TP);
      long type = PositionGetInteger(POSITION_TYPE);
      double price = type == POSITION_TYPE_BUY ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
      double risk = MathAbs(openPrice - sl);
      if(risk <= 0.0)
         continue;

      double tp1 = type == POSITION_TYPE_BUY ? openPrice + risk * 2.0 : openPrice - risk * 2.0;
      double tp2 = type == POSITION_TYPE_BUY ? openPrice + risk * 2.5 : openPrice - risk * 2.5;
      double tp3 = type == POSITION_TYPE_BUY ? openPrice + risk * 4.0 : openPrice - risk * 4.0;

      string baseKey = StringFormat("GoldBot.%I64u", ticket);
      bool tp1Hit = GlobalVariableCheck(baseKey + ".tp1");
      bool tp2Hit = GlobalVariableCheck(baseKey + ".tp2");
      bool hitTp1 = type == POSITION_TYPE_BUY ? price >= tp1 : price <= tp1;
      bool hitTp2 = type == POSITION_TYPE_BUY ? price >= tp2 : price <= tp2;
      bool hitTp3 = type == POSITION_TYPE_BUY ? price >= tp3 : price <= tp3;

      if(!tp1Hit && hitTp1)
      {
         trade.PositionClosePartial(ticket, GoldBotNormalizeLot(symbol, volume * 0.5, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN), volume));
         trade.PositionModify(ticket, openPrice, 0.0);
         GlobalVariableSet(baseKey + ".tp1", 1.0);
         GoldBotJournal("TP1 hit; SL moved to breakeven");
      }
      else if(tp1Hit && !tp2Hit && hitTp2)
      {
         trade.PositionClosePartial(ticket, GoldBotNormalizeLot(symbol, volume * 0.6, SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN), volume));
         double trailSl = type == POSITION_TYPE_BUY ? price - atr : price + atr;
         trade.PositionModify(ticket, trailSl, 0.0);
         GlobalVariableSet(baseKey + ".tp2", 1.0);
         GoldBotJournal("TP2 hit; trailing SL active");
      }
      else if(tp2Hit && hitTp3)
      {
         trade.PositionClose(ticket);
         GoldBotJournal("TP3 hit; position closed");
      }
   }
}

#endif
