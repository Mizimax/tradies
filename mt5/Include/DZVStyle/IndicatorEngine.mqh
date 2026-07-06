#ifndef DZV_STYLE_INDICATOR_ENGINE_MQH
#define DZV_STYLE_INDICATOR_ENGINE_MQH

#include <DZVStyle/DZVTypes.mqh>

struct DZVIndicatorHandles
{
   string symbol;
   int count;
   ENUM_TIMEFRAMES timeframes[DZV_MAX_TF_COUNT];
   int ema_handle[DZV_MAX_TF_COUNT];
   int rsi_handle[DZV_MAX_TF_COUNT];
   int stoch_handle[DZV_MAX_TF_COUNT];
};

bool DZVBufferValue(const int handle, const int buffer, const int shift, double &value)
{
   value = EMPTY_VALUE;
   if(handle == INVALID_HANDLE)
      return false;
   if(BarsCalculated(handle) <= shift)
      return false;
   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1)
      return false;
   value = values[0];
   return value != EMPTY_VALUE;
}

void DZVIndicatorHandlesReset(DZVIndicatorHandles &handles)
{
   handles.symbol = "";
   handles.count = 0;
   for(int i = 0; i < DZV_MAX_TF_COUNT; i++)
   {
      handles.timeframes[i] = PERIOD_CURRENT;
      handles.ema_handle[i] = INVALID_HANDLE;
      handles.rsi_handle[i] = INVALID_HANDLE;
      handles.stoch_handle[i] = INVALID_HANDLE;
   }
}

bool DZVIndicatorHandlesInit(DZVIndicatorHandles &handles,
                             const string symbol,
                             const ENUM_TIMEFRAMES &timeframes[],
                             const int timeframeCount,
                             const int emaPeriod,
                             const int rsiPeriod,
                             const int stochK,
                             const int stochD,
                             const int stochSlowing)
{
   DZVIndicatorHandlesReset(handles);
   handles.symbol = symbol;
   handles.count = MathMin(timeframeCount, DZV_MAX_TF_COUNT);
   if(handles.count <= 0)
      return false;

   for(int i = 0; i < handles.count; i++)
   {
      handles.timeframes[i] = timeframes[i];
      handles.ema_handle[i] = iMA(symbol, timeframes[i], emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      handles.rsi_handle[i] = iRSI(symbol, timeframes[i], rsiPeriod, PRICE_CLOSE);
      handles.stoch_handle[i] = iStochastic(symbol, timeframes[i], stochK, stochD, stochSlowing, MODE_SMA, STO_LOWHIGH);
      if(handles.ema_handle[i] == INVALID_HANDLE ||
         handles.rsi_handle[i] == INVALID_HANDLE ||
         handles.stoch_handle[i] == INVALID_HANDLE)
      {
         Print("DZVStyle: indicator handle init failed for ", symbol, " ", DZVTimeframeName(timeframes[i]));
         return false;
      }
   }
   return true;
}

void DZVIndicatorHandlesRelease(DZVIndicatorHandles &handles)
{
   for(int i = 0; i < handles.count; i++)
   {
      if(handles.ema_handle[i] != INVALID_HANDLE)
         IndicatorRelease(handles.ema_handle[i]);
      if(handles.rsi_handle[i] != INVALID_HANDLE)
         IndicatorRelease(handles.rsi_handle[i]);
      if(handles.stoch_handle[i] != INVALID_HANDLE)
         IndicatorRelease(handles.stoch_handle[i]);
      handles.ema_handle[i] = INVALID_HANDLE;
      handles.rsi_handle[i] = INVALID_HANDLE;
      handles.stoch_handle[i] = INVALID_HANDLE;
   }
   handles.count = 0;
}

int DZVFindTimeframeIndex(const DZVIndicatorHandles &handles, const ENUM_TIMEFRAMES timeframe)
{
   for(int i = 0; i < handles.count; i++)
   {
      if(handles.timeframes[i] == timeframe)
         return i;
   }
   return -1;
}

bool DZVIndicatorSnapshotAt(const DZVIndicatorHandles &handles,
                            const int index,
                            const double rsiSidewaysLower,
                            const double rsiSidewaysUpper,
                            DZVIndicatorSnapshot &snapshot)
{
   snapshot.ready = false;
   snapshot.timeframe = PERIOD_CURRENT;
   snapshot.candle_time = 0;
   snapshot.close = EMPTY_VALUE;
   snapshot.ema50 = EMPTY_VALUE;
   snapshot.rsi = EMPTY_VALUE;
   snapshot.stoch_k = EMPTY_VALUE;
   snapshot.stoch_d = EMPTY_VALUE;
   snapshot.trend = DZV_TREND_UNAVAILABLE;
   snapshot.status = "not_ready";

   if(index < 0 || index >= handles.count)
   {
      snapshot.status = "invalid_index";
      return false;
   }

   ENUM_TIMEFRAMES timeframe = handles.timeframes[index];
   snapshot.timeframe = timeframe;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(handles.symbol, timeframe, 1, 1, rates) != 1)
   {
      snapshot.status = "rates_unavailable";
      return false;
   }

   double ema = EMPTY_VALUE;
   double rsi = EMPTY_VALUE;
   double k = EMPTY_VALUE;
   double d = EMPTY_VALUE;
   if(!DZVBufferValue(handles.ema_handle[index], 0, 1, ema) ||
      !DZVBufferValue(handles.rsi_handle[index], 0, 1, rsi) ||
      !DZVBufferValue(handles.stoch_handle[index], 0, 1, k) ||
      !DZVBufferValue(handles.stoch_handle[index], 1, 1, d))
   {
      snapshot.status = "buffers_unavailable";
      return false;
   }

   snapshot.ready = true;
   snapshot.candle_time = rates[0].time;
   snapshot.close = rates[0].close;
   snapshot.ema50 = ema;
   snapshot.rsi = rsi;
   snapshot.stoch_k = k;
   snapshot.stoch_d = d;
   snapshot.status = "ready";

   if(rsi >= rsiSidewaysLower && rsi <= rsiSidewaysUpper)
      snapshot.trend = DZV_TREND_SIDEWAY;
   else if(rates[0].close > ema)
      snapshot.trend = DZV_TREND_UP;
   else if(rates[0].close < ema)
      snapshot.trend = DZV_TREND_DOWN;
   else
      snapshot.trend = DZV_TREND_SIDEWAY;

   return true;
}

bool DZVIndicatorSnapshotForTf(const DZVIndicatorHandles &handles,
                               const ENUM_TIMEFRAMES timeframe,
                               const double rsiSidewaysLower,
                               const double rsiSidewaysUpper,
                               DZVIndicatorSnapshot &snapshot)
{
   int index = DZVFindTimeframeIndex(handles, timeframe);
   if(index < 0)
   {
      snapshot.ready = false;
      snapshot.status = "timeframe_not_initialized";
      return false;
   }
   return DZVIndicatorSnapshotAt(handles, index, rsiSidewaysLower, rsiSidewaysUpper, snapshot);
}

#endif
