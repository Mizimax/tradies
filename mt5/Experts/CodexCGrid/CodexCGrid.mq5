//+------------------------------------------------------------------+
//|                                                   CodexCGrid.mq5 |
//| Original broker-portable grid EA inspired by user-owned presets. |
//| No closed-source EX5 code is copied or decompiled.               |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Original MA/Stochastic grid EA with capped martingale, money TP, trailing, and DD guard."

#include <Trade/Trade.mqh>

CTrade trade;

input string InpSymbol = "";                 // Blank = chart symbol
input long   MagicStart = 26062901;
input int    InpDeviationPoints = 30;

input bool   TRADE_BUY = true;
input bool   TRADE_SELL = true;
input double Lot = 0.01;
input double Martingale_multiply = 1.5;
input bool   Distance = true;
input double NearBy_distance = 400.0;
input double MAX_LOT = 0.05;
input int    MaxOrder = 8;

input bool   Gride_Candle = false;
input bool   Next_Candle = true;
input bool   Signal_Candle = false;

input bool   STO_MA_USE = true;
input bool   STO_USE = true;
input bool   MA_USE = true;
input int    Signal_TF = 1;

input int    MA_FAST = 3;
input int    MA_SLOW = 9;
input int    MA_TREND = 50;
input ENUM_MA_METHOD InpMaMethod = MODE_EMA;

input int    STO_K = 100;
input int    STO_D = 8;
input int    STO_SLOW = 8;
input double Level_Buy = 20.0;
input double Level_Sell = 80.0;

input bool   TP_Money_buy_sell = true;
input double TP_Money = 10.0;
input bool   TP_PIP_buy_sell = false;
input double TP_Pip = 100.0;
input bool   TP_Traling_buy_sell = true;
input double Trailing_Start = 250.0;
input double Trailing_Step = 50.0;
input double Trailing_Stop = 100.0;

input bool   TP_Money_CloseAll = true;
input double TP_Money_Close = 10.0;
input bool   TP_PIP_CloseAll = true;
input double TP_Pip_Close = 100.0;

input bool   Open_Safe_Mode = true;
input double Order_to_SafeMode = 10.0;
input double TP_Close = 1.0;

input double PF_Day_need = 999999999.0;
input double Percent_Max_DD = 40.0;
input bool   InpStopAfterDrawdownHit = true;

input bool   Monday = true;
input string Mon_Start_time = "00:00";
input string Mon_End_time = "23:59";
input bool   Tuesday = true;
input string Tue_start_time = "00:00";
input string Tue_End_time = "23:59";
input bool   Wednesday = true;
input string Wed_Start_time = "00:00";
input string Wed_End_time = "23:59";
input bool   Thursday = true;
input string Thu_Start_time = "00:00";
input string Thu_End_time = "23:59";
input bool   Friday = true;
input string Fri_Start_time = "00:00";
input string Fri_End_time = "23:59";

int g_ma_fast_handle = INVALID_HANDLE;
int g_ma_slow_handle = INVALID_HANDLE;
int g_ma_trend_handle = INVALID_HANDLE;
int g_sto_handle = INVALID_HANDLE;
datetime g_last_bar_time = 0;
bool g_drawdown_stopped = false;

string TradeSymbol()
{
   if(StringLen(InpSymbol) > 0)
      return InpSymbol;
   return _Symbol;
}

ENUM_TIMEFRAMES TimeframeFromMinutes(const int minutes)
{
   switch(minutes)
   {
      case 1: return PERIOD_M1;
      case 2: return PERIOD_M2;
      case 3: return PERIOD_M3;
      case 4: return PERIOD_M4;
      case 5: return PERIOD_M5;
      case 6: return PERIOD_M6;
      case 10: return PERIOD_M10;
      case 12: return PERIOD_M12;
      case 15: return PERIOD_M15;
      case 20: return PERIOD_M20;
      case 30: return PERIOD_M30;
      case 60: return PERIOD_H1;
      case 120: return PERIOD_H2;
      case 180: return PERIOD_H3;
      case 240: return PERIOD_H4;
      case 360: return PERIOD_H6;
      case 480: return PERIOD_H8;
      case 720: return PERIOD_H12;
      case 1440: return PERIOD_D1;
      default: return PERIOD_M1;
   }
}

