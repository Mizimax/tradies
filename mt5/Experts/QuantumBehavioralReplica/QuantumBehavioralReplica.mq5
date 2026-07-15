#property copyright "Independent behavioral research implementation"
#property link      ""
#property version   "1.13"
#property strict
#property description "QuantumBehavioralReplica: independent, deterministic behavioral replica."
#property description "Not Bunny Quantum source code; proprietary fidelity is unverified."

#include <QBR/Types.mqh>
#include <QBR/Indicators.mqh>
#include <QBR/QSync.mqh>
#include <QBR/StateFlow.mqh>
#include <QBR/DeepContext.mqh>
#include <QBR/PatternReader.mqh>
#include <QBR/BalanceFinder.mqh>
#include <QBR/SafetyFocus.mqh>
#include <QBR/EntryEngine.mqh>
#include <QBR/BasketManager.mqh>
#include <QBR/PositionSizer.mqh>
#include <QBR/TradeExecutor.mqh>
#include <QBR/Dashboard.mqh>
#include <QBR/CsvLogger.mqh>

// Core identity and operating mode
input string                InpBuildTag="QBR-1.13-aggressive";
input string                InpRunId="manual";
input long                  InpMagicNumber=2607121501;
input QBREntryMode          InpEntryMode=TREND_MULTI_ENTRY;
input QBRAddMode            InpAddMode=ADD_ON_CONTINUATION;
input QBRSizingMode         InpSizingMode=FIXED_LOT;
input bool                  InpFixedLot=true;
input double                InpInitialLot=0.01;
input double                InpLotMultiplier=1.0;
input bool                  InpAveragingAgainstMove=false;

// Feature parameters
input int                   InpEmaFast=21;
input int                   InpEmaSlow=55;
input int                   InpEmaDaily=50;
input int                   InpAtrPeriod=14;
input int                   InpAdxPeriod=14;
input int                   InpRsiPeriod=14;
input int                   InpMedianLookback=50;
input int                   InpSwingLookback=20;
input int                   InpBreakoutLookback=10;
input int                   InpVolumeLookback=30;

// Q-Sync weights and thresholds
input double                InpTrendWeight=0.32;
input double                InpMomentumWeight=0.24;
input double                InpBreakoutWeight=0.18;
input double                InpVolumeWeight=0.08;
input double                InpContextWeight=0.18;
input double                InpVolatilityPenaltyWeight=0.20;
input double                InpSpreadPenaltyWeight=0.15;
input double                InpConflictPenaltyWeight=0.15;
input double                InpLongThreshold=0.28;
input double                InpShortThreshold=-0.28;
input double                InpBreakoutThreshold=0.35;
input int                   InpMinPatternConfidence=68;
input bool                  InpAllowBalancedReentry=true;
input bool                  InpAllowTrendPullbackInBalanced=true;
input bool                  InpEnableTrendPullback=true;
input bool                  InpEnableFailedBreakout=true;
input bool                  InpEnableBreakoutRetest=true;
input bool                  InpEnableReversalRejection=true;
input bool                  InpEnableInsideBarCompression=true;
input bool                  InpRequireTrendReentry=true;
input bool                  InpRequireDailyAlignment=false;
input double                InpMaxEntryDistanceEMAATR=0.85;
input double                InpMaxRsiLong=68.0;
input double                InpMinRsiShort=32.0;

// Regime and tradability
input double                InpMinBalanceScore=62.0;
input double                InpMaxAtrRatio=1.80;
input double                InpExtremeAtrRatio=2.80;
input double                InpMinAdxTrend=20.0;
input double                InpMaxAdxBalance=17.0;
input int                   InpStateHysteresisBars=2;
input int                   InpWarmupBars=250;

// Safety Focus
input double                InpMaxSpreadPoints=350.0;
input double                InpMaxSpreadAtrRatio=0.12;
input double                InpMinFreeMargin=50.0;
input double                InpMinMarginLevel=180.0;
input double                InpMaxTotalLots=0.10;
input int                   InpMaxOrder=10;
input int                   InpMaxOrdersPerDirection=10;
input double                InpMaxBasketExposurePct=20.0;
input double                InpMaxDailyLossPct=3.0;
input double                InpMaxWeeklyLossPct=7.0;
input double                InpMaxEquityDrawdownPct=20.0;
input double                InpMaxFloatingLossPct=18.0;
input int                   InpMaxConsecutiveLosses=3;
input int                   InpDeviationPoints=20;
input int                   InpCooldownBars=4;
input int                   InpPostExitCooldownBars=1;
input int                   InpSpikeCooldownBars=2;
input int                   InpMinBarsBetweenOrders=1;
input QBREmergencyAction    InpEmergencyAction=EMERGENCY_STOP_NEW;
input int                   InpCloseRetryCount=3;

// SpikeGuard
input double                InpSpikeCurrentRangeATR=2.50;
input double                InpSpikePreviousRangeATR=2.20;
input double                InpSpikeTickJumpATR=0.35;
input double                InpSpikeSpreadMultiplier=2.50;
input double                InpSpikeGapATR=0.50;
input double                InpSpikeVolumeRatio=3.00;

// Position sizing and multi-entry
input double                InpRiskPerOrderPct=0.35;
input double                InpRiskPerBasketPct=1.00;
input bool                  InpAllowMinLotWithNativeRiskCap=false;
input string                InpMinLotAllowedHours="";
input double                InpEntrySpacingATR=0.45;

// Basket target and exits
input QBRBasketTargetMode   InpBasketTargetMode=TARGET_FIXED_MONEY;
input double                InpBasketTargetValue=2.00;
input double                InpBasketHardStopPct=8.00;
input double                InpMaxLossTargetRatio=2.50;
input int                   InpBasketMaxAgeBars=192;
input bool                  InpExitH4SwingBreak=true;
input bool                  InpExitQSyncReversal=true;
input bool                  InpExitContextReversal=true;
input bool                  InpExitPatternInvalidation=true;
input bool                  InpExitInvalidationClosedBar=true;
input bool                  InpExitEndSession=false;
input double                InpProfitLockTriggerFraction=0.80;
input double                InpProfitLockFloorFraction=0.20;

// Optional M5 trigger layer; M15/H4 remain the regime and direction authority.
input bool                  InpEnableM5ScalpLayer=false;
input double                InpM5TargetPct=0.15;
input double                InpM5HardStopPct=0.30;

// Broker-server session hours
input bool                  InpAllowAsian=true;
input bool                  InpAllowLondon=true;
input bool                  InpAllowNewYork=true;
input int                   InpAsianStartHour=0;
input int                   InpAsianEndHour=8;
input int                   InpLondonStartHour=7;
input int                   InpLondonEndHour=16;
input int                   InpNewYorkStartHour=13;
input int                   InpNewYorkEndHour=22;
input int                   InpSessionEdgeMinutes=10;

// UI and logging
input bool                  InpDashboardEnabled=true;
input bool                  InpCsvLogging=true;
input string                InpLogFolder="QBR_Logs";

QBRConfig       g_cfg;
CIndicators     g_indicators;
CQSync          g_qsync;
CStateFlow      g_state_flow;
CDeepContext    g_context;
CPatternReader  g_pattern_reader;
CBalanceFinder  g_balance_finder;
CSafetyFocus    g_safety;
CEntryEngine    g_entry_engine;
CBasketManager  g_basket;
CPositionSizer  g_sizer;
CTradeExecutor  g_executor;
CDashboard      g_dashboard;
CCsvLogger      g_logger;

QBRFeatures       g_features;
QBRQSyncResult    g_qsync_result;
QBRContextResult  g_context_result;
QBRPatternSignal  g_pattern;
QBRBalanceResult  g_balance;
QBRBasketSnapshot g_basket_snapshot;
QBRPerformanceStats g_stats;

