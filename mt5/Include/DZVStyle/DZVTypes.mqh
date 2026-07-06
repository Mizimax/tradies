#ifndef DZV_STYLE_TYPES_MQH
#define DZV_STYLE_TYPES_MQH

#define DZV_ZONE_COUNT 7
#define DZV_MAX_TF_COUNT 7

enum ENUM_DZV_ADR_MODE
{
   DZV_ADR_HIGH_LOW = 0,
   DZV_ADR_TRUE_RANGE = 1,
   DZV_ADR_DIRECTIONAL_EXCURSION = 2
};

enum ENUM_DZV_ZONE_BASE
{
   DZV_BASE_CURRENT_DAILY_OPEN = 0,
   DZV_BASE_PREVIOUS_DAILY_CLOSE = 1,
   DZV_BASE_PREVIOUS_DAILY_MIDPOINT = 2,
   DZV_BASE_PREVIOUS_TYPICAL_PRICE = 3
};

enum ENUM_DZV_SYSTEM_MODE
{
   DZV_MODE_INDICATOR_ONLY = 0,
   DZV_MODE_SIGNAL_ONLY = 1,
   DZV_MODE_SIMULATED_TRADING = 2,
   DZV_MODE_LIVE_TRADING = 3
};

enum ENUM_DZV_SIGNAL_MODULE
{
   DZV_SIGNAL_REJECTION = 0,
   DZV_SIGNAL_BREAKOUT = 1,
   DZV_SIGNAL_BOTH = 2
};

enum ENUM_DZV_DIRECTION
{
   DZV_DIR_NONE = 0,
   DZV_DIR_LONG = 1,
   DZV_DIR_SHORT = -1
};

enum ENUM_DZV_TREND_STATE
{
   DZV_TREND_UNAVAILABLE = -1,
   DZV_TREND_SIDEWAY = 0,
   DZV_TREND_UP = 1,
   DZV_TREND_DOWN = -1
};

enum ENUM_DZV_STOP_MODE
{
   DZV_STOP_BEYOND_SIGNAL_CANDLE = 0,
   DZV_STOP_BEYOND_SIGNAL_ZONE = 1,
   DZV_STOP_AT_NEXT_OUTER_ZONE = 2,
   DZV_STOP_VOLATILITY_DISTANCE = 3
};

enum ENUM_DZV_TARGET_MODE
{
   DZV_TARGET_BASE_PRICE = 0,
   DZV_TARGET_NEXT_INNER_ZONE = 1,
   DZV_TARGET_NEXT_OUTER_ZONE = 2,
   DZV_TARGET_SELECTED_ZONE = 3,
   DZV_TARGET_RISK_REWARD = 4
};

enum ENUM_DZV_LOT_MODE
{
   DZV_LOT_FIXED = 0,
   DZV_LOT_RISK_PERCENT = 1
};

struct DZVDailyZoneSet
{
   datetime day_start;
   double base_price;
   double adr;
   double average_upper_excursion;
   double average_lower_excursion;
   double upper[DZV_ZONE_COUNT];
   double lower[DZV_ZONE_COUNT];
   bool valid;
   string error;
};

struct DZVIndicatorSnapshot
{
   ENUM_TIMEFRAMES timeframe;
   bool ready;
   datetime candle_time;
   double close;
   double ema50;
   double rsi;
   double stoch_k;
   double stoch_d;
   ENUM_DZV_TREND_STATE trend;
   string status;
};

struct DZVSignal
{
   bool valid;
   ENUM_DZV_DIRECTION direction;
   ENUM_DZV_SIGNAL_MODULE module;
   int zone_index;
   datetime broker_day;
   datetime candle_time;
   double zone_price;
   double entry_price;
   double stop_loss;
   double take_profit;
   double risk_points;
   string id;
   string reason;
};

struct DZVSimTrade
{
   bool open;
   string signal_id;
   datetime entry_time;
   double entry_price;
   ENUM_DZV_DIRECTION direction;
   int zone_index;
   double stop_loss;
   double take_profit;
   double mfe_points;
   double mae_points;
};

