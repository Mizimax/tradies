#ifndef GOLDBOT_PROPMODE_MQH
#define GOLDBOT_PROPMODE_MQH

//+------------------------------------------------------------------+
//| PropMode.mqh -- opt-in prop-firm compliance/risk-guard layer for  |
//| GoldBot. Ported (not reinvented) from the proven PropGuard rule   |
//| engine: mt5/Include/PropGuard/PropRules.mqh + RiskBudget.mqh,     |
//| verified by tests/test_propguard_rules.py. See design doc         |
//| mt5/backtests/PROPGUARD_DESIGN.md for the frozen rule list and    |
//| mt5/backtests/PROPGUARD_GOLDBOT_SIM.md for the go/no-go sizing    |
//| study this feature is built on.                                   |
//|                                                                    |
//| Every function here is inert unless the caller passes a           |
//| GoldBotPropConfig with enabled=true (wired from InpEnablePropMode |
//| in GoldBot.mq5). Nothing in this file is called when prop mode    |
//| is off, so the non-prop code path is byte-for-byte unchanged.     |
//|                                                                    |
//| Deviation from PropGuard flagged here rather than silently copied:|
//| PropGuardInitialBalance/PropGuardEquityPeak (PropRules.mqh) reset  |
//| their GlobalVariable to the CURRENT balance/equity on every single|
//| call when MQL_TESTER is true -- and PropGuard.mq5 calls           |
//| PropGuardInitialBalance() again every OnTick (not just OnInit).   |
//| That means "initial balance" would keep re-anchoring to whatever  |
//| the balance is right now after every closed trade within one      |
//| tester run, which would defeat a STATIC max-DD floor. The doc      |
//| comment's stated intent ("tester runs always start clean... live  |
//| resumes the persisted peak") only requires a reset ONCE at the    |
//| start of a run, not on every call. GoldBotPropInitialBalance/      |
//| GoldBotPropEquityPeak below implement that documented intent      |
//| literally: reset exactly once, from GoldBot.mq5 OnInit, guarded   |
//| by a tester-mode GlobalVariableDel; every other call is a pure    |
//| read-or-seed-once (initial balance) / pure upward ratchet (peak). |
//| PropGuard.mq5 itself was NOT touched -- out of scope here -- but  |
//| this is flagged for the orchestrator to double-check separately.  |
//+------------------------------------------------------------------+

struct GoldBotPropConfig
{
   bool   enabled;
   //--- Firm contract (published rules)
   double firmDailyLossPct;
   double firmMaxDrawdownPct;
   bool   ddIsTrailing;          // false = static floor off initial balance (FTMO 2-Step default)
   double phaseTargetPct;        // active challenge phase's profit target, e.g. 10.0 for FTMO P1
   //--- Internal thresholds, always strictly tighter than the firm's
   double dailySoftHaltPct;
   double dailyHardFlattenPct;
   double ddHardHaltPct;         // % of firm's max-DD budget consumed before internal halt
   double dailyProfitCapPct;
   double targetProximityPct;
   double targetLockBufferPct;  // extra equity above target reserved for close costs/slippage
   double costGateMaxPct;        // (spread+commission)/stopDistance cap, percent
   //--- Anti-ruin sizing
   double challengeRiskPct;      // base risk % of equity per trade
   int    dailyRiskDivisor;
   int    totalRiskDivisor;
   //--- Calendar / session
   int    dailyResetServerHour;
   int    fridayCloseHour;
   int    rolloverBlockStartHour;
   int    rolloverBlockEndHour;
   //--- Concurrency / spread
   int    maxOpenAndPending;     // pending-inclusive concurrency cap
   double maxSpreadPriceM15;     // 0 = no cap
   double maxSpreadPriceM5;      // 0 = defer to InpScalpMaxSpreadPrice unchanged
   double maxSpreadPriceM1;      // 0 = defer to InpM1MicroMaxSpreadPrice unchanged
   bool   forceNewsFilter;
   //--- Cost estimation
   double commissionPerLotUsd;
   double swapEstimatePerLotUsd;
};

// Tester-chain persistence is deliberately separate from the normal prop
// accessors.  Ordinary tester, demo, and live runs never call these helpers.
struct GoldBotPropTesterChainState
{
   double   originalChallengeBalance;
   double   endingBalance;
   double   endingEquity;
   double   nextStartBalance;
   double   equityPeak;
   bool     phaseTargetCompleted;
   datetime segmentEndTimestamp;
};

