#property strict
#property version   "3.00"
#property description "Gold XAU/USD SMC + confluence Expert Advisor"

#include <Trade/Trade.mqh>
#include <GoldBot/Indicators.mqh>
#include <GoldBot/SMC.mqh>
#include <GoldBot/Risk.mqh>
#include <GoldBot/TradeManager.mqh>
#include <GoldBot/EntryFilters.mqh>

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
input int             InpMacdFast = 12;
input int             InpMacdSlow = 26;
input int             InpMacdSignal = 9;
input int             InpBbPeriod = 20;
input double          InpBbDeviation = 2.0;
input int             InpStochKPeriod = 14;
input int             InpStochDPeriod = 3;
input int             InpStochSlowing = 3;
input double          InpStochLongMax = 35.0;
input double          InpStochShortMin = 65.0;
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
input bool            InpResetJournalOnInit = true;
input bool            InpPythonParityMode = false;
input string          InpSessionFilter = "all";
input string          InpPythonParityStart = "";
input bool            InpLegacyParityMode = false;
input bool            InpRequireHigherTfConfirmation = true;
input double          InpMinRealModeScore = 68.75;
input int             InpMaxLaddersPerDay = 3;
input bool            InpUseSessionFilterForRealMode = true;
input int             InpRealSessionStartHour = 7;
input int             InpRealSessionEndHour = 22;
input double          InpTp1R = 1.5;
input double          InpTp2R = 2.0;
input double          InpTp3R = 3.0;
input double          InpBreakEvenAtR = 0.0;
input bool            InpTrailAfterTp1 = true;
input int             InpLadderOrderCount = 3;
input int             InpLadderFirstSplit = 1;
input int             InpMinRealConfluences = 5;
input bool            InpRequireDirectionalAdx = true;
input bool            InpRequireEmaTrend = false;
input bool            InpUseMacdConfluence = true;
input bool            InpUseBollingerConfluence = true;
input bool            InpUseStochasticConfluence = true;
input bool            InpRequireM5PullbackConfirmation = true;
input int             InpPullbackConfirmChecks = 2;
input bool            InpEnableNewsFilter = false;
input int             InpNewsBlackoutMinutes = 30;
input string          InpHighImpactNewsTimes = "";
input bool            InpBlockIndicatorDirectionConflicts = true;
input bool            InpUseExtendedDirectionConflict = true;
input bool            InpUseHtfTargetsForTp2Tp3 = true;
input bool            InpRequireNearZoneBeforeLadder = true;
input double          InpNearZoneBuffer = 0.5;
input bool            InpRequireSmcSequence = false;
input bool            InpRequireLiquiditySweepForSmc = false;
input bool            InpRequireDisplacementForSmc = false;
input bool            InpRequireObFvgOverlap = false;
input bool            InpRequireHtfSmcContext = false;
input string          InpAllowedEntryHours = "";
input string          InpAllowedLongEntryHours = "";
input string          InpAllowedShortEntryHours = "";
input bool            InpAllowLong = true;
input bool            InpAllowShort = true;

CTrade trade;
datetime lastM15Bar = 0;
datetime lastParityClosedBar = 0;
datetime parityStartTime = 0;

struct PythonParityTrade
{
   bool active;
   GoldBotDirection direction;
   datetime entryTime;
   double entry;
   double sl;
   double tp;
   double risk;
   int barsHeld;
};

PythonParityTrade parityTrades[];
double parityRResults[];
string parityTradeDays[];
int parityTradesClosed = 0;
int parityWins = 0;
int parityLosses = 0;
double parityGrossWin = 0.0;
double parityGrossLoss = 0.0;
double parityEquityR = 0.0;
double parityPeakR = 0.0;
double parityMaxDrawdownR = 0.0;
int parityCooldownRemaining = 0;
int parityObservedBars = 0;

GoldBotDirection GoldBotLegacySignalDirection(const string symbol, const IndicatorSnapshot &indicators);
EntryZone GoldBotLegacyEntryZone(const string symbol, const GoldBotDirection direction);
bool GoldBotPlaceLegacyMarket(const string symbol, const long magic, const GoldBotDirection direction, const double sl, const double atrValue, const double score);
void GoldBotPythonParityReset();
void GoldBotPythonParityOnNewBar(const string symbol);
void GoldBotPythonParityCatchUp(const string symbol);
void GoldBotPythonParityProcessClosedBar(const string symbol, const MqlRates &closedBar);
bool GoldBotPythonParitySignal(const string symbol, const datetime signalTime, GoldBotDirection &direction, double &atrValue);
void GoldBotPythonParityOpen(const GoldBotDirection direction, const datetime entryTime, const double entry, const double atrValue);
void GoldBotPythonParityManage(const string symbol, const MqlRates &closedBar);
void GoldBotPythonParityClose(const int index, const datetime exitTime, const double exitPrice, const double rr, const string exitReason);
void GoldBotPythonParityJournalHeader();
void GoldBotPythonParityJournalSignal(const datetime signalTime, const GoldBotDirection direction, const double close, const IndicatorSnapshot &indicators, const bool sweptLow, const bool sweptHigh);
void GoldBotPythonParityJournalTrade(const PythonParityTrade &tradeState, const datetime exitTime, const double exitPrice, const double rr, const string exitReason);
void GoldBotPythonParityPrintSummary();
bool GoldBotPythonIndicatorSnapshot(const string symbol, const datetime signalTime, IndicatorSnapshot &out);
bool GoldBotCopyRatesWindow(const string symbol, const ENUM_TIMEFRAMES tf, const datetime endTime, const int bars, MqlRates &rates[]);
bool GoldBotCopyRatesSinceCapped(const string symbol, const ENUM_TIMEFRAMES tf, const datetime startTime, const datetime endTime, const int maxBars, MqlRates &rates[]);
bool GoldBotPythonResampleH1FromM15(MqlRates &m15[], const int m15Count, MqlRates &h1[]);
double GoldBotPythonEMAFromRates(MqlRates &rates[], const int count, const int period);
double GoldBotPythonRSIFromRates(MqlRates &rates[], const int count, const int period);
double GoldBotPythonATRFromRates(MqlRates &rates[], const int count, const int period);
bool GoldBotPythonADXFromRates(MqlRates &rates[], const int count, const int period, double &adx, double &plusDI, double &minusDI);
bool GoldBotPythonRollingVWAP(MqlRates &rates[], const int count, const int bars, double &vwap, double &upper, double &lower);
void GoldBotPythonRMA(double &values[], const int count, const int period, double &out[]);
bool GoldBotPythonInSession(const datetime timeValue);
void GoldBotAddParityDay(const datetime entryTime);
void GoldBotRemoveParityTrade(const int index);
string GoldBotNewSignalId(const GoldBotDirection direction);
void GoldBotCopyOrderMetadataToPosition(const ulong orderTicket, const long positionId, const string comment, const long dealType);
void GoldBotDeletePositionMetadata(const long positionId);
double GoldBotMetadataValue(const string baseKey, const string field, const double fallback);
int GoldBotSplitFromComment(const string comment);
bool GoldBotAllowedEntryHour(const string allowedHours);
bool GoldBotDirectionAllowedEntryHour(const GoldBotDirection direction, const string allowedLongHours, const string allowedShortHours);

