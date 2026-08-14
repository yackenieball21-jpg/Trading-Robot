//+------------------------------------------------------------------+
//|                                                      MY BOT.mq5 |
//|  H4 zone + H4 entry multi-timeframe system                      |
//|  v10.0 — H4 zones + H4 trend + break-retest entries            |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property version   "10.10"
#property strict

static const string EA_VERSION = "v10.1";

#include <Trade\Trade.mqh>
#include "SymbolProfiler.mqh"
#include "MarketStateManager.mqh"
#include "IndicatorManager.mqh"
#include "ZoneManager.mqh"
#include "ZoneScoringEngine.mqh"
#include "RiskManager.mqh"
#include "SignalEngine.mqh"
#include "PositionManager.mqh"  // Now includes TradeManager functionality
#include "AIScaffold.mqh"
#include "TradeExecutor.mqh"
#include "MarketClassifier.mqh"
#include "NewsFilter.mqh"
#include "MaintenanceFilter.mqh"
#include "CandlePatterns.mqh"
#include "AIMemory.mqh"
#include "ConfidenceTracker.mqh"
// DISABLED FOR SIMPLIFIED LIVE MODEL:
// #include "SupportResistanceZones.mqh"
// #include "TrailingStopManager.mqh"
// #include "PartialProfitManager.mqh"
// #include "ChannelPositionManager.mqh"
// Note: MarketStructure.mqh is included via ZoneManager.mqh

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== Risk Management ==="
input double EquityPercentForLots      = 1.0;   // (Legacy) Equity % fallback - not primary
input double RiskPercent               = 0.50;  // Risk per trade (%) — auto-adjusts lots per symbol/spread/digits
input double RewardRisk                = 2.0;   // Reward:Risk ratio
input double MaxDailyLossPercent       = 2.0;   // Max daily loss (%)
input double MaxDrawdownPercent        = 10.0;  // Max account drawdown (%)
input int    MaxConsecutiveLosses      = 3;     // Max consecutive losses
input int    MaxBrokerErrors           = 3;     // Max broker errors before lockout
input int    CooldownBarsAfterLoss     = 1;     // Bars to wait after loss
input bool   UseMinLotFallback           = false; // Use volMin when idealLots < volMin (RISK MODE ONLY)
input double MinLotFallbackMaxRiskMult   = 1.25;  // Max risk multiple allowed for min-lot fallback
input double MinLotFallbackMaxEquityPct  = 1.50;  // Absolute max % equity allowed when using volMin fallback
input bool   AllowAggressiveMinLotFallback       = false; // OPTIONAL: Second-stage aggressive fallback (default OFF)
input double AggressiveMinLotFallbackMaxRiskMult = 12.0;  // Aggressive max risk multiple (only if above enabled)
input double AggressiveMinLotFallbackMaxEquityPct = 12.0; // Aggressive max equity % (only if above enabled)

// STEP 1: High-risk backtest mode
input bool   InpUseHighRiskBacktestMode = false;  // Enable 15% risk for tester only
input double InpHighRiskBacktestPercent = 15.0;   // High-risk tester risk %
input double InpLiveMaxRiskPercent      = 3.0;    // Live safety cap when high-risk mode is off

input group "=== Position Sizing Mode ==="
enum ENUM_POSITION_SIZING_MODE
{
   SIZE_BY_RISK = 0,
   SIZE_BY_EQUITY_NOTIONAL = 1,
   SIZE_BY_EQUITY_MARGIN = 2,
   SIZE_BY_FIXED_LOT = 3
};
input ENUM_POSITION_SIZING_MODE LotSizingMode = SIZE_BY_RISK;      // Position sizing mode
input double FixedLotSize              = 0.01;  // Default fixed lot (forex/unknown)
input double FixedLotSizeGold          = 0.01;  // Fixed lot for XAUUSD/Gold
input double FixedLotSizeVol10         = 1.00;  // Fixed lot for Volatility 10 Index
input double FixedLotSizeVol25         = 0.50;  // Fixed lot for Volatility 25 Index
input double FixedLotSizeVol50         = 0.30;  // Fixed lot for Volatility 50 Index
input double FixedLotSizeVol75         = 0.20;  // Fixed lot for Volatility 75 Index
input double FixedLotSizeVol100        = 0.10;  // Fixed lot for Volatility 100 Index
input double FixedLotSizeBoom          = 0.20;  // Fixed lot for Boom 300/500/1000
input double FixedLotSizeCrash         = 0.20;  // Fixed lot for Crash 300/500/1000
input double FixedLotSizeStep          = 0.50;  // Fixed lot for Step Index
input double FixedLotSizeJump          = 0.20;  // Fixed lot for Jump indices
input double FixedLotSizeIndex         = 0.10;  // Fixed lot for US/EU indices (NAS100, US30)
input double FixedLotSizeCrypto        = 0.01;  // Fixed lot for Crypto CFDs
input double EquityPerTradePercent = 30.0;   // % of account equity per trade (equity modes only)
input bool   BlockTradeIfBelowMinLot = false; // Allow fallback to min lot when equity-based size below broker minimum

input group "=== Structure + ATR Stop-Loss ==="
input int    ATRPeriod             = 14;       // ATR period (live)
input int    ATRReferencePeriod    = 20;       // ATR reference period (original tuning baseline)

input group "=== Position Stacking ==="
input bool   EnableStacking             = false;   // Allow multiple sweep entries per session
input bool   OnePositionPerSymbol       = true;    // Only one position per symbol

input group "=== Entry Filters ==="
input int    TrendSlopeLookback    = 5;        // Bars for EMA slope (regime classifier)
input int    SwingLookback         = 10;       // Bars for swing SL (trailing/structure)
input double MinSLOverridePoints   = 0.0;      // Min SL distance override (points)
input double MaxSpreadMultiplier   = 2.0;      // Max spread multiplier
input int    ZoneMergePoints       = 150;      // Merge zones within this distance (points)

input group "=== Zone Entry Filter Stack ==="
input double EntryADXMin       = 15.0;  // Minimum ADX for any entry (loosened from 20)
input double EntryADXTrend     = 25.0;  // ADX >= this → trend mode (EMA50/200 filter active)
input double EntryADXRange     = 18.0;  // ADX < this  → range mode (bounce both sides) (loosened from 20)
input double EntryZoneTolATR   = 1.00;  // Zone proximity tolerance (× ATR)
input double EntryStopATR      = 0.50;  // SL buffer beyond zone edge (× ATR)


input group "=== Market Classifier ==="
input bool   UseMarketClassifier   = true;     // Enable market regime classification
input double ClassTrendATRMult     = 0.80;     // EMA gap >= ATR*this = trending
input double ClassConsolidATRRatio = 0.65;     // ATR/avg <= this = consolidation
input double ClassRangeATRMult     = 0.35;     // EMA gap <= ATR*this = range
input bool   ClassUseSlopeFilter   = true;     // Require EMAs sloping for trend
input int    ClassSlopeLookback    = 3;        // Bars for slope comparison


input group "=== Position Management ==="
// OnePositionPerSymbol moved to Position Stacking group
input int    MaxOpenPositionsTotal = 2;        // Max total positions (0=unlimited)
input bool   AllowHedging          = false;    // Allow opposite-direction positions on same symbol
input bool   CloseOnOppositeCross  = false;    // DISABLED for live - trend positions managed by ManageStructureTrail only
input bool   ExitOnCloseBeyondEMA50 = false;   // DISABLED for live - no immediate EMA50 exit
input bool   UseEMA50ProfitProtection = false; // DISABLED for live - no EMA50 profit protection

input group "=== Trailing Stop ==="
input bool   UseBreakeven          = true;     // ON - required for structure trail progression
input double BreakevenAtR          = 1.5;      // Move to breakeven at this R multiple
input int    TrailSwingLookback    = 10;       // Bars to look for H4 swing high/low
input double TrailSwingBuffATR     = 0.60;     // ATR buffer below swing low / above swing high
input bool   UseEMA50Trail         = true;     // Use EMA50 trail when trend is very strong
input double EMA50TrailBuffATR     = 0.75;     // ATR buffer from EMA50 in strong trend mode

input group "=== Partial Profit Taking ==="

input group "=== Time Filter ==="
input int    TradingStartHour      = -1;       // Start hour (-1=disabled)
input int    TradingEndHour        = -1;       // End hour (-1=disabled)

input group "=== News & Maintenance Filter ==="
input bool   UseNewsFilter         = true;     // Enable forex news filter
input int    HighNewsBlockBefore   = 30;       // Block entries X min before HIGH news
input int    HighNewsBlockAfter    = 30;       // Block entries X min after HIGH news
input int    HighNewsCloseBefore   = 10;       // Force-close trades X min before HIGH news
input int    MedNewsBlockBefore    = 15;       // Block entries X min before MEDIUM news
input int    MedNewsBlockAfter     = 15;       // Block entries X min after MEDIUM news
input bool   UseMaintFilter        = true;     // Enable maintenance filter
input int    MaintBlockBefore      = 30;       // Block entries X min before maintenance
input int    MaintBlockAfter       = 15;       // Resume trading X min after maintenance
input int    MaintCloseBefore      = 10;       // Force-close trades X min before maintenance

input group "=== AI Layer ==="
input bool   EnableAI              = false;    // Enable AI layer
input string AIModelPath           = "";       // ONNX model path
input double AISkipThreshold       = 0.0;      // Skip trade if AI score below this (0=disabled, try 0.55)

input group "=== AI Learning ==="
input bool   UseAILearning         = false;    // Enable adaptive learning from all trades
input double MinLearnedWinRate     = 0.35;     // Block patterns below this win rate
input ENUM_AI_LEARN_MODE AILearnMode = AI_LEARN_NORMAL; // Learning mode for this run
input bool   AIMemoryReset         = false;    // Reset all learned patterns (backs up first)
input string AIMemoryTag           = "";       // Version tag for memory file (empty=default)

input group "=== Notifications ==="
input bool   EnableNotifications   = false;    // Enable push notifications

input group "=== Zone Scoring ==="
input bool   UseZoneScoring        = false;    // Enable zone-score entry gate
input int    MinEntryScore         = 0;        // Min score to allow entry (0=disabled)
input double ZoneConfluenceATRMult = 0.5;      // ATR mult for fresh/hist zone confluence
input int    MaxZoneRetests        = 4;        // Max retests before zone is overtested
// NOTE: ZoneLifetimeBars moved to "D1 Zone Strength & Lookback" section as InpD1ZoneLifetimeBars
// PATCH 15: Quality scoring thresholds
input bool   ZoneStrictMajorFilter = true;     // Strict major-zone-only filter for trend mode
input double ZoneMajorScoreThreshold = 5.75;   // Photo-like filter: only strong zones qualify as major
input double ZoneWeakRejectThreshold = 3.25;   // Reject weak/noisy zones earlier
input bool   InpUsePhotoLikeZoneFilter = true; // Keep only clean checklist-qualified zones
input int    InpZoneMinimumChecklistHits = 3;  // Zone must pass at least 3/5: departure, BOS, swing, freshness, confluence

// Force photo-style zones even if MT5 Strategy Tester loads old .set values.
input bool   InpForcePhotoStyleZonePreset      = true;
input double InpPhotoZoneMajorScoreThreshold   = 5.75;
input double InpPhotoZoneWeakRejectThreshold   = 3.25;
input int    InpPhotoZoneMinimumChecklistHits  = 3;

// Wick-play entry model
input bool   InpUseWickPlayEntryOnly           = false;  // true = entries only from wick/sweep/rejection at zones
input bool   InpAggressiveZoneEntry            = true;   // Allow entries on any zone touch with basic candle confirmation (less strict)
input double InpWickPlayMinWickToRange         = 0.20;   // wick must be at least 20% of candle range (relaxed for more entries)
input double InpWickPlayMinCloseBackZoneATR    = 0.10;   // close must reclaim/reject zone by ATR amount (increased)
input double InpWickPlayZoneTouchATR           = 0.50;   // candle must touch/penetrate zone within this ATR tolerance (increased)
input bool   InpWickPlayAllowEngulfingConfirm  = true;   // allow engulfing only if candle interacts with zone
input bool   InpWickPlayAllowBreakRetest       = true;   // allow break-retest only if rejection candle confirms
input bool   InpSDBodyTouchRequiresConfirmation = true;  // Aggressive zone-touch entries must also show wick rejection or close-back out of zone
input bool   InpSDRequireH4TrendAlignment      = true;   // Block S/D entries against H4 EMA200 trend (demand only in uptrend / supply only in downtrend)
input ENUM_TIMEFRAMES InpSDTrendReferenceTF    = PERIOD_H4; // Higher-TF used as trend reference when bot runs on lower TFs (M1/M5/M15 etc.)
input bool   InpSDReversalBypassIfMajor        = true;   // Allow DBR/RBD reversal entries against H4 trend when zone is structurally major

input group "=== Pullback Filter ==="
input bool   EnablePullbackFilter  = true;     // Enable fake pullback detection
input int    MaxRecentTouches      = 5;        // Max recent zone touches before rejection (loosened from 3)
input double MinBodyRatio          = 0.20;      // Min candle body ratio (loosened from 0.30)
input double MaxWickRatio          = 0.75;      // Max wick ratio before rejection (loosened from 0.60)
input double MinPenetrationATR     = 0.08;      // Min zone penetration depth (ATR) (loosened from 0.15)
input double MinVolumeRatio        = 0.50;      // Min volume ratio vs average (loosened from 0.70)

input group "=== Zone Merge ==="
input bool   EnableZoneMerge            = true;    // Enable overlapping zone consolidation
input int    MergeDistancePoints        = 80;      // Max gap (points) to still merge
input double MinOverlapPercent          = 0.30;    // Min overlap ratio to auto-merge
input int    MaxMergedZoneWidthPoints   = 400;     // Hard floor for merged width
input double MaxMergedZoneWidthATR      = 2.50;    // Dynamic max merged width = max(hard floor, ATR*mult)
input bool   AllowBullishFamilyMerge    = true;    // Merge Support+Demand zones (same bull side)
input bool   AllowBearishFamilyMerge    = true;    // Merge Resistance+Supply zones (same bear side)
// H1 zone detection removed - bot now uses H4 execution only

input group "=== Sweep Entry Filter ==="
input bool   UseSweepEntry          = true;     // Enable sweep+rejection entry filter
input int    SweepEMA_Period        = 50;       // EMA period for sweep direction filter
input int    SweepADX_Period        = 14;       // ADX period for strength filter
input double SweepADX_Minimum       = 15.0;     // Min ADX for valid entry
input double SweepATRMultiplier     = 0.50;     // Max sweep penetration (ATR mult)
input double SweepRecoveryATRMult   = 0.10;     // Min recovery distance (ATR mult)
input double MinSweepCandleATR      = 0.50;     // Min sweep candle range (ATR mult)
input double MinConfirmCandleATR    = 0.40;     // Min confirm candle range (ATR mult)
input double SweepStopBufferATR     = 0.15;     // SL buffer beyond sweep/zone (ATR mult)
input bool   SweepUseDIConfirmation = true;     // Require +DI/-DI direction match
input bool   SweepRequireCloseBeyond = true;    // Require confirm close beyond sweep extreme
input bool   SweepOneTradePerZone   = true;     // One trade per zone until price leaves

input group "=== Setup Family Control ==="
input bool   UseBreakRetestEntry               = true;   // ON - trend continuation family
input bool   UseReversalDetector               = false;  // OFF - reversal detection disabled
input bool   AllowSweepCounterTrend            = false;  // Allow sweep reversals counter-trend
input double ReversalScoreMin                  = 5.0;    // Min score for sweep reversal entry
input double BreakRetestScoreMin               = 4.0;    // Min score for break+retest entry
input int    MaxStackedTrendPositions          = 3;      // Max stacked positions in same direction
input bool   BlockContinuationOnHTFReversal    = true;   // NOT WIRED - placeholder for future HTF reversal filter
// RequireH1StructureShiftForReversal removed - bot now uses H4 execution only

input group "=== Market Structure ==="
input bool   UseMarketStructure        = true;    // ON - required for dynamic/channel trend entries
input int    StructureSwingLookback    = 4;       // Bars on each side for swing detection
input int    StructureScanBars         = 50;      // Bars to scan for swing points
input double ChannelTouchTolerance     = 0.6;     // ATR tolerance for channel touch
input bool   BlockCounterTrendTrades   = true;    // Block trades against confirmed trend

