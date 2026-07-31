#ifndef PROPGUARD_ENGINES_MQH
#define PROPGUARD_ENGINES_MQH

//+------------------------------------------------------------------+
//| Engines.mqh -- Engine A (London ORB) + Engine B (NY continuation) |
//| Part of PropGuard EA. Both engines share the same geometry        |
//| parameters (breakout buffer, stop ATR mult, target R, vol band)   |
//| and only differ in their session window -- see the approved plan  |
//| §4 and mt5/backtests/PROPGUARD_DESIGN.md §2.                      |
//|                                                                    |
//| M15 signal bar, market order on bar CLOSE, one position at a time,|
//| hard SL attached at send, flat by session end. No pending orders, |
//| no ladders, no partials, no trailing -- a near-two-point           |
//| R-distribution minimizes variance for a given expectancy.          |
//+------------------------------------------------------------------+

struct PropGuardEngineSignal
  {
   bool     has_signal;
   int      direction;        // +1 long, -1 short
   double   entry_ref;        // reference close price that triggered the breakout
   double   sl;
   double   tp;
   double   stop_distance;
   double   range_high;
   double   range_low;
   double   range_width;
   double   vol_ratio;        // today's range / median of the lookback window
   string   reason;
  };

void PropGuardEmptySignal(PropGuardEngineSignal &s,const string reason)
  {
   s.has_signal=false;
   s.direction=0;
   s.entry_ref=0.0; s.sl=0.0; s.tp=0.0; s.stop_distance=0.0;
   s.range_high=0.0; s.range_low=0.0; s.range_width=0.0; s.vol_ratio=0.0;
   s.reason=reason;
  }

//--- Hour-range membership test, overnight-wrap aware (mirrors GoldScalperInHourRange).
bool PropGuardHourInRange(const int hour,const int startHour,const int endHour)
  {
   if(startHour==endHour) return true;
   if(startHour<endHour) return (hour>=startHour && hour<endHour);
   return (hour>=startHour || hour<endHour);
  }

//--- The server-time start of "today's" session window for a given hour range, evaluated
//--- relative to `now`. Handles overnight wrap (e.g. 23-07) by anchoring to the day the
//--- window STARTS on, not the day it ends on.
datetime PropGuardSessionWindowStart(const datetime now,const int startHour)
  {
   MqlDateTime t;
   TimeToStruct(now,t);
   t.hour=startHour; t.min=0; t.sec=0;
   datetime candidate=StructToTime(t);
   if(candidate>now)
      candidate-=86400;
   return candidate;
  }

//--- Builds the session high/low over closed M15 bars in [startHour, endHour) of the trading
//--- day containing `asOf` (the last closed bar's open time -- never the forming bar, to keep
//--- range-building deterministic and repaint-free in both backtest and live).
bool PropGuardBuildSessionRange(const string symbol,const ENUM_TIMEFRAMES tf,
                                 const datetime asOf,const int startHour,const int endHour,
                                 double &rangeHigh,double &rangeLow)
  {
   rangeHigh=0.0; rangeLow=0.0;
   datetime winStart=PropGuardSessionWindowStart(asOf,startHour);
   MqlDateTime ws; TimeToStruct(winStart,ws);
   ws.hour=endHour; ws.min=0; ws.sec=0;
   datetime winEnd=StructToTime(ws);
   if(winEnd<=winStart)
      winEnd+=86400;
   if(winEnd>asOf)
      winEnd=asOf;
   if(winEnd<=winStart)
      return false;

   int idxEnd=iBarShift(symbol,tf,winEnd,false);
   int idxStart=iBarShift(symbol,tf,winStart,false);
   if(idxEnd<0 || idxStart<0 || idxStart<idxEnd)
      return false;
   int count=idxStart-idxEnd+1;
   if(count<=0)
      return false;

   int hIdx=iHighest(symbol,tf,MODE_HIGH,count,idxEnd);
   int lIdx=iLowest(symbol,tf,MODE_LOW,count,idxEnd);
   if(hIdx<0 || lIdx<0)
      return false;

   rangeHigh=iHigh(symbol,tf,hIdx);
   rangeLow=iLow(symbol,tf,lIdx);
   return (rangeHigh>rangeLow);
  }

