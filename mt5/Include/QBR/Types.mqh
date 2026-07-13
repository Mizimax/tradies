#ifndef QBR_TYPES_MQH
#define QBR_TYPES_MQH

// QuantumBehavioralReplica is an independent behavioral implementation.
// It does not contain, derive from, or claim fidelity to proprietary source code.

enum QBRState
  {
   QBR_DISABLED=0,
   QBR_WARMUP,
   QBR_SCAN,
   QBR_BALANCED,
   QBR_TREND_UP,
   QBR_TREND_DOWN,
   QBR_BREAKOUT_UP,
   QBR_BREAKOUT_DOWN,
   QBR_HIGH_VOLATILITY,
   QBR_SPIKE,
   QBR_BASKET_LONG,
   QBR_BASKET_SHORT,
   QBR_COOLDOWN,
   QBR_DAILY_STOP,
   QBR_EMERGENCY
  };

enum QBRDirection
  {
   QBR_DIR_FLAT=0,
   QBR_DIR_LONG=1,
   QBR_DIR_SHORT=-1
  };

enum QBREntryMode
  {
   SINGLE_ENTRY=0,
   TREND_MULTI_ENTRY,
   ATR_SPACED_BASKET,
   RESEARCH_REPLICA
  };

enum QBRAddMode
  {
   ADD_ON_CONTINUATION=0,
   ADD_ON_PULLBACK,
   ADD_ON_BREAKOUT_RETEST
  };

enum QBRSizingMode
  {
   FIXED_LOT=0,
   RISK_PER_ORDER,
   RISK_PER_BASKET
  };

enum QBRBasketTargetMode
  {
   TARGET_FIXED_MONEY=0,
   TARGET_BALANCE_PERCENT,
   TARGET_EQUITY_PERCENT,
   TARGET_ATR_ADJUSTED,
   TARGET_PER_LOT
  };

enum QBREmergencyAction
  {
   EMERGENCY_STOP_NEW=0,
   EMERGENCY_CLOSE_PROFITABLE,
   EMERGENCY_CLOSE_BASKET,
   EMERGENCY_CLOSE_ALL_EA,
   EMERGENCY_DISABLE_UNTIL_NEXT_DAY,
   EMERGENCY_REQUIRE_MANUAL_RESUME
  };

enum QBRMarketClass
  {
   MARKET_STABLE_TREND=0,
   MARKET_TRADABLE_BREAKOUT,
   MARKET_CHOPPY_UNSTABLE,
   MARKET_EXTREME_VOLATILITY
  };