input group "=== Trend Campaign ==="
input bool   EnableTrendCampaign                 = true;   // Enable trend campaign mode
input bool   TrendTradesUseNoFixedTP             = true;   // No fixed TP for trend runners
input bool   AllowTrendAddsAtDynamicZones        = true;   // Allow adds at dynamic zone retests
input int    MaxTrendCampaignPositions           = 3;      // Max positions per trend campaign
input int    MinBarsBetweenTrendAdds             = 2;      // Min bars between trend adds
input double MinATRDistanceBetweenTrendAdds      = 0.80;   // Min ATR distance between adds
input bool   RequireExistingTrendPositionProfit  = true;   // Require existing position in profit for add
input bool   OneAddPerFreshDynamicZone           = true;   // Only one add per fresh zone
input double TrendEndADXFloor                    = 18.0;   // ADX floor for trend-end check
input int    TrendEndConfirmBars                 = 2;      // Bars to confirm trend end
input bool   InpSDTrendRetestsAreRunners         = true;   // Trend-aligned S/D retests become trend runners
input bool   InpTrendRunnerNoBrokerTP            = true;   // Trend runners have no fixed broker TP
input bool   InpTrendRunnerUseVirtualTarget      = true;   // Keep target internally for confidence only
input double InpTrendRunnerTrailStartR           = 1.50;   // Start structure trailing after 1.5R
input double InpTrendRunnerBEAtR                 = 1.20;   // Move to BE after 1.2R for runners
input bool   InpTrendRunnerCloseOnlyOnTrendEnd   = true;   // Do not TP trend trades early

input group "=== PDF-Style Supply & Demand Zones ==="
input bool   InpUseSupplyDemandZones       = true;     // Use PDF-style Supply/Demand zones
input bool   InpDisableLegacySRZones       = true;     // Disable old swing support/resistance marking
input bool   InpUseStructuralFallbackZones = true;     // Use HH/HL/LH/LL structural zones when S/D detection creates no usable zones
input bool   InpSDDrawRectangles           = true;     // Draw full rectangles like the PDF
input color  InpSDDemandColor              = C'0,255,0';   // Demand = bright green
input color  InpSDSupplyColor              = C'255,0,0';   // Supply = bright red
input ENUM_SD_MARKING_METHOD InpSDMarkingMethod = SD_MARK_METHOD_MOMENTUM; // Primary method: momentum candles
input bool   InpSDEnableAllMethods         = false;    // Use all 3 S/D methods together (momentum + consolidation + wick)
input bool   InpSDUseMomentumMethod        = true;     // Momentum: 3+ strong candles → zone = previous candle high/low
input bool   InpSDUseConsolidationMethod   = false;    // Consolidation: sideways base → box the entire range
input bool   InpSDUseWickMethod            = false;    // Default: wick-play S/D method
input bool   InpSDUseSingleMomentumCandleMethod = false;  // Extreme impulse method: 1 huge candle marks previous candle high/low as S/D zone
input int    InpSDMinMomentumCandles       = 3;        // PDF method: at least N momentum candles (min floor = 3)
input int    InpSDMaxMomentumCandles       = 6;        // Allow stronger 4/5/6 candle runs
input double InpSDMomentumBodyPct          = 0.50;     // Momentum candle body must be 50%+ of candle range
input double InpSDMomentumBodyMult         = 1.05;     // Body must be larger than average body
input double InpSDExtremeImpulseBodyMult   = 1.60;     // Single impulse body must be at least 1.6x average body
input double InpSDExtremeImpulseRangeATR   = 0.80;     // Single impulse full candle range must be at least 0.8 ATR
input double InpSDExtremeImpulseBodyPct    = 0.55;     // Body must be at least 55% of candle range
input bool   InpSDExtremeImpulseRequireBOS = false;    // Require the impulse candle to break structure
input int    InpSDConsolidationBars        = 5;        // Box previous sideways consolidation
input double InpSDConsolidationMaxATR      = 1.25;     // Max consolidation height in ATR
input double InpSDMinDepartureATR          = 0.80;     // Minimum push away from zone
input double InpSDMajorDepartureATR        = 1.25;     // Major zone threshold
input double InpSDMinWickPct               = 0.35;     // Wick method: wick must be 35%+ of candle range
input int    InpSDWickScanBars             = 60;       // Wick method: bars to scan for confluent wicks
input int    InpSDMinWickCluster           = 2;        // Wick method: minimum confluent wicks to form a band
input double InpSDWickClusterATR           = 0.25;     // Wick method: cluster tolerance in ATR (how close wicks must be)
input int    InpSDBOSLookback              = 12;       // Break-of-structure lookback
input double InpSDMinZoneWidthPoints       = 35;       // Minimum rectangle height in points
input bool   InpSDClassifyPatternType      = true;     // Classify zones as RBD/DBD/DBR/RBR
input bool   InpSDShowPatternInLabel       = false;    // false = chart says Supply/Demand only, true = show Supply RBD etc.
input int    InpSDPreBaseLegBars           = 4;        // Candles before base used to classify incoming leg
input int    InpSDMinPreBaseMomentum       = 2;        // Minimum momentum candles before base
input double InpSDWeakLegBodyPct           = 0.50;     // Fallback body % for classifying incoming leg
input bool   InpSDTradeOnlyActivePair      = true;     // Trade only the best active Supply and Demand
input bool   InpSDShowOnlyActivePair       = true;     // Show only active Supply/Demand rectangles on chart
input bool   InpSDKeepBackupZonesInMemory  = true;     // Keep other zones hidden but available as backups
input int    InpSDMaxBackupZonesPerSide    = 2;        // Number of backup supply/demand zones to mark internally
input int    InpSDMaxFreshTouches          = 1;        // 0 = untouched only, 1 = allow first retest
input double InpSDMinActiveZoneScore       = 0.35;     // Minimum score for active zone selection
input double InpSDMinSpaceBetweenPairATR   = 1.20;     // Active Supply/Demand must have enough room between them
input double InpSDProximityWeight          = 1.00;     // Prefer nearby valid zones
input double InpSDFreshnessWeight          = 1.50;     // Prefer fresh zones
input double InpSDStrengthWeight           = 1.25;     // Prefer strong departure zones
input double InpSDPatternWeight            = 0.75;     // Prefer RBD/DBD/DBR/RBR classified zones
input bool   InpSDRequireSideCorrectPair   = true;     // Demand below/touching price, Supply above/touching price
input bool   InpSDUseStructurePermission   = true;     // Trade S/D with market structure
input bool   InpSDAllowCounterTrendIfBOS    = true;     // Counter-trend only if opposite zone was taken out
input int    InpSDMaxCandlesInsideZone     = 3;        // If price sits inside zone too long, avoid entry
input double InpSDMaxZonePenetrationPct     = 0.55;     // More than 55% deep = warning/fail without strong confirmation
input double InpSDDuplicateMergeATR         = 0.35;     // Merge zones too close together
input bool   InpSDPreferTrendContinuation   = true;     // Prefer DBD in bear trend, RBR in bull trend
input bool   InpSDAllowHistoricalActiveZone = true;    // Allow valid historical zones if selected as active

input group "=== S/D Entry Confirmation: Candles + Indicators ==="
input bool   InpSDUseCandlePatternConfirmation = true;   // Use candle patterns at S/D retest
input bool   InpSDUseIndicatorConfirmation     = true;   // Use EMA/ADX/Stochastic as confirmation
input int    InpSDMinCandlePatternScore        = 2;      // Minimum candle pattern score
input int    InpSDMinIndicatorScore            = 1;      // Minimum indicator confirmation score
input int    InpSDMinTotalConfirmationScore    = 3;      // Candle + indicator minimum total
input bool   InpSDAllowStrongPatternOverride   = true;   // Strong candle pattern can override weak indicators

input bool   InpSDUseDojiConfirmation          = true;   // Include doji rejection
input bool   InpSDUseHammerConfirmation        = true;   // Include hammer
input bool   InpSDUseInvertedHammerConfirmation = true;  // Include inverted hammer
input bool   InpSDUsePinbarConfirmation        = true;   // Include pin bar
input bool   InpSDUseEngulfingConfirmation     = true;   // Include engulfing
input bool   InpSDUseStrongCandleConfirmation  = true;   // Include strong body candle

input bool   InpSDUseEMAIndicatorConfirm       = true;   // EMA50/EMA200 trend confirmation
input bool   InpSDUseADXIndicatorConfirm       = true;   // ADX trend strength confirmation
input bool   InpSDUseStochIndicatorConfirm     = true;   // Stochastic helper confirmation, not trend hard blocker
input bool   InpSDUseOscillatorAsTrendHardFilter = false; // FALSE: do not let Stochastic block trend S/D entries
input bool   InpSDUseOscillatorForRangeReversal = true;   // TRUE: use Stochastic for range/reversal confirmation
input bool   InpSDUseOscillatorConfidenceBoost  = true;   // TRUE: Stochastic can add confirmation score
input double InpSDMinADXForTrendConfirm        = 18.0;   // Minimum ADX for trend confirmation
input double InpSDDojiMaxBodyPct               = 0.15;   // Doji body <= 15% of range
input double InpSDHammerMinWickToBody          = 2.00;   // Hammer wick >= 2x body
input double InpSDPinbarMinWickToBody          = 1.30;   // Pinbar wick >= 1.3x body

input bool   InpSDUseMorningStarConfirmation   = true;   // Morning Star at Demand
input bool   InpSDUseEveningStarConfirmation   = true;   // Evening Star at Supply
input double InpSDStarSmallBodyPct             = 0.35;   // Middle star candle body <= 35% range
input double InpSDStarCloseBeyondMidPct        = 0.50;   // Confirmation candle closes beyond 50% of first candle

// STEP 1: Pre-trade confidence and quality gates
input bool   InpSDUsePreTradeConfidenceGate      = false;
input double InpSDMinPreTradeConfidence          = 50.0;
input bool   InpSDBlockIndecisionEntries         = true;
input bool   InpSDRequireOppositeZoneOrStrongRR  = true;
input double InpSDMinRRWithoutOppositeZone       = 2.20;
input int    InpSDExtraConfirmWithoutOppZone     = 2;

input bool   InpSDCloseOppositeOnStrongSignal    = true;
input double InpSDOppositeSignalMinRR            = 3.00;
input double InpSDOppositeSignalMinRank          = 6.00;
input double InpSDOppositeSignalMinConfidence    = 82.0;

input bool   InpSDAllowTouchedZoneOverride       = true;
input double InpSDTouchedOverrideMinQuality      = 6.00;
input double InpSDTouchedOverrideMinRank         = 7.00;
input int    InpSDTouchedOverrideMaxTouches      = 2;

//+------------------------------------------------------------------+
//| D1 Zone Strength & Lookback Settings                             |
//| NOTE: ENUM_ZONE_STRENGTH_MODE defined in ZoneManager.mqh         |
//+------------------------------------------------------------------+
input group "=== D1 Zone Strength & Lookback ==="
input ENUM_ZONE_STRENGTH_MODE InpVisualZoneStrengthMode = ZONE_STRENGTH_STRONG_ONLY;  // Visual zone filter mode
input ENUM_ZONE_STRENGTH_MODE InpTradeZoneStrengthMode  = ZONE_STRENGTH_MODERATE_AND_STRONG;  // Trade zone filter mode

input double InpStrongZoneQuality   = 5.75;    // Strong zone quality threshold
input double InpModerateZoneQuality = 4.50;    // Moderate zone quality threshold
input bool   InpPreferStructuralZones = true;  // Prefer structural zones

// Horizontal zones only: 6 months to 1 year of D1 history
input int InpD1ZoneStartupLookbackBars = 260;   // ~1 trading year startup scan
input int InpD1ZoneRefreshLookbackBars = 130;   // ~6 trading months refresh scan
input int InpD1ZoneLifetimeBars        = 260;   // Keep D1 zones alive ~1 year

input group "=== Trend & Counter-Trend Strategy ==="
input bool   InpUseHorizontalTrendZones        = true;    // Use horizontal continuation zones in trend
input bool   InpKeepTrendZonesUntilRetestFail  = true;    // Keep trend zones until trendline break+retest
input bool   InpUseTrendCampaignAdds           = false;   // Allow add-on trend positions
input int    InpMaxTrendCampaignPositions      = 4;       // Max trend campaign positions
input bool   InpCloseTrendOnDoubleTopBottom    = true;    // Close trend on double top/bottom
input bool   InpCloseTrendOnRepeatedExhaustion = true;    // Close trend on repeated exhaustion rejection
input int    InpExhaustionRejectCount          = 2;       // Exhaustion rejection count threshold
input bool   InpEnableCounterTrend             = false;   // Enable counter-trend strategy
input bool   InpUseCounterTrend                = false;   // Use counter-trend strategy
input bool   InpCounterTrendNeedsExhaustion    = true;    // Counter-trend requires exhaustion confirmation
input double InpCounterTrendRR                 = 1.2;     // Counter-trend minimum RR
input bool   InpCounterTrendTrailingOnly       = true;    // Counter-trend uses trailing stop only
input bool   InpUseBreakoutRetest              = false;   // Use breakout retest strategy

input group "=== Range Strategy ==="
input bool   InpStrictSingleRangePair          = true;    // Strict single support/resistance pair in range
input bool   InpRangeNeedsDoublePattern        = true;    // Range requires double bottom/top
input bool   InpUseStochasticForRangeOnly      = true;    // Use Stochastic only in range mode
input bool   InpUseStochasticInRange           = true;    // Use Stochastic in range mode
input bool   InpUseStochasticInCounterTrend    = false;   // Stochastic off by default for counter-trend
input int    InpStochK                         = 14;       // Stochastic K period
input int    InpStochD                         = 3;        // Stochastic D period
input int    InpStochSlowing                   = 2;        // Stochastic slowing, 14/3/2 setup
input double InpStochOversold                  = 20.0;    // Stochastic oversold level
input double InpStochOverbought                = 80.0;    // Stochastic overbought level

input double InpTrendSL_ATR_Buffer             = 0.25;    // Trend SL ATR buffer
input double InpCounterTrendSL_ATR_Buffer      = 0.20;    // Counter-trend SL ATR buffer
input double InpRangeSL_ATR_Buffer             = 0.15;    // Range SL ATR buffer

input group "=== Dynamic Zone Stop Anchor ==="
input double TrendZoneBandATR                    = 0.35;   // Zone band width (ATR mult)
input double TrendZoneSLBufferATR                = 0.30;   // SL buffer beyond zone (ATR mult)
input int    TrendZoneWickLookback               = 6;      // Bars to check for wick extremes
input bool   UseWickExtremeBeyondZone            = true;   // Use wick extreme if beyond zone
input double TrendTrailMinProfitATR             = 1.0;   // Min ATR profit before trail starts
input double TrendBEMinProfitATR                = 1.5;   // Min ATR profit before breakeven snap
input double TrendBEProfitLockATR               = 0.3;   // ATR profit to lock at breakeven

input group "=== Multi-Timeframe ==="
input ENUM_TIMEFRAMES InpZoneTF                  = PERIOD_D1;   // Zone detection timeframe (D1 permission)
input ENUM_TIMEFRAMES InpEntryTF                 = PERIOD_CURRENT;   // Structure / regime / zone execution timeframe (uses ChartTimeframe)
input ENUM_TIMEFRAMES InpTrendTF                 = PERIOD_CURRENT;   // Trend EMA timeframe (uses ChartTimeframe)
input ENUM_TIMEFRAMES InpHTF                     = PERIOD_D1;   // Higher timeframe for bias (D1 context)
// Channel source is D1, but it is displayed on the H4 chart and used with H4 execution logic.
input int             InpTrendEMA                = 50;           // Main trend EMA (H4 EMA50 = pullback/trend reference)
input bool            InpBlockTradesInConsolidation = true;      // Block trades when H4 trend = FLAT
input double          InpDuplicateZoneTolerancePoints = 30;      // Skip new zone if existing within this distance

input group "=== H4 SR Zone Settings ==="
input int    InpSRSwingLookback       = 4;       // Swing lookback for H4 zone detection
input int    InpSRMaxZones            = 10;      // Max SR zones to maintain
input double InpSRMinZoneWidthPts     = 80;      // Min zone width (points)
input double InpSRTouchBufferPts      = 25;      // Zone touch buffer (points)
input double InpSRBreakBufferPts      = 20;      // Zone break buffer (points)
input int    InpSRScanBars            = 200;     // H4 bars to scan for zones
input double InpSRSLBufferPts         = 30;      // SL buffer beyond zone (points)
input bool   InpSROnePositionPerSymbol = true;   // Only one SR position per symbol

input group "=== Expert Settings ==="
input ulong  ExpertMagic           = 20260307; // Magic number

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
CTrade             g_trade;
SymbolProfile      g_profile;
IndicatorState     g_ind;
AIState            g_ai;
CMarketClassifier  g_classifier;
MARKET_REGIME g_regime = MARKET_UNKNOWN;

bool           g_initComplete = false;
int            g_cooldownRemain = 0;
datetime       g_lastHeartbeat = 0;

//+------------------------------------------------------------------+
//| 4-state market classifier                                        |
//| Primary : H4 swing structure (HH/HL = bull, LH/LL = bear)       |
//| Secondary: EMA50 + EMA200 alignment on H4                        |
//| Strength : ADX >= 20                                             |
//| Activity : ATR >= 40% of 5-bar average (dead market gate)        |
//| States   : UP, DOWN, RANGE, BREAKOUT, FLAT                       |
//+------------------------------------------------------------------+
enum TrendState
{
   TREND_DOWN     = -1,
   TREND_FLAT     =  0,
   TREND_UP       =  1,
   TREND_RANGE    =  2,
   TREND_BREAKOUT =  3,
   TREND_REVERSAL =  4
};

