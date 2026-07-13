#ifndef QBR_SAFETYFOCUS_MQH
#define QBR_SAFETYFOCUS_MQH

#include "Types.mqh"

class CSafetyFocus
  {
private:
   string    m_symbol;
   QBRConfig m_cfg;
   double    m_equity_peak;
   double    m_last_bid;
   datetime  m_last_tick_time;

   string EquityPeakKey(void) const
     {
      return StringFormat("QBR_%s_%I64d_%s_EQUITY_PEAK",m_symbol,m_cfg.magic,m_cfg.run_id);
     }

   void SaveEquityPeak(void) const
     {
      GlobalVariableSet(EquityPeakKey(),m_equity_peak);
     }

   datetime DayStart(const datetime now) const
     {
      MqlDateTime t;
      TimeToStruct(now,t);
      t.hour=0; t.min=0; t.sec=0;
      return StructToTime(t);
     }

   datetime WeekStart(const datetime now) const
     {
      MqlDateTime t;
      TimeToStruct(now,t);
      datetime day_start=DayStart(now);
      int days_from_monday=(t.day_of_week==0 ? 6 : t.day_of_week-1);
      return day_start-days_from_monday*86400;
     }

   double ClosedProfitSince(const datetime from_time) const
     {
      if(!HistorySelect(from_time,TimeCurrent())) return 0.0;
      double profit=0.0;
      int total=HistoryDealsTotal();
      for(int i=0;i<total;i++)
        {
         ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0) continue;
         if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=m_symbol) continue;
         if((long)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=m_cfg.magic) continue;
         long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT) continue;
         profit+=HistoryDealGetDouble(ticket,DEAL_PROFIT)+
                 HistoryDealGetDouble(ticket,DEAL_SWAP)+
                 HistoryDealGetDouble(ticket,DEAL_COMMISSION)+
                 HistoryDealGetDouble(ticket,DEAL_FEE);
        }
      return profit;
     }

   bool PositionVolumesValid(void) const
     {
      double minimum=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      double maximum=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
      double step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      if(step<=0.0) return false;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic) continue;
         double volume=PositionGetDouble(POSITION_VOLUME);
         double steps=volume/step;
         if(volume<minimum-1e-8 || volume>maximum+1e-8 || MathAbs(steps-MathRound(steps))>1e-6) return false;
        }
      return true;
     }

   bool SessionAllowed(void) const
     {
      MqlDateTime t;
      TimeToStruct(TimeCurrent(),t);
      bool asian=(m_cfg.asian_start_hour<m_cfg.asian_end_hour ?
                  (t.hour>=m_cfg.asian_start_hour && t.hour<m_cfg.asian_end_hour) :
                  (t.hour>=m_cfg.asian_start_hour || t.hour<m_cfg.asian_end_hour));
      bool london=(m_cfg.london_start_hour<m_cfg.london_end_hour ?
                   (t.hour>=m_cfg.london_start_hour && t.hour<m_cfg.london_end_hour) :
                   (t.hour>=m_cfg.london_start_hour || t.hour<m_cfg.london_end_hour));
      bool ny=(m_cfg.new_york_start_hour<m_cfg.new_york_end_hour ?
               (t.hour>=m_cfg.new_york_start_hour && t.hour<m_cfg.new_york_end_hour) :
               (t.hour>=m_cfg.new_york_start_hour || t.hour<m_cfg.new_york_end_hour));
      return (asian && m_cfg.allow_asian) || (london && m_cfg.allow_london) || (ny && m_cfg.allow_new_york);
     }