//--- Median of the session range over `lookbackDays` prior trading days (today excluded).
//--- Used by the volatility-band filter -- the cheapest available defence against regime
//--- change (PROPGUARD_DESIGN.md §3). Returns 0 if too few days have data (caller should
//--- treat that as "skip the filter", not "block every day").
double PropGuardSessionRangeMedian(const string symbol,const ENUM_TIMEFRAMES tf,
                                    const datetime asOf,const int startHour,const int endHour,
                                    const int lookbackDays)
  {
   double samples[];
   int found=0;
   ArrayResize(samples,lookbackDays);
   datetime cursor=asOf;
   for(int d=1; d<=lookbackDays*2 && found<lookbackDays; d++)
     {
      datetime dayAsOf=cursor-((datetime)d)*86400;
      double hi,lo;
      if(PropGuardBuildSessionRange(symbol,tf,dayAsOf,startHour,endHour,hi,lo))
        {
         samples[found]=hi-lo;
         found++;
        }
     }
   if(found==0)
      return 0.0;
   ArrayResize(samples,found);
   ArraySort(samples);
   int mid=found/2;
   if(found%2==1)
      return samples[mid];
   return (samples[mid-1]+samples[mid])/2.0;
  }

//--- Per-day, per-engine "already traded" latch -- one trade per engine per session,
//--- never a re-entry after a stop-out within the same window (PROPGUARD_DESIGN.md §3).
string PropGuardEngineTradedKey(const long magic,const datetime day_start,const string enginePrefix)
  {
   MqlDateTime t; TimeToStruct(day_start,t);
   return StringFormat("PropGuard.%I64d.%04d%02d%02d.%s.traded", magic, t.year, t.mon, t.day, enginePrefix);
  }

bool PropGuardEngineAlreadyTraded(const long magic,const datetime day_start,const string enginePrefix)
  {
   string key=PropGuardEngineTradedKey(magic,day_start,enginePrefix);
   return GlobalVariableCheck(key) && GlobalVariableGet(key)>0.5;
  }

void PropGuardMarkEngineTraded(const long magic,const datetime day_start,const string enginePrefix)
  {
   GlobalVariableSet(PropGuardEngineTradedKey(magic,day_start,enginePrefix),1.0);
  }

//--- The shared breakout core. `rangeStartHour`/`rangeEndHour` define the range window;
//--- `entryEndHour` is the last hour new entries are allowed (session-end flatten is a
//--- separate, always-on rule handled by Executor.mqh -- this only gates NEW entries).
PropGuardEngineSignal PropGuardEvaluateBreakout(const string symbol,const ENUM_TIMEFRAMES tf,
                                                 const long magic,const string enginePrefix,
                                                 const int rangeStartHour,const int rangeEndHour,
                                                 const int entryEndHour,
                                                 const double breakoutBufferAtr,
                                                 const double stopAtrMult,
                                                 const double targetR,
                                                 const double volBandLow,const double volBandHigh,
                                                 const int volLookbackDays,
                                                 const int atrHandle,
                                                 const datetime dayStart)
  {
   PropGuardEngineSignal sig;
   datetime lastClosed=iTime(symbol,tf,1);
   MqlDateTime t; TimeToStruct(lastClosed,t);

   if(PropGuardEngineAlreadyTraded(magic,dayStart,enginePrefix))
     { PropGuardEmptySignal(sig,"already_traded_today"); return sig; }

   if(!PropGuardHourInRange(t.hour,rangeEndHour,entryEndHour))
     { PropGuardEmptySignal(sig,"outside_entry_window"); return sig; }

   double rangeHigh,rangeLow;
   if(!PropGuardBuildSessionRange(symbol,tf,lastClosed,rangeStartHour,rangeEndHour,rangeHigh,rangeLow))
     { PropGuardEmptySignal(sig,"range_unavailable"); return sig; }
   double rangeWidth=rangeHigh-rangeLow;
   if(rangeWidth<=0.0)
     { PropGuardEmptySignal(sig,"degenerate_range"); return sig; }

   double median=PropGuardSessionRangeMedian(symbol,tf,lastClosed,rangeStartHour,rangeEndHour,volLookbackDays);
   double volRatio=(median>0.0) ? rangeWidth/median : 1.0;
   if(median>0.0 && (volRatio<volBandLow || volRatio>volBandHigh))
     { PropGuardEmptySignal(sig,StringFormat("vol_band_reject ratio=%.3f",volRatio)); return sig; }

   double atrBuf[];
   ArraySetAsSeries(atrBuf,true);
   if(atrHandle==INVALID_HANDLE || CopyBuffer(atrHandle,0,1,1,atrBuf)!=1 || atrBuf[0]<=0.0)
     { PropGuardEmptySignal(sig,"atr_unavailable"); return sig; }
   double atr=atrBuf[0];

   double close1=iClose(symbol,tf,1);
   double buf=breakoutBufferAtr*atr;
   int direction=0;
   if(close1>rangeHigh+buf)
      direction=1;
   else if(close1<rangeLow-buf)
      direction=-1;

   if(direction==0)
     { PropGuardEmptySignal(sig,"no_breakout"); return sig; }

   double stopFromAtr=stopAtrMult*atr;
   double stopDistance;
   double sl;
   if(direction==1)
     {
      double stopFromRange=close1-rangeLow;
      stopDistance=MathMin(stopFromRange,stopFromAtr);
      if(stopDistance<=0.0) stopDistance=stopFromAtr;
      sl=close1-stopDistance;
     }
   else
     {
      double stopFromRange=rangeHigh-close1;
      stopDistance=MathMin(stopFromRange,stopFromAtr);
      if(stopDistance<=0.0) stopDistance=stopFromAtr;
      sl=close1+stopDistance;
     }

   double tp=(direction==1) ? close1+stopDistance*targetR : close1-stopDistance*targetR;

   sig.has_signal=true;
   sig.direction=direction;
   sig.entry_ref=close1;
   sig.sl=sl;
   sig.tp=tp;
   sig.stop_distance=stopDistance;
   sig.range_high=rangeHigh;
   sig.range_low=rangeLow;
   sig.range_width=rangeWidth;
   sig.vol_ratio=volRatio;
   sig.reason="breakout";
   return sig;
  }

