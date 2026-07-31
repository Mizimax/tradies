#property strict
#property version   "3.00"
#property description "Gold XAU/USD SMC + confluence Expert Advisor"

#include <Trade/Trade.mqh>
#include <GoldBot/Indicators.mqh>
#include <GoldBot/SMC.mqh>
#include <GoldBot/Risk.mqh>
#include <GoldBot/TradeManager.mqh>
#include <GoldBot/PropMode.mqh>
#include <GoldBot/EntryFilters.mqh>

#define GOLDBOT_SETUP_SMC 1
#define GOLDBOT_SETUP_CONTINUATION 2
#define GOLDBOT_SETUP_BREAKOUT_RETEST 3
#define GOLDBOT_SETUP_M5_SCALP 4
#define GOLDBOT_SETUP_M1_MICRO_SCALP 5

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
input double          InpStressExtraSpreadPrice = 0.0; // extra spread stress (raw price units) widened into every ladder SL; 0 = no change
input int             InpMaxHoldBars = 48;
input int             InpCooldownBars = 16;
input int             InpStreakCooldownBars = 48;
input int             InpLadderFillGapBars = 4;
input int             InpMaxOpenTrades = 2;
input double          InpMaxDailyLossPct = 3.0;
input double          InpMaxMonthlyLossPct = 5.0;
input double          InpDailyTargetPct = 5.0;
input bool            InpEnableCompoundGovernor = false;
input double          InpCompoundMaxDrawdownPct = 30.0;
input double          InpCompoundSoftDrawdownPct = 10.0;
input double          InpCompoundHardThrottleDrawdownPct = 20.0;
input double          InpCompoundSoftRiskMultiplier = 0.75;
input double          InpCompoundHardRiskMultiplier = 0.50;
input double          InpCompoundMonthlyProfitLockPct = 0.0;
input double          InpCompoundMonthlyProfitLockMultiplier = 0.50;
input bool            InpEnableMonthlyLossThrottle = false;
input double          InpMonthlyLossSoftPct = 1.5;
input double          InpMonthlyLossHardPct = 4.0;
input double          InpMonthlyLossSoftRiskMultiplier = 0.50;
input bool            InpMonthlyLossHardBlock = true;
input bool            InpEnableRollingPerformanceGovernor = false;
input int             InpRollingLookbackClosedTrades = 20;
input double          InpRollingMinNetR = -1.0;
input double          InpRollingMinWinRatePct = 45.0;
input double          InpRollingThrottleMultiplier = 0.35;
input int             InpRollingPauseMinutes = 720;
input bool            InpRollingApplyToM5 = true;
input bool            InpRollingApplyToM15 = true;
input int             InpAthLookbackBars = 0;
input double          InpAthProximityPct = 0.0;
input int             InpMinMonthlyTrades = 0;
input double          InpElevatedScoreThreshold = 0.0;
input double          InpRsiOverboughtGate = 0.0;
input bool            InpEnableTelegram = false;
input bool            InpDebugOnly = false;
input bool            InpResetJournalOnInit = true;
input bool            InpEnableChartDashboard = false;
input ENUM_BASE_CORNER InpDashboardCorner = CORNER_LEFT_UPPER;
input int             InpDashboardUpdateSeconds = 5;
input bool            InpDashboardVerbose = false;
input bool            InpEnableForwardEventLog = true;
input string          InpForwardEventFile = "GoldBot/forward_events.csv";
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
input bool            InpEnableSmcSetup = true;
input string          InpSmcAllowedLongHours = "";
input string          InpSmcAllowedShortHours = "";
input double          InpSmcMinScore = 0.0;
input bool            InpSmcRequireHtfContext = false;
input bool            InpEnableRegimeFilter = false;
input int             InpRegimeSlopeBars = 24;
input double          InpRegimeMinSlopeAtr = 0.0;
input double          InpRegimeMaxExtensionAtr = 3.0;
input bool            InpRegimeRequireH1Direction = false;
input bool            InpEnableRobustRegimeFilter = false;
input bool            InpRobustApplyToM5 = true;
input bool            InpRobustApplyToM15 = true;
input double          InpRobustMinH1Adx = 18.0;
input double          InpRobustMinH1AtrRatio = 0.75;
input double          InpRobustMaxH1AtrRatio = 1.80;
input double          InpRobustMinH1EmaSlopeAtr = 0.03;
input double          InpRobustBlockIfMonthlyLossPct = 0.0;
input bool            InpEnableStrictHourQuality = false;
input string          InpStrictLongHours = "";
input string          InpStrictShortHours = "";
input double          InpStrictHourMinAdx = 18.0;
input double          InpStrictHourMinDiGap = 4.0;
input bool            InpStrictHourRequireVwap = false;
input bool            InpStrictHourRequireEma = false;
input bool            InpStrictHourRequireM5Pullback = false;
input int             InpStrictHourPullbackChecks = 2;
input bool            InpEnableHourSplitGuard = false;
input string          InpSplit1OnlyLongHours = "";
input string          InpSplit1OnlyShortHours = "";
input string          InpSplit2OnlyLongHours = "";
input string          InpSplit2OnlyShortHours = "";
input bool            InpEnableContinuationPullbackSetup = false;
input string          InpContinuationLongHours = "";
input string          InpContinuationShortHours = "";
input double          InpContinuationMinAdx = 18.0;
input double          InpContinuationMinDiGap = 4.0;
input bool            InpContinuationRequireVwap = true;
input bool            InpContinuationRequireEma = true;
input bool            InpContinuationRequireM5Pullback = true;
input int             InpContinuationPullbackChecks = 2;
input double          InpContinuationZoneAtr = 0.35;
input bool            InpEnableBreakoutRetestSetup = false;
input string          InpBreakoutLongHours = "";
input string          InpBreakoutShortHours = "";
input string          InpBreakoutAllowedLongHours = "";
input string          InpBreakoutAllowedShortHours = "";
input int             InpBreakoutLookbackBars = 16;
input double          InpBreakoutRangeBufferAtr = 0.10;
input double          InpBreakoutMinBodyAtr = 0.35;
input double          InpMinBodyRatio = 0.35;
input double          InpVolumeMultiplier = 1.1;
input double          InpBreakoutMinAdx = 18.0;
input double          InpBreakoutMinDiGap = 4.0;
input bool            InpBreakoutRequireEma = true;
input bool            InpBreakoutRequireVwap = true;
input bool            InpBreakoutRequireH1Trend = true;
input double          InpBreakoutZoneAtr = 0.25;
input double          InpBreakoutMaxZoneAtr = 0.80;
input double          InpBreakoutBaseScore = 25.0;
input bool            InpEnableM5ScalpSetup = false;
input string          InpScalpLongHours = "7;10;12;18";
input string          InpScalpShortHours = "7;10";
input double          InpScalpMinAdx = 18.0;
input double          InpScalpMinDiGap = 4.0;
input bool            InpScalpRequireH1Trend = true;
input bool            InpScalpRequireM15Direction = true;
input double          InpScalpMaxSpreadPrice = 0.50;
input int             InpScalpPendingExpiryMinutes = 15;
input int             InpScalpMaxHoldMinutes = 90;
input double          InpScalpSlAtr = 0.35;
input double          InpScalpLongSlAtr = 0.0;
input double          InpScalpShortSlAtr = 0.0;
input double          InpScalpTp1R = 0.5;
input double          InpScalpTp2R = 0.8;
input double          InpScalpTp3R = 1.2;
input int             InpScalpLadderOrderCount = 1;
input double          InpScalpLotMultiplier = 0.50;
input int             InpScalpMaxTradesPerDay = 8;
input bool            InpEnableShortTermScalp = false;
input string          InpShortTermBaseMode = "freq100i";
input double          InpShortTermMaxDailyLossR = 2.5;
input int             InpShortTermMaxConsecutiveScalpLosses = 3;
input int             InpShortTermPauseAfterLossMinutes = 90;
input double          InpScalpMaxSpreadToTp1Pct = 25.0;
input bool            InpScalpEnableVolatilityRegime = true;
input int             InpScalpAtrLookbackBars = 96;
input double          InpScalpMinAtrRatio = 0.70;
input double          InpScalpMaxAtrRatio = 1.80;
input bool            InpScalpEnableClassicPullback = true;
input bool            InpScalpEnableLiquiditySweepReclaim = false;
input bool            InpScalpEnableSessionBreakoutRetest = false;
input int             InpScalpSweepLookbackBars = 12;
input int             InpScalpBreakoutLookbackBars = 16;
input double          InpScalpBreakoutBufferAtr = 0.05;
input double          InpScalpBreakEvenAtR = 0.35;
input double          InpScalpTrailStartR = 0.70;
input int             InpScalpTimeStopMinutes = 45;
input double          InpSmcRiskMultiplier = 1.0;
input double          InpBreakoutRiskMultiplier = 1.0;
input double          InpM5ScalpRiskMultiplier = 1.0;
input double          InpM5ScalpLongRiskMultiplier = 0.0;
input double          InpM5ScalpShortRiskMultiplier = 0.0;
input double          InpM1MicroRiskMultiplier = 1.0;
input bool            InpEnableM1MicroScalpSetup = false;
input string          InpM1MicroLongHours = "10;18";
input string          InpM1MicroShortHours = "7;8;10";
input double          InpM1MicroMinAdx = 18.0;
input double          InpM1MicroMinDiGap = 4.0;
input bool            InpM1MicroRequireH1Trend = true;
input bool            InpM1MicroRequireM15Direction = true;
input bool            InpM1MicroRequireM5Direction = true;
input double          InpM1MicroMaxSpreadPrice = 0.35;
input double          InpM1MicroMaxSpreadToTp1Pct = 20.0;
input bool            InpM1MicroEnableVolatilityRegime = true;
input int             InpM1MicroAtrLookbackBars = 120;
input double          InpM1MicroMinAtrRatio = 0.75;
input double          InpM1MicroMaxAtrRatio = 1.70;
input int             InpM1MicroPendingExpiryMinutes = 4;
input int             InpM1MicroMaxHoldMinutes = 20;
input double          InpM1MicroSlAtr = 0.22;
input double          InpM1MicroTp1R = 0.25;
input double          InpM1MicroTp2R = 0.45;
input double          InpM1MicroTp3R = 0.75;
input int             InpM1MicroLadderOrderCount = 1;
input double          InpM1MicroLotMultiplier = 0.20;
input int             InpM1MicroMaxTradesPerDay = 8;
input double          InpM1MicroBreakEvenAtR = 0.25;
input double          InpM1MicroTrailStartR = 0.50;
input int             InpM1MicroTimeStopMinutes = 20;
input string          InpAllowedEntryHours = "";
input string          InpAllowedLongEntryHours = "";
input string          InpAllowedShortEntryHours = "";
input int             InpLongSessionEndHour = 0;
input bool            InpAllowLong = true;
input bool            InpAllowShort = true;

//--- Prop-firm mode (opt-in; InpEnablePropMode=false is the default and makes every input
//--- below a no-op -- see mt5/Include/GoldBot/PropMode.mqh and mt5/backtests/PROPGUARD_DESIGN.md.
//--- Ported from the proven mt5/Include/PropGuard/{PropRules,RiskBudget}.mqh rule engine.
input bool            InpEnablePropMode = false;
input bool            InpPropMonitorOnly = false;             // enforce hard account floors without changing entries or sizing
input double          InpPropFirmDailyLossPct = 5.0;
input double          InpPropFirmMaxDrawdownPct = 10.0;
input bool            InpPropDdIsTrailing = false;
input double          InpPropPhaseTargetPct = 10.0;         // active challenge phase's profit target
input double          InpPropDailySoftHaltPct = 2.0;
input double          InpPropDailyHardFlattenPct = 2.5;
input double          InpPropDdHardHaltPct = 8.0;
input double          InpPropDailyProfitCapPct = 2.5;
input double          InpPropTargetProximityPct = 1.5;
input double          InpPropTargetLockBufferPct = 0.10;  // close all once equity clears phase target plus costs
input double          InpPropCostGateMaxPct = 8.0;
input double          InpPropChallengeRiskPct = 1.00;        // base risk % of equity per trade
input int             InpPropDailyRiskDivisor = 3;
input int             InpPropTotalRiskDivisor = 8;
input int             InpPropDailyResetServerHour = 0;
input int             InpPropFridayCloseHour = 20;
input int             InpPropRolloverBlockStartHour = 21;
input int             InpPropRolloverBlockEndHour = 23;
input int             InpPropMaxOpenAndPending = 1;          // pending-inclusive concurrency cap
input double          InpPropMaxSpreadPrice = 0.80;          // M15 path has no spread cap outside prop mode
input double          InpPropM5MaxSpreadPrice = 0.35;        // tightens InpScalpMaxSpreadPrice under prop mode
input double          InpPropM1MaxSpreadPrice = 0.25;        // tightens InpM1MicroMaxSpreadPrice under prop mode
input bool            InpPropForceNewsFilter = true;         // forces news blackout for all 3 entry paths
input double          InpPropCommissionPerLotUsd = 7.0;
input double          InpPropSwapEstimatePerLotUsd = 1.0;

CTrade trade;
datetime lastM15Bar = 0;
datetime lastM5Bar = 0;
datetime lastM1Bar = 0;
datetime lastParityClosedBar = 0;
datetime parityStartTime = 0;
datetime lastPropBreachLogDay = 0;

//--- Builds the prop-mode config struct from Inp* inputs. Cheap (plain struct assignment), so
//--- it is safe to call fresh every tick rather than caching -- keeps every prop-mode call site
//--- (OnInit, OnTick monitor, entry gate, sizing gate) reading the same live input values.
GoldBotPropConfig GoldBotBuildPropConfig()
{
   GoldBotPropConfig cfg;
   cfg.enabled = InpEnablePropMode;
   cfg.firmDailyLossPct = InpPropFirmDailyLossPct;
   cfg.firmMaxDrawdownPct = InpPropFirmMaxDrawdownPct;
   cfg.ddIsTrailing = InpPropDdIsTrailing;
   cfg.phaseTargetPct = InpPropPhaseTargetPct;
   cfg.dailySoftHaltPct = InpPropDailySoftHaltPct;
   cfg.dailyHardFlattenPct = InpPropDailyHardFlattenPct;
   cfg.ddHardHaltPct = InpPropDdHardHaltPct;
   cfg.dailyProfitCapPct = InpPropDailyProfitCapPct;
   cfg.targetProximityPct = InpPropTargetProximityPct;
   cfg.targetLockBufferPct = InpPropTargetLockBufferPct;
   cfg.costGateMaxPct = InpPropCostGateMaxPct;
   cfg.challengeRiskPct = InpPropChallengeRiskPct;
   cfg.dailyRiskDivisor = InpPropDailyRiskDivisor;
   cfg.totalRiskDivisor = InpPropTotalRiskDivisor;
   cfg.dailyResetServerHour = InpPropDailyResetServerHour;
   cfg.fridayCloseHour = InpPropFridayCloseHour;
   cfg.rolloverBlockStartHour = InpPropRolloverBlockStartHour;
   cfg.rolloverBlockEndHour = InpPropRolloverBlockEndHour;
   cfg.maxOpenAndPending = InpPropMaxOpenAndPending;
   cfg.maxSpreadPriceM15 = InpPropMaxSpreadPrice;
   cfg.maxSpreadPriceM5 = InpPropM5MaxSpreadPrice;
   cfg.maxSpreadPriceM1 = InpPropM1MaxSpreadPrice;
   cfg.forceNewsFilter = InpPropForceNewsFilter;
   cfg.commissionPerLotUsd = InpPropCommissionPerLotUsd;
   cfg.swapEstimatePerLotUsd = InpPropSwapEstimatePerLotUsd;
   return cfg;
}

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

string dashboardStatus = "INIT";
string dashboardBlocker = "";
string dashboardHint = "Waiting for first tick";
string dashboardSmcState = "not checked";
string dashboardBreakoutState = "not checked";
string dashboardM5State = "not checked";
string dashboardM1State = "not checked";
string dashboardLastSetup = "";
string dashboardLastSignalId = "";
string dashboardLastEventKey = "";
datetime dashboardLastTick = 0;

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
string GoldBotSetupName(const int setupCode);
bool GoldBotLongSessionEndAllowed(const GoldBotDirection direction, const int longSessionEndHour);
bool GoldBotAllowedEntryHour(const string allowedHours);
bool GoldBotDirectionAllowedEntryHour(const GoldBotDirection direction, const string allowedLongHours, const string allowedShortHours);
bool GoldBotHourListContains(const string allowedHours, const int targetHour);
bool GoldBotStrictHourApplies(const GoldBotDirection direction, const string strictLongHours, const string strictShortHours);
bool GoldBotOptionalDirectionHourPass(const GoldBotDirection direction, const string allowedLongHours, const string allowedShortHours);
bool GoldBotStrictHourQualityPass(const string symbol, const GoldBotDirection direction, const EntryZone &zone, const IndicatorSnapshot &indicators, const bool emaPass, const bool vwapPass, const double score, const int confluenceCount, const int enabledConfluences);
bool GoldBotSmcSetupAllocationPass(const SMCResult &smc, const double score);
bool GoldBotContextLongEntryPass(const string symbol, const GoldBotDirection direction, const int setupCode, const double score, const int confluenceCount, const int enabledConfluences);
void GoldBotResetEntryZone(EntryZone &zone);
bool GoldBotBuildContinuationEntryZone(const string symbol, const IndicatorSnapshot &indicators, EntryZone &zone);
bool GoldBotContinuationSetupPass(const string symbol, const GoldBotDirection direction, const IndicatorSnapshot &indicators, const bool emaPass, const bool vwapPass, const double score, const int confluenceCount, const int enabledConfluences, EntryZone &zone);
bool GoldBotBreakoutH1TrendPass(const string symbol, const GoldBotDirection direction);
bool GoldBotBuildBreakoutRetestZone(const string symbol, const GoldBotDirection direction, const double breakoutLevel, const IndicatorSnapshot &indicators, EntryZone &zone);
bool GoldBotBreakoutRetestSetupPass(const string symbol, const IndicatorSnapshot &indicators, GoldBotDirection &direction, double &score, EntryZone &zone);
bool GoldBotBreakoutVolumePass(const string symbol, const double multiplier, long &volume, double &averageVolume, double &requiredVolume);
bool GoldBotIsNewM5Bar(const string symbol);
bool GoldBotIsNewM1Bar(const string symbol);
bool GoldBotM5ScalpAllowedToday(int &currentCount);
void GoldBotMarkM5ScalpPlaced();
bool GoldBotM1MicroAllowedToday(int &currentCount);
void GoldBotMarkM1MicroPlaced();
bool GoldBotShortTermScalpAllowed(double &dailyR, int &losses, datetime &pauseUntil);
void GoldBotUpdateShortTermScalpState(const double profit, const double riskCash);
bool GoldBotM15DirectionPass(const string symbol, const GoldBotDirection direction, bool &longAligned, bool &shortAligned);
bool GoldBotM5DirectionPass(const string symbol, const GoldBotDirection direction, bool &longAligned, bool &shortAligned);
bool GoldBotBuildM5ScalpZone(const GoldBotDirection direction, const double ema21, const double vwap, const double atr, EntryZone &zone);
bool GoldBotBuildM5LevelScalpZone(const GoldBotDirection direction, const double level, const double ema21, const double vwap, const double atr, EntryZone &zone);
bool GoldBotM5RecentRange(MqlRates &rates[], const int count, const int startIndex, const int lookbackBars, double &rangeHigh, double &rangeLow);
bool GoldBotM5VolatilityRegimePass(MqlRates &rates[], const int count, const double currentAtr, double &averageAtr, double &atrRatio);
bool GoldBotM1MicroVolatilityRegimePass(MqlRates &rates[], const int count, const double currentAtr, double &averageAtr, double &atrRatio);
bool GoldBotM5LiquiditySweepReclaimPass(MqlRates &rates[], const int count, const GoldBotDirection direction, const double ema21, const double vwap, const double atr, double &sweepLevel);
bool GoldBotM5SessionBreakoutRetestPass(MqlRates &rates[], const int count, const GoldBotDirection direction, const double ema21, const double vwap, const double atr, double &breakoutLevel);
bool GoldBotScalpDynamicCostPass(const GoldBotDirection direction, const double spread, const double risk, const double tp1R, double &tp1Distance, double &spreadToTpPct);
bool GoldBotMicroDynamicCostPass(const GoldBotDirection direction, const double spread, const double risk, const double tp1R, double &tp1Distance, double &spreadToTpPct);
double GoldBotSetupRiskMultiplier(const int setupCode);
bool GoldBotTryM5Scalp(const string symbol);
bool GoldBotTryM1MicroScalp(const string symbol);
void GoldBotApplyHourSplitGuard(const GoldBotDirection direction, const double score, const int confluenceCount, const int enabledConfluences, int &ladderOrderCount, int &ladderFirstSplit);
bool GoldBotRegimePass(const string symbol, const GoldBotDirection direction, const SMCResult &smc, const bool enabled, const int slopeBars, const double minSlopeAtr, const double maxExtensionAtr, const bool requireH1Direction, const double score, const int confluenceCount, const int enabledConfluences, double &slopeAtr, double &extensionAtr);
double GoldBotAverageATR(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const int startShift, const int bars);
bool GoldBotRobustMonthlyRiskAllowed(double &monthlyPnlPct, bool &monthlyBlocked);
bool GoldBotRobustRegimePass(const string symbol, const string setupName, const GoldBotDirection direction, const bool isM5Setup, const double score, const int confluenceCount, const int enabledConfluences);
string GoldBotMagicKey(const string suffix);
int GoldBotMonthCode(const datetime timeValue);
void GoldBotResetRollingPerformanceState();
void GoldBotUpdateRollingPerformanceState(const double profit, const double riskCash, const int setupCode);
bool GoldBotRollingPerformanceGovernorPass(const string symbol, const string setupName, const int setupCode, const GoldBotDirection direction, const int entryHour, double &multiplier, string &reason);
bool GoldBotCompoundGovernorPass(const string symbol, const string setupName, const int setupCode, const GoldBotDirection direction, const int entryHour, const double stopDistancePrice, const double spreadPrice, double &effectiveLotPer100Usd);
void GoldBotResetMonthlyTradeCounterIfNeeded(const datetime timeValue);
int GoldBotMonthlyCompletedTradeCount(const datetime timeValue);
void GoldBotIncrementMonthlyCompletedTrades(const datetime timeValue);
double GoldBotEffectiveScoreThreshold(const double baseThreshold, const int monthTrades, const datetime timeValue);
bool GoldBotMonthlyRiskAllowed(const double maxMonthlyLossPct, double &pnlPct);
bool GoldBotStreakCooldownAllowed(double &remainingMinutes, datetime &cooldownEnd, int &consecutiveLosses);
void GoldBotUpdateLossStreak(const double profit);
void GoldBotDashboardSetState(const string status, const string blocker, const string hint);
void GoldBotDashboardSetSetupState(const string setupName, const string state);
void GoldBotDashboardBlock(const string setupName, const GoldBotDirection direction, const string reason, const double score, const int confluences, const string signalId);
void GoldBotDashboardWait(const string setupName, const GoldBotDirection direction, const string reason, const double score, const int confluences);
void GoldBotDashboardAccepted(const string setupName, const GoldBotDirection direction, const string signalId, const double score, const int confluences);
void GoldBotDashboardOrderPlaced(const string setupName, const GoldBotDirection direction, const string signalId, const int orderCount);
void GoldBotDashboardRefresh();
void GoldBotDashboardDelete();
void GoldBotDashboardLabel(const string name, const int row, const string text, const color textColor);
int GoldBotCountManagedPendingOrders(const string symbol, const long magic);
string GoldBotDashboardTime(const datetime value);
string GoldBotForwardEventPath();
void GoldBotForwardEvent(const string eventName, const string setupName, const GoldBotDirection direction, const string reason, const double score, const int confluences, const string signalId, const bool alwaysWrite);
double GoldBotReadDailyPnlPct(bool &available);
double GoldBotReadMonthlyPnlPct(bool &available);

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
   if((InpEnableCompoundGovernor || InpEnableMonthlyLossThrottle) && (bool)MQLInfoInteger(MQL_TESTER))
   {
      GlobalVariableDel(GoldBotMagicKey("CompoundPeakEquity"));
      GlobalVariableDel(GoldBotMagicKey("CompoundMonth"));
      GlobalVariableDel(GoldBotMagicKey("CompoundMonthStartEquity"));
      GlobalVariableDel(GoldBotMagicKey("CompoundMonthProfitLock"));
      GoldBotJournal("Compound governor tester state reset");
   }
   if(InpEnableRobustRegimeFilter && (bool)MQLInfoInteger(MQL_TESTER))
   {
      GlobalVariableDel(GoldBotMagicKey("RobustMonth"));
      GlobalVariableDel(GoldBotMagicKey("RobustMonthStartEquity"));
      GlobalVariableDel(GoldBotMagicKey("RobustMonthlyHalt"));
      GoldBotJournal("Robust regime tester state reset");
   }
   if(InpEnableRollingPerformanceGovernor && (bool)MQLInfoInteger(MQL_TESTER))
      GoldBotResetRollingPerformanceState();
   if(InpEnablePropMode)
   {
      if((bool)MQLInfoInteger(MQL_TESTER))
         GoldBotPropResetTesterAnchors(InpMagicNumber);
      GoldBotPropInitialBalance(InpMagicNumber);
      GoldBotPropEquityPeak(InpMagicNumber, AccountInfoDouble(ACCOUNT_EQUITY));
      GoldBotJournal(StringFormat("Prop mode enabled monitorOnly=%s challengeRiskPct=%.3f phaseTargetPct=%.2f firmDailyLossPct=%.2f firmMaxDrawdownPct=%.2f ddIsTrailing=%s",
         InpPropMonitorOnly ? "yes" : "no",
         InpPropChallengeRiskPct,
         InpPropPhaseTargetPct,
         InpPropFirmDailyLossPct,
         InpPropFirmMaxDrawdownPct,
         InpPropDdIsTrailing ? "yes" : "no"));
      GoldBotJournal(StringFormat("Prop symbol specification symbol=%s contractSize=%.4f tickSize=%.8f tickValue=%.8f tickValueProfit=%.8f tickValueLoss=%.8f cashPerPriceUnit=%.4f volumeMin=%.4f volumeStep=%.4f volumeMax=%.4f commissionPerLotUsd=%.2f",
         symbol,
         SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE),
         SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE),
         SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE),
         SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT),
         SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS),
         GoldBotPropCashPerPriceUnitPerLot(symbol),
         SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
         SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP),
         SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX),
         InpPropCommissionPerLotUsd));
   }
   GoldBotDashboardSetState(InpDebugOnly ? "DEBUG ONLY" : "LIVE", "", "EA initialized; waiting for market data");
   GoldBotDashboardSetSetupState("smc", "not checked");
   GoldBotDashboardSetSetupState("breakout_retest", "not checked");
   GoldBotDashboardSetSetupState("m5_scalp", InpEnableM5ScalpSetup ? "not checked" : "disabled");
   GoldBotDashboardSetSetupState("m1_micro_scalp", InpEnableM1MicroScalpSetup ? "not checked" : "disabled");
   if(InpEnableChartDashboard)
   {
      EventSetTimer(MathMax(1, InpDashboardUpdateSeconds));
      GoldBotDashboardRefresh();
   }
   GoldBotForwardEvent("ea_init", "", DIR_NONE, "initialized", 0.0, -1, "", true);
   Print("GoldBot initialized for ", symbol, " magic=", InpMagicNumber);
   if(InpStressExtraSpreadPrice > 0.0)
      GoldBotJournal(StringFormat("Spread stress active extraSpreadPrice=%.4f", InpStressExtraSpreadPrice));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   GoldBotForwardEvent("ea_deinit", "", DIR_NONE, StringFormat("reason=%d", reason), 0.0, -1, "", true);
   if(InpEnableChartDashboard)
   {
      EventKillTimer();
      GoldBotDashboardDelete();
   }
   if(InpPythonParityMode)
      GoldBotPythonParityPrintSummary();
}

