#ifndef PROPGUARD_TELEMETRY_MQH
#define PROPGUARD_TELEMETRY_MQH

#include "PropRules.mqh"

//+------------------------------------------------------------------+
//| Telemetry.mqh -- CSV journal, rule-state log, rejection log, and  |
//| a lightweight chart dashboard. See the approved plan §9.          |
//+------------------------------------------------------------------+

void PropGuardResetJournal()
  {
   int handle=FileOpen("PropGuard/trades.csv",FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI,',');
   if(handle==INVALID_HANDLE) return;
   FileWrite(handle,"timestamp","engine","direction","entry","sl","tp","lots","risk_cash",
             "clamp_bound","spread_price","cost_to_stop_pct","atr","range_width","vol_ratio",
             "phase","ticket","event","reason","exit_price","r_multiple");
   FileClose(handle);
  }

//--- One row per lifecycle event (open / close), so a full trade's economics can be
//--- reconstructed from two rows without a separate join.
void PropGuardJournalTrade(const string enginePrefix,const int direction,
                            const double entry,const double sl,const double tp,
                            const double lots,const double riskCash,const string clampBound,
                            const double spreadPrice,const double costToStopPct,
                            const double atr,const double rangeWidth,const double volRatio,
                            const int phase,const ulong ticket,const string event,
                            const string reason,const double exitPrice,const double rMultiple)
  {
   int handle=FileOpen("PropGuard/trades.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI,',');
   if(handle==INVALID_HANDLE) return;
   FileSeek(handle,0,SEEK_END);
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   string timestamp=StringFormat("%04d.%02d.%02d %02d:%02d:%02d",t.year,t.mon,t.day,t.hour,t.min,t.sec);
   FileWrite(handle,timestamp,enginePrefix,direction,
             DoubleToString(entry,5),DoubleToString(sl,5),DoubleToString(tp,5),
             DoubleToString(lots,2),DoubleToString(riskCash,2),clampBound,
             DoubleToString(spreadPrice,5),DoubleToString(costToStopPct,3),
             DoubleToString(atr,5),DoubleToString(rangeWidth,5),DoubleToString(volRatio,3),
             PropGuardPhaseToString(phase),(long)ticket,event,reason,
             DoubleToString(exitPrice,5),DoubleToString(rMultiple,3));
   FileClose(handle);
  }

void PropGuardResetRejectionLog()
  {
   int handle=FileOpen("PropGuard/rejections.csv",FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI,',');
   if(handle==INVALID_HANDLE) return;
   FileWrite(handle,"timestamp","engine","reason");
   FileClose(handle);
  }

//--- Every blocked signal, with its reason, so filter attribution is measurable rather than
//--- guessed (approved plan §9).
void PropGuardLogRejection(const string enginePrefix,const string reason)
  {
   int handle=FileOpen("PropGuard/rejections.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI,',');
   if(handle==INVALID_HANDLE) return;
   FileSeek(handle,0,SEEK_END);
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   string timestamp=StringFormat("%04d.%02d.%02d %02d:%02d:%02d",t.year,t.mon,t.day,t.hour,t.min,t.sec);
   FileWrite(handle,timestamp,enginePrefix,reason);
   FileClose(handle);
  }

void PropGuardResetStateLog()
  {
   int handle=FileOpen("PropGuard/state.csv",FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI,',');
   if(handle==INVALID_HANDLE) return;
   FileWrite(handle,"timestamp","phase","equity","balance","day_baseline","daily_soft_floor",
             "daily_hard_floor","equity_peak","max_dd_floor","halted","halt_reason");
   FileClose(handle);
  }

//--- Daily/event row reconciled against the firm's own dashboard in gate G6 (plan §8).
void PropGuardLogState(const int phase,const double equity,const double balance,
                        const double dayBaseline,const double dailySoftFloor,
                        const double dailyHardFloor,const double equityPeak,
                        const double maxDdFloor,const bool halted,const string haltReason)
  {
   int handle=FileOpen("PropGuard/state.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI,',');
   if(handle==INVALID_HANDLE) return;
   FileSeek(handle,0,SEEK_END);
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   string timestamp=StringFormat("%04d.%02d.%02d %02d:%02d:%02d",t.year,t.mon,t.day,t.hour,t.min,t.sec);
   FileWrite(handle,timestamp,PropGuardPhaseToString(phase),
             DoubleToString(equity,2),DoubleToString(balance,2),DoubleToString(dayBaseline,2),
             DoubleToString(dailySoftFloor,2),DoubleToString(dailyHardFloor,2),
             DoubleToString(equityPeak,2),DoubleToString(maxDdFloor,2),
             (halted?"1":"0"),haltReason);
   FileClose(handle);
  }

//--- Lightweight on-chart dashboard via Comment() -- distance to each floor, daily P/L vs
//--- cap, trades today, next reset time. Deliberately minimal (no chart objects) to keep
//--- this file small; see mt5/Include/QBR/Dashboard.mqh for a fuller object-based pattern
//--- if a richer panel is ever needed.
void PropGuardUpdateDashboard(const int phase,const double equity,const double balance,
                               const double dayBaseline,const PropGuardConfig &cfg,
                               const double equityPeak,const double initialBalance,
                               const int tradesToday,const datetime nextReset)
  {
   double dailySoft=PropGuardDailySoftFloor(dayBaseline,cfg);
   double dailyHard=PropGuardDailyHardFloor(dayBaseline,cfg);
   double ddFloor=PropGuardMaxDdFloor(initialBalance,equityPeak,cfg);
   double dailyPnlPct=100.0*(equity-dayBaseline)/dayBaseline;
   double ddUsedPct=100.0*(equityPeak-equity)/MathMax(equityPeak,1.0);
   string text=StringFormat(
      "PropGuard  [%s]\n"
      "Equity          %.2f\n"
      "Balance         %.2f\n"
      "Daily P/L       %.2f%%  (soft %.2f / hard %.2f)\n"
      "Equity peak     %.2f  (DD used %.2f%%)\n"
      "Max-DD floor    %.2f\n"
      "Trades today    %d\n"
      "Next reset      %s",
      PropGuardPhaseToString(phase),equity,balance,dailyPnlPct,dailySoft,dailyHard,
      equityPeak,ddUsedPct,ddFloor,tradesToday,TimeToString(nextReset,TIME_DATE|TIME_MINUTES));
   Comment(text);
  }

#endif
