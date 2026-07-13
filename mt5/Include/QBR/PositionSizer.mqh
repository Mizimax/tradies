#ifndef QBR_POSITIONSIZER_MQH
#define QBR_POSITIONSIZER_MQH

#include "Types.mqh"

class CPositionSizer
  {
private:
   string    m_symbol;
   QBRConfig m_cfg;

public:
   void Configure(const string symbol,const QBRConfig &cfg)
     {
      m_symbol=symbol;
      m_cfg=cfg;
     }

   double NormalizeVolume(const double requested) const
     {
      double minimum=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      double maximum=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
      double step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      if(step<=0.0) step=minimum;
      double volume=MathFloor((requested+1e-12)/step)*step;
      volume=MathMax(minimum,MathMin(maximum,volume));
      int digits=0;
      double probe=step;
      while(digits<8 && MathAbs(probe-MathRound(probe))>1e-9)
        {
         probe*=10.0;
         digits++;
        }
      return NormalizeDouble(volume,digits);
     }

   double CapVolumeToLimits(const QBRDirection direction,const double requested,
                            const double entry_price,const QBRBasketSnapshot &basket,
                            string &reason) const
     {
      double minimum=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      double step=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      if(step<=0.0) step=minimum;
      double capped=MathMin(requested,MathMax(0.0,m_cfg.max_total_lots-basket.total_lots));

      double one_lot_margin=0.0;
      ENUM_ORDER_TYPE type=(direction==QBR_DIR_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      if(!OrderCalcMargin(type,m_symbol,1.0,entry_price,one_lot_margin) || one_lot_margin<=0.0)
        {
         reason="OrderCalcMargin failed";
         return 0.0;
        }
      double margin_cap=AccountInfoDouble(ACCOUNT_BALANCE)*m_cfg.max_basket_exposure_pct/100.0;
      double remaining_margin=MathMax(0.0,margin_cap-basket.margin_usage);
      capped=MathMin(capped,remaining_margin/one_lot_margin);
      capped=MathFloor((capped+1e-12)/step)*step;
      if(capped+1e-12<minimum)
        {
         reason="Broker minimum lot exceeds total-lot or margin-exposure limit";
         return 0.0;
        }
      return NormalizeVolume(capped);
     }

   double ExistingRiskAtStop(const double stop_price) const
     {
      double risk=0.0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=m_cfg.magic) continue;
         ENUM_POSITION_TYPE position_type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         ENUM_ORDER_TYPE order_type=(position_type==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
         double pnl=0.0;
         if(!OrderCalcProfit(order_type,m_symbol,PositionGetDouble(POSITION_VOLUME),
                             PositionGetDouble(POSITION_PRICE_OPEN),stop_price,pnl))
            return DBL_MAX;
         if(pnl<0.0) risk+=MathAbs(pnl);
        }
      return risk;
     }

   double Calculate(const QBRDirection direction,const double entry_price,const double stop_price,
                    const QBRBasketSnapshot &basket,string &reason) const
     {
      reason="Fixed lot";
      if(m_cfg.sizing_mode==FIXED_LOT || m_cfg.fixed_lot)
        {
         string cap_reason;
         double volume=CapVolumeToLimits(direction,m_cfg.initial_lot,entry_price,basket,cap_reason);
         if(volume<=0.0) reason=cap_reason;
         return volume;
        }

      double risk_pct=(m_cfg.sizing_mode==RISK_PER_ORDER ? m_cfg.risk_per_order_pct : m_cfg.risk_per_basket_pct);
      double risk_money=AccountInfoDouble(ACCOUNT_BALANCE)*risk_pct/100.0;
      if(m_cfg.sizing_mode==RISK_PER_BASKET && basket.orders>0)
        {
         double used_risk=ExistingRiskAtStop(stop_price);
         if(used_risk==DBL_MAX)
           {
            reason="Unable to calculate existing basket risk";
            return 0.0;
           }
         risk_money=MathMax(0.0,risk_money-used_risk);
        }
      if(risk_money<=0.0)
        {
         reason="No remaining risk budget";
         return 0.0;
        }
      if(MathAbs(entry_price-stop_price)<SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE))
        {
         reason="Invalid stop distance";
         return 0.0;
        }
      double one_lot_profit=0.0;
      ENUM_ORDER_TYPE type=(direction==QBR_DIR_LONG ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      if(!OrderCalcProfit(type,m_symbol,1.0,entry_price,stop_price,one_lot_profit))
        {
         reason="OrderCalcProfit failed";
         return 0.0;
        }
      double loss_per_lot=MathAbs(one_lot_profit);
      if(loss_per_lot<=0.0)
        {
         reason="Calculated loss per lot is zero";
         return 0.0;
        }
      double requested=risk_money/loss_per_lot;
      double minimum=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      if(requested+1e-12<minimum)
        {
         bool native_cap_safe=(m_cfg.allow_min_lot_with_native_risk_cap &&
                               m_cfg.sizing_mode==RISK_PER_BASKET &&
                               m_cfg.basket_hard_stop_pct<=m_cfg.risk_per_basket_pct+1e-8);
         if(!native_cap_safe)
           {
            reason="Risk budget is below broker minimum lot";
            return 0.0;
           }
         requested=minimum;
         reason="Broker minimum lot allowed by native basket-risk cap";
        }
      string cap_reason;
      double volume=CapVolumeToLimits(direction,requested,entry_price,basket,cap_reason);
      if(volume<=0.0)
        {
         reason=cap_reason;
         return 0.0;
        }
      if(reason!="Broker minimum lot allowed by native basket-risk cap")
         reason=(m_cfg.sizing_mode==RISK_PER_ORDER ? "Risk per order" : "Risk per basket");
      return volume;
     }

   bool ValidateSymbolProperties(string &reason) const
     {
      double contract=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_CONTRACT_SIZE);
      double tick_size=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE);
      double tick_value=SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE);
      double vmin=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN);
      double vmax=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX);
      double vstep=SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP);
      long stops=SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL);
      if(contract<=0.0 || tick_size<=0.0 || tick_value<=0.0 || vmin<=0.0 || vmax<vmin || vstep<=0.0 || stops<0)
        {
         reason="Invalid broker symbol specification";
         return false;
        }
      reason="Symbol specification valid";
      return true;
     }
  };

#endif