void OnTimer()
{
   if(InpEnableChartDashboard)
      GoldBotDashboardRefresh();
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
   {
      GoldBotCopyOrderMetadataToPosition(orderTicket, positionId, comment, dealType);
      if(InpLadderFillGapBars > 0)
      {
         long fillSignalCode = GoldBotSignalCodeFromComment(comment);
         if(fillSignalCode > 0)
         {
            string fillKey = StringFormat("GoldBot_LastFill_%I64d_%I64d", InpMagicNumber, fillSignalCode);
            datetime gapEnd = TimeCurrent() + InpLadderFillGapBars * PeriodSeconds(PERIOD_M15);
            GlobalVariableSet(fillKey, (double)TimeCurrent());
            int cancelledOnFill = GoldBotCancelSiblingPendingSplitsBySignalCode(symbol, InpMagicNumber, fillSignalCode, "ladder_gap_cancel", trade);
            GoldBotJournal(StringFormat("Ladder fill gap processed signalCode=%I64d bars=%d gapEnd=%s cancelled=%d",
               fillSignalCode,
               InpLadderFillGapBars,
               TimeToString(gapEnd, TIME_DATE | TIME_MINUTES),
               cancelledOnFill));
         }
      }
   }

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
   int setupCode = (int)GoldBotMetadataValue(posKey, "setup", (double)GOLDBOT_SETUP_SMC);
   int scalpVariantCode = (int)GoldBotMetadataValue(posKey, "scalpVariant", 0.0);
   long signalCode = (long)GoldBotMetadataValue(posKey, "signalCode", (double)GoldBotSignalCodeFromComment(comment));
   string setupName = GoldBotSetupName(setupCode);
   double riskCash = GoldBotMetadataValue(posKey, "riskCash", 0.0);
   double featureSpread = GoldBotMetadataValue(posKey, "spread", 0.0);
   double featureSpreadToTpPct = GoldBotMetadataValue(posKey, "spreadToTpPct", 0.0);
   double featureAdx = GoldBotMetadataValue(posKey, "adx", 0.0);
   double featureDiGap = GoldBotMetadataValue(posKey, "diGap", 0.0);
   double featureAtr = GoldBotMetadataValue(posKey, "atr", 0.0);
   double featureAtrRatio = GoldBotMetadataValue(posKey, "atrRatio", 0.0);
   double featureEma21 = GoldBotMetadataValue(posKey, "ema21", 0.0);
   double featureEma50 = GoldBotMetadataValue(posKey, "ema50", 0.0);
   double featureVwap = GoldBotMetadataValue(posKey, "vwap", 0.0);
   double featureZoneBottom = GoldBotMetadataValue(posKey, "zoneBottom", 0.0);
   double featureZoneTop = GoldBotMetadataValue(posKey, "zoneTop", 0.0);
   double featureZoneWidth = GoldBotMetadataValue(posKey, "zoneWidth", MathAbs(featureZoneTop - featureZoneBottom));
   double featureSlDistance = GoldBotMetadataValue(posKey, "slDistance", 0.0);
   double featureLotMultiplier = GoldBotMetadataValue(posKey, "lotMultiplier", 0.0);
   double featureSetupRiskMultiplier = GoldBotMetadataValue(posKey, "setupRiskMultiplier", 0.0);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(trans.deal, DEAL_COMMISSION) +
                   HistoryDealGetDouble(trans.deal, DEAL_SWAP);

   GoldBotJournal(StringFormat("Deal event deal=%I64u position=%I64d entry=%d type=%d reason=%d price=%.2f volume=%.2f profit=%.2f dir=%d split=%d hour=%d scoreBucket=%.0f confluences=%d/%d setup=%s scalpVariant=%d spread=%.2f spreadToTpPct=%.2f adx=%.2f diGap=%.2f atr=%.2f atrRatio=%.2f ema21=%.2f ema50=%.2f vwap=%.2f zoneBottom=%.2f zoneTop=%.2f zoneWidth=%.2f slDistance=%.2f lotMultiplier=%.2f setupRiskMultiplier=%.2f comment=%s",
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
      setupName,
      scalpVariantCode,
      featureSpread,
      featureSpreadToTpPct,
      featureAdx,
      featureDiGap,
      featureAtr,
      featureAtrRatio,
      featureEma21,
      featureEma50,
      featureVwap,
      featureZoneBottom,
      featureZoneTop,
      featureZoneWidth,
      featureSlDistance,
      featureLotMultiplier,
      featureSetupRiskMultiplier,
      comment));
   dashboardLastSetup = setupName;
   dashboardLastSignalId = GoldBotSignalIdFromComment(comment);
   GoldBotDashboardSetState("LIVE", "", StringFormat("Deal event %I64u profit %.2f", trans.deal, profit));
   GoldBotForwardEvent("deal_event", setupName, (GoldBotDirection)metaDirection, StringFormat("entry=%d reason=%d profit=%.2f", dealEntry, dealReason, profit), scoreBucket, confluences, dashboardLastSignalId, true);

   if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY)
   {
      bool finalPositionClose = positionId > 0 && !PositionSelectByTicket((ulong)positionId);
      double cumulativeProfit = GoldBotMetadataValue(posKey, "closedProfit", 0.0) + profit;
      GlobalVariableSet(posKey + ".closedProfit", cumulativeProfit);
      if((profit < 0.0 || dealReason == DEAL_REASON_SL) && signalCode > 0)
      {
         int cancelledOnSl = GoldBotCancelSiblingPendingSplitsBySignalCode(symbol, InpMagicNumber, signalCode, "sibling_sl_cancel", trade);
         if(cancelledOnSl > 0)
            GoldBotJournal(StringFormat("Sibling pending splits cancelled on SL signalCode=%I64d cancelled=%d profit=%.2f reason=%d",
               signalCode,
               cancelledOnSl,
               profit,
               dealReason));
      }
      GoldBotUpdateLossStreak(profit);
      if(setupCode == GOLDBOT_SETUP_M5_SCALP || setupCode == GOLDBOT_SETUP_M1_MICRO_SCALP)
         GoldBotUpdateShortTermScalpState(profit, riskCash);
      if(finalPositionClose)
      {
         GoldBotIncrementMonthlyCompletedTrades(dealTime);
         GoldBotUpdateRollingPerformanceState(cumulativeProfit, riskCash, setupCode);
      }
   }

   if((dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY) && positionId > 0 && !PositionSelectByTicket((ulong)positionId))
      GoldBotDeletePositionMetadata(positionId);
}