// Process-local immutable seed for the active tester segment.  Terminal
// GlobalVariables remain the normal storage used by the prop engine, while
// this explicit chain seed prevents any later read-or-seed call from silently
// re-anchoring the challenge to the carried tester deposit.
bool   gGoldBotPropTesterChainSeedActive = false;
long   gGoldBotPropTesterChainSeedMagic = 0;
double gGoldBotPropTesterChainOriginalBalance = 0.0;

void GoldBotPropSeedTesterChainInitialBalance(const long magic, const double originalBalance)
{
   gGoldBotPropTesterChainSeedActive = true;
   gGoldBotPropTesterChainSeedMagic = magic;
   gGoldBotPropTesterChainOriginalBalance = originalBalance;
   GlobalVariableSet(GoldBotPropKey(magic, "initialBalance"), originalBalance);
}

void GoldBotPropClearTesterChainInitialBalanceSeed()
{
   gGoldBotPropTesterChainSeedActive = false;
   gGoldBotPropTesterChainSeedMagic = 0;
   gGoldBotPropTesterChainOriginalBalance = 0.0;
}

//+------------------------------------------------------------------+
//| GlobalVariable keys -- magic-scoped, distinct namespace from both |
//| GoldBot's own non-magic-scoped daily key (Risk.mqh GoldBotDayKey, |
//| a documented cross-instance bug, deliberately not reused) and     |
//| PropGuard's own PropGuard.%magic%.suffix keys (different EA).     |
//+------------------------------------------------------------------+

string GoldBotPropKey(const long magic, const string suffix)
{
   return StringFormat("GoldBotProp_%s_%I64d", suffix, magic);
}

//+------------------------------------------------------------------+
//| Day boundary in server time, offset by the configurable reset     |
//| hour. Ported verbatim from PropGuardDayStart (PropRules.mqh).     |
//+------------------------------------------------------------------+

datetime GoldBotPropDayStart(const datetime now, const int resetHour)
{
   MqlDateTime t;
   TimeToStruct(now, t);
   t.hour = 0; t.min = 0; t.sec = 0;
   datetime midnight = StructToTime(t);
   datetime candidate = midnight + resetHour * 3600;
   if(candidate > now)
      candidate -= 86400;
   return candidate;
}

//+------------------------------------------------------------------+
//| Initial balance: set once, never overwritten except by an         |
//| explicit tester-mode reset from GoldBot.mq5 OnInit. See the       |
//| file-header note above for why this differs from PropGuard's      |
//| literal per-call-reset-in-tester implementation.                  |
//+------------------------------------------------------------------+

double GoldBotPropInitialBalance(const long magic)
{
   string key = GoldBotPropKey(magic, "initialBalance");
   if(gGoldBotPropTesterChainSeedActive && gGoldBotPropTesterChainSeedMagic == magic &&
      gGoldBotPropTesterChainOriginalBalance > 0.0)
   {
      GlobalVariableSet(key, gGoldBotPropTesterChainOriginalBalance);
      return gGoldBotPropTesterChainOriginalBalance;
   }
   if(GlobalVariableCheck(key))
      return GlobalVariableGet(key);
   double b = AccountInfoDouble(ACCOUNT_BALANCE);
   GlobalVariableSet(key, b);
   return b;
}

//+------------------------------------------------------------------+
//| Equity peak: ratchets up only. Callers reset the underlying key   |
//| explicitly (GoldBot.mq5 OnInit, tester mode only) rather than      |
//| this function silently resetting on every call.                   |
//+------------------------------------------------------------------+

double GoldBotPropEquityPeak(const long magic, const double currentEquity)
{
   string key = GoldBotPropKey(magic, "equityPeak");
   double peak = currentEquity;
   if(GlobalVariableCheck(key))
      peak = MathMax(currentEquity, GlobalVariableGet(key));
   GlobalVariableSet(key, peak);
   return peak;
}

void GoldBotPropResetTesterAnchors(const long magic)
{
   GoldBotPropClearTesterChainInitialBalanceSeed();
   GlobalVariableDel(GoldBotPropKey(magic, "initialBalance"));
   GlobalVariableDel(GoldBotPropKey(magic, "equityPeak"));
   GlobalVariableDel(GoldBotPropKey(magic, "phaseTargetCompleted"));
}