int OnInit()
{
   string symbol = GoldBotSymbol();
   if(!SymbolSelect(symbol, true))
   {
      Print("GoldBot: unable to select symbol ", symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   if(InpPythonParityMode)
      GoldBotPythonParityReset();
   else if(InpResetJournalOnInit)
      GoldBotResetJournal();
   Print("GoldBot initialized for ", symbol, " magic=", InpMagicNumber);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(InpPythonParityMode)
      GoldBotPythonParityPrintSummary();
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(symbol != GoldBotSymbol() || magic != InpMagicNumber)
      return;

   long dealEntry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   long dealType = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
   long dealReason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
   long positionId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   ulong orderTicket = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
   string comment = HistoryDealGetString(trans.deal, DEAL_COMMENT);

   if(dealEntry == DEAL_ENTRY_IN || dealEntry == DEAL_ENTRY_INOUT)
      GoldBotCopyOrderMetadataToPosition(orderTicket, positionId, comment, dealType);

   datetime dealTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);
   MqlDateTime dealParts;
   TimeToStruct(dealTime, dealParts);
   string posKey = StringFormat("GoldBot.pos.%I64d", positionId);
   int directionFallback = 0;
   if(dealType == DEAL_TYPE_BUY)
      directionFallback = (dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY) ? DIR_SHORT : DIR_LONG;
   else if(dealType == DEAL_TYPE_SELL)
      directionFallback = (dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY) ? DIR_LONG : DIR_SHORT;

   int metaDirection = (int)GoldBotMetadataValue(posKey, "dir", (double)directionFallback);
   int split = (int)GoldBotMetadataValue(posKey, "split", (double)GoldBotSplitFromComment(comment));
   int hour = (int)GoldBotMetadataValue(posKey, "hour", (double)dealParts.hour);
   int confluences = (int)GoldBotMetadataValue(posKey, "confluences", -1.0);
   int enabledConfluences = (int)GoldBotMetadataValue(posKey, "enabledConfluences", -1.0);
   double scoreBucket = GoldBotMetadataValue(posKey, "scoreBucket", -1.0);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP);

   GoldBotJournal(StringFormat("Deal event deal=%I64u position=%I64d entry=%d type=%d reason=%d price=%.2f volume=%.2f profit=%.2f dir=%d split=%d hour=%d scoreBucket=%.0f confluences=%d/%d comment=%s",
      trans.deal,
      positionId,
      dealEntry,
      dealType,
      dealReason,
      HistoryDealGetDouble(trans.deal, DEAL_PRICE),
      HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
      profit,
      metaDirection,
      split,
      hour,
      scoreBucket,
      confluences,
      enabledConfluences,
      comment));

   if((dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY) && positionId > 0 && !PositionSelectByTicket((ulong)positionId))
      GoldBotDeletePositionMetadata(positionId);
}

