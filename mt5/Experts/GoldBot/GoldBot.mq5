#property strict
#property version   "3.00"
#property description "Gold XAU/USD SMC + confluence Expert Advisor"

#include <Trade/Trade.mqh>
#include <GoldBot/Indicators.mqh>
#include <GoldBot/SMC.mqh>
#include <GoldBot/Risk.mqh>
#include <GoldBot/TradeManager.mqh>

input string          InpSymbol = "XAUUSD";
input long            InpMagicNumber = 26053101;
input GoldBotRiskMode InpRiskMode = EQUITY_LOT_RATIO;
input double          InpLotPer100Usd = 0.01;
input double          InpMinLot = 0.01;
input double          InpMaxLot = 5.0;
input double          InpScoreThreshold = 75.0;
input double          InpHighConvictionScore = 88.0;
input int             InpRsiPeriod = 10;
input double          InpRsiLongMax = 38.0;
input double          InpRsiShortMin = 40.0;
input double          InpAdxMin = 14.0;
input double          InpAtrMin = 1.0;
input double          InpAtrMax = 35.0;
input double          InpSlAtr = 0.8;
input double          InpMinRR = 2.0;
input int             InpMaxHoldBars = 48;
input int             InpCooldownBars = 16;
input int             InpMaxOpenTrades = 2;
input double          InpMaxDailyLossPct = 3.0;
input double          InpDailyTargetPct = 5.0;
input bool            InpEnableTelegram = false;
input bool            InpDebugOnly = false;
input bool            InpLegacyParityMode = true;

CTrade trade;
datetime lastM15Bar = 0;

GoldBotDirection GoldBotLegacySignalDirection(const string symbol, const IndicatorSnapshot &indicators);
EntryZone GoldBotLegacyEntryZone(const string symbol, const GoldBotDirection direction);
bool GoldBotPlaceLegacyMarket(const string symbol, const long magic, const GoldBotDirection direction, const double sl, const double atrValue, const double score);