datetime g_last_bar_time=0;
datetime g_last_entry_bar=0;
datetime g_last_daily_log=0;
datetime g_emergency_confirm_time=0;
datetime g_last_spike_cooldown_bar=0;
datetime g_last_m5_bar_time=0;
datetime g_last_m5_entry_bar=0;
int      g_cooldown_remaining=0;
int      g_consecutive_basket_losses=0;
int      g_completed_basket_wins=0;
int      g_completed_basket_losses=0;
bool     g_paused=false;
bool     g_emergency_latched=false;
bool     g_context_fallback_logged=false;
double   g_deposit_baseline=0.0;
double   g_equity_peak=0.0;
double   g_basket_invalidation=0.0;
datetime g_disable_until=0;
datetime g_loss_streak_block_until=0;
bool     g_profit_lock_armed=false;
string   g_last_exit_rule="NONE";
string   g_pending_exit_reason="";
string   g_basket_entry_pattern="UNKNOWN";
string   g_basket_entry_state="UNKNOWN";
int      g_basket_entry_confidence=0;
double   g_basket_entry_qsync=0.0;
double   g_basket_entry_balance=0.0;
long     g_last_finalized_basket_id=0;
QBRBasketSnapshot g_basket_audit_snapshot;
int      g_m5_ema_handle=INVALID_HANDLE;
int      g_m5_atr_handle=INVALID_HANDLE;
bool     g_active_m5_profile=false;
bool     g_pending_basket_finalization=false;
QBRBasketSnapshot g_pending_finalization_snapshot;
string   g_pending_finalization_reason="";

string PersistentKey(const string suffix)
  {
   return StringFormat("QBR_%s_%I64d_%s",_Symbol,g_cfg.magic,suffix);
  }

void BuildConfig()
  {
   g_cfg.magic=InpMagicNumber;
   g_cfg.execution_tf=PERIOD_M15;
   g_cfg.higher_tf=PERIOD_H4;
   g_cfg.ema_fast=InpEmaFast;
   g_cfg.ema_slow=InpEmaSlow;
   g_cfg.ema_daily=InpEmaDaily;
   g_cfg.atr_period=InpAtrPeriod;
   g_cfg.adx_period=InpAdxPeriod;
   g_cfg.rsi_period=InpRsiPeriod;
   g_cfg.median_lookback=InpMedianLookback;
   g_cfg.swing_lookback=InpSwingLookback;
   g_cfg.breakout_lookback=InpBreakoutLookback;
   g_cfg.volume_lookback=InpVolumeLookback;
   g_cfg.trend_weight=InpTrendWeight;
   g_cfg.momentum_weight=InpMomentumWeight;
   g_cfg.breakout_weight=InpBreakoutWeight;
   g_cfg.volume_weight=InpVolumeWeight;
   g_cfg.context_weight=InpContextWeight;
   g_cfg.volatility_penalty_weight=InpVolatilityPenaltyWeight;
   g_cfg.spread_penalty_weight=InpSpreadPenaltyWeight;
   g_cfg.conflict_penalty_weight=InpConflictPenaltyWeight;
   g_cfg.long_threshold=InpLongThreshold;
   g_cfg.short_threshold=InpShortThreshold;
   g_cfg.breakout_threshold=InpBreakoutThreshold;
   g_cfg.min_pattern_confidence=InpMinPatternConfidence;
   g_cfg.allow_balanced_reentry=InpAllowBalancedReentry;
   g_cfg.allow_trend_pullback_in_balanced=InpAllowTrendPullbackInBalanced;
   g_cfg.enable_trend_pullback=InpEnableTrendPullback;
   g_cfg.enable_failed_breakout=InpEnableFailedBreakout;
   g_cfg.enable_breakout_retest=InpEnableBreakoutRetest;
   g_cfg.enable_reversal_rejection=InpEnableReversalRejection;
   g_cfg.enable_inside_bar_compression=InpEnableInsideBarCompression;
   g_cfg.require_trend_reentry=InpRequireTrendReentry;
   g_cfg.require_daily_alignment=InpRequireDailyAlignment;
   g_cfg.max_entry_distance_ema_atr=InpMaxEntryDistanceEMAATR;
   g_cfg.max_rsi_long=InpMaxRsiLong;
   g_cfg.min_rsi_short=InpMinRsiShort;
   g_cfg.min_balance_score=InpMinBalanceScore;
   g_cfg.max_atr_ratio=InpMaxAtrRatio;
   g_cfg.extreme_atr_ratio=InpExtremeAtrRatio;
   g_cfg.min_adx_trend=InpMinAdxTrend;
   g_cfg.max_adx_balance=InpMaxAdxBalance;
   g_cfg.max_spread_points=InpMaxSpreadPoints;
   g_cfg.max_spread_atr_ratio=InpMaxSpreadAtrRatio;
   g_cfg.min_free_margin=InpMinFreeMargin;
   g_cfg.min_margin_level=InpMinMarginLevel;
   g_cfg.max_total_lots=InpMaxTotalLots;
   g_cfg.max_orders=InpMaxOrder;
   g_cfg.max_orders_direction=InpMaxOrdersPerDirection;
   g_cfg.max_basket_exposure_pct=InpMaxBasketExposurePct;
   g_cfg.max_daily_loss_pct=InpMaxDailyLossPct;
   g_cfg.max_weekly_loss_pct=InpMaxWeeklyLossPct;
   g_cfg.max_equity_drawdown_pct=InpMaxEquityDrawdownPct;
   g_cfg.max_floating_loss_pct=InpMaxFloatingLossPct;
   g_cfg.max_consecutive_losses=InpMaxConsecutiveLosses;
   g_cfg.deviation_points=InpDeviationPoints;
   g_cfg.cooldown_bars=InpCooldownBars;
   g_cfg.post_exit_cooldown_bars=InpPostExitCooldownBars;
   g_cfg.spike_cooldown_bars=InpSpikeCooldownBars;
   g_cfg.min_bars_between_orders=InpMinBarsBetweenOrders;
   g_cfg.spike_current_range_atr=InpSpikeCurrentRangeATR;
   g_cfg.spike_previous_range_atr=InpSpikePreviousRangeATR;
   g_cfg.spike_tick_jump_atr=InpSpikeTickJumpATR;
   g_cfg.spike_spread_multiplier=InpSpikeSpreadMultiplier;
   g_cfg.spike_gap_atr=InpSpikeGapATR;
   g_cfg.spike_volume_ratio=InpSpikeVolumeRatio;
   g_cfg.initial_lot=InpInitialLot;
   g_cfg.lot_multiplier=InpLotMultiplier;
   g_cfg.fixed_lot=InpFixedLot;
   g_cfg.sizing_mode=InpSizingMode;
   g_cfg.risk_per_order_pct=InpRiskPerOrderPct;
   g_cfg.risk_per_basket_pct=InpRiskPerBasketPct;
   g_cfg.allow_min_lot_with_native_risk_cap=InpAllowMinLotWithNativeRiskCap;
   g_cfg.min_lot_allowed_hours=InpMinLotAllowedHours;
   g_cfg.entry_mode=InpEntryMode;
   g_cfg.add_mode=InpAddMode;
   g_cfg.averaging_against_move=InpAveragingAgainstMove;
   g_cfg.entry_spacing_atr=InpEntrySpacingATR;
   g_cfg.basket_target_mode=InpBasketTargetMode;
   g_cfg.basket_target_value=InpBasketTargetValue;
   g_cfg.basket_hard_stop_pct=InpBasketHardStopPct;
   g_cfg.max_loss_target_ratio=InpMaxLossTargetRatio;
   g_cfg.basket_max_age_bars=InpBasketMaxAgeBars;
   g_cfg.exit_h4_swing_break=InpExitH4SwingBreak;
   g_cfg.exit_qsync_reversal=InpExitQSyncReversal;
   g_cfg.exit_context_reversal=InpExitContextReversal;
   g_cfg.exit_pattern_invalidation=InpExitPatternInvalidation;
   g_cfg.exit_invalidation_closed_bar=InpExitInvalidationClosedBar;
   g_cfg.exit_end_session=InpExitEndSession;
   g_cfg.profit_lock_trigger_fraction=InpProfitLockTriggerFraction;
   g_cfg.profit_lock_floor_fraction=InpProfitLockFloorFraction;
   g_cfg.enable_m5_scalp_layer=InpEnableM5ScalpLayer;
   g_cfg.m5_target_pct=InpM5TargetPct;
   g_cfg.m5_hard_stop_pct=InpM5HardStopPct;
   g_cfg.allow_asian=InpAllowAsian;
   g_cfg.allow_london=InpAllowLondon;
   g_cfg.allow_new_york=InpAllowNewYork;
   g_cfg.asian_start_hour=InpAsianStartHour;
   g_cfg.asian_end_hour=InpAsianEndHour;
   g_cfg.london_start_hour=InpLondonStartHour;
   g_cfg.london_end_hour=InpLondonEndHour;
   g_cfg.new_york_start_hour=InpNewYorkStartHour;
   g_cfg.new_york_end_hour=InpNewYorkEndHour;
   g_cfg.session_edge_minutes=InpSessionEdgeMinutes;
   g_cfg.state_hysteresis_bars=InpStateHysteresisBars;
   g_cfg.warmup_bars=InpWarmupBars;
   g_cfg.close_retry_count=InpCloseRetryCount;
   g_cfg.emergency_action=InpEmergencyAction;
   g_cfg.dashboard_enabled=InpDashboardEnabled;
   g_cfg.csv_logging=InpCsvLogging;
   g_cfg.log_prefix=InpLogFolder;
   g_cfg.run_id=InpRunId;
   g_cfg.build_tag=InpBuildTag;
  }