int SignalShift()
{
   if(Signal_Candle)
      return 0;
   return 1;
}

bool ReadBufferValue(const int handle, const int buffer_index, const int shift, double &value)
{
   double values[1];
   if(handle == INVALID_HANDLE)
      return false;
   if(CopyBuffer(handle, buffer_index, shift, 1, values) != 1)
      return false;
   if(values[0] == EMPTY_VALUE)
      return false;
   value = values[0];
   return true;
}

double PointValue(const string symbol)
{
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = _Point;
   return point;
}

double NormalizePrice(const string symbol, const double price)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   return NormalizeDouble(price, digits);
}

double NormalizeLot(const string symbol, const double requested)
{
   double min_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   if(min_lot <= 0.0 || max_lot <= 0.0 || step <= 0.0)
      return 0.0;

   double cap = MathMin(MAX_LOT, max_lot);
   if(cap < min_lot)
      return 0.0;

   double volume = MathMax(min_lot, MathMin(requested, cap));
   double steps = MathFloor((volume - min_lot + 0.000000001) / step);
   volume = min_lot + steps * step;
   volume = MathMax(min_lot, MathMin(volume, cap));
   return NormalizeDouble(volume, 2);
}

bool IsOurPosition(const string symbol, const long position_type)
{
   if(PositionGetString(POSITION_SYMBOL) != symbol)
      return false;
   if((long)PositionGetInteger(POSITION_MAGIC) != MagicStart)
      return false;
   if(position_type >= 0 && (long)PositionGetInteger(POSITION_TYPE) != position_type)
      return false;
   return true;
}

int CountPositions(const string symbol, const long position_type = -1)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(IsOurPosition(symbol, position_type))
         ++count;
   }
   return count;
}

double PositionProfit(const string symbol, const long position_type = -1)
{
   double profit = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsOurPosition(symbol, position_type))
         continue;
      profit += PositionGetDouble(POSITION_PROFIT);
      profit += PositionGetDouble(POSITION_SWAP);
   }
   return profit;
}

double DailyClosedProfit(const string symbol)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime day_start = StructToTime(dt);

   if(!HistorySelect(day_start, TimeCurrent()))
      return 0.0;

   double profit = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; ++i)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != symbol)
         continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicStart)
         continue;

      long entry = (long)HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT && entry != DEAL_ENTRY_OUT_BY)
         continue;

      profit += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      profit += HistoryDealGetDouble(ticket, DEAL_SWAP);
      profit += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return profit;
}

double CurrentDrawdownPercent()
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance <= 0.0 || equity >= balance)
      return 0.0;
   return (balance - equity) / balance * 100.0;
}

int ParseTimeOfDay(const string value)
{
   int sep = StringFind(value, ":");
   if(sep < 0)
      return 0;
   int hour = (int)StringToInteger(StringSubstr(value, 0, sep));
   int minute = (int)StringToInteger(StringSubstr(value, sep + 1));
   hour = MathMax(0, MathMin(23, hour));
   minute = MathMax(0, MathMin(59, minute));
   return hour * 3600 + minute * 60;
}

bool InTimeWindow(const string start_text, const string end_text)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int now = dt.hour * 3600 + dt.min * 60 + dt.sec;
   int start_time = ParseTimeOfDay(start_text);
   int end_time = ParseTimeOfDay(end_text);

   if(start_time <= end_time)
      return now >= start_time && now <= end_time;
   return now >= start_time || now <= end_time;
}

bool IsTradingWindow()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   switch(dt.day_of_week)
   {
      case 1: return Monday && InTimeWindow(Mon_Start_time, Mon_End_time);
      case 2: return Tuesday && InTimeWindow(Tue_start_time, Tue_End_time);
      case 3: return Wednesday && InTimeWindow(Wed_Start_time, Wed_End_time);
      case 4: return Thursday && InTimeWindow(Thu_Start_time, Thu_End_time);
      case 5: return Friday && InTimeWindow(Fri_Start_time, Fri_End_time);
      default: return false;
   }
}

