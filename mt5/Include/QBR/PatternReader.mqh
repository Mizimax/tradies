#ifndef QBR_PATTERNREADER_MQH
#define QBR_PATTERNREADER_MQH

#include "Types.mqh"

class CPatternReader
  {
private:
   string    m_symbol;
   QBRConfig m_cfg;

   bool PatternEnabled(const string name) const
     {
      if(name=="TREND_PULLBACK") return m_cfg.enable_trend_pullback;
      if(name=="FAILED_BREAKOUT") return m_cfg.enable_failed_breakout;
      if(name=="BREAKOUT_AND_RETEST") return m_cfg.enable_breakout_retest;
      if(name=="REVERSAL_REJECTION") return m_cfg.enable_reversal_rejection;
      if(name=="INSIDE_BAR_COMPRESSION") return m_cfg.enable_inside_bar_compression;
      return true;
     }

   void Assign(QBRPatternSignal &target,const QBRDirection direction,const int confidence,
               const double invalidation,const string name,const int age)
     {
      target.detected=true;
      target.direction=direction;
      target.confidence=confidence;
      target.invalidation_price=invalidation;
      target.age_bars=age;
      target.source_tf=m_cfg.execution_tf;
      target.name=name;
     }

   void Consider(QBRPatternSignal &best,QBRPatternSignal &aligned,const int preferred_bias,
                 const bool detected,const QBRDirection direction,const int confidence,
                 const double invalidation,const string name,const int age=0)
     {
      if(!detected) return;
      if(!PatternEnabled(name)) return;
      if(confidence>best.confidence) Assign(best,direction,confidence,invalidation,name,age);
      bool is_aligned=(preferred_bias>0 && direction==QBR_DIR_LONG) ||
                      (preferred_bias<0 && direction==QBR_DIR_SHORT);
      if(is_aligned && confidence>aligned.confidence) Assign(aligned,direction,confidence,invalidation,name,age);
     }

public:
   void Configure(const string symbol,const QBRConfig &cfg)
     {
      m_symbol=symbol;
      m_cfg=cfg;
     }

   QBRPatternSignal Evaluate(const QBRFeatures &f,const QBRState state)
     {
      QBRPatternSignal best,aligned;
      ZeroMemory(best);
      ZeroMemory(aligned);
      best.direction=QBR_DIR_FLAT;
      aligned.direction=QBR_DIR_FLAT;
      best.source_tf=m_cfg.execution_tf;
      aligned.source_tf=m_cfg.execution_tf;
      best.name="NONE";
      aligned.name="NONE";

      MqlRates r[];
      ArraySetAsSeries(r,true);
      int rates_needed=(int)MathMax(12.0,(double)m_cfg.breakout_lookback+3.0);
      if(CopyRates(m_symbol,m_cfg.execution_tf,1,rates_needed,r)<rates_needed) return best;

      double atr=MathMax(f.atr,1e-8);
      bool bull1=r[0].close>r[0].open;
      bool bear1=r[0].close<r[0].open;
      bool bull_seq=(r[0].close>r[1].close && r[1].close>r[2].close && r[0].close>r[0].open);
      bool bear_seq=(r[0].close<r[1].close && r[1].close<r[2].close && r[0].close<r[0].open);
      Consider(best,aligned,f.h4_bias,bull_seq,QBR_DIR_LONG,72,r[2].low,"MULTI_BAR_DIRECTIONAL_SEQUENCE");
      Consider(best,aligned,f.h4_bias,bear_seq,QBR_DIR_SHORT,72,r[2].high,"MULTI_BAR_DIRECTIONAL_SEQUENCE");

      double range0=r[0].high-r[0].low;
      double body0=MathAbs(r[0].close-r[0].open);
      bool large_body=(range0/atr>=1.10 && QBRSafeDivide(body0,range0,0.0)>=0.65);
      Consider(best,aligned,f.h4_bias,large_body && bull1,QBR_DIR_LONG,78,r[0].low,"LARGE_BODY_IMPULSE");
      Consider(best,aligned,f.h4_bias,large_body && bear1,QBR_DIR_SHORT,78,r[0].high,"LARGE_BODY_IMPULSE");

      bool inside=(r[0].high<r[1].high && r[0].low>r[1].low);
      double prior_mom=r[1].close-r[3].close;
      Consider(best,aligned,f.h4_bias,inside && prior_mom>0.5*atr,QBR_DIR_LONG,58,r[1].low,"INSIDE_BAR_COMPRESSION");
      Consider(best,aligned,f.h4_bias,inside && prior_mom<-0.5*atr,QBR_DIR_SHORT,58,r[1].high,"INSIDE_BAR_COMPRESSION");

      double prior_high=-DBL_MAX,prior_low=DBL_MAX;
      for(int i=1;i<=m_cfg.breakout_lookback && i<ArraySize(r);i++)
        {
         if(r[i].high>prior_high) prior_high=r[i].high;
         if(r[i].low<prior_low) prior_low=r[i].low;
        }
      bool breakout_up=(r[0].close>prior_high && bull1);
      bool breakout_down=(r[0].close<prior_low && bear1);
      Consider(best,aligned,f.h4_bias,breakout_up,QBR_DIR_LONG,84,prior_high,"SWING_BREAKOUT");
      Consider(best,aligned,f.h4_bias,breakout_down,QBR_DIR_SHORT,84,prior_low,"SWING_BREAKOUT");

      // Retest level excludes the breakout bar itself. The old calculation used
      // r[1] inside prior_high/prior_low, making r[1].close>prior_high (or the
      // short equivalent) mathematically impossible.
      double retest_high=-DBL_MAX,retest_low=DBL_MAX;
      for(int i=2;i<=m_cfg.breakout_lookback+1 && i<ArraySize(r);i++)
        {
         if(r[i].high>retest_high) retest_high=r[i].high;
         if(r[i].low<retest_low) retest_low=r[i].low;
        }
      bool retest_up=(r[1].close>retest_high && r[0].low<=retest_high+0.15*atr && r[0].close>retest_high);
      bool retest_down=(r[1].close<retest_low && r[0].high>=retest_low-0.15*atr && r[0].close<retest_low);
      Consider(best,aligned,f.h4_bias,retest_up,QBR_DIR_LONG,88,r[0].low,"BREAKOUT_AND_RETEST");
      Consider(best,aligned,f.h4_bias,retest_down,QBR_DIR_SHORT,88,r[0].high,"BREAKOUT_AND_RETEST");

      double avg_old=0.0,avg_new=0.0;
      for(int i=1;i<=4;i++) avg_new+=(r[i].high-r[i].low);
      for(int i=5;i<=8;i++) avg_old+=(r[i].high-r[i].low);
      avg_new/=4.0; avg_old/=4.0;
      bool expansion=(avg_new>1.25*avg_old && range0>1.20*avg_new);
      Consider(best,aligned,f.h4_bias,expansion && bull1,QBR_DIR_LONG,76,r[0].low,"ATR_CONTRACTION_EXPANSION");
      Consider(best,aligned,f.h4_bias,expansion && bear1,QBR_DIR_SHORT,76,r[0].high,"ATR_CONTRACTION_EXPANSION");

      bool pullback_state_allowed=(state!=QBR_BALANCED || m_cfg.allow_trend_pullback_in_balanced);
      bool pullback_long=(pullback_state_allowed && f.h4_bias>0 && r[1].close<f.ema_fast && r[0].close>f.ema_fast && bull1);
      bool pullback_short=(pullback_state_allowed && f.h4_bias<0 && r[1].close>f.ema_fast && r[0].close<f.ema_fast && bear1);
      Consider(best,aligned,f.h4_bias,pullback_long,QBR_DIR_LONG,74,MathMin(r[0].low,r[1].low),"TREND_PULLBACK");
      Consider(best,aligned,f.h4_bias,pullback_short,QBR_DIR_SHORT,74,MathMax(r[0].high,r[1].high),"TREND_PULLBACK");

      double upper_wick=r[0].high-MathMax(r[0].open,r[0].close);
      double lower_wick=MathMin(r[0].open,r[0].close)-r[0].low;
      bool rejection_long=(lower_wick>2.0*body0 && r[0].close>r[0].open);
      bool rejection_short=(upper_wick>2.0*body0 && r[0].close<r[0].open);
      Consider(best,aligned,f.h4_bias,rejection_long,QBR_DIR_LONG,64,r[0].low,"REVERSAL_REJECTION");
      Consider(best,aligned,f.h4_bias,rejection_short,QBR_DIR_SHORT,64,r[0].high,"REVERSAL_REJECTION");

      bool failed_up=(r[0].high>prior_high && r[0].close<prior_high && bear1);
      bool failed_down=(r[0].low<prior_low && r[0].close>prior_low && bull1);
      Consider(best,aligned,f.h4_bias,failed_up,QBR_DIR_SHORT,80,r[0].high,"FAILED_BREAKOUT");
      Consider(best,aligned,f.h4_bias,failed_down,QBR_DIR_LONG,80,r[0].low,"FAILED_BREAKOUT");

      bool continuation_long=(f.h4_bias>0 && f.momentum_1>0.25 && f.momentum_3>0.50 && f.adx>=m_cfg.min_adx_trend);
      bool continuation_short=(f.h4_bias<0 && f.momentum_1<-0.25 && f.momentum_3<-0.50 && f.adx>=m_cfg.min_adx_trend);
      Consider(best,aligned,f.h4_bias,continuation_long,QBR_DIR_LONG,70,r[1].low,"MOMENTUM_CONTINUATION");
      Consider(best,aligned,f.h4_bias,continuation_short,QBR_DIR_SHORT,70,r[1].high,"MOMENTUM_CONTINUATION");
      return (aligned.detected ? aligned : best);
     }
  };

#endif