// Return 0 when no seed exists (the first chain segment), 1 for a valid seed,
// and -1 for a present-but-invalid seed.  Unknown rows are allowed so GoldBot
// can append its non-prop governor state to the same versioned CSV.
int GoldBotPropLoadTesterChainState(const string fileName,
                                   const long magic,
                                   GoldBotPropTesterChainState &state,
                                   string &error)
{
   error = "";
   if(StringLen(fileName) <= 0)
   {
      error = "empty state filename";
      return -1;
   }
   ResetLastError();
   int handle = FileOpen(fileName, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
   {
      int openError = GetLastError();
      if(openError == 5004) // ERR_CANNOT_OPEN_FILE: normal only for chain segment 1
         return 0;
      error = StringFormat("cannot open state file error=%d", openError);
      return -1;
   }

   bool seenSchema = false, seenValid = false, seenFlat = false;
   bool seenOriginal = false, seenBalance = false, seenEquity = false;
   bool seenNextStart = false, seenPeak = false, seenCompleted = false, seenTimestamp = false;
   bool valid = false, flat = false;
   int schemaVersion = 0;
   while(!FileIsEnding(handle))
   {
      string key = FileReadString(handle);
      if(FileIsEnding(handle) && StringLen(key) <= 0)
         break;
      string value = FileReadString(handle);
      if(key == "schema_version") { schemaVersion = (int)StringToInteger(value); seenSchema = true; }
      else if(key == "valid") { valid = (value == "true" || value == "1"); seenValid = true; }
      else if(key == "flat") { flat = (value == "true" || value == "1"); seenFlat = true; }
      else if(key == "original_challenge_balance") { state.originalChallengeBalance = StringToDouble(value); seenOriginal = true; }
      else if(key == "ending_balance") { state.endingBalance = StringToDouble(value); seenBalance = true; }
      else if(key == "ending_equity") { state.endingEquity = StringToDouble(value); seenEquity = true; }
      else if(key == "next_start_balance") { state.nextStartBalance = StringToDouble(value); seenNextStart = true; }
      else if(key == "equity_peak") { state.equityPeak = StringToDouble(value); seenPeak = true; }
      else if(key == "phase_target_completed") { state.phaseTargetCompleted = (value == "true" || value == "1"); seenCompleted = true; }
      else if(key == "segment_end_timestamp") { state.segmentEndTimestamp = (datetime)StringToInteger(value); seenTimestamp = true; }
   }
   FileClose(handle);

   if(!seenSchema || schemaVersion != 1 || !seenValid || !seenFlat ||
      !seenOriginal || !seenBalance || !seenEquity || !seenNextStart || !seenPeak ||
      !seenCompleted || !seenTimestamp)
   {
      error = "missing or unsupported required state fields";
      return -1;
   }
   if(!valid || !flat)
   {
      error = "previous segment state is invalid or non-flat";
      return -1;
   }
   if(state.originalChallengeBalance <= 0.0 || state.endingBalance <= 0.0 ||
      state.endingEquity <= 0.0 || state.nextStartBalance <= 0.0 || state.equityPeak <= 0.0 ||
      state.segmentEndTimestamp <= 0)
   {
      error = "required state values are out of range";
      return -1;
   }
   if(MathAbs(AccountInfoDouble(ACCOUNT_BALANCE) - state.nextStartBalance) > 0.005)
   {
      error = StringFormat("deposit carry mismatch tester=%.2f expectedStart=%.2f previousEnd=%.2f",
         AccountInfoDouble(ACCOUNT_BALANCE), state.nextStartBalance, state.endingBalance);
      return -1;
   }

   GoldBotPropSeedTesterChainInitialBalance(magic, state.originalChallengeBalance);
   GlobalVariableSet(GoldBotPropKey(magic, "equityPeak"), state.equityPeak);
   GlobalVariableSet(GoldBotPropKey(magic, "phaseTargetCompleted"), state.phaseTargetCompleted ? 1.0 : 0.0);
   return 1;
}

bool GoldBotPropWriteTesterChainBase(const int handle,
                                    const long magic,
                                    const bool valid,
                                    const bool flat,
                                    const datetime segmentEndTimestamp)
{
   if(handle == INVALID_HANDLE)
      return false;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double originalBalance = GoldBotPropInitialBalance(magic);
   double peak = GoldBotPropEquityPeak(magic, equity);
   FileWrite(handle, "schema_version", "1");
   FileWrite(handle, "valid", valid ? "true" : "false");
   FileWrite(handle, "flat", flat ? "true" : "false");
   FileWrite(handle, "original_challenge_balance", DoubleToString(originalBalance, 2));
   FileWrite(handle, "ending_balance", DoubleToString(balance, 2));
   FileWrite(handle, "ending_equity", DoubleToString(equity, 2));
   // MT5's tester INI parser accepts only whole-dollar deposits.  Carry the
   // exact prior end for evidence and a separate explicit next-start value for
   // the runner/loader handshake; never silently compare rounded and exact cash.
   FileWrite(handle, "next_start_balance", DoubleToString(MathFloor(balance), 2));
   FileWrite(handle, "equity_peak", DoubleToString(peak, 2));
   FileWrite(handle, "phase_target_completed", GoldBotPropPhaseTargetCompleted(magic) ? "true" : "false");
   FileWrite(handle, "segment_end_timestamp", IntegerToString((long)segmentEndTimestamp));
   return true;
}

double GoldBotPropPhaseTargetLevel(const double initialBalance, const GoldBotPropConfig &cfg)
{
   return initialBalance * (1.0 + cfg.phaseTargetPct / 100.0);
}

double GoldBotPropPhaseTargetLockLevel(const double initialBalance, const GoldBotPropConfig &cfg)
{
   double bufferPct = MathMax(0.0, cfg.targetLockBufferPct);
   return initialBalance * (1.0 + (cfg.phaseTargetPct + bufferPct) / 100.0);
}

bool GoldBotPropPhaseTargetLockReached(const double equity, const double initialBalance, const GoldBotPropConfig &cfg)
{
   return cfg.enabled && cfg.phaseTargetPct > 0.0 && equity >= GoldBotPropPhaseTargetLockLevel(initialBalance, cfg);
}

bool GoldBotPropPhaseTargetCompleted(const long magic)
{
   string key = GoldBotPropKey(magic, "phaseTargetCompleted");
   return GlobalVariableCheck(key) && GlobalVariableGet(key) > 0.5;
}

void GoldBotPropSetPhaseTargetCompleted(const long magic)
{
   GlobalVariableSet(GoldBotPropKey(magic, "phaseTargetCompleted"), 1.0);
}

//+------------------------------------------------------------------+
//| Realized P/L accounting -- ported from PropGuardClosedProfitSince.|
//| Includes swap/commission/fee, not just raw profit (matches QBR    |
//| SafetyFocus.mqh convention referenced by PropRules.mqh).          |
//+------------------------------------------------------------------+

double GoldBotPropClosedProfitSince(const string symbol, const long magic, const datetime fromTime)
{
   if(!HistorySelect(fromTime, TimeCurrent()))
      return 0.0;
   double profit = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != symbol) continue;
      if((long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != magic) continue;
      long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) continue;
      profit += HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                HistoryDealGetDouble(ticket, DEAL_SWAP) +
                HistoryDealGetDouble(ticket, DEAL_COMMISSION) +
                HistoryDealGetDouble(ticket, DEAL_FEE);
   }
   return profit;
}

