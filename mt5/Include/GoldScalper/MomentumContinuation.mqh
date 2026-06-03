#ifndef GOLDSCALPER_MOMENTUM_CONTINUATION_MQH
#define GOLDSCALPER_MOMENTUM_CONTINUATION_MQH

//+------------------------------------------------------------------+
//| MomentumContinuation.mqh                                          |
//| GoldScalper — Momentum Continuation after Breakout TP             |
//|                                                                    |
//| Activates only when the Asian Breakout strategy has already hit    |
//| a TP today.  Looks for an M5 pullback to EMA with RSI in a        |
//| neutral zone, then enters in the breakout direction.               |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>

//--- Module-level indicator handles (created once in Init)
static int g_gsm_emaHandle   = INVALID_HANDLE;
static int g_gsm_rsiHandle   = INVALID_HANDLE;
static int g_gsm_atrHandle   = INVALID_HANDLE;

//--- Cached init parameters so we can recreate handles if symbol changes
static string g_gsm_symbol      = "";
static int    g_gsm_emaPeriod   = 0;
static int    g_gsm_rsiPeriod   = 0;

//+------------------------------------------------------------------+
//| Helper: build a date-stamped GlobalVariable key for today         |
//+------------------------------------------------------------------+
string GoldScalperMomDayKey(const string suffix)
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   return StringFormat("GoldScalper.%04d%02d%02d.%s", t.year, t.mon, t.day, suffix);
}

//+------------------------------------------------------------------+
//| Helper: read a single indicator buffer value                      |
//+------------------------------------------------------------------+
double GoldScalperMomBufValue(const int handle, const int buffer, const int shift)
{
   double values[];
   ArraySetAsSeries(values, true);
   if(CopyBuffer(handle, buffer, shift, 1, values) != 1)
      return EMPTY_VALUE;
   return values[0];
}

//+------------------------------------------------------------------+
//| Initialise indicator handles.                                     |
//| Call once from OnInit() of the EA. Pass the same symbol and       |
//| periods that GoldScalperMomentumSignal will use.                  |
//+------------------------------------------------------------------+
void GoldScalperMomentumInit(const string symbol,
                             const int pullbackEma = 9,
                             const int rsiPeriod   = 10)
{
   //--- Release any existing handles first
   GoldScalperMomentumDeinit();

   g_gsm_symbol    = symbol;
   g_gsm_emaPeriod = pullbackEma;
   g_gsm_rsiPeriod = rsiPeriod;

   g_gsm_emaHandle = iMA(symbol, PERIOD_M5, pullbackEma, 0, MODE_EMA, PRICE_CLOSE);
   if(g_gsm_emaHandle == INVALID_HANDLE)
      Print("[GoldScalper-Mom] ERROR: iMA handle creation failed for EMA(", pullbackEma, ")");

   g_gsm_rsiHandle = iRSI(symbol, PERIOD_M5, rsiPeriod, PRICE_CLOSE);
   if(g_gsm_rsiHandle == INVALID_HANDLE)
      Print("[GoldScalper-Mom] ERROR: iRSI handle creation failed for RSI(", rsiPeriod, ")");

   g_gsm_atrHandle = iATR(symbol, PERIOD_M5, 14);
   if(g_gsm_atrHandle == INVALID_HANDLE)
      Print("[GoldScalper-Mom] ERROR: iATR handle creation failed for ATR(14)");

   Print("[GoldScalper-Mom] Init OK  sym=", symbol,
         " ema=", pullbackEma, " rsi=", rsiPeriod,
         " emaH=", g_gsm_emaHandle,
         " rsiH=", g_gsm_rsiHandle,
         " atrH=", g_gsm_atrHandle);
}

//+------------------------------------------------------------------+
//| Release indicator handles.  Call from OnDeinit().                 |
//+------------------------------------------------------------------+
void GoldScalperMomentumDeinit()
{
   if(g_gsm_emaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_gsm_emaHandle);
      g_gsm_emaHandle = INVALID_HANDLE;
   }
   if(g_gsm_rsiHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_gsm_rsiHandle);
      g_gsm_rsiHandle = INVALID_HANDLE;
   }
   if(g_gsm_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_gsm_atrHandle);
      g_gsm_atrHandle = INVALID_HANDLE;
   }
   Print("[GoldScalper-Mom] Deinit — handles released");
}