bool ValidateInputs(string &reason)
  {
   if(InpMagicNumber<=0) { reason="Magic Number must be positive"; return false; }
   if(InpEmaFast<=1 || InpEmaSlow<=InpEmaFast) { reason="EMA periods invalid"; return false; }
   if(InpInitialLot<=0.0 || InpLotMultiplier!=1.0) { reason="Initial lot must be positive and LotMultiplier must remain 1.0 (no Martingale)"; return false; }
   if(InpMaxOrder<1 || InpMaxOrdersPerDirection<1 || InpMaxOrdersPerDirection>InpMaxOrder) { reason="Order limits invalid"; return false; }
   if(InpBasketHardStopPct<=0.0 || InpMaxFloatingLossPct<=0.0) { reason="Every basket requires positive hard-risk limits"; return false; }
   if(InpShortThreshold>=0.0 || InpLongThreshold<=0.0) { reason="Long/short thresholds must straddle zero"; return false; }
   if(InpMinPatternConfidence<0 || InpMinPatternConfidence>100) { reason="Pattern confidence must be 0..100"; return false; }
   if(InpMaxEntryDistanceEMAATR<=0.0) { reason="Maximum EMA distance must be positive"; return false; }
   if(InpMinRsiShort<0.0 || InpMaxRsiLong>100.0 || InpMinRsiShort>=InpMaxRsiLong) { reason="RSI entry limits invalid"; return false; }
   if(InpProfitLockTriggerFraction<0.0 || InpProfitLockTriggerFraction>1.0 || InpProfitLockFloorFraction<0.0 || InpProfitLockFloorFraction>InpProfitLockTriggerFraction) { reason="Profit-lock fractions invalid"; return false; }
   if(InpMaxLossTargetRatio<=0.0) { reason="Maximum loss/target ratio must be positive"; return false; }
   if(InpPostExitCooldownBars<0 || InpSpikeCooldownBars<0) { reason="Cooldown bars cannot be negative"; return false; }
   if(InpEnableM5ScalpLayer && (InpM5TargetPct<=0.0 || InpM5HardStopPct<=0.0 || InpM5HardStopPct/InpM5TargetPct>InpMaxLossTargetRatio+1e-8))
     { reason="M5 target/stop profile is invalid"; return false; }
   if((InpBasketTargetMode==TARGET_BALANCE_PERCENT || InpBasketTargetMode==TARGET_EQUITY_PERCENT) &&
      InpBasketTargetValue>0.0 && InpBasketHardStopPct/InpBasketTargetValue>InpMaxLossTargetRatio+1e-8)
     { reason="Configured hard stop exceeds maximum loss/target ratio"; return false; }
   if(InpAveragingAgainstMove && InpBasketHardStopPct>20.0) { reason="Averaging against move requires hard basket stop <=20%"; return false; }
   return g_sizer.ValidateSymbolProperties(reason);
  }

void LoadPersistentState()
  {
   // Strategy Tester runs must start clean. Terminal Global Variables can survive
   // earlier tests and previously caused a transient spread event to leave the
   // EA permanently paused in a later backtest. Live/restart recovery remains unchanged.
   if((bool)MQLInfoInteger(MQL_TESTER))
     {
      g_deposit_baseline=AccountInfoDouble(ACCOUNT_BALANCE);
      g_paused=false;
      g_emergency_latched=false;
      g_consecutive_basket_losses=0;
      g_completed_basket_wins=0;
      g_completed_basket_losses=0;
      g_basket_invalidation=0.0;
      g_disable_until=0;
      g_loss_streak_block_until=0;
      g_profit_lock_armed=false;
      return;
     }

   string baseline_key=PersistentKey("BASELINE");
   if(GlobalVariableCheck(baseline_key)) g_deposit_baseline=GlobalVariableGet(baseline_key);
   else { g_deposit_baseline=AccountInfoDouble(ACCOUNT_BALANCE); GlobalVariableSet(baseline_key,g_deposit_baseline); }

   string pause_key=PersistentKey("PAUSED");
   if(GlobalVariableCheck(pause_key)) g_paused=(GlobalVariableGet(pause_key)>0.5);

   string loss_key=PersistentKey("LOSS_STREAK");
   if(GlobalVariableCheck(loss_key)) g_consecutive_basket_losses=(int)GlobalVariableGet(loss_key);
   string loss_block_key=PersistentKey("LOSS_STREAK_BLOCK_UNTIL");
   if(GlobalVariableCheck(loss_block_key)) g_loss_streak_block_until=(datetime)GlobalVariableGet(loss_block_key);
   string profit_lock_key=PersistentKey("PROFIT_LOCK_ARMED");
   if(GlobalVariableCheck(profit_lock_key)) g_profit_lock_armed=(GlobalVariableGet(profit_lock_key)>0.5);
   string wins_key=PersistentKey("BASKET_WINS");
   string losses_key=PersistentKey("BASKET_LOSSES");
   if(GlobalVariableCheck(wins_key)) g_completed_basket_wins=(int)GlobalVariableGet(wins_key);
   if(GlobalVariableCheck(losses_key)) g_completed_basket_losses=(int)GlobalVariableGet(losses_key);

   string invalidation_key=PersistentKey("INVALIDATION");
   if(GlobalVariableCheck(invalidation_key)) g_basket_invalidation=GlobalVariableGet(invalidation_key);

   string disable_key=PersistentKey("DISABLE_UNTIL");
   if(GlobalVariableCheck(disable_key))
     {
      g_disable_until=(datetime)GlobalVariableGet(disable_key);
      if(TimeCurrent()<g_disable_until) g_paused=true;
      else { g_disable_until=0; GlobalVariableDel(disable_key); }
     }
  }

void SavePaused()
  {
   if((bool)MQLInfoInteger(MQL_TESTER)) return;
   GlobalVariableSet(PersistentKey("PAUSED"),(g_paused ? 1.0 : 0.0));
  }

void SaveLossStreak()
  {
   if((bool)MQLInfoInteger(MQL_TESTER)) return;
   GlobalVariableSet(PersistentKey("LOSS_STREAK"),(double)g_consecutive_basket_losses);
   GlobalVariableSet(PersistentKey("LOSS_STREAK_BLOCK_UNTIL"),(double)g_loss_streak_block_until);
  }

void SaveProfitLock()
  {
   if((bool)MQLInfoInteger(MQL_TESTER)) return;
   GlobalVariableSet(PersistentKey("PROFIT_LOCK_ARMED"),(g_profit_lock_armed ? 1.0 : 0.0));
  }

datetime NextBrokerDayStart(const datetime now)
  {
   MqlDateTime t;
   TimeToStruct(now,t);
   t.hour=0; t.min=0; t.sec=0;
   return StructToTime(t)+86400;
  }

void RefreshLossStreakBlock()
  {
   if(g_loss_streak_block_until<=0 || TimeCurrent()<g_loss_streak_block_until) return;
   g_loss_streak_block_until=0;
   g_consecutive_basket_losses=0;
   SaveLossStreak();
  }

void SaveOutcomeCounts()
  {
   if((bool)MQLInfoInteger(MQL_TESTER)) return;
   GlobalVariableSet(PersistentKey("BASKET_WINS"),(double)g_completed_basket_wins);
   GlobalVariableSet(PersistentKey("BASKET_LOSSES"),(double)g_completed_basket_losses);
  }

void SaveInvalidation()
  {
   if((bool)MQLInfoInteger(MQL_TESTER)) return;
   GlobalVariableSet(PersistentKey("INVALIDATION"),g_basket_invalidation);
  }

bool IsNewExecutionBar()
  {
   datetime current=iTime(_Symbol,g_cfg.execution_tf,0);
   if(current<=0) return false;
   if(current==g_last_bar_time) return false;
   g_last_bar_time=current;
   if(g_cooldown_remaining>0) g_cooldown_remaining--;
   return true;
  }

bool EntryFrequencyPassed(const datetime current_bar,const QBRBasketSnapshot &basket)
  {
   if(g_last_entry_bar==current_bar) return false;
   if(basket.last_entry_time<=0) return true;
   int seconds=PeriodSeconds(g_cfg.execution_tf)*(int)MathMax((double)g_cfg.min_bars_between_orders,1.0);
   return (current_bar-basket.last_entry_time>=seconds);
  }

