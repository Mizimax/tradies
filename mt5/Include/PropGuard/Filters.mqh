#ifndef PROPGUARD_FILTERS_MQH
#define PROPGUARD_FILTERS_MQH

#include "PropRules.mqh"
#include <GoldScalper/NewsFilter.mqh>

//+------------------------------------------------------------------+
//| Filters.mqh -- news / weekend / rollover / cost / projection      |
//| gates, composed into one PreTrade decision. Session-hour and      |
//| volatility-band checks live in Engines.mqh (they gate SIGNAL      |
//| GENERATION, not order placement); this file gates PLACEMENT of    |
//| an already-generated signal.                                      |
//+------------------------------------------------------------------+

//--- Thin wrapper so PropGuard's naming stays self-contained even though the underlying
//--- parser is reused verbatim from GoldScalper/NewsFilter.mqh (see PROPGUARD_DESIGN.md
//--- "modules to reuse").
bool PropGuardNewsGateOk(const string newsTimes,const int blackoutMinutes,string &matchedEvent)
  {
   return !GoldScalperNewsBlocked(newsTimes,blackoutMinutes,matchedEvent);
  }

//--- Everything needed to decide whether an already-generated PropGuardEngineSignal may be
//--- sent as a live order. Composes the account-wide monitor (PropRules) with the
//--- order-specific cost gate and predictive projection guard.
PropGuardResult PropGuardPreTradeOk(const string symbol,const datetime now,
                                     const double equity,const double initialBalance,
                                     const double equityPeak,const double dayBaseline,
                                     const PropGuardConfig &cfg,
                                     const double stopDistancePrice,
                                     const double spreadPrice,const double commissionPrice,
                                     const double riskCash,const double spreadCash,
                                     const double commissionCash,const double swapEstimateCash,
                                     const double currentFloatingLoss,
                                     const string newsTimes,const int newsBlackoutMinutes)
  {
   PropGuardResult r=PropGuardAccountMonitor(symbol,now,equity,initialBalance,equityPeak,dayBaseline,cfg);
   if(!r.allow)
      return r;

   string matchedEvent="";
   if(!PropGuardNewsGateOk(newsTimes,newsBlackoutMinutes,matchedEvent))
     { r.allow=false; r.reason="News blackout: "+matchedEvent; return r; }

   if(!PropGuardCostGateOk(spreadPrice,commissionPrice,stopDistancePrice,cfg))
     { r.allow=false; r.reason="Cost gate: (spread+commission)/stop exceeds cap"; return r; }

   double dailyFloor=PropGuardDailyHardFloor(dayBaseline,cfg);
   double hardFloor=PropGuardMaxDdFloor(initialBalance,equityPeak,cfg);
   if(!PropGuardProjectionGuardOk(equity,riskCash,spreadCash,commissionCash,swapEstimateCash,
                                  currentFloatingLoss,dailyFloor,hardFloor))
     { r.allow=false; r.reason="Projection guard: worst-case breaches a floor"; return r; }

   if(riskCash<=0.0)
     { r.allow=false; r.reason="Anti-ruin risk budget clamped to zero"; return r; }

   r.allow=true;
   r.reason="ok";
   return r;
  }

#endif
