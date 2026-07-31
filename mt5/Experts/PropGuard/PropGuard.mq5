#property strict
#property version   "1.00"
#property description "PropGuard -- XAUUSD prop-firm challenge EA"
#property description "London ORB + NY continuation, one position at a time, anti-ruin sizing"
#property description "See mt5/backtests/PROPGUARD_DESIGN.md for the frozen spec this implements"

#include <Trade/Trade.mqh>
#include <PropGuard/PropRules.mqh>
#include <PropGuard/Engines.mqh>
#include <PropGuard/Filters.mqh>
#include <PropGuard/Executor.mqh>
#include <PropGuard/Telemetry.mqh>

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+

//--- Identity
input string   InpSymbol                  = "XAUUSD";
input long     InpMagicNumber             = 27072601;
input double   InpMinLot                  = 0.01;
input double   InpMaxLot                  = 10.0;

//--- Firm contract (PROPGUARD_DESIGN.md §1 -- FTMO 2-Step defaults)
input double   InpFirmDailyLossPct        = 5.0;
input double   InpFirmMaxDdPct            = 10.0;
input bool     InpFirmDdIsTrailing        = false;
input double   InpPhase1TargetPct         = 10.0;
input double   InpPhase2TargetPct         = 5.0;

//--- Internal thresholds, always strictly tighter than the firm's (design §3)
input double   InpDailySoftHaltPct        = 2.0;
input double   InpDailyHardFlattenPct     = 2.5;
input double   InpDdHardHaltPct           = 8.0;
input double   InpDailyProfitCapPct       = 2.5;
input double   InpTargetProximityPct      = 1.5;
input double   InpCostGateMaxPct          = 8.0;
input int      InpDailyResetServerHour    = 0;
input int      InpFridayCloseHour         = 20;
input int      InpRolloverBlockStartHour  = 21;
input int      InpRolloverBlockEndHour    = 23;

//--- Risk (anti-ruin invariant, RiskBudget.mqh)
input double   InpChallengeBaseRiskPct    = 1.00;
input double   InpFundedBaseRiskPct       = 0.50;
input int      InpDailyRiskDivisor        = 3;
input int      InpTotalRiskDivisor        = 8;
input int      InpMaxOpenTrades           = 1;

//--- The 8 frozen search parameters (design §2) -- shared geometry
input int      InpAsianStartHour          = 0;     // #1
input int      InpAsianEndHour            = 7;     // #2 (also London range-end / entry-window start)
input double   InpBreakoutBufferAtr       = 0.25;  // #3
input double   InpStopAtrMult             = 1.0;   // #4
input double   InpTargetR                 = 1.5;   // #5
input double   InpVolBandLow              = 0.5;   // #6
input double   InpVolBandHigh             = 1.5;   // #6
input int      InpNyRangeStartHour        = 12;    // #7
input double   InpNyEntryWindowHours      = 4.0;   // #8

//--- Rules, not swept (design §3)
input int      InpAtrPeriod               = 14;
input int      InpVolLookbackDays         = 20;
input int      InpLondonEndHour           = 13;
input double   InpNyRangeHours            = 3.0;   // NY range duration -- fixed, not swept
input int      InpNyFlatHour              = 20;    // force-close time for open NY positions
input bool     InpEnableNewsFilter        = true;
input int      InpNewsBlackoutMinutes     = 5;
input string   InpHighImpactNewsTimes     = "";
input double   InpCommissionPerLotUsd     = 7.0;
input double   InpSwapEstimatePerLotUsd   = 0.0;
input double   InpStressExtraSpreadPrice  = 0.0;   // backtest-only cost stress, PROPGUARD_DESIGN.md §6

//--- Diagnostics
input bool     InpResetJournalOnInit      = true;
input bool     InpShowDashboard           = true;
input int      InpForceStartPhase         = 0;     // 0=CHALLENGE_P1 1=CHALLENGE_P2 2=FUNDED -- isolates one phase for testing

//+------------------------------------------------------------------+
//| Globals                                                            |
//+------------------------------------------------------------------+
CTrade   g_trade;
int      g_atrHandle=INVALID_HANDLE;
datetime g_lastM15Bar=0;

