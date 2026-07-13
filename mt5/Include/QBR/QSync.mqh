#ifndef QBR_QSYNC_MQH
#define QBR_QSYNC_MQH

#include "Types.mqh"

class CQSync
  {
private:
   QBRConfig m_cfg;

public:
   void Configure(const QBRConfig &cfg) { m_cfg=cfg; }

   QBRQSyncResult Evaluate(const QBRFeatures &f,const QBRContextResult &context)
     {
      QBRQSyncResult r;
      ZeroMemory(r);

      double ema_alignment=QBRNormalizeSigned(f.ema_fast-f.ema_slow,MathMax(f.atr,1e-8));
      double ema_slope=QBRNormalizeSigned(f.ema_fast-f.ema_fast_prev,MathMax(0.25*f.atr,1e-8));
      double h4_alignment=(double)f.h4_bias;
      double di_bias=QBRNormalizeSigned(f.di_plus-f.di_minus,25.0);
      double adx_strength=QBRClamp((f.adx-m_cfg.min_adx_trend)/25.0,0.0,1.0);
      r.trend_score=QBRClamp(0.32*ema_alignment+0.18*ema_slope+0.30*h4_alignment+0.20*di_bias*adx_strength,-1.0,1.0);

      double rsi_norm=QBRClamp((f.rsi-50.0)/25.0,-1.0,1.0);
      double multi_momentum=0.50*QBRNormalizeSigned(f.momentum_1,1.0)+
                            0.30*QBRNormalizeSigned(f.momentum_3,2.0)+
                            0.20*QBRNormalizeSigned(f.momentum_5,3.0);
      r.momentum_score=QBRClamp(0.65*multi_momentum+0.35*rsi_norm,-1.0,1.0);

      double breakout=QBRNormalizeSigned(f.breakout_distance,1.5);
      double body_direction=(f.close_price>=f.open_price ? 1.0 : -1.0);
      double impulse=body_direction*QBRClamp(f.body_range_ratio,0.0,1.0);
      r.breakout_score=QBRClamp(0.70*breakout+0.30*impulse,-1.0,1.0);

      double volume_strength=QBRClamp((f.volume_ratio-1.0)/1.5,-1.0,1.0);
      r.volume_score=QBRClamp(volume_strength*body_direction,-1.0,1.0);
      r.context_score=context.total;

      r.volatility_penalty=0.0;
      if(f.atr_ratio>m_cfg.max_atr_ratio)
         r.volatility_penalty=QBRClamp((f.atr_ratio-m_cfg.max_atr_ratio)/MathMax(m_cfg.extreme_atr_ratio-m_cfg.max_atr_ratio,0.1),0.0,1.0);
      r.spread_penalty=QBRClamp(f.spread_atr_ratio/MathMax(m_cfg.max_spread_atr_ratio,1e-8),0.0,1.5);

      int signs=0;
      if(r.trend_score>0.15) signs++;
      if(r.trend_score<-0.15) signs--;
      if(r.momentum_score>0.15) signs++;
      if(r.momentum_score<-0.15) signs--;
      if(r.breakout_score>0.15) signs++;
      if(r.breakout_score<-0.15) signs--;
      bool conflict=(MathAbs(signs)<=1 &&
                     (MathAbs(r.trend_score)+MathAbs(r.momentum_score)+MathAbs(r.breakout_score))>1.0);
      r.conflict_penalty=(conflict ? 0.50 : 0.0);

      double weighted=m_cfg.trend_weight*r.trend_score+
                      m_cfg.momentum_weight*r.momentum_score+
                      m_cfg.breakout_weight*r.breakout_score+
                      m_cfg.volume_weight*r.volume_score+
                      m_cfg.context_weight*r.context_score;
      double weight_sum=MathAbs(m_cfg.trend_weight)+MathAbs(m_cfg.momentum_weight)+
                        MathAbs(m_cfg.breakout_weight)+MathAbs(m_cfg.volume_weight)+
                        MathAbs(m_cfg.context_weight);
      if(weight_sum>0.0) weighted/=weight_sum;
      weighted-=m_cfg.volatility_penalty_weight*r.volatility_penalty;
      weighted-=m_cfg.spread_penalty_weight*r.spread_penalty;
      if(weighted>=0.0) weighted-=m_cfg.conflict_penalty_weight*r.conflict_penalty;
      else weighted+=m_cfg.conflict_penalty_weight*r.conflict_penalty;
      r.total=QBRClamp(weighted,-1.0,1.0);
      return r;
     }
  };

#endif