double GoldBotPropDayBaseline(const string symbol, const long magic, const datetime dayStart)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double closedToday = GoldBotPropClosedProfitSince(symbol, magic, dayStart);
   double baseline = balance - closedToday;
   return (baseline > 0.0 ? baseline : balance);
}

//+------------------------------------------------------------------+
//| Floors, thresholds -- ported verbatim from PropRules.mqh.         |
//+------------------------------------------------------------------+

double GoldBotPropDailySoftFloor(const double dayBaseline, const GoldBotPropConfig &cfg)
{
   return dayBaseline * (1.0 - cfg.dailySoftHaltPct / 100.0);
}

double GoldBotPropDailyHardFloor(const double dayBaseline, const GoldBotPropConfig &cfg)
{
   return dayBaseline * (1.0 - cfg.dailyHardFlattenPct / 100.0);
}

double GoldBotPropDailyProfitCap(const double dayBaseline, const GoldBotPropConfig &cfg)
{
   return dayBaseline * (1.0 + cfg.dailyProfitCapPct / 100.0);
}

//--- Static: fraction of initial balance (FTMO 2-Step default). Trailing: fraction of the
//--- ratcheting equity peak. Internal halt trips at ddHardHaltPct, strictly before the firm's
//--- full budget (firmMaxDrawdownPct).
double GoldBotPropMaxDdFloor(const double initialBalance, const double equityPeak, const GoldBotPropConfig &cfg)
{
   double keepPct = 100.0 - cfg.ddHardHaltPct;
   if(cfg.ddIsTrailing)
      return equityPeak * (keepPct / 100.0);
   return initialBalance * (keepPct / 100.0);
}

