#ifndef QBR_CSVLOGGER_MQH
#define QBR_CSVLOGGER_MQH

#include "Types.mqh"

class CCsvLogger
  {
private:
   bool   m_enabled;
   string m_folder;
   string m_run_id;
   string m_build_tag;
   int    m_signals;
   int    m_states;
   int    m_orders;
   int    m_deals;
   int    m_baskets;
   int    m_risk;
   int    m_daily;

   string Clean(string value)
     {
      StringReplace(value,",",";");
      StringReplace(value,"\r"," ");
      StringReplace(value,"\n"," ");
      return value;
     }

   int OpenFile(const string name)
     {
      string path=m_folder+"\\"+name;
      int handle=FileOpen(path,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
      if(handle==INVALID_HANDLE) Print("QBR logger failed to open ",path," error=",GetLastError());
      return handle;
     }

   void EndRow(const int handle)
     {
      if(handle==INVALID_HANDLE) return;
      FileFlush(handle);
     }

public:
   CCsvLogger(void)
     {
      m_enabled=false;
      m_signals=INVALID_HANDLE;
      m_states=INVALID_HANDLE;
      m_orders=INVALID_HANDLE;
      m_deals=INVALID_HANDLE;
      m_baskets=INVALID_HANDLE;
      m_risk=INVALID_HANDLE;
      m_daily=INVALID_HANDLE;
     }

   bool Init(const bool enabled,const string prefix,const string run_id,const string build_tag)
     {
      m_enabled=enabled;
      if(!m_enabled) return true;
      m_folder=(prefix=="" ? "QBR_Logs" : prefix);
      m_run_id=run_id;
      m_build_tag=build_tag;
      FolderCreate(m_folder);
      m_signals=OpenFile("signals.csv");
      m_states=OpenFile("state_transitions.csv");
      m_orders=OpenFile("orders.csv");
      m_deals=OpenFile("deals.csv");
      m_baskets=OpenFile("baskets.csv");
      m_risk=OpenFile("risk_events.csv");
      m_daily=OpenFile("daily_summary.csv");
      if(m_signals==INVALID_HANDLE || m_states==INVALID_HANDLE || m_orders==INVALID_HANDLE || m_deals==INVALID_HANDLE ||
         m_baskets==INVALID_HANDLE || m_risk==INVALID_HANDLE || m_daily==INVALID_HANDLE) return false;

      if(FileSize(m_signals)==0) FileWrite(m_signals,"run_id","build_tag","timestamp","symbol","timeframe","state","direction","trend_score","momentum_score","breakout_score","volume_score","context_score","volatility_penalty","spread_penalty","conflict_penalty","qsync_total","deep_context_total","balance_score","rsi","adx","ema_distance_atr","atr_ratio","spread_points","pattern","pattern_confidence","entry_allowed","rejection_reason");
      if(FileSize(m_states)==0) FileWrite(m_states,"run_id","build_tag","timestamp","old_state","new_state","reason","qsync_score","atr_ratio","adx","spread_points","basket_pl");
      if(FileSize(m_orders)==0) FileWrite(m_orders,"run_id","build_tag","timestamp","action","direction","volume","price","retcode","result","signal_id","basket_id");
      if(FileSize(m_deals)==0) FileWrite(m_deals,"run_id","build_tag","timestamp","deal_ticket","position_id","basket_id","entry","direction","volume","price","gross_profit","costs","net_profit","reason");
      if(FileSize(m_baskets)==0) FileWrite(m_baskets,"run_id","build_tag","basket_id","start_time","end_time","direction","entry_state","child_orders","closed_deals","closed_positions","total_lots","gross_profit","costs","net_profit","mae","mfe","holding_seconds","exit_reason","entry_pattern","entry_pattern_confidence","entry_qsync","entry_balance_score","target_money","hard_stop_money","exit_qsync","exit_context","exit_state");
      if(FileSize(m_risk)==0) FileWrite(m_risk,"run_id","build_tag","timestamp","severity","event","action","state","equity","balance","margin_level","floating_pl","spread_points");
      if(FileSize(m_daily)==0) FileWrite(m_daily,"run_id","build_tag","date","balance","equity","daily_closed_pl","weekly_closed_pl","open_pl","drawdown_pct","winning_orders","losing_orders","profit_factor","average_winner","average_loser","largest_loss","wins_erased_by_average_loss");
      FileSeek(m_signals,0,SEEK_END); FileSeek(m_states,0,SEEK_END); FileSeek(m_orders,0,SEEK_END); FileSeek(m_deals,0,SEEK_END);
      FileSeek(m_baskets,0,SEEK_END); FileSeek(m_risk,0,SEEK_END); FileSeek(m_daily,0,SEEK_END);
      return true;
     }

   void Shutdown(void)
     {
      if(m_signals!=INVALID_HANDLE) FileClose(m_signals);
      if(m_states!=INVALID_HANDLE) FileClose(m_states);
      if(m_orders!=INVALID_HANDLE) FileClose(m_orders);
      if(m_deals!=INVALID_HANDLE) FileClose(m_deals);
      if(m_baskets!=INVALID_HANDLE) FileClose(m_baskets);
      if(m_risk!=INVALID_HANDLE) FileClose(m_risk);
      if(m_daily!=INVALID_HANDLE) FileClose(m_daily);
     }

   void Signal(const QBRFeatures &f,const QBRState state,const QBRDirection direction,
               const QBRQSyncResult &q,const QBRContextResult &ctx,const QBRBalanceResult &bal,
               const QBRPatternSignal &pattern,const bool allowed,const string rejection)
     {
      if(!m_enabled || m_signals==INVALID_HANDLE) return;
      double ema_distance=QBRSafeDivide(MathAbs(f.close_price-f.ema_fast),MathMax(f.atr,1e-8),0.0);
      FileWrite(m_signals,m_run_id,m_build_tag,TimeToString(f.timestamp,TIME_DATE|TIME_SECONDS),_Symbol,EnumToString(PERIOD_M15),
                QBRStateToString(state),QBRDirectionToString(direction),q.trend_score,q.momentum_score,q.breakout_score,
                q.volume_score,q.context_score,q.volatility_penalty,q.spread_penalty,q.conflict_penalty,q.total,ctx.total,
                bal.score,f.rsi,f.adx,ema_distance,f.atr_ratio,f.spread_points,Clean(pattern.name),pattern.confidence,(allowed ? 1 : 0),Clean(rejection));
      EndRow(m_signals);
     }

   void StateTransition(const QBRState old_state,const QBRState new_state,const string reason,
                        const QBRQSyncResult &q,const QBRFeatures &f,const QBRBasketSnapshot &basket)
     {
      if(!m_enabled || m_states==INVALID_HANDLE) return;
      FileWrite(m_states,m_run_id,m_build_tag,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),QBRStateToString(old_state),QBRStateToString(new_state),
                Clean(reason),q.total,f.atr_ratio,f.adx,f.spread_points,basket.floating_profit);
      EndRow(m_states);
     }

   void Order(const string action,const QBRDirection direction,const double volume,const double price,
              const uint retcode,const string result,const string signal_id,const long basket_id)
     {
      if(!m_enabled || m_orders==INVALID_HANDLE) return;
      FileWrite(m_orders,m_run_id,m_build_tag,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Clean(action),QBRDirectionToString(direction),
                volume,price,(long)retcode,Clean(result),Clean(signal_id),basket_id);
      EndRow(m_orders);
     }

   void Deal(const datetime timestamp,const ulong deal_ticket,const long position_id,const long basket_id,
             const string entry,const QBRDirection direction,const double volume,const double price,
             const double gross_profit,const double costs,const string reason)
     {
      if(!m_enabled || m_deals==INVALID_HANDLE) return;
      FileWrite(m_deals,m_run_id,m_build_tag,TimeToString(timestamp,TIME_DATE|TIME_SECONDS),(long)deal_ticket,
                position_id,basket_id,Clean(entry),QBRDirectionToString(direction),volume,price,gross_profit,costs,
                gross_profit+costs,Clean(reason));
      EndRow(m_deals);
     }

   void Basket(const QBRBasketSnapshot &basket,const datetime end_time,const int closed_deals,const int closed_positions,const double gross_profit,
               const double costs,const double net_profit,const string exit_reason,const string entry_pattern,
               const string entry_state,const int entry_confidence,const double entry_qsync,const double entry_balance,
               const double exit_qsync,const double exit_context,const string exit_state)
     {
      if(!m_enabled || m_baskets==INVALID_HANDLE) return;
      FileWrite(m_baskets,m_run_id,m_build_tag,basket.basket_id,TimeToString(basket.start_time,TIME_DATE|TIME_SECONDS),
                TimeToString(end_time,TIME_DATE|TIME_SECONDS),QBRDirectionToString(basket.direction),Clean(entry_state),basket.orders,closed_deals,closed_positions,
                basket.total_lots,gross_profit,costs,net_profit,basket.mae,basket.mfe,(long)(end_time-basket.start_time),Clean(exit_reason),
                Clean(entry_pattern),entry_confidence,entry_qsync,entry_balance,basket.target_money,basket.hard_stop_money,
                exit_qsync,exit_context,Clean(exit_state));
      EndRow(m_baskets);
     }

   void Risk(const string severity,const string event_name,const string action,const QBRState state,
             const QBRBasketSnapshot &basket,const QBRFeatures &f)
     {
      if(!m_enabled || m_risk==INVALID_HANDLE) return;
      FileWrite(m_risk,m_run_id,m_build_tag,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Clean(severity),Clean(event_name),Clean(action),
                QBRStateToString(state),AccountInfoDouble(ACCOUNT_EQUITY),AccountInfoDouble(ACCOUNT_BALANCE),
                AccountInfoDouble(ACCOUNT_MARGIN_LEVEL),basket.floating_profit,f.spread_points);
      EndRow(m_risk);
     }

   void Daily(const double daily_pl,const double weekly_pl,const QBRBasketSnapshot &basket,const QBRPerformanceStats &stats,const double drawdown_pct)
     {
      if(!m_enabled || m_daily==INVALID_HANDLE) return;
      FileWrite(m_daily,m_run_id,m_build_tag,TimeToString(TimeCurrent(),TIME_DATE),AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY),
                daily_pl,weekly_pl,basket.floating_profit,drawdown_pct,stats.winning_orders,stats.losing_orders,stats.profit_factor,
                stats.average_winner,stats.average_loser,stats.largest_loser,stats.wins_erased_by_average_loss);
      EndRow(m_daily);
     }
  };

#endif