bool IsNewM5Bar()
  {
   datetime current=iTime(_Symbol,PERIOD_M5,0);
   if(current<=0 || current==g_last_m5_bar_time) return false;
   g_last_m5_bar_time=current;
   return true;
  }

void RememberBasketForAudit(const QBRBasketSnapshot &basket)
  {
   if(basket.orders<=0 || basket.basket_id<=0) return;
   if(g_basket_audit_snapshot.basket_id!=basket.basket_id)
     {
      g_basket_audit_snapshot=basket;
      return;
     }
   g_basket_audit_snapshot.orders=MathMax(g_basket_audit_snapshot.orders,basket.orders);
   g_basket_audit_snapshot.total_lots=MathMax(g_basket_audit_snapshot.total_lots,basket.total_lots);
   g_basket_audit_snapshot.mfe=MathMax(g_basket_audit_snapshot.mfe,basket.mfe);
   g_basket_audit_snapshot.mae=MathMin(g_basket_audit_snapshot.mae,basket.mae);
   g_basket_audit_snapshot.last_entry_time=MathMax(g_basket_audit_snapshot.last_entry_time,basket.last_entry_time);
   g_basket_audit_snapshot.last_entry_price=basket.last_entry_price;
  }

void BasketDealTotals(const datetime start_time,const datetime end_time,int &closed_deals,int &closed_positions,
                      double &gross,double &costs,double &net)
  {
   closed_deals=0; closed_positions=0; gross=0.0; costs=0.0; net=0.0;
   if(start_time<=0 || !HistorySelect(start_time,end_time)) return;
   long position_ids[];
   for(int i=0;i<HistoryDealsTotal();i++)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if((long)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=g_cfg.magic) continue;
      double p=HistoryDealGetDouble(ticket,DEAL_PROFIT);
      double c=HistoryDealGetDouble(ticket,DEAL_SWAP)+HistoryDealGetDouble(ticket,DEAL_COMMISSION)+HistoryDealGetDouble(ticket,DEAL_FEE);
      gross+=p; costs+=c; net+=p+c;
      long entry=HistoryDealGetInteger(ticket,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
        {
         closed_deals++;
         long position_id=(long)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
         bool known=false;
         for(int j=0;j<ArraySize(position_ids);j++)
            if(position_ids[j]==position_id) { known=true; break; }
         if(!known)
           {
            int count=ArraySize(position_ids);
            ArrayResize(position_ids,count+1);
            position_ids[count]=position_id;
            closed_positions++;
           }
        }
     }
  }

string ExitReasonFromDeal(const ulong deal)
  {
   ENUM_DEAL_REASON reason=(ENUM_DEAL_REASON)HistoryDealGetInteger(deal,DEAL_REASON);
   if(reason==DEAL_REASON_SL) return "BROKER_NATIVE_SL";
   if(reason==DEAL_REASON_TP) return "BROKER_NATIVE_TP";
   if(reason==DEAL_REASON_SO) return "BROKER_STOPOUT";
   if(reason==DEAL_REASON_CLIENT || reason==DEAL_REASON_MOBILE || reason==DEAL_REASON_WEB) return "MANUAL_EXTERNAL_CLOSE";
   if(reason==DEAL_REASON_EXPERT) return (g_pending_exit_reason!="" ? g_pending_exit_reason : "EXPERT_EXIT");
   return "BROKER_EXTERNAL_EXIT";
  }

bool FinalizeClosedBasket(const QBRBasketSnapshot &snapshot,const datetime end_time,const string reason)
  {
   QBRBasketSnapshot before=snapshot;
   if(before.basket_id<=0 || before.basket_id==g_last_finalized_basket_id) return false;
   int closed_deals=0;
   int closed_positions=0;
   double gross,costs,net;
   BasketDealTotals(before.start_time,end_time,closed_deals,closed_positions,gross,costs,net);
   if(closed_deals<=0) return false;
   g_logger.Basket(before,end_time,closed_deals,closed_positions,gross,costs,net,reason,g_basket_entry_pattern,g_basket_entry_state,
                   g_basket_entry_confidence,g_basket_entry_qsync,g_basket_entry_balance,g_qsync_result.total,
                   g_context_result.total,QBRStateToString(g_state_flow.Current()));
   g_last_finalized_basket_id=before.basket_id;
   if(net<0.0)
     {
      g_consecutive_basket_losses++;
      g_completed_basket_losses++;
      if(g_consecutive_basket_losses>=g_cfg.max_consecutive_losses)
         g_loss_streak_block_until=NextBrokerDayStart(end_time);
     }
   else if(net>0.0)
     {
      g_consecutive_basket_losses=0;
      g_loss_streak_block_until=0;
      g_completed_basket_wins++;
     }
   SaveLossStreak();
   SaveOutcomeCounts();
   g_basket_invalidation=0.0;
   g_profit_lock_armed=false;
   SaveProfitLock();
   g_basket_entry_pattern="UNKNOWN";
   g_basket_entry_state="UNKNOWN";
   g_basket_entry_confidence=0;
   g_basket_entry_qsync=0.0;
   g_basket_entry_balance=0.0;
   g_pending_exit_reason="";
   ZeroMemory(g_basket_audit_snapshot);
   g_basket.ClearRiskProfileOverrides();
   g_active_m5_profile=false;
   SaveInvalidation();
   g_cooldown_remaining=MathMax(g_cooldown_remaining,g_cfg.post_exit_cooldown_bars);
   g_last_exit_rule=reason;
   return true;
  }

void QueueBasketFinalization(const QBRBasketSnapshot &snapshot,const string reason)
  {
   if(snapshot.orders<=0 || snapshot.basket_id<=0) return;
   g_pending_finalization_snapshot=snapshot;
   g_pending_finalization_reason=reason;
   g_pending_basket_finalization=true;
  }

void RetryPendingBasketFinalization(void)
  {
   if(!g_pending_basket_finalization || g_basket_snapshot.orders>0) return;
   if(FinalizeClosedBasket(g_pending_finalization_snapshot,TimeCurrent(),g_pending_finalization_reason))
     {
      g_pending_basket_finalization=false;
      ZeroMemory(g_pending_finalization_snapshot);
      g_pending_finalization_reason="";
     }
  }

bool CloseBasketWithReason(const string reason)
  {
   QBRBasketSnapshot before=g_basket_snapshot;
   if(before.orders<=0) return true;
   RememberBasketForAudit(before);
   g_pending_exit_reason=reason;
   int failures=g_executor.CloseBasket();
   g_logger.Order("CLOSE_BASKET",before.direction,before.total_lots,before.weighted_average,g_executor.LastRetcode(),
                  (failures==0 ? "OK" : g_executor.LastError()),"",before.basket_id);
   g_basket_snapshot=g_basket.Refresh(g_features.atr);
   if(failures==0 && g_basket_snapshot.orders==0)
     {
      QBRBasketSnapshot audit=before;
      if(g_basket_audit_snapshot.basket_id>0) audit=g_basket_audit_snapshot;
      if(!FinalizeClosedBasket(audit,TimeCurrent(),reason)) QueueBasketFinalization(audit,reason);
      return true;
     }
   g_pending_exit_reason="";
   g_logger.Risk("ERROR","Partial basket close failure","Refresh state and stop duplicate close",g_state_flow.Current(),g_basket_snapshot,g_features);
   return false;
  }

void ExecuteEmergency(const QBRSafetyResult &risk)
  {
   if(g_emergency_latched && g_cfg.emergency_action!=EMERGENCY_CLOSE_PROFITABLE) return;
   g_emergency_latched=true;
   g_state_flow.Force(QBR_EMERGENCY,risk.reason);
   g_paused=true;
   SavePaused();
   string action="STOP_NEW_ENTRIES";
   if(g_cfg.emergency_action==EMERGENCY_CLOSE_PROFITABLE)
     {
      g_executor.CloseProfitableOnly();
      action="CLOSE_PROFITABLE_ONLY";
     }
   else if(g_cfg.emergency_action==EMERGENCY_CLOSE_BASKET || g_cfg.emergency_action==EMERGENCY_CLOSE_ALL_EA)
     {
      CloseBasketWithReason("EMERGENCY_RISK_EXIT");
      action="CLOSE_EA_BASKET";
     }
   else if(g_cfg.emergency_action==EMERGENCY_DISABLE_UNTIL_NEXT_DAY)
     {
      MqlDateTime t; TimeToStruct(TimeCurrent(),t); t.hour=0; t.min=0; t.sec=0;
      g_disable_until=StructToTime(t)+86400;
      GlobalVariableSet(PersistentKey("DISABLE_UNTIL"),(double)g_disable_until);
      action="DISABLE_UNTIL_NEXT_DAY";
     }
   else if(g_cfg.emergency_action==EMERGENCY_REQUIRE_MANUAL_RESUME)
      action="REQUIRE_MANUAL_RESUME";
   g_logger.Risk("EMERGENCY",risk.reason,action,g_state_flow.Current(),g_basket_snapshot,g_features);
  }