string PropGuardSymbol() { return (InpSymbol=="") ? _Symbol : InpSymbol; }

PropGuardConfig PropGuardBuildConfig()
  {
   PropGuardConfig c;
   c.magic=InpMagicNumber;
   c.firm_daily_loss_pct=InpFirmDailyLossPct;
   c.firm_max_dd_pct=InpFirmMaxDdPct;
   c.firm_dd_is_trailing=InpFirmDdIsTrailing;
   c.phase1_target_pct=InpPhase1TargetPct;
   c.phase2_target_pct=InpPhase2TargetPct;
   c.daily_soft_halt_pct=InpDailySoftHaltPct;
   c.daily_hard_flatten_pct=InpDailyHardFlattenPct;
   c.dd_hard_halt_pct=InpDdHardHaltPct;
   c.daily_profit_cap_pct=InpDailyProfitCapPct;
   c.target_proximity_pct=InpTargetProximityPct;
   c.cost_gate_max_pct=InpCostGateMaxPct;
   c.daily_reset_server_hour=InpDailyResetServerHour;
   c.friday_close_hour=InpFridayCloseHour;
   c.rollover_block_start_hour=InpRolloverBlockStartHour;
   c.rollover_block_end_hour=InpRolloverBlockEndHour;
   c.challenge_base_risk_pct=InpChallengeBaseRiskPct;
   c.funded_base_risk_pct=InpFundedBaseRiskPct;
   c.daily_risk_divisor=InpDailyRiskDivisor;
   c.total_risk_divisor=InpTotalRiskDivisor;
   c.max_open_trades=InpMaxOpenTrades;
   return c;
  }

//--- Per-position bookkeeping needed to compute an R-multiple at close time.
string PropGuardPosRiskKey(const ulong ticket)   { return StringFormat("PropGuard.%I64d.pos.%I64u.riskCash",InpMagicNumber,ticket); }
string PropGuardPosEngineKey(const ulong ticket) { return StringFormat("PropGuard.%I64d.pos.%I64u.engine",InpMagicNumber,ticket); }

void PropGuardStorePositionMeta(const ulong ticket,const double riskCash,const string engine)
  {
   GlobalVariableSet(PropGuardPosRiskKey(ticket),riskCash);
   GlobalVariableSet(PropGuardPosEngineKey(ticket),(engine=="london" ? 1.0 : 2.0));
  }

double PropGuardReadPositionRisk(const ulong ticket)
  {
   string key=PropGuardPosRiskKey(ticket);
   return GlobalVariableCheck(key) ? GlobalVariableGet(key) : 0.0;
  }

string PropGuardReadPositionEngine(const ulong ticket)
  {
   string key=PropGuardPosEngineKey(ticket);
   if(!GlobalVariableCheck(key)) return "unknown";
   return (GlobalVariableGet(key)>1.5) ? "ny" : "london";
  }

void PropGuardClearPositionMeta(const ulong ticket)
  {
   string k1=PropGuardPosRiskKey(ticket), k2=PropGuardPosEngineKey(ticket);
   if(GlobalVariableCheck(k1)) GlobalVariableDel(k1);
   if(GlobalVariableCheck(k2)) GlobalVariableDel(k2);
  }