//+------------------------------------------------------------------+
//| Mark that the Asian Breakout strategy hit a TP today.             |
//| direction: +1 = bullish breakout, -1 = bearish breakout.          |
//| Called by the main EA when a breakout trade hits TP.              |
//+------------------------------------------------------------------+
void GoldScalperMarkBreakoutTpHit(const int direction)
{
   string keyHit = GoldScalperMomDayKey("breakoutTpHit");
   string keyDir = GoldScalperMomDayKey("breakoutDir");

   GlobalVariableSet(keyHit, 1.0);
   GlobalVariableSet(keyDir, (double)direction);

   Print("[GoldScalper-Mom] Breakout TP hit marked  dir=", direction,
         " key=", keyHit);
}

//+------------------------------------------------------------------+
//| Internal: was breakout TP hit today, and in which direction?      |
//| Returns +1 / -1 / 0 (not hit).                                   |
//+------------------------------------------------------------------+
int GoldScalperBreakoutDirection()
{
   string keyHit = GoldScalperMomDayKey("breakoutTpHit");
   string keyDir = GoldScalperMomDayKey("breakoutDir");

   if(!GlobalVariableCheck(keyHit))
      return 0;
   if(GlobalVariableGet(keyHit) < 0.5)
      return 0;
   if(!GlobalVariableCheck(keyDir))
      return 0;

   int dir = (int)GlobalVariableGet(keyDir);
   return dir;
}

//+------------------------------------------------------------------+
//| Internal: check server-time session window                        |
//+------------------------------------------------------------------+
bool GoldScalperMomSessionAllowed(const int startHour, const int endHour)
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int s = MathMax(0, MathMin(23, startHour));
   int e = MathMax(0, MathMin(23, endHour));

   if(s == e)
      return true;
   if(s < e)
      return t.hour >= s && t.hour < e;
   return t.hour >= s || t.hour < e;   // wrap-around midnight
}

//+------------------------------------------------------------------+
//| Return number of momentum trades placed today.                    |
//| Tracked via a GlobalVariable counter incremented by Entry.        |
//+------------------------------------------------------------------+
int GoldScalperMomentumDailyCount()
{
   string key = GoldScalperMomDayKey("momTradeCount");
   if(!GlobalVariableCheck(key))
      return 0;
   return (int)GlobalVariableGet(key);
}

//+------------------------------------------------------------------+
//| Internal: increment daily momentum trade counter                  |
//+------------------------------------------------------------------+
void GoldScalperMomIncrementCount()
{
   string key = GoldScalperMomDayKey("momTradeCount");
   int current = GoldScalperMomentumDailyCount();
   GlobalVariableSet(key, (double)(current + 1));
}

