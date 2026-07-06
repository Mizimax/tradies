#ifndef DZV_STYLE_TRADE_EXECUTOR_MQH
#define DZV_STYLE_TRADE_EXECUTOR_MQH

#include <Trade/Trade.mqh>
#include <DZVStyle/SignalEngine.mqh>

void DZVJournal(const string message)
{
   int handle = FileOpen("DZV_Style_ADR/trades.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return;
   FileSeek(handle, 0, SEEK_END);
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   string timestamp = StringFormat("%04d.%02d.%02d %02d:%02d:%02d", t.year, t.mon, t.day, t.hour, t.min, t.sec);
   FileWrite(handle, timestamp, message);
   FileClose(handle);
}

void DZVResetJournal()
{
   int handle = FileOpen("DZV_Style_ADR/trades.csv", FILE_WRITE | FILE_CSV | FILE_SHARE_READ | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return;
   FileWrite(handle, "timestamp", "event");
   FileClose(handle);
}

void DZVSimTradeReset(DZVSimTrade &trade)
{
   trade.open = false;
   trade.signal_id = "";
   trade.entry_time = 0;
   trade.entry_price = 0.0;
   trade.direction = DZV_DIR_NONE;
   trade.zone_index = -1;
   trade.stop_loss = 0.0;
   trade.take_profit = 0.0;
   trade.mfe_points = 0.0;
   trade.mae_points = 0.0;
}

void DZVZoneBandOrderReset(DZVZoneBandOrder &order)
{
   order.pending = false;
   order.open = false;
   order.id = "";
   order.day_start = 0;
   order.direction = DZV_DIR_NONE;
   order.zone_index = -1;
   order.edge_index = -1;
   order.entry_price = 0.0;
   order.stop_loss = 0.0;
   order.take_profit = 0.0;
   order.mfe_points = 0.0;
   order.mae_points = 0.0;
}

void DZVZoneBandOrderConfigure(DZVZoneBandOrder &order,
                               const string symbol,
                               const datetime dayStart,
                               const ENUM_DZV_DIRECTION direction,
                               const int zoneIndex,
                               const int edgeIndex,
                               const double entryPrice,
                               const double stopDistance,
                               const double targetDistance)
{
   order.pending = true;
   order.open = false;
   order.day_start = dayStart;
   order.direction = direction;
   order.zone_index = zoneIndex;
   order.edge_index = edgeIndex;
   order.entry_price = DZVNormalizePrice(symbol, entryPrice);
   if(direction == DZV_DIR_LONG)
   {
      order.stop_loss = DZVNormalizePrice(symbol, order.entry_price - stopDistance);
      order.take_profit = DZVNormalizePrice(symbol, order.entry_price + targetDistance);
   }
   else
   {
      order.stop_loss = DZVNormalizePrice(symbol, order.entry_price + stopDistance);
      order.take_profit = DZVNormalizePrice(symbol, order.entry_price - targetDistance);
   }
   order.mfe_points = 0.0;
   order.mae_points = 0.0;
   order.id = StringFormat("%s.%I64d.%s.Z%d.edge%d",
                           symbol,
                           (long)dayStart,
                           DZVDirectionName(direction),
                           zoneIndex + 1,
                           edgeIndex + 1);
   DZVJournal(StringFormat("band_pending,id=%s,dir=%s,zone=Z%d,edge=%d,entry=%.5f,sl=%.5f,tp=%.5f",
                           order.id, DZVDirectionName(direction), zoneIndex + 1, edgeIndex + 1,
                           order.entry_price, order.stop_loss, order.take_profit));
}

void DZVZoneBandPlaceDaily(DZVZoneBandOrder &orders[],
                           const string symbol,
                           const DZVDailyZoneSet &zones,
                           const int zoneNumber,
                           const double stopDistance,
                           const double targetDistance,
                           const bool allowLong,
                           const bool allowShort,
                           const bool allowLongEdge1,
                           const bool allowLongEdge2,
                           const bool allowShortEdge1,
                           const bool allowShortEdge2)
{
   int zone = MathMax(2, MathMin(DZV_ZONE_COUNT, zoneNumber)) - 1;
   double longFirst = zones.lower[zone - 1];
   double longLast = zones.lower[zone];
   double shortFirst = zones.upper[zone - 1];
   double shortLast = zones.upper[zone];

   for(int i = 0; i < ArraySize(orders); i++)
      DZVZoneBandOrderReset(orders[i]);

   int slot = 0;
   if(allowLong && allowLongEdge1 && slot < ArraySize(orders))
      DZVZoneBandOrderConfigure(orders[slot++], symbol, zones.day_start, DZV_DIR_LONG, zone, 0, longFirst, stopDistance, targetDistance);
   if(allowLong && allowLongEdge2 && slot < ArraySize(orders))
      DZVZoneBandOrderConfigure(orders[slot++], symbol, zones.day_start, DZV_DIR_LONG, zone, 1, longLast, stopDistance, targetDistance);
   if(allowShort && allowShortEdge1 && slot < ArraySize(orders))
      DZVZoneBandOrderConfigure(orders[slot++], symbol, zones.day_start, DZV_DIR_SHORT, zone, 0, shortFirst, stopDistance, targetDistance);
   if(allowShort && allowShortEdge2 && slot < ArraySize(orders))
      DZVZoneBandOrderConfigure(orders[slot++], symbol, zones.day_start, DZV_DIR_SHORT, zone, 1, shortLast, stopDistance, targetDistance);
}

void DZVZoneBandManage(DZVZoneBandOrder &orders[],
                       const string symbol,
                       const bool allowLongFill,
                       const bool allowShortFill,
                       const string longBlockReason,
                       const string shortBlockReason)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(point <= 0.0 || bid <= 0.0 || ask <= 0.0)
      return;

   for(int i = 0; i < ArraySize(orders); i++)
   {
      if(!orders[i].pending && !orders[i].open)
         continue;

      if(orders[i].pending)
      {
         bool filled = false;
         if(orders[i].direction == DZV_DIR_LONG)
            filled = ask <= orders[i].entry_price;
         else if(orders[i].direction == DZV_DIR_SHORT)
            filled = bid >= orders[i].entry_price;

         if(filled)
         {
            bool allowFill = orders[i].direction == DZV_DIR_LONG ? allowLongFill : allowShortFill;
            string blockReason = orders[i].direction == DZV_DIR_LONG ? longBlockReason : shortBlockReason;
            if(!allowFill)
            {
               DZVJournal(StringFormat("band_block,id=%s,dir=%s,zone=Z%d,edge=%d,reason=%s",
                                       orders[i].id, DZVDirectionName(orders[i].direction),
                                       orders[i].zone_index + 1, orders[i].edge_index + 1,
                                       blockReason));
               DZVZoneBandOrderReset(orders[i]);
               continue;
            }
            orders[i].pending = false;
            orders[i].open = true;
            DZVJournal(StringFormat("band_open,id=%s,dir=%s,zone=Z%d,edge=%d,entry=%.5f,sl=%.5f,tp=%.5f",
                                    orders[i].id, DZVDirectionName(orders[i].direction),
                                    orders[i].zone_index + 1, orders[i].edge_index + 1,
                                    orders[i].entry_price, orders[i].stop_loss, orders[i].take_profit));
         }
      }

      if(!orders[i].open)
         continue;

      double price = orders[i].direction == DZV_DIR_LONG ? bid : ask;
      double favorable = orders[i].direction == DZV_DIR_LONG ? price - orders[i].entry_price : orders[i].entry_price - price;
      double adverse = -favorable;
      orders[i].mfe_points = MathMax(orders[i].mfe_points, favorable / point);
      orders[i].mae_points = MathMax(orders[i].mae_points, adverse / point);

      bool hitStop = false;
      bool hitTarget = false;
      if(orders[i].direction == DZV_DIR_LONG)
      {
         hitStop = bid <= orders[i].stop_loss;
         hitTarget = bid >= orders[i].take_profit;
      }
      else if(orders[i].direction == DZV_DIR_SHORT)
      {
         hitStop = ask >= orders[i].stop_loss;
         hitTarget = ask <= orders[i].take_profit;
      }

      if(hitStop || hitTarget)
      {
         double pnlPoints = favorable / point;
         double riskPoints = MathAbs(orders[i].entry_price - orders[i].stop_loss) / point;
         double pnlR = riskPoints > 0.0 ? pnlPoints / riskPoints : 0.0;
         DZVJournal(StringFormat("band_close,id=%s,exit=%s,price=%.5f,pnl_points=%.1f,pnl_r=%.2f,mfe=%.1f,mae=%.1f",
                                 orders[i].id, hitTarget ? "target" : "stop", price,
                                 pnlPoints, pnlR, orders[i].mfe_points, orders[i].mae_points));
         DZVZoneBandOrderReset(orders[i]);
      }
   }
}

bool DZVSimOpen(DZVSimTrade &trade, const DZVSignal &signal)
{
   if(trade.open || !signal.valid)
      return false;
   trade.open = true;
   trade.signal_id = signal.id;
   trade.entry_time = TimeCurrent();
   trade.entry_price = signal.entry_price;
   trade.direction = signal.direction;
   trade.zone_index = signal.zone_index;
   trade.stop_loss = signal.stop_loss;
   trade.take_profit = signal.take_profit;
   trade.mfe_points = 0.0;
   trade.mae_points = 0.0;
   DZVJournal(StringFormat("sim_open,id=%s,dir=%s,zone=Z%d,entry=%.5f,sl=%.5f,tp=%.5f",
                           signal.id, DZVDirectionName(signal.direction), signal.zone_index + 1,
                           signal.entry_price, signal.stop_loss, signal.take_profit));
   return true;
}

void DZVSimManage(DZVSimTrade &trade, const string symbol)
{
   if(!trade.open)
      return;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(point <= 0.0 || bid <= 0.0 || ask <= 0.0)
      return;

   double price = trade.direction == DZV_DIR_LONG ? bid : ask;
   double favorable = trade.direction == DZV_DIR_LONG ? price - trade.entry_price : trade.entry_price - price;
   double adverse = -favorable;
   trade.mfe_points = MathMax(trade.mfe_points, favorable / point);
   trade.mae_points = MathMax(trade.mae_points, adverse / point);

   bool hitStop = false;
   bool hitTarget = false;
   if(trade.direction == DZV_DIR_LONG)
   {
      hitStop = price <= trade.stop_loss;
      hitTarget = price >= trade.take_profit;
   }
   else if(trade.direction == DZV_DIR_SHORT)
   {
      hitStop = price >= trade.stop_loss;
      hitTarget = price <= trade.take_profit;
   }

   if(hitStop || hitTarget)
   {
      double pnlPoints = favorable / point;
      double riskPoints = MathAbs(trade.entry_price - trade.stop_loss) / point;
      double pnlR = riskPoints > 0.0 ? pnlPoints / riskPoints : 0.0;
      DZVJournal(StringFormat("sim_close,id=%s,exit=%s,price=%.5f,pnl_points=%.1f,pnl_r=%.2f,mfe=%.1f,mae=%.1f",
                              trade.signal_id, hitTarget ? "target" : "stop", price, pnlPoints, pnlR,
                              trade.mfe_points, trade.mae_points));
      DZVSimTradeReset(trade);
   }
}

bool DZVExecuteLive(CTrade &trade,
                    const string symbol,
                    const long magic,
                    const int deviationPoints,
                    const DZVSignal &signal,
                    const double volume,
                    string &result)
{
   result = "";
   if(!signal.valid)
   {
      result = "invalid_signal";
      return false;
   }
   if(volume <= 0.0)
   {
      result = "invalid_volume";
      return false;
   }

   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(deviationPoints);
   trade.SetTypeFillingBySymbol(symbol);

   string comment = StringFormat("DZV_%s_Z%d", DZVModuleName(signal.module), signal.zone_index + 1);
   bool ok = false;
   if(signal.direction == DZV_DIR_LONG)
      ok = trade.Buy(volume, symbol, 0.0, signal.stop_loss, signal.take_profit, comment);
   else if(signal.direction == DZV_DIR_SHORT)
      ok = trade.Sell(volume, symbol, 0.0, signal.stop_loss, signal.take_profit, comment);

   result = StringFormat("retcode=%u,%s,order=%I64u,deal=%I64u",
                         trade.ResultRetcode(),
                         trade.ResultRetcodeDescription(),
                         trade.ResultOrder(),
                         trade.ResultDeal());
   DZVJournal(StringFormat("live_order,id=%s,ok=%s,%s", signal.id, ok ? "true" : "false", result));
   return ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED);
}

#endif