bool GetSidePriceRange(const string symbol, const long position_type, double &lowest, double &highest, double &weighted_average)
{
   double weighted_sum = 0.0;
   double volume_sum = 0.0;
   bool found = false;
   lowest = DBL_MAX;
   highest = -DBL_MAX;
   weighted_average = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsOurPosition(symbol, position_type))
         continue;

      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      lowest = MathMin(lowest, open_price);
      highest = MathMax(highest, open_price);
      weighted_sum += open_price * volume;
      volume_sum += volume;
      found = true;
   }

   if(!found || volume_sum <= 0.0)
      return false;

   weighted_average = weighted_sum / volume_sum;
   return true;
}

bool ClosePositions(const string symbol, const long position_type = -1)
{
   bool ok = true;
   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsOurPosition(symbol, position_type))
         continue;
      if(!trade.PositionClose(ticket))
      {
         PrintFormat("CodexCGrid: failed to close position %I64u, retcode=%u", ticket, trade.ResultRetcode());
         ok = false;
      }
   }
   return ok;
}

void ApplyTrailingStops(const string symbol)
{
   if(!TP_Traling_buy_sell)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return;

   double point = PointValue(symbol);
   double start = Trailing_Start * point;
   double stop = Trailing_Stop * point;
   double step = Trailing_Step * point;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(!IsOurPosition(symbol, -1))
         continue;

      long type = (long)PositionGetInteger(POSITION_TYPE);
      double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
      double old_sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY)
      {
         if(tick.bid - open_price < start)
            continue;
         double new_sl = NormalizePrice(symbol, tick.bid - stop);
         if(old_sl == 0.0 || new_sl > old_sl + step)
            trade.PositionModify(ticket, new_sl, tp);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(open_price - tick.ask < start)
            continue;
         double new_sl = NormalizePrice(symbol, tick.ask + stop);
         if(old_sl == 0.0 || new_sl < old_sl - step)
            trade.PositionModify(ticket, new_sl, tp);
      }
   }
}

bool HasBuySignal(const string symbol)
{
   int shift = SignalShift();
   ENUM_TIMEFRAMES tf = TimeframeFromMinutes(Signal_TF);
   bool ok = true;

   if(MA_USE)
   {
      double fast = 0.0, slow = 0.0, trend = 0.0;
      if(!ReadBufferValue(g_ma_fast_handle, 0, shift, fast))
         return false;
      if(!ReadBufferValue(g_ma_slow_handle, 0, shift, slow))
         return false;
      if(!ReadBufferValue(g_ma_trend_handle, 0, shift, trend))
         return false;

      double close_price = iClose(symbol, tf, shift);
      ok = ok && fast > slow && close_price > trend;
   }

   if(STO_USE || STO_MA_USE)
   {
      double main = 0.0, signal = 0.0;
      if(!ReadBufferValue(g_sto_handle, 0, shift, main))
         return false;
      if(!ReadBufferValue(g_sto_handle, 1, shift, signal))
         return false;

      bool sto_ok = true;
      if(STO_USE)
         sto_ok = sto_ok && main <= Level_Buy;
      if(STO_MA_USE)
         sto_ok = sto_ok && main > signal;
      ok = ok && sto_ok;
   }

   return ok;
}

bool HasSellSignal(const string symbol)
{
   int shift = SignalShift();
   ENUM_TIMEFRAMES tf = TimeframeFromMinutes(Signal_TF);
   bool ok = true;

   if(MA_USE)
   {
      double fast = 0.0, slow = 0.0, trend = 0.0;
      if(!ReadBufferValue(g_ma_fast_handle, 0, shift, fast))
         return false;
      if(!ReadBufferValue(g_ma_slow_handle, 0, shift, slow))
         return false;
      if(!ReadBufferValue(g_ma_trend_handle, 0, shift, trend))
         return false;

      double close_price = iClose(symbol, tf, shift);
      ok = ok && fast < slow && close_price < trend;
   }

   if(STO_USE || STO_MA_USE)
   {
      double main = 0.0, signal = 0.0;
      if(!ReadBufferValue(g_sto_handle, 0, shift, main))
         return false;
      if(!ReadBufferValue(g_sto_handle, 1, shift, signal))
         return false;

      bool sto_ok = true;
      if(STO_USE)
         sto_ok = sto_ok && main >= Level_Sell;
      if(STO_MA_USE)
         sto_ok = sto_ok && main < signal;
      ok = ok && sto_ok;
   }

   return ok;
}