//+------------------------------------------------------------------+
//| Signal generator.                                                  |
//| Returns: +1 BUY, -1 SELL, 0 no signal.                           |
//| Only triggers when breakout TP has been hit today.                |
//+------------------------------------------------------------------+
int GoldScalperMomentumSignal(const string symbol,
                              const int pullbackEma,
                              const int rsiPeriod,
                              const int rsiLow,
                              const int rsiHigh,
                              const int sessionStartHour,
                              const int sessionEndHour)
{
   //--- 1. Breakout TP bias (or EMA slope fallback if no breakout today)
   //    If breakout hit TP today: use that direction as trade bias.
   //    If no breakout today (or breakout disabled): use EMA slope as trend direction.
   //    This allows momentum to trade independently without requiring a breakout.
   int breakoutDir = GoldScalperBreakoutDirection();
   int trendDir = breakoutDir; // start with breakout direction
   if(trendDir == 0)
   {
      // Fallback: determine trend from EMA slope (2 bars ago vs 1 bar ago)
      double emaRecent[2];
      if(CopyBuffer(g_gsm_emaHandle, 0, 1, 2, emaRecent) == 2)
         trendDir = (emaRecent[0] > emaRecent[1]) ? 1 : -1; // emaRecent[0]=bar1, emaRecent[1]=bar2
      else
         return 0; // can't determine trend
   }

   //--- 2. Session filter
   if(!GoldScalperMomSessionAllowed(sessionStartHour, sessionEndHour))
      return 0;

   //--- 3. Ensure handles are valid (lazy re-init if symbol changed)
   if(g_gsm_emaHandle == INVALID_HANDLE || g_gsm_rsiHandle == INVALID_HANDLE ||
      g_gsm_atrHandle == INVALID_HANDLE ||
      g_gsm_symbol != symbol || g_gsm_emaPeriod != pullbackEma || g_gsm_rsiPeriod != rsiPeriod)
   {
      GoldScalperMomentumInit(symbol, pullbackEma, rsiPeriod);
      if(g_gsm_emaHandle == INVALID_HANDLE || g_gsm_rsiHandle == INVALID_HANDLE || g_gsm_atrHandle == INVALID_HANDLE)
         return 0;
   }

   //--- 4. Get last 10 M5 bars (shift 1 = completed bars)
   MqlRates m5[];
   ArraySetAsSeries(m5, true);
   if(CopyRates(symbol, PERIOD_M5, 1, 10, m5) < 10)
   {
      Print("[GoldScalper-Mom] Not enough M5 bars");
      return 0;
   }

   //--- 5. Read EMA, RSI, ATR for the most-recent completed bar (shift=1)
   double emaValue = GoldScalperMomBufValue(g_gsm_emaHandle, 0, 1);
   double rsiValue = GoldScalperMomBufValue(g_gsm_rsiHandle, 0, 1);
   double atrValue = GoldScalperMomBufValue(g_gsm_atrHandle, 0, 1);

   if(emaValue == EMPTY_VALUE || rsiValue == EMPTY_VALUE || atrValue == EMPTY_VALUE)
   {
      Print("[GoldScalper-Mom] Indicator read failed  ema=", emaValue,
            " rsi=", rsiValue, " atr=", atrValue);
      return 0;
   }

   //--- 6. RSI neutral zone check
   if(rsiValue < rsiLow || rsiValue > rsiHigh)
      return 0;

   //--- 7. Pullback proximity: close within 0.5×ATR of EMA
   double closePrice = m5[0].close;
   double distToEma  = MathAbs(closePrice - emaValue);
   if(distToEma > 0.5 * atrValue)
      return 0;

   //--- 8. Directional pullback logic
   if(trendDir > 0)  // bullish bias (breakout or EMA slope) → look for BUY
   {
      // Price should have been above EMA recently and pulled back to it
      bool wasAbove = false;
      for(int i = 1; i < 10; i++)
      {
         double prevEma = GoldScalperMomBufValue(g_gsm_emaHandle, 0, 1 + i);
         if(prevEma != EMPTY_VALUE && m5[i].close > prevEma)
         {
            wasAbove = true;
            break;
         }
      }
      if(!wasAbove)
         return 0;

      // Current bar touches EMA from above (close >= ema, or low dipped to ema)
      if(closePrice >= emaValue || m5[0].low <= emaValue)
      {
         Print("[GoldScalper-Mom] BUY signal  close=", closePrice,
               " ema=", emaValue, " rsi=", rsiValue,
               " atr=", atrValue, " dist=", distToEma);
         return 1;
      }
   }
   else if(trendDir < 0)  // bearish bias (breakout or EMA slope) → look for SELL
   {
      bool wasBelow = false;
      for(int i = 1; i < 10; i++)
      {
         double prevEma = GoldScalperMomBufValue(g_gsm_emaHandle, 0, 1 + i);
         if(prevEma != EMPTY_VALUE && m5[i].close < prevEma)
         {
            wasBelow = true;
            break;
         }
      }
      if(!wasBelow)
         return 0;

      if(closePrice <= emaValue || m5[0].high >= emaValue)
      {
         Print("[GoldScalper-Mom] SELL signal  close=", closePrice,
               " ema=", emaValue, " rsi=", rsiValue,
               " atr=", atrValue, " dist=", distToEma);
         return -1;
      }
   }

   return 0;
}

//+------------------------------------------------------------------+
//| Internal: find the next H1 structure level for TP                 |
//| For BUY  → nearest H1 swing high above entry                     |
//| For SELL → nearest H1 swing low below entry                      |
//+------------------------------------------------------------------+
double GoldScalperMomH1Target(const string symbol, const int signal, const double entry)
{
   MqlRates h1[];
   ArraySetAsSeries(h1, true);
   int copied = CopyRates(symbol, PERIOD_H1, 1, 48, h1);
   if(copied < 10)
      return 0.0;

   double target = 0.0;
   bool   found  = false;

   for(int i = 0; i < copied; i++)
   {
      double candidate = signal > 0 ? h1[i].high : h1[i].low;
      bool   valid     = signal > 0 ? candidate > entry : candidate < entry;
      if(!valid)
         continue;

      if(!found)
      {
         target = candidate;
         found  = true;
      }
      else
      {
         // closest structure level
         if(signal > 0 && candidate < target)
            target = candidate;
         else if(signal < 0 && candidate > target)
            target = candidate;
      }
   }

   return found ? target : 0.0;
}

//+------------------------------------------------------------------+
//| Normalise lot size to broker constraints.                         |
//+------------------------------------------------------------------+
double GoldScalperMomNormalizeLot(const string symbol, const double rawLot,
                                  const double minLot, const double maxLot)
{
   double step      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double brokerMin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double brokerMax = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0)
      step = 0.01;

   double low     = MathMax(minLot, brokerMin);
   double high    = MathMin(maxLot, brokerMax);
   double clamped = MathMax(low, MathMin(rawLot, high));
   return NormalizeDouble(MathRound(clamped / step) * step, 2);
}