//--- Engine A: London opening-range breakout (primary). Range built over the Asian session;
//--- entries fire from the London open through InpLondonEndHour.
PropGuardEngineSignal PropGuardEngineALondonSignal(const string symbol,const ENUM_TIMEFRAMES tf,
                                                    const long magic,
                                                    const int asianStartHour,const int asianEndHour,
                                                    const int londonEndHour,
                                                    const double breakoutBufferAtr,const double stopAtrMult,
                                                    const double targetR,
                                                    const double volBandLow,const double volBandHigh,
                                                    const int volLookbackDays,
                                                    const int atrHandle,const datetime dayStart)
  {
   return PropGuardEvaluateBreakout(symbol,tf,magic,"london",
                                     asianStartHour,asianEndHour,londonEndHour,
                                     breakoutBufferAtr,stopAtrMult,targetR,
                                     volBandLow,volBandHigh,volLookbackDays,
                                     atrHandle,dayStart);
  }

//--- Engine B: NY-session continuation. Same shared geometry as Engine A; only the session
//--- window differs (the mechanism that buys trade frequency without raising per-trade risk
//--- -- see the approved plan §4 "Why Engine B exists").
//---
//--- Three distinct times, not to be conflated: `nyRangeHours` (fixed rule, e.g. 3h) sets
//--- where the range ends and the entry window starts; `nyEntryWindowHours` (frozen search
//--- param #8) sets how long NEW entries are allowed; `nyFlatHour` (fixed rule, e.g. 20:00,
//--- passed separately to the Executor as the position's flatten time) is when an ALREADY
//--- OPEN position gets force-closed and is always later than the entry window's end.
PropGuardEngineSignal PropGuardEngineBNySignal(const string symbol,const ENUM_TIMEFRAMES tf,
                                                const long magic,
                                                const int nyRangeStartHour,const double nyRangeHours,
                                                const double nyEntryWindowHours,
                                                const double breakoutBufferAtr,const double stopAtrMult,
                                                const double targetR,
                                                const double volBandLow,const double volBandHigh,
                                                const int volLookbackDays,
                                                const int atrHandle,const datetime dayStart)
  {
   int rangeEndHour=(nyRangeStartHour+(int)MathRound(nyRangeHours))%24;
   int entryEndHour=(rangeEndHour+(int)MathRound(nyEntryWindowHours))%24;
   return PropGuardEvaluateBreakout(symbol,tf,magic,"ny",
                                     nyRangeStartHour,rangeEndHour,entryEndHour,
                                     breakoutBufferAtr,stopAtrMult,targetR,
                                     volBandLow,volBandHigh,volLookbackDays,
                                     atrHandle,dayStart);
  }

#endif