bool GoldBotPropDailySoftHalted(const double equity, const double dayBaseline, const GoldBotPropConfig &cfg)
{
   return equity <= GoldBotPropDailySoftFloor(dayBaseline, cfg);
}

bool GoldBotPropDailyHardFlatten(const double equity, const double dayBaseline, const GoldBotPropConfig &cfg)
{
   return equity <= GoldBotPropDailyHardFloor(dayBaseline, cfg);
}

bool GoldBotPropMaxDdHalted(const double equity, const double initialBalance, const double equityPeak, const GoldBotPropConfig &cfg)
{
   return equity <= GoldBotPropMaxDdFloor(initialBalance, equityPeak, cfg);
}

bool GoldBotPropDailyProfitCapReached(const double equity, const double dayBaseline, const GoldBotPropConfig &cfg)
{
   return equity >= GoldBotPropDailyProfitCap(dayBaseline, cfg);
}

//+------------------------------------------------------------------+
//| Session / calendar rules -- ported verbatim from PropRules.mqh.   |
//+------------------------------------------------------------------+

bool GoldBotPropIsWeekendFlattenTime(const datetime now, const GoldBotPropConfig &cfg)
{
   MqlDateTime t;
   TimeToStruct(now, t);
   if(t.day_of_week == 5 && t.hour >= cfg.fridayCloseHour) return true; // Friday, past close hour
   if(t.day_of_week == 6 || t.day_of_week == 0) return true;            // Saturday / Sunday
   return false;
}

bool GoldBotPropIsRolloverBlackout(const datetime now, const GoldBotPropConfig &cfg)
{
   MqlDateTime t;
   TimeToStruct(now, t);
   int h = t.hour;
   int s = cfg.rolloverBlockStartHour, e = cfg.rolloverBlockEndHour;
   if(s == e) return false;
   if(s < e) return (h >= s && h < e);
   return (h >= s || h < e); // overnight wrap
}

//+------------------------------------------------------------------+
//| Cost & predictive guards -- ported verbatim from PropRules.mqh.   |
//+------------------------------------------------------------------+

bool GoldBotPropCostGateOk(const double spreadPrice, const double commissionPrice,
                            const double stopDistance, const GoldBotPropConfig &cfg)
{
   if(stopDistance <= 0.0) return false;
   double costPct = 100.0 * (spreadPrice + commissionPrice) / stopDistance;
   return costPct <= cfg.costGateMaxPct;
}

//--- Predictive guard: rejects BEFORE a breach can happen. worstCase folds in the full
//--- stop-loss cash risk, round-trip cost, an estimated swap, and any already-open floating
//--- loss. Floating PROFIT (negative currentFloatingLoss) must not add headroom -- clamped to
//--- 0, matching test_propguard_rules.py::test_floating_profit_does_not_add_headroom.
bool GoldBotPropProjectionGuardOk(const double equity, const double stopLossCash,
                                   const double spreadCash, const double commissionCash,
                                   const double swapEstimateCash, const double currentFloatingLoss,
                                   const double dailyFloor, const double hardFloor)
{
   double worstCase = stopLossCash + spreadCash + commissionCash + swapEstimateCash +
                       MathMax(0.0, currentFloatingLoss);
   double floor = MathMax(dailyFloor, hardFloor);
   return (equity - worstCase) >= floor;
}

//--- Risk % after the target-proximity throttle: halved once within targetProximityPct of the
//--- phase's profit target. Ported verbatim from PropGuardThrottledRiskPct.
double GoldBotPropThrottledRiskPct(const double equity, const double initialBalance, const GoldBotPropConfig &cfg)
{
   double targetLevel = initialBalance * (1.0 + cfg.phaseTargetPct / 100.0);
   double proximityLevel = targetLevel * (1.0 - cfg.targetProximityPct / 100.0);
   if(equity >= proximityLevel)
      return cfg.challengeRiskPct * 0.5;
   return cfg.challengeRiskPct;
}