//+------------------------------------------------------------------+
//| Place a market order for the momentum continuation trade.         |
//|                                                                    |
//| signal:   +1 BUY, -1 SELL                                        |
//| momRR:    reward-to-risk ratio for TP (default 2.0)               |
//| riskPct:  equity percentage to risk                               |
//| Returns true if the order was placed.                             |
//+------------------------------------------------------------------+
bool GoldScalperMomentumEntry(const string symbol,
                              const long magic,
                              CTrade &trade,
                              const int signal,
                              const double momRR,
                              const double riskPct,
                              const double minLot,
                              const double maxLot,
                              const int maxTrades)
{
   //--- Guard: valid signal
   if(signal == 0)
      return false;

   //--- Guard: daily limit
   int dailyCount = GoldScalperMomentumDailyCount();
   if(dailyCount >= maxTrades)
   {
      Print("[GoldScalper-Mom] Daily limit reached  count=", dailyCount,
            " max=", maxTrades);
      return false;
   }

   //--- Get last 5 completed M5 bars for SL computation
   MqlRates m5[];
   ArraySetAsSeries(m5, true);
   if(CopyRates(symbol, PERIOD_M5, 1, 5, m5) < 5)
   {
      Print("[GoldScalper-Mom] Not enough M5 bars for SL calc");
      return false;
   }

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.01;
   double buffer = point * 30.0;  // small SL buffer (~0.30 for gold)

   //--- Compute SL
   double sl = 0.0;
   if(signal > 0)
   {
      double lowestLow = m5[0].low;
      for(int i = 1; i < 5; i++)
         lowestLow = MathMin(lowestLow, m5[i].low);
      sl = lowestLow - buffer;
   }
   else
   {
      double highestHigh = m5[0].high;
      for(int i = 1; i < 5; i++)
         highestHigh = MathMax(highestHigh, m5[i].high);
      sl = highestHigh + buffer;
   }

   //--- Entry price
   double entry = signal > 0
                  ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                  : SymbolInfoDouble(symbol, SYMBOL_BID);

   double slDist = MathAbs(entry - sl);
   if(slDist <= 0.0)
   {
      Print("[GoldScalper-Mom] SL distance is zero — skipping");
      return false;
   }

   //--- TP: momRR × SL distance, or H1 structure level (whichever is nearer to entry)
   double rrTp = signal > 0 ? entry + momRR * slDist
                             : entry - momRR * slDist;
   double h1Target = GoldScalperMomH1Target(symbol, signal, entry);
   double tp = rrTp;
   if(h1Target > 0.0)
   {
      // Choose the closer of the two targets (be conservative)
      double h1Dist = MathAbs(h1Target - entry);
      double rrDist = MathAbs(rrTp - entry);
      if(h1Dist > 0.0 && h1Dist < rrDist)
         tp = h1Target;
   }

   //--- Position sizing: equity-percentage risk
   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskAmt  = equity * riskPct / 100.0;
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickVal  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickVal <= 0.0)
   {
      Print("[GoldScalper-Mom] Tick size/value invalid");
      return false;
   }
   double rawLot = riskAmt / ((slDist / tickSize) * tickVal);
   double lot    = GoldScalperMomNormalizeLot(symbol, rawLot, minLot, maxLot);

   if(lot <= 0.0)
   {
      Print("[GoldScalper-Mom] Lot calculation resulted in 0");
      return false;
   }

   //--- Place market order
   trade.SetExpertMagicNumber(magic);
   bool ok = false;
   string comment = StringFormat("GS_Mom_%s", (signal > 0 ? "BUY" : "SELL"));

   if(signal > 0)
      ok = trade.Buy(lot, symbol, entry, sl, tp, comment);
   else
      ok = trade.Sell(lot, symbol, entry, sl, tp, comment);

   if(ok)
   {
      GoldScalperMomIncrementCount();
      Print("[GoldScalper-Mom] Order placed  dir=", signal,
            " lot=", lot, " entry=", entry,
            " sl=", sl, " tp=", tp,
            " slDist=", slDist, " RR=", momRR,
            " h1Target=", h1Target,
            " ticket=", trade.ResultOrder());
   }
   else
   {
      Print("[GoldScalper-Mom] Order FAILED  dir=", signal,
            " lot=", lot, " entry=", entry,
            " sl=", sl, " tp=", tp,
            " retcode=", (int)trade.ResultRetcode(),
            " ", trade.ResultRetcodeDescription());
   }

   return ok;
}

#endif
