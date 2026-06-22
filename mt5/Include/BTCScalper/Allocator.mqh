#ifndef BTCSCALPER_ALLOCATOR_MQH
#define BTCSCALPER_ALLOCATOR_MQH

//+------------------------------------------------------------------+
//| Allocator.mqh — performance-feedback strategy allocation         |
//| Part of BTCScalper EA                                            |
//|                                                                  |
//| Tracks each strategy's recent closed-trade outcomes in an        |
//| in-memory rolling window and maps the rolling profit factor to   |
//| a per-strategy risk multiplier (probation / normal / boost).     |
//| The Strategy Tester zero-inits these statics each pass, so the   |
//| rings reset cleanly per backtest run.                            |
//+------------------------------------------------------------------+

#include <BTCScalper/SessionTime.mqh>
#include <BTCScalper/RiskManager.mqh>

//--- Strategy identity (index into the perf store)
enum BTCStrategyId
{
   BTC_STRAT_MR    = 0,   // mean_reversion
   BTC_STRAT_VWAP  = 1,   // vwap_reversion
   BTC_STRAT_MOM   = 2,   // momentum
   BTC_STRAT_COUNT = 3    // sentinel / unknown
};

#define BTC_PERF_MAX_WINDOW 100   // storage ceiling for the ring buffer

//--- Rolling window of the last-N closed trades for one strategy
struct BTCPerfRing
{
   double  profit[BTC_PERF_MAX_WINDOW];   // signed net per closed trade
   bool    win[BTC_PERF_MAX_WINDOW];      // profit > 0
   int     head;                          // next write index
   int     size;                          // valid entries (<= capacity)
};

//--- Aggregated metrics over the window
struct BTCPerfMetrics
{
   int     n;             // sample count in window
   int     wins;
   double  winRate;       // wins / n  (0..1)
   double  grossProfit;
   double  grossLoss;     // positive magnitude
   double  profitFactor;  // gp/gl; DBL_MAX if gl==0 and gp>0; 0 if empty
   double  netPnl;
};

//--- Primary store (global -> zero-initialized each tester pass)
BTCPerfRing g_btcPerf[BTC_STRAT_COUNT];

//+------------------------------------------------------------------+
//| Clear all rings (call from OnInit)                               |
//+------------------------------------------------------------------+
void BTCScalperPerfReset()
{
   for(int s = 0; s < BTC_STRAT_COUNT; s++)
   {
      g_btcPerf[s].head = 0;
      g_btcPerf[s].size = 0;
      ArrayInitialize(g_btcPerf[s].profit, 0.0);
      for(int i = 0; i < BTC_PERF_MAX_WINDOW; i++)
         g_btcPerf[s].win[i] = false;
   }
}

//+------------------------------------------------------------------+
//| Map the comment-derived strategy name to a strategy id           |
//| (names match those already computed in OnTradeTransaction)       |
//+------------------------------------------------------------------+
BTCStrategyId BTCScalperStrategyIdFromName(const string name)
{
   if(name == "mean_reversion") return BTC_STRAT_MR;
   if(name == "vwap_reversion") return BTC_STRAT_VWAP;
   if(name == "momentum")       return BTC_STRAT_MOM;
   return BTC_STRAT_COUNT;   // unknown -> not recorded
}

//+------------------------------------------------------------------+
//| Push one closed-trade outcome into a strategy's ring             |
//+------------------------------------------------------------------+
void BTCScalperPerfRecord(const BTCStrategyId sid, const double profit, const int window)
{
   if(sid < 0 || sid >= BTC_STRAT_COUNT)
      return;

   int cap = (window > 0 && window < BTC_PERF_MAX_WINDOW) ? window : BTC_PERF_MAX_WINDOW;

   g_btcPerf[sid].profit[g_btcPerf[sid].head] = profit;
   g_btcPerf[sid].win[g_btcPerf[sid].head]    = (profit > 0.0);
   g_btcPerf[sid].head = (g_btcPerf[sid].head + 1) % cap;
   if(g_btcPerf[sid].size < cap)
      g_btcPerf[sid].size++;
}

//+------------------------------------------------------------------+
//| Compute rolling metrics for one strategy                         |
//+------------------------------------------------------------------+
BTCPerfMetrics BTCScalperPerfMetrics(const BTCStrategyId sid)
{
   BTCPerfMetrics m;
   m.n = 0; m.wins = 0; m.winRate = 0.0;
   m.grossProfit = 0.0; m.grossLoss = 0.0; m.profitFactor = 0.0; m.netPnl = 0.0;
   if(sid < 0 || sid >= BTC_STRAT_COUNT)
      return m;

   int sz = g_btcPerf[sid].size;
   for(int i = 0; i < sz; i++)
   {
      double p = g_btcPerf[sid].profit[i];   // aggregate order is irrelevant
      m.netPnl += p;
      if(p > 0.0) { m.grossProfit += p; m.wins++; }
      else        { m.grossLoss  += -p; }
   }
   m.n = sz;
   if(sz > 0)
      m.winRate = (double)m.wins / (double)sz;
   if(m.grossLoss > 0.0)
      m.profitFactor = m.grossProfit / m.grossLoss;
   else if(m.grossProfit > 0.0)
      m.profitFactor = DBL_MAX;   // wins, no losses yet
   else
      m.profitFactor = 0.0;       // empty / flat
   return m;
}

//+------------------------------------------------------------------+
//| Map recent performance to a risk multiplier (discrete tiers)     |
//|   warmup (n<minSample) -> 1.0 (baseline behavior)                |
//|   probation (PF<pfFloor) -> probationMult                        |
//|   boost (PF>=pfBoost)    -> boostMult                            |
//|   normal                -> 1.0                                   |
//+------------------------------------------------------------------+
double BTCScalperAllocMultiplier(const BTCStrategyId sid,
                                 const int    minSample,
                                 const double pfFloor,
                                 const double pfBoost,
                                 const double probationMult,
                                 const double boostMult)
{
   BTCPerfMetrics m = BTCScalperPerfMetrics(sid);

   if(m.n < minSample)
      return 1.0;                 // warmup: act like the baseline

   if(m.profitFactor < pfFloor)
      return probationMult;       // recent edge is bad -> shrink/disable

   if(m.profitFactor >= pfBoost)
      return boostMult;           // strong recent edge -> optional boost

   return 1.0;                    // normal tier
}

//+------------------------------------------------------------------+
//| Daily "parole": let one signal/day through for a probation       |
//| strategy so its window can refill and recover.                   |
//| Uses the day-keyed GlobalVariable pattern from RiskManager.      |
//+------------------------------------------------------------------+
string BTCScalperParoleKey(const BTCStrategyId sid)
{
   return BTCScalperDayKey(StringFormat("parole_%d", (int)sid));
}

bool BTCScalperPerfParoleAvailable(const BTCStrategyId sid)
{
   string key = BTCScalperParoleKey(sid);
   if(!GlobalVariableCheck(key))
      return true;
   return ((int)GlobalVariableGet(key) < 1);
}

void BTCScalperPerfParoleConsume(const BTCStrategyId sid)
{
   string key = BTCScalperParoleKey(sid);
   int current = GlobalVariableCheck(key) ? (int)GlobalVariableGet(key) : 0;
   GlobalVariableSet(key, (double)(current + 1));
}

#endif
