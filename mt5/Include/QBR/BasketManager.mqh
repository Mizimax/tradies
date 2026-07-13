#ifndef QBR_BASKETMANAGER_MQH
#define QBR_BASKETMANAGER_MQH

#include "Types.mqh"

class CBasketManager
  {
private:
   string            m_symbol;
   QBRConfig         m_cfg;
   QBRBasketSnapshot m_snapshot;
   double            m_peak_profit;
   double            m_trough_profit;
   double            m_target_pct_override;
   double            m_hard_stop_pct_override;

public:
   CBasketManager(void)
     {
      ZeroMemory(m_snapshot);
      m_snapshot.direction=QBR_DIR_FLAT;
      m_peak_profit=0.0;
      m_trough_profit=0.0;
      m_target_pct_override=-1.0;
      m_hard_stop_pct_override=-1.0;
     }

   void SetRiskProfileOverrides(const double target_pct,const double hard_stop_pct)
     {
      m_target_pct_override=target_pct;
      m_hard_stop_pct_override=hard_stop_pct;
     }

   void ClearRiskProfileOverrides(void)
     {
      m_target_pct_override=-1.0;
      m_hard_stop_pct_override=-1.0;
     }

   void Configure(const string symbol,const QBRConfig &cfg)
     {
      m_symbol=symbol;
      m_cfg=cfg;
     }

   QBRBasketSnapshot Refresh(const double atr)
     {
      QBRBasketSnapshot s;
      ZeroMemory(s);
      s.direction=QBR_DIR_FLAT;
      s.start_time=0;
      s.last_entry_time=0;
      double weighted=0.0;
      int long_count=0,short_count=0;

      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic) continue;
         ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double volume=PositionGetDouble(POSITION_VOLUME);
         double price=PositionGetDouble(POSITION_PRICE_OPEN);
         datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
         s.orders++;
         s.total_lots+=volume;
         weighted+=price*volume;
         s.floating_profit+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
         if(type==POSITION_TYPE_BUY) long_count++; else if(type==POSITION_TYPE_SELL) short_count++;
         if(s.start_time==0 || opened<s.start_time) s.start_time=opened;
         if(opened>=s.last_entry_time)
           {
            s.last_entry_time=opened;
            s.last_entry_price=price;
           }
        }
      if(s.total_lots>0.0) s.weighted_average=weighted/s.total_lots;
      if(long_count>0 && short_count==0) s.direction=QBR_DIR_LONG;
      else if(short_count>0 && long_count==0) s.direction=QBR_DIR_SHORT;
      else if(long_count>0 && short_count>0) s.direction=QBR_DIR_FLAT;

      if(s.orders>0)
        {
         if(m_snapshot.orders==0)
           {
            m_peak_profit=s.floating_profit;
            m_trough_profit=s.floating_profit;
           }
         m_peak_profit=MathMax(m_peak_profit,s.floating_profit);
         m_trough_profit=MathMin(m_trough_profit,s.floating_profit);
         s.mfe=m_peak_profit;
         s.mae=m_trough_profit;
         s.basket_id=(long)s.start_time;
         int seconds_per_bar=PeriodSeconds(m_cfg.execution_tf);
         if(seconds_per_bar>0) s.age_bars=(int)((TimeCurrent()-s.start_time)/seconds_per_bar);

         double balance=AccountInfoDouble(ACCOUNT_BALANCE);
         double equity=AccountInfoDouble(ACCOUNT_EQUITY);
         if(m_target_pct_override>=0.0) s.target_money=balance*m_target_pct_override/100.0;
         else if(m_cfg.basket_target_mode==TARGET_FIXED_MONEY) s.target_money=m_cfg.basket_target_value;
         else if(m_cfg.basket_target_mode==TARGET_BALANCE_PERCENT) s.target_money=balance*m_cfg.basket_target_value/100.0;
         else if(m_cfg.basket_target_mode==TARGET_EQUITY_PERCENT) s.target_money=equity*m_cfg.basket_target_value/100.0;
         else if(m_cfg.basket_target_mode==TARGET_PER_LOT) s.target_money=s.total_lots*m_cfg.basket_target_value;
         else
           {
            double tick_size=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
            double tick_value=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
            double atr_value=QBRSafeDivide(atr,tick_size,0.0)*tick_value*s.total_lots;
            s.target_money=atr_value*m_cfg.basket_target_value;
           }
         double hard_stop_pct=(m_hard_stop_pct_override>=0.0 ? m_hard_stop_pct_override : m_cfg.basket_hard_stop_pct);
         s.hard_stop_money=-balance*hard_stop_pct/100.0;

         double margin=0.0;
         ENUM_ORDER_TYPE order_type=(s.direction==QBR_DIR_SHORT ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
         if(s.direction!=QBR_DIR_FLAT)
           {
            double price=(s.direction==QBR_DIR_LONG ? SymbolInfoDouble(m_symbol,SYMBOL_ASK) : SymbolInfoDouble(m_symbol,SYMBOL_BID));
            if(!OrderCalcMargin(order_type,m_symbol,s.total_lots,price,margin))
               margin=AccountInfoDouble(ACCOUNT_MARGIN);
           }
         s.margin_usage=margin;
        }
      else
        {
         m_peak_profit=0.0;
         m_trough_profit=0.0;
        }
      m_snapshot=s;
      return m_snapshot;
     }

   QBRBasketSnapshot Snapshot(void) const { return m_snapshot; }

   int CountDirection(const QBRDirection direction) const
     {
      int count=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic) continue;
         ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(direction==QBR_DIR_LONG && type==POSITION_TYPE_BUY) count++;
         if(direction==QBR_DIR_SHORT && type==POSITION_TYPE_SELL) count++;
        }
      return count;
     }

   bool HasOpposite(const QBRDirection direction) const
     {
      if(m_snapshot.orders==0) return false;
      if(m_snapshot.direction==QBR_DIR_FLAT) return true;
      return (m_snapshot.direction!=direction);
     }

   bool SpacingPassed(const QBRDirection direction,const double current_price,const double atr) const
     {
      if(m_snapshot.orders==0) return true;
      if(m_snapshot.last_entry_price<=0.0 || atr<=0.0) return false;
      double distance=MathAbs(current_price-m_snapshot.last_entry_price);
      return distance>=m_cfg.entry_spacing_atr*atr;
     }

   bool ProfitTargetHit(void) const
     {
      return (m_snapshot.orders>0 && m_snapshot.floating_profit>=m_snapshot.target_money);
     }

   bool HardStopHit(void) const
     {
      return (m_snapshot.orders>0 && m_snapshot.floating_profit<=m_snapshot.hard_stop_money);
     }

   bool TimeStopHit(void) const
     {
      return (m_cfg.basket_max_age_bars>0 && m_snapshot.age_bars>=m_cfg.basket_max_age_bars);
     }

   double RealizedSince(const datetime start_time) const
     {
      if(start_time<=0 || !HistorySelect(start_time,TimeCurrent())) return 0.0;
      double net=0.0;
      for(int i=0;i<HistoryDealsTotal();i++)
        {
         ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0) continue;
         if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=m_symbol) continue;
         if((long)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=m_cfg.magic) continue;
         net+=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_SWAP)+
              HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_FEE);
        }
      return net;
     }

   QBRPerformanceStats PerformanceStats(const datetime from_time=0) const
     {
      QBRPerformanceStats s;
      ZeroMemory(s);
      datetime start=(from_time>0 ? from_time : 0);
      if(!HistorySelect(start,TimeCurrent())) return s;
      double winners=0.0,losers=0.0;
      for(int i=0;i<HistoryDealsTotal();i++)
        {
         ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0) continue;
         if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=m_symbol) continue;
         if((long)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=m_cfg.magic) continue;
         long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT) continue;
         double net=HistoryDealGetDouble(ticket,DEAL_PROFIT)+HistoryDealGetDouble(ticket,DEAL_SWAP)+
                    HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_FEE);
         if(net>0.0)
           {
            s.winning_orders++; winners+=net; s.gross_profit+=net;
            if(net>s.largest_winner) s.largest_winner=net;
           }
         else if(net<0.0)
           {
            s.losing_orders++; losers+=net; s.gross_loss+=net;
            if(net<s.largest_loser) s.largest_loser=net;
           }
        }
      if(s.winning_orders>0) s.average_winner=winners/s.winning_orders;
      if(s.losing_orders>0) s.average_loser=losers/s.losing_orders;
      s.profit_factor=QBRSafeDivide(s.gross_profit,MathAbs(s.gross_loss),0.0);
      s.payoff_ratio=QBRSafeDivide(s.average_winner,MathAbs(s.average_loser),0.0);
      s.wins_erased_by_average_loss=QBRSafeDivide(MathAbs(s.average_loser),s.average_winner,0.0);
      s.small_wins_erased_by_largest_loss=QBRSafeDivide(MathAbs(s.largest_loser),s.average_winner,0.0);
      return s;
     }
  };

#endif