void OnTick()
{
   string symbol = GoldBotSymbol();
   dashboardLastTick = TimeCurrent();
   if(InpPythonParityMode)
   {
      GoldBotDashboardSetState("LIVE", "", "Python parity diagnostic mode active");
      GoldBotPythonParityCatchUp(symbol);
      GoldBotDashboardRefresh();
      return;
   }

   //--- Prop-mode intra-bar hard-breach monitor. Must run every tick, not just on new bars --
   //--- a daily hard-flatten or max-DD breach can happen mid-bar and must be flattened
   //--- immediately, not held until the next bar close. No-op entirely when prop mode is off.
   if(InpEnablePropMode)
   {
      GoldBotPropConfig propCfg = GoldBotBuildPropConfig();
      if(GoldBotPropPhaseTargetCompleted(InpMagicNumber))
      {
         GoldBotFlattenAll(symbol, InpMagicNumber, trade);
         GoldBotDashboardSetState("PROP PASSED", "", "Phase target locked; trading halted");
         GoldBotDashboardRefresh();
         return;
      }
      GoldBotPropMonitorResult propMon = GoldBotPropIntraBarMonitor(symbol, InpMagicNumber, propCfg);
      if(GoldBotPropPhaseTargetLockReached(propMon.equity, propMon.initialBalance, propCfg))
      {
         double lockEquity = propMon.equity;
         int targetClosed = GoldBotFlattenAll(symbol, InpMagicNumber, trade);
         double balanceAfterClose = AccountInfoDouble(ACCOUNT_BALANCE);
         double targetLevel = GoldBotPropPhaseTargetLevel(propMon.initialBalance, propCfg);
         bool completed = balanceAfterClose + 0.01 >= targetLevel;
         if(completed)
            GoldBotPropSetPhaseTargetCompleted(InpMagicNumber);
         GoldBotJournal(StringFormat("Prop phase target lock reached completed=%s closed=%d triggerEquity=%.2f balanceAfterClose=%.2f target=%.2f lockLevel=%.2f",
            completed ? "yes" : "no",
            targetClosed,
            lockEquity,
            balanceAfterClose,
            targetLevel,
            GoldBotPropPhaseTargetLockLevel(propMon.initialBalance, propCfg)));
         GoldBotDashboardSetState(completed ? "PROP PASSED" : "PROP TARGET LOCK", "", completed ? "Phase target locked; trading halted" : "Close costs left balance below target");
         GoldBotDashboardRefresh();
         return;
      }
      if(propMon.breach)
      {
         int propClosed = GoldBotFlattenAll(symbol, InpMagicNumber, trade);
         datetime breachDay = GoldBotPropDayStart(TimeCurrent(), InpPropDailyResetServerHour);
         if(lastPropBreachLogDay != breachDay)
         {
            GoldBotJournal(StringFormat("Prop mode breach flatten reason=%s closed=%d equity=%.2f initialBalance=%.2f equityPeak=%.2f dayBaseline=%.2f",
               propMon.reason,
               propClosed,
               propMon.equity,
               propMon.initialBalance,
               propMon.equityPeak,
               propMon.dayBaseline));
            lastPropBreachLogDay = breachDay;
         }
         GoldBotDashboardSetState("PROP HALT", "", propMon.reason);
         if(InpPropMonitorOnly)
         {
            GoldBotDashboardRefresh();
            return;
         }
      }
   }

   bool newM15Bar = GoldBotIsNewM15Bar(symbol);
   bool newM5Bar = GoldBotIsNewM5Bar(symbol);
   bool newM1Bar = GoldBotIsNewM1Bar(symbol);
   if(!newM15Bar && !newM5Bar && !newM1Bar)
   {
      GoldBotManagePositions(symbol, InpMagicNumber, MathMax(GoldBotATR(symbol, PERIOD_H1, 14, 1), 0.0), InpMaxHoldBars, InpTp1R, InpTp2R, InpTp3R, InpBreakEvenAtR, InpTrailAfterTp1, InpUseHtfTargetsForTp2Tp3, trade);
      GoldBotDashboardRefresh();
      return;
   }

   GoldBotExpirePendingOrders(symbol, InpMagicNumber, trade);
   GoldBotCancelPendingOnStopBreach(symbol, InpMagicNumber, trade);
   GoldBotCancelLongPendingAfterSessionEnd(symbol, InpMagicNumber, InpLongSessionEndHour, trade);
   GoldBotManagePositions(symbol, InpMagicNumber, MathMax(GoldBotATR(symbol, PERIOD_H1, 14, 1), 0.0), InpMaxHoldBars, InpTp1R, InpTp2R, InpTp3R, InpBreakEvenAtR, InpTrailAfterTp1, InpUseHtfTargetsForTp2Tp3, trade);

   double pnlPct = 0.0;
   if(!GoldBotDailyRiskAllowed(InpMaxDailyLossPct, InpDailyTargetPct, pnlPct))
   {
      string reason = "Daily risk gate PnL%=" + DoubleToString(pnlPct, 2);
      GoldBotLog("Daily risk gate blocked new entries. PnL%=" + DoubleToString(pnlPct, 2));
      GoldBotDashboardBlock("", DIR_NONE, reason, 0.0, -1, "");
      return;
   }

   double monthlyPnlPct = 0.0;
   if(!GoldBotMonthlyRiskAllowed(InpMaxMonthlyLossPct, monthlyPnlPct))
   {
      string reason = "Monthly risk gate PnL%=" + DoubleToString(monthlyPnlPct, 2);
      GoldBotLog("Monthly risk gate blocked new entries. PnL%=" + DoubleToString(monthlyPnlPct, 2));
      GoldBotJournal(StringFormat("Monthly risk gate blocked pnlPct=%.2f maxLossPct=%.2f",
         monthlyPnlPct,
         InpMaxMonthlyLossPct));
      GoldBotDashboardBlock("", DIR_NONE, reason, 0.0, -1, "");
      return;
   }

   double streakRemainingMinutes = 0.0;
   datetime streakCooldownEnd = 0;
   int streakLosses = 0;
   if(!GoldBotStreakCooldownAllowed(streakRemainingMinutes, streakCooldownEnd, streakLosses))
   {
      GoldBotLog("Streak cooldown gate blocked new entries.");
      string reason = StringFormat("Streak cooldown %.1f min losses=%d", streakRemainingMinutes, streakLosses);
      GoldBotJournal(StringFormat("Streak cooldown active losses=%d remainingMinutes=%.1f end=%s",
         streakLosses,
         streakRemainingMinutes,
         TimeToString(streakCooldownEnd, TIME_DATE | TIME_MINUTES)));
      GoldBotDashboardBlock("", DIR_NONE, reason, 0.0, -1, "");
      return;
   }

   if(!GoldBotCooldownAllowed(InpCooldownBars))
   {
      GoldBotLog("Cooldown gate blocked new entries.");
      GoldBotDashboardBlock("", DIR_NONE, "Cooldown gate active", 0.0, -1, "");
      return;
   }

   if(GoldBotCountManagedPositions(symbol, InpMagicNumber) >= InpMaxOpenTrades)
   {
      GoldBotLog("Max open trades gate blocked new entries.");
      GoldBotDashboardBlock("", DIR_NONE, "Max open trades reached", 0.0, -1, "");
      return;
   }

   //--- Prop entry gate: single choke point ahead of the M15/M5/M1 fan-out below, so all three
   //--- entry paths are gated uniformly by one call. No-op entirely when prop mode is off.
   if(InpEnablePropMode && !InpPropMonitorOnly)
   {
      GoldBotPropConfig propGateCfg = GoldBotBuildPropConfig();
      GoldBotPropGateResult propGate = GoldBotPropEntryGate(symbol, InpMagicNumber, propGateCfg);
      if(!propGate.allow)
      {
         GoldBotLog("Prop entry gate blocked new entries: " + propGate.reason);
         GoldBotJournal("Prop entry gate blocked reason=" + propGate.reason);
         GoldBotDashboardBlock("", DIR_NONE, propGate.reason, 0.0, -1, "");
         return;
      }
      if(propGateCfg.forceNewsFilter)
      {
         string propMatchedEvent = "";
         if(GoldBotNewsBlocked(InpHighImpactNewsTimes, InpNewsBlackoutMinutes, propMatchedEvent))
         {
            GoldBotLog("Prop mode forced news filter blocked new entries.");
            GoldBotJournal("Prop mode forced news filter blocked event=" + propMatchedEvent);
            GoldBotDashboardBlock("", DIR_NONE, "Prop news blackout " + propMatchedEvent, 0.0, -1, "");
            return;
         }
      }
   }

   if(!newM15Bar)
   {
      bool lowerTfPlaced = false;
      if(newM5Bar)
         lowerTfPlaced = GoldBotTryM5Scalp(symbol);
      if(!lowerTfPlaced && newM1Bar)
         lowerTfPlaced = GoldBotTryM1MicroScalp(symbol);
      if(!lowerTfPlaced)
         GoldBotDashboardRefresh();
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
      GoldBotDashboardBlock("", DIR_NONE, "Indicator snapshot unavailable", 0.0, -1, "");
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
   int setupCode = GOLDBOT_SETUP_SMC;
   string setupName = GoldBotSetupName(setupCode);
   EntryZone selectedZone;
   GoldBotResetEntryZone(selectedZone);
   bool setupHasPrebuiltZone = false;

   if(InpLegacyParityMode)
   {
      direction = GoldBotLegacySignalDirection(symbol, indicators);
      if(direction == DIR_NONE)
      {
         GoldBotLog("Legacy parity gates failed.");
         GoldBotDashboardBlock("legacy", DIR_NONE, "Legacy parity gates failed", 0.0, -1, "");
         return;
      }
      score = 75.0;
      fvg.valid = false;
      orderBlock.valid = false;
   }
   else
   {
      bool smcCandidate = false;
      if(!smcReady || !smc.allPass)
      {
         GoldBotLog(StringFormat("SMC gates failed. h4=%s h1=%s m15=%s dir=%d fvg=%s ob=%s",
            smc.gateH4 ? "yes" : "no",
            smc.gateH1 ? "yes" : "no",
            smc.gateM15 ? "yes" : "no",
            smc.direction,
            smc.fvg.valid ? "yes" : "no",
            smc.orderBlock.valid ? "yes" : "no"));
         GoldBotDashboardWait("smc", smc.direction, StringFormat("SMC gates failed h4=%s h1=%s m15=%s fvg=%s ob=%s",
            smc.gateH4 ? "yes" : "no",
            smc.gateH1 ? "yes" : "no",
            smc.gateM15 ? "yes" : "no",
            smc.fvg.valid ? "yes" : "no",
            smc.orderBlock.valid ? "yes" : "no"), smc.score, -1);
      }
      else
      {
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

         smcCandidate = GoldBotSmcSetupAllocationPass(smc, smc.score);
         if(smcCandidate)
         {
            direction = smc.direction;
            score = smc.score;
            fvg = smc.fvg;
            orderBlock = smc.orderBlock;
         }

         if(smcCandidate && InpRequireHigherTfConfirmation && !smc.gateH4 && !smc.gateH1)
         {
            GoldBotLog("Higher timeframe confirmation blocked new entry.");
            GoldBotJournal(StringFormat("Higher timeframe confirmation blocked h4=%s h1=%s m15=%s dir=%d",
               smc.gateH4 ? "yes" : "no",
               smc.gateH1 ? "yes" : "no",
               smc.gateM15 ? "yes" : "no",
               smc.direction));
            smcCandidate = false;
         }
         else if(smcCandidate && InpRequireHtfSmcContext && !smc.gateH4 && !smc.gateH1)
         {
            GoldBotLog("HTF SMC context blocked new entry.");
            GoldBotJournal(StringFormat("HTF SMC context blocked h4=%s h1=%s h4Dir=%d h1Dir=%d dir=%d",
               smc.gateH4 ? "yes" : "no",
               smc.gateH1 ? "yes" : "no",
               smc.h4Direction,
               smc.h1Direction,
               smc.direction));
            smcCandidate = false;
         }
         else if(smcCandidate && InpRequireSmcSequence && !smc.m15SequenceOk)
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
            smcCandidate = false;
         }
         else if(smcCandidate && InpRequireLiquiditySweepForSmc && !smc.m15RecentSweep)
         {
            GoldBotLog("SMC liquidity sweep blocked new entry.");
            GoldBotJournal(StringFormat("SMC liquidity sweep blocked currentSweep=%s recentSweep=%s dir=%d",
               smc.m15LiquiditySweep ? "yes" : "no",
               smc.m15RecentSweep ? "yes" : "no",
               smc.direction));
            smcCandidate = false;
         }
         else if(smcCandidate && InpRequireDisplacementForSmc && !smc.m15Displacement)
         {
            GoldBotLog("SMC displacement blocked new entry.");
            GoldBotJournal(StringFormat("SMC displacement blocked displacement=%s bos=%s dir=%d",
               smc.m15Displacement ? "yes" : "no",
               smc.m15BosChoCh ? "yes" : "no",
               smc.direction));
            smcCandidate = false;
         }
         else if(smcCandidate && InpRequireObFvgOverlap && !smc.m15ObFvgOverlap)
         {
            GoldBotLog("SMC OB/FVG overlap blocked new entry.");
            GoldBotJournal(StringFormat("SMC OB/FVG overlap blocked fvg=%s ob=%s overlap=%s dir=%d",
               smc.fvg.valid ? "yes" : "no",
               smc.orderBlock.valid ? "yes" : "no",
               smc.m15ObFvgOverlap ? "yes" : "no",
               smc.direction));
            smcCandidate = false;
         }

         if(smcCandidate)
         {
            selectedZone = GoldBotBuildEntryZone(fvg, orderBlock, indicators.ema21, indicators.atr);
            setupHasPrebuiltZone = selectedZone.valid;
         }
      }

      if(!smcCandidate || !setupHasPrebuiltZone)
      {
         GoldBotDirection breakoutDirection = DIR_NONE;
         double breakoutScore = 0.0;
         EntryZone breakoutZone;
         GoldBotResetEntryZone(breakoutZone);
         if(GoldBotBreakoutRetestSetupPass(symbol, indicators, breakoutDirection, breakoutScore, breakoutZone))
         {
            direction = breakoutDirection;
            score = breakoutScore;
            fvg.valid = false;
            orderBlock.valid = false;
            selectedZone = breakoutZone;
            setupHasPrebuiltZone = true;
            setupCode = GOLDBOT_SETUP_BREAKOUT_RETEST;
            setupName = GoldBotSetupName(setupCode);
            GoldBotDashboardWait(setupName, direction, "Breakout candidate passed; checking filters", score, -1);
         }
         else if(!smcCandidate)
         {
            GoldBotDashboardWait("smc/breakout", DIR_NONE, "No SMC or breakout setup on closed M15 bar", 0.0, -1);
            return;
         }
      }

      if(direction == DIR_NONE)
      {
         GoldBotDashboardWait(setupName, DIR_NONE, "No direction selected", score, -1);
         return;
      }
   }

   if(!InpLegacyParityMode && !GoldBotAllowedEntryHour(InpAllowedEntryHours))
   {
      GoldBotLog("Allowed entry hour filter blocked new entry.");
      GoldBotJournal(StringFormat("Allowed entry hour blocked allowed=%s", InpAllowedEntryHours));
      GoldBotDashboardBlock(setupName, direction, "Allowed entry hour filter", score, -1, "");
      return;
   }

   if(!InpLegacyParityMode && !GoldBotDirectionAllowedEntryHour(direction, InpAllowedLongEntryHours, InpAllowedShortEntryHours))
   {
      GoldBotLog("Direction-specific allowed entry hour filter blocked new entry.");
      GoldBotJournal(StringFormat("Direction allowed entry hour blocked dir=%d allowedLong=%s allowedShort=%s",
         direction,
         InpAllowedLongEntryHours,
         InpAllowedShortEntryHours));
      GoldBotDashboardBlock(setupName, direction, "Direction-specific hour filter", score, -1, "");
      return;
   }

   if(!InpLegacyParityMode && !GoldBotServerHourAllowed(InpUseSessionFilterForRealMode, InpRealSessionStartHour, InpRealSessionEndHour))
   {
      GoldBotLog("Real session filter blocked new entry.");
      GoldBotJournal(StringFormat("Real session filter blocked start=%d end=%d",
         InpRealSessionStartHour,
         InpRealSessionEndHour));
      GoldBotDashboardBlock(setupName, direction, "Real session filter", score, -1, "");
      return;
   }

   if(!InpLegacyParityMode && ((direction == DIR_LONG && !InpAllowLong) || (direction == DIR_SHORT && !InpAllowShort)))
   {
      GoldBotJournal(StringFormat("Direction side blocked dir=%d allowLong=%s allowShort=%s",
         direction,
         InpAllowLong ? "yes" : "no",
         InpAllowShort ? "yes" : "no"));
      GoldBotDashboardBlock(setupName, direction, "Direction side disabled", score, -1, "");
      return;
   }

   if(!InpLegacyParityMode && !GoldBotLongSessionEndAllowed(direction, InpLongSessionEndHour))
   {
      MqlDateTime nowParts;
      TimeToStruct(TimeCurrent(), nowParts);
      GoldBotJournal(StringFormat("Long session end blocked dir=%d hour=%d cutoff=%d score=%.2f",
         direction,
         nowParts.hour,
         InpLongSessionEndHour,
         score));
      GoldBotDashboardBlock(setupName, direction, "Long session end cutoff", score, -1, "");
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
         GoldBotDashboardBlock(setupName, direction, "News blackout " + matchedEvent, score, -1, "");
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
      GoldBotDashboardBlock(setupName, direction, StringFormat("Daily ladder limit %d/%d", dailyLadderCount, InpMaxLaddersPerDay), score, -1, "");
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
         GoldBotDashboardBlock(setupName, direction, "Indicator direction conflict", score, -1, "");
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
         GoldBotDashboardBlock(setupName, direction, StringFormat("Confluence %d/%d min=%d", confluenceCount, enabledConfluences, minConfluences), score, confluenceCount, "");
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
         GoldBotDashboardBlock(setupName, direction, "Directional ADX failed", score, confluenceCount, "");
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
         GoldBotDashboardBlock(setupName, direction, "EMA trend failed", score, confluenceCount, "");
         return;
      }
   }

   if(!InpLegacyParityMode && !GoldBotContextLongEntryPass(symbol, direction, setupCode, score, confluenceCount, enabledConfluences))
   {
      GoldBotDashboardBlock(setupName, direction, "Context long entry filter", score, confluenceCount, "");
      return;
   }

   double regimeSlopeAtr = 0.0;
   double regimeExtensionAtr = 0.0;
   if(!InpLegacyParityMode && !GoldBotRegimePass(symbol, direction, smc, InpEnableRegimeFilter, InpRegimeSlopeBars, InpRegimeMinSlopeAtr, InpRegimeMaxExtensionAtr, InpRegimeRequireH1Direction, score, confluenceCount, enabledConfluences, regimeSlopeAtr, regimeExtensionAtr))
   {
      GoldBotDashboardBlock(setupName, direction, "Regime filter", score, confluenceCount, "");
      return;
   }

   EntryZone zone;
   if(InpLegacyParityMode)
      zone = GoldBotLegacyEntryZone(symbol, direction);
   else if(setupHasPrebuiltZone)
      zone = selectedZone;
   else
      zone = GoldBotBuildEntryZone(fvg, orderBlock, indicators.ema21, indicators.atr);
   double baseScoreThreshold = InpLegacyParityMode ? InpScoreThreshold : MathMax(InpScoreThreshold, InpMinRealModeScore);
   int monthlyCompletedTrades = InpLegacyParityMode ? 0 : GoldBotMonthlyCompletedTradeCount(TimeCurrent());
   double effectiveScoreThreshold = InpLegacyParityMode ? baseScoreThreshold : GoldBotEffectiveScoreThreshold(baseScoreThreshold, monthlyCompletedTrades, TimeCurrent());
   if(score < effectiveScoreThreshold)
   {
      GoldBotLog(StringFormat("Signal skipped. score=%.2f threshold=%.2f zone=%s", score, effectiveScoreThreshold, zone.valid ? "yes" : "no"));
      if(score >= 50.0 || zone.valid)
         GoldBotJournal(StringFormat("Signal skipped setup=%s score=%.2f threshold=%.2f zone=%s dir=%d confluences=%d/%d monthlyTrades=%d ema=%s rsi=%s vwap=%s atr=%s adx=%s macd=%s bb=%s stoch=%s",
            setupName,
            score,
            effectiveScoreThreshold,
            zone.valid ? "yes" : "no",
            direction,
            confluenceCount,
            enabledConfluences,
            monthlyCompletedTrades,
            emaPass ? "yes" : "no",
            rsiPass ? "yes" : "no",
            vwapPass ? "yes" : "no",
            atrPass ? "yes" : "no",
            adxPass ? "yes" : "no",
            macdPass ? "yes" : "no",
            bbPass ? "yes" : "no",
            stochPass ? "yes" : "no"));
      GoldBotDashboardBlock(setupName, direction, StringFormat("Score %.2f < %.2f", score, effectiveScoreThreshold), score, confluenceCount, "");
      return;
   }
   if(!zone.valid)
   {
      if(!InpLegacyParityMode && GoldBotContinuationSetupPass(symbol, direction, indicators, emaPass, vwapPass, score, confluenceCount, enabledConfluences, zone))
      {
         setupCode = GOLDBOT_SETUP_CONTINUATION;
         setupName = GoldBotSetupName(setupCode);
      }
      else
      {
         GoldBotLog(StringFormat("Signal skipped. score=%.2f threshold=%.2f zone=no", score, effectiveScoreThreshold));
         GoldBotJournal(StringFormat("Signal skipped setup=smc score=%.2f threshold=%.2f zone=no continuation=%s dir=%d confluences=%d/%d ema=%s rsi=%s vwap=%s atr=%s adx=%s macd=%s bb=%s stoch=%s",
            score,
            effectiveScoreThreshold,
            InpEnableContinuationPullbackSetup ? "failed" : "disabled",
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
         GoldBotDashboardBlock(setupName, direction, "No valid entry zone", score, confluenceCount, "");
         return;
      }
   }

   MqlRates m15[];
   ArraySetAsSeries(m15, true);
   if(CopyRates(symbol, PERIOD_M15, 1, 2, m15) < 2)
   {
      GoldBotDashboardBlock(setupName, direction, "M15 rates unavailable", score, confluenceCount, "");
      return;
   }

   double entryReference = m15[0].close;
   double sl = direction == DIR_LONG ? MathMin(zone.bottom, entryReference - indicators.atr * InpSlAtr)
                                     : MathMax(zone.top, entryReference + indicators.atr * InpSlAtr);

   if(!InpLegacyParityMode && !GoldBotStrictHourQualityPass(symbol, direction, zone, indicators, emaPass, vwapPass, score, confluenceCount, enabledConfluences))
   {
      GoldBotDashboardBlock(setupName, direction, "Strict hour quality filter", score, confluenceCount, "");
      return;
   }

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
         GoldBotDashboardBlock(setupName, direction, "M5 pullback confirmation", score, confluenceCount, "");
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
      GoldBotDashboardBlock(setupName, direction, "Price not near entry zone", score, confluenceCount, "");
      return;
   }

   if(!InpLegacyParityMode && !GoldBotRobustRegimePass(symbol, setupName, direction, false, score, confluenceCount, enabledConfluences))
   {
      GoldBotDashboardBlock(setupName, direction, "Robust regime filter", score, confluenceCount, "");
      return;
   }

   string signalId = GoldBotNewSignalId(direction);
   GoldBotDashboardAccepted(setupName, direction, signalId, score, confluenceCount);
   GoldBotLog(StringFormat("Signal score=%.2f dir=%d zone=%.2f-%.2f sl=%.2f confluences=%d/%d", score, direction, zone.bottom, zone.top, sl, confluenceCount, enabledConfluences));
   GoldBotJournal(StringFormat("Signal accepted signalId=%s setup=%s score=%.2f dir=%d confluences=%d/%d emaPass=%s rsiPass=%s vwapPass=%s atrPass=%s adxPass=%s macdPass=%s bbPass=%s stochPass=%s zone=%.2f-%.2f sl=%.2f rsi=%.2f adx=%.2f plusDI=%.2f minusDI=%.2f atr=%.2f ema21=%.2f ema50=%.2f ema200=%.2f vwap=%.2f regimeSlopeAtr=%.2f regimeExtensionAtr=%.2f",
      signalId,
      setupName,
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
      sl,
      indicators.rsi,
      indicators.adx,
      indicators.plusDI,
      indicators.minusDI,
      indicators.atr,
      indicators.ema21,
      indicators.ema50,
      indicators.ema200,
      indicators.vwap,
      regimeSlopeAtr,
      regimeExtensionAtr));

   if(InpDebugOnly)
   {
      GoldBotDashboardSetState("DEBUG ONLY", "", "Signal accepted but debug mode blocks trading");
      return;
   }

   if(InpLegacyParityMode)
   {
      if(GoldBotPlaceLegacyMarket(symbol, InpMagicNumber, direction, sl, indicators.atr, score))
      {
         GoldBotJournal("Legacy parity market order placed");
         GoldBotDashboardOrderPlaced("legacy", direction, signalId, 1);
      }
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

   GoldBotApplyHourSplitGuard(direction, score, confluenceCount, enabledConfluences, ladderOrderCount, ladderFirstSplit);

   MqlDateTime compoundNow;
   TimeToStruct(TimeCurrent(), compoundNow);
   double effectiveLotPer100Usd = InpLotPer100Usd;
   double featureAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double featureBid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double featureSpread = (featureAsk > 0.0 && featureBid > 0.0) ? featureAsk - featureBid : 0.0;
   double featureRisk = MathAbs(zone.midpoint - sl);
   if(!GoldBotCompoundGovernorPass(symbol, setupName, setupCode, direction, compoundNow.hour, featureRisk, featureSpread, effectiveLotPer100Usd))
   {
      GoldBotLog("Compound governor blocked new M15 entry.");
      GoldBotDashboardBlock(setupName, direction, "Compound governor", score, confluenceCount, signalId);
      return;
   }

   //--- Prop-mode sizing gate (above, inside GoldBotCompoundGovernorPass) hands back
   //--- effectiveLotPer100Usd calibrated for one full-size order, mirroring
   //--- GoldBotPlaceLegacyMarket's InpLotPer100Usd*3.0 at line ~4859. GoldBotSplitLot bakes
   //--- in a fixed ~0.33 per-leg weight on every call regardless of how many ladder rungs are
   //--- configured, so without this compensation each realized fill only carries ~1/3 of the
   //--- intended prop risk budget. Only compensate when prop sizing is authoritative --
   //--- non-prop mode's governor-only value relies on the ladder's weights summing to ~1.0
   //--- across a full 3-way split and must not be tripled.
   //--- GoldBotPlaceLadder's own lotMultiplier parameter (here GoldBotSetupRiskMultiplier)
   //--- multiplies lotPer100Usd again downstream inside GoldBotSplitLot -- a leftover
   //--- notional-sizer knob for scaling risk by setup type that silently compresses/inflates
   //--- the prop sizer's already-correct per-trade $ risk when prop mode is authoritative.
   //--- Divide it back out here so the realized risk lands at the prop sizer's target
   //--- regardless of setup type, matching the ladder-weight compensation above.
   if(InpEnablePropMode && !InpPropMonitorOnly)
   {
      effectiveLotPer100Usd *= 3.0;
      double setupLotMultiplier = MathMax(0.01, GoldBotSetupRiskMultiplier(setupCode));
      effectiveLotPer100Usd /= setupLotMultiplier;
   }

   bool m15Placed = GoldBotPlaceLadder(
      symbol,
      InpMagicNumber,
      direction,
      zone,
      sl,
      score,
      signalId,
      setupCode,
      setupName,
      0,
      ladderOrderCount,
      ladderFirstSplit,
      confluenceCount,
      enabledConfluences,
      effectiveLotPer100Usd,
      InpMinLot,
      InpMaxLot,
      InpHighConvictionScore,
      InpMinRR,
      InpMaxHoldBars,
      0,
      0,
      0.0,
      0.0,
      0.0,
      -1,
      0.0,
      0.0,
      GoldBotSetupRiskMultiplier(setupCode),
      trade,
      featureSpread,
      0.0,
      indicators.adx,
      MathAbs(indicators.plusDI - indicators.minusDI),
      indicators.atr,
      0.0,
      indicators.ema21,
      indicators.ema50,
      indicators.vwap,
      zone.bottom,
      zone.top,
      featureRisk,
      1.0,
      GoldBotSetupRiskMultiplier(setupCode),
      InpStressExtraSpreadPrice);
   if(m15Placed)
   {
      GoldBotMarkLadderPlaced();
      GoldBotJournal(StringFormat("Pending ladder placed signalId=%s setup=%s orderCount=%d firstSplit=%d", signalId, setupName, ladderOrderCount, ladderFirstSplit));
      GoldBotDashboardOrderPlaced(setupName, direction, signalId, ladderOrderCount);
   }
   else if(newM5Bar)
   {
      if(!GoldBotTryM5Scalp(symbol) && newM1Bar)
         GoldBotTryM1MicroScalp(symbol);
   }
   else if(newM1Bar)
      GoldBotTryM1MicroScalp(symbol);
   else
      GoldBotDashboardBlock(setupName, direction, "Pending ladder placement failed", score, confluenceCount, signalId);
}

string GoldBotSymbol()
{
   return InpSymbol == "" ? _Symbol : InpSymbol;
}

string GoldBotMagicKey(const string suffix)
{
   return StringFormat("GoldBot_%s_%I64d", suffix, InpMagicNumber);
}

int GoldBotMonthCode(const datetime timeValue)
{
   MqlDateTime parts;
   TimeToStruct(timeValue, parts);
   return parts.year * 100 + parts.mon;
}

void GoldBotResetRollingPerformanceState()
{
   GlobalVariableDel(GoldBotMagicKey("RollingPerfCount"));
   GlobalVariableDel(GoldBotMagicKey("RollingPerfIndex"));
   GlobalVariableDel(GoldBotMagicKey("RollingPerfFailStreak"));
   GlobalVariableDel(GoldBotMagicKey("RollingPerfPauseUntil"));

   int resetLookback = InpRollingLookbackClosedTrades;
   if(resetLookback < 1)
      resetLookback = 1;
   if(resetLookback > 200)
      resetLookback = 200;
   for(int i = 0; i < resetLookback; i++)
   {
      GlobalVariableDel(GoldBotMagicKey(StringFormat("RollingPerfR%d", i)));
      GlobalVariableDel(GoldBotMagicKey(StringFormat("RollingPerfSetup%d", i)));
   }
   GoldBotJournal(StringFormat("Rolling performance governor tester state reset lookback=%d", resetLookback));
}

void GoldBotUpdateRollingPerformanceState(const double profit, const double riskCash, const int setupCode)
{
   if(!InpEnableRollingPerformanceGovernor)
      return;

   if(riskCash <= 0.0)
   {
      GoldBotJournal(StringFormat("Rolling performance update skipped setup=%s profit=%.2f riskCash=%.2f reason=missing_risk",
         GoldBotSetupName(setupCode),
         profit,
         riskCash));
      return;
   }

   int lookback = InpRollingLookbackClosedTrades;
   if(lookback < 1)
      lookback = 1;
   if(lookback > 200)
      lookback = 200;

   string countKey = GoldBotMagicKey("RollingPerfCount");
   string indexKey = GoldBotMagicKey("RollingPerfIndex");
   int count = GlobalVariableCheck(countKey) ? (int)GlobalVariableGet(countKey) : 0;
   int index = GlobalVariableCheck(indexKey) ? (int)GlobalVariableGet(indexKey) : 0;
   if(index < 0)
      index = 0;

   int slot = index % lookback;
   double rr = profit / riskCash;
   GlobalVariableSet(GoldBotMagicKey(StringFormat("RollingPerfR%d", slot)), rr);
   GlobalVariableSet(GoldBotMagicKey(StringFormat("RollingPerfSetup%d", slot)), (double)setupCode);
   GlobalVariableSet(countKey, (double)(count + 1));
   GlobalVariableSet(indexKey, (double)(index + 1));

   GoldBotJournal(StringFormat("Rolling performance updated setup=%s rr=%.2f profit=%.2f riskCash=%.2f slot=%d count=%d lookback=%d",
      GoldBotSetupName(setupCode),
      rr,
      profit,
      riskCash,
      slot,
      count + 1,
      lookback));
}

bool GoldBotRollingPerformanceGovernorPass(const string symbol, const string setupName, const int setupCode, const GoldBotDirection direction, const int entryHour, double &multiplier, string &reason)
{
   multiplier = 1.0;
   reason = "rolling_ok";
   if(!InpEnableRollingPerformanceGovernor)
      return true;

   bool isM5Setup = setupCode == GOLDBOT_SETUP_M5_SCALP || setupCode == GOLDBOT_SETUP_M1_MICRO_SCALP;
   if(isM5Setup && !InpRollingApplyToM5)
   {
      reason = "rolling_skipped_m5";
      return true;
   }
   if(!isM5Setup && !InpRollingApplyToM15)
   {
      reason = "rolling_skipped_m15";
      return true;
   }

   int lookback = InpRollingLookbackClosedTrades;
   if(lookback < 1)
      lookback = 1;
   if(lookback > 200)
      lookback = 200;

   string countKey = GoldBotMagicKey("RollingPerfCount");
   string failKey = GoldBotMagicKey("RollingPerfFailStreak");
   string pauseKey = GoldBotMagicKey("RollingPerfPauseUntil");
   int storedCount = GlobalVariableCheck(countKey) ? (int)GlobalVariableGet(countKey) : 0;
   int count = storedCount;
   if(count > lookback)
      count = lookback;

   int minSamples = lookback < 5 ? lookback : 5;
   if(count < minSamples)
   {
      reason = "rolling_insufficient_history";
      GoldBotJournal(StringFormat("Rolling governor decision setup=%s dir=%d hour=%d count=%d netR=0.00 winRate=0.00 multiplier=1.00 allowed=yes reason=%s",
         setupName,
         direction,
         entryHour,
         count,
         reason));
      return true;
   }

   datetime now = TimeCurrent();
   datetime pauseUntil = GlobalVariableCheck(pauseKey) ? (datetime)GlobalVariableGet(pauseKey) : 0;
   if(pauseUntil > now)
   {
      reason = "rolling_pause_active";
      multiplier = 0.0;
      GoldBotJournal(StringFormat("Rolling governor decision setup=%s dir=%d hour=%d count=%d netR=0.00 winRate=0.00 multiplier=0.00 allowed=no reason=%s pauseUntil=%s",
         setupName,
         direction,
         entryHour,
         count,
         reason,
         TimeToString(pauseUntil, TIME_DATE | TIME_MINUTES)));
      GoldBotCancelPendingOrders(symbol, InpMagicNumber, trade);
      return false;
   }

   double netR = 0.0;
   int wins = 0;
   for(int i = 0; i < count; i++)
   {
      string rrKey = GoldBotMagicKey(StringFormat("RollingPerfR%d", i));
      if(!GlobalVariableCheck(rrKey))
         continue;
      double rr = GlobalVariableGet(rrKey);
      netR += rr;
      if(rr > 0.0)
         wins++;
   }

   double winRatePct = count > 0 ? ((double)wins / (double)count) * 100.0 : 0.0;
   bool failed = netR < InpRollingMinNetR || winRatePct < InpRollingMinWinRatePct;
   if(!failed)
   {
      GlobalVariableSet(failKey, 0.0);
      reason = "rolling_ok";
      GoldBotJournal(StringFormat("Rolling governor decision setup=%s dir=%d hour=%d count=%d netR=%.2f winRate=%.2f multiplier=1.00 allowed=yes reason=%s",
         setupName,
         direction,
         entryHour,
         count,
         netR,
         winRatePct,
         reason));
      return true;
   }

   int failStreak = GlobalVariableCheck(failKey) ? (int)GlobalVariableGet(failKey) : 0;
   failStreak++;
   GlobalVariableSet(failKey, (double)failStreak);
   multiplier = MathMax(0.0, InpRollingThrottleMultiplier);
   reason = StringFormat("rolling_weak_perf_streak%d", failStreak);

   if(InpRollingPauseMinutes > 0 && failStreak >= 2)
   {
      pauseUntil = now + InpRollingPauseMinutes * 60;
      GlobalVariableSet(pauseKey, (double)pauseUntil);
      multiplier = 0.0;
      reason = "rolling_pause_started";
      GoldBotJournal(StringFormat("Rolling governor decision setup=%s dir=%d hour=%d count=%d netR=%.2f winRate=%.2f minNetR=%.2f minWinRate=%.2f multiplier=0.00 allowed=no reason=%s pauseUntil=%s",
         setupName,
         direction,
         entryHour,
         count,
         netR,
         winRatePct,
         InpRollingMinNetR,
         InpRollingMinWinRatePct,
         reason,
         TimeToString(pauseUntil, TIME_DATE | TIME_MINUTES)));
      GoldBotCancelPendingOrders(symbol, InpMagicNumber, trade);
      return false;
   }

   GoldBotJournal(StringFormat("Rolling governor decision setup=%s dir=%d hour=%d count=%d netR=%.2f winRate=%.2f minNetR=%.2f minWinRate=%.2f multiplier=%.2f allowed=yes reason=%s",
      setupName,
      direction,
      entryHour,
      count,
      netR,
      winRatePct,
      InpRollingMinNetR,
      InpRollingMinWinRatePct,
      multiplier,
      reason));
   return multiplier > 0.0;
}

bool GoldBotCompoundGovernorPass(const string symbol, const string setupName, const int setupCode, const GoldBotDirection direction, const int entryHour, const double stopDistancePrice, const double spreadPrice, double &effectiveLotPer100Usd)
{
   effectiveLotPer100Usd = InpLotPer100Usd;
   bool anyGovernorActive = InpEnableCompoundGovernor || InpEnableMonthlyLossThrottle || InpEnableRollingPerformanceGovernor;
   if(!anyGovernorActive && !InpEnablePropMode)
      return true;

   if(anyGovernorActive)
   {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
   {
      GoldBotJournal(StringFormat("Compound governor blocked setup=%s dir=%d hour=%d reason=invalid_equity equity=%.2f",
         setupName,
         direction,
         entryHour,
         equity));
      return false;
   }

   double multiplier = 1.0;
   string reason = "normal";
   bool allowed = true;

   string peakKey = GoldBotMagicKey("CompoundPeakEquity");
   double peakEquity = GlobalVariableCheck(peakKey) ? GlobalVariableGet(peakKey) : 0.0;
   if(peakEquity <= 0.0 || equity > peakEquity)
   {
      peakEquity = equity;
      GlobalVariableSet(peakKey, peakEquity);
   }

   double drawdownPct = peakEquity > 0.0 ? ((peakEquity - equity) / peakEquity) * 100.0 : 0.0;

   int currentMonth = GoldBotMonthCode(TimeCurrent());
   string monthKey = GoldBotMagicKey("CompoundMonth");
   string monthStartKey = GoldBotMagicKey("CompoundMonthStartEquity");
   string monthLockKey = GoldBotMagicKey("CompoundMonthProfitLock");
   int storedMonth = GlobalVariableCheck(monthKey) ? (int)GlobalVariableGet(monthKey) : 0;
   if(storedMonth != currentMonth || !GlobalVariableCheck(monthStartKey))
   {
      GlobalVariableSet(monthKey, (double)currentMonth);
      GlobalVariableSet(monthStartKey, equity);
      GlobalVariableSet(monthLockKey, 0.0);
      GoldBotJournal(StringFormat("Compound governor monthly baseline reset month=%d equity=%.2f",
         currentMonth,
         equity));
   }

   double monthStartEquity = GlobalVariableGet(monthStartKey);
   if(monthStartEquity <= 0.0)
   {
      monthStartEquity = equity;
      GlobalVariableSet(monthStartKey, equity);
   }
   double monthlyPnlPct = monthStartEquity > 0.0 ? ((equity - monthStartEquity) / monthStartEquity) * 100.0 : 0.0;

   if(InpEnableCompoundGovernor)
   {
      double softThreshold = MathMax(0.0, InpCompoundSoftDrawdownPct);
      double hardThreshold = MathMax(softThreshold, InpCompoundHardThrottleDrawdownPct);
      double maxDrawdown = MathMax(hardThreshold, InpCompoundMaxDrawdownPct);

      if(InpCompoundMaxDrawdownPct > 0.0 && drawdownPct >= maxDrawdown)
      {
         allowed = false;
         multiplier = 0.0;
         reason = "max_drawdown_halt";
      }
      else
      {
         if(softThreshold > 0.0 && drawdownPct >= softThreshold)
         {
            multiplier = MathMin(multiplier, MathMax(0.0, InpCompoundSoftRiskMultiplier));
            reason = "soft_drawdown_throttle";
         }
         if(hardThreshold > 0.0 && drawdownPct >= hardThreshold)
         {
            multiplier = MathMin(multiplier, MathMax(0.0, InpCompoundHardRiskMultiplier));
            reason = "hard_drawdown_throttle";
         }

         bool monthlyLocked = false;
         int lockedMonth = GlobalVariableCheck(monthLockKey) ? (int)GlobalVariableGet(monthLockKey) : 0;
         if(InpCompoundMonthlyProfitLockPct > 0.0 && lockedMonth == currentMonth)
            monthlyLocked = true;
         else if(InpCompoundMonthlyProfitLockPct > 0.0 && monthlyPnlPct >= InpCompoundMonthlyProfitLockPct)
         {
            monthlyLocked = true;
            GlobalVariableSet(monthLockKey, (double)currentMonth);
         }
         else if(InpCompoundMonthlyProfitLockPct <= 0.0 && lockedMonth != 0)
         {
            GlobalVariableSet(monthLockKey, 0.0);
         }

         if(monthlyLocked)
         {
            multiplier = MathMin(multiplier, MathMax(0.0, InpCompoundMonthlyProfitLockMultiplier));
            reason = reason + "+monthly_profit_lock";
         }

         if(multiplier <= 0.0)
         {
            allowed = false;
            reason = reason + "+zero_multiplier";
         }
      }
   }

   double monthlyLossPct = monthlyPnlPct < 0.0 ? -monthlyPnlPct : 0.0;
   if(allowed && InpEnableMonthlyLossThrottle)
   {
      double monthlySoftPct = MathMax(0.0, InpMonthlyLossSoftPct);
      double monthlyHardPct = MathMax(monthlySoftPct, InpMonthlyLossHardPct);
      if(InpMonthlyLossHardBlock && monthlyHardPct > 0.0 && monthlyLossPct >= monthlyHardPct)
      {
         allowed = false;
         multiplier = 0.0;
         reason = reason + "+monthly_loss_hard_block";
      }
      else if(monthlySoftPct > 0.0 && monthlyLossPct >= monthlySoftPct)
      {
         multiplier = MathMin(multiplier, MathMax(0.0, InpMonthlyLossSoftRiskMultiplier));
         reason = reason + "+monthly_loss_soft_throttle";
      }

      if(multiplier <= 0.0)
      {
         allowed = false;
         reason = reason + "+monthly_loss_zero_multiplier";
      }
   }

   if(allowed && InpEnableRollingPerformanceGovernor)
   {
      double rollingMultiplier = 1.0;
      string rollingReason = "";
      bool rollingAllowed = GoldBotRollingPerformanceGovernorPass(symbol, setupName, setupCode, direction, entryHour, rollingMultiplier, rollingReason);
      if(!rollingAllowed)
      {
         allowed = false;
         multiplier = 0.0;
         reason = reason + "+" + rollingReason;
      }
      else if(rollingMultiplier < 1.0)
      {
         multiplier = MathMin(multiplier, rollingMultiplier);
         reason = reason + "+" + rollingReason;
      }
   }

   effectiveLotPer100Usd = InpLotPer100Usd * multiplier;
   GoldBotJournal(StringFormat("Compound governor decision setup=%s dir=%d hour=%d equity=%.2f peakEquity=%.2f drawdownPct=%.2f monthlyPnlPct=%.2f monthlyLossPct=%.2f monthlyThrottle=%s rollingGovernor=%s multiplier=%.2f effectiveLotPer100=%.5f allowed=%s reason=%s",
      setupName,
      direction,
      entryHour,
      equity,
      peakEquity,
      drawdownPct,
      monthlyPnlPct,
      monthlyLossPct,
      InpEnableMonthlyLossThrottle ? "yes" : "no",
      InpEnableRollingPerformanceGovernor ? "yes" : "no",
      multiplier,
      effectiveLotPer100Usd,
      allowed ? "yes" : "no",
      reason));

   if(!allowed)
   {
      GoldBotCancelPendingOrders(symbol, InpMagicNumber, trade);
      GoldBotJournal(StringFormat("Compound governor cancelled pending orders setup=%s dir=%d hour=%d reason=%s",
         setupName,
         direction,
         entryHour,
         reason));
      return false;
   }
   } // anyGovernorActive

   //--- Prop-mode sizing override: replaces the linear equity-proportional base with an
   //--- SL-aware anti-ruin-clamped equivalent (mt5/Include/GoldBot/PropMode.mqh). Runs after
   //--- the governors above so prop mode's own risk budget is authoritative when both are
   //--- enabled together; effectiveLotPer100Usd from the governor stage (if any) is discarded
   //--- in favor of the prop-mode value on success. No-op entirely when prop mode is off.
   if(InpEnablePropMode && !InpPropMonitorOnly)
   {
      GoldBotPropConfig propCfg = GoldBotBuildPropConfig();

      bool isM15Setup = (setupCode == GOLDBOT_SETUP_SMC || setupCode == GOLDBOT_SETUP_CONTINUATION || setupCode == GOLDBOT_SETUP_BREAKOUT_RETEST);
      if(isM15Setup && propCfg.maxSpreadPriceM15 > 0.0 && spreadPrice > propCfg.maxSpreadPriceM15)
      {
         GoldBotJournal(StringFormat("Prop mode blocked setup=%s dir=%d hour=%d reason=max_spread spread=%.2f max=%.2f",
            setupName,
            direction,
            entryHour,
            spreadPrice,
            propCfg.maxSpreadPriceM15));
         GoldBotCancelPendingOrders(symbol, InpMagicNumber, trade);
         return false;
      }

      double propLotPer100Usd = effectiveLotPer100Usd;
      string propReason = "";
      bool propSizingOk = GoldBotPropCostAndSizingGate(symbol, InpMagicNumber, propCfg, stopDistancePrice, spreadPrice,
         InpMinLot, InpMaxLot, propLotPer100Usd, propReason);
      GoldBotJournal(StringFormat("Prop sizing gate setup=%s dir=%d hour=%d stopDistance=%.2f spread=%.2f allowed=%s effectiveLotPer100Usd=%.5f detail=%s",
         setupName,
         direction,
         entryHour,
         stopDistancePrice,
         spreadPrice,
         propSizingOk ? "yes" : "no",
         propLotPer100Usd,
         propReason));
      if(!propSizingOk)
      {
         GoldBotCancelPendingOrders(symbol, InpMagicNumber, trade);
         return false;
      }
      effectiveLotPer100Usd = propLotPer100Usd;
   }

   return true;
}

void GoldBotResetMonthlyTradeCounterIfNeeded(const datetime timeValue)
{
   int currentMonth = GoldBotMonthCode(timeValue);
   string monthKey = GoldBotMagicKey("CompletedTradeMonth");
   string countKey = GoldBotMagicKey("CompletedTrades");
   int storedMonth = GlobalVariableCheck(monthKey) ? (int)GlobalVariableGet(monthKey) : 0;

   if(storedMonth == currentMonth && GlobalVariableCheck(countKey))
      return;

   GlobalVariableSet(monthKey, (double)currentMonth);
   GlobalVariableSet(countKey, 0.0);
   GoldBotJournal(StringFormat("Monthly completed-trade counter reset month=%d", currentMonth));
}

int GoldBotMonthlyCompletedTradeCount(const datetime timeValue)
{
   GoldBotResetMonthlyTradeCounterIfNeeded(timeValue);
   string countKey = GoldBotMagicKey("CompletedTrades");
   return GlobalVariableCheck(countKey) ? (int)GlobalVariableGet(countKey) : 0;
}

void GoldBotIncrementMonthlyCompletedTrades(const datetime timeValue)
{
   GoldBotResetMonthlyTradeCounterIfNeeded(timeValue);
   string countKey = GoldBotMagicKey("CompletedTrades");
   int completedTrades = GlobalVariableCheck(countKey) ? (int)GlobalVariableGet(countKey) : 0;
   completedTrades++;
   GlobalVariableSet(countKey, (double)completedTrades);
   GoldBotJournal(StringFormat("Monthly completed trade counted month=%d completedTrades=%d",
      GoldBotMonthCode(timeValue),
      completedTrades));
}

double GoldBotEffectiveScoreThreshold(const double baseThreshold, const int monthTrades, const datetime timeValue)
{
   if(InpMinMonthlyTrades <= 0 || InpElevatedScoreThreshold <= 0.0)
      return baseThreshold;

   MqlDateTime parts;
   TimeToStruct(timeValue, parts);
   if(parts.day <= 15 || monthTrades >= InpMinMonthlyTrades)
      return baseThreshold;

   double elevatedThreshold = MathMax(baseThreshold, InpElevatedScoreThreshold);
   GoldBotJournal(StringFormat("Monthly frequency floor active month=%d day=%d completedTrades=%d minTrades=%d baseThreshold=%.2f elevatedThreshold=%.2f",
      GoldBotMonthCode(timeValue),
      parts.day,
      monthTrades,
      InpMinMonthlyTrades,
      baseThreshold,
      elevatedThreshold));
   return elevatedThreshold;
}

bool GoldBotMonthlyRiskAllowed(const double maxMonthlyLossPct, double &pnlPct)
{
   pnlPct = 0.0;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return true;

   int currentMonth = GoldBotMonthCode(TimeCurrent());
   string monthKey = GoldBotMagicKey("MonthYear");
   string startKey = GoldBotMagicKey("MonthStartEquity");
   string haltKey = GoldBotMagicKey("MonthlyHalt");

   int storedMonth = GlobalVariableCheck(monthKey) ? (int)GlobalVariableGet(monthKey) : 0;
   if(storedMonth != currentMonth || !GlobalVariableCheck(startKey))
   {
      GlobalVariableSet(monthKey, (double)currentMonth);
      GlobalVariableSet(startKey, equity);
      GlobalVariableSet(haltKey, 0.0);
      GoldBotJournal(StringFormat("Monthly risk baseline reset month=%d equity=%.2f",
         currentMonth,
         equity));
      return true;
   }

   double startEquity = GlobalVariableGet(startKey);
   if(startEquity <= 0.0)
   {
      GlobalVariableSet(startKey, equity);
      startEquity = equity;
   }

   pnlPct = ((equity - startEquity) / startEquity) * 100.0;
   if(maxMonthlyLossPct <= 0.0)
      return true;

   int haltedMonth = GlobalVariableCheck(haltKey) ? (int)GlobalVariableGet(haltKey) : 0;
   if(haltedMonth == currentMonth)
      return false;

   double lossPct = ((startEquity - equity) / startEquity) * 100.0;
   if(lossPct > maxMonthlyLossPct)
   {
      GlobalVariableSet(haltKey, (double)currentMonth);
      GoldBotJournal(StringFormat("Monthly loss limit reached month=%d startEquity=%.2f equity=%.2f lossPct=%.2f maxLossPct=%.2f",
         currentMonth,
         startEquity,
         equity,
         lossPct,
         maxMonthlyLossPct));
      return false;
   }

   return true;
}

bool GoldBotStreakCooldownAllowed(double &remainingMinutes, datetime &cooldownEnd, int &consecutiveLosses)
{
   remainingMinutes = 0.0;
   cooldownEnd = 0;
   consecutiveLosses = 0;
   if(InpStreakCooldownBars <= 0)
      return true;

   string endKey = GoldBotMagicKey("StreakCooldownEnd");
   string lossKey = GoldBotMagicKey("ConsecLosses");
   if(GlobalVariableCheck(lossKey))
      consecutiveLosses = (int)GlobalVariableGet(lossKey);
   if(!GlobalVariableCheck(endKey))
      return true;

   cooldownEnd = (datetime)GlobalVariableGet(endKey);
   datetime now = TimeCurrent();
   if(cooldownEnd <= now)
      return true;

   remainingMinutes = (double)(cooldownEnd - now) / 60.0;
   return false;
}

void GoldBotUpdateLossStreak(const double profit)
{
   if(InpStreakCooldownBars <= 0)
      return;

   string lossKey = GoldBotMagicKey("ConsecLosses");
   string endKey = GoldBotMagicKey("StreakCooldownEnd");
   int previousLosses = GlobalVariableCheck(lossKey) ? (int)GlobalVariableGet(lossKey) : 0;

   if(profit > 0.0)
   {
      if(previousLosses > 0)
         GoldBotJournal(StringFormat("Streak loss counter reset profit=%.2f previousLosses=%d",
            profit,
            previousLosses));
      GlobalVariableSet(lossKey, 0.0);
      return;
   }

   if(profit >= 0.0)
      return;

   int consecutiveLosses = previousLosses + 1;
   GlobalVariableSet(lossKey, (double)consecutiveLosses);
   GoldBotJournal(StringFormat("Streak loss counted profit=%.2f consecutiveLosses=%d",
      profit,
      consecutiveLosses));

   if(consecutiveLosses >= 2)
   {
      datetime cooldownEnd = TimeCurrent() + InpStreakCooldownBars * PeriodSeconds(PERIOD_M15);
      GlobalVariableSet(endKey, (double)cooldownEnd);
      GoldBotJournal(StringFormat("Streak cooldown extended losses=%d bars=%d end=%s",
         consecutiveLosses,
         InpStreakCooldownBars,
         TimeToString(cooldownEnd, TIME_DATE | TIME_MINUTES)));
   }
}

bool GoldBotAllowedEntryHour(const string allowedHours)
{
   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   return GoldBotHourListContains(allowedHours, nowParts.hour);
}

bool GoldBotHourListContains(const string allowedHours, const int targetHour)
{
   if(StringLen(allowedHours) <= 0)
      return true;

   string normalized = allowedHours;
   StringReplace(normalized, ";", ",");
   StringReplace(normalized, " ", "");
   StringReplace(normalized, "\t", "");
   if(StringLen(normalized) <= 0)
      return true;

   string tokens[];
   int count = StringSplit(normalized, ',', tokens);
   for(int i = 0; i < count; i++)
   {
      if(StringLen(tokens[i]) <= 0)
         continue;
      int hour = (int)StringToInteger(tokens[i]);
      if(hour == targetHour)
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

bool GoldBotLongSessionEndAllowed(const GoldBotDirection direction, const int longSessionEndHour)
{
   if(direction != DIR_LONG || longSessionEndHour <= 0)
      return true;

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   int cutoff = MathMax(0, MathMin(23, longSessionEndHour));
   return nowParts.hour < cutoff;
}

bool GoldBotStrictHourApplies(const GoldBotDirection direction, const string strictLongHours, const string strictShortHours)
{
   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   if(direction == DIR_LONG && StringLen(strictLongHours) > 0)
      return GoldBotHourListContains(strictLongHours, nowParts.hour);
   if(direction == DIR_SHORT && StringLen(strictShortHours) > 0)
      return GoldBotHourListContains(strictShortHours, nowParts.hour);
   return false;
}

bool GoldBotOptionalDirectionHourPass(const GoldBotDirection direction, const string allowedLongHours, const string allowedShortHours)
{
   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   if(direction == DIR_LONG && StringLen(allowedLongHours) > 0)
      return GoldBotHourListContains(allowedLongHours, nowParts.hour);
   if(direction == DIR_SHORT && StringLen(allowedShortHours) > 0)
      return GoldBotHourListContains(allowedShortHours, nowParts.hour);
   return true;
}

bool GoldBotSmcSetupAllocationPass(const SMCResult &smc, const double score)
{
   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);

   if(!InpEnableSmcSetup)
   {
      GoldBotJournal(StringFormat("SMC setup allocation blocked reason=disabled dir=%d hour=%d score=%.2f",
         smc.direction,
         nowParts.hour,
         score));
      return false;
   }

   if(!GoldBotOptionalDirectionHourPass(smc.direction, InpSmcAllowedLongHours, InpSmcAllowedShortHours))
   {
      GoldBotJournal(StringFormat("SMC setup allocation blocked reason=hour dir=%d hour=%d allowedLong=%s allowedShort=%s score=%.2f",
         smc.direction,
         nowParts.hour,
         InpSmcAllowedLongHours,
         InpSmcAllowedShortHours,
         score));
      return false;
   }

   if(InpSmcMinScore > 0.0 && score < InpSmcMinScore)
   {
      GoldBotJournal(StringFormat("SMC setup allocation blocked reason=min_score dir=%d hour=%d score=%.2f minScore=%.2f",
         smc.direction,
         nowParts.hour,
         score,
         InpSmcMinScore));
      return false;
   }

   if(InpSmcRequireHtfContext && !smc.gateH4 && !smc.gateH1)
   {
      GoldBotJournal(StringFormat("SMC setup allocation blocked reason=htf_context dir=%d hour=%d h4=%s h1=%s score=%.2f",
         smc.direction,
         nowParts.hour,
         smc.gateH4 ? "yes" : "no",
         smc.gateH1 ? "yes" : "no",
         score));
      return false;
   }

   return true;
}

bool GoldBotStrictHourQualityPass(
   const string symbol,
   const GoldBotDirection direction,
   const EntryZone &zone,
   const IndicatorSnapshot &indicators,
   const bool emaPass,
   const bool vwapPass,
   const double score,
   const int confluenceCount,
   const int enabledConfluences)
{
   if(!InpEnableStrictHourQuality)
      return true;
   if(!GoldBotStrictHourApplies(direction, InpStrictLongHours, InpStrictShortHours))
      return true;

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   const double diGap = MathAbs(indicators.plusDI - indicators.minusDI);
   const bool adxOk = indicators.adx >= InpStrictHourMinAdx;
   const bool diGapOk = diGap >= InpStrictHourMinDiGap;
   const bool vwapOk = !InpStrictHourRequireVwap || vwapPass;
   const bool emaOk = !InpStrictHourRequireEma || emaPass;

   bool candlePattern = false;
   bool rsiShift = false;
   bool microChoCH = false;
   int checksHit = 0;
   bool m5Ok = true;
   int requiredChecks = MathMax(1, MathMin(3, InpStrictHourPullbackChecks));
   if(InpStrictHourRequireM5Pullback)
      m5Ok = GoldBotPullbackConfirmed(symbol, zone, direction, InpRsiPeriod, requiredChecks, candlePattern, rsiShift, microChoCH, checksHit);

   if(adxOk && diGapOk && vwapOk && emaOk && m5Ok)
      return true;

   GoldBotJournal(StringFormat("Strict hour quality blocked dir=%d hour=%d adx=%.2f minAdx=%.2f diGap=%.2f minDiGap=%.2f ema=%s vwap=%s m5Checks=%d required=%d m5=%s score=%.2f confluences=%d/%d",
      direction,
      nowParts.hour,
      indicators.adx,
      InpStrictHourMinAdx,
      diGap,
      InpStrictHourMinDiGap,
      emaPass ? "yes" : "no",
      vwapPass ? "yes" : "no",
      checksHit,
      requiredChecks,
      m5Ok ? "yes" : "no",
      score,
      confluenceCount,
      enabledConfluences));
   return false;
}

bool GoldBotContextLongEntryPass(
   const string symbol,
   const GoldBotDirection direction,
   const int setupCode,
   const double score,
   const int confluenceCount,
   const int enabledConfluences
)
{
   if(direction != DIR_LONG)
      return true;

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   string setupName = GoldBotSetupName(setupCode);

   double athHigh = 0.0;
   double currentAsk = 0.0;
   double distancePct = 0.0;
   if(GoldBotNearAth(symbol, InpAthLookbackBars, InpAthProximityPct, athHigh, currentAsk, distancePct))
   {
      GoldBotJournal(StringFormat("ATH proximity blocked setup=%s dir=%d hour=%d ask=%.2f athHigh=%.2f distancePct=%.2f thresholdPct=%.2f lookbackBars=%d score=%.2f confluences=%d/%d",
         setupName,
         direction,
         nowParts.hour,
         currentAsk,
         athHigh,
         distancePct,
         InpAthProximityPct,
         InpAthLookbackBars,
         score,
         confluenceCount,
         enabledConfluences));
      return false;
   }

   double h4Rsi = 0.0;
   if(GoldBotH4RsiOverbought(symbol, InpRsiPeriod, InpRsiOverboughtGate, h4Rsi))
   {
      GoldBotJournal(StringFormat("H4 RSI overbought blocked setup=%s dir=%d hour=%d h4Rsi=%.2f threshold=%.2f score=%.2f confluences=%d/%d",
         setupName,
         direction,
         nowParts.hour,
         h4Rsi,
         InpRsiOverboughtGate,
         score,
         confluenceCount,
         enabledConfluences));
      return false;
   }

   return true;
}

void GoldBotResetEntryZone(EntryZone &zone)
{
   zone.valid = false;
   zone.bottom = 0.0;
   zone.top = 0.0;
   zone.midpoint = 0.0;
   zone.quarterPoint = 0.0;
}

bool GoldBotBuildContinuationEntryZone(const string symbol, const IndicatorSnapshot &indicators, EntryZone &zone)
{
   GoldBotResetEntryZone(zone);

   if(indicators.ema21 <= 0.0 || indicators.vwap <= 0.0 || indicators.atr <= 0.0)
      return false;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.01;

   double padding = indicators.atr * MathMax(0.0, InpContinuationZoneAtr);
   if(padding <= 0.0)
      padding = point * 10.0;

   double bottom = MathMin(indicators.ema21, indicators.vwap) - padding;
   double top = MathMax(indicators.ema21, indicators.vwap) + padding;
   if(bottom <= 0.0 || top <= bottom)
      return false;

   zone.valid = true;
   zone.bottom = bottom;
   zone.top = top;
   zone.midpoint = bottom + (top - bottom) / 2.0;
   zone.quarterPoint = bottom + (top - bottom) * 0.25;
   return true;
}

bool GoldBotBreakoutH1TrendPass(const string symbol, const GoldBotDirection direction)
{
   double h1Close = iClose(symbol, PERIOD_H1, 1);
   double ema21 = GoldBotMA(symbol, PERIOD_H1, 21, 1);
   double ema50 = GoldBotMA(symbol, PERIOD_H1, 50, 1);
   if(h1Close <= 0.0 || ema21 == EMPTY_VALUE || ema50 == EMPTY_VALUE || ema21 <= 0.0 || ema50 <= 0.0)
      return false;

   if(direction == DIR_LONG)
      return h1Close > ema21 && ema21 > ema50;
   if(direction == DIR_SHORT)
      return h1Close < ema21 && ema21 < ema50;
   return false;
}

bool GoldBotBuildBreakoutRetestZone(
   const string symbol,
   const GoldBotDirection direction,
   const double breakoutLevel,
   const IndicatorSnapshot &indicators,
   EntryZone &zone
)
{
   GoldBotResetEntryZone(zone);
   if(direction == DIR_NONE || breakoutLevel <= 0.0 || indicators.ema21 <= 0.0 || indicators.vwap <= 0.0 || indicators.atr <= 0.0)
      return false;

   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.01;

   double padding = indicators.atr * MathMax(0.0, InpBreakoutZoneAtr);
   if(padding <= 0.0)
      padding = point * 10.0;

   double bottom = MathMin(breakoutLevel, MathMin(indicators.ema21, indicators.vwap)) - padding;
   double top = MathMax(breakoutLevel, MathMax(indicators.ema21, indicators.vwap)) + padding;
   if(bottom <= 0.0 || top <= bottom)
      return false;

   double maxWidth = indicators.atr * MathMax(0.10, InpBreakoutMaxZoneAtr);
   if(maxWidth > 0.0 && top - bottom > maxWidth)
   {
      double center = (breakoutLevel + indicators.ema21 + indicators.vwap) / 3.0;
      bottom = center - maxWidth / 2.0;
      top = center + maxWidth / 2.0;
      if(bottom <= 0.0 || top <= bottom)
         return false;
   }

   zone.valid = true;
   zone.bottom = bottom;
   zone.top = top;
   zone.midpoint = bottom + (top - bottom) / 2.0;
   zone.quarterPoint = bottom + (top - bottom) * 0.25;
   return true;
}

bool GoldBotBreakoutVolumePass(const string symbol, const double multiplier, long &volume, double &averageVolume, double &requiredVolume)
{
   volume = iVolume(symbol, PERIOD_M15, 1);
   averageVolume = 0.0;
   requiredVolume = 0.0;

   double sum = 0.0;
   int count = 0;
   for(int i = 1; i <= 20; i++)
   {
      long candleVolume = iVolume(symbol, PERIOD_M15, i);
      if(candleVolume <= 0)
         continue;
      sum += (double)candleVolume;
      count++;
   }

   if(count <= 0)
      return multiplier <= 1.0;

   averageVolume = sum / count;
   requiredVolume = averageVolume * MathMax(1.0, multiplier);
   if(multiplier <= 1.0)
      return true;
   if(volume <= 0 || averageVolume <= 0.0)
      return false;
   return (double)volume >= requiredVolume;
}

bool GoldBotBreakoutRetestSetupPass(
   const string symbol,
   const IndicatorSnapshot &indicators,
   GoldBotDirection &direction,
   double &score,
   EntryZone &zone
)
{
   direction = DIR_NONE;
   score = 0.0;
   GoldBotResetEntryZone(zone);

   if(!InpEnableBreakoutRetestSetup)
      return false;
   if(indicators.atr <= 0.0 || !indicators.atrPass)
      return false;

   int lookback = MathMax(4, InpBreakoutLookbackBars);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(symbol, PERIOD_M15, 1, lookback + 1, rates);
   if(copied < lookback + 1)
      return false;

   double previousHigh = rates[1].high;
   double previousLow = rates[1].low;
   for(int i = 2; i <= lookback; i++)
   {
      previousHigh = MathMax(previousHigh, rates[i].high);
      previousLow = MathMin(previousLow, rates[i].low);
   }

   double buffer = indicators.atr * MathMax(0.0, InpBreakoutRangeBufferAtr);
   double body = MathAbs(rates[0].close - rates[0].open);
   double range = rates[0].high - rates[0].low;
   double bodyRatio = range > 0.0 ? body / range : 0.0;
   double bodyAtr = body / indicators.atr;
   bool bodyOk = bodyAtr >= InpBreakoutMinBodyAtr;
   bool bodyRatioOk = InpMinBodyRatio <= 0.0 || (range > 0.0 && bodyRatio >= InpMinBodyRatio);
   bool longBreak = rates[0].close > previousHigh + buffer;
   bool shortBreak = rates[0].close < previousLow - buffer;
   if(longBreak && shortBreak)
   {
      double longDistance = rates[0].close - previousHigh;
      double shortDistance = previousLow - rates[0].close;
      shortBreak = shortDistance > longDistance;
      longBreak = !shortBreak;
   }

   if(!longBreak && !shortBreak)
      return false;

   GoldBotDirection candidateDirection = longBreak ? DIR_LONG : DIR_SHORT;
   double breakoutLevel = longBreak ? previousHigh : previousLow;
   bool hourOk = GoldBotOptionalDirectionHourPass(candidateDirection, InpBreakoutLongHours, InpBreakoutShortHours)
      && GoldBotOptionalDirectionHourPass(candidateDirection, InpBreakoutAllowedLongHours, InpBreakoutAllowedShortHours);
   double diGap = MathAbs(indicators.plusDI - indicators.minusDI);
   bool adxOk = indicators.adx >= InpBreakoutMinAdx;
   bool diOk = diGap >= InpBreakoutMinDiGap
      && ((candidateDirection == DIR_LONG && indicators.plusDI > indicators.minusDI)
          || (candidateDirection == DIR_SHORT && indicators.minusDI > indicators.plusDI));
   bool emaOk = !InpBreakoutRequireEma
      || (candidateDirection == DIR_LONG ? indicators.emaLong : indicators.emaShort);
   bool vwapOk = !InpBreakoutRequireVwap
      || (candidateDirection == DIR_LONG ? indicators.vwapLong : indicators.vwapShort);
   bool h1Ok = !InpBreakoutRequireH1Trend || GoldBotBreakoutH1TrendPass(symbol, candidateDirection);
   bool zoneOk = GoldBotBuildBreakoutRetestZone(symbol, candidateDirection, breakoutLevel, indicators, zone);
   long breakoutVolume = 0;
   double averageVolume = 0.0;
   double requiredVolume = 0.0;
   bool volumeOk = GoldBotBreakoutVolumePass(symbol, InpVolumeMultiplier, breakoutVolume, averageVolume, requiredVolume);

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   if(bodyOk && bodyRatioOk && hourOk && adxOk && diOk && emaOk && vwapOk && h1Ok && zoneOk && volumeOk)
   {
      direction = candidateDirection;
      score = InpBreakoutBaseScore;
      GoldBotJournal(StringFormat("Breakout retest setup accepted dir=%d hour=%d close=%.2f level=%.2f prevHigh=%.2f prevLow=%.2f bodyAtr=%.2f minBodyAtr=%.2f bodyRatio=%.2f minBodyRatio=%.2f volume=%I64d avgVolume=%.2f requiredVolume=%.2f adx=%.2f minAdx=%.2f diGap=%.2f minDiGap=%.2f ema=%s vwap=%s h1=%s zone=%.2f-%.2f baseScore=%.2f",
         direction,
         nowParts.hour,
         rates[0].close,
         breakoutLevel,
         previousHigh,
         previousLow,
         bodyAtr,
         InpBreakoutMinBodyAtr,
         bodyRatio,
         InpMinBodyRatio,
         breakoutVolume,
         averageVolume,
         requiredVolume,
         indicators.adx,
         InpBreakoutMinAdx,
         diGap,
         InpBreakoutMinDiGap,
         emaOk ? "yes" : "no",
         vwapOk ? "yes" : "no",
         h1Ok ? "yes" : "no",
         zone.bottom,
         zone.top,
         score));
      return true;
   }

   GoldBotJournal(StringFormat("Breakout retest setup blocked dir=%d hour=%d close=%.2f level=%.2f prevHigh=%.2f prevLow=%.2f bodyAtr=%.2f minBodyAtr=%.2f bodyRatio=%.2f minBodyRatio=%.2f body=%s bodyRatioOk=%s volume=%I64d avgVolume=%.2f requiredVolume=%.2f volumeOk=%s hourOk=%s adx=%.2f minAdx=%.2f adxOk=%s diGap=%.2f minDiGap=%.2f diOk=%s ema=%s vwap=%s h1=%s zone=%s",
      candidateDirection,
      nowParts.hour,
      rates[0].close,
      breakoutLevel,
      previousHigh,
      previousLow,
      bodyAtr,
      InpBreakoutMinBodyAtr,
      bodyRatio,
      InpMinBodyRatio,
      bodyOk ? "yes" : "no",
      bodyRatioOk ? "yes" : "no",
      breakoutVolume,
      averageVolume,
      requiredVolume,
      volumeOk ? "yes" : "no",
      hourOk ? "yes" : "no",
      indicators.adx,
      InpBreakoutMinAdx,
      adxOk ? "yes" : "no",
      diGap,
      InpBreakoutMinDiGap,
      diOk ? "yes" : "no",
      emaOk ? "yes" : "no",
      vwapOk ? "yes" : "no",
      h1Ok ? "yes" : "no",
      zoneOk ? "yes" : "no"));
   return false;
}

bool GoldBotContinuationSetupPass(
   const string symbol,
   const GoldBotDirection direction,
   const IndicatorSnapshot &indicators,
   const bool emaPass,
   const bool vwapPass,
   const double score,
   const int confluenceCount,
   const int enabledConfluences,
   EntryZone &zone
)
{
   if(!InpEnableContinuationPullbackSetup)
      return false;
   if(!GoldBotStrictHourApplies(direction, InpContinuationLongHours, InpContinuationShortHours))
      return false;

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   const double diGap = MathAbs(indicators.plusDI - indicators.minusDI);
   const bool adxOk = indicators.adx >= InpContinuationMinAdx;
   const bool diGapOk = diGap >= InpContinuationMinDiGap;
   const bool vwapOk = !InpContinuationRequireVwap || vwapPass;
   const bool emaOk = !InpContinuationRequireEma || emaPass;

   bool zoneOk = GoldBotBuildContinuationEntryZone(symbol, indicators, zone);
   bool candlePattern = false;
   bool rsiShift = false;
   bool microChoCH = false;
   int checksHit = 0;
   bool m5Ok = true;
   int requiredChecks = MathMax(1, MathMin(3, InpContinuationPullbackChecks));
   if(zoneOk && InpContinuationRequireM5Pullback)
      m5Ok = GoldBotPullbackConfirmed(symbol, zone, direction, InpRsiPeriod, requiredChecks, candlePattern, rsiShift, microChoCH, checksHit);

   if(adxOk && diGapOk && vwapOk && emaOk && zoneOk && m5Ok)
   {
      GoldBotJournal(StringFormat("Continuation setup accepted dir=%d hour=%d adx=%.2f minAdx=%.2f diGap=%.2f minDiGap=%.2f ema=%s vwap=%s zone=%.2f-%.2f m5Checks=%d required=%d score=%.2f confluences=%d/%d",
         direction,
         nowParts.hour,
         indicators.adx,
         InpContinuationMinAdx,
         diGap,
         InpContinuationMinDiGap,
         emaPass ? "yes" : "no",
         vwapPass ? "yes" : "no",
         zone.bottom,
         zone.top,
         checksHit,
         requiredChecks,
         score,
         confluenceCount,
         enabledConfluences));
      return true;
   }

   GoldBotJournal(StringFormat("Continuation setup blocked dir=%d hour=%d adx=%.2f minAdx=%.2f diGap=%.2f minDiGap=%.2f ema=%s vwap=%s zone=%s m5Checks=%d required=%d m5=%s score=%.2f confluences=%d/%d",
      direction,
      nowParts.hour,
      indicators.adx,
      InpContinuationMinAdx,
      diGap,
      InpContinuationMinDiGap,
      emaPass ? "yes" : "no",
      vwapPass ? "yes" : "no",
      zoneOk ? "yes" : "no",
      checksHit,
      requiredChecks,
      m5Ok ? "yes" : "no",
      score,
      confluenceCount,
      enabledConfluences));
   return false;
}

void GoldBotApplyHourSplitGuard(
   const GoldBotDirection direction,
   const double score,
   const int confluenceCount,
   const int enabledConfluences,
   int &ladderOrderCount,
   int &ladderFirstSplit
)
{
   if(!InpEnableHourSplitGuard)
      return;
   bool split2Only = GoldBotStrictHourApplies(direction, InpSplit2OnlyLongHours, InpSplit2OnlyShortHours);
   bool split1Only = GoldBotStrictHourApplies(direction, InpSplit1OnlyLongHours, InpSplit1OnlyShortHours);
   if(!split2Only && !split1Only)
      return;

   int originalOrderCount = ladderOrderCount;
   int originalFirstSplit = ladderFirstSplit;
   ladderFirstSplit = split2Only ? 2 : 1;
   ladderOrderCount = 1;
   if(originalOrderCount == ladderOrderCount && originalFirstSplit == ladderFirstSplit)
      return;

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   GoldBotJournal(StringFormat("Hour split guard adjusted dir=%d hour=%d originalFirstSplit=%d originalOrderCount=%d finalFirstSplit=%d finalOrderCount=%d score=%.2f confluences=%d/%d",
      direction,
      nowParts.hour,
      originalFirstSplit,
      originalOrderCount,
      ladderFirstSplit,
      ladderOrderCount,
      score,
      confluenceCount,
      enabledConfluences));
}

bool GoldBotRegimePass(
   const string symbol,
   const GoldBotDirection direction,
   const SMCResult &smc,
   const bool enabled,
   const int slopeBars,
   const double minSlopeAtr,
   const double maxExtensionAtr,
   const bool requireH1Direction,
   const double score,
   const int confluenceCount,
   const int enabledConfluences,
   double &slopeAtr,
   double &extensionAtr
)
{
   slopeAtr = 0.0;
   extensionAtr = 0.0;

   int normalizedSlopeBars = MathMax(1, slopeBars);
   double emaNow = GoldBotMA(symbol, PERIOD_H1, 21, 1);
   double emaPast = GoldBotMA(symbol, PERIOD_H1, 21, normalizedSlopeBars + 1);
   double atr = GoldBotATR(symbol, PERIOD_H1, 14, 1);
   double h1Close = iClose(symbol, PERIOD_H1, 1);

   bool hasRegimeData = emaNow != EMPTY_VALUE
      && emaPast != EMPTY_VALUE
      && atr != EMPTY_VALUE
      && atr > 0.0
      && h1Close > 0.0;

   if(hasRegimeData)
   {
      slopeAtr = (emaNow - emaPast) / atr;
      extensionAtr = MathAbs(h1Close - emaNow) / atr;
   }

   if(!enabled)
      return true;

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);

   if(!hasRegimeData)
   {
      GoldBotJournal(StringFormat("Regime filter blocked reason=unavailable dir=%d slopeAtr=%.2f extensionAtr=%.2f h1Dir=%d score=%.2f confluences=%d/%d hour=%d",
         direction,
         slopeAtr,
         extensionAtr,
         smc.h1Direction,
         score,
         confluenceCount,
         enabledConfluences,
         nowParts.hour));
      return false;
   }

   string reason = "";
   if(direction == DIR_LONG)
   {
      if(slopeAtr < minSlopeAtr)
         reason = "weak_long_slope";
      else if(maxExtensionAtr > 0.0 && extensionAtr > maxExtensionAtr)
         reason = "long_overextension";
      else if(requireH1Direction && smc.h1Direction == DIR_SHORT)
         reason = "h1_direction_conflict";
   }
   else if(direction == DIR_SHORT)
   {
      if(-slopeAtr < minSlopeAtr)
         reason = "weak_short_slope";
      else if(maxExtensionAtr > 0.0 && extensionAtr > maxExtensionAtr)
         reason = "short_overextension";
      else if(requireH1Direction && smc.h1Direction == DIR_LONG)
         reason = "h1_direction_conflict";
   }

   if(StringLen(reason) <= 0)
      return true;

   GoldBotJournal(StringFormat("Regime filter blocked reason=%s dir=%d slopeAtr=%.2f extensionAtr=%.2f h1Dir=%d score=%.2f confluences=%d/%d hour=%d",
      reason,
      direction,
      slopeAtr,
      extensionAtr,
      smc.h1Direction,
      score,
      confluenceCount,
      enabledConfluences,
      nowParts.hour));
   return false;
}

double GoldBotAverageATR(const string symbol, const ENUM_TIMEFRAMES tf, const int period, const int startShift, const int bars)
{
   int normalizedBars = MathMax(10, bars);
   int handle = iATR(symbol, tf, period);
   if(handle == INVALID_HANDLE)
      return EMPTY_VALUE;

   double values[];
   ArraySetAsSeries(values, true);
   int copied = CopyBuffer(handle, 0, MathMax(1, startShift), normalizedBars, values);
   IndicatorRelease(handle);
   if(copied < 10)
      return EMPTY_VALUE;

   double sum = 0.0;
   int count = 0;
   for(int i = 0; i < copied; i++)
   {
      if(values[i] == EMPTY_VALUE || values[i] <= 0.0)
         continue;
      sum += values[i];
      count++;
   }

   return count > 0 ? sum / count : EMPTY_VALUE;
}

bool GoldBotRobustMonthlyRiskAllowed(double &monthlyPnlPct, bool &monthlyBlocked)
{
   monthlyPnlPct = 0.0;
   monthlyBlocked = false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return true;

   int currentMonth = GoldBotMonthCode(TimeCurrent());
   string monthKey = GoldBotMagicKey("RobustMonth");
   string startKey = GoldBotMagicKey("RobustMonthStartEquity");
   string haltKey = GoldBotMagicKey("RobustMonthlyHalt");

   int storedMonth = GlobalVariableCheck(monthKey) ? (int)GlobalVariableGet(monthKey) : 0;
   if(storedMonth != currentMonth || !GlobalVariableCheck(startKey))
   {
      GlobalVariableSet(monthKey, (double)currentMonth);
      GlobalVariableSet(startKey, equity);
      GlobalVariableSet(haltKey, 0.0);
      GoldBotJournal(StringFormat("Robust monthly baseline reset month=%d equity=%.2f",
         currentMonth,
         equity));
      return true;
   }

   double startEquity = GlobalVariableGet(startKey);
   if(startEquity <= 0.0)
   {
      startEquity = equity;
      GlobalVariableSet(startKey, equity);
   }

   monthlyPnlPct = ((equity - startEquity) / startEquity) * 100.0;
   if(InpRobustBlockIfMonthlyLossPct <= 0.0)
      return true;

   int haltedMonth = GlobalVariableCheck(haltKey) ? (int)GlobalVariableGet(haltKey) : 0;
   if(haltedMonth == currentMonth)
   {
      monthlyBlocked = true;
      return false;
   }

   double lossPct = ((startEquity - equity) / startEquity) * 100.0;
   if(lossPct >= InpRobustBlockIfMonthlyLossPct)
   {
      GlobalVariableSet(haltKey, (double)currentMonth);
      monthlyBlocked = true;
      return false;
   }

   return true;
}

bool GoldBotRobustRegimePass(
   const string symbol,
   const string setupName,
   const GoldBotDirection direction,
   const bool isM5Setup,
   const double score,
   const int confluenceCount,
   const int enabledConfluences
)
{
   if(!InpEnableRobustRegimeFilter)
      return true;
   if(isM5Setup && !InpRobustApplyToM5)
      return true;
   if(!isM5Setup && !InpRobustApplyToM15)
      return true;

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);

   double h1Adx = 0.0;
   double plusDI = 0.0;
   double minusDI = 0.0;
   bool hasAdx = GoldBotADX(symbol, PERIOD_H1, 14, 1, h1Adx, plusDI, minusDI);
   double h1Atr = GoldBotATR(symbol, PERIOD_H1, 14, 1);
   double h1AverageAtr = GoldBotAverageATR(symbol, PERIOD_H1, 14, 1, 96);
   double atrRatio = (h1AverageAtr != EMPTY_VALUE && h1AverageAtr > 0.0 && h1Atr != EMPTY_VALUE && h1Atr > 0.0) ? h1Atr / h1AverageAtr : 0.0;
   double emaNow = GoldBotMA(symbol, PERIOD_H1, 21, 1);
   double emaPast = GoldBotMA(symbol, PERIOD_H1, 21, 25);
   double slopeAtr = (emaNow != EMPTY_VALUE && emaPast != EMPTY_VALUE && h1Atr != EMPTY_VALUE && h1Atr > 0.0) ? (emaNow - emaPast) / h1Atr : 0.0;

   bool monthlyBlocked = false;
   double monthlyPnlPct = 0.0;
   bool monthlyAllowed = GoldBotRobustMonthlyRiskAllowed(monthlyPnlPct, monthlyBlocked);

   bool hasRegimeData = hasAdx
      && h1Atr != EMPTY_VALUE
      && h1Atr > 0.0
      && h1AverageAtr != EMPTY_VALUE
      && h1AverageAtr > 0.0
      && emaNow != EMPTY_VALUE
      && emaPast != EMPTY_VALUE;

   string reason = "";
   if(!monthlyAllowed)
      reason = "monthly_loss";
   else if(!hasRegimeData)
      reason = "unavailable";
   else if(InpRobustMinH1Adx > 0.0 && h1Adx < InpRobustMinH1Adx)
      reason = "h1_adx_low";
   else if(InpRobustMinH1AtrRatio > 0.0 && atrRatio < InpRobustMinH1AtrRatio)
      reason = "h1_atr_ratio_low";
   else if(InpRobustMaxH1AtrRatio > 0.0 && atrRatio > InpRobustMaxH1AtrRatio)
      reason = "h1_atr_ratio_high";
   else if(InpRobustMinH1EmaSlopeAtr > 0.0 && direction == DIR_LONG && slopeAtr < InpRobustMinH1EmaSlopeAtr)
      reason = "h1_long_slope_low";
   else if(InpRobustMinH1EmaSlopeAtr > 0.0 && direction == DIR_SHORT && -slopeAtr < InpRobustMinH1EmaSlopeAtr)
      reason = "h1_short_slope_low";

   if(StringLen(reason) <= 0)
      return true;

   if(monthlyBlocked)
      GoldBotCancelPendingOrders(symbol, InpMagicNumber, trade);

   GoldBotJournal(StringFormat("Robust regime filter blocked setup=%s isM5=%s reason=%s dir=%d hour=%d h1Adx=%.2f minAdx=%.2f atr=%.2f avgAtr=%.2f atrRatio=%.2f minAtrRatio=%.2f maxAtrRatio=%.2f emaSlopeAtr=%.4f minSlopeAtr=%.4f monthlyPnlPct=%.2f monthlyLossLimit=%.2f score=%.2f confluences=%d/%d cancelledPending=%s",
      setupName,
      isM5Setup ? "yes" : "no",
      reason,
      direction,
      nowParts.hour,
      h1Adx,
      InpRobustMinH1Adx,
      h1Atr,
      h1AverageAtr,
      atrRatio,
      InpRobustMinH1AtrRatio,
      InpRobustMaxH1AtrRatio,
      slopeAtr,
      InpRobustMinH1EmaSlopeAtr,
      monthlyPnlPct,
      InpRobustBlockIfMonthlyLossPct,
      score,
      confluenceCount,
      enabledConfluences,
      monthlyBlocked ? "yes" : "no"));
   return false;
}

