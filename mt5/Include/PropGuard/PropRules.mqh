#ifndef PROPGUARD_PROPRULES_MQH
#define PROPGUARD_PROPRULES_MQH

#include "RiskBudget.mqh"

//+------------------------------------------------------------------+
//| PropRules.mqh -- firm rule engine + phase state machine           |
//| Part of PropGuard EA. See mt5/backtests/PROPGUARD_DESIGN.md,      |
//| the definitive frozen spec this file must match.                  |
//+------------------------------------------------------------------+

enum PropGuardPhase
  {
   PROPGUARD_PHASE_CHALLENGE_P1=0,
   PROPGUARD_PHASE_CHALLENGE_P2=1,
   PROPGUARD_PHASE_FUNDED=2
  };

string PropGuardPhaseToString(const int phase)
  {
   switch(phase)
     {
      case PROPGUARD_PHASE_CHALLENGE_P1: return "CHALLENGE_P1";
      case PROPGUARD_PHASE_CHALLENGE_P2: return "CHALLENGE_P2";
      case PROPGUARD_PHASE_FUNDED:       return "FUNDED";
     }
   return "UNKNOWN";
  }

struct PropGuardConfig
  {
   long   magic;
   //--- Firm contract (published rules) -- PROPGUARD_DESIGN.md §1
   double firm_daily_loss_pct;       // e.g. 5.0 FTMO
   double firm_max_dd_pct;           // e.g. 10.0 FTMO
   bool   firm_dd_is_trailing;       // false = static floor off initial balance (FTMO 2-Step)
   double phase1_target_pct;         // 10.0
   double phase2_target_pct;         // 5.0
   //--- Internal thresholds, always strictly tighter than the firm's -- PROPGUARD_DESIGN.md §3
   double daily_soft_halt_pct;       // 2.0
   double daily_hard_flatten_pct;    // 2.5
   double dd_hard_halt_pct;          // 8.0  (of the firm's max-DD budget consumed)
   double daily_profit_cap_pct;      // 2.5
   double target_proximity_pct;      // 1.5
   double cost_gate_max_pct;         // 8.0  (spread+commission)/stopDistance
   int    daily_reset_server_hour;   // 0
   int    friday_close_hour;         // 20
   int    rollover_block_start_hour; // 21
   int    rollover_block_end_hour;   // 23
   double challenge_base_risk_pct;   // 1.00
   double funded_base_risk_pct;      // 0.50
   int    daily_risk_divisor;        // 3
   int    total_risk_divisor;        // 8
   int    max_open_trades;           // 1 -- absolute, never raised
  };

PropGuardConfig PropGuardDefaultFtmo2StepConfig(const long magic)
  {
   PropGuardConfig c;
   c.magic=magic;
   c.firm_daily_loss_pct=5.0;
   c.firm_max_dd_pct=10.0;
   c.firm_dd_is_trailing=false;
   c.phase1_target_pct=10.0;
   c.phase2_target_pct=5.0;
   c.daily_soft_halt_pct=2.0;
   c.daily_hard_flatten_pct=2.5;
   c.dd_hard_halt_pct=8.0;
   c.daily_profit_cap_pct=2.5;
   c.target_proximity_pct=1.5;
   c.cost_gate_max_pct=8.0;
   c.daily_reset_server_hour=0;
   c.friday_close_hour=20;
   c.rollover_block_start_hour=21;
   c.rollover_block_end_hour=23;
   c.challenge_base_risk_pct=1.00;
   c.funded_base_risk_pct=0.50;
   c.daily_risk_divisor=3;
   c.total_risk_divisor=8;
   c.max_open_trades=1;
   return c;
  }

struct PropGuardResult
  {
   bool   allow;
   string reason;
  };

//+------------------------------------------------------------------+
//| GlobalVariable persistence -- magic-scoped throughout.            |
//| GoldBot's daily-loss key is NOT magic-scoped (Risk.mqh:49-65),    |
//| a documented cross-instance bug (AGENTS.md). Do not repeat it.    |
//+------------------------------------------------------------------+

string PropGuardKey(const long magic,const string suffix)
  {
   return StringFormat("PropGuard.%I64d.%s", magic, suffix);
  }

string PropGuardDayKey(const long magic,const datetime day_start,const string suffix)
  {
   MqlDateTime t;
   TimeToStruct(day_start,t);
   return StringFormat("PropGuard.%I64d.%04d%02d%02d.%s", magic, t.year, t.mon, t.day, suffix);
  }