public:
   void Configure(const string symbol,const QBRConfig &cfg)
     {
      m_symbol=symbol;
      m_cfg=cfg;
      m_equity_peak=AccountInfoDouble(ACCOUNT_EQUITY);
      // Tester runs must start from a clean peak. Live/demo restarts resume the
      // same run_id peak so a restart cannot erase permanent drawdown.
      if((bool)MQLInfoInteger(MQL_TESTER)) GlobalVariableDel(EquityPeakKey());
      else if(GlobalVariableCheck(EquityPeakKey()))
         m_equity_peak=MathMax(m_equity_peak,GlobalVariableGet(EquityPeakKey()));
      SaveEquityPeak();
      m_last_bid=0.0;
      m_last_tick_time=0;
     }

   double DailyClosedProfit(void) const { return ClosedProfitSince(DayStart(TimeCurrent())); }
   double WeeklyClosedProfit(void) const { return ClosedProfitSince(WeekStart(TimeCurrent())); }
   double EquityPeak(void) const { return m_equity_peak; }

   bool DailyStopReached(void) const
     {
      double balance=AccountInfoDouble(ACCOUNT_BALANCE);
      double baseline=balance-ClosedProfitSince(DayStart(TimeCurrent()));
      if(baseline<=0.0) baseline=balance;
      return ClosedProfitSince(DayStart(TimeCurrent()))<=-baseline*m_cfg.max_daily_loss_pct/100.0;
     }

   bool SpikeDetected(const QBRFeatures &f,string &reason)
     {
      MqlTick tick;
      if(!SymbolInfoTick(m_symbol,tick))
        {
         reason="No current tick";
         return true;
        }
      bool current_range=(f.current_bar_range_atr>=m_cfg.spike_current_range_atr);
      bool previous_range=(f.previous_bar_range_atr>=m_cfg.spike_previous_range_atr);
      bool spread_expanded=(f.spread_atr_ratio>=m_cfg.max_spread_atr_ratio*m_cfg.spike_spread_multiplier);
      bool gap=(f.gap_atr>=m_cfg.spike_gap_atr);
      bool volume=(f.volume_ratio>=m_cfg.spike_volume_ratio);
      bool tick_jump=false;
      if(m_last_bid>0.0 && f.atr>0.0) tick_jump=(MathAbs(tick.bid-m_last_bid)/f.atr>=m_cfg.spike_tick_jump_atr);
      m_last_bid=tick.bid;
      m_last_tick_time=TimeCurrent();
      if(current_range || previous_range || spread_expanded || gap || volume || tick_jump)
        {
         if(current_range) reason="Current bar range/ATR spike";
         else if(previous_range) reason="Previous closed bar range/ATR spike";
         else if(tick_jump) reason="Tick-to-tick price jump";
         else if(spread_expanded) reason="Spread expansion";
         else if(gap) reason="Price gap from prior close";
         else reason="Abnormal tick volume";
         return true;
        }
      reason="No spike";
      return false;
     }

   QBRSafetyResult Monitor(const QBRFeatures &f,const QBRBasketSnapshot &basket)
     {
      QBRSafetyResult r;
      r.allow=true;
      r.emergency=false;
      r.reason="Risk monitor normal";
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      double balance=AccountInfoDouble(ACCOUNT_BALANCE);
      double margin_level=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(equity>m_equity_peak)
        {
         m_equity_peak=equity;
         SaveEquityPeak();
        }
      double dd=100.0*QBRSafeDivide(m_equity_peak-equity,m_equity_peak,0.0);
      double floating_loss_pct=100.0*QBRSafeDivide(MathMax(-basket.floating_profit,0.0),balance,0.0);
      double daily=ClosedProfitSince(DayStart(TimeCurrent()));
      double weekly=ClosedProfitSince(WeekStart(TimeCurrent()));
      double day_baseline=MathMax(balance-daily,1.0);
      double week_baseline=MathMax(balance-weekly,1.0);

      if(margin_level>0.0 && margin_level<m_cfg.min_margin_level)
        { r.allow=false; r.emergency=true; r.reason="Margin level below emergency threshold"; }
      else if(dd>=m_cfg.max_equity_drawdown_pct)
        { r.allow=false; r.emergency=true; r.reason="Equity drawdown limit exceeded"; }
      else if(floating_loss_pct>=m_cfg.max_floating_loss_pct)
        { r.allow=false; r.emergency=true; r.reason="Floating basket loss limit exceeded"; }
      else if(basket.orders>0 && basket.direction==QBR_DIR_FLAT)
        { r.allow=false; r.emergency=true; r.reason="Position state is mixed or inconsistent with one-direction basket"; }
      else if(basket.orders>m_cfg.max_orders)
        { r.allow=false; r.emergency=true; r.reason="EA order count exceeds MaxOrder"; }
      else if(basket.orders>m_cfg.max_orders_direction)
        { r.allow=false; r.emergency=true; r.reason="EA direction order count exceeds configured maximum"; }
      else if(!PositionVolumesValid())
        { r.allow=false; r.emergency=true; r.reason="Open position volume is invalid for broker volume step/range"; }
      else if(basket.total_lots>m_cfg.max_total_lots+1e-8)
        { r.allow=false; r.emergency=true; r.reason="EA total lots exceeds configured maximum"; }
      else if(100.0*QBRSafeDivide(basket.margin_usage,MathMax(equity,1.0),0.0)>m_cfg.max_basket_exposure_pct)
        { r.allow=false; r.emergency=true; r.reason="Basket margin exposure limit exceeded"; }
      else if(daily<=-day_baseline*m_cfg.max_daily_loss_pct/100.0)
        { r.allow=false; r.reason="Daily loss limit reached"; }
      else if(weekly<=-week_baseline*m_cfg.max_weekly_loss_pct/100.0)
        { r.allow=false; r.reason="Weekly loss limit reached"; }
      else if(f.spread_points>m_cfg.max_spread_points*m_cfg.spike_spread_multiplier &&
              f.spread_atr_ratio>m_cfg.max_spread_atr_ratio*m_cfg.spike_spread_multiplier)
        {
         // A market-liquidity hazard blocks entries but must not persistently pause
         // the EA or panic-close a basket. Account/system risk remains emergency.
         r.allow=false;
         r.emergency=false;
         r.reason="Transient hard spread gate";
        }
      else if(f.gap_atr>=m_cfg.spike_gap_atr*2.0)
        {
         r.allow=false;
         r.emergency=false;
         r.reason="Transient extreme price-gap gate";
        }
      return r;
     }

   QBRSafetyResult PreTrade(const QBRFeatures &f,const QBRBasketSnapshot &basket,const QBRDirection direction,
                            const double proposed_lot,const int consecutive_losses,const bool cooldown_active)
     {
      QBRSafetyResult r=Monitor(f,basket);
      if(!r.allow) return r;
      r.reason="Pre-trade safety checks passed";
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
        { r.allow=false; r.reason="Algorithmic trading disabled"; }
      else if(!SessionAllowed())
        { r.allow=false; r.reason="Trading session not permitted"; }
      else if(cooldown_active)
        { r.allow=false; r.reason="Cooldown active"; }
      else if(f.spread_points>m_cfg.max_spread_points)
        { r.allow=false; r.reason="Spread points above maximum"; }
      else if(f.spread_atr_ratio>m_cfg.max_spread_atr_ratio)
        { r.allow=false; r.reason="Spread/ATR ratio above maximum"; }
      else if(AccountInfoDouble(ACCOUNT_MARGIN_FREE)<m_cfg.min_free_margin)
        { r.allow=false; r.reason="Free margin below minimum"; }
      else if(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)>0.0 && AccountInfoDouble(ACCOUNT_MARGIN_LEVEL)<m_cfg.min_margin_level)
        { r.allow=false; r.emergency=true; r.reason="Margin level below minimum"; }
      else if(proposed_lot<=0.0)
        { r.allow=false; r.reason="Calculated lot is not positive"; }
      else if(basket.total_lots+proposed_lot>m_cfg.max_total_lots+1e-8)
        { r.allow=false; r.reason="Maximum total lots would be exceeded"; }
      else if(basket.orders>=m_cfg.max_orders)
        { r.allow=false; r.reason="Maximum order count reached"; }
      else if(consecutive_losses>=m_cfg.max_consecutive_losses)
        { r.allow=false; r.reason="Maximum consecutive losses reached"; }
      else
        {
         double price=(direction==QBR_DIR_LONG ? SymbolInfoDouble(m_symbol,SYMBOL_ASK) : SymbolInfoDouble(m_symbol,SYMBOL_BID));
         double margin=0.0;
         ENUM_ORDER_TYPE type=(direction==QBR_DIR_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
         if(!OrderCalcMargin(type,m_symbol,proposed_lot,price,margin))
           { r.allow=false; r.reason="Margin calculation failed"; }
         else if(margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
           { r.allow=false; r.reason="Insufficient margin for proposed order"; }
         else if(100.0*QBRSafeDivide(basket.margin_usage+margin,MathMax(AccountInfoDouble(ACCOUNT_EQUITY),1.0),0.0)>m_cfg.max_basket_exposure_pct)
           { r.allow=false; r.reason="Proposed basket margin exposure exceeds maximum"; }
        }
      return r;
     }
  };

#endif