string TrendStateToString(TrendState s)
{
   switch(s)
   {
      case TREND_UP:       return "UP";
      case TREND_DOWN:     return "DOWN";
      case TREND_FLAT:     return "FLAT";
      case TREND_RANGE:    return "RANGE";
      case TREND_BREAKOUT: return "BREAKOUT";
      case TREND_REVERSAL: return "REVERSAL";
   }
   return "UNKNOWN";
}

TrendState TrendStateFromRegime(const MARKET_REGIME regime)
{
   switch(regime)
   {
      case MARKET_TREND_BULL:     return TREND_UP;
      case MARKET_TREND_BEAR:     return TREND_DOWN;
      case MARKET_RANGE:          return TREND_RANGE;
      case MARKET_CONSOLIDATION:  return TREND_FLAT;
      case MARKET_BREAKOUT_BULL:  return TREND_BREAKOUT;
      case MARKET_BREAKOUT_BEAR:  return TREND_BREAKOUT;
      case MARKET_REVERSAL_BULL:  return TREND_REVERSAL;
      case MARKET_REVERSAL_BEAR:  return TREND_REVERSAL;
      default:                    return TREND_FLAT;
   }
}

TrendState g_trendState = TREND_FLAT;

//+------------------------------------------------------------------+
//| Dirty/Transition Trend Context Helper                            |
//| Returns true if H4 context is too dirty/transition for trend     |
//+------------------------------------------------------------------+
bool IsMarketTooDirty()
{
   if(!g_structure.valid) return true;

   if(g_structure.rangeLikelyTransition) return true;

   if(g_structure.state == STRUCTURE_RANGE) return true;

   if(g_structure.channel.valid && !g_structure.channel.directionalValid)
      return true;

   if(g_structure.consecutiveHH == 0 && g_structure.consecutiveHL == 0 &&
      g_structure.consecutiveLH == 0 && g_structure.consecutiveLL == 0)
      return true;

   return false;
}

bool IsTrendExhausted()
{
   // Use consecutive swing counts as exhaustion indicator
   // If we have many consecutive HH/LL but no valid structure, trend may be exhausted
   if(g_structure.consecutiveHH >= 4 && g_structure.state != STRUCTURE_BULL_TREND) return true;
   if(g_structure.consecutiveLL >= 4 && g_structure.state != STRUCTURE_BEAR_TREND) return true;
   
   // If no valid swings for long time, trend may be exhausted
   if(g_structure.consecutiveHH == 0 && g_structure.consecutiveHL == 0 &&
      g_structure.consecutiveLH == 0 && g_structure.consecutiveLL == 0) return true;
      
   return false;
}

bool IsDirtyTrendContext(bool forBuy)
{
   if(!g_structure.valid)
      return true;

   bool rangeState        = (g_structure.state == STRUCTURE_RANGE);
   bool bullBiasState     = (g_structure.state == STRUCTURE_BIAS_BULL);
   bool bearBiasState     = (g_structure.state == STRUCTURE_BIAS_BEAR);
   bool fullBullTrend     = (g_structure.state == STRUCTURE_BULL_TREND);
   bool fullBearTrend     = (g_structure.state == STRUCTURE_BEAR_TREND);
   bool weakBiasState     = bullBiasState || bearBiasState;
   bool transition        = g_structure.rangeLikelyTransition;
   bool channelInvalidDir = (g_structure.channel.valid && !g_structure.channel.directionalValid);
   
   // Override: Allow trades when channel is strongly directional with moderate ADX
   double h4Adx = GetADX(g_ind, 1);
   bool strongDirectionalChannel = (g_structure.channel.valid && 
                                     g_structure.channel.directionalValid && 
                                     h4Adx >= 20.0);
   
   bool mixedRangeish     = (rangeState || (transition && !strongDirectionalChannel) || channelInvalidDir);

   if(forBuy)
   {
      // Relaxed: Allow bias states and don't require D1 alignment
      if(bearBiasState || fullBearTrend) return true;  // Only block if opposite direction
      if(mixedRangeish) return true;
      // Removed D1 bias requirement to allow H4 trades even when D1 disagrees
   }
   else
   {
      // Relaxed: Allow bias states and don't require D1 alignment
      if(bullBiasState || fullBullTrend) return true;  // Only block if opposite direction
      if(mixedRangeish) return true;
      // Removed D1 bias requirement to allow H4 trades even when D1 disagrees
   }

   return false;
}

//+------------------------------------------------------------------+
//| Trend Campaign State - defined in MarketStructure.mqh            |
//| g_campaign is the global instance                                |
//+------------------------------------------------------------------+
void InitTrendCampaign()
{
   g_campaign.active         = false;
   g_campaign.direction      = 0;
   g_campaign.positionCount  = 0;
   g_campaign.lastAddBar     = 0;
   g_campaign.lastAddPrice   = 0.0;
   g_campaign.lastZoneAnchor = 0.0;
   g_campaign.lastAddTime    = 0;
   g_campaign.trendEndVotes  = 0;
   g_campaign.barsBreakingZone = 0;
}