int OnInit()
{
   string symbol = GoldBotSymbol();
   if(!SymbolSelect(symbol, true))
   {
      Print("GoldBot: unable to select symbol ", symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   Print("GoldBot initialized for ", symbol, " magic=", InpMagicNumber);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   string symbol = GoldBotSymbol();
   if(!GoldBotIsNewM15Bar(symbol))
   {
      GoldBotManagePositions(symbol, InpMagicNumber, MathMax(GoldBotATR(symbol, PERIOD_H1, 14, 1), 0.0), trade);
      return;
   }

   GoldBotExpirePendingOrders(symbol, InpMagicNumber, trade);
   GoldBotCancelPendingOnStopBreach(symbol, InpMagicNumber, trade);
   GoldBotManagePositions(symbol, InpMagicNumber, MathMax(GoldBotATR(symbol, PERIOD_H1, 14, 1), 0.0), trade);

   double pnlPct = 0.0;
   if(!GoldBotDailyRiskAllowed(InpMaxDailyLossPct, InpDailyTargetPct, pnlPct))
   {
      GoldBotLog("Daily risk gate blocked new entries. PnL%=" + DoubleToString(pnlPct, 2));
      return;
   }

   if(!GoldBotCooldownAllowed(InpCooldownBars))
   {
      GoldBotLog("Cooldown gate blocked new entries.");
      return;
   }

   if(GoldBotCountManagedPositions(symbol, InpMagicNumber) >= InpMaxOpenTrades)
   {
      GoldBotLog("Max open trades gate blocked new entries.");
      return;
   }

   IndicatorSnapshot indicators;
   if(!GoldBotIndicatorSnapshot(symbol, InpRsiLongMax, InpRsiShortMin, InpAdxMin, InpAtrMin, InpAtrMax, InpRsiPeriod, indicators))
   {
      GoldBotLog("Indicator snapshot unavailable.");
      return;
   }

   SMCResult smc;
   bool smcReady = GoldBotRunSMC(symbol, smc);
   GoldBotDirection direction = DIR_NONE;
   double score = 0.0;
   GoldBotZone fvg;
   fvg.valid = false;
   fvg.bottom = 0.0;
   fvg.top = 0.0;
   GoldBotZone orderBlock;
   orderBlock.valid = false;
   orderBlock.bottom = 0.0;
   orderBlock.top = 0.0;

   if(InpLegacyParityMode)
   {
      direction = GoldBotLegacySignalDirection(symbol, indicators);
      if(direction == DIR_NONE)
      {
         GoldBotLog("Legacy parity gates failed.");
         return;
      }
      score = 75.0;
      fvg.valid = false;
      orderBlock.valid = false;
   }
   else
   {
      if(!smcReady || !smc.allPass)
      {
         GoldBotLog(StringFormat("SMC gates failed. h4=%s h1=%s m15=%s dir=%d fvg=%s ob=%s",
            smc.gateH4 ? "yes" : "no",
            smc.gateH1 ? "yes" : "no",
            smc.gateM15 ? "yes" : "no",
            smc.direction,
            smc.fvg.valid ? "yes" : "no",
            smc.orderBlock.valid ? "yes" : "no"));
         return;
      }
      direction = smc.direction;
      score = smc.score;
      fvg = smc.fvg;
      orderBlock = smc.orderBlock;
   }

   if(direction == DIR_LONG)
   {
      score += indicators.emaLong ? 12.5 : 0.0;
      score += indicators.rsiLong ? 12.5 : 0.0;
      score += indicators.vwapLong ? 12.5 : 0.0;
      score += indicators.atrPass ? 12.5 : 0.0;
      score += indicators.adxLong ? 12.5 : 0.0;
   }
   else if(direction == DIR_SHORT)
   {
      score += indicators.emaShort ? 12.5 : 0.0;
      score += indicators.rsiShort ? 12.5 : 0.0;
      score += indicators.vwapShort ? 12.5 : 0.0;
      score += indicators.atrPass ? 12.5 : 0.0;
      score += indicators.adxShort ? 12.5 : 0.0;
   }

   EntryZone zone = InpLegacyParityMode ? GoldBotLegacyEntryZone(symbol, direction)
                                        : GoldBotBuildEntryZone(fvg, orderBlock, indicators.ema21, indicators.atr);
   if(score < InpScoreThreshold || !zone.valid)
   {
      GoldBotLog(StringFormat("Signal skipped. score=%.2f zone=%s", score, zone.valid ? "yes" : "no"));
      return;
   }

   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   if(CopyRates(symbol, PERIOD_M15, 1, 2, m15) < 2)
      return;

   double entryReference = m15[0].close;
   double sl = direction == DIR_LONG ? MathMin(zone.bottom, entryReference - indicators.atr * InpSlAtr)
                                     : MathMax(zone.top, entryReference + indicators.atr * InpSlAtr);

   GoldBotLog(StringFormat("Signal score=%.2f dir=%d zone=%.2f-%.2f sl=%.2f", score, direction, zone.bottom, zone.top, sl));

   if(InpDebugOnly)
      return;

   if(InpLegacyParityMode)
   {
      if(GoldBotPlaceLegacyMarket(symbol, InpMagicNumber, direction, sl, indicators.atr, score))
         GoldBotJournal("Legacy parity market order placed");
      return;
   }

   if(GoldBotPlaceLadder(symbol, InpMagicNumber, direction, zone, sl, score, InpLotPer100Usd, InpMinLot, InpMaxLot, InpHighConvictionScore, InpMinRR, InpMaxHoldBars, trade))
      GoldBotJournal("Pending ladder placed");
}

string GoldBotSymbol()
{
   return InpSymbol == "" ? _Symbol : InpSymbol;
}

bool GoldBotIsNewM15Bar(const string symbol)
{
   datetime barTime = iTime(symbol, PERIOD_M15, 0);
   if(barTime == 0 || barTime == lastM15Bar)
      return false;
   lastM15Bar = barTime;
   return true;
}

void GoldBotLog(const string message)
{
   Print("GoldBot: ", message);
   if(InpDebugOnly)
      GoldBotJournal(message);
}

GoldBotDirection GoldBotLegacySignalDirection(const string symbol, const IndicatorSnapshot &indicators)
{
   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   if(CopyRates(symbol, PERIOD_M15, 1, 36, m15) < 36)
      return DIR_NONE;

   double recentLow = m15[0].low;
   double recentHigh = m15[0].high;
   for(int i = 0; i <= 11; i++)
   {
      recentLow = MathMin(recentLow, m15[i].low);
      recentHigh = MathMax(recentHigh, m15[i].high);
   }

   double previousLow = m15[12].low;
   double previousHigh = m15[12].high;
   for(int i = 12; i < 36; i++)
   {
      previousLow = MathMin(previousLow, m15[i].low);
      previousHigh = MathMax(previousHigh, m15[i].high);
   }

   double close = m15[0].close;
   bool sweptLow = recentLow < previousLow && close > previousLow;
   bool sweptHigh = recentHigh > previousHigh && close < previousHigh;
   bool longPullback = close <= indicators.vwap && (close <= indicators.vwapLower * 1.003 || sweptLow);
   bool shortPullback = close >= indicators.vwap && (close >= indicators.vwapUpper * 0.997 || sweptHigh);

   if(indicators.emaLong && indicators.adxLong && indicators.rsiLong && indicators.atrPass && longPullback)
      return DIR_LONG;
   if(indicators.emaShort && indicators.adxShort && indicators.rsiShort && indicators.atrPass && shortPullback)
      return DIR_SHORT;
   return DIR_NONE;
}

EntryZone GoldBotLegacyEntryZone(const string symbol, const GoldBotDirection direction)
{
   EntryZone zone;
   zone.valid = false;
   zone.bottom = 0.0;
   zone.top = 0.0;
   zone.midpoint = 0.0;

   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   if(CopyRates(symbol, PERIOD_M15, 1, 2, m15) < 2)
      return zone;

   double entry = m15[0].close;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double spread = MathMax(SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID), point * 10.0);
   double width = MathMax(spread * 3.0, point * 50.0);

   zone.valid = true;
   if(direction == DIR_LONG)
   {
      zone.top = entry;
      zone.bottom = entry - width;
   }
   else if(direction == DIR_SHORT)
   {
      zone.bottom = entry;
      zone.top = entry + width;
   }
   else
      return zone;

   zone.midpoint = zone.bottom + (zone.top - zone.bottom) / 2.0;
   return zone;
}

bool GoldBotPlaceLegacyMarket(const string symbol, const long magic, const GoldBotDirection direction, const double sl, const double atrValue, const double score)
{
   trade.SetExpertMagicNumber(magic);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lot = GoldBotSplitLot(symbol, equity, score, 0, InpLotPer100Usd * 3.0, InpMinLot, InpMaxLot, InpHighConvictionScore);
   if(lot <= 0.0 || atrValue <= 0.0)
      return false;

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double entry = direction == DIR_LONG ? ask : bid;
   double risk = MathAbs(entry - sl);
   if(risk <= 0.0)
      return false;

   double tp = direction == DIR_LONG ? entry + risk * InpMinRR : entry - risk * InpMinRR;
   string comment = "GoldBot_legacy_parity";
   bool ok = false;
   if(direction == DIR_LONG)
      ok = trade.Buy(lot, symbol, 0.0, sl, tp, comment);
   else if(direction == DIR_SHORT)
      ok = trade.Sell(lot, symbol, 0.0, sl, tp, comment);

   if(ok)
      GoldBotMarkSignalTime();
   return ok;
}