bool GoldBotIsNewM15Bar(const string symbol)
{
   datetime barTime = iTime(symbol, PERIOD_M15, 0);
   if(barTime == 0 || barTime == lastM15Bar)
      return false;
   lastM15Bar = barTime;
   return true;
}

bool GoldBotIsNewM5Bar(const string symbol)
{
   datetime barTime = iTime(symbol, PERIOD_M5, 0);
   if(barTime == 0 || barTime == lastM5Bar)
      return false;
   lastM5Bar = barTime;
   return true;
}

bool GoldBotIsNewM1Bar(const string symbol)
{
   datetime barTime = iTime(symbol, PERIOD_M1, 0);
   if(barTime == 0 || barTime == lastM1Bar)
      return false;
   lastM1Bar = barTime;
   return true;
}

bool GoldBotM5ScalpAllowedToday(int &currentCount)
{
   currentCount = 0;
   if(InpScalpMaxTradesPerDay <= 0)
      return true;

   string key = GoldBotDayKey(StringFormat("m5ScalpCount.%I64d", InpMagicNumber));
   if(GlobalVariableCheck(key))
      currentCount = (int)GlobalVariableGet(key);
   return currentCount < InpScalpMaxTradesPerDay;
}

void GoldBotMarkM5ScalpPlaced()
{
   string key = GoldBotDayKey(StringFormat("m5ScalpCount.%I64d", InpMagicNumber));
   int currentCount = GlobalVariableCheck(key) ? (int)GlobalVariableGet(key) : 0;
   GlobalVariableSet(key, (double)(currentCount + 1));
}

