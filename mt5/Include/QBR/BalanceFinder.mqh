#ifndef QBR_BALANCEFINDER_MQH
#define QBR_BALANCEFINDER_MQH

#include "Types.mqh"

class CBalanceFinder
  {
private:
   QBRConfig m_cfg;

public:
   void Configure(const QBRConfig &cfg) { m_cfg=cfg; }

   QBRBalanceResult Evaluate(const QBRFeatures &f,const QBRQSyncResult &qsync,const QBRPatternSignal &pattern)
     {
      QBRBalanceResult r;
      ZeroMemory(r);
      double atr_stability=100.0*(1.0-QBRClamp(MathAbs(f.atr_ratio-1.0)/MathMax(m_cfg.extreme_atr_ratio-1.0,0.5),0.0,1.0));
      double percentile_score=100.0*(1.0-QBRClamp(MathAbs(f.atr_percentile-55.0)/55.0,0.0,1.0));
      double adx_score=(f.adx>=m_cfg.min_adx_trend ? 80.0 :
                       (f.adx<=m_cfg.max_adx_balance ? 55.0 : 65.0));
      double spread_score=100.0*(1.0-QBRClamp(f.spread_atr_ratio/MathMax(m_cfg.max_spread_atr_ratio,1e-8),0.0,1.0));
      double normalized_variance=QBRSafeDivide(MathSqrt(MathMax(f.bar_range_variance,0.0)),MathMax(f.atr,1e-8),0.0);
      double variance_score=100.0*(1.0-QBRClamp(normalized_variance/1.5,0.0,1.0));
      double conflict_score=100.0*(1.0-QBRClamp(qsync.conflict_penalty,0.0,1.0));
      double gap_score=100.0*(1.0-QBRClamp(f.gap_atr/m_cfg.spike_gap_atr,0.0,1.0));
      double volume_score=100.0*(1.0-QBRClamp(MathAbs(f.volume_ratio-1.0)/MathMax(m_cfg.spike_volume_ratio-1.0,0.5),0.0,1.0));
      double agreement=(f.h4_bias==0 ? 50.0 : ((f.h4_bias>0 && qsync.total>0.0)||(f.h4_bias<0 && qsync.total<0.0) ? 100.0 : 0.0));
      double spike_distance_score=(f.previous_bar_range_atr>=m_cfg.spike_previous_range_atr ? 0.0 : 100.0);

      r.score=0.17*atr_stability+0.10*percentile_score+0.12*adx_score+0.14*spread_score+
              0.10*variance_score+0.10*conflict_score+0.07*gap_score+0.06*volume_score+
              0.09*agreement+0.05*spike_distance_score;
      r.score=QBRClamp(r.score,0.0,100.0);

      bool extreme=(f.atr_ratio>=m_cfg.extreme_atr_ratio ||
                    f.current_bar_range_atr>=m_cfg.spike_current_range_atr ||
                    f.spread_atr_ratio>=m_cfg.max_spread_atr_ratio*1.5);
      bool breakout=(pattern.detected &&
                     (pattern.name=="SWING_BREAKOUT" || pattern.name=="BREAKOUT_AND_RETEST" || pattern.name=="ATR_CONTRACTION_EXPANSION") &&
                     MathAbs(qsync.breakout_score)>=m_cfg.breakout_threshold &&
                     f.atr_ratio>=0.90 && f.atr_ratio<m_cfg.extreme_atr_ratio);

      if(extreme)
        {
         r.market_class=MARKET_EXTREME_VOLATILITY;
         r.reason="Extreme volatility/spread condition";
        }
      else if(breakout)
        {
         r.market_class=MARKET_TRADABLE_BREAKOUT;
         r.reason="Expansion and breakout conditions agree";
        }
      else if(r.score>=m_cfg.min_balance_score && f.adx>=m_cfg.min_adx_trend)
        {
         r.market_class=MARKET_STABLE_TREND;
         r.reason="Stable trend tradability filter passed";
        }
      else
        {
         r.market_class=MARKET_CHOPPY_UNSTABLE;
         r.reason="Tradability score below threshold or weak trend";
        }
      r.breakout_override=breakout;
      r.allow_entry=(r.score>=m_cfg.min_balance_score || breakout) && !extreme;
      return r;
     }
  };

#endif