double NextLotForSide(const string symbol, const long position_type)
{
   int side_count = CountPositions(symbol, position_type);
   double requested = Lot * MathPow(MathMax(1.0, Martingale_multiply), side_count);
   return NormalizeLot(symbol, requested);
}

bool HasEnoughMargin(const string symbol, const long position_type, const double volume, const double price)
{
   double margin = 0.0;
   ENUM_ORDER_TYPE order_type = position_type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcMargin(order_type, symbol, volume, price, margin))
      return true;
   return AccountInfoDouble(ACCOUNT_MARGIN_FREE) > margin;
}

bool OpenPosition(const string symbol, const long position_type, const string reason)
{
   if(CountPositions(symbol, -1) >= MaxOrder)
      return false;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return false;

   double volume = NextLotForSide(symbol, position_type);
   if(volume <= 0.0)
   {
      Print("CodexCGrid: volume is below broker minimum or MAX_LOT cap.");
      return false;
   }

   double price = position_type == POSITION_TYPE_BUY ? tick.ask : tick.bid;
   if(!HasEnoughMargin(symbol, position_type, volume, price))
   {
      PrintFormat("CodexCGrid: not enough free margin for %.2f lots on %s", volume, symbol);
      return false;
   }

   bool ok = false;
   string comment = "CodexCGrid " + reason;
   if(position_type == POSITION_TYPE_BUY)
      ok = trade.Buy(volume, symbol, 0.0, 0.0, 0.0, comment);
   else
      ok = trade.Sell(volume, symbol, 0.0, 0.0, 0.0, comment);

   if(!ok)
      PrintFormat("CodexCGrid: order failed, retcode=%u, %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   return ok;
}

void ManageProfitTargets(const string symbol)
{
   int total = CountPositions(symbol, -1);
   if(total <= 0)
      return;

   double safe_target = TP_Money_Close;
   if(Open_Safe_Mode && total >= (int)MathMax(1.0, Order_to_SafeMode))
      safe_target = TP_Close;

   if(TP_Money_CloseAll && PositionProfit(symbol, -1) >= safe_target)
   {
      ClosePositions(symbol, -1);
      return;
   }

   if(TP_Money_buy_sell)
   {
      if(PositionProfit(symbol, POSITION_TYPE_BUY) >= TP_Money)
         ClosePositions(symbol, POSITION_TYPE_BUY);
      if(PositionProfit(symbol, POSITION_TYPE_SELL) >= TP_Money)
         ClosePositions(symbol, POSITION_TYPE_SELL);
   }

   if(!TP_PIP_buy_sell && !TP_PIP_CloseAll)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return;

   double point = PointValue(symbol);
   double lowest = 0.0, highest = 0.0, average = 0.0;
   if(GetSidePriceRange(symbol, POSITION_TYPE_BUY, lowest, highest, average))
   {
      double target_points = TP_PIP_CloseAll ? TP_Pip_Close : TP_Pip;
      if(tick.bid - average >= target_points * point)
         ClosePositions(symbol, POSITION_TYPE_BUY);
   }
   if(GetSidePriceRange(symbol, POSITION_TYPE_SELL, lowest, highest, average))
   {
      double target_points = TP_PIP_CloseAll ? TP_Pip_Close : TP_Pip;
      if(average - tick.ask >= target_points * point)
         ClosePositions(symbol, POSITION_TYPE_SELL);
   }
}

void ManageGridEntries(const string symbol)
{
   if(!Distance)
      return;
   if(CountPositions(symbol, -1) >= MaxOrder)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(symbol, tick))
      return;

   double point = PointValue(symbol);
   double grid = NearBy_distance * point;
   double lowest = 0.0, highest = 0.0, average = 0.0;

   if(TRADE_BUY && GetSidePriceRange(symbol, POSITION_TYPE_BUY, lowest, highest, average))
   {
      if(tick.ask <= lowest - grid)
         OpenPosition(symbol, POSITION_TYPE_BUY, "grid-buy");
   }

   if(TRADE_SELL && GetSidePriceRange(symbol, POSITION_TYPE_SELL, lowest, highest, average))
   {
      if(tick.bid >= highest + grid)
         OpenPosition(symbol, POSITION_TYPE_SELL, "grid-sell");
   }
}