bool EndSessionNow()
  {
   MqlDateTime t; TimeToStruct(TimeCurrent(),t);
   return (t.min>=60-g_cfg.session_edge_minutes &&
           (t.hour==g_cfg.asian_end_hour-1 || t.hour==g_cfg.london_end_hour-1 || t.hour==g_cfg.new_york_end_hour-1));
  }

double BasketCatastropheStop(const QBRBasketSnapshot &basket)
  {
   if(basket.orders<=0 || basket.total_lots<=0.0 || basket.hard_stop_money>=0.0) return 0.0;
   double tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tick_value=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_value<=0.0) tick_value=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(tick_size<=0.0 || tick_value<=0.0) return 0.0;
   double distance=MathAbs(basket.hard_stop_money)*tick_size/(tick_value*basket.total_lots);
   double stop=(basket.direction==QBR_DIR_LONG ? basket.weighted_average-distance : basket.weighted_average+distance);
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return NormalizeDouble(stop,digits);
  }

void ManageOpenBasket(const QBRSafetyResult &risk,const bool new_bar)
  {
   if(g_basket_snapshot.orders<=0) return;
   if(risk.emergency) { ExecuteEmergency(risk); return; }
   if(g_basket.HardStopHit()) { CloseBasketWithReason("HARD_BASKET_LOSS"); return; }
   if(g_basket.ProfitTargetHit()) { CloseBasketWithReason("BASKET_PROFIT_TARGET"); return; }
   if(!g_profit_lock_armed && g_cfg.profit_lock_trigger_fraction>0.0 && g_basket_snapshot.target_money>0.0 &&
      g_basket_snapshot.mfe>=g_basket_snapshot.target_money*g_cfg.profit_lock_trigger_fraction)
     {
      g_profit_lock_armed=true;
      SaveProfitLock();
     }
   if(g_profit_lock_armed && g_basket_snapshot.target_money>0.0 &&
      g_basket_snapshot.floating_profit<=g_basket_snapshot.target_money*g_cfg.profit_lock_floor_fraction)
     { CloseBasketWithReason("PROFIT_LOCK"); return; }
   if(g_safety.DailyStopReached()) { CloseBasketWithReason("DAILY_STOP"); return; }
   if(g_basket.TimeStopHit()) { CloseBasketWithReason("TIME_STOP"); return; }

   if(g_cfg.exit_h4_swing_break)
     {
      bool broken=(g_basket_snapshot.direction==QBR_DIR_LONG && g_features.h4_structure<0) ||
                  (g_basket_snapshot.direction==QBR_DIR_SHORT && g_features.h4_structure>0);
      if(broken) { CloseBasketWithReason("H4_SWING_BREAK"); return; }
     }
   if(g_cfg.exit_qsync_reversal)
     {
      bool reversed=(g_basket_snapshot.direction==QBR_DIR_LONG && g_qsync_result.total<=g_cfg.short_threshold*0.5) ||
                    (g_basket_snapshot.direction==QBR_DIR_SHORT && g_qsync_result.total>=g_cfg.long_threshold*0.5);
      if(reversed) { CloseBasketWithReason("QSYNC_REVERSAL"); return; }
     }
   if(g_cfg.exit_context_reversal)
     {
      bool reversed=(g_basket_snapshot.direction==QBR_DIR_LONG && g_context_result.total<-0.35) ||
                    (g_basket_snapshot.direction==QBR_DIR_SHORT && g_context_result.total>0.35);
      if(reversed) { CloseBasketWithReason("DEEPCONTEXT_REVERSAL"); return; }
     }
   if(g_cfg.exit_pattern_invalidation && g_basket_invalidation>0.0 &&
      (!g_cfg.exit_invalidation_closed_bar || new_bar))
     {
      double price=(g_cfg.exit_invalidation_closed_bar ? g_features.close_price :
                    (g_basket_snapshot.direction==QBR_DIR_LONG ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK)));
      bool invalid=(g_basket_snapshot.direction==QBR_DIR_LONG && price<=g_basket_invalidation) ||
                   (g_basket_snapshot.direction==QBR_DIR_SHORT && price>=g_basket_invalidation);
      if(invalid) { CloseBasketWithReason("PATTERN_INVALIDATION"); return; }
     }
   if(g_cfg.exit_end_session && EndSessionNow()) CloseBasketWithReason("END_OF_SESSION");
  }