//+------------------------------------------------------------------+
//| Anti-ruin sizing invariant -- ported verbatim from                |
//| PropGuardRiskCash (RiskBudget.mqh). Never risk more than basePct  |
//| of equity, nor more than 1/dailyDivisor of the remaining daily    |
//| budget, nor more than 1/totalDivisor of the remaining max-DD      |
//| budget. The tightest of the three always wins.                    |
//+------------------------------------------------------------------+

double GoldBotPropRiskCash(const double equity, const double basePct,
                            const double dailyFloor, const double hardFloor,
                            const int dailyDivisor, const int totalDivisor)
{
   double byBase  = equity * basePct / 100.0;
   double byDaily = (dailyDivisor > 0) ? (equity - dailyFloor) / dailyDivisor : DBL_MAX;
   double byTotal = (totalDivisor > 0) ? (equity - hardFloor) / totalDivisor : DBL_MAX;
   double riskCash = MathMin(byBase, MathMin(byDaily, byTotal));
   return (riskCash > 0.0 ? riskCash : 0.0);
}

//--- Broker-normalized cash value of a 1.00 price move for one lot. Some prop-firm
//--- tester feeds expose SYMBOL_TRADE_TICK_VALUE values that are inconsistent with
//--- the symbol's contract size (FundingPips-Trial XAUUSD has reported 0.01 for a
//--- 0.01 tick while contractSize=100). OrderCalcProfit follows the broker's actual
//--- profit calculation mode and is therefore authoritative for sizing. The direct
//--- contract-size fallback is exact when profit and deposit currencies match; the
//--- legacy tick-value conversion remains only as a final cross-currency fallback.
double GoldBotPropCashPerPriceUnitPerLot(const string symbol)
{
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double referencePrice = SymbolInfoDouble(symbol, SYMBOL_BID);
   if(referencePrice <= 0.0)
      referencePrice = SymbolInfoDouble(symbol, SYMBOL_ASK);

   if(tickSize > 0.0 && referencePrice > 0.0)
   {
      double probeProfit = 0.0;
      if(OrderCalcProfit(ORDER_TYPE_BUY, symbol, 1.0,
                         referencePrice, referencePrice + tickSize, probeProfit))
      {
         double calculatedValue = MathAbs(probeProfit) / tickSize;
         if(calculatedValue > 0.0)
            return calculatedValue;
      }
   }

   string profitCurrency = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   string depositCurrency = AccountInfoString(ACCOUNT_CURRENCY);
   double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(contractSize > 0.0 && profitCurrency == depositCurrency)
      return contractSize;

   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tickValue <= 0.0)
      tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue > 0.0 && tickSize > 0.0)
      return tickValue / tickSize;

   return 0.0;
}

//--- Stop-distance-aware raw lot (pre-broker-step normalization). Adapted from
//--- PropGuardCalculateLot (RiskBudget.mqh) minus the normalization step, which callers do
//--- via GoldBot's own GoldBotNormalizeLot (Risk.mqh) so behavior matches the rest of GoldBot.
double GoldBotPropRawLot(const string symbol, const double stopDistancePrice, const double riskCash)
{
   double cashPerPriceUnit = GoldBotPropCashPerPriceUnitPerLot(symbol);
   if(cashPerPriceUnit <= 0.0 || riskCash <= 0.0 || stopDistancePrice <= 0.0)
      return 0.0;
   return riskCash / (stopDistancePrice * cashPerPriceUnit);
}

//+------------------------------------------------------------------+
//| Concurrency -- pending-inclusive. GoldBot's own InpMaxOpenTrades  |
//| gate (GoldBotCountManagedPositions) counts open positions only;   |
//| prop mode additionally caps positions+pending together.           |
//+------------------------------------------------------------------+