struct DZVZoneBandOrder
{
   bool pending;
   bool open;
   string id;
   datetime day_start;
   ENUM_DZV_DIRECTION direction;
   int zone_index;
   int edge_index;
   double entry_price;
   double stop_loss;
   double take_profit;
   double mfe_points;
   double mae_points;
};

string DZVAdrModeName(const ENUM_DZV_ADR_MODE mode)
{
   if(mode == DZV_ADR_TRUE_RANGE)
      return "ADR_TRUE_RANGE";
   if(mode == DZV_ADR_DIRECTIONAL_EXCURSION)
      return "ADR_DIRECTIONAL_EXCURSION";
   return "ADR_HIGH_LOW";
}

string DZVBaseModeName(const ENUM_DZV_ZONE_BASE mode)
{
   if(mode == DZV_BASE_PREVIOUS_DAILY_CLOSE)
      return "PREVIOUS_DAILY_CLOSE";
   if(mode == DZV_BASE_PREVIOUS_DAILY_MIDPOINT)
      return "PREVIOUS_DAILY_MIDPOINT";
   if(mode == DZV_BASE_PREVIOUS_TYPICAL_PRICE)
      return "PREVIOUS_TYPICAL_PRICE";
   return "CURRENT_DAILY_OPEN";
}

string DZVTimeframeName(const ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_M1)
      return "M1";
   if(tf == PERIOD_M5)
      return "M5";
   if(tf == PERIOD_M15)
      return "M15";
   if(tf == PERIOD_M30)
      return "M30";
   if(tf == PERIOD_H1)
      return "H1";
   if(tf == PERIOD_H4)
      return "H4";
   if(tf == PERIOD_D1)
      return "D1";
   return EnumToString(tf);
}

string DZVDirectionName(const ENUM_DZV_DIRECTION direction)
{
   if(direction == DZV_DIR_LONG)
      return "long";
   if(direction == DZV_DIR_SHORT)
      return "short";
   return "none";
}

string DZVModuleName(const ENUM_DZV_SIGNAL_MODULE module)
{
   if(module == DZV_SIGNAL_BREAKOUT)
      return "breakout";
   if(module == DZV_SIGNAL_BOTH)
      return "both";
   return "rejection";
}

double DZVNormalizePrice(const string symbol, const double price)
{
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(tickSize <= 0.0)
      return NormalizeDouble(price, digits);
   return NormalizeDouble(MathRound(price / tickSize) * tickSize, digits);
}

double DZVNormalizeVolume(const string symbol, const double rawVolume, const double minLot, const double maxLot)
{
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double brokerMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double brokerMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      step = 0.01;

   double low = MathMax(minLot, brokerMin);
   double high = MathMin(maxLot, brokerMax);
   if(high < low)
      return 0.0;

   double clamped = MathMax(low, MathMin(rawVolume, high));
   int precision = 2;
   if(step < 0.01)
      precision = 3;
   if(step < 0.001)
      precision = 4;
   return NormalizeDouble(MathFloor(clamped / step) * step, precision);
}

datetime DZVDayStart(const string symbol)
{
   MqlRates d1[];
   ArraySetAsSeries(d1, true);
   if(CopyRates(symbol, PERIOD_D1, 0, 1, d1) != 1)
      return 0;
   return d1[0].time;
}

bool DZVIsSunday(const datetime timeValue)
{
   MqlDateTime parts;
   TimeToStruct(timeValue, parts);
   return parts.day_of_week == 0;
}

bool DZVIsNewCompletedBar(const string symbol, const ENUM_TIMEFRAMES timeframe, datetime &lastCompletedBar)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(symbol, timeframe, 1, 1, rates) != 1)
      return false;
   if(rates[0].time == lastCompletedBar)
      return false;
   lastCompletedBar = rates[0].time;
   return true;
}

string DZVGlobalPrefix(const string symbol, const long magic)
{
   return StringFormat("DZVStyle.%s.%I64d", symbol, magic);
}

#endif