bool GoldBotM1MicroAllowedToday(int &currentCount)
{
   currentCount = 0;
   if(InpM1MicroMaxTradesPerDay <= 0)
      return true;

   string key = GoldBotDayKey(StringFormat("m1MicroCount.%I64d", InpMagicNumber));
   if(GlobalVariableCheck(key))
      currentCount = (int)GlobalVariableGet(key);
   return currentCount < InpM1MicroMaxTradesPerDay;
}

void GoldBotMarkM1MicroPlaced()
{
   string key = GoldBotDayKey(StringFormat("m1MicroCount.%I64d", InpMagicNumber));
   int currentCount = GlobalVariableCheck(key) ? (int)GlobalVariableGet(key) : 0;
   GlobalVariableSet(key, (double)(currentCount + 1));
}

bool GoldBotShortTermScalpAllowed(double &dailyR, int &losses, datetime &pauseUntil)
{
   dailyR = 0.0;
   losses = 0;
   pauseUntil = 0;
   if(!InpEnableShortTermScalp)
      return true;

   string dailyRKey = GoldBotDayKey(StringFormat("shortTermScalpR.%I64d", InpMagicNumber));
   string lossesKey = GoldBotDayKey(StringFormat("shortTermScalpLosses.%I64d", InpMagicNumber));
   string pauseKey = GoldBotDayKey(StringFormat("shortTermScalpPause.%I64d", InpMagicNumber));
   if(GlobalVariableCheck(dailyRKey))
      dailyR = GlobalVariableGet(dailyRKey);
   if(GlobalVariableCheck(lossesKey))
      losses = (int)GlobalVariableGet(lossesKey);
   if(GlobalVariableCheck(pauseKey))
      pauseUntil = (datetime)GlobalVariableGet(pauseKey);

   if(InpShortTermMaxDailyLossR > 0.0 && dailyR <= -InpShortTermMaxDailyLossR)
      return false;
   if(pauseUntil > TimeCurrent())
      return false;
   return true;
}