//--- Day boundary in server time, offset by the configurable reset hour. Handles the case
//--- where "now" is before today's reset hour by rolling back to yesterday's boundary.
datetime PropGuardDayStart(const datetime now,const int reset_hour)
  {
   MqlDateTime t;
   TimeToStruct(now,t);
   t.hour=0; t.min=0; t.sec=0;
   datetime midnight=StructToTime(t);
   datetime candidate=midnight+reset_hour*3600;
   if(candidate>now)
      candidate-=86400;
   return candidate;
  }

//--- Initial balance: set once, never overwritten, survives restarts (live/demo). Tester
//--- runs always start clean -- mirrors QBR SafetyFocus.mqh's equity-peak tester/live split.
double PropGuardInitialBalance(const long magic)
  {
   string key=PropGuardKey(magic,"initialBalance");
   if((bool)MQLInfoInteger(MQL_TESTER))
     {
      double b=AccountInfoDouble(ACCOUNT_BALANCE);
      GlobalVariableSet(key,b);
      return b;
     }
   if(GlobalVariableCheck(key))
      return GlobalVariableGet(key);
   double b=AccountInfoDouble(ACCOUNT_BALANCE);
   GlobalVariableSet(key,b);
   return b;
  }

//--- Equity peak: ratchets up only. Tester resets to a clean peak each run; live/demo resumes
//--- the persisted peak so a restart cannot erase drawdown already taken (mirrors QBR
//--- SafetyFocus.mqh:104-108 exactly -- call once per OnInit with reset=true).
double PropGuardEquityPeak(const long magic,const double current_equity,const bool reset_if_tester)
  {
   string key=PropGuardKey(magic,"equityPeak");
   if(reset_if_tester && (bool)MQLInfoInteger(MQL_TESTER))
     {
      GlobalVariableSet(key,current_equity);
      return current_equity;
     }
   double peak=current_equity;
   if(GlobalVariableCheck(key))
      peak=MathMax(current_equity,GlobalVariableGet(key));
   GlobalVariableSet(key,peak);
   return peak;
  }

int PropGuardGetPhase(const long magic)
  {
   string key=PropGuardKey(magic,"phase");
   if(!GlobalVariableCheck(key))
     {
      GlobalVariableSet(key,(double)PROPGUARD_PHASE_CHALLENGE_P1);
      return PROPGUARD_PHASE_CHALLENGE_P1;
     }
   return (int)GlobalVariableGet(key);
  }

void PropGuardSetPhase(const long magic,const int phase)
  {
   GlobalVariableSet(PropGuardKey(magic,"phase"),(double)phase);
  }

//--- Unconditional resets, used ONLY at a genuine phase transition (P1->P2->FUNDED), never
//--- at an ordinary restart. Unlike PropGuardInitialBalance/PropGuardEquityPeak (which
//--- preserve state across live/demo restarts by design), a phase transition legitimately
//--- re-anchors both to the equity at the moment the prior phase's target was hit -- the
//--- firm gives a new account/login at each phase, which is what this simulates.
void PropGuardResetInitialBalanceTo(const long magic,const double value)
  {
   GlobalVariableSet(PropGuardKey(magic,"initialBalance"),value);
  }

void PropGuardResetEquityPeakTo(const long magic,const double value)
  {
   GlobalVariableSet(PropGuardKey(magic,"equityPeak"),value);
  }

int PropGuardNextPhase(const int phase)
  {
   if(phase==PROPGUARD_PHASE_CHALLENGE_P1) return PROPGUARD_PHASE_CHALLENGE_P2;
   if(phase==PROPGUARD_PHASE_CHALLENGE_P2) return PROPGUARD_PHASE_FUNDED;
   return PROPGUARD_PHASE_FUNDED;
  }

//+------------------------------------------------------------------+
//| Realized P/L accounting                                           |
//+------------------------------------------------------------------+

//--- Sum of realized PnL (profit+swap+commission+fee) for this symbol/magic since from_time.
//--- Mirrors QBR SafetyFocus.mqh ClosedProfitSince -- the correct P/L definition for rule
//--- checks (must include swap/commission, not just raw profit).
double PropGuardClosedProfitSince(const string symbol,const long magic,const datetime from_time)
  {
   if(!HistorySelect(from_time,TimeCurrent()))
      return 0.0;
   double profit=0.0;
   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=symbol) continue;
      if((long)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=magic) continue;
      long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT) continue;
      profit+=HistoryDealGetDouble(ticket,DEAL_PROFIT)+
              HistoryDealGetDouble(ticket,DEAL_SWAP)+
              HistoryDealGetDouble(ticket,DEAL_COMMISSION)+
              HistoryDealGetDouble(ticket,DEAL_FEE);
     }
   return profit;
  }

