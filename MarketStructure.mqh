//+------------------------------------------------------------------+
//|                                              MarketStructure.mqh |
//|  Market Structure Detection: Swings, Channels, Trend/Range      |
//|  Core: In trends, use diagonal channel S/R + flipped major      |
//|        In ranges, use only horizontal major S/R                 |
//|                                                                  |
//|  SECTION MAP:                                                    |
//|   L18   — SECTION 1: Enums & Structs (Swing, Channel, State)   |
//|   L265  — SECTION 2: Global State & Config Variables            |
//|   L1464 — SECTION 3: Compatibility & Wrapper Functions          |
//|   L1476 — SECTION 4: Swing Point Detection                      |
//|   L2008 — SECTION 5: Main Structure Update (per bar)            |
//|   L4120 — SECTION 6: Gap Detection & Tracking                   |
//|   L5100 — SECTION 7: D1 Trendline & Breakout/Reversal State     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, AI Trading Bot"
#property link      ""
#property version   "1.00"

#ifndef MARKET_STRUCTURE_MQH
#define MARKET_STRUCTURE_MQH

#include <Arrays\ArrayObj.mqh>
#include "IndicatorManager.mqh"
#include "SymbolProfiler.mqh"

//+==================================================================+
//| SECTION 1: ENUMS & STRUCTS                                       |
//| SwingPoint, Channel, Structure state types + data structs        |
//+==================================================================+

//+------------------------------------------------------------------+
//| Swing Point Types                                                |
//+------------------------------------------------------------------+
enum ENUM_SWING_TYPE
{
   SWING_NONE = 0,
   SWING_HIGH = 1,
   SWING_LOW  = 2
};

//+------------------------------------------------------------------+
//| Channel State - for multi-state channel management               |
//+------------------------------------------------------------------+
enum ENUM_CHANNEL_STATE
{
   CHANNEL_STATE_NONE      = 0,  // No channel
   CHANNEL_STATE_CANDIDATE = 1,  // Scored but not yet promoted
   CHANNEL_STATE_ACTIVE    = 2,  // Current valid trend channel - used for entries
   CHANNEL_STATE_BROKEN    = 3,  // Invalidated but kept for transition detection
   CHANNEL_STATE_ARCHIVED  = 4   // Old historical - chart reference only
};

//+------------------------------------------------------------------+
//| Market Structure State                                           |
//+------------------------------------------------------------------+
enum ENUM_STRUCTURE_STATE
{
   STRUCTURE_UNKNOWN      = 0,
   STRUCTURE_BULL_TREND   = 1,  // HH + HL sequence
   STRUCTURE_BEAR_TREND   = 2,  // LH + LL sequence
   STRUCTURE_RANGE        = 3,  // No clear sequence
   STRUCTURE_BIAS_BULL    = 4,  // Transitioning to bull (structure shift)
   STRUCTURE_BIAS_BEAR    = 5,  // Transitioning to bear (structure shift)
   STRUCTURE_CONSOLIDATION = 6  // Tight range â€” ADX weak, EMA compressed, no tradable room
};

//+------------------------------------------------------------------+
//| Swing Point Structure                                            |
//+------------------------------------------------------------------+
struct SwingPoint
{
   bool           valid;
   ENUM_SWING_TYPE type;
   double         price;
   int            barIndex;     // Bar index when swing formed
   datetime       time;
   bool           isHigherHigh; // For swing highs: is it higher than previous swing high?
   bool           isLowerLow;   // For swing lows: is it lower than previous swing low?
   bool           isLowerHigh;  // For swing highs: is it lower than previous swing high?
   bool           isHigherLow;  // For swing lows: is it higher than previous swing low?
};

//+------------------------------------------------------------------+
//| Professional Parallel Channel Structure                          |
//| Single active channel with full validation and lifecycle         |
//+------------------------------------------------------------------+
struct ActiveChannel
{
   // Validity and state
   bool     valid;              // Channel is validated and active
   bool     active;             // Channel is currently active for trading
   bool     archived;           // Channel is archived (historical)
   bool     broken;             // Channel has been broken
   int      direction;          // +1 = up channel, -1 = down channel, 0 = none
   
   // Anchor points (swing-based, NOT ema-based)
   int      anchor1Bar;         // First swing point bar index
   int      anchor2Bar;         // Second swing point bar index  
   int      anchor3Bar;         // Confirming swing on opposite side
   double   anchor1Price;       // First swing price
   double   anchor2Price;       // Second swing price
   double   anchor3Price;       // Confirming swing price
   datetime startTime;          // When channel was created
   
   // Channel boundaries (parallel lines)
   double   upperSlope;         // Upper line slope (price change per bar)
   double   upperIntercept;     // Upper line price at bar 0
   double   lowerSlope;         // Lower line slope (price change per bar)
   double   lowerIntercept;     // Lower line price at bar 0
   
   // Validation metrics
   double   width;              // Channel width in price units
   double   widthATR;           // Channel width in ATR multiples
   int      touchCountUpper;    // Valid touches on upper boundary
   int      touchCountLower;    // Valid touches on lower boundary
   double   fitPercentage;      // % of recent bars inside channel (0-100)
   
   // Breakout detection
   int      breakoutCount;      // Consecutive closes outside channel
   double   breakoutBuffer;     // ATR-based buffer for breakout (0.2-0.3 ATR)
   datetime breakTime;          // When channel was broken
   
   // Chart object names
   string   objNameUpper;       // Upper boundary line object
   string   objNameLower;       // Lower boundary line object
   
   // Drawing state fields
   int      startBar;           // Starting bar for drawing
   datetime t1;                 // Time coordinate 1
   datetime t2;                 // Time coordinate 2
   double   p1;                 // Price coordinate 1 (primary line)
   double   p2;                 // Price coordinate 2 (primary line)
   datetime tp1;                // Time coordinate 1 (parallel line)
   datetime tp2;                // Time coordinate 2 (parallel line)
   double   pp1;                // Price coordinate 1 (parallel line)
   double   pp2;                // Price coordinate 2 (parallel line)
};

//+------------------------------------------------------------------+
//| Swing Point for Channel Building                                 |
//+------------------------------------------------------------------+
struct ChannelSwing
{
   int      barIndex;           // Bar index of swing
   double   price;              // Swing price (high for SH, low for SL)
   bool     isHigh;             // true = swing high, false = swing low
   double   strength;           // Quality score of this swing
};

static ActiveChannel g_activeChannel;

//+------------------------------------------------------------------+
//| Trend Anchor Struct (needed by ChannelBuilder)                    |
//+------------------------------------------------------------------+
struct TrendAnchor
{
   datetime t;
   double   p;
   int      b;
};

void SortTrendAnchorsByTime(TrendAnchor &arr[], int count)
{
   for(int i = 0; i < count - 1; i++)
   {
      for(int j = i + 1; j < count; j++)
      {
         if(arr[i].t > arr[j].t)
         {
            TrendAnchor tmp = arr[i];
            arr[i] = arr[j];
            arr[j] = tmp;
         }
      }
   }
}

// Channel code removed per user request - ChannelBuilder.mqh deleted

// Legacy struct for compatibility - will be removed
struct DiagonalChannel
{
   bool   valid;
   bool   isAscending;
   ENUM_CHANNEL_STATE state;
   double upperSlope;
   double upperIntercept;
   double lowerSlope;
   double lowerIntercept;
   double channelWidth;
   double slopeATR;
   int    touchesUpper;
   int    touchesLower;
   int    barsValid;
   bool   directionalValid;
   int    direction;
   double upperSlopeATR;
   double lowerSlopeATR;
   bool   slopesSameSign;
   bool   weakSlope;
   bool   geometryClean;
   double slopeDivergence;
   datetime createdTime;
   datetime brokenTime;
   int      barsAsBroken;
   string   objectNameUpper;
   string   objectNameLower;
   
   double fitPercentage;       // % of bars fitting inside the channel
   int    anchor1Bar;          // first structural anchor
   int    anchor2Bar;          // second structural anchor
   int    confirmBar;          // confirming opposite-side anchor
};

//+------------------------------------------------------------------+
//| Market Structure State Container                                 |
//+------------------------------------------------------------------+
#define MAX_BROKEN_CHANNELS 3
#define MAX_ARCHIVED_CHANNELS 5

struct MarketStructureState
{
   bool                  valid;
   ENUM_STRUCTURE_STATE  state;
   
   // Swing points (most recent first)
   SwingPoint            swingHighs[20];
   SwingPoint            swingLows[20];
   int                   swingHighCount;
   int                   swingLowCount;
   
   // Structure sequence
   int                   consecutiveHH;    // Consecutive higher highs
   int                   consecutiveHL;    // Consecutive higher lows
   int                   consecutiveLH;    // Consecutive lower highs
   int                   consecutiveLL;    // Consecutive lower lows
   
   // Active Channel (only one at a time)
   DiagonalChannel       channel;
   
   // Broken Channels (recently invalidated - for transition detection)
   DiagonalChannel       brokenChannels[MAX_BROKEN_CHANNELS];
   int                   brokenChannelCount;
   
   // Archived Channels (old historical - chart reference only)
   DiagonalChannel       archivedChannels[MAX_ARCHIVED_CHANNELS];
   int                   archivedChannelCount;
   
   // Dynamic S/R from channel
   double                dynamicSupport;   // Current channel support price
   double                dynamicResistance;// Current channel resistance price
   
   // Bias change detection
   bool                  biasChangeDetected;
   bool                  biasChangeBullish;
   int                   barsInCurrentState;
   
   // Channel transition context
   bool                  recentChannelBroken;     // A channel was recently broken
   int                   brokenChannelDirection;  // Direction of most recently broken channel (+1/-1)
   datetime              lastChannelBreakTime;    // When the last channel was broken

   // Range quality fields (Part 1 patch)
   double                rangeQuality;            // 0..10 quality of range classification
   bool                  rangeLikelyTransition;   // true = range is probably a transition state
   
   // Timing
   datetime              lastUpdate;             // Last update timestamp
};

//+==================================================================+
//| SECTION 2: GLOBAL STATE & CONFIG VARIABLES                      |
//| g_structure, trend campaign flags, exhaustion thresholds         |
//+==================================================================+

// Global structure state
MarketStructureState g_structure;

//+------------------------------------------------------------------+
//| Function declarations                                              |
//+------------------------------------------------------------------+
void DetectSwingPoints(const IndicatorState &ind, double atr);
void ClassifySwingSequences(void);
ENUM_STRUCTURE_STATE DetermineStructureState(const IndicatorState &ind, double atr);
int GetMarketTrend(void);

// D1 Master Trendline helpers
bool BuildD1MasterTrendline();
bool ReflectD1TrendlineToLowerTF(ENUM_TIMEFRAMES tf, double &outLineNow, int &outDir);
bool IsD1TrendlineBrokenAndRetested(const IndicatorState &ind, double atr);
bool IsTrendStructureConsolidating(const IndicatorState &ind, double atr);

// Trend persistence memory â€” prevents immediate TREND->RANGE drop
int g_lastConfirmedTrendDir = 0;   // +1 bull, -1 bear
int g_trendPersistenceBars  = 0;

// --- Trend campaign runtime config (set from MY BOT.mq5 OnInit) ---
bool   g_enableTrendCampaign                = true;
bool   g_trendTradesUseNoFixedTP            = true;
bool   g_allowTrendAddsAtDynamicZones       = true;
int    g_maxTrendCampaignPositions          = 3;
int    g_minBarsBetweenTrendAdds            = 2;
double g_minATRDistanceBetweenTrendAdds     = 0.80;
bool   g_requireExistingTrendPositionProfit = true;
bool   g_oneAddPerFreshDynamicZone          = true;
double g_trendEndADXFloor                   = 18.0;
int    g_trendEndConfirmBars                = 2;

int    g_trendExhaustionSwingLookback       = 6;
int    g_trendZoneRejectionMinCount         = 2;
double g_trendEndADXWeakFloor               = 20.0;
double g_trendEndADXDecayMin                = 3.0;
double g_trendEndEmaSpreadWeakATR           = 0.85;
double g_trendEndSlopeWeakATR50             = 0.012;
double g_trendEndSlopeWeakATR200            = 0.010;
double g_trendEndZoneTouchTolATR            = 0.30;

double g_trendZoneBandATR                   = 0.35;
double g_trendZoneSLBufferATR               = 0.30;
int    g_trendZoneWickLookback              = 6;
bool   g_useWickExtremeBeyondZone           = true;

double g_trendTrailMinProfitATR             = 1.0;   // Min ATR profit before zone trail starts
double g_trendBEMinProfitATR                = 1.5;   // Min ATR profit before breakeven snap
double g_trendBEProfitLockATR               = 0.3;   // ATR profit locked in at breakeven stage

// --- Trend Campaign State (shared across modules) ---
struct TrendCampaignState
{
   bool     active;              // Campaign is running
   int      direction;           // +1 = bull, -1 = bear, 0 = none
   int      positionCount;       // Number of open campaign positions
   int      lastAddBar;          // Bar index of last add
   double   lastAddPrice;        // Entry price of last add
   double   lastZoneAnchor;      // Zone anchor used for last add
   datetime lastAddTime;         // Time of last add
   int      trendEndVotes;       // Votes toward trend ending
   int      barsBreakingZone;    // Consecutive bars breaking dynamic zone
};

TrendCampaignState g_campaign = {false, 0, 0, 0, 0.0, 0.0, 0, 0, 0};

//+------------------------------------------------------------------+
//| D1 Master Trendline State                                         |
//+------------------------------------------------------------------+
struct MasterTrendlineState
{
   bool     valid;
   int      direction;        // +1 up, -1 down
   datetime startTime;
   datetime endTime;
   double   startPrice;
   double   endPrice;
   double   lineNow;
   double   slopePerBar;
   int      startBar;
   int      endBar;
   bool     broken;
   bool     retested;
};

MasterTrendlineState g_d1MasterTrendline;

// Lower-TF trendline (reflected from D1)
double   g_lowerTFTrendline = 0.0;
bool     g_lowerTFTrendlineValid = false;

//+------------------------------------------------------------------+
//| Channel State Management Functions                               |
//| NOTE: Channel lifecycle now owned by ChannelBuilder.mqh          |
//|       These are compatibility stubs only                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Sync g_structure.channel - DISABLED (channel code removed)       |
//+------------------------------------------------------------------+
void SyncStructureChannelFromRegistry(const IndicatorState &ind, double atr)
{
   // Channel code removed per user request
   g_structure.channel.valid = false;
   g_structure.channel.state = CHANNEL_STATE_NONE;
   g_structure.channel.direction = 0;
   g_structure.channel.directionalValid = false;
   g_structure.dynamicSupport = 0.0;
   g_structure.dynamicResistance = 0.0;
}

// Initialize a channel with default values
void InitializeChannel(DiagonalChannel &ch)
{
   ch.valid = false;
   ch.isAscending = false;
   ch.state = CHANNEL_STATE_NONE;
   ch.upperSlope = 0.0;
   ch.upperIntercept = 0.0;
   ch.lowerSlope = 0.0;
   ch.lowerIntercept = 0.0;
   ch.channelWidth = 0.0;
   ch.slopeATR = 0.0;
   ch.touchesUpper = 0;
   ch.touchesLower = 0;
   ch.barsValid = 0;
   ch.directionalValid = false;
   ch.direction = 0;
   ch.upperSlopeATR = 0.0;
   ch.lowerSlopeATR = 0.0;
   ch.slopesSameSign = false;
   ch.weakSlope = false;
   ch.geometryClean = false;
   ch.slopeDivergence = 0.0;
   ch.createdTime = 0;
   ch.brokenTime = 0;
   ch.barsAsBroken = 0;
   ch.objectNameUpper = "";
   ch.objectNameLower = "";
   ch.fitPercentage = 0.0;
   ch.anchor1Bar = -1;
   ch.anchor2Bar = -1;
   ch.confirmBar = -1;
}

// Copy channel data
void CopyChannel(DiagonalChannel &dest, const DiagonalChannel &src)
{
   dest.valid = src.valid;
   dest.isAscending = src.isAscending;
   dest.state = src.state;
   dest.upperSlope = src.upperSlope;
   dest.upperIntercept = src.upperIntercept;
   dest.lowerSlope = src.lowerSlope;
   dest.lowerIntercept = src.lowerIntercept;
   dest.channelWidth = src.channelWidth;
   dest.slopeATR = src.slopeATR;
   dest.touchesUpper = src.touchesUpper;
   dest.touchesLower = src.touchesLower;
   dest.barsValid = src.barsValid;
   dest.directionalValid = src.directionalValid;
   dest.direction = src.direction;
   dest.upperSlopeATR = src.upperSlopeATR;
   dest.lowerSlopeATR = src.lowerSlopeATR;
   dest.slopesSameSign = src.slopesSameSign;
   dest.weakSlope = src.weakSlope;
   dest.geometryClean = src.geometryClean;
   dest.slopeDivergence = src.slopeDivergence;
   dest.createdTime = src.createdTime;
   dest.brokenTime = src.brokenTime;
   dest.barsAsBroken = src.barsAsBroken;
   dest.objectNameUpper = src.objectNameUpper;
   dest.objectNameLower = src.objectNameLower;
   dest.fitPercentage = src.fitPercentage;
   dest.anchor1Bar = src.anchor1Bar;
   dest.anchor2Bar = src.anchor2Bar;
   dest.confirmBar = src.confirmBar;
}

// REMOVED: LoadFromActiveChannel - not used, channel lifecycle owned by ChannelBuilder

// REMOVED: BreakActiveChannel - channel lifecycle owned by ChannelBuilder

// REMOVED: ArchiveBrokenChannel - channel lifecycle owned by ChannelBuilder

// REMOVED: DeleteChannelObjects(DiagonalChannel&) - conflicts with ChannelBuilder's DeleteChannelObjects()

// REMOVED: UpdateBrokenChannelBars - channel lifecycle owned by ChannelBuilder

// REMOVED: IsActiveChannelStillValid - channel breakout detection owned by ChannelBuilder

// REMOVED: DetectChannelTransitionPattern - not critical to trading logic

// Check if a channel is usable for trading (only ACTIVE state)
bool IsChannelUsableForTrading()
{
   return (g_structure.channel.valid && 
           g_structure.channel.state == CHANNEL_STATE_ACTIVE &&
           g_structure.channel.directionalValid);
}

// REMOVED: GetMostRecentBrokenChannel - broken channels owned by ChannelBuilder

// REMOVED: All channel drawing functions - drawing owned by ChannelBuilder
// - GetChannelColor
// - GetChannelLineStyle
// - GetChannelLineWidth
// - DrawChannelLine
// - DrawChannelWithState
// - UpdateAllChannelDrawings
// - CleanupAllChannelObjects

double GetDynamicZoneHalfWidth(const IndicatorState &ind)
{
   if(!g_structure.valid || !g_structure.channel.valid)
      return 0.0;

   double atr = GetATR(ind, 1);
   if(atr <= 0.0)
      return 0.0;

   double half = atr * g_trendZoneBandATR;
   double cap  = g_structure.channel.channelWidth * 0.20;

   if(cap > 0.0)
      half = MathMin(half, cap);

   return half;
}

bool GetBullDynamicZoneBand(const IndicatorState &ind,
                            double &zoneLow, double &zoneMid, double &zoneHigh, double &halfWidth)
{
   zoneLow = zoneMid = zoneHigh = halfWidth = 0.0;

   if(!g_structure.valid || !g_structure.channel.valid)
      return false;
   // Only ACTIVE channels can be used for trading
   if(g_structure.channel.state != CHANNEL_STATE_ACTIVE)
      return false;
   if(!g_structure.channel.directionalValid || g_structure.channel.direction != +1)
      return false;
   if(g_structure.dynamicSupport <= 0.0)
      return false;

   halfWidth = GetDynamicZoneHalfWidth(ind);
   if(halfWidth <= 0.0)
      return false;

   zoneMid  = g_structure.dynamicSupport;
   zoneLow  = zoneMid - halfWidth;
   zoneHigh = zoneMid + halfWidth;
   return true;
}

bool GetBearDynamicZoneBand(const IndicatorState &ind,
                            double &zoneLow, double &zoneMid, double &zoneHigh, double &halfWidth)
{
   zoneLow = zoneMid = zoneHigh = halfWidth = 0.0;

   if(!g_structure.valid || !g_structure.channel.valid)
      return false;
   // Only ACTIVE channels can be used for trading
   if(g_structure.channel.state != CHANNEL_STATE_ACTIVE)
      return false;
   if(!g_structure.channel.directionalValid || g_structure.channel.direction != -1)
      return false;
   if(g_structure.dynamicResistance <= 0.0)
      return false;

   halfWidth = GetDynamicZoneHalfWidth(ind);
   if(halfWidth <= 0.0)
      return false;

   zoneMid  = g_structure.dynamicResistance;
   zoneLow  = zoneMid - halfWidth;
   zoneHigh = zoneMid + halfWidth;
   return true;
}

//+------------------------------------------------------------------+
//| Reversal State Enum                                              |
//+------------------------------------------------------------------+
enum ENUM_REVERSAL_STATE
{
   REVERSAL_NONE           = 0,
   REVERSAL_BULL_FORMING   = 1,
   REVERSAL_BULL_CANDIDATE = 2,
   REVERSAL_BULL_CONFIRMED = 3,
   REVERSAL_BULL_ENTRY     = 4,
   REVERSAL_BEAR_FORMING   = 5,
   REVERSAL_BEAR_CANDIDATE = 6,
   REVERSAL_BEAR_CONFIRMED = 7,
   REVERSAL_BEAR_ENTRY     = 8
};

//+------------------------------------------------------------------+
//| Role-Flip Zone Structure                                         |
//+------------------------------------------------------------------+
struct RoleFlipZone
{
   bool     valid;
   bool     wasSupport;
   double   price;
   double   zoneHigh;
   double   zoneLow;
   datetime flipTime;
   int      retestCount;
   bool     retestConfirmed;
};

//+------------------------------------------------------------------+
//| Reversal State Container                                         |
//+------------------------------------------------------------------+
struct ReversalState
{
   bool                 valid;
   ENUM_REVERSAL_STATE  bullState;
   ENUM_REVERSAL_STATE  bearState;
   