//+------------------------------------------------------------------+
//| Attempt to place one engine's signal, subject to every gate.      |
//+------------------------------------------------------------------+
void PropGuardTryEngine(const string enginePrefix,const PropGuardEngineSignal &sig,
                         const int flattenHour,const PropGuardConfig &cfg,
                         const int phase,const double basePct,
                         const double equity,const double initialBalance,
                         const double equityPeak,const double dayBaseline,
                         const datetime now)
  {
   if(!sig.has_signal)
     {
      if(sig.reason!="already_traded_today" && sig.reason!="outside_entry_window" && sig.reason!="no_breakout")
         PropGuardLogRejection(enginePrefix,sig.reason);
      return;
     }

   string symbol=PropGuardSymbol();
   double throttledPct=PropGuardThrottledRiskPct(equity,initialBalance,
                        PropGuardPhaseTargetPct(phase,cfg),basePct,cfg);
   double dailyFloor=PropGuardDailyHardFloor(dayBaseline,cfg);
   double hardFloor=PropGuardMaxDdFloor(initialBalance,equityPeak,cfg);
   double riskCash=PropGuardRiskCash(equity,throttledPct,dailyFloor,hardFloor,
                                      cfg.daily_risk_divisor,cfg.total_risk_divisor);

   string clampBound="base";
   double byBase=equity*throttledPct/100.0;
   double byDaily=(equity-dailyFloor)/MathMax(cfg.daily_risk_divisor,1);
   double byTotal=(equity-hardFloor)/MathMax(cfg.total_risk_divisor,1);
   if(byTotal<=byDaily && byTotal<=byBase) clampBound="total";
   else if(byDaily<=byBase) clampBound="daily";

   double lots=PropGuardCalculateLot(symbol,sig.entry_ref,sig.sl,riskCash,InpMinLot,InpMaxLot);
   if(lots<=0.0)
     {
      PropGuardLogRejection(enginePrefix,"lot size resolved to zero");
      return;
     }

   double tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
   double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   //--- Backtest-only cost stress (PROPGUARD_DESIGN.md §6): widens the spread used by the
   //--- cost gate and projection guard, never the live order price. Real spread cannot be
   //--- overridden from the headless tester .ini under the real-tick model, so stress is
   //--- applied EA-side, mirroring GoldBot's InpStressExtraSpreadPrice mechanism.
   double spreadPrice=(SymbolInfoDouble(symbol,SYMBOL_ASK)-SymbolInfoDouble(symbol,SYMBOL_BID))+
                       MathMax(0.0,InpStressExtraSpreadPrice);
   double commissionPrice=(tickValue>0.0) ? InpCommissionPerLotUsd*tickSize/tickValue : 0.0;
   double spreadCash=(tickSize>0.0) ? spreadPrice*lots*tickValue/tickSize : 0.0;
   double commissionCash=InpCommissionPerLotUsd*lots;
   double swapEstimateCash=InpSwapEstimatePerLotUsd*lots;
   double currentFloatingLoss=MathMax(0.0,-AccountInfoDouble(ACCOUNT_PROFIT));

   PropGuardResult gate=PropGuardPreTradeOk(symbol,now,equity,initialBalance,equityPeak,dayBaseline,cfg,
                                             sig.stop_distance,spreadPrice,commissionPrice,
                                             riskCash,spreadCash,commissionCash,swapEstimateCash,
                                             currentFloatingLoss,InpEnableNewsFilter ? InpHighImpactNewsTimes : "",
                                             InpNewsBlackoutMinutes);
   if(!gate.allow)
     {
      PropGuardLogRejection(enginePrefix,gate.reason);
      return;
     }

   ulong ticket=0;
   string sendReason="";
   string comment=StringFormat("PG_%s_%s",enginePrefix,(sig.direction==1?"L":"S"));
   bool ok=PropGuardSendMarketOrder(g_trade,symbol,InpMagicNumber,sig.direction,lots,
                                     sig.sl,sig.tp,comment,flattenHour,ticket,sendReason);
   if(!ok)
     {
      PropGuardLogRejection(enginePrefix,"order send failed: "+sendReason);
      return;
     }

   PropGuardStorePositionMeta(ticket,riskCash,enginePrefix);
   datetime dayStart=PropGuardDayStart(now,InpDailyResetServerHour);
   PropGuardMarkEngineTraded(InpMagicNumber,dayStart,enginePrefix);

   double costToStopPct=100.0*(spreadPrice+commissionPrice)/MathMax(sig.stop_distance,1e-9);
   double atrVal=MathAbs(sig.entry_ref-sig.sl)/MathMax(InpStopAtrMult,0.01);
   PropGuardJournalTrade(enginePrefix,sig.direction,sig.entry_ref,sig.sl,sig.tp,lots,riskCash,
                         clampBound,spreadPrice,costToStopPct,atrVal,sig.range_width,sig.vol_ratio,
                         phase,ticket,"open",sendReason,0.0,0.0);
  }

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   string symbol=PropGuardSymbol();
   if(!SymbolSelect(symbol,true))
     {
      Print("PropGuard: unable to select symbol ",symbol);
      return INIT_FAILED;
     }

   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_atrHandle=iATR(symbol,PERIOD_M15,InpAtrPeriod);
   if(g_atrHandle==INVALID_HANDLE)
     {
      Print("PropGuard: failed to create ATR handle");
      return INIT_FAILED;
     }

   if(InpResetJournalOnInit)
     {
      PropGuardResetJournal();
      PropGuardResetRejectionLog();
      PropGuardResetStateLog();
     }

   PropGuardInitialBalance(InpMagicNumber);
   PropGuardEquityPeak(InpMagicNumber,AccountInfoDouble(ACCOUNT_EQUITY),true);
   if((bool)MQLInfoInteger(MQL_TESTER) && InpForceStartPhase>=0 && InpForceStartPhase<=2)
      PropGuardSetPhase(InpMagicNumber,InpForceStartPhase);
   else
      PropGuardGetPhase(InpMagicNumber);

   PrintFormat("PropGuard initialized symbol=%s magic=%I64d initialBalance=%.2f",
               symbol,InpMagicNumber,PropGuardInitialBalance(InpMagicNumber));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrHandle!=INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   Comment("");
   PrintFormat("PropGuard deinitialized. Reason=%d",reason);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
  {
   string symbol=PropGuardSymbol();
   datetime now=TimeCurrent();
   PropGuardConfig cfg=PropGuardBuildConfig();

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   double initialBalance=PropGuardInitialBalance(InpMagicNumber);
   double equityPeak=PropGuardEquityPeak(InpMagicNumber,equity,false);
   int phase=PropGuardGetPhase(InpMagicNumber);
   datetime dayStart=PropGuardDayStart(now,InpDailyResetServerHour);
   double dayBaseline=PropGuardDayBaseline(symbol,InpMagicNumber,dayStart);

   //--- Phase transition: the firm issues a new account/login at each phase boundary, so a
   //--- transition re-anchors initial balance and equity peak to "now" -- everything
   //--- downstream this tick (floors, risk sizing) must see the NEW phase, not the old one.
   if(PropGuardPhaseTargetReached(equity,initialBalance,phase,cfg))
     {
      int newPhase=PropGuardNextPhase(phase);
      PropGuardSetPhase(InpMagicNumber,newPhase);
      PropGuardResetInitialBalanceTo(InpMagicNumber,equity);
      PropGuardResetEquityPeakTo(InpMagicNumber,equity);
      PrintFormat("PropGuard: PHASE TRANSITION %s -> %s at equity=%.2f",
                  PropGuardPhaseToString(phase),PropGuardPhaseToString(newPhase),equity);
      phase=newPhase;
      initialBalance=equity;
      equityPeak=equity;
     }

   //--- Every-tick emergency checks: these force-close regardless of bar timing, because
   //--- equity can move between M15 bars and a forced flatten must not wait for one.
   bool ddHalted=PropGuardMaxDdHalted(equity,initialBalance,equityPeak,cfg);
   bool dailyHardFlatten=PropGuardDailyHardFlatten(equity,dayBaseline,cfg);
   bool weekend=PropGuardIsWeekendFlattenTime(now,cfg);

   string forceReason="";
   if(ddHalted) forceReason="max_dd_halt";
   else if(dailyHardFlatten) forceReason="daily_hard_flatten";
   // weekend is handled inside PropGuardManagePositions itself (its own branch), so it is
   // deliberately not added to forceReason here -- passing it would also mislabel
   // session-end-only closes on a weekday as "weekend_flatten".

   int closed=PropGuardManagePositions(g_trade,symbol,InpMagicNumber,now,cfg,forceReason);
   if(closed>0 && forceReason!="")
      PrintFormat("PropGuard: forced flatten x%d reason=%s",closed,forceReason);

   if(InpShowDashboard)
     {
      int tradesToday=(PropGuardEngineAlreadyTraded(InpMagicNumber,dayStart,"london")?1:0)+
                       (PropGuardEngineAlreadyTraded(InpMagicNumber,dayStart,"ny")?1:0);
      datetime nextReset=dayStart+86400;
      PropGuardUpdateDashboard(phase,equity,balance,dayBaseline,cfg,equityPeak,initialBalance,
                                tradesToday,nextReset);
     }

   //--- Signal generation only on a new closed M15 bar.
   datetime curBar=iTime(symbol,PERIOD_M15,0);
   if(curBar==0 || curBar==g_lastM15Bar)
      return;
   g_lastM15Bar=curBar;

   if(ddHalted || dailyHardFlatten || weekend)
      return; // account-level halt already blocks entries via PropGuardAccountMonitor too;
              // skip signal evaluation outright to avoid pointless work every bar.

   double basePct=PropGuardBaseRiskPctForPhase(phase,cfg);

   PropGuardEngineSignal sigA=PropGuardEngineALondonSignal(symbol,PERIOD_M15,InpMagicNumber,
                               InpAsianStartHour,InpAsianEndHour,InpLondonEndHour,
                               InpBreakoutBufferAtr,InpStopAtrMult,InpTargetR,
                               InpVolBandLow,InpVolBandHigh,InpVolLookbackDays,
                               g_atrHandle,dayStart);
   PropGuardTryEngine("london",sigA,InpLondonEndHour,cfg,phase,basePct,
                       equity,initialBalance,equityPeak,dayBaseline,now);

   PropGuardEngineSignal sigB=PropGuardEngineBNySignal(symbol,PERIOD_M15,InpMagicNumber,
                               InpNyRangeStartHour,InpNyRangeHours,InpNyEntryWindowHours,
                               InpBreakoutBufferAtr,InpStopAtrMult,InpTargetR,
                               InpVolBandLow,InpVolBandHigh,InpVolLookbackDays,
                               g_atrHandle,dayStart);
   PropGuardTryEngine("ny",sigB,InpNyFlatHour,cfg,phase,basePct,
                       equity,initialBalance,equityPeak,dayBaseline,now);

   PropGuardLogState(phase,equity,balance,dayBaseline,
                      PropGuardDailySoftFloor(dayBaseline,cfg),PropGuardDailyHardFloor(dayBaseline,cfg),
                      equityPeak,PropGuardMaxDdFloor(initialBalance,equityPeak,cfg),
                      (ddHalted||dailyHardFlatten),(ddHalted?"max_dd_halt":(dailyHardFlatten?"daily_hard_flatten":"")));
  }