void OnTick()
{
   string symbol = GoldBotSymbol();
   if(InpPythonParityMode)
   {
      GoldBotPythonParityCatchUp(symbol);
      return;
   }

   if(!GoldBotIsNewM15Bar(symbol))
   {
      GoldBotManagePositions(symbol, InpMagicNumber, MathMax(GoldBotATR(symbol, PERIOD_H1, 14, 1), 0.0), InpMaxHoldBars, InpTp1R, InpTp2R, InpTp3R, InpBreakEvenAtR, InpTrailAfterTp1, InpUseHtfTargetsForTp2Tp3, trade);
      return;
   }

   GoldBotExpirePendingOrders(symbol, InpMagicNumber, trade);
   GoldBotCancelPendingOnStopBreach(symbol, InpMagicNumber, trade);
   GoldBotManagePositions(symbol, InpMagicNumber, MathMax(GoldBotATR(symbol, PERIOD_H1, 14, 1), 0.0), InpMaxHoldBars, InpTp1R, InpTp2R, InpTp3R, InpBreakEvenAtR, InpTrailAfterTp1, InpUseHtfTargetsForTp2Tp3, trade);

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
   if(!GoldBotIndicatorSnapshot(
      symbol,
      InpRsiLongMax,
      InpRsiShortMin,
      InpAdxMin,
      InpAtrMin,
      InpAtrMax,
      InpRsiPeriod,
      InpMacdFast,
      InpMacdSlow,
      InpMacdSignal,
      InpBbPeriod,
      InpBbDeviation,
      InpStochKPeriod,
      InpStochDPeriod,
      InpStochSlowing,
      InpStochLongMax,
      InpStochShortMin,
      indicators))
   {
      GoldBotLog("Indicator snapshot unavailable.");
      return;
   }

   SMCResult smc;
   GoldBotResetSMC(smc);
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
      GoldBotJournal(StringFormat("SMC candidate h4=%s h1=%s m15=%s dir=%d h4Dir=%d h1Dir=%d m15Dir=%d smcScore=%.2f fvg=%s ob=%s h4PD=%s h4Sweep=%s h4Disp=%s h4Bos=%s h4Overlap=%s h1Aligned=%s h1Sweep=%s h1Disp=%s h1Bos=%s h1Overlap=%s m15Sweep=%s m15RecentSweep=%s m15Disp=%s m15Bos=%s m15HasZone=%s m15Overlap=%s m15Retest=%s m15Sequence=%s",
         smc.gateH4 ? "yes" : "no",
         smc.gateH1 ? "yes" : "no",
         smc.gateM15 ? "yes" : "no",
         smc.direction,
         smc.h4Direction,
         smc.h1Direction,
         smc.m15Direction,
         smc.score,
         smc.fvg.valid ? "yes" : "no",
         smc.orderBlock.valid ? "yes" : "no",
         smc.h4PremiumDiscount ? "yes" : "no",
         smc.h4LiquiditySweep ? "yes" : "no",
         smc.h4Displacement ? "yes" : "no",
         smc.h4BosChoCh ? "yes" : "no",
         smc.h4ObFvgOverlap ? "yes" : "no",
         smc.h1Aligned ? "yes" : "no",
         smc.h1LiquiditySweep ? "yes" : "no",
         smc.h1Displacement ? "yes" : "no",
         smc.h1BosChoCh ? "yes" : "no",
         smc.h1ObFvgOverlap ? "yes" : "no",
         smc.m15LiquiditySweep ? "yes" : "no",
         smc.m15RecentSweep ? "yes" : "no",
         smc.m15Displacement ? "yes" : "no",
         smc.m15BosChoCh ? "yes" : "no",
         smc.m15HasZone ? "yes" : "no",
         smc.m15ObFvgOverlap ? "yes" : "no",
         smc.m15RetestingZone ? "yes" : "no",
         smc.m15SequenceOk ? "yes" : "no"));

      if(InpRequireHigherTfConfirmation && !smc.gateH4 && !smc.gateH1)
      {
         GoldBotLog("Higher timeframe confirmation blocked new entry.");
         GoldBotJournal(StringFormat("Higher timeframe confirmation blocked h4=%s h1=%s m15=%s dir=%d",
            smc.gateH4 ? "yes" : "no",
            smc.gateH1 ? "yes" : "no",
            smc.gateM15 ? "yes" : "no",
            smc.direction));
         return;
      }
      if(InpRequireHtfSmcContext && !smc.gateH4 && !smc.gateH1)
      {
         GoldBotLog("HTF SMC context blocked new entry.");
         GoldBotJournal(StringFormat("HTF SMC context blocked h4=%s h1=%s h4Dir=%d h1Dir=%d dir=%d",
            smc.gateH4 ? "yes" : "no",
            smc.gateH1 ? "yes" : "no",
            smc.h4Direction,
            smc.h1Direction,
            smc.direction));
         return;
      }
      if(InpRequireSmcSequence && !smc.m15SequenceOk)
      {
         GoldBotLog("SMC sequence blocked new entry.");
         GoldBotJournal(StringFormat("SMC sequence blocked recentSweep=%s displacement=%s bos=%s hasZone=%s retest=%s overlap=%s dir=%d",
            smc.m15RecentSweep ? "yes" : "no",
            smc.m15Displacement ? "yes" : "no",
            smc.m15BosChoCh ? "yes" : "no",
            smc.m15HasZone ? "yes" : "no",
            smc.m15RetestingZone ? "yes" : "no",
            smc.m15ObFvgOverlap ? "yes" : "no",
            smc.direction));
         return;
      }
      if(InpRequireLiquiditySweepForSmc && !smc.m15RecentSweep)
      {
         GoldBotLog("SMC liquidity sweep blocked new entry.");
         GoldBotJournal(StringFormat("SMC liquidity sweep blocked currentSweep=%s recentSweep=%s dir=%d",
            smc.m15LiquiditySweep ? "yes" : "no",
            smc.m15RecentSweep ? "yes" : "no",
            smc.direction));
         return;
      }
      if(InpRequireDisplacementForSmc && !smc.m15Displacement)
      {
         GoldBotLog("SMC displacement blocked new entry.");
         GoldBotJournal(StringFormat("SMC displacement blocked displacement=%s bos=%s dir=%d",
            smc.m15Displacement ? "yes" : "no",
            smc.m15BosChoCh ? "yes" : "no",
            smc.direction));
         return;
      }
      if(InpRequireObFvgOverlap && !smc.m15ObFvgOverlap)
      {
         GoldBotLog("SMC OB/FVG overlap blocked new entry.");
         GoldBotJournal(StringFormat("SMC OB/FVG overlap blocked fvg=%s ob=%s overlap=%s dir=%d",
            smc.fvg.valid ? "yes" : "no",
            smc.orderBlock.valid ? "yes" : "no",
            smc.m15ObFvgOverlap ? "yes" : "no",
            smc.direction));
         return;
      }
   }

   if(!InpLegacyParityMode && !GoldBotAllowedEntryHour(InpAllowedEntryHours))
   {
      GoldBotLog("Allowed entry hour filter blocked new entry.");
      GoldBotJournal(StringFormat("Allowed entry hour blocked allowed=%s", InpAllowedEntryHours));
      return;
   }

   if(!InpLegacyParityMode && !GoldBotDirectionAllowedEntryHour(direction, InpAllowedLongEntryHours, InpAllowedShortEntryHours))
   {
      GoldBotLog("Direction-specific allowed entry hour filter blocked new entry.");
      GoldBotJournal(StringFormat("Direction allowed entry hour blocked dir=%d allowedLong=%s allowedShort=%s",
         direction,
         InpAllowedLongEntryHours,
         InpAllowedShortEntryHours));
      return;
   }

   if(!InpLegacyParityMode && !GoldBotServerHourAllowed(InpUseSessionFilterForRealMode, InpRealSessionStartHour, InpRealSessionEndHour))
   {
      GoldBotLog("Real session filter blocked new entry.");
      GoldBotJournal(StringFormat("Real session filter blocked start=%d end=%d",
         InpRealSessionStartHour,
         InpRealSessionEndHour));
      return;
   }

   if(!InpLegacyParityMode && ((direction == DIR_LONG && !InpAllowLong) || (direction == DIR_SHORT && !InpAllowShort)))
   {
      GoldBotJournal(StringFormat("Direction side blocked dir=%d allowLong=%s allowShort=%s",
         direction,
         InpAllowLong ? "yes" : "no",
         InpAllowShort ? "yes" : "no"));
      return;
   }

   if(!InpLegacyParityMode && InpEnableNewsFilter)
   {
      string matchedEvent = "";
      if(GoldBotNewsBlocked(InpHighImpactNewsTimes, InpNewsBlackoutMinutes, matchedEvent))
      {
         GoldBotLog("High-impact news filter blocked new entry.");
         GoldBotJournal(StringFormat("News filter blocked event=%s blackoutMinutes=%d",
            matchedEvent,
            InpNewsBlackoutMinutes));
         return;
      }
   }

   int dailyLadderCount = 0;
   if(!InpLegacyParityMode && !GoldBotDailyLadderAllowed(InpMaxLaddersPerDay, dailyLadderCount))
   {
      GoldBotLog("Daily ladder limit blocked new entry. Count=" + IntegerToString(dailyLadderCount));
      GoldBotJournal(StringFormat("Daily ladder limit blocked count=%d max=%d",
         dailyLadderCount,
         InpMaxLaddersPerDay));
      return;
   }

   bool emaPass = false;
   bool rsiPass = false;
   bool vwapPass = false;
   bool atrPass = indicators.atrPass;
   bool adxPass = false;
   bool macdPass = false;
   bool bbPass = false;
   bool stochPass = false;

   if(direction == DIR_LONG)
   {
      emaPass = indicators.emaLong;
      rsiPass = indicators.rsiLong;
      vwapPass = indicators.vwapLong;
      adxPass = indicators.adxLong;
      macdPass = indicators.macdLong;
      bbPass = indicators.bbLong;
      stochPass = indicators.stochLong;
   }
   else if(direction == DIR_SHORT)
   {
      emaPass = indicators.emaShort;
      rsiPass = indicators.rsiShort;
      vwapPass = indicators.vwapShort;
      adxPass = indicators.adxShort;
      macdPass = indicators.macdShort;
      bbPass = indicators.bbShort;
      stochPass = indicators.stochShort;
   }

   if(!InpLegacyParityMode && InpBlockIndicatorDirectionConflicts)
   {
      int longDirections = 0;
      int shortDirections = 0;
      if(GoldBotIndicatorDirectionConflicts(indicators, InpUseExtendedDirectionConflict, longDirections, shortDirections) > 0)
      {
         GoldBotJournal(StringFormat("Direction conflict blocked longIndicators=%d shortIndicators=%d extended=%s dir=%d",
            longDirections,
            shortDirections,
            InpUseExtendedDirectionConflict ? "yes" : "no",
            direction));
         return;
      }
   }

   int confluenceCount = 0;
   int enabledConfluences = 5;
   if(emaPass)
      confluenceCount++;
   if(rsiPass)
      confluenceCount++;
   if(vwapPass)
      confluenceCount++;
   if(atrPass)
      confluenceCount++;
   if(adxPass)
      confluenceCount++;
   if(InpUseMacdConfluence)
   {
      enabledConfluences++;
      if(macdPass)
         confluenceCount++;
   }
   if(InpUseBollingerConfluence)
   {
      enabledConfluences++;
      if(bbPass)
         confluenceCount++;
   }
   if(InpUseStochasticConfluence)
   {
      enabledConfluences++;
      if(stochPass)
         confluenceCount++;
   }

   double indicatorWeight = enabledConfluences > 0 ? 62.5 / enabledConfluences : 0.0;
   score += emaPass ? indicatorWeight : 0.0;
   score += rsiPass ? indicatorWeight : 0.0;
   score += vwapPass ? indicatorWeight : 0.0;
   score += atrPass ? indicatorWeight : 0.0;
   score += adxPass ? indicatorWeight : 0.0;
   if(InpUseMacdConfluence)
      score += macdPass ? indicatorWeight : 0.0;
   if(InpUseBollingerConfluence)
      score += bbPass ? indicatorWeight : 0.0;
   if(InpUseStochasticConfluence)
      score += stochPass ? indicatorWeight : 0.0;

   int minConfluences = MathMax(0, MathMin(enabledConfluences, InpMinRealConfluences));
   if(!InpLegacyParityMode)
   {
      if(confluenceCount < minConfluences)
      {
         GoldBotJournal(StringFormat("Confluence quality blocked count=%d min=%d enabled=%d ema=%s rsi=%s vwap=%s atr=%s adx=%s macd=%s bb=%s stoch=%s dir=%d score=%.2f",
            confluenceCount,
            minConfluences,
            enabledConfluences,
            emaPass ? "yes" : "no",
            rsiPass ? "yes" : "no",
            vwapPass ? "yes" : "no",
            atrPass ? "yes" : "no",
            adxPass ? "yes" : "no",
            macdPass ? "yes" : "no",
            bbPass ? "yes" : "no",
            stochPass ? "yes" : "no",
            direction,
            score));
         return;
      }
      if(InpRequireDirectionalAdx && !adxPass)
      {
         GoldBotJournal(StringFormat("Directional ADX blocked ema=%s rsi=%s vwap=%s atr=%s adx=%s macd=%s bb=%s stoch=%s dir=%d score=%.2f",
            emaPass ? "yes" : "no",
            rsiPass ? "yes" : "no",
            vwapPass ? "yes" : "no",
            atrPass ? "yes" : "no",
            adxPass ? "yes" : "no",
            macdPass ? "yes" : "no",
            bbPass ? "yes" : "no",
            stochPass ? "yes" : "no",
            direction,
            score));
         return;
      }
      if(InpRequireEmaTrend && !emaPass)
      {
         GoldBotJournal(StringFormat("EMA trend blocked ema=%s rsi=%s vwap=%s atr=%s adx=%s macd=%s bb=%s stoch=%s dir=%d score=%.2f",
            emaPass ? "yes" : "no",
            rsiPass ? "yes" : "no",
            vwapPass ? "yes" : "no",
            atrPass ? "yes" : "no",
            adxPass ? "yes" : "no",
            macdPass ? "yes" : "no",
            bbPass ? "yes" : "no",
            stochPass ? "yes" : "no",
            direction,
            score));
         return;
      }
   }

   EntryZone zone = InpLegacyParityMode ? GoldBotLegacyEntryZone(symbol, direction)
                                        : GoldBotBuildEntryZone(fvg, orderBlock, indicators.ema21, indicators.atr);
   double effectiveScoreThreshold = InpLegacyParityMode ? InpScoreThreshold : MathMax(InpScoreThreshold, InpMinRealModeScore);
   if(score < effectiveScoreThreshold || !zone.valid)
   {
      GoldBotLog(StringFormat("Signal skipped. score=%.2f threshold=%.2f zone=%s", score, effectiveScoreThreshold, zone.valid ? "yes" : "no"));
      if(score >= 50.0 || zone.valid)
         GoldBotJournal(StringFormat("Signal skipped score=%.2f threshold=%.2f zone=%s dir=%d confluences=%d/%d ema=%s rsi=%s vwap=%s atr=%s adx=%s macd=%s bb=%s stoch=%s",
            score,
            effectiveScoreThreshold,
            zone.valid ? "yes" : "no",
            direction,
            confluenceCount,
            enabledConfluences,
            emaPass ? "yes" : "no",
            rsiPass ? "yes" : "no",
            vwapPass ? "yes" : "no",
            atrPass ? "yes" : "no",
            adxPass ? "yes" : "no",
            macdPass ? "yes" : "no",
            bbPass ? "yes" : "no",
            stochPass ? "yes" : "no"));
      return;
   }

   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   if(CopyRates(symbol, PERIOD_M15, 1, 2, m15) < 2)
      return;

   double entryReference = m15[0].close;
   double sl = direction == DIR_LONG ? MathMin(zone.bottom, entryReference - indicators.atr * InpSlAtr)
                                     : MathMax(zone.top, entryReference + indicators.atr * InpSlAtr);

   if(!InpLegacyParityMode && InpRequireM5PullbackConfirmation)
   {
      bool candlePattern = false;
      bool rsiShift = false;
      bool microChoCH = false;
      int checksHit = 0;
      if(!GoldBotPullbackConfirmed(symbol, zone, direction, InpRsiPeriod, InpPullbackConfirmChecks, candlePattern, rsiShift, microChoCH, checksHit))
      {
         GoldBotJournal(StringFormat("M5 pullback confirmation blocked checks=%d required=%d candle=%s rsiShift=%s microChoCH=%s dir=%d zone=%.2f-%.2f",
            checksHit,
            MathMax(1, MathMin(3, InpPullbackConfirmChecks)),
            candlePattern ? "yes" : "no",
            rsiShift ? "yes" : "no",
            microChoCH ? "yes" : "no",
            direction,
            zone.bottom,
            zone.top));
         return;
      }
      GoldBotJournal(StringFormat("M5 pullback confirmation passed checks=%d required=%d candle=%s rsiShift=%s microChoCH=%s dir=%d",
         checksHit,
         MathMax(1, MathMin(3, InpPullbackConfirmChecks)),
         candlePattern ? "yes" : "no",
         rsiShift ? "yes" : "no",
         microChoCH ? "yes" : "no",
         direction));
   }

   if(!InpLegacyParityMode && InpRequireNearZoneBeforeLadder && !GoldBotPriceNearEntryZone(symbol, zone, direction, InpNearZoneBuffer))
   {
      GoldBotJournal(StringFormat("Near-zone placement blocked dir=%d buffer=%.2f bid=%.2f ask=%.2f zone=%.2f-%.2f",
         direction,
         InpNearZoneBuffer,
         SymbolInfoDouble(symbol, SYMBOL_BID),
         SymbolInfoDouble(symbol, SYMBOL_ASK),
         zone.bottom,
         zone.top));
      return;
   }

   string signalId = GoldBotNewSignalId(direction);
   GoldBotLog(StringFormat("Signal score=%.2f dir=%d zone=%.2f-%.2f sl=%.2f confluences=%d/%d", score, direction, zone.bottom, zone.top, sl, confluenceCount, enabledConfluences));
   GoldBotJournal(StringFormat("Signal accepted signalId=%s score=%.2f dir=%d confluences=%d/%d ema=%s rsi=%s vwap=%s atr=%s adx=%s macd=%s bb=%s stoch=%s zone=%.2f-%.2f sl=%.2f",
      signalId,
      score,
      direction,
      confluenceCount,
      enabledConfluences,
      emaPass ? "yes" : "no",
      rsiPass ? "yes" : "no",
      vwapPass ? "yes" : "no",
      atrPass ? "yes" : "no",
      adxPass ? "yes" : "no",
      macdPass ? "yes" : "no",
      bbPass ? "yes" : "no",
      stochPass ? "yes" : "no",
      zone.bottom,
      zone.top,
      sl));

   if(InpDebugOnly)
      return;

   if(InpLegacyParityMode)
   {
      if(GoldBotPlaceLegacyMarket(symbol, InpMagicNumber, direction, sl, indicators.atr, score))
         GoldBotJournal("Legacy parity market order placed");
      return;
   }

   int ladderOrderCount = InpLadderOrderCount;
   if(ladderOrderCount < 1)
      ladderOrderCount = 1;
   else if(ladderOrderCount > 3)
      ladderOrderCount = 3;

   int ladderFirstSplit = InpLadderFirstSplit;
   if(ladderFirstSplit < 1)
      ladderFirstSplit = 1;
   else if(ladderFirstSplit > 3)
      ladderFirstSplit = 3;
   int maxOrdersFromFirstSplit = 4 - ladderFirstSplit;
   if(ladderOrderCount > maxOrdersFromFirstSplit)
      ladderOrderCount = maxOrdersFromFirstSplit;

   if(GoldBotPlaceLadder(symbol, InpMagicNumber, direction, zone, sl, score, signalId, ladderOrderCount, ladderFirstSplit, confluenceCount, enabledConfluences, InpLotPer100Usd, InpMinLot, InpMaxLot, InpHighConvictionScore, InpMinRR, InpMaxHoldBars, trade))
   {
      GoldBotMarkLadderPlaced();
      GoldBotJournal(StringFormat("Pending ladder placed signalId=%s orderCount=%d firstSplit=%d", signalId, ladderOrderCount, ladderFirstSplit));
   }
}