   double               bullBaseLevel;
   double               bullNeckline;
   int                  bullRejectionCount;
   bool                 bullMomentumWeak;
   bool                 bullHLFormed;
   bool                 bullNecklineBroken;
   datetime             bullNecklineBreakTime;
   bool                 bullRetestPending;
   
   double               bearBaseLevel;
   double               bearNeckline;
   int                  bearRejectionCount;
   bool                 bearMomentumWeak;
   bool                 bearLHFormed;
   bool                 bearNecklineBroken;
   datetime             bearNecklineBreakTime;
   bool                 bearRetestPending;
   
   RoleFlipZone         flipZones[5];
   int                  flipZoneCount;
   
   bool                 trendTransitionBull;
   bool                 trendTransitionBear;
};

// Global reversal state
ReversalState g_reversal;

//+------------------------------------------------------------------+
//| Initialize Reversal State                                        |
//+------------------------------------------------------------------+
void InitReversalState()
{
   ZeroMemory(g_reversal);
   g_reversal.valid = false;
   g_reversal.bullState = REVERSAL_NONE;
   g_reversal.bearState = REVERSAL_NONE;
   g_reversal.flipZoneCount = 0;
}

//+------------------------------------------------------------------+
//| Breakout State Enum                                              |
//+------------------------------------------------------------------+
enum ENUM_BREAKOUT_STATE
{
   BREAKOUT_NONE              = 0,
   BREAKOUT_BULL_DETECTED     = 1,
   BREAKOUT_BULL_PULLBACK     = 2,
   BREAKOUT_BULL_ENTRY        = 3,
   BREAKOUT_BULL_INVALIDATED  = 4,
   BREAKOUT_BEAR_DETECTED     = 5,
   BREAKOUT_BEAR_PULLBACK     = 6,
   BREAKOUT_BEAR_ENTRY        = 7,
   BREAKOUT_BEAR_INVALIDATED  = 8
};

//+------------------------------------------------------------------+
//| Breakout Level Structure                                         |
//+------------------------------------------------------------------+
struct BreakoutLevel
{
   bool     valid;
   bool     isBullish;
   double   levelPrice;
   double   levelHigh;
   double   levelLow;
   datetime breakoutTime;
   double   breakoutClose;
   double   breakoutBodySize;
   double   breakoutATR;
   int      breakoutBarIndex;
   
   ENUM_BREAKOUT_STATE state;
   int      pullbackBars;
   double   pullbackLow;
   double   pullbackHigh;
   bool     pullbackTouchedLevel;
   bool     pullbackConfirmed;
   int      retestCount;
};

//+------------------------------------------------------------------+
//| Breakout Tracking Container                                      |
//+------------------------------------------------------------------+
struct BreakoutTracker
{
   bool           valid;
   BreakoutLevel  bullBreakouts[5];
   BreakoutLevel  bearBreakouts[5];
   int            bullCount;
   int            bearCount;
   
   // Simple breakout fields for simplified tracking
   int            direction;    // +1 bullish, -1 bearish, 0 none
   double         breakPrice;   // Price where breakout occurred
   datetime       breakTime;    // Time when breakout occurred
};

// Global breakout tracker
BreakoutTracker g_breakout;

//+------------------------------------------------------------------+
//| Initialize Breakout Tracker                                      |
//+------------------------------------------------------------------+
void InitBreakoutTracker()
{
   ZeroMemory(g_breakout);
   g_breakout.valid = true;
   g_breakout.bullCount = 0;
   g_breakout.bearCount = 0;
}

//+------------------------------------------------------------------+
//| Check if price is in pullback zone                               |
//+------------------------------------------------------------------+
bool IsPriceInPullbackZone(double price, const BreakoutLevel &bo, double atr)
{
   double tolerance = atr * 0.5;
   if(bo.isBullish)
      return (price >= bo.levelLow - tolerance && price <= bo.levelHigh + tolerance);
   else
      return (price >= bo.levelLow - tolerance && price <= bo.levelHigh + tolerance);
}