struct QBRConfig
  {
   long                  magic;
   ENUM_TIMEFRAMES       execution_tf;
   ENUM_TIMEFRAMES       higher_tf;
   int                   ema_fast;
   int                   ema_slow;
   int                   ema_daily;
   int                   atr_period;
   int                   adx_period;
   int                   rsi_period;
   int                   median_lookback;
   int                   swing_lookback;
   int                   breakout_lookback;
   int                   volume_lookback;
   double                trend_weight;
   double                momentum_weight;
   double                breakout_weight;
   double                volume_weight;
   double                context_weight;
   double                volatility_penalty_weight;
   double                spread_penalty_weight;
   double                conflict_penalty_weight;
   double                long_threshold;
   double                short_threshold;
   double                breakout_threshold;
   int                   min_pattern_confidence;
   bool                  allow_balanced_reentry;
   bool                  allow_trend_pullback_in_balanced;
   bool                  enable_trend_pullback;
   bool                  enable_failed_breakout;
   bool                  enable_breakout_retest;
   bool                  enable_reversal_rejection;
   bool                  enable_inside_bar_compression;
   bool                  require_trend_reentry;
   bool                  require_daily_alignment;
   double                max_entry_distance_ema_atr;
   double                max_rsi_long;
   double                min_rsi_short;
   double                min_balance_score;
   double                max_atr_ratio;
   double                extreme_atr_ratio;
   double                min_adx_trend;
   double                max_adx_balance;
   double                max_spread_points;
   double                max_spread_atr_ratio;
   double                min_free_margin;
   double                min_margin_level;
   double                max_total_lots;
   int                   max_orders;
   int                   max_orders_direction;
   double                max_basket_exposure_pct;
   double                max_daily_loss_pct;
   double                max_weekly_loss_pct;
   double                max_equity_drawdown_pct;
   double                max_floating_loss_pct;
   int                   max_consecutive_losses;
   int                   deviation_points;
   int                   cooldown_bars;
   int                   post_exit_cooldown_bars;
   int                   spike_cooldown_bars;
   int                   min_bars_between_orders;
   double                spike_current_range_atr;
   double                spike_previous_range_atr;
   double                spike_tick_jump_atr;
   double                spike_spread_multiplier;
   double                spike_gap_atr;
   double                spike_volume_ratio;
   double                initial_lot;
   double                lot_multiplier;
   bool                  fixed_lot;
   QBRSizingMode         sizing_mode;
   double                risk_per_order_pct;
   double                risk_per_basket_pct;
   bool                  allow_min_lot_with_native_risk_cap;
   QBREntryMode          entry_mode;
   QBRAddMode            add_mode;
   bool                  averaging_against_move;
   double                entry_spacing_atr;
   QBRBasketTargetMode   basket_target_mode;
   double                basket_target_value;
   double                basket_hard_stop_pct;
   double                max_loss_target_ratio;
   int                   basket_max_age_bars;
   bool                  exit_h4_swing_break;
   bool                  exit_qsync_reversal;
   bool                  exit_context_reversal;
   bool                  exit_pattern_invalidation;
   bool                  exit_invalidation_closed_bar;
   bool                  exit_end_session;
   double                profit_lock_trigger_fraction;
   double                profit_lock_floor_fraction;
   bool                  enable_m5_scalp_layer;
   double                m5_target_pct;
   double                m5_hard_stop_pct;
   bool                  allow_asian;
   bool                  allow_london;
   bool                  allow_new_york;
   int                   asian_start_hour;
   int                   asian_end_hour;
   int                   london_start_hour;
   int                   london_end_hour;
   int                   new_york_start_hour;
   int                   new_york_end_hour;
   int                   session_edge_minutes;
   int                   state_hysteresis_bars;
   int                   warmup_bars;
   int                   close_retry_count;
   QBREmergencyAction    emergency_action;
   bool                  dashboard_enabled;
   bool                  csv_logging;
   string                log_prefix;
   string                run_id;
   string                build_tag;
  };

struct QBRFeatures
  {
   datetime timestamp;
   double   close_price;
   double   open_price;
   double   high_price;
   double   low_price;
   double   ema_fast;
   double   ema_slow;
   double   ema_fast_prev;
   double   ema_h4_fast;
   double   ema_h4_slow;
   double   ema_daily_fast;
   double   ema_daily_slow;
   double   adx;
   double   di_plus;
   double   di_minus;
   double   rsi;
   double   atr;
   double   atr_median;
   double   atr_ratio;
   double   atr_percentile;
   double   body_range_ratio;
   double   breakout_distance;
   double   recent_swing_high;
   double   recent_swing_low;
   double   distance_swing;
   double   tick_volume;
   double   tick_volume_median;
   double   volume_ratio;
   double   momentum_1;
   double   momentum_3;
   double   momentum_5;
   double   session_high;
   double   session_low;
   double   distance_session_high;
   double   distance_session_low;
   double   daily_high;
   double   daily_low;
   double   h4_swing_high;
   double   h4_swing_low;
   double   spread_points;
   double   spread_price;
   double   spread_atr_ratio;
   double   previous_bar_range_atr;
   double   current_bar_range_atr;
   double   gap_atr;
   double   bar_range_variance;
   double   h4_atr_ratio;
   int      h4_bias;
   int      daily_bias;
   int      h4_structure;
   bool     data_ready;
  };