//--- Day-start baseline = current balance minus whatever has already closed today. Floored
//--- at the raw balance if the subtraction goes non-positive (guards a corrupted state).
double PropGuardDayBaseline(const string symbol,const long magic,const datetime day_start)
  {
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double closedToday=PropGuardClosedProfitSince(symbol,magic,day_start);
   double baseline=balance-closedToday;
   return (baseline>0.0 ? baseline : balance);
  }

//+------------------------------------------------------------------+
//| Floors, thresholds, and the guards built on them                  |
//+------------------------------------------------------------------+

double PropGuardDailySoftFloor(const double day_baseline,const PropGuardConfig &cfg)
  {
   return day_baseline*(1.0-cfg.daily_soft_halt_pct/100.0);
  }

double PropGuardDailyHardFloor(const double day_baseline,const PropGuardConfig &cfg)
  {
   return day_baseline*(1.0-cfg.daily_hard_flatten_pct/100.0);
  }

double PropGuardDailyProfitCap(const double day_baseline,const PropGuardConfig &cfg)
  {
   return day_baseline*(1.0+cfg.daily_profit_cap_pct/100.0);
  }

//--- Max-drawdown floor. Static: fixed fraction of initial balance (FTMO 2-Step). Trailing:
//--- fraction of the ratcheting equity peak (FTMO 1-Step / other trailing-DD firms). Either
//--- way the internal halt trips at dd_hard_halt_pct, strictly before the firm's full budget.
double PropGuardMaxDdFloor(const double initial_balance,const double equity_peak,const PropGuardConfig &cfg)
  {
   double keepPct=100.0-cfg.dd_hard_halt_pct;
   if(cfg.firm_dd_is_trailing)
      return equity_peak*(keepPct/100.0);
   return initial_balance*(keepPct/100.0);
  }

bool PropGuardDailySoftHalted(const double equity,const double day_baseline,const PropGuardConfig &cfg)
  {
   return equity<=PropGuardDailySoftFloor(day_baseline,cfg);
  }

bool PropGuardDailyHardFlatten(const double equity,const double day_baseline,const PropGuardConfig &cfg)
  {
   return equity<=PropGuardDailyHardFloor(day_baseline,cfg);
  }

bool PropGuardMaxDdHalted(const double equity,const double initial_balance,const double equity_peak,const PropGuardConfig &cfg)
  {
   return equity<=PropGuardMaxDdFloor(initial_balance,equity_peak,cfg);
  }

bool PropGuardDailyProfitCapReached(const double equity,const double day_baseline,const PropGuardConfig &cfg)
  {
   return equity>=PropGuardDailyProfitCap(day_baseline,cfg);
  }

//+------------------------------------------------------------------+
//| Session / calendar rules                                          |
//+------------------------------------------------------------------+

bool PropGuardIsWeekendFlattenTime(const datetime now,const PropGuardConfig &cfg)
  {
   MqlDateTime t;
   TimeToStruct(now,t);
   if(t.day_of_week==5 && t.hour>=cfg.friday_close_hour) return true;   // Friday, past close hour
   if(t.day_of_week==6 || t.day_of_week==0) return true;                // Saturday / Sunday
   return false;
  }

bool PropGuardIsRolloverBlackout(const datetime now,const PropGuardConfig &cfg)
  {
   MqlDateTime t;
   TimeToStruct(now,t);
   int h=t.hour;
   int s=cfg.rollover_block_start_hour, e=cfg.rollover_block_end_hour;
   if(s==e) return false;
   if(s<e) return (h>=s && h<e);
   return (h>=s || h<e);                                                // overnight wrap
  }

//+------------------------------------------------------------------+
//| Cost & predictive guards                                          |
//+------------------------------------------------------------------+

bool PropGuardCostGateOk(const double spread_price,const double commission_price,
                          const double stop_distance,const PropGuardConfig &cfg)
  {
   if(stop_distance<=0.0) return false;
   double costPct=100.0*(spread_price+commission_price)/stop_distance;
   return costPct<=cfg.cost_gate_max_pct;
  }