string GoldBotSymbol()
{
   return InpSymbol == "" ? _Symbol : InpSymbol;
}

bool GoldBotAllowedEntryHour(const string allowedHours)
{
   if(StringLen(allowedHours) <= 0)
      return true;

   string normalized = allowedHours;
   StringReplace(normalized, ";", ",");
   StringReplace(normalized, " ", "");
   StringReplace(normalized, "\t", "");
   if(StringLen(normalized) <= 0)
      return true;

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);

   string tokens[];
   int count = StringSplit(normalized, ',', tokens);
   for(int i = 0; i < count; i++)
   {
      if(StringLen(tokens[i]) <= 0)
         continue;
      int hour = (int)StringToInteger(tokens[i]);
      if(hour == nowParts.hour)
         return true;
   }
   return false;
}

bool GoldBotDirectionAllowedEntryHour(const GoldBotDirection direction, const string allowedLongHours, const string allowedShortHours)
{
   if(direction == DIR_LONG && StringLen(allowedLongHours) > 0)
      return GoldBotAllowedEntryHour(allowedLongHours);
   if(direction == DIR_SHORT && StringLen(allowedShortHours) > 0)
      return GoldBotAllowedEntryHour(allowedShortHours);
   return true;
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

string GoldBotNewSignalId(const GoldBotDirection direction)
{
   long stamp = (long)TimeCurrent();
   int side = direction == DIR_LONG ? 1 : 2;
   return StringFormat("GB%d%06d", side, (int)(stamp % 1000000));
}

double GoldBotMetadataValue(const string baseKey, const string field, const double fallback)
{
   string key = baseKey + "." + field;
   return GlobalVariableCheck(key) ? GlobalVariableGet(key) : fallback;
}

int GoldBotSplitFromComment(const string comment)
{
   int underscore = -1;
   int searchFrom = 0;
   while(true)
   {
      int found = StringFind(comment, "_", searchFrom);
      if(found < 0)
         break;
      underscore = found;
      searchFrom = found + 1;
   }
   if(underscore < 0 || underscore + 1 >= StringLen(comment))
      return 0;
   return (int)StringToInteger(StringSubstr(comment, underscore + 1));
}

void GoldBotCopyOrderMetadataToPosition(const ulong orderTicket, const long positionId, const string comment, const long dealType)
{
   if(orderTicket == 0 || positionId <= 0)
      return;

   string orderKey = StringFormat("GoldBot.order.%I64u", orderTicket);
   string posKey = StringFormat("GoldBot.pos.%I64d", positionId);
   double directionFallback = dealType == DEAL_TYPE_BUY ? (double)DIR_LONG : (dealType == DEAL_TYPE_SELL ? (double)DIR_SHORT : 0.0);
   GlobalVariableSet(posKey + ".dir", GoldBotMetadataValue(orderKey, "dir", directionFallback));
   GlobalVariableSet(posKey + ".split", GoldBotMetadataValue(orderKey, "split", (double)GoldBotSplitFromComment(comment)));
   GlobalVariableSet(posKey + ".hour", GoldBotMetadataValue(orderKey, "hour", 0.0));
   GlobalVariableSet(posKey + ".scoreBucket", GoldBotMetadataValue(orderKey, "scoreBucket", -1.0));
   GlobalVariableSet(posKey + ".confluences", GoldBotMetadataValue(orderKey, "confluences", -1.0));
   GlobalVariableSet(posKey + ".enabledConfluences", GoldBotMetadataValue(orderKey, "enabledConfluences", -1.0));

   GlobalVariableDel(orderKey + ".dir");
   GlobalVariableDel(orderKey + ".split");
   GlobalVariableDel(orderKey + ".hour");
   GlobalVariableDel(orderKey + ".scoreBucket");
   GlobalVariableDel(orderKey + ".confluences");
   GlobalVariableDel(orderKey + ".enabledConfluences");
}

void GoldBotDeletePositionMetadata(const long positionId)
{
   if(positionId <= 0)
      return;
   string posKey = StringFormat("GoldBot.pos.%I64d", positionId);
   GlobalVariableDel(posKey + ".dir");
   GlobalVariableDel(posKey + ".split");
   GlobalVariableDel(posKey + ".hour");
   GlobalVariableDel(posKey + ".scoreBucket");
   GlobalVariableDel(posKey + ".confluences");
   GlobalVariableDel(posKey + ".enabledConfluences");
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
   zone.quarterPoint = 0.0;

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
   zone.quarterPoint = zone.bottom + (zone.top - zone.bottom) * 0.25;
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

void GoldBotPythonParityReset()
{
   ArrayResize(parityTrades, 0);
   ArrayResize(parityRResults, 0);
   ArrayResize(parityTradeDays, 0);
   parityTradesClosed = 0;
   parityWins = 0;
   parityLosses = 0;
   parityGrossWin = 0.0;
   parityGrossLoss = 0.0;
   parityEquityR = 0.0;
   parityPeakR = 0.0;
   parityMaxDrawdownR = 0.0;
   parityCooldownRemaining = 0;
   parityObservedBars = 0;
   lastParityClosedBar = 0;
   parityStartTime = 0;
   if(StringLen(InpPythonParityStart) > 0)
      parityStartTime = StringToTime(InpPythonParityStart);
   FileDelete("GoldBot\\parity_trades.csv");
   FileDelete("GoldBot\\parity_signals.csv");
   GoldBotPythonParityJournalHeader();
}

void GoldBotPythonParityOnNewBar(const string symbol)
{
   MqlRates closed[];
   ArraySetAsSeries(closed, true);
   if(CopyRates(symbol, PERIOD_M15, 1, 1, closed) != 1)
      return;

   GoldBotPythonParityProcessClosedBar(symbol, closed[0]);
}

void GoldBotPythonParityCatchUp(const string symbol)
{
   datetime currentBar = iTime(symbol, PERIOD_M15, 0);
   if(currentBar == 0)
      return;

   if(lastM15Bar == 0)
   {
      lastM15Bar = currentBar;
      return;
   }

   if(currentBar <= lastM15Bar)
      return;

   int seconds = PeriodSeconds(PERIOD_M15);
   int barsToProcess = (int)((currentBar - lastM15Bar) / seconds);
   if(barsToProcess <= 0)
      return;
   barsToProcess = MathMin(barsToProcess, 500);

   MqlRates closed[];
   int copied = CopyRates(symbol, PERIOD_M15, 1, barsToProcess, closed);
   if(copied <= 0)
      return;

   for(int i = 0; i < copied - 1; i++)
   {
      for(int j = i + 1; j < copied; j++)
      {
         if(closed[i].time > closed[j].time)
         {
            MqlRates tmp = closed[i];
            closed[i] = closed[j];
            closed[j] = tmp;
         }
      }
   }

   for(int i = 0; i < copied; i++)
      GoldBotPythonParityProcessClosedBar(symbol, closed[i]);

   lastM15Bar = currentBar;
}

void GoldBotPythonParityProcessClosedBar(const string symbol, const MqlRates &closedBar)
{
   if(closedBar.time <= lastParityClosedBar)
      return;
   lastParityClosedBar = closedBar.time;
   if(parityStartTime <= 0)
      parityStartTime = closedBar.time;

   GoldBotPythonParityManage(symbol, closedBar);
   parityObservedBars++;
   if(parityObservedBars < 900)
      return;

   if(parityCooldownRemaining > 0)
   {
      parityCooldownRemaining--;
      return;
   }

   GoldBotDirection direction = DIR_NONE;
   double atrValue = 0.0;
   if(!GoldBotPythonParitySignal(symbol, closedBar.time, direction, atrValue))
      return;

   datetime expectedEntryTime = closedBar.time + PeriodSeconds(PERIOD_M15);
   int entryShift = iBarShift(symbol, PERIOD_M15, expectedEntryTime, true);
   if(entryShift < 0)
      return;
   datetime entryTime = iTime(symbol, PERIOD_M15, entryShift);
   double entry = iOpen(symbol, PERIOD_M15, entryShift);
   if(entryTime == 0 || entry <= 0.0)
      return;

   GoldBotPythonParityOpen(direction, entryTime, entry, atrValue);
   parityCooldownRemaining = MathMax(0, InpCooldownBars - 1);
}

bool GoldBotPythonParitySignal(const string symbol, const datetime signalTime, GoldBotDirection &direction, double &atrValue)
{
   direction = DIR_NONE;
   atrValue = 0.0;
   if(!GoldBotPythonInSession(signalTime))
      return false;

   IndicatorSnapshot indicators;
   if(!GoldBotPythonIndicatorSnapshot(symbol, signalTime, indicators))
   {
      GoldBotLog("Python parity indicator snapshot unavailable.");
      return false;
   }

   MqlRates m15[];
   if(!GoldBotCopyRatesWindow(symbol, PERIOD_M15, signalTime, 36, m15))
      return false;
   int count = ArraySize(m15);
   if(count < 36)
      return false;

   double recentLow = m15[count - 12].low;
   double recentHigh = m15[count - 12].high;
   for(int i = count - 12; i < count; i++)
   {
      recentLow = MathMin(recentLow, m15[i].low);
      recentHigh = MathMax(recentHigh, m15[i].high);
   }

   double previousLow = m15[count - 36].low;
   double previousHigh = m15[count - 36].high;
   for(int i = count - 36; i <= count - 13; i++)
   {
      previousLow = MathMin(previousLow, m15[i].low);
      previousHigh = MathMax(previousHigh, m15[i].high);
   }

   double close = m15[count - 1].close;
   bool sweptLow = recentLow < previousLow && close > previousLow;
   bool sweptHigh = recentHigh > previousHigh && close < previousHigh;

   if(indicators.emaLong && indicators.adxLong && indicators.rsiLong && indicators.atrPass &&
      close <= indicators.vwap && (close <= indicators.vwapLower * 1.003 || sweptLow))
   {
      direction = DIR_LONG;
      atrValue = indicators.atr;
      GoldBotPythonParityJournalSignal(signalTime, direction, close, indicators, sweptLow, sweptHigh);
      return true;
   }

   if(indicators.emaShort && indicators.adxShort && indicators.rsiShort && indicators.atrPass &&
      close >= indicators.vwap && (close >= indicators.vwapUpper * 0.997 || sweptHigh))
   {
      direction = DIR_SHORT;
      atrValue = indicators.atr;
      GoldBotPythonParityJournalSignal(signalTime, direction, close, indicators, sweptLow, sweptHigh);
      return true;
   }

   return false;
}

void GoldBotPythonParityOpen(const GoldBotDirection direction, const datetime entryTime, const double entry, const double atrValue)
{
   double risk = atrValue * InpSlAtr;
   if(risk <= 0.0 || direction == DIR_NONE)
      return;

   PythonParityTrade tradeState;
   tradeState.active = true;
   tradeState.direction = direction;
   tradeState.entryTime = entryTime;
   tradeState.entry = entry;
   tradeState.risk = risk;
   tradeState.sl = direction == DIR_LONG ? entry - risk : entry + risk;
   tradeState.tp = direction == DIR_LONG ? entry + risk * InpMinRR : entry - risk * InpMinRR;
   tradeState.barsHeld = 0;

   int size = ArraySize(parityTrades);
   ArrayResize(parityTrades, size + 1);
   parityTrades[size] = tradeState;
   GoldBotAddParityDay(entryTime);
   GoldBotLog(StringFormat("Python parity signal dir=%d entry=%.2f sl=%.2f tp=%.2f", direction, entry, tradeState.sl, tradeState.tp));
}

void GoldBotPythonParityManage(const string symbol, const MqlRates &closedBar)
{
   for(int i = ArraySize(parityTrades) - 1; i >= 0; i--)
   {
      if(!parityTrades[i].active)
         continue;

      parityTrades[i].barsHeld++;
      bool hitSL = false;
      bool hitTP = false;

      if(parityTrades[i].direction == DIR_LONG)
      {
         hitSL = closedBar.low <= parityTrades[i].sl;
         hitTP = closedBar.high >= parityTrades[i].tp;
      }
      else if(parityTrades[i].direction == DIR_SHORT)
      {
         hitSL = closedBar.high >= parityTrades[i].sl;
         hitTP = closedBar.low <= parityTrades[i].tp;
      }

      if(hitSL)
      {
         GoldBotPythonParityClose(i, closedBar.time, parityTrades[i].sl, -1.0, "SL");
         continue;
      }
      if(hitTP)
      {
         GoldBotPythonParityClose(i, closedBar.time, parityTrades[i].tp, InpMinRR, "TP");
         continue;
      }

      if(parityTrades[i].barsHeld >= InpMaxHoldBars)
      {
         double raw = parityTrades[i].direction == DIR_LONG
            ? (closedBar.close - parityTrades[i].entry) / parityTrades[i].risk
            : (parityTrades[i].entry - closedBar.close) / parityTrades[i].risk;
         double capped = MathMax(-1.0, MathMin(InpMinRR, raw));
         GoldBotPythonParityClose(i, closedBar.time, closedBar.close, capped, "MAX_HOLD");
      }
   }
}

void GoldBotPythonParityClose(const int index, const datetime exitTime, const double exitPrice, const double rr, const string exitReason)
{
   PythonParityTrade tradeState = parityTrades[index];
   GoldBotPythonParityJournalTrade(tradeState, exitTime, exitPrice, rr, exitReason);

   int rSize = ArraySize(parityRResults);
   ArrayResize(parityRResults, rSize + 1);
   parityRResults[rSize] = rr;

   parityTradesClosed++;
   if(rr > 0.0)
   {
      parityWins++;
      parityGrossWin += rr;
   }
   else if(rr < 0.0)
   {
      parityLosses++;
      parityGrossLoss += MathAbs(rr);
   }

   parityEquityR += rr;
   parityPeakR = MathMax(parityPeakR, parityEquityR);
   parityMaxDrawdownR = MathMax(parityMaxDrawdownR, parityPeakR - parityEquityR);
   GoldBotRemoveParityTrade(index);
}

void GoldBotPythonParityJournalHeader()
{
   FolderCreate("GoldBot");
   int handle = FileOpen("GoldBot\\parity_trades.csv", FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return;
   FileWrite(handle, "entry_time", "exit_time", "direction", "entry", "sl", "tp", "rr", "planned_rr", "exit_reason");
   FileClose(handle);
}

void GoldBotPythonParityJournalSignal(const datetime signalTime, const GoldBotDirection direction, const double close, const IndicatorSnapshot &indicators, const bool sweptLow, const bool sweptHigh)
{
   FolderCreate("GoldBot");
   bool exists = FileIsExist("GoldBot\\parity_signals.csv");
   int handle = FileOpen("GoldBot\\parity_signals.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return;
   FileSeek(handle, 0, SEEK_END);
   if(!exists)
   {
      FileWrite(
         handle,
         "signal_time",
         "direction",
         "close",
         "h1_ema21",
         "h1_ema50",
         "h1_ema200",
         "rsi",
         "adx",
         "plus_di",
         "minus_di",
         "atr",
         "vwap",
         "vwap_upper",
         "vwap_lower",
         "ema_long",
         "ema_short",
         "rsi_long",
         "rsi_short",
         "adx_long",
         "adx_short",
         "atr_pass",
         "swept_low",
         "swept_high"
      );
   }
   FileWrite(
      handle,
      TimeToString(signalTime, TIME_DATE | TIME_MINUTES),
      direction == DIR_LONG ? "LONG" : "SHORT",
      DoubleToString(close, _Digits),
      DoubleToString(indicators.ema21, 6),
      DoubleToString(indicators.ema50, 6),
      DoubleToString(indicators.ema200, 6),
      DoubleToString(indicators.rsi, 6),
      DoubleToString(indicators.adx, 6),
      DoubleToString(indicators.plusDI, 6),
      DoubleToString(indicators.minusDI, 6),
      DoubleToString(indicators.atr, 6),
      DoubleToString(indicators.vwap, 6),
      DoubleToString(indicators.vwapUpper, 6),
      DoubleToString(indicators.vwapLower, 6),
      indicators.emaLong ? "1" : "0",
      indicators.emaShort ? "1" : "0",
      indicators.rsiLong ? "1" : "0",
      indicators.rsiShort ? "1" : "0",
      indicators.adxLong ? "1" : "0",
      indicators.adxShort ? "1" : "0",
      indicators.atrPass ? "1" : "0",
      sweptLow ? "1" : "0",
      sweptHigh ? "1" : "0"
   );
   FileClose(handle);
}

void GoldBotPythonParityJournalTrade(const PythonParityTrade &tradeState, const datetime exitTime, const double exitPrice, const double rr, const string exitReason)
{
   FolderCreate("GoldBot");
   int handle = FileOpen("GoldBot\\parity_trades.csv", FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(handle == INVALID_HANDLE)
      return;
   FileSeek(handle, 0, SEEK_END);
   string direction = tradeState.direction == DIR_LONG ? "LONG" : "SHORT";
   FileWrite(
      handle,
      TimeToString(tradeState.entryTime, TIME_DATE | TIME_MINUTES),
      TimeToString(exitTime, TIME_DATE | TIME_MINUTES),
      direction,
      DoubleToString(tradeState.entry, _Digits),
      DoubleToString(tradeState.sl, _Digits),
      DoubleToString(tradeState.tp, _Digits),
      DoubleToString(rr, 6),
      DoubleToString(InpMinRR, 2),
      exitReason
   );
   FileClose(handle);
}

void GoldBotPythonParityPrintSummary()
{
   double winRate = parityTradesClosed > 0 ? (double)parityWins / (double)parityTradesClosed : 0.0;
   double profitFactor = parityGrossLoss > 0.0 ? parityGrossWin / parityGrossLoss : 0.0;
   double expectancy = parityTradesClosed > 0 ? parityEquityR / (double)parityTradesClosed : 0.0;
   double avgTradesDay = ArraySize(parityTradeDays) > 0 ? (double)parityTradesClosed / (double)ArraySize(parityTradeDays) : 0.0;
   Print(StringFormat(
      "GoldBot Python parity summary: trades=%d wins=%d losses=%d win_rate=%.4f profit_factor=%.4f expectancy_r=%.4f max_drawdown_r=%.4f avg_trades_day=%.4f open_trades=%d",
      parityTradesClosed,
      parityWins,
      parityLosses,
      winRate,
      profitFactor,
      expectancy,
      parityMaxDrawdownR,
      avgTradesDay,
      ArraySize(parityTrades)
   ));
}

bool GoldBotPythonIndicatorSnapshot(const string symbol, const datetime signalTime, IndicatorSnapshot &out)
{
   MqlRates h1[];
   MqlRates m15[];
   if(parityStartTime <= 0)
      return false;
   if(!GoldBotCopyRatesSinceCapped(symbol, PERIOD_M15, parityStartTime, signalTime, 2000, m15))
      return false;

   int m15Count = ArraySize(m15);
   if(!GoldBotPythonResampleH1FromM15(m15, m15Count, h1))
      return false;

   int h1Count = ArraySize(h1);
   if(h1Count < 220 || m15Count < 220)
      return false;

   out.ema21 = GoldBotPythonEMAFromRates(h1, h1Count, 21);
   out.ema50 = GoldBotPythonEMAFromRates(h1, h1Count, 50);
   out.ema200 = GoldBotPythonEMAFromRates(h1, h1Count, 200);
   out.rsi = GoldBotPythonRSIFromRates(m15, m15Count, InpRsiPeriod);
   out.atr = GoldBotPythonATRFromRates(h1, h1Count, 14);
   if(!GoldBotPythonADXFromRates(h1, h1Count, 14, out.adx, out.plusDI, out.minusDI))
      return false;
   if(!GoldBotPythonRollingVWAP(m15, m15Count, 96, out.vwap, out.vwapUpper, out.vwapLower))
      return false;

   double price = h1[h1Count - 1].close;
   double close = m15[m15Count - 1].close;
   out.emaLong = price > out.ema21 && out.ema21 > out.ema50 && out.ema50 > out.ema200;
   out.emaShort = price < out.ema21 && out.ema21 < out.ema50 && out.ema50 < out.ema200;
   out.rsiLong = out.rsi <= InpRsiLongMax;
   out.rsiShort = out.rsi >= InpRsiShortMin;
   out.vwapLong = close <= out.vwap && close <= out.vwapLower * 1.003;
   out.vwapShort = close >= out.vwap && close >= out.vwapUpper * 0.997;
   out.atrPass = out.atr >= InpAtrMin && out.atr <= InpAtrMax;
   out.adxLong = out.adx >= InpAdxMin && out.plusDI > out.minusDI;
   out.adxShort = out.adx >= InpAdxMin && out.minusDI > out.plusDI;
   return true;
}

bool GoldBotCopyRatesWindow(const string symbol, const ENUM_TIMEFRAMES tf, const datetime endTime, const int bars, MqlRates &rates[])
{
   int shift = iBarShift(symbol, tf, endTime, false);
   if(shift < 0)
      return false;

   int copied = CopyRates(symbol, tf, shift, bars, rates);
   if(copied < bars)
      return false;
   ArrayResize(rates, copied);

   if(copied > 1 && rates[0].time > rates[copied - 1].time)
   {
      for(int i = 0; i < copied / 2; i++)
      {
         MqlRates tmp = rates[i];
         rates[i] = rates[copied - 1 - i];
         rates[copied - 1 - i] = tmp;
      }
   }

   return true;
}

bool GoldBotCopyRatesSinceCapped(const string symbol, const ENUM_TIMEFRAMES tf, const datetime startTime, const datetime endTime, const int maxBars, MqlRates &rates[])
{
   int endShift = iBarShift(symbol, tf, endTime, false);
   if(endShift < 0)
      return false;

   int startShift = iBarShift(symbol, tf, startTime, false);
   int copied = 0;
   if(startShift >= endShift)
   {
      int availableBars = startShift - endShift + 1;
      int barsToCopy = MathMin(availableBars, maxBars);
      copied = CopyRates(symbol, tf, endShift, barsToCopy, rates);
   }
   else
   {
      copied = CopyRates(symbol, tf, startTime, endTime, rates);
   }

   if(copied <= 0)
      return false;
   ArrayResize(rates, copied);

   if(copied > 1 && rates[0].time > rates[copied - 1].time)
   {
      for(int i = 0; i < copied / 2; i++)
      {
         MqlRates tmp = rates[i];
         rates[i] = rates[copied - 1 - i];
         rates[copied - 1 - i] = tmp;
      }
   }

   int firstInRange = 0;
   while(firstInRange < copied && rates[firstInRange].time < startTime)
      firstInRange++;
   if(firstInRange > 0)
   {
      for(int i = firstInRange; i < copied; i++)
         rates[i - firstInRange] = rates[i];
      copied -= firstInRange;
      ArrayResize(rates, copied);
   }

   if(copied <= 0)
      return false;
   return true;
}

bool GoldBotPythonResampleH1FromM15(MqlRates &m15[], const int m15Count, MqlRates &h1[])
{
   ArrayResize(h1, 0);
   if(m15Count <= 0)
      return false;

   datetime currentBucket = 0;
   MqlRates bucket;
   int h1Count = 0;

   for(int i = 0; i < m15Count; i++)
   {
      datetime bucketTime = (datetime)((long)m15[i].time - ((long)m15[i].time % 3600));
      if(currentBucket == 0 || bucketTime != currentBucket)
      {
         if(currentBucket != 0)
         {
            ArrayResize(h1, h1Count + 1);
            h1[h1Count] = bucket;
            h1Count++;
         }

         currentBucket = bucketTime;
         bucket.time = bucketTime;
         bucket.open = m15[i].open;
         bucket.high = m15[i].high;
         bucket.low = m15[i].low;
         bucket.close = m15[i].close;
         bucket.tick_volume = m15[i].tick_volume;
         bucket.spread = m15[i].spread;
         bucket.real_volume = m15[i].real_volume;
      }
      else
      {
         bucket.high = MathMax(bucket.high, m15[i].high);
         bucket.low = MathMin(bucket.low, m15[i].low);
         bucket.close = m15[i].close;
         bucket.tick_volume += m15[i].tick_volume;
         bucket.real_volume += m15[i].real_volume;
         bucket.spread = m15[i].spread;
      }
   }

   if(currentBucket != 0)
   {
      ArrayResize(h1, h1Count + 1);
      h1[h1Count] = bucket;
      h1Count++;
   }

   return h1Count > 0;
}

double GoldBotPythonEMAFromRates(MqlRates &rates[], const int count, const int period)
{
   double alpha = 2.0 / (period + 1.0);
   double current = rates[0].close;
   for(int i = 0; i < count; i++)
      current = rates[i].close * alpha + current * (1.0 - alpha);
   return current;
}

double GoldBotPythonRSIFromRates(MqlRates &rates[], const int count, const int period)
{
   double gains[];
   double losses[];
   double avgGain[];
   double avgLoss[];
   ArrayResize(gains, count);
   ArrayResize(losses, count);
   for(int i = 0; i < count; i++)
   {
      double diff = i == 0 ? 0.0 : rates[i].close - rates[i - 1].close;
      gains[i] = MathMax(diff, 0.0);
      losses[i] = MathMax(-diff, 0.0);
   }
   GoldBotPythonRMA(gains, count, period, avgGain);
   GoldBotPythonRMA(losses, count, period, avgLoss);
   if(avgLoss[count - 1] == 0.0)
      return 100.0;
   return 100.0 - 100.0 / (1.0 + avgGain[count - 1] / avgLoss[count - 1]);
}

double GoldBotPythonATRFromRates(MqlRates &rates[], const int count, const int period)
{
   double ranges[];
   double atrValues[];
   ArrayResize(ranges, count);
   for(int i = 0; i < count; i++)
   {
      double prevClose = i == 0 ? rates[i].close : rates[i - 1].close;
      ranges[i] = MathMax(rates[i].high - rates[i].low, MathMax(MathAbs(rates[i].high - prevClose), MathAbs(rates[i].low - prevClose)));
   }
   GoldBotPythonRMA(ranges, count, period, atrValues);
   return atrValues[count - 1];
}

bool GoldBotPythonADXFromRates(MqlRates &rates[], const int count, const int period, double &adx, double &plusDI, double &minusDI)
{
   if(count < period + 2)
      return false;

   double tr[];
   double plusDM[];
   double minusDM[];
   double atrValues[];
   double plusRma[];
   double minusRma[];
   double dx[];
   double adxValues[];
   ArrayResize(tr, count);
   ArrayResize(plusDM, count);
   ArrayResize(minusDM, count);
   ArrayResize(dx, count);

   for(int i = 0; i < count; i++)
   {
      int prevIndex = i == 0 ? 0 : i - 1;
      double upMove = rates[i].high - rates[prevIndex].high;
      double downMove = rates[prevIndex].low - rates[i].low;
      tr[i] = MathMax(rates[i].high - rates[i].low, MathMax(MathAbs(rates[i].high - rates[prevIndex].close), MathAbs(rates[i].low - rates[prevIndex].close)));
      plusDM[i] = upMove > downMove && upMove > 0.0 ? upMove : 0.0;
      minusDM[i] = downMove > upMove && downMove > 0.0 ? downMove : 0.0;
   }

   GoldBotPythonRMA(tr, count, period, atrValues);
   GoldBotPythonRMA(plusDM, count, period, plusRma);
   GoldBotPythonRMA(minusDM, count, period, minusRma);

   for(int i = 0; i < count; i++)
   {
      double p = 100.0 * plusRma[i] / MathMax(atrValues[i], 0.000000001);
      double m = 100.0 * minusRma[i] / MathMax(atrValues[i], 0.000000001);
      dx[i] = 100.0 * MathAbs(p - m) / MathMax(p + m, 0.000000001);
      if(i == count - 1)
      {
         plusDI = p;
         minusDI = m;
      }
   }

   GoldBotPythonRMA(dx, count, period, adxValues);
   adx = adxValues[count - 1];
   return true;
}

bool GoldBotPythonRollingVWAP(MqlRates &rates[], const int count, const int bars, double &vwap, double &upper, double &lower)
{
   if(count < bars)
      return false;

   double pv = 0.0;
   double volume = 0.0;
   double typicals[];
   ArrayResize(typicals, bars);
   int start = count - bars;
   for(int i = start; i < count; i++)
   {
      double typical = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      double vol = rates[i].tick_volume > 0 ? (double)rates[i].tick_volume : 1.0;
      int outIndex = i - start;
      typicals[outIndex] = typical;
      pv += typical * vol;
      volume += vol;
   }

   vwap = pv / MathMax(volume, 1.0);
   double variance = 0.0;
   for(int i = 0; i < bars; i++)
      variance += MathPow(typicals[i] - vwap, 2.0);
   double dev = MathSqrt(variance / bars);
   upper = vwap + dev;
   lower = vwap - dev;
   return true;
}

void GoldBotPythonRMA(double &values[], const int count, const int period, double &out[])
{
   ArrayResize(out, count);
   double initial = 0.0;
   int initialCount = MathMax(1, MathMin(period, count));
   for(int i = 0; i < initialCount; i++)
      initial += values[i];
   double current = initial / initialCount;

   for(int i = 0; i < count; i++)
   {
      if(i < period)
      {
         double sum = 0.0;
         for(int j = 0; j <= i; j++)
            sum += values[j];
         current = sum / (i + 1);
      }
      else
         current = (current * (period - 1) + values[i]) / period;
      out[i] = current;
   }
}

bool GoldBotPythonInSession(const datetime timeValue)
{
   if(InpSessionFilter == "" || InpSessionFilter == "all")
      return true;

   MqlDateTime t;
   TimeToStruct(timeValue, t);
   bool london = t.hour >= 7 && t.hour < 12;
   bool overlap = t.hour >= 12 && t.hour < 16;
   bool ny = t.hour >= 16 && t.hour < 21;
   if(InpSessionFilter == "london_ny")
      return london || overlap || ny;
   if(InpSessionFilter == "london")
      return london;
   if(InpSessionFilter == "ny")
      return ny || overlap;
   return true;
}

void GoldBotAddParityDay(const datetime entryTime)
{
   string day = TimeToString(entryTime, TIME_DATE);
   for(int i = 0; i < ArraySize(parityTradeDays); i++)
   {
      if(parityTradeDays[i] == day)
         return;
   }
   int size = ArraySize(parityTradeDays);
   ArrayResize(parityTradeDays, size + 1);
   parityTradeDays[size] = day;
}

void GoldBotRemoveParityTrade(const int index)
{
   int total = ArraySize(parityTrades);
   if(index < 0 || index >= total)
      return;
   for(int i = index; i < total - 1; i++)
      parityTrades[i] = parityTrades[i + 1];
   ArrayResize(parityTrades, total - 1);
}