struct QBRQSyncResult
  {
   double trend_score;
   double momentum_score;
   double breakout_score;
   double volume_score;
   double context_score;
   double volatility_penalty;
   double spread_penalty;
   double conflict_penalty;
   double total;
  };

struct QBRContextResult
  {
   double h4_bias_score;
   double h4_structure_score;
   double daily_trend_score;
   double session_score;
   double session_edge_score;
   double spread_score;
   double atr_regime_score;
   double daily_location_score;
   double h4_location_score;
   double breakout_failure_score;
   double loss_streak_score;
   double exposure_score;
   double margin_score;
   double total;
   bool   fallback_used;
   string warning;
  };

struct QBRPatternSignal
  {
   bool              detected;
   QBRDirection      direction;
   int               confidence;
   double            invalidation_price;
   int               age_bars;
   ENUM_TIMEFRAMES   source_tf;
   string            name;
  };

struct QBRBalanceResult
  {
   double         score;
   QBRMarketClass market_class;
   bool           allow_entry;
   bool           breakout_override;
   string         reason;
  };

struct QBRSafetyResult
  {
   bool   allow;
   bool   emergency;
   string reason;
  };

struct QBREntryDecision
  {
   bool         allow;
   QBRDirection direction;
   string       reason;
   string       signal_id;
  };

struct QBRBasketSnapshot
  {
   long         basket_id;
   QBRDirection direction;
   int          orders;
   double       total_lots;
   double       weighted_average;
   double       floating_profit;
   double       realized_profit;
   double       target_money;
   double       hard_stop_money;
   datetime     start_time;
   int          age_bars;
   double       mfe;
   double       mae;
   double       margin_usage;
   double       last_entry_price;
   datetime     last_entry_time;
  };

struct QBRPerformanceStats
  {
   int    winning_orders;
   int    losing_orders;
   int    winning_baskets;
   int    losing_baskets;
   int    independent_signals;
   double gross_profit;
   double gross_loss;
   double average_winner;
   double average_loser;
   double largest_winner;
   double largest_loser;
   double profit_factor;
   double payoff_ratio;
   double wins_erased_by_average_loss;
   double small_wins_erased_by_largest_loss;
  };

string QBRStateToString(const QBRState state)
  {
   switch(state)
     {
      case QBR_DISABLED:          return "DISABLED";
      case QBR_WARMUP:            return "WARMUP";
      case QBR_SCAN:              return "SCAN";
      case QBR_BALANCED:          return "BALANCED";
      case QBR_TREND_UP:          return "TREND_UP";
      case QBR_TREND_DOWN:        return "TREND_DOWN";
      case QBR_BREAKOUT_UP:       return "BREAKOUT_UP";
      case QBR_BREAKOUT_DOWN:     return "BREAKOUT_DOWN";
      case QBR_HIGH_VOLATILITY:   return "HIGH_VOLATILITY";
      case QBR_SPIKE:             return "SPIKE";
      case QBR_BASKET_LONG:       return "BASKET_LONG";
      case QBR_BASKET_SHORT:      return "BASKET_SHORT";
      case QBR_COOLDOWN:          return "COOLDOWN";
      case QBR_DAILY_STOP:        return "DAILY_STOP";
      case QBR_EMERGENCY:         return "EMERGENCY";
     }
   return "UNKNOWN";
  }

string QBRDirectionToString(const QBRDirection direction)
  {
   if(direction==QBR_DIR_LONG)  return "LONG";
   if(direction==QBR_DIR_SHORT) return "SHORT";
   return "FLAT";
  }

double QBRClamp(const double value,const double min_value,const double max_value)
  {
   return MathMax(min_value,MathMin(max_value,value));
  }

double QBRNormalizeSigned(const double value,const double scale)
  {
   if(scale<=0.0) return 0.0;
   return QBRClamp(value/scale,-1.0,1.0);
  }

double QBRSafeDivide(const double numerator,const double denominator,const double fallback=0.0)
  {
   if(MathAbs(denominator)<1e-12) return fallback;
   return numerator/denominator;
  }

#endif