void GoldBotUpdateShortTermScalpState(const double profit, const double riskCash)
{
   if(!InpEnableShortTermScalp || riskCash <= 0.0)
      return;

   string dailyRKey = GoldBotDayKey(StringFormat("shortTermScalpR.%I64d", InpMagicNumber));
   string lossesKey = GoldBotDayKey(StringFormat("shortTermScalpLosses.%I64d", InpMagicNumber));
   string pauseKey = GoldBotDayKey(StringFormat("shortTermScalpPause.%I64d", InpMagicNumber));
   double dailyR = GlobalVariableCheck(dailyRKey) ? GlobalVariableGet(dailyRKey) : 0.0;
   int losses = GlobalVariableCheck(lossesKey) ? (int)GlobalVariableGet(lossesKey) : 0;
   double rr = profit / riskCash;
   dailyR += rr;

   if(profit < 0.0)
      losses++;
   else if(profit > 0.0)
      losses = 0;

   GlobalVariableSet(dailyRKey, dailyR);
   GlobalVariableSet(lossesKey, (double)losses);

   if(InpShortTermMaxConsecutiveScalpLosses > 0 && losses >= InpShortTermMaxConsecutiveScalpLosses)
   {
      int pauseMinutes = InpShortTermPauseAfterLossMinutes < 1 ? 1 : InpShortTermPauseAfterLossMinutes;
      datetime pauseUntil = TimeCurrent() + pauseMinutes * 60;
      GlobalVariableSet(pauseKey, (double)pauseUntil);
      GoldBotJournal(StringFormat("Short-term scalp pause activated losses=%d rr=%.2f dailyR=%.2f pauseUntil=%s",
         losses,
         rr,
         dailyR,
         TimeToString(pauseUntil, TIME_DATE | TIME_MINUTES)));
   }
   else
   {
      GoldBotJournal(StringFormat("Short-term scalp state updated profit=%.2f rr=%.2f dailyR=%.2f losses=%d",
         profit,
         rr,
         dailyR,
         losses));
   }
}

bool GoldBotM15DirectionPass(const string symbol, const GoldBotDirection direction, bool &longAligned, bool &shortAligned)
{
   longAligned = false;
   shortAligned = false;

   double close = iClose(symbol, PERIOD_M15, 1);
   double ema21 = GoldBotMA(symbol, PERIOD_M15, 21, 1);
   double ema50 = GoldBotMA(symbol, PERIOD_M15, 50, 1);
   if(close <= 0.0 || ema21 == EMPTY_VALUE || ema50 == EMPTY_VALUE || ema21 <= 0.0 || ema50 <= 0.0)
      return false;

   longAligned = close > ema21 && ema21 >= ema50;
   shortAligned = close < ema21 && ema21 <= ema50;
   if(direction == DIR_LONG)
      return longAligned;
   if(direction == DIR_SHORT)
      return shortAligned;
   return false;
}

bool GoldBotM5DirectionPass(const string symbol, const GoldBotDirection direction, bool &longAligned, bool &shortAligned)
{
   longAligned = false;
   shortAligned = false;

   double close = iClose(symbol, PERIOD_M5, 1);
   double ema21 = GoldBotMA(symbol, PERIOD_M5, 21, 1);
   double ema50 = GoldBotMA(symbol, PERIOD_M5, 50, 1);
   double vwap = 0.0;
   double vwapUpper = 0.0;
   double vwapLower = 0.0;
   if(close <= 0.0 || ema21 == EMPTY_VALUE || ema50 == EMPTY_VALUE || ema21 <= 0.0 || ema50 <= 0.0)
      return false;
   if(!GoldBotSessionVWAP(symbol, PERIOD_M5, 144, vwap, vwapUpper, vwapLower))
      return false;

   longAligned = close > ema21 && ema21 >= ema50 && close >= vwap;
   shortAligned = close < ema21 && ema21 <= ema50 && close <= vwap;
   if(direction == DIR_LONG)
      return longAligned;
   if(direction == DIR_SHORT)
      return shortAligned;
   return false;
}

double GoldBotM5ScalpSlAtr(const GoldBotDirection direction)
{
   if(direction == DIR_LONG && InpScalpLongSlAtr > 0.0)
      return InpScalpLongSlAtr;
   if(direction == DIR_SHORT && InpScalpShortSlAtr > 0.0)
      return InpScalpShortSlAtr;
   return InpScalpSlAtr;
}