void ProcessNewBar(const QBRSafetyResult &monitor_risk,const bool spike)
  {
   bool warm=g_indicators.IsWarm(g_cfg.warmup_bars) && g_features.data_ready;
   QBRState old_state,new_state;
   string transition_reason;
   bool transitioned=g_state_flow.Update(g_features,g_qsync_result,g_balance,g_basket_snapshot,g_paused,warm,
                                          g_safety.DailyStopReached(),monitor_risk.emergency,spike,g_cooldown_remaining,
                                          old_state,new_state,transition_reason);
   if(transitioned) g_logger.StateTransition(old_state,new_state,transition_reason,g_qsync_result,g_features,g_basket_snapshot);
   g_pattern=g_pattern_reader.Evaluate(g_features,g_state_flow.Current());
   g_balance=g_balance_finder.Evaluate(g_features,g_qsync_result,g_pattern);

   if(!warm || spike || monitor_risk.emergency)
     {
      g_logger.Signal(g_features,g_state_flow.Current(),QBR_DIR_FLAT,g_qsync_result,g_context_result,g_balance,g_pattern,false,
                      (!warm ? "Warmup/data unavailable" : (spike ? "SpikeGuard active" : monitor_risk.reason)));
      return;
     }
   if(g_active_m5_profile && g_basket_snapshot.orders>0)
     {
      g_logger.Signal(g_features,g_state_flow.Current(),QBR_DIR_FLAT,g_qsync_result,g_context_result,g_balance,g_pattern,false,
                      "M15 add blocked while M5 single-position basket is active");
      return;
     }

   QBRDirection candidate=QBR_DIR_FLAT;
   if(g_state_flow.Current()==QBR_TREND_UP || g_state_flow.Current()==QBR_BREAKOUT_UP || g_state_flow.Current()==QBR_BASKET_LONG) candidate=QBR_DIR_LONG;
   if(g_state_flow.Current()==QBR_TREND_DOWN || g_state_flow.Current()==QBR_BREAKOUT_DOWN || g_state_flow.Current()==QBR_BASKET_SHORT) candidate=QBR_DIR_SHORT;
   if(candidate==QBR_DIR_FLAT && g_cfg.allow_balanced_reentry && g_state_flow.Current()==QBR_BALANCED && g_pattern.detected)
     {
      if(g_pattern.direction==QBR_DIR_LONG && g_features.h4_bias>0) candidate=QBR_DIR_LONG;
      if(g_pattern.direction==QBR_DIR_SHORT && g_features.h4_bias<0) candidate=QBR_DIR_SHORT;
     }
   if(candidate==QBR_DIR_FLAT)
     {
      string state_reason=StringFormat("StateFlow not in entry state (%s): %s",
                                       QBRStateToString(g_state_flow.Current()),g_state_flow.LastReason());
      g_logger.Signal(g_features,g_state_flow.Current(),candidate,g_qsync_result,g_context_result,g_balance,g_pattern,false,state_reason);
      return;
     }
   double current_price=(candidate==QBR_DIR_LONG ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID));
   bool spacing=g_basket.SpacingPassed(candidate,current_price,g_features.atr);
   int dir_count=g_basket.CountDirection(candidate);

   string sizing_reason;
   double stop_price=g_pattern.invalidation_price;
   if(stop_price<=0.0)
      stop_price=(candidate==QBR_DIR_LONG ? g_features.recent_swing_low : g_features.recent_swing_high);
   if(g_basket_snapshot.orders>0 && g_basket_invalidation>0.0)
     {
      if(candidate==QBR_DIR_LONG) stop_price=MathMax(g_basket_invalidation,stop_price);
      else if(candidate==QBR_DIR_SHORT) stop_price=MathMin(g_basket_invalidation,stop_price);
     }
   double lot=g_sizer.Calculate(candidate,current_price,stop_price,g_basket_snapshot,sizing_reason);
   QBRSafetyResult pretrade=g_safety.PreTrade(g_features,g_basket_snapshot,candidate,lot,g_consecutive_basket_losses,
                                              g_cooldown_remaining>0);
   if(!monitor_risk.allow) pretrade=monitor_risk;

   QBREntryDecision decision=g_entry_engine.Evaluate(g_state_flow.Current(),g_features,g_qsync_result,g_pattern,g_balance,
                                                      pretrade,g_basket_snapshot,spacing,dir_count);
   datetime current_bar=iTime(_Symbol,g_cfg.execution_tf,0);
   if(decision.allow && !EntryFrequencyPassed(current_bar,g_basket_snapshot))
     {
      decision.allow=false;
      decision.reason="One-order-per-bar or new-order frequency limit";
     }
   g_logger.Signal(g_features,g_state_flow.Current(),decision.direction,g_qsync_result,g_context_result,g_balance,g_pattern,
                   decision.allow,decision.reason);
   if(!decision.allow) return;

   bool was_empty=(g_basket_snapshot.orders==0);
   double lots_before=g_basket_snapshot.total_lots;
   string comment=StringFormat("QBR|%s|%s",decision.signal_id,g_pattern.name);
   bool opened=g_executor.Open(decision.direction,lot,comment,0.0,0.0);
   g_logger.Order("OPEN",decision.direction,lot,current_price,g_executor.LastRetcode(),
                  (opened ? "OK" : g_executor.LastError()),decision.signal_id,g_basket_snapshot.basket_id);
   if(opened)
     {
      g_last_entry_bar=current_bar;
      g_basket_snapshot=g_basket.Refresh(g_features.atr);
      RememberBasketForAudit(g_basket_snapshot);
      double catastrophe_stop=BasketCatastropheStop(g_basket_snapshot);
      int stop_failures=g_executor.SetBasketStop(catastrophe_stop);
      if(stop_failures>0)
        {
         string stop_error=g_executor.LastError();
         g_paused=true;
         SavePaused();
         g_logger.Risk("EMERGENCY","Unable to place broker-native basket stop; position closed immediately",stop_error,g_state_flow.Current(),g_basket_snapshot,g_features);
         CloseBasketWithReason("NATIVE_STOP_PLACEMENT_FAILED");
         return;
        }
      double actual_added=g_basket_snapshot.total_lots-lots_before;
      double volume_step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      if(MathAbs(actual_added-lot)>MathMax(volume_step*0.51,1e-8))
        {
         g_paused=true; SavePaused();
         g_logger.Risk("EMERGENCY","Actual filled lot differs from calculated lot","Pause new entries and require state review",g_state_flow.Current(),g_basket_snapshot,g_features);
        }
      if(was_empty)
        {
         g_basket_invalidation=stop_price;
         g_basket_entry_pattern=g_pattern.name;
         g_basket_entry_state=QBRStateToString(g_state_flow.Current());
         g_basket_entry_confidence=g_pattern.confidence;
         g_basket_entry_qsync=g_qsync_result.total;
         g_basket_entry_balance=g_balance.score;
         SaveInvalidation();
        }
      else if(g_basket_invalidation>0.0)
        {
         if(decision.direction==QBR_DIR_LONG) g_basket_invalidation=MathMax(g_basket_invalidation,stop_price);
         else g_basket_invalidation=MathMin(g_basket_invalidation,stop_price);
         SaveInvalidation();
        }
     }
   else g_logger.Risk("ERROR","Order send failed",g_executor.LastError(),g_state_flow.Current(),g_basket_snapshot,g_features);
  }

void AssignM5Pattern(QBRPatternSignal &target,const QBRDirection direction,const int confidence,
                     const double invalidation,const string name)
  {
   if(target.detected && target.confidence>=confidence) return;
   target.detected=true;
   target.direction=direction;
   target.confidence=confidence;
   target.invalidation_price=invalidation;
   target.age_bars=0;
   target.source_tf=PERIOD_M5;
   target.name=name;
  }

QBRPatternSignal EvaluateM5ScalpPattern()
  {
   QBRPatternSignal result;
   ZeroMemory(result);
   result.direction=QBR_DIR_FLAT;
   result.source_tf=PERIOD_M5;
   result.name="NONE";
   int needed=(int)MathMax(14.0,(double)g_cfg.breakout_lookback+3.0);
   MqlRates r[];
   ArraySetAsSeries(r,true);
   if(CopyRates(_Symbol,PERIOD_M5,1,needed,r)<needed) return result;
   double ema[],atr[];
   ArraySetAsSeries(ema,true);
   ArraySetAsSeries(atr,true);
   if(CopyBuffer(g_m5_ema_handle,0,1,2,ema)<2 || CopyBuffer(g_m5_atr_handle,0,1,2,atr)<2) return result;
   double current_atr=MathMax(atr[0],SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE));
   bool bull=r[0].close>r[0].open;
   bool bear=r[0].close<r[0].open;

   double prior_high=-DBL_MAX,prior_low=DBL_MAX;
   for(int i=1;i<=g_cfg.breakout_lookback && i<ArraySize(r);i++)
     {
      prior_high=MathMax(prior_high,r[i].high);
      prior_low=MathMin(prior_low,r[i].low);
     }
   bool failed_up=(r[0].high>prior_high && r[0].close<prior_high && bear);
   bool failed_down=(r[0].low<prior_low && r[0].close>prior_low && bull);
   if(failed_up && g_features.h4_bias<0) AssignM5Pattern(result,QBR_DIR_SHORT,80,r[0].high,"M5_FAILED_BREAKOUT");
   if(failed_down && g_features.h4_bias>0) AssignM5Pattern(result,QBR_DIR_LONG,80,r[0].low,"M5_FAILED_BREAKOUT");

   double retest_high=-DBL_MAX,retest_low=DBL_MAX;
   for(int i=2;i<=g_cfg.breakout_lookback+1 && i<ArraySize(r);i++)
     {
      retest_high=MathMax(retest_high,r[i].high);
      retest_low=MathMin(retest_low,r[i].low);
     }
   bool retest_up=(r[1].close>retest_high && r[0].low<=retest_high+0.15*current_atr && r[0].close>retest_high);
   bool retest_down=(r[1].close<retest_low && r[0].high>=retest_low-0.15*current_atr && r[0].close<retest_low);
   if(retest_up && g_features.h4_bias>0) AssignM5Pattern(result,QBR_DIR_LONG,88,r[0].low,"M5_BREAKOUT_AND_RETEST");
   if(retest_down && g_features.h4_bias<0) AssignM5Pattern(result,QBR_DIR_SHORT,88,r[0].high,"M5_BREAKOUT_AND_RETEST");

   bool pullback_long=(g_features.h4_bias>0 && r[1].close<ema[1] && r[0].close>ema[0] && bull);
   bool pullback_short=(g_features.h4_bias<0 && r[1].close>ema[1] && r[0].close<ema[0] && bear);
   if(pullback_long) AssignM5Pattern(result,QBR_DIR_LONG,74,MathMin(r[0].low,r[1].low),"M5_TREND_PULLBACK");
   if(pullback_short) AssignM5Pattern(result,QBR_DIR_SHORT,74,MathMax(r[0].high,r[1].high),"M5_TREND_PULLBACK");
   return result;
  }

bool M5StateDirectionAllowed(const QBRDirection direction)
  {
   QBRState state=g_state_flow.Current();
   if(direction==QBR_DIR_LONG)
      return (state==QBR_TREND_UP || state==QBR_BREAKOUT_UP || state==QBR_BALANCED);
   if(direction==QBR_DIR_SHORT)
      return (state==QBR_TREND_DOWN || state==QBR_BREAKOUT_DOWN || state==QBR_BALANCED);
   return false;
  }