//+------------------------------------------------------------------+
//| Multi-TF new bar detection                                       |
//+------------------------------------------------------------------+
bool IsNewBarTF(string symbol, ENUM_TIMEFRAMES tf, datetime &storeVar)
{
   datetime t = iTime(symbol, tf, 0);
   if(t != storeVar)
   {
      storeVar = t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| STEP 4: Pre-trade confidence helper                               |
//+------------------------------------------------------------------+
double ComputePreTradeConfidence(const EntryDecision &d,
                                  const IndicatorState &ind,
                                  int regime)
{
   bool emaBias = false;

   double ema50  = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);

   if(ema50 > 0.0 && ema200 > 0.0)
   {
      if(d.isBuy)
         emaBias = (ema50 >= ema200);
      else
         emaBias = (ema50 <= ema200);
   }

   bool sdReason =
      (StringFind(d.reason, "Demand") >= 0 ||
       StringFind(d.reason, "Supply") >= 0 ||
       StringFind(d.reason, "ZONE_RETEST") >= 0 ||
       StringFind(d.reason, "RETEST") >= 0);

   double patternBonus = 0.0;

   if(regime == MARKET_TREND_BULL || regime == MARKET_TREND_BEAR)
      patternBonus = 10.0;
   else if(regime == MARKET_RANGE)
      patternBonus = 7.0;
   else
      patternBonus = 2.0;

   double conf = ComputeTradeConfidence(emaBias,
                                        false,
                                        sdReason,
                                        false,
                                        false,
                                        false,
                                        0.0,
                                        patternBonus);

   if(d.usedZoneTarget)
      conf += 7.0;

   if(d.projectedRR >= 3.0)
      conf += 5.0;

   if(d.projectedRR < 1.50)
      conf -= 12.0;

   if(d.rankScore >= 7.0)
      conf += 6.0;

   if(StringFind(d.reason, "TREND_RUNNER_HOLD") >= 0)
      conf += 4.0;

   return MathMax(0.0, MathMin(conf, 100.0));
}

//+------------------------------------------------------------------+
//| Diagnostic wrapper helpers                                        |
//+------------------------------------------------------------------+
bool IsRiskLocked() { return !IsRiskAllowed(); }

bool IsNewsBlockingNow(int highBefore, int highAfter, int medBefore, int medAfter)
{
   return IsNewsEntryBlocked(_Symbol, highBefore, highAfter, medBefore, medAfter);
}

bool IsMaintenanceBlockingNow(int maintBefore, int maintAfter)
{
   return IsSymbolInMaintenanceWindow(_Symbol, maintBefore, maintAfter);
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("========================================");
   Print("MY BOT ", EA_VERSION, " INITIALIZING");
   Print("Symbol: ", _Symbol, " | TF: ", EnumToString(Period()));
   Print("========================================");

   Print("INIT: Running on chart TF=", EnumToString(Period()), " | Zone+Sweep+EMA50+ADX entry system");

   // Set lot sizing mode to equity percentage (simple mode)
   g_equityPercentForLots    = EquityPercentForLots;
   Print("[LOT_SIZING] mode=EQUITY_PERCENT value=", DoubleToString(g_equityPercentForLots, 2), "%");

   g_minLotFallbackEnabled   = UseMinLotFallback;
   g_minLotFallbackMaxMult   = MinLotFallbackMaxRiskMult;
   g_minLotFallbackMaxEqPct  = MinLotFallbackMaxEquityPct;
   
   // Aggressive min-lot fallback (optional, default OFF)
   g_allowAggressiveMinLotFallback    = AllowAggressiveMinLotFallback;
   g_aggressiveMinLotFallbackMaxMult  = AggressiveMinLotFallbackMaxRiskMult;
   g_aggressiveMinLotFallbackMaxEqPct = AggressiveMinLotFallbackMaxEquityPct;

   // Initialize trend campaign global config from inputs
   g_enableTrendCampaign                = EnableTrendCampaign;
   g_trendTradesUseNoFixedTP            = TrendTradesUseNoFixedTP;
   g_allowTrendAddsAtDynamicZones       = AllowTrendAddsAtDynamicZones;
   g_maxTrendCampaignPositions          = MaxTrendCampaignPositions;
   g_minBarsBetweenTrendAdds            = MinBarsBetweenTrendAdds;
   g_minATRDistanceBetweenTrendAdds     = MinATRDistanceBetweenTrendAdds;
   g_requireExistingTrendPositionProfit = RequireExistingTrendPositionProfit;
   g_oneAddPerFreshDynamicZone          = OneAddPerFreshDynamicZone;
   g_trendEndADXFloor                   = TrendEndADXFloor;
   g_trendEndConfirmBars                = TrendEndConfirmBars;

   // STEP 2: Initialize trend runner config from inputs
   g_sdTrendRetestsAreRunners       = InpSDTrendRetestsAreRunners;
   g_trendRunnerNoBrokerTP          = InpTrendRunnerNoBrokerTP;
   g_trendRunnerUseVirtualTarget    = InpTrendRunnerUseVirtualTarget;
   g_trendRunnerTrailStartR         = InpTrendRunnerTrailStartR;
   g_trendRunnerBEAtR               = InpTrendRunnerBEAtR;
   g_trendRunnerCloseOnlyOnTrendEnd = InpTrendRunnerCloseOnlyOnTrendEnd;

   Print("[TREND_RUNNER_CONFIG] sdRetestsAreRunners=", g_sdTrendRetestsAreRunners,
         " noBrokerTP=", g_trendRunnerNoBrokerTP,
         " trailStartR=", DoubleToString(g_trendRunnerTrailStartR, 2),
         " beAtR=", DoubleToString(g_trendRunnerBEAtR, 2),
         " closeOnlyOnTrendEnd=", g_trendRunnerCloseOnlyOnTrendEnd);

   // Initialize dynamic zone stop anchor config from inputs
   g_trendZoneBandATR                   = TrendZoneBandATR;
   g_trendZoneSLBufferATR               = TrendZoneSLBufferATR;
   g_trendZoneWickLookback              = TrendZoneWickLookback;
   g_useWickExtremeBeyondZone           = UseWickExtremeBeyondZone;
   g_trendTrailMinProfitATR             = TrendTrailMinProfitATR;
   g_trendBEMinProfitATR                = TrendBEMinProfitATR;
   g_trendBEProfitLockATR               = TrendBEProfitLockATR;

   Print("[TREND_CAMPAIGN_CONFIG] enabled=", g_enableTrendCampaign,
         " noFixedTP=", g_trendTradesUseNoFixedTP,
         " maxPositions=", g_maxTrendCampaignPositions,
         " zoneBandATR=", g_trendZoneBandATR);

   // Load symbol profile
   if(!LoadSymbolProfile(g_profile))
   {
      Print("INIT ERROR: Failed to load symbol profile");
      return INIT_FAILED;
   }

   Print("PROFILE: class=", EnumToString(g_profile.classEnum),
         " digits=", g_profile.digits,
         " point=", DoubleToString(g_profile.point, g_profile.digits),
         " minTrendGap=", g_profile.defaultMinTrendGapPoints, "pts",
         " is24x7=", g_profile.is24x7);

   // Set all indicator timeframes before creating handles
   ENUM_TIMEFRAMES activeTF = Period();  // Auto-detect from chart timeframe
   g_zoneTF      = InpZoneTF;    // Zone detection timeframe (from input)
   g_indicatorTF = activeTF;     // Execution/entry timeframe (uses chart TF)
   g_htfBiasTF   = InpHTF;       // HTF bias timeframe (from input)
   SetIndicatorTimeframe(activeTF);

   // Initialize indicators (ATR periods, ADX) - creates handles for both execution and HTF bias TFs
   if(!InitIndicators(ATRPeriod, ATRPeriod, SweepADX_Period, ATRReferencePeriod))
   {
      Print("INIT ERROR: Failed to initialize indicators");
      return INIT_FAILED;
   }

   Print("[TF_CONFIG] execution_tf=", EnumToString(g_indicatorTF),
         " bias_tf=", EnumToString(g_htfBiasTF),
         " zone_tf=", EnumToString(g_zoneTF));

   // Initialize risk state
   if(!LoadRiskState())
      InitRiskState();

   Print("RISK: dailyPnL=$", DoubleToString(g_risk.dailyPnL, 2),
         " consecLosses=", g_risk.consecutiveLosses,
         " locked=", (g_risk.lockReason != "" ? g_risk.lockReason : "none"));

   // Initialize trade executor
   g_trade.SetExpertMagicNumber(ExpertMagic);
   g_trade.SetDeviationInPoints(30);
   ValidateOrderFillingMode(g_trade, g_profile);
   InitTradeLog();

   // Initialize AI layer
   LoadModel(g_ai, EnableAI, AIModelPath);
   if(g_ai.enabled)
   {
      InitAIOutcomeLog();
      Print("AI: enabled=", g_ai.enabled,
            " modelLoaded=", g_ai.modelLoaded,
            " usingFallback=", g_ai.usingRuleFallback);
   }

   // Initialize zone manager (use H4 for zone detection)
   InitZoneManager();
   ResetVisualD1Cache();
   SetZoneSwingLookback(InpSRSwingLookback);
   SetZoneTimeframe(InpZoneTF);

   // SR zone settings DISABLED - SupportResistanceZones.mqh not used
   // g_srZoneTF          = InpZoneTF;
   // g_srSwingLookback   = InpSRSwingLookback;
   // g_srMaxZones        = InpSRMaxZones;
   // g_srMinZoneWidthPts = InpSRMinZoneWidthPts;
   // g_srTouchBufferPts  = InpSRTouchBufferPts;
   // g_srBreakBufferPts  = InpSRBreakBufferPts;
   // g_srScanBars        = InpSRScanBars;
   Print("[SIMPLIFIED_LIVE] SR zones disabled, using ZoneManager only");

   // Initialize zone scoring bank
   InitZoneScoreBank();

   // Initialize trade manager (cross state, exit filters)
   InitTradeManager();


   // Configure market classifier — prefer profile thresholds, fallback to inputs
   if(UseMarketClassifier)
   {
      double cfTrend   = (g_profile.regimeTrendATRMult  > 0) ? g_profile.regimeTrendATRMult  : ClassTrendATRMult;
      double cfConsol  = (g_profile.regimeConsolidRatio  > 0) ? g_profile.regimeConsolidRatio  : ClassConsolidATRRatio;
      double cfRange   = (g_profile.regimeRangeATRMult   > 0) ? g_profile.regimeRangeATRMult   : ClassRangeATRMult;
      g_classifier.Configure(cfTrend, cfConsol, cfRange,
                             ClassUseSlopeFilter, ClassSlopeLookback);
      Print("CLASSIFIER: trend=", cfTrend, " consol=", cfConsol,
            " range=", cfRange, " slope=", ClassUseSlopeFilter,
            " lookback=", ClassSlopeLookback, " (from profile)");
   }

   // Initialize news and maintenance filters
   InitNewsCalendar();
   InitMaintenanceSchedule();

   if(UseNewsFilter)
   {
      LoadTodaysNewsFromCalendar();
      Print("NEWS FILTER: enabled | HIGH block=", HighNewsBlockBefore, "/", HighNewsBlockAfter,
            "min | close=", HighNewsCloseBefore, "min | MED block=", MedNewsBlockBefore, "/", MedNewsBlockAfter, "min");
   }

   if(UseMaintFilter)
   {
      EnsureDerivWeeklyMaintenanceLoaded();
      Print("MAINT FILTER: enabled | block=", MaintBlockBefore, "/", MaintBlockAfter,
            "min | close=", MaintCloseBefore, "min before");
   }

   // Initialize lightweight setup memory (AIScaffold)
   LoadSetupMemory();

   // Initialize AI learning system (AIMemory - richer pattern tracking)
   if(UseAILearning)
      InitAIMemory(AILearnMode, AIMemoryReset, AIMemoryTag);

   // Initialize confidence tracker
   InitConfidenceTracker();

   // Initialize trend campaign state
   InitTrendCampaign();

   // HYBRID MODEL:
   // trend = dynamic/channel + break-retest continuation
   // range = horizontal zones only
   if(UseMarketStructure)
   {
      InitMarketStructure();
      InitBreakoutTracker();

      if(UseReversalDetector)
         InitReversalState();
   }

   Print("[HYBRID_MODEL] MarketStructure ENABLED");
   Print("[HYBRID_MODEL] trend=horizontal_zone_wick_retest channel=context_only range=horizontal_only");
   Print("[MARKET_STRUCTURE] live integration enabled");
   Print("[DYNAMIC_CHANNEL] drawing enabled context_only=true");

   // Initial market state
   if(!RefreshMarketState(g_market, g_profile, MaxSpreadMultiplier))
      Print("INIT WARNING: Could not refresh market state");
   else
      LogMarketState(g_market, g_profile);

   g_initComplete = true;
   g_lastHeartbeat = TimeCurrent();

   Print("========================================");
   Print("MY BOT ", EA_VERSION, " READY (Hybrid Trend/Range Zone Model)");
   Print("========================================");
   Print("[TREND_EXIT_STACK] structure_only=true generic_trailing=false generic_be=false partials=false htf_reversal_blocker=false");
   Print("[LIVE_MODEL] trend=horizontal_zone_wick_retest channel=context_only range=horizontal_only h4_injection=false forced_rescan=false");

   // Channel code removed
   Print("[CHANNEL_REGISTRY] disabled - channel code removed");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ClearZoneLines();
   // Channel code removed
   ReleaseIndicators();
   ReleaseModel(g_ai);
   SaveRiskState();
   // Save lightweight setup memory (AIScaffold)
   SaveSetupMemory();
   // Shutdown AI learning system (AIMemory - richer pattern tracking)
   if(UseAILearning)
      ShutdownAIMemory();
   ShutdownConfidenceTracker();
   Print("MY BOT ", EA_VERSION, " SHUTDOWN. Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Check if within trading hours                                    |
//+------------------------------------------------------------------+
bool IsWithinTradingHours()
{
   // Synthetic indices trade 24/7 — time filter never blocks
   if(g_profile.is24x7)
      return true;

   if(TradingStartHour < 0 || TradingEndHour < 0)
      return true;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;

   if(TradingStartHour <= TradingEndHour)
      return (hour >= TradingStartHour && hour < TradingEndHour);
   else
      return (hour >= TradingStartHour || hour < TradingEndHour);
}

//+------------------------------------------------------------------+
//| Heartbeat logging every 5 minutes                                |
//+------------------------------------------------------------------+
void CheckHeartbeat()
{
   datetime now = TimeCurrent();
   if(now - g_lastHeartbeat >= 300)
   {
      g_lastHeartbeat = now;
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("HEARTBEAT: equity=$", DoubleToString(equity, 2),
            " dailyPnL=$", DoubleToString(g_risk.dailyPnL, 2),
            " dd=", DoubleToString(g_risk.currentDrawdownPct, 2), "%",
            " positions=", CountAllPositionsByMagic(ExpertMagic));
   }
}

//+------------------------------------------------------------------+
//| Bar-by-bar signal audit logging                                  |
//+------------------------------------------------------------------+
void LogSignalAudit(const string &buyReject, const string &sellReject)
{
   double close1  = g_ind.closeArr[1];
   double ema50_1 = GetEMA50(g_ind, 1);
   double atrVal  = GetATR(g_ind, 1);

   Print("AUDIT: close=", DoubleToString(close1, g_profile.digits),
         " EMA50=", DoubleToString(ema50_1, g_profile.digits),
         " spread=", DoubleToString(g_market.spreadPoints, 1), "pts",
         " ATR=", DoubleToString(atrVal, g_profile.digits));

   Print("AUDIT: Trend=", TrendStateToString(g_trendState),
         " ADX=", DoubleToString(GetADX(g_ind, 1), 2),
         " EMA50=", DoubleToString(GetEMA50(g_ind, 1), g_profile.digits),
         " ATR=", DoubleToString(GetATR(g_ind, 1), g_profile.digits));

   // Zone proximity info
   double zoneDist = 0;
   ENUM_ZONE_TYPE zoneType = ZONE_SUPPORT_MINOR;
   bool nearZone = IsNearAnyZone(close1, g_profile, zoneDist, zoneType);
   Print("AUDIT: NearZone=", nearZone,
         (nearZone ? " type=" + ZoneTypeToString(zoneType) +
                     " dist=" + DoubleToString(zoneDist / g_profile.point, 0) + "pts"
                   : ""),
         " | MajorZone=", IsNearMajorZone(close1, g_profile));

   Print("SIGNAL: BUY reject=", (buyReject == "" ? "PASS" : buyReject),
         " | SELL reject=", (sellReject == "" ? "PASS" : sellReject));
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initComplete) return;

   // === EVERY TICK: Risk monitoring + Trailing + Heartbeat ===
   CheckDailyRiskReset();
   UpdateRiskMetrics(MaxDailyLossPercent, MaxDrawdownPercent);

   // Structure-based trailing: Stage 2 = BE at +1R, Stage 3 = swing trail / EMA50 trail
   if(HasOpenPositionForSymbol(ExpertMagic))
   {
      ManageStructureTrail(g_trade, g_profile, g_ind, ExpertMagic,
                           UseBreakeven,      BreakevenAtR,
                           TrailSwingLookback, TrailSwingBuffATR,
                           UseEMA50Trail,      EMA50TrailBuffATR,
                           EntryADXTrend,      TrendSlopeLookback);
      
      // Dynamic zone anchor trailing for trend campaign positions
      if(EnableTrendCampaign && g_campaign.active)
      {
         ManageDynamicZoneTrail(g_trade, g_profile, g_ind, ExpertMagic,
                                TrendZoneBandATR, TrendZoneSLBufferATR,
                                TrendZoneWickLookback, UseWickExtremeBeyondZone);
      }
   }

   // MFE/MAE tracking for AI outcome log
   if(g_pendingTrade.active)
   {
      MqlTick tick;
      if(SymbolInfoTick(_Symbol, tick) && tick.bid > 0)
      {
         g_market.bid = tick.bid;
         g_market.ask = tick.ask;
         g_market.tickFresh = true;
         UpdateMFEMAE(g_market);
      }
   }

   // Heartbeat every 5 minutes
   CheckHeartbeat();

   // === EVERY TICK: Force-close before high-impact news or maintenance ===
   if(HasOpenPositionForSymbol(ExpertMagic))
   {
      // Maintenance force-close (synthetics only)
      if(UseMaintFilter && g_profile.classEnum == INST_SYNTH_VOL
         && IsSymbolInMaintenanceCloseWindow(_Symbol, MaintCloseBefore))
      {
         Print("FORCE CLOSE: Maintenance approaching for ", _Symbol,
               " — ", GetMaintenanceBlockReason(_Symbol, MaintBlockBefore, MaintBlockAfter));
         CloseAllPositionsForSymbol(g_trade, ExpertMagic);
      }

      // News force-close (forex only)
      if(UseNewsFilter && g_profile.classEnum == INST_FOREX_MAJOR)
      {
         if(IsHighImpactNewsCloseWindow(_Symbol, HighNewsCloseBefore))
         {
            Print("FORCE CLOSE: High-impact news approaching for ", _Symbol,
                  " — ", GetNewsBlockReason(_Symbol, HighNewsBlockBefore, HighNewsBlockAfter,
                                            MedNewsBlockBefore, MedNewsBlockAfter));
            CloseAllPositionsForSymbol(g_trade, ExpertMagic);
         }
      }
      
      // Trend positions are managed only by ManageStructureTrail().
      // Generic trailing, generic breakeven, and partial profits are disabled here.
      // ManageStructureTrail handles: swing-based trailing, EMA50 trail, and breakeven.
   }

   // === NEW BAR ONLY: Indicator copy + signal evaluation ===
   if(!IsNewBar()) return;

   // Reload news calendar once per day (after midnight)
   if(UseNewsFilter)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime todayStart = StructToTime(dt);
      if(g_news.lastLoad < todayStart)
      {
         PurgeOldNewsEvents();
         LoadTodaysNewsFromCalendar();
      }
   }

   // Purge expired maintenance windows
   if(UseMaintFilter)
      EnsureDerivWeeklyMaintenanceLoaded();

   if(!RefreshMarketState(g_market, g_profile, MaxSpreadMultiplier))
   {
      Print("TICK: Market state refresh failed");
      return;
   }

   if(!CopyLatestIndicatorValues(g_ind))
   {
      Print("TICK: Indicator copy failed");
      return;
   }

   // Copy D1 HTF bias indicators (refresh on new D1 bar or if not yet valid)
   if(IsNewD1Bar() || !g_d1Ind.valid)
   {
      CopyD1IndicatorValues();
      // PATCH 4: Reset visual D1 cache on new D1 bar to refresh zone lines
      ResetVisualD1Cache();
   }

   // Log D1 HTF bias state
   ENUM_D1_BIAS d1Bias = GetD1Bias();
   double d1SepATR = (g_d1Ind.atr[1] > 0) ? MathAbs(g_d1Ind.ema50[1] - g_d1Ind.ema200[1]) / g_d1Ind.atr[1] : 0;
   Print("[HTF_BIAS] tf=D1 state=", D1BiasToString(d1Bias),
         " ema50=", DoubleToString(g_d1Ind.ema50[1], g_profile.digits),
         " ema200=", DoubleToString(g_d1Ind.ema200[1], g_profile.digits),
         " adx=", DoubleToString(g_d1Ind.adx[1], 2),
         " emaSepATR=", DoubleToString(d1SepATR, 2));

   // EMA LOGGING: H4 EMA50 (trend reference) + EMA200 (broad filter only)
   Print("[LOCAL_REGIME] tf=H4 ema50=", DoubleToString(GetEMA50(g_ind, 1), g_profile.digits),
         " ema200=", DoubleToString(GetEMA200(g_ind, 1), g_profile.digits),
         " adx=", DoubleToString(GetADX(g_ind, 1), 2),
         " bullBias200=", IsBullBiasByEMA200(g_ind),
         " bearBias200=", IsBearBiasByEMA200(g_ind));

   // Hybrid model structure update:
   // trend uses dynamic/channel + break-retest continuation
   // range uses horizontal zones only
   if(UseMarketStructure)
   {
      double atrStruct = GetATR(g_ind, 1);
      if(atrStruct > 0.0)
      {
         UpdateMarketStructure(g_ind, atrStruct, StructureSwingLookback);
         UpdateBreakoutTracker(g_ind, atrStruct);

         if(UseReversalDetector)
         {
            double nearestSupport = FindNearestMajorSupportLevel(g_ind.closeArr[1], atrStruct);
            double nearestResist  = FindNearestMajorResistanceLevel(g_ind.closeArr[1], atrStruct);
            UpdateReversalState(g_ind, atrStruct, nearestSupport, nearestResist);
         }

         Print("[STRUCTURE_UPDATE] state=", StructureStateToString(g_structure.state));
      }
   }

   // Refresh zone detection on each new bar (with merge/filter)
   // Zone merge distance: ATR * profile multiplier, converted to points
   double atrMerge = GetATR(g_ind, 1);
   int effectiveMergePoints = (atrMerge > 0 && g_profile.zoneMergeATRMult > 0)
                              ? (int)(atrMerge * g_profile.zoneMergeATRMult / g_profile.point)
                              : ZoneMergePoints;
   // Keep horizontal zone map stable in hybrid model
   // Do not force full rescan when price drifts away
   RefreshZones(g_ind, g_profile, effectiveMergePoints);

   // No H1 horizontal zone injection in hybrid model
   TagZoneRejections(g_ind.openArr, g_ind.highArr, g_ind.lowArr, g_ind.closeArr,
                     60, atrMerge);
   TagBreakoutOrigins(g_ind.openArr, g_ind.closeArr, 60, atrMerge);
   if(atrMerge > 0)
      ResetTradedZonesIfPriceLeft(g_ind.closeArr[1], atrMerge);

   // Consolidate overlapping same-side zones before entry evaluation
   if(EnableZoneMerge)
   {
      int effectiveMaxMergedWidthPts = MaxMergedZoneWidthPoints;
      if(atrMerge > 0.0 && MaxMergedZoneWidthATR > 0.0)
      {
         int atrWidthPts = (int)MathRound((atrMerge * MaxMergedZoneWidthATR) / g_profile.point);
         if(atrWidthPts > effectiveMaxMergedWidthPts)
            effectiveMaxMergedWidthPts = atrWidthPts;
      }

      ConsolidateOverlappingZones(g_profile, MergeDistancePoints, MinOverlapPercent,
                                  effectiveMaxMergedWidthPts,
                                  AllowBullishFamilyMerge, AllowBearishFamilyMerge);
   }

   // Detect break+retest opportunities on broken zones (upgraded: role-based, stateful)
   DetectBreakRetestZones(g_ind.closeArr, g_ind.highArr, g_ind.lowArr, 60, atrMerge);

   // PATCH 7: Reduce dense same-family zone stacks before entry evaluation
   if(atrMerge > 0.0)
      ReduceDenseRangeZoneStacks(atrMerge);

   // Reversal detector DISABLED for simplified live model
   // if(UseReversalDetector)
   //    UpdateZoneReversalSignals(g_ind.openArr, g_ind.highArr, g_ind.lowArr, g_ind.closeArr, 60, atrMerge);
   // if(UseReversalDetector)
   // {
   //    RefreshSRZones(_Symbol);
   //    UpdateBrokenSRZones(_Symbol);
   //    UpdateSRReversalState(_Symbol);
   // }

   // HTF reversal blocker DISABLED - advisory only
   // Print("[REVERSAL_STATE] htfBearish=", HasMajorBearishReversalSRSignal(_Symbol),
   //       " htfBullish=", HasMajorBullishReversalSRSignal(_Symbol));

   DrawZoneLines(g_profile);
   
   // D1 master trendline - DISABLED (channels only)
   // if(UseMarketStructure && InpUseD1MasterTrendline)
   // {
   //    BuildD1MasterTrendline();
   //    if(InpShowD1MasterLineOnChart)
   //       DrawD1MasterTrendlineVisual();
   //    DrawD1TrendMapVisuals();
   //    ChartRedraw(0);
   // }

   // Channel code removed per user request

   if(UseZoneScoring)
      RefreshZoneScoreBank(g_ind.closeArr[1], g_profile, GetATR(g_ind, 1),
                           MaxZoneRetests, g_zoneLifetimeBars, ZoneConfluenceATRMult);

   // Run AI inference if enabled
   if(g_ai.enabled)
      RunModelInference(g_ai, g_ind, g_market, g_profile, TrendSlopeLookback);

   // Channel position tracker DISABLED for simplified live model
   // g_channelPosManager.UpdatePositions();
   // if(g_channelPosManager.GetActiveCount() > 0) { ... }

   // Manage existing positions on every new bar (closed-candle exits)
   if(HasOpenPositionForSymbol(ExpertMagic))
   {
      ManageOpenPosition(g_trade, g_ind, g_market, g_profile, ExpertMagic,
                         CloseOnOppositeCross, ExitOnCloseBeyondEMA50,
                         UseEMA50ProfitProtection);
   }

   // === ENTRY EVALUATION ===
   Print("STATE CHECK: canTradeNow=", g_market.canTradeNow,
         " sessionOpen=", g_market.sessionOpen,
         " tradeAllowed=", g_market.tradeAllowed,
         " tickFresh=", g_market.tickFresh,
         " spreadPts=", DoubleToString(g_market.spreadPoints, 1));

   // Gate: maintenance block (synthetics only)
   if(UseMaintFilter && g_profile.classEnum == INST_SYNTH_VOL
      && IsSymbolInMaintenanceWindow(_Symbol, MaintBlockBefore, MaintBlockAfter))
   {
      Print("ENTRY BLOCKED: ", GetMaintenanceBlockReason(_Symbol, MaintBlockBefore, MaintBlockAfter));
      return;
   }

   // Gate: news block (forex only)
   if(UseNewsFilter && g_profile.classEnum == INST_FOREX_MAJOR)
   {
      if(IsNewsEntryBlocked(_Symbol, HighNewsBlockBefore, HighNewsBlockAfter,
                            MedNewsBlockBefore, MedNewsBlockAfter))
      {
         Print("ENTRY BLOCKED: ", GetNewsBlockReason(_Symbol, HighNewsBlockBefore, HighNewsBlockAfter,
                                                      MedNewsBlockBefore, MedNewsBlockAfter));
         return;
      }
   }

   Print("FILTER CHECK: riskLocked=", IsRiskLocked(),
         " newsBlocked=", IsNewsBlockingNow(HighNewsBlockBefore, HighNewsBlockAfter, MedNewsBlockBefore, MedNewsBlockAfter),
         " maintBlocked=", IsMaintenanceBlockingNow(MaintBlockBefore, MaintBlockAfter));

   if(!IsSpreadAcceptable(g_market, g_profile, MaxSpreadMultiplier))
   {
      Print("[ENTRY_BLOCKED] reason=SPREAD_TOO_HIGH_PRECHECK spreadPts=",
            DoubleToString(g_market.spreadPoints, 1));
      return;
   }

   // Gate: execution allowed?
   if(!g_market.canTradeNow)
   {
      Print("ENTRY BLOCKED: canTradeNow=false (session=", g_market.sessionOpen,
            " trade=", g_market.tradeAllowed, " tickFresh=", g_market.tickFresh, ")");
      return;
   }

   // Gate: risk allowed?
   if(!IsRiskAllowed())
   {
      Print("ENTRY BLOCKED: Risk lock active: ", g_risk.lockReason);
      return;
   }

   // Gate: position limits (stacking bypasses OnePositionPerSymbol)
   if(OnePositionPerSymbol && !EnableStacking && HasOpenPositionForSymbol(ExpertMagic)) return;
   if(MaxOpenPositionsTotal > 0 && CountAllPositionsByMagic(ExpertMagic) >= MaxOpenPositionsTotal) return;

   // Gate: time-of-day filter
   if(!IsWithinTradingHours()) return;

   // Gate: cooldown after loss
   if(g_cooldownRemain > 0)
   {
      g_cooldownRemain--;
      return;
   }

   // Determine AI active state (only if real model loaded, not fallback)
   bool aiActive = (g_ai.enabled && g_ai.modelLoaded && !g_ai.usingRuleFallback);

   double atrNow = GetATR(g_ind, 1);
   if(atrNow <= 0.0) return;

   // ============================================================
   // STRUCTURE-FIRST REGIME SELECTION
   // Priority: 1) Price Structure, 2) Channel, 3) EMA, 4) ADX
   // ============================================================
   MARKET_REGIME entryRegime = REGIME_NONE;
   string regimeSource = "";
   bool structureWasValid = (UseMarketStructure && g_structure.valid);

   if(structureWasValid)
   {
      // Map structure state to regime - structure is PRIMARY
      double h4Ema50  = GetEMA50(g_ind, 1);
      double h4Ema200 = GetEMA200(g_ind, 1);
      double h4Adx    = GetADX(g_ind, 1);
      switch(g_structure.state)
      {
         case STRUCTURE_BULL_TREND:
            entryRegime = REGIME_TREND_BULL;
            regimeSource = "structure_bull_trend";
            break;
         case STRUCTURE_BEAR_TREND:
            entryRegime = REGIME_TREND_BEAR;
            regimeSource = "structure_bear_trend";
            break;
         case STRUCTURE_BIAS_BULL:
         {
            int biasBars = g_structure.barsInCurrentState;

            bool hasSwingPair      = (g_structure.consecutiveHH >= 1 && g_structure.consecutiveHL >= 1);
            bool hasDirectionalCh  = false; // Channel code removed
            bool emaBullAligned    = (h4Ema50 > h4Ema200);
            bool adxHealthy        = (h4Adx >= MathMax(EntryADXTrend - 3.0, 18.0));
            bool d1BullAligned     = (d1Bias == D1_BIAS_BULL);
            bool dirtyTransition   = g_structure.rangeLikelyTransition;

            bool d1NotConflicting = (d1Bias != D1_BIAS_BEAR);
            bool enoughEvidence = false;
            if((hasSwingPair && emaBullAligned && d1NotConflicting && biasBars >= 2) ||
               (hasSwingPair && hasDirectionalCh && emaBullAligned && biasBars >= 2) ||
               (hasDirectionalCh && emaBullAligned && adxHealthy && d1NotConflicting && biasBars >= 3))
            {
               enoughEvidence = true;
            }

            bool nearDynamicSupport = false;
            if(g_structure.dynamicSupport > 0.0)
            {
               nearDynamicSupport = (MathAbs(g_ind.closeArr[1] - g_structure.dynamicSupport) <= atrNow * 0.80);
            }

            if((dirtyTransition || g_structure.recentChannelBroken) && g_structure.rangeQuality >= 6.5)
            {
               entryRegime  = REGIME_CONSOLIDATION;
               regimeSource = "bias_bull_high_range_quality";
            }
            else if(enoughEvidence)
            {
               entryRegime  = REGIME_TREND_BULL;
               regimeSource = "bias_bull_promoted_relaxed";
            }
            else if(hasSwingPair && emaBullAligned && biasBars >= 2)
            {
               entryRegime  = REGIME_TREND_BULL;
               regimeSource = "bias_bull_soft_promoted";
            }
            else if(dirtyTransition && !hasSwingPair)
            {
               entryRegime  = REGIME_CONSOLIDATION;
               regimeSource = "bias_bull_consolidation";
            }
            else if(nearDynamicSupport && emaBullAligned)
            {
               entryRegime  = REGIME_TREND_BULL;
               regimeSource = "bias_bull_near_dynamic_support";
            }
            else
            {
               entryRegime  = REGIME_NONE;
               regimeSource = "bias_bull_needs_validation";
            }

            Print("[BIAS_PROMOTION] state=BIAS_BULL strict=false biasBars=", biasBars,
                  " swingPair=", hasSwingPair,
                  " dirCh=", hasDirectionalCh,
                  " ema=", emaBullAligned,
                  " adx=", adxHealthy,
                  " d1Aligned=", d1BullAligned,
                  " d1NoConflict=", d1NotConflicting,
                  " dirty=", dirtyTransition,
                  " regime=", EnumToString(entryRegime));
            break;
         }

         case STRUCTURE_BIAS_BEAR:
         {
            int biasBars = g_structure.barsInCurrentState;

            bool hasSwingPair      = (g_structure.consecutiveLH >= 1 && g_structure.consecutiveLL >= 1);
            bool hasDirectionalCh  = false; // Channel code removed
            bool emaBearAligned    = (h4Ema50 < h4Ema200);
            bool adxHealthy        = (h4Adx >= MathMax(EntryADXTrend - 3.0, 18.0));
            bool d1BearAligned     = (d1Bias == D1_BIAS_BEAR);
            bool dirtyTransition   = g_structure.rangeLikelyTransition;

            bool d1NotConflicting = (d1Bias != D1_BIAS_BULL);
            bool enoughEvidence = false;
            if((hasSwingPair && emaBearAligned && d1NotConflicting && biasBars >= 2) ||
               (hasSwingPair && hasDirectionalCh && emaBearAligned && biasBars >= 2) ||
               (hasDirectionalCh && emaBearAligned && adxHealthy && d1NotConflicting && biasBars >= 3))
            {
               enoughEvidence = true;
            }

            bool nearDynamicResistance = false;
            if(g_structure.dynamicResistance > 0.0)
            {
               nearDynamicResistance = (MathAbs(g_ind.closeArr[1] - g_structure.dynamicResistance) <= atrNow * 0.80);
            }

            if((dirtyTransition || g_structure.recentChannelBroken) && g_structure.rangeQuality >= 6.5)
            {
               entryRegime  = REGIME_CONSOLIDATION;
               regimeSource = "bias_bear_high_range_quality";
            }
            else if(enoughEvidence)
            {
               entryRegime  = REGIME_TREND_BEAR;
               regimeSource = "bias_bear_promoted_relaxed";
            }
            else if(hasSwingPair && emaBearAligned && biasBars >= 2)
            {
               entryRegime  = REGIME_TREND_BEAR;
               regimeSource = "bias_bear_soft_promoted";
            }
            else if(dirtyTransition && !hasSwingPair)
            {
               entryRegime  = REGIME_CONSOLIDATION;
               regimeSource = "bias_bear_consolidation";
            }
            else if(nearDynamicResistance && emaBearAligned)
            {
               entryRegime  = REGIME_TREND_BEAR;
               regimeSource = "bias_bear_near_dynamic_resistance";
            }
            else
            {
               entryRegime  = REGIME_NONE;
               regimeSource = "bias_bear_needs_validation";
            }

            Print("[BIAS_PROMOTION] state=BIAS_BEAR strict=false biasBars=", biasBars,
                  " swingPair=", hasSwingPair,
                  " dirCh=", hasDirectionalCh,
                  " ema=", emaBearAligned,
                  " adx=", adxHealthy,
                  " d1Aligned=", d1BearAligned,
                  " d1NoConflict=", d1NotConflicting,
                  " dirty=", dirtyTransition,
                  " regime=", EnumToString(entryRegime));
            break;
         }
         case STRUCTURE_RANGE:
            // When D1 has a strong directional bias, H4 STRUCTURE_RANGE is likely just
            // a pullback/consolidation within the D1 trend. Don't trade it as range
            // (mean-reversion) because the D1 trend will resume and stop out range trades.
            if(d1Bias == D1_BIAS_BULL || d1Bias == D1_BIAS_BEAR)
            {
               entryRegime = REGIME_CONSOLIDATION;
               regimeSource = "structure_range_d1_override";
               Print("[RANGE_D1_OVERRIDE] H4=RANGE but D1=", D1BiasToString(d1Bias),
                     " -> CONSOLIDATION (avoid range trades against D1 trend)");
            }
            else
            {
               entryRegime = REGIME_RANGE;
               regimeSource = "structure_range";
            }
            break;
         default:
            entryRegime = REGIME_NONE;
            regimeSource = "structure_unknown";
            break;
      }
      
      Print("[REGIME_FROM_STRUCTURE] structure=", StructureStateToString(g_structure.state),
            " regime=", EnumToString(entryRegime),
            " source=", regimeSource,
            " HH=", g_structure.consecutiveHH,
            " HL=", g_structure.consecutiveHL,
            " LH=", g_structure.consecutiveLH,
            " LL=", g_structure.consecutiveLL);
   }
   
   // FALLBACK: Use GetFallbackRegimeFromClassifier only when g_structure is not yet valid
   // Do NOT run fallback when structure WAS valid but returned BIAS/UNKNOWN — those are deliberate REGIME_NONE
   if(!structureWasValid && entryRegime == REGIME_NONE)
   {
      entryRegime  = GetFallbackRegimeFromClassifier(g_ind, true);
      regimeSource = "fallback_classifier";
      Print("[REGIME_FROM_STRUCTURE] structure=INVALID regime=", EnumToString(entryRegime),
            " source=fallback_classifier");
   }

   // Validate range regime — check horizontal map validity before allowing REGIME_RANGE
   // REGIME_CONSOLIDATION and REGIME_NONE may be promoted to REGIME_RANGE if map is valid
   if((entryRegime == REGIME_RANGE || entryRegime == REGIME_CONSOLIDATION || entryRegime == REGIME_NONE) && atrNow > 0.0)
   {
      RangeBoundarySelection rangeGate = BuildFinalHorizontalRangeMap(g_ind, g_ind.closeArr[1], atrNow);
      
      // Only promote to REGIME_RANGE if horizontal map is valid
      if(IsHorizontalRangeMapValid(rangeGate))
      {
         // Valid range map detected - promote to REGIME_RANGE
         if(entryRegime == REGIME_CONSOLIDATION || entryRegime == REGIME_NONE)
         {
            string prevRegime = (entryRegime == REGIME_CONSOLIDATION ? "CONSOLIDATION" : "NONE");
            entryRegime = REGIME_RANGE;
            regimeSource = "horizontal_range_map_validated";
            Print("[RANGE_PROMOTION] from=", prevRegime,
                  " to=REGIME_RANGE demandIdx=", rangeGate.bestDemand.zoneIdx,
                  " supplyIdx=", rangeGate.bestSupply.zoneIdx);
         }
      }
      else
      {
         // Patch 9: If classified regime was already REGIME_RANGE, keep it alive
         // so GenerateRangeBoundaryEntries can scan backup zones for a valid boundary trade.
         if(entryRegime == REGIME_RANGE)
         {
            Print("[RANGE_MAP_KEPT] reason=", rangeGate.reason,
                  " regime=REGIME_RANGE kept_for_boundary_wrapper");
         }
         else if(entryRegime == REGIME_CONSOLIDATION)
         {
            MARKET_REGIME fallbackTrend = GetFallbackRegimeFromClassifier(g_ind, true);
            
            if(fallbackTrend == REGIME_TREND_BULL || fallbackTrend == REGIME_TREND_BEAR)
            {
               entryRegime = fallbackTrend;
               regimeSource = "invalid_range_map_trend_fallback";
               Print("[RANGE_REGIME_FALLBACK] reason=", rangeGate.reason,
                     " fallback=", EnumToString(entryRegime));
            }
            else
            {
               entryRegime  = REGIME_NONE;
               regimeSource = "invalid_range_map_no_fallback";
               Print("[RANGE_REGIME_FALLBACK] reason=", rangeGate.reason, " regime=NONE");
            }
         }
      }
   }

   // ============================================================
   // REGIME PROMOTION LAYER
   // Priority: TREND (dynamic channel) > COUNTER-TREND > BREAKOUT > RANGE
   // ============================================================
   
   // D1 master trendline DISABLED - channels only
   // if(InpUseD1MasterTrendline)
   //    BuildD1MasterTrendline();

   // Assign zone strategy roles based on trend bias (no D1 trendline)
   if(InpUseHorizontalTrendZones || InpUseCounterTrend || InpUseBreakoutRetest)
   {
      int trendBias = 0;
      if(entryRegime == REGIME_TREND_BULL) trendBias = 1;
      else if(entryRegime == REGIME_TREND_BEAR) trendBias = -1;
      
      AssignZoneStrategyRoles(g_ind.closeArr[1], atrNow, trendBias, false);
   }

   // TREND LINE CODE REMOVED - All trend line code deleted per user request

   // Check for counter-trend exhaustion zones
   if(InpUseCounterTrend && (entryRegime == REGIME_TREND_BULL || entryRegime == REGIME_TREND_BEAR))
   {
      int trendBias = (entryRegime == REGIME_TREND_BULL) ? 1 : -1;
      bool hasExhaustion = HasRepeatedExhaustionRejections(trendBias, atrNow);
      
      if(hasExhaustion)
      {
         Print("[REGIME_PRIORITY] Counter-trend exhaustion detected for trend regime");
      }
   }

   bool bullBreakoutReady =
      (g_breakout.valid &&
       g_breakout.bullCount > 0 &&
       g_breakout.bullBreakouts[0].valid &&
       (g_breakout.bullBreakouts[0].state == BREAKOUT_BULL_PULLBACK ||
        g_breakout.bullBreakouts[0].state == BREAKOUT_BULL_ENTRY));

   bool bearBreakoutReady =
      (g_breakout.valid &&
       g_breakout.bearCount > 0 &&
       g_breakout.bearBreakouts[0].valid &&
       (g_breakout.bearBreakouts[0].state == BREAKOUT_BEAR_PULLBACK ||
        g_breakout.bearBreakouts[0].state == BREAKOUT_BEAR_ENTRY));

   if(InpUseBreakoutRetest &&
      (entryRegime == REGIME_RANGE || entryRegime == REGIME_CONSOLIDATION || entryRegime == REGIME_NONE))
   {
      if(bullBreakoutReady && bearBreakoutReady)
      {
         entryRegime  = REGIME_NONE;
         regimeSource = "breakout_conflict";
      }
      else if(bullBreakoutReady && d1Bias != D1_BIAS_BEAR)
      {
         entryRegime  = REGIME_BREAKOUT_BULL;
         regimeSource = "breakout_tracker_bull";
      }
      else if(bearBreakoutReady && d1Bias != D1_BIAS_BULL)
      {
         entryRegime  = REGIME_BREAKOUT_BEAR;
         regimeSource = "breakout_tracker_bear";
      }
   }

   if(UseReversalDetector && (entryRegime == REGIME_NONE || entryRegime == REGIME_CONSOLIDATION))
   {
      bool bullReversalReady =
         (g_reversal.valid &&
          g_reversal.bullState == REVERSAL_BULL_ENTRY &&
          g_reversal.bullNecklineBroken);

      bool bearReversalReady =
         (g_reversal.valid &&
          g_reversal.bearState == REVERSAL_BEAR_ENTRY &&
          g_reversal.bearNecklineBroken);

      if(bullReversalReady && bearReversalReady)
      {
         entryRegime  = REGIME_NONE;
         regimeSource = "reversal_conflict";
      }
      else if(bullReversalReady && (d1Bias != D1_BIAS_BEAR || AllowSweepCounterTrend))
      {
         entryRegime  = REGIME_REVERSAL_BULL;
         regimeSource = "reversal_tracker_bull";
      }
      else if(bearReversalReady && (d1Bias != D1_BIAS_BULL || AllowSweepCounterTrend))
      {
         entryRegime  = REGIME_REVERSAL_BEAR;
         regimeSource = "reversal_tracker_bear";
      }
   }

   Print("[REGIME_SOURCE] source=", regimeSource,
         " state=", (g_structure.valid ? StructureStateToString(g_structure.state) : "INVALID"),
         " regime=", (int)entryRegime);
   Print("[TREND_WRAPPER] regime=", (int)entryRegime);

   if(entryRegime == REGIME_NONE)
   {
      Print("[ENTRY_LOGIC] regime=NONE source=", regimeSource,
            " trying one-sided D1 zone retest before blocking");
   }

   g_trendState = TrendStateFromRegime(entryRegime);
   Print("[LOCAL_REGIME] tf=H4 state=", TrendStateToString(g_trendState),
         " zoneTF=", EnumToString(InpZoneTF),
         " entryTF=", EnumToString(InpEntryTF),
         " d1Aligned=", (d1Bias == D1_BIAS_BULL ? "BUY" : (d1Bias == D1_BIAS_BEAR ? "SELL" : "NEUTRAL")));

   // === Zone proximity check (context only, not entry blocker) ===
   double zoneDist = 0.0;
   ENUM_ZONE_TYPE zoneType = ZONE_DEMAND;
   double zoneProxDist = GetATR(g_ind, 1) * g_profile.zoneProximityATRMult;
   bool nearZone = IsNearAnyZone(g_ind.closeArr[1], g_profile, zoneDist, zoneType, zoneProxDist);
   if(nearZone)
   {
      Print("NEAR ZONE: type=", ZoneTypeToString(zoneType),
            " dist=", DoubleToString(zoneDist / g_profile.point, 0), " pts");

      ZoneInfo touchedZone;
      if(GetNearestZone(g_ind.closeArr[1], touchedZone))
      {
         Print("[ZONE_TOUCH] type=", ZoneTypeToString(touchedZone.type),
               " bid=", DoubleToString(g_market.bid, g_profile.digits),
               " ask=", DoubleToString(g_market.ask, g_profile.digits),
               " zoneHigh=", DoubleToString(touchedZone.upperBound, g_profile.digits),
               " zoneLow=", DoubleToString(touchedZone.lowerBound, g_profile.digits),
               " zoneMid=", DoubleToString(touchedZone.midPoint, g_profile.digits),
               " tag=", touchedZone.structuralTag,
               " id=", touchedZone.id);
      }
   }

   // === AI Learning: scan for manual trades + build learning keys ===
   string regimeStr = TrendStateToString(g_trendState);
   string buyLearningKey  = "";
   string sellLearningKey = "";
   if(UseAILearning)
   {
      ScanForManualTrades(ExpertMagic, regimeStr, nearZone, (int)zoneType, false, false);
      buyLearningKey  = BuildLearningKey("BUY",  regimeStr, nearZone, (int)zoneType, false);
      sellLearningKey = BuildLearningKey("SELL", regimeStr, nearZone, (int)zoneType, false);
   }


   // === Setup keys for trade mapping ===
   string buySetupKey  = BuildSetupKey("BUY", g_ind, zoneType);
   string sellSetupKey = BuildSetupKey("SELL", g_ind, zoneType);

   // STEP 2: Effective risk with high-risk backtest mode and live safety cap
   double requestedRisk = (g_profile.riskPctOverride > 0.0) ? g_profile.riskPctOverride : RiskPercent;
   double effectiveRisk = requestedRisk;

   if(InpUseHighRiskBacktestMode)
   {
      effectiveRisk = InpHighRiskBacktestPercent;

      Print("[RISK_MODE] HIGH_RISK_BACKTEST enabled risk=",
            DoubleToString(effectiveRisk, 2), "%");
   }
   else
   {
      effectiveRisk = MathMin(requestedRisk, InpLiveMaxRiskPercent);

      if(requestedRisk > InpLiveMaxRiskPercent)
      {
         Print("[RISK_CAP] requested=", DoubleToString(requestedRisk, 2),
               "% capped_to=", DoubleToString(effectiveRisk, 2),
               "% high_risk_mode=false");
      }
   }

   // === HTF REVERSAL BLOCKER DISABLED ===
   // HTF reversal signals from SupportResistanceZones.mqh are no longer used
   // bool htfBearishReversal = UseReversalDetector && HasMajorBearishReversalSRSignal(_Symbol);
   // bool htfBullishReversal = UseReversalDetector && HasMajorBullishReversalSRSignal(_Symbol);
   bool blockContBuys  = false;  // DISABLED - no blocking
   bool blockContSells = false;  // DISABLED - no blocking

   if(atrNow <= 0 || !g_market.canTradeNow || IsRiskLocked()) return;

   if(IsTrendExhausted())
   {
      Print("[BLOCK] Trend exhausted");
      return;
   }

   EntryDecision finalDecision = MakeEmptyDecision();

   // Regime classification
   bool isBull = (entryRegime == MARKET_TREND_BULL ||
                  entryRegime == MARKET_BREAKOUT_BULL ||
                  entryRegime == MARKET_REVERSAL_BULL);
   bool isTrendRegime = (entryRegime == MARKET_TREND_BULL || entryRegime == MARKET_TREND_BEAR);
   bool isRangeRegime = (entryRegime == MARKET_RANGE);
   bool isConsolidation = (entryRegime == MARKET_CONSOLIDATION);
   
   // Check for breakout/reversal using regimeSource
   bool isBreakout = (StringFind(regimeSource, "breakout") >= 0);
   bool isReversal = (StringFind(regimeSource, "reversal") >= 0);

   if(entryRegime == REGIME_NONE)
   {
      ENUM_D1_BIAS d1BiasNow = GetD1Bias();

      EntryDecision retestBuy  = GenerateZoneRetestDecision(g_ind, g_profile, true,  EntryStopATR, RewardRisk);
      EntryDecision retestSell = GenerateZoneRetestDecision(g_ind, g_profile, false, EntryStopATR, RewardRisk);

      if(d1BiasNow == D1_BIAS_BULL && retestSell.valid)
      {
         Print("[REGIME_NONE_FILTER] blocking SELL retest because D1 bias is BUY");
         retestSell.valid = false;
         retestSell.reason = "blocked by D1_BULL";
      }
      else if(d1BiasNow == D1_BIAS_BEAR && retestBuy.valid)
      {
         Print("[REGIME_NONE_FILTER] blocking BUY retest because D1 bias is SELL");
         retestBuy.valid = false;
         retestBuy.reason = "blocked by D1_BEAR";
      }

      if(retestBuy.valid && retestSell.valid)
      {
         finalDecision = (retestBuy.rankScore >= retestSell.rankScore) ? retestBuy : retestSell;
         finalDecision.reason += " | ZONE_RETEST";
      }
      else if(retestBuy.valid)
      {
         finalDecision = retestBuy;
         finalDecision.reason += " | ZONE_RETEST";
      }
      else if(retestSell.valid)
      {
         finalDecision = retestSell;
         finalDecision.reason += " | ZONE_RETEST";
      }

      if(!finalDecision.valid)
      {
         Print("[ENTRY_BLOCKED] reason=REGIME_NONE source=", regimeSource,
               " — no trend, no valid range, and no valid one-sided D1 zone retest");
         return;
      }
   }
   else if(isTrendRegime && !isBreakout && !isReversal)
   {
      Print("[ENTRY_LOGIC] regime=", EnumToString(entryRegime), " source=", regimeSource,
            " using INDEPENDENT trend continuation first; S/D retest fallback only");

      bool trendHardBlocked = false;

      // STEP 1: Real trend-continuation engine must run first.
      finalDecision = GenerateTrendContinuationDecision(g_ind, g_profile, isBull);

      ENUM_D1_BIAS d1BiasNow = GetD1Bias();
      bool d1Conflicts = (isBull && d1BiasNow == D1_BIAS_BEAR) ||
                         (!isBull && d1BiasNow == D1_BIAS_BULL);

      if(finalDecision.valid && d1Conflicts)
      {
         Print("[TREND_BLOCKED] reason=d1_alignment side=", (isBull ? "BUY" : "SELL"),
               " d1=", D1BiasToString(d1BiasNow));
         finalDecision = MakeEmptyDecision();
         finalDecision.reason = "D1 bias conflicts with H4 trend direction";
         trendHardBlocked = true;
      }
      else if(finalDecision.valid && isBull && IsDirtyTrendContext(true))
      {
         Print("[TREND_BLOCKED] reason=dirty_h4_buy_context");
         finalDecision = MakeEmptyDecision();
         finalDecision.reason = "Dirty H4 context blocks buy";
         trendHardBlocked = true;
      }
      else if(finalDecision.valid && !isBull && IsDirtyTrendContext(false))
      {
         Print("[TREND_BLOCKED] reason=dirty_h4_sell_context");
         finalDecision = MakeEmptyDecision();
         finalDecision.reason = "Dirty H4 context blocks sell";
         trendHardBlocked = true;
      }

      if(finalDecision.valid)
      {
         finalDecision.mode = isBull ? TRADE_MODE_BULL_TREND : TRADE_MODE_BEAR_TREND;

         if(StringFind(finalDecision.reason, " | TREND") < 0)
            finalDecision.reason += " | TREND_CONTINUATION_DIRECT";

         finalDecision.rankScore += 0.50;

         Print("[TREND_DIRECT_ENTRY] side=", (isBull ? "BUY" : "SELL"),
               " reason=", finalDecision.reason);
      }

      // STEP 2: Only if trend continuation did not trigger, try same-direction S/D retest.
      // IMPORTANT: S/D may NOT return early and block all trend trades anymore.
      if(!trendHardBlocked && !finalDecision.valid && InpUseSupplyDemandZones)
      {
         bool sdHandled = false;
         EntryDecision sdFallback = GenerateTrendAlignedSDDecision(g_ind, g_profile, sdHandled);

         // Accept SD fallback if direction matches H4 trend OR if D1 supports the SD direction
         // (D1 pullback scenario: H4 is bear but D1 strongly bullish → BUY the dip is correct)
         ENUM_D1_BIAS d1ForSD = GetD1Bias();
         bool d1AlignsWithSD = (sdFallback.isBuy && d1ForSD == D1_BIAS_BULL) ||
                               (!sdFallback.isBuy && d1ForSD == D1_BIAS_BEAR);
         bool directionAccepted = (sdFallback.isBuy == isBull) || d1AlignsWithSD;

         if(sdFallback.valid && directionAccepted)
         {
            if(sdFallback.isBuy == isBull)
            {
               sdFallback.mode = isBull ? TRADE_MODE_BULL_TREND : TRADE_MODE_BEAR_TREND;
               sdFallback.reason += " | TREND_ALIGNED_SD_FALLBACK";
            }
            else
            {
               // D1 pullback trade: H4 disagrees but D1 strongly supports this direction
               sdFallback.mode = sdFallback.isBuy ? TRADE_MODE_BULL_TREND : TRADE_MODE_BEAR_TREND;
               sdFallback.reason += " | D1_PULLBACK_SD_ENTRY";
               Print("[D1_PULLBACK_TRADE] side=", (sdFallback.isBuy ? "BUY" : "SELL"),
                     " d1=", D1BiasToString(d1ForSD),
                     " h4_regime=", EnumToString(entryRegime),
                     " note=D1_overrides_H4_pullback");
            }
            sdFallback.rankScore += 0.35;
            finalDecision = sdFallback;

            Print("[TREND_SD_FALLBACK] side=", (sdFallback.isBuy ? "BUY" : "SELL"),
                  " reason=", finalDecision.reason);
         }
         else if(sdHandled)
         {
            Print("[TREND_SD_FALLBACK_WAIT] side=", (isBull ? "BUY" : "SELL"),
                  " sdReason=", sdFallback.reason,
                  " note=trend_engine_failed_but_sd_no_longer_hard_blocks_trend_mode");
         }
      }
   }
   else if(isBreakout && isBull)
   {
      Print("[ENTRY_LOGIC] regime=BREAKOUT_BULL source=", regimeSource, " retest_only=true");
      finalDecision = GenerateBreakoutBuySignal(g_ind, g_profile, EntryStopATR, RewardRisk);
      if(finalDecision.valid)
         finalDecision.reason += " | BREAKOUT_BUY";
   }
   else if(isBreakout && !isBull)
   {
      Print("[ENTRY_LOGIC] regime=BREAKOUT_BEAR source=", regimeSource, " retest_only=true");
      finalDecision = GenerateBreakoutSellSignal(g_ind, g_profile, EntryStopATR, RewardRisk);
      if(finalDecision.valid)
         finalDecision.reason += " | BREAKOUT_SELL";
   }
   else if(isReversal && isBull)
   {
      // Counter-trend buy
      EntryDecision sameDirTrend = GenerateTrendContinuationDecision(g_ind, g_profile, true);
      if(sameDirTrend.valid)
      {
         Print("[COUNTER_TREND_BLOCKED] reason=trend_continuation_has_priority side=BUY");
         finalDecision.reason = "counter-trend blocked by valid bull trend continuation";
      }
      else
      {
         finalDecision = GenerateCounterTrendDecision(g_ind, g_profile, true);
      }
   }
   else if(isReversal && !isBull)
   {
      // Counter-trend sell
      EntryDecision sameDirTrend = GenerateTrendContinuationDecision(g_ind, g_profile, false);
      if(sameDirTrend.valid)
      {
         Print("[COUNTER_TREND_BLOCKED] reason=trend_continuation_has_priority side=SELL");
         finalDecision.reason = "counter-trend blocked by valid bear trend continuation";
      }
      else
      {
         finalDecision = GenerateCounterTrendDecision(g_ind, g_profile, false);
      }
   }
   else if(isRangeRegime)
   {
      Print("[ENTRY_LOGIC] regime=RANGE source=", regimeSource, " using horizontal boundaries only");
      finalDecision = GenerateRangeBoundaryEntries(g_ind, g_profile,
                                                   EntryADXMin, EntryADXTrend, EntryADXRange,
                                                   EntryZoneTolATR, EntryStopATR, RewardRisk,
                                                   TrendSlopeLookback);

      if(GetD1Bias() == D1_BIAS_BULL && finalDecision.valid && !finalDecision.isBuy)
      {
         finalDecision.valid = false;
         finalDecision.reason = "blocked by D1_BULL range filter";
      }
      else if(GetD1Bias() == D1_BIAS_BEAR && finalDecision.valid && finalDecision.isBuy)
      {
         finalDecision.valid = false;
         finalDecision.reason = "blocked by D1_BEAR range filter";
      }
      else if(finalDecision.valid)
      {
         if(GetD1Bias() == D1_BIAS_BULL && finalDecision.isBuy)
            finalDecision.rankScore += 0.40;
         else if(GetD1Bias() == D1_BIAS_BEAR && !finalDecision.isBuy)
            finalDecision.rankScore += 0.40;

         finalDecision.reason += " | RANGE";
      }

      if(!finalDecision.valid)
      {
         Print("[ENTRY_LOGIC] regime=RANGE_RETEST source=", regimeSource, " trying one-sided D1 zone retest");

         EntryDecision retestBuy  = GenerateZoneRetestDecision(g_ind, g_profile, true,  EntryStopATR, RewardRisk);
         EntryDecision retestSell = GenerateZoneRetestDecision(g_ind, g_profile, false, EntryStopATR, RewardRisk);

         if(retestBuy.valid && retestSell.valid)
            finalDecision = (retestBuy.rankScore >= retestSell.rankScore) ? retestBuy : retestSell;
         else if(retestBuy.valid)
            finalDecision = retestBuy;
         else if(retestSell.valid)
            finalDecision = retestSell;

         if(finalDecision.valid)
            finalDecision.reason += " | ZONE_RETEST";
      }
   }
   else if(isConsolidation)
   {
      Print("[ENTRY_LOGIC] regime=CONSOLIDATION source=", regimeSource);
      if(InpBlockTradesInConsolidation)
      {
         Print("[ENTRY_BLOCKED] reason=CONSOLIDATION blocked_by_input");
         return;
      }

      // Try zone retest as last resort
      if(!finalDecision.valid)
      {
         EntryDecision retestBuy  = GenerateZoneRetestDecision(g_ind, g_profile, true,  EntryStopATR, RewardRisk);
         EntryDecision retestSell = GenerateZoneRetestDecision(g_ind, g_profile, false, EntryStopATR, RewardRisk);

         if(retestBuy.valid && retestSell.valid)
            finalDecision = (retestBuy.rankScore >= retestSell.rankScore) ? retestBuy : retestSell;
         else if(retestBuy.valid)
            finalDecision = retestBuy;
         else if(retestSell.valid)
            finalDecision = retestSell;

         if(finalDecision.valid)
         {
            finalDecision.reason += " | CONSOLIDATION_ZONE_RETEST";
            Print("[CONSOLIDATION_FALLBACK] using_zone_retest side=", (finalDecision.isBuy ? "BUY" : "SELL"));
         }
      }

      if(!finalDecision.valid)
         finalDecision.reason = "consolidation: no valid zone retest available";
   }

   if(!finalDecision.valid)
   {
      Print("[ENTRY_BLOCKED] reason=NO_VALID_SIGNAL regime=", EnumToString(entryRegime),
            " detail=", finalDecision.reason);
      return;
   }
         
   Print("[ENTRY_EVAL] regime=", (int)entryRegime,
         " decision=", finalDecision.valid, "(", finalDecision.reason, ")");

   if(!finalDecision.valid) return;

   // Zone scoring gate — hard block entries below MinEntryScore
   if(UseZoneScoring && MinEntryScore > 0)
   {
      bool htfTrendAligned =
         (entryRegime == MARKET_TREND_BULL || entryRegime == MARKET_TREND_BEAR);
      bool candleConfirmOK = true;
      string scoreDetail = "";

      int setupScore = ScoreSetup(finalDecision.isBuy,
                                  g_ind.closeArr[1],
                                  GetATR(g_ind, 1),
                                  htfTrendAligned,
                                  candleConfirmOK,
                                  scoreDetail);

      if(finalDecision.zoneIdx >= 0 && finalDecision.zoneIdx < g_zoneReg.count)
      {
         ZoneInfo sel = g_zoneReg.zones[finalDecision.zoneIdx];
         double scoreTol = MathMax(GetATR(g_ind, 1) * 0.20, g_profile.point * 5.0);
         bool inSelectedZone =
            (g_ind.closeArr[1] >= sel.lowerBound - scoreTol &&
             g_ind.closeArr[1] <= sel.upperBound + scoreTol);

         if(inSelectedZone)
         {
            setupScore += 2;
            scoreDetail += "+2(selectedZone) ";
         }

         if(sel.isFlipZone)
         {
            setupScore += 1;
            scoreDetail += "+1(selectedFlip) ";
         }

         if(finalDecision.interactionType == ZONE_INTERACTION_SWEEP_RECLAIM)
         {
            setupScore += 1;
            scoreDetail += "+1(sweep) ";
         }
         else if(finalDecision.interactionType == ZONE_INTERACTION_BREAKRETEST)
         {
            setupScore += 1;
            scoreDetail += "+1(breakRetest) ";
         }
         else if(finalDecision.interactionType == ZONE_INTERACTION_REJECTION)
         {
            setupScore += 1;
            scoreDetail += "+1(rejection) ";
         }
      }

      Print("[ENTRY_SCORE] dir=", (finalDecision.isBuy ? "BUY" : "SELL"),
            " score=", setupScore,
            " min=", MinEntryScore,
            " detail=", scoreDetail);

      if(setupScore < MinEntryScore)
      {
         Print("[ENTRY_BLOCKED] reason=ZONE_SCORE_TOO_LOW score=", setupScore,
               " min=", MinEntryScore,
               " detail=", scoreDetail);
         return;
      }
   }

   // === AI Scoring Gate ===
   // Runs AFTER all hard rules pass. AI may reduce risk or skip weak setups.
   if(g_ai.enabled)
   {
      SetupContext aiCtx;
      aiCtx.isBuy        = finalDecision.isBuy;
      aiCtx.regime       = entryRegime;
      aiCtx.isTrendTrade =
         (entryRegime == REGIME_TREND_BULL || entryRegime == REGIME_TREND_BEAR ||
          entryRegime == REGIME_BREAKOUT_BULL || entryRegime == REGIME_BREAKOUT_BEAR);

      if(finalDecision.zoneIdx >= 0 && finalDecision.zoneIdx < g_zoneReg.count)
      {
         ZoneInfo zs = g_zoneReg.zones[finalDecision.zoneIdx];
         aiCtx.zoneStrength  = zs.strength;
         aiCtx.zoneFreshness = zs.freshness;
         aiCtx.zoneTouches   = zs.cleanTouchCount;
         aiCtx.isFlip        = zs.isFlipZone;
         aiCtx.distToZoneATR = ZoneDistanceFromPriceATR(zs, g_ind.closeArr[1], atrNow);
         aiCtx.zoneRole = zs.isFlipZone
                        ? (aiCtx.isBuy ? "FLIP_SUPPORT" : "FLIP_RESISTANCE")
                        : (aiCtx.isBuy ? "SUPPORT_MAJOR" : "RESISTANCE_MAJOR");
      }
      else
      {
         aiCtx.zoneRole      = aiCtx.isBuy ? "SUPPORT_MAJOR" : "RESISTANCE_MAJOR";
         aiCtx.zoneStrength  = 0.5;
         aiCtx.zoneFreshness = 0.5;
         aiCtx.zoneTouches   = 1;
         aiCtx.isFlip        = false;
         aiCtx.distToZoneATR = 0.0;
      }

      if(finalDecision.interactionType == ZONE_INTERACTION_SWEEP_RECLAIM)
         aiCtx.patternName = "SWEEP_RECLAIM";
      else if(finalDecision.interactionType == ZONE_INTERACTION_BREAKRETEST)
         aiCtx.patternName = "BREAK_RETEST";
      else if(finalDecision.interactionType == ZONE_INTERACTION_REJECTION)
         aiCtx.patternName = "REJECTION";
      else
         aiCtx.patternName = "NONE";

      aiCtx.stopSizeATR     = (atrNow > 0) ? MathAbs(g_ind.closeArr[1] - finalDecision.stopLoss) / atrNow : 2.0;
      aiCtx.distToTargetATR = (atrNow > 0) ? MathAbs(finalDecision.takeProfit - g_ind.closeArr[1]) / atrNow : 4.0;

      double nzLow = 0, nzHigh = 0; int nzIdx = -1;
      if(finalDecision.isBuy)
         FindNextResistanceZoneAbove(g_ind.closeArr[1], atrNow, nzIdx, nzLow, nzHigh);
      else
         FindNextSupportZoneBelow(g_ind.closeArr[1], atrNow, nzIdx, nzLow, nzHigh);
      aiCtx.roomToNextATR = (nzIdx >= 0 && atrNow > 0)
                          ? MathAbs(((nzLow + nzHigh) * 0.5) - g_ind.closeArr[1]) / atrNow
                          : 5.0;

      RunModelInferenceEx(g_ai, g_ind, g_market, g_profile, TrendSlopeLookback, aiCtx);

      if(AISkipThreshold > 0 && g_ai.tradeScore < AISkipThreshold)
      {
         Print("[AI_BLOCKED] reason=SCORE_TOO_LOW score=", DoubleToString(g_ai.tradeScore, 3),
               " min=", DoubleToString(AISkipThreshold, 2));
         return;
      }
      Print("[AI_SCORE_PASS] score=", DoubleToString(g_ai.tradeScore, 3),
            " risk=", DoubleToString(g_ai.riskMultiplier, 2),
            " stop=", DoubleToString(g_ai.stopMultiplier, 2));

      // Update learning keys with real setup context from finalDecision
      if(UseAILearning && finalDecision.zoneIdx >= 0 && finalDecision.zoneIdx < g_zoneReg.count)
      {
         ZoneInfo fz = g_zoneReg.zones[finalDecision.zoneIdx];
         bool fIsTrend = aiCtx.isTrendTrade;
         buyLearningKey  = BuildLearningKeyV2("BUY",  fIsTrend,
                              (fz.isFlipZone ? "FLIP_SUPPORT"    : "SUPPORT_MAJOR"),
                              aiCtx.patternName, (int)g_profile.classEnum);
         sellLearningKey = BuildLearningKeyV2("SELL", fIsTrend,
                              (fz.isFlipZone ? "FLIP_RESISTANCE" : "RESISTANCE_MAJOR"),
                              aiCtx.patternName, (int)g_profile.classEnum);
      }
   }

   // === CONDITIONAL DIRTY MARKET FILTER (after finalDecision) ===
   bool dirtyNow = IsMarketTooDirty();

   bool allowDespiteDirty = false;
   if(finalDecision.valid)
   {
      if(entryRegime == REGIME_TREND_BULL || entryRegime == REGIME_TREND_BEAR ||
         entryRegime == REGIME_BREAKOUT_BULL || entryRegime == REGIME_BREAKOUT_BEAR ||
         entryRegime == REGIME_REVERSAL_BULL || entryRegime == REGIME_REVERSAL_BEAR)
      {
         allowDespiteDirty = true;
      }

      if(entryRegime == REGIME_RANGE &&
         (finalDecision.interactionType == ZONE_INTERACTION_REJECTION ||
          finalDecision.interactionType == ZONE_INTERACTION_BREAKRETEST))
      {
         allowDespiteDirty = true;
      }
   }

   if(dirtyNow && !allowDespiteDirty)
   {
      Print("[BLOCK] Market too dirty → no trade");
      return;
   }
   else if(dirtyNow && allowDespiteDirty)
   {
      Print("[DIRTY_FILTER_BYPASS] allowed=true regime=", (int)entryRegime,
            " interaction=", InteractionToString(finalDecision.interactionType));
   }

   // STEP 5: Pre-trade confidence gate
   double preConf = 0.0;

   if(InpSDUsePreTradeConfidenceGate && finalDecision.valid)
   {
      preConf = ComputePreTradeConfidence(finalDecision, g_ind, entryRegime);

      Print("[PRE_TRADE_CONF] side=", finalDecision.isBuy ? "BUY" : "SELL",
            " conf=", DoubleToString(preConf, 1),
            " min=", DoubleToString(InpSDMinPreTradeConfidence, 1),
            " rr=", DoubleToString(finalDecision.projectedRR, 2),
            " usedOppositeZoneTP=", finalDecision.usedZoneTarget,
            " rank=", DoubleToString(finalDecision.rankScore, 2),
            " reason=", finalDecision.reason);

      if(preConf < InpSDMinPreTradeConfidence)
      {
         Print("[ENTRY_BLOCKED] reason=PRE_TRADE_CONF_TOO_LOW conf=",
               DoubleToString(preConf, 1));
         return;
      }
   }

   // STEP 6: Anti-hedge with strong-signal close/reverse logic
   if(finalDecision.isBuy && !AllowHedging && HasOpenSellPosition(ExpertMagic))
   {
      bool strongOppositeSignal =
         InpSDCloseOppositeOnStrongSignal &&
         finalDecision.projectedRR >= InpSDOppositeSignalMinRR &&
         finalDecision.rankScore >= InpSDOppositeSignalMinRank &&
         (!InpSDUsePreTradeConfidenceGate || preConf >= InpSDOppositeSignalMinConfidence);

      if(strongOppositeSignal)
      {
         Print("[ANTI_HEDGE_REVERSAL] closing SELL positions before BUY",
               " rr=", DoubleToString(finalDecision.projectedRR, 2),
               " rank=", DoubleToString(finalDecision.rankScore, 2),
               " conf=", DoubleToString(preConf, 1));

         CloseTrendCampaignPositions(g_trade,
                                     ExpertMagic,
                                     -1,
                                     "CLOSE_SELL_FOR_STRONG_BUY_SD_SIGNAL");
      }
      else
      {
         Print("[ENTRY_BLOCKED] reason=ANTI_HEDGE (open sell)",
               " rr=", DoubleToString(finalDecision.projectedRR, 2),
               " rank=", DoubleToString(finalDecision.rankScore, 2),
               " conf=", DoubleToString(preConf, 1));
         return;
      }
   }

   if(!finalDecision.isBuy && !AllowHedging && HasOpenBuyPosition(ExpertMagic))
   {
      bool strongOppositeSignal =
         InpSDCloseOppositeOnStrongSignal &&
         finalDecision.projectedRR >= InpSDOppositeSignalMinRR &&
         finalDecision.rankScore >= InpSDOppositeSignalMinRank &&
         (!InpSDUsePreTradeConfidenceGate || preConf >= InpSDOppositeSignalMinConfidence);

      if(strongOppositeSignal)
      {
         Print("[ANTI_HEDGE_REVERSAL] closing BUY positions before SELL",
               " rr=", DoubleToString(finalDecision.projectedRR, 2),
               " rank=", DoubleToString(finalDecision.rankScore, 2),
               " conf=", DoubleToString(preConf, 1));

         CloseTrendCampaignPositions(g_trade,
                                     ExpertMagic,
                                     +1,
                                     "CLOSE_BUY_FOR_STRONG_SELL_SD_SIGNAL");
      }
      else
      {
         Print("[ENTRY_BLOCKED] reason=ANTI_HEDGE (open buy)",
               " rr=", DoubleToString(finalDecision.projectedRR, 2),
               " rank=", DoubleToString(finalDecision.rankScore, 2),
               " conf=", DoubleToString(preConf, 1));
         return;
      }
   }

   STRATEGY_OWNER requestedOwner = OWNER_NONE;
   if(entryRegime == REGIME_TREND_BULL || entryRegime == REGIME_TREND_BEAR)
      requestedOwner = OWNER_TREND;
   else if(entryRegime == REGIME_RANGE)
      requestedOwner = OWNER_RANGE;
   else if(entryRegime == REGIME_BREAKOUT_BULL || entryRegime == REGIME_BREAKOUT_BEAR)
      requestedOwner = OWNER_BREAKOUT;
   else if(entryRegime == REGIME_REVERSAL_BULL || entryRegime == REGIME_REVERSAL_BEAR)
      requestedOwner = OWNER_REVERSAL;

   // Infer owner when regime is NONE but a valid decision still exists.
   if(requestedOwner == OWNER_NONE && finalDecision.valid)
   {
      bool withD1Bias =
         ((finalDecision.isBuy  && GetD1Bias() == D1_BIAS_BULL) ||
          (!finalDecision.isBuy && GetD1Bias() == D1_BIAS_BEAR));

      if(StringFind(finalDecision.reason, "BREAKOUT") >= 0)
         requestedOwner = OWNER_BREAKOUT;
      else if(StringFind(finalDecision.reason, "REVERSAL") >= 0 ||
              StringFind(finalDecision.reason, "CT_") >= 0)
         requestedOwner = OWNER_REVERSAL;
      else if(StringFind(finalDecision.reason, "ZONE_RETEST") >= 0 ||
              StringFind(finalDecision.reason, "TREND") >= 0 ||
              StringFind(finalDecision.reason, "CONTINUATION") >= 0)
         requestedOwner = withD1Bias ? OWNER_TREND : OWNER_REVERSAL;
   }

   STRATEGY_OWNER openOwner = GetOpenSymbolOwner(ExpertMagic);
   bool sameDirectionOpen =
      (finalDecision.isBuy  && HasOpenBuyPosition(ExpertMagic)  && !HasOpenSellPosition(ExpertMagic)) ||
      (!finalDecision.isBuy && HasOpenSellPosition(ExpertMagic) && !HasOpenBuyPosition(ExpertMagic));

   if(openOwner != OWNER_NONE && openOwner != requestedOwner)
   {
      bool compatible = AreOwnersCompatible(openOwner, requestedOwner, sameDirectionOpen);
      if(!compatible)
      {
         Print("[ENTRY_BLOCKED] reason=OWNER_CONFLICT openOwner=", (int)openOwner,
               " requestedOwner=", (int)requestedOwner);
         return;
      }

      Print("[OWNER_COMPAT] openOwner=", (int)openOwner,
            " requestedOwner=", (int)requestedOwner,
            " sameDirection=", (sameDirectionOpen ? "true" : "false"));
   }

   // non-trend families may not duplicate ownership on the same symbol
   if(openOwner == requestedOwner &&
      requestedOwner != OWNER_NONE &&
      requestedOwner != OWNER_TREND &&
      requestedOwner != OWNER_BREAKOUT)
   {
      Print("[ENTRY_BLOCKED] reason=DUPLICATE_OWNER existing_owner=", (int)openOwner);
      return;
   }

   // Position limit gate - trend campaign uses centralized helper rules
   bool isTrendEntry = (entryRegime == REGIME_TREND_BULL || entryRegime == REGIME_TREND_BEAR);

   if(isTrendEntry && EnableTrendCampaign)
   {
      RefreshTrendCampaignState(ExpertMagic);

      int desiredDir = finalDecision.isBuy ? +1 : -1;
      int sameDirCount = CountTrendCampaignPositions(ExpertMagic, desiredDir);
      int oppDirCount  = CountTrendCampaignPositions(ExpertMagic, -desiredDir);

      if(oppDirCount > 0 && !AllowHedging)
      {
         Print("[TREND_ADD_BLOCKED] reason=opposite_trend_campaign_open");
         return;
      }

      string addReason = "";
      double entryProbe = finalDecision.isBuy ? g_market.ask : g_market.bid;
      double zoneAnchor = finalDecision.isBuy ? g_structure.dynamicSupport : g_structure.dynamicResistance;

      // Patch 7: Fallback to active S/D zone when dynamic channel is disabled (dynSupport/dynResist=0)
      if(zoneAnchor <= 0.0 && finalDecision.zoneIdx >= 0 && finalDecision.zoneIdx < g_zoneReg.count)
      {
         ZoneInfo za = g_zoneReg.zones[finalDecision.zoneIdx];
         zoneAnchor = finalDecision.isBuy ? za.lowerBound : za.upperBound;
         Print("[ZONE_ANCHOR_FALLBACK] dynChannel=0 using_sd_zone id=", za.id,
               " anchor=", DoubleToString(zoneAnchor, _Digits));
      }

      bool trendAddAllowed = TrendAddAllowed(g_ind, g_profile, ExpertMagic,
                                             finalDecision.isBuy,
                                             entryProbe,
                                             zoneAnchor,
                                             addReason);

      if(sameDirCount > 0 && !trendAddAllowed)
      {
         Print("[TREND_ADD_BLOCKED] reason=", addReason);
         return;
      }

      Print("[TREND_CAMPAIGN] leader_opened=", (sameDirCount <= 0),
            " add_allowed=", trendAddAllowed,
            " reason=", addReason,
            " posCount=", sameDirCount);
   }
   else
   {
      if(OnePositionPerSymbol && !EnableStacking && HasOpenPositionForSymbol(ExpertMagic))
      {
         Print("[ENTRY_BLOCKED] reason=ALREADY_IN_POSITION");
         return;
      }

      if(EnableStacking)
      {
         int openCount = CountAllPositionsByMagic(ExpertMagic);
         if(openCount >= MaxStackedTrendPositions)
         {
            Print("[ENTRY_BLOCKED] reason=MAX_STACKED_POSITIONS (", openCount, "/", MaxStackedTrendPositions, ")");
            return;
         }

         if(!(entryRegime == REGIME_TREND_BULL || entryRegime == REGIME_TREND_BEAR))
         {
            if(HasOpenPositionForSymbol(ExpertMagic))
            {
               Print("[ENTRY_BLOCKED] reason=STACKING_DISABLED_FOR_RANGE");
               return;
            }
         }
      }
   }

   Print("[ZONE_ENTRY] dir=", (finalDecision.isBuy ? "BUY" : "SELL"),
         " zone[", finalDecision.zoneIdx, "]",
         " interaction=", InteractionToString(finalDecision.interactionType),
         " sl=", DoubleToString(finalDecision.stopLoss, g_profile.digits),
         " tp=", DoubleToString(finalDecision.takeProfit, g_profile.digits),
         " regime=", (int)entryRegime,
         " reason=", finalDecision.reason);

   bool isChannelToChannelTrade = false;

   // STEP 3: Detect trend-aligned S/D runners
   bool trendAlignedSDRunner = false;

   if(InpSDTrendRetestsAreRunners && isTrendEntry)
   {
      bool bullTrendBuy =
         finalDecision.isBuy &&
         (entryRegime == REGIME_TREND_BULL || entryRegime == MARKET_TREND_BULL) &&
         StringFind(finalDecision.reason, "BUY active Demand retest confirmed") >= 0;

      bool bearTrendSell =
         !finalDecision.isBuy &&
         (entryRegime == REGIME_TREND_BEAR || entryRegime == MARKET_TREND_BEAR) &&
         StringFind(finalDecision.reason, "SELL active Supply retest confirmed") >= 0;

      trendAlignedSDRunner = (bullTrendBuy || bearTrendSell);
   }

   bool isRunnerStyleTrend =
      !isChannelToChannelTrade &&
      isTrendEntry &&
      (trendAlignedSDRunner ||
       StringFind(finalDecision.reason, "trigger=CONTINUATION") >= 0 ||
       StringFind(finalDecision.reason, "CONTINUATION_STRONG") >= 0 ||
       StringFind(finalDecision.reason, "BREAK_RETEST") >= 0 ||
       StringFind(finalDecision.reason, "ZONE_CONTINUATION_") >= 0 ||
       StringFind(finalDecision.reason, "TREND_ZONE_FALLBACK") >= 0 ||
       StringFind(finalDecision.reason, "TREND_CONTINUATION_DIRECT") >= 0 ||
       StringFind(finalDecision.reason, "TREND FALLBACK BUY") >= 0 ||
       StringFind(finalDecision.reason, "TREND FALLBACK SELL") >= 0 ||
       StringFind(finalDecision.reason, "TREND_ALIGNED_SD_FALLBACK") >= 0);

   // STEP 4: Remove broker TP from trend runners only
   double virtualTrendTP = finalDecision.takeProfit;

   if((TrendTradesUseNoFixedTP || InpTrendRunnerNoBrokerTP) && isTrendEntry && isRunnerStyleTrend)
   {
      Print("[TREND_RUNNER] tp_mode=NONE style=runner",
            " virtualTP=", DoubleToString(virtualTrendTP, g_profile.digits),
            " reason=", finalDecision.reason);

      // No broker TP. Position will be managed by trend-end logic and protective trailing.
      finalDecision.takeProfit = 0.0;

      if(StringFind(finalDecision.reason, "TREND_RUNNER_HOLD") < 0)
         finalDecision.reason += " | TREND_RUNNER_HOLD";
   }
   else if(isTrendEntry)
   {
      Print("[TREND_RUNNER] tp_mode=FIXED style=",
            (isChannelToChannelTrade ? "channel_to_channel" : "standard"),
            " tp=", DoubleToString(finalDecision.takeProfit, g_profile.digits));
   }

   if(finalDecision.isBuy)
   {
      string buyLabel =
         (entryRegime == REGIME_RANGE) ? "RANGE_BUY" :
         (entryRegime == REGIME_BREAKOUT_BULL) ? "BREAKOUT_BUY" :
         (entryRegime == REGIME_REVERSAL_BULL) ? "CT_BUY" :
         (isRunnerStyleTrend ? "TREND_RUNNER_BUY" :
         ((StringFind(finalDecision.reason, "TREND_CONTINUATION") >= 0) ||
          (StringFind(finalDecision.reason, "ZONE_CONTINUATION_") >= 0) ||
          (StringFind(finalDecision.reason, "TREND_ZONE_FALLBACK") >= 0)) ? "TREND_CONTINUATION_BUY" :
         "TREND_BUY");
      bool ok = SendBuy(g_trade, g_profile, g_market, g_ind,
                        effectiveRisk, RewardRisk, SwingLookback, MaxSpreadMultiplier,
                        MinSLOverridePoints, g_ai.stopMultiplier, g_ai.riskMultiplier, aiActive,
                        MaxBrokerErrors, EnableNotifications,
                        buyLabel, finalDecision.stopLoss, finalDecision.takeProfit);
      if(ok)
      {
         if(finalDecision.zoneIdx >= 0) MarkZoneTraded(finalDecision.zoneIdx);
         ResetExitFilter();
         ulong posId = FindLastOpenedPositionId(ExpertMagic);
         if(posId > 0)
         {
            // --- FORCE TREND TRADE TAGGING TO STAY TREND, NEVER RANGE ---
            string finalSetupKey = buySetupKey;
            if(StringFind(buyLabel, "TREND") >= 0)
            {
               // Force setup key to use TREND model tag, not RANGE
               string correctedKey = "BUY|TREND|";
               double adx = GetADX(g_ind, 1);
               string adxTag = (adx >= 30) ? "ADXhigh" : (adx <= 15) ? "ADXlow" : "ADXmid";
               correctedKey += adxTag + "|";
               
               if(finalDecision.zoneIdx >= 0 && finalDecision.zoneIdx < g_zoneReg.count)
                  correctedKey += ZoneTypeToString(g_zoneReg.zones[finalDecision.zoneIdx].type);
               else
                  correctedKey += ZoneTypeToString(zoneType);
               
               finalSetupKey = correctedKey;
               Print("[SETUP_TAG_FIX] comment=", buyLabel, " mappedModel=TREND key=", finalSetupKey);
            }
            
            RegisterTradeSetup(posId, finalSetupKey);
            // Register initial risk for true 1R tracking (trailing/BE uses this)
            RegisterInitialRisk(posId, g_lastTrade.entry, finalDecision.stopLoss);

            // --- Confidence tracker: log entry immediately after successful open ---
            string confZoneStateBuy =
               (finalDecision.zoneIdx >= 0 && finalDecision.zoneIdx < g_zoneReg.count)
               ? ZoneTypeToString(g_zoneReg.zones[finalDecision.zoneIdx].type)
               : ZoneTypeToString(zoneType);

            bool confEmaBiasBuy = (GetEMA50(g_ind, 1) > GetEMA200(g_ind, 1));
            bool confPatternBuy =
               (StringFind(finalDecision.reason, "SWEEP") >= 0) ||
               (StringFind(finalDecision.reason, "REJECTION") >= 0) ||
               (StringFind(finalDecision.reason, "ENGULFING") >= 0) ||
               (StringFind(finalDecision.reason, "PULLBACK") >= 0) ||
               (StringFind(finalDecision.reason, "BREAK_RETEST") >= 0) ||
               (StringFind(finalDecision.reason, "CONTINUATION") >= 0);

            string confModel = DeriveModelFromTradeComment(buyLabel);

            double confPatternBonusBuy =
               (entryRegime == REGIME_RANGE) ? 6.0 :
               ((entryRegime == REGIME_BREAKOUT_BULL || entryRegime == REGIME_BREAKOUT_BEAR) ? 7.0 :
               ((entryRegime == REGIME_REVERSAL_BULL || entryRegime == REGIME_REVERSAL_BEAR) ? 6.5 : 8.0));
            double confScoreBuy = ComputeTradeConfidence(
               confEmaBiasBuy, false,
               confPatternBuy, false,
               false, false,
               0.0,
               confPatternBonusBuy
            );

            LogConfidenceEntry(
               posId,
               g_lastTrade.ticket,
               "BUY",
               confScoreBuy,
               buyLabel,
               confModel,
               confZoneStateBuy,
               g_lastTrade.entry,
               finalDecision.stopLoss
            );
         }
         
         if(EnableTrendCampaign && isTrendEntry)
            RegisterTrendCampaignFill(true, g_lastTrade.entry, g_structure.dynamicSupport);
         
         Print("[TRADE_OPENED] direction=BUY model=", buyLabel,
               " sl=", DoubleToString(finalDecision.stopLoss, g_profile.digits),
               " tp=", DoubleToString(finalDecision.takeProfit, g_profile.digits));
      }
   }
   else
   {
      string sellLabel =
         (entryRegime == REGIME_RANGE) ? "RANGE_SELL" :
         (entryRegime == REGIME_BREAKOUT_BEAR) ? "BREAKOUT_SELL" :
         (entryRegime == REGIME_REVERSAL_BEAR) ? "CT_SELL" :
         (isRunnerStyleTrend ? "TREND_RUNNER_SELL" :
         ((StringFind(finalDecision.reason, "TREND_CONTINUATION") >= 0) ||
          (StringFind(finalDecision.reason, "ZONE_CONTINUATION_") >= 0) ||
          (StringFind(finalDecision.reason, "TREND_ZONE_FALLBACK") >= 0)) ? "TREND_CONTINUATION_SELL" :
         "TREND_SELL");
      bool ok = SendSell(g_trade, g_profile, g_market, g_ind,
                         effectiveRisk, RewardRisk, SwingLookback, MaxSpreadMultiplier,
                         MinSLOverridePoints, g_ai.stopMultiplier, g_ai.riskMultiplier, aiActive,
                         MaxBrokerErrors, EnableNotifications,
                         sellLabel, finalDecision.stopLoss, finalDecision.takeProfit);
      if(ok)
      {
         if(finalDecision.zoneIdx >= 0) MarkZoneTraded(finalDecision.zoneIdx);
         ResetExitFilter();
         ulong posId = FindLastOpenedPositionId(ExpertMagic);
         if(posId > 0)
         {
            // --- FORCE TREND TRADE TAGGING TO STAY TREND, NEVER RANGE ---
            string finalSetupKey = sellSetupKey;
            if(StringFind(sellLabel, "TREND") >= 0)
            {
               // Force setup key to use TREND model tag, not RANGE
               string correctedKey = "SELL|TREND|";
               double adx = GetADX(g_ind, 1);
               string adxTag = (adx >= 30) ? "ADXhigh" : (adx <= 15) ? "ADXlow" : "ADXmid";
               correctedKey += adxTag + "|";
               
               if(finalDecision.zoneIdx >= 0 && finalDecision.zoneIdx < g_zoneReg.count)
                  correctedKey += ZoneTypeToString(g_zoneReg.zones[finalDecision.zoneIdx].type);
               else
                  correctedKey += ZoneTypeToString(zoneType);
               
               finalSetupKey = correctedKey;
               Print("[SETUP_TAG_FIX] comment=", sellLabel, " mappedModel=TREND key=", finalSetupKey);
            }
            
            RegisterTradeSetup(posId, finalSetupKey);
            // Register initial risk for true 1R tracking (trailing/BE uses this)
            RegisterInitialRisk(posId, g_lastTrade.entry, finalDecision.stopLoss);

            // --- Confidence tracker: log entry immediately after successful open ---
            string confZoneStateSell =
               (finalDecision.zoneIdx >= 0 && finalDecision.zoneIdx < g_zoneReg.count)
               ? ZoneTypeToString(g_zoneReg.zones[finalDecision.zoneIdx].type)
               : ZoneTypeToString(zoneType);

            bool confEmaBiasSell = (GetEMA50(g_ind, 1) < GetEMA200(g_ind, 1));
            bool confPatternSell =
               (StringFind(finalDecision.reason, "SWEEP") >= 0) ||
               (StringFind(finalDecision.reason, "REJECTION") >= 0) ||
               (StringFind(finalDecision.reason, "ENGULFING") >= 0) ||
               (StringFind(finalDecision.reason, "PULLBACK") >= 0) ||
               (StringFind(finalDecision.reason, "BREAK_RETEST") >= 0) ||
               (StringFind(finalDecision.reason, "CONTINUATION") >= 0);

            string confModel = DeriveModelFromTradeComment(sellLabel);

            double confPatternBonusSell =
               (entryRegime == REGIME_RANGE) ? 6.0 :
               ((entryRegime == REGIME_BREAKOUT_BULL || entryRegime == REGIME_BREAKOUT_BEAR) ? 7.0 :
               ((entryRegime == REGIME_REVERSAL_BULL || entryRegime == REGIME_REVERSAL_BEAR) ? 6.5 : 8.0));
            double confScoreSell = ComputeTradeConfidence(
               confEmaBiasSell, false,
               confPatternSell, false,
               false, false,
               0.0,
               confPatternBonusSell
            );

            LogConfidenceEntry(
               posId,
               g_lastTrade.ticket,
               "SELL",
               confScoreSell,
               sellLabel,
               confModel,
               confZoneStateSell,
               g_lastTrade.entry,
               finalDecision.stopLoss
            );
         }
         
         if(EnableTrendCampaign && isTrendEntry)
            RegisterTrendCampaignFill(false, g_lastTrade.entry, g_structure.dynamicResistance);
         
         Print("[TRADE_OPENED] direction=SELL model=", sellLabel,
               " sl=", DoubleToString(finalDecision.stopLoss, g_profile.digits),
               " tp=", DoubleToString(finalDecision.takeProfit, g_profile.digits));
      }
   }
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   ProcessTradeTransaction(trans, request, result, ExpertMagic, g_profile, MaxConsecutiveLosses);

   // Set cooldown after loss
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      ulong dealTicket = trans.deal;
      if(dealTicket > 0 && HistoryDealSelect(dealTicket))
      {
         if(HistoryDealGetInteger(dealTicket, DEAL_MAGIC) == ExpertMagic)
         {
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
            {
               double pnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);

               // [TRADE_CLOSED] journal log
               {
                  ENUM_DEAL_TYPE dtLog = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                  string dirLog = (dtLog == DEAL_TYPE_BUY) ? "SELL" : (dtLog == DEAL_TYPE_SELL) ? "BUY" : "UNKNOWN";
                  double cpLog  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                  string reasonLog = (pnl >= 0) ? "TP_OR_MANUAL" : "SL_OR_MANUAL";
                  string comment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
                  if(StringFind(comment, "sl") >= 0 || StringFind(comment, "SL") >= 0)
                     reasonLog = "STOP_LOSS";
                  else if(StringFind(comment, "tp") >= 0 || StringFind(comment, "TP") >= 0)
                     reasonLog = "TAKE_PROFIT";
                  Print("[TRADE_CLOSED] direction=", dirLog,
                        " closePrice=", DoubleToString(cpLog, _Digits),
                        " profit=", DoubleToString(pnl, 2),
                        " reason=", reasonLog);
               }

               // Recover setup key from trade-to-setup mapping
               ulong posId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
               string setupKey = FindTradeSetup(posId);
               if(setupKey == "")
               {
                  // Fallback: build key from current state if not mapped
                  string dealDir = "";
                  ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                  if(dealType == DEAL_TYPE_BUY)  dealDir = "SELL";
                  else if(dealType == DEAL_TYPE_SELL) dealDir = "BUY";
                  if(dealDir != "")
                  {
                     double zd = 0.0;
                     ENUM_ZONE_TYPE zt = ZONE_SUPPORT_MINOR;
                     IsNearAnyZone(g_ind.closeArr[1], g_profile, zd, zt);
                     setupKey = BuildSetupKey(dealDir, g_ind, zt);
                  }
               }

               // Update setup memory with realized PnL
               if(setupKey != "")
               {
                  UpdateSetupOutcome(setupKey, pnl);
                  RemoveTradeSetup(posId);
                  SaveSetupMemory();
               }

               // Remove initial risk entry (cleanup for trailing/BE tracking)
               RemoveInitialRisk(posId);

               // AI outcome logging handled by ProcessTradeTransaction (uses netPnl with commission+swap)
               // Do not duplicate here — would corrupt AI learning with raw pnl

               // Net PnL for confidence tracker and AI learning
               double netPnl = pnl
                             + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)
                             + HistoryDealGetDouble(dealTicket, DEAL_SWAP);
               double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);

               // Confidence tracker: log outcome with R-multiple
               LogConfidenceOutcome(posId, netPnl, dealPrice);

               // AI Learning: record outcome for the learned pattern
               if(UseAILearning)
               {
                  string lKey = FindLearningKey(posId);
                  if(lKey != "")
                  {
                     RecordPatternOutcome(lKey, netPnl, false);
                     RemoveLearningEntry(posId);
                     SaveLearnedPatterns();
                  }
               }

               if(netPnl < 0.0)
               {
                  double lossATR = MathAbs(netPnl);
                  g_cooldownRemain = (lossATR > 0.0 ? CooldownBarsAfterLoss : 0);
               }
               else
               {
                  g_cooldownRemain = 0;
               }
            }
         }
         else
         {
            // Non-bot deal: check if it's a tracked manual trade closing
            if(UseAILearning)
               ProcessManualTradeClose(dealTicket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Redraw visuals on timeframe change or chart click
   if(id == CHARTEVENT_CHART_CHANGE)
   {
      ResetVisualD1Cache();
      DrawZoneLines(g_profile);
      // D1 master trendline visuals removed
      // H4 visual channel removed
      ChartRedraw(0);
   }
}