bool GoldBotBuildM5ScalpZone(const GoldBotDirection direction, const double ema21, const double vwap, const double atr, EntryZone &zone)
{
   GoldBotResetEntryZone(zone);
   if(direction == DIR_NONE || ema21 <= 0.0 || vwap <= 0.0 || atr <= 0.0)
      return false;

   double point = SymbolInfoDouble(GoldBotSymbol(), SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.01;

   double padding = MathMax(point * 10.0, atr * MathMax(0.05, GoldBotM5ScalpSlAtr(direction) * 0.5));
   double bottom = MathMin(ema21, vwap) - padding;
   double top = MathMax(ema21, vwap) + padding;
   if(bottom <= 0.0 || top <= bottom)
      return false;

   zone.valid = true;
   zone.bottom = bottom;
   zone.top = top;
   zone.midpoint = bottom + (top - bottom) / 2.0;
   zone.quarterPoint = bottom + (top - bottom) * 0.25;
   return true;
}

bool GoldBotBuildM5LevelScalpZone(const GoldBotDirection direction, const double level, const double ema21, const double vwap, const double atr, EntryZone &zone)
{
   GoldBotResetEntryZone(zone);
   if(direction == DIR_NONE || level <= 0.0 || ema21 <= 0.0 || vwap <= 0.0 || atr <= 0.0)
      return false;

   double point = SymbolInfoDouble(GoldBotSymbol(), SYMBOL_POINT);
   if(point <= 0.0)
      point = 0.01;

   double anchor = (level + ema21 + vwap) / 3.0;
   double padding = MathMax(point * 10.0, atr * 0.18);
   double bottom = MathMin(anchor, level) - padding;
   double top = MathMax(anchor, level) + padding;
   if(bottom <= 0.0 || top <= bottom)
      return false;

   zone.valid = true;
   zone.bottom = bottom;
   zone.top = top;
   zone.midpoint = bottom + (top - bottom) / 2.0;
   zone.quarterPoint = bottom + (top - bottom) * 0.25;
   return true;
}

bool GoldBotM5RecentRange(MqlRates &rates[], const int count, const int startIndex, const int lookbackBars, double &rangeHigh, double &rangeLow)
{
   rangeHigh = 0.0;
   rangeLow = 0.0;
   int lookback = MathMax(3, lookbackBars);
   if(count <= startIndex + lookback)
      return false;

   for(int i = startIndex; i < startIndex + lookback; i++)
   {
      if(i == startIndex)
      {
         rangeHigh = rates[i].high;
         rangeLow = rates[i].low;
      }
      else
      {
         rangeHigh = MathMax(rangeHigh, rates[i].high);
         rangeLow = MathMin(rangeLow, rates[i].low);
      }
   }
   return rangeHigh > rangeLow && rangeLow > 0.0;
}

bool GoldBotM5VolatilityRegimePass(MqlRates &rates[], const int count, const double currentAtr, double &averageAtr, double &atrRatio)
{
   averageAtr = 0.0;
   atrRatio = 0.0;
   if(!InpEnableShortTermScalp || !InpScalpEnableVolatilityRegime)
      return true;
   if(currentAtr <= 0.0)
      return false;

   int lookback = MathMax(20, InpScalpAtrLookbackBars);
   if(count <= lookback + 1)
      return false;

   double total = 0.0;
   for(int i = 0; i < lookback; i++)
   {
      double prevClose = rates[i + 1].close;
      double tr = MathMax(rates[i].high - rates[i].low, MathMax(MathAbs(rates[i].high - prevClose), MathAbs(rates[i].low - prevClose)));
      total += tr;
   }
   averageAtr = total / lookback;
   if(averageAtr <= 0.0)
      return false;

   atrRatio = currentAtr / averageAtr;
   double minRatio = MathMax(0.0, InpScalpMinAtrRatio);
   double maxRatio = MathMax(minRatio, InpScalpMaxAtrRatio);
   return atrRatio >= minRatio && (maxRatio <= 0.0 || atrRatio <= maxRatio);
}

bool GoldBotM1MicroVolatilityRegimePass(MqlRates &rates[], const int count, const double currentAtr, double &averageAtr, double &atrRatio)
{
   averageAtr = 0.0;
   atrRatio = 0.0;
   if(!InpM1MicroEnableVolatilityRegime)
      return true;
   if(currentAtr <= 0.0)
      return false;

   int lookback = MathMax(30, InpM1MicroAtrLookbackBars);
   if(count <= lookback + 1)
      return false;

   double total = 0.0;
   for(int i = 0; i < lookback; i++)
   {
      double prevClose = rates[i + 1].close;
      double tr = MathMax(rates[i].high - rates[i].low, MathMax(MathAbs(rates[i].high - prevClose), MathAbs(rates[i].low - prevClose)));
      total += tr;
   }
   averageAtr = total / lookback;
   if(averageAtr <= 0.0)
      return false;

   atrRatio = currentAtr / averageAtr;
   double minRatio = MathMax(0.0, InpM1MicroMinAtrRatio);
   double maxRatio = MathMax(minRatio, InpM1MicroMaxAtrRatio);
   return atrRatio >= minRatio && (maxRatio <= 0.0 || atrRatio <= maxRatio);
}

bool GoldBotM5LiquiditySweepReclaimPass(MqlRates &rates[], const int count, const GoldBotDirection direction, const double ema21, const double vwap, const double atr, double &sweepLevel)
{
   sweepLevel = 0.0;
   if(direction == DIR_NONE || ema21 <= 0.0 || vwap <= 0.0 || atr <= 0.0)
      return false;

   double rangeHigh = 0.0;
   double rangeLow = 0.0;
   if(!GoldBotM5RecentRange(rates, count, 1, MathMax(4, InpScalpSweepLookbackBars), rangeHigh, rangeLow))
      return false;

   double reclaimLine = direction == DIR_LONG ? MathMax(ema21, vwap) : MathMin(ema21, vwap);
   if(direction == DIR_LONG)
   {
      bool swept = rates[0].low < rangeLow - atr * 0.02;
      bool reclaimed = rates[0].close > reclaimLine && rates[0].close > rates[0].open;
      if(swept && reclaimed)
      {
         sweepLevel = rangeLow;
         return true;
      }
   }
   else if(direction == DIR_SHORT)
   {
      bool swept = rates[0].high > rangeHigh + atr * 0.02;
      bool reclaimed = rates[0].close < reclaimLine && rates[0].close < rates[0].open;
      if(swept && reclaimed)
      {
         sweepLevel = rangeHigh;
         return true;
      }
   }
   return false;
}

bool GoldBotM5SessionBreakoutRetestPass(MqlRates &rates[], const int count, const GoldBotDirection direction, const double ema21, const double vwap, const double atr, double &breakoutLevel)
{
   breakoutLevel = 0.0;
   if(direction == DIR_NONE || ema21 <= 0.0 || vwap <= 0.0 || atr <= 0.0)
      return false;

   double rangeHigh = 0.0;
   double rangeLow = 0.0;
   if(!GoldBotM5RecentRange(rates, count, 1, MathMax(6, InpScalpBreakoutLookbackBars), rangeHigh, rangeLow))
      return false;

   double buffer = atr * MathMax(0.0, InpScalpBreakoutBufferAtr);
   double retestPad = MathMax(atr * 0.20, SymbolInfoDouble(GoldBotSymbol(), SYMBOL_POINT) * 10.0);
   if(direction == DIR_LONG)
   {
      bool broke = rates[0].close > rangeHigh + buffer;
      bool retested = rates[0].low <= rangeHigh + retestPad;
      bool aligned = rates[0].close > ema21 && rates[0].close > vwap;
      if(broke && retested && aligned)
      {
         breakoutLevel = rangeHigh;
         return true;
      }
   }
   else if(direction == DIR_SHORT)
   {
      bool broke = rates[0].close < rangeLow - buffer;
      bool retested = rates[0].high >= rangeLow - retestPad;
      bool aligned = rates[0].close < ema21 && rates[0].close < vwap;
      if(broke && retested && aligned)
      {
         breakoutLevel = rangeLow;
         return true;
      }
   }
   return false;
}

bool GoldBotScalpDynamicCostPass(const GoldBotDirection direction, const double spread, const double risk, const double tp1R, double &tp1Distance, double &spreadToTpPct)
{
   tp1Distance = 0.0;
   spreadToTpPct = 0.0;
   if(!InpEnableShortTermScalp || InpScalpMaxSpreadToTp1Pct <= 0.0)
      return true;
   if(direction == DIR_NONE || spread < 0.0 || risk <= 0.0 || tp1R <= 0.0)
      return false;

   tp1Distance = risk * tp1R;
   if(tp1Distance <= 0.0)
      return false;
   spreadToTpPct = (spread / tp1Distance) * 100.0;
   return spreadToTpPct <= InpScalpMaxSpreadToTp1Pct;
}

bool GoldBotMicroDynamicCostPass(const GoldBotDirection direction, const double spread, const double risk, const double tp1R, double &tp1Distance, double &spreadToTpPct)
{
   tp1Distance = 0.0;
   spreadToTpPct = 0.0;
   if(InpM1MicroMaxSpreadToTp1Pct <= 0.0)
      return true;
   if(direction == DIR_NONE || spread < 0.0 || risk <= 0.0 || tp1R <= 0.0)
      return false;

   tp1Distance = risk * tp1R;
   if(tp1Distance <= 0.0)
      return false;
   spreadToTpPct = (spread / tp1Distance) * 100.0;
   return spreadToTpPct <= InpM1MicroMaxSpreadToTp1Pct;
}

double GoldBotSetupRiskMultiplier(const int setupCode)
{
   if(setupCode == GOLDBOT_SETUP_BREAKOUT_RETEST)
      return MathMax(0.0, InpBreakoutRiskMultiplier);
   if(setupCode == GOLDBOT_SETUP_M5_SCALP)
      return MathMax(0.0, InpM5ScalpRiskMultiplier);
   if(setupCode == GOLDBOT_SETUP_M1_MICRO_SCALP)
      return MathMax(0.0, InpM1MicroRiskMultiplier);
   return MathMax(0.0, InpSmcRiskMultiplier);
}

double GoldBotM5ScalpRiskMultiplier(const GoldBotDirection direction)
{
   if(direction == DIR_LONG && InpM5ScalpLongRiskMultiplier > 0.0)
      return InpM5ScalpLongRiskMultiplier;
   if(direction == DIR_SHORT && InpM5ScalpShortRiskMultiplier > 0.0)
      return InpM5ScalpShortRiskMultiplier;
   return MathMax(0.0, InpM5ScalpRiskMultiplier);
}

bool GoldBotTryM5Scalp(const string symbol)
{
   if(!InpEnableM5ScalpSetup)
   {
      GoldBotDashboardSetSetupState("m5_scalp", "disabled");
      return false;
   }

   double shortTermDailyR = 0.0;
   int shortTermLosses = 0;
   datetime shortTermPauseUntil = 0;
   if(!GoldBotShortTermScalpAllowed(shortTermDailyR, shortTermLosses, shortTermPauseUntil))
   {
      GoldBotJournal(StringFormat("M5 scalp blocked shortTermControl base=%s dailyR=%.2f maxDailyLossR=%.2f losses=%d maxLosses=%d pauseUntil=%s",
         InpShortTermBaseMode,
         shortTermDailyR,
         InpShortTermMaxDailyLossR,
         shortTermLosses,
         InpShortTermMaxConsecutiveScalpLosses,
         TimeToString(shortTermPauseUntil, TIME_DATE | TIME_MINUTES)));
      GoldBotDashboardBlock("m5_scalp", DIR_NONE, "M5 short-term loss/pause control", 0.0, -1, "");
      return false;
   }

   int scalpCount = 0;
   if(!GoldBotM5ScalpAllowedToday(scalpCount))
   {
      GoldBotJournal(StringFormat("M5 scalp blocked dailyCap current=%d max=%d",
         scalpCount,
         InpScalpMaxTradesPerDay));
      GoldBotDashboardBlock("m5_scalp", DIR_NONE, StringFormat("M5 daily cap %d/%d", scalpCount, InpScalpMaxTradesPerDay), 0.0, -1, "");
      return false;
   }

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double spread = ask - bid;
   if(ask <= 0.0 || bid <= 0.0 || spread < 0.0)
   {
      GoldBotDashboardBlock("m5_scalp", DIR_NONE, "M5 invalid bid/ask", 0.0, -1, "");
      return false;
   }
   bool propExecutionControls = InpEnablePropMode && !InpPropMonitorOnly;
   double m5SpreadCap = propExecutionControls ? GoldBotPropEffectiveSpreadCap(InpScalpMaxSpreadPrice, InpPropM5MaxSpreadPrice) : InpScalpMaxSpreadPrice;
   if(m5SpreadCap > 0.0 && spread > m5SpreadCap)
   {
      GoldBotJournal(StringFormat("M5 scalp blocked spread=%.2f max=%.2f prop=%s",
         spread,
         m5SpreadCap,
         propExecutionControls ? "yes" : "no"));
      GoldBotDashboardBlock("m5_scalp", DIR_NONE, StringFormat("M5 spread %.2f > %.2f", spread, m5SpreadCap), 0.0, -1, "");
      return false;
   }

   MqlRates m5[];
   ArraySetAsSeries(m5, true);
   int barsToCopy = 80;
   int requiredAtrBars = InpScalpAtrLookbackBars + 4;
   int requiredBreakoutBars = InpScalpBreakoutLookbackBars + 4;
   int requiredSweepBars = InpScalpSweepLookbackBars + 4;
   if(requiredAtrBars > barsToCopy)
      barsToCopy = requiredAtrBars;
   if(requiredBreakoutBars > barsToCopy)
      barsToCopy = requiredBreakoutBars;
   if(requiredSweepBars > barsToCopy)
      barsToCopy = requiredSweepBars;
   int copied = CopyRates(symbol, PERIOD_M5, 1, barsToCopy, m5);
   if(copied < 60)
   {
      GoldBotDashboardBlock("m5_scalp", DIR_NONE, "M5 rates unavailable", 0.0, -1, "");
      return false;
   }

   double ema21 = GoldBotMA(symbol, PERIOD_M5, 21, 1);
   double ema50 = GoldBotMA(symbol, PERIOD_M5, 50, 1);
   double atr = GoldBotATR(symbol, PERIOD_M5, 14, 1);
   double vwap = 0.0;
   double vwapUpper = 0.0;
   double vwapLower = 0.0;
   double adx = 0.0;
   double plusDI = 0.0;
   double minusDI = 0.0;
   if(ema21 == EMPTY_VALUE || ema50 == EMPTY_VALUE || atr == EMPTY_VALUE || ema21 <= 0.0 || ema50 <= 0.0 || atr <= 0.0)
   {
      GoldBotDashboardBlock("m5_scalp", DIR_NONE, "M5 indicator unavailable", 0.0, -1, "");
      return false;
   }
   if(!GoldBotSessionVWAP(symbol, PERIOD_M5, 144, vwap, vwapUpper, vwapLower))
   {
      GoldBotDashboardBlock("m5_scalp", DIR_NONE, "M5 VWAP unavailable", 0.0, -1, "");
      return false;
   }
   if(!GoldBotADX(symbol, PERIOD_M5, 14, 1, adx, plusDI, minusDI))
   {
      GoldBotDashboardBlock("m5_scalp", DIR_NONE, "M5 ADX unavailable", 0.0, -1, "");
      return false;
   }

   double averageAtr = 0.0;
   double atrRatio = 0.0;
   if(!GoldBotM5VolatilityRegimePass(m5, copied, atr, averageAtr, atrRatio))
   {
      MqlDateTime blockedParts;
      TimeToStruct(TimeCurrent(), blockedParts);
      GoldBotJournal(StringFormat("M5 scalp blocked volatilityRegime hour=%d atr=%.2f avgAtr=%.2f atrRatio=%.2f min=%.2f max=%.2f",
         blockedParts.hour,
         atr,
         averageAtr,
         atrRatio,
         InpScalpMinAtrRatio,
         InpScalpMaxAtrRatio));
      GoldBotDashboardBlock("m5_scalp", DIR_NONE, StringFormat("M5 ATR regime %.2f", atrRatio), 0.0, -1, "");
      return false;
   }

   EntryZone zone;
   bool zoneLongOk = GoldBotBuildM5ScalpZone(DIR_LONG, ema21, vwap, atr, zone);
   EntryZone longZone = zone;
   bool zoneShortOk = GoldBotBuildM5ScalpZone(DIR_SHORT, ema21, vwap, atr, zone);
   EntryZone shortZone = zone;

   double minimumZonePad = SymbolInfoDouble(symbol, SYMBOL_POINT) * 10.0;
   double longZonePad = MathMax(atr * MathMax(0.05, GoldBotM5ScalpSlAtr(DIR_LONG) * 0.5), minimumZonePad);
   double shortZonePad = MathMax(atr * MathMax(0.05, GoldBotM5ScalpSlAtr(DIR_SHORT) * 0.5), minimumZonePad);
   bool longPullback = InpScalpEnableClassicPullback && zoneLongOk && m5[0].close > ema21 && m5[0].close > vwap && m5[0].low <= longZone.top + longZonePad;
   bool shortPullback = InpScalpEnableClassicPullback && zoneShortOk && m5[0].close < ema21 && m5[0].close < vwap && m5[0].high >= shortZone.bottom - shortZonePad;

   double longSweepLevel = 0.0;
   double shortSweepLevel = 0.0;
   bool longSweep = InpScalpEnableLiquiditySweepReclaim && zoneLongOk && GoldBotM5LiquiditySweepReclaimPass(m5, copied, DIR_LONG, ema21, vwap, atr, longSweepLevel);
   bool shortSweep = InpScalpEnableLiquiditySweepReclaim && zoneShortOk && GoldBotM5LiquiditySweepReclaimPass(m5, copied, DIR_SHORT, ema21, vwap, atr, shortSweepLevel);

   double longBreakoutLevel = 0.0;
   double shortBreakoutLevel = 0.0;
   EntryZone longBreakoutZone;
   EntryZone shortBreakoutZone;
   GoldBotResetEntryZone(longBreakoutZone);
   GoldBotResetEntryZone(shortBreakoutZone);
   bool longBreakout = InpScalpEnableSessionBreakoutRetest
      && GoldBotM5SessionBreakoutRetestPass(m5, copied, DIR_LONG, ema21, vwap, atr, longBreakoutLevel)
      && GoldBotBuildM5LevelScalpZone(DIR_LONG, longBreakoutLevel, ema21, vwap, atr, longBreakoutZone);
   bool shortBreakout = InpScalpEnableSessionBreakoutRetest
      && GoldBotM5SessionBreakoutRetestPass(m5, copied, DIR_SHORT, ema21, vwap, atr, shortBreakoutLevel)
      && GoldBotBuildM5LevelScalpZone(DIR_SHORT, shortBreakoutLevel, ema21, vwap, atr, shortBreakoutZone);

   GoldBotDirection direction = DIR_NONE;
   bool longCandidate = longPullback || longSweep || longBreakout;
   bool shortCandidate = shortPullback || shortSweep || shortBreakout;
   if(longCandidate && !shortCandidate)
      direction = DIR_LONG;
   else if(shortCandidate && !longCandidate)
      direction = DIR_SHORT;
   else if(longCandidate && shortCandidate)
      direction = plusDI >= minusDI ? DIR_LONG : DIR_SHORT;

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   if(direction == DIR_NONE)
   {
      GoldBotJournal(StringFormat("M5 scalp blocked reason=no_setup hour=%d close=%.2f ema21=%.2f vwap=%.2f low=%.2f high=%.2f spread=%.2f classicLong=%s classicShort=%s sweepLong=%s sweepShort=%s breakoutLong=%s breakoutShort=%s",
         nowParts.hour,
         m5[0].close,
         ema21,
         vwap,
         m5[0].low,
         m5[0].high,
         spread,
         longPullback ? "yes" : "no",
         shortPullback ? "yes" : "no",
         longSweep ? "yes" : "no",
         shortSweep ? "yes" : "no",
         longBreakout ? "yes" : "no",
         shortBreakout ? "yes" : "no"));
      GoldBotDashboardWait("m5_scalp", DIR_NONE, "M5 no classic/sweep/breakout setup", 0.0, -1);
      return false;
   }

   bool hourOk = GoldBotOptionalDirectionHourPass(direction, InpScalpLongHours, InpScalpShortHours);
   double diGap = MathAbs(plusDI - minusDI);
   bool adxOk = adx >= InpScalpMinAdx;
   bool diOk = diGap >= InpScalpMinDiGap
      && ((direction == DIR_LONG && plusDI > minusDI) || (direction == DIR_SHORT && minusDI > plusDI));
   bool h1Ok = !InpScalpRequireH1Trend || GoldBotBreakoutH1TrendPass(symbol, direction);
   bool m15Long = false;
   bool m15Short = false;
   bool m15Ok = !InpScalpRequireM15Direction || GoldBotM15DirectionPass(symbol, direction, m15Long, m15Short);
   bool atrOk = atr > spread * 2.0;
   EntryZone selectedZone = direction == DIR_LONG ? longZone : shortZone;
   string scalpVariant = "classic_pullback";
   int scalpVariantCode = 1;
   double techniqueLevel = 0.0;
   if(direction == DIR_LONG)
   {
      if(longSweep)
      {
         scalpVariant = "liquidity_sweep_reclaim";
         scalpVariantCode = 2;
         selectedZone = longZone;
         techniqueLevel = longSweepLevel;
      }
      else if(longBreakout)
      {
         scalpVariant = "session_breakout_retest";
         scalpVariantCode = 3;
         selectedZone = longBreakoutZone;
         techniqueLevel = longBreakoutLevel;
      }
      else
      {
         selectedZone = longZone;
      }
   }
   else
   {
      if(shortSweep)
      {
         scalpVariant = "liquidity_sweep_reclaim";
         scalpVariantCode = 2;
         selectedZone = shortZone;
         techniqueLevel = shortSweepLevel;
      }
      else if(shortBreakout)
      {
         scalpVariant = "session_breakout_retest";
         scalpVariantCode = 3;
         selectedZone = shortBreakoutZone;
         techniqueLevel = shortBreakoutLevel;
      }
      else
      {
         selectedZone = shortZone;
      }
   }

   if(!hourOk || !adxOk || !diOk || !h1Ok || !m15Ok || !atrOk || !selectedZone.valid)
   {
      GoldBotJournal(StringFormat("M5 scalp blocked dir=%d setupVariant=%s hour=%d spread=%.2f adx=%.2f minAdx=%.2f adxOk=%s diGap=%.2f minDiGap=%.2f diOk=%s h1=%s m15=%s m15Long=%s m15Short=%s atr=%.2f atrRatio=%.2f atrOk=%s zone=%s hourOk=%s",
         direction,
         scalpVariant,
         nowParts.hour,
         spread,
         adx,
         InpScalpMinAdx,
         adxOk ? "yes" : "no",
         diGap,
         InpScalpMinDiGap,
         diOk ? "yes" : "no",
         h1Ok ? "yes" : "no",
         m15Ok ? "yes" : "no",
         m15Long ? "yes" : "no",
         m15Short ? "yes" : "no",
         atr,
         atrRatio,
         atrOk ? "yes" : "no",
         selectedZone.valid ? "yes" : "no",
         hourOk ? "yes" : "no"));
      GoldBotDashboardBlock("m5_scalp", direction, StringFormat("M5 filter hour=%s adx=%s di=%s h1=%s m15=%s zone=%s",
         hourOk ? "yes" : "no",
         adxOk ? "yes" : "no",
         diOk ? "yes" : "no",
         h1Ok ? "yes" : "no",
         m15Ok ? "yes" : "no",
         selectedZone.valid ? "yes" : "no"), 0.0, -1, "");
      return false;
   }

   double entryReference = m5[0].close;
   double scalpSlAtr = GoldBotM5ScalpSlAtr(direction);
   double sl = direction == DIR_LONG ? MathMin(selectedZone.bottom, entryReference - atr * MathMax(0.05, scalpSlAtr))
                                     : MathMax(selectedZone.top, entryReference + atr * MathMax(0.05, scalpSlAtr));
   double risk = MathAbs(entryReference - sl);
   if(risk <= spread * 2.0)
   {
      GoldBotJournal(StringFormat("M5 scalp blocked reason=risk_too_small dir=%d risk=%.2f spread=%.2f zone=%.2f-%.2f",
         direction,
         risk,
         spread,
         selectedZone.bottom,
         selectedZone.top));
      GoldBotDashboardBlock("m5_scalp", direction, "M5 risk too small vs spread", 0.0, -1, "");
      return false;
   }

   double tp1Distance = 0.0;
   double spreadToTpPct = 0.0;
   if(!GoldBotScalpDynamicCostPass(direction, spread, risk, InpScalpTp1R, tp1Distance, spreadToTpPct))
   {
      GoldBotJournal(StringFormat("M5 scalp blocked dynamicCost dir=%d setupVariant=%s hour=%d spread=%.2f tp1Distance=%.2f spreadToTpPct=%.2f maxPct=%.2f risk=%.2f",
         direction,
         scalpVariant,
         nowParts.hour,
         spread,
         tp1Distance,
         spreadToTpPct,
         InpScalpMaxSpreadToTp1Pct,
         risk));
      GoldBotDashboardBlock("m5_scalp", direction, StringFormat("M5 spread/TP %.1f%%", spreadToTpPct), 0.0, -1, "");
      return false;
   }

   int orderCount = MathMax(1, MathMin(3, InpScalpLadderOrderCount));
   double score = MathMax(62.5, MathMax(InpScoreThreshold, InpMinRealModeScore));
   int confluenceCount = 6;
   int enabledConfluences = 6;
   if(!GoldBotRobustRegimePass(symbol, GoldBotSetupName(GOLDBOT_SETUP_M5_SCALP), direction, true, score, confluenceCount, enabledConfluences))
   {
      GoldBotDashboardBlock("m5_scalp", direction, "M5 robust regime filter", score, confluenceCount, "");
      return false;
   }

   string signalId = GoldBotNewSignalId(direction);
   GoldBotDashboardAccepted("m5_scalp", direction, signalId, score, confluenceCount);
   GoldBotJournal(StringFormat("Signal accepted signalId=%s setup=m5_scalp setupVariant=%s shortTermBase=%s score=%.2f dir=%d confluences=%d/%d hour=%d spread=%.2f spreadToTpPct=%.2f adx=%.2f diGap=%.2f ema21=%.2f ema50=%.2f vwap=%.2f atr=%.2f atrRatio=%.2f techniqueLevel=%.2f zone=%.2f-%.2f sl=%.2f tpR=%.2f/%.2f/%.2f beAtR=%.2f trailStartR=%.2f timeStopMin=%d lotMultiplier=%.2f",
      signalId,
      scalpVariant,
      InpShortTermBaseMode,
      score,
      direction,
      confluenceCount,
      enabledConfluences,
      nowParts.hour,
      spread,
      spreadToTpPct,
      adx,
      diGap,
      ema21,
      ema50,
      vwap,
      atr,
      atrRatio,
      techniqueLevel,
      selectedZone.bottom,
      selectedZone.top,
      sl,
      InpScalpTp1R,
      InpScalpTp2R,
      InpScalpTp3R,
      InpScalpBreakEvenAtR,
      InpScalpTrailStartR,
      InpScalpTimeStopMinutes,
      InpScalpLotMultiplier));

   if(InpDebugOnly)
   {
      GoldBotDashboardSetState("DEBUG ONLY", "", "M5 signal accepted but debug mode blocks trading");
      return false;
   }

   double effectiveLotPer100Usd = InpLotPer100Usd;
   if(!GoldBotCompoundGovernorPass(symbol, GoldBotSetupName(GOLDBOT_SETUP_M5_SCALP), GOLDBOT_SETUP_M5_SCALP, direction, nowParts.hour, risk, spread, effectiveLotPer100Usd))
   {
      GoldBotLog("Compound governor blocked new M5 scalp entry.");
      GoldBotDashboardBlock("m5_scalp", direction, "M5 compound governor", score, confluenceCount, signalId);
      return false;
   }

   //--- Compensate GoldBotSplitLot's fixed ~0.33 per-leg weight for prop-authoritative sizing;
   //--- see the matching comment at the M15 ladder call site (~line 1554) for the full rationale.
   //--- Also divide back out InpScalpLotMultiplier*GoldBotM5ScalpRiskMultiplier(direction) --
   //--- the same lotMultiplier passed to GoldBotPlaceLadder below -- so this setup's leftover
   //--- notional-sizer scaling knob doesn't silently compress/inflate the prop sizer's target.
   if(InpEnablePropMode && !InpPropMonitorOnly)
   {
      effectiveLotPer100Usd *= 3.0;
      double setupLotMultiplier = MathMax(0.01, InpScalpLotMultiplier * GoldBotM5ScalpRiskMultiplier(direction));
      effectiveLotPer100Usd /= setupLotMultiplier;
   }

   int holdSeconds = (InpScalpMaxHoldMinutes < 1 ? 1 : InpScalpMaxHoldMinutes) * 60;
   if(InpEnableShortTermScalp && InpScalpTimeStopMinutes > 0)
   {
      int scalpTimeStopSeconds = (InpScalpTimeStopMinutes < 1 ? 1 : InpScalpTimeStopMinutes) * 60;
      if(scalpTimeStopSeconds < holdSeconds)
         holdSeconds = scalpTimeStopSeconds;
   }
   int pendingExpirySeconds = (InpScalpPendingExpiryMinutes < 1 ? 1 : InpScalpPendingExpiryMinutes) * 60;
   double scalpRiskMultiplier = GoldBotM5ScalpRiskMultiplier(direction);

   bool placed = GoldBotPlaceLadder(
      symbol,
      InpMagicNumber,
      direction,
      selectedZone,
      sl,
      score,
      signalId,
      GOLDBOT_SETUP_M5_SCALP,
      GoldBotSetupName(GOLDBOT_SETUP_M5_SCALP),
      scalpVariantCode,
      orderCount,
      1,
      confluenceCount,
      enabledConfluences,
      effectiveLotPer100Usd,
      InpMinLot,
      InpMaxLot,
      InpHighConvictionScore,
      InpMinRR,
      InpMaxHoldBars,
      pendingExpirySeconds,
      holdSeconds,
      InpScalpTp1R,
      InpScalpTp2R,
      InpScalpTp3R,
      InpTrailAfterTp1 ? 1 : 0,
      InpEnableShortTermScalp ? InpScalpBreakEvenAtR : 0.0,
      InpEnableShortTermScalp ? InpScalpTrailStartR : 0.0,
      InpScalpLotMultiplier * scalpRiskMultiplier,
      trade,
      spread,
      spreadToTpPct,
      adx,
      diGap,
      atr,
      atrRatio,
      ema21,
      ema50,
      vwap,
      selectedZone.bottom,
      selectedZone.top,
      risk,
      InpScalpLotMultiplier,
      scalpRiskMultiplier,
      InpStressExtraSpreadPrice);
   if(placed)
   {
      GoldBotMarkLadderPlaced();
      GoldBotMarkM5ScalpPlaced();
      GoldBotJournal(StringFormat("Pending ladder placed signalId=%s setup=m5_scalp orderCount=%d firstSplit=1 dailyScalpsBefore=%d",
         signalId,
         orderCount,
         scalpCount));
      GoldBotDashboardOrderPlaced("m5_scalp", direction, signalId, orderCount);
   }
   else
      GoldBotDashboardBlock("m5_scalp", direction, "M5 pending ladder placement failed", score, confluenceCount, signalId);
   return placed;
}

bool GoldBotTryM1MicroScalp(const string symbol)
{
   if(!InpEnableM1MicroScalpSetup)
   {
      GoldBotDashboardSetSetupState("m1_micro_scalp", "disabled");
      return false;
   }

   double shortTermDailyR = 0.0;
   int shortTermLosses = 0;
   datetime shortTermPauseUntil = 0;
   if(!GoldBotShortTermScalpAllowed(shortTermDailyR, shortTermLosses, shortTermPauseUntil))
   {
      GoldBotJournal(StringFormat("M1 micro scalp blocked shortTermControl dailyR=%.2f losses=%d pauseUntil=%s",
         shortTermDailyR,
         shortTermLosses,
         TimeToString(shortTermPauseUntil, TIME_DATE | TIME_MINUTES)));
      GoldBotDashboardBlock("m1_micro_scalp", DIR_NONE, "M1 short-term loss/pause control", 0.0, -1, "");
      return false;
   }

   int microCount = 0;
   if(!GoldBotM1MicroAllowedToday(microCount))
   {
      GoldBotJournal(StringFormat("M1 micro scalp blocked dailyCap current=%d max=%d",
         microCount,
         InpM1MicroMaxTradesPerDay));
      GoldBotDashboardBlock("m1_micro_scalp", DIR_NONE, StringFormat("M1 daily cap %d/%d", microCount, InpM1MicroMaxTradesPerDay), 0.0, -1, "");
      return false;
   }

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double spread = ask - bid;
   if(ask <= 0.0 || bid <= 0.0 || spread < 0.0)
   {
      GoldBotDashboardBlock("m1_micro_scalp", DIR_NONE, "M1 invalid bid/ask", 0.0, -1, "");
      return false;
   }
   bool propExecutionControls = InpEnablePropMode && !InpPropMonitorOnly;
   double m1SpreadCap = propExecutionControls ? GoldBotPropEffectiveSpreadCap(InpM1MicroMaxSpreadPrice, InpPropM1MaxSpreadPrice) : InpM1MicroMaxSpreadPrice;
   if(m1SpreadCap > 0.0 && spread > m1SpreadCap)
   {
      GoldBotJournal(StringFormat("M1 micro scalp blocked spread=%.2f max=%.2f prop=%s",
         spread,
         m1SpreadCap,
         propExecutionControls ? "yes" : "no"));
      GoldBotDashboardBlock("m1_micro_scalp", DIR_NONE, StringFormat("M1 spread %.2f > %.2f", spread, m1SpreadCap), 0.0, -1, "");
      return false;
   }

   MqlRates m1[];
   ArraySetAsSeries(m1, true);
   int barsToCopy = MathMax(160, InpM1MicroAtrLookbackBars + 4);
   int copied = CopyRates(symbol, PERIOD_M1, 1, barsToCopy, m1);
   if(copied < 80)
   {
      GoldBotDashboardBlock("m1_micro_scalp", DIR_NONE, "M1 rates unavailable", 0.0, -1, "");
      return false;
   }

   double ema21 = GoldBotMA(symbol, PERIOD_M1, 21, 1);
   double ema50 = GoldBotMA(symbol, PERIOD_M1, 50, 1);
   double atr = GoldBotATR(symbol, PERIOD_M1, 14, 1);
   double vwap = 0.0;
   double vwapUpper = 0.0;
   double vwapLower = 0.0;
   double adx = 0.0;
   double plusDI = 0.0;
   double minusDI = 0.0;
   if(ema21 == EMPTY_VALUE || ema50 == EMPTY_VALUE || atr == EMPTY_VALUE || ema21 <= 0.0 || ema50 <= 0.0 || atr <= 0.0)
   {
      GoldBotDashboardBlock("m1_micro_scalp", DIR_NONE, "M1 indicator unavailable", 0.0, -1, "");
      return false;
   }
   if(!GoldBotSessionVWAP(symbol, PERIOD_M1, 240, vwap, vwapUpper, vwapLower))
   {
      GoldBotDashboardBlock("m1_micro_scalp", DIR_NONE, "M1 VWAP unavailable", 0.0, -1, "");
      return false;
   }
   if(!GoldBotADX(symbol, PERIOD_M1, 14, 1, adx, plusDI, minusDI))
   {
      GoldBotDashboardBlock("m1_micro_scalp", DIR_NONE, "M1 ADX unavailable", 0.0, -1, "");
      return false;
   }

   double averageAtr = 0.0;
   double atrRatio = 0.0;
   if(!GoldBotM1MicroVolatilityRegimePass(m1, copied, atr, averageAtr, atrRatio))
   {
      MqlDateTime blockedParts;
      TimeToStruct(TimeCurrent(), blockedParts);
      GoldBotJournal(StringFormat("M1 micro scalp blocked volatilityRegime hour=%d atr=%.2f avgAtr=%.2f atrRatio=%.2f min=%.2f max=%.2f",
         blockedParts.hour,
         atr,
         averageAtr,
         atrRatio,
         InpM1MicroMinAtrRatio,
         InpM1MicroMaxAtrRatio));
      GoldBotDashboardBlock("m1_micro_scalp", DIR_NONE, StringFormat("M1 ATR regime %.2f", atrRatio), 0.0, -1, "");
      return false;
   }

   EntryZone zone;
   bool zoneLongOk = GoldBotBuildM5ScalpZone(DIR_LONG, ema21, vwap, atr, zone);
   EntryZone longZone = zone;
   bool zoneShortOk = GoldBotBuildM5ScalpZone(DIR_SHORT, ema21, vwap, atr, zone);
   EntryZone shortZone = zone;

   double zonePad = MathMax(atr * MathMax(0.03, InpM1MicroSlAtr * 0.45), SymbolInfoDouble(symbol, SYMBOL_POINT) * 5.0);
   bool longPullback = zoneLongOk && m1[0].close > ema21 && m1[0].close > vwap && m1[0].low <= longZone.top + zonePad;
   bool shortPullback = zoneShortOk && m1[0].close < ema21 && m1[0].close < vwap && m1[0].high >= shortZone.bottom - zonePad;

   GoldBotDirection direction = DIR_NONE;
   if(longPullback && !shortPullback)
      direction = DIR_LONG;
   else if(shortPullback && !longPullback)
      direction = DIR_SHORT;
   else if(longPullback && shortPullback)
      direction = plusDI >= minusDI ? DIR_LONG : DIR_SHORT;

   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   if(direction == DIR_NONE)
   {
      GoldBotJournal(StringFormat("M1 micro scalp blocked reason=no_setup hour=%d close=%.2f ema21=%.2f vwap=%.2f low=%.2f high=%.2f spread=%.2f longPullback=%s shortPullback=%s",
         nowParts.hour,
         m1[0].close,
         ema21,
         vwap,
         m1[0].low,
         m1[0].high,
         spread,
         longPullback ? "yes" : "no",
         shortPullback ? "yes" : "no"));
      GoldBotDashboardWait("m1_micro_scalp", DIR_NONE, "M1 no pullback setup", 0.0, -1);
      return false;
   }

   bool hourOk = GoldBotOptionalDirectionHourPass(direction, InpM1MicroLongHours, InpM1MicroShortHours);
   double diGap = MathAbs(plusDI - minusDI);
   bool adxOk = adx >= InpM1MicroMinAdx;
   bool diOk = diGap >= InpM1MicroMinDiGap
      && ((direction == DIR_LONG && plusDI > minusDI) || (direction == DIR_SHORT && minusDI > plusDI));
   bool h1Ok = !InpM1MicroRequireH1Trend || GoldBotBreakoutH1TrendPass(symbol, direction);
   bool m15Long = false;
   bool m15Short = false;
   bool m15Ok = !InpM1MicroRequireM15Direction || GoldBotM15DirectionPass(symbol, direction, m15Long, m15Short);
   bool m5Long = false;
   bool m5Short = false;
   bool m5Ok = !InpM1MicroRequireM5Direction || GoldBotM5DirectionPass(symbol, direction, m5Long, m5Short);
   bool atrOk = atr > spread * 2.0;
   EntryZone selectedZone = direction == DIR_LONG ? longZone : shortZone;

   if(!hourOk || !adxOk || !diOk || !h1Ok || !m15Ok || !m5Ok || !atrOk || !selectedZone.valid)
   {
      GoldBotJournal(StringFormat("M1 micro scalp blocked dir=%d hour=%d spread=%.2f adx=%.2f minAdx=%.2f adxOk=%s diGap=%.2f minDiGap=%.2f diOk=%s h1=%s m15=%s m15Long=%s m15Short=%s m5=%s m5Long=%s m5Short=%s atr=%.2f atrRatio=%.2f atrOk=%s zone=%s hourOk=%s",
         direction,
         nowParts.hour,
         spread,
         adx,
         InpM1MicroMinAdx,
         adxOk ? "yes" : "no",
         diGap,
         InpM1MicroMinDiGap,
         diOk ? "yes" : "no",
         h1Ok ? "yes" : "no",
         m15Ok ? "yes" : "no",
         m15Long ? "yes" : "no",
         m15Short ? "yes" : "no",
         m5Ok ? "yes" : "no",
         m5Long ? "yes" : "no",
         m5Short ? "yes" : "no",
         atr,
         atrRatio,
         atrOk ? "yes" : "no",
         selectedZone.valid ? "yes" : "no",
         hourOk ? "yes" : "no"));
      GoldBotDashboardBlock("m1_micro_scalp", direction, StringFormat("M1 filter hour=%s adx=%s di=%s h1=%s m15=%s m5=%s",
         hourOk ? "yes" : "no",
         adxOk ? "yes" : "no",
         diOk ? "yes" : "no",
         h1Ok ? "yes" : "no",
         m15Ok ? "yes" : "no",
         m5Ok ? "yes" : "no"), 0.0, -1, "");
      return false;
   }

   double entryReference = m1[0].close;
   double sl = direction == DIR_LONG ? MathMin(selectedZone.bottom, entryReference - atr * MathMax(0.05, InpM1MicroSlAtr))
                                     : MathMax(selectedZone.top, entryReference + atr * MathMax(0.05, InpM1MicroSlAtr));
   double risk = MathAbs(entryReference - sl);
   if(risk <= spread * 2.0)
   {
      GoldBotJournal(StringFormat("M1 micro scalp blocked reason=risk_too_small dir=%d risk=%.2f spread=%.2f zone=%.2f-%.2f",
         direction,
         risk,
         spread,
         selectedZone.bottom,
         selectedZone.top));
      GoldBotDashboardBlock("m1_micro_scalp", direction, "M1 risk too small vs spread", 0.0, -1, "");
      return false;
   }

   double tp1Distance = 0.0;
   double spreadToTpPct = 0.0;
   if(!GoldBotMicroDynamicCostPass(direction, spread, risk, InpM1MicroTp1R, tp1Distance, spreadToTpPct))
   {
      GoldBotJournal(StringFormat("M1 micro scalp blocked dynamicCost dir=%d hour=%d spread=%.2f tp1Distance=%.2f spreadToTpPct=%.2f maxPct=%.2f risk=%.2f",
         direction,
         nowParts.hour,
         spread,
         tp1Distance,
         spreadToTpPct,
         InpM1MicroMaxSpreadToTp1Pct,
         risk));
      GoldBotDashboardBlock("m1_micro_scalp", direction, StringFormat("M1 spread/TP %.1f%%", spreadToTpPct), 0.0, -1, "");
      return false;
   }

   int orderCount = MathMax(1, MathMin(3, InpM1MicroLadderOrderCount));
   double score = MathMax(62.5, MathMax(InpScoreThreshold, InpMinRealModeScore));
   int confluenceCount = 7;
   int enabledConfluences = 7;
   if(!GoldBotRobustRegimePass(symbol, GoldBotSetupName(GOLDBOT_SETUP_M1_MICRO_SCALP), direction, true, score, confluenceCount, enabledConfluences))
   {
      GoldBotDashboardBlock("m1_micro_scalp", direction, "M1 robust regime filter", score, confluenceCount, "");
      return false;
   }

   string signalId = GoldBotNewSignalId(direction);
   GoldBotDashboardAccepted("m1_micro_scalp", direction, signalId, score, confluenceCount);
   GoldBotJournal(StringFormat("Signal accepted signalId=%s setup=m1_micro_scalp setupVariant=micro_pullback score=%.2f dir=%d confluences=%d/%d hour=%d spread=%.2f spreadToTpPct=%.2f adx=%.2f diGap=%.2f ema21=%.2f ema50=%.2f vwap=%.2f atr=%.2f atrRatio=%.2f zone=%.2f-%.2f sl=%.2f tpR=%.2f/%.2f/%.2f beAtR=%.2f trailStartR=%.2f timeStopMin=%d lotMultiplier=%.2f setupRiskMultiplier=%.2f",
      signalId,
      score,
      direction,
      confluenceCount,
      enabledConfluences,
      nowParts.hour,
      spread,
      spreadToTpPct,
      adx,
      diGap,
      ema21,
      ema50,
      vwap,
      atr,
      atrRatio,
      selectedZone.bottom,
      selectedZone.top,
      sl,
      InpM1MicroTp1R,
      InpM1MicroTp2R,
      InpM1MicroTp3R,
      InpM1MicroBreakEvenAtR,
      InpM1MicroTrailStartR,
      InpM1MicroTimeStopMinutes,
      InpM1MicroLotMultiplier,
      GoldBotSetupRiskMultiplier(GOLDBOT_SETUP_M1_MICRO_SCALP)));

   if(InpDebugOnly)
   {
      GoldBotDashboardSetState("DEBUG ONLY", "", "M1 signal accepted but debug mode blocks trading");
      return false;
   }

   double effectiveLotPer100Usd = InpLotPer100Usd;
   if(!GoldBotCompoundGovernorPass(symbol, GoldBotSetupName(GOLDBOT_SETUP_M1_MICRO_SCALP), GOLDBOT_SETUP_M1_MICRO_SCALP, direction, nowParts.hour, risk, spread, effectiveLotPer100Usd))
   {
      GoldBotLog("Compound governor blocked new M1 micro scalp entry.");
      GoldBotDashboardBlock("m1_micro_scalp", direction, "M1 compound governor", score, confluenceCount, signalId);
      return false;
   }

   //--- Compensate GoldBotSplitLot's fixed ~0.33 per-leg weight for prop-authoritative sizing;
   //--- see the matching comment at the M15 ladder call site (~line 1554) for the full rationale.
   //--- Also divide back out InpM1MicroLotMultiplier*GoldBotSetupRiskMultiplier(...) -- the
   //--- same lotMultiplier passed to GoldBotPlaceLadder below -- so this setup's leftover
   //--- notional-sizer scaling knob doesn't silently compress/inflate the prop sizer's target.
   //--- (This is the dominant leakage case: InpM1MicroLotMultiplier=0.08 alone would otherwise
   //--- compress realized risk to ~8% of the intended per-trade target.)
   if(InpEnablePropMode && !InpPropMonitorOnly)
   {
      effectiveLotPer100Usd *= 3.0;
      double setupLotMultiplier = MathMax(0.01, InpM1MicroLotMultiplier * GoldBotSetupRiskMultiplier(GOLDBOT_SETUP_M1_MICRO_SCALP));
      effectiveLotPer100Usd /= setupLotMultiplier;
   }

   int holdSeconds = (InpM1MicroMaxHoldMinutes < 1 ? 1 : InpM1MicroMaxHoldMinutes) * 60;
   if(InpM1MicroTimeStopMinutes > 0)
   {
      int timeStopSeconds = (InpM1MicroTimeStopMinutes < 1 ? 1 : InpM1MicroTimeStopMinutes) * 60;
      if(timeStopSeconds < holdSeconds)
         holdSeconds = timeStopSeconds;
   }
   int pendingExpirySeconds = (InpM1MicroPendingExpiryMinutes < 1 ? 1 : InpM1MicroPendingExpiryMinutes) * 60;

   bool placed = GoldBotPlaceLadder(
      symbol,
      InpMagicNumber,
      direction,
      selectedZone,
      sl,
      score,
      signalId,
      GOLDBOT_SETUP_M1_MICRO_SCALP,
      GoldBotSetupName(GOLDBOT_SETUP_M1_MICRO_SCALP),
      1,
      orderCount,
      1,
      confluenceCount,
      enabledConfluences,
      effectiveLotPer100Usd,
      InpMinLot,
      InpMaxLot,
      InpHighConvictionScore,
      InpMinRR,
      InpMaxHoldBars,
      pendingExpirySeconds,
      holdSeconds,
      InpM1MicroTp1R,
      InpM1MicroTp2R,
      InpM1MicroTp3R,
      InpTrailAfterTp1 ? 1 : 0,
      InpM1MicroBreakEvenAtR,
      InpM1MicroTrailStartR,
      InpM1MicroLotMultiplier * GoldBotSetupRiskMultiplier(GOLDBOT_SETUP_M1_MICRO_SCALP),
      trade,
      spread,
      spreadToTpPct,
      adx,
      diGap,
      atr,
      atrRatio,
      ema21,
      ema50,
      vwap,
      selectedZone.bottom,
      selectedZone.top,
      risk,
      InpM1MicroLotMultiplier,
      GoldBotSetupRiskMultiplier(GOLDBOT_SETUP_M1_MICRO_SCALP),
      InpStressExtraSpreadPrice);
   if(placed)
   {
      GoldBotMarkLadderPlaced();
      GoldBotMarkM1MicroPlaced();
      GoldBotJournal(StringFormat("Pending ladder placed signalId=%s setup=m1_micro_scalp orderCount=%d firstSplit=1 dailyMicroBefore=%d",
         signalId,
         orderCount,
         microCount));
      GoldBotDashboardOrderPlaced("m1_micro_scalp", direction, signalId, orderCount);
   }
   else
      GoldBotDashboardBlock("m1_micro_scalp", direction, "M1 pending ladder placement failed", score, confluenceCount, signalId);
   return placed;
}

void GoldBotDashboardSetState(const string status, const string blocker, const string hint)
{
   dashboardStatus = status;
   dashboardBlocker = blocker;
   dashboardHint = hint;
   if(status == "BLOCKED" && StringLen(blocker) > 0)
      dashboardHint = "Blocked: " + blocker;
}

void GoldBotDashboardSetSetupState(const string setupName, const string state)
{
   if(setupName == "m5_scalp")
      dashboardM5State = state;
   else if(setupName == "m1_micro_scalp")
      dashboardM1State = state;
   else if(setupName == "breakout_retest")
      dashboardBreakoutState = state;
   else if(setupName == "smc")
      dashboardSmcState = state;
}

void GoldBotDashboardBlock(const string setupName, const GoldBotDirection direction, const string reason, const double score, const int confluences, const string signalId)
{
   string effectiveSetup = setupName;
   if(StringLen(effectiveSetup) <= 0)
      effectiveSetup = "global";
   GoldBotDashboardSetState("BLOCKED", reason, "Blocked: " + reason);
   GoldBotDashboardSetSetupState(effectiveSetup, "blocked: " + reason);
   GoldBotForwardEvent("block", effectiveSetup, direction, reason, score, confluences, signalId, false);
   GoldBotDashboardRefresh();
}

void GoldBotDashboardWait(const string setupName, const GoldBotDirection direction, const string reason, const double score, const int confluences)
{
   string effectiveSetup = setupName;
   if(StringLen(effectiveSetup) <= 0)
      effectiveSetup = "global";
   GoldBotDashboardSetState(InpDebugOnly ? "DEBUG ONLY" : "WAITING SETUP", "", "Waiting: " + reason);
   GoldBotDashboardSetSetupState(effectiveSetup, "waiting: " + reason);
   GoldBotForwardEvent("setup_wait", effectiveSetup, direction, reason, score, confluences, "", false);
   GoldBotDashboardRefresh();
}

void GoldBotDashboardAccepted(const string setupName, const GoldBotDirection direction, const string signalId, const double score, const int confluences)
{
   dashboardLastSetup = setupName;
   dashboardLastSignalId = signalId;
   GoldBotDashboardSetState(InpDebugOnly ? "DEBUG ONLY" : "LIVE", "", "Signal accepted; placing pending ladder");
   GoldBotDashboardSetSetupState(setupName, StringFormat("accepted dir=%d score=%.2f conf=%d", direction, score, confluences));
   GoldBotForwardEvent("signal_accepted", setupName, direction, "accepted", score, confluences, signalId, true);
   GoldBotDashboardRefresh();
}

void GoldBotDashboardOrderPlaced(const string setupName, const GoldBotDirection direction, const string signalId, const int orderCount)
{
   dashboardLastSetup = setupName;
   dashboardLastSignalId = signalId;
   GoldBotDashboardSetState("ORDER PLACED", "", StringFormat("Placed %d pending order(s)", orderCount));
   GoldBotDashboardSetSetupState(setupName, StringFormat("order placed signal=%s count=%d", signalId, orderCount));
   GoldBotForwardEvent("pending_ladder_placed", setupName, direction, StringFormat("orderCount=%d", orderCount), 0.0, -1, signalId, true);
   GoldBotDashboardRefresh();
}

string GoldBotDashboardTime(const datetime value)
{
   if(value <= 0)
      return "-";
   return TimeToString(value, TIME_DATE | TIME_SECONDS);
}

int GoldBotCountManagedPendingOrders(const string symbol, const long magic)
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0 || !OrderSelect(ticket))
         continue;
      if(OrderGetString(ORDER_SYMBOL) != symbol || OrderGetInteger(ORDER_MAGIC) != magic)
         continue;
      long type = OrderGetInteger(ORDER_TYPE);
      if(type == ORDER_TYPE_BUY_LIMIT || type == ORDER_TYPE_SELL_LIMIT || type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_SELL_STOP)
         count++;
   }
   return count;
}

