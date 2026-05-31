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

CTrade trade;
datetime lastM15Bar = 0;

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

   SMCResult smc;
   if(!GoldBotRunSMC(symbol, smc) || !smc.allPass)
   {
      GoldBotLog("SMC gates failed.");
      return;
   }

   IndicatorSnapshot indicators;
   if(!GoldBotIndicatorSnapshot(symbol, InpRsiLongMax, InpRsiShortMin, InpAdxMin, InpAtrMin, InpAtrMax, InpRsiPeriod, indicators))
   {
      GoldBotLog("Indicator snapshot unavailable.");
      return;
   }

   double score = smc.score;
   if(smc.direction == DIR_LONG)
   {
      score += indicators.emaLong ? 12.5 : 0.0;
      score += indicators.rsiLong ? 12.5 : 0.0;
      score += indicators.vwapLong ? 12.5 : 0.0;
      score += indicators.atrPass ? 12.5 : 0.0;
      score += indicators.adxLong ? 12.5 : 0.0;
   }
   else if(smc.direction == DIR_SHORT)
   {
      score += indicators.emaShort ? 12.5 : 0.0;
      score += indicators.rsiShort ? 12.5 : 0.0;
      score += indicators.vwapShort ? 12.5 : 0.0;
      score += indicators.atrPass ? 12.5 : 0.0;
      score += indicators.adxShort ? 12.5 : 0.0;
   }

   EntryZone zone = GoldBotBuildEntryZone(smc.fvg, smc.orderBlock, indicators.ema21, indicators.atr);
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
   double sl = smc.direction == DIR_LONG ? MathMin(zone.bottom, entryReference - indicators.atr * InpSlAtr)
                                         : MathMax(zone.top, entryReference + indicators.atr * InpSlAtr);

   GoldBotLog(StringFormat("Signal score=%.2f dir=%d zone=%.2f-%.2f sl=%.2f", score, smc.direction, zone.bottom, zone.top, sl));

   if(InpDebugOnly)
      return;

   if(GoldBotPlaceLadder(symbol, InpMagicNumber, smc.direction, zone, sl, score, InpLotPer100Usd, InpMinLot, InpMaxLot, InpHighConvictionScore, InpMinRR, InpMaxHoldBars, trade))
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