void ManageSignalEntries(const string symbol)
{
   if(CountPositions(symbol, -1) >= MaxOrder)
      return;

   if(TRADE_BUY && CountPositions(symbol, POSITION_TYPE_BUY) == 0 && HasBuySignal(symbol))
      OpenPosition(symbol, POSITION_TYPE_BUY, "signal-buy");

   if(TRADE_SELL && CountPositions(symbol, POSITION_TYPE_SELL) == 0 && HasSellSignal(symbol))
      OpenPosition(symbol, POSITION_TYPE_SELL, "signal-sell");
}

int OnInit()
{
   string symbol = TradeSymbol();
   if(!SymbolSelect(symbol, true))
   {
      PrintFormat("CodexCGrid: unable to select symbol %s", symbol);
      return INIT_FAILED;
   }

   ENUM_TIMEFRAMES tf = TimeframeFromMinutes(Signal_TF);
   g_ma_fast_handle = iMA(symbol, tf, MA_FAST, 0, InpMaMethod, PRICE_CLOSE);
   g_ma_slow_handle = iMA(symbol, tf, MA_SLOW, 0, InpMaMethod, PRICE_CLOSE);
   g_ma_trend_handle = iMA(symbol, tf, MA_TREND, 0, InpMaMethod, PRICE_CLOSE);
   g_sto_handle = iStochastic(symbol, tf, STO_K, STO_D, STO_SLOW, MODE_SMA, STO_LOWHIGH);

   if(g_ma_fast_handle == INVALID_HANDLE || g_ma_slow_handle == INVALID_HANDLE ||
      g_ma_trend_handle == INVALID_HANDLE || g_sto_handle == INVALID_HANDLE)
   {
      Print("CodexCGrid: failed to create indicator handles.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(MagicStart);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(symbol);

   g_last_bar_time = 0;
   g_drawdown_stopped = false;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_ma_fast_handle != INVALID_HANDLE)
      IndicatorRelease(g_ma_fast_handle);
   if(g_ma_slow_handle != INVALID_HANDLE)
      IndicatorRelease(g_ma_slow_handle);
   if(g_ma_trend_handle != INVALID_HANDLE)
      IndicatorRelease(g_ma_trend_handle);
   if(g_sto_handle != INVALID_HANDLE)
      IndicatorRelease(g_sto_handle);
}

void OnTick()
{
   string symbol = TradeSymbol();
   if(g_drawdown_stopped)
      return;

   if(Percent_Max_DD > 0.0 && CurrentDrawdownPercent() >= Percent_Max_DD)
   {
      PrintFormat("CodexCGrid: drawdown guard hit %.2f%% >= %.2f%%", CurrentDrawdownPercent(), Percent_Max_DD);
      ClosePositions(symbol, -1);
      if(InpStopAfterDrawdownHit)
         g_drawdown_stopped = true;
      return;
   }

   ApplyTrailingStops(symbol);
   ManageProfitTargets(symbol);

   if(PF_Day_need > 0.0 && DailyClosedProfit(symbol) + PositionProfit(symbol, -1) >= PF_Day_need)
      return;
   if(!IsTradingWindow())
      return;

   ENUM_TIMEFRAMES tf = TimeframeFromMinutes(Signal_TF);
   datetime bar_time = iTime(symbol, tf, 0);
   bool is_new_bar = bar_time != 0 && bar_time != g_last_bar_time;
   if(is_new_bar)
      g_last_bar_time = bar_time;

   bool candle_gate = (Next_Candle || Gride_Candle) ? is_new_bar : true;
   if(candle_gate)
      ManageGridEntries(symbol);

   bool signal_gate = Next_Candle ? is_new_bar : true;
   if(signal_gate)
      ManageSignalEntries(symbol);
}