void ProcessM5ScalpBar(const QBRSafetyResult &monitor_risk,const bool spike)
  {
   if(!g_cfg.enable_m5_scalp_layer || spike || monitor_risk.emergency || !monitor_risk.allow) return;
   if(g_basket_snapshot.orders>0 || g_cooldown_remaining>0) return;
   datetime current_bar=iTime(_Symbol,PERIOD_M5,0);
   if(current_bar<=0 || current_bar==g_last_m5_entry_bar) return;
   QBRPatternSignal pattern=EvaluateM5ScalpPattern();
   if(!pattern.detected || pattern.confidence<g_cfg.min_pattern_confidence) return;
   QBRBalanceResult m5_balance=g_balance_finder.Evaluate(g_features,g_qsync_result,pattern);
   if(!M5StateDirectionAllowed(pattern.direction)) return;
   if(pattern.direction==QBR_DIR_LONG && (g_features.h4_bias<=0 || g_qsync_result.total<g_cfg.long_threshold)) return;
   if(pattern.direction==QBR_DIR_SHORT && (g_features.h4_bias>=0 || g_qsync_result.total>g_cfg.short_threshold)) return;
   if(!m5_balance.allow_entry) return;

   double price=(pattern.direction==QBR_DIR_LONG ? SymbolInfoDouble(_Symbol,SYMBOL_ASK) : SymbolInfoDouble(_Symbol,SYMBOL_BID));
   string sizing_reason;
   double lot=g_sizer.Calculate(pattern.direction,price,pattern.invalidation_price,g_basket_snapshot,sizing_reason);
   QBRSafetyResult pretrade=g_safety.PreTrade(g_features,g_basket_snapshot,pattern.direction,lot,g_consecutive_basket_losses,false);
   if(!pretrade.allow)
     {
      g_logger.Signal(g_features,g_state_flow.Current(),pattern.direction,g_qsync_result,g_context_result,m5_balance,pattern,false,pretrade.reason);
      return;
     }

   g_basket.SetRiskProfileOverrides(g_cfg.m5_target_pct,g_cfg.m5_hard_stop_pct);
   g_active_m5_profile=true;
   string signal_id=StringFormat("%s-M5-%I64d",_Symbol,(long)current_bar);
   bool opened=g_executor.Open(pattern.direction,lot,StringFormat("QBR|%s|%s",signal_id,pattern.name),0.0,0.0);
   g_logger.Signal(g_features,g_state_flow.Current(),pattern.direction,g_qsync_result,g_context_result,m5_balance,pattern,opened,
                   (opened ? "M5 scalp gates passed" : g_executor.LastError()));
   g_logger.Order("OPEN_M5",pattern.direction,lot,price,g_executor.LastRetcode(),
                  (opened ? "OK" : g_executor.LastError()),signal_id,g_basket_snapshot.basket_id);
   if(!opened)
     {
      g_basket.ClearRiskProfileOverrides();
      g_active_m5_profile=false;
      return;
     }
   g_last_m5_entry_bar=current_bar;
   g_basket_snapshot=g_basket.Refresh(g_features.atr);
   RememberBasketForAudit(g_basket_snapshot);
   g_basket_invalidation=pattern.invalidation_price;
   g_basket_entry_pattern=pattern.name;
   g_basket_entry_state=QBRStateToString(g_state_flow.Current());
   g_basket_entry_confidence=pattern.confidence;
   g_basket_entry_qsync=g_qsync_result.total;
   g_basket_entry_balance=m5_balance.score;
   SaveInvalidation();
   double stop=BasketCatastropheStop(g_basket_snapshot);
   if(g_executor.SetBasketStop(stop)>0)
     {
      CloseBasketWithReason("NATIVE_STOP_PLACEMENT_FAILED");
      g_paused=true;
      SavePaused();
      g_logger.Risk("EMERGENCY","Unable to place broker-native M5 basket stop",g_executor.LastError(),g_state_flow.Current(),g_basket_snapshot,g_features);
     }
  }

void UpdateDailySummary()
  {
   MqlDateTime t; TimeToStruct(TimeCurrent(),t); t.hour=0; t.min=0; t.sec=0;
   datetime today=StructToTime(t);
   if(g_last_daily_log==today) return;
   if(g_last_daily_log!=0)
     {
      double dd=100.0*QBRSafeDivide(g_equity_peak-AccountInfoDouble(ACCOUNT_EQUITY),g_equity_peak,0.0);
      g_logger.Daily(g_safety.DailyClosedProfit(),g_safety.WeeklyClosedProfit(),g_basket_snapshot,g_stats,dd);
     }
   g_last_daily_log=today;
  }

void RecoverLastEntryBar()
  {
   datetime bar_open=iTime(_Symbol,g_cfg.execution_tf,0);
   if(bar_open<=0 || !HistorySelect(bar_open,TimeCurrent())) return;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
     {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;
      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if((long)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=g_cfg.magic) continue;
      if(HistoryDealGetInteger(ticket,DEAL_ENTRY)==DEAL_ENTRY_IN)
        {
         g_last_entry_bar=bar_open;
         return;
        }
     }
  }

void RecoverM5RiskProfile()
  {
   g_active_m5_profile=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=g_cfg.magic) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT),"|M5_")>=0)
        {
         g_active_m5_profile=true;
         g_basket.SetRiskProfileOverrides(g_cfg.m5_target_pct,g_cfg.m5_hard_stop_pct);
         return;
        }
     }
   g_basket.ClearRiskProfileOverrides();
  }