//+------------------------------------------------------------------+
//| Trade transaction handler -- journals closes and computes R.      |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   string symbol=HistoryDealGetString(trans.deal,DEAL_SYMBOL);
   long magic=HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
   if(symbol!=PropGuardSymbol() || magic!=InpMagicNumber)
      return;

   long dealEntry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(dealEntry!=DEAL_ENTRY_OUT && dealEntry!=DEAL_ENTRY_OUT_BY)
      return;

   ulong positionId=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   double profit=HistoryDealGetDouble(trans.deal,DEAL_PROFIT)+
                 HistoryDealGetDouble(trans.deal,DEAL_SWAP)+
                 HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
   double closePrice=HistoryDealGetDouble(trans.deal,DEAL_PRICE);
   double riskCash=PropGuardReadPositionRisk(positionId);
   string engine=PropGuardReadPositionEngine(positionId);
   double rMultiple=(riskCash>0.0) ? profit/riskCash : 0.0;
   int phase=PropGuardGetPhase(InpMagicNumber);

   PropGuardJournalTrade(engine,0,0.0,0.0,0.0,0.0,riskCash,"",0.0,0.0,0.0,0.0,0.0,
                         phase,positionId,"close",StringFormat("profit=%.2f",profit),
                         closePrice,rMultiple);

   PropGuardClearPositionMeta(positionId);
   PropGuardClearPositionState(InpMagicNumber,positionId);
  }
