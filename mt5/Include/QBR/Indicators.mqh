#ifndef QBR_INDICATORS_MQH
#define QBR_INDICATORS_MQH

#include "Types.mqh"

class CIndicators
  {
private:
   string          m_symbol;
   QBRConfig       m_cfg;
   int             m_ema_fast_m15;
   int             m_ema_slow_m15;
   int             m_ema_fast_h4;
   int             m_ema_slow_h4;
   int             m_ema_fast_d1;
   int             m_ema_slow_d1;
   int             m_atr_m15;
   int             m_atr_h4;
   int             m_adx_m15;
   int             m_rsi_m15;

   bool CopyOne(const int handle,const int buffer,const int shift,double &value)
     {
      double data[1];
      if(handle==INVALID_HANDLE) return false;
      if(CopyBuffer(handle,buffer,shift,1,data)!=1) return false;
      value=data[0];
      return MathIsValidNumber(value);
     }

   double Median(double &values[],const int count)
     {
      if(count<=0) return 0.0;
      double work[];
      ArrayResize(work,count);
      for(int i=0;i<count;i++) work[i]=values[i];
      ArraySort(work);
      if((count%2)==1) return work[count/2];
      return 0.5*(work[count/2-1]+work[count/2]);
     }

   double PercentileRank(const double value,double &values[],const int count)
     {
      if(count<=0) return 0.0;
      int below=0;
      for(int i=0;i<count;i++) if(values[i]<=value) below++;
      return 100.0*(double)below/(double)count;
     }

   bool LoadRates(const ENUM_TIMEFRAMES tf,const int start_shift,const int count,MqlRates &rates[])
     {
      ArraySetAsSeries(rates,true);
      return (CopyRates(m_symbol,tf,start_shift,count,rates)==count);
     }

   void RangeStats(MqlRates &rates[],const int count,double &variance)
     {
      variance=0.0;
      if(count<2) return;
      double mean=0.0;
      for(int i=0;i<count;i++) mean+=(rates[i].high-rates[i].low);
      mean/=(double)count;
      for(int i=0;i<count;i++)
        {
         double d=(rates[i].high-rates[i].low)-mean;
         variance+=d*d;
        }
      variance/=(double)(count-1);
     }

   void RecentExtremes(MqlRates &rates[],const int count,double &highest,double &lowest)
     {
      highest=-DBL_MAX;
      lowest=DBL_MAX;
      for(int i=0;i<count;i++)
        {
         if(rates[i].high>highest) highest=rates[i].high;
         if(rates[i].low<lowest) lowest=rates[i].low;
        }
     }

   int ConfirmedH4Structure(MqlRates &rates[],double &latest_swing_high,double &latest_swing_low)
     {
      int count=ArraySize(rates);
      double recent_high=0.0,older_high=0.0,recent_low=0.0,older_low=0.0;
      int high_count=0,low_count=0;
      for(int i=2;i<count-2 && (high_count<2 || low_count<2);i++)
        {
         bool swing_high=(rates[i].high>rates[i-1].high && rates[i].high>rates[i-2].high &&
                          rates[i].high>=rates[i+1].high && rates[i].high>=rates[i+2].high);
         bool swing_low=(rates[i].low<rates[i-1].low && rates[i].low<rates[i-2].low &&
                         rates[i].low<=rates[i+1].low && rates[i].low<=rates[i+2].low);
         if(swing_high && high_count<2)
           {
            if(high_count==0) recent_high=rates[i].high; else older_high=rates[i].high;
            high_count++;
           }
         if(swing_low && low_count<2)
           {
            if(low_count==0) recent_low=rates[i].low; else older_low=rates[i].low;
            low_count++;
           }
        }
      if(high_count>0) latest_swing_high=recent_high;
      if(low_count>0) latest_swing_low=recent_low;
      if(high_count<2 || low_count<2) return 0;
      if(recent_high>older_high && recent_low>older_low) return 1;
      if(recent_high<older_high && recent_low<older_low) return -1;
      return 0;
     }

   bool SessionExtremes(const datetime now,double &session_high,double &session_low)
     {
      MqlDateTime t;
      TimeToStruct(now,t);
      t.hour=0; t.min=0; t.sec=0;
      datetime day_start=StructToTime(t);
      MqlRates rates[];
      datetime current_bar_open=iTime(m_symbol,m_cfg.execution_tf,0);
      datetime closed_data_end=(current_bar_open>day_start ? current_bar_open-1 : now);
      int copied=CopyRates(m_symbol,m_cfg.execution_tf,day_start,closed_data_end,rates);
      if(copied<=0) return false;
      session_high=-DBL_MAX;
      session_low=DBL_MAX;
      for(int i=0;i<copied;i++)
        {
         if(rates[i].high>session_high) session_high=rates[i].high;
         if(rates[i].low<session_low) session_low=rates[i].low;
        }
      return true;
     }

public:
   CIndicators(void)
     {
      m_ema_fast_m15=INVALID_HANDLE;
      m_ema_slow_m15=INVALID_HANDLE;
      m_ema_fast_h4=INVALID_HANDLE;
      m_ema_slow_h4=INVALID_HANDLE;
      m_ema_fast_d1=INVALID_HANDLE;
      m_ema_slow_d1=INVALID_HANDLE;
      m_atr_m15=INVALID_HANDLE;
      m_atr_h4=INVALID_HANDLE;
      m_adx_m15=INVALID_HANDLE;
      m_rsi_m15=INVALID_HANDLE;
     }

   bool Init(const string symbol,const QBRConfig &cfg)
     {
      m_symbol=symbol;
      m_cfg=cfg;
      m_ema_fast_m15=iMA(symbol,cfg.execution_tf,cfg.ema_fast,0,MODE_EMA,PRICE_CLOSE);
      m_ema_slow_m15=iMA(symbol,cfg.execution_tf,cfg.ema_slow,0,MODE_EMA,PRICE_CLOSE);
      m_ema_fast_h4=iMA(symbol,cfg.higher_tf,cfg.ema_fast,0,MODE_EMA,PRICE_CLOSE);
      m_ema_slow_h4=iMA(symbol,cfg.higher_tf,cfg.ema_slow,0,MODE_EMA,PRICE_CLOSE);
      m_ema_fast_d1=iMA(symbol,PERIOD_D1,cfg.ema_daily,0,MODE_EMA,PRICE_CLOSE);
      m_ema_slow_d1=iMA(symbol,PERIOD_D1,cfg.ema_slow,0,MODE_EMA,PRICE_CLOSE);
      m_atr_m15=iATR(symbol,cfg.execution_tf,cfg.atr_period);
      m_atr_h4=iATR(symbol,cfg.higher_tf,cfg.atr_period);
      m_adx_m15=iADX(symbol,cfg.execution_tf,cfg.adx_period);
      m_rsi_m15=iRSI(symbol,cfg.execution_tf,cfg.rsi_period,PRICE_CLOSE);
      return (m_ema_fast_m15!=INVALID_HANDLE && m_ema_slow_m15!=INVALID_HANDLE &&
              m_ema_fast_h4!=INVALID_HANDLE && m_ema_slow_h4!=INVALID_HANDLE &&
              m_atr_m15!=INVALID_HANDLE && m_adx_m15!=INVALID_HANDLE &&
              m_rsi_m15!=INVALID_HANDLE);
     }

   void Shutdown(void)
     {
      if(m_ema_fast_m15!=INVALID_HANDLE) IndicatorRelease(m_ema_fast_m15);
      if(m_ema_slow_m15!=INVALID_HANDLE) IndicatorRelease(m_ema_slow_m15);
      if(m_ema_fast_h4!=INVALID_HANDLE) IndicatorRelease(m_ema_fast_h4);
      if(m_ema_slow_h4!=INVALID_HANDLE) IndicatorRelease(m_ema_slow_h4);
      if(m_ema_fast_d1!=INVALID_HANDLE) IndicatorRelease(m_ema_fast_d1);
      if(m_ema_slow_d1!=INVALID_HANDLE) IndicatorRelease(m_ema_slow_d1);
      if(m_atr_m15!=INVALID_HANDLE) IndicatorRelease(m_atr_m15);
      if(m_atr_h4!=INVALID_HANDLE) IndicatorRelease(m_atr_h4);
      if(m_adx_m15!=INVALID_HANDLE) IndicatorRelease(m_adx_m15);
      if(m_rsi_m15!=INVALID_HANDLE) IndicatorRelease(m_rsi_m15);
     }

   bool IsWarm(const int bars_required) const
     {
      int bars=Bars(m_symbol,m_cfg.execution_tf);
      int h4bars=Bars(m_symbol,m_cfg.higher_tf);
      return (bars>=bars_required && h4bars>=MathMax(m_cfg.ema_slow,m_cfg.swing_lookback)+5);
     }

   bool BuildFeatures(QBRFeatures &f)
     {
      ZeroMemory(f);
      f.data_ready=false;
      MqlRates m15[];
      int need=(int)MathMax(MathMax((double)m_cfg.median_lookback,(double)m_cfg.breakout_lookback),(double)m_cfg.volume_lookback)+10;
      if(!LoadRates(m_cfg.execution_tf,0,need,m15)) return false;
      MqlRates h4[];
      int h4need=(int)MathMax((double)m_cfg.swing_lookback,(double)m_cfg.median_lookback)+10;
      if(!LoadRates(m_cfg.higher_tf,1,h4need,h4)) return false;
      MqlRates d1[];
      if(!LoadRates(PERIOD_D1,1,4,d1)) return false;

      f.timestamp=m15[1].time;
      f.open_price=m15[1].open;
      f.high_price=m15[1].high;
      f.low_price=m15[1].low;
      f.close_price=m15[1].close;

      if(!CopyOne(m_ema_fast_m15,0,1,f.ema_fast)) return false;
      if(!CopyOne(m_ema_slow_m15,0,1,f.ema_slow)) return false;
      if(!CopyOne(m_ema_fast_m15,0,2,f.ema_fast_prev)) return false;
      if(!CopyOne(m_ema_fast_h4,0,1,f.ema_h4_fast)) return false;
      if(!CopyOne(m_ema_slow_h4,0,1,f.ema_h4_slow)) return false;
      if(!CopyOne(m_ema_fast_d1,0,1,f.ema_daily_fast)) f.ema_daily_fast=d1[0].close;
      if(!CopyOne(m_ema_slow_d1,0,1,f.ema_daily_slow)) f.ema_daily_slow=d1[1].close;
      if(!CopyOne(m_atr_m15,0,1,f.atr) || f.atr<=0.0) return false;
      if(!CopyOne(m_adx_m15,0,1,f.adx)) return false;
      if(!CopyOne(m_adx_m15,1,1,f.di_plus)) return false;
      if(!CopyOne(m_adx_m15,2,1,f.di_minus)) return false;
      if(!CopyOne(m_rsi_m15,0,1,f.rsi)) return false;

      double atr_values[];
      ArrayResize(atr_values,m_cfg.median_lookback);
      if(CopyBuffer(m_atr_m15,0,1,m_cfg.median_lookback,atr_values)!=m_cfg.median_lookback) return false;
      f.atr_median=Median(atr_values,m_cfg.median_lookback);
      f.atr_ratio=QBRSafeDivide(f.atr,f.atr_median,1.0);
      f.atr_percentile=PercentileRank(f.atr,atr_values,m_cfg.median_lookback);

      double h4_atr=0.0;
      double h4_atrs[];
      ArrayResize(h4_atrs,m_cfg.median_lookback);
      if(CopyOne(m_atr_h4,0,1,h4_atr) && CopyBuffer(m_atr_h4,0,1,m_cfg.median_lookback,h4_atrs)==m_cfg.median_lookback)
         f.h4_atr_ratio=QBRSafeDivide(h4_atr,Median(h4_atrs,m_cfg.median_lookback),1.0);
      else
         f.h4_atr_ratio=1.0;

      double range=m15[1].high-m15[1].low;
      f.body_range_ratio=QBRSafeDivide(MathAbs(m15[1].close-m15[1].open),range,0.0);
      f.previous_bar_range_atr=QBRSafeDivide(m15[1].high-m15[1].low,f.atr,0.0);
      f.current_bar_range_atr=QBRSafeDivide(m15[0].high-m15[0].low,f.atr,0.0);
      f.gap_atr=QBRSafeDivide(MathAbs(m15[0].open-m15[1].close),f.atr,0.0);

      MqlRates breakout_rates[];
      ArrayResize(breakout_rates,m_cfg.breakout_lookback);
      for(int i=0;i<m_cfg.breakout_lookback;i++) breakout_rates[i]=m15[i+2];
      double recent_high,recent_low;
      RecentExtremes(breakout_rates,m_cfg.breakout_lookback,recent_high,recent_low);
      if(f.close_price>recent_high) f.breakout_distance=(f.close_price-recent_high)/f.atr;
      else if(f.close_price<recent_low) f.breakout_distance=(f.close_price-recent_low)/f.atr;
      else f.breakout_distance=0.0;

      MqlRates swing_rates[];
      ArrayResize(swing_rates,m_cfg.swing_lookback);
      for(int i=0;i<m_cfg.swing_lookback;i++) swing_rates[i]=m15[i+1];
      RecentExtremes(swing_rates,m_cfg.swing_lookback,f.recent_swing_high,f.recent_swing_low);
      double mid=0.5*(f.recent_swing_high+f.recent_swing_low);
      f.distance_swing=QBRSafeDivide(f.close_price-mid,f.atr,0.0);

      double volumes[];
      ArrayResize(volumes,m_cfg.volume_lookback);
      for(int i=0;i<m_cfg.volume_lookback;i++) volumes[i]=(double)m15[i+1].tick_volume;
      f.tick_volume=(double)m15[1].tick_volume;
      f.tick_volume_median=Median(volumes,m_cfg.volume_lookback);
      f.volume_ratio=QBRSafeDivide(f.tick_volume,f.tick_volume_median,1.0);

      f.momentum_1=QBRSafeDivide(m15[1].close-m15[2].close,f.atr,0.0);
      f.momentum_3=QBRSafeDivide(m15[1].close-m15[4].close,f.atr,0.0);
      f.momentum_5=QBRSafeDivide(m15[1].close-m15[6].close,f.atr,0.0);

      if(!SessionExtremes(TimeCurrent(),f.session_high,f.session_low))
        {
         f.session_high=f.recent_swing_high;
         f.session_low=f.recent_swing_low;
        }
      f.distance_session_high=QBRSafeDivide(f.session_high-f.close_price,f.atr,0.0);
      f.distance_session_low=QBRSafeDivide(f.close_price-f.session_low,f.atr,0.0);
      f.daily_high=f.session_high;
      f.daily_low=f.session_low;

      RecentExtremes(h4,m_cfg.swing_lookback,f.h4_swing_high,f.h4_swing_low);
      f.h4_bias=(f.ema_h4_fast>f.ema_h4_slow ? 1 : (f.ema_h4_fast<f.ema_h4_slow ? -1 : 0));
      f.daily_bias=(f.ema_daily_fast>f.ema_daily_slow ? 1 : (f.ema_daily_fast<f.ema_daily_slow ? -1 : 0));
      f.h4_structure=ConfirmedH4Structure(h4,f.h4_swing_high,f.h4_swing_low);

      MqlTick tick;
      if(!SymbolInfoTick(m_symbol,tick)) return false;
      double point=SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      f.spread_price=tick.ask-tick.bid;
      f.spread_points=QBRSafeDivide(f.spread_price,point,0.0);
      f.spread_atr_ratio=QBRSafeDivide(f.spread_price,f.atr,0.0);

      MqlRates variance_rates[];
      int variance_count=(int)MathMin(20.0,(double)(ArraySize(m15)-2));
      ArrayResize(variance_rates,variance_count);
      for(int i=0;i<variance_count;i++) variance_rates[i]=m15[i+1];
      RangeStats(variance_rates,variance_count,f.bar_range_variance);
      f.data_ready=true;
      return true;
     }
  };

#endif