int OnInit()
  {
   BuildConfig();
   g_sizer.Configure(_Symbol,g_cfg);
   string reason;
   if(!ValidateInputs(reason))
     {
      Print("QBR initialization rejected: ",reason);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(StringFind(_Symbol,"XAU")<0) Print("QBR warning: specification targets XAUUSD; current symbol is ",_Symbol);
   if(_Period!=PERIOD_M15) Print("QBR note: entries are evaluated on M15 regardless of chart timeframe.");
   if(InpAveragingAgainstMove) Print("QBR HIGH-RISK WARNING: AveragingAgainstMove is enabled; lots never increase and hard basket stop remains mandatory.");

   if(!g_indicators.Init(_Symbol,g_cfg)) return INIT_FAILED;
   if(g_cfg.enable_m5_scalp_layer)
     {
      g_m5_ema_handle=iMA(_Symbol,PERIOD_M5,g_cfg.ema_fast,0,MODE_EMA,PRICE_CLOSE);
      g_m5_atr_handle=iATR(_Symbol,PERIOD_M5,g_cfg.atr_period);
      if(g_m5_ema_handle==INVALID_HANDLE || g_m5_atr_handle==INVALID_HANDLE) return INIT_FAILED;
     }
   g_qsync.Configure(g_cfg);
   g_state_flow.Configure(g_cfg);
   g_context.Configure(g_cfg);
   g_pattern_reader.Configure(_Symbol,g_cfg);
   g_balance_finder.Configure(g_cfg);
   g_safety.Configure(_Symbol,g_cfg);
   g_entry_engine.Configure(g_cfg);
   g_basket.Configure(_Symbol,g_cfg);
   g_executor.Configure(_Symbol,g_cfg);
   if(!g_logger.Init(g_cfg.csv_logging,g_cfg.log_prefix,g_cfg.run_id,g_cfg.build_tag)) Print("QBR warning: CSV logging could not initialize completely.");
   g_dashboard.Init(g_cfg.dashboard_enabled,g_cfg.magic);

   LoadPersistentState();
   RecoverM5RiskProfile();
   g_equity_peak=g_safety.EquityPeak();
   g_last_bar_time=iTime(_Symbol,g_cfg.execution_tf,0);
   g_last_m5_bar_time=iTime(_Symbol,PERIOD_M5,0);
   RecoverLastEntryBar();
   if(g_indicators.BuildFeatures(g_features))
     {
      g_basket_snapshot=g_basket.Refresh(g_features.atr);
      RememberBasketForAudit(g_basket_snapshot);
      if(g_basket_snapshot.last_entry_time>=g_last_bar_time) g_last_entry_bar=g_last_bar_time;
      if(g_basket_snapshot.orders>0 && g_basket_invalidation<=0.0)
         g_basket_invalidation=(g_basket_snapshot.direction==QBR_DIR_LONG ? g_features.recent_swing_low : g_features.recent_swing_high);
      if(g_basket_snapshot.orders>0)
        {
         g_basket_entry_pattern="RECOVERED";
         g_basket_entry_state=QBRStateToString(g_state_flow.Current());
         g_basket_entry_confidence=0;
         g_basket_entry_qsync=g_qsync_result.total;
         g_basket_entry_balance=g_balance.score;
        }
     }
   EventSetTimer(1);
   Print("QuantumBehavioralReplica ",InpBuildTag," initialized. Independent behavioral implementation; proprietary fidelity unverified.");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_indicators.Shutdown();
   if(g_m5_ema_handle!=INVALID_HANDLE) IndicatorRelease(g_m5_ema_handle);
   if(g_m5_atr_handle!=INVALID_HANDLE) IndicatorRelease(g_m5_atr_handle);
   g_logger.Shutdown();
   g_dashboard.Shutdown();
  }

void OnTick()
  {
   RefreshLossStreakBlock();
   if(g_disable_until>0 && TimeCurrent()>=g_disable_until)
     {
      g_disable_until=0;
      GlobalVariableDel(PersistentKey("DISABLE_UNTIL"));
      g_paused=false;
      g_emergency_latched=false;
      SavePaused();
     }
   if(!g_indicators.BuildFeatures(g_features)) return;
   QBRBasketSnapshot prior_basket=g_basket_snapshot;
   RememberBasketForAudit(prior_basket);
   g_basket_snapshot=g_basket.Refresh(g_features.atr);
   RememberBasketForAudit(g_basket_snapshot);
   if(prior_basket.orders>0 && g_basket_snapshot.orders==0 &&
      prior_basket.basket_id!=g_last_finalized_basket_id)
     {
      QBRBasketSnapshot audit=prior_basket;
      if(g_basket_audit_snapshot.basket_id>0) audit=g_basket_audit_snapshot;
      if(!FinalizeClosedBasket(audit,TimeCurrent(),"UNOBSERVED_EXTERNAL_EXIT"))
         QueueBasketFinalization(audit,"UNOBSERVED_EXTERNAL_EXIT");
     }
   RetryPendingBasketFinalization();
   g_context_result=g_context.Evaluate(g_features,g_basket_snapshot,g_consecutive_basket_losses);
   if(g_context_result.fallback_used && !g_context_fallback_logged)
     {
      g_logger.Risk("WARNING",g_context_result.warning,"Use deterministic session/spike fallback",g_state_flow.Current(),g_basket_snapshot,g_features);
      g_context_fallback_logged=true;
     }
   g_qsync_result=g_qsync.Evaluate(g_features,g_context_result);
   g_pattern=g_pattern_reader.Evaluate(g_features,g_state_flow.Current());
   g_balance=g_balance_finder.Evaluate(g_features,g_qsync_result,g_pattern);

   bool new_bar=IsNewExecutionBar();
   bool new_m5_bar=IsNewM5Bar();

   string spike_reason;
   bool spike=g_safety.SpikeDetected(g_features,spike_reason);
   datetime spike_bar=iTime(_Symbol,g_cfg.execution_tf,0);
   // Edge-trigger cooldown once per M15 bar. The previous implementation reset
   // the full cooldown on every tick while a spike condition remained true.
   if(spike && spike_bar>0 && spike_bar!=g_last_spike_cooldown_bar)
     {
      g_cooldown_remaining=MathMax(g_cooldown_remaining,g_cfg.spike_cooldown_bars);
      g_last_spike_cooldown_bar=spike_bar;
      g_logger.Risk("MARKET_HAZARD",spike_reason,"Block new entries and start bounded cooldown",
                    g_state_flow.Current(),g_basket_snapshot,g_features);
     }
   QBRSafetyResult monitor_risk=g_safety.Monitor(g_features,g_basket_snapshot);
   if(monitor_risk.emergency) ExecuteEmergency(monitor_risk);
   ManageOpenBasket(monitor_risk,new_bar);

   if(new_bar) ProcessNewBar(monitor_risk,spike);
   if(new_m5_bar && g_basket_snapshot.orders==0) ProcessM5ScalpBar(monitor_risk,spike);

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_equity_peak=g_safety.EquityPeak();
   double dd=100.0*QBRSafeDivide(g_equity_peak-equity,g_equity_peak,0.0);
   g_stats=g_basket.PerformanceStats();
   g_stats.winning_baskets=g_completed_basket_wins;
   g_stats.losing_baskets=g_completed_basket_losses;
   g_stats.independent_signals=g_completed_basket_wins+g_completed_basket_losses;
   g_dashboard.Update(g_state_flow.Current(),g_features,g_qsync_result,g_context_result,g_balance,g_pattern,g_basket_snapshot,
                      g_stats,g_paused,g_deposit_baseline,dd,g_last_exit_rule,g_cfg.max_orders,g_cfg.initial_lot);
   UpdateDailySummary();
  }

void OnTimer()
  {
   if(g_emergency_confirm_time>0 && TimeCurrent()-g_emergency_confirm_time>10)
     {
      g_emergency_confirm_time=0;
      ObjectSetString(0,"QBR_EMERGENCY",OBJPROP_TEXT,"EMERGENCY CLOSE");
     }
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK) return;
   if(g_dashboard.IsButton(sparam,"CLOSE"))
     {
      CloseBasketWithReason("MANUAL_CLOSE_EA_BASKET");
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
     }
   else if(g_dashboard.IsButton(sparam,"PAUSE"))
     {
      g_paused=true; SavePaused();
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
     }
   else if(g_dashboard.IsButton(sparam,"RESUME"))
     {
      if(g_disable_until>TimeCurrent())
         g_logger.Risk("WARNING","Resume blocked until next day","Keep emergency disable active",g_state_flow.Current(),g_basket_snapshot,g_features);
      else
        {
         g_paused=false; g_emergency_latched=false; SavePaused();
         g_state_flow.Force(QBR_SCAN,"Manual resume");
        }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
     }
   else if(g_dashboard.IsButton(sparam,"EMERGENCY"))
     {
      if(g_emergency_confirm_time==0 || TimeCurrent()-g_emergency_confirm_time>10)
        {
         g_emergency_confirm_time=TimeCurrent();
         ObjectSetString(0,sparam,OBJPROP_TEXT,"CLICK AGAIN TO CONFIRM");
        }
      else
        {
         CloseBasketWithReason("MANUAL_EMERGENCY_CLOSE");
         g_paused=true; SavePaused();
         g_emergency_confirm_time=0;
         ObjectSetString(0,sparam,OBJPROP_TEXT,"EMERGENCY CLOSE");
        }
      ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
     }
   ChartRedraw();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol) return;
   if((long)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=g_cfg.magic) return;
   long deal_type=HistoryDealGetInteger(trans.deal,DEAL_TYPE);
   long entry=HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   QBRDirection direction=(deal_type==DEAL_TYPE_BUY ? QBR_DIR_LONG : QBR_DIR_SHORT);
   double gross=HistoryDealGetDouble(trans.deal,DEAL_PROFIT);
   double costs=HistoryDealGetDouble(trans.deal,DEAL_SWAP)+HistoryDealGetDouble(trans.deal,DEAL_COMMISSION)+HistoryDealGetDouble(trans.deal,DEAL_FEE);
   g_logger.Deal((datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME),trans.deal,
                 (long)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID),g_basket_snapshot.basket_id,
                 EnumToString((ENUM_DEAL_ENTRY)entry),direction,HistoryDealGetDouble(trans.deal,DEAL_VOLUME),
                 HistoryDealGetDouble(trans.deal,DEAL_PRICE),gross,costs,
                 EnumToString((ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal,DEAL_REASON)));
   string action=(entry==DEAL_ENTRY_IN ? "DEAL_ENTRY" : "DEAL_EXIT");
   g_logger.Order(action,direction,HistoryDealGetDouble(trans.deal,DEAL_VOLUME),HistoryDealGetDouble(trans.deal,DEAL_PRICE),
                  result.retcode,result.comment,"",g_basket_snapshot.basket_id);
   if(entry==DEAL_ENTRY_IN)
     {
      g_basket_snapshot=g_basket.Refresh(g_features.atr);
      RememberBasketForAudit(g_basket_snapshot);
      return;
     }
   if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT) return;
   QBRBasketSnapshot before=g_basket_snapshot;
   RememberBasketForAudit(before);
   QBRBasketSnapshot after=g_basket.Refresh(g_features.atr);
   g_basket_snapshot=after;
   if(after.orders==0 && before.orders>0)
     {
      QBRBasketSnapshot audit=before;
      if(g_basket_audit_snapshot.basket_id>0) audit=g_basket_audit_snapshot;
      string reason=ExitReasonFromDeal(trans.deal);
      if(!FinalizeClosedBasket(audit,(datetime)HistoryDealGetInteger(trans.deal,DEAL_TIME),reason))
         QueueBasketFinalization(audit,reason);
     }
  }

double OnTester()
  {
   double pf=TesterStatistics(STAT_PROFIT_FACTOR);
   double dd=TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   if(!MathIsValidNumber(pf)) pf=0.0;
   if(!MathIsValidNumber(dd)) dd=100.0;
   return pf/(1.0+dd/10.0);
  }