double GoldBotReadDailyPnlPct(bool &available)
{
   available = false;
   string key = GoldBotDayKey("startEquity");
   if(!GlobalVariableCheck(key))
      return 0.0;
   double startEquity = GlobalVariableGet(key);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(startEquity <= 0.0 || equity <= 0.0)
      return 0.0;
   available = true;
   return ((equity - startEquity) / startEquity) * 100.0;
}

double GoldBotReadMonthlyPnlPct(bool &available)
{
   available = false;
   string startKey = GoldBotMagicKey("MonthStartEquity");
   if(!GlobalVariableCheck(startKey))
      startKey = GoldBotMagicKey("CompoundMonthStartEquity");
   if(!GlobalVariableCheck(startKey))
      return 0.0;
   double startEquity = GlobalVariableGet(startKey);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(startEquity <= 0.0 || equity <= 0.0)
      return 0.0;
   available = true;
   return ((equity - startEquity) / startEquity) * 100.0;
}

void GoldBotDashboardLabel(const string name, const int row, const string text, const color textColor)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER, InpDashboardCorner);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 14);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 12 + row * 16);
   ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, row == 0 ? 10 : 8);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void GoldBotDashboardRefresh()
{
   if(!InpEnableChartDashboard)
      return;

   string symbol = GoldBotSymbol();
   int openCount = GoldBotCountManagedPositions(symbol, InpMagicNumber);
   int pendingCount = GoldBotCountManagedPendingOrders(symbol, InpMagicNumber);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double spread = (ask > 0.0 && bid > 0.0) ? ask - bid : 0.0;
   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   bool dailyAvailable = false;
   bool monthlyAvailable = false;
   double dailyPnlPct = GoldBotReadDailyPnlPct(dailyAvailable);
   double monthlyPnlPct = GoldBotReadMonthlyPnlPct(monthlyAvailable);
   string dailyText = dailyAvailable ? DoubleToString(dailyPnlPct, 2) + "%" : "n/a";
   string monthlyText = monthlyAvailable ? DoubleToString(monthlyPnlPct, 2) + "%" : "n/a";

   string backgroundName = "GoldBotDash_BG";
   int rowCount = InpDashboardVerbose ? 13 : 11;
   if(ObjectFind(0, backgroundName) < 0)
      ObjectCreate(0, backgroundName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, backgroundName, OBJPROP_CORNER, InpDashboardCorner);
   ObjectSetInteger(0, backgroundName, OBJPROP_XDISTANCE, 8);
   ObjectSetInteger(0, backgroundName, OBJPROP_YDISTANCE, 8);
   ObjectSetInteger(0, backgroundName, OBJPROP_XSIZE, 430);
   ObjectSetInteger(0, backgroundName, OBJPROP_YSIZE, 24 + rowCount * 16);
   ObjectSetInteger(0, backgroundName, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, backgroundName, OBJPROP_COLOR, clrDimGray);
   ObjectSetInteger(0, backgroundName, OBJPROP_BACK, false);

   color statusColor = clrWhite;
   if(dashboardStatus == "BLOCKED")
      statusColor = clrTomato;
   else if(dashboardStatus == "ORDER PLACED")
      statusColor = clrLime;
   else if(dashboardStatus == "WAITING SETUP")
      statusColor = clrGold;
   else if(dashboardStatus == "DEBUG ONLY")
      statusColor = clrDeepSkyBlue;

   GoldBotDashboardLabel("GoldBotDash_Row0", 0, StringFormat("GoldBot %s | %s M15 | magic %I64d", dashboardStatus, symbol, InpMagicNumber), statusColor);
   GoldBotDashboardLabel("GoldBotDash_Row1", 1, StringFormat("Tick %s | H%02d | spread %.2f", GoldBotDashboardTime(dashboardLastTick), nowParts.hour, spread), clrWhite);
   GoldBotDashboardLabel("GoldBotDash_Row2", 2, StringFormat("Bars M15 %s | M5 %s | M1 %s", GoldBotDashboardTime(lastM15Bar), GoldBotDashboardTime(lastM5Bar), GoldBotDashboardTime(lastM1Bar)), clrSilver);
   GoldBotDashboardLabel("GoldBotDash_Row3", 3, StringFormat("PnL day %s | month %s | ladders %d/%d", dailyText, monthlyText, GoldBotDailyLadderCount(), InpMaxLaddersPerDay), clrWhite);
   GoldBotDashboardLabel("GoldBotDash_Row4", 4, StringFormat("Positions %d/%d | pending %d", openCount, InpMaxOpenTrades, pendingCount), clrWhite);
   GoldBotDashboardLabel("GoldBotDash_Row5", 5, "SMC: " + dashboardSmcState, clrSilver);
   GoldBotDashboardLabel("GoldBotDash_Row6", 6, "Breakout: " + dashboardBreakoutState, clrSilver);
   GoldBotDashboardLabel("GoldBotDash_Row7", 7, "M5 scalp: " + dashboardM5State, clrSilver);
   GoldBotDashboardLabel("GoldBotDash_Row8", 8, "M1 micro: " + dashboardM1State, clrSilver);
   GoldBotDashboardLabel("GoldBotDash_Row9", 9, StringFormat("Last setup %s | signal %s", dashboardLastSetup, dashboardLastSignalId), clrWhite);
   GoldBotDashboardLabel("GoldBotDash_Row10", 10, dashboardHint, statusColor);

   if(InpDashboardVerbose)
   {
      GoldBotDashboardLabel("GoldBotDash_Row11", 11, "Blocker: " + dashboardBlocker, clrSilver);
      GoldBotDashboardLabel("GoldBotDash_Row12", 12, StringFormat("Debug=%s parity=%s forwardLog=%s", InpDebugOnly ? "yes" : "no", InpPythonParityMode ? "yes" : "no", InpEnableForwardEventLog ? "yes" : "no"), clrSilver);
   }
   else
   {
      ObjectDelete(0, "GoldBotDash_Row11");
      ObjectDelete(0, "GoldBotDash_Row12");
   }

   ChartRedraw(0);
}

void GoldBotDashboardDelete()
{
   ObjectDelete(0, "GoldBotDash_BG");
   for(int i = 0; i < 20; i++)
      ObjectDelete(0, StringFormat("GoldBotDash_Row%d", i));
}

string GoldBotForwardEventPath()
{
   string path = InpForwardEventFile;
   if(StringLen(path) <= 0)
      path = "GoldBot/forward_events.csv";
   StringReplace(path, "/", "\\");
   return path;
}

void GoldBotForwardEvent(const string eventName, const string setupName, const GoldBotDirection direction, const string reason, const double score, const int confluences, const string signalId, const bool alwaysWrite)
{
   if(!InpEnableForwardEventLog)
      return;

   string key = eventName + "|" + setupName + "|" + IntegerToString((int)direction) + "|" + reason + "|" + signalId;
   if(!alwaysWrite && key == dashboardLastEventKey)
      return;
   dashboardLastEventKey = key;

   string path = GoldBotForwardEventPath();
   int slash = StringFind(path, "\\");
   if(slash > 0)
      FolderCreate(StringSubstr(path, 0, slash));

   int handle = FileOpen(path, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI);
   if(handle == INVALID_HANDLE)
      return;
   bool writeHeader = FileSize(handle) == 0;
   FileSeek(handle, 0, SEEK_END);
   if(writeHeader)
      FileWrite(handle, "time", "symbol", "magic", "status", "event", "setup", "direction", "hour", "reason", "score", "confluences", "dailyPnlPct", "monthlyPnlPct", "spread", "openPositions", "pendingOrders", "signalId");

   string symbol = GoldBotSymbol();
   MqlDateTime nowParts;
   TimeToStruct(TimeCurrent(), nowParts);
   bool dailyAvailable = false;
   bool monthlyAvailable = false;
   double dailyPnlPct = GoldBotReadDailyPnlPct(dailyAvailable);
   double monthlyPnlPct = GoldBotReadMonthlyPnlPct(monthlyAvailable);
   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
   double spread = (ask > 0.0 && bid > 0.0) ? ask - bid : 0.0;

   FileWrite(
      handle,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      symbol,
      InpMagicNumber,
      dashboardStatus,
      eventName,
      setupName,
      (int)direction,
      nowParts.hour,
      reason,
      DoubleToString(score, 2),
      confluences,
      dailyAvailable ? DoubleToString(dailyPnlPct, 2) : "",
      monthlyAvailable ? DoubleToString(monthlyPnlPct, 2) : "",
      DoubleToString(spread, 2),
      GoldBotCountManagedPositions(symbol, InpMagicNumber),
      GoldBotCountManagedPendingOrders(symbol, InpMagicNumber),
      signalId
   );
   FileClose(handle);
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

string GoldBotSetupName(const int setupCode)
{
   if(setupCode == GOLDBOT_SETUP_CONTINUATION)
      return "continuation";
   if(setupCode == GOLDBOT_SETUP_BREAKOUT_RETEST)
      return "breakout_retest";
   if(setupCode == GOLDBOT_SETUP_M5_SCALP)
      return "m5_scalp";
   if(setupCode == GOLDBOT_SETUP_M1_MICRO_SCALP)
      return "m1_micro_scalp";
   return "smc";
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
   GlobalVariableSet(posKey + ".setup", GoldBotMetadataValue(orderKey, "setup", (double)GOLDBOT_SETUP_SMC));
   GlobalVariableSet(posKey + ".scalpVariant", GoldBotMetadataValue(orderKey, "scalpVariant", 0.0));
   GlobalVariableSet(posKey + ".signalCode", GoldBotMetadataValue(orderKey, "signalCode", (double)GoldBotSignalCodeFromComment(comment)));
   if(GlobalVariableCheck(orderKey + ".maxHoldSeconds"))
      GlobalVariableSet(posKey + ".maxHoldSeconds", GoldBotMetadataValue(orderKey, "maxHoldSeconds", 0.0));
   if(GlobalVariableCheck(orderKey + ".tp1R"))
      GlobalVariableSet(posKey + ".tp1R", GoldBotMetadataValue(orderKey, "tp1R", 0.0));
   if(GlobalVariableCheck(orderKey + ".tp2R"))
      GlobalVariableSet(posKey + ".tp2R", GoldBotMetadataValue(orderKey, "tp2R", 0.0));
   if(GlobalVariableCheck(orderKey + ".tp3R"))
      GlobalVariableSet(posKey + ".tp3R", GoldBotMetadataValue(orderKey, "tp3R", 0.0));
   if(GlobalVariableCheck(orderKey + ".trailAfterTp1Setting"))
      GlobalVariableSet(posKey + ".trailAfterTp1Setting", GoldBotMetadataValue(orderKey, "trailAfterTp1Setting", -1.0));
   if(GlobalVariableCheck(orderKey + ".breakEvenAtR"))
      GlobalVariableSet(posKey + ".breakEvenAtR", GoldBotMetadataValue(orderKey, "breakEvenAtR", 0.0));
   if(GlobalVariableCheck(orderKey + ".trailStartR"))
      GlobalVariableSet(posKey + ".trailStartR", GoldBotMetadataValue(orderKey, "trailStartR", 0.0));
   if(GlobalVariableCheck(orderKey + ".riskCash"))
      GlobalVariableSet(posKey + ".riskCash", GoldBotMetadataValue(orderKey, "riskCash", 0.0));
   if(GlobalVariableCheck(orderKey + ".spread"))
      GlobalVariableSet(posKey + ".spread", GoldBotMetadataValue(orderKey, "spread", 0.0));
   if(GlobalVariableCheck(orderKey + ".spreadToTpPct"))
      GlobalVariableSet(posKey + ".spreadToTpPct", GoldBotMetadataValue(orderKey, "spreadToTpPct", 0.0));
   if(GlobalVariableCheck(orderKey + ".adx"))
      GlobalVariableSet(posKey + ".adx", GoldBotMetadataValue(orderKey, "adx", 0.0));
   if(GlobalVariableCheck(orderKey + ".diGap"))
      GlobalVariableSet(posKey + ".diGap", GoldBotMetadataValue(orderKey, "diGap", 0.0));
   if(GlobalVariableCheck(orderKey + ".atr"))
      GlobalVariableSet(posKey + ".atr", GoldBotMetadataValue(orderKey, "atr", 0.0));
   if(GlobalVariableCheck(orderKey + ".atrRatio"))
      GlobalVariableSet(posKey + ".atrRatio", GoldBotMetadataValue(orderKey, "atrRatio", 0.0));
   if(GlobalVariableCheck(orderKey + ".ema21"))
      GlobalVariableSet(posKey + ".ema21", GoldBotMetadataValue(orderKey, "ema21", 0.0));
   if(GlobalVariableCheck(orderKey + ".ema50"))
      GlobalVariableSet(posKey + ".ema50", GoldBotMetadataValue(orderKey, "ema50", 0.0));
   if(GlobalVariableCheck(orderKey + ".vwap"))
      GlobalVariableSet(posKey + ".vwap", GoldBotMetadataValue(orderKey, "vwap", 0.0));
   if(GlobalVariableCheck(orderKey + ".zoneBottom"))
      GlobalVariableSet(posKey + ".zoneBottom", GoldBotMetadataValue(orderKey, "zoneBottom", 0.0));
   if(GlobalVariableCheck(orderKey + ".zoneTop"))
      GlobalVariableSet(posKey + ".zoneTop", GoldBotMetadataValue(orderKey, "zoneTop", 0.0));
   if(GlobalVariableCheck(orderKey + ".zoneWidth"))
      GlobalVariableSet(posKey + ".zoneWidth", GoldBotMetadataValue(orderKey, "zoneWidth", 0.0));
   if(GlobalVariableCheck(orderKey + ".slDistance"))
      GlobalVariableSet(posKey + ".slDistance", GoldBotMetadataValue(orderKey, "slDistance", 0.0));
   if(GlobalVariableCheck(orderKey + ".lotMultiplier"))
      GlobalVariableSet(posKey + ".lotMultiplier", GoldBotMetadataValue(orderKey, "lotMultiplier", 0.0));
   if(GlobalVariableCheck(orderKey + ".setupRiskMultiplier"))
      GlobalVariableSet(posKey + ".setupRiskMultiplier", GoldBotMetadataValue(orderKey, "setupRiskMultiplier", 0.0));

   GlobalVariableDel(orderKey + ".dir");
   GlobalVariableDel(orderKey + ".split");
   GlobalVariableDel(orderKey + ".hour");
   GlobalVariableDel(orderKey + ".scoreBucket");
   GlobalVariableDel(orderKey + ".confluences");
   GlobalVariableDel(orderKey + ".enabledConfluences");
   GlobalVariableDel(orderKey + ".setup");
   GlobalVariableDel(orderKey + ".scalpVariant");
   GlobalVariableDel(orderKey + ".signalCode");
   GlobalVariableDel(orderKey + ".maxHoldSeconds");
   GlobalVariableDel(orderKey + ".tp1R");
   GlobalVariableDel(orderKey + ".tp2R");
   GlobalVariableDel(orderKey + ".tp3R");
   GlobalVariableDel(orderKey + ".trailAfterTp1Setting");
   GlobalVariableDel(orderKey + ".breakEvenAtR");
   GlobalVariableDel(orderKey + ".trailStartR");
   GlobalVariableDel(orderKey + ".riskCash");
   GlobalVariableDel(orderKey + ".spread");
   GlobalVariableDel(orderKey + ".spreadToTpPct");
   GlobalVariableDel(orderKey + ".adx");
   GlobalVariableDel(orderKey + ".diGap");
   GlobalVariableDel(orderKey + ".atr");
   GlobalVariableDel(orderKey + ".atrRatio");
   GlobalVariableDel(orderKey + ".ema21");
   GlobalVariableDel(orderKey + ".ema50");
   GlobalVariableDel(orderKey + ".vwap");
   GlobalVariableDel(orderKey + ".zoneBottom");
   GlobalVariableDel(orderKey + ".zoneTop");
   GlobalVariableDel(orderKey + ".zoneWidth");
   GlobalVariableDel(orderKey + ".slDistance");
   GlobalVariableDel(orderKey + ".lotMultiplier");
   GlobalVariableDel(orderKey + ".setupRiskMultiplier");
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
   GlobalVariableDel(posKey + ".setup");
   GlobalVariableDel(posKey + ".scalpVariant");
   GlobalVariableDel(posKey + ".signalCode");
   GlobalVariableDel(posKey + ".maxHoldSeconds");
   GlobalVariableDel(posKey + ".tp1R");
   GlobalVariableDel(posKey + ".tp2R");
   GlobalVariableDel(posKey + ".tp3R");
   GlobalVariableDel(posKey + ".trailAfterTp1Setting");
   GlobalVariableDel(posKey + ".breakEvenAtR");
   GlobalVariableDel(posKey + ".trailStartR");
   GlobalVariableDel(posKey + ".riskCash");
   GlobalVariableDel(posKey + ".spread");
   GlobalVariableDel(posKey + ".spreadToTpPct");
   GlobalVariableDel(posKey + ".adx");
   GlobalVariableDel(posKey + ".diGap");
   GlobalVariableDel(posKey + ".atr");
   GlobalVariableDel(posKey + ".atrRatio");
   GlobalVariableDel(posKey + ".ema21");
   GlobalVariableDel(posKey + ".ema50");
   GlobalVariableDel(posKey + ".vwap");
   GlobalVariableDel(posKey + ".zoneBottom");
   GlobalVariableDel(posKey + ".zoneTop");
   GlobalVariableDel(posKey + ".zoneWidth");
   GlobalVariableDel(posKey + ".slDistance");
   GlobalVariableDel(posKey + ".lotMultiplier");
   GlobalVariableDel(posKey + ".setupRiskMultiplier");
   GlobalVariableDel(posKey + ".closedProfit");
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
   ZeroMemory(bucket);
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