//+------------------------------------------------------------------+
//| Check for bullish pullback confirmation                          |
//+------------------------------------------------------------------+
bool HasBullishPullbackConfirmation(const IndicatorState &ind, const BreakoutLevel &bo, double atr)
{
   if(IsBullishEngulfing(_Symbol, g_indicatorTF, 1)) return true;
   if(IsBullishRejection(ind)) return true;
   
   double lowerWick = MathMin(ind.openArr[1], ind.closeArr[1]) - ind.lowArr[1];
   double range = ind.highArr[1] - ind.lowArr[1];
   if(range > 0 && lowerWick > range * 0.60 && ind.closeArr[1] > ind.openArr[1])
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for bearish pullback confirmation                          |
//+------------------------------------------------------------------+
bool HasBearishPullbackConfirmation(const IndicatorState &ind, const BreakoutLevel &bo, double atr)
{
   if(IsBearishEngulfing(_Symbol, g_indicatorTF, 1)) return true;
   if(IsBearishRejection(ind)) return true;
   
   double upperWick = ind.highArr[1] - MathMax(ind.openArr[1], ind.closeArr[1]);
   double range = ind.highArr[1] - ind.lowArr[1];
   if(range > 0 && upperWick > range * 0.60 && ind.closeArr[1] < ind.openArr[1])
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if bullish reversal entry is allowed                       |
//+------------------------------------------------------------------+
bool IsBullishReversalEntryAllowed(const IndicatorState &ind, double price, double atr)
{
   if(!g_reversal.valid) return false;
   
   // Check if bullish reversal is in entry state
   if(g_reversal.bullState != REVERSAL_BULL_ENTRY) return false;
   
   // Check if neckline was broken and retest held
   if(!g_reversal.bullNecklineBroken) return false;
   
   // Price should be near the neckline (retest zone)
   double tolerance = atr * 0.5;
   if(price < g_reversal.bullNeckline - tolerance || price > g_reversal.bullNeckline + tolerance)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if bearish reversal entry is allowed                       |
//+------------------------------------------------------------------+
bool IsBearishReversalEntryAllowed(const IndicatorState &ind, double price, double atr)
{
   if(!g_reversal.valid) return false;
   
   // Check if bearish reversal is in entry state
   if(g_reversal.bearState != REVERSAL_BEAR_ENTRY) return false;
   
   // Check if neckline was broken and retest failed
   if(!g_reversal.bearNecklineBroken) return false;
   
   // Price should be near the neckline (retest zone)
   double tolerance = atr * 0.5;
   if(price < g_reversal.bearNeckline - tolerance || price > g_reversal.bearNeckline + tolerance)
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check if bullish pullback entry is allowed (breakout retest buy) |
//+------------------------------------------------------------------+
bool IsBullishPullbackEntryAllowed(const IndicatorState &ind, double price, double atr,
                                    double &outSL, double &outTP)
{
   outSL = 0;
   outTP = 0;
   
   if(!g_breakout.valid) return false;
   
   for(int i = 0; i < g_breakout.bullCount; i++)
   {
      BreakoutLevel bo = g_breakout.bullBreakouts[i];
      if(!bo.valid) continue;
      if(bo.state != BREAKOUT_BULL_PULLBACK && bo.state != BREAKOUT_BULL_ENTRY) continue;
      
      // Price must be in the pullback zone
      if(!IsPriceInPullbackZone(price, bo, atr)) continue;
      
      // Must have bullish confirmation
      if(!HasBullishPullbackConfirmation(ind, bo, atr)) continue;
      
      // Set SL below the level and TP at next major resistance
      outSL = bo.levelLow - atr * 0.35;
      outTP = FindNearestMajorResistanceLevel(price, atr);
      if(outTP <= price || outTP <= 0) outTP = price + atr * 2.0;
      
      double risk = price - outSL;
      double reward = outTP - price;
      if(risk <= 0 || reward < risk * 1.0) continue;
      
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if bearish pullback entry is allowed (breakdown retest sell)|
//+------------------------------------------------------------------+
bool IsBearishPullbackEntryAllowed(const IndicatorState &ind, double price, double atr,
                                    double &outSL, double &outTP)
{
   outSL = 0;
   outTP = 0;
   
   if(!g_breakout.valid) return false;
   
   for(int i = 0; i < g_breakout.bearCount; i++)
   {
      BreakoutLevel bo = g_breakout.bearBreakouts[i];
      if(!bo.valid) continue;
      if(bo.state != BREAKOUT_BEAR_PULLBACK && bo.state != BREAKOUT_BEAR_ENTRY) continue;
      
      // Price must be in the pullback zone
      if(!IsPriceInPullbackZone(price, bo, atr)) continue;
      
      // Must have bearish confirmation
      if(!HasBearishPullbackConfirmation(ind, bo, atr)) continue;
      
      // Set SL above the level and TP at next major support
      outSL = bo.levelHigh + atr * 0.35;
      outTP = FindNearestMajorSupportLevel(price, atr);
      if(outTP >= price || outTP <= 0) outTP = price - atr * 2.0;
      
      double risk = outSL - price;
      double reward = price - outTP;
      if(risk <= 0 || reward < risk * 1.0) continue;
      
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Live major support role: active major support OR flipped major   |
//| resistance that has been broken and confirmed as support         |
//+------------------------------------------------------------------+
bool IsLiveMajorSupportRole(const ZoneInfo &z)
{
   if(!z.valid || !z.active || z.historical || z.traded) return false;
   
   // Case 1: Active unbroken major support
   if(!z.broken && z.type == ZONE_SUPPORT_MAJOR)
      return true;
   
   // Case 2: Flipped zone - was RESISTANCE_MAJOR, now acting as SUPPORT_MAJOR
   // After flip: type = SUPPORT_MAJOR, originalType = RESISTANCE_MAJOR, broken = true
   // Require retest confirmation for high-quality entry
   if(z.isFlipZone && z.type == ZONE_SUPPORT_MAJOR && 
      z.originalType == ZONE_RESISTANCE_MAJOR)
   {
      // Confirmed retest: breakRetestReady + continuationEligible
      if(z.breakRetestReady && z.continuationEligible && !z.failedRetest)
         return true;
      
      // Alternative: zone has been touched after flip (retest count)
      if(z.retestCount >= 1 && !z.failedRetest)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Live major resistance role: active major resistance OR flipped   |
//| major support that has been broken and confirmed as resistance   |
//+------------------------------------------------------------------+
bool IsLiveMajorResistanceRole(const ZoneInfo &z)
{
   if(!z.valid || !z.active || z.historical || z.traded) return false;
   
   // Case 1: Active unbroken major resistance
   if(!z.broken && z.type == ZONE_RESISTANCE_MAJOR)
      return true;
   
   // Case 2: Flipped zone - was SUPPORT_MAJOR, now acting as RESISTANCE_MAJOR
   // After flip: type = RESISTANCE_MAJOR, originalType = SUPPORT_MAJOR, broken = true
   // Require retest confirmation for high-quality entry
   if(z.isFlipZone && z.type == ZONE_RESISTANCE_MAJOR && 
      z.originalType == ZONE_SUPPORT_MAJOR)
   {
      // Confirmed retest: breakRetestReady + continuationEligible
      if(z.breakRetestReady && z.continuationEligible && !z.failedRetest)
         return true;
      
      // Alternative: zone has been touched after flip (retest count)
      if(z.retestCount >= 1 && !z.failedRetest)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Range: unbroken major support only (no flips in range mode)      |
//+------------------------------------------------------------------+
bool IsLiveMajorRangeSupport(const ZoneInfo &z)
{
   if(!z.valid || !z.active || z.historical || z.traded || z.broken) return false;
   return (z.type == ZONE_SUPPORT_MAJOR);
}

//+------------------------------------------------------------------+
//| Range: unbroken major resistance only (no flips in range mode)   |
//+------------------------------------------------------------------+
bool IsLiveMajorRangeResistance(const ZoneInfo &z)
{
   if(!z.valid || !z.active || z.historical || z.traded || z.broken) return false;
   return (z.type == ZONE_RESISTANCE_MAJOR);
}

//+------------------------------------------------------------------+
//| Initialize Market Structure State                                |
//+------------------------------------------------------------------+
void InitMarketStructure()
{
   ZeroMemory(g_structure);
   g_structure.valid = false;
   g_structure.state = STRUCTURE_UNKNOWN;
   g_structure.swingHighCount = 0;
   g_structure.swingLowCount = 0;
}

//+------------------------------------------------------------------+
//| Detect Swing High at given bar index                             |
//| A swing high requires: high[i] > high[i-1] AND high[i] > high[i+1]|
//| Using lookback bars on each side for confirmation                |
//+------------------------------------------------------------------+
bool IsSwingHigh(const double &highArr[], int barIndex, int lookback = 3)
{
   if(barIndex < lookback || barIndex >= ArraySize(highArr) - lookback)
      return false;
   
   double centerHigh = highArr[barIndex];
   
   // Check left side (more recent bars)
   for(int i = 1; i <= lookback; i++)
   {
      if(highArr[barIndex - i] >= centerHigh)
         return false;
   }
   
   // Check right side (older bars)
   for(int i = 1; i <= lookback; i++)
   {
      if(highArr[barIndex + i] >= centerHigh)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Detect Swing Low at given bar index                              |
//+------------------------------------------------------------------+
bool IsSwingLow(const double &lowArr[], int barIndex, int lookback = 3)
{
   if(barIndex < lookback || barIndex >= ArraySize(lowArr) - lookback)
      return false;
   
   double centerLow = lowArr[barIndex];
   
   // Check left side (more recent bars)
   for(int i = 1; i <= lookback; i++)
   {
      if(lowArr[barIndex - i] <= centerLow)
         return false;
   }
   
   // Check right side (older bars)
   for(int i = 1; i <= lookback; i++)
   {
      if(lowArr[barIndex + i] <= centerLow)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Scan for swing points in price data                              |
//+------------------------------------------------------------------+
void ScanSwingPoints(const IndicatorState &ind, int maxBars = 200, int swingLookback = 3)
{
   g_structure.swingHighCount = 0;
   g_structure.swingLowCount = 0;
   
   // Scan for swing highs
   for(int i = swingLookback; i < maxBars - swingLookback && i < 200; i++)
   {
      if(IsSwingHigh(ind.highArr, i, swingLookback))
      {
         if(g_structure.swingHighCount < 10)
         {
            SwingPoint sp;
            sp.valid = true;
            sp.type = SWING_HIGH;
            sp.price = ind.highArr[i];
            sp.barIndex = i;
            sp.time = iTime(_Symbol, g_indicatorTF, i);
            sp.isHigherHigh = false;
            sp.isLowerHigh = false;
            sp.isHigherLow = false;
            sp.isLowerLow = false;
            
            g_structure.swingHighs[g_structure.swingHighCount] = sp;
            g_structure.swingHighCount++;
         }
      }
   }
   
   // Scan for swing lows
   for(int i = swingLookback; i < maxBars - swingLookback && i < 200; i++)
   {
      if(IsSwingLow(ind.lowArr, i, swingLookback))
      {
         if(g_structure.swingLowCount < 10)
         {
            SwingPoint sp;
            sp.valid = true;
            sp.type = SWING_LOW;
            sp.price = ind.lowArr[i];
            sp.barIndex = i;
            sp.time = iTime(_Symbol, g_indicatorTF, i);
            sp.isHigherHigh = false;
            sp.isLowerHigh = false;
            sp.isHigherLow = false;
            sp.isLowerLow = false;
            
            g_structure.swingLows[g_structure.swingLowCount] = sp;
            g_structure.swingLowCount++;
         }
      }
   }
   
   // Classify swing highs (HH vs LH)
   for(int i = 0; i < g_structure.swingHighCount - 1; i++)
   {
      double current = g_structure.swingHighs[i].price;
      double previous = g_structure.swingHighs[i + 1].price;
      
      g_structure.swingHighs[i].isHigherHigh = (current > previous);
      g_structure.swingHighs[i].isLowerHigh = (current < previous);
   }
   
   // Classify swing lows (HL vs LL)
   for(int i = 0; i < g_structure.swingLowCount - 1; i++)
   {
      double current = g_structure.swingLows[i].price;
      double previous = g_structure.swingLows[i + 1].price;
      
      g_structure.swingLows[i].isHigherLow = (current > previous);
      g_structure.swingLows[i].isLowerLow = (current < previous);
   }
}

//+------------------------------------------------------------------+
//| Count consecutive HH/HL/LH/LL sequences                          |
//+------------------------------------------------------------------+
void CountSwingSequences()
{
   g_structure.consecutiveHH = 0;
   g_structure.consecutiveHL = 0;
   g_structure.consecutiveLH = 0;
   g_structure.consecutiveLL = 0;
   
   // Count consecutive higher highs
   for(int i = 0; i < g_structure.swingHighCount; i++)
   {
      if(g_structure.swingHighs[i].isHigherHigh)
         g_structure.consecutiveHH++;
      else
         break;
   }
   
   // Count consecutive lower highs
   for(int i = 0; i < g_structure.swingHighCount; i++)
   {
      if(g_structure.swingHighs[i].isLowerHigh)
         g_structure.consecutiveLH++;
      else
         break;
   }
   
   // Count consecutive higher lows
   for(int i = 0; i < g_structure.swingLowCount; i++)
   {
      if(g_structure.swingLows[i].isHigherLow)
         g_structure.consecutiveHL++;
      else
         break;
   }
   
   // Count consecutive lower lows
   for(int i = 0; i < g_structure.swingLowCount; i++)
   {
      if(g_structure.swingLows[i].isLowerLow)
         g_structure.consecutiveLL++;
      else
         break;
   }
}

//+------------------------------------------------------------------+
//| Select bull trendline anchors from swing lows                    |
//+------------------------------------------------------------------+
bool SelectBullTrendlineAnchors(const IndicatorState &ind,
                                double atr,
                                int &olderBar, int &newerBar,
                                double &olderPrice, double &newerPrice,
                                int &confirmBar, double &confirmPrice)
{
   olderBar = newerBar = confirmBar = -1;
   olderPrice = newerPrice = confirmPrice = 0.0;

   if(g_structure.swingLowCount < 2)
      return false;

   double bestScore = -DBL_MAX;

   for(int i = 0; i < g_structure.swingLowCount; i++)
   {
      int barA = g_structure.swingLows[i].barIndex;
      double pxA = g_structure.swingLows[i].price;

      for(int j = i + 1; j < g_structure.swingLowCount; j++)
      {
         int barB = g_structure.swingLows[j].barIndex;
         double pxB = g_structure.swingLows[j].price;

         int older = MathMax(barA, barB);
         int newer = MathMin(barA, barB);

         double olderPx = (older == barA ? pxA : pxB);
         double newerPx = (newer == barA ? pxA : pxB);

         int spacing = older - newer;
         if(spacing < 5 || spacing > 120)
            continue;

         // Uptrend line must slope upward from older -> newer swing low (relaxed)
         if(newerPx <= olderPx)
            continue;

         double slope = (newerPx - olderPx) / (double)(newer - older);
         double intercept = olderPx - slope * older;

         int touchCount = 0;
         for(int k = 0; k < g_structure.swingLowCount; k++)
         {
            int b = g_structure.swingLows[k].barIndex;
            double p = g_structure.swingLows[k].price;
            double lineAtB = intercept + slope * b;
            if(MathAbs(p - lineAtB) <= atr * 0.30)
               touchCount++;
         }

         int bestHighBar = -1;
         double bestHighPrice = 0.0;
         for(int h = 0; h < g_structure.swingHighCount; h++)
         {
            int hb = g_structure.swingHighs[h].barIndex;
            double hp = g_structure.swingHighs[h].price;

            // confirming high should be between older anchor and current area
            if(hb > older || hb < 1)
               continue;

            double lineAtH = intercept + slope * hb;
            double clearance = hp - lineAtH;
            if(clearance >= atr * 0.50)
            {
               if(bestHighBar == -1 || hp > bestHighPrice)
               {
                  bestHighBar = hb;
                  bestHighPrice = hp;
               }
            }
         }

         // Allow lines without perfect confirming high if touchCount is good
         if(bestHighBar == -1 && touchCount < 2)
            continue;

         double score = 0.0;
         score += touchCount * 2.0;
         score += (newerPx - olderPx) / atr;
         score += MathMin(spacing / 10.0, 6.0);

         if(score > bestScore)
         {
            bestScore = score;
            olderBar = older;
            newerBar = newer;
            olderPrice = olderPx;
            newerPrice = newerPx;
            confirmBar = bestHighBar;
            confirmPrice = bestHighPrice;
         }
      }
   }

   return (olderBar > 0 && newerBar > 0 && confirmBar > 0);
}

//+------------------------------------------------------------------+
//| Select bear trendline anchors from swing highs                   |
//+------------------------------------------------------------------+
bool SelectBearTrendlineAnchors(const IndicatorState &ind,
                                double atr,
                                int &olderBar, int &newerBar,
                                double &olderPrice, double &newerPrice,
                                int &confirmBar, double &confirmPrice)
{
   olderBar = newerBar = confirmBar = -1;
   olderPrice = newerPrice = confirmPrice = 0.0;

   if(g_structure.swingHighCount < 2)
      return false;

   double bestScore = -DBL_MAX;

   for(int i = 0; i < g_structure.swingHighCount; i++)
   {
      int barA = g_structure.swingHighs[i].barIndex;
      double pxA = g_structure.swingHighs[i].price;

      for(int j = i + 1; j < g_structure.swingHighCount; j++)
      {
         int barB = g_structure.swingHighs[j].barIndex;
         double pxB = g_structure.swingHighs[j].price;

         int older = MathMax(barA, barB);
         int newer = MathMin(barA, barB);

         double olderPx = (older == barA ? pxA : pxB);
         double newerPx = (newer == barA ? pxA : pxB);

         int spacing = older - newer;
         if(spacing < 5 || spacing > 120)
            continue;

         // Downtrend line must slope downward from older -> newer swing high (relaxed)
         if(newerPx >= olderPx)
            continue;

         double slope = (newerPx - olderPx) / (double)(newer - older);
         double intercept = olderPx - slope * older;

         int touchCount = 0;
         for(int k = 0; k < g_structure.swingHighCount; k++)
         {
            int b = g_structure.swingHighs[k].barIndex;
            double p = g_structure.swingHighs[k].price;
            double lineAtB = intercept + slope * b;
            if(MathAbs(p - lineAtB) <= atr * 0.30)
               touchCount++;
         }

         int bestLowBar = -1;
         double bestLowPrice = 0.0;
         for(int l = 0; l < g_structure.swingLowCount; l++)
         {
            int lb = g_structure.swingLows[l].barIndex;
            double lp = g_structure.swingLows[l].price;

            if(lb > older || lb < 1)
               continue;

            double lineAtL = intercept + slope * lb;
            double clearance = lineAtL - lp;
            if(clearance >= atr * 0.50)
            {
               if(bestLowBar == -1 || lp < bestLowPrice)
               {
                  bestLowBar = lb;
                  bestLowPrice = lp;
               }
            }
         }

         // Allow lines without perfect confirming low if touchCount is good
         if(bestLowBar == -1 && touchCount < 2)
            continue;

         double score = 0.0;
         score += touchCount * 2.0;
         score += (olderPx - newerPx) / atr;
         score += MathMin(spacing / 10.0, 6.0);

         if(score > bestScore)
         {
            bestScore = score;
            olderBar = older;
            newerBar = newer;
            olderPrice = olderPx;
            newerPrice = newerPx;
            confirmBar = bestLowBar;
            confirmPrice = bestLowPrice;
         }
      }
   }

   return (olderBar > 0 && newerBar > 0 && confirmBar > 0);
}

//+------------------------------------------------------------------+
//| Estimate virtual width from trend line to opposite swings        |
//+------------------------------------------------------------------+
double EstimateTrendlineVirtualWidth(int trend,
                                     double slope,
                                     double intercept,
                                     double atr)
{
   double accum = 0.0;
   int count = 0;

   if(trend == 1)
   {
      for(int i = 0; i < g_structure.swingHighCount; i++)
      {
         int b = g_structure.swingHighs[i].barIndex;
         double p = g_structure.swingHighs[i].price;
         double lineAtB = intercept + slope * b;
         double d = p - lineAtB;
         if(d > atr * 0.50 && d < atr * 8.0)
         {
            accum += d;
            count++;
         }
      }
   }
   else if(trend == -1)
   {
      for(int i = 0; i < g_structure.swingLowCount; i++)
      {
         int b = g_structure.swingLows[i].barIndex;
         double p = g_structure.swingLows[i].price;
         double lineAtB = intercept + slope * b;
         double d = lineAtB - p;
         if(d > atr * 0.50 && d < atr * 8.0)
         {
            accum += d;
            count++;
         }
      }
   }

   if(count <= 0)
      return atr * 2.0;

   return MathMax(accum / count, atr * 1.8);
}

// REMOVED: BuildDiagonalChannel - channel building owned by ChannelBuilder

//+==================================================================+
//| SECTION 3: COMPATIBILITY & WRAPPER FUNCTIONS                    |
//| One-arg wrapper, deprecated helpers, forward-compat stubs        |
//+==================================================================+

//+------------------------------------------------------------------+
//| Compatibility wrapper: one-arg UpdateMarketStructure             |
//+------------------------------------------------------------------+
void UpdateMarketStructure(const IndicatorState &ind)
{
   double atr = GetATR(ind, 1);
   if(atr <= 0.0)
      return;

   UpdateMarketStructure(ind, atr, 3);
}

//+==================================================================+
//| SECTION 4: SWING POINT DETECTION                                |
//| Fractal-based HH/HL/LH/LL detection and classification           |
//+==================================================================+

//+------------------------------------------------------------------+
//| Detect swing points using fractal logic                           |
//+------------------------------------------------------------------+
void DetectSwingPoints(const IndicatorState &ind, double atr)
{
   // Reset swing counts
   g_structure.swingHighCount = 0;
   g_structure.swingLowCount = 0;
   
   // Simple fractal detection for now
   // This is a placeholder - more sophisticated detection can be added later
   for(int i = 2; i < 50 && i < ArraySize(ind.highArr); i++)
   {
      // Swing High detection
      if(ind.highArr[i] > ind.highArr[i-1] && ind.highArr[i] > ind.highArr[i+1])
      {
         if(g_structure.swingHighCount < 20)
         {
            g_structure.swingHighs[g_structure.swingHighCount].price = ind.highArr[i];
            g_structure.swingHighs[g_structure.swingHighCount].barIndex = i;
            g_structure.swingHighs[g_structure.swingHighCount].time = iTime(_Symbol, g_indicatorTF, i);
            g_structure.swingHighCount++;
         }
      }
      
      // Swing Low detection
      if(ind.lowArr[i] < ind.lowArr[i-1] && ind.lowArr[i] < ind.lowArr[i+1])
      {
         if(g_structure.swingLowCount < 20)
         {
            g_structure.swingLows[g_structure.swingLowCount].price = ind.lowArr[i];
            g_structure.swingLows[g_structure.swingLowCount].barIndex = i;
            g_structure.swingLows[g_structure.swingLowCount].time = iTime(_Symbol, g_indicatorTF, i);
            g_structure.swingLowCount++;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Get market trend from structure                                    |
//+------------------------------------------------------------------+
int GetMarketTrend(void)
{
   if(!g_structure.valid) return 0;
   
   switch(g_structure.state)
   {
      case STRUCTURE_BULL_TREND:
      case STRUCTURE_BIAS_BULL:
         return 1;  // Bull
         
      case STRUCTURE_BEAR_TREND:
      case STRUCTURE_BIAS_BEAR:
         return -1; // Bear
         
      default:
         return 0;  // Neutral
   }
}

//+------------------------------------------------------------------+
//| Determine structure state (simplified)                             |
//+------------------------------------------------------------------+
ENUM_STRUCTURE_STATE DetermineStructureState(const IndicatorState &ind, double atr)
{
   // Simple structure determination
   // This is a placeholder - the full logic is already in the file
   
   if(g_structure.consecutiveHH >= 2 && g_structure.consecutiveHL >= 2)
      return STRUCTURE_BULL_TREND;
      
   if(g_structure.consecutiveLH >= 2 && g_structure.consecutiveLL >= 2)
      return STRUCTURE_BEAR_TREND;
      
   if(g_structure.consecutiveHH >= 1 && g_structure.consecutiveHL >= 1)
      return STRUCTURE_BIAS_BULL;
      
   if(g_structure.consecutiveLH >= 1 && g_structure.consecutiveLL >= 1)
      return STRUCTURE_BIAS_BEAR;
      
   return STRUCTURE_RANGE;
}

//+------------------------------------------------------------------+
//| Classify market structure using STRUCTURE-FIRST SCORING          |
//| Priority: 1) Price Structure, 2) Channel, 3) EMA, 4) ADX         |
//+------------------------------------------------------------------+
ENUM_STRUCTURE_STATE ClassifyStructureFromSwings(const IndicatorState &ind, double atr)
{
   // ============================================================
   // STRUCTURE-FIRST CLASSIFICATION
   // Price structure (HH/HL, LL/LH) is PRIMARY
   // Indicators only FILTER/CONFIRM, never override clear structure
   // ============================================================
   
   // Reset transition flag each bar (only set true in RANGE block below)
   g_structure.rangeLikelyTransition = false;

   // --- Indicator context (for filtering only) ---
   double ema50     = GetEMA50(ind, 1);
   double ema200    = GetEMA200(ind, 1);
   double adx       = GetADX(ind, 1);
   double price     = ind.closeArr[1];
   
   // EMA spread and slope calculation
   double emaSpread = (ema50 > 0 && ema200 > 0) ? MathAbs(ema50 - ema200) : 0.0;
   double emaSpreadATR = (atr > 0) ? emaSpread / atr : 0.0;
   
   // EMA50 slope (approximate from recent bars)
   double ema50Slope = 0.0;
   if(ArraySize(ind.ema50) >= 6)
      ema50Slope = (ind.ema50[1] - ind.ema50[5]) / 4.0;
   double ema50SlopeATR = (atr > 0) ? ema50Slope / atr : 0.0;
   
   // Channel info
   bool chanValid   = g_structure.channel.valid;
   bool chanDirectional = chanValid && g_structure.channel.directionalValid;
   bool chanAscend  = chanDirectional && g_structure.channel.direction == +1;
   bool chanDescend = chanDirectional && g_structure.channel.direction == -1;
   double channelWidth = chanValid ? g_structure.channel.channelWidth : 0.0;
   double channelWidthATR = (atr > 0 && channelWidth > 0) ? channelWidth / atr : 0.0;
   
   // ============================================================
   // THRESHOLDS
   // ============================================================
   const double ADX_STRONG = 20.0;
   const double ADX_WEAK = 18.0;
   const double ADX_CONSOL = 15.0;
   const double EMA_SPREAD_COMPRESSED = 0.20;
   const double RANGE_WIDTH_NARROW = 1.0;
   
   // ============================================================
   // STRUCTURE-FIRST SCORE ACCUMULATORS
   // ============================================================
   int bullScore = 0;
   int bearScore = 0;
   int rangeScore = 0;
   int consolScore = 0;
   
   // --- Swing structure variables ---
   int HH = g_structure.consecutiveHH;
   int HL = g_structure.consecutiveHL;
   int LH = g_structure.consecutiveLH;
   int LL = g_structure.consecutiveLL;
   
   bool bullishStructure = (HH >= 1 && HL >= 1);
   bool bearishStructure = (LH >= 1 && LL >= 1);
   bool strongBullSequence = (HH >= 2 || HL >= 2) && bullishStructure;
   bool strongBearSequence = (LH >= 2 || LL >= 2) && bearishStructure;
   bool mixedStructure = (bullishStructure && bearishStructure) || 
                         (!bullishStructure && !bearishStructure);
   
   // EMA context (for filtering)
   bool emaBullSoft = (ema50 > ema200);
   bool emaBearSoft = (ema50 < ema200);
   bool emaSlopePositive = (ema50SlopeATR > 0.02);
   bool emaSlopeNegative = (ema50SlopeATR < -0.02);
   bool emaCompressed = (emaSpreadATR < EMA_SPREAD_COMPRESSED);
   bool emaStronglyOpposingBull = (ema50 < ema200 && emaSpreadATR > 0.40 && ema50SlopeATR < -0.10);
   bool emaStronglyOpposingBear = (ema50 > ema200 && emaSpreadATR > 0.40 && ema50SlopeATR > 0.10);
   
   // ============================================================
   // SCORE 1: PRICE STRUCTURE (PRIMARY - up to 6 points)
   // This is the DOMINANT factor
   // ============================================================
   
   // Bull structure scoring
   if(HH >= 1 && HL >= 1)
      bullScore += 3;  // Base bullish structure confirmed
   if(HH + HL >= 3)
      bullScore += 2;  // Extended sequence
   if(HL >= 2)
      bullScore += 1;  // Extra for consecutive higher lows
   
   // Bear structure scoring
   if(LL >= 1 && LH >= 1)
      bearScore += 3;  // Base bearish structure confirmed
   if(LL + LH >= 3)
      bearScore += 2;  // Extended sequence
   if(LH >= 2)
      bearScore += 1;  // Extra for consecutive lower highs
   
   // Range/mixed structure scoring
   if(mixedStructure)
      rangeScore += 3;
   if(!bullishStructure && !bearishStructure)
      rangeScore += 2;  // Neither structure complete
   
   // ============================================================
   // SCORE 2: CHANNEL DIRECTION (SECONDARY - up to 2 points)
   // Supports structure, does not override it
   // ============================================================
   if(chanAscend)
      bullScore += 1;  // Channel supports bull structure
   
   if(chanDescend)
      bearScore += 1;  // Channel supports bear structure
   
   if(!chanDirectional)
      rangeScore += 1;  // No directional channel
   
   // ============================================================
   // SCORE 3: EMA ALIGNMENT (TERTIARY - up to 2 points)
   // Confirms quality, does not determine direction
   // ============================================================
   if(emaBullSoft)
      bullScore += 1;
   if(emaSlopePositive)
      bullScore += 1;
   
   if(emaBearSoft)
      bearScore += 1;
   if(emaSlopeNegative)
      bearScore += 1;
   
   if(emaCompressed)
   {
      rangeScore += 1;
      consolScore += 1;
   }
   
   // ============================================================
   // SCORE 4: ADX STRENGTH (LAST - up to 1 point)
   // Confirms strength, does not determine direction
   // ============================================================
   if(adx >= ADX_STRONG)
   {
      // ADX only adds to the side that already has structure
      if(bullishStructure && bullScore > bearScore)
         bullScore += 1;
      else if(bearishStructure && bearScore > bullScore)
         bearScore += 1;
   }
   
   if(adx < ADX_WEAK)
      rangeScore += 1;
   
   if(adx < ADX_CONSOL)
      consolScore += 2;
   
   // ============================================================
   // CONSOLIDATION SCORING
   // ============================================================
   if(emaCompressed && emaSpreadATR < EMA_SPREAD_COMPRESSED)
      consolScore += 2;
   
   if(channelWidthATR > 0 && channelWidthATR < RANGE_WIDTH_NARROW)
      consolScore += 2;
   
   // ============================================================
   // LOGGING
   // ============================================================
   Print("[STRUCTURE_SCORE] bull=", bullScore, " bear=", bearScore, 
         " range=", rangeScore, " consol=", consolScore,
         " HH=", HH, " HL=", HL, " LH=", LH, " LL=", LL,
         " adx=", DoubleToString(adx, 1),
         " emaSpreadATR=", DoubleToString(emaSpreadATR, 2),
         " chanDir=", g_structure.channel.direction);
   
   // --- Transition hint: flag when range looks too directional ---
   if(rangeScore >= bullScore && rangeScore >= bearScore)
   {
      double hintWidthATR = channelWidthATR;
      if(hintWidthATR <= 0.0 && atr > 0.0)
         hintWidthATR = RecentRangeWidth(ind, 20) / atr;

      bool transitionHint = (hintWidthATR > 3.0 && adx > 21.0) ||
                            (hintWidthATR > 2.5 && adx > 26.0);
      if(transitionHint)
         Print("[STRUCTURE_TRANSITION_HINT] widthATR=", DoubleToString(hintWidthATR, 2),
               " adx=", DoubleToString(adx, 1),
               " range_may_be_transition=true");
   }
   
   // ============================================================
   // CLASSIFICATION DECISION - STRUCTURE DOMINATES
   // ============================================================
   
   // --- A) BULL TREND ---
   // Requires: HH >= 1 AND HL >= 1, bullScore >= bearScore + 2, bullScore >= rangeScore + 1
   // EMA must not strongly oppose
   if(bullishStructure &&
      bullScore >= bearScore + 2 &&
      bullScore >= rangeScore + 1 &&
      !emaStronglyOpposingBull)
   {
      Print("[STRUCTURE_DECISION] state=BULL_TREND reason=structure_confirmed",
            " bullScore=", bullScore, " bearScore=", bearScore, " rangeScore=", rangeScore);
      g_structure.biasChangeDetected = false;
      return STRUCTURE_BULL_TREND;
   }
   
   // --- B) BEAR TREND ---
   // Requires: LL >= 1 AND LH >= 1, bearScore >= bullScore + 2, bearScore >= rangeScore + 1
   // EMA must not strongly oppose
   if(bearishStructure &&
      bearScore >= bullScore + 2 &&
      bearScore >= rangeScore + 1 &&
      !emaStronglyOpposingBear)
   {
      Print("[STRUCTURE_DECISION] state=BEAR_TREND reason=structure_confirmed",
            " bearScore=", bearScore, " bullScore=", bullScore, " rangeScore=", rangeScore);
      g_structure.biasChangeDetected = false;
      return STRUCTURE_BEAR_TREND;
   }
   
   // --- RANGE PRE-CHECK ---
   double hintWidthATR = channelWidthATR;
   if(hintWidthATR <= 0.0 && atr > 0.0)
      hintWidthATR = RecentRangeWidth(ind, 20) / atr;

   bool rqMixed    = ((HH > 0 || HL > 0) && (LH > 0 || LL > 0));
   bool rqAdxOk    = (adx <= 24.0);
   bool rqNeutral  = (!chanDirectional || g_structure.channel.direction == 0);
   bool rqEmaOk    = (emaSpreadATR <= 1.8);
   bool rqWidthOk  = (hintWidthATR >= 1.5 && hintWidthATR <= 5.5);

   int rqScore = (rqMixed ? 1 : 0) +
                 (rqAdxOk ? 1 : 0) +
                 (rqNeutral ? 1 : 0) +
                 (rqEmaOk ? 1 : 0) +
                 (rqWidthOk ? 1 : 0);

   double rangeQualityNow = rqScore * 2.0;
   if(rqMixed && (HH > 0 && HL > 0 && LH > 0 && LL > 0)) rangeQualityNow += 1.0;
   if(adx < 18.0) rangeQualityNow += 0.5;
   if(rqWidthOk && hintWidthATR >= 2.0 && hintWidthATR <= 4.5) rangeQualityNow += 0.5;
   rangeQualityNow = MathMin(rangeQualityNow, 10.0);

   bool rangeLikelyTransitionNow = (chanDirectional && adx > 23.0) ||
                                   (g_structure.recentChannelBroken && rqMixed && adx > 21.0);

   string transReason = "none";
   if(chanDirectional && adx > 23.0)
      transReason = "chan_directional_and_adx_high";
   else if(g_structure.recentChannelBroken && rqMixed && adx > 21.0)
      transReason = "broken_channel_mixed_swings";

   g_structure.rangeQuality          = rangeQualityNow;
   g_structure.rangeLikelyTransition = rangeLikelyTransitionNow;

   Print("[RANGE_QUALITY] score=", DoubleToString(rangeQualityNow, 1),
         " mixed=", rqMixed,
         " adxOk=", rqAdxOk,
         " neutral=", rqNeutral,
         " widthOk=", rqWidthOk,
         " emaOk=", rqEmaOk,
         " adx=", DoubleToString(adx, 1));

   Print("[RANGE_TRANSITION_FILTER] transition=", rangeLikelyTransitionNow,
         " reason=", transReason,
         " adx=", DoubleToString(adx, 1),
         " chanDir=", g_structure.channel.direction,
         " recentBroken=", g_structure.recentChannelBroken);

   bool preferRangeNow =
      (rqScore >= 4 &&
       rqMixed &&
       rqWidthOk &&
       (rqNeutral || g_structure.recentChannelBroken) &&
       adx <= 26.5);
   
   // --- C) BULL BIAS ---
   // Bullish structure partial OR channel/EMA support bullish side
   // Strong structure + weak ADX => BIAS, not RANGE
   if(!preferRangeNow && bullishStructure && !bearishStructure)
   {
      // Structure exists but not enough for full trend
      Print("[STRUCTURE_DECISION] state=BIAS_BULL reason=partial_structure",
            " bullScore=", bullScore, " bearScore=", bearScore, " rangeScore=", rangeScore);
      return STRUCTURE_BIAS_BULL;
   }
   
   if(!preferRangeNow &&
      !bullishStructure && !bearishStructure &&
      (chanAscend || (emaBullSoft && emaSlopePositive)) &&
      (HH >= 1 || HL >= 1) &&
      bullScore > bearScore)
   {
      // Partial swings + channel/EMA support
      Print("[STRUCTURE_DECISION] state=BIAS_BULL reason=partial_swings_with_support",
            " HH=", HH, " HL=", HL, " chanAscend=", chanAscend);
      return STRUCTURE_BIAS_BULL;
   }
   
   // --- D) BEAR BIAS ---
   // Bearish structure partial OR channel/EMA support bearish side
   // Strong structure + weak ADX => BIAS, not RANGE
   if(!preferRangeNow && bearishStructure && !bullishStructure)
   {
      // Structure exists but not enough for full trend
      Print("[STRUCTURE_DECISION] state=BIAS_BEAR reason=partial_structure",
            " bearScore=", bearScore, " bullScore=", bullScore, " rangeScore=", rangeScore);
      return STRUCTURE_BIAS_BEAR;
   }
   
   if(!preferRangeNow &&
      !bullishStructure && !bearishStructure &&
      (chanDescend || (emaBearSoft && emaSlopeNegative)) &&
      (LH >= 1 || LL >= 1) &&
      bearScore > bullScore)
   {
      // Partial swings + channel/EMA support
      Print("[STRUCTURE_DECISION] state=BIAS_BEAR reason=partial_swings_with_support",
            " LH=", LH, " LL=", LL, " chanDescend=", chanDescend);
      return STRUCTURE_BIAS_BEAR;
   }
   
   // --- STRUCTURE DOMINANCE RULES ---
   // If HH+HL clearly exists, EMA/ADX may downgrade to BIAS but NOT force RANGE
   if(!preferRangeNow && bullishStructure && rangeScore > bullScore)
   {
      Print("[STRUCTURE_DECISION] state=BIAS_BULL reason=structure_dominates_range_score",
            " bullScore=", bullScore, " rangeScore=", rangeScore);
      return STRUCTURE_BIAS_BULL;
   }
   
   // If LL+LH clearly exists, EMA/ADX may downgrade to BIAS but NOT force RANGE
   if(!preferRangeNow && bearishStructure && rangeScore > bearScore)
   {
      Print("[STRUCTURE_DECISION] state=BIAS_BEAR reason=structure_dominates_range_score",
            " bearScore=", bearScore, " rangeScore=", rangeScore);
      return STRUCTURE_BIAS_BEAR;
   }
   
   // --- F) CONSOLIDATION ---
   // ADX very weak + EMA compressed + tight range
   if(consolScore >= 4 && adx < ADX_CONSOL && emaCompressed)
   {
      Print("[STRUCTURE_DECISION] state=CONSOLIDATION reason=compressed_range",
            " consolScore=", consolScore, " adx=", DoubleToString(adx, 1),
            " emaSpreadATR=", DoubleToString(emaSpreadATR, 2));
      return STRUCTURE_CONSOLIDATION;
   }
   
   // --- BIAS CHANGE DETECTION ---
   ENUM_STRUCTURE_STATE prevState = g_structure.state;

   if(prevState == STRUCTURE_BULL_TREND || prevState == STRUCTURE_BIAS_BULL)
   {
      if(bearishStructure && bearScore > bullScore)
      {
         Print("[STRUCTURE_DECISION] state=BIAS_BEAR reason=bias_change_from_bull");
         g_structure.biasChangeDetected = true;
         g_structure.biasChangeBullish  = false;
         return STRUCTURE_BIAS_BEAR;
      }
   }
   if(prevState == STRUCTURE_BEAR_TREND || prevState == STRUCTURE_BIAS_BEAR)
   {
      if(bullishStructure && bullScore > bearScore)
      {
         Print("[STRUCTURE_DECISION] state=BIAS_BULL reason=bias_change_from_bear");
         g_structure.biasChangeDetected = true;
         g_structure.biasChangeBullish  = true;
         return STRUCTURE_BIAS_BULL;
      }
   }

   // --- BIAS PERSISTENCE ---
   // Hold existing bias if structure still partially supports it
   if(!preferRangeNow &&
      prevState == STRUCTURE_BIAS_BULL &&
      (HH >= 1 || HL >= 1) &&
      bullScore >= bearScore)
   {
      Print("[STRUCTURE_DECISION] state=BIAS_BULL reason=bias_persistence",
            " HH=", HH, " HL=", HL);
      return STRUCTURE_BIAS_BULL;
   }

   if(!preferRangeNow &&
      prevState == STRUCTURE_BIAS_BEAR &&
      (LH >= 1 || LL >= 1) &&
      bearScore >= bullScore)
   {
      Print("[STRUCTURE_DECISION] state=BIAS_BEAR reason=bias_persistence",
            " LH=", LH, " LL=", LL);
      return STRUCTURE_BIAS_BEAR;
   }

   // --- E) RANGE ---
   if(rqScore < 3)
   {
      bool bullSide = (ema50 >= ema200 || bullScore > bearScore || (HH > 0 || HL > 0));
      ENUM_STRUCTURE_STATE downgrade = bullSide ? STRUCTURE_BIAS_BULL : STRUCTURE_BIAS_BEAR;
      Print("[STRUCTURE_DECISION] state=", (bullSide ? "BIAS_BULL" : "BIAS_BEAR"),
            " reason=range_qualification_failed rqScore=", rqScore,
            " bullScore=", bullScore,
            " bearScore=", bearScore);
      return downgrade;
   }

   Print("[STRUCTURE_DECISION] state=RANGE reason=mixed_or_no_structure",
         " bullScore=", bullScore,
         " bearScore=", bearScore,
         " rangeScore=", rangeScore,
         " HH=", HH,
         " HL=", HL,
         " LH=", LH,
         " LL=", LL);
   return STRUCTURE_RANGE;
}

//+------------------------------------------------------------------+
//| Optional EMA confirmation for structure                          |
//+------------------------------------------------------------------+
bool ConfirmBullTrendWithEMA(const IndicatorState &ind)
{
   double ema50 = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   double price = ind.closeArr[1];
   
   if(ema50 <= 0 || ema200 <= 0) return false;
   
   // Bull confirmation: price > EMA50 > EMA200
   return (price > ema50 && ema50 > ema200);
}

bool ConfirmBearTrendWithEMA(const IndicatorState &ind)
{
   double ema50 = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   double price = ind.closeArr[1];
   
   if(ema50 <= 0 || ema200 <= 0) return false;
   
   // Bear confirmation: price < EMA50 < EMA200
   return (price < ema50 && ema50 < ema200);
}

//+==================================================================+
//| SECTION 5: MAIN STRUCTURE UPDATE (call each bar)                |
//| Full structure refresh: swings, channels, bias, S/R levels       |
//+==================================================================+

//+------------------------------------------------------------------+
//| Main structure update function - call each bar                   |
//+------------------------------------------------------------------+
void UpdateMarketStructure(const IndicatorState &ind, double atr, int swingLookback = 3)
{
   // Clear bias change flag at start of each update cycle
   g_structure.biasChangeDetected = false;
   
   // Scan for swing points
   ScanSwingPoints(ind, 200, swingLookback);
   
   // Count sequences
   CountSwingSequences();
   
   // Channel code removed per user request
   
   // Sync legacy g_structure.channel from registry for backward compatibility
   SyncStructureChannelFromRegistry(ind, atr);
   
   // Capture old state before classifying new state
   ENUM_STRUCTURE_STATE prevState = g_structure.state;
   
   // Classify structure (may set biasChangeDetected = true for current bar)
   ENUM_STRUCTURE_STATE newState = ClassifyStructureFromSwings(ind, atr);
   
   // --- TREND PERSISTENCE: prevent immediate TREND->RANGE drop ---
   // Update persistence memory when confirmed trend detected
   if(newState == STRUCTURE_BULL_TREND)
   {
      g_lastConfirmedTrendDir = +1;
      g_trendPersistenceBars  = 3;
   }
   else if(newState == STRUCTURE_BEAR_TREND)
   {
      g_lastConfirmedTrendDir = -1;
      g_trendPersistenceBars  = 3;
   }
   
   // If weakening from TREND to RANGE but EMA stack still agrees and ADX >= 18,
   // hold BIAS in same direction instead of immediate RANGE
   if(newState == STRUCTURE_RANGE && g_trendPersistenceBars > 0 && g_lastConfirmedTrendDir != 0)
   {
      bool keepDetectedRange =
         (g_structure.rangeQuality >= 8.0) ||
         g_structure.rangeLikelyTransition ||
         g_structure.recentChannelBroken;

      if(keepDetectedRange)
      {
         Print("[TREND_PERSISTENCE_SKIP] reason=strong_range_detected",
               " quality=", DoubleToString(g_structure.rangeQuality, 1),
               " transition=", g_structure.rangeLikelyTransition,
               " recentBroken=", g_structure.recentChannelBroken);
         g_trendPersistenceBars = 0;
         g_lastConfirmedTrendDir = 0;
      }
      else
      {
         double ema50P  = GetEMA50(ind, 1);
         double ema200P = GetEMA200(ind, 1);
         double adxP    = GetADX(ind, 1);
         bool emaAgreesP = (g_lastConfirmedTrendDir == +1) ? (ema50P > ema200P) : (ema50P < ema200P);

         if(emaAgreesP && adxP >= 18.0)
         {
            if(g_lastConfirmedTrendDir == +1)
            {
               newState = STRUCTURE_BIAS_BULL;
               Print("[TREND_PERSISTENCE] previous=BULL fallback=BIAS_BULL barsLeft=", g_trendPersistenceBars);
            }
            else
            {
               newState = STRUCTURE_BIAS_BEAR;
               Print("[TREND_PERSISTENCE] previous=BEAR fallback=BIAS_BEAR barsLeft=", g_trendPersistenceBars);
            }
            g_trendPersistenceBars--;
         }
         else
         {
            g_trendPersistenceBars = 0;
            g_lastConfirmedTrendDir = 0;
         }
      }
   }
   else if(newState != STRUCTURE_RANGE)
   {
      // Any non-range state that isn't the original trend resets persistence
      if(newState != STRUCTURE_BULL_TREND && newState != STRUCTURE_BEAR_TREND &&
         newState != STRUCTURE_BIAS_BULL  && newState != STRUCTURE_BIAS_BEAR)
      {
         g_trendPersistenceBars = 0;
         g_lastConfirmedTrendDir = 0;
      }
   }
   
   // Reset barsInCurrentState when state changes
   if(newState != prevState)
      g_structure.barsInCurrentState = 0;
   
   // Assign new state
   g_structure.state = newState;
   g_structure.valid = true;
   
   // Increment only after state is assigned
   g_structure.barsInCurrentState++;
   
   // Channel drawing owned by ChannelBuilder (DrawH4VisualChannel called from MY BOT.mq5)
   
   string oldStr = StructureStateToString(prevState);
   string newStr = StructureStateToString(newState);
   
   Print("[STRUCTURE_STATE] old=", oldStr,
         " new=", newStr,
         " bars=", g_structure.barsInCurrentState,
         " biasChange=", g_structure.biasChangeDetected,
         " biasChangeBull=", g_structure.biasChangeBullish);
   
   Print("[MARKET_STRUCTURE] state=", newStr,
         " swingHighs=", g_structure.swingHighCount,
         " swingLows=", g_structure.swingLowCount,
         " HH=", g_structure.consecutiveHH,
         " HL=", g_structure.consecutiveHL,
         " LH=", g_structure.consecutiveLH,
         " LL=", g_structure.consecutiveLL,
         " dynSupport=", DoubleToString(g_structure.dynamicSupport, _Digits),
         " dynResist=", DoubleToString(g_structure.dynamicResistance, _Digits));
}

//+------------------------------------------------------------------+
//| Check if price is near dynamic channel support                   |
//+------------------------------------------------------------------+
bool IsNearDynamicChannelSupport(double price, double atr, double tolerance = 0.60)
{
   if(atr <= 0.0) return false;
   if(!g_structure.channel.valid || !g_structure.channel.directionalValid) return false;
   if(g_structure.channel.direction != +1) return false;
   if(g_structure.state != STRUCTURE_BULL_TREND && g_structure.state != STRUCTURE_BIAS_BULL) return false;
   if(g_structure.dynamicSupport <= 0.0) return false;

   double dist    = MathAbs(price - g_structure.dynamicSupport);
   double distATR = dist / atr;
   bool   near    = (distATR <= tolerance);

   Print("[DYNAMIC_CHANNEL_PROXIMITY] side=BUY near=", near,
         " distATR=", DoubleToString(distATR, 2),
         " support=", DoubleToString(g_structure.dynamicSupport, _Digits));
   return near;
}

//+------------------------------------------------------------------+
//| Check if price is near dynamic channel resistance                |
//+------------------------------------------------------------------+
bool IsNearDynamicChannelResistance(double price, double atr, double tolerance = 0.60)
{
   if(atr <= 0.0) return false;
   if(!g_structure.channel.valid || !g_structure.channel.directionalValid) return false;
   if(g_structure.channel.direction != -1) return false;
   if(g_structure.state != STRUCTURE_BEAR_TREND && g_structure.state != STRUCTURE_BIAS_BEAR) return false;
   if(g_structure.dynamicResistance <= 0.0) return false;

   double dist    = MathAbs(price - g_structure.dynamicResistance);
   double distATR = dist / atr;
   bool   near    = (distATR <= tolerance);

   Print("[DYNAMIC_CHANNEL_PROXIMITY] side=SELL near=", near,
         " distATR=", DoubleToString(distATR, 2),
         " resistance=", DoubleToString(g_structure.dynamicResistance, _Digits));
   return near;
}

//+------------------------------------------------------------------+
//| Dynamic Zone Band Structure                                       |
//+------------------------------------------------------------------+
struct DynamicZoneBand
{
   bool   valid;
   int    side;        // +1 = bull support, -1 = bear resistance
   double mid;         // Zone midpoint (dynamicSupport or dynamicResistance)
   double low;         // Zone lower edge
   double high;        // Zone upper edge
   double width;       // Zone width in price
};

//+------------------------------------------------------------------+
//| Get Bull Dynamic Support Zone Band                                |
//+------------------------------------------------------------------+
DynamicZoneBand GetBullDynamicZoneBand(double atr, double bandATR = 0.35)
{
   DynamicZoneBand zone;
   zone.valid = false;
   zone.side  = +1;
   zone.mid   = 0.0;
   zone.low   = 0.0;
   zone.high  = 0.0;
   zone.width = 0.0;
   
   if(!g_structure.valid || !g_structure.channel.valid)
      return zone;
   // Only ACTIVE channels can be used for trading
   if(g_structure.channel.state != CHANNEL_STATE_ACTIVE)
      return zone;
   if(!g_structure.channel.directionalValid || g_structure.channel.direction != +1)
      return zone;
   if(g_structure.dynamicSupport <= 0.0)
      return zone;
   
   zone.valid = true;
   zone.mid   = g_structure.dynamicSupport;
   zone.low   = zone.mid - atr * bandATR;
   zone.high  = zone.mid + atr * bandATR;
   zone.width = zone.high - zone.low;
   
   // Logging moved to caller to reduce spam
   return zone;
}

//+------------------------------------------------------------------+
//| Get Bear Dynamic Resistance Zone Band                             |
//+------------------------------------------------------------------+
DynamicZoneBand GetBearDynamicZoneBand(double atr, double bandATR = 0.35)
{
   DynamicZoneBand zone;
   zone.valid = false;
   zone.side  = -1;
   zone.mid   = 0.0;
   zone.low   = 0.0;
   zone.high  = 0.0;
   zone.width = 0.0;
   
   if(!g_structure.valid || !g_structure.channel.valid)
      return zone;
   // Only ACTIVE channels can be used for trading
   if(g_structure.channel.state != CHANNEL_STATE_ACTIVE)
      return zone;
   if(!g_structure.channel.directionalValid || g_structure.channel.direction != -1)
      return zone;
   if(g_structure.dynamicResistance <= 0.0)
      return zone;
   
   zone.valid = true;
   zone.mid   = g_structure.dynamicResistance;
   zone.low   = zone.mid - atr * bandATR;
   zone.high  = zone.mid + atr * bandATR;
   zone.width = zone.high - zone.low;
   
   // Logging moved to caller to reduce spam
   return zone;
}

//+------------------------------------------------------------------+
//| Check if price is within dynamic zone band                        |
//+------------------------------------------------------------------+
bool IsPriceInDynamicZoneBand(double price, const DynamicZoneBand &zone)
{
   if(!zone.valid) return false;
   return (price >= zone.low && price <= zone.high);
}

//+------------------------------------------------------------------+
//| Check if price is retesting dynamic zone band                     |
//+------------------------------------------------------------------+
bool IsPriceRetestingDynamicZone(double price, const DynamicZoneBand &zone, double atr)
{
   if(!zone.valid) return false;
   
   // For bull zone (support): price should be near or within zone from above
   if(zone.side == +1)
   {
      double tolerance = atr * 0.15;
      return (price >= zone.low - tolerance && price <= zone.high + tolerance);
   }
   // For bear zone (resistance): price should be near or within zone from below
   else if(zone.side == -1)
   {
      double tolerance = atr * 0.15;
      return (price >= zone.low - tolerance && price <= zone.high + tolerance);
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Trend End Detection - Bull Trend                                  |
//| Returns number of votes (0-4) toward trend ending                 |
//+------------------------------------------------------------------+
int CheckBullTrendEndVotes(const IndicatorState &ind, double atr, 
                           const DynamicZoneBand &zone, int confirmBars, double adxFloor)
{
   int votes = 0;
   
   // Vote 1: Structure flipped to bearish
   if(g_structure.state == STRUCTURE_BEAR_TREND || g_structure.state == STRUCTURE_BIAS_BEAR)
   {
      votes++;
      Print("[TREND_END_VOTE] side=BUY vote=1 reason=structure_bearish");
   }
   
   // Vote 2: Directional channel invalid or bear channel took over
   if(!g_structure.channel.directionalValid || 
      (g_structure.channel.directionalValid && g_structure.channel.direction == -1))
   {
      votes++;
      Print("[TREND_END_VOTE] side=BUY vote=2 reason=channel_invalid_or_bear");
   }
   
   // Vote 3: Price broke below dynamic support band for confirmBars consecutive bars
   // This is tracked externally via barsBreakingZone counter
   
   // Vote 4: EMA50 sloping down + price below EMA50 + ADX < floor
   double ema50 = GetEMA50(ind, 1);
   double ema50Prev = (ArraySize(ind.ema50) >= 6) ? ind.ema50[5] : ema50;
   double ema50Slope = ema50 - ema50Prev;
   double adx = GetADX(ind, 1);
   double close = ind.closeArr[1];
   
   if(ema50Slope < 0 && close < ema50 && adx < adxFloor)
   {
      votes++;
      Print("[TREND_END_VOTE] side=BUY vote=4 reason=ema50_down_price_below_adx_low",
            " ema50Slope=", DoubleToString(ema50Slope, _Digits),
            " close=", DoubleToString(close, _Digits),
            " ema50=", DoubleToString(ema50, _Digits),
            " adx=", DoubleToString(adx, 1));
   }
   
   return votes;
}

//+------------------------------------------------------------------+
//| Trend End Detection - Bear Trend                                  |
//| Returns number of votes (0-4) toward trend ending                 |
//+------------------------------------------------------------------+
int CheckBearTrendEndVotes(const IndicatorState &ind, double atr,
                           const DynamicZoneBand &zone, int confirmBars, double adxFloor)
{
   int votes = 0;
   
   // Vote 1: Structure flipped to bullish
   if(g_structure.state == STRUCTURE_BULL_TREND || g_structure.state == STRUCTURE_BIAS_BULL)
   {
      votes++;
      Print("[TREND_END_VOTE] side=SELL vote=1 reason=structure_bullish");
   }
   
   // Vote 2: Directional channel invalid or bull channel took over
   if(!g_structure.channel.directionalValid || 
      (g_structure.channel.directionalValid && g_structure.channel.direction == +1))
   {
      votes++;
      Print("[TREND_END_VOTE] side=SELL vote=2 reason=channel_invalid_or_bull");
   }
   
   // Vote 3: Price broke above dynamic resistance band for confirmBars consecutive bars
   // This is tracked externally via barsBreakingZone counter
   
   // Vote 4: EMA50 sloping up + price above EMA50 + ADX < floor
   double ema50 = GetEMA50(ind, 1);
   double ema50Prev = (ArraySize(ind.ema50) >= 6) ? ind.ema50[5] : ema50;
   double ema50Slope = ema50 - ema50Prev;
   double adx = GetADX(ind, 1);
   double close = ind.closeArr[1];
   
   if(ema50Slope > 0 && close > ema50 && adx < adxFloor)
   {
      votes++;
      Print("[TREND_END_VOTE] side=SELL vote=4 reason=ema50_up_price_above_adx_low",
            " ema50Slope=", DoubleToString(ema50Slope, _Digits),
            " close=", DoubleToString(close, _Digits),
            " ema50=", DoubleToString(ema50, _Digits),
            " adx=", DoubleToString(adx, 1));
   }
   
   return votes;
}

//+------------------------------------------------------------------+
//| Check if bull trend has ended (>= 2 votes)                        |
//+------------------------------------------------------------------+
bool IsBullTrendEnded(const IndicatorState &ind, double atr, 
                      const DynamicZoneBand &zone, int barsBreakingZone,
                      int confirmBars, double adxFloor)
{
   int votes = CheckBullTrendEndVotes(ind, atr, zone, confirmBars, adxFloor);
   
   // Add vote 3 if price broke below zone for confirmBars
   if(barsBreakingZone >= confirmBars)
   {
      votes++;
      Print("[TREND_END_VOTE] side=BUY vote=3 reason=broke_below_zone bars=", barsBreakingZone);
   }
   
   bool ended = (votes >= 2);
   Print("[TREND_END_CHECK] side=BUY votes=", votes, " ended=", ended);
   return ended;
}

//+------------------------------------------------------------------+
//| Check if bear trend has ended (>= 2 votes)                        |
//+------------------------------------------------------------------+
bool IsBearTrendEnded(const IndicatorState &ind, double atr,
                      const DynamicZoneBand &zone, int barsBreakingZone,
                      int confirmBars, double adxFloor)
{
   int votes = CheckBearTrendEndVotes(ind, atr, zone, confirmBars, adxFloor);
   
   // Add vote 3 if price broke above zone for confirmBars
   if(barsBreakingZone >= confirmBars)
   {
      votes++;
      Print("[TREND_END_VOTE] side=SELL vote=3 reason=broke_above_zone bars=", barsBreakingZone);
   }
   
   bool ended = (votes >= 2);
   Print("[TREND_END_CHECK] side=SELL votes=", votes, " ended=", ended);
   return ended;
}

//+------------------------------------------------------------------+
//| Get structure state as string                                    |
//+------------------------------------------------------------------+
string StructureStateToString(ENUM_STRUCTURE_STATE state)
{
   switch(state)
   {
      case STRUCTURE_BULL_TREND: return "BULL_TREND";
      case STRUCTURE_BEAR_TREND: return "BEAR_TREND";
      case STRUCTURE_RANGE:           return "RANGE";
      case STRUCTURE_BIAS_BULL:        return "BIAS_BULL";
      case STRUCTURE_BIAS_BEAR:        return "BIAS_BEAR";
      case STRUCTURE_CONSOLIDATION:    return "CONSOLIDATION";
      default:                         return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| Check if structure allows buy entry                              |
//| In trends: channel support + major zones + flips                 |
//| In ranges: horizontal major support only                         |
//+------------------------------------------------------------------+
bool StructureAllowsBuy(double price, double atr)
{
   if(!g_structure.valid) return true; // Fallback to old logic
   
   switch(g_structure.state)
   {
      case STRUCTURE_BULL_TREND:
      case STRUCTURE_BIAS_BULL:
         // Bull trend: allow buy at channel support or major horizontal support/flip
         // Do NOT sell in bull trend (handled separately)
         return true;
         
      case STRUCTURE_BEAR_TREND:
      case STRUCTURE_BIAS_BEAR:
         // Bear trend: do NOT buy unless bias change confirmed
         Print("[STRUCTURE_FILTER] BUY blocked - bear trend active");
         return false;
         
      case STRUCTURE_RANGE:
         // Range: allow buy at major horizontal support only
         return true;

      case STRUCTURE_CONSOLIDATION:
         // Tight consolidation: no internal trades, breakout/retest only
         Print("[STRUCTURE_FILTER] BUY blocked - consolidation active (no internal trades)");
         return false;
         
      default:
         return true;
   }
}

//+------------------------------------------------------------------+
//| Check if structure allows sell entry                             |
//+------------------------------------------------------------------+
bool StructureAllowsSell(double price, double atr)
{
   if(!g_structure.valid) return true; // Fallback to old logic
   
   switch(g_structure.state)
   {
      case STRUCTURE_BEAR_TREND:
      case STRUCTURE_BIAS_BEAR:
         // Bear trend: allow sell at channel resistance or major horizontal resistance/flip
         return true;
         
      case STRUCTURE_BULL_TREND:
      case STRUCTURE_BIAS_BULL:
         // Bull trend: do NOT sell unless bias change confirmed
         Print("[STRUCTURE_FILTER] SELL blocked - bull trend active");
         return false;
         
      case STRUCTURE_RANGE:
         // Range: allow sell at major horizontal resistance only
         return true;

      case STRUCTURE_CONSOLIDATION:
         // Tight consolidation: no internal trades, breakout/retest only
         Print("[STRUCTURE_FILTER] SELL blocked - consolidation active (no internal trades)");
         return false;
         
      default:
         return true;
   }
}

//+------------------------------------------------------------------+
//| Check if we should use diagonal channel for entry                |
//| Only in trends, not in ranges                                    |
//+------------------------------------------------------------------+
bool ShouldUseDiagonalChannel()
{
   if(!g_structure.valid || !g_structure.channel.valid)
      return false;
   
   // Use diagonal channel only in trends
   return (g_structure.state == STRUCTURE_BULL_TREND ||
           g_structure.state == STRUCTURE_BEAR_TREND ||
           g_structure.state == STRUCTURE_BIAS_BULL ||
           g_structure.state == STRUCTURE_BIAS_BEAR);
}

//+------------------------------------------------------------------+
//| Check if buy setup is valid at current location                  |
//| Trends: channel support OR major horizontal support OR flip      |
//| Ranges: major horizontal support only                            |
//+------------------------------------------------------------------+
bool IsValidBuyLocation(double price, double atr, bool atMajorSupport, bool atFlippedResistance)
{
   if(!g_structure.valid) return (atMajorSupport || atFlippedResistance);
   
   switch(g_structure.state)
   {
      case STRUCTURE_BULL_TREND:
      case STRUCTURE_BIAS_BULL:
         // Bull trend: channel support + major support + flipped resistance
         if(IsNearDynamicChannelSupport(price, atr, 0.6))
         {
            Print("[STRUCTURE_LOCATION] BUY valid at diagonal channel support");
            return true;
         }
         if(atMajorSupport)
         {
            Print("[STRUCTURE_LOCATION] BUY valid at major horizontal support");
            return true;
         }
         if(atFlippedResistance)
         {
            Print("[STRUCTURE_LOCATION] BUY valid at flipped resistance (now support)");
            return true;
         }
         return false;
         
      case STRUCTURE_RANGE:
         // Range: horizontal major support only, no channel
         if(atMajorSupport)
         {
            Print("[STRUCTURE_LOCATION] BUY valid at major horizontal support (range)");
            return true;
         }
         if(atFlippedResistance)
         {
            Print("[STRUCTURE_LOCATION] BUY valid at flipped resistance (range)");
            return true;
         }
         return false;
         
      default:
         return (atMajorSupport || atFlippedResistance);
   }
}

//+------------------------------------------------------------------+
//| Check if sell setup is valid at current location                 |
//+------------------------------------------------------------------+
bool IsValidSellLocation(double price, double atr, bool atMajorResistance, bool atFlippedSupport)
{
   if(!g_structure.valid) return (atMajorResistance || atFlippedSupport);
   
   switch(g_structure.state)
   {
      case STRUCTURE_BEAR_TREND:
      case STRUCTURE_BIAS_BEAR:
         // Bear trend: channel resistance + major resistance + flipped support
         if(IsNearDynamicChannelResistance(price, atr, 0.6))
         {
            Print("[STRUCTURE_LOCATION] SELL valid at diagonal channel resistance");
            return true;
         }
         if(atMajorResistance)
         {
            Print("[STRUCTURE_LOCATION] SELL valid at major horizontal resistance");
            return true;
         }
         if(atFlippedSupport)
         {
            Print("[STRUCTURE_LOCATION] SELL valid at flipped support (now resistance)");
            return true;
         }
         return false;
         
      case STRUCTURE_RANGE:
         // Range: horizontal major resistance only, no channel
         if(atMajorResistance)
         {
            Print("[STRUCTURE_LOCATION] SELL valid at major horizontal resistance (range)");
            return true;
         }
         if(atFlippedSupport)
         {
            Print("[STRUCTURE_LOCATION] SELL valid at flipped support (range)");
            return true;
         }
         return false;
         
      default:
         return (atMajorResistance || atFlippedSupport);
   }
}

//+------------------------------------------------------------------+
//| MULTI-TIMEFRAME LEVEL HIERARCHY SYSTEM                           |
//| HTF major levels = structure map                                  |
//| LTF secondary levels = refinement zones                          |
//| Pierce-and-reversal = valid if quick reclaim                     |
//| Price action confirmation = required at all levels               |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Level Entry Context                                               |
//+------------------------------------------------------------------+
struct LevelEntryContext
{
   bool              valid;
   ENUM_LEVEL_HIERARCHY hierarchy;
   double            levelPrice;
   double            levelHigh;
   double            levelLow;
   bool              isSupport;           // true = support, false = resistance
   bool              isFlipped;           // Role-flipped level
   bool              isDynamic;           // Dynamic trendline
   bool              pierceDetected;      // Price pierced through level
   bool              quickReclaim;        // Price quickly reclaimed correct side
   bool              priceActionConfirmed; // PA confirmation at level
   int               barsSinceTouch;      // Bars since level was touched
   double            entryPrice;
   double            stopLoss;
   double            takeProfit;
   
   // Simplified fields for our implementation
   double            level;              // Simplified level price
   bool              confirmed;          // Simplified confirmation flag
   double            score;              // Simplified score
};

//+------------------------------------------------------------------+
//| Check if level is HTF major (structure map level)                 |
//+------------------------------------------------------------------+
bool IsHTFMajorLevel(const ZoneInfo &zone)
{
   // HTF major levels: high touch count, strong reactions, protected key zones
   if(zone.protectedKeyZone) return true;
   if(zone.cleanTouchCount >= 3) return true;
   if(zone.reactionScore >= 0.7) return true;
   
   // Major zone types
   if(zone.type == ZONE_SUPPORT_MAJOR || zone.type == ZONE_RESISTANCE_MAJOR)
      return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if level is LTF refinement zone                             |
//+------------------------------------------------------------------+
bool IsLTFRefinementLevel(const ZoneInfo &zone)
{
   // LTF refinement: minor zones, fewer touches, recent creation
   if(zone.type == ZONE_SUPPORT_MINOR || zone.type == ZONE_RESISTANCE_MINOR)
      return true;
   
   if(zone.isRefinement) return true;
   if(zone.cleanTouchCount <= 1 && zone.generation <= 1) return true;
   
   return false;
}

//+------------------------------------------------------------------+
//| Classify level hierarchy                                          |
//+------------------------------------------------------------------+
ENUM_LEVEL_HIERARCHY ClassifyLevelHierarchy(const ZoneInfo &zone)
{
   if(zone.isFlipZone) return LEVEL_FLIPPED;
   if(IsHTFMajorLevel(zone)) return LEVEL_HTF_MAJOR;
   if(IsLTFRefinementLevel(zone)) return LEVEL_LTF_REFINEMENT;
   return LEVEL_HTF_MINOR;
}

//+------------------------------------------------------------------+
//| Check for pierce-and-reversal (quick reclaim)                     |
//| Valid if price pierces level but quickly reclaims correct side   |
//+------------------------------------------------------------------+
bool IsPierceAndReversal(const IndicatorState &ind, double levelPrice, bool isSupport, double atr)
{
   double close1 = ind.closeArr[1];
   double low1 = ind.lowArr[1];
   double high1 = ind.highArr[1];
   double open1 = ind.openArr[1];
   
   double pierceThreshold = atr * 0.3;  // Max pierce depth
   
   if(isSupport)
   {
      // Support pierce: wick below level but close above
      bool wickedBelow = (low1 < levelPrice - atr * 0.1);
      bool closedAbove = (close1 > levelPrice);
      bool quickReclaim = (close1 > open1);  // Bullish close
      bool notTooDeep = (levelPrice - low1 < pierceThreshold);
      
      if(wickedBelow && closedAbove && quickReclaim && notTooDeep)
      {
         Print("[PIERCE_REVERSAL] Support pierced but quickly reclaimed: level=", 
               DoubleToString(levelPrice, _Digits));
         return true;
      }
   }
   else
   {
      // Resistance pierce: wick above level but close below
      bool wickedAbove = (high1 > levelPrice + atr * 0.1);
      bool closedBelow = (close1 < levelPrice);
      bool quickReclaim = (close1 < open1);  // Bearish close
      bool notTooDeep = (high1 - levelPrice < pierceThreshold);
      
      if(wickedAbove && closedBelow && quickReclaim && notTooDeep)
      {
         Print("[PIERCE_REVERSAL] Resistance pierced but quickly reclaimed: level=", 
               DoubleToString(levelPrice, _Digits));
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for bullish price action confirmation at level              |
//+------------------------------------------------------------------+
bool HasBullishPAConfirmationAtLevel(const IndicatorState &ind, double levelPrice, double atr)
{
   double price = ind.closeArr[1];
   double tolerance = atr * 0.5;
   
   // Must be near the level
   if(price < levelPrice - tolerance || price > levelPrice + atr)
      return false;
   
   // 1. Bullish engulfing
   if(IsBullishEngulfing(_Symbol, g_indicatorTF, 1))
   {
      Print("[PA_CONFIRM] Bullish engulfing at level");
      return true;
   }
   
   // 2. Hammer / strong lower wick
   double lowerWick = MathMin(ind.openArr[1], ind.closeArr[1]) - ind.lowArr[1];
   double body = MathAbs(ind.closeArr[1] - ind.openArr[1]);
   double range = ind.highArr[1] - ind.lowArr[1];
   
   if(range > 0 && lowerWick > range * 0.60 && body < range * 0.30 && ind.closeArr[1] > ind.openArr[1])
   {
      Print("[PA_CONFIRM] Hammer at level");
      return true;
   }
   
   // 3. Bullish rejection
   if(IsBullishRejection(ind))
   {
      Print("[PA_CONFIRM] Bullish rejection at level");
      return true;
   }
   
   // 4. Pierce and reversal (sweep and reclaim)
   if(IsPierceAndReversal(ind, levelPrice, true, atr))
   {
      Print("[PA_CONFIRM] Pierce-and-reversal (bullish) at level");
      return true;
   }
   
   // 5. Double bottom
   if(ind.lowArr[1] >= levelPrice - tolerance && ind.lowArr[2] >= levelPrice - tolerance)
   {
      if(MathAbs(ind.lowArr[1] - ind.lowArr[2]) < atr * 0.2 && ind.closeArr[1] > ind.openArr[1])
      {
         Print("[PA_CONFIRM] Double bottom at level");
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for bearish price action confirmation at level              |
//+------------------------------------------------------------------+
bool HasBearishPAConfirmationAtLevel(const IndicatorState &ind, double levelPrice, double atr)
{
   double price = ind.closeArr[1];
   double tolerance = atr * 0.5;
   
   // Must be near the level
   if(price > levelPrice + tolerance || price < levelPrice - atr)
      return false;
   
   // 1. Bearish engulfing
   if(IsBearishEngulfing(_Symbol, g_indicatorTF, 1))
   {
      Print("[PA_CONFIRM] Bearish engulfing at level");
      return true;
   }
   
   // 2. Shooting star / strong upper wick
   double upperWick = ind.highArr[1] - MathMax(ind.openArr[1], ind.closeArr[1]);
   double body = MathAbs(ind.closeArr[1] - ind.openArr[1]);
   double range = ind.highArr[1] - ind.lowArr[1];
   
   if(range > 0 && upperWick > range * 0.60 && body < range * 0.30 && ind.closeArr[1] < ind.openArr[1])
   {
      Print("[PA_CONFIRM] Shooting star at level");
      return true;
   }
   
   // 3. Bearish rejection
   if(IsBearishRejection(ind))
   {
      Print("[PA_CONFIRM] Bearish rejection at level");
      return true;
   }
   
   // 4. Pierce and reversal (sweep and reclaim)
   if(IsPierceAndReversal(ind, levelPrice, false, atr))
   {
      Print("[PA_CONFIRM] Pierce-and-reversal (bearish) at level");
      return true;
   }
   
   // 5. Double top
   if(ind.highArr[1] <= levelPrice + tolerance && ind.highArr[2] <= levelPrice + tolerance)
   {
      if(MathAbs(ind.highArr[1] - ind.highArr[2]) < atr * 0.2 && ind.closeArr[1] < ind.openArr[1])
      {
         Print("[PA_CONFIRM] Double top at level");
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if entry is valid based on market state and level type     |
//| Ranges: outer horizontal S/R only                                 |
//| Trends: major S/R + flipped levels + dynamic trendlines          |
//+------------------------------------------------------------------+
bool IsEntryValidForMarketState(ENUM_LEVEL_HIERARCHY hierarchy, bool isDynamic, bool isFlipped)
{
   if(!g_structure.valid) return true;  // Allow if no structure data
   
   switch(g_structure.state)
   {
      case STRUCTURE_RANGE:
         // RANGE: Only outer horizontal major S/R allowed
         // No dynamic trendlines, no minor levels
         if(isDynamic)
         {
            Print("[LEVEL_FILTER] Dynamic level rejected in range");
            return false;
         }
         if(hierarchy == LEVEL_LTF_REFINEMENT)
         {
            Print("[LEVEL_FILTER] LTF refinement level rejected in range");
            return false;
         }
         if(hierarchy == LEVEL_HTF_MINOR)
         {
            Print("[LEVEL_FILTER] HTF minor level rejected in range - use outer major only");
            return false;
         }
         // Only HTF_MAJOR and FLIPPED allowed in range
         return (hierarchy == LEVEL_HTF_MAJOR || hierarchy == LEVEL_FLIPPED);
         
      case STRUCTURE_BULL_TREND:
      case STRUCTURE_BEAR_TREND:
      case STRUCTURE_BIAS_BULL:
      case STRUCTURE_BIAS_BEAR:
         // TREND: Major S/R + flipped levels + dynamic trendlines allowed
         // LTF refinement zones can be used for precision entry
         return true;
         
      default:
         return true;
   }
}

//+------------------------------------------------------------------+
//| Find best entry level for buy setup (Simplified)                   |
//+------------------------------------------------------------------+
LevelEntryContext FindBestBuyLevel(const IndicatorState &ind, double atr)
{
   LevelEntryContext ctx;
   ZeroMemory(ctx);
   ctx.valid = false;
   
   // Simplified version - use dynamic support from channel
   if(g_structure.valid && g_structure.dynamicSupport > 0.0)
   {
      double price = ind.closeArr[1];
      double tolerance = atr * 0.5;
      
      if(MathAbs(price - g_structure.dynamicSupport) <= tolerance)
      {
         ctx.valid = true;
         ctx.level = g_structure.dynamicSupport;
         ctx.hierarchy = LEVEL_HTF_MAJOR;
         ctx.confirmed = true;
         ctx.score = 0.8;
      }
   }
   
   if(ctx.valid)
   {
      Print("[LEVEL_ENTRY] BUY level found: hierarchy=", LevelHierarchyToString(ctx.hierarchy),
            " price=", DoubleToString(ctx.level, _Digits),
            " confirmed=", ctx.confirmed);
   }
   
   return ctx;
}

//+------------------------------------------------------------------+
//| Find best entry level for sell setup (Simplified)                 |
//+------------------------------------------------------------------+
LevelEntryContext FindBestSellLevel(const IndicatorState &ind, double atr)
{
   LevelEntryContext ctx;
   ZeroMemory(ctx);
   ctx.valid = false;
   
   // Simplified version - use dynamic resistance from channel
   if(g_structure.valid && g_structure.dynamicResistance > 0.0)
   {
      double price = ind.closeArr[1];
      double tolerance = atr * 0.5;
      
      if(MathAbs(price - g_structure.dynamicResistance) <= tolerance)
      {
         ctx.valid = true;
         ctx.level = g_structure.dynamicResistance;
         ctx.hierarchy = LEVEL_HTF_MAJOR;
         ctx.confirmed = true;
         ctx.score = 0.8;
      }
   }
   
   if(ctx.valid)
   {
      Print("[LEVEL_ENTRY] SELL level found: hierarchy=", LevelHierarchyToString(ctx.hierarchy),
            " price=", DoubleToString(ctx.level, _Digits),
            " confirmed=", ctx.confirmed);
   }
   
   return ctx;
}

//+------------------------------------------------------------------+
//| Get level hierarchy as string                                     |
//+------------------------------------------------------------------+
string LevelHierarchyToString(ENUM_LEVEL_HIERARCHY hierarchy)
{
   switch(hierarchy)
   {
      case LEVEL_HTF_MAJOR:      return "HTF_MAJOR";
      case LEVEL_HTF_MINOR:      return "HTF_MINOR";
      case LEVEL_LTF_REFINEMENT: return "LTF_REFINEMENT";
      case LEVEL_FLIPPED:        return "FLIPPED";
      case LEVEL_DYNAMIC:        return "DYNAMIC";
      default:                   return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| ZONE-BASED TRADING SYSTEM                                         |
//| Zones are price ranges, not single lines                          |
//| Zone = lower bound + upper bound + midpoint + width + strength   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Zone Position Classification                                      |
//+------------------------------------------------------------------+
enum ENUM_ZONE_POSITION
{
   ZONE_POS_ABOVE       = 0,  // Price above zone
   ZONE_POS_AT_UPPER    = 1,  // Price at upper boundary
   ZONE_POS_INSIDE      = 2,  // Price inside zone
   ZONE_POS_AT_LOWER    = 3,  // Price at lower boundary
   ZONE_POS_BELOW       = 4   // Price below zone
};

//+------------------------------------------------------------------+
//| Zone Entry Context (enhanced)                                     |
//+------------------------------------------------------------------+
struct ZoneEntrySetup
{
   bool              valid;
   int               zoneIndex;
   double            zoneLower;
   double            zoneUpper;
   double            zoneMid;
   double            zoneWidth;
   double            zoneStrength;
   int               zoneContacts;
   bool              isHTFZone;           // From higher timeframe
   bool              hasSubZone;          // Has LTF refinement sub-zone
   double            subZoneLower;        // LTF sub-zone bounds
   double            subZoneUpper;
   ENUM_ZONE_POSITION pricePosition;
   bool              isWickPierce;        // Wick pierced but body inside
   bool              isBodyInside;        // Body fully inside zone
   bool              isDecisiveBreak;     // Decisive close beyond zone
   bool              paConfirmed;         // Price action confirmation
   bool              isSupport;           // Support or resistance zone
   double            entryPrice;
   double            stopLoss;
   double            takeProfit;
   double            riskReward;
};

//+------------------------------------------------------------------+
//| Calculate zone width                                              |
//+------------------------------------------------------------------+
double GetZoneWidth(const ZoneInfo &zone)
{
   return zone.upperBound - zone.lowerBound;
}

//+------------------------------------------------------------------+
//| Calculate zone midpoint                                           |
//+------------------------------------------------------------------+
double GetZoneMidpoint(const ZoneInfo &zone)
{
   return (zone.upperBound + zone.lowerBound) / 2.0;
}

//+------------------------------------------------------------------+
//| Calculate comprehensive zone strength score                       |
//| Based on: HTF, contacts, reactions, wick/body, round numbers     |
//+------------------------------------------------------------------+
double CalculateZoneStrength(const ZoneInfo &zone, double atr)
{
   double strength = 0.0;
   
   // 1. Higher timeframe bonus (+0.25)
   if(zone.majorTFZone || zone.sourceTF >= PERIOD_H4)
      strength += 0.25;
   
   // 2. Contact points bonus (+0.05 per contact, max +0.30)
   strength += MathMin(zone.cleanTouchCount * 0.05, 0.30);
   
   // 3. Reaction strength (+0.20 max)
   strength += zone.reactionScore * 0.20;
   
   // 4. Rejection quality (+0.15 max)
   strength += zone.rejectionScore * 0.15;
   
   // 5. Protected key zone bonus (+0.15)
   if(zone.protectedKeyZone)
      strength += 0.15;
   
   // 6. Round number alignment (+0.10)
   if(zone.isRoundNumber)
      strength += 0.10;
   
   // 7. Session level (previous day high/low) (+0.10)
   if(zone.isSessionLevel)
      strength += 0.10;
   
   // 8. Zone width penalty (too wide = less precise)
   double width = GetZoneWidth(zone);
   if(width > atr * 2.0)
      strength -= 0.10;
   else if(width < atr * 0.5)
      strength += 0.05;  // Tight zone bonus
   
   // 9. Freshness bonus (recent zones more relevant)
   strength += zone.freshness * 0.10;
   
   // 10. Flip zone bonus (+0.15)
   if(zone.isFlipZone)
      strength += 0.15;
   
   // 11. Confirmed retest bonus (+0.10)
   if(zone.confirmedRetest)
      strength += 0.10;
   
   // Clamp to 0-1 range
   return MathMax(0.0, MathMin(1.0, strength));
}

//+------------------------------------------------------------------+
//| Determine price position relative to zone                         |
//+------------------------------------------------------------------+
ENUM_ZONE_POSITION GetPricePositionInZone(double price, const ZoneInfo &zone, double atr)
{
   double tolerance = atr * 0.15;  // Small tolerance for boundary detection
   
   if(price > zone.upperBound + tolerance)
      return ZONE_POS_ABOVE;
   
   if(price >= zone.upperBound - tolerance && price <= zone.upperBound + tolerance)
      return ZONE_POS_AT_UPPER;
   
   if(price > zone.lowerBound + tolerance && price < zone.upperBound - tolerance)
      return ZONE_POS_INSIDE;
   
   if(price >= zone.lowerBound - tolerance && price <= zone.lowerBound + tolerance)
      return ZONE_POS_AT_LOWER;
   
   return ZONE_POS_BELOW;
}

//+------------------------------------------------------------------+
//| Check if candle is testing zone (wick pierce, body inside)        |
//+------------------------------------------------------------------+
bool IsZoneTesting(const IndicatorState &ind, const ZoneInfo &zone, bool isSupport, double atr)
{
   double close1 = ind.closeArr[1];
   double open1 = ind.openArr[1];
   double high1 = ind.highArr[1];
   double low1 = ind.lowArr[1];
   
   double bodyHigh = MathMax(open1, close1);
   double bodyLow = MathMin(open1, close1);
   
   if(isSupport)
   {
      // Support testing: wick below zone but body above or inside
      bool wickBelow = (low1 < zone.lowerBound);
      bool bodyAboveOrInside = (bodyLow >= zone.lowerBound - atr * 0.1);
      return (wickBelow && bodyAboveOrInside);
   }
   else
   {
      // Resistance testing: wick above zone but body below or inside
      bool wickAbove = (high1 > zone.upperBound);
      bool bodyBelowOrInside = (bodyHigh <= zone.upperBound + atr * 0.1);
      return (wickAbove && bodyBelowOrInside);
   }
}

//+------------------------------------------------------------------+
//| Check for decisive zone breakout                                  |
//| Requires: close beyond zone + sufficient body + not just wick    |
//+------------------------------------------------------------------+
bool IsDecisiveZoneBreak(const IndicatorState &ind, const ZoneInfo &zone, bool isSupport, double atr)
{
   double close1 = ind.closeArr[1];
   double open1 = ind.openArr[1];
   double body = MathAbs(close1 - open1);
   
   // Minimum body size for decisive break
   if(body < atr * 0.30)
      return false;
   
   if(isSupport)
   {
      // Decisive break below support: close below zone with bearish body
      return (close1 < zone.lowerBound - atr * 0.10 && close1 < open1);
   }
   else
   {
      // Decisive break above resistance: close above zone with bullish body
      return (close1 > zone.upperBound + atr * 0.10 && close1 > open1);
   }
}

//+------------------------------------------------------------------+
//| Check if price is in center of wide zone (avoid trading)          |
//+------------------------------------------------------------------+
bool IsInZoneCenter(double price, const ZoneInfo &zone, double atr)
{
   double width = GetZoneWidth(zone);
   double mid = GetZoneMidpoint(zone);
   
   // Zone must be wide enough to have a meaningful center
   if(width < atr * 1.0)
      return false;
   
   // Center is middle 40% of zone
   double centerMargin = width * 0.30;
   return (price > mid - centerMargin && price < mid + centerMargin);
}

//+------------------------------------------------------------------+
//| Find LTF sub-zone inside HTF zone for entry refinement            |
//+------------------------------------------------------------------+
bool FindSubZoneForRefinement(const ZoneInfo &htfZone, bool isSupport, double atr,
                               double &outSubLower, double &outSubUpper)
{
   outSubLower = 0;
   outSubUpper = 0;
   
   // Look for minor zones inside the HTF zone
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active) continue;
      if(g_zoneReg.zones[i].id == htfZone.id) continue;  // Skip same zone
      
      // Check if this is a minor/refinement zone
      if(!g_zoneReg.zones[i].isRefinement && g_zoneReg.zones[i].type != ZONE_SUPPORT_MINOR && g_zoneReg.zones[i].type != ZONE_RESISTANCE_MINOR)
         continue;
      
      // Check if sub-zone is inside HTF zone
      double subMid = GetZoneMidpoint(g_zoneReg.zones[i]);
      if(subMid < htfZone.lowerBound || subMid > htfZone.upperBound)
         continue;
      
      // Check direction match
      bool subIsSupport = (g_zoneReg.zones[i].type == ZONE_SUPPORT_MINOR || g_zoneReg.zones[i].type == ZONE_SUPPORT_MAJOR || g_zoneReg.zones[i].type == ZONE_DEMAND);
      if(subIsSupport != isSupport)
         continue;
      
      // Found a sub-zone
      outSubLower = g_zoneReg.zones[i].lowerBound;
      outSubUpper = g_zoneReg.zones[i].upperBound;
      Print("[ZONE_REFINE] Found sub-zone inside HTF zone: sub=", DoubleToString(subMid, _Digits),
            " htf=", DoubleToString(GetZoneMidpoint(htfZone), _Digits));
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for bullish entry confirmation inside zone                  |
//+------------------------------------------------------------------+
bool HasBullishZoneConfirmation(const IndicatorState &ind, const ZoneInfo &zone, double atr)
{
   double price = ind.closeArr[1];
   
   // Must be at or inside the zone (at lower boundary or inside)
   ENUM_ZONE_POSITION pos = GetPricePositionInZone(price, zone, atr);
   if(pos != ZONE_POS_AT_LOWER && pos != ZONE_POS_INSIDE && pos != ZONE_POS_BELOW)
      return false;
   
   // Check for zone testing (wick pierce but body holds)
   if(IsZoneTesting(ind, zone, true, atr))
   {
      Print("[ZONE_CONFIRM] Bullish zone testing detected");
      return true;
   }
   
   // Standard bullish confirmations
   if(IsBullishEngulfing(_Symbol, g_indicatorTF, 1))
   {
      Print("[ZONE_CONFIRM] Bullish engulfing in support zone");
      return true;
   }
   
   // Hammer
   double lowerWick = MathMin(ind.openArr[1], ind.closeArr[1]) - ind.lowArr[1];
   double body = MathAbs(ind.closeArr[1] - ind.openArr[1]);
   double range = ind.highArr[1] - ind.lowArr[1];
   
   if(range > 0 && lowerWick > range * 0.60 && body < range * 0.30 && ind.closeArr[1] > ind.openArr[1])
   {
      Print("[ZONE_CONFIRM] Hammer in support zone");
      return true;
   }
   
   // Bullish rejection
   if(IsBullishRejection(ind))
   {
      Print("[ZONE_CONFIRM] Bullish rejection in support zone");
      return true;
   }
   
   // Double bottom inside zone
   if(ind.lowArr[1] >= zone.lowerBound - atr * 0.2 && ind.lowArr[2] >= zone.lowerBound - atr * 0.2)
   {
      if(MathAbs(ind.lowArr[1] - ind.lowArr[2]) < atr * 0.15 && ind.closeArr[1] > ind.openArr[1])
      {
         Print("[ZONE_CONFIRM] Double bottom in support zone");
         return true;
      }
   }
   
   // Sweep below zone and reclaim
   if(ind.lowArr[1] < zone.lowerBound - atr * 0.1 && ind.closeArr[1] > zone.lowerBound)
   {
      Print("[ZONE_CONFIRM] Sweep and reclaim at support zone");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for bearish entry confirmation inside zone                  |
//+------------------------------------------------------------------+
bool HasBearishZoneConfirmation(const IndicatorState &ind, const ZoneInfo &zone, double atr)
{
   double price = ind.closeArr[1];
   
   // Must be at or inside the zone (at upper boundary or inside)
   ENUM_ZONE_POSITION pos = GetPricePositionInZone(price, zone, atr);
   if(pos != ZONE_POS_AT_UPPER && pos != ZONE_POS_INSIDE && pos != ZONE_POS_ABOVE)
      return false;
   
   // Check for zone testing (wick pierce but body holds)
   if(IsZoneTesting(ind, zone, false, atr))
   {
      Print("[ZONE_CONFIRM] Bearish zone testing detected");
      return true;
   }
   
   // Standard bearish confirmations
   if(IsBearishEngulfing(_Symbol, g_indicatorTF, 1))
   {
      Print("[ZONE_CONFIRM] Bearish engulfing in resistance zone");
      return true;
   }
   
   // Shooting star
   double upperWick = ind.highArr[1] - MathMax(ind.openArr[1], ind.closeArr[1]);
   double body = MathAbs(ind.closeArr[1] - ind.openArr[1]);
   double range = ind.highArr[1] - ind.lowArr[1];
   
   if(range > 0 && upperWick > range * 0.60 && body < range * 0.30 && ind.closeArr[1] < ind.openArr[1])
   {
      Print("[ZONE_CONFIRM] Shooting star in resistance zone");
      return true;
   }
   
   // Bearish rejection
   if(IsBearishRejection(ind))
   {
      Print("[ZONE_CONFIRM] Bearish rejection in resistance zone");
      return true;
   }
   
   // Double top inside zone
   if(ind.highArr[1] <= zone.upperBound + atr * 0.2 && ind.highArr[2] <= zone.upperBound + atr * 0.2)
   {
      if(MathAbs(ind.highArr[1] - ind.highArr[2]) < atr * 0.15 && ind.closeArr[1] < ind.openArr[1])
      {
         Print("[ZONE_CONFIRM] Double top in resistance zone");
         return true;
      }
   }
   
   // Sweep above zone and reclaim
   if(ind.highArr[1] > zone.upperBound + atr * 0.1 && ind.closeArr[1] < zone.upperBound)
   {
      Print("[ZONE_CONFIRM] Sweep and reclaim at resistance zone");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Find best support zone for buy entry                              |
//| Implements: zone behavior, range/trend rules, entry refinement   |
//+------------------------------------------------------------------+
ZoneEntrySetup FindBestSupportZone(const IndicatorState &ind, double atr)
{
   ZoneEntrySetup setup;
   ZeroMemory(setup);
   setup.valid = false;
   
   double price = ind.closeArr[1];
   double bestScore = 0;
   
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      
      // Must be support-type zone
      bool isSupport = (z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_SUPPORT_MINOR || z.type == ZONE_DEMAND);
      if(!isSupport && !z.isFlipZone) continue;
      if(z.isFlipZone && z.type != ZONE_RESISTANCE_MAJOR && z.type != ZONE_RESISTANCE_MINOR) continue;
      
      // Check price position relative to zone
      ENUM_ZONE_POSITION pos = GetPricePositionInZone(price, z, atr);
      
      // Price must be at or near the zone (not far above or below)
      if(pos == ZONE_POS_ABOVE && price > z.upperBound + atr * 0.5) continue;
      if(pos == ZONE_POS_BELOW && price < z.lowerBound - atr * 0.5) continue;
      
      // RANGE RULES: In ranges, only trade outer major zones
      if(g_structure.valid && g_structure.state == STRUCTURE_RANGE)
      {
         if(z.type != ZONE_SUPPORT_MAJOR && !z.protectedKeyZone)
         {
            continue;  // Skip non-major zones in range
         }
      }
      
      // Calculate zone strength
      double strength = CalculateZoneStrength(z, atr);
      
      // Reject weak zones
      if(strength < 0.30)
      {
         continue;
      }
      
      // INVALIDATION: Reject if in center of wide zone without sub-zone
      if(IsInZoneCenter(price, z, atr))
      {
         double subLower = 0, subUpper = 0;
         if(!FindSubZoneForRefinement(z, true, atr, subLower, subUpper))
         {
            Print("[ZONE_REJECT] Price in center of wide zone without refinement");
            continue;
         }
      }
      
      // Check for decisive break (invalidation)
      if(IsDecisiveZoneBreak(ind, z, true, atr))
      {
         Print("[ZONE_REJECT] Decisive break below support zone");
         continue;
      }
      
      // Check for bullish confirmation
      bool paConfirmed = HasBullishZoneConfirmation(ind, z, atr);
      if(!paConfirmed) continue;  // REQUIRE confirmation
      
      // Calculate target (next major resistance)
      double target = FindNearestMajorResistanceLevel(price, atr);
      if(target <= price) target = price + atr * 2.0;
      
      // Check room to target
      double room = target - price;
      double risk = price - (z.lowerBound - atr * 0.3);
      if(risk <= 0 || room < risk * 1.0)
      {
         Print("[ZONE_REJECT] Insufficient room to next major zone");
         continue;
      }
      
      // Score the zone
      double score = strength;
      if(z.majorTFZone) score += 0.20;
      if(z.protectedKeyZone) score += 0.15;
      if(z.isFlipZone) score += 0.10;
      if(pos == ZONE_POS_AT_LOWER) score += 0.10;  // At boundary is better
      
      if(score > bestScore)
      {
         bestScore = score;
         setup.valid = true;
         setup.zoneIndex = i;
         setup.zoneLower = z.lowerBound;
         setup.zoneUpper = z.upperBound;
         setup.zoneMid = GetZoneMidpoint(z);
         setup.zoneWidth = GetZoneWidth(z);
         setup.zoneStrength = strength;
         setup.zoneContacts = z.cleanTouchCount;
         setup.isHTFZone = z.majorTFZone;
         setup.pricePosition = pos;
         setup.paConfirmed = true;
         setup.isSupport = true;
         setup.stopLoss = z.lowerBound - atr * 0.35;
         setup.takeProfit = target;
         setup.riskReward = room / risk;
         
         // Check for sub-zone refinement
         double subLower = 0, subUpper = 0;
         if(FindSubZoneForRefinement(z, true, atr, subLower, subUpper))
         {
            setup.hasSubZone = true;
            setup.subZoneLower = subLower;
            setup.subZoneUpper = subUpper;
         }
      }
   }
   
   if(setup.valid)
   {
      Print("[ZONE_ENTRY] Support zone found: strength=", DoubleToString(setup.zoneStrength, 2),
            " contacts=", setup.zoneContacts, " HTF=", setup.isHTFZone,
            " RR=", DoubleToString(setup.riskReward, 2));
   }
   
   return setup;
}

//+------------------------------------------------------------------+
//| Find best resistance zone for sell entry                          |
//+------------------------------------------------------------------+
ZoneEntrySetup FindBestResistanceZone(const IndicatorState &ind, double atr)
{
   ZoneEntrySetup setup;
   ZeroMemory(setup);
   setup.valid = false;
   
   double price = ind.closeArr[1];
   double bestScore = 0;
   
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      
      // Must be resistance-type zone
      bool isResistance = (z.type == ZONE_RESISTANCE_MAJOR || z.type == ZONE_RESISTANCE_MINOR || z.type == ZONE_SUPPLY);
      if(!isResistance && !z.isFlipZone) continue;
      if(z.isFlipZone && z.type != ZONE_SUPPORT_MAJOR && z.type != ZONE_SUPPORT_MINOR) continue;
      
      // Check price position relative to zone
      ENUM_ZONE_POSITION pos = GetPricePositionInZone(price, z, atr);
      
      // Price must be at or near the zone
      if(pos == ZONE_POS_BELOW && price < z.lowerBound - atr * 0.5) continue;
      if(pos == ZONE_POS_ABOVE && price > z.upperBound + atr * 0.5) continue;
      
      // RANGE RULES: In ranges, only trade outer major zones
      if(g_structure.valid && g_structure.state == STRUCTURE_RANGE)
      {
         if(z.type != ZONE_RESISTANCE_MAJOR && !z.protectedKeyZone)
         {
            continue;
         }
      }
      
      // Calculate zone strength
      double strength = CalculateZoneStrength(z, atr);
      
      // Reject weak zones
      if(strength < 0.30)
      {
         continue;
      }
      
      // INVALIDATION: Reject if in center of wide zone without sub-zone
      if(IsInZoneCenter(price, z, atr))
      {
         double subLower = 0, subUpper = 0;
         if(!FindSubZoneForRefinement(z, false, atr, subLower, subUpper))
         {
            Print("[ZONE_REJECT] Price in center of wide zone without refinement");
            continue;
         }
      }
      
      // Check for decisive break (invalidation)
      if(IsDecisiveZoneBreak(ind, z, false, atr))
      {
         Print("[ZONE_REJECT] Decisive break above resistance zone");
         continue;
      }
      
      // Check for bearish confirmation
      bool paConfirmed = HasBearishZoneConfirmation(ind, z, atr);
      if(!paConfirmed) continue;
      
      // Calculate target (next major support)
      double target = FindNearestMajorSupportLevel(price, atr);
      if(target >= price || target <= 0) target = price - atr * 2.0;
      
      // Check room to target
      double room = price - target;
      double risk = (z.upperBound + atr * 0.3) - price;
      if(risk <= 0 || room < risk * 1.0)
      {
         Print("[ZONE_REJECT] Insufficient room to next major zone");
         continue;
      }
      
      // Score the zone
      double score = strength;
      if(z.majorTFZone) score += 0.20;
      if(z.protectedKeyZone) score += 0.15;
      if(z.isFlipZone) score += 0.10;
      if(pos == ZONE_POS_AT_UPPER) score += 0.10;
      
      if(score > bestScore)
      {
         bestScore = score;
         setup.valid = true;
         setup.zoneIndex = i;
         setup.zoneLower = z.lowerBound;
         setup.zoneUpper = z.upperBound;
         setup.zoneMid = GetZoneMidpoint(z);
         setup.zoneWidth = GetZoneWidth(z);
         setup.zoneStrength = strength;
         setup.zoneContacts = z.cleanTouchCount;
         setup.isHTFZone = z.majorTFZone;
         setup.pricePosition = pos;
         setup.paConfirmed = true;
         setup.isSupport = false;
         setup.stopLoss = z.upperBound + atr * 0.35;
         setup.takeProfit = target;
         setup.riskReward = room / risk;
         
         // Check for sub-zone refinement
         double subLower = 0, subUpper = 0;
         if(FindSubZoneForRefinement(z, false, atr, subLower, subUpper))
         {
            setup.hasSubZone = true;
            setup.subZoneLower = subLower;
            setup.subZoneUpper = subUpper;
         }
      }
   }
   
   if(setup.valid)
   {
      Print("[ZONE_ENTRY] Resistance zone found: strength=", DoubleToString(setup.zoneStrength, 2),
            " contacts=", setup.zoneContacts, " HTF=", setup.isHTFZone,
            " RR=", DoubleToString(setup.riskReward, 2));
   }
   
   return setup;
}

//+------------------------------------------------------------------+
//| Get zone position as string                                       |
//+------------------------------------------------------------------+
string ZonePositionToString(ENUM_ZONE_POSITION pos)
{
   switch(pos)
   {
      case ZONE_POS_ABOVE:    return "ABOVE";
      case ZONE_POS_AT_UPPER: return "AT_UPPER";
      case ZONE_POS_INSIDE:   return "INSIDE";
      case ZONE_POS_AT_LOWER: return "AT_LOWER";
      case ZONE_POS_BELOW:    return "BELOW";
      default:                return "UNKNOWN";
   }
}


//+------------------------------------------------------------------+
//| Find nearest major support level below current price             |
//+------------------------------------------------------------------+
double FindNearestMajorSupportLevel(double price, double atr)
{
   double nearestSupport = 0;
   double minDist = DBL_MAX;
   
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      
      // Only major support zones
      if(z.type != ZONE_SUPPORT_MAJOR) continue;
      
      double zoneMid = (z.upperBound + z.lowerBound) / 2.0;
      
      // Must be below current price
      if(zoneMid >= price) continue;
      
      double dist = price - zoneMid;
      if(dist < minDist)
      {
         minDist = dist;
         nearestSupport = zoneMid;
      }
   }
   
   return nearestSupport;
}

//+------------------------------------------------------------------+
//| Find nearest major resistance level above current price          |
//+------------------------------------------------------------------+
double FindNearestMajorResistanceLevel(double price, double atr)
{
   double nearestResist = 0;
   double minDist = DBL_MAX;
   
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      
      // Only major resistance zones
      if(z.type != ZONE_RESISTANCE_MAJOR) continue;
      
      double zoneMid = (z.upperBound + z.lowerBound) / 2.0;
      
      // Must be above current price
      if(zoneMid <= price) continue;
      
      double dist = zoneMid - price;
      if(dist < minDist)
      {
         minDist = dist;
         nearestResist = zoneMid;
      }
   }
   
   return nearestResist;
}

//+------------------------------------------------------------------+
//| GAP TRADING SYSTEM                                                |
//| Gaps into/through major S/R levels with trend context            |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Gap Type Classification                                           |
//+------------------------------------------------------------------+
enum ENUM_GAP_TYPE
{
   GAP_NONE                    = 0,
   GAP_UP_INTO_RESISTANCE      = 1,  // Gap up into major resistance
   GAP_UP_THROUGH_RESISTANCE   = 2,  // Gap up through major resistance
   GAP_DOWN_INTO_SUPPORT       = 3,  // Gap down into major support
   GAP_DOWN_THROUGH_SUPPORT    = 4   // Gap down through major support
};

//+------------------------------------------------------------------+
//| Gap State                                                         |
//+------------------------------------------------------------------+
enum ENUM_GAP_STATE
{
   GAP_STATE_DETECTED     = 0,
   GAP_STATE_CONFIRMING   = 1,
   GAP_STATE_ENTRY_READY  = 2,
   GAP_STATE_FILLED       = 3,
   GAP_STATE_INVALIDATED  = 4
};

//+------------------------------------------------------------------+
//| Gap Setup Structure                                               |
//+------------------------------------------------------------------+
struct GapSetup
{
   bool              valid;
   ENUM_GAP_TYPE     type;
   ENUM_GAP_STATE    state;
   
   double            gapOpen;
   double            priorClose;
   double            gapSize;
   double            gapSizeATR;
   bool              isGapUp;
   datetime          gapTime;
   int               gapBarIndex;
   
   double            majorLevelPrice;
   double            majorLevelHigh;
   double            majorLevelLow;
   bool              gapIntoLevel;
   bool              isIntoLevel;
   bool              isBullTrend;
   bool              isBearTrend;
   
   bool              isBuySetup;
   double            entryPrice;
   double            stopLoss;
   double            takeProfit;
   double            gapFillTarget;
   
   bool              confirmationSeen;
   int               barsSinceGap;
};

//+------------------------------------------------------------------+
//| Gap Tracker                                                       |
//+------------------------------------------------------------------+
struct GapTracker
{
   bool        valid;
   GapSetup    activeGaps[5];
   int         gapCount;
};

// Global gap tracker
GapTracker g_gapTracker;

//+------------------------------------------------------------------+
//| Initialize Gap Tracker                                            |
//+------------------------------------------------------------------+
void InitGapTracker()
{
   ZeroMemory(g_gapTracker);
   g_gapTracker.valid = true;
   g_gapTracker.gapCount = 0;
}

//+------------------------------------------------------------------+
//| Classify gap relative to major S/R levels                         |
//+------------------------------------------------------------------+
ENUM_GAP_TYPE ClassifyGap(double gapOpen, double priorClose, bool isGapUp, double atr,
                          double &outLevelPrice, double &outLevelHigh, double &outLevelLow,
                          bool &outIsIntoLevel)
{
   outLevelPrice = 0;
   outLevelHigh = 0;
   outLevelLow = 0;
   outIsIntoLevel = false;
   
   double tolerance = atr * 0.60;
   
   if(isGapUp)
   {
      // Check if gap up is into or through major resistance
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         ZoneInfo z = g_zoneReg.zones[i];
         if(!z.active) continue;
         if(z.type != ZONE_RESISTANCE_MAJOR) continue;
         
         double zoneMid = (z.upperBound + z.lowerBound) / 2.0;
         
         // Gap up INTO resistance: prior close below, gap open at/near resistance
         if(priorClose < z.lowerBound && gapOpen >= z.lowerBound - tolerance && gapOpen <= z.upperBound + tolerance)
         {
            outLevelPrice = zoneMid;
            outLevelHigh = z.upperBound;
            outLevelLow = z.lowerBound;
            outIsIntoLevel = true;
            return GAP_UP_INTO_RESISTANCE;
         }
         
         // Gap up THROUGH resistance: prior close below, gap open above resistance
         if(priorClose < z.lowerBound && gapOpen > z.upperBound + tolerance)
         {
            outLevelPrice = zoneMid;
            outLevelHigh = z.upperBound;
            outLevelLow = z.lowerBound;
            outIsIntoLevel = false;
            return GAP_UP_THROUGH_RESISTANCE;
         }
      }
   }
   else
   {
      // Check if gap down is into or through major support
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         ZoneInfo z = g_zoneReg.zones[i];
         if(!z.active) continue;
         if(z.type != ZONE_SUPPORT_MAJOR) continue;
         
         double zoneMid = (z.upperBound + z.lowerBound) / 2.0;
         
         // Gap down INTO support: prior close above, gap open at/near support
         if(priorClose > z.upperBound && gapOpen >= z.lowerBound - tolerance && gapOpen <= z.upperBound + tolerance)
         {
            outLevelPrice = zoneMid;
            outLevelHigh = z.upperBound;
            outLevelLow = z.lowerBound;
            outIsIntoLevel = true;
            return GAP_DOWN_INTO_SUPPORT;
         }
         
         // Gap down THROUGH support: prior close above, gap open below support
         if(priorClose > z.upperBound && gapOpen < z.lowerBound - tolerance)
         {
            outLevelPrice = zoneMid;
            outLevelHigh = z.upperBound;
            outLevelLow = z.lowerBound;
            outIsIntoLevel = false;
            return GAP_DOWN_THROUGH_SUPPORT;
         }
      }
   }
   
   return GAP_NONE;
}

//+------------------------------------------------------------------+
//| Check for bearish confirmation at resistance (for gap up into R) |
//+------------------------------------------------------------------+
bool HasBearishGapConfirmation(const IndicatorState &ind, double resistanceLevel, double atr)
{
   double price = ind.closeArr[1];
   double tolerance = atr * 0.5;
   
   // Must be near resistance
   if(price < resistanceLevel - tolerance || price > resistanceLevel + atr)
      return false;
   
   // 1. Bearish engulfing
   if(IsBearishEngulfing(_Symbol, g_indicatorTF, 1))
   {
      Print("[GAP_CONFIRM] Bearish engulfing at resistance after gap up");
      return true;
   }
   
   // 2. Upper wick rejection (shooting star)
   double upperWick = ind.highArr[1] - MathMax(ind.openArr[1], ind.closeArr[1]);
   double body = MathAbs(ind.closeArr[1] - ind.openArr[1]);
   double range = ind.highArr[1] - ind.lowArr[1];
   
   if(range > 0 && upperWick > range * 0.60 && body < range * 0.30)
   {
      Print("[GAP_CONFIRM] Upper wick rejection at resistance after gap up");
      return true;
   }
   
   // 3. Bearish rejection
   if(IsBearishRejection(ind))
   {
      Print("[GAP_CONFIRM] Bearish rejection at resistance after gap up");
      return true;
   }
   
   // 4. Double top pattern
   if(ind.highArr[1] <= resistanceLevel + tolerance && ind.highArr[2] <= resistanceLevel + tolerance)
   {
      if(MathAbs(ind.highArr[1] - ind.highArr[2]) < atr * 0.2 && ind.closeArr[1] < ind.openArr[1])
      {
         Print("[GAP_CONFIRM] Double top at resistance after gap up");
         return true;
      }
   }
   
   // 5. Sweep above and reclaim
   if(ind.highArr[1] > resistanceLevel + tolerance && ind.closeArr[1] < resistanceLevel)
   {
      Print("[GAP_CONFIRM] Sweep and reclaim at resistance after gap up");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for bullish confirmation at support (for gap down into S)  |
//+------------------------------------------------------------------+
bool HasBullishGapConfirmation(const IndicatorState &ind, double supportLevel, double atr)
{
   double price = ind.closeArr[1];
   double tolerance = atr * 0.5;
   
   // Must be near support
   if(price > supportLevel + tolerance || price < supportLevel - atr)
      return false;
   
   // 1. Bullish engulfing
   if(IsBullishEngulfing(_Symbol, g_indicatorTF, 1))
   {
      Print("[GAP_CONFIRM] Bullish engulfing at support after gap down");
      return true;
   }
   
   // 2. Lower wick rejection (hammer)
   double lowerWick = MathMin(ind.openArr[1], ind.closeArr[1]) - ind.lowArr[1];
   double body = MathAbs(ind.closeArr[1] - ind.openArr[1]);
   double range = ind.highArr[1] - ind.lowArr[1];
   
   if(range > 0 && lowerWick > range * 0.60 && body < range * 0.30)
   {
      Print("[GAP_CONFIRM] Hammer at support after gap down");
      return true;
   }
   
   // 3. Bullish rejection
   if(IsBullishRejection(ind))
   {
      Print("[GAP_CONFIRM] Bullish rejection at support after gap down");
      return true;
   }
   
   // 4. Double bottom pattern
   if(ind.lowArr[1] >= supportLevel - tolerance && ind.lowArr[2] >= supportLevel - tolerance)
   {
      if(MathAbs(ind.lowArr[1] - ind.lowArr[2]) < atr * 0.2 && ind.closeArr[1] > ind.openArr[1])
      {
         Print("[GAP_CONFIRM] Double bottom at support after gap down");
         return true;
      }
   }
   
   // 5. Sweep below and reclaim
   if(ind.lowArr[1] < supportLevel - tolerance && ind.closeArr[1] > supportLevel)
   {
      Print("[GAP_CONFIRM] Sweep and reclaim at support after gap down");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Add a new gap setup                                               |
//+------------------------------------------------------------------+
void AddGapSetup(const IndicatorState &ind, double atr, ENUM_GAP_TYPE gapType,
                 double gapSize, double levelPrice, double levelHigh, double levelLow,
                 bool isIntoLevel, bool isBullTrend, bool isBearTrend)
{
   // Check if already tracking similar gap
   for(int i = 0; i < g_gapTracker.gapCount; i++)
   {
      if(MathAbs(g_gapTracker.activeGaps[i].majorLevelPrice - levelPrice) < atr * 0.3)
         return; // Already tracking
   }
   
   if(g_gapTracker.gapCount >= 3)
   {
      // Remove oldest gap
      for(int i = 0; i < 2; i++)
         g_gapTracker.activeGaps[i] = g_gapTracker.activeGaps[i + 1];
      g_gapTracker.gapCount = 2;
   }
   
   GapSetup gs;
   ZeroMemory(gs);
   gs.valid = true;
   gs.type = gapType;
   gs.state = GAP_STATE_DETECTED;
   gs.gapOpen = ind.openArr[1];
   gs.priorClose = ind.closeArr[2];
   gs.gapSize = gapSize;
   gs.gapSizeATR = gapSize / atr;
   gs.gapTime = TimeCurrent();
   gs.gapBarIndex = 1;
   gs.majorLevelPrice = levelPrice;
   gs.majorLevelHigh = levelHigh;
   gs.majorLevelLow = levelLow;
   gs.isIntoLevel = isIntoLevel;
   gs.isBullTrend = isBullTrend;
   gs.isBearTrend = isBearTrend;
   gs.barsSinceGap = 0;
   gs.confirmationSeen = false;
   
   // Determine setup direction and targets based on gap type and trend
   switch(gapType)
   {
      case GAP_UP_INTO_RESISTANCE:
         // DOWNTREND: Short candidate at resistance
         // UPTREND: Wait for breakout confirmation
         if(isBearTrend)
         {
            gs.isBuySetup = false;
            gs.gapFillTarget = gs.priorClose;  // Gap fill
            gs.stopLoss = levelHigh + atr * 0.40;
            gs.takeProfit = gs.gapFillTarget;  // First target is gap fill
         }
         else
         {
            // In uptrend, gap up into resistance could be breakout attempt
            gs.isBuySetup = true;
            gs.gapFillTarget = gs.priorClose;
            gs.stopLoss = levelLow - atr * 0.40;
            gs.takeProfit = FindNearestMajorResistanceLevel(gs.gapOpen, atr);
            if(gs.takeProfit <= gs.gapOpen) gs.takeProfit = gs.gapOpen + atr * 2.0;
         }
         break;
         
      case GAP_UP_THROUGH_RESISTANCE:
         // Breakout event - wait for retest (handled by breakout system)
         // But in uptrend, can be continuation buy after pullback
         gs.isBuySetup = true;
         gs.gapFillTarget = levelHigh;  // Retest target
         gs.stopLoss = levelLow - atr * 0.40;
         gs.takeProfit = FindNearestMajorResistanceLevel(gs.gapOpen, atr);
         if(gs.takeProfit <= gs.gapOpen) gs.takeProfit = gs.gapOpen + atr * 2.0;
         break;
         
      case GAP_DOWN_INTO_SUPPORT:
         // UPTREND: Buy candidate at support
         // DOWNTREND: Wait for support fail or bounce to resistance
         if(isBullTrend)
         {
            gs.isBuySetup = true;
            gs.gapFillTarget = gs.priorClose;  // Gap fill
            gs.stopLoss = levelLow - atr * 0.40;
            gs.takeProfit = gs.gapFillTarget;  // First target is gap fill
         }
         else
         {
            // In downtrend, gap down into support - wait for fail
            gs.isBuySetup = false;
            gs.gapFillTarget = gs.priorClose;
            gs.stopLoss = levelHigh + atr * 0.40;
            gs.takeProfit = FindNearestMajorSupportLevel(gs.gapOpen, atr);
            if(gs.takeProfit >= gs.gapOpen || gs.takeProfit <= 0) gs.takeProfit = gs.gapOpen - atr * 2.0;
         }
         break;
         
      case GAP_DOWN_THROUGH_SUPPORT:
         // Breakdown event - wait for retest (handled by breakout system)
         // In downtrend, can be continuation sell after pullback
         gs.isBuySetup = false;
         gs.gapFillTarget = levelLow;  // Retest target
         gs.stopLoss = levelHigh + atr * 0.40;
         gs.takeProfit = FindNearestMajorSupportLevel(gs.gapOpen, atr);
         if(gs.takeProfit >= gs.gapOpen || gs.takeProfit <= 0) gs.takeProfit = gs.gapOpen - atr * 2.0;
         break;
   }
   
   g_gapTracker.activeGaps[g_gapTracker.gapCount] = gs;
   g_gapTracker.gapCount++;
   
   Print("[GAP] Detected: type=", GapTypeToString(gapType),
         " size=", DoubleToString(gapSize, _Digits),
         " ATR=", DoubleToString(gs.gapSizeATR, 2),
         " level=", DoubleToString(levelPrice, _Digits),
         " trend=", isBullTrend ? "BULL" : (isBearTrend ? "BEAR" : "RANGE"),
         " setup=", gs.isBuySetup ? "BUY" : "SELL");
}

//+==================================================================+
//| SECTION 6: GAP DETECTION & TRACKING                             |
//| Gap detection, gap fill tracking, gap setup scoring              |
//+==================================================================+

//+------------------------------------------------------------------+
//| Update gap setups                                                 |
//+------------------------------------------------------------------+
void UpdateGapSetups(const IndicatorState &ind, double atr)
{
   double price = ind.closeArr[1];
   
   for(int i = 0; i < g_gapTracker.gapCount; i++)
   {
      GapSetup gs = g_gapTracker.activeGaps[i];
      if(!gs.valid) continue;
      
      gs.barsSinceGap++;
      
      switch(gs.state)
      {
         case GAP_STATE_DETECTED:
            gs.state = GAP_STATE_CONFIRMING;
            // Fall through to confirming
            
         case GAP_STATE_CONFIRMING:
            // Check for confirmation based on gap type
            if(gs.isBuySetup)
            {
               // Looking for bullish confirmation
               if(HasBullishGapConfirmation(ind, gs.majorLevelPrice, atr))
               {
                  gs.confirmationSeen = true;
                  gs.state = GAP_STATE_ENTRY_READY;
                  gs.entryPrice = price;
                  Print("[GAP] Entry READY: BUY at ", DoubleToString(price, _Digits),
                        " SL=", DoubleToString(gs.stopLoss, _Digits),
                        " TP=", DoubleToString(gs.takeProfit, _Digits));
               }
            }
            else
            {
               // Looking for bearish confirmation
               if(HasBearishGapConfirmation(ind, gs.majorLevelPrice, atr))
               {
                  gs.confirmationSeen = true;
                  gs.state = GAP_STATE_ENTRY_READY;
                  gs.entryPrice = price;
                  Print("[GAP] Entry READY: SELL at ", DoubleToString(price, _Digits),
                        " SL=", DoubleToString(gs.stopLoss, _Digits),
                        " TP=", DoubleToString(gs.takeProfit, _Digits));
               }
            }
            
            // Check for invalidation
            if(gs.isBuySetup)
            {
               // Buy setup invalidated if price closes decisively below support
               if(price < gs.majorLevelLow - atr * 0.5)
               {
                  gs.state = GAP_STATE_INVALIDATED;
                  Print("[GAP] INVALIDATED: price broke below support");
               }
            }
            else
            {
               // Sell setup invalidated if price closes decisively above resistance
               if(price > gs.majorLevelHigh + atr * 0.5)
               {
                  gs.state = GAP_STATE_INVALIDATED;
                  Print("[GAP] INVALIDATED: price broke above resistance");
               }
            }
            break;
            
         case GAP_STATE_ENTRY_READY:
            // Check if gap has been filled
            if(gs.isBuySetup && price >= gs.gapFillTarget)
            {
               gs.state = GAP_STATE_FILLED;
               Print("[GAP] Gap FILLED (bullish)");
            }
            else if(!gs.isBuySetup && price <= gs.gapFillTarget)
            {
               gs.state = GAP_STATE_FILLED;
               Print("[GAP] Gap FILLED (bearish)");
            }
            
            // Check for continued invalidation
            if(gs.isBuySetup && price < gs.majorLevelLow - atr * 0.5)
            {
               gs.state = GAP_STATE_INVALIDATED;
               Print("[GAP] Entry INVALIDATED after confirmation");
            }
            else if(!gs.isBuySetup && price > gs.majorLevelHigh + atr * 0.5)
            {
               gs.state = GAP_STATE_INVALIDATED;
               Print("[GAP] Entry INVALIDATED after confirmation");
            }
            break;
            
         case GAP_STATE_INVALIDATED:
         case GAP_STATE_FILLED:
            // These are terminal states
            break;
      }
      
      // Expire old gaps (>20 bars)
      if(gs.barsSinceGap > 20)
      {
         gs.valid = false;
         Print("[GAP] Expired: too old");
      }
      
      // Write back modified copy
      g_gapTracker.activeGaps[i] = gs;
   }
}

//+------------------------------------------------------------------+
//| Detect gap between current and previous bar                       |
//+------------------------------------------------------------------+
bool DetectGap(const IndicatorState &ind, double atr, double &outGapSize, bool &outIsGapUp)
{
   outGapSize = 0;
   outIsGapUp = false;
   
   double currentOpen = ind.openArr[1];
   double priorClose = ind.closeArr[2];
   double priorHigh = ind.highArr[2];
   double priorLow = ind.lowArr[2];
   
   // Gap up: current open > prior high
   if(currentOpen > priorHigh)
   {
      outGapSize = currentOpen - priorHigh;
      outIsGapUp = true;
      
      // Require minimum gap size (0.3 ATR)
      if(outGapSize >= atr * 0.3)
         return true;
   }
   // Gap down: current open < prior low
   else if(currentOpen < priorLow)
   {
      outGapSize = priorLow - currentOpen;
      outIsGapUp = false;
      
      // Require minimum gap size (0.3 ATR)
      if(outGapSize >= atr * 0.3)
         return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Scan for new gaps                                                 |
//+------------------------------------------------------------------+
void ScanForGaps(const IndicatorState &ind, double atr, bool isBullTrend, bool isBearTrend)
{
   double gapSize = 0;
   bool isGapUp = false;
   
   if(!DetectGap(ind, atr, gapSize, isGapUp))
      return;
   
   // Classify the gap
   double levelPrice = 0, levelHigh = 0, levelLow = 0;
   bool isIntoLevel = false;
   
   ENUM_GAP_TYPE gapType = ClassifyGap(ind.openArr[1], ind.closeArr[2], isGapUp, atr,
                                        levelPrice, levelHigh, levelLow, isIntoLevel);
   
   if(gapType == GAP_NONE)
   {
      Print("[GAP] Detected but no major level involved - ignoring");
      return;
   }
   
   // Add the gap setup
   AddGapSetup(ind, atr, gapType, gapSize, levelPrice, levelHigh, levelLow,
               isIntoLevel, isBullTrend, isBearTrend);
}

//+------------------------------------------------------------------+
//| Main gap tracker update function - call each bar                  |
//+------------------------------------------------------------------+
void UpdateGapTracker(const IndicatorState &ind, double atr, bool isBullTrend, bool isBearTrend)
{
   if(!g_gapTracker.valid)
      InitGapTracker();
   
   // Scan for new gaps
   ScanForGaps(ind, atr, isBullTrend, isBearTrend);
   
   // Update existing gap setups
   UpdateGapSetups(ind, atr);
}

//+------------------------------------------------------------------+
//| Check if gap buy entry is allowed                                 |
//+------------------------------------------------------------------+
bool IsGapBuyEntryAllowed(const IndicatorState &ind, double price, double atr,
                          double &outSL, double &outTP)
{
   outSL = 0;
   outTP = 0;
   
   for(int i = 0; i < g_gapTracker.gapCount; i++)
   {
      GapSetup gs = g_gapTracker.activeGaps[i];
      if(!gs.valid) continue;
      if(!gs.isBuySetup) continue;
      
      if(gs.state == GAP_STATE_ENTRY_READY)
      {
         // Check room to target
         double room = gs.takeProfit - price;
         double risk = price - gs.stopLoss;
         
         if(risk <= 0 || room < risk * 1.0)
         {
            Print("[GAP] Buy rejected: insufficient room to target");
            continue;
         }
         
         outSL = gs.stopLoss;
         outTP = gs.takeProfit;
         
         Print("[GAP_ENTRY] Gap BUY allowed: type=", GapTypeToString(gs.type),
               " SL=", DoubleToString(outSL, _Digits),
               " TP=", DoubleToString(outTP, _Digits));
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check if gap sell entry is allowed                                |
//+------------------------------------------------------------------+
bool IsGapSellEntryAllowed(const IndicatorState &ind, double price, double atr,
                           double &outSL, double &outTP)
{
   outSL = 0;
   outTP = 0;
   
   for(int i = 0; i < g_gapTracker.gapCount; i++)
   {
      GapSetup gs = g_gapTracker.activeGaps[i];
      if(!gs.valid) continue;
      if(gs.isBuySetup) continue;
      
      if(gs.state == GAP_STATE_ENTRY_READY)
      {
         // Check room to target
         double room = price - gs.takeProfit;
         double risk = gs.stopLoss - price;
         
         if(risk <= 0 || room < risk * 1.0)
         {
            Print("[GAP] Sell rejected: insufficient room to target");
            continue;
         }
         
         outSL = gs.stopLoss;
         outTP = gs.takeProfit;
         
         Print("[GAP_ENTRY] Gap SELL allowed: type=", GapTypeToString(gs.type),
               " SL=", DoubleToString(outSL, _Digits),
               " TP=", DoubleToString(outTP, _Digits));
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Get gap type as string                                            |
//+------------------------------------------------------------------+
string GapTypeToString(ENUM_GAP_TYPE type)
{
   switch(type)
   {
      case GAP_NONE:                    return "NONE";
      case GAP_UP_INTO_RESISTANCE:      return "UP_INTO_RESISTANCE";
      case GAP_UP_THROUGH_RESISTANCE:   return "UP_THROUGH_RESISTANCE";
      case GAP_DOWN_INTO_SUPPORT:       return "DOWN_INTO_SUPPORT";
      case GAP_DOWN_THROUGH_SUPPORT:    return "DOWN_THROUGH_SUPPORT";
      default:                          return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| Get gap state as string                                           |
//+------------------------------------------------------------------+
string GapStateToString(ENUM_GAP_STATE state)
{
   switch(state)
   {
      case GAP_STATE_DETECTED:    return "DETECTED";
      case GAP_STATE_CONFIRMING:  return "CONFIRMING";
      case GAP_STATE_ENTRY_READY: return "ENTRY_READY";
      case GAP_STATE_INVALIDATED: return "INVALIDATED";
      case GAP_STATE_FILLED:      return "FILLED";
      default:                    return "UNKNOWN";
   }
}

//+------------------------------------------------------------------+
//| CHANNEL ENTRY LOGIC - Trade trends and reversals in channels     |
//+------------------------------------------------------------------+

// Channel entry setup struct
struct ChannelEntrySetup
{
   bool   valid;
   bool   isBuy;
   bool   isTrendEntry;     // true = with trend, false = reversal
   double entryPrice;
   double stopLoss;
   double takeProfit;
   double channelSupport;
   double channelResistance;
   string reason;
};

// Check for bullish confirmation candle
bool HasBullishChannelConfirmation(const IndicatorState &ind)
{
   double open1  = ind.openArr[1];
   double close1 = ind.closeArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];
   double range  = high1 - low1;
   
   if(range <= 0) return false;
   
   // Bullish engulfing or strong bull close
   bool bullishClose = (close1 > open1);
   bool strongBody   = (close1 - open1) > range * 0.5;
   bool lowerWick    = (open1 - low1) > range * 0.3;  // Rejection wick
   
   return (bullishClose && (strongBody || lowerWick));
}

// Check for bearish confirmation candle
bool HasBearishChannelConfirmation(const IndicatorState &ind)
{
   double open1  = ind.openArr[1];
   double close1 = ind.closeArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];
   double range  = high1 - low1;
   
   if(range <= 0) return false;
   
   // Bearish engulfing or strong bear close
   bool bearishClose = (close1 < open1);
   bool strongBody   = (open1 - close1) > range * 0.5;
   bool upperWick    = (high1 - open1) > range * 0.3;  // Rejection wick
   
   return (bearishClose && (strongBody || upperWick));
}

//+------------------------------------------------------------------+
//| Check for TREND entry at channel support (BUY in bull channel)   |
//+------------------------------------------------------------------+
ChannelEntrySetup CheckChannelTrendBuy(const IndicatorState &ind, double atr)
{
   ChannelEntrySetup setup;
   ZeroMemory(setup);
   setup.valid = false;
   
   if(!g_structure.valid || !g_structure.channel.valid) return setup;
   
   // Allow bull channel OR range (for flexibility)
   // Skip only if strongly bear
   if(g_structure.state == STRUCTURE_BEAR_TREND)
      return setup;
   
   double price = ind.closeArr[1];
   double channelSup = g_structure.dynamicSupport;
   double channelRes = g_structure.dynamicResistance;
   
   // Price must be in lower half of channel (near support)
   double channelMid = (channelSup + channelRes) / 2.0;
   if(price > channelMid) return setup;  // Too high, wait for pullback
   
   // Looser confirmation - just need bullish close or rejection wick
   bool bullClose = (ind.closeArr[1] > ind.openArr[1]);
   bool rejectionWick = (ind.openArr[1] - ind.lowArr[1]) > (ind.highArr[1] - ind.lowArr[1]) * 0.25;
   if(!bullClose && !rejectionWick)
      return setup;
   
   // Calculate room to target
   double roomToTarget = channelRes - price;
   if(roomToTarget < atr * 1.0) return setup;  // Need at least 1 ATR room
   
   // Build setup
   setup.valid = true;
   setup.isBuy = true;
   setup.isTrendEntry = true;
   setup.entryPrice = price;
   setup.channelSupport = channelSup;
   setup.channelResistance = channelRes;
   setup.stopLoss = channelSup - atr * 0.7;  // Give more breathing room
   setup.takeProfit = channelRes - atr * 0.15;
   setup.reason = "CHANNEL_TREND_BUY | pullback to channel support";
   
   Print("[CHANNEL_ENTRY] TREND BUY setup: price=", DoubleToString(price, _Digits),
         " channelSup=", DoubleToString(channelSup, _Digits),
         " channelRes=", DoubleToString(channelRes, _Digits),
         " SL=", DoubleToString(setup.stopLoss, _Digits),
         " TP=", DoubleToString(setup.takeProfit, _Digits));
   
   return setup;
}

//+------------------------------------------------------------------+
//| Check for TREND entry at channel resistance (SELL in bear channel)|
//+------------------------------------------------------------------+
ChannelEntrySetup CheckChannelTrendSell(const IndicatorState &ind, double atr)
{
   ChannelEntrySetup setup;
   ZeroMemory(setup);
   setup.valid = false;
   
   if(!g_structure.valid || !g_structure.channel.valid) return setup;
   
   // Allow bear channel OR range (for flexibility)
   // Skip only if strongly bull
   if(g_structure.state == STRUCTURE_BULL_TREND)
      return setup;
   
   double price = ind.closeArr[1];
   double channelSup = g_structure.dynamicSupport;
   double channelRes = g_structure.dynamicResistance;
   
   // Price must be in upper half of channel (near resistance)
   double channelMid = (channelSup + channelRes) / 2.0;
   if(price < channelMid) return setup;  // Too low, wait for rally
   
   // Looser confirmation - just need bearish close or rejection wick
   bool bearClose = (ind.closeArr[1] < ind.openArr[1]);
   bool rejectionWick = (ind.highArr[1] - ind.openArr[1]) > (ind.highArr[1] - ind.lowArr[1]) * 0.25;
   if(!bearClose && !rejectionWick)
      return setup;
   
   // Calculate room to target
   double roomToTarget = price - channelSup;
   if(roomToTarget < atr * 1.0) return setup;  // Need at least 1 ATR room
   
   // Build setup
   setup.valid = true;
   setup.isBuy = false;
   setup.isTrendEntry = true;
   setup.entryPrice = price;
   setup.channelSupport = channelSup;
   setup.channelResistance = channelRes;
   setup.stopLoss = channelRes + atr * 0.7;  // Give more breathing room
   setup.takeProfit = channelSup + atr * 0.15;
   setup.reason = "CHANNEL_TREND_SELL | pullback to channel resistance";
   
   Print("[CHANNEL_ENTRY] TREND SELL setup: price=", DoubleToString(price, _Digits),
         " channelSup=", DoubleToString(channelSup, _Digits),
         " channelRes=", DoubleToString(channelRes, _Digits));
   
   return setup;
}

//+------------------------------------------------------------------+
//| Check for REVERSAL entry at channel resistance (SELL at top)     |
//+------------------------------------------------------------------+
ChannelEntrySetup CheckChannelReversalSell(const IndicatorState &ind, double atr)
{
   ChannelEntrySetup setup;
   ZeroMemory(setup);
   setup.valid = false;
   
   if(!g_structure.valid || !g_structure.channel.valid) return setup;
   
   double price = ind.closeArr[1];
   double channelSup = g_structure.dynamicSupport;
   double channelRes = g_structure.dynamicResistance;
   double channelHeight = channelRes - channelSup;
   
   // CRITICAL: Price must be within 1.5 ATR of channel resistance
   // Don't try to sell if price has broken far above channel
   double distFromRes = price - channelRes;
   if(distFromRes > atr * 1.5)
   {
      // Price too far above channel - channel is stale
      return setup;
   }
   
   // Price must be in upper 25% of channel OR slightly above (overextended)
   double upperZone = channelRes - channelHeight * 0.25;
   if(price < upperZone) return setup;
   
   // EMA FILTER: Don't sell reversals when EMA50 > EMA200 (bullish alignment)
   double ema50 = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   if(ema50 > ema200)
   {
      // Bull trend alignment - don't try counter-trend reversal sells
      return setup;
   }
   
   // Looser confirmation - bearish close or upper rejection wick
   bool bearClose = (ind.closeArr[1] < ind.openArr[1]);
   bool rejectionWick = (ind.highArr[1] - MathMax(ind.openArr[1], ind.closeArr[1])) > channelHeight * 0.05;
   if(!bearClose && !rejectionWick)
      return setup;
   
   // Check for overextension above channel
   bool overextended = (ind.highArr[1] > channelRes);
   
   // Calculate room to target (channel support)
   double roomToTarget = price - channelSup;
   if(roomToTarget < atr * 1.5) return setup;  // Need 1.5 ATR room
   
   // Build setup - SL MUST be ABOVE entry price for SELL
   setup.valid = true;
   setup.isBuy = false;
   setup.isTrendEntry = false;  // Reversal
   setup.entryPrice = price;
   setup.channelSupport = channelSup;
   setup.channelResistance = channelRes;
   
   // SL calculation: Use the higher of (channelRes + buffer) or (price + min buffer)
   double slFromChannel = channelRes + atr * 0.5;
   double slMinAboveEntry = price + atr * 0.5;
   setup.stopLoss = MathMax(slFromChannel, slMinAboveEntry);
   
   setup.takeProfit = channelSup + atr * 0.2;
   setup.reason = overextended ? "CHANNEL_REVERSAL_SELL | overextended at resistance" 
                               : "CHANNEL_REVERSAL_SELL | rejection at resistance";
   
   Print("[CHANNEL_ENTRY] REVERSAL SELL setup: price=", DoubleToString(price, _Digits),
         " channelRes=", DoubleToString(channelRes, _Digits),
         " overextended=", overextended,
         " SL=", DoubleToString(setup.stopLoss, _Digits),
         " TP=", DoubleToString(setup.takeProfit, _Digits));
   
   return setup;
}

//+------------------------------------------------------------------+
//| Check for REVERSAL entry at channel support (BUY at bottom)      |
//+------------------------------------------------------------------+
ChannelEntrySetup CheckChannelReversalBuy(const IndicatorState &ind, double atr)
{
   ChannelEntrySetup setup;
   ZeroMemory(setup);
   setup.valid = false;
   
   if(!g_structure.valid || !g_structure.channel.valid) return setup;
   
   double price = ind.closeArr[1];
   double channelSup = g_structure.dynamicSupport;
   double channelRes = g_structure.dynamicResistance;
   double channelHeight = channelRes - channelSup;
   
   // CRITICAL: Price must be within 1.5 ATR of channel support
   // Don't try to buy if price has broken far below channel
   double distFromSup = channelSup - price;
   if(distFromSup > atr * 1.5)
   {
      // Price too far below channel - channel is stale
      return setup;
   }
   
   // Price must be in lower 25% of channel OR slightly below (overextended)
   double lowerZone = channelSup + channelHeight * 0.25;
   if(price > lowerZone) return setup;
   
   // EMA FILTER: Don't buy reversals when EMA50 < EMA200 (bearish alignment)
   double ema50 = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   if(ema50 < ema200)
   {
      // Bear trend alignment - don't try counter-trend reversal buys
      return setup;
   }
   
   // Looser confirmation - bullish close or lower rejection wick
   bool bullClose = (ind.closeArr[1] > ind.openArr[1]);
   bool rejectionWick = (MathMin(ind.openArr[1], ind.closeArr[1]) - ind.lowArr[1]) > channelHeight * 0.05;
   if(!bullClose && !rejectionWick)
      return setup;
   
   // Check for overextension below channel
   bool overextended = (ind.lowArr[1] < channelSup);
   
   // Calculate room to target (channel resistance)
   double roomToTarget = channelRes - price;
   if(roomToTarget < atr * 1.5) return setup;  // Need 1.5 ATR room
   
   // Build setup - SL MUST be BELOW entry price for BUY
   setup.valid = true;
   setup.isBuy = true;
   setup.isTrendEntry = false;  // Reversal
   setup.entryPrice = price;
   setup.channelSupport = channelSup;
   setup.channelResistance = channelRes;
   
   // SL calculation: Use the lower of (channelSup - buffer) or (price - min buffer)
   double slFromChannel = channelSup - atr * 0.5;
   double slMinBelowEntry = price - atr * 0.5;
   setup.stopLoss = MathMin(slFromChannel, slMinBelowEntry);
   
   setup.takeProfit = channelRes - atr * 0.2;
   setup.reason = overextended ? "CHANNEL_REVERSAL_BUY | overextended at support" 
                               : "CHANNEL_REVERSAL_BUY | rejection at support";
   
   Print("[CHANNEL_ENTRY] REVERSAL BUY setup: price=", DoubleToString(price, _Digits),
         " channelSup=", DoubleToString(channelSup, _Digits),
         " overextended=", overextended,
         " SL=", DoubleToString(setup.stopLoss, _Digits),
         " TP=", DoubleToString(setup.takeProfit, _Digits));
   
   return setup;
}

//+------------------------------------------------------------------+
//| Find best channel entry (trend first, then reversal)             |
//+------------------------------------------------------------------+
ChannelEntrySetup FindBestChannelEntry(const IndicatorState &ind, double atr, bool preferBuy)
{
   ChannelEntrySetup setup;
   ZeroMemory(setup);
   setup.valid = false;
   
   if(!g_structure.valid || !g_structure.channel.valid)
      return setup;
   
   if(preferBuy)
   {
      // Try trend buy first (bull channel pullback)
      setup = CheckChannelTrendBuy(ind, atr);
      if(setup.valid) return setup;
      
      // Try reversal buy (at channel support extreme)
      setup = CheckChannelReversalBuy(ind, atr);
      if(setup.valid) return setup;
   }
   else
   {
      // Try trend sell first (bear channel pullback)
      setup = CheckChannelTrendSell(ind, atr);
      if(setup.valid) return setup;
      
      // Try reversal sell (at channel resistance extreme)
      setup = CheckChannelReversalSell(ind, atr);
      if(setup.valid) return setup;
   }
   
   return setup;
}

//+------------------------------------------------------------------+
//| CHANNEL VISUALIZATION - Draw diagonal channel on chart           |
//+------------------------------------------------------------------+
#define CHANNEL_OBJ_PREFIX "MS_CHANNEL_"

int GetDiagonalChannelLookback()
{
   int barsAvailable = iBars(_Symbol, g_indicatorTF);
   if(barsAvailable <= 10)
      return 0;

   int farthestSwing = 0;
   int useHighs = MathMin(g_structure.swingHighCount, 4);
   int useLows  = MathMin(g_structure.swingLowCount, 4);

   for(int i = 0; i < useHighs; i++)
   {
      if(g_structure.swingHighs[i].valid)
         farthestSwing = MathMax(farthestSwing, g_structure.swingHighs[i].barIndex);
   }

   for(int i = 0; i < useLows; i++)
   {
      if(g_structure.swingLows[i].valid)
         farthestSwing = MathMax(farthestSwing, g_structure.swingLows[i].barIndex);
   }

   int barsBack = MathMax(200, farthestSwing + 20);
   int maxAllowed = barsAvailable - 5;
   if(maxAllowed < 20)
      return 0;

   if(barsBack > maxAllowed)
      barsBack = maxAllowed;

   return barsBack;
}

bool UpsertTrendObject(const string name,
                       datetime t1, double p1,
                       datetime t2, double p2,
                       color clr, int width, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2))
         return false;
   }
   else
   {
      ObjectMove(0, name, 0, t1, p1);
      ObjectMove(0, name, 1, t2, p2);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   return true;
}

bool UpsertHLineObject(const string name,
                       double price,
                       color clr, int width, ENUM_LINE_STYLE style)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
         return false;
   }

   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   return true;
}

bool UpsertTextObject(const string name,
                      datetime t, double p,
                      const string text,
                      color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, p))
         return false;
   }
   else
   {
      ObjectMove(0, name, 0, t, p);
   }

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   return true;
}

void DeleteLegacyStructureChannelObjects()
{
   // Delete trend-line mode active line
   ObjectDelete(0, "TRENDLINE_ACTIVE");
   
   // Delete legacy channel boundary lines
   ObjectDelete(0, "CHANNEL_UPPER_ACTIVE");
   ObjectDelete(0, "CHANNEL_LOWER_ACTIVE");
   
   // Clean up any old channel objects that might exist
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "UPPER");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "LOWER");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "MID");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "LABEL");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "DYN_SUP");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "DYN_RES");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "DYN_SUP_TOP");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "DYN_SUP_BOT");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "DYN_RES_TOP");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "DYN_RES_BOT");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "SUP_ZONE_TOP");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "SUP_ZONE_BOT");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "RES_ZONE_TOP");
   ObjectDelete(0, CHANNEL_OBJ_PREFIX + "RES_ZONE_BOT");
}

// REMOVED: DrawDiagonalChannel - channel drawing owned by ChannelBuilder

//+------------------------------------------------------------------+
//| Clear Old Local Trendline Only - Preserve H4 Channel Objects     |
//+------------------------------------------------------------------+
void ClearOldLocalTrendlineOnly()
{
   ObjectDelete(0, "TRENDLINE_ACTIVE");

   // Preserve H4 channel objects - do NOT delete:
   // H4_VISUAL_CH_UPPER
   // H4_VISUAL_CH_LOWER
   // H4_BROKEN_CH_UPPER
   // H4_BROKEN_CH_LOWER
}

//+------------------------------------------------------------------+
//| IsChannelBroken overload for DiagonalChannel compatibility       |
//+------------------------------------------------------------------+
bool IsChannelBroken(const DiagonalChannel &ch, double price)
{
   if(!ch.valid || ch.state != CHANNEL_STATE_ACTIVE)
      return true;
      
   double atr = GetATR(g_ind, 1);
   if(atr <= 0.0) return false;
   
   double buffer = atr * 0.25;
   double upper = ch.upperIntercept + ch.upperSlope * 1;
   double lower = ch.lowerIntercept + ch.lowerSlope * 1;
   
   if(price > upper + buffer || price < lower - buffer)
      return true;
      
   return false;
}

//+------------------------------------------------------------------+
//| Strict Structure Validation - Only True Trends Allowed           |
//+------------------------------------------------------------------+
bool IsBullishStructureValid()
{
   return (g_structure.state == STRUCTURE_BULL_TREND);
}

bool IsBearishStructureValid()
{
   return (g_structure.state == STRUCTURE_BEAR_TREND);
}

//+------------------------------------------------------------------+
//| Wick Midpoint Helpers - Anchor through middle of reaction wicks  |
//+------------------------------------------------------------------+
double LowerWickMidPrice(const double openPrice,
                         const double closePrice,
                         const double lowPrice)
{
   double bodyLow = MathMin(openPrice, closePrice);
   return lowPrice + (bodyLow - lowPrice) * 0.50;
}

double UpperWickMidPrice(const double openPrice,
                         const double closePrice,
                         const double highPrice)
{
   double bodyHigh = MathMax(openPrice, closePrice);
   return bodyHigh + (highPrice - bodyHigh) * 0.50;
}

bool GetBarOHLC(const ENUM_TIMEFRAMES tf,
                const int shift,
                double &o, double &h, double &l, double &c,
                datetime &t)
{
   t = iTime(_Symbol, tf, shift);
   o = iOpen(_Symbol, tf, shift);
   h = iHigh(_Symbol, tf, shift);
   l = iLow(_Symbol, tf, shift);
   c = iClose(_Symbol, tf, shift);

   return (t > 0 && o > 0 && h > 0 && l > 0 && c > 0);
}

//+------------------------------------------------------------------+
//| Find Beginning of Active Trend Run                               |
//+------------------------------------------------------------------+
int FindBullTrendStartIndex()
{
   int startIdx = -1;

   for(int i = g_structure.swingLowCount - 1; i >= 0; i--)
   {
      if(g_structure.swingLows[i].isHigherLow)
         startIdx = i;
      else if(startIdx >= 0)
         break;
   }

   return startIdx;
}

int FindBearTrendStartIndex()
{
   int startIdx = -1;

   for(int i = g_structure.swingHighCount - 1; i >= 0; i--)
   {
      if(g_structure.swingHighs[i].isLowerHigh)
         startIdx = i;
      else if(startIdx >= 0)
         break;
   }

   return startIdx;
}

//+------------------------------------------------------------------+
//| Collect Bull Trend Anchors - From Trend Start, Through Wick Mids |
//+------------------------------------------------------------------+
int CollectBullTrendAnchors(TrendAnchor &anchors[])
{
   int count = 0;
   ArrayResize(anchors, g_structure.swingLowCount);

   int startIdx = FindBullTrendStartIndex();
   if(startIdx < 0)
   {
      ArrayResize(anchors, 0);
      return 0;
   }

   for(int i = startIdx; i >= 0; i--)
   {
      if(!g_structure.swingLows[i].isHigherLow)
         continue;

      int barShift = g_structure.swingLows[i].barIndex;

      double o, h, l, c;
      datetime t;
      if(!GetBarOHLC(PERIOD_D1, barShift, o, h, l, c, t))
         continue;

      double wickMid = LowerWickMidPrice(o, c, l);

      anchors[count].t = t;
      anchors[count].p = wickMid;
      anchors[count].b = barShift;
      count++;
   }

   ArrayResize(anchors, count);
   SortTrendAnchorsByTime(anchors, count);
   return count;
}

int CollectBearTrendAnchors(TrendAnchor &anchors[])
{
   int count = 0;
   ArrayResize(anchors, g_structure.swingHighCount);

   int startIdx = FindBearTrendStartIndex();
   if(startIdx < 0)
   {
      ArrayResize(anchors, 0);
      return 0;
   }

   for(int i = startIdx; i >= 0; i--)
   {
      if(!g_structure.swingHighs[i].isLowerHigh)
         continue;

      int barShift = g_structure.swingHighs[i].barIndex;

      double o, h, l, c;
      datetime t;
      if(!GetBarOHLC(PERIOD_D1, barShift, o, h, l, c, t))
         continue;

      double wickMid = UpperWickMidPrice(o, c, h);

      anchors[count].t = t;
      anchors[count].p = wickMid;
      anchors[count].b = barShift;
      count++;
   }

   ArrayResize(anchors, count);
   SortTrendAnchorsByTime(anchors, count);
   return count;
}

//+==================================================================+
//| SECTION 7: D1 TRENDLINE, BREAKOUT & REVERSAL STATE              |
//| D1 trendline stub, breakout tracker, reversal state machine       |
//+==================================================================+

// TREND LINE CODE REMOVED - All trend line functions deleted per user request

//+------------------------------------------------------------------+
//| Check if structure is consolidating                                 |
//+------------------------------------------------------------------+
bool IsTrendStructureConsolidating(const IndicatorState &ind, double atr)
{
   // Consolidation if:
   // 1. No clear HH/HL or LH/LL sequence
   // 2. ADX is weak
   // 3. EMAs are compressed

   if(g_structure.state == STRUCTURE_CONSOLIDATION)
      return true;

   if(g_structure.state == STRUCTURE_RANGE)
      return true;

   // Check if consecutive counts are low
   if(g_structure.consecutiveHH < 1 && g_structure.consecutiveHL < 1 &&
      g_structure.consecutiveLH < 1 && g_structure.consecutiveLL < 1)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Update Breakout Tracker (stub - actual implementation elsewhere)|
//+------------------------------------------------------------------+
void UpdateBreakoutTracker(const IndicatorState &ind, double atr)
{
   // Placeholder - implement actual breakout tracking logic
   // For now, just mark tracker as valid
   if(!g_breakout.valid)
   {
      g_breakout.valid = true;
      g_breakout.bullCount = 0;
      g_breakout.bearCount = 0;
   }
}

//+------------------------------------------------------------------+
//| Update Reversal State (stub - actual implementation elsewhere)  |
//+------------------------------------------------------------------+
void UpdateReversalState(const IndicatorState &ind, double atr, double nearestSupport, double nearestResist)
{
   // Placeholder - implement actual reversal tracking logic
   // For now, just mark tracker as valid
   if(!g_reversal.valid)
   {
      g_reversal.valid = true;
      g_reversal.bullState = REVERSAL_NONE;
      g_reversal.bearState = REVERSAL_NONE;
   }
}

#endif // MARKET_STRUCTURE_MQH
