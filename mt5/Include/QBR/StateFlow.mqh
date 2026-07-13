#ifndef QBR_STATEFLOW_MQH
#define QBR_STATEFLOW_MQH

#include "Types.mqh"

class CStateFlow
  {
private:
   QBRConfig m_cfg;
   QBRState  m_state;
   QBRState  m_candidate;
   int       m_candidate_bars;
   string    m_reason;

   QBRState RawState(const QBRFeatures &f,const QBRQSyncResult &qsync,const QBRBalanceResult &balance,
                     const QBRBasketSnapshot &basket,const bool paused,const bool warm,
                     const bool daily_stop,const bool emergency,const bool spike,const int cooldown_remaining)
     {
      if(emergency) return QBR_EMERGENCY;
      if(paused) return QBR_DISABLED;
      if(!warm) return QBR_WARMUP;
      if(daily_stop) return QBR_DAILY_STOP;
      if(spike) return QBR_SPIKE;
      if(cooldown_remaining>0) return QBR_COOLDOWN;
      if(basket.orders>0) return (basket.direction==QBR_DIR_LONG ? QBR_BASKET_LONG : QBR_BASKET_SHORT);
      if(balance.market_class==MARKET_EXTREME_VOLATILITY) return QBR_HIGH_VOLATILITY;
      // StateFlow identifies the market regime; EntryEngine applies the final
      // Q-Sync threshold. Requiring the same total threshold in both places
      // duplicated the gate and caused short-lived valid signals to be missed.
      double regime_threshold=MathMax(0.08,MathMin(0.18,MathAbs(m_cfg.long_threshold)*0.50));
      if(balance.market_class==MARKET_TRADABLE_BREAKOUT)
        {
         if(qsync.breakout_score>=m_cfg.breakout_threshold) return QBR_BREAKOUT_UP;
         if(qsync.breakout_score<=-m_cfg.breakout_threshold) return QBR_BREAKOUT_DOWN;
        }
      bool trend_regime=(f.adx>=m_cfg.min_adx_trend || balance.market_class==MARKET_STABLE_TREND);
      bool long_regime=(qsync.trend_score>=regime_threshold ||
                        (f.di_plus>f.di_minus && qsync.momentum_score>0.0));
      bool short_regime=(qsync.trend_score<=-regime_threshold ||
                         (f.di_minus>f.di_plus && qsync.momentum_score<0.0));
      if(trend_regime && f.h4_bias>0 && long_regime) return QBR_TREND_UP;
      if(trend_regime && f.h4_bias<0 && short_regime) return QBR_TREND_DOWN;
      if(balance.score>=m_cfg.min_balance_score) return QBR_BALANCED;
      return QBR_SCAN;
     }

public:
   CStateFlow(void)
     {
      m_state=QBR_WARMUP;
      m_candidate=QBR_WARMUP;
      m_candidate_bars=0;
      m_reason="Initial state";
     }

   void Configure(const QBRConfig &cfg) { m_cfg=cfg; }
   QBRState Current(void) const { return m_state; }
   string LastReason(void) const { return m_reason; }

   bool Update(const QBRFeatures &f,const QBRQSyncResult &qsync,const QBRBalanceResult &balance,
               const QBRBasketSnapshot &basket,const bool paused,const bool warm,
               const bool daily_stop,const bool emergency,const bool spike,const int cooldown_remaining,
               QBRState &old_state,QBRState &new_state,string &reason)
     {
      QBRState raw=RawState(f,qsync,balance,basket,paused,warm,daily_stop,emergency,spike,cooldown_remaining);
      bool immediate=(raw==QBR_EMERGENCY || raw==QBR_SPIKE || raw==QBR_DAILY_STOP ||
                      raw==QBR_DISABLED || raw==QBR_BASKET_LONG || raw==QBR_BASKET_SHORT ||
                      raw==QBR_WARMUP || raw==QBR_COOLDOWN);
      if(raw==m_state)
        {
         m_candidate=raw;
         m_candidate_bars=0;
         return false;
        }
      if(raw!=m_candidate)
        {
         m_candidate=raw;
         m_candidate_bars=1;
        }
      else m_candidate_bars++;

      if(!immediate && m_candidate_bars<m_cfg.state_hysteresis_bars) return false;
      old_state=m_state;
      m_state=raw;
      new_state=m_state;
      if(raw==QBR_SPIKE) reason="SpikeGuard activated";
      else if(raw==QBR_EMERGENCY) reason="Hard risk monitor activated";
      else if(raw==QBR_DAILY_STOP) reason="Daily loss limit reached";
      else if(raw==QBR_BASKET_LONG || raw==QBR_BASKET_SHORT) reason="Open EA basket recovered/active";
      else if(raw==QBR_TREND_UP || raw==QBR_TREND_DOWN) reason="H4 bias and Q-Sync trend agreement";
      else if(raw==QBR_BREAKOUT_UP || raw==QBR_BREAKOUT_DOWN) reason="Tradable breakout classification";
      else if(raw==QBR_HIGH_VOLATILITY) reason="Volatility regime exceeds entry tolerance";
      else if(raw==QBR_BALANCED) reason="Tradability score passed without directional trigger";
      else reason="Scanning/no complete setup";
      m_reason=reason;
      m_candidate_bars=0;
      return true;
     }

   void Force(const QBRState state,const string reason)
     {
      m_state=state;
      m_candidate=state;
      m_candidate_bars=0;
      m_reason=reason;
     }
  };

#endif