int GoldBotPropOpenAndPendingCount(const string symbol, const long magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != magic) continue;
      count++;
   }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket)) continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != magic) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Intra-bar account monitor -- call EVERY tick (above the new-bar   |
//| early return in OnTick), never just on new bars. Detects a hard   |
//| breach (daily hard-flatten floor or max-DD internal halt) that    |
//| requires flattening open positions and cancelling pendings NOW,   |
//| not waiting for the next bar.                                     |
//+------------------------------------------------------------------+

struct GoldBotPropMonitorResult
{
   bool   breach;
   string reason;
   double equity;
   double initialBalance;
   double equityPeak;
   double dayBaseline;
};

GoldBotPropMonitorResult GoldBotPropIntraBarMonitor(const string symbol, const long magic, const GoldBotPropConfig &cfg)
{
   GoldBotPropMonitorResult r;
   r.breach = false;
   r.reason = "ok";
   r.equity = AccountInfoDouble(ACCOUNT_EQUITY);
   r.initialBalance = GoldBotPropInitialBalance(magic);
   r.equityPeak = GoldBotPropEquityPeak(magic, r.equity);
   datetime dayStart = GoldBotPropDayStart(TimeCurrent(), cfg.dailyResetServerHour);
   r.dayBaseline = GoldBotPropDayBaseline(symbol, magic, dayStart);

   if(GoldBotPropMaxDdHalted(r.equity, r.initialBalance, r.equityPeak, cfg))
   {
      r.breach = true;
      r.reason = StringFormat("prop_max_dd_halt equity=%.2f floor=%.2f", r.equity,
         GoldBotPropMaxDdFloor(r.initialBalance, r.equityPeak, cfg));
      return r;
   }
   if(GoldBotPropDailyHardFlatten(r.equity, r.dayBaseline, cfg))
   {
      r.breach = true;
      r.reason = StringFormat("prop_daily_hard_flatten equity=%.2f floor=%.2f", r.equity,
         GoldBotPropDailyHardFloor(r.dayBaseline, cfg));
      return r;
   }
   return r;
}

//+------------------------------------------------------------------+
//| Pre-trade account-level gate -- call ONCE per tick at the entry   |
//| choke point, before the M15/M5/M1 setup fan-out, so all three     |
//| entry paths are gated uniformly by one call.                      |
//+------------------------------------------------------------------+

struct GoldBotPropGateResult
{
   bool   allow;
   string reason;
};

GoldBotPropGateResult GoldBotPropEntryGate(const string symbol, const long magic, const GoldBotPropConfig &cfg)
{
   GoldBotPropGateResult r;
   r.allow = true;
   r.reason = "ok";

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double initialBalance = GoldBotPropInitialBalance(magic);
   double equityPeak = GoldBotPropEquityPeak(magic, equity);
   datetime dayStart = GoldBotPropDayStart(TimeCurrent(), cfg.dailyResetServerHour);
   double dayBaseline = GoldBotPropDayBaseline(symbol, magic, dayStart);
   datetime now = TimeCurrent();

   if(GoldBotPropMaxDdHalted(equity, initialBalance, equityPeak, cfg))
   { r.allow = false; r.reason = "Prop max-drawdown internal halt"; return r; }
   if(GoldBotPropDailyHardFlatten(equity, dayBaseline, cfg))
   { r.allow = false; r.reason = "Prop daily hard-flatten floor"; return r; }
   if(GoldBotPropDailySoftHalted(equity, dayBaseline, cfg))
   { r.allow = false; r.reason = "Prop daily soft-halt floor"; return r; }
   if(GoldBotPropDailyProfitCapReached(equity, dayBaseline, cfg))
   { r.allow = false; r.reason = "Prop daily profit cap (give-back prevention)"; return r; }
   if(GoldBotPropIsWeekendFlattenTime(now, cfg))
   { r.allow = false; r.reason = "Prop weekend flatten window"; return r; }
   if(GoldBotPropIsRolloverBlackout(now, cfg))
   { r.allow = false; r.reason = "Prop rollover blackout window"; return r; }
   if(cfg.maxOpenAndPending > 0 && GoldBotPropOpenAndPendingCount(symbol, magic) >= cfg.maxOpenAndPending)
   { r.allow = false; r.reason = "Prop pending-inclusive concurrency cap"; return r; }

   return r;
}

//+------------------------------------------------------------------+
//| Cost gate + projection guard + anti-ruin sizing, composed. Call   |
//| immediately adjacent to GoldBotCompoundGovernorPass (from inside  |
//| it, when cfg.enabled) once SL/entry/spread are known for the      |
//| specific setup about to place an order. Overrides                 |
//| effectiveLotPer100Usd in place; GoldBot's existing                 |
//| GoldBotSplitLot/GoldBotNormalizeLot machinery (per-leg weighting,  |
//| high-conviction score bump, broker step rounding) still runs      |
//| downstream exactly as it does for non-prop sizing -- this only     |
//| replaces the linear (equity/100)*lotPer100Usd base with an        |
//| SL-aware, anti-ruin-clamped equivalent.                            |
//|                                                                    |
//| Known, documented simplification: the high-conviction 1.5x score  |
//| bump in GoldBotSplitLot and each path's own lotMultiplier still    |
//| apply on top of this, exactly as in non-prop mode -- so realized   |
//| worst-case risk on a high-conviction trade can run up to ~1.5x the |
//| riskCash computed here. Not neutralized because doing so would     |
//| require threading score/highConvictionScore through the governor   |
//| call at all 3 sites, diverging conviction-scaling behavior between |
//| prop/non-prop modes in a way not specified by the brief.           |
//+------------------------------------------------------------------+

bool GoldBotPropCostAndSizingGate(
   const string symbol,
   const long magic,
   const GoldBotPropConfig &cfg,
   const double stopDistancePrice,
   const double spreadPrice,
   const double minLot,
   const double maxLot,
   double &effectiveLotPer100Usd,
   string &reason
)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
   { reason = "prop invalid equity"; return false; }

   double initialBalance = GoldBotPropInitialBalance(magic);
   double equityPeak = GoldBotPropEquityPeak(magic, equity);
   datetime dayStart = GoldBotPropDayStart(TimeCurrent(), cfg.dailyResetServerHour);
   double dayBaseline = GoldBotPropDayBaseline(symbol, magic, dayStart);

   double cashPerPriceUnit = GoldBotPropCashPerPriceUnitPerLot(symbol);
   if(cashPerPriceUnit <= 0.0)
   { reason = "prop invalid broker price value"; return false; }
   double commissionPrice = cfg.commissionPerLotUsd / cashPerPriceUnit;

   if(!GoldBotPropCostGateOk(spreadPrice, commissionPrice, stopDistancePrice, cfg))
   {
      double costPct = stopDistancePrice > 0.0
         ? 100.0 * (spreadPrice + commissionPrice) / stopDistancePrice
         : DBL_MAX;
      reason = StringFormat("prop cost gate exceeds cap costPct=%.2f capPct=%.2f commissionPrice=%.4f cashPerPriceUnit=%.4f",
         costPct, cfg.costGateMaxPct, commissionPrice, cashPerPriceUnit);
      return false;
   }

   double throttledPct = GoldBotPropThrottledRiskPct(equity, initialBalance, cfg);
   double dailyFloor = GoldBotPropDailyHardFloor(dayBaseline, cfg);
   double hardFloor = GoldBotPropMaxDdFloor(initialBalance, equityPeak, cfg);
   double riskCash = GoldBotPropRiskCash(equity, throttledPct, dailyFloor, hardFloor, cfg.dailyRiskDivisor, cfg.totalRiskDivisor);
   if(riskCash <= 0.0)
   { reason = "prop anti-ruin risk budget clamped to zero"; return false; }

   double rawLot = GoldBotPropRawLot(symbol, stopDistancePrice, riskCash);
   double lots = GoldBotNormalizeLot(symbol, rawLot, minLot, maxLot);
   if(lots <= 0.0)
   { reason = "prop lot resolved to zero"; return false; }

   double spreadCash = spreadPrice * lots * cashPerPriceUnit;
   double commissionCash = cfg.commissionPerLotUsd * lots;
   double swapEstimateCash = cfg.swapEstimatePerLotUsd * lots;
   double currentFloatingLoss = MathMax(0.0, -AccountInfoDouble(ACCOUNT_PROFIT));

   if(!GoldBotPropProjectionGuardOk(equity, riskCash, spreadCash, commissionCash, swapEstimateCash,
                                     currentFloatingLoss, dailyFloor, hardFloor))
   { reason = "prop projection guard: worst-case breaches a floor"; return false; }

   effectiveLotPer100Usd = lots * 100.0 / equity;
   reason = StringFormat("prop sizing ok riskCash=%.2f lots=%.2f throttledPct=%.3f cashPerPriceUnit=%.4f",
      riskCash, lots, throttledPct, cashPerPriceUnit);
   return true;
}

//+------------------------------------------------------------------+
//| Effective spread cap: MIN of the setup's own cap and the prop     |
//| mode tightened cap, when both are configured (>0). Falls back to  |
//| whichever single cap is set; 0 means "no cap" as elsewhere in     |
//| GoldBot.                                                           |
//+------------------------------------------------------------------+

double GoldBotPropEffectiveSpreadCap(const double baseCapPrice, const double propCapPrice)
{
   if(propCapPrice <= 0.0)
      return baseCapPrice;
   if(baseCapPrice <= 0.0)
      return propCapPrice;
   return MathMin(baseCapPrice, propCapPrice);
}

#endif
