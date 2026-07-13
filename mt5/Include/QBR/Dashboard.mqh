#ifndef QBR_DASHBOARD_MQH
#define QBR_DASHBOARD_MQH

#include "Types.mqh"

class CDashboard
  {
private:
   string m_prefix;
   bool   m_enabled;
   long   m_magic;

   void MakeButton(const string suffix,const string text,const int x,const int y,const int width)
     {
      string name=m_prefix+suffix;
      ObjectDelete(0,name);
      if(!ObjectCreate(0,name,OBJ_BUTTON,0,0,0)) return;
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(0,name,OBJPROP_XSIZE,width);
      ObjectSetInteger(0,name,OBJPROP_YSIZE,22);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
      ObjectSetString(0,name,OBJPROP_TEXT,text);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
     }

public:
   CDashboard(void) { m_prefix="QBR_"; m_enabled=false; m_magic=0; }

   void Init(const bool enabled,const long magic)
     {
      m_enabled=enabled;
      m_magic=magic;
      if(!m_enabled) return;
      string label=m_prefix+"PANEL";
      ObjectDelete(0,label);
      ObjectCreate(0,label,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,label,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,label,OBJPROP_XDISTANCE,12);
      ObjectSetInteger(0,label,OBJPROP_YDISTANCE,18);
      ObjectSetInteger(0,label,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,label,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
      ObjectSetString(0,label,OBJPROP_FONT,"Consolas");
      MakeButton("CLOSE","CLOSE EA BASKET",12,470,125);
      MakeButton("PAUSE","PAUSE NEW ENTRIES",142,470,135);
      MakeButton("RESUME","RESUME",282,470,80);
      MakeButton("EMERGENCY","EMERGENCY CLOSE",367,470,125);
      ChartRedraw();
     }

   void Shutdown(void)
     {
      if(!m_enabled) return;
      ObjectDelete(0,m_prefix+"PANEL");
      ObjectDelete(0,m_prefix+"CLOSE");
      ObjectDelete(0,m_prefix+"PAUSE");
      ObjectDelete(0,m_prefix+"RESUME");
      ObjectDelete(0,m_prefix+"EMERGENCY");
     }

   bool IsButton(const string object_name,const string suffix) const
     {
      return (object_name==m_prefix+suffix);
     }

   void Update(const QBRState state,const QBRFeatures &f,const QBRQSyncResult &q,const QBRContextResult &ctx,
               const QBRBalanceResult &balance,const QBRPatternSignal &pattern,const QBRBasketSnapshot &basket,
               const QBRPerformanceStats &stats,const bool paused,const double baseline,const double drawdown_pct,
               const string exit_rule,const int max_order,const double lot)
     {
      if(!m_enabled) return;
      int buy_count=0,sell_count=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(type==POSITION_TYPE_BUY) buy_count++; else if(type==POSITION_TYPE_SELL) sell_count++;
        }
      double growth=100.0*QBRSafeDivide(AccountInfoDouble(ACCOUNT_BALANCE)-baseline,baseline,0.0);
      int completed_baskets=stats.winning_baskets+stats.losing_baskets;
      double basket_win_rate=100.0*QBRSafeDivide((double)stats.winning_baskets,(double)completed_baskets,0.0);
      double signal_win_rate=100.0*QBRSafeDivide((double)stats.winning_baskets,(double)stats.independent_signals,0.0);
      string text=StringFormat(
         "Quantum Behavioral Replica  [INDEPENDENT]\n"
         "SYSTEM          %s\n"
         "NEXT BAR        %s\n"
         "ORDERS B/S      %d / %d\n"
         "AVERAGE         %.3f\n"
         "BIAS H4/D1      %d / %d\n"
         "VOL FILTER      ATR %.2f  Spread %.1f\n"
         "EXIT RULE       %s\n"
         "Win/Loss/Total  %d / %d / %d\n"
         "Balance         %.2f\n"
         "Equity          %.2f\n"
         "Margin %%        %.1f\n"
         "MaxOrder/Lot    %d / %.2f\n"
         "EA Basket P/L   %.2f\n"
         "Open P/L        %.2f\n"
         "Deposit Base    %.2f\n"
         "Basket TP       %.2f\n"
         "Growth/DD %%     %.2f / %.2f\n"
         "StateFlow       %s\n"
         "QSync/Balance   %.3f / %.1f\n"
         "DeepContext     %.3f\n"
         "Pattern         %s (%d)\n"
         "Order Avg W/L   %.2f / %.2f\n"
         "Order Max W/L   %.2f / %.2f\n"
         "Payoff/PF       %.2f / %.2f\n"
         "Wins erased     %.2f avg; %.2f max\n"
         "Basket W/L %%    %d/%d  %.1f%%\n"
         "Signal Win %%    %.1f%% (%d closed)\n"
         "PAUSED          %s",
         (paused ? "PAUSED" : "ACTIVE"),TimeToString(iTime(_Symbol,PERIOD_M15,0)+PeriodSeconds(PERIOD_M15),TIME_MINUTES),
         buy_count,sell_count,basket.weighted_average,f.h4_bias,f.daily_bias,f.atr_ratio,f.spread_points,exit_rule,
         stats.winning_orders,stats.losing_orders,stats.winning_orders+stats.losing_orders,
         AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY),AccountInfoDouble(ACCOUNT_MARGIN_LEVEL),
         max_order,lot,basket.floating_profit,AccountInfoDouble(ACCOUNT_PROFIT),baseline,basket.target_money,growth,drawdown_pct,
         QBRStateToString(state),q.total,balance.score,ctx.total,pattern.name,pattern.confidence,
         stats.average_winner,stats.average_loser,stats.largest_winner,stats.largest_loser,stats.payoff_ratio,stats.profit_factor,
         stats.wins_erased_by_average_loss,stats.small_wins_erased_by_largest_loss,stats.winning_baskets,stats.losing_baskets,basket_win_rate,
         signal_win_rate,stats.independent_signals,(paused ? "YES" : "NO"));
      ObjectSetString(0,m_prefix+"PANEL",OBJPROP_TEXT,text);
      ChartRedraw();
     }
  };

#endif
