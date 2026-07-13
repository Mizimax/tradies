#ifndef QBR_DEEPCONTEXT_MQH
#define QBR_DEEPCONTEXT_MQH

#include "Types.mqh"

class CDeepContext
  {
private:
   QBRConfig m_cfg;

   bool InHourWindow(const int hour,const int start_hour,const int end_hour) const
     {
      if(start_hour==end_hour) return true;
      if(start_hour<end_hour) return (hour>=start_hour && hour<end_hour);
      return (hour>=start_hour || hour<end_hour);
     }

   int MinutesToBoundary(const int current_minutes,const int boundary_hour) const
     {
      int boundary=boundary_hour*60;
      int distance=MathAbs(current_minutes-boundary);
      return MathMin(distance,1440-distance);
     }

public:
   void Configure(const QBRConfig &cfg) { m_cfg=cfg; }

   QBRContextResult Evaluate(const QBRFeatures &f,const QBRBasketSnapshot &basket,const int consecutive_losses)
     {
      QBRContextResult r;
      ZeroMemory(r);
      r.fallback_used=true;
      r.warning="Economic calendar integration unavailable; deterministic session/spike fallback active";

      r.h4_bias_score=(double)f.h4_bias;
      r.h4_structure_score=(double)f.h4_structure;
      r.daily_trend_score=(double)f.daily_bias;

      MqlDateTime t;
      TimeToStruct(TimeCurrent(),t);
      bool asian=InHourWindow(t.hour,m_cfg.asian_start_hour,m_cfg.asian_end_hour);
      bool london=InHourWindow(t.hour,m_cfg.london_start_hour,m_cfg.london_end_hour);
      bool ny=InHourWindow(t.hour,m_cfg.new_york_start_hour,m_cfg.new_york_end_hour);
      bool permitted=(asian && m_cfg.allow_asian) || (london && m_cfg.allow_london) || (ny && m_cfg.allow_new_york);
      r.session_score=(permitted ? 0.35 : -1.0);

      int now_minutes=t.hour*60+t.min;
      int nearest=1440;
      nearest=MathMin(nearest,MinutesToBoundary(now_minutes,m_cfg.asian_start_hour));
      nearest=MathMin(nearest,MinutesToBoundary(now_minutes,m_cfg.asian_end_hour));
      nearest=MathMin(nearest,MinutesToBoundary(now_minutes,m_cfg.london_start_hour));
      nearest=MathMin(nearest,MinutesToBoundary(now_minutes,m_cfg.london_end_hour));
      nearest=MathMin(nearest,MinutesToBoundary(now_minutes,m_cfg.new_york_start_hour));
      nearest=MathMin(nearest,MinutesToBoundary(now_minutes,m_cfg.new_york_end_hour));
      r.session_edge_score=(nearest<=m_cfg.session_edge_minutes ? -0.45 : 0.10);

      r.spread_score=1.0-QBRClamp(QBRSafeDivide(f.spread_points,m_cfg.max_spread_points,1.0),0.0,2.0);
      if(f.atr_ratio>=m_cfg.extreme_atr_ratio) r.atr_regime_score=-1.0;
      else if(f.atr_ratio>m_cfg.max_atr_ratio) r.atr_regime_score=-0.5;
      else if(f.atr_ratio>=0.75 && f.atr_ratio<=1.5) r.atr_regime_score=0.4;
      else r.atr_regime_score=0.0;

      double daily_mid=0.5*(f.daily_high+f.daily_low);
      r.daily_location_score=QBRNormalizeSigned(f.close_price-daily_mid,MathMax(f.atr,1e-8));
      double h4_mid=0.5*(f.h4_swing_high+f.h4_swing_low);
      r.h4_location_score=QBRNormalizeSigned(f.close_price-h4_mid,MathMax(2.0*f.atr,1e-8));

      bool likely_failed_breakout=(MathAbs(f.breakout_distance)<0.10 &&
                                   f.previous_bar_range_atr>1.30 &&
                                   f.body_range_ratio<0.35);
      r.breakout_failure_score=(likely_failed_breakout ? -0.6 : 0.0);
      r.loss_streak_score=-QBRClamp((double)consecutive_losses/MathMax(1,m_cfg.max_consecutive_losses),0.0,1.0);
      r.exposure_score=-QBRClamp(QBRSafeDivide(basket.total_lots,m_cfg.max_total_lots,0.0),0.0,1.0);

      double margin_level=AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
      if(margin_level<=0.0) margin_level=9999.0;
      r.margin_score=QBRClamp((margin_level-m_cfg.min_margin_level)/MathMax(m_cfg.min_margin_level,1.0),-1.0,1.0);

      double directional=0.22*r.h4_bias_score+0.14*r.h4_structure_score+0.12*r.daily_trend_score;
      double environment=0.10*r.session_score+0.05*r.session_edge_score+0.08*r.spread_score+0.08*r.atr_regime_score;
      double location=0.06*r.daily_location_score+0.06*r.h4_location_score;
      double risk=0.04*r.breakout_failure_score+0.03*r.loss_streak_score+0.03*r.exposure_score+0.04*r.margin_score;
      r.total=QBRClamp(directional+environment+location+risk,-1.0,1.0);
      return r;
     }
  };

#endif