//--- Predictive guard: rejects BEFORE a breach can happen, not after. worstCase folds in the
//--- full stop-loss cash risk, round-trip cost, an estimated swap, and any already-open
//--- floating loss. This is the single most important check in the whole rule engine --
//--- every other guard here is reactive.
bool PropGuardProjectionGuardOk(const double equity,const double stop_loss_cash,
                                 const double spread_cash,const double commission_cash,
                                 const double swap_estimate_cash,const double current_floating_loss,
                                 const double daily_floor,const double hard_floor)
  {
   double worstCase=stop_loss_cash+spread_cash+commission_cash+swap_estimate_cash+
                     MathMax(0.0,current_floating_loss);
   double floor=MathMax(daily_floor,hard_floor);
   return (equity-worstCase)>=floor;
  }

//--- Risk % after the target-proximity throttle: halved once within target_proximity_pct of
//--- the active phase's profit target. Near the target the option value of full risk is
//--- negative -- the only remaining way to fail from there is a drawdown.
double PropGuardThrottledRiskPct(const double equity,const double initial_balance,
                                  const double phase_target_pct,const double base_risk_pct,
                                  const PropGuardConfig &cfg)
  {
   double targetLevel=initial_balance*(1.0+phase_target_pct/100.0);
   double proximityLevel=targetLevel*(1.0-cfg.target_proximity_pct/100.0);
   if(equity>=proximityLevel)
      return base_risk_pct*0.5;
   return base_risk_pct;
  }

double PropGuardBaseRiskPctForPhase(const int phase,const PropGuardConfig &cfg)
  {
   return (phase==PROPGUARD_PHASE_FUNDED) ? cfg.funded_base_risk_pct : cfg.challenge_base_risk_pct;
  }

double PropGuardPhaseTargetPct(const int phase,const PropGuardConfig &cfg)
  {
   return (phase==PROPGUARD_PHASE_CHALLENGE_P2) ? cfg.phase2_target_pct : cfg.phase1_target_pct;
  }

//--- True once equity reaches the active phase's target. FUNDED has no further target (a
//--- funded account does not "graduate" out of PropGuard's rule engine).
bool PropGuardPhaseTargetReached(const double equity,const double initialBalance,
                                  const int phase,const PropGuardConfig &cfg)
  {
   if(phase==PROPGUARD_PHASE_FUNDED)
      return false;
   double targetLevel=initialBalance*(1.0+PropGuardPhaseTargetPct(phase,cfg)/100.0);
   return equity>=targetLevel;
  }

//+------------------------------------------------------------------+
//| Concurrency                                                       |
//+------------------------------------------------------------------+

int PropGuardOpenPositionCount(const string symbol,const long magic)
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
      count++;
     }
   return count;
  }

bool PropGuardMaxOpenTradesOk(const string symbol,const long magic,const PropGuardConfig &cfg)
  {
   return PropGuardOpenPositionCount(symbol,magic)<cfg.max_open_trades;
  }

//+------------------------------------------------------------------+
//| Aggregate account-level monitor -- everything that does NOT need  |
//| a proposed order's spread/stop (that lives in Filters.mqh, which  |
//| composes this with PropGuardCostGateOk / PropGuardProjectionGuardOk|
//| for the order-specific PreTrade check).                           |
//+------------------------------------------------------------------+

PropGuardResult PropGuardAccountMonitor(const string symbol,const datetime now,
                                         const double equity,const double initial_balance,
                                         const double equity_peak,const double day_baseline,
                                         const PropGuardConfig &cfg)
  {
   PropGuardResult r;
   r.allow=true;
   r.reason="ok";
   if(PropGuardMaxDdHalted(equity,initial_balance,equity_peak,cfg))
     { r.allow=false; r.reason="Max-drawdown internal halt reached"; return r; }
   if(PropGuardDailyHardFlatten(equity,day_baseline,cfg))
     { r.allow=false; r.reason="Daily hard-flatten floor reached"; return r; }
   if(PropGuardDailySoftHalted(equity,day_baseline,cfg))
     { r.allow=false; r.reason="Daily soft-halt floor reached"; return r; }
   if(PropGuardDailyProfitCapReached(equity,day_baseline,cfg))
     { r.allow=false; r.reason="Daily profit cap reached (give-back prevention)"; return r; }
   if(PropGuardIsWeekendFlattenTime(now,cfg))
     { r.allow=false; r.reason="Weekend flatten window"; return r; }
   if(PropGuardIsRolloverBlackout(now,cfg))
     { r.allow=false; r.reason="Rollover blackout window"; return r; }
   if(!PropGuardMaxOpenTradesOk(symbol,cfg.magic,cfg))
     { r.allow=false; r.reason="Max open trades reached"; return r; }
   return r;
  }

#endif
