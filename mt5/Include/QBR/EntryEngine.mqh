#ifndef QBR_ENTRYENGINE_MQH
#define QBR_ENTRYENGINE_MQH

#include "Types.mqh"

class CEntryEngine
  {
private:
   QBRConfig m_cfg;

   bool IsTrendReentryPattern(const string name) const
     {
      return (name=="TREND_PULLBACK" || name=="BREAKOUT_AND_RETEST" ||
              name=="FAILED_BREAKOUT" || name=="REVERSAL_REJECTION" ||
              name=="INSIDE_BAR_COMPRESSION");
     }

public:
   void Configure(const QBRConfig &cfg) { m_cfg=cfg; }

   QBREntryDecision Evaluate(const QBRState state,const QBRFeatures &f,const QBRQSyncResult &qsync,
                             const QBRPatternSignal &pattern,const QBRBalanceResult &balance,
                             const QBRSafetyResult &safety,const QBRBasketSnapshot &basket,
                             const bool spacing_passed,const int direction_order_count)
     {
      QBREntryDecision d;
      d.allow=false;
      d.direction=QBR_DIR_FLAT;
      d.reason="No directional candidate";
      d.signal_id=StringFormat("%s-%I64d",_Symbol,(long)f.timestamp);

      if(state==QBR_TREND_UP || state==QBR_BREAKOUT_UP || state==QBR_BASKET_LONG) d.direction=QBR_DIR_LONG;
      else if(state==QBR_TREND_DOWN || state==QBR_BREAKOUT_DOWN || state==QBR_BASKET_SHORT) d.direction=QBR_DIR_SHORT;
      else if(m_cfg.allow_balanced_reentry && state==QBR_BALANCED && pattern.detected)
         d.direction=pattern.direction;
      else { d.reason="StateFlow not in entry state"; return d; }

      if(!safety.allow) { d.reason=safety.reason; return d; }
      if(d.direction==QBR_DIR_LONG && f.h4_bias<=0) { d.reason="H4 long bias missing"; return d; }
      if(d.direction==QBR_DIR_SHORT && f.h4_bias>=0) { d.reason="H4 short bias missing"; return d; }
      if(m_cfg.require_daily_alignment)
        {
         if(d.direction==QBR_DIR_LONG && f.daily_bias<0) { d.reason="Daily trend conflicts with long"; return d; }
         if(d.direction==QBR_DIR_SHORT && f.daily_bias>0) { d.reason="Daily trend conflicts with short"; return d; }
        }
      if(d.direction==QBR_DIR_LONG && qsync.total<m_cfg.long_threshold) { d.reason="Long Q-Sync threshold not reached"; return d; }
      if(d.direction==QBR_DIR_SHORT && qsync.total>m_cfg.short_threshold) { d.reason="Short Q-Sync threshold not reached"; return d; }
      if(!pattern.detected || pattern.direction!=d.direction) { d.reason="No aligned deterministic pattern"; return d; }
      if(pattern.confidence<m_cfg.min_pattern_confidence) { d.reason="Pattern confidence below minimum"; return d; }
      if(m_cfg.require_trend_reentry && !IsTrendReentryPattern(pattern.name)) { d.reason="Entry profile rejects chase/impulse pattern"; return d; }

      double ema_distance=QBRSafeDivide(MathAbs(f.close_price-f.ema_fast),MathMax(f.atr,1e-8),999.0);
      if(ema_distance>m_cfg.max_entry_distance_ema_atr) { d.reason="Entry too extended from M15 EMA"; return d; }
      if(d.direction==QBR_DIR_LONG && f.rsi>m_cfg.max_rsi_long) { d.reason="Long entry RSI overextended"; return d; }
      if(d.direction==QBR_DIR_SHORT && f.rsi<m_cfg.min_rsi_short) { d.reason="Short entry RSI overextended"; return d; }
      if(!balance.allow_entry) { d.reason=balance.reason; return d; }
      if(basket.orders>0 && basket.direction!=d.direction) { d.reason="Opposite or mixed basket exists"; return d; }
      if(direction_order_count>=m_cfg.max_orders_direction) { d.reason="Maximum orders for direction reached"; return d; }
      if(m_cfg.entry_mode==SINGLE_ENTRY && basket.orders>0) { d.reason="Single-entry mode already has a position"; return d; }
      if(basket.orders>0 && !spacing_passed) { d.reason="ATR spacing from last entry not reached"; return d; }
      if(basket.orders>0 && !m_cfg.averaging_against_move)
        {
         bool adverse=(d.direction==QBR_DIR_LONG && f.close_price<basket.last_entry_price) ||
                      (d.direction==QBR_DIR_SHORT && f.close_price>basket.last_entry_price);
         if(adverse) { d.reason="Averaging against the latest entry is disabled"; return d; }
        }

      if(basket.orders>0)
        {
         if(m_cfg.add_mode==ADD_ON_CONTINUATION && pattern.name!="MOMENTUM_CONTINUATION" && pattern.name!="MULTI_BAR_DIRECTIONAL_SEQUENCE")
           { d.reason="Continuation add mode not confirmed"; return d; }
         if(m_cfg.add_mode==ADD_ON_PULLBACK && pattern.name!="TREND_PULLBACK" && pattern.name!="REVERSAL_REJECTION")
           { d.reason="Pullback add mode not confirmed"; return d; }
         if(m_cfg.add_mode==ADD_ON_BREAKOUT_RETEST && pattern.name!="BREAKOUT_AND_RETEST")
           { d.reason="Breakout-retest add mode not confirmed"; return d; }
        }
      d.allow=true;
      d.reason="All entry gates passed";
      return d;
     }
  };

#endif
