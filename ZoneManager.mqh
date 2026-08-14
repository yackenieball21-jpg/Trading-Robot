//+------------------------------------------------------------------+
//|                                                  ZoneManager.mqh |
//|  Persistent market-structure zone engine v7.1                    |
//|  Two-layer registry: active + historical with stable IDs         |
//|  No reference-to-array-element patterns (MQL5 safe)              |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef ZONE_MANAGER_MQH
#define ZONE_MANAGER_MQH

#include "SymbolProfiler.mqh"
#include "IndicatorManager.mqh"

//+------------------------------------------------------------------+
//| Zone Type Enumeration                                            |
//+------------------------------------------------------------------+
enum ENUM_ZONE_TYPE
{
   ZONE_DEMAND_MAJOR,
   ZONE_DEMAND_MINOR,
   ZONE_SUPPLY_MAJOR,
   ZONE_SUPPLY_MINOR,
   ZONE_DEMAND,
   ZONE_SUPPLY,
   ZONE_EMA_CONFLUENCE
};

// Backward-compatible aliases.
// The EA now displays/trades PDF-style Demand/Supply,
// but older modules may still use Support/Resistance names.
#define ZONE_SUPPORT_MAJOR     ZONE_DEMAND_MAJOR
#define ZONE_SUPPORT_MINOR     ZONE_DEMAND_MINOR
#define ZONE_RESISTANCE_MAJOR  ZONE_SUPPLY_MAJOR
#define ZONE_RESISTANCE_MINOR  ZONE_SUPPLY_MINOR

//+------------------------------------------------------------------+
//| Zone Family — for merge compatibility                            |
//+------------------------------------------------------------------+
enum ENUM_ZONE_FAMILY
{
   ZFAM_DEMAND,
   ZFAM_SUPPLY,
   ZFAM_DEMAND_ALT,
   ZFAM_SUPPLY_ALT,
   ZFAM_EMA,
   ZFAM_UNKNOWN
};

#define ZFAM_SUPPORT     ZFAM_DEMAND
#define ZFAM_RESISTANCE  ZFAM_SUPPLY

//+------------------------------------------------------------------+
//| Level Hierarchy — for zone importance                            |
//+------------------------------------------------------------------+
enum ENUM_LEVEL_HIERARCHY
{
   LEVEL_LTF_REFINEMENT,
   LEVEL_HTF_MINOR,
   LEVEL_HTF_MAJOR,
   LEVEL_FLIPPED,
   LEVEL_DYNAMIC
};

//+------------------------------------------------------------------+
//| Canonical Zone Role - fixed role assignment                       |
//+------------------------------------------------------------------+
enum ZONE_CANONICAL_ROLE
{
   ZROLE_UNKNOWN = 0,
   ZROLE_DEMAND = 1,
   ZROLE_SUPPLY = 2
};

// Backward-compatible canonical role aliases.
// Older logic still says Support/Resistance, but the new model is Demand/Supply.
#define ZROLE_SUPPORT     ZROLE_DEMAND
#define ZROLE_RESISTANCE  ZROLE_SUPPLY

//+------------------------------------------------------------------+
//| Zone Strategy Role - for trend vs range vs counter-trend           |
//+------------------------------------------------------------------+
enum ZONE_STRATEGY_ROLE
{
   ZROLE_NONE = 0,
   ZROLE_TREND_CONTINUATION,
   ZROLE_COUNTERTREND_EXHAUSTION,
   ZROLE_RANGE_DEMAND,
   ZROLE_RANGE_SUPPLY,
   ZROLE_BREAKOUT_RETEST,
   ZROLE_SUPPLY_DEMAND
};

// Backward-compatible strategy role aliases.
#define ZROLE_RANGE_SUPPORT     ZROLE_RANGE_DEMAND
#define ZROLE_RANGE_RESISTANCE  ZROLE_RANGE_SUPPLY

//+------------------------------------------------------------------+
//| S/D Marking Method - PDF zone detection method selector          |
//+------------------------------------------------------------------+
enum ENUM_SD_MARKING_METHOD
{
   SD_MARK_METHOD_MOMENTUM = 0,       // PDF method #1: 3+ momentum candles, mark previous candle/base
   SD_MARK_METHOD_CONSOLIDATION = 1,  // PDF method #2: mark sideways consolidation base
   SD_MARK_METHOD_WICK = 2            // PDF method #3: mark rejection wick area
};

//+------------------------------------------------------------------+
//| Zone Strength Mode - for filtering zones by quality              |
//+------------------------------------------------------------------+
enum ENUM_ZONE_STRENGTH_MODE
{
   ZONE_STRENGTH_ALL,                 // Show/trade all valid zones
   ZONE_STRENGTH_STRONG_ONLY,         // Show/trade only strong zones
   ZONE_STRENGTH_MODERATE_AND_STRONG, // Show/trade moderate and strong zones
   ZONE_STRENGTH_WEAK_ONLY            // Show/trade only weak zones
};

//+------------------------------------------------------------------+
//| Zone Data Structure — full persistent fields                     |
//+------------------------------------------------------------------+
struct ZoneInfo
{
   int            id;
   ENUM_ZONE_TYPE type;
   double         upperBound;
   double         lowerBound;
   double         midPoint;
   datetime       createdTime;
   datetime       lastTouchedTime;
   datetime       lastEvaluatedTime;
   bool           protectedKeyZone;
   int            parentZoneId;
   int            generation;
   int            retestCount;
   int            cleanTouchCount;
   int            rawTouches;
   double         breakScore;
   double         reactionScore;
   int            breakConfirmCount;
   int            relatedHistoricalZoneId;
   bool           isRefinement;
   bool           isFlipZone;
   bool           isRetestOfHistoricalZone;
   string         label;
   
   // Active flags
   bool           valid;
   bool           active;
   bool           historical;
   bool           broken;
   bool           traded;
   
   // Strength and scoring
   double         strength;
   double         freshness;
   double         score;
   
   // Additional fields
   int            ageInBars;
   int            firstSeenBar;
   double         rejectionScore;
   double         breakoutScore;
   double         volumeScore;
   double         structuralScore;
   int            lastTouchBar;
   bool           isBreakoutOrigin;
   bool           hasRejection;
   int            lastSweepBar;
   datetime       lastTradeTime;
   bool           reversalCandidate;
   double         reversalScore;
   double         continuationScore;
   ENUM_TIMEFRAMES sourceTF;
   int            lastStructureBreakBar;
   bool           isRoundNumber;
   bool           isSessionLevel;
   double         execBandLow;
   double         execBandHigh;
   bool           hasExecBand;
   int            sourceBarIndex;
   datetime       sourceSwingTime;
   string         structuralSide;
   
   // Structural information
   bool           structuralAnchor;
   string         structuralTag;
   string         sdCreationMethod;   // MOMENTUM, CONSOLIDATION, WICK, FLIP, UNKNOWN
   int            sequenceIndex;
   bool           structuralLocked;
   
   // Zone family and hierarchy
   ENUM_ZONE_FAMILY family;
   ENUM_LEVEL_HIERARCHY hierarchy;
   bool           majorTFZone;
   bool           isPrimary;
   bool           isBackup;
   bool           isExecutionEligible;
   
   // STEP 8: Separate TP target zones from active trading zones
   bool           isTPTargetOnly;  // Zone used only for TP targeting, not for entries
   
   // Flip and refinement tracking
   bool           confirmedRetest;
   bool           flipRetestConfirmed;
   bool           continuationEligible;
   bool           breakRetestReady;
   bool           failedRetest;
   int            breakBarIndex;
   
   // Original type tracking for flip zones
   ENUM_ZONE_TYPE originalType;

   // Quality scoring fields (Patch 15)
   double departureATR;
   double structureImpactScore;
   double freshnessScore;
   double htfVisibilityScore;
   double cleanShapeScore;
   double rejectionQualityScore;
   double confluenceScore;
   double qualityScore;
   int    touchCountTotal;
   int    rejections;
   bool   majorQualified;
   int    qualityChecklistHits;

   // High-probability institutional S/D markers
   bool   ledToBOS;            // Creation impulse broke prior swing structure
   bool   causedZoneFailure;   // Creation impulse invalidated an older opposing zone

   // Strategy role for trend vs range vs counter-trend
   ZONE_STRATEGY_ROLE strategyRole;
};

//+------------------------------------------------------------------+
//| Primary Zones - Only 2 zones used for trading                     |
//+------------------------------------------------------------------+
struct PrimaryZones
{
   ZoneInfo support;
   ZoneInfo resistance;
   
   bool hasSupport;
   bool hasResistance;
};

struct VisualLineSet
{
   ZoneInfo zones[12];   // nearest 6 below + nearest 6 above
   int      count;
   datetime anchorBarTime;
};

VisualLineSet g_visualD1Cache;
bool          g_visualD1CacheValid = false;
datetime      g_visualD1CacheBarTime = 0;

VisualLineSet g_lastDrawnVisualD1;
bool          g_lastDrawnVisualValid = false;

//+------------------------------------------------------------------+
//| Zone Registry - Unified persistent storage                        |
//| Constants                                                        |
//+------------------------------------------------------------------+
#define ZM_MAX_ACTIVE         16
#define ZM_MAX_ACTIVE_PER_DIR  5
#define ZM_MAX_HISTORICAL  30
#define ZM_MAX_TOTAL       80
#define ZM_HISTORY_BARS    300
#define ZM_FRESH_BARS      40
int g_zoneSwingLookback = 4;
#define ZM_LIFETIME_BARS   500
#define ZM_BREAK_CONFIRM   2
#define ZM_BREAK_ATR_MULT  0.15
#define ZM_TOUCH_COOLDOWN  3
#define ZM_KEY_ZONE_MIN_TOUCHES 3
#define ZM_KEY_ZONE_MIN_STR     0.55
#define ZM_MERGE_MAX_WIDTH_RATIO 3.0
#define ZM_MERGE_MAX_AGE_DIFF    150

// Supply/Demand active zone display policy constants
#define SD_ACTIVE_MAX_WIDTH_ATR          2.25
#define SD_ACTIVE_MAX_CLEAN_TOUCHES      6
#define SD_ACTIVE_NEAR_ATR               5.00
#define SD_ACTIVE_PAIR_FALLBACK_MAX_ATR  10.00
#define SD_FLIP_RETEST_KEEP_BARS         36

// g_atrScale is set dynamically each bar: atrRef / atrLive
// Keeps all ATR-distance multipliers proportional to original (ATRReferencePeriod) tuning.
// e.g. ATRlive=14 is bigger than ATRref=20 → scale<1 → distances shrink proportionally.
double g_atrScale = 1.0;

// Visual-only filter flags (Patch 1)
bool   g_showOnlyPresentZones      = true;
bool   g_showHistoricalZones       = false;
bool   g_showArchivedChannels      = false;
bool   g_showOnlyCurrentChannel    = true;
bool   g_deletePastZoneObjects     = true;
int    g_maxVisibleSupportZones    = 3;
int    g_maxVisibleResistanceZones = 3;
double g_lastDrawPrice             = 0.0;
double g_lastDrawAtr               = 0.0;

// Zone lookback configuration (D1 horizontal zones: 6 months to 1 year)
int g_zoneStartupLookbackBars = 260;
int g_zoneRefreshLookbackBars = 130;
int g_zoneLifetimeBars        = 260;

// Active Supply/Demand pair selection
int g_activeDemandZoneId = -1;
int g_activeSupplyZoneId = -1;

int g_backupDemandZoneIds[];
int g_backupSupplyZoneIds[];

datetime g_lastActiveSDSelectionTime = 0;

//+------------------------------------------------------------------+
//| S/D Marking Method Helpers                                       |
//+------------------------------------------------------------------+
string SDMarkMethodName()
{
   if(InpSDMarkingMethod == SD_MARK_METHOD_MOMENTUM)
      return "MOMENTUM";

   if(InpSDMarkingMethod == SD_MARK_METHOD_CONSOLIDATION)
      return "CONSOLIDATION";

   if(InpSDMarkingMethod == SD_MARK_METHOD_WICK)
      return "WICK";

   return "UNKNOWN";
}

bool SDUseMomentumMethod()
{
   if(InpSDEnableAllMethods) return InpSDUseMomentumMethod;
   return (InpSDMarkingMethod == SD_MARK_METHOD_MOMENTUM);
}

bool SDUseConsolidationMethod()
{
   if(InpSDEnableAllMethods) return InpSDUseConsolidationMethod;
   return (InpSDMarkingMethod == SD_MARK_METHOD_CONSOLIDATION);
}

bool SDUseWickMethod()
{
   if(InpSDEnableAllMethods) return InpSDUseWickMethod;
   return (InpSDMarkingMethod == SD_MARK_METHOD_WICK);
}

bool SDIsPDFMethodTag(string tag)
{
   return (StringFind(tag, "PDF_MOMENTUM") >= 0 ||
           StringFind(tag, "PDF_CONSOLIDATION") >= 0 ||
           StringFind(tag, "PDF_WICK") >= 0);
}

string SDMethodNameFromTag(string tag)
{
   if(StringFind(tag, "MOMENTUM") >= 0)
      return "MOMENTUM";

   if(StringFind(tag, "CONSOLIDATION") >= 0)
      return "CONSOLIDATION";

   if(StringFind(tag, "WICK") >= 0)
      return "WICK";

   if(StringFind(tag, "FLIP") >= 0)
      return "FLIP";

   return tag;
}

bool SDIsPDFLockedMethod(string method)
{
   return (method == "MOMENTUM" ||
           method == "CONSOLIDATION" ||
           method == "WICK" ||
           StringFind(method, "PDF_MOMENTUM") >= 0 ||
           StringFind(method, "PDF_CONSOLIDATION") >= 0 ||
           StringFind(method, "PDF_WICK") >= 0);
}

bool SDZoneIsPDFLocked(const ZoneInfo &z)
{
   return SDIsPDFLockedMethod(z.sdCreationMethod) ||
          SDIsPDFMethodTag(z.structuralTag);
}

bool SDIncomingMethodMatchesZone(const ZoneInfo &z, string methodTag)
{
   string m = SDMethodNameFromTag(methodTag);

   if(m == "")
      return false;

   if(z.sdCreationMethod == m)
      return true;

   if(StringFind(z.sdCreationMethod, m) >= 0)
      return true;

   if(StringFind(z.structuralTag, m) >= 0)
      return true;

   if(SDIsPDFMethodTag(methodTag) && SDZoneIsPDFLocked(z))
      return true;

   return false;
}

datetime SDZoneAnchorTimeFromShift(int shift)
{
   int safeShift = MathMax(shift, 1);
   datetime t = iTime(_Symbol, g_zoneTF, safeShift);

   if(t > 0)
      return t;

   return TimeCurrent();
}

#define ZM_FRESHNESS_INITIAL     1.0
#define ZM_FRESHNESS_DECAY       0.12
#define ZM_FRESHNESS_AGE_DECAY   0.002
#define ZM_MIN_VALID_SCORE       0.20
#define ZM_STRONG_ZONE_SCORE     0.55
#define ZM_TOUCH_BONUS_1         0.10
#define ZM_TOUCH_BONUS_2         0.15
#define ZM_TOUCH_BONUS_3         0.08
#define ZM_TOUCH_PENALTY_4PLUS  -0.05
#define ZM_REJECTION_WICK_BODY   2.0
#define ZM_REJECTION_WICK_RANGE  0.55
#define ZM_REJECTION_CLOSE_LOC   0.35
#define ZM_BREAKOUT_BODY_ATR     1.5
#define ZM_ENABLE_REJECTION      true
#define ZM_ENABLE_BREAKOUT_TAG   true

//+------------------------------------------------------------------+
//| Zone Role Helper Functions                                         |
//+------------------------------------------------------------------+
bool IsSupportTag(const string tag)
{
   return (tag == "HL" || tag == "LL");
}

bool IsResistanceTag(const string tag)
{
   return (tag == "LH" || tag == "HH");
}

ZONE_CANONICAL_ROLE ResolveZoneRole(const ZoneInfo &z, double price, double atr)
{
   if(z.structuralTag == "HL" || z.structuralTag == "LL")
      return ZROLE_SUPPORT;

   if(z.structuralTag == "HH" || z.structuralTag == "LH")
      return ZROLE_RESISTANCE;

   if(z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_SUPPORT_MINOR || z.type == ZONE_DEMAND)
      return ZROLE_SUPPORT;

   if(z.type == ZONE_RESISTANCE_MAJOR || z.type == ZONE_RESISTANCE_MINOR || z.type == ZONE_SUPPLY)
      return ZROLE_RESISTANCE;

   return ZROLE_UNKNOWN;
}

double ComputePrimaryRelevance(const ZoneInfo &z, double price, double atr)
{
   double safeAtr   = MathMax(atr, _Point * 10.0);
   double distATR   = MathAbs(z.midPoint - price) / safeAtr;
   double widthATR  = (z.upperBound - z.lowerBound) / safeAtr;

   double structure = z.structuralScore * 1.20;
   double touches   = MathMin((double)z.cleanTouchCount, 4.0) * 0.90;
   double reject    = MathMin(z.rejectionScore, 4.0) * 0.70;
   double fresh     = MathMax(0.0, 3.0 - z.ageInBars / 25.0);
   double flipBonus = (z.continuationEligible ? 0.50 : 0.0);
   double widthPen  = MathMax(0.0, widthATR - 0.60) * 2.20;
   double distPen   = MathMax(0.0, distATR - 1.20) * 1.20;

   return structure + touches + reject + fresh + flipBonus - widthPen - distPen;
}

bool IsUsablePrimaryScore(const double v)
{
   return (v == v && v > -DBL_MAX / 4.0 && v < DBL_MAX / 4.0);
}

double SafePrimaryScoreValue(const ZoneInfo &z,
                             const bool wantSupport,
                             const double price,
                             const double atr)
{
   double s = ScorePrimaryCandidate(z, wantSupport, price, atr);

   if(!IsUsablePrimaryScore(s))
      s = ComputePrimaryRelevance(z, price, atr);

   if(!IsUsablePrimaryScore(s))
      s = -9999.0;

   return s;
}

int GetZoneTrendBias()
{
   if(g_structure.state == STRUCTURE_BULL_TREND || g_structure.state == STRUCTURE_BIAS_BULL)
      return 1;
   if(g_structure.state == STRUCTURE_BEAR_TREND || g_structure.state == STRUCTURE_BIAS_BEAR)
      return -1;
   return 0;
}

double GetTrendAwarePrimaryBonus(const ZoneInfo &z, bool wantSupport, int trendBias)
{
   double bonus = 0.0;

   if(trendBias == 1)
   {
      if(wantSupport)
      {
         if(z.structuralTag == "HL") bonus += 2.40;
         else if(z.structuralTag == "LL") bonus += 1.15;
         else if(z.type == ZONE_DEMAND || z.type == ZONE_SUPPORT_MAJOR) bonus += 0.80;
      }
      else
      {
         if(z.structuralTag == "HH") bonus += 1.20;
         else if(z.structuralTag == "LH") bonus += 0.75;
         else if(z.type == ZONE_RESISTANCE_MAJOR || z.type == ZONE_SUPPLY) bonus += 0.45;
      }
   }
   else if(trendBias == -1)
   {
      if(!wantSupport)
      {
         if(z.structuralTag == "LH") bonus += 2.40;
         else if(z.structuralTag == "HH") bonus += 1.15;
         else if(z.type == ZONE_SUPPLY || z.type == ZONE_RESISTANCE_MAJOR) bonus += 0.80;
      }
      else
      {
         if(z.structuralTag == "LL") bonus += 1.20;
         else if(z.structuralTag == "HL") bonus += 0.75;
         else if(z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_DEMAND) bonus += 0.45;
      }
   }
   else
   {
      if(wantSupport)
      {
         if(z.structuralTag == "HL" || z.structuralTag == "LL") bonus += 1.20;
      }
      else
      {
         if(z.structuralTag == "LH" || z.structuralTag == "HH") bonus += 1.20;
      }
   }

   if(z.structuralAnchor)      bonus += 0.60;
   if(z.protectedKeyZone)      bonus += 0.45;
   if(z.continuationEligible)  bonus += 0.40;
   if(z.isFlipZone)            bonus += 0.25;

   return bonus;
}

//+------------------------------------------------------------------+
//| Get Zone Lookback Bars (Startup vs Refresh)                      |
//+------------------------------------------------------------------+
int GetZoneLookbackBars(bool startupScan)
{
   int bars = startupScan ? g_zoneStartupLookbackBars : g_zoneRefreshLookbackBars;

   if(g_zoneTF == PERIOD_D1)
      return MathMax(60, bars);

   return bars;
}

//+------------------------------------------------------------------+
//| Zone Strength Mode Filter                                         |
//+------------------------------------------------------------------+
bool PassesZoneStrengthMode(const ZoneInfo &z, ENUM_ZONE_STRENGTH_MODE mode)
{
   double q = z.qualityScore;

   bool structural =
      (z.structuralTag == "HL" || z.structuralTag == "LH" ||
       z.structuralTag == "HH" || z.structuralTag == "LL" ||
       z.structuralAnchor || z.isFlipZone || z.protectedKeyZone);

   switch(mode)
   {
      case ZONE_STRENGTH_STRONG_ONLY:
         return (q >= InpStrongZoneQuality) || (InpPreferStructuralZones && structural && q >= InpModerateZoneQuality);

      case ZONE_STRENGTH_MODERATE_AND_STRONG:
         return (q >= InpModerateZoneQuality) || (InpPreferStructuralZones && structural);

      case ZONE_STRENGTH_WEAK_ONLY:
         return (q > 0.0 && q < InpModerateZoneQuality);

      case ZONE_STRENGTH_ALL:
      default:
         return (q > 0.0) || structural;
   }
}

bool FindClosestStructuralRoleZone(bool wantSupport,
                                   int trendBias,
                                   double price,
                                   double atr,
                                   ZoneInfo &outZone)
{
   double safeAtr   = MathMax(atr, _Point * 10.0);
   double bestScore = -DBL_MAX;
   double bestDist  = DBL_MAX;
   bool found       = false;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.valid || !z.active || z.broken)
         continue;

      bool structuralLike =
         (z.structuralAnchor || z.structuralTag != "" || z.isFlipZone || z.protectedKeyZone);

      if(!structuralLike)
         continue;

      if(wantSupport)
      {
         if(!ZoneEligibleAsSupportHere(z, price, atr))
            continue;
      }
      else
      {
         if(!ZoneEligibleAsResistanceHere(z, price, atr))
            continue;
      }

      double distATR = MathAbs(z.midPoint - price) / safeAtr;
      if(distATR > 5.25)
         continue;

      double score =
         ComputePrimaryRelevance(z, price, atr) +
         GetTrendAwarePrimaryBonus(z, wantSupport, trendBias) -
         MathMax(0.0, distATR - 1.75) * 0.55;

      if(!found || score > bestScore ||
         (MathAbs(score - bestScore) < 1e-6 && distATR < bestDist))
      {
         outZone   = z;
         bestScore = score;
         bestDist  = distATR;
         found     = true;
      }
   }

   return found;
}

//+------------------------------------------------------------------+
//| Zone Registry - Unified persistent storage                        |
//+------------------------------------------------------------------+
struct ZoneRegistry
{
   ZoneInfo       zones[ZM_MAX_TOTAL];
   int            count;
   int            activeCount;
   int            historicalCount;
   bool     initialized;
   datetime lastUpdate;
   int      lastScanBar;
};

ZoneRegistry g_zoneReg;
#define g_zones g_zoneReg
int          g_nextZoneId = 1;
// g_zoneTF defined in IndicatorManager.mqh with other TF globals

// Global primary zones - THE ONLY zones used for trading
PrimaryZones g_primaryZones;

void SetZoneTimeframe(ENUM_TIMEFRAMES tf)
{
   g_zoneTF = tf;
   Print("ZONE TF SET TO: ", EnumToString(g_zoneTF));
}

void SetZoneSwingLookback(int lookback)
{
   g_zoneSwingLookback = MathMax(2, MathMin(lookback, 10));
   Print("ZONE: swing lookback set to ", g_zoneSwingLookback);
}

// Include after ZoneInfo/ENUM_ZONE_TYPE/ZoneRegistry are fully defined
#include "MarketStructure.mqh"

//+------------------------------------------------------------------+
//| Structural sequence protection settings                          |
//+------------------------------------------------------------------+
int g_minKeepBullHL = 3;
int g_minKeepBullHH = 2;
int g_minKeepBearLH = 3;
int g_minKeepBearLL = 2;

bool IsProtectedStructuralSequence(const ZoneInfo &z)
{
   if(!z.structuralAnchor || !z.structuralLocked) return false;

   bool bullState = (g_structure.state == STRUCTURE_BULL_TREND ||
                     g_structure.state == STRUCTURE_BIAS_BULL);
   bool bearState = (g_structure.state == STRUCTURE_BEAR_TREND ||
                     g_structure.state == STRUCTURE_BIAS_BEAR);

   if(bullState)
   {
      if(z.structuralTag == "HL" && z.sequenceIndex >= 0 && z.sequenceIndex < g_minKeepBullHL) return true;
      if(z.structuralTag == "HH" && z.sequenceIndex >= 0 && z.sequenceIndex < g_minKeepBullHH) return true;
   }
   if(bearState)
   {
      if(z.structuralTag == "LH" && z.sequenceIndex >= 0 && z.sequenceIndex < g_minKeepBearLH) return true;
      if(z.structuralTag == "LL" && z.sequenceIndex >= 0 && z.sequenceIndex < g_minKeepBearLL) return true;
   }
   return false;
}

bool IsNearPrice(double mid, double price, double atrVal, double maxATR)
{
   if(atrVal <= 0.0) return false;
   return (MathAbs(mid - price) / atrVal <= maxATR);
}

//+------------------------------------------------------------------+
//| Function declarations                                              |
//+------------------------------------------------------------------+
void InitZoneManager(void);
void SetZoneSwingLookback(int lookback);
void SetZoneTimeframe(ENUM_TIMEFRAMES tf);
void RefreshZones(const IndicatorState &ind, double atr);
void DrawZoneLines(void);
bool IsNearAnyZone(double price, double atr, double tolATR = 0.5);
bool IsNearMajorZone(double price, double atr, double tolATR = 0.5);
bool IsNearMinorZone(double price, double atr, double tolATR = 0.5);
bool IsNearSupplyDemandZone(double price, double atr, double tolATR = 0.5);
ZoneInfo GetNearestZone(double price, double atr, double tolATR = 0.5);
int FindNearestSupportIndexBelow(double price, double atr);
int FindNearestResistanceIndexAbove(double price, double atr);
string ZoneTypeToString(ENUM_ZONE_TYPE type);
void LogAllZones(void);

// Zone strategy role assignment
void AssignZoneStrategyRoles(double price, double atr, int trendBias, bool d1TrendValid);

// Trend zone retirement logic
bool ShouldRetireTrendZone(const ZoneInfo &z, const IndicatorState &ind, double atr, int trendBias);

//+------------------------------------------------------------------+
//| S/R reaction helpers                                             |
//+------------------------------------------------------------------+
bool IsSupportRole(const ZoneInfo &z)
{
   return IsBullishZone(z.type);
}

bool IsResistanceRole(const ZoneInfo &z)
{
   return IsBearishZone(z.type);
}

string ZoneRoleName(const ZoneInfo &z)
{
   return IsSupportRole(z) ? "Support" : "Resistance";
}

bool IsZoneBrokenUp(const ZoneInfo &z)
{
   return (z.broken && IsBearishZone(z.type));
}

bool IsZoneBrokenDown(const ZoneInfo &z)
{
   return (z.broken && IsBullishZone(z.type));
}

bool IsZoneHoldingFromAbove(double price, const ZoneInfo &z, double atr)
{
   return (price >= z.lowerBound - atr * 0.30);
}

bool IsZoneHoldingFromBelow(double price, const ZoneInfo &z, double atr)
{
   return (price <= z.upperBound + atr * 0.30);
}

double ZoneMid(const ZoneInfo &z)
{
   return (z.upperBound + z.lowerBound) * 0.5;
}

bool PriceInsideZone(double price, const ZoneInfo &z)
{
   return (price >= z.lowerBound && price <= z.upperBound);
}

bool PriceNearZone(double price, const ZoneInfo &z, double atr, double toleranceATR = 0.20)
{
   double tol = atr * toleranceATR;
   return (price >= z.lowerBound - tol && price <= z.upperBound + tol);
}

bool ZoneAllowsTradeDirection(const ZoneInfo &z, bool isBuy, double price, double atr)
{
   if(isBuy)
   {
      if(IsSupportRole(z))
         return PriceNearZone(price, z, atr);
      if(IsResistanceRole(z) && price > ZoneMid(z))
         return PriceNearZone(price, z, atr);
      return false;
   }
   else
   {
      if(IsResistanceRole(z))
         return PriceNearZone(price, z, atr);
      if(IsSupportRole(z) && price < ZoneMid(z))
         return PriceNearZone(price, z, atr);
      return false;
   }
}

bool BuyReactionLocationOK(const ZoneInfo &z, double price)
{
   return price <= ZoneMid(z);
}

bool SellReactionLocationOK(const ZoneInfo &z, double price)
{
   return price >= ZoneMid(z);
}

int FindNearestActiveZoneIndex(double price)
{
   int bestIdx = -1;
   double bestDist = DBL_MAX;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active && !g_zoneReg.zones[i].valid) continue;

      double dist = 0.0;
      if(price < g_zoneReg.zones[i].lowerBound)
         dist = g_zoneReg.zones[i].lowerBound - price;
      else if(price > g_zoneReg.zones[i].upperBound)
         dist = price - g_zoneReg.zones[i].upperBound;

      if(dist < bestDist)
      {
         bestDist = dist;
         bestIdx = i;
      }
   }
   return bestIdx;
}

//+------------------------------------------------------------------+
//| Find zone index by ID                                            |
//+------------------------------------------------------------------+
int ZMFindZoneIndexById(int zoneId)
{
   if(zoneId <= 0) return -1;
   
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(g_zoneReg.zones[i].id == zoneId)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| ID generator                                                     |
//+------------------------------------------------------------------+
int GenerateZoneId() { return g_nextZoneId++; }

//+------------------------------------------------------------------+
//| Initialize registry                                              |
//+------------------------------------------------------------------+
void InitZoneManager()
{
   g_zoneReg.count       = 0;
   g_zoneReg.initialized = false;
   g_zoneReg.lastUpdate  = 0;
   g_zoneReg.lastScanBar = 0;
   for(int i = 0; i < ZM_MAX_TOTAL; i++)
   {
      g_zoneReg.zones[i].active     = false;
      g_zoneReg.zones[i].historical = false;
      g_zoneReg.zones[i].id         = 0;
   }
   g_nextZoneId = 1;
   
   // Initialize zone lookback configuration
   g_zoneStartupLookbackBars = InpD1ZoneStartupLookbackBars;
   g_zoneRefreshLookbackBars = InpD1ZoneRefreshLookbackBars;
   g_zoneLifetimeBars        = InpD1ZoneLifetimeBars;
   
   Print("ZONE: ZoneManager v7.1 initialized (persistent registry)");
   Print("[ZONE_LOOKBACK_CONFIG] startupBars=", g_zoneStartupLookbackBars,
         " refreshBars=", g_zoneRefreshLookbackBars,
         " lifetimeBars=", g_zoneLifetimeBars);
}

//+------------------------------------------------------------------+
//| Zone type helpers                                                |
//+------------------------------------------------------------------+
bool IsBullishZone(ENUM_ZONE_TYPE t)
{
   return (t == ZONE_DEMAND_MAJOR ||
           t == ZONE_DEMAND_MINOR ||
           t == ZONE_DEMAND);
}

bool IsBearishZone(ENUM_ZONE_TYPE t)
{
   return (t == ZONE_SUPPLY_MAJOR ||
           t == ZONE_SUPPLY_MINOR ||
           t == ZONE_SUPPLY);
}
bool IsSameZoneDirection(ENUM_ZONE_TYPE a, ENUM_ZONE_TYPE b)
{
   if(IsBullishZone(a) && IsBullishZone(b)) return true;
   if(IsBearishZone(a) && IsBearishZone(b)) return true;
   return false;
}
ENUM_ZONE_FAMILY GetZoneFamily(ENUM_ZONE_TYPE t)
{
   switch(t)
   {
      case ZONE_DEMAND_MAJOR:
      case ZONE_DEMAND_MINOR:
      case ZONE_DEMAND:
         return ZFAM_DEMAND;

      case ZONE_SUPPLY_MAJOR:
      case ZONE_SUPPLY_MINOR:
      case ZONE_SUPPLY:
         return ZFAM_SUPPLY;

      case ZONE_EMA_CONFLUENCE:
         return ZFAM_EMA;

      default:
         return ZFAM_UNKNOWN;
   }
}
bool AreFamiliesCompatible(ENUM_ZONE_FAMILY a, ENUM_ZONE_FAMILY b)
{
   if(a == ZFAM_EMA || b == ZFAM_EMA) return true;
   return (a == b);
}
int GetZonePriority(ENUM_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_DEMAND_MAJOR:
      case ZONE_SUPPLY_MAJOR:
         return 3;

      case ZONE_DEMAND:
      case ZONE_SUPPLY:
      case ZONE_EMA_CONFLUENCE:
         return 2;

      case ZONE_DEMAND_MINOR:
      case ZONE_SUPPLY_MINOR:
         return 1;

      default:
         return 0;
   }
}
string ZoneTypeToString(ENUM_ZONE_TYPE type)
{
   switch(type)
   {
      case ZONE_DEMAND_MAJOR:
      case ZONE_DEMAND_MINOR:
      case ZONE_DEMAND:
         return "Demand";

      case ZONE_SUPPLY_MAJOR:
      case ZONE_SUPPLY_MINOR:
      case ZONE_SUPPLY:
         return "Supply";

      case ZONE_EMA_CONFLUENCE:
         return "EMA_CONFLUENCE";

      default:
         return "UNKNOWN";
   }
}

string GetDynamicZoneLabel(const ZoneInfo &z, double currentPrice)
{
   if(z.upperBound <= currentPrice)
      return "Demand";  // Zone below price
   else if(z.lowerBound >= currentPrice)
      return "Supply";  // Zone above price
   else
      return "Inside";  // Price inside zone
}

//+------------------------------------------------------------------+
//| Dynamic S/D role helpers                                         |
//| below price = Demand, above price = Supply                       |
//| Active IDs override old static zone type                         |
//+------------------------------------------------------------------+
double SDCurrentRolePrice()
{
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double last = SymbolInfoDouble(_Symbol, SYMBOL_LAST);

   if(bid > 0.0 && ask > 0.0)
      return (bid + ask) * 0.50;

   if(last > 0.0)
      return last;

   return 0.0;
}

bool SDZoneActsAsDemand(ZoneInfo &z, double price)
{
   // Active Demand ID is final authority.
   if(z.id > 0 && z.id == g_activeDemandZoneId)
      return true;

   if(z.id > 0 && z.id == g_activeSupplyZoneId)
      return false;

   // Flip-zone current type is the second authority.
   // A broken Supply flipped upward is now Demand.
   if(z.isFlipZone && IsBullishZone(z.type))
      return true;

   if(z.isFlipZone && IsBearishZone(z.type))
      return false;

   if(price > 0.0)
   {
      if(z.upperBound <= price)
         return true;

      if(z.lowerBound >= price)
         return false;

      if(price >= z.lowerBound && price <= z.upperBound)
         return (price <= z.midPoint);
   }

   return IsBullishZone(z.type);
}

bool SDZoneActsAsSupply(ZoneInfo &z, double price)
{
   // Active Supply ID is final authority.
   if(z.id > 0 && z.id == g_activeSupplyZoneId)
      return true;

   if(z.id > 0 && z.id == g_activeDemandZoneId)
      return false;

   // Flip-zone current type is the second authority.
   // A broken Demand flipped downward is now Supply.
   if(z.isFlipZone && IsBearishZone(z.type))
      return true;

   if(z.isFlipZone && IsBullishZone(z.type))
      return false;

   if(price > 0.0)
   {
      if(z.lowerBound >= price)
         return true;

      if(z.upperBound <= price)
         return false;

      if(price >= z.lowerBound && price <= z.upperBound)
         return (price >= z.midPoint);
   }

   return IsBearishZone(z.type);
}

string SDDynamicRoleName(ZoneInfo &z, double price)
{
   if(SDZoneActsAsDemand(z, price))
      return "Demand";

   if(SDZoneActsAsSupply(z, price))
      return "Supply";

   return "Unknown";
}

//+------------------------------------------------------------------+
//| Visual role helpers — active IDs and flip role override price     |
//+------------------------------------------------------------------+
double SDVisualRolePrice()
{
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double last = SymbolInfoDouble(_Symbol, SYMBOL_LAST);

   if(bid > 0.0 && ask > 0.0)
      return (bid + ask) * 0.50;

   if(last > 0.0)
      return last;

   double c0 = iClose(_Symbol, PERIOD_CURRENT, 0);
   if(c0 > 0.0)
      return c0;

   return iClose(_Symbol, g_zoneTF, 0);
}

string SDVisualRoleLabel(const ZoneInfo &zin)
{
   ZoneInfo z = zin;
   double price = SDVisualRolePrice();

   if(z.id > 0 && z.id == g_activeDemandZoneId)
      return "Demand";

   if(z.id > 0 && z.id == g_activeSupplyZoneId)
      return "Supply";

   if(z.isFlipZone)
   {
      if(IsBullishZone(z.type))
         return "Demand";

      if(IsBearishZone(z.type))
         return "Supply";
   }

   if(SDZoneActsAsDemand(z, price))
      return "Demand";

   if(SDZoneActsAsSupply(z, price))
      return "Supply";

   return GetDynamicZoneLabel(z, price);
}

bool SDVisualIsDemand(const ZoneInfo &zin)
{
   return (SDVisualRoleLabel(zin) == "Demand");
}

bool SDVisualIsSupply(const ZoneInfo &zin)
{
   return (SDVisualRoleLabel(zin) == "Supply");
}

string SDOriginalRoleLabel(const ZoneInfo &z)
{
   if(IsBullishZone(z.originalType))
      return "Demand";

   if(IsBearishZone(z.originalType))
      return "Supply";

   return ZoneTypeToString(z.type);
}

//+------------------------------------------------------------------+
//| Zone geometry helpers                                            |
//+------------------------------------------------------------------+
double ZoneWidth(const ZoneInfo &z)    { return z.upperBound - z.lowerBound; }
double ZoneMidDist(const ZoneInfo &a, const ZoneInfo &b)
   { return MathAbs(a.midPoint - b.midPoint); }

double ZoneOverlapPct(const ZoneInfo &a, const ZoneInfo &b)
{
   double ov = MathMin(a.upperBound, b.upperBound) - MathMax(a.lowerBound, b.lowerBound);
   if(ov <= 0) return 0.0;
   double w = MathMax(ZoneWidth(a), ZoneWidth(b));
   return (w > 0) ? ov / w : 0.0;
}

//+------------------------------------------------------------------+
//| Round number confluence helper                                   |
//+------------------------------------------------------------------+
bool IsRoundNumberLevel(double midPrice)
{
   long priceInPts = (long)MathRound(midPrice / _Point);
   return (priceInPts % 1000 < 20 || priceInPts % 1000 > 980 ||
           priceInPts % 500  < 20 || priceInPts % 500  > 480);
}

//+------------------------------------------------------------------+
//| Strength calculation                                             |
//+------------------------------------------------------------------+
double CalcTouchBonus(int touches)
{
   if(touches <= 0) return 0.0;
   if(touches == 1) return ZM_TOUCH_BONUS_1;
   if(touches == 2) return ZM_TOUCH_BONUS_1 + ZM_TOUCH_BONUS_2;
   if(touches == 3) return ZM_TOUCH_BONUS_1 + ZM_TOUCH_BONUS_2 + ZM_TOUCH_BONUS_3;
   return ZM_TOUCH_BONUS_1 + ZM_TOUCH_BONUS_2 + ZM_TOUCH_BONUS_3
          + (touches - 3) * ZM_TOUCH_PENALTY_4PLUS;
}

double CalcZoneStrength(const ZoneInfo &z)
{
   double s = 0.0;
   s += MathMax(CalcTouchBonus(z.cleanTouchCount), 0.0);
   s += MathMin(z.reactionScore * 0.05, 0.15);
   switch(z.type)
   {
      case ZONE_SUPPORT_MAJOR:
      case ZONE_RESISTANCE_MAJOR: s += 0.25; break;
      case ZONE_DEMAND:
      case ZONE_SUPPLY:           s += 0.22; break;
      case ZONE_EMA_CONFLUENCE:   s += 0.10; break;
      default:                    s += 0.08; break;
   }
   if(z.ageInBars < 15)       s += 0.20;
   else if(z.ageInBars < 40)  s += 0.16;
   else if(z.ageInBars < 100) s += 0.12;
   else if(z.ageInBars < 200) s += 0.06;
   else                       s += 0.02;
   s += MathMin(z.freshness * 0.10, 0.10);
   s += MathMin(z.rejectionScore * 0.08, 0.16);
   s += MathMin(z.breakoutScore * 0.06, 0.12);
   if(z.isRefinement)             s += 0.05;
   if(z.isFlipZone)               s += 0.08;
   if(z.isRetestOfHistoricalZone) s += 0.06;
   if(z.protectedKeyZone)         s += 0.05;
   if(z.isBreakoutOrigin)         s += 0.04;
   if(z.hasRejection)             s += 0.03;
   if(z.isRoundNumber)            s += 0.10;
   if(z.isSessionLevel)           s += 0.08;
   if(z.broken)                   s -= 0.15;
   if(z.breakConfirmCount >= ZM_BREAK_CONFIRM) s -= 0.10;
   return MathMax(MathMin(s, 1.0), 0.0);
}

void UpdateZoneScoreAndValid(int idx)
{
   g_zoneReg.zones[idx].strength = CalcZoneStrength(g_zoneReg.zones[idx]);
   g_zoneReg.zones[idx].score    = g_zoneReg.zones[idx].strength;

   // Patch 10: Structural score boost in trend states
   if(g_zoneReg.zones[idx].structuralAnchor)
   {
      bool bullState = (g_structure.state == STRUCTURE_BULL_TREND ||
                        g_structure.state == STRUCTURE_BIAS_BULL);
      bool bearState = (g_structure.state == STRUCTURE_BEAR_TREND ||
                        g_structure.state == STRUCTURE_BIAS_BEAR);
      string tag = g_zoneReg.zones[idx].structuralTag;

      if(bullState)
      {
         if(tag == "HL") g_zoneReg.zones[idx].score = MathMin(1.0, g_zoneReg.zones[idx].score + 0.30);
         if(tag == "HH") g_zoneReg.zones[idx].score = MathMin(1.0, g_zoneReg.zones[idx].score + 0.12);
      }
      else if(bearState)
      {
         if(tag == "LH") g_zoneReg.zones[idx].score = MathMin(1.0, g_zoneReg.zones[idx].score + 0.30);
         if(tag == "LL") g_zoneReg.zones[idx].score = MathMin(1.0, g_zoneReg.zones[idx].score + 0.12);
      }
   }

   g_zoneReg.zones[idx].valid    = (g_zoneReg.zones[idx].score >= ZM_MIN_VALID_SCORE
                                    && !g_zoneReg.zones[idx].broken
                                    && g_zoneReg.zones[idx].active);
}

//+------------------------------------------------------------------+
//| Count zones                                                      |
//+------------------------------------------------------------------+
int CountActiveZones()
{
   int c = 0;
   for(int i = 0; i < g_zoneReg.count; i++)
      if(g_zoneReg.zones[i].active && !g_zoneReg.zones[i].historical) c++;
   return c;
}
int CountHistoricalZones()
{
   int c = 0;
   for(int i = 0; i < g_zoneReg.count; i++)
      if(g_zoneReg.zones[i].historical) c++;
   return c;
}

//+------------------------------------------------------------------+
//| Find zone by ID                                                  |
//+------------------------------------------------------------------+
int FindZoneById(int zoneId)
{
   for(int i = 0; i < g_zoneReg.count; i++)
      if(g_zoneReg.zones[i].id == zoneId) return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Remove a zone slot (compact array)                               |
//+------------------------------------------------------------------+
void RemoveZoneSlot(int idx)
{
   if(idx < 0 || idx >= g_zoneReg.count) return;
   for(int k = idx; k < g_zoneReg.count - 1; k++)
      g_zoneReg.zones[k] = g_zoneReg.zones[k + 1];
   g_zoneReg.count--;
}

//+------------------------------------------------------------------+
//| Mark zone historical (not deleted)                               |
//+------------------------------------------------------------------+
void MarkZoneHistorical(int idx)
{
   if(idx < 0 || idx >= g_zoneReg.count) return;
   g_zoneReg.zones[idx].active     = false;
   g_zoneReg.zones[idx].historical = true;
}

//+------------------------------------------------------------------+
//| Cleanup oldest/weakest historical zones beyond cap               |
//+------------------------------------------------------------------+
void CleanupHistoricalZones()
{
   // STEP 7: Clean old broken flip zones harder to prevent journal clutter
   for(int i = g_zoneReg.count - 1; i >= 0; i--)
   {
      bool shouldRemove = false;
      string reason = "";
      
      // Remove old broken flip zones
      if(g_zoneReg.zones[i].isFlipZone && g_zoneReg.zones[i].broken &&
         g_zoneReg.zones[i].ageInBars > 80)
      {
         shouldRemove = true;
         reason = "old_broken_flip_zone";
      }
      
      // Remove flip zones with invalid pattern tags
      if(g_zoneReg.zones[i].isFlipZone && g_zoneReg.zones[i].structuralTag != "")
      {
         bool isBearish = IsBearishZone(g_zoneReg.zones[i].type);
         bool isBullish = IsBullishZone(g_zoneReg.zones[i].type);
         string tag = g_zoneReg.zones[i].structuralTag;
         
         // Supply with bullish pattern = invalid
         if(isBearish && (tag == "DBR" || tag == "RBR" || tag == "DBR_UNKNOWN"))
         {
            shouldRemove = true;
            reason = "flip_zone_invalid_pattern_mismatch";
         }
         
         // Demand with bearish pattern = invalid
         if(isBullish && (tag == "RBD" || tag == "DBD" || tag == "RBD_UNKNOWN"))
         {
            shouldRemove = true;
            reason = "flip_zone_invalid_pattern_mismatch";
         }
      }
      
      // Remove flip zones that are both broken and historical
      if(g_zoneReg.zones[i].isFlipZone && g_zoneReg.zones[i].broken && 
         g_zoneReg.zones[i].historical && g_zoneReg.zones[i].ageInBars > 50)
      {
         shouldRemove = true;
         reason = "flip_zone_broken_historical";
      }
      
      if(shouldRemove)
      {
         Print("[FLIP_ZONE_CLEANUP] id=", g_zoneReg.zones[i].id,
               " tag=", g_zoneReg.zones[i].structuralTag,
               " type=", ZoneTypeToString(g_zoneReg.zones[i].type),
               " age=", g_zoneReg.zones[i].ageInBars,
               " reason=", reason);
         RemoveZoneSlot(i);
      }
   }

   while(CountHistoricalZones() > ZM_MAX_HISTORICAL)
   {
      int worst = -1;
      double worstScore = 999.0;
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         if(!g_zoneReg.zones[i].historical) continue;
         if(g_zoneReg.zones[i].protectedKeyZone) continue;
         double sc = g_zoneReg.zones[i].strength - g_zoneReg.zones[i].ageInBars * 0.0001;
         if(sc < worstScore) { worstScore = sc; worst = i; }
      }
      if(worst < 0)
      {
         worst = -1; worstScore = 999.0;
         for(int i = 0; i < g_zoneReg.count; i++)
         {
            if(!g_zoneReg.zones[i].historical) continue;
            if(g_zoneReg.zones[i].strength < worstScore)
               { worstScore = g_zoneReg.zones[i].strength; worst = i; }
         }
      }
      if(worst < 0) break;
      RemoveZoneSlot(worst);
   }
}

//+------------------------------------------------------------------+
//| Evict weakest active zone to historical when over cap            |
//+------------------------------------------------------------------+
void EvictWeakestActive()
{
   while(CountActiveZones() > ZM_MAX_ACTIVE)
   {
      int worst = -1;
      double ws = 999.0;
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         if(!g_zoneReg.zones[i].active || g_zoneReg.zones[i].historical) continue;
         if(g_zoneReg.zones[i].protectedKeyZone) continue;
         if(g_zoneReg.zones[i].strength < ws) { ws = g_zoneReg.zones[i].strength; worst = i; }
      }
      if(worst < 0)
      {
         worst = -1; ws = 999.0;
         for(int i = 0; i < g_zoneReg.count; i++)
         {
            if(!g_zoneReg.zones[i].active || g_zoneReg.zones[i].historical) continue;
            if(g_zoneReg.zones[i].strength < ws) { ws = g_zoneReg.zones[i].strength; worst = i; }
         }
      }
      if(worst < 0) break;
      MarkZoneHistorical(worst);
   }
   CleanupHistoricalZones();
}

//+------------------------------------------------------------------+
//| Cap active zones to ZM_MAX_ACTIVE_PER_DIR per direction          |
//| Zones far from current price get a distance penalty so nearby   |
//| fresh zones beat stale distant ones.                            |
//+------------------------------------------------------------------+
void EvictExcessByDirection(double currentPrice = 0.0, double atrVal = 0.0)
{
   for(int pass = 0; pass < 2; pass++)
   {
      bool wantBull = (pass == 0);

      while(true)
      {
         int count = 0;
         for(int i = 0; i < g_zoneReg.count; i++)
         {
            if(!g_zoneReg.zones[i].active || g_zoneReg.zones[i].historical) continue;
            bool isBull = IsBullishZone(g_zoneReg.zones[i].type);
            if(isBull == wantBull) count++;
         }
         if(count <= ZM_MAX_ACTIVE_PER_DIR) break;

         int worst = -1;
         double ws = 999.0;
         for(int i = 0; i < g_zoneReg.count; i++)
         {
            if(!g_zoneReg.zones[i].active || g_zoneReg.zones[i].historical) continue;
            bool isBull = IsBullishZone(g_zoneReg.zones[i].type);
            if(isBull != wantBull) continue;
            if(g_zoneReg.zones[i].protectedKeyZone) continue;

            // Patch 8: Preserve protected structural sequence zones from eviction
            if(IsProtectedStructuralSequence(g_zoneReg.zones[i]))
            {
               Print("[ZONE_EVICT_SKIP_STRUCTURAL] id=", g_zoneReg.zones[i].id,
                     " tag=", g_zoneReg.zones[i].structuralTag,
                     " seq=", g_zoneReg.zones[i].sequenceIndex);
               continue;
            }

            // PATCH STEP 15: Preserve structurally important opposite-side target zones
            // These zones may be needed as TP targets for current direction trades
            bool isStructuralTarget = (g_zoneReg.zones[i].structuralAnchor ||
                                      g_zoneReg.zones[i].isPrimary ||
                                      g_zoneReg.zones[i].isFlipZone ||
                                      g_zoneReg.zones[i].protectedKeyZone);
            if(isStructuralTarget && g_zoneReg.zones[i].strength >= 0.35)
            {
               Print("[ZONE_EVICT_SKIP_STRUCTURAL_TARGET] id=", g_zoneReg.zones[i].id,
                     " tag=", g_zoneReg.zones[i].structuralTag,
                     " strength=", DoubleToString(g_zoneReg.zones[i].strength, 2),
                     " isPrimary=", g_zoneReg.zones[i].isPrimary,
                     " isFlip=", g_zoneReg.zones[i].isFlipZone);
               continue;
            }

            // NEAR-PRICE PROTECTION: never evict a zone price is currently reacting at
            if(currentPrice > 0 && atrVal > 0)
            {
               double distNear = (currentPrice >= g_zoneReg.zones[i].lowerBound &&
                                  currentPrice <= g_zoneReg.zones[i].upperBound) ? 0.0
                              : MathMin(MathAbs(currentPrice - g_zoneReg.zones[i].upperBound),
                                        MathAbs(currentPrice - g_zoneReg.zones[i].lowerBound));
               if(distNear <= atrVal * 1.25)
               {
                  Print("[ZONE_EVICT_SKIP] id=", g_zoneReg.zones[i].id,
                        " protected=near_price distATR=", DoubleToString(distNear / atrVal, 2));
                  continue;
               }
            }

            // PATCH 8: Don't evict HL/LH continuation zones via fast path
            bool isContinuationZone = (g_zoneReg.zones[i].strategyRole == ZROLE_TREND_CONTINUATION ||
                                      g_zoneReg.zones[i].structuralTag == "HL" ||
                                      g_zoneReg.zones[i].structuralTag == "LH");

            // Weak zones should be first in line for eviction, except continuation zones
            if(!g_zoneReg.zones[i].structuralAnchor &&
               !g_zoneReg.zones[i].protectedKeyZone &&
               !g_zoneReg.zones[i].isPrimary &&
               g_zoneReg.zones[i].qualityScore < 4.25 &&
               !isContinuationZone)
            {
               // Immediately mark as worst candidate
               ws = -999.0;
               worst = i;
               Print("[ZONE_EVICT_WEAK] id=", g_zoneReg.zones[i].id,
                     " quality=", DoubleToString(g_zoneReg.zones[i].qualityScore, 2),
                     " threshold=4.25");
               break; // Exit loop to evict this weak zone first
            }

            double effectiveScore = g_zoneReg.zones[i].strength;
            if(currentPrice > 0 && atrVal > 0)
            {
               double d = (currentPrice >= g_zoneReg.zones[i].lowerBound &&
                           currentPrice <= g_zoneReg.zones[i].upperBound) ? 0.0
                        : MathMin(MathAbs(currentPrice - g_zoneReg.zones[i].upperBound),
                                  MathAbs(currentPrice - g_zoneReg.zones[i].lowerBound));
               double penaltyThresh = atrVal * g_atrScale;
               if(d > penaltyThresh)
                  effectiveScore -= (d / penaltyThresh - 1.0) * 0.20;
            }
            if(effectiveScore < ws) { ws = effectiveScore; worst = i; }
         }
         if(worst < 0)
         {
            // Second pass without near-price guard (fallback only if all remaining zones are near-price)
            for(int i = 0; i < g_zoneReg.count; i++)
            {
               if(!g_zoneReg.zones[i].active || g_zoneReg.zones[i].historical) continue;
               bool isBull = IsBullishZone(g_zoneReg.zones[i].type);
               if(isBull != wantBull) continue;
               double effectiveScore = g_zoneReg.zones[i].strength;
               if(currentPrice > 0 && atrVal > 0)
               {
                  double d = (currentPrice >= g_zoneReg.zones[i].lowerBound &&
                              currentPrice <= g_zoneReg.zones[i].upperBound) ? 0.0
                           : MathMin(MathAbs(currentPrice - g_zoneReg.zones[i].upperBound),
                                     MathAbs(currentPrice - g_zoneReg.zones[i].lowerBound));
                  double penaltyThresh2 = atrVal * g_atrScale;
                  if(d > penaltyThresh2) effectiveScore -= (d / penaltyThresh2 - 1.0) * 0.20;
               }
               if(effectiveScore < ws) { ws = effectiveScore; worst = i; }
            }
         }
         if(worst < 0) break;
         double evictDist = (currentPrice > 0 && atrVal > 0)
            ? (MathMin(MathAbs(currentPrice - g_zoneReg.zones[worst].upperBound),
                       MathAbs(currentPrice - g_zoneReg.zones[worst].lowerBound)) / atrVal)
            : -1.0;
         Print("[ZONE_EVICT] id=", g_zoneReg.zones[worst].id,
               " type=", ZoneTypeToString(g_zoneReg.zones[worst].type),
               " score=", DoubleToString(g_zoneReg.zones[worst].strength, 2),
               " distATR=", DoubleToString(evictDist, 2));
         MarkZoneHistorical(worst);
      }
   }
}

//+------------------------------------------------------------------+
//| Force full rescan when price has moved far from all active zones |
//+------------------------------------------------------------------+
void ForceZoneRescanIfPriceFar(double currentPrice, double atrVal)
{
   if(atrVal <= 0 || currentPrice <= 0 || !g_zoneReg.initialized) return;
   if(CountActiveZones() == 0) { g_zoneReg.initialized = false; return; }

   double minDist = 999999.0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active || g_zoneReg.zones[i].historical) continue;
      double d = (currentPrice >= g_zoneReg.zones[i].lowerBound &&
                  currentPrice <= g_zoneReg.zones[i].upperBound) ? 0.0
               : MathMin(MathAbs(currentPrice - g_zoneReg.zones[i].upperBound),
                         MathAbs(currentPrice - g_zoneReg.zones[i].lowerBound));
      if(d < minDist) minDist = d;
   }

   if(minDist > atrVal * (2.0 * g_atrScale))
   {
      g_zoneReg.initialized = false;
      Print("[ZONE_RESCAN] Price moved ", DoubleToString(minDist / atrVal, 1),
            "x ATR from nearest zone — forcing full 300-bar rescan");
   }
}

//+------------------------------------------------------------------+
//| Initialize a new ZoneInfo                                        |
//+------------------------------------------------------------------+
void InitZoneInfo(ZoneInfo &z, ENUM_ZONE_TYPE type, double upper, double lower,
                  int touches, int ageBars, const SymbolProfile &prof)
{
   z.id                       = GenerateZoneId();
   z.type                     = type;
   z.upperBound               = NormalizeDouble(upper, prof.digits);
   z.lowerBound               = NormalizeDouble(lower, prof.digits);
   z.midPoint                 = NormalizeDouble((upper + lower) * 0.5, prof.digits);
   z.createdTime              = TimeCurrent();
   z.lastTouchedTime          = TimeCurrent();
   z.lastEvaluatedTime        = TimeCurrent();
   z.active                   = true;
   z.broken                   = false;
   z.historical               = false;
   z.protectedKeyZone         = false;
   z.parentZoneId             = 0;
   z.generation               = 0;
   z.retestCount              = 0;
   z.cleanTouchCount          = touches;
   z.rawTouches               = touches;
   z.breakScore               = 0.0;
   z.reactionScore            = 0.0;
   z.strength                 = 0.0;
   z.ageInBars                = ageBars;
   z.firstSeenBar             = Bars(_Symbol, g_zoneTF) - ageBars;
   z.breakConfirmCount        = 0;
   z.relatedHistoricalZoneId  = 0;
   z.isRefinement             = false;
   z.isFlipZone               = false;
   z.originalType             = type;   // Track original type for flip zones
   z.isRetestOfHistoricalZone = false;
   z.label                    = ZoneTypeToString(type);
   z.score                    = 0.0;
   z.valid                    = true;
   z.freshness                = ZM_FRESHNESS_INITIAL;
   z.rejectionScore           = 0.0;
   z.breakoutScore            = 0.0;
   z.volumeScore              = 0.0;
   z.structuralScore          = (double)GetZonePriority(type) / 4.0;
   z.lastTouchBar             = Bars(_Symbol, g_zoneTF);
   z.isBreakoutOrigin         = false;
   z.hasRejection             = false;
   z.traded                   = false;
   z.lastSweepBar             = 0;
   z.lastTradeTime            = 0;
   z.breakRetestReady         = false;
   z.breakBarIndex            = 0;
   z.continuationEligible     = false;
   z.reversalCandidate        = false;
   z.reversalScore            = 0.0;
   z.continuationScore        = 0.0;
   z.sourceTF                 = g_zoneTF;
   z.majorTFZone              = (g_zoneTF >= PERIOD_H4);
   z.confirmedRetest          = false;
   z.failedRetest             = false;
   z.lastStructureBreakBar    = 0;
   z.isRoundNumber            = false;
   z.isSessionLevel           = false;
   z.isPrimary                = false;
   z.isBackup                 = false;
   z.isTPTargetOnly           = false;  // STEP 8: Initialize TP target flag
   z.execBandLow              = 0.0;
   z.execBandHigh             = 0.0;
   z.hasExecBand              = false;
   z.structuralAnchor         = false;
   z.structuralTag            = "";
   z.sourceBarIndex           = ageBars;
   z.sourceSwingTime          = SDZoneAnchorTimeFromShift(ageBars);
   z.sequenceIndex            = -1;
   z.structuralLocked         = false;
   z.structuralSide           = "";
   z.qualityChecklistHits     = 0;
   z.strength                 = CalcZoneStrength(z);
}

//+------------------------------------------------------------------+
//| Find matching existing zone                                      |
//+------------------------------------------------------------------+
bool SimilarZoneShape(const ZoneInfo &z, double upper, double lower)
{
   double oldW  = MathMax(z.upperBound - z.lowerBound, _Point);
   double newW  = MathMax(upper - lower, _Point);
   double ratio = MathMax(oldW, newW) / MathMax(MathMin(oldW, newW), _Point);
   return (ratio <= 1.8);
}

int FindMatchingZone(ENUM_ZONE_TYPE type, double upper, double lower, double atrVal = 0.0)
{
   double newMid   = (upper + lower) * 0.5;
   double newWidth = MathMax(upper - lower, _Point);

   int bestIdx = -1;
   double bestScore = -999999.0;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active) continue;
      if(g_zoneReg.zones[i].broken)  continue;
      if(!IsSameZoneDirection(type, g_zoneReg.zones[i].type)) continue;

      double ov = MathMin(upper, g_zoneReg.zones[i].upperBound) - MathMax(lower, g_zoneReg.zones[i].lowerBound);
      double w  = MathMax(newWidth, ZoneWidth(g_zoneReg.zones[i]));
      double overlapPct = (w > 0.0) ? (ov / w) : 0.0;

      double midDist = MathAbs(newMid - g_zoneReg.zones[i].midPoint);
      double atrBased = (atrVal > 0) ? atrVal * 0.35 : 0.0;
      double nearThreshold = MathMax(MathMin(atrBased, w * 0.45), _Point * 10);

      bool overlapping = (overlapPct >= 0.35);
      bool veryNearMid = (midDist <= nearThreshold);

      if(!overlapping && !veryNearMid)
         continue;

      if(ov <= 0.0 && atrVal > 0.0 && midDist > atrVal * 0.25)
         continue;

      if(veryNearMid && !overlapping)
      {
         if(!AreFamiliesCompatible(GetZoneFamily(type), GetZoneFamily(g_zoneReg.zones[i].type)))
            continue;
         if(!SimilarZoneShape(g_zoneReg.zones[i], upper, lower))
            continue;
      }

      double score = g_zoneReg.zones[i].strength;
      if(AreFamiliesCompatible(GetZoneFamily(type), GetZoneFamily(g_zoneReg.zones[i].type)))
         score += 0.25;
      if(GetZonePriority(type) == GetZonePriority(g_zoneReg.zones[i].type))
         score += 0.10;
      score -= midDist / MathMax(w, _Point);

      if(score > bestScore)
      {
         bestScore = score;
         bestIdx = i;
      }
   }
   return bestIdx;
}

//+------------------------------------------------------------------+
//| Find related historical zone                                     |
//+------------------------------------------------------------------+
int FindRelatedHistoricalZone(ENUM_ZONE_TYPE type, double upper, double lower, double atrVal)
{
   double threshold = MathMax(atrVal * 0.5, 0.0001);
   double mid = (upper + lower) * 0.5;
   int bestIdx = -1;
   double bestDist = 999999.0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].historical) continue;
      if(!IsSameZoneDirection(type, g_zoneReg.zones[i].type) && !g_zoneReg.zones[i].broken) continue;
      double dist = MathAbs(mid - g_zoneReg.zones[i].midPoint);
      if(dist > threshold) continue;
      if(dist < bestDist) { bestDist = dist; bestIdx = i; }
   }
   return bestIdx;
}

//+------------------------------------------------------------------+
//| Smart merge check                                                |
//+------------------------------------------------------------------+
bool ShouldMergeZones(const ZoneInfo &a, const ZoneInfo &b, double atrVal)
{
   if(!a.active || !b.active) return false;
   if(!IsSameZoneDirection(a.type, b.type)) return false;
   if(!AreFamiliesCompatible(GetZoneFamily(a.type), GetZoneFamily(b.type))) return false;

   double ov = MathMin(a.upperBound, b.upperBound) - MathMax(a.lowerBound, b.lowerBound);
   double gap = 0.0;
   if(ov < 0.0)
      gap = -ov;

   double wA = ZoneWidth(a), wB = ZoneWidth(b);
   double wMax = MathMax(wA, wB), wMin = MathMax(MathMin(wA, wB), 0.00001);
   if(wMax / wMin > ZM_MERGE_MAX_WIDTH_RATIO) return false;

   bool overlapping = (ov > 0.0);

   bool isMajorA = (a.type == ZONE_SUPPORT_MAJOR || a.type == ZONE_RESISTANCE_MAJOR);
   bool isMajorB = (b.type == ZONE_SUPPORT_MAJOR || b.type == ZONE_RESISTANCE_MAJOR);

   double threshold = 0.0;
   if(atrVal > 0)
   {
      if(isMajorA && isMajorB)        threshold = atrVal * 0.75;
      else if(!isMajorA && !isMajorB) threshold = atrVal * 0.35;
      else                            threshold = atrVal * 0.30;
   }
   bool closeEnough = (threshold > 0.0 && gap <= threshold);

   if(!overlapping && !closeEnough)
   {
      if(overlapping == false && gap <= atrVal * 0.75)
         Print("[ZONE_MERGE_SKIPPED_DISTINCT_INTERNAL] gap=", DoubleToString(gap,_Digits),
               " threshold=", DoubleToString(threshold,_Digits));
      return false;
   }

   if(MathAbs(a.ageInBars - b.ageInBars) > ZM_MERGE_MAX_AGE_DIFF) return false;
   if(a.protectedKeyZone && b.protectedKeyZone) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Cluster check: same direction, overlapping or gap < 0.5 ATR    |
//+------------------------------------------------------------------+
bool AreZonesClustered(const ZoneInfo &a, const ZoneInfo &b, double atr)
{
   if(atr <= 0) return false;
   if(!IsSameZoneDirection(a.type, b.type)) return false;
   double ov = MathMin(a.upperBound, b.upperBound) - MathMax(a.lowerBound, b.lowerBound);
   if(ov > 0) return true;          // overlapping
   return (-ov < atr * 0.5);        // gap smaller than half ATR
}

//+------------------------------------------------------------------+
//| Smart merge two zones — direct indexing, no array refs          |
//+------------------------------------------------------------------+
void MergeZonesSmart(int winnerIdx, int loserIdx)
{
   ZoneInfo loserCopy = g_zoneReg.zones[loserIdx];

   g_zoneReg.zones[winnerIdx].upperBound = MathMax(g_zoneReg.zones[winnerIdx].upperBound, loserCopy.upperBound);
   g_zoneReg.zones[winnerIdx].lowerBound = MathMin(g_zoneReg.zones[winnerIdx].lowerBound, loserCopy.lowerBound);
   g_zoneReg.zones[winnerIdx].midPoint   = (g_zoneReg.zones[winnerIdx].upperBound + g_zoneReg.zones[winnerIdx].lowerBound) * 0.5;
   g_zoneReg.zones[winnerIdx].cleanTouchCount = MathMax(g_zoneReg.zones[winnerIdx].cleanTouchCount, loserCopy.cleanTouchCount);
   g_zoneReg.zones[winnerIdx].rawTouches = g_zoneReg.zones[winnerIdx].rawTouches + loserCopy.rawTouches;
   if(loserCopy.ageInBars < g_zoneReg.zones[winnerIdx].ageInBars)
      g_zoneReg.zones[winnerIdx].ageInBars = loserCopy.ageInBars;
   if(loserCopy.reactionScore > g_zoneReg.zones[winnerIdx].reactionScore)
      g_zoneReg.zones[winnerIdx].reactionScore = loserCopy.reactionScore;
   if(GetZonePriority(loserCopy.type) > GetZonePriority(g_zoneReg.zones[winnerIdx].type))
      g_zoneReg.zones[winnerIdx].type = loserCopy.type;
   if(loserCopy.protectedKeyZone)
      g_zoneReg.zones[winnerIdx].protectedKeyZone = true;
   g_zoneReg.zones[winnerIdx].label    = ZoneTypeToString(g_zoneReg.zones[winnerIdx].type);
   g_zoneReg.zones[winnerIdx].strength = CalcZoneStrength(g_zoneReg.zones[winnerIdx]);

   g_zoneReg.zones[loserIdx].active     = false;
   g_zoneReg.zones[loserIdx].historical = true;
   g_zoneReg.zones[loserIdx].parentZoneId = g_zoneReg.zones[winnerIdx].id;
}

//+------------------------------------------------------------------+
//| Confirmed-break check (pass zone by const ref — OK in MQL5)    |
//+------------------------------------------------------------------+
bool IsZoneConfirmedBroken(const ZoneInfo &z, const double &close[],
                           const double &high[], const double &low[],
                           int bars, double atrVal)
{
   if(bars < ZM_BREAK_CONFIRM + 1) return false;
   double buffer = atrVal * ZM_BREAK_ATR_MULT;
   bool isSup = IsBullishZone(z.type);
   bool isRes = IsBearishZone(z.type);
   if(!isSup && !isRes) return false;
   int confirms = 0;
   for(int b = 1; b <= ZM_BREAK_CONFIRM && b < bars; b++)
   {
      if(isSup && close[b] < z.lowerBound - buffer) confirms++;
      if(isRes && close[b] > z.upperBound + buffer) confirms++;
   }
   if(confirms >= ZM_BREAK_CONFIRM)
   {
      for(int b = 1; b <= ZM_BREAK_CONFIRM && b < bars; b++)
      {
         if(isSup && low[b]  > z.lowerBound) return false;
         if(isRes && high[b] < z.upperBound) return false;
      }
      return true;
   }
   return false;
}

bool IsZoneReclaimed(const ZoneInfo &z, double closePrice)
{
   if(!z.broken) return false;
   return (closePrice >= z.lowerBound && closePrice <= z.upperBound);
}

//+------------------------------------------------------------------+
//| Add zone or update existing match — direct indexing for writes  |
//+------------------------------------------------------------------+
int AddOrUpdateZone(ENUM_ZONE_TYPE type, double upper, double lower,
                    int touches, int ageBars, const SymbolProfile &prof,
                    double atrVal,
                    bool preserveDistinctStructure = false,
                    const string structuralTag = "",
                    int structuralBarIndex = -1,
                    const string methodTag = "",
                    int sourceCandleIndex = -1)
{
   string incomingMethod = SDMethodNameFromTag(methodTag);
   bool incomingPDFZone = SDIsPDFMethodTag(methodTag) || SDIsPDFLockedMethod(incomingMethod);

   int anchorShift = sourceCandleIndex >= 0 ? sourceCandleIndex : ageBars;
   datetime anchorTime = SDZoneAnchorTimeFromShift(anchorShift);

   // PDF method zones must be pinned. If the same method and source candle/base
   // already exists, reuse it and do not move the rectangle.
   if(incomingPDFZone && anchorTime > 0)
   {
      for(int ez = 0; ez < g_zoneReg.count; ez++)
      {
         if(!g_zoneReg.zones[ez].active)
            continue;

         if(g_zoneReg.zones[ez].broken)
            continue;

         if(!IsSameZoneDirection(type, g_zoneReg.zones[ez].type))
            continue;

         bool sameMethod = SDIncomingMethodMatchesZone(g_zoneReg.zones[ez], methodTag);
         bool sameAnchor =
            (g_zoneReg.zones[ez].sourceSwingTime == anchorTime ||
             g_zoneReg.zones[ez].sourceBarIndex == anchorShift);

         if(sameMethod && sameAnchor)
         {
            // Do not move, expand, shrink, or recenter.
            g_zoneReg.zones[ez].rawTouches += MathMax(touches, 1);
            g_zoneReg.zones[ez].cleanTouchCount = MathMax(g_zoneReg.zones[ez].cleanTouchCount, touches);
            g_zoneReg.zones[ez].lastEvaluatedTime = TimeCurrent();
            g_zoneReg.zones[ez].active = true;
            g_zoneReg.zones[ez].historical = false;

            Print("[SD_PINNED_ZONE_REUSED] id=", g_zoneReg.zones[ez].id,
                  " method=", g_zoneReg.zones[ez].sdCreationMethod,
                  " incomingMethod=", incomingMethod,
                  " anchor=", TimeToString(anchorTime),
                  " upper=", DoubleToString(g_zoneReg.zones[ez].upperBound, _Digits),
                  " lower=", DoubleToString(g_zoneReg.zones[ez].lowerBound, _Digits),
                  " reason=same_method_same_source_not_moved");

            return ez;
         }
      }
   }

   int matchIdx = FindMatchingZone(type, upper, lower, atrVal);

   // Secondary churn guard: if no match found, scan for a near-clone active same-family zone
   // to prevent spawning duplicates that slipped through FindMatchingZone's criteria.
   if(matchIdx < 0 && atrVal > 0)
   {
      double newMidCG = (upper + lower) * 0.5;
      for(int k = 0; k < g_zoneReg.count; k++)
      {
         bool allowHistorical =
            (g_zoneReg.zones[k].historical &&
             (g_zoneReg.zones[k].qualityScore >= MathMax(ZoneWeakRejectThreshold, 2.5) ||
              g_zoneReg.zones[k].structuralAnchor || g_zoneReg.zones[k].isFlipZone || g_zoneReg.zones[k].protectedKeyZone));

         if(!g_zoneReg.zones[k].active || g_zoneReg.zones[k].broken || (g_zoneReg.zones[k].historical && !allowHistorical)) continue;
         if(!IsSameZoneDirection(type, g_zoneReg.zones[k].type)) continue;
         if(!AreFamiliesCompatible(GetZoneFamily(type), GetZoneFamily(g_zoneReg.zones[k].type))) continue;
         if(MathAbs(newMidCG - g_zoneReg.zones[k].midPoint) > atrVal * 0.35) continue;
         if(!SimilarZoneShape(g_zoneReg.zones[k], upper, lower)) continue;
         if(preserveDistinctStructure && g_zoneReg.zones[k].structuralAnchor)
         {
            int barGap   = MathAbs(g_zoneReg.zones[k].sourceBarIndex - structuralBarIndex);
            bool sameTag  = (g_zoneReg.zones[k].structuralTag == structuralTag);
            string newSide   = ((structuralTag == "HH" || structuralTag == "HL") ? "BULL" : "BEAR");
            bool sameSide = (g_zoneReg.zones[k].structuralSide == newSide);
            if(!(sameTag && sameSide && barGap <= 1))
               continue;
         }
         matchIdx = k;
         Print("[ZONE_CHURN_GUARD] Reusing zone[", k, "] instead of spawning near-clone midDist=",
               DoubleToString(MathAbs(newMidCG - g_zoneReg.zones[k].midPoint) / atrVal, 2), "ATR");
         break;
      }
   }

   if(matchIdx >= 0 && atrVal > 0)
   {
      if(preserveDistinctStructure && g_zoneReg.zones[matchIdx].structuralAnchor)
      {
         int barGap   = MathAbs(g_zoneReg.zones[matchIdx].sourceBarIndex - structuralBarIndex);
         bool sameTag  = (g_zoneReg.zones[matchIdx].structuralTag == structuralTag);
         string newSide   = ((structuralTag == "HH" || structuralTag == "HL") ? "BULL" : "BEAR");
         bool sameSide = (g_zoneReg.zones[matchIdx].structuralSide == newSide);
         if(!(sameTag && sameSide && barGap <= 1))
            matchIdx = -1;
      }
   }
   if(matchIdx >= 0 && atrVal > 0)
   {
      double _newU = MathMax(g_zoneReg.zones[matchIdx].upperBound, upper);
      double _newL = MathMin(g_zoneReg.zones[matchIdx].lowerBound, lower);
      double mergedWidth = (_newU - _newL);
      double newMidAOU = (upper + lower) * 0.5;
      double midDistAOU = MathAbs(newMidAOU - g_zoneReg.zones[matchIdx].midPoint);

      if(mergedWidth > atrVal * 4.0 &&
         !SimilarZoneShape(g_zoneReg.zones[matchIdx], upper, lower) &&
         midDistAOU > atrVal * 0.25)
      {
         Print("[ZONE_KEEP_PARENT_CREATE_CHILD] parent kept, child will be minor, width=",
               DoubleToString(mergedWidth / prof.point, 0), "pts > ATR*4=",
               DoubleToString(atrVal / prof.point * 4.0, 0), "pts");
         matchIdx = -1;
         if(type == ZONE_RESISTANCE_MAJOR || type == ZONE_SUPPLY)  type = ZONE_RESISTANCE_MINOR;
         if(type == ZONE_SUPPORT_MAJOR    || type == ZONE_DEMAND)  type = ZONE_SUPPORT_MINOR;
      }
   }
   if(matchIdx >= 0)
   {
      if(g_zoneReg.zones[matchIdx].historical && !g_zoneReg.zones[matchIdx].broken)
      {
         g_zoneReg.zones[matchIdx].active     = true;
         g_zoneReg.zones[matchIdx].historical = false;
      }

      double proposedUpper = MathMax(g_zoneReg.zones[matchIdx].upperBound, upper);
      double proposedLower = MathMin(g_zoneReg.zones[matchIdx].lowerBound, lower);
      double proposedWidth = proposedUpper - proposedLower;
      double maxWidth = MathMax(atrVal * 0.60, prof.point * 45);

      // If new zone is fully contained in existing (no expansion), always allow merge
      bool fullyContained = (upper <= g_zoneReg.zones[matchIdx].upperBound &&
                             lower >= g_zoneReg.zones[matchIdx].lowerBound);

      if(proposedWidth > maxWidth && !fullyContained)
      {
         matchIdx = -1;
      }
   }

   if(matchIdx >= 0)
   {
      // PATCH 9: Do not move method zones after first creation
      bool isMethodZone = (g_zoneReg.zones[matchIdx].sdCreationMethod != "" &&
                           (StringFind(g_zoneReg.zones[matchIdx].sdCreationMethod, "PDF_") == 0 ||
                            StringFind(g_zoneReg.zones[matchIdx].sdCreationMethod, "FLIP") == 0));
      
      // absorb the new zone into the existing zone instead of creating another one
      if(!isMethodZone)
      {
         g_zoneReg.zones[matchIdx].upperBound = MathMax(g_zoneReg.zones[matchIdx].upperBound, upper);
         g_zoneReg.zones[matchIdx].lowerBound = MathMin(g_zoneReg.zones[matchIdx].lowerBound, lower);
         g_zoneReg.zones[matchIdx].midPoint   = (g_zoneReg.zones[matchIdx].upperBound + g_zoneReg.zones[matchIdx].lowerBound) * 0.5;
      }

      g_zoneReg.zones[matchIdx].rawTouches       += MathMax(touches, 1);
      g_zoneReg.zones[matchIdx].cleanTouchCount   = MathMax(g_zoneReg.zones[matchIdx].cleanTouchCount, touches);
      g_zoneReg.zones[matchIdx].ageInBars         = MathMin(g_zoneReg.zones[matchIdx].ageInBars, ageBars);
      g_zoneReg.zones[matchIdx].lastEvaluatedTime = TimeCurrent();
      g_zoneReg.zones[matchIdx].freshness         = MathMin(1.0, g_zoneReg.zones[matchIdx].freshness + 0.08);

      // keep the most useful type if overlapping families compete
      if(GetZonePriority(type) > GetZonePriority(g_zoneReg.zones[matchIdx].type))
         g_zoneReg.zones[matchIdx].type = type;
      else if(GetZonePriority(type) == GetZonePriority(g_zoneReg.zones[matchIdx].type))
      {
         ENUM_ZONE_FAMILY oldFam = GetZoneFamily(g_zoneReg.zones[matchIdx].type);
         ENUM_ZONE_FAMILY newFam = GetZoneFamily(type);

         // prefer Demand over Support for bullish zones
         if((oldFam == ZFAM_SUPPORT && newFam == ZFAM_DEMAND) ||
            (oldFam == ZFAM_RESISTANCE && newFam == ZFAM_SUPPLY))
         {
            g_zoneReg.zones[matchIdx].type = type;
         }
      }

      // PATCH 9: Skip width clamping for method zones
      if(!isMethodZone)
      {
         double width = g_zoneReg.zones[matchIdx].upperBound - g_zoneReg.zones[matchIdx].lowerBound;
         double maxWidth = MathMax(atrVal * 0.60, prof.point * 45);
         if(width > maxWidth)
         {
            double mid = g_zoneReg.zones[matchIdx].midPoint;
            g_zoneReg.zones[matchIdx].upperBound = mid + maxWidth * 0.5;
            g_zoneReg.zones[matchIdx].lowerBound = mid - maxWidth * 0.5;
            g_zoneReg.zones[matchIdx].midPoint   = mid;
         }
      }

      g_zoneReg.zones[matchIdx].label    = ZoneTypeToString(g_zoneReg.zones[matchIdx].type);
      g_zoneReg.zones[matchIdx].strength = CalcZoneStrength(g_zoneReg.zones[matchIdx]);
      g_zoneReg.zones[matchIdx].score    = g_zoneReg.zones[matchIdx].strength;
      g_zoneReg.zones[matchIdx].valid    = (g_zoneReg.zones[matchIdx].score >= ZM_MIN_VALID_SCORE
                                            && !g_zoneReg.zones[matchIdx].broken
                                            && g_zoneReg.zones[matchIdx].active);

      // PATCH 15: Track total touch count
      g_zoneReg.zones[matchIdx].touchCountTotal = MathMax(g_zoneReg.zones[matchIdx].touchCountTotal, touches);

      // Reduce log spam
      // Print("[ZONE_UPDATED] type=", ZoneTypeToString(g_zoneReg.zones[matchIdx].type),
      //       " high=", DoubleToString(g_zoneReg.zones[matchIdx].upperBound, _Digits),
      //       " low=", DoubleToString(g_zoneReg.zones[matchIdx].lowerBound, _Digits));

      return matchIdx;
   }

   int histRelIdx = FindRelatedHistoricalZone(type, upper, lower, atrVal);

   // Duplicate zone check: if a similar zone exists, merge instead of creating new
   if(atrVal > 0.0)
   {
      for(int k = 0; k < g_zoneReg.count; k++)
      {
         if(SDIsDuplicateZone(g_zoneReg.zones[k], type, upper, lower, atrVal))
         {
            double proposedUpper = MathMax(g_zoneReg.zones[k].upperBound, upper);
            double proposedLower = MathMin(g_zoneReg.zones[k].lowerBound, lower);
            double proposedWidth = proposedUpper - proposedLower;
            double maxWidth = MathMax(atrVal * 0.60, prof.point * 45);

            // If new zone is fully inside existing, allow merge (no expansion)
            bool fullyContained = (upper <= g_zoneReg.zones[k].upperBound &&
                                   lower >= g_zoneReg.zones[k].lowerBound);

            if(proposedWidth > maxWidth && !fullyContained)
            {
               Print("[DUPLICATE_MERGE_REJECTED_TOO_WIDE] newZone type=", ZoneTypeToString(type),
                     " upper=", DoubleToString(upper, _Digits),
                     " lower=", DoubleToString(lower, _Digits),
                     " existingId=", g_zoneReg.zones[k].id,
                     " proposedWidth=", DoubleToString(proposedWidth / prof.point, 0), "pts",
                     " maxWidth=", DoubleToString(maxWidth / prof.point, 0), "pts",
                     " reason=prevent_huge_merged_zone");
               continue;
            }

            Print("[DUPLICATE_ZONE_MERGE] newZone type=", ZoneTypeToString(type),
                  " upper=", DoubleToString(upper, _Digits),
                  " lower=", DoubleToString(lower, _Digits),
                  " mergedInto existingId=", g_zoneReg.zones[k].id);
            
            // PATCH 10: Do not move method zones
            bool isMethodZoneDup = (g_zoneReg.zones[k].sdCreationMethod != "" &&
                                    (StringFind(g_zoneReg.zones[k].sdCreationMethod, "PDF_") == 0 ||
                                     StringFind(g_zoneReg.zones[k].sdCreationMethod, "FLIP") == 0));
            
            // Merge into existing zone
            if(!isMethodZoneDup)
            {
               g_zoneReg.zones[k].upperBound = proposedUpper;
               g_zoneReg.zones[k].lowerBound = proposedLower;
               g_zoneReg.zones[k].midPoint = (proposedUpper + proposedLower) * 0.5;
            }
            g_zoneReg.zones[k].rawTouches += MathMax(touches, 1);
            g_zoneReg.zones[k].cleanTouchCount = MathMax(g_zoneReg.zones[k].cleanTouchCount, touches);
            g_zoneReg.zones[k].ageInBars = MathMin(g_zoneReg.zones[k].ageInBars, ageBars);
            g_zoneReg.zones[k].lastEvaluatedTime = TimeCurrent();
            g_zoneReg.zones[k].freshness = MathMin(1.0, g_zoneReg.zones[k].freshness + 0.08);
            
            if(GetZonePriority(type) > GetZonePriority(g_zoneReg.zones[k].type))
               g_zoneReg.zones[k].type = type;
            
            // STEP 6: Correct pattern after type update in duplicate merge
            if(InpSDClassifyPatternType && g_zoneReg.zones[k].structuralTag != "")
            {
               g_zoneReg.zones[k].structuralTag = SDCorrectPatternForZoneType(g_zoneReg.zones[k], g_zoneReg.zones[k].structuralTag);
               
               if(g_zoneReg.zones[k].isFlipZone)
               {
                  if(IsBearishZone(g_zoneReg.zones[k].type))
                     g_zoneReg.zones[k].structuralTag = "FLIP_SUPPLY";
                  else if(IsBullishZone(g_zoneReg.zones[k].type))
                     g_zoneReg.zones[k].structuralTag = "FLIP_DEMAND";
               }
            }
            
            g_zoneReg.zones[k].label = ZoneTypeToString(g_zoneReg.zones[k].type);
            g_zoneReg.zones[k].strength = CalcZoneStrength(g_zoneReg.zones[k]);
            g_zoneReg.zones[k].score = g_zoneReg.zones[k].strength;
            
            if(InpUseSupplyDemandZones)
            {
               g_zoneReg.zones[k].active = true;
               g_zoneReg.zones[k].historical = false;
               
               bool qualityOk =
                  g_zoneReg.zones[k].majorQualified ||
                  g_zoneReg.zones[k].qualityScore >= 4.50 ||
                  g_zoneReg.zones[k].score >= InpSDMinActiveZoneScore ||
                  g_zoneReg.zones[k].departureATR >= InpSDMinDepartureATR;
               
               g_zoneReg.zones[k].valid = qualityOk && !g_zoneReg.zones[k].broken;
            }
            else
            {
               g_zoneReg.zones[k].valid = (g_zoneReg.zones[k].score >= ZM_MIN_VALID_SCORE
                                          && !g_zoneReg.zones[k].broken
                                          && g_zoneReg.zones[k].active);
            }
            
            return k;
         }
      }
   }

   EvictWeakestActive();
   if(g_zoneReg.count >= ZM_MAX_TOTAL)
   {
      CleanupHistoricalZones();
      if(g_zoneReg.count >= ZM_MAX_TOTAL)
      {
         int worst = -1; double ws = 999.0;
         for(int i = 0; i < g_zoneReg.count; i++)
         {
            if(g_zoneReg.zones[i].protectedKeyZone) continue;
            if(g_zoneReg.zones[i].strength < ws)
               { ws = g_zoneReg.zones[i].strength; worst = i; }
         }
         if(worst >= 0) RemoveZoneSlot(worst);
         else return -1;
      }
   }

   int idx = g_zoneReg.count;
   InitZoneInfo(g_zoneReg.zones[idx], type, upper, lower, touches, ageBars, prof);

   // PATCH 8: Store method tag and source time for PDF zones
   if(methodTag != "")
   {
      g_zoneReg.zones[idx].sdCreationMethod = methodTag;
      if(sourceCandleIndex >= 0)
      {
         datetime srcTime = iTime(_Symbol, InpEntryTF, sourceCandleIndex);
         if(srcTime > 0)
         {
            // PATCH 12: Set source anchor for method zones
            g_zoneReg.zones[idx].structuralAnchor = true;
            g_zoneReg.zones[idx].sourceBarIndex = sourceCandleIndex;
            g_zoneReg.zones[idx].sourceSwingTime = srcTime;
         }
      }
   }

   if(histRelIdx >= 0)
   {
      ZoneInfo histCopy = g_zoneReg.zones[histRelIdx];
      g_zoneReg.zones[idx].relatedHistoricalZoneId = histCopy.id;
      bool sameDir     = IsSameZoneDirection(type, histCopy.type);
      bool oppositeDir = !sameDir && histCopy.broken;
      if(sameDir && ZoneOverlapPct(g_zoneReg.zones[idx], histCopy) > 0.3)
      {
         g_zoneReg.zones[idx].isRefinement             = true;
         g_zoneReg.zones[idx].isRetestOfHistoricalZone = true;
         g_zoneReg.zones[idx].strength = CalcZoneStrength(g_zoneReg.zones[idx]);
      }
      if(oppositeDir)
      {
         g_zoneReg.zones[idx].isFlipZone = true;
         g_zoneReg.zones[idx].strength   = CalcZoneStrength(g_zoneReg.zones[idx]);
         
         // STEP 5: Use corrected pattern after flip logic
         if(IsBearishZone(g_zoneReg.zones[idx].type))
         {
            g_zoneReg.zones[idx].structuralTag = "FLIP_SUPPLY";
            g_zoneReg.zones[idx].sdCreationMethod = "FLIP";
         }
         else if(IsBullishZone(g_zoneReg.zones[idx].type))
         {
            g_zoneReg.zones[idx].structuralTag = "FLIP_DEMAND";
            g_zoneReg.zones[idx].sdCreationMethod = "FLIP";
         }
      }
   }

   // PATCH 9 (insert path): Do not clamp PDF/FLIP method zones — they must keep
   // the full wick H/L of their source candle / consolidation as drawn by PDF.
   bool isMethodZoneNew = (g_zoneReg.zones[idx].sdCreationMethod != "" &&
                           (StringFind(g_zoneReg.zones[idx].sdCreationMethod, "PDF_") == 0 ||
                            StringFind(g_zoneReg.zones[idx].sdCreationMethod, "FLIP") == 0));

   if(!isMethodZoneNew)
   {
      double width = g_zoneReg.zones[idx].upperBound - g_zoneReg.zones[idx].lowerBound;
      double maxWidth = MathMax(atrVal * 0.60, prof.point * 45);
      if(width > maxWidth)
      {
         double mid = g_zoneReg.zones[idx].midPoint;
         g_zoneReg.zones[idx].upperBound = mid + maxWidth * 0.5;
         g_zoneReg.zones[idx].lowerBound = mid - maxWidth * 0.5;
         g_zoneReg.zones[idx].midPoint   = mid;
      }
   }

   // PATCH 15: Track total touch count
   g_zoneReg.zones[idx].touchCountTotal = MathMax(g_zoneReg.zones[idx].touchCountTotal, touches);

   g_zoneReg.count++;

   // Reduce log spam - only log major zones
   if(type == ZONE_SUPPORT_MAJOR || type == ZONE_RESISTANCE_MAJOR)
   {
      // Print("[ZONE_CREATED] type=", ZoneTypeToString(type),
      //       " high=", DoubleToString(upper, _Digits),
      //       " low=", DoubleToString(lower, _Digits));
   }

   return idx;
}

//+------------------------------------------------------------------+
//| Structural zone wrapper — stamps HH/HL/LH/LL directly           |
//+------------------------------------------------------------------+
int AddOrUpdateStructuralZone(ENUM_ZONE_TYPE type,
                              double upper,
                              double lower,
                              int touches,
                              int ageBars,
                              const SymbolProfile &prof,
                              double atrVal,
                              const string structuralTag,
                              const int sourceBarIndex,
                              const datetime sourceSwingTime,
                              const int sequenceIndex)
{
   int idx = AddOrUpdateZone(type, upper, lower, touches, ageBars, prof, atrVal,
                             true, structuralTag, sourceBarIndex);
   if(idx >= 0)
   {
      g_zoneReg.zones[idx].structuralAnchor = true;
      g_zoneReg.zones[idx].structuralTag    = structuralTag;
      g_zoneReg.zones[idx].sourceBarIndex   = sourceBarIndex;
      g_zoneReg.zones[idx].sourceSwingTime  = sourceSwingTime;
      g_zoneReg.zones[idx].sequenceIndex    = sequenceIndex;
      g_zoneReg.zones[idx].structuralScore  = MathMax(g_zoneReg.zones[idx].structuralScore, 0.80);
      g_zoneReg.zones[idx].sourceTF         = g_zoneTF;

      g_zoneReg.zones[idx].structuralLocked = true;

      if(structuralTag == "HH" || structuralTag == "HL")
         g_zoneReg.zones[idx].structuralSide = "BULL";
      else if(structuralTag == "LH" || structuralTag == "LL")
         g_zoneReg.zones[idx].structuralSide = "BEAR";
      else
         g_zoneReg.zones[idx].structuralSide = "";

      if(structuralTag == "HL" || structuralTag == "LH")
         g_zoneReg.zones[idx].score = MathMax(g_zoneReg.zones[idx].score, 0.90);
      else
         g_zoneReg.zones[idx].score = MathMax(g_zoneReg.zones[idx].score, 0.72);
   }
   return idx;
}

//+------------------------------------------------------------------+
//| Per-bar: age zones and update touch counts — direct indexing    |
//+------------------------------------------------------------------+
void AgeAndTouchUpdate(const double &high[], const double &low[],
                       int bars, const SymbolProfile &prof, double atrVal)
{
   double tolerance = MathMax(atrVal * 0.15, prof.defaultSLBufferPoints * prof.point);
   int currentBar = Bars(_Symbol, g_zoneTF);
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active && !g_zoneReg.zones[i].historical) continue;
      g_zoneReg.zones[i].ageInBars++;
      g_zoneReg.zones[i].lastEvaluatedTime = TimeCurrent();
      g_zoneReg.zones[i].freshness = MathMax(g_zoneReg.zones[i].freshness - ZM_FRESHNESS_AGE_DECAY, 0.0);
      if(!g_zoneReg.zones[i].active) continue;
      if(bars < 2) continue;
      bool hit = (high[1] >= g_zoneReg.zones[i].lowerBound - tolerance &&
                  low[1]  <= g_zoneReg.zones[i].upperBound + tolerance);
      if(hit)
      {
         g_zoneReg.zones[i].rawTouches++;
         int barsSince = (int)((TimeCurrent() - g_zoneReg.zones[i].lastTouchedTime) / PeriodSeconds(g_zoneTF));
         if(barsSince >= ZM_TOUCH_COOLDOWN)
         {
            g_zoneReg.zones[i].cleanTouchCount++;
            g_zoneReg.zones[i].lastTouchedTime = TimeCurrent();
            g_zoneReg.zones[i].lastTouchBar    = currentBar;
            g_zoneReg.zones[i].retestCount++;
            g_zoneReg.zones[i].freshness = MathMax(g_zoneReg.zones[i].freshness - ZM_FRESHNESS_DECAY, 0.0);
            double displacement = 0.0;
            if(IsBullishZone(g_zoneReg.zones[i].type))
               displacement = high[1] - g_zoneReg.zones[i].upperBound;
            else if(IsBearishZone(g_zoneReg.zones[i].type))
               displacement = g_zoneReg.zones[i].lowerBound - low[1];
            if(displacement > 0 && atrVal > 0)
               g_zoneReg.zones[i].reactionScore = MathMax(g_zoneReg.zones[i].reactionScore, displacement / atrVal);

            // STEP 15-16: Override touched zone with fresher alternative if available
            if(InpSDAllowTouchedZoneOverride &&
               g_zoneReg.zones[i].cleanTouchCount >= InpSDTouchedOverrideMaxTouches)
            {
               bool isBullish = IsBullishZone(g_zoneReg.zones[i].type);
               int freshIdx = -1;
               double bestFreshness = -DBL_MAX;

               for(int j = 0; j < g_zoneReg.count; j++)
               {
                  if(j == i || !g_zoneReg.zones[j].valid || g_zoneReg.zones[j].broken)
                     continue;

                  if(IsBullishZone(g_zoneReg.zones[j].type) != isBullish)
                     continue;

                  if(g_zoneReg.zones[j].cleanTouchCount >= g_zoneReg.zones[i].cleanTouchCount)
                     continue;

                  if(g_zoneReg.zones[j].qualityScore < InpSDTouchedOverrideMinQuality)
                     continue;

                  double freshScore = g_zoneReg.zones[j].qualityScore -
                                      (g_zoneReg.zones[j].cleanTouchCount * 0.5);

                  if(freshScore > bestFreshness)
                  {
                     bestFreshness = freshScore;
                     freshIdx = j;
                  }
               }

               if(freshIdx >= 0)
               {
                  Print("[SD_ZONE_OVERRIDE] Replacing touched zone id=", g_zoneReg.zones[i].id,
                        " touches=", g_zoneReg.zones[i].cleanTouchCount,
                        " with fresher zone id=", g_zoneReg.zones[freshIdx].id,
                        " touches=", g_zoneReg.zones[freshIdx].cleanTouchCount,
                        " quality=", DoubleToString(g_zoneReg.zones[freshIdx].qualityScore, 2));

                  if(isBullish)
                     g_activeDemandZoneId = g_zoneReg.zones[freshIdx].id;
                  else
                     g_activeSupplyZoneId = g_zoneReg.zones[freshIdx].id;

                  g_zoneReg.zones[i].isTPTargetOnly = true;
               }
            }
         }
         UpdateZoneScoreAndValid(i);
      }
   }
}

//+------------------------------------------------------------------+
//| Per-bar: evaluate confirmed breaks — direct indexing            |
//+------------------------------------------------------------------+
void EvaluateBreaks(const double &close[], const double &high[],
                    const double &low[], int bars, double atrVal)
{
   for(int i = g_zoneReg.count - 1; i >= 0; i--)
   {
      if(!g_zoneReg.zones[i].active)  continue;
      if(g_zoneReg.zones[i].broken)   continue;
      if(!IsZoneConfirmedBroken(g_zoneReg.zones[i], close, high, low, bars, atrVal)) continue;

      // Flip idempotence: skip if this zone was already flipped on the current structural bar
      int flipBarNow = Bars(_Symbol, g_zoneTF);
      if(g_zoneReg.zones[i].lastStructureBreakBar == flipBarNow && flipBarNow > 0)
         continue;
      g_zoneReg.zones[i].lastStructureBreakBar = flipBarNow;

      g_zoneReg.zones[i].breakConfirmCount = ZM_BREAK_CONFIRM;
      g_zoneReg.zones[i].breakScore        = 1.0;
      g_zoneReg.zones[i].broken            = true;

      if(g_zoneReg.zones[i].type == ZONE_SUPPORT_MAJOR)
      {
         // Demand/support broken downward: redraw it as Supply.
         g_zoneReg.zones[i].originalType = ZONE_SUPPORT_MAJOR;
         g_zoneReg.zones[i].type         = ZONE_RESISTANCE_MAJOR;
         g_zoneReg.zones[i].isFlipZone   = true;

         // Keep broken=true only while awaiting retest confirmation.
         g_zoneReg.zones[i].broken                 = true;
         g_zoneReg.zones[i].breakRetestReady       = false;
         g_zoneReg.zones[i].continuationEligible   = false;
         g_zoneReg.zones[i].confirmedRetest        = false;
         g_zoneReg.zones[i].failedRetest           = false;

         // Keep it visible and redrawable as the new role.
         g_zoneReg.zones[i].valid                  = true;
         g_zoneReg.zones[i].active                 = true;
         g_zoneReg.zones[i].historical             = false;
         g_zoneReg.zones[i].isPrimary              = true;
         g_zoneReg.zones[i].isBackup               = false;
         g_zoneReg.zones[i].isTPTargetOnly         = false;
         g_zoneReg.zones[i].isExecutionEligible    = false;

         // This former Demand is now the active Supply being watched for retest.
         if(g_activeDemandZoneId == g_zoneReg.zones[i].id)
            g_activeDemandZoneId = -1;

         g_activeSupplyZoneId = g_zoneReg.zones[i].id;

         g_zoneReg.zones[i].label = "Supply [FLIP_RETEST]";
         g_zoneReg.zones[i].structuralTag = "FLIP_SUPPLY";
         g_zoneReg.zones[i].sdCreationMethod = "FLIP";

         Print("[ZONE_FLIP_REDRAW_READY] oldRole=Demand newRole=Supply id=",
               g_zoneReg.zones[i].id,
               " upper=", DoubleToString(g_zoneReg.zones[i].upperBound, _Digits),
               " lower=", DoubleToString(g_zoneReg.zones[i].lowerBound, _Digits),
               " color=RED awaiting_retest=true");
      }
      else if(g_zoneReg.zones[i].type == ZONE_RESISTANCE_MAJOR)
      {
         // Supply/resistance broken upward: redraw it as Demand.
         g_zoneReg.zones[i].originalType = ZONE_RESISTANCE_MAJOR;
         g_zoneReg.zones[i].type         = ZONE_SUPPORT_MAJOR;
         g_zoneReg.zones[i].isFlipZone   = true;

         // Keep broken=true only while awaiting retest confirmation.
         g_zoneReg.zones[i].broken                 = true;
         g_zoneReg.zones[i].breakRetestReady       = false;
         g_zoneReg.zones[i].continuationEligible   = false;
         g_zoneReg.zones[i].confirmedRetest        = false;
         g_zoneReg.zones[i].failedRetest           = false;

         // Keep it visible and redrawable as the new role.
         g_zoneReg.zones[i].valid                  = true;
         g_zoneReg.zones[i].active                 = true;
         g_zoneReg.zones[i].historical             = false;
         g_zoneReg.zones[i].isPrimary              = true;
         g_zoneReg.zones[i].isBackup               = false;
         g_zoneReg.zones[i].isTPTargetOnly         = false;
         g_zoneReg.zones[i].isExecutionEligible    = false;

         // This former Supply is now the active Demand being watched for retest.
         if(g_activeSupplyZoneId == g_zoneReg.zones[i].id)
            g_activeSupplyZoneId = -1;

         g_activeDemandZoneId = g_zoneReg.zones[i].id;

         g_zoneReg.zones[i].label = "Demand [FLIP_RETEST]";
         g_zoneReg.zones[i].structuralTag = "FLIP_DEMAND";
         g_zoneReg.zones[i].sdCreationMethod = "FLIP";

         Print("[ZONE_FLIP_REDRAW_READY] oldRole=Supply newRole=Demand id=",
               g_zoneReg.zones[i].id,
               " upper=", DoubleToString(g_zoneReg.zones[i].upperBound, _Digits),
               " lower=", DoubleToString(g_zoneReg.zones[i].lowerBound, _Digits),
               " color=GREEN awaiting_retest=true");
      }
      else
      {
         MarkZoneHistorical(i);
      }
   }

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].broken || !g_zoneReg.zones[i].active) continue;
      if(bars < 2) continue;
      // Skip flip zones - they must stay broken=true for retest detection
      if(g_zoneReg.zones[i].isFlipZone) continue;
      if(IsZoneReclaimed(g_zoneReg.zones[i], close[1]))
      {
         g_zoneReg.zones[i].broken           = false;
         g_zoneReg.zones[i].breakConfirmCount = 0;
         g_zoneReg.zones[i].breakScore        = 0.0;
         g_zoneReg.zones[i].retestCount++;
         g_zoneReg.zones[i].cleanTouchCount++;
         g_zoneReg.zones[i].reactionScore    += 0.1;
         g_zoneReg.zones[i].strength          = CalcZoneStrength(g_zoneReg.zones[i]);
      }
   }
}

//+------------------------------------------------------------------+
//| Per-bar: expire old zones                                        |
//+------------------------------------------------------------------+
void ExpireOldZones(double atrVal = 0.0)
{
   double maxWidthPts = (atrVal > 0) ? (atrVal / _Point * 4.0) : 600.0;
   for(int i = g_zoneReg.count - 1; i >= 0; i--)
   {
      if(!g_zoneReg.zones[i].active)         continue;
      if(g_zoneReg.zones[i].protectedKeyZone) continue;
      if(g_zoneReg.zones[i].ageInBars > g_zoneLifetimeBars)
         { MarkZoneHistorical(i); continue; }
      double wPts = (g_zoneReg.zones[i].upperBound - g_zoneReg.zones[i].lowerBound) / _Point;
      if(wPts > maxWidthPts)
         { MarkZoneHistorical(i); Print("[ZONE_EVICTED_WIDE] width=", DoubleToString(wPts,0), "pts max=", DoubleToString(maxWidthPts,0), "pts"); }
   }
}

//+------------------------------------------------------------------+
//| Classify key zones — direct indexing                            |
//+------------------------------------------------------------------+
void ClassifyKeyZones()
{
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active && !g_zoneReg.zones[i].historical) continue;
      bool wasKey = g_zoneReg.zones[i].protectedKeyZone;
      g_zoneReg.zones[i].protectedKeyZone = false;

      if(g_zoneReg.zones[i].cleanTouchCount >= ZM_KEY_ZONE_MIN_TOUCHES &&
         g_zoneReg.zones[i].strength >= ZM_KEY_ZONE_MIN_STR)
         g_zoneReg.zones[i].protectedKeyZone = true;
      if(g_zoneReg.zones[i].reactionScore >= 0.5 && g_zoneReg.zones[i].cleanTouchCount >= 2)
         g_zoneReg.zones[i].protectedKeyZone = true;
      if(g_zoneReg.zones[i].isFlipZone && g_zoneReg.zones[i].retestCount >= 1)
         g_zoneReg.zones[i].protectedKeyZone = true;
      if(g_zoneReg.zones[i].isRefinement && g_zoneReg.zones[i].relatedHistoricalZoneId > 0
         && g_zoneReg.zones[i].cleanTouchCount >= 2)
         g_zoneReg.zones[i].protectedKeyZone = true;

      if(g_zoneReg.zones[i].protectedKeyZone != wasKey)
         g_zoneReg.zones[i].strength = CalcZoneStrength(g_zoneReg.zones[i]);
      g_zoneReg.zones[i].isRoundNumber = IsRoundNumberLevel(g_zoneReg.zones[i].midPoint);
   }
}

//+------------------------------------------------------------------+
//| Detection functions                                              |
//+------------------------------------------------------------------+
bool IsNearStructuralTaggedZone(double level, bool wantHigh, double atrVal)
{
   double tol = MathMax(atrVal * 0.20, _Point * 20);
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.valid || z.historical) continue;

      if(wantHigh)
      {
         if((z.structuralTag == "HH" || z.structuralTag == "LH") &&
            MathAbs(z.midPoint - level) <= tol)
            return true;
      }
      else
      {
         if((z.structuralTag == "HL" || z.structuralTag == "LL") &&
            MathAbs(z.midPoint - level) <= tol)
            return true;
      }
   }
   return false;
}

bool IsNearStructuralPrice(double level, bool wantHigh, double atrVal)
{
   if(!g_structure.valid) return false;
   
   double tol = MathMax(atrVal * 0.20, _Point * 20);
   
   if(wantHigh)
   {
      for(int i = 0; i < g_structure.swingHighCount; i++)
      {
         if(g_structure.swingHighs[i].valid && 
            (g_structure.swingHighs[i].isHigherHigh || g_structure.swingHighs[i].isLowerHigh) &&
            MathAbs(g_structure.swingHighs[i].price - level) <= tol)
            return true;
      }
   }
   else
   {
      for(int i = 0; i < g_structure.swingLowCount; i++)
      {
         if(g_structure.swingLows[i].valid && 
            (g_structure.swingLows[i].isHigherLow || g_structure.swingLows[i].isLowerLow) &&
            MathAbs(g_structure.swingLows[i].price - level) <= tol)
            return true;
      }
   }
   return false;
}

void DetectSwingHighs(const double &high[], const double &low[],
                      const double &close[], int bars, int lookback,
                      const SymbolProfile &prof, double atrVal)
{
   lookback = MathMax(lookback, 4);
   double tolerance = MathMax(atrVal * 0.16, prof.point * 22);
   int searchStart = MathMax(0, bars - 180);

   for(int i = lookback; i < bars - lookback; i++)
   {
      bool isSH = true;
      for(int j = 1; j <= lookback && isSH; j++)
         if(high[i] <= high[i-j] || high[i] <= high[i+j]) isSH = false;
      if(!isSH) continue;

      double level = high[i];
      int ageInBars = bars - 1 - i;
      bool isRecent = (ageInBars <= 60);

      bool isStructural = IsNearStructuralPrice(level, true, atrVal) ||
                          IsNearStructuralTaggedZone(level, true, atrVal);

      int touches = 0;
      int lastTouchBar = -999;
      int rejectionCount = 0;

      for(int k = searchStart; k < bars; k++)
      {
         if(k == i) continue;
         if(MathAbs(high[k] - level) <= tolerance)
         {
            if(MathAbs(k - lastTouchBar) >= 3)
            {
               double barRange = MathMax(high[k] - low[k], prof.point * 20);
               bool reject = (close[k] < high[k] - atrVal * 0.08);
               bool wickReject = ((high[k] - MathMax(close[k], low[k])) >= barRange * 0.22);

               if(reject)
               {
                  touches++;
                  if(wickReject) rejectionCount++;
                  lastTouchBar = k;
               }
            }
         }
      }

      if(!isStructural && touches < 2)
         continue;

      if(isStructural && !isRecent && touches < 1)
         continue;

      if((bars - 1 - i) <= 4)
         continue; // do not mark still-forming most recent pivot

      ENUM_ZONE_TYPE type = (touches >= 3 || rejectionCount >= 2)
         ? ZONE_RESISTANCE_MAJOR
         : ZONE_RESISTANCE_MINOR;

      AddOrUpdateZone(type, level + tolerance * 0.45, level - tolerance * 0.45,
                      MathMax(touches, 1), ageInBars, prof, atrVal);
   }
}

void DetectSwingLows(const double &high[], const double &low[],
                     const double &close[], int bars, int lookback,
                     const SymbolProfile &prof, double atrVal)
{
   lookback = MathMax(lookback, 4);
   double tolerance = MathMax(atrVal * 0.16, prof.point * 22);
   int searchStart = MathMax(0, bars - 180);

   for(int i = lookback; i < bars - lookback; i++)
   {
      bool isSL = true;
      for(int j = 1; j <= lookback && isSL; j++)
         if(low[i] >= low[i-j] || low[i] >= low[i+j]) isSL = false;
      if(!isSL) continue;

      double level = low[i];
      int ageInBars = bars - 1 - i;
      bool isRecent = (ageInBars <= 60);

      bool isStructural = IsNearStructuralPrice(level, false, atrVal) ||
                          IsNearStructuralTaggedZone(level, false, atrVal);

      int touches = 0;
      int lastTouchBar = -999;
      int rejectionCount = 0;

      for(int k = searchStart; k < bars; k++)
      {
         if(k == i) continue;
         if(MathAbs(low[k] - level) <= tolerance)
         {
            if(MathAbs(k - lastTouchBar) >= 3)
            {
               double barRange = MathMax(high[k] - low[k], prof.point * 20);
               bool reject = (close[k] > low[k] + atrVal * 0.08);
               bool wickReject = ((MathMin(close[k], high[k]) - low[k]) >= barRange * 0.22);

               if(reject)
               {
                  touches++;
                  if(wickReject) rejectionCount++;
                  lastTouchBar = k;
               }
            }
         }
      }

      if(!isStructural && touches < 2)
         continue;

      if(isStructural && !isRecent && touches < 1)
         continue;

      if((bars - 1 - i) <= 4)
         continue; // do not mark still-forming most recent pivot

      ENUM_ZONE_TYPE type = (touches >= 3 || rejectionCount >= 2)
         ? ZONE_SUPPORT_MAJOR
         : ZONE_SUPPORT_MINOR;

      AddOrUpdateZone(type, level + tolerance * 0.45, level - tolerance * 0.45,
                      MathMax(touches, 1), ageInBars, prof, atrVal);
   }
}

//+------------------------------------------------------------------+
//| Stamp HH/HL/LH/LL directly from g_structure into zone registry  |
//+------------------------------------------------------------------+
void StampTrendStructureZones(const SymbolProfile &prof, double atrVal)
{
   if(atrVal <= 0.0) return;

   bool bullState = (g_structure.state == STRUCTURE_BULL_TREND ||
                     g_structure.state == STRUCTURE_BIAS_BULL);
   bool bearState = (g_structure.state == STRUCTURE_BEAR_TREND ||
                     g_structure.state == STRUCTURE_BIAS_BEAR);

   if(!bullState && !bearState) return;

   double tolMajor = MathMax(atrVal * 0.10, prof.defaultSLBufferPoints * prof.point);
   double tolMinor = MathMax(atrVal * 0.08, prof.defaultSLBufferPoints * prof.point * 0.75);

   if(bullState)
   {
      int hlSeq = 0;
      for(int i = 0; i < g_structure.swingLowCount && hlSeq < 6; i++)
      {
         SwingPoint sp = g_structure.swingLows[i];
         if(!sp.valid || !sp.isHigherLow) continue;

         int idx = AddOrUpdateStructuralZone(
            ZONE_SUPPORT_MAJOR,
            sp.price + tolMajor,
            sp.price - tolMajor,
            2, sp.barIndex, prof, atrVal,
            "HL", sp.barIndex, sp.time, hlSeq);

         if(idx >= 0)
         {
            g_zoneReg.zones[idx].label = "HL_SUPPORT";
            g_zoneReg.zones[idx].score = MathMax(g_zoneReg.zones[idx].score, 0.85);
         }
         hlSeq++;
      }

      int hhSeq = 0;
      for(int i = 0; i < g_structure.swingHighCount && hhSeq < 6; i++)
      {
         SwingPoint sp = g_structure.swingHighs[i];
         if(!sp.valid || !sp.isHigherHigh) continue;

         int idx = AddOrUpdateStructuralZone(
            ZONE_RESISTANCE_MINOR,
            sp.price + tolMinor,
            sp.price - tolMinor,
            1, sp.barIndex, prof, atrVal,
            "HH", sp.barIndex, sp.time, hhSeq);

         if(idx >= 0)
         {
            g_zoneReg.zones[idx].label = "HH_RESISTANCE";
            g_zoneReg.zones[idx].score = MathMax(g_zoneReg.zones[idx].score, 0.60);
         }
         hhSeq++;
      }
   }

   if(bearState)
   {
      int lhSeq = 0;
      for(int i = 0; i < g_structure.swingHighCount && lhSeq < 6; i++)
      {
         SwingPoint sp = g_structure.swingHighs[i];
         if(!sp.valid || !sp.isLowerHigh) continue;

         int idx = AddOrUpdateStructuralZone(
            ZONE_RESISTANCE_MAJOR,
            sp.price + tolMajor,
            sp.price - tolMajor,
            2, sp.barIndex, prof, atrVal,
            "LH", sp.barIndex, sp.time, lhSeq);

         if(idx >= 0)
         {
            g_zoneReg.zones[idx].label = "LH_RESISTANCE";
            g_zoneReg.zones[idx].score = MathMax(g_zoneReg.zones[idx].score, 0.85);
         }
         lhSeq++;
      }

      int llSeq = 0;
      for(int i = 0; i < g_structure.swingLowCount && llSeq < 6; i++)
      {
         SwingPoint sp = g_structure.swingLows[i];
         if(!sp.valid || !sp.isLowerLow) continue;

         int idx = AddOrUpdateStructuralZone(
            ZONE_SUPPORT_MINOR,
            sp.price + tolMinor,
            sp.price - tolMinor,
            1, sp.barIndex, prof, atrVal,
            "LL", sp.barIndex, sp.time, llSeq);

         if(idx >= 0)
         {
            g_zoneReg.zones[idx].label = "LL_SUPPORT";
            g_zoneReg.zones[idx].score = MathMax(g_zoneReg.zones[idx].score, 0.60);
         }
         llSeq++;
      }
   }
}

void DetectCongestionZones(const double &high[], const double &low[],
                           const double &close[], const double &atr[],
                           int bars, const SymbolProfile &prof, double atrVal)
{
   int minBars = 3;
   for(int i = minBars; i < bars - 1; i++)
   {
      double av = (atr[i] > 0) ? atr[i] : prof.defaultSLBufferPoints * prof.point * 2.0;
      double band = av * 0.4;
      double wH = high[i], wL = low[i];

      for(int k = 1; k < minBars; k++)
      {
         wH = MathMax(wH, high[i-k]);
         wL = MathMin(wL, low[i-k]);
      }

      if(wH - wL > band || wH - wL <= 0) continue;

      bool allOv = true;
      for(int k = 1; k < minBars && allOv; k++)
      {
         if(low[i-k] > wH || high[i-k] < wL)
            allOv = false;
      }
      if(!allOv) continue;

      bool up   = (close[i - minBars] > wH);
      bool down = (close[i - minBars] < wL);

      // Do not create a directional zone when congestion is neutral
      if(!up && !down)
         continue;

      ENUM_ZONE_TYPE ct = down ? ZONE_RESISTANCE_MAJOR : ZONE_SUPPORT_MAJOR;
      AddOrUpdateZone(ct, wH, wL, minBars, bars - 1 - i, prof, atrVal);
   }
}

double SDHighest(const double &arr[], int from, int to)
{
   double v = -DBL_MAX;
   for(int i = from; i <= to; i++)
      v = MathMax(v, arr[i]);
   return v;
}

double SDLowest(const double &arr[], int from, int to)
{
   double v = DBL_MAX;
   for(int i = from; i <= to; i++)
      v = MathMin(v, arr[i]);
   return v;
}

double SDAvgBody(const double &open[], const double &close[], int bars)
{
   double sum = 0.0;
   int n = 0;

   for(int i = 1; i < bars - 1; i++)
   {
      sum += MathAbs(close[i] - open[i]);
      n++;
   }

   return (n > 0 ? sum / n : 0.0);
}

bool SDIsBullMomentum(const double &open[], const double &high[],
                      const double &low[], const double &close[],
                      int i, double avgBody)
{
   double range = high[i] - low[i];
   if(range <= 0.0) return false;

   double body = MathAbs(close[i] - open[i]);
   double bodyPct = body / range;

   return (close[i] > open[i] &&
           bodyPct >= InpSDMomentumBodyPct &&
           body >= avgBody * InpSDMomentumBodyMult);
}

bool SDIsExtremeBullImpulse(const double &open[], const double &high[],
                            const double &low[], const double &close[],
                            int i, double avgBody, double atrVal)
{
   double range = high[i] - low[i];
   if(range <= 0.0 || avgBody <= 0.0 || atrVal <= 0.0)
      return false;

   double body = MathAbs(close[i] - open[i]);
   double bodyPct = body / range;

   return (close[i] > open[i] &&
           bodyPct >= InpSDExtremeImpulseBodyPct &&
           body >= avgBody * InpSDExtremeImpulseBodyMult &&
           range >= atrVal * InpSDExtremeImpulseRangeATR);
}

bool SDIsBearMomentum(const double &open[], const double &high[],
                      const double &low[], const double &close[],
                      int i, double avgBody)
{
   double range = high[i] - low[i];
   if(range <= 0.0) return false;

   double body = MathAbs(close[i] - open[i]);
   double bodyPct = body / range;

   return (close[i] < open[i] &&
           bodyPct >= InpSDMomentumBodyPct &&
           body >= avgBody * InpSDMomentumBodyMult);
}

bool SDIsExtremeBearImpulse(const double &open[], const double &high[],
                            const double &low[], const double &close[],
                            int i, double avgBody, double atrVal)
{
   double range = high[i] - low[i];
   if(range <= 0.0 || avgBody <= 0.0 || atrVal <= 0.0)
      return false;

   double body = MathAbs(close[i] - open[i]);
   double bodyPct = body / range;

   return (close[i] < open[i] &&
           bodyPct >= InpSDExtremeImpulseBodyPct &&
           body >= avgBody * InpSDExtremeImpulseBodyMult &&
           range >= atrVal * InpSDExtremeImpulseRangeATR);
}

int SDIncomingLegDirection(const double &open[],
                           const double &high[],
                           const double &low[],
                           const double &close[],
                           int baseIndex,
                           int bars,
                           double avgBody)
{
   // Arrays are now series:
   // index 0 = current forming candle
   // index 1 = last closed candle
   // higher index = older candles
   //
   // Incoming leg BEFORE the base is older than the base:
   // baseIndex + 1, baseIndex + 2, etc.

   int bull = 0;
   int bear = 0;

   int maxBars = MathMax(2, InpSDPreBaseLegBars);
   int endIndex = MathMin(baseIndex + maxBars, bars - 2);

   for(int k = baseIndex + 1; k <= endIndex; k++)
   {
      if(k < 1 || k >= bars)
         continue;

      double range = high[k] - low[k];
      if(range <= 0.0)
         continue;

      double body = MathAbs(close[k] - open[k]);
      double bodyPct = body / range;

      bool bullMomentum = SDIsBullMomentum(open, high, low, close, k, avgBody);
      bool bearMomentum = SDIsBearMomentum(open, high, low, close, k, avgBody);

      if(!bullMomentum && !bearMomentum && bodyPct >= InpSDWeakLegBodyPct)
      {
         if(close[k] > open[k])
            bullMomentum = true;
         else if(close[k] < open[k])
            bearMomentum = true;
      }

      if(bullMomentum)
         bull++;

      if(bearMomentum)
         bear++;
   }

   int minNeeded = MathMax(1, InpSDMinPreBaseMomentum);

   if(bull >= minNeeded && bull > bear)
      return 1;     // Rally into the base

   if(bear >= minNeeded && bear > bull)
      return -1;    // Drop into the base

   return 0;
}

string SDPatternCode(bool isDemand, int incomingLegDirection)
{
   // incomingLegDirection:
   // +1 = Rally before base
   // -1 = Drop before base
   //  0 = Unknown/mixed

   if(isDemand)
   {
      if(incomingLegDirection < 0)
         return "DBR";   // Drop Base Rally = Demand reversal

      if(incomingLegDirection > 0)
         return "RBR";   // Rally Base Rally = Demand continuation

      return "DBR_UNKNOWN";
   }

   // Supply
   if(incomingLegDirection > 0)
      return "RBD";      // Rally Base Drop = Supply reversal

   if(incomingLegDirection < 0)
      return "DBD";      // Drop Base Drop = Supply continuation

   return "RBD_UNKNOWN";
}

bool SDPatternIsContinuation(string patternCode)
{
   return (patternCode == "DBD" || patternCode == "RBR");
}

bool SDPatternIsReversal(string patternCode)
{
   return (patternCode == "RBD" || patternCode == "DBR" ||
           patternCode == "RBD_UNKNOWN" || patternCode == "DBR_UNKNOWN");
}

string SDPatternDescription(string patternCode)
{
   if(patternCode == "RBD") return "Rally Base Drop";
   if(patternCode == "DBD") return "Drop Base Drop";
   if(patternCode == "DBR") return "Drop Base Rally";
   if(patternCode == "RBR") return "Rally Base Rally";
   return "Unknown S/D Pattern";
}

string SDCorrectPatternForZoneType(ZoneInfo &z, string patternCode)
{
   if(IsBullishZone(z.type))
   {
      if(patternCode == "RBD" || patternCode == "DBD")
         return "DBR";
      if(patternCode == "RBD_UNKNOWN")
         return "DBR_UNKNOWN";
   }
   else if(IsBearishZone(z.type))
   {
      if(patternCode == "DBR" || patternCode == "RBR")
         return "RBD";
      if(patternCode == "DBR_UNKNOWN")
         return "RBD_UNKNOWN";
   }
   
   return patternCode;
}

//+------------------------------------------------------------------+
//| Active Supply/Demand Pair Selection Helpers                      |
//+------------------------------------------------------------------+
int SDFindZoneIndexById(int zoneId)
{
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(g_zoneReg.zones[i].id == zoneId)
         return i;
   }
   return -1;
}

bool SDZoneContainsPrice(ZoneInfo &z, double price)
{
   return (price <= z.upperBound && price >= z.lowerBound);
}

bool SDZoneIsBelowOrTouchingPrice(ZoneInfo &z, double price)
{
   return (z.upperBound <= price || SDZoneContainsPrice(z, price));
}

bool SDZoneIsAboveOrTouchingPrice(ZoneInfo &z, double price)
{
   return (z.lowerBound >= price || SDZoneContainsPrice(z, price));
}

bool SDPatternIsKnown(const string patternCode)
{
   return (patternCode == "RBD" ||
           patternCode == "DBD" ||
           patternCode == "DBR" ||
           patternCode == "RBR");
}

bool SDZoneIsFreshEnough(ZoneInfo &z)
{
   if(z.broken)
      return false;
   if(z.cleanTouchCount > InpSDMaxFreshTouches)
      return false;
   return true;
}

bool SDPatternMatchesZoneType(ZoneInfo &z)
{
   string p = z.structuralTag;

   if(IsBearishZone(z.type))
   {
      // Supply zones can only be RBD/DBD or flip supply.
      return (p == "RBD" ||
              p == "DBD" ||
              p == "RBD_UNKNOWN" ||
              p == "DBD_UNKNOWN" ||
              p == "FLIP_SUPPLY" ||
              p == "PDF_WICK_SUPPLY" ||
              p == "PDF_MOMENTUM_SUPPLY" ||
              p == "PDF_CONSOLIDATION_SUPPLY");
   }

   if(IsBullishZone(z.type))
   {
      // Demand zones can only be DBR/RBR or flip demand.
      return (p == "DBR" ||
              p == "RBR" ||
              p == "DBR_UNKNOWN" ||
              p == "RBR_UNKNOWN" ||
              p == "FLIP_DEMAND" ||
              p == "PDF_WICK_DEMAND" ||
              p == "PDF_MOMENTUM_DEMAND" ||
              p == "PDF_CONSOLIDATION_DEMAND");
   }

   return false;
}

bool SDZoneCorrectSideForTrading(ZoneInfo &z, double price)
{
   if(SDZoneContainsPrice(z, price))
      return true;

   // Use dynamic labeling based on price position instead of static zone type
   if(z.upperBound <= price)
      return true;  // Zone below price → Demand
   if(z.lowerBound >= price)
      return true;  // Zone above price → Supply

   return false;
}

double SDZoneFreshnessValue(ZoneInfo &z)
{
   double v = 1.0;
   
   if(z.cleanTouchCount <= 0)
      v += 1.0;
   else if(z.cleanTouchCount == 1)
      v += 0.40;
   else
      v -= 0.75;
   
   v += MathMax(0.0, z.freshnessScore);
   
   if(z.ageInBars <= 50)
      v += 0.50;
   else if(z.ageInBars <= 150)
      v += 0.20;
   else
      v -= 0.35;
   
   return v;
}

double SDZoneStrengthValue(ZoneInfo &z)
{
   double v = 0.0;
   
   v += z.score;
   v += z.strength;
   v += z.qualityScore * 0.25;
   v += MathMin(z.departureATR, 2.50) * 0.35;
   v += z.majorQualified ? 0.75 : 0.0;
   
   return v;
}

double SDZonePatternValue(ZoneInfo &z)
{
   string p = z.structuralTag;
   
   if(p == "DBD" || p == "RBR")
      return 1.00;
   
   if(p == "RBD" || p == "DBR")
      return 0.85;
   
   if(p == "RBD_UNKNOWN" || p == "DBR_UNKNOWN")
      return 0.35;
   
   return 0.0;
}

double SDZoneProximityValue(ZoneInfo &z, double price, double atrVal)
{
   if(atrVal <= 0.0)
      return 0.0;
   
   if(SDZoneContainsPrice(z, price))
      return 1.50;
   
   double dist = 0.0;
   
   if(IsBullishZone(z.type))
      dist = MathAbs(price - z.upperBound);
   else if(IsBearishZone(z.type))
      dist = MathAbs(z.lowerBound - price);
   
   double atrDist = dist / atrVal;
   
   if(atrDist <= 0.50)
      return 1.25;
   if(atrDist <= 1.00)
      return 1.00;
   if(atrDist <= 2.00)
      return 0.60;
   if(atrDist <= 4.00)
      return 0.25;
   
   return -0.25;
}

double SDMethodScore(ZoneInfo &z)
{
   string m = z.sdCreationMethod;

   // Momentum zones are strongest when there is clear imbalance.
   if(m == "MOMENTUM")
      return 1.50;

   // Consolidation zones are strong when the base is clean and departure is strong.
   if(m == "CONSOLIDATION")
      return 1.25;

   // Wick zones are useful, but should be treated more carefully unless quality confirms.
   if(m == "WICK")
   {
      double s = 0.50;

      if(z.rejectionQualityScore >= 0.60)
         s += 0.50;

      if(z.structureImpactScore >= 0.75 || z.majorQualified)
         s += 0.50;

      return s;
   }

   return 0.0;
}

double SDActiveZoneScore(ZoneInfo &z, double price, double atrVal)
{
   double score = 0.0;

   int trend = GetMarketTrend(); // 1 bull, -1 bear, 0 range/neutral
   string p = z.structuralTag;

   bool actsAsDemand = SDZoneActsAsDemand(z, price);
   bool actsAsSupply = SDZoneActsAsSupply(z, price);

   // 1. Trend-direction priority using dynamic S/D role.
   if(trend == -1)
   {
      if(actsAsSupply)
      {
         score += 3.00;

         if(p == "DBD" || p == "FLIP_SUPPLY" || p == "PDF_MOMENTUM_SUPPLY" || p == "PDF_CONSOLIDATION_SUPPLY")
            score += 2.00;
         else if(p == "RBD" || p == "RBD_UNKNOWN" || p == "PDF_WICK_SUPPLY")
            score += 1.20;
      }
      else if(actsAsDemand)
      {
         bool counterTrendOk =
            (p == "DBR" || p == "DBR_UNKNOWN" || p == "FLIP_DEMAND" ||
             p == "PDF_MOMENTUM_DEMAND" || p == "PDF_CONSOLIDATION_DEMAND") &&
            (z.structureImpactScore >= 0.75 || z.majorQualified);

         score += counterTrendOk ? 0.50 : -4.00;
      }
   }
   else if(trend == 1)
   {
      if(actsAsDemand)
      {
         score += 3.00;

         if(p == "RBR" || p == "FLIP_DEMAND" || p == "PDF_MOMENTUM_DEMAND" || p == "PDF_CONSOLIDATION_DEMAND")
            score += 2.00;
         else if(p == "DBR" || p == "DBR_UNKNOWN" || p == "PDF_WICK_DEMAND")
            score += 1.20;
      }
      else if(actsAsSupply)
      {
         bool counterTrendOk =
            (p == "RBD" || p == "RBD_UNKNOWN" || p == "FLIP_SUPPLY" ||
             p == "PDF_MOMENTUM_SUPPLY" || p == "PDF_CONSOLIDATION_SUPPLY") &&
            (z.structureImpactScore >= 0.75 || z.majorQualified);

         score += counterTrendOk ? 0.50 : -4.00;
      }
   }
   else
   {
      score += 1.00;
   }

   // 2. Freshness
   if(z.cleanTouchCount == 0)
      score += 2.00;
   else if(z.cleanTouchCount == 1)
      score += 1.00;
   else
      score -= z.cleanTouchCount * 0.35;

   // 3. Strength / quality
   score += MathMin(z.departureATR, 3.00) * 1.20;
   score += z.qualityScore * 0.40;
   score += z.score * 1.00;
   score += z.strength * 0.75;

   if(z.majorQualified)
      score += 1.00;

   score += SDMethodScore(z);

   // 4. Proximity using dynamic role.
   if(atrVal > 0.0)
   {
      double dist = 0.0;

      if(price >= z.lowerBound && price <= z.upperBound)
         dist = 0.0;
      else if(actsAsDemand)
         dist = MathAbs(price - z.upperBound);
      else if(actsAsSupply)
         dist = MathAbs(z.lowerBound - price);
      else
         dist = MathAbs(price - z.midPoint);

      double distATR = dist / atrVal;

      if(distATR <= 0.50) score += 1.50;
      else if(distATR <= 1.00) score += 1.00;
      else if(distATR <= 2.00) score += 0.50;
      else if(distATR > 5.00) score -= 1.00;
   }

   if(z.historical)
      score -= 0.50;

   if(!z.valid)
      score -= 0.50;

   return score;
}

void SDClearActiveFlags()
{
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      g_zoneReg.zones[i].isPrimary = false;
      g_zoneReg.zones[i].isBackup  = false;
   }
   
   g_activeDemandZoneId = -1;
   g_activeSupplyZoneId = -1;
   
   ArrayResize(g_backupDemandZoneIds, 0);
   ArrayResize(g_backupSupplyZoneIds, 0);
}

void SDAddBackupId(bool isDemand, int zoneId)
{
   if(zoneId < 0)
      return;
   
   if(isDemand)
   {
      int n = ArraySize(g_backupDemandZoneIds);
      if(n >= InpSDMaxBackupZonesPerSide)
         return;
      ArrayResize(g_backupDemandZoneIds, n + 1);
      g_backupDemandZoneIds[n] = zoneId;
   }
   else
   {
      int n = ArraySize(g_backupSupplyZoneIds);
      if(n >= InpSDMaxBackupZonesPerSide)
         return;
      ArrayResize(g_backupSupplyZoneIds, n + 1);
      g_backupSupplyZoneIds[n] = zoneId;
   }
}

//+------------------------------------------------------------------+
//| STEP 6: Find Nearest Opposite Zone for TP Targets               |
//| Finds the nearest Supply zone (if wantDemand=false) or          |
//| Demand zone (if wantDemand=true) for use as TP target           |
//| Internal-only and relevance-aware                                |
//+------------------------------------------------------------------+
int SDFindNearestOppositeZone(bool wantDemand, double price, double atrVal)
{
   double bestScore = -DBL_MAX;
   int bestIdx = -1;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      // Allow historical-but-sound zones to be promoted as opposite-side
      // fallback. Many supply zones get flipped to historical=true/active=false
      // during dedup/photo-filter but are still structurally valid.
      if(!g_zoneReg.zones[i].active)
      {
         bool soundHistorical =
            (!g_zoneReg.zones[i].broken &&
             !g_zoneReg.zones[i].failedRetest &&
             (g_zoneReg.zones[i].valid ||
              g_zoneReg.zones[i].majorQualified ||
              g_zoneReg.zones[i].qualityScore >= 4.75));

         if(!soundHistorical)
            continue;
      }

      if(g_zoneReg.zones[i].broken && !SDIsPendingFlipRetestZone(g_zoneReg.zones[i]))
         continue;

      if(g_zoneReg.zones[i].failedRetest)
         continue;

      bool isCorrectSide = wantDemand ? (g_zoneReg.zones[i].upperBound <= price)
                                      : (g_zoneReg.zones[i].lowerBound >= price);

      if(!isCorrectSide)
         continue;

      double distATR = SDDistanceToZoneATR(g_zoneReg.zones[i], price, atrVal);

      if(atrVal > 0.0 && distATR > SD_ACTIVE_PAIR_FALLBACK_MAX_ATR)
         continue;

      if(g_zoneReg.zones[i].ageInBars > 1200 && !g_zoneReg.zones[i].majorQualified)
         continue;

      if(SDZoneTooWideForActiveDisplay(g_zoneReg.zones[i], atrVal))
         continue;

      bool qualityOk =
         g_zoneReg.zones[i].valid ||
         g_zoneReg.zones[i].majorQualified ||
         g_zoneReg.zones[i].qualityScore >= 4.75 ||
         g_zoneReg.zones[i].departureATR >= InpSDMinDepartureATR;

      if(!qualityOk)
         continue;

      double score = SDVisibleSideScore(g_zoneReg.zones[i], wantDemand, price, atrVal);

      // For the opposite visible boundary, distance matters, but do not hide it
      // only because price is not currently touching it.
      score -= distATR * 0.65;

      if(score > bestScore)
      {
         bestScore = score;
         bestIdx = i;
      }
   }

   return bestIdx;
}

bool SDPromoteFallbackVisibleSide(bool wantDemand, double price, double atrVal)
{
   int idx = SDFindNearestOppositeZone(wantDemand, price, atrVal);

   if(idx < 0)
      return false;

   bool executable = !g_zoneReg.zones[idx].broken;

   SDMarkActiveVisualSlot(idx, wantDemand, executable);

   // Re-read after potential valid-rehab inside SDMarkActiveVisualSlot.
   executable = g_zoneReg.zones[idx].isExecutionEligible;

   Print(wantDemand ? "[DEMAND_FALLBACK_PROMOTED_VISIBLE]" : "[SUPPLY_FALLBACK_PROMOTED_VISIBLE]",
         " id=", g_zoneReg.zones[idx].id,
         " upper=", DoubleToString(g_zoneReg.zones[idx].upperBound, _Digits),
         " lower=", DoubleToString(g_zoneReg.zones[idx].lowerBound, _Digits),
         " age=", g_zoneReg.zones[idx].ageInBars,
         " touches=", g_zoneReg.zones[idx].cleanTouchCount,
         " executable=", executable ? "true" : "false",
         " reason=visible_opposite_active_side");

   return true;
}

//+------------------------------------------------------------------+
//| Final active S/D visual policy                                   |
//| Registry may keep many zones. Chart may show max 1 Demand +       |
//| max 1 Supply. Visible active zones must be recent, clean, and     |
//| close/relevant.                                                   |
//+------------------------------------------------------------------+

double SDZoneWidthATR(ZoneInfo &z, double atrVal)
{
   if(atrVal <= 0.0)
      return 0.0;

   return MathAbs(z.upperBound - z.lowerBound) / atrVal;
}

double SDDistanceToZoneATR(ZoneInfo &z, double price, double atrVal)
{
   if(atrVal <= 0.0)
      return 0.0;

   if(SDZoneContainsPrice(z, price))
      return 0.0;

   double dist = 0.0;

   if(z.upperBound < price)
      dist = price - z.upperBound;
   else if(z.lowerBound > price)
      dist = z.lowerBound - price;
   else
      dist = 0.0;

   return dist / atrVal;
}

bool SDIsPendingFlipRetestZone(ZoneInfo &z)
{
   return (z.isFlipZone &&
           z.broken &&
           !z.failedRetest &&
           z.active &&
           z.ageInBars <= SD_FLIP_RETEST_KEEP_BARS);
}

bool SDZoneTooWideForActiveDisplay(ZoneInfo &z, double atrVal)
{
   if(atrVal <= 0.0)
      return false;

   double widthATR = SDZoneWidthATR(z, atrVal);

   if(widthATR <= SD_ACTIVE_MAX_WIDTH_ATR)
      return false;

   // Major zones may remain in registry, but wide zones should not become
   // the visible active entry zone unless they are being watched as a fresh flip.
   if(SDIsPendingFlipRetestZone(z))
      return false;

   return true;
}

bool SDZoneTooTouchedForActiveDisplay(ZoneInfo &z, double price, double atrVal)
{
   if(z.cleanTouchCount <= SD_ACTIVE_MAX_CLEAN_TOUCHES)
      return false;

   if(z.majorQualified && SDZoneWidthATR(z, atrVal) <= SD_ACTIVE_MAX_WIDTH_ATR)
      return false;

   // If a zone is very clean and narrow, allow extra touches only when price is
   // actually inside it. Wide multi-touch zones must not be marked as active.
   if(SDZoneContainsPrice(z, price) &&
      SDZoneWidthATR(z, atrVal) <= 1.20 &&
      z.cleanTouchCount <= SD_ACTIVE_MAX_CLEAN_TOUCHES + 2)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Structural role helpers                                          |
//| HL/LL = support/demand unless confirmed broken and retested.      |
//| LH/HH = resistance/supply unless confirmed broken and retested.   |
//+------------------------------------------------------------------+
bool SDTagIsDemandSide(const string tag)
{
   return (tag == "HL" || tag == "LL");
}

bool SDTagIsSupplySide(const string tag)
{
   return (tag == "LH" || tag == "HH");
}

double SDSweepTolerance(ZoneInfo &z, double atrVal)
{
   double width = MathAbs(z.upperBound - z.lowerBound);
   double atrTol = (atrVal > 0.0 ? atrVal * 0.35 : 0.0);
   double widthTol = width * 0.75;
   return MathMax(atrTol, widthTol);
}

bool SDZoneCanActAsDemandSide(ZoneInfo &z, double price, double atrVal)
{
   if(price <= 0.0)
      return false;

   if(SDIsPendingFlipRetestZone(z))
      return false;

   if(z.broken || z.failedRetest)
      return false;

   double tol = SDSweepTolerance(z, atrVal);

   // Structural support must not become supply just because price sweeps a little below it.
   if(SDTagIsDemandSide(z.structuralTag))
      return (price >= z.lowerBound - tol);

   // Bearish structural zones are not demand unless explicitly flipped/retested.
   if(SDTagIsSupplySide(z.structuralTag) && !z.flipRetestConfirmed)
      return false;

   if(IsBullishZone(z.type))
      return (price >= z.lowerBound - tol);

   if(z.isFlipZone && z.flipRetestConfirmed && IsBullishZone(z.type))
      return true;

   return false;
}

bool SDZoneCanActAsSupplySide(ZoneInfo &z, double price, double atrVal)
{
   if(price <= 0.0)
      return false;

   if(SDIsPendingFlipRetestZone(z))
      return false;

   if(z.broken || z.failedRetest)
      return false;

   double tol = SDSweepTolerance(z, atrVal);

   // Structural resistance can act as supply.
   if(SDTagIsSupplySide(z.structuralTag))
      return (price <= z.upperBound + tol);

   // Structural support should not be treated as supply unless flip was confirmed.
   if(SDTagIsDemandSide(z.structuralTag) && !z.flipRetestConfirmed)
      return false;

   if(IsBearishZone(z.type))
      return (price <= z.upperBound + tol);

   if(z.isFlipZone && z.flipRetestConfirmed && IsBearishZone(z.type))
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Strong/moderate execution filter for S/D and structural zones     |
//| Weak zones can remain in memory/visual context, but cannot trade. |
//+------------------------------------------------------------------+
bool SDZonePassesExecutionQuality(ZoneInfo &z, double atrVal, bool allowModerate)
{
   if(!z.active)
      return false;

   if(z.isTPTargetOnly)
      return false;

   if(z.failedRetest)
      return false;

   if(z.broken)
      return false;

   // Pending broken flip zones are watch-only until retest confirms.
   if(SDIsPendingFlipRetestZone(z))
      return false;

   bool structuralZone =
      (z.structuralAnchor ||
       z.protectedKeyZone ||
       z.structuralTag == "HL" ||
       z.structuralTag == "LH" ||
       z.structuralTag == "HH" ||
       z.structuralTag == "LL" ||
       z.continuationEligible ||
       z.breakRetestReady);

   bool strongZone =
      z.majorQualified ||
      z.qualityScore >= InpStrongZoneQuality ||
      (z.qualityChecklistHits >= ZoneMinimumChecklistHitsEffective() &&
       z.qualityScore >= ZoneMajorThresholdEffective());

   bool moderateZone = false;

   if(allowModerate)
   {
      moderateZone =
         z.qualityScore >= InpModerateZoneQuality &&
         (z.qualityChecklistHits >= MathMax(2, ZoneMinimumChecklistHitsEffective() - 1) ||
          z.departureATR >= InpSDMinDepartureATR * 0.70 ||
          z.hasRejection ||
          z.rejectionQualityScore >= 0.50 ||
          structuralZone);
   }

   bool structuralException =
      allowModerate &&
      InpPreferStructuralZones &&
      structuralZone &&
      z.qualityScore >= MathMax(3.75, InpModerateZoneQuality - 0.50);

   if(!strongZone && !moderateZone && !structuralException)
      return false;

   if(atrVal > 0.0)
   {
      double widthATR = SDZoneWidthATR(z, atrVal);

      // Moderate wide zones are too risky for execution.
      if(widthATR > SD_ACTIVE_MAX_WIDTH_ATR && !strongZone)
         return false;
   }

   return true;
}

bool SDZoneIsVisibleSideCandidate(ZoneInfo &z, bool wantDemand, double price, double atrVal)
{
   if(!z.active)
      return false;

   if(z.isTPTargetOnly)
      return false;

   if(z.failedRetest)
      return false;

   if(SDIsPendingFlipRetestZone(z))
      return false;

   if(z.broken)
      return false;

   if(!IsBullishZone(z.type) && !IsBearishZone(z.type))
      return false;

   bool sideOk =
      wantDemand
      ? SDZoneCanActAsDemandSide(z, price, atrVal)
      : SDZoneCanActAsSupplySide(z, price, atrVal);

   if(!sideOk)
      return false;

   double distATR = SDDistanceToZoneATR(z, price, atrVal);

   // Do not use ancient far-away zones as active visual zones.
   if(z.ageInBars > 800 && distATR > 0.50)
      return false;

   if(z.ageInBars > 300 && !z.majorQualified && distATR > 2.00)
      return false;

   if(SDZoneTooWideForActiveDisplay(z, atrVal))
      return false;

   if(SDZoneTooTouchedForActiveDisplay(z, price, atrVal))
      return false;

   // Active visible zone must be relevant. Allow a demand/supply sweep through the edge.
   bool priceNearOrSweeping =
      SDZoneContainsPrice(z, price) ||
      (distATR <= SD_ACTIVE_NEAR_ATR) ||
      (wantDemand && SDZoneCanActAsDemandSide(z, price, atrVal) &&
       price >= z.lowerBound - SDSweepTolerance(z, atrVal)) ||
      (!wantDemand && SDZoneCanActAsSupplySide(z, price, atrVal) &&
       price <= z.upperBound + SDSweepTolerance(z, atrVal));

   if(!priceNearOrSweeping)
      return false;

   bool qualityOk = SDZonePassesExecutionQuality(z, atrVal, true);

   if(!qualityOk)
   {
      Print("[SD_QUALITY_BLOCK] id=", z.id,
            " side=", wantDemand ? "Demand" : "Supply",
            " tag=", z.structuralTag,
            " quality=", DoubleToString(z.qualityScore, 2),
            " hits=", z.qualityChecklistHits,
            " major=", z.majorQualified ? "true" : "false",
            " touches=", z.cleanTouchCount,
            " depATR=", DoubleToString(z.departureATR, 2),
            " reason=weak_or_unconfirmed_zone_not_allowed_active");
   }

   return qualityOk;
}

double SDVisibleSideScore(ZoneInfo &z, bool wantDemand, double price, double atrVal)
{
   double score = SDActiveZoneScore(z, price, atrVal);

   double widthATR = SDZoneWidthATR(z, atrVal);
   double distATR  = SDDistanceToZoneATR(z, price, atrVal);

   if(SDZoneContainsPrice(z, price))
      score += 8.00;

   if(distATR <= 0.25)
      score += 4.00;
   else if(distATR <= 0.50)
      score += 3.00;
   else if(distATR <= 1.00)
      score += 2.00;
   else if(distATR <= 2.00)
      score += 0.75;
   else
      score -= distATR * 2.00;

   if(widthATR > 1.25)
      score -= (widthATR - 1.25) * 3.00;

   if(z.cleanTouchCount > 2)
      score -= (z.cleanTouchCount - 2) * 0.85;

   if(z.ageInBars > 800)
      score -= 12.00;
   else if(z.ageInBars > 500)
      score -= 8.00;
   else if(z.ageInBars > 300)
      score -= 4.00;
   else if(z.ageInBars <= 100)
      score += 1.50;

   if(SDIsPendingFlipRetestZone(z))
      score += 2.00;

   return score;
}

void SDMarkActiveVisualSlot(int idx, bool isDemand, bool executable)
{
   if(idx < 0 || idx >= g_zoneReg.count)
      return;

   g_zoneReg.zones[idx].active          = true;
   g_zoneReg.zones[idx].historical      = false;
   g_zoneReg.zones[idx].isPrimary       = true;
   g_zoneReg.zones[idx].isBackup        = false;
   g_zoneReg.zones[idx].isTPTargetOnly  = false;

   // Rehabilitate sound historical zones when explicitly selected as the
   // active demand/supply slot. Photo-filter / dedup can flip valid=false on
   // structurally sound zones; once we commit to trading this zone, mark it
   // valid again unless it's actually broken or failedRetest.
   if(!g_zoneReg.zones[idx].valid &&
      !g_zoneReg.zones[idx].broken &&
      !g_zoneReg.zones[idx].failedRetest &&
      (g_zoneReg.zones[idx].majorQualified ||
       g_zoneReg.zones[idx].qualityScore >= 4.75))
   {
      g_zoneReg.zones[idx].valid = true;
   }

   // Pending broken/flip zones are visual/watch zones only.
   g_zoneReg.zones[idx].isExecutionEligible = executable &&
                                              !g_zoneReg.zones[idx].broken &&
                                              g_zoneReg.zones[idx].valid;

   if(isDemand)
   {
      g_activeDemandZoneId = g_zoneReg.zones[idx].id;
      if(g_activeSupplyZoneId == g_activeDemandZoneId)
         g_activeSupplyZoneId = -1;
   }
   else
   {
      g_activeSupplyZoneId = g_zoneReg.zones[idx].id;
      if(g_activeDemandZoneId == g_activeSupplyZoneId)
         g_activeDemandZoneId = -1;
   }
}

//+------------------------------------------------------------------+
//| Active S/D relevance helpers                                     |
//| The registry can keep many zones, but active visible zones must   |
//| be recent/relevant to current price.                              |
//+------------------------------------------------------------------+
bool SDZoneIsNearOrTouchingPrice(ZoneInfo &z, double price, double atrVal)
{
   if(price <= 0.0)
      return false;

   if(SDZoneContainsPrice(z, price))
      return true;

   if(atrVal <= 0.0)
      return true;

   double dist = DBL_MAX;

   if(z.upperBound < price)
      dist = price - z.upperBound;
   else if(z.lowerBound > price)
      dist = z.lowerBound - price;
   else
      dist = 0.0;

   // Active chart zones should be close enough to matter.
   // Far old zones may remain in registry, but not be visible active zones.
   return (dist <= atrVal * 3.00);
}

bool SDZoneTooOldForActiveDisplay(ZoneInfo &z, double price, double atrVal)
{
   // Recent zones are okay.
   if(z.ageInBars <= 300)
      return false;

   // Old zones can stay in memory/registry, but should not become the visible active zone
   // unless price is actually touching/inside them.
   if(SDZoneContainsPrice(z, price))
      return false;

   // Very old zones are not active display candidates.
   if(z.ageInBars > 800)
      return true;

   // Major zones between 300 and 800 bars can be considered only if close.
   if(z.majorQualified && SDZoneIsNearOrTouchingPrice(z, price, atrVal))
      return false;

   return true;
}

bool SDZoneCanBeActiveDisplayCandidate(ZoneInfo &z, double price, double atrVal)
{
   // Compatibility wrapper: allow either side only if it qualifies for one of
   // the two visible slots.
   return SDZoneIsVisibleSideCandidate(z, true, price, atrVal) ||
          SDZoneIsVisibleSideCandidate(z, false, price, atrVal);
}

bool SDZoneActsAsDemandForSelection(ZoneInfo &z, double price)
{
   if(SDIsPendingFlipRetestZone(z))
      return IsBullishZone(z.type);

   if(z.id > 0 && z.id == g_activeDemandZoneId)
      return true;

   if(z.id > 0 && z.id == g_activeSupplyZoneId)
      return false;

   if(SDZoneContainsPrice(z, price))
   {
      if(IsBullishZone(z.type))
         return true;

      if(IsBearishZone(z.type))
         return false;

      return (price <= z.midPoint);
   }

   return (z.upperBound <= price);
}

bool SDZoneActsAsSupplyForSelection(ZoneInfo &z, double price)
{
   if(SDIsPendingFlipRetestZone(z))
      return IsBearishZone(z.type);

   if(z.id > 0 && z.id == g_activeSupplyZoneId)
      return true;

   if(z.id > 0 && z.id == g_activeDemandZoneId)
      return false;

   if(SDZoneContainsPrice(z, price))
   {
      if(IsBearishZone(z.type))
         return true;

      if(IsBullishZone(z.type))
         return false;

      return (price >= z.midPoint);
   }

   return (z.lowerBound >= price);
}

double SDActiveDisplaySelectionScore(ZoneInfo &z, bool wantDemand, double price, double atrVal)
{
   return SDVisibleSideScore(z, wantDemand, price, atrVal);
}

bool SDZoneIsUsableForActivePair(ZoneInfo &z)
{
   // Legacy compatibility wrapper.
   // Selection now uses SDZoneCanBeActiveDisplayCandidate() because active visible
   // zones must be recent/relevant to current price.
   if(z.broken)
      return false;

   if(!IsBullishZone(z.type) && !IsBearishZone(z.type))
      return false;

   if(!SDPatternMatchesZoneType(z))
      return false;

   bool qualityOk =
      z.valid ||
      z.majorQualified ||
      z.qualityScore >= 4.00 ||
      z.score >= InpSDMinActiveZoneScore ||
      z.departureATR >= InpSDMinDepartureATR;

   return qualityOk;
}

void SDSelectBackups(double price, double atrVal)
{
   int maxBackups = MathMax(0, InpSDMaxBackupZonesPerSide);
   if(maxBackups <= 0 || !InpSDKeepBackupZonesInMemory)
      return;

   // Clear previous backup flags from non-primary zones and reset backup ID arrays
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(g_zoneReg.zones[i].isPrimary)
         continue;
      if(g_zoneReg.zones[i].id == g_activeDemandZoneId ||
         g_zoneReg.zones[i].id == g_activeSupplyZoneId)
         continue;

      g_zoneReg.zones[i].isBackup = false;
      if(!g_zoneReg.zones[i].isTPTargetOnly)
         g_zoneReg.zones[i].isExecutionEligible = false;
   }

   ArrayResize(g_backupDemandZoneIds, 0);
   ArrayResize(g_backupSupplyZoneIds, 0);

   // Select qualified hidden backups for Demand and Supply independently
   for(int side = 0; side < 2; side++)
   {
      bool wantDemand = (side == 0);

      for(int b = 0; b < maxBackups; b++)
      {
         double bestScore = -DBL_MAX;
         int bestIndex = -1;

         for(int i = 0; i < g_zoneReg.count; i++)
         {
            if(g_zoneReg.zones[i].id <= 0)
               continue;

            if(g_zoneReg.zones[i].id == g_activeDemandZoneId ||
               g_zoneReg.zones[i].id == g_activeSupplyZoneId)
               continue;

            if(g_zoneReg.zones[i].isPrimary || g_zoneReg.zones[i].isBackup)
               continue;

            if(g_zoneReg.zones[i].historical ||
               g_zoneReg.zones[i].broken ||
               g_zoneReg.zones[i].failedRetest)
               continue;

            if(g_zoneReg.zones[i].isTPTargetOnly)
               continue;

            if(!g_zoneReg.zones[i].active || !g_zoneReg.zones[i].valid)
               continue;

            bool sideOk = wantDemand
                          ? SDZoneCanActAsDemandSide(g_zoneReg.zones[i], price, atrVal)
                          : SDZoneCanActAsSupplySide(g_zoneReg.zones[i], price, atrVal);

            if(!sideOk)
               continue;

            if(!SDZonePassesExecutionQuality(g_zoneReg.zones[i], atrVal, true))
               continue;

            double rankScore = SDActiveZoneScore(g_zoneReg.zones[i], price, atrVal);

            string tag = g_zoneReg.zones[i].structuralTag;
            if(wantDemand)
            {
               if(tag == "HL" || tag == "LL")
                  rankScore += 2.0;
            }
            else
            {
               if(tag == "LH" || tag == "HH")
                  rankScore += 2.0;
            }

            double distATR = SDDistanceToZoneATR(g_zoneReg.zones[i], price, atrVal);
            rankScore += MathMax(0.0, 1.5 - distATR);

            if(rankScore > bestScore)
            {
               bestScore = rankScore;
               bestIndex = i;
            }
         }

         if(bestIndex < 0)
            break;

         g_zoneReg.zones[bestIndex].isBackup = true;
         g_zoneReg.zones[bestIndex].isPrimary = false;
         g_zoneReg.zones[bestIndex].isExecutionEligible = true;

         SDAddBackupId(wantDemand, g_zoneReg.zones[bestIndex].id);

         double distATR = SDDistanceToZoneATR(g_zoneReg.zones[bestIndex], price, atrVal);

         Print("[SD_BACKUP_SELECTED]",
               " side=", wantDemand ? "DEMAND" : "SUPPLY",
               " id=", g_zoneReg.zones[bestIndex].id,
               " tag=", g_zoneReg.zones[bestIndex].structuralTag,
               " qualityScore=", DoubleToString(g_zoneReg.zones[bestIndex].qualityScore, 2),
               " rankScore=", DoubleToString(bestScore, 2),
               " distATR=", DoubleToString(distATR, 2));

         Print("[SD_BACKUP_EXEC_ELIGIBLE]",
               " id=", g_zoneReg.zones[bestIndex].id,
               " side=", wantDemand ? "DEMAND" : "SUPPLY",
               " tag=", g_zoneReg.zones[bestIndex].structuralTag,
               " qualityScore=", DoubleToString(g_zoneReg.zones[bestIndex].qualityScore, 2));
      }
   }
}

bool SDPairHasEnoughSpace(int demandIndex, int supplyIndex, double atrVal)
{
   if(demandIndex < 0 || supplyIndex < 0)
      return true;
   if(atrVal <= 0.0)
      return true;
   
   double demandTop = g_zoneReg.zones[demandIndex].upperBound;
   double supplyBottom = g_zoneReg.zones[supplyIndex].lowerBound;
   
   double space = supplyBottom - demandTop;
   
   if(space <= 0.0)
      return false;
   
   return (space >= atrVal * InpSDMinSpaceBetweenPairATR);
}

bool SDZoneIsCorrectSideForActivePair(ZoneInfo &z, double price)
{
   if(SDZoneContainsPrice(z, price))
      return true;

   // Use dynamic labeling based on price position instead of static zone type
   if(z.upperBound <= price)
      return true;  // Zone below price → Demand
   if(z.lowerBound >= price)
      return true;  // Zone above price → Supply

   return false;
}

void SDDebugActiveReject(ZoneInfo &z, string reason, double price)
{
   string dynamicLabel = GetDynamicZoneLabel(z, price);
   
   double distToPrice = 0.0;
   if(SDZoneContainsPrice(z, price))
      distToPrice = 0.0;
   else if(z.upperBound < price)
      distToPrice = price - z.upperBound;
   else if(z.lowerBound > price)
      distToPrice = z.lowerBound - price;
   
   Print("[ACTIVE_SD_REJECT] id=", z.id,
         " label=", z.label,
         " dynamicLabel=", dynamicLabel,
         " type=", ZoneTypeToString(z.type),
         " tag=", z.structuralTag,
         " reason=", reason,
         " price=", DoubleToString(price, _Digits),
         " upper=", DoubleToString(z.upperBound, _Digits),
         " lower=", DoubleToString(z.lowerBound, _Digits),
         " score=", DoubleToString(z.score, 2),
         " quality=", DoubleToString(z.qualityScore, 2),
         " touches=", z.cleanTouchCount,
         " age=", z.ageInBars,
         " distToPrice=", DoubleToString(distToPrice, _Digits),
         " broken=", z.broken,
         " historical=", z.historical,
         " valid=", z.valid);
}

void SDSelectActiveSupplyDemandPair(const SymbolProfile &prof, double atrVal)
{
   if(!InpUseSupplyDemandZones)
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double price = (bid > 0.0 && ask > 0.0) ? (bid + ask) * 0.50 : SymbolInfoDouble(_Symbol, SYMBOL_LAST);

   if(price <= 0.0)
      return;

   SDClearActiveFlags();

   double bestDemandScore = -DBL_MAX;
   double bestSupplyScore = -DBL_MAX;

   int bestDemandIndex = -1;
   int bestSupplyIndex = -1;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      bool canBeDemand = SDZoneIsVisibleSideCandidate(g_zoneReg.zones[i], true, price, atrVal);
      bool canBeSupply = SDZoneIsVisibleSideCandidate(g_zoneReg.zones[i], false, price, atrVal);

      if(!canBeDemand && !canBeSupply)
      {
         SDDebugActiveReject(g_zoneReg.zones[i], "not_visible_side_candidate", price);
         continue;
      }

      if(canBeDemand)
      {
         double sc = SDVisibleSideScore(g_zoneReg.zones[i], true, price, atrVal);

         if(sc > bestDemandScore)
         {
            bestDemandScore = sc;
            bestDemandIndex = i;
         }
      }

      if(canBeSupply)
      {
         double sc = SDVisibleSideScore(g_zoneReg.zones[i], false, price, atrVal);

         if(sc > bestSupplyScore)
         {
            bestSupplyScore = sc;
            bestSupplyIndex = i;
         }
      }
   }

   if(bestDemandIndex >= 0 && bestSupplyIndex >= 0 && bestDemandIndex == bestSupplyIndex)
   {
      if(IsBullishZone(g_zoneReg.zones[bestDemandIndex].type))
         bestSupplyIndex = -1;
      else if(IsBearishZone(g_zoneReg.zones[bestSupplyIndex].type))
         bestDemandIndex = -1;
      else
      {
         if(bestDemandScore >= bestSupplyScore)
            bestSupplyIndex = -1;
         else
            bestDemandIndex = -1;
      }
   }

   if(bestDemandIndex >= 0 && bestSupplyIndex >= 0 && atrVal > 0.0)
   {
      double demandTop = g_zoneReg.zones[bestDemandIndex].upperBound;
      double supplyBottom = g_zoneReg.zones[bestSupplyIndex].lowerBound;
      double space = supplyBottom - demandTop;

      bool touchingDemand = SDZoneContainsPrice(g_zoneReg.zones[bestDemandIndex], price);
      bool touchingSupply = SDZoneContainsPrice(g_zoneReg.zones[bestSupplyIndex], price);

      if(space < atrVal * InpSDMinSpaceBetweenPairATR)
      {
         if(touchingDemand && !touchingSupply)
            bestSupplyIndex = -1;
         else if(touchingSupply && !touchingDemand)
            bestDemandIndex = -1;
         else if(bestDemandScore >= bestSupplyScore)
            bestSupplyIndex = -1;
         else
            bestDemandIndex = -1;
      }
   }

   if(bestDemandIndex >= 0)
   {
      // Pass !broken; SDMarkActiveVisualSlot may rehab valid=true, then final
      // isExecutionEligible is (!broken && valid).
      bool executable = !g_zoneReg.zones[bestDemandIndex].broken;

      SDMarkActiveVisualSlot(bestDemandIndex, true, executable);

      // Re-read executable after potential rehabilitation for accurate log.
      executable = g_zoneReg.zones[bestDemandIndex].isExecutionEligible;

      Print("[ACTIVE_DEMAND_SELECTED] id=", g_activeDemandZoneId,
            " pattern=", g_zoneReg.zones[bestDemandIndex].structuralTag,
            " score=", DoubleToString(bestDemandScore, 2),
            " upper=", DoubleToString(g_zoneReg.zones[bestDemandIndex].upperBound, _Digits),
            " lower=", DoubleToString(g_zoneReg.zones[bestDemandIndex].lowerBound, _Digits),
            " touches=", g_zoneReg.zones[bestDemandIndex].cleanTouchCount,
            " age=", g_zoneReg.zones[bestDemandIndex].ageInBars,
            " executable=", executable ? "true" : "false",
            " selection=recent_relevant_active_display");
   }

   if(bestSupplyIndex >= 0)
   {
      bool executable = !g_zoneReg.zones[bestSupplyIndex].broken;

      SDMarkActiveVisualSlot(bestSupplyIndex, false, executable);

      executable = g_zoneReg.zones[bestSupplyIndex].isExecutionEligible;

      Print("[ACTIVE_SUPPLY_SELECTED] id=", g_activeSupplyZoneId,
            " pattern=", g_zoneReg.zones[bestSupplyIndex].structuralTag,
            " score=", DoubleToString(bestSupplyScore, 2),
            " upper=", DoubleToString(g_zoneReg.zones[bestSupplyIndex].upperBound, _Digits),
            " lower=", DoubleToString(g_zoneReg.zones[bestSupplyIndex].lowerBound, _Digits),
            " touches=", g_zoneReg.zones[bestSupplyIndex].cleanTouchCount,
            " age=", g_zoneReg.zones[bestSupplyIndex].ageInBars,
            " executable=", executable ? "true" : "false",
            " selection=recent_relevant_active_display");
   }

   if(bestDemandIndex < 0)
      SDPromoteFallbackVisibleSide(true, price, atrVal);

   if(bestSupplyIndex < 0)
      SDPromoteFallbackVisibleSide(false, price, atrVal);

   // Phase 8: select hidden backup zones after the active visible pair is finalized
   if(InpSDKeepBackupZonesInMemory)
      SDSelectBackups(price, atrVal);

   string demandScoreStr = (bestDemandScore <= -DBL_MAX * 0.5) ? "n/a" : DoubleToString(bestDemandScore, 2);
   string supplyScoreStr = (bestSupplyScore <= -DBL_MAX * 0.5) ? "n/a" : DoubleToString(bestSupplyScore, 2);

   Print("[ACTIVE_SD_PAIR] DemandId=", g_activeDemandZoneId,
         " DemandScore=", demandScoreStr,
         " SupplyId=", g_activeSupplyZoneId,
         " SupplyScore=", supplyScoreStr,
         " policy=max_1_demand_max_1_supply_visible_only");
}

bool SDIsActiveTradingZone(ZoneInfo &z)
{
   if(!InpUseSupplyDemandZones || !InpSDTradeOnlyActivePair)
      return true;

   bool isActiveDemand = (z.id > 0 && z.id == g_activeDemandZoneId);
   bool isActiveSupply = (z.id > 0 && z.id == g_activeSupplyZoneId);

   // Active IDs are final authority.
   // Do not use old static type here because zones can dynamically act as Demand/Supply.
   if(isActiveDemand || isActiveSupply)
   {
      if(z.broken)
         return false;

      if(!z.valid || !z.active)
         return false;

      if(!z.isExecutionEligible)
         return false;

      return true;
   }

   // Backup zones can trade if execution-eligible and quality passes
   if(InpSDKeepBackupZonesInMemory && z.isBackup)
   {
      if(!z.active || !z.valid)
         return false;

      if(!z.isExecutionEligible)
         return false;

      if(!SDZonePassesExecutionQuality(z, 0.0, true))
         return false;

      static datetime s_lastBackupTradeAllowedLog = 0;
      if(TimeCurrent() - s_lastBackupTradeAllowedLog >= 5)
      {
         s_lastBackupTradeAllowedLog = TimeCurrent();
         string side = IsBullishZone(z.type) ? "DEMAND" : "SUPPLY";
         Print("[SD_BACKUP_TRADE_ALLOWED] id=", z.id,
               " side=", side,
               " tag=", z.structuralTag,
               " quality=", DoubleToString(z.qualityScore, 2));
      }

      return true;
   }

   // Non-active zones cannot be used for entries.
   return false;
}

bool SDShouldDrawZone(ZoneInfo &z)
{
   if(!InpUseSupplyDemandZones)
      return false;

   // Pending flip zones remain visible until retest confirms/fails
   if(z.isFlipZone && z.broken && !z.flipRetestConfirmed)
      return true;

   // Keep registry data internal; this function controls chart display only.
   if(InpSDShowOnlyActivePair)
      return ZMZoneIsVisualActiveSlot(z);

   return ZMZoneCanBeVisible(z);
}

bool SDGetActiveDemandZone(ZoneInfo &outZone)
{
   int idx = SDFindZoneIndexById(g_activeDemandZoneId);
   if(idx < 0)
      return false;
   outZone = g_zoneReg.zones[idx];
   return true;
}

bool SDGetActiveSupplyZone(ZoneInfo &outZone)
{
   int idx = SDFindZoneIndexById(g_activeSupplyZoneId);
   if(idx < 0)
      return false;
   outZone = g_zoneReg.zones[idx];
   return true;
}

// STEP 12-14: Improved TP target zone selection with quality filtering
bool SDGetNearestTargetZone(bool isBuy, double price, double atrVal, ZoneInfo &outZone)
{
   // Dynamic role: for buys we need Resistance (zone above price);
   //                for sells we need Support (zone below price).
   // Original zone type is irrelevant for selection.

   double bestDist = DBL_MAX;
   int bestIdx = -1;
   double bestQuality = -DBL_MAX;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].valid || g_zoneReg.zones[i].broken)
         continue;

      if(g_zoneReg.zones[i].isTPTargetOnly)
         continue;

      // STEP 13: Position check only — ignore original zone type
      double dist = 0.0;
      if(isBuy)
      {
         if(g_zoneReg.zones[i].lowerBound <= price)
            continue;
         dist = g_zoneReg.zones[i].lowerBound - price;
      }
      else
      {
         if(g_zoneReg.zones[i].upperBound >= price)
            continue;
         dist = price - g_zoneReg.zones[i].upperBound;
      }

      double distATR = dist / atrVal;

      if(distATR > 8.0)
         continue;

      double quality = g_zoneReg.zones[i].qualityScore;

      double score = quality - (distATR * 0.5);

      if(score > bestQuality || (score == bestQuality && dist < bestDist))
      {
         bestQuality = score;
         bestDist = dist;
         bestIdx = i;
      }
   }

   if(bestIdx < 0)
      return false;

   outZone = g_zoneReg.zones[bestIdx];

   string dynamicRole = isBuy ? SDDynamicRoleName(outZone, price) : SDDynamicRoleName(outZone, price);

   Print("[SD_TP_TARGET_SELECT] side=", isBuy ? "BUY" : "SELL",
         " zoneId=", outZone.id,
         " dynamicRole=", dynamicRole,
         " origType=", ZoneTypeToString(outZone.type),
         " quality=", DoubleToString(outZone.qualityScore, 2),
         " distATR=", DoubleToString(bestDist / atrVal, 2),
         " score=", DoubleToString(bestQuality, 2));

   return true;
}

bool SDHasActivePair()
{
   return (g_activeDemandZoneId >= 0 && g_activeSupplyZoneId >= 0);
}

bool SDHasActiveDemand()
{
   return (g_activeDemandZoneId >= 0);
}

bool SDHasActiveSupply()
{
   return (g_activeSupplyZoneId >= 0);
}

bool SDZoneCorrectSide(ZoneInfo &z, double price)
{
   if(SDZoneContainsPrice(z, price))
      return true;

   if(IsBullishZone(z.type))
      return (z.upperBound <= price);

   if(IsBearishZone(z.type))
      return (z.lowerBound >= price);

   return false;
}

bool SDZoneIsProfessionalCandidate(ZoneInfo &z, double price, double atrVal)
{
   if(z.broken)
      return false;

   if(z.historical && !z.majorQualified && z.qualityScore < 6.0)
      return false;

   if(!z.active && !z.majorQualified)
      return false;

   if(!IsBullishZone(z.type) && !IsBearishZone(z.type))
      return false;

   if(InpSDRequireSideCorrectPair && !SDZoneCorrectSide(z, price))
      return false;

   bool qualityOk =
      z.valid ||
      z.majorQualified ||
      z.qualityScore >= 4.50 ||
      z.score >= InpSDMinActiveZoneScore ||
      z.departureATR >= InpSDMinDepartureATR;

   if(!qualityOk)
      return false;

   if(z.cleanTouchCount > InpSDMaxFreshTouches && !z.majorQualified)
      return false;

   if(z.departureATR > 0.0 && z.departureATR < InpSDMinDepartureATR && !z.majorQualified)
      return false;

   if(z.ageInBars > InpD1ZoneLifetimeBars && !z.majorQualified)
      return false;

   return true;
}

double SDPatternStructureScore(ZoneInfo &z)
{
   string p = z.structuralTag;

   int trend = GetMarketTrend(); // 1 bullish, -1 bearish, 0 range/neutral

   double score = 0.0;

   if(trend == -1)
   {
      // Bearish market: prefer Supply.
      if(IsBearishZone(z.type))
      {
         if(p == "DBD") score += 2.00;          // continuation supply
         else if(p == "RBD") score += 1.40;     // reversal supply
         else score += 0.75;
      }
      else
      {
         // Demand in bearish trend is counter-trend.
         if(p == "DBR" && (z.structureImpactScore >= 0.75 || z.majorQualified))
            score += 0.75;
         else
            score -= 2.00;
      }
   }
   else if(trend == 1)
   {
      // Bullish market: prefer Demand.
      if(IsBullishZone(z.type))
      {
         if(p == "RBR") score += 2.00;          // continuation demand
         else if(p == "DBR") score += 1.40;     // reversal demand
         else score += 0.75;
      }
      else
      {
         // Supply in bullish trend is counter-trend.
         if(p == "RBD" && (z.structureImpactScore >= 0.75 || z.majorQualified))
            score += 0.75;
         else
            score -= 2.00;
      }
   }
   else
   {
      // Range/neutral: both sides allowed.
      if(p == "DBD" || p == "RBR")
         score += 1.20;
      else if(p == "RBD" || p == "DBR")
         score += 1.00;
      else
         score += 0.40;
   }

   return score;
}

bool SDZonesOverlap(double high1, double low1, double high2, double low2)
{
   return (low1 <= high2 && high1 >= low2);
}

bool SDIsDuplicateZone(ZoneInfo &oldZ, ENUM_ZONE_TYPE newType, double newHigh, double newLow, double atrVal)
{
   if(!IsSameZoneDirection(oldZ.type, newType))
      return false;

   double oldMid = (oldZ.upperBound + oldZ.lowerBound) * 0.50;
   double newMid = (newHigh + newLow) * 0.50;

   double maxDist = MathMax(atrVal * InpSDDuplicateMergeATR, _Point * 50);

   if(MathAbs(oldMid - newMid) <= maxDist)
      return true;

   if(SDZonesOverlap(oldZ.upperBound, oldZ.lowerBound, newHigh, newLow))
      return true;

   return false;
}

int SDFallbackBestSide(bool wantDemand, double price, double atrVal)
{
   double bestScore = -DBL_MAX;
   int bestIdx = -1;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!SDZoneIsUsableForActivePair(g_zoneReg.zones[i]))
         continue;

      if(wantDemand && !IsBullishZone(g_zoneReg.zones[i].type))
         continue;

      if(!wantDemand && !IsBearishZone(g_zoneReg.zones[i].type))
         continue;

      double sc = SDActiveZoneScore(g_zoneReg.zones[i], price, atrVal);

      if(sc > bestScore)
      {
         bestScore = sc;
         bestIdx = i;
      }
   }

   if(bestIdx >= 0)
   {
      Print("[SD_FALLBACK_BEST_SIDE] side=", (wantDemand ? "DEMAND" : "SUPPLY"),
            " idx=", bestIdx,
            " id=", g_zoneReg.zones[bestIdx].id,
            " score=", DoubleToString(bestScore, 2));
   }

   return bestIdx;
}

void StampPDFSupplyDemandZone(int idx,
                              bool isDemand,
                              string methodTag,
                              double departureATR,
                              bool bos,
                              int sourceBar,
                              int momentumCount,
                              string patternCode)
{
   if(idx < 0 || idx >= g_zoneReg.count)
      return;

   g_zoneReg.zones[idx].structuralAnchor = true;
   
   // STEP 4: Correct pattern before assigning to structuralTag
   patternCode = SDCorrectPatternForZoneType(g_zoneReg.zones[idx], patternCode);
   
   // structuralTag stores the pattern type: RBD, DBD, DBR, RBR
   if(InpSDClassifyPatternType)
      g_zoneReg.zones[idx].structuralTag = patternCode;
   else
      g_zoneReg.zones[idx].structuralTag = methodTag;
   
   // sdCreationMethod stores HOW the zone was created.
   if(StringFind(methodTag, "MOMENTUM") >= 0)
      g_zoneReg.zones[idx].sdCreationMethod = "MOMENTUM";
   else if(StringFind(methodTag, "CONSOLIDATION") >= 0)
      g_zoneReg.zones[idx].sdCreationMethod = "CONSOLIDATION";
   else if(StringFind(methodTag, "WICK") >= 0)
      g_zoneReg.zones[idx].sdCreationMethod = "WICK";
   else
      g_zoneReg.zones[idx].sdCreationMethod = "UNKNOWN";
   
   g_zoneReg.zones[idx].structuralSide   = isDemand ? "BULL" : "BEAR";
   g_zoneReg.zones[idx].sourceBarIndex   = sourceBar;
   g_zoneReg.zones[idx].sourceSwingTime  = iTime(_Symbol, InpEntryTF, sourceBar);
   g_zoneReg.zones[idx].sequenceIndex    = momentumCount;
   g_zoneReg.zones[idx].sourceTF         = g_zoneTF;

   if(InpSDShowPatternInLabel && InpSDClassifyPatternType)
      g_zoneReg.zones[idx].label = (isDemand ? "Demand " : "Supply ") + patternCode;
   else
      g_zoneReg.zones[idx].label = isDemand ? "Demand" : "Supply";
   
   g_zoneReg.zones[idx].family = isDemand ? ZFAM_DEMAND : ZFAM_SUPPLY;

   g_zoneReg.zones[idx].departureATR         = departureATR;
   g_zoneReg.zones[idx].structureImpactScore = bos ? 1.0 : 0.35;
   g_zoneReg.zones[idx].ledToBOS             = bos;

   // Detect "caused other zones to fail": did the impulse leaving this zone
   // break through an older opposing-side zone?
   //   - Demand impulse (bullish): broke an older Supply zone upward
   //   - Supply impulse (bearish): broke an older Demand zone downward
   {
      bool causedFailure = false;
      double zUp  = g_zoneReg.zones[idx].upperBound;
      double zLo  = g_zoneReg.zones[idx].lowerBound;
      datetime tNew = g_zoneReg.zones[idx].sourceSwingTime;

      for(int kk = 0; kk < g_zoneReg.count; kk++)
      {
         if(kk == idx) continue;
         ZoneInfo zo = g_zoneReg.zones[kk];

         // older only
         if(zo.sourceSwingTime <= 0 || tNew <= 0) continue;
         if(zo.sourceSwingTime >= tNew) continue;

         if(isDemand)
         {
            // we are demand; opposing = supply that sat above us and got broken upward
            if(!IsBearishZone(zo.type)) continue;
            if(zo.lowerBound <= zUp) continue;     // must be above us
            if(zo.broken)
            {
               causedFailure = true;
               break;
            }
         }
         else
         {
            // we are supply; opposing = demand that sat below us and got broken downward
            if(!IsBullishZone(zo.type)) continue;
            if(zo.upperBound >= zLo) continue;     // must be below us
            if(zo.broken)
            {
               causedFailure = true;
               break;
            }
         }
      }

      g_zoneReg.zones[idx].causedZoneFailure = causedFailure;
   }

   g_zoneReg.zones[idx].freshnessScore       = MathMax(0.0, 1.0 - g_zoneReg.zones[idx].ageInBars / 260.0);
   g_zoneReg.zones[idx].cleanShapeScore      = 0.80;
   g_zoneReg.zones[idx].rejectionQualityScore = MathMin(departureATR / 2.0, 1.0);

   int hits = 0;
   if(departureATR >= InpSDMinDepartureATR) hits++;
   if(departureATR >= InpSDMajorDepartureATR) hits++;
   if(bos) hits++;
   if(momentumCount >= InpSDMinMomentumCandles) hits++;
   if(g_zoneReg.zones[idx].ageInBars <= InpD1ZoneLifetimeBars) hits++;

   g_zoneReg.zones[idx].qualityChecklistHits = hits;
   g_zoneReg.zones[idx].majorQualified       = (hits >= 3);

   double q = 2.0;
   q += MathMin(departureATR, 2.5);
   q += bos ? 1.50 : 0.25;
   q += MathMin(momentumCount * 0.30, 1.50);
   q += g_zoneReg.zones[idx].freshnessScore;
   q += g_zoneReg.zones[idx].majorQualified ? 1.0 : 0.0;

   g_zoneReg.zones[idx].qualityScore = q;
   g_zoneReg.zones[idx].score        = MathMax(g_zoneReg.zones[idx].score, q / 7.0);
   g_zoneReg.zones[idx].strength     = MathMax(g_zoneReg.zones[idx].strength, g_zoneReg.zones[idx].score);

   if(isDemand)
   {
      g_zoneReg.zones[idx].strategyRole = ZROLE_TREND_CONTINUATION;
      g_zoneReg.zones[idx].execBandLow  = g_zoneReg.zones[idx].lowerBound;
      g_zoneReg.zones[idx].execBandHigh = g_zoneReg.zones[idx].lowerBound + ZoneWidth(g_zoneReg.zones[idx]) * 0.50;
      g_zoneReg.zones[idx].hasExecBand  = true;
   }
   else
   {
      g_zoneReg.zones[idx].strategyRole = ZROLE_TREND_CONTINUATION;
      g_zoneReg.zones[idx].execBandLow  = g_zoneReg.zones[idx].upperBound - ZoneWidth(g_zoneReg.zones[idx]) * 0.50;
      g_zoneReg.zones[idx].execBandHigh = g_zoneReg.zones[idx].upperBound;
      g_zoneReg.zones[idx].hasExecBand  = true;
   }
   
   if(InpSDClassifyPatternType)
   {
      bool isContinuation = SDPatternIsContinuation(patternCode);
      bool isReversal     = SDPatternIsReversal(patternCode);

      g_zoneReg.zones[idx].continuationEligible = isContinuation;
      g_zoneReg.zones[idx].reversalCandidate    = isReversal;

      if(isContinuation)
      {
         g_zoneReg.zones[idx].strategyRole       = ZROLE_TREND_CONTINUATION;
         g_zoneReg.zones[idx].continuationScore  = MathMax(g_zoneReg.zones[idx].continuationScore, 1.00);
         g_zoneReg.zones[idx].reversalScore      = MathMax(g_zoneReg.zones[idx].reversalScore, 0.25);
      }
      else if(isReversal)
      {
         g_zoneReg.zones[idx].strategyRole       = ZROLE_COUNTERTREND_EXHAUSTION;
         g_zoneReg.zones[idx].reversalScore      = MathMax(g_zoneReg.zones[idx].reversalScore, 1.00);
         g_zoneReg.zones[idx].continuationScore  = MathMax(g_zoneReg.zones[idx].continuationScore, 0.25);
      }

      Print("[SD_PATTERN_CLASSIFIED] id=", g_zoneReg.zones[idx].id,
            " zone=", isDemand ? "Demand" : "Supply",
            " pattern=", patternCode,
            " method=", g_zoneReg.zones[idx].sdCreationMethod,
            " rawMethod=", methodTag,
            " description=", SDPatternDescription(patternCode),
            " role=", isContinuation ? "CONTINUATION" : "REVERSAL");
   }
}

bool SDIsValidZoneWidth(double zoneHigh, double zoneLow, const SymbolProfile &prof, double atrVal)
{
   double width = zoneHigh - zoneLow;

   if(width <= 0.0)
      return false;

   if(width < InpSDMinZoneWidthPoints * prof.point)
      return false;

   if(atrVal > 0.0 && width > atrVal * InpSDConsolidationMaxATR)
      return false;

   return true;
}

void DetectMomentumCandleSupplyZones(const double &open[],
                                     const double &high[],
                                     const double &low[],
                                     const double &close[],
                                     int bars,
                                     const SymbolProfile &prof,
                                     double atrVal)
{
   // Deprecated. The PDF method requires at least 3 momentum candles.
   // Use DetectSupplyZones() momentum block instead.
   return;

   if(!InpSDUseSingleMomentumCandleMethod)
      return;

   if(bars < 20 || atrVal <= 0.0)
      return;

   double avgBody = SDAvgBody(open, close, bars);
   if(avgBody <= 0.0)
      avgBody = atrVal * 0.30;

   for(int m = 1; m < bars - 3; m++)
   {
      if(!SDIsBearMomentum(open, high, low, close, m, avgBody))
         continue;

      int base = m + 1;
      if(base >= bars)
         continue;

      double zoneHigh = high[base];
      double zoneLow  = low[base];

      if(!SDIsValidZoneWidth(zoneHigh, zoneLow, prof, atrVal))
         continue;

      double departureATR = (zoneLow - close[m]) / atrVal;
      if(departureATR < InpSDMinDepartureATR)
         continue;

      double olderLow = SDLowest(low, base + 1, MathMin(base + InpSDBOSLookback, bars - 1));
      bool bos = (close[m] < olderLow - atrVal * 0.10);

      ENUM_ZONE_TYPE zt =
         (departureATR >= InpSDMajorDepartureATR || bos)
         ? ZONE_SUPPLY_MAJOR
         : ZONE_SUPPLY_MINOR;

      int incomingDir = SDIncomingLegDirection(open, high, low, close, base, bars, avgBody);
      string patternCode = SDPatternCode(false, incomingDir);

      int idx = AddOrUpdateZone(zt, zoneHigh, zoneLow, 1, base, prof, atrVal);

      StampPDFSupplyDemandZone(idx,
                               false,
                               "PDF_MOMENTUM_SUPPLY",
                               departureATR,
                               bos,
                               base,
                               1,
                               patternCode);

      Print("[SD_METHOD_CREATED] method=PDF_MOMENTUM_SUPPLY",
            " id=", idx,
            " pattern=", patternCode,
            " momentumShift=", m,
            " baseShift=", base,
            " upper=", DoubleToString(zoneHigh, _Digits),
            " lower=", DoubleToString(zoneLow, _Digits),
            " departureATR=", DoubleToString(departureATR, 2));
   }
}

void DetectMomentumCandleDemandZones(const double &open[],
                                     const double &high[],
                                     const double &low[],
                                     const double &close[],
                                     int bars,
                                     const SymbolProfile &prof,
                                     double atrVal)
{
   // Deprecated. The PDF method requires at least 3 momentum candles.
   // Use DetectDemandZones() momentum block instead.
   return;

   if(!InpSDUseSingleMomentumCandleMethod)
      return;

   if(bars < 20 || atrVal <= 0.0)
      return;

   double avgBody = SDAvgBody(open, close, bars);
   if(avgBody <= 0.0)
      avgBody = atrVal * 0.30;

   for(int m = 1; m < bars - 3; m++)
   {
      if(!SDIsBullMomentum(open, high, low, close, m, avgBody))
         continue;

      int base = m + 1;
      if(base >= bars)
         continue;

      double zoneHigh = high[base];
      double zoneLow  = low[base];

      if(!SDIsValidZoneWidth(zoneHigh, zoneLow, prof, atrVal))
         continue;

      double departureATR = (close[m] - zoneHigh) / atrVal;
      if(departureATR < InpSDMinDepartureATR)
         continue;

      double olderHigh = SDHighest(high, base + 1, MathMin(base + InpSDBOSLookback, bars - 1));
      bool bos = (close[m] > olderHigh + atrVal * 0.10);

      ENUM_ZONE_TYPE zt =
         (departureATR >= InpSDMajorDepartureATR || bos)
         ? ZONE_DEMAND_MAJOR
         : ZONE_DEMAND_MINOR;

      int incomingDir = SDIncomingLegDirection(open, high, low, close, base, bars, avgBody);
      string patternCode = SDPatternCode(true, incomingDir);

      int idx = AddOrUpdateZone(zt, zoneHigh, zoneLow, 1, base, prof, atrVal);

      StampPDFSupplyDemandZone(idx,
                               true,
                               "PDF_MOMENTUM_DEMAND",
                               departureATR,
                               bos,
                               base,
                               1,
                               patternCode);

      Print("[SD_METHOD_CREATED] method=PDF_MOMENTUM_DEMAND",
            " id=", idx,
            " pattern=", patternCode,
            " momentumShift=", m,
            " baseShift=", base,
            " upper=", DoubleToString(zoneHigh, _Digits),
            " lower=", DoubleToString(zoneLow, _Digits),
            " departureATR=", DoubleToString(departureATR, 2));
   }
}

void DetectSupplyZones(const double &open[], const double &high[],
                       const double &low[], const double &close[],
                       int bars, const SymbolProfile &prof, double atrVal)
{
   if(bars < 40 || atrVal <= 0.0)
   {
      Print("[SD_DETECT_SUPPLY_EARLY_EXIT] bars=", bars, " atr=", DoubleToString(atrVal, _Digits));
      return;
   }

   double avgBodyRaw = SDAvgBody(open, close, bars);
   double avgBody = avgBodyRaw;
   if(avgBody <= 0.0)
      avgBody = atrVal * 0.30;
   // Cap avgBody so outlier impulse candles cannot inflate the momentum threshold
   // above what typical candles in a ranging window can meet.
   if(atrVal > 0.0 && avgBody > atrVal * 0.60)
      avgBody = atrVal * 0.60;

   int minMom = MathMax(2, InpSDMinMomentumCandles);
   int maxMom = MathMax(minMom, InpSDMaxMomentumCandles);

   int dbgExtScanned=0, dbgExtImpulse=0, dbgExtDepart=0, dbgExtBOS=0, dbgExtWidth=0, dbgExtCreated=0;
   int dbgWickCand=0, dbgWickClusters=0, dbgWickHitsOk=0, dbgWickWidthOk=0, dbgWickDepartOk=0, dbgWickCreated=0;
   int dbgMomScan=0, dbgMomRunOk=0, dbgMomWidthOk=0, dbgMomDepartOk=0, dbgMomCreated=0;

   // Last closed bar's close, used to skip momentum zones that currently wrap price.
   double refPrice = (bars > 1 ? close[1] : close[0]);

   Print("[SD_AVGBODY_CAP] avgBodyRaw=", DoubleToString(avgBodyRaw, _Digits),
         " atr=", DoubleToString(atrVal, _Digits),
         " avgBodyEffective=", DoubleToString(avgBody, _Digits),
         " capped=", (avgBodyRaw > atrVal * 0.60 ? "true" : "false"));

   // ------------------------------------------------------------
   // EXTREME SINGLE IMPULSE METHOD — Supply
   // One huge bearish momentum candle marks the previous candle's
   // full wick high to wick low as the Supply zone.
   // ------------------------------------------------------------
   if(InpSDUseSingleMomentumCandleMethod)
   {
      for(int m = 1; m < bars - InpSDPreBaseLegBars - 3; m++)
      {
         dbgExtScanned++;
         if(!SDIsExtremeBearImpulse(open, high, low, close, m, avgBody, atrVal))
            continue;
         dbgExtImpulse++;

         int base = m + 1;
         if(base >= bars)
            continue;

         double zoneHigh = high[base];
         double zoneLow  = low[base];

         if(zoneHigh <= zoneLow)
            continue;

         if((zoneHigh - zoneLow) < InpSDMinZoneWidthPoints * prof.point)
            continue;

         if((zoneHigh - zoneLow) > atrVal * SD_ACTIVE_MAX_WIDTH_ATR)
         {
            Print("[EXTREME_IMPULSE_ZONE_REJECT] side=Supply reason=previous_candle_zone_too_wide",
                  " upper=", DoubleToString(zoneHigh, _Digits),
                  " lower=", DoubleToString(zoneLow, _Digits),
                  " widthATR=", DoubleToString((zoneHigh - zoneLow) / atrVal, 2));
            continue;
         }
         dbgExtWidth++;

         double departureATR = (zoneLow - close[m]) / atrVal;
         if(departureATR < InpSDMinDepartureATR)
            continue;
         dbgExtDepart++;

         double olderLow = SDLowest(low, base + 1, MathMin(base + InpSDBOSLookback, bars - 1));
         bool bos = (close[m] < olderLow - atrVal * 0.10);

         if(InpSDExtremeImpulseRequireBOS && !bos)
            continue;
         dbgExtBOS++;

         ENUM_ZONE_TYPE zt =
            (departureATR >= InpSDMajorDepartureATR || bos)
            ? ZONE_SUPPLY_MAJOR
            : ZONE_SUPPLY_MINOR;

         int incomingDir = SDIncomingLegDirection(open, high, low, close, base, bars, avgBody);
         string patternCode = SDPatternCode(false, incomingDir);

         int idx = AddOrUpdateZone(zt, zoneHigh, zoneLow, 1, base, prof, atrVal,
                                   false, "", -1, "PDF_EXTREME_IMPULSE_SUPPLY", base);
         dbgExtCreated++;

         StampPDFSupplyDemandZone(idx,
                                  false,
                                  "PDF_EXTREME_IMPULSE_SUPPLY",
                                  departureATR,
                                  bos,
                                  base,
                                  1,
                                  patternCode);

         Print("[SD_METHOD_CREATED] method=PDF_EXTREME_IMPULSE_SUPPLY",
               " id=", idx,
               " pattern=", patternCode,
               " impulseShift=", m,
               " baseShift=", base,
               " upper=", DoubleToString(zoneHigh, _Digits),
               " lower=", DoubleToString(zoneLow, _Digits),
               " departureATR=", DoubleToString(departureATR, 2),
               " bos=", bos ? "true" : "false");
      }
   }

   // ------------------------------------------------------------
   // PDF METHOD 1: Momentum candles
   // Look for at least 3 strong bearish momentum candles in a row.
   // Mark the high/low of the candle directly before the momentum.
   // ------------------------------------------------------------
   if(SDUseMomentumMethod())
   {
   for(int base = maxMom + 2; base < bars - InpSDPreBaseLegBars - 2; base++)
   {
      dbgMomScan++;
      bool run = true;
      int momCount = 0;

      for(int m = 1; m <= maxMom; m++)
      {
         int mi = base - m;
         if(mi < 1) break;

         if(SDIsBearMomentum(open, high, low, close, mi, avgBody))
            momCount++;
         else
         {
            if(m <= minMom) run = false;
            break;
         }
      }

      if(!run || momCount < minMom)
         continue;
      dbgMomRunOk++;

      double zoneHigh = high[base];
      double zoneLow  = low[base];

      if(zoneHigh <= zoneLow)
         continue;

      if((zoneHigh - zoneLow) < InpSDMinZoneWidthPoints * prof.point)
         continue;
      dbgMomWidthOk++;

      // C) Skip zones that currently wrap price — they cannot be retested from above.
      // For a Supply zone we need current price BELOW zoneLow so a rally up to the zone is possible.
      if(refPrice >= zoneLow)
         continue;

      int finalMomBar = base - momCount;
      if(finalMomBar < 1)
         continue;

      double departureATR = (zoneLow - close[finalMomBar]) / atrVal;
      if(departureATR < InpSDMinDepartureATR)
         continue;
      dbgMomDepartOk++;

      double olderLow = SDLowest(low, base + 1, MathMin(base + InpSDBOSLookback, bars - 1));
      bool bos = (close[finalMomBar] < olderLow - atrVal * 0.10);

      ENUM_ZONE_TYPE zt = (departureATR >= InpSDMajorDepartureATR || momCount >= 5 || bos)
                          ? ZONE_SUPPLY_MAJOR
                          : ZONE_SUPPLY_MINOR;

      int incomingDir = SDIncomingLegDirection(open, high, low, close, base, bars, avgBody);
      string patternCode = SDPatternCode(false, incomingDir);
      int idx = AddOrUpdateZone(zt, zoneHigh, zoneLow, momCount, base, prof, atrVal, false, "", -1, "PDF_MOMENTUM_SUPPLY", base);
      dbgMomCreated++;
      StampPDFSupplyDemandZone(idx, false, "PDF_MOMENTUM_SUPPLY", departureATR, bos, base, momCount, patternCode);

      Print("[SD_METHOD_CREATED] method=PDF_MOMENTUM_SUPPLY",
            " id=", idx,
            " pattern=", patternCode,
            " baseShift=", base,
            " momCount=", momCount,
            " upper=", DoubleToString(zoneHigh, _Digits),
            " lower=", DoubleToString(zoneLow, _Digits),
            " departureATR=", DoubleToString(departureATR, 2),
            " bos=", bos ? "true" : "false");
   }
   }

   // ------------------------------------------------------------
   // PDF METHOD 2: Consolidation
   // Find sideways base before bearish momentum and box the entire base.
   // ------------------------------------------------------------
   if(SDUseConsolidationMethod())
   {
   int baseBars = MathMax(3, InpSDConsolidationBars);

   for(int base = maxMom + 2; base < bars - baseBars - InpSDPreBaseLegBars - 2; base++)
   {
      double zoneHigh = SDHighest(high, base, base + baseBars - 1);
      double zoneLow  = SDLowest(low, base, base + baseBars - 1);
      double width = zoneHigh - zoneLow;

      if(width <= 0.0)
         continue;

      if(width > atrVal * InpSDConsolidationMaxATR)
         continue;

      double avgBaseBody = 0.0;
      for(int b = base; b <= base + baseBars - 1; b++)
      {
         avgBaseBody += MathAbs(close[b] - open[b]);
      }
      avgBaseBody /= MathMax(baseBars, 1);

      if(avgBaseBody > atrVal * 0.35)
         continue;

      int momCount = 0;
      for(int m = 1; m <= maxMom; m++)
      {
         int mi = base - m;
         if(mi < 1) break;

         if(SDIsBearMomentum(open, high, low, close, mi, avgBody))
            momCount++;
         else
            break;
      }

      if(momCount < minMom)
         continue;

      int finalMomBar = base - momCount;
      if(finalMomBar < 1)
         continue;

      double departureATR = (zoneLow - close[finalMomBar]) / atrVal;
      if(departureATR < InpSDMinDepartureATR)
         continue;

      double olderLow = SDLowest(low, base + baseBars, MathMin(base + baseBars + InpSDBOSLookback, bars - 1));
      bool bos = (close[finalMomBar] < olderLow - atrVal * 0.10);

      ENUM_ZONE_TYPE zt = (departureATR >= InpSDMajorDepartureATR || momCount >= 5 || bos)
                          ? ZONE_SUPPLY_MAJOR
                          : ZONE_SUPPLY_MINOR;

      int incomingDir = SDIncomingLegDirection(open, high, low, close, base + baseBars - 1, bars, avgBody);
      string patternCode = SDPatternCode(false, incomingDir);
      int idx = AddOrUpdateZone(zt, zoneHigh, zoneLow, momCount, base, prof, atrVal, false, "", -1, "PDF_CONSOLIDATION_SUPPLY", base);
      StampPDFSupplyDemandZone(idx, false, "PDF_CONSOLIDATION_SUPPLY", departureATR, bos, base, momCount, patternCode);
   }
   }

   // ------------------------------------------------------------
   // PDF METHOD 3: Wick rejection (confluent cluster)
   // Find multiple upper wicks that reject at the same level and form
   // a horizontal Supply band from the body-top of the deepest wick to
   // the highest wick extreme in the cluster.
   // ------------------------------------------------------------
   if(SDUseWickMethod())
   {
   int scanMax = MathMin(bars - 2, MathMax(8, InpSDWickScanBars));
   int    candIdx[256];
   double candExtreme[256];
   double candBodyEdge[256];
   int    candCount = 0;

   for(int i = 2; i < scanMax && candCount < 256; i++)
   {
      double range = high[i] - low[i];
      if(range <= 0.0) continue;

      double bodyHigh = MathMax(open[i], close[i]);
      double upperWick = high[i] - bodyHigh;
      if(upperWick / range < InpSDMinWickPct) continue;

      double body = MathAbs(close[i] - open[i]);
      if(body <= 0.0) continue;
      if(upperWick < body * InpSDPinbarMinWickToBody) continue;

      candIdx[candCount]      = i;
      candExtreme[candCount]  = high[i];
      candBodyEdge[candCount] = bodyHigh;
      candCount++;
   }
   dbgWickCand = candCount;

   bool   used[256];
   ArrayInitialize(used, false);
   double clusterTol = atrVal * MathMax(0.05, InpSDWickClusterATR);
   int    minCluster = MathMax(2, InpSDMinWickCluster);

   for(int a = 0; a < candCount; a++)
   {
      if(used[a]) continue;
      double anchorH = candExtreme[a];
      double zHigh   = anchorH;
      double zLow    = candBodyEdge[a];
      int    hits    = 1;
      int    newestI = candIdx[a];
      int    oldestI = candIdx[a];
      used[a] = true;

      for(int b = a + 1; b < candCount; b++)
      {
         if(used[b]) continue;
         if(MathAbs(candExtreme[b] - anchorH) > clusterTol) continue;
         used[b] = true;
         hits++;
         if(candExtreme[b] > zHigh)  zHigh = candExtreme[b];
         if(candBodyEdge[b] < zLow)  zLow  = candBodyEdge[b];
         if(candIdx[b] < newestI)    newestI = candIdx[b];
         if(candIdx[b] > oldestI)    oldestI = candIdx[b];
      }

      dbgWickClusters++;
      if(hits < minCluster) continue;
      dbgWickHitsOk++;
      if((zHigh - zLow) < InpSDMinZoneWidthPoints * prof.point) continue;
      if((zHigh - zLow) > atrVal * SD_ACTIVE_MAX_WIDTH_ATR) continue;
      dbgWickWidthOk++;

      // Validate price subsequently moved DOWN since the newest wick in the cluster.
      double minLowAfter = low[MathMax(1, newestI - 1)];
      for(int k = 1; k < newestI; k++)
         if(low[k] < minLowAfter) minLowAfter = low[k];

      double departureATR = (zLow - minLowAfter) / atrVal;
      if(departureATR < InpSDMinDepartureATR * 0.50) continue;
      dbgWickDepartOk++;

      ENUM_ZONE_TYPE zt = (departureATR >= InpSDMajorDepartureATR || hits >= 3)
                          ? ZONE_SUPPLY_MAJOR
                          : ZONE_SUPPLY_MINOR;

      int incomingDir = SDIncomingLegDirection(open, high, low, close, oldestI, bars, avgBody);
      string patternCode = SDPatternCode(false, incomingDir);
      int idx = AddOrUpdateZone(zt, zHigh, zLow, hits, newestI, prof, atrVal, false, "", -1, "PDF_WICK_SUPPLY", newestI);
      dbgWickCreated++;
      StampPDFSupplyDemandZone(idx, false, "PDF_WICK_SUPPLY", departureATR, false, newestI, hits, patternCode);

      Print("[SD_METHOD_CREATED] method=PDF_WICK_SUPPLY",
            " id=", idx, " hits=", hits,
            " zHigh=", DoubleToString(zHigh, _Digits),
            " zLow=", DoubleToString(zLow, _Digits),
            " newest=", newestI, " oldest=", oldestI,
            " departureATR=", DoubleToString(departureATR, 2));
   }
   }

   Print("[SD_DETECT_SUPPLY_DIAG] bars=", bars,
         " atr=", DoubleToString(atrVal, _Digits),
         " avgBody=", DoubleToString(avgBody, _Digits),
         " extScan=", dbgExtScanned,
         " extImp=", dbgExtImpulse,
         " extWidthOk=", dbgExtWidth,
         " extDepart=", dbgExtDepart,
         " extBOS=", dbgExtBOS,
         " extCreated=", dbgExtCreated,
         " wickCand=", dbgWickCand,
         " wickClusters=", dbgWickClusters,
         " wickHitsOk=", dbgWickHitsOk,
         " wickWidthOk=", dbgWickWidthOk,
         " wickDepartOk=", dbgWickDepartOk,
         " wickCreated=", dbgWickCreated,
         " momScan=", dbgMomScan,
         " momRunOk=", dbgMomRunOk,
         " momWidthOk=", dbgMomWidthOk,
         " momDepartOk=", dbgMomDepartOk,
         " momCreated=", dbgMomCreated);
}

void DetectDemandZones(const double &open[], const double &high[],
                       const double &low[], const double &close[],
                       int bars, const SymbolProfile &prof, double atrVal)
{
   if(bars < 40 || atrVal <= 0.0)
   {
      Print("[SD_DETECT_DEMAND_EARLY_EXIT] bars=", bars, " atr=", DoubleToString(atrVal, _Digits));
      return;
   }

   double avgBodyRaw = SDAvgBody(open, close, bars);
   double avgBody = avgBodyRaw;
   if(avgBody <= 0.0)
      avgBody = atrVal * 0.30;
   // Cap avgBody so outlier impulse candles cannot inflate the momentum threshold
   // above what typical candles in a ranging window can meet.
   if(atrVal > 0.0 && avgBody > atrVal * 0.60)
      avgBody = atrVal * 0.60;

   int minMom = MathMax(2, InpSDMinMomentumCandles);
   int maxMom = MathMax(minMom, InpSDMaxMomentumCandles);

   int dbgExtScanned=0, dbgExtImpulse=0, dbgExtDepart=0, dbgExtBOS=0, dbgExtWidth=0, dbgExtCreated=0;
   int dbgWickCand=0, dbgWickClusters=0, dbgWickHitsOk=0, dbgWickWidthOk=0, dbgWickDepartOk=0, dbgWickCreated=0;
   int dbgMomScan=0, dbgMomRunOk=0, dbgMomWidthOk=0, dbgMomDepartOk=0, dbgMomCreated=0;

   // Last closed bar's close, used to skip momentum zones that currently wrap price.
   double refPrice = (bars > 1 ? close[1] : close[0]);

   // ------------------------------------------------------------
   // EXTREME SINGLE IMPULSE METHOD — Demand
   // One huge bullish momentum candle marks the previous candle's
   // full wick high to wick low as the Demand zone.
   // ------------------------------------------------------------
   if(InpSDUseSingleMomentumCandleMethod)
   {
      for(int m = 1; m < bars - InpSDPreBaseLegBars - 3; m++)
      {
         dbgExtScanned++;
         if(!SDIsExtremeBullImpulse(open, high, low, close, m, avgBody, atrVal))
            continue;
         dbgExtImpulse++;

         int base = m + 1;
         if(base >= bars)
            continue;

         double zoneHigh = high[base];
         double zoneLow  = low[base];

         if(zoneHigh <= zoneLow)
            continue;

         if((zoneHigh - zoneLow) < InpSDMinZoneWidthPoints * prof.point)
            continue;

         if((zoneHigh - zoneLow) > atrVal * SD_ACTIVE_MAX_WIDTH_ATR)
         {
            Print("[EXTREME_IMPULSE_ZONE_REJECT] side=Demand reason=previous_candle_zone_too_wide",
                  " upper=", DoubleToString(zoneHigh, _Digits),
                  " lower=", DoubleToString(zoneLow, _Digits),
                  " widthATR=", DoubleToString((zoneHigh - zoneLow) / atrVal, 2));
            continue;
         }
         dbgExtWidth++;

         double departureATR = (close[m] - zoneHigh) / atrVal;
         if(departureATR < InpSDMinDepartureATR)
            continue;
         dbgExtDepart++;

         double olderHigh = SDHighest(high, base + 1, MathMin(base + InpSDBOSLookback, bars - 1));
         bool bos = (close[m] > olderHigh + atrVal * 0.10);

         if(InpSDExtremeImpulseRequireBOS && !bos)
            continue;
         dbgExtBOS++;

         ENUM_ZONE_TYPE zt =
            (departureATR >= InpSDMajorDepartureATR || bos)
            ? ZONE_DEMAND_MAJOR
            : ZONE_DEMAND_MINOR;

         int incomingDir = SDIncomingLegDirection(open, high, low, close, base, bars, avgBody);
         string patternCode = SDPatternCode(true, incomingDir);

         int idx = AddOrUpdateZone(zt, zoneHigh, zoneLow, 1, base, prof, atrVal,
                                   false, "", -1, "PDF_EXTREME_IMPULSE_DEMAND", base);
         dbgExtCreated++;

         StampPDFSupplyDemandZone(idx,
                                  true,
                                  "PDF_EXTREME_IMPULSE_DEMAND",
                                  departureATR,
                                  bos,
                                  base,
                                  1,
                                  patternCode);

         Print("[SD_METHOD_CREATED] method=PDF_EXTREME_IMPULSE_DEMAND",
               " id=", idx,
               " pattern=", patternCode,
               " impulseShift=", m,
               " baseShift=", base,
               " upper=", DoubleToString(zoneHigh, _Digits),
               " lower=", DoubleToString(zoneLow, _Digits),
               " departureATR=", DoubleToString(departureATR, 2),
               " bos=", bos ? "true" : "false");
      }
   }

   // ------------------------------------------------------------
   // PDF METHOD 1: Momentum candles
   // Look for at least 3 strong bullish momentum candles in a row.
   // Mark the high/low of the candle directly before the momentum.
   // ------------------------------------------------------------
   if(SDUseMomentumMethod())
   {
   for(int base = maxMom + 2; base < bars - InpSDPreBaseLegBars - 2; base++)
   {
      dbgMomScan++;
      bool run = true;
      int momCount = 0;

      for(int m = 1; m <= maxMom; m++)
      {
         int mi = base - m;
         if(mi < 1) break;

         if(SDIsBullMomentum(open, high, low, close, mi, avgBody))
            momCount++;
         else
         {
            if(m <= minMom) run = false;
            break;
         }
      }

      if(!run || momCount < minMom)
         continue;
      dbgMomRunOk++;

      double zoneHigh = high[base];
      double zoneLow  = low[base];

      if(zoneHigh <= zoneLow)
         continue;

      if((zoneHigh - zoneLow) < InpSDMinZoneWidthPoints * prof.point)
         continue;
      dbgMomWidthOk++;

      // C) Skip zones that currently wrap price — they cannot be retested from below.
      // For a Demand zone we need current price ABOVE zoneHigh so a pullback down to the zone is possible.
      if(refPrice <= zoneHigh)
         continue;

      int finalMomBar = base - momCount;
      if(finalMomBar < 1)
         continue;

      double departureATR = (close[finalMomBar] - zoneHigh) / atrVal;
      if(departureATR < InpSDMinDepartureATR)
         continue;
      dbgMomDepartOk++;

      double olderHigh = SDHighest(high, base + 1, MathMin(base + InpSDBOSLookback, bars - 1));
      bool bos = (close[finalMomBar] > olderHigh + atrVal * 0.10);

      ENUM_ZONE_TYPE zt = (departureATR >= InpSDMajorDepartureATR || momCount >= 5 || bos)
                          ? ZONE_DEMAND_MAJOR
                          : ZONE_DEMAND_MINOR;

      int incomingDir = SDIncomingLegDirection(open, high, low, close, base, bars, avgBody);
      string patternCode = SDPatternCode(true, incomingDir);
      int idx = AddOrUpdateZone(zt, zoneHigh, zoneLow, momCount, base, prof, atrVal, false, "", -1, "PDF_MOMENTUM_DEMAND", base);
      dbgMomCreated++;
      StampPDFSupplyDemandZone(idx, true, "PDF_MOMENTUM_DEMAND", departureATR, bos, base, momCount, patternCode);

      Print("[SD_METHOD_CREATED] method=PDF_MOMENTUM_DEMAND",
            " id=", idx,
            " pattern=", patternCode,
            " baseShift=", base,
            " momCount=", momCount,
            " upper=", DoubleToString(zoneHigh, _Digits),
            " lower=", DoubleToString(zoneLow, _Digits),
            " departureATR=", DoubleToString(departureATR, 2),
            " bos=", bos ? "true" : "false");
   }
   }

   // ------------------------------------------------------------
   // PDF METHOD 2: Consolidation
   // Find sideways base before bullish momentum and box the entire base.
   // ------------------------------------------------------------
   if(SDUseConsolidationMethod())
   {
   int baseBars = MathMax(3, InpSDConsolidationBars);

   for(int base = maxMom + 2; base < bars - baseBars - InpSDPreBaseLegBars - 2; base++)
   {
      double zoneHigh = SDHighest(high, base, base + baseBars - 1);
      double zoneLow  = SDLowest(low, base, base + baseBars - 1);
      double width = zoneHigh - zoneLow;

      if(width <= 0.0)
         continue;

      if(width > atrVal * InpSDConsolidationMaxATR)
         continue;

      double avgBaseBody = 0.0;
      for(int b = base; b <= base + baseBars - 1; b++)
      {
         avgBaseBody += MathAbs(close[b] - open[b]);
      }
      avgBaseBody /= MathMax(baseBars, 1);

      if(avgBaseBody > atrVal * 0.35)
         continue;

      int momCount = 0;
      for(int m = 1; m <= maxMom; m++)
      {
         int mi = base - m;
         if(mi < 1) break;

         if(SDIsBullMomentum(open, high, low, close, mi, avgBody))
            momCount++;
         else
            break;
      }

      if(momCount < minMom)
         continue;

      int finalMomBar = base - momCount;
      if(finalMomBar < 1)
         continue;

      double departureATR = (close[finalMomBar] - zoneHigh) / atrVal;
      if(departureATR < InpSDMinDepartureATR)
         continue;

      double olderHigh = SDHighest(high, base + baseBars, MathMin(base + baseBars + InpSDBOSLookback, bars - 1));
      bool bos = (close[finalMomBar] > olderHigh + atrVal * 0.10);

      ENUM_ZONE_TYPE zt = (departureATR >= InpSDMajorDepartureATR || momCount >= 5 || bos)
                          ? ZONE_DEMAND_MAJOR
                          : ZONE_DEMAND_MINOR;

      int incomingDir = SDIncomingLegDirection(open, high, low, close, base + baseBars - 1, bars, avgBody);
      string patternCode = SDPatternCode(true, incomingDir);
      int idx = AddOrUpdateZone(zt, zoneHigh, zoneLow, momCount, base, prof, atrVal, false, "", -1, "PDF_CONSOLIDATION_DEMAND", base);
      StampPDFSupplyDemandZone(idx, true, "PDF_CONSOLIDATION_DEMAND", departureATR, bos, base, momCount, patternCode);
   }
   }

   // ------------------------------------------------------------
   // PDF METHOD 3: Wick rejection (confluent cluster)
   // Find multiple lower wicks that reject at the same level and form
   // a horizontal Demand band from the lowest wick extreme to the
   // body-bottom of the shallowest wick in the cluster.
   // ------------------------------------------------------------
   if(SDUseWickMethod())
   {
   int scanMax = MathMin(bars - 2, MathMax(8, InpSDWickScanBars));
   int    candIdx[256];
   double candExtreme[256];
   double candBodyEdge[256];
   int    candCount = 0;

   for(int i = 2; i < scanMax && candCount < 256; i++)
   {
      double range = high[i] - low[i];
      if(range <= 0.0) continue;

      double bodyLow = MathMin(open[i], close[i]);
      double lowerWick = bodyLow - low[i];
      if(lowerWick / range < InpSDMinWickPct) continue;

      double body = MathAbs(close[i] - open[i]);
      if(body <= 0.0) continue;
      if(lowerWick < body * InpSDPinbarMinWickToBody) continue;

      candIdx[candCount]      = i;
      candExtreme[candCount]  = low[i];
      candBodyEdge[candCount] = bodyLow;
      candCount++;
   }
   dbgWickCand = candCount;

   bool   used[256];
   ArrayInitialize(used, false);
   double clusterTol = atrVal * MathMax(0.05, InpSDWickClusterATR);
   int    minCluster = MathMax(2, InpSDMinWickCluster);

   for(int a = 0; a < candCount; a++)
   {
      if(used[a]) continue;
      double anchorL = candExtreme[a];
      double zLow    = anchorL;
      double zHigh   = candBodyEdge[a];
      int    hits    = 1;
      int    newestI = candIdx[a];
      int    oldestI = candIdx[a];
      used[a] = true;

      for(int b = a + 1; b < candCount; b++)
      {
         if(used[b]) continue;
         if(MathAbs(candExtreme[b] - anchorL) > clusterTol) continue;
         used[b] = true;
         hits++;
         if(candExtreme[b] < zLow)   zLow  = candExtreme[b];
         if(candBodyEdge[b] > zHigh) zHigh = candBodyEdge[b];
         if(candIdx[b] < newestI)    newestI = candIdx[b];
         if(candIdx[b] > oldestI)    oldestI = candIdx[b];
      }

      dbgWickClusters++;
      if(hits < minCluster) continue;
      dbgWickHitsOk++;
      if((zHigh - zLow) < InpSDMinZoneWidthPoints * prof.point) continue;
      if((zHigh - zLow) > atrVal * SD_ACTIVE_MAX_WIDTH_ATR) continue;
      dbgWickWidthOk++;

      // Validate price subsequently moved UP since the newest wick in the cluster.
      double maxHighAfter = high[MathMax(1, newestI - 1)];
      for(int k = 1; k < newestI; k++)
         if(high[k] > maxHighAfter) maxHighAfter = high[k];

      double departureATR = (maxHighAfter - zHigh) / atrVal;
      if(departureATR < InpSDMinDepartureATR * 0.50) continue;
      dbgWickDepartOk++;

      ENUM_ZONE_TYPE zt = (departureATR >= InpSDMajorDepartureATR || hits >= 3)
                          ? ZONE_DEMAND_MAJOR
                          : ZONE_DEMAND_MINOR;

      int incomingDir = SDIncomingLegDirection(open, high, low, close, oldestI, bars, avgBody);
      string patternCode = SDPatternCode(true, incomingDir);
      int idx = AddOrUpdateZone(zt, zHigh, zLow, hits, newestI, prof, atrVal, false, "", -1, "PDF_WICK_DEMAND", newestI);
      dbgWickCreated++;
      StampPDFSupplyDemandZone(idx, true, "PDF_WICK_DEMAND", departureATR, false, newestI, hits, patternCode);

      Print("[SD_METHOD_CREATED] method=PDF_WICK_DEMAND",
            " id=", idx, " hits=", hits,
            " zHigh=", DoubleToString(zHigh, _Digits),
            " zLow=", DoubleToString(zLow, _Digits),
            " newest=", newestI, " oldest=", oldestI,
            " departureATR=", DoubleToString(departureATR, 2));
   }
   }

   Print("[SD_DETECT_DEMAND_DIAG] bars=", bars,
         " atr=", DoubleToString(atrVal, _Digits),
         " avgBody=", DoubleToString(avgBody, _Digits),
         " extScan=", dbgExtScanned,
         " extImp=", dbgExtImpulse,
         " extWidthOk=", dbgExtWidth,
         " extDepart=", dbgExtDepart,
         " extBOS=", dbgExtBOS,
         " extCreated=", dbgExtCreated,
         " wickCand=", dbgWickCand,
         " wickClusters=", dbgWickClusters,
         " wickHitsOk=", dbgWickHitsOk,
         " wickWidthOk=", dbgWickWidthOk,
         " wickDepartOk=", dbgWickDepartOk,
         " wickCreated=", dbgWickCreated,
         " momScan=", dbgMomScan,
         " momRunOk=", dbgMomRunOk,
         " momWidthOk=", dbgMomWidthOk,
         " momDepartOk=", dbgMomDepartOk,
         " momCreated=", dbgMomCreated);
}

//+------------------------------------------------------------------+
//| Previous day highs/lows as session-level major zones             |
//+------------------------------------------------------------------+
void DetectDailyLevels(const SymbolProfile &prof, double atrVal)
{
   double hiD1[], loD1[];
   int copied = CopyHigh(_Symbol, PERIOD_D1, 1, 5, hiD1);
   if(copied < 1) return;
   int copiedL = CopyLow(_Symbol, PERIOD_D1, 1, MathMin(copied, 5), loD1);
   int useCount = MathMin(copied, MathMin(copiedL, 5));
   if(useCount < 1) return;

   double tol = MathMax(atrVal * 0.25, prof.defaultSLBufferPoints * prof.point);
   for(int i = 0; i < useCount; i++)
   {
      int age = (i + 1) * 6;
      int idxH = AddOrUpdateZone(ZONE_RESISTANCE_MAJOR, hiD1[i] + tol, hiD1[i] - tol,
                                  1, age, prof, atrVal);
      if(idxH >= 0) g_zoneReg.zones[idxH].isSessionLevel = true;

      int idxL = AddOrUpdateZone(ZONE_SUPPORT_MAJOR, loD1[i] + tol, loD1[i] - tol,
                                  1, age, prof, atrVal);
      if(idxL >= 0) g_zoneReg.zones[idxL].isSessionLevel = true;
   }
}

//+------------------------------------------------------------------+
//| PATCH 9: Prune duplicate pending flip zones                      |
//+------------------------------------------------------------------+
void SDPrunePendingFlipRetestClones(double atrVal)
{
   if(!InpUseSupplyDemandZones || atrVal <= 0.0)
      return;

   for(int i = g_zoneReg.count - 1; i >= 0; i--)
   {
      if(!g_zoneReg.zones[i].isFlipZone || !g_zoneReg.zones[i].broken)
         continue;

      if(g_zoneReg.zones[i].flipRetestConfirmed)
         continue;

      for(int j = i - 1; j >= 0; j--)
      {
         if(!g_zoneReg.zones[j].isFlipZone || !g_zoneReg.zones[j].broken)
            continue;

         if(g_zoneReg.zones[j].flipRetestConfirmed)
            continue;

         if(!IsSameZoneDirection(g_zoneReg.zones[i].type, g_zoneReg.zones[j].type))
            continue;

         double overlapPct = ZoneOverlapPct(g_zoneReg.zones[i], g_zoneReg.zones[j]);

         if(overlapPct > 0.50)
         {
            int keepIdx = (g_zoneReg.zones[i].ageInBars <= g_zoneReg.zones[j].ageInBars) ? i : j;
            int removeIdx = (keepIdx == i) ? j : i;

            Print("[PRUNE_DUPLICATE_FLIP_ZONE] removeId=", g_zoneReg.zones[removeIdx].id,
                  " keepId=", g_zoneReg.zones[keepIdx].id,
                  " overlap=", DoubleToString(overlapPct * 100.0, 1), "%",
                  " reason=pending_flip_retest_clone");

            RemoveZoneSlot(removeIdx);

            if(removeIdx < i)
               i--;

            break;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Smart merge pass                                                 |
//+------------------------------------------------------------------+
void MergePass(double atrVal)
{
   bool didMerge = true;
   while(didMerge)
   {
      didMerge = false;
      for(int i = 0; i < g_zoneReg.count && !didMerge; i++)
      {
         if(!g_zoneReg.zones[i].active) continue;
         for(int j = i + 1; j < g_zoneReg.count && !didMerge; j++)
         {
            if(!g_zoneReg.zones[j].active) continue;
            if(!ShouldMergeZones(g_zoneReg.zones[i], g_zoneReg.zones[j], atrVal)) continue;
            int winner = i, loser = j;
            // PATCH 15: Use IsPreferredClusterWinner for stronger clustered-zone winner logic
            if(IsPreferredClusterWinner(g_zoneReg.zones[j], g_zoneReg.zones[i]))
               { winner = j; loser = i; }
            MergeZonesSmart(winner, loser);
            didMerge = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dedup pass: remove zones with near-identical bounds              |
//+------------------------------------------------------------------+
void DeduplicateZones(double atrVal)
{
   double tol = _Point * 10.0; // 1 pip tolerance
   int removed = 0;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].valid) continue;

      for(int j = i + 1; j < g_zoneReg.count; j++)
      {
         if(!g_zoneReg.zones[j].valid) continue;
         if(!IsSameZoneDirection(g_zoneReg.zones[i].type, g_zoneReg.zones[j].type)) continue;

         double upperDiff = MathAbs(g_zoneReg.zones[i].upperBound - g_zoneReg.zones[j].upperBound);
         double lowerDiff = MathAbs(g_zoneReg.zones[i].lowerBound - g_zoneReg.zones[j].lowerBound);

         if(upperDiff <= tol && lowerDiff <= tol)
         {
            // Keep the one with better quality score
            int loser = (g_zoneReg.zones[i].qualityScore >= g_zoneReg.zones[j].qualityScore) ? j : i;
            g_zoneReg.zones[loser].valid = false;
            g_zoneReg.zones[loser].active = false;
            g_zoneReg.zones[loser].isBackup = false;
            removed++;

            if(loser == i) break; // i is dead, move to next i
         }
      }
   }

   // Purge invalid slots to free array space and prevent registry bloat
   for(int i = g_zoneReg.count - 1; i >= 0; i--)
   {
      if(!g_zoneReg.zones[i].valid && !g_zoneReg.zones[i].active && !g_zoneReg.zones[i].isBackup)
         RemoveZoneSlot(i);
   }

   if(removed > 0)
      Print("[ZONE_DEDUP] removed=", removed, " total_after_purge=", g_zoneReg.count);
}

bool ZoneEligibleAsSupportHere(const ZoneInfo &z, double price, double atr);
bool ZoneEligibleAsResistanceHere(const ZoneInfo &z, double price, double atr);
double ScorePrimaryCandidate(const ZoneInfo &z, bool wantSupport, double price, double atr);
PrimaryZones BuildPrimaryZonesFromRegistry(double price, double atr);

bool FindLocationBasedPrimaryFallback(const bool wantSupport,
                                      const double price,
                                      const double atr,
                                      const int excludeId,
                                      ZoneInfo &outZone)
{
   double safeAtr = MathMax(atr, _Point * 10.0);
   double bestScore = -DBL_MAX;
   bool found = false;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.valid || !z.active || z.broken)
         continue;
      if(z.id == excludeId)
         continue;

      bool allowHistorical =
         (z.historical &&
          (z.qualityScore >= MathMax(ZoneWeakRejectThreshold, 2.5) ||
           z.structuralAnchor || z.isFlipZone || z.protectedKeyZone));

      if(z.historical && !allowHistorical)
         continue;

      bool correctSide =
         wantSupport
         ? (z.midPoint < price - safeAtr * 0.10)
         : (z.midPoint > price + safeAtr * 0.10);

      if(!correctSide)
         continue;

      bool sideFamilyOk = false;
      if(wantSupport)
      {
         sideFamilyOk =
            IsSupportStructurallyValid(z) ||
            z.isFlipZone || z.protectedKeyZone ||
            z.type == ZONE_SUPPORT_MAJOR ||
            z.type == ZONE_SUPPORT_MINOR ||
            z.type == ZONE_DEMAND;
      }
      else
      {
         sideFamilyOk =
            IsResistanceStructurallyValid(z) ||
            z.isFlipZone || z.protectedKeyZone ||
            z.type == ZONE_RESISTANCE_MAJOR ||
            z.type == ZONE_RESISTANCE_MINOR ||
            z.type == ZONE_SUPPLY;
      }

      if(!sideFamilyOk)
         continue;

      double distATR = MathAbs(z.midPoint - price) / safeAtr;
      if(distATR > 6.0)
         continue;

      double score = SafePrimaryScoreValue(z, wantSupport, price, atr);

      // fallback-safe scoring: still usable even if ScorePrimaryCandidate was too strict
      score += z.strength * 0.25;
      score += (z.structuralAnchor ? 0.40 : 0.0);
      score += (z.protectedKeyZone ? 0.35 : 0.0);
      score += (z.isFlipZone ? 0.30 : 0.0);
      score += (allowHistorical ? 0.15 : 0.0);
      score -= MathMax(0.0, distATR - 1.50) * 0.30;

      if(!found || score > bestScore)
      {
         outZone = z;
         bestScore = score;
         found = true;
      }
   }

   return found;
}

//+------------------------------------------------------------------+
//| Select Primary Zone Pair                                         |
//+------------------------------------------------------------------+
bool SelectPrimaryZonePair(double price, double atr, ZoneInfo &outSupport, ZoneInfo &outResistance, bool &hasSupport, bool &hasResistance)
{
   hasSupport = false;
   hasResistance = false;

   double safeAtr = MathMax(atr, _Point * 10.0);
   int trendBias  = GetZoneTrendBias();

   double bestSupScore = -DBL_MAX;
   double bestResScore = -DBL_MAX;
   double bestSupDist  = DBL_MAX;
   double bestResDist  = DBL_MAX;

   for(int i = 0; i < g_zoneReg.count; ++i)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.valid || !z.active || z.historical || z.broken)
         continue;

      ZONE_CANONICAL_ROLE role = ResolveZoneRole(z, price, atr);
      if(role == ZROLE_UNKNOWN)
         continue;

      double distATR = MathAbs(z.midPoint - price) / safeAtr;
      bool structuralish = (z.structuralAnchor || z.structuralTag != "" || z.protectedKeyZone || z.continuationEligible);

      if(distATR > 3.60 && !structuralish)
         continue;

      if(role == ZROLE_SUPPORT)
      {
         if(!ZoneEligibleAsSupportHere(z, price, atr))
            continue;

         double score = SafePrimaryScoreValue(z, true, price, atr);
         score += GetTrendAwarePrimaryBonus(z, true, trendBias);
         score -= MathMax(0.0, distATR - 1.60) * 0.40;

         if(!hasSupport || score > bestSupScore ||
            (MathAbs(score - bestSupScore) < 1e-6 && distATR < bestSupDist))
         {
            outSupport    = z;
            hasSupport    = true;
            bestSupScore  = score;
            bestSupDist   = distATR;
         }
      }
      else if(role == ZROLE_RESISTANCE)
      {
         if(!ZoneEligibleAsResistanceHere(z, price, atr))
            continue;

         double score = SafePrimaryScoreValue(z, false, price, atr);
         score += GetTrendAwarePrimaryBonus(z, false, trendBias);
         score -= MathMax(0.0, distATR - 1.60) * 0.40;

         if(!hasResistance || score > bestResScore ||
            (MathAbs(score - bestResScore) < 1e-6 && distATR < bestResDist))
         {
            outResistance   = z;
            hasResistance   = true;
            bestResScore    = score;
            bestResDist     = distATR;
         }
      }
   }

   if(!hasSupport)
   {
      ZoneInfo fb;
      if(FindClosestStructuralRoleZone(true, trendBias, price, atr, fb))
      {
         outSupport = fb;
         hasSupport = true;
         bestSupScore = SafePrimaryScoreValue(fb, true, price, atr) +
                        GetTrendAwarePrimaryBonus(fb, true, trendBias);
         bestSupDist = MathAbs(fb.midPoint - price) / safeAtr;

         Print("[PRIMARY_STRUCTURAL_FALLBACK] side=support id=", fb.id,
               " tag=", fb.structuralTag,
               " mid=", DoubleToString(fb.midPoint, _Digits));
      }
   }

   if(!hasResistance)
   {
      ZoneInfo fb;
      if(FindClosestStructuralRoleZone(false, trendBias, price, atr, fb))
      {
         outResistance = fb;
         hasResistance = true;
         bestResScore = SafePrimaryScoreValue(fb, false, price, atr) +
                        GetTrendAwarePrimaryBonus(fb, false, trendBias);
         bestResDist = MathAbs(fb.midPoint - price) / safeAtr;

         Print("[PRIMARY_STRUCTURAL_FALLBACK] side=resistance id=", fb.id,
               " tag=", fb.structuralTag,
               " mid=", DoubleToString(fb.midPoint, _Digits));
      }
   }

   if(!hasSupport)
   {
      ZoneInfo fb;
      if(FindLocationBasedPrimaryFallback(true, price, atr, hasResistance ? outResistance.id : -1, fb))
      {
         outSupport = fb;
         hasSupport = true;
         bestSupScore = SafePrimaryScoreValue(fb, true, price, atr);
         bestSupDist = MathAbs(fb.midPoint - price) / safeAtr;

         Print("[PRIMARY_LOCATION_FALLBACK] side=support id=", fb.id,
               " tag=", fb.structuralTag,
               " mid=", DoubleToString(fb.midPoint, _Digits));
      }
   }

   if(!hasResistance)
   {
      ZoneInfo fb;
      if(FindLocationBasedPrimaryFallback(false, price, atr, hasSupport ? outSupport.id : -1, fb))
      {
         outResistance = fb;
         hasResistance = true;
         bestResScore = SafePrimaryScoreValue(fb, false, price, atr);
         bestResDist = MathAbs(fb.midPoint - price) / safeAtr;

         Print("[PRIMARY_LOCATION_FALLBACK] side=resistance id=", fb.id,
               " tag=", fb.structuralTag,
               " mid=", DoubleToString(fb.midPoint, _Digits));
      }
   }

   if(hasSupport && hasResistance && outSupport.id == outResistance.id)
   {
      if(bestSupScore >= bestResScore)
         hasResistance = false;
      else
         hasSupport = false;
   }

   if(hasSupport)
   {
      Print("[PRIMARY_ZONE_SELECTED] side=SUPPORT id=", outSupport.id,
            " tag=", outSupport.structuralTag,
            " mid=", DoubleToString(outSupport.midPoint, _Digits),
            " score=", DoubleToString(bestSupScore, 2),
            " quality=", DoubleToString(outSupport.qualityScore, 2),
            " major=", outSupport.majorQualified ? "true" : "false");
   }

   if(hasResistance)
   {
      Print("[PRIMARY_ZONE_SELECTED] side=RESISTANCE id=", outResistance.id,
            " tag=", outResistance.structuralTag,
            " mid=", DoubleToString(outResistance.midPoint, _Digits),
            " score=", DoubleToString(bestResScore, 2),
            " quality=", DoubleToString(outResistance.qualityScore, 2),
            " major=", outResistance.majorQualified ? "true" : "false");
   }

   return (hasSupport || hasResistance);
}

//+------------------------------------------------------------------+
//| Promote exactly one primary support + one primary resistance.    |
//+------------------------------------------------------------------+
void PromotePrimaryZones(double price, double atr)
{
   // Clear all primary/backup flags first
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      g_zoneReg.zones[i].isPrimary = false;
      g_zoneReg.zones[i].isBackup = false;
      g_zoneReg.zones[i].hasExecBand = false;
   }

   if(price <= 0.0 || atr <= 0.0)
   {
      Print("[PRIMARY_ZONE_MISSING] support=false resistance=false reason=invalid_price_or_atr");
      return;
   }

   ZoneInfo supportZone, resistanceZone;
   bool hasSupport, hasResistance;

   if(!SelectPrimaryZonePair(price, atr, supportZone, resistanceZone, hasSupport, hasResistance))
   {
      Print("[PRIMARY_ZONE_MISSING] support=false resistance=false reason=no_valid_candidates");
      return;
   }
   
   // Calculate relevance scores for logging
   double bestSup = -DBL_MAX;
   double bestRes = -DBL_MAX;
   if(hasSupport)
      bestSup = ComputePrimaryRelevance(supportZone, price, atr);
   if(hasResistance)
      bestRes = ComputePrimaryRelevance(resistanceZone, price, atr);

   // Apply minimum width requirement
   double minWidth = atr * 0.12;
   
   if(hasSupport)
   {
      // Fix role flags and execution band
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         if(g_zoneReg.zones[i].id == supportZone.id)
         {
            // Ensure minimum width
            if((g_zoneReg.zones[i].upperBound - g_zoneReg.zones[i].lowerBound) < minWidth)
            {
               double halfW = minWidth * 0.5;
               g_zoneReg.zones[i].upperBound = g_zoneReg.zones[i].midPoint + halfW;
               g_zoneReg.zones[i].lowerBound = g_zoneReg.zones[i].midPoint - halfW;
            }
            
            // Set execution band (upper 30% for support)
            double w = g_zoneReg.zones[i].upperBound - g_zoneReg.zones[i].lowerBound;
            g_zoneReg.zones[i].execBandLow = g_zoneReg.zones[i].lowerBound + w * 0.70;
            g_zoneReg.zones[i].execBandHigh = g_zoneReg.zones[i].upperBound;
            g_zoneReg.zones[i].hasExecBand = true;
            
            // Set primary flags
            g_zoneReg.zones[i].isPrimary = true;
            g_zoneReg.zones[i].isBackup = false;
            g_zoneReg.zones[i].isExecutionEligible = true;
            
            Print("[PRIMARY_ZONE_ROLE] id=", g_zoneReg.zones[i].id, " role=support tag=", g_zoneReg.zones[i].structuralTag, 
                  " mid=", DoubleToString(g_zoneReg.zones[i].midPoint, _Digits), " rel=", DoubleToString(bestSup, 2));
            break;
         }
      }
   }
   
   if(hasResistance)
   {
      // Fix role flags and execution band
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         if(g_zoneReg.zones[i].id == resistanceZone.id)
         {
            // Ensure minimum width
            if((g_zoneReg.zones[i].upperBound - g_zoneReg.zones[i].lowerBound) < minWidth)
            {
               double halfW = minWidth * 0.5;
               g_zoneReg.zones[i].upperBound = g_zoneReg.zones[i].midPoint + halfW;
               g_zoneReg.zones[i].lowerBound = g_zoneReg.zones[i].midPoint - halfW;
            }
            
            // Set execution band (lower 30% for resistance)
            double w = g_zoneReg.zones[i].upperBound - g_zoneReg.zones[i].lowerBound;
            g_zoneReg.zones[i].execBandLow = g_zoneReg.zones[i].lowerBound;
            g_zoneReg.zones[i].execBandHigh = g_zoneReg.zones[i].lowerBound + w * 0.30;
            g_zoneReg.zones[i].hasExecBand = true;
            
            // Set primary flags
            g_zoneReg.zones[i].isPrimary = true;
            g_zoneReg.zones[i].isBackup = false;
            g_zoneReg.zones[i].isExecutionEligible = true;
            
            Print("[PRIMARY_ZONE_ROLE] id=", g_zoneReg.zones[i].id, " role=resistance tag=", g_zoneReg.zones[i].structuralTag,
                  " mid=", DoubleToString(g_zoneReg.zones[i].midPoint, _Digits), " rel=", DoubleToString(bestRes, 2));
            break;
         }
      }
   }
   
   // Log primary pair selection
   if(hasSupport && hasResistance)
   {
      Print("[PRIMARY_ZONE_PAIR] supportId=", supportZone.id, " resistanceId=", resistanceZone.id,
            " supportTag=", supportZone.structuralTag, " resistanceTag=", resistanceZone.structuralTag);
   }
   else if(hasSupport)
   {
      Print("[PRIMARY_ZONE_MISSING] support=true resistance=false reason=no_resistance_candidate");
   }
   else if(hasResistance)
   {
      Print("[PRIMARY_ZONE_MISSING] support=false resistance=true reason=no_support_candidate");
   }
   
   // Demote all other zones to non-execution-eligible (only when not in S/D active pair mode)
   if(!InpUseSupplyDemandZones || !InpSDTradeOnlyActivePair)
   {
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         bool isPrimaryChosen = (hasSupport && g_zoneReg.zones[i].id == supportZone.id) ||
                               (hasResistance && g_zoneReg.zones[i].id == resistanceZone.id);

         if(!isPrimaryChosen)
         {
            g_zoneReg.zones[i].isPrimary = false;
            g_zoneReg.zones[i].isExecutionEligible = false;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| MAIN REFRESH                                                     |
//+------------------------------------------------------------------+
void RefreshZones(const IndicatorState &ind, const SymbolProfile &prof, int mergePoints = 150)
{
   bool isFullScan = !g_zoneReg.initialized;
   
   // Use configurable lookback for D1 zones, fallback to defaults for other TFs
   int scanBars = (g_zoneTF == PERIOD_D1) ? GetZoneLookbackBars(isFullScan)
                                           : (isFullScan ? ZM_HISTORY_BARS : ZM_FRESH_BARS);
   
   int availableBars = Bars(_Symbol, g_zoneTF);
   if(availableBars > 0)
      scanBars = MathMin(scanBars, availableBars - 10);
   
   scanBars = MathMax(scanBars, 60);

   double histOpen[], histHigh[], histLow[], histClose[];
   ArraySetAsSeries(histOpen,  true);
   ArraySetAsSeries(histHigh,  true);
   ArraySetAsSeries(histLow,   true);
   ArraySetAsSeries(histClose, true);
   
   int copiedO = CopyOpen(_Symbol, g_zoneTF, 0, scanBars, histOpen);
   int copied  = CopyHigh(_Symbol, g_zoneTF, 0, scanBars, histHigh);
   int minNeeded = isFullScan ? 50 : (g_zoneSwingLookback * 2 + 3);
   if(copied < minNeeded) { Print("ZONE: Not enough ", EnumToString(g_zoneTF), " bars (", copied, ")"); return; }

   int cL = CopyLow  (_Symbol, g_zoneTF, 0, scanBars, histLow);
   int cC = CopyClose(_Symbol, g_zoneTF, 0, scanBars, histClose);
   int bars = (int)MathMin(copiedO, MathMin(copied, MathMin(cL, cC)));
   if(bars < g_zoneSwingLookback * 2 + 3) return;

   double atrVal    = GetATR(ind, 1);
   double atrRefVal  = GetATRRef(ind, 1);
   if(atrVal    <= 0) atrVal    = prof.defaultSLBufferPoints * prof.point * 2.0;
   if(atrRefVal <= 0) atrRefVal = atrVal;
   g_atrScale = (atrVal > 0) ? (atrRefVal / atrVal) : 1.0;
   double mergePrice = MathMax(mergePoints * prof.point, atrVal * (1.0 * g_atrScale));

   if(!isFullScan)
   {
      AgeAndTouchUpdate(histHigh, histLow, bars, prof, atrVal);
      EvaluateBreaks(histClose, histHigh, histLow, bars, atrVal);
      ExpireOldZones(atrVal);
   }

   if(InpUseSupplyDemandZones)
   {
      // Only call the selected marking method. Each method is now self-contained.
      if(InpSDMarkingMethod == SD_MARK_METHOD_MOMENTUM)
      {
         DetectSupplyZones(histOpen, histHigh, histLow, histClose, bars, prof, atrVal);
         DetectDemandZones(histOpen, histHigh, histLow, histClose, bars, prof, atrVal);
      }
      else if(InpSDMarkingMethod == SD_MARK_METHOD_WICK)
      {
         DetectSupplyZones(histOpen, histHigh, histLow, histClose, bars, prof, atrVal);
         DetectDemandZones(histOpen, histHigh, histLow, histClose, bars, prof, atrVal);
      }
      else if(InpSDMarkingMethod == SD_MARK_METHOD_CONSOLIDATION)
      {
         DetectSupplyZones(histOpen, histHigh, histLow, histClose, bars, prof, atrVal);
         DetectDemandZones(histOpen, histHigh, histLow, histClose, bars, prof, atrVal);
      }

      if(!InpDisableLegacySRZones)
      {
         DetectSwingHighs(histHigh, histLow, histClose, bars, g_zoneSwingLookback, prof, atrVal);
         DetectSwingLows (histHigh, histLow, histClose, bars, g_zoneSwingLookback, prof, atrVal);
         DetectDailyLevels(prof, atrVal);
      }

      // Structural HH/HL/LH/LL fallback zones are NOT legacy clutter.
      // They are needed for trend pullbacks and range boundaries when wick/momentum/consolidation S/D creates no zones.
      if(InpUseStructuralFallbackZones)
         StampTrendStructureZones(prof, atrVal);
   }
   else
   {
      DetectSwingHighs(histHigh, histLow, histClose, bars, g_zoneSwingLookback, prof, atrVal);
      DetectSwingLows (histHigh, histLow, histClose, bars, g_zoneSwingLookback, prof, atrVal);
      StampTrendStructureZones(prof, atrVal);
      DetectDailyLevels(prof, atrVal);
   }

   // Step 2-4: merge overlapping + type-aware ATR threshold, repeat until convergence
   MergePass(atrVal);

   // Step 2b: remove exact-duplicate zones (same bounds within 1 pip)
   DeduplicateZones(atrVal);

   // Step 5: rank zones (must happen before eviction so scores are fresh)
   ClassifyKeyZones();
   for(int i = 0; i < g_zoneReg.count; i++)
      UpdateZoneScoreAndValid(i);

   // Step 6: keep top 3 support + top 3 resistance (proximity-weighted)
   double closedPrice = histClose[1];
   
   EvictExcessByDirection(closedPrice, atrVal);

   // Step 6b: final deduplication — remove same-side nearby duplicates
   DeduplicateNearbyZones(atrVal);

   // Step 6c: photo-like cleanup — reduce stacked/clustered same-side zones
   ReduceDenseRangeZoneStacks(atrVal);

   // Step 6d: prune duplicate pending flip zones
   SDPrunePendingFlipRetestClones(atrVal);

   if(!InpUseSupplyDemandZones || !InpSDTradeOnlyActivePair)
   {
      PromotePrimaryZones(closedPrice, atrVal);
   }

   CleanupHistoricalZones();

   // Final purge: remove dead slots that are neither valid, active, backup, nor historical
   for(int i = g_zoneReg.count - 1; i >= 0; i--)
   {
      if(!g_zoneReg.zones[i].valid && !g_zoneReg.zones[i].active &&
         !g_zoneReg.zones[i].isBackup && !g_zoneReg.zones[i].historical)
         RemoveZoneSlot(i);
   }

   // PATCH 15: Recompute zone quality scores after cleanup/dedup
   RecomputeZoneQualityScores(closedPrice, atrVal);

   // Select active Supply/Demand pair for trading and display
   if(InpUseSupplyDemandZones)
   {
      SDSelectActiveSupplyDemandPair(prof, atrVal);

      // STEP 4: Separate visual zones from execution zones.
      // Visible active Demand/Supply are primary; execution eligibility depends on quality.
      // Qualified hidden backups are execution-eligible but not primary.
      int backupDemandCount = 0;
      int backupSupplyCount = 0;
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         bool isActiveDemand = (g_zoneReg.zones[i].id == g_activeDemandZoneId);
         bool isActiveSupply = (g_zoneReg.zones[i].id == g_activeSupplyZoneId);

         if(isActiveDemand || isActiveSupply)
         {
            g_zoneReg.zones[i].isPrimary = true;
            g_zoneReg.zones[i].isBackup  = false;
            g_zoneReg.zones[i].isExecutionEligible =
               SDZonePassesExecutionQuality(g_zoneReg.zones[i], atrVal, true);
         }
         else
         {
            g_zoneReg.zones[i].isPrimary = false;

            if(g_zoneReg.zones[i].isBackup
               && g_zoneReg.zones[i].active
               && g_zoneReg.zones[i].valid
               && SDZonePassesExecutionQuality(g_zoneReg.zones[i], atrVal, true))
            {
               g_zoneReg.zones[i].isExecutionEligible = true;

               if(IsBullishZone(g_zoneReg.zones[i].type))
                  backupDemandCount++;
               else if(IsBearishZone(g_zoneReg.zones[i].type))
                  backupSupplyCount++;
            }
            else if(!g_zoneReg.zones[i].isTPTargetOnly)
            {
               g_zoneReg.zones[i].isExecutionEligible = false;
            }
         }
      }

      Print("[SD_EXEC_ELIGIBILITY] DemandId=", g_activeDemandZoneId,
            " SupplyId=", g_activeSupplyZoneId,
            " backupDemandCount=", backupDemandCount,
            " backupSupplyCount=", backupSupplyCount);
   }

   g_zoneReg.initialized = true;
   g_zoneReg.lastUpdate  = TimeCurrent();
   g_zoneReg.lastScanBar = Bars(_Symbol, PERIOD_CURRENT);

   // Cache for visual draw filter
   g_lastDrawPrice = closedPrice;
   g_lastDrawAtr   = atrVal;

   int keptHL=0, keptHH=0, keptLH=0, keptLL=0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active) continue;
      if(g_zoneReg.zones[i].structuralTag == "HL")      keptHL++;
      else if(g_zoneReg.zones[i].structuralTag == "HH") keptHH++;
      else if(g_zoneReg.zones[i].structuralTag == "LH") keptLH++;
      else if(g_zoneReg.zones[i].structuralTag == "LL") keptLL++;
   }
   Print("[STRUCTURAL_ZONE_COUNTS] HL=", keptHL, " HH=", keptHH,
         " LH=", keptLH, " LL=", keptLL);

   Print("ZONE REGISTRY: active=", CountActiveZones(),
         " historical=", CountHistoricalZones(), " total=", g_zoneReg.count);
}

//+------------------------------------------------------------------+
//| Rejection tagging — call after RefreshZones each bar            |
//+------------------------------------------------------------------+
void TagZoneRejections(const double &open[], const double &high[],
                       const double &low[], const double &close[],
                       int bars, double atrVal)
{
   if(!ZM_ENABLE_REJECTION || bars < 2) return;
   double o1 = open[1], h1 = high[1], l1 = low[1], c1 = close[1];
   double body  = MathAbs(c1 - o1);
   double range = h1 - l1;
   if(range <= 0 || body <= 0) return;
   double upperWick = h1 - MathMax(c1, o1);
   double lowerWick = MathMin(c1, o1) - l1;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active) continue;
      bool isBull = IsBullishZone(g_zoneReg.zones[i].type);
      bool isBear = IsBearishZone(g_zoneReg.zones[i].type);
      if(!isBull && !isBear) continue;

      bool inZone = (l1 <= g_zoneReg.zones[i].upperBound && h1 >= g_zoneReg.zones[i].lowerBound);
      if(!inZone) continue;

      double rejScore = 0.0;
      if(isBull && lowerWick > body * ZM_REJECTION_WICK_BODY &&
         lowerWick / range >= ZM_REJECTION_WICK_RANGE &&
         c1 > l1 + range * (1.0 - ZM_REJECTION_CLOSE_LOC))
      {
         rejScore = lowerWick / range;
         if(atrVal > 0) rejScore *= MathMin(lowerWick / atrVal, 1.0);
      }
      if(isBear && upperWick > body * ZM_REJECTION_WICK_BODY &&
         upperWick / range >= ZM_REJECTION_WICK_RANGE &&
         c1 < h1 - range * (1.0 - ZM_REJECTION_CLOSE_LOC))
      {
         rejScore = upperWick / range;
         if(atrVal > 0) rejScore *= MathMin(upperWick / atrVal, 1.0);
      }
      if(rejScore > 0)
      {
         g_zoneReg.zones[i].rejectionScore = MathMax(g_zoneReg.zones[i].rejectionScore, rejScore);
         g_zoneReg.zones[i].hasRejection   = true;
         UpdateZoneScoreAndValid(i);
      }
   }
}

//+------------------------------------------------------------------+
//| Breakout-origin tagging — call after RefreshZones each bar      |
//+------------------------------------------------------------------+
void TagBreakoutOrigins(const double &open[], const double &close[],
                        int bars, double atrVal)
{
   if(!ZM_ENABLE_BREAKOUT_TAG || bars < 3 || atrVal <= 0) return;
   double body1 = MathAbs(close[1] - open[1]);
   if(body1 < atrVal * ZM_BREAKOUT_BODY_ATR) return;
   bool bullBO = (close[1] > open[1]);

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active) continue;
      if(g_zoneReg.zones[i].isBreakoutOrigin) continue;

      bool isBull = IsBullishZone(g_zoneReg.zones[i].type);
      bool isBear = IsBearishZone(g_zoneReg.zones[i].type);

      if(bullBO && isBull && open[1] >= g_zoneReg.zones[i].lowerBound &&
         open[1] <= g_zoneReg.zones[i].upperBound + atrVal * 0.3)
      {
         g_zoneReg.zones[i].isBreakoutOrigin = true;
         g_zoneReg.zones[i].breakoutScore    = MathMin(body1 / atrVal, 2.0);
         UpdateZoneScoreAndValid(i);
      }
      if(!bullBO && isBear && open[1] <= g_zoneReg.zones[i].upperBound &&
         open[1] >= g_zoneReg.zones[i].lowerBound - atrVal * 0.3)
      {
         g_zoneReg.zones[i].isBreakoutOrigin = true;
         g_zoneReg.zones[i].breakoutScore    = MathMin(body1 / atrVal, 2.0);
         UpdateZoneScoreAndValid(i);
      }
   }
}

//+------------------------------------------------------------------+
//| UPGRADED PROXIMITY HELPERS                                       |
//+------------------------------------------------------------------+

bool IsNearValidZone(double price, const SymbolProfile &prof,
                     double &nearestDist, ENUM_ZONE_TYPE &nearestType,
                     double proximityOverride = 0.0)
{
   double prox = (proximityOverride > 0) ? proximityOverride
                  : prof.defaultMinTrendGapPoints * prof.point;
   nearestDist = 999999.0;
   bool found  = false;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.valid) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox && d < nearestDist) { nearestDist = d; nearestType = z.type; found = true; }
   }
   return found;
}

bool IsNearFreshZone(double price, const SymbolProfile &prof,
                     double minFreshness, double proximityOverride = 0.0)
{
   double prox = (proximityOverride > 0) ? proximityOverride
                  : prof.defaultMinTrendGapPoints * prof.point;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.valid || z.freshness < minFreshness) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox) return true;
   }
   return false;
}

int GetNearestZoneIndex(double price, bool validOnly = true)
{
   int best = -1;
   double bd = 999999.0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(validOnly && !z.valid) continue;
      if(!validOnly && !z.active) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d < bd) { bd = d; best = i; }
   }
   return best;
}

int GetBestNearbyZoneIndex(double price, const SymbolProfile &prof,
                           double proximityOverride = 0.0)
{
   double prox = (proximityOverride > 0) ? proximityOverride
                  : prof.defaultMinTrendGapPoints * prof.point;
   int best = -1;
   double bestScore = -1.0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.valid) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d > prox) continue;
      if(z.score > bestScore) { bestScore = z.score; best = i; }
   }
   return best;
}

bool IsNearValidSupply(double price, const SymbolProfile &prof,
                       double proximityOverride = 0.0)
{
   double prox = (proximityOverride > 0) ? proximityOverride
                  : prof.defaultMinTrendGapPoints * prof.point;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.valid || !IsBearishZone(z.type)) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox) return true;
   }
   return false;
}

bool IsNearValidDemand(double price, const SymbolProfile &prof,
                       double proximityOverride = 0.0)
{
   double prox = (proximityOverride > 0) ? proximityOverride
                  : prof.defaultMinTrendGapPoints * prof.point;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.valid || !IsBullishZone(z.type)) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox) return true;
   }
   return false;
}

bool GetNearbyZoneInfo(double price, const SymbolProfile &prof,
                       int &outIdx, double &outDist, double &outScore,
                       bool &outValid, bool &outFresh,
                       double proximityOverride = 0.0)
{
   double prox = (proximityOverride > 0) ? proximityOverride
                  : prof.defaultMinTrendGapPoints * prof.point;
   outIdx = -1; outDist = 999999.0; outScore = 0; outValid = false; outFresh = false;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active && !z.historical) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox && d < outDist)
      {
         outDist  = d;
         outIdx   = i;
         outScore = z.score;
         outValid = z.valid;
         outFresh = (z.freshness >= 0.5);
      }
   }
   return (outIdx >= 0);
}

bool IsStrongZone(int idx)
{
   if(idx < 0 || idx >= g_zoneReg.count) return false;
   return (g_zoneReg.zones[idx].score >= ZM_STRONG_ZONE_SCORE && g_zoneReg.zones[idx].valid);
}

//+------------------------------------------------------------------+
//| QUERY FUNCTIONS — all use local copies, no array refs           |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Buy-context zone: unbroken bullish zone OR confirmed flip→support|
//+------------------------------------------------------------------+
bool IsBuyContextZone(const ZoneInfo &z)
{
   if(!z.valid) return false;
   if(!z.active && !z.historical) return false;
   if(!z.broken && IsBullishZone(z.type)) return true;
   if(z.isFlipZone && IsBullishZone(z.type) && z.retestCount >= 1 && !z.failedRetest) return true;
   return false;
}

//+------------------------------------------------------------------+
//| Sell-context zone: unbroken bearish zone OR confirmed flip→resist|
//+------------------------------------------------------------------+
bool IsSellContextZone(const ZoneInfo &z)
{
   if(!z.valid) return false;
   if(!z.active && !z.historical) return false;
   if(!z.broken && IsBearishZone(z.type)) return true;
   if(z.isFlipZone && IsBearishZone(z.type) && z.retestCount >= 1 && !z.failedRetest) return true;
   return false;
}

bool IsSupportRoleZone(const ZoneInfo &z)    { return IsBuyContextZone(z); }
bool IsResistanceRoleZone(const ZoneInfo &z) { return IsSellContextZone(z); }

//+------------------------------------------------------------------+
//| IsNearAnyZone — expanded to all support/resistance families      |
//+------------------------------------------------------------------+
bool IsNearAnyZone(double price, const SymbolProfile &prof,
                   double &nearestDist, ENUM_ZONE_TYPE &nearestType,
                   double proximityOverride = 0.0)
{
   double prox = (proximityOverride > 0) ? proximityOverride
                  : prof.defaultMinTrendGapPoints * prof.point;

   nearestDist = 999999.0;
   bool found  = false;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];

      // only live active zones
      if(!z.valid || !z.active || z.historical || z.broken)
         continue;

      if(!IsBuyContextZone(z) && !IsSellContextZone(z))
         continue;

      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));

      if(d <= prox && d < nearestDist)
      {
         nearestDist = d;
         nearestType = z.type;
         found = true;
      }
   }

   return found;
}

bool IsNearMajorZone(double price, const SymbolProfile &prof)
{
   double prox = prof.defaultMinTrendGapPoints * prof.point;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active && !z.historical) continue;
      if(z.type != ZONE_SUPPORT_MAJOR && z.type != ZONE_RESISTANCE_MAJOR &&
         z.type != ZONE_EMA_CONFLUENCE) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox) return true;
   }
   return false;
}

bool IsNearMinorZone(double price, const SymbolProfile &prof)
{
   double prox = prof.defaultMinTrendGapPoints * prof.point;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      if(z.type != ZONE_SUPPORT_MINOR && z.type != ZONE_RESISTANCE_MINOR) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox) return true;
   }
   return false;
}

bool IsNearSupplyDemandZone(double price, const SymbolProfile &prof, bool &isSupply)
{
   double prox = prof.defaultMinTrendGapPoints * prof.point;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active && !z.historical) continue;
      if(z.type != ZONE_SUPPLY && z.type != ZONE_DEMAND) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox) { isSupply = (z.type == ZONE_SUPPLY); return true; }
   }
   return false;
}

bool GetNearestZone(double price, ZoneInfo &nearest)
{
   double atr = GetATR(g_ind, 1);
   if(atr <= 0.0)
      atr = _Point * 50.0;

   double minDist = DBL_MAX;
   double bestScore = -DBL_MAX;
   bool found = false;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];

      if(!z.valid || !z.active || z.historical || z.broken)
         continue;

      if(!IsBuyContextZone(z) && !IsSellContextZone(z))
         continue;

      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));

      double score = ComputePrimaryRelevance(z, price, atr);
      if(z.isPrimary) score += 2.00;
      if(z.structuralTag == "HL" || z.structuralTag == "LL" || z.structuralTag == "LH" || z.structuralTag == "HH")
         score += 1.00;

      if(!found || d < minDist - (_Point * 2.0) ||
         (MathAbs(d - minDist) <= (_Point * 2.0) && score > bestScore))
      {
         minDist = d;
         bestScore = score;
         nearest = z;
         found = true;
      }
   }

   return found;
}

double FindNearestSupportBelow(double price, const SymbolProfile &prof)
{
   double bestLevel = 0, bestDist = 999999.0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active && !(z.historical && z.protectedKeyZone)) continue;
      bool ok = (z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_DEMAND ||
                 (z.type == ZONE_EMA_CONFLUENCE && z.midPoint < price));
      if(!ok || z.upperBound >= price) continue;
      double dist = price - z.lowerBound;
      if(dist < bestDist) { bestDist = dist; bestLevel = z.lowerBound; }
   }
   return bestLevel;
}

double FindNearestResistanceAbove(double price, const SymbolProfile &prof)
{
   double bestLevel = 0, bestDist = 999999.0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active && !(z.historical && z.protectedKeyZone)) continue;
      bool ok = (z.type == ZONE_RESISTANCE_MAJOR || z.type == ZONE_SUPPLY ||
                 (z.type == ZONE_EMA_CONFLUENCE && z.midPoint > price));
      if(!ok || z.lowerBound <= price) continue;
      double dist = z.upperBound - price;
      if(dist < bestDist) { bestDist = dist; bestLevel = z.upperBound; }
   }
   return bestLevel;
}

double FindNearestActiveSupportBelow(double price)
{
   double best = 0, bd = 999999.0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      if(!IsBullishZone(z.type)) continue;
      if(z.upperBound >= price) continue;
      double d = price - z.lowerBound;
      if(d < bd) { bd = d; best = z.lowerBound; }
   }
   return best;
}

double FindNearestActiveResistanceAbove(double price)
{
   double best = 0, bd = 999999.0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      if(!IsBearishZone(z.type)) continue;
      if(z.lowerBound <= price) continue;
      double d = z.upperBound - price;
      if(d < bd) { bd = d; best = z.upperBound; }
   }
   return best;
}

int FindNearestProtectedHistoricalZone(double price, bool isBuy)
{
   int best = -1;
   double bd = 999999.0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.protectedKeyZone) continue;
      if(!z.historical && !z.active) continue;
      if(isBuy  && !IsBullishZone(z.type)) continue;
      if(!isBuy && !IsBearishZone(z.type)) continue;
      double d = MathAbs(price - z.midPoint);
      if(d < bd) { bd = d; best = i; }
   }
   return best;
}

bool IsPriceRetestingHistoricalKeyLevel(double price, double atrVal)
{
   double prox = MathMax(atrVal * 0.5, 0.0001);
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.historical || !z.protectedKeyZone) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox) return true;
   }
   return false;
}

int FindRelatedHistoricalZoneForNewZone(int activeZoneIdx)
{
   if(activeZoneIdx < 0 || activeZoneIdx >= g_zoneReg.count) return -1;
   int rid = g_zoneReg.zones[activeZoneIdx].relatedHistoricalZoneId;
   if(rid <= 0) return -1;
   return FindZoneById(rid);
}

//+------------------------------------------------------------------+
//| Log all zones                                                    |
//+------------------------------------------------------------------+
void LogAllZones(const SymbolProfile &prof)
{
   Print("ZONE: === Registry (", g_zoneReg.count, " total) ===");
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      string state = z.active ? "ACT" : (z.historical ? "HIST" : "DEAD");
      string flags = "";
      if(z.protectedKeyZone)        flags += "KEY ";
      if(z.broken)                  flags += "BRK ";
      if(z.isFlipZone)              flags += "FLIP ";
      if(z.isRefinement)            flags += "REF ";
      if(z.isRetestOfHistoricalZone) flags += "RHIST ";
      Print("  [", z.id, "] ", state, " ", z.label, " ",
            DoubleToString(z.lowerBound, prof.digits), "-",
            DoubleToString(z.upperBound, prof.digits),
            " ct=", z.cleanTouchCount, " age=", z.ageInBars,
            " str=", DoubleToString(z.strength, 2),
            " par=", z.parentZoneId, " rel=", z.relatedHistoricalZoneId, " ", flags);
   }
}

//+------------------------------------------------------------------+
//| DRAWING — stable object IDs, no blanket delete                  |
//+------------------------------------------------------------------+
#define ZONE_OBJ_PREFIX "MYBOT_ZONE_"

//+------------------------------------------------------------------+
//| S/D visual policy                                                |
//| The registry may keep many zones, but the chart only shows the    |
//| most recent active Demand and most recent active Supply.          |
//+------------------------------------------------------------------+
#define ZM_VISIBLE_SD_PER_SIDE 1

double ZMVisualPrice()
{
   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask  = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double last = SymbolInfoDouble(_Symbol, SYMBOL_LAST);

   if(bid > 0.0 && ask > 0.0)
      return (bid + ask) * 0.50;

   if(last > 0.0)
      return last;

   double c0 = iClose(_Symbol, PERIOD_CURRENT, 0);
   if(c0 > 0.0)
      return c0;

   return iClose(_Symbol, g_zoneTF, 0);
}

string ZMCurrentVisualRole(ZoneInfo &z)
{
   double price = ZMVisualPrice();

   // Active IDs are final visual authority.
   if(z.id > 0 && z.id == g_activeDemandZoneId)
      return "Demand";

   if(z.id > 0 && z.id == g_activeSupplyZoneId)
      return "Supply";

   // Flip zones use the new/current type, not the old type.
   if(z.isFlipZone)
   {
      if(IsBullishZone(z.type))
         return "Demand";

      if(IsBearishZone(z.type))
         return "Supply";
   }

   // Normal dynamic role.
   if(z.upperBound <= price)
      return "Demand";

   if(z.lowerBound >= price)
      return "Supply";

   // If price is inside the zone, use the current zone type first.
   if(IsBullishZone(z.type))
      return "Demand";

   if(IsBearishZone(z.type))
      return "Supply";

   return "Unknown";
}

bool ZMVisualIsDemand(ZoneInfo &z)
{
   return (ZMCurrentVisualRole(z) == "Demand");
}

bool ZMVisualIsSupply(ZoneInfo &z)
{
   return (ZMCurrentVisualRole(z) == "Supply");
}

string ZMOriginalVisualRole(ZoneInfo &z)
{
   if(IsBullishZone(z.originalType))
      return "Demand";

   if(IsBearishZone(z.originalType))
      return "Supply";

   if(IsBullishZone(z.type))
      return "Demand";

   if(IsBearishZone(z.type))
      return "Supply";

   return ZoneTypeToString(z.type);
}

bool ZMZoneCanBeVisible(ZoneInfo &z)
{
   if(!InpUseSupplyDemandZones)
      return false;

   if(!z.active)
      return false;

   // Normal broken zones are hidden.
   // Flip zones waiting for retest are allowed to remain visible.
   if(z.broken)
   {
      if(!(z.isFlipZone && !z.failedRetest))
         return false;
   }

   if(!z.valid)
   {
      if(!(z.isFlipZone && z.broken && !z.failedRetest))
         return false;
   }

   return true;
}

bool ZMZoneIsVisualActiveSlot(ZoneInfo &z)
{
   if(!ZMZoneCanBeVisible(z))
      return false;

   // The visible chart slots are only:
   // 1 current active Demand
   // 1 current active Supply
   if(z.id == g_activeDemandZoneId)
      return true;

   if(z.id == g_activeSupplyZoneId)
      return true;

   return false;
}

void _SetOrCreateHLine(string name, double price, color clr, int width,
                       ENUM_LINE_STYLE style, string tip)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   else
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
   ObjectSetString (0, name, OBJPROP_TOOLTIP, "");

   Print("[VISUAL_OBJECT_ALL_TF] name=", name, " price=", DoubleToString(price, _Digits));
}

void _SetOrCreateRect(string name, datetime t1, double price1, datetime t2, double price2,
                       color clr, int width, ENUM_LINE_STYLE style, string tip)
{
   bool needCreate = true;
   if(ObjectFind(0, name) >= 0)
   {
      ENUM_OBJECT ot = (ENUM_OBJECT)ObjectGetInteger(0, name, OBJPROP_TYPE);
      if(ot == OBJ_RECTANGLE)
      {
         ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
         ObjectSetDouble (0, name, OBJPROP_PRICE, 0, price1);
         ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
         ObjectSetDouble (0, name, OBJPROP_PRICE, 1, price2);
         needCreate = false;
      }
      else
         ObjectDelete(0, name);
   }
   if(needCreate)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, price1, t2, price2);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, name, OBJPROP_BACK,       true);
      ObjectSetInteger(0, name, OBJPROP_FILL,       false);
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetString (0, name, OBJPROP_TOOLTIP, tip);
}

bool IsVisualBullRole(const ZoneInfo &z)
{
   return IsBullishZone(z.type);
}

bool IsVisualBearRole(const ZoneInfo &z)
{
   return IsBearishZone(z.type);
}

// --- Flip role helpers (IsLiveMajorSupportRole/IsLiveMajorResistanceRole defined in MarketStructure.mqh) ---

bool IsFlippedToSupport(const ZoneInfo &z)
{
   return (z.active && z.valid && z.isFlipZone &&
           z.type == ZONE_SUPPORT_MAJOR &&
           z.originalType == ZONE_RESISTANCE_MAJOR &&
           z.retestCount >= 1 && !z.failedRetest);
}

bool IsFlippedToResistance(const ZoneInfo &z)
{
   return (z.active && z.valid && z.isFlipZone &&
           z.type == ZONE_RESISTANCE_MAJOR &&
           z.originalType == ZONE_SUPPORT_MAJOR &&
           z.retestCount >= 1 && !z.failedRetest);
}

bool ShouldDrawZoneVisual(const ZoneInfo &z)
{
   if(!z.active || !z.valid) return false;
   if(z.historical && !g_showHistoricalZones) return false;

   // Always show promoted execution zones
   if(z.isPrimary || z.isBackup)
      return true;

   // Always show structural anchors that are still active
   if(z.structuralAnchor && !z.broken)
      return true;

   // Valid flipped zones should remain visible
   if(z.isFlipZone)
   {
      if(z.failedRetest) return false;
      if(z.confirmedRetest || z.continuationEligible) return true;
      if(z.breakRetestReady && z.retestCount >= 1) return true;
      return (z.strength >= 0.40 && z.retestCount >= 1);
   }

   bool isMajor = (z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_RESISTANCE_MAJOR);
   if(isMajor)
      return (z.cleanTouchCount >= 1 && z.strength >= 0.45);

   bool strongMinor =
      (z.structuralAnchor ||
       z.protectedKeyZone ||
       z.cleanTouchCount >= 2 ||
       z.score >= 0.80);

   if(strongMinor && !z.broken)
      return true;

   return false;
}

// Check if zone is a price action zone (minor, not flip, not major TF)
bool IsPriceActionZone(const ZoneInfo &z)
{
   if(z.type == ZONE_DEMAND || z.type == ZONE_SUPPLY)
      return false;
   if(z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_RESISTANCE_MAJOR)
      return false;
   if(z.isFlipZone)
      return false;
   if(z.majorTFZone)
      return false;
   return true;
}

void _DeleteZoneObjectsById(int zoneId)
{
   string tag = ZONE_OBJ_PREFIX + IntegerToString(zoneId);
   string names[6] =
   {
      tag + "_RECT",
      tag + "_MID",
      tag + "_TOP",
      tag + "_BOT",
      tag + "_LBL",
      tag + "_LINE"
   };

   for(int i = 0; i < 6; i++)
   {
      if(ObjectFind(0, names[i]) >= 0)
         ObjectDelete(0, names[i]);
   }

   Print("[ZONE_CLEAR] id=", zoneId);
}

// Extract zone ID from object name (format: ZONE_OBJ_PREFIX + id + "_SUFFIX")
int ZMExtractZoneIdFromObjName(string name)
{
   if(StringFind(name, ZONE_OBJ_PREFIX) != 0)
      return -1;
   
   string remainder = StringSubstr(name, StringLen(ZONE_OBJ_PREFIX));
   int underscorePos = StringFind(remainder, "_");
   if(underscorePos < 0)
      return -1;
   
   string idStr = StringSubstr(remainder, 0, underscorePos);
   return (int)StringToInteger(idStr);
}

// Hard cleanup: delete all non-active S/D zone visuals and legacy objects
void ZMHardClearNonActiveSDVisuals()
{
   if(!InpUseSupplyDemandZones || !InpSDShowOnlyActivePair)
      return;

   int total = ObjectsTotal(0);
   int deleted = 0;

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);

      bool isMyZone = (StringFind(name, ZONE_OBJ_PREFIX) == 0);
      bool isLegacy =
         (StringFind(name, "D1_VISUAL_") == 0 ||
          StringFind(name, "ZONE_LOWER_") == 0 ||
          StringFind(name, "ZONE_UPPER_") == 0);

      if(isMyZone)
      {
         int zid = ZMExtractZoneIdFromObjName(name);

         bool keep =
            (zid > 0 && (zid == g_activeDemandZoneId || zid == g_activeSupplyZoneId));

         if(!keep)
         {
            ObjectDelete(0, name);
            deleted++;
         }

         continue;
      }

      if(isLegacy)
      {
         ObjectDelete(0, name);
         deleted++;
      }
   }

   Print("[ZM_VISUAL_CLEAN] deleted=", deleted,
         " keepDemand=", g_activeDemandZoneId,
         " keepSupply=", g_activeSupplyZoneId,
         " note=registry_kept_many_chart_shows_active_only");
}

void _DrawOneZone(const ZoneInfo &z)
{
   string tag      = ZONE_OBJ_PREFIX + IntegerToString(z.id);
   string nameRect = tag + "_RECT";
   string nameTop  = tag + "_TOP";
   string nameBot  = tag + "_BOT";
   string nameLbl  = tag + "_LBL";

   // Chart label/color must use CURRENT visual role.
   // Active Demand is always green. Active Supply is always red.
   // Flip zones are drawn by the new role, not the original role.
   ZoneInfo zLocal = z;
   string dynamicLabel = ZMCurrentVisualRole(zLocal);
   
   // Never draw "Inside" zones
   if(dynamicLabel == "Inside")
      return;
   
   bool isDemand = (dynamicLabel == "Demand");
   bool isSupply = (dynamicLabel == "Supply");
   bool isKey    = z.protectedKeyZone;
   bool isFlip   = z.isFlipZone;

   color rectColor;
   color lineColor;
   int   lineWidth;
   ENUM_LINE_STYLE lineStyle;

   if(InpSDDrawRectangles && InpUseSupplyDemandZones)
   {
      rectColor = isDemand ? InpSDDemandColor : InpSDSupplyColor;
      lineColor = rectColor;
      lineWidth = (z.isPrimary || isKey) ? 2 : 1;
      lineStyle = isFlip ? STYLE_DASH : STYLE_SOLID;
   }
   else
   {
      if(z.isPrimary && z.structuralAnchor)
      {
         lineColor = isDemand ? (color)clrLime : (color)clrOrangeRed;
         lineWidth = 3;
         lineStyle = STYLE_SOLID;
      }
      else if(z.isBackup && z.structuralAnchor)
      {
         lineColor = isDemand ? (color)C'0,210,80' : (color)C'255,100,0';
         lineWidth = 2;
         lineStyle = STYLE_SOLID;
      }
      else if(isFlip)
      {
         lineColor = isDemand ? (color)C'0,190,190' : (color)C'255,140,0';
         lineWidth = isKey ? 2 : 1;
         lineStyle = STYLE_DASH;
      }
      else
      {
         lineColor = isDemand ? (color)clrLime : (color)clrOrangeRed;
         lineWidth = isKey ? 2 : 1;
         lineStyle = STYLE_SOLID;
      }
      rectColor = lineColor;
   }

   // Use dynamic label for display
   string sdName = dynamicLabel;

   string tip = "";
   if(InpSDDrawRectangles && InpUseSupplyDemandZones)
   {
      tip = sdName
            + " pattern=" + z.structuralTag
            + " method=" + z.sdCreationMethod
            + " q=" + DoubleToString(z.qualityScore, 2)
            + " str=" + DoubleToString(z.strength, 2);
   }
   else
   {
      tip = z.label
            + " ct=" + IntegerToString(z.cleanTouchCount)
            + " str=" + DoubleToString(z.strength, 2)
            + (isKey  ? " [KEY]"  : "")
            + (isFlip ? " [FLIP]" : "")
            + (z.broken ? " [BRK]" : "");
   }
   
   if(InpSDDrawRectangles && InpUseSupplyDemandZones)
   {
      Print("[ZONE_DRAW_SD] id=", z.id,
            " currentRole=", dynamicLabel,
            " originalRole=", ZMOriginalVisualRole(zLocal),
            " pattern=", z.structuralTag,
            " method=", z.sdCreationMethod,
            " flip=", z.isFlipZone ? "true" : "false",
            " broken=", z.broken ? "true" : "false",
            " flipRetestConfirmed=", z.flipRetestConfirmed ? "true" : "false",
            " activeDemandId=", g_activeDemandZoneId,
            " activeSupplyId=", g_activeSupplyZoneId,
            " mode=PDF_RECTANGLE",
            " upper=", DoubleToString(z.upperBound, _Digits),
            " lower=", DoubleToString(z.lowerBound, _Digits),
            " color=", isDemand ? "GREEN" : "RED");
   }
   else
   {
      Print("[ZONE_DRAW] id=", z.id,
            " currentRole=", dynamicLabel,
            " originalRole=", ZMOriginalVisualRole(zLocal),
            " mode=", (InpSDDrawRectangles ? "RECTANGLE" : "HLINE"),
            " flip=", isFlip,
            " broken=", z.broken,
            " flipRetestConfirmed=", z.flipRetestConfirmed,
            " active=", z.active,
            " upper=", DoubleToString(z.upperBound, _Digits),
            " lower=", DoubleToString(z.lowerBound, _Digits));
   }

   if(InpSDDrawRectangles && InpUseSupplyDemandZones)
   {
      // Keep chart clean: do not stretch rectangles from the old creation bar.
      // The bot still keeps many zones internally; this only controls the visual.
      int ps = PeriodSeconds(PERIOD_CURRENT);
      if(ps <= 0)
         ps = PeriodSeconds(PERIOD_H1);

      datetime t1 = TimeCurrent() - ps * 160;
      datetime t2 = TimeCurrent() + ps * 48;

      if(ObjectFind(0, nameRect) < 0)
      {
         ObjectCreate(0, nameRect, OBJ_RECTANGLE, 0, t1, z.upperBound, t2, z.lowerBound);
         ObjectSetInteger(0, nameRect, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, nameRect, OBJPROP_HIDDEN,     true);
         ObjectSetInteger(0, nameRect, OBJPROP_BACK,       true);
         ObjectSetInteger(0, nameRect, OBJPROP_FILL,       false);
      }
      else
      {
         ObjectSetInteger(0, nameRect, OBJPROP_TIME,  0, t1);
         ObjectSetDouble (0, nameRect, OBJPROP_PRICE, 0, z.upperBound);
         ObjectSetInteger(0, nameRect, OBJPROP_TIME,  1, t2);
         ObjectSetDouble (0, nameRect, OBJPROP_PRICE, 1, z.lowerBound);
      }

      ObjectSetInteger(0, nameRect, OBJPROP_COLOR, rectColor);
      ObjectSetInteger(0, nameRect, OBJPROP_WIDTH, lineWidth);
      ObjectSetInteger(0, nameRect, OBJPROP_STYLE, lineStyle);
      ObjectSetString (0, nameRect, OBJPROP_TOOLTIP, tip);

      if(ObjectFind(0, nameTop) >= 0) ObjectDelete(0, nameTop);
      if(ObjectFind(0, nameBot) >= 0) ObjectDelete(0, nameBot);
   }
   else
   {
      _SetOrCreateHLine(nameTop, z.upperBound, lineColor, lineWidth, lineStyle, tip + " [TOP]");
      _SetOrCreateHLine(nameBot, z.lowerBound, lineColor, lineWidth, lineStyle, tip + " [BOT]");

      if(ObjectFind(0, nameRect) >= 0)
         ObjectDelete(0, nameRect);
   }

   // Use dynamic label for display
   string lbl = dynamicLabel;

   if(InpSDShowPatternInLabel && InpSDClassifyPatternType && z.structuralTag != "")
      lbl += " " + z.structuralTag;
   
   if(z.id == g_activeDemandZoneId || z.id == g_activeSupplyZoneId)
      lbl += " [ACTIVE]";
   
   if(z.isBackup)
      lbl += " [BACKUP]";
   
   if(isFlip)
      lbl += " [FLIP]";
   
   if(z.isPrimary)
      lbl += " [P]";

   color lblColor = isDemand ? InpSDDemandColor : InpSDSupplyColor;

   datetime tLbl = TimeCurrent() + PeriodSeconds(PERIOD_H4) * 3;

   if(ObjectFind(0, nameLbl) < 0)
   {
      ObjectCreate(0, nameLbl, OBJ_TEXT, 0, tLbl, z.midPoint);
      ObjectSetInteger(0, nameLbl, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nameLbl, OBJPROP_HIDDEN,     true);
      ObjectSetInteger(0, nameLbl, OBJPROP_FONTSIZE,   8);
      ObjectSetInteger(0, nameLbl, OBJPROP_BACK,       false);
   }
   else
   {
      ObjectSetInteger(0, nameLbl, OBJPROP_TIME,  0, tLbl);
      ObjectSetDouble (0, nameLbl, OBJPROP_PRICE, 0, z.midPoint);
   }

   ObjectSetString (0, nameLbl, OBJPROP_TEXT,  lbl);
   ObjectSetInteger(0, nameLbl, OBJPROP_COLOR, lblColor);
}

void _CleanOrphanedObjects()
{
   ENUM_OBJECT types[3] = {OBJ_RECTANGLE, OBJ_TEXT, OBJ_HLINE};
   for(int pass = 0; pass < 3; pass++)
   {
      int total = ObjectsTotal(0, 0, types[pass]);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(0, i, 0, types[pass]);
         if(StringFind(name, ZONE_OBJ_PREFIX) != 0) continue;
         int prefLen = StringLen(ZONE_OBJ_PREFIX);
         int uscore  = StringFind(name, "_", prefLen);
         if(uscore <= prefLen) continue;
         int zid = (int)StringToInteger(StringSubstr(name, prefLen, uscore - prefLen));
         if(zid <= 0 || FindZoneById(zid) < 0)
            ObjectDelete(0, name);
      }
   }
}

void ResetVisualD1Cache()
{
   g_visualD1Cache.count = 0;
   g_visualD1Cache.anchorBarTime = 0;
   g_visualD1CacheValid = false;
   g_visualD1CacheBarTime = 0;

   // Keep last drawn set alive so lines do not disappear on a weak rebuild.
}

bool VisualZoneStillUsable(const ZoneInfo &z, double price, double atr)
{
   if(!z.valid || !z.active || z.historical || z.broken)
      return false;

   if(z.sourceTF != g_zoneTF)
      return false;

   return (MathAbs(z.midPoint - price) <= MathMax(atr * 18.0, _Point * 1200.0));
}

bool CanReuseVisualD1Cache(datetime closedD1BarTime, double price, double atr)
{
   if(!g_visualD1CacheValid)
      return false;

   if(g_visualD1CacheBarTime != closedD1BarTime)
      return false;

   if(g_visualD1Cache.count <= 0)
      return false;

   // Reuse even if only some lines are still usable.
   int usable = 0;
   for(int i = 0; i < g_visualD1Cache.count; i++)
   {
      if(VisualZoneStillUsable(g_visualD1Cache.zones[i], price, atr))
         usable++;
   }

   return (usable >= 2);
}

double GetD1VisualATR()
{
   int h = iATR(_Symbol, g_zoneTF, 14);
   if(h == INVALID_HANDLE)
      return 0.0;

   double buf[];
   ArrayResize(buf, 3);
   ArraySetAsSeries(buf, true);
   double out = 0.0;

   if(CopyBuffer(h, 0, 0, 3, buf) > 1)
      out = buf[1];

   IndicatorRelease(h);
   return out;
}

// NOTE: ZoneEligibleForVisualD1 and ScoreVisualD1Zone moved to end of file (lines ~5570-5634)
// to incorporate zone strength mode filtering

bool ZoneFitsVisualBucket(const ZoneInfo &z, bool wantSupport, double price, double atr)
{
   ZONE_CANONICAL_ROLE role = ResolveZoneRole(z, price, atr);
   double tol = MathMax(atr * 1.80, _Point * 160.0);

   if(wantSupport)
   {
      bool supportLike =
         (role == ZROLE_SUPPORT) ||
         (z.structuralTag == "HL") ||
         (z.isFlipZone && z.midPoint <= price + tol) ||
         (z.majorTFZone && z.midPoint <= price + tol);

      if(!supportLike)
         return false;

      if(z.midPoint > price + tol)
         return false;
   }
   else
   {
      bool resistanceLike =
         (role == ZROLE_RESISTANCE) ||
         (z.structuralTag == "LH") ||
         (z.isFlipZone && z.midPoint >= price - tol) ||
         (z.majorTFZone && z.midPoint >= price - tol);

      if(!resistanceLike)
         return false;

      if(z.midPoint < price - tol)
         return false;
   }

   return true;
}

bool IsVisualSupportLike(const ZoneInfo &z, double price, double atr)
{
   double tol = MathMax(atr * 0.10, _Point * 10.0);
   ZONE_CANONICAL_ROLE role = ResolveZoneRole(z, price, atr);

   return (role == ZROLE_SUPPORT ||
           z.structuralTag == "HL" ||
           z.structuralTag == "LL" ||
           z.midPoint <= price + tol);
}

bool IsVisualResistanceLike(const ZoneInfo &z, double price, double atr)
{
   double tol = MathMax(atr * 0.10, _Point * 10.0);
   ZONE_CANONICAL_ROLE role = ResolveZoneRole(z, price, atr);

   return (role == ZROLE_RESISTANCE ||
           z.structuralTag == "LH" ||
           z.structuralTag == "HH" ||
           z.midPoint >= price - tol);
}

bool VisualZonesSameSide(const ZoneInfo &a, const ZoneInfo &b, double price, double atr)
{
   bool aSup = IsVisualSupportLike(a, price, atr);
   bool aRes = IsVisualResistanceLike(a, price, atr);
   bool bSup = IsVisualSupportLike(b, price, atr);
   bool bRes = IsVisualResistanceLike(b, price, atr);

   if(aSup && bSup) return true;
   if(aRes && bRes) return true;

   double tol = MathMax(atr * 0.10, _Point * 10.0);
   bool aBelow = (a.midPoint <= price + tol);
   bool bBelow = (b.midPoint <= price + tol);
   bool aAbove = (a.midPoint >= price - tol);
   bool bAbove = (b.midPoint >= price - tol);

   return ((aBelow && bBelow) || (aAbove && bAbove));
}

double ScoreVisualKeepPriority(const ZoneInfo &z)
{
   double s = 0.0;
   s += z.qualityScore * 1.00;
   s += z.strength * 0.60;
   s += (z.structuralAnchor ? 1.20 : 0.0);
   s += (z.protectedKeyZone ? 1.00 : 0.0);
   s += (z.isFlipZone ? 0.80 : 0.0);
   s += (z.isPrimary ? 1.50 : 0.0);
   s += (z.isBackup ? 0.75 : 0.0);
   s += (z.cleanTouchCount >= 1 ? 0.30 : 0.0);
   return s;
}

void RemoveVisualZoneAt(VisualLineSet &vs, int idx)
{
   if(idx < 0 || idx >= vs.count) return;
   for(int k = idx; k < vs.count - 1; k++)
      vs.zones[k] = vs.zones[k + 1];
   vs.count--;
}

void CollapseNearbyVisualZones(VisualLineSet &vs, double price, double atr)
{
   if(vs.count <= 1) return;

   double mergeTol = MathMax(atr * 0.22, _Point * 30.0);
   bool changed = true;

   while(changed)
   {
      changed = false;

      for(int i = 0; i < vs.count && !changed; i++)
      {
         for(int j = i + 1; j < vs.count && !changed; j++)
         {
            if(!VisualZonesSameSide(vs.zones[i], vs.zones[j], price, atr))
               continue;

            double midDist = MathAbs(vs.zones[i].midPoint - vs.zones[j].midPoint);
            if(midDist > mergeTol)
               continue;

            int keepIdx = i;
            int dropIdx = j;

            if(ScoreVisualKeepPriority(vs.zones[j]) > ScoreVisualKeepPriority(vs.zones[i]))
            {
               keepIdx = j;
               dropIdx = i;
            }

            ZoneInfo merged = vs.zones[keepIdx];
            merged.upperBound = MathMax(vs.zones[i].upperBound, vs.zones[j].upperBound);
            merged.lowerBound = MathMin(vs.zones[i].lowerBound, vs.zones[j].lowerBound);
            merged.midPoint   = NormalizeDouble((merged.upperBound + merged.lowerBound) * 0.5, _Digits);
            merged.cleanTouchCount = MathMax(vs.zones[i].cleanTouchCount, vs.zones[j].cleanTouchCount);
            merged.strength        = MathMax(vs.zones[i].strength, vs.zones[j].strength);
            merged.qualityScore    = MathMax(vs.zones[i].qualityScore, vs.zones[j].qualityScore);
            merged.protectedKeyZone = (vs.zones[i].protectedKeyZone || vs.zones[j].protectedKeyZone);
            merged.structuralAnchor = (vs.zones[i].structuralAnchor || vs.zones[j].structuralAnchor);
            merged.isFlipZone       = (vs.zones[i].isFlipZone || vs.zones[j].isFlipZone);
            merged.isPrimary        = (vs.zones[i].isPrimary || vs.zones[j].isPrimary);
            merged.isBackup         = (vs.zones[i].isBackup || vs.zones[j].isBackup);

            Print("[VISUAL_ZONE_MERGED] keep_id=", merged.id,
                  " drop_id=", vs.zones[dropIdx].id,
                  " midDistATR=", DoubleToString(midDist / MathMax(atr, _Point * 10.0), 2),
                  " newMid=", DoubleToString(merged.midPoint, _Digits));

            vs.zones[keepIdx] = merged;
            RemoveVisualZoneAt(vs, dropIdx);
            changed = true;
         }
      }
   }
}

bool VisualSetContainsNearby(const VisualLineSet &vs, const ZoneInfo &z, double tol)
{
   for(int i = 0; i < vs.count; i++)
   {
      if(vs.zones[i].id == z.id)
         return true;
      if(MathAbs(vs.zones[i].midPoint - z.midPoint) <= tol)
         return true;
   }
   return false;
}

bool ShouldKeepStickyVisualZone(const ZoneInfo &z, double price, double atr)
{
   if(!z.valid)
      return false;

   double tol = MathMax(atr * 0.20, _Point * 20.0);

   if(IsVisualSupportLike(z, price, atr))
   {
      if(price >= z.lowerBound - tol)
         return true;
   }

   if(IsVisualResistanceLike(z, price, atr))
   {
      if(price <= z.upperBound + tol)
         return true;
   }

   if(z.protectedKeyZone || z.isFlipZone || z.structuralAnchor)
   {
      if(MathAbs(price - z.midPoint) <= atr * 0.90)
         return true;
   }

   return false;
}

void SortVisualLineSetByMid(VisualLineSet &vs)
{
   for(int i = 0; i < vs.count - 1; i++)
   {
      for(int j = i + 1; j < vs.count; j++)
      {
         if(vs.zones[j].midPoint < vs.zones[i].midPoint)
         {
            ZoneInfo tmp = vs.zones[i];
            vs.zones[i] = vs.zones[j];
            vs.zones[j] = tmp;
         }
      }
   }
}

VisualLineSet BuildVisualD1LineSet(double price, double atr)
{
   VisualLineSet out;
   out.count = 0;
   out.anchorBarTime = iTime(_Symbol, g_zoneTF, 1);

   bool used[ZM_MAX_TOTAL];
   for(int i = 0; i < ZM_MAX_TOTAL; i++)
      used[i] = false;

   double minSpacing = MathMax(atr * 0.18, _Point * 25.0);
   double distTieTol = MathMax(_Point * 8.0, atr * 0.02);

   for(int side = 0; side < 2; side++)
   {
      bool wantSupport = (side == 0);

      for(int slot = 0; slot < 3; slot++)
      {
         int bestIdx = -1;
         double bestDist = DBL_MAX;
         double bestScore = -DBL_MAX;

         for(int i = 0; i < g_zoneReg.count && i < ZM_MAX_TOTAL; i++)
         {
            if(used[i])
               continue;

            ZoneInfo z = g_zoneReg.zones[i];

            if(!ZoneEligibleForVisualD1(z, price, atr))
               continue;

            if(!ZoneFitsVisualBucket(z, wantSupport, price, atr))
               continue;

            bool tooClose = false;
            for(int k = 0; k < out.count; k++)
            {
               if(MathAbs(out.zones[k].midPoint - z.midPoint) < minSpacing)
               {
                  tooClose = true;
                  break;
               }
            }
            if(tooClose)
               continue;

            double dist = MathAbs(z.midPoint - price);
            double score = ScoreVisualD1Zone(z, price, atr);

            bool better =
               (bestIdx < 0) ||
               (dist < bestDist - distTieTol) ||
               (MathAbs(dist - bestDist) <= distTieTol && score > bestScore);

            if(better)
            {
               bestIdx = i;
               bestDist = dist;
               bestScore = score;
            }
         }

         if(bestIdx < 0)
            break;

         out.zones[out.count] = g_zoneReg.zones[bestIdx];
         out.count++;
         used[bestIdx] = true;
      }
   }

   CollapseNearbyVisualZones(out, price, atr);
   SortVisualLineSetByMid(out);
   return out;
}

void DrawZoneRegistry()
{
   // Draw Supply/Demand zones from registry
   if(!InpUseSupplyDemandZones || !InpSDDrawRectangles)
      return;
   
   // Delete non-active zone rectangles first
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!SDShouldDrawZone(g_zoneReg.zones[i]))
         _DeleteZoneObjectsById(g_zoneReg.zones[i].id);
   }
   
   // Draw only active zones
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active || g_zoneReg.zones[i].broken)
         continue;
      
      if(!SDShouldDrawZone(g_zoneReg.zones[i]))
         continue;
      
      _DrawOneZone(g_zoneReg.zones[i]);
   }
   
   _CleanOrphanedObjects();
}

void DrawZoneLines(const SymbolProfile &prof)
{
   // S/D active pair mode: draw rectangles for active zones only, skip old visual drawing
   if(InpUseSupplyDemandZones && InpSDShowOnlyActivePair)
   {
      // STEP 1: Hard cleanup of all non-active zone visuals
      ZMHardClearNonActiveSDVisuals();

      int drawnCount = 0;
      int demandDrawn = 0;
      int supplyDrawn = 0;

      // STEP 2: Draw active zones + pending flip zones
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         ZoneInfo z = g_zoneReg.zones[i];
         if(!z.valid)
            continue;

         // Draw if it should be visible
         if(!SDShouldDrawZone(z))
            continue;

         string currentRole = ZMCurrentVisualRole(z);

         // Enforce max 1 Demand + max 1 Supply
         if(currentRole == "Demand")
         {
            if(demandDrawn >= 1)
               continue;
            demandDrawn++;
         }
         else if(currentRole == "Supply")
         {
            if(supplyDrawn >= 1)
               continue;
            supplyDrawn++;
         }
         else
         {
            // Skip "Inside" or other roles
            continue;
         }

         _DrawOneZone(z);
         drawnCount++;

         Print("[DRAW_ACTIVE_ZONE] id=", z.id,
               " role=", currentRole,
               " originalRole=", ZMOriginalVisualRole(z),
               " flip=", z.isFlipZone ? "true" : "false",
               " broken=", z.broken ? "true" : "false",
               " flipRetestConfirmed=", z.flipRetestConfirmed ? "true" : "false");
      }

      Print("[VISUAL_ACTIVE_ONLY] drawn=", drawnCount,
            " demandDrawn=", demandDrawn,
            " supplyDrawn=", supplyDrawn,
            " activeDemand=", g_activeDemandZoneId,
            " activeSupply=", g_activeSupplyZoneId,
            " note=max_1_demand_1_supply_includes_pending_flip");

      _CleanOrphanedObjects();
      return;
   }

   // Draw Supply/Demand rectangles if enabled (for non-active-pair mode)
   DrawZoneRegistry();

   // Photo-style visual model:
   // Do not preserve old visual zones. Rebuild clean D1 zones each draw.

   double tradePrice = iClose(_Symbol, g_indicatorTF, 1);
   double tradeAtr   = GetATR(g_ind, 1);

   if(tradePrice > 0.0 && tradeAtr > 0.0)
   {
      PromotePrimaryZones(tradePrice, tradeAtr);
      g_primaryZones = BuildPrimaryZonesFromRegistry(tradePrice, tradeAtr);
      SanitizePrimaryZones(g_primaryZones, tradePrice, tradeAtr);
   }

   double visualPrice = iClose(_Symbol, g_zoneTF, 1);
   if(visualPrice <= 0.0)
      return;

   double visualAtr = GetD1VisualATR();
   if(visualAtr <= 0.0)
      visualAtr = MathMax(tradeAtr, _Point * 150.0);

   datetime closedD1BarTime = iTime(_Symbol, g_zoneTF, 1);

   VisualLineSet vs;
   bool rebuilt = true;

   // Always rebuild the current D1 visual zones.
   // This prevents old cached zones from staying on the chart.
   vs = BuildVisualD1LineSet(visualPrice, visualAtr);
   rebuilt = true;

   g_visualD1Cache = vs;
   g_visualD1CacheValid = (vs.count > 0);
   g_visualD1CacheBarTime = closedD1BarTime;

   CollapseNearbyVisualZones(vs, visualPrice, visualAtr);
   SortVisualLineSetByMid(vs);

   Print("[ZONE_DRAW_VISUAL_CACHE] rebuilt=", (rebuilt ? "true" : "false"),
         " count=", vs.count,
         " bar=", TimeToString(closedD1BarTime));

   if(vs.count <= 0)
   {
      ClearZoneLines();
      g_lastDrawnVisualValid = false;
      Print("[ZONE_DRAW_VISUAL] no current D1 visual zones found - cleared old objects");
      ChartRedraw(0);
      return;
   }

   // Clear old visual objects before drawing new current zones.
   for(int j = 0; j < 12; j++)
   {
      string oldMid = "D1_VISUAL_LINE_" + IntegerToString(j);
      string oldTop = "D1_VISUAL_ZONE_" + IntegerToString(j) + "_TOP";
      string oldBot = "D1_VISUAL_ZONE_" + IntegerToString(j) + "_BOT";

      if(ObjectFind(0, oldMid) >= 0) ObjectDelete(0, oldMid);
      if(ObjectFind(0, oldTop) >= 0) ObjectDelete(0, oldTop);
      if(ObjectFind(0, oldBot) >= 0) ObjectDelete(0, oldBot);
   }

   for(int i = 0; i < vs.count; i++)
   {
      string oldMid = "D1_VISUAL_LINE_" + IntegerToString(i);
      if(ObjectFind(0, oldMid) >= 0)
         ObjectDelete(0, oldMid);

      string nameTop = "D1_VISUAL_ZONE_" + IntegerToString(i) + "_TOP";
      string nameBot = "D1_VISUAL_ZONE_" + IntegerToString(i) + "_BOT";
      _SetOrCreateHLine(nameTop, vs.zones[i].upperBound, clrGold, 2, STYLE_SOLID, "D1 zone top");
      _SetOrCreateHLine(nameBot, vs.zones[i].lowerBound, clrGold, 2, STYLE_SOLID, "D1 zone bottom");

      string sideLabel = (vs.zones[i].midPoint <= visualPrice ? "BELOW_OR_NEAR" : "ABOVE_OR_NEAR");

      Print("[ZONE_DRAW_VISUAL] idx=", i,
            " side=", sideLabel,
            " id=", vs.zones[i].id,
            " tag=", vs.zones[i].structuralTag,
            " mid=", DoubleToString(vs.zones[i].midPoint, _Digits),
            " sourceTF=", EnumToString(vs.zones[i].sourceTF));
   }

   // Delete only stale extras after a valid set exists and after sticky preservation/merge
   for(int i = vs.count; i < 12; i++)
   {
      string staleMid = "D1_VISUAL_LINE_" + IntegerToString(i);
      string staleTop = "D1_VISUAL_ZONE_" + IntegerToString(i) + "_TOP";
      string staleBot = "D1_VISUAL_ZONE_" + IntegerToString(i) + "_BOT";
      if(ObjectFind(0, staleMid) >= 0) ObjectDelete(0, staleMid);
      if(ObjectFind(0, staleTop) >= 0) ObjectDelete(0, staleTop);
      if(ObjectFind(0, staleBot) >= 0) ObjectDelete(0, staleBot);
   }

   g_lastDrawnVisualD1 = vs;
   g_lastDrawnVisualValid = (vs.count > 0);

   // STEP 5: Draw rectangles for active Supply/Demand zones when enabled
   if(InpUseSupplyDemandZones && InpSDShowOnlyActivePair)
   {
      // Delete old objects for zones not to be drawn
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         if(!SDShouldDrawZone(g_zoneReg.zones[i]))
            _DeleteZoneObjectsById(g_zoneReg.zones[i].id);
      }

      // Draw active zones using _DrawOneZone
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         if(!g_zoneReg.zones[i].active || g_zoneReg.zones[i].broken)
            continue;

         if(!SDShouldDrawZone(g_zoneReg.zones[i]))
            continue;

         _DrawOneZone(g_zoneReg.zones[i]);
      }

      _CleanOrphanedObjects();

      Print("[SD_RECTANGLE_DRAW] active_demand_id=", g_activeDemandZoneId,
            " active_supply_id=", g_activeSupplyZoneId,
            " rectangles_drawn=true");
   }

   Print("[VISUAL_STYLE_APPLIED] simple_hlines=true labels=false nearest6x2=true maxLines=12 allTF=true");
   ChartRedraw(0);
}

void _DrawSimplifiedZone(const ZoneInfo &z, bool isSupport, bool isSecondary)
{
   string nameTop, nameBot, nameMid;
   
   if(isSecondary)
   {
      nameTop = isSupport ? "ZONE_LOWER_BACKUP_TOP" : "ZONE_UPPER_BACKUP_TOP";
      nameBot = isSupport ? "ZONE_LOWER_BACKUP_BOTTOM" : "ZONE_UPPER_BACKUP_BOTTOM";
      nameMid = isSupport ? "ZONE_LOWER_BACKUP_MID" : "ZONE_UPPER_BACKUP_MID";
   }
   else
   {
      nameTop = isSupport ? "ZONE_LOWER_ACTIVE_TOP" : "ZONE_UPPER_ACTIVE_TOP";
      nameBot = isSupport ? "ZONE_LOWER_ACTIVE_BOTTOM" : "ZONE_UPPER_ACTIVE_BOTTOM";
      nameMid = isSupport ? "ZONE_LOWER_ACTIVE_MID" : "ZONE_UPPER_ACTIVE_MID";
   }

   // Determine line style based on zone properties
   color lineColor;
   int lineWidth;
   ENUM_LINE_STYLE lineStyle;

   bool isBull = IsVisualBullRole(z);
   bool isKey  = z.protectedKeyZone;
   bool isFlip = z.isFlipZone;
   bool isMajor = (z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_RESISTANCE_MAJOR);

   if(isSecondary)
   {
      lineColor = isBull ? (color)C'0,150,50' : (color)C'200,80,0';
      lineWidth = 1;
      lineStyle = STYLE_DASH;
   }
   else if(z.isPrimary && z.structuralAnchor)
   {
      lineColor = isBull ? (color)clrLime : (color)clrOrangeRed;
      lineWidth = 3;
      lineStyle = STYLE_SOLID;
   }
   else if(z.isBackup && z.structuralAnchor)
   {
      lineColor = isBull ? (color)C'0,210,80' : (color)C'255,100,0';
      lineWidth = 2;
      lineStyle = STYLE_SOLID;
   }
   else if(isFlip)
   {
      lineColor = isBull ? (color)C'0,190,190' : (color)C'255,140,0';
      lineWidth = isKey ? 2 : 1;
      lineStyle = STYLE_DASH;
   }
   else if(isMajor)
   {
      lineColor = isBull ? (color)clrLime : (color)clrOrangeRed;
      lineWidth = isKey ? 3 : 2;
      lineStyle = STYLE_SOLID;
   }
   else
   {
      lineColor = isBull ? (color)clrGreen : (color)clrRed;
      lineWidth = 1;
      lineStyle = STYLE_SOLID;
   }

   // Draw upper boundary
   _SetOrCreateHLine(nameTop, z.upperBound, lineColor, lineWidth, lineStyle, "");
   
   // Draw lower boundary  
   _SetOrCreateHLine(nameBot, z.lowerBound, lineColor, lineWidth, lineStyle, "");
   
   // Zone-first visual model: midpoint is internal only.
   if(ObjectFind(0, nameMid) >= 0)
      ObjectDelete(0, nameMid);

   Print("[ZONE_DRAW_SIMPLE] isSupport=", isSupport,
         " upper=", DoubleToString(z.upperBound, _Digits),
         " lower=", DoubleToString(z.lowerBound, _Digits),
         " midpoint_internal_only=", DoubleToString(z.midPoint, _Digits));
}

void ClearZoneLines()
{
   for(int i = 0; i < 12; i++)
   {
      string nameMid = "D1_VISUAL_LINE_" + IntegerToString(i);          // legacy midpoint
      string nameTop = "D1_VISUAL_ZONE_" + IntegerToString(i) + "_TOP";
      string nameBot = "D1_VISUAL_ZONE_" + IntegerToString(i) + "_BOT";
      if(ObjectFind(0, nameMid) >= 0) ObjectDelete(0, nameMid);
      if(ObjectFind(0, nameTop) >= 0) ObjectDelete(0, nameTop);
      if(ObjectFind(0, nameBot) >= 0) ObjectDelete(0, nameBot);
   }

   // clear legacy objects only
   string legacy[] =
   {
      "ZONE_LOWER_ACTIVE_TOP","ZONE_LOWER_ACTIVE_BOTTOM","ZONE_LOWER_ACTIVE_MID",
      "ZONE_UPPER_ACTIVE_TOP","ZONE_UPPER_ACTIVE_BOTTOM","ZONE_UPPER_ACTIVE_MID",
      "ZONE_LOWER_BACKUP_TOP","ZONE_LOWER_BACKUP_BOTTOM","ZONE_LOWER_BACKUP_MID",
      "ZONE_UPPER_BACKUP_TOP","ZONE_UPPER_BACKUP_BOTTOM","ZONE_UPPER_BACKUP_MID"
   };

   for(int i = 0; i < ArraySize(legacy); i++)
   {
      if(ObjectFind(0, legacy[i]) >= 0)
         ObjectDelete(0, legacy[i]);
   }

   g_lastDrawnVisualValid = false;
}

//+------------------------------------------------------------------+
//| PRIMARY ZONE SYSTEM - ARCHITECTURE FIX                             |
//+------------------------------------------------------------------+

bool IsSupportStructurallyValid(const ZoneInfo &z)
{
   if(!z.valid) return false;
   if(z.structuralTag == "HH" || z.structuralTag == "LH") return false;
   return true;
}

bool IsResistanceStructurallyValid(const ZoneInfo &z)
{
   if(!z.valid) return false;
   if(z.structuralTag == "HL" || z.structuralTag == "LL") return false;
   return true;
}

bool ZoneEligibleAsSupportHere(const ZoneInfo &z, double price, double atr)
{
   double tol = MathMax(atr * 0.30, _Point * 16.0);

   if(!z.valid || !z.active || z.broken)
      return false;

   bool allowHistorical =
      (z.historical &&
       (z.qualityScore >= MathMax(ZoneWeakRejectThreshold, 2.5) ||
        z.structuralAnchor || z.isFlipZone || z.protectedKeyZone));

   if(z.historical && !allowHistorical)
      return false;

   if(!IsSupportStructurallyValid(z))
      return false;

   if(z.lowerBound > price + tol)
      return false;

   bool continuationLike =
      (z.strategyRole == ZROLE_TREND_CONTINUATION ||
       z.structuralTag == "HL" ||
       z.structuralTag == "LH");

   double minQual =
      continuationLike
      ? MathMax(2.5, ZoneWeakRejectThreshold - 0.50)
      : MathMax(2.75, ZoneWeakRejectThreshold);

   if(z.qualityScore < minQual && !allowHistorical)
      return false;

   return true;
}

bool ZoneEligibleAsResistanceHere(const ZoneInfo &z, double price, double atr)
{
   double tol = MathMax(atr * 0.30, _Point * 16.0);

   if(!z.valid || !z.active || z.broken)
      return false;

   bool allowHistorical =
      (z.historical &&
       (z.qualityScore >= MathMax(ZoneWeakRejectThreshold, 2.5) ||
        z.structuralAnchor || z.isFlipZone || z.protectedKeyZone));

   if(z.historical && !allowHistorical)
      return false;

   if(!IsResistanceStructurallyValid(z))
      return false;

   if(z.upperBound < price - tol)
      return false;

   bool continuationLike =
      (z.strategyRole == ZROLE_TREND_CONTINUATION ||
       z.structuralTag == "LH" ||
       z.structuralTag == "HL");

   double minQual =
      continuationLike
      ? MathMax(2.5, ZoneWeakRejectThreshold - 0.50)
      : MathMax(2.75, ZoneWeakRejectThreshold);

   if(z.qualityScore < minQual && !allowHistorical)
      return false;

   return true;
}

double ScorePrimaryCandidate(const ZoneInfo &z, bool wantSupport, double price, double atr)
{
   double safeAtr  = MathMax(atr, _Point * 10.0);
   double distATR  = MathAbs(z.midPoint - price) / safeAtr;
   double widthATR = (z.upperBound - z.lowerBound) / safeAtr;

   double score = ComputePrimaryRelevance(z, price, atr);

   bool structuralSupport    = (z.structuralTag == "HL" || z.structuralTag == "LL");
   bool structuralResistance = (z.structuralTag == "LH" || z.structuralTag == "HH");
   bool protectedFallback    = (z.structuralAnchor || z.protectedKeyZone || z.isFlipZone || z.continuationEligible);

   if(wantSupport)
   {
      if(!ZoneEligibleAsSupportHere(z, price, atr)) return -DBL_MAX;

      // RELAXED: Allow SUPPORT_MINOR zones, not just structural/protected/DEMAND
      if(!structuralSupport && !protectedFallback && z.type != ZONE_DEMAND && z.type != ZONE_SUPPORT_MINOR)
         return -DBL_MAX;

      if(z.structuralTag == "HL")       score += 2.10;
      else if(z.structuralTag == "LL")  score += 1.50;
      else                              score -= 0.50;  // RELAXED: Reduced from -2.25 to -0.50

      if(z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_DEMAND)
         score += 0.55;
      else if(z.type == ZONE_SUPPORT_MINOR)
         score += 0.25;  // RELAXED: Add small bonus for minor support
   }
   else
   {
      if(!ZoneEligibleAsResistanceHere(z, price, atr)) return -DBL_MAX;

      // RELAXED: Allow RESISTANCE_MINOR zones, not just structural/protected/SUPPLY
      if(!structuralResistance && !protectedFallback && z.type != ZONE_SUPPLY && z.type != ZONE_RESISTANCE_MINOR)
         return -DBL_MAX;

      if(z.structuralTag == "LH")       score += 2.10;
      else if(z.structuralTag == "HH")  score += 1.50;
      else                              score -= 0.50;  // RELAXED: Reduced from -2.25 to -0.50

      if(z.type == ZONE_RESISTANCE_MAJOR || z.type == ZONE_SUPPLY)
         score += 0.55;
      else if(z.type == ZONE_RESISTANCE_MINOR)
         score += 0.25;  // RELAXED: Add small bonus for minor resistance
   }

   if(z.cleanTouchCount >= 3)  score += 0.60;

   if(widthATR > 0.55)
      score -= ((widthATR - 0.55) * 2.00 + 0.75);

   if(distATR > 1.50)
      score -= (distATR - 1.50) * 1.10;

   // PATCH 15: Replace primary scoring to use qualityScore
   score += z.qualityScore * 0.60;

   if(z.majorQualified)
      score += 1.00;

   // PATCH 7: Reduce penalty for continuation zones, add bonus
   bool continuationLike =
      (z.strategyRole == ZROLE_TREND_CONTINUATION ||
       z.structuralTag == "HL" ||
       z.structuralTag == "LH");

   if(z.qualityScore < 5.0)
      score -= continuationLike ? 0.75 : 2.50;

   if(continuationLike)
      score += 0.60;

   return score;
}

bool IsPhotoTradableZone(const ZoneInfo &z)
{
   if(!z.valid || !z.active)
      return false;

   if(!UsePhotoZoneFilterEffective())
      return (z.qualityScore >= ZoneWeakThresholdEffective());

   if(z.majorQualified)
      return true;

   if(z.qualityChecklistHits >= ZoneMinimumChecklistHitsEffective() &&
      z.qualityScore >= ZoneMajorThresholdEffective())
      return true;

   return false;
}

bool FindPrimarySideFallback(bool wantSupport, double price, double atr, const int excludeId, ZoneInfo &outZone)
{
   double safeAtr = MathMax(atr, _Point * 10.0);
   double bestScore = -DBL_MAX;
   bool found = false;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.valid || !z.active || z.broken)
         continue;
      if(z.id == excludeId)
         continue;

      if(!IsPhotoTradableZone(z) && !z.protectedKeyZone && !z.structuralAnchor && !z.isFlipZone)
         continue;

      bool allowHistorical =
         (z.historical &&
          (z.qualityScore >= MathMax(ZoneWeakThresholdEffective(), 2.5) ||
           z.structuralAnchor || z.isFlipZone || z.protectedKeyZone));

      if(z.historical && !allowHistorical)
         continue;

      bool correctSide =
         wantSupport
         ? (z.midPoint < price - safeAtr * 0.10)
         : (z.midPoint > price + safeAtr * 0.10);

      if(!correctSide)
         continue;

      bool structuralSupport =
         (z.structuralTag == "HL" || z.structuralTag == "LL" ||
          z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_DEMAND ||
          z.structuralAnchor || z.protectedKeyZone ||
          (z.isFlipZone && z.midPoint < price));

      bool structuralResistance =
         (z.structuralTag == "LH" || z.structuralTag == "HH" ||
          z.type == ZONE_RESISTANCE_MAJOR || z.type == ZONE_SUPPLY ||
          z.structuralAnchor || z.protectedKeyZone ||
          (z.isFlipZone && z.midPoint > price));

      if(wantSupport && !structuralSupport)
         continue;
      if(!wantSupport && !structuralResistance)
         continue;

      // NEW: reject weak fallback zones unless they are strongly protected / structural
      bool protectedException = (z.structuralAnchor || z.protectedKeyZone || z.isFlipZone);
      double minFallbackQual = wantSupport ? 1.80 : 2.25;

      if(z.qualityScore < minFallbackQual && !protectedException)
         continue;

      double distATR = MathAbs(z.midPoint - price) / safeAtr;
      if(distATR > 5.0)
         continue;

      double score = SafePrimaryScoreValue(z, wantSupport, price, atr);

      if(score <= -9998.0 && !protectedException)
         continue;

      score += z.strength * 0.20;
      score += (z.structuralAnchor ? 0.55 : 0.0);
      score += (z.protectedKeyZone ? 0.45 : 0.0);
      score += (z.isFlipZone ? 0.35 : 0.0);
      score += (allowHistorical ? 0.15 : 0.0);
      score -= MathMax(0.0, distATR - 1.25) * 0.35;

      if(!found || score > bestScore)
      {
         outZone = z;
         bestScore = score;
         found = true;
      }
   }

   return found;
}

bool FindNearestOppositeTargetZone(bool wantResistance, double price, double atr, ZoneInfo &outZone)
{
   double bestDist = DBL_MAX;
   bool found = false;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.valid || !z.active || z.historical || z.broken)
         continue;

      ZONE_CANONICAL_ROLE role = ResolveZoneRole(z, price, atr);

      if(wantResistance)
      {
         if(role != ZROLE_RESISTANCE) continue;
         if(z.midPoint <= price) continue;
      }
      else
      {
         if(role != ZROLE_SUPPORT) continue;
         if(z.midPoint >= price) continue;
      }

      double dist = MathAbs(z.midPoint - price);
      if(dist < bestDist)
      {
         bestDist = dist;
         outZone = z;
         found = true;
      }
   }

   return found;
}

void SanitizePrimaryZones(PrimaryZones &pz, double price, double atr)
{
   // 1) Basic validation
   if(pz.hasSupport)
   {
      if(!ZoneEligibleAsSupportHere(pz.support, price, atr))
      {
         Print("[ZONE_SUPPORT_INVALID] id=", pz.support.id,
               " tag=", pz.support.structuralTag,
               " low=", DoubleToString(pz.support.lowerBound, _Digits),
               " high=", DoubleToString(pz.support.upperBound, _Digits),
               " price=", DoubleToString(price, _Digits));
         pz.hasSupport = false;
      }
   }

   if(pz.hasResistance)
   {
      if(!ZoneEligibleAsResistanceHere(pz.resistance, price, atr))
      {
         Print("[ZONE_RESIST_INVALID] id=", pz.resistance.id,
               " tag=", pz.resistance.structuralTag,
               " low=", DoubleToString(pz.resistance.lowerBound, _Digits),
               " high=", DoubleToString(pz.resistance.upperBound, _Digits),
               " price=", DoubleToString(price, _Digits));
         pz.hasResistance = false;
      }
   }

   // 2) Backfill missing side
   if(!pz.hasSupport)
   {
      ZoneInfo fb;
      if(FindPrimarySideFallback(true, price, atr, pz.hasResistance ? pz.resistance.id : -1, fb))
      {
         bool strongEnough =
            (fb.qualityScore >= 1.80 ||
             fb.structuralAnchor || fb.protectedKeyZone || fb.isFlipZone);

         if(strongEnough)
         {
            pz.support = fb;
            pz.hasSupport = true;
            Print("[PRIMARY_BACKFILL] side=support id=", fb.id,
                  " tag=", fb.structuralTag,
                  " mid=", DoubleToString(fb.midPoint, _Digits));
         }
         else
         {
            Print("[PRIMARY_BACKFILL_REJECTED] side=support id=", fb.id,
                  " quality=", DoubleToString(fb.qualityScore, 2));
         }
      }
   }

   if(!pz.hasResistance)
   {
      ZoneInfo fb;
      if(FindPrimarySideFallback(false, price, atr, pz.hasSupport ? pz.support.id : -1, fb))
      {
         bool strongEnough =
            (fb.qualityScore >= 2.25 ||
             fb.structuralAnchor || fb.protectedKeyZone || fb.isFlipZone);

         if(strongEnough)
         {
            pz.resistance = fb;
            pz.hasResistance = true;
            Print("[PRIMARY_BACKFILL] side=resistance id=", fb.id,
                  " tag=", fb.structuralTag,
                  " mid=", DoubleToString(fb.midPoint, _Digits));
         }
         else
         {
            Print("[PRIMARY_BACKFILL_REJECTED] side=resistance id=", fb.id,
                  " quality=", DoubleToString(fb.qualityScore, 2));
         }
      }
   }

   // 3) Backfill opposite target based on trend bias
   int trendBias = GetZoneTrendBias();

   if(trendBias == 1 && pz.hasSupport && !pz.hasResistance)
   {
      ZoneInfo target;
      if(FindNearestOppositeTargetZone(true, price, atr, target))
      {
         pz.resistance = target;
         pz.hasResistance = true;
         Print("[PRIMARY_TARGET_BACKFILL] side=resistance id=", target.id,
               " mid=", DoubleToString(target.midPoint, _Digits));
      }
   }

   if(trendBias == -1 && pz.hasResistance && !pz.hasSupport)
   {
      ZoneInfo target;
      if(FindNearestOppositeTargetZone(false, price, atr, target))
      {
         pz.support = target;
         pz.hasSupport = true;
         Print("[PRIMARY_TARGET_BACKFILL] side=support id=", target.id,
               " mid=", DoubleToString(target.midPoint, _Digits));
      }
   }

   // 4) Fix crossed pair by keeping stronger side and recovering the other
   if(pz.hasSupport && pz.hasResistance && pz.support.midPoint >= pz.resistance.midPoint)
   {
      double supScore = ScorePrimaryCandidate(pz.support, true,  price, atr);
      double resScore = ScorePrimaryCandidate(pz.resistance, false, price, atr);

      Print("[ZONE_CROSS_ERROR] supportId=", pz.support.id,
            " resistanceId=", pz.resistance.id,
            " supScore=", DoubleToString(supScore, 2),
            " resScore=", DoubleToString(resScore, 2));

      if(supScore >= resScore)
      {
         int keepId = pz.support.id;
         pz.hasResistance = false;

         ZoneInfo fb;
         if(FindPrimarySideFallback(false, price, atr, keepId, fb) && fb.midPoint > pz.support.midPoint)
         {
            pz.resistance = fb;
            pz.hasResistance = true;
            Print("[PRIMARY_RECOVER] side=resistance id=", fb.id,
                  " tag=", fb.structuralTag,
                  " mid=", DoubleToString(fb.midPoint, _Digits));
         }
      }
      else
      {
         int keepId = pz.resistance.id;
         pz.hasSupport = false;

         ZoneInfo fb;
         if(FindPrimarySideFallback(true, price, atr, keepId, fb) && fb.midPoint < pz.resistance.midPoint)
         {
            pz.support = fb;
            pz.hasSupport = true;
            Print("[PRIMARY_RECOVER] side=support id=", fb.id,
                  " tag=", fb.structuralTag,
                  " mid=", DoubleToString(fb.midPoint, _Digits));
         }
      }
   }

   // 4) Final hard validation using edge-aware helpers
   if(pz.hasSupport && !ZoneEligibleAsSupportHere(pz.support, price, atr))
   {
      Print("[ZONE_SUPPORT_INVALID_FINAL] id=", pz.support.id,
            " tag=", pz.support.structuralTag,
            " low=", DoubleToString(pz.support.lowerBound, _Digits),
            " high=", DoubleToString(pz.support.upperBound, _Digits),
            " quality=", DoubleToString(pz.support.qualityScore, 2),
            " price=", DoubleToString(price, _Digits));
      pz.hasSupport = false;
   }

   if(pz.hasResistance && !ZoneEligibleAsResistanceHere(pz.resistance, price, atr))
   {
      Print("[ZONE_RESIST_INVALID_FINAL] id=", pz.resistance.id,
            " tag=", pz.resistance.structuralTag,
            " low=", DoubleToString(pz.resistance.lowerBound, _Digits),
            " high=", DoubleToString(pz.resistance.upperBound, _Digits),
            " quality=", DoubleToString(pz.resistance.qualityScore, 2),
            " price=", DoubleToString(price, _Digits));
      pz.hasResistance = false;
   }

   if(pz.hasSupport && pz.hasResistance && pz.support.midPoint >= pz.resistance.midPoint)
   {
      double supScore = ScorePrimaryCandidate(pz.support, true, price, atr);
      double resScore = ScorePrimaryCandidate(pz.resistance, false, price, atr);

      if(supScore >= resScore)
      {
         pz.hasResistance = false;
         Print("[ZONE_FINAL_REPAIR] kept=support id=", pz.support.id);
      }
      else
      {
         pz.hasSupport = false;
         Print("[ZONE_FINAL_REPAIR] kept=resistance id=", pz.resistance.id);
      }
   }
}

PrimaryZones BuildPrimaryZonesFromRegistry(double price, double atr)
{
   PrimaryZones result;
   result.hasSupport = false;
   result.hasResistance = false;

   if(price <= 0.0 || atr <= 0.0)
      return result;

   ZoneInfo supportZone, resistanceZone;
   bool hasSupport = false, hasResistance = false;

   if(!SelectPrimaryZonePair(price, atr, supportZone, resistanceZone, hasSupport, hasResistance))
   {
      Print("[PRIMARY_ZONES] support=NO resistance=NO supportTag=NONE resistanceTag=NONE supportMid=NONE resistanceMid=NONE");
      return result;
   }

   if(hasSupport)
   {
      result.support = supportZone;
      result.hasSupport = true;
   }

   if(hasResistance)
   {
      result.resistance = resistanceZone;
      result.hasResistance = true;
   }

   SanitizePrimaryZones(result, price, atr);

   Print("[PRIMARY_ZONES] support=", result.hasSupport ? "YES" : "NO",
         " resistance=", result.hasResistance ? "YES" : "NO",
         " supportTag=", result.hasSupport ? result.support.structuralTag : "NONE",
         " resistanceTag=", result.hasResistance ? result.resistance.structuralTag : "NONE",
         " supportMid=", result.hasSupport ? DoubleToString(result.support.midPoint, _Digits) : "NONE",
         " resistanceMid=", result.hasResistance ? DoubleToString(result.resistance.midPoint, _Digits) : "NONE");

   return result;
}

PrimaryZones GetPrimaryZones(double price, double atr)
{
    PrimaryZones result;
    result.hasSupport = false;
    result.hasResistance = false;

    double localBestSupportScore    = -DBL_MAX;
    double localBestResistanceScore = -DBL_MAX;
    double bestSupportDist     = DBL_MAX;
    double bestResistanceDist  = DBL_MAX;

    if(price <= 0.0 || atr <= 0.0)
    {
        Print("[PRIMARY_ZONES] invalid_input price=", DoubleToString(price, _Digits),
              " atr=", DoubleToString(atr, _Digits));
        return result;
    }

    double safeAtr = MathMax(atr, _Point * 10.0);
    int trendBias = GetZoneTrendBias();

    for(int i = 0; i < g_zoneReg.count; i++)
    {
        ZoneInfo z = g_zoneReg.zones[i];
        // RELAXED: Allow historical zones if they are protected key zones
        if(!z.valid || !z.active || (z.historical && !z.protectedKeyZone) || z.broken)
            continue;

        ZONE_CANONICAL_ROLE role = ResolveZoneRole(z, price, atr);
        // RELAXED: Allow ZROLE_UNKNOWN zones to be considered with lower priority
        // if(role == ZROLE_UNKNOWN)
        //     continue;

        double distATR = MathAbs(z.midPoint - price) / safeAtr;
        // RELAXED: Increase distance threshold from 2.75 to 4.0 ATR
        if(distATR > 4.0)
            continue;

        // RELAXED: Remove strict trend bias filtering - allow all zones to be scored
        bool isTrendContinuationZone = (z.strategyRole == ZROLE_TREND_CONTINUATION);

        if(role == ZROLE_SUPPORT || role == ZROLE_UNKNOWN)
        {
            // RELAXED: Remove heavy penalty for non-continuation zones
            double score = ScorePrimaryCandidate(z, true, price, atr);
            if(score == -DBL_MAX) continue;

            // Small preference for continuation zones but not a hard penalty
            if(trendBias == 1 && isTrendContinuationZone)
                score += 0.50;

            if(score > localBestSupportScore ||
               (MathAbs(score - localBestSupportScore) < 1e-6 && distATR < bestSupportDist))
            {
                localBestSupportScore = score;
                bestSupportDist  = distATR;
                result.support   = z;
                result.hasSupport = true;
            }
        }
        else if(role == ZROLE_RESISTANCE)
        {
            // RELAXED: Remove heavy penalty for non-continuation zones
            double score = ScorePrimaryCandidate(z, false, price, atr);
            if(score == -DBL_MAX) continue;

            // Small preference for continuation zones but not a hard penalty
            if(trendBias == -1 && isTrendContinuationZone)
                score += 0.50;

            if(score > localBestResistanceScore ||
               (MathAbs(score - localBestResistanceScore) < 1e-6 && distATR < bestResistanceDist))
            {
                localBestResistanceScore = score;
                bestResistanceDist  = distATR;
                result.resistance   = z;
                result.hasResistance = true;
            }
        }
    }

    if(!result.hasSupport || !result.hasResistance)
    {
        Print("[PRIMARY_ZONE_MISSING] support=", result.hasSupport ? "true" : "false",
              " resistance=", result.hasResistance ? "true" : "false",
              " reason=no_candidate_or_filtered_out");
    }

    SanitizePrimaryZones(result, price, atr);

    Print("[PRIMARY_ZONES] support=", result.hasSupport ? "YES" : "NO",
          " resistance=", result.hasResistance ? "YES" : "NO",
          " supportTag=", result.hasSupport ? result.support.structuralTag : "NONE",
          " resistanceTag=", result.hasResistance ? result.resistance.structuralTag : "NONE",
          " supportMid=", result.hasSupport ? DoubleToString(result.support.midPoint, _Digits) : "NONE",
          " resistanceMid=", result.hasResistance ? DoubleToString(result.resistance.midPoint, _Digits) : "NONE");

    return result;
}

void LimitToPrimaryZonesOnly()
{
    // ARCHITECTURE FIX:
    // Do NOT mutate the working zone registry.
    // The full registry must stay intact for logic, targeting, fallback, and structure context.
    Print("[PRIMARY_LIMIT] visual_only=true registry_preserved count=", g_zoneReg.count);
}

//+------------------------------------------------------------------+
//| CORE ZONE SELECTION FIXES                                         |
//+------------------------------------------------------------------+

bool IsZoneValidForTrend(const ZoneInfo &z, int trend, double price)
{
    // BULL TREND
    if(trend == 1)
    {
        // ONLY allow HL / demand below price
        if(z.structuralTag == "HL" && z.midPoint < price)
            return true;
        if(z.type == ZONE_DEMAND && z.midPoint < price)
            return true;
    }

    // BEAR TREND
    if(trend == -1)
    {
        // ONLY allow LH / supply above price
        if(z.structuralTag == "LH" && z.midPoint > price)
            return true;
        if(z.type == ZONE_SUPPLY && z.midPoint > price)
            return true;
    }

    return false;
}

bool SelectZonesStrict(ZoneInfo &upper, ZoneInfo &lower, int trend, double price)
{
    double bestUpperDist = DBL_MAX;
    double bestLowerDist = DBL_MAX;

    bool foundUpper = false;
    bool foundLower = false;

    for(int i=0; i<g_zoneReg.count; i++)
    {
        ZoneInfo z = g_zoneReg.zones[i];

        if(!z.valid || !ShouldDrawZoneVisual(z)) continue;

        // 🔥 STRUCTURE FILTER FIRST
        if(!IsZoneValidForTrend(z, trend, price))
            continue;

        // --- UPPER ZONE ---
        if(z.midPoint > price)
        {
            double dist = z.midPoint - price;

            if(dist < bestUpperDist)
            {
                bestUpperDist = dist;
                upper = z;
                foundUpper = true;
            }
        }

        // --- LOWER ZONE ---
        if(z.midPoint < price)
        {
            double dist = price - z.midPoint;

            if(dist < bestLowerDist)
            {
                bestLowerDist = dist;
                lower = z;
                foundLower = true;
            }
        }
    }

    // 🚫 prevent same zone being both
    if(foundUpper && foundLower && upper.id == lower.id)
    {
        Print("[ZONE_SELECT_STRICT] Same zone selected as both upper and lower - rejecting");
        return false;
    }

    return (foundUpper && foundLower);
}

bool IsZoneTooClose(const ZoneInfo &a, const ZoneInfo &b, double atr)
{
    double distance = MathAbs(a.midPoint - b.midPoint);

    return (distance < atr * 1.2); // adjust multiplier
}

//+------------------------------------------------------------------+
//| Legacy compatibility helpers                                     |
//+------------------------------------------------------------------+
bool IsFreshZoneInsideHistoricalZone(const ZoneInfo &fresh, const ZoneInfo &hist)
{
   return (fresh.lowerBound >= hist.lowerBound && fresh.upperBound <= hist.upperBound);
}

bool IsFreshZoneConfluentWithHistoricalZone(const ZoneInfo &fresh, const ZoneInfo &hist,
                                            double atrVal, double mult)
{
   double threshold = MathMax(atrVal * mult, 0.0001);
   if(MathAbs(fresh.midPoint - hist.midPoint) <= threshold) return true;
   return (fresh.lowerBound <= hist.upperBound && hist.lowerBound <= fresh.upperBound);
}

int GetBestHistoricalConfluenceZone(bool isBuy, double price, double atrVal,
                                    double confMult, ZoneInfo &outFresh, ZoneInfo &outHist)
{
   double bestScore = -1.0;
   int    bestHIdx  = -1;
   for(int f = 0; f < g_zoneReg.count; f++)
   {
      ZoneInfo fz = g_zoneReg.zones[f];
      if(!fz.active || fz.historical) continue;
      if(isBuy  && !IsBullishZone(fz.type)) continue;
      if(!isBuy && !IsBearishZone(fz.type)) continue;
      for(int h = 0; h < g_zoneReg.count; h++)
      {
         ZoneInfo hz = g_zoneReg.zones[h];
         if(!hz.historical) continue;
         if(isBuy  && !IsBullishZone(hz.type)) continue;
         if(!isBuy && !IsBearishZone(hz.type)) continue;
         if(!IsFreshZoneConfluentWithHistoricalZone(fz, hz, atrVal, confMult)) continue;
         double score = fz.strength + hz.strength;
         if(score > bestScore) { bestScore = score; bestHIdx = h; outFresh = fz; outHist = hz; }
      }
   }
   return bestHIdx;
}

//+------------------------------------------------------------------+
//| Zone merge side classification                                   |
//+------------------------------------------------------------------+
enum ENUM_MERGE_SIDE { MERGE_BULL, MERGE_BEAR, MERGE_NONE };

ENUM_MERGE_SIDE GetMergeSide(ENUM_ZONE_TYPE t, bool allowBullFamily, bool allowBearFamily)
{
   switch(t)
   {
      case ZONE_DEMAND:
         return MERGE_BULL;
      case ZONE_SUPPORT_MAJOR:
      case ZONE_SUPPORT_MINOR:
         return allowBullFamily ? MERGE_BULL : MERGE_NONE;
      case ZONE_SUPPLY:
         return MERGE_BEAR;
      case ZONE_RESISTANCE_MAJOR:
      case ZONE_RESISTANCE_MINOR:
         return allowBearFamily ? MERGE_BEAR : MERGE_NONE;
      default:
         return MERGE_NONE;
   }
}

bool CanMergeTypes(ENUM_ZONE_TYPE a, ENUM_ZONE_TYPE b,
                   bool allowBullFamily, bool allowBearFamily)
{
   ENUM_MERGE_SIDE sA = GetMergeSide(a, allowBullFamily, allowBearFamily);
   ENUM_MERGE_SIDE sB = GetMergeSide(b, allowBullFamily, allowBearFamily);
   if(sA == MERGE_NONE || sB == MERGE_NONE) return false;
   return (sA == sB);
}

ENUM_ZONE_TYPE PickStrongerType(ENUM_ZONE_TYPE a, ENUM_ZONE_TYPE b)
{
   return (GetZonePriority(a) >= GetZonePriority(b)) ? a : b;
}

//+------------------------------------------------------------------+
//| Merge two zones into result — force tradable family             |
//+------------------------------------------------------------------+
void MergeTwoZones(const ZoneInfo &a, const ZoneInfo &b, ZoneInfo &result)
{
   result.lowerBound = MathMin(a.lowerBound, b.lowerBound);
   result.upperBound = MathMax(a.upperBound, b.upperBound);
   result.midPoint   = (result.upperBound + result.lowerBound) / 2.0;
   result.cleanTouchCount = a.cleanTouchCount + b.cleanTouchCount;
   result.ageInBars  = MathMin(a.ageInBars, b.ageInBars);
   result.strength   = MathMax(a.strength, b.strength);
   result.active     = true;
   result.broken     = false;

   // Force tradable merged zone family - use SUPPORT/RESISTANCE (DEMAND/SUPPLY normalized)
   bool aBull = IsBullishZone(a.type);
   bool bBull = IsBullishZone(b.type);
   if(aBull && bBull)
      result.type = ZONE_SUPPORT_MAJOR;  // Merged bullish -> SUPPORT_MAJOR
   else if(!aBull && !bBull)
      result.type = ZONE_RESISTANCE_MAJOR;  // Merged bearish -> RESISTANCE_MAJOR
   else
      result.type = (GetZonePriority(a.type) >= GetZonePriority(b.type)) ? a.type : b.type;
}

//+------------------------------------------------------------------+
//| Consolidate overlapping same-side zones                          |
//| Call once per bar AFTER RefreshZones, BEFORE entry checks        |
//+------------------------------------------------------------------+
void ConsolidateOverlappingZones(const SymbolProfile &prof,
                                  int mergeDistPts, double minOverlapPct,
                                  int maxWidthPts,
                                  bool allowBullFamily, bool allowBearFamily)
{
   double mergeDist = mergeDistPts * prof.point;
   double maxWidth  = maxWidthPts  * prof.point;
   bool merged = true;

   while(merged)
   {
      merged = false;
      for(int i = 0; i < g_zoneReg.count && !merged; i++)
      {
         if(!g_zoneReg.zones[i].active) continue;

         for(int j = i + 1; j < g_zoneReg.count && !merged; j++)
         {
            if(!g_zoneReg.zones[j].active) continue;

            // Same-side check
            if(!CanMergeTypes(g_zoneReg.zones[i].type, g_zoneReg.zones[j].type,
                              allowBullFamily, allowBearFamily))
               continue;

            // Overlap or proximity check
            double overlapHi = MathMin(g_zoneReg.zones[i].upperBound, g_zoneReg.zones[j].upperBound);
            double overlapLo = MathMax(g_zoneReg.zones[i].lowerBound, g_zoneReg.zones[j].lowerBound);
            double overlap   = overlapHi - overlapLo;

            double wI = g_zoneReg.zones[i].upperBound - g_zoneReg.zones[i].lowerBound;
            double wJ = g_zoneReg.zones[j].upperBound - g_zoneReg.zones[j].lowerBound;
            double maxW = MathMax(wI, wJ);

            bool overlapOk = (maxW > 0 && overlap > 0 && overlap / maxW >= minOverlapPct);
            bool proximityOk = false;
            if(!overlapOk)
            {
               double gap = -overlap; // gap is positive when no overlap
               proximityOk = (gap >= 0 && gap <= mergeDist);
            }

            if(!overlapOk && !proximityOk) continue;

            // Width check
            double newHi = MathMax(g_zoneReg.zones[i].upperBound, g_zoneReg.zones[j].upperBound);
            double newLo = MathMin(g_zoneReg.zones[i].lowerBound, g_zoneReg.zones[j].lowerBound);
            double newWidth = newHi - newLo;

            if(maxWidth > 0 && newWidth > maxWidth)
            {
               Print("[ZONE_MERGE_SKIPPED] reason=TOO_WIDE width=",
                     DoubleToString(newWidth / prof.point, 0), "pts > max=", maxWidthPts, "pts");
               continue;
            }

            // Determine winner (higher score/strength)
            int winIdx = i, loseIdx = j;
            if(g_zoneReg.zones[j].strength > g_zoneReg.zones[i].strength)
               { winIdx = j; loseIdx = i; }

            // Pick stronger type
            ENUM_ZONE_TYPE mergedType = PickStrongerType(g_zoneReg.zones[i].type,
                                                          g_zoneReg.zones[j].type);
            string sideStr = IsBullishZone(mergedType) ? "BULL" : "BEAR";

            Print("[ZONE_MERGED] side=", sideStr,
                  " oldTypeA=", ZoneTypeToString(g_zoneReg.zones[i].type),
                  " oldTypeB=", ZoneTypeToString(g_zoneReg.zones[j].type),
                  " newType=", ZoneTypeToString(mergedType),
                  " high=", DoubleToString(newHi, prof.digits),
                  " low=", DoubleToString(newLo, prof.digits),
                  " widthPts=", DoubleToString(newWidth / prof.point, 0));

            // Apply merge to winner
            g_zoneReg.zones[winIdx].upperBound = NormalizeDouble(newHi, prof.digits);
            g_zoneReg.zones[winIdx].lowerBound = NormalizeDouble(newLo, prof.digits);
            g_zoneReg.zones[winIdx].midPoint   = NormalizeDouble((newHi + newLo) * 0.5, prof.digits);
            g_zoneReg.zones[winIdx].type        = mergedType;
            g_zoneReg.zones[winIdx].label       = ZoneTypeToString(mergedType);

            // Combine touches
            g_zoneReg.zones[winIdx].cleanTouchCount =
               MathMax(g_zoneReg.zones[winIdx].cleanTouchCount,
                       g_zoneReg.zones[loseIdx].cleanTouchCount);
            g_zoneReg.zones[winIdx].rawTouches +=
               g_zoneReg.zones[loseIdx].rawTouches;
            g_zoneReg.zones[winIdx].retestCount =
               MathMax(g_zoneReg.zones[winIdx].retestCount,
                       g_zoneReg.zones[loseIdx].retestCount);

            // Keep best scores
            if(g_zoneReg.zones[loseIdx].freshness > g_zoneReg.zones[winIdx].freshness)
               g_zoneReg.zones[winIdx].freshness = g_zoneReg.zones[loseIdx].freshness;
            if(g_zoneReg.zones[loseIdx].reactionScore > g_zoneReg.zones[winIdx].reactionScore)
               g_zoneReg.zones[winIdx].reactionScore = g_zoneReg.zones[loseIdx].reactionScore;
            if(g_zoneReg.zones[loseIdx].protectedKeyZone)
               g_zoneReg.zones[winIdx].protectedKeyZone = true;
            if(g_zoneReg.zones[loseIdx].hasRejection)
               g_zoneReg.zones[winIdx].hasRejection = true;
            if(g_zoneReg.zones[loseIdx].isBreakoutOrigin)
               g_zoneReg.zones[winIdx].isBreakoutOrigin = true;
            if(g_zoneReg.zones[loseIdx].isFlipZone)
               g_zoneReg.zones[winIdx].isFlipZone = true;

            // Newest age
            if(g_zoneReg.zones[loseIdx].ageInBars < g_zoneReg.zones[winIdx].ageInBars)
               g_zoneReg.zones[winIdx].ageInBars = g_zoneReg.zones[loseIdx].ageInBars;

            // Recalc strength
            g_zoneReg.zones[winIdx].strength = CalcZoneStrength(g_zoneReg.zones[winIdx]);
            g_zoneReg.zones[winIdx].score    = g_zoneReg.zones[winIdx].strength;
            g_zoneReg.zones[winIdx].valid    = (g_zoneReg.zones[winIdx].score >= ZM_MIN_VALID_SCORE
                                                && !g_zoneReg.zones[winIdx].broken
                                                && g_zoneReg.zones[winIdx].active);

            // Deactivate loser
            g_zoneReg.zones[loseIdx].active     = false;
            g_zoneReg.zones[loseIdx].historical = true;
            g_zoneReg.zones[loseIdx].parentZoneId = g_zoneReg.zones[winIdx].id;

            merged = true; // restart scan
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Post-merge deduplication pass                                    |
//| Removes nearby same-side duplicate active zones after all merges |
//+------------------------------------------------------------------+
void DeduplicateNearbyZones(double atrVal)
{
   if(atrVal <= 0) return;

   int removed = 0;
   int consolidated = 0;
   bool changed = true;

   while(changed)
   {
      changed = false;
      for(int i = 0; i < g_zoneReg.count && !changed; i++)
      {
         if(!g_zoneReg.zones[i].active || g_zoneReg.zones[i].historical) continue;

         for(int j = i + 1; j < g_zoneReg.count && !changed; j++)
         {
            if(!g_zoneReg.zones[j].active || g_zoneReg.zones[j].historical) continue;

            // C1: Guard against same-zone or duplicate-ID comparison
            if(i == j) continue;
            if(g_zoneReg.zones[i].id == g_zoneReg.zones[j].id) continue;

            // Same side check
            bool bothBull = IsBullishZone(g_zoneReg.zones[i].type) && IsBullishZone(g_zoneReg.zones[j].type);
            bool bothBear = IsBearishZone(g_zoneReg.zones[i].type) && IsBearishZone(g_zoneReg.zones[j].type);
            if(!bothBull && !bothBear) continue;

            // Patch 4: Preserve distinct structural sequence zones
            bool iProtected = IsProtectedStructuralSequence(g_zoneReg.zones[i]);
            bool jProtected = IsProtectedStructuralSequence(g_zoneReg.zones[j]);

            if(iProtected && jProtected)
            {
               int barGap  = MathAbs(g_zoneReg.zones[i].sourceBarIndex -
                                     g_zoneReg.zones[j].sourceBarIndex);
               bool sameTag = (g_zoneReg.zones[i].structuralTag ==
                                g_zoneReg.zones[j].structuralTag);
               if(barGap >= 1 || !sameTag)
               {
                  Print("[ZONE_DEDUP_SKIP_STRUCTURAL_PAIR] keep_both ids=",
                        g_zoneReg.zones[i].id, ",", g_zoneReg.zones[j].id,
                        " tags=", g_zoneReg.zones[i].structuralTag,
                        ",", g_zoneReg.zones[j].structuralTag);
                  continue;
               }
            }

            if(iProtected && !jProtected) continue;

            if(!iProtected && jProtected)
            {
               int tmp = i; i = j; j = tmp;
            }

            double midI = g_zoneReg.zones[i].midPoint;
            double midJ = g_zoneReg.zones[j].midPoint;
            double midDist = MathAbs(midI - midJ);

            double overlapHi = MathMin(g_zoneReg.zones[i].upperBound, g_zoneReg.zones[j].upperBound);
            double overlapLo = MathMax(g_zoneReg.zones[i].lowerBound, g_zoneReg.zones[j].lowerBound);
            double overlap   = overlapHi - overlapLo;
            double wMin      = MathMin(g_zoneReg.zones[i].upperBound - g_zoneReg.zones[i].lowerBound,
                                       g_zoneReg.zones[j].upperBound - g_zoneReg.zones[j].lowerBound);
            double overlapPct = (wMin > 0 && overlap > 0) ? overlap / wMin : 0.0;

            double edgeGap = (overlap < 0) ? -overlap : 0.0;

            // Hard guard: never merge 0%-overlap zones that are >0.25 ATR apart
            if(overlapPct <= 0.0 && midDist > atrVal * 0.25)
               continue;

            // Tighter dedup: require genuinely redundant overlap or very tight proximity with real overlap
            bool realOverlapMerge  = (overlapPct >= 0.50);              // was 0.35 — tightened
            bool veryTightMidMerge = (midDist <= atrVal * 0.25 && overlapPct > 0.0); // was 0.35 — tightened
            bool tightEdgeMerge    = (edgeGap > 0.0 && edgeGap <= atrVal * 0.20);   // was 0.35 — tightened
            bool shouldMerge = realOverlapMerge || veryTightMidMerge || tightEdgeMerge;

            if(!shouldMerge) continue;

            // Never dedup a narrow tradeable zone into a monster zone that's too wide
            // for active display. The narrow zone is what we actually trade at.
            double widthI_ATR = (atrVal > 0) ? (g_zoneReg.zones[i].upperBound - g_zoneReg.zones[i].lowerBound) / atrVal : 0;
            double widthJ_ATR = (atrVal > 0) ? (g_zoneReg.zones[j].upperBound - g_zoneReg.zones[j].lowerBound) / atrVal : 0;
            bool iWide = (widthI_ATR > SD_ACTIVE_MAX_WIDTH_ATR);
            bool jWide = (widthJ_ATR > SD_ACTIVE_MAX_WIDTH_ATR);
            if(iWide != jWide)
               continue;  // One is tradeable, one is structural context — don't merge

            // Keep the stronger zone, demote the weaker to historical
            int keepIdx = i, dropIdx = j;
            if(g_zoneReg.zones[j].strength > g_zoneReg.zones[i].strength ||
               (g_zoneReg.zones[j].strength == g_zoneReg.zones[i].strength &&
                g_zoneReg.zones[j].freshness > g_zoneReg.zones[i].freshness))
            {
               keepIdx = j; dropIdx = i;
            }

            Print("[ZONE_DEDUP] keep_id=", g_zoneReg.zones[keepIdx].id,
                  "(", ZoneTypeToString(g_zoneReg.zones[keepIdx].type), ")",
                  " drop_id=", g_zoneReg.zones[dropIdx].id,
                  "(", ZoneTypeToString(g_zoneReg.zones[dropIdx].type), ")",
                  " midDistATR=", DoubleToString(midDist / atrVal, 2),
                  " overlap=", DoubleToString(overlapPct * 100.0, 0), "%",
                  " reason=", (realOverlapMerge ? "real_overlap" : (veryTightMidMerge ? "tight_mid" : "tight_edge")));

            g_zoneReg.zones[dropIdx].active     = false;
            g_zoneReg.zones[dropIdx].historical = true;
            g_zoneReg.zones[dropIdx].parentZoneId = g_zoneReg.zones[keepIdx].id;
            consolidated++;
            changed = true;
         }
      }
   }

   // Count current active/historical
   int activeBull = 0, activeBear = 0, histCount = 0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(g_zoneReg.zones[i].historical)  { histCount++; continue; }
      if(!g_zoneReg.zones[i].active)     continue;
      if(IsBullishZone(g_zoneReg.zones[i].type)) activeBull++;
      if(IsBearishZone(g_zoneReg.zones[i].type)) activeBear++;
   }

   Print("[ZONE_POST_CLEANUP] activeBull=", activeBull,
         " activeBear=", activeBear,
         " historical=", histCount,
         " removed=", removed,
         " consolidated=", consolidated);
}

//+------------------------------------------------------------------+
//| Break+retest + continuation state detector                       |
//+------------------------------------------------------------------+
bool IsZoneBrokenWithConviction(const ZoneInfo &z, const double &close[], double atrVal, int shift = 1)
{
   if(atrVal <= 0) return false;
   double pad = atrVal * 0.15;
   if(IsSupportRole(z))
      return (close[shift] < z.lowerBound - pad);
   if(IsResistanceRole(z))
      return (close[shift] > z.upperBound + pad);
   return false;
}

bool IsValidRetestHold(const ZoneInfo &z, const double &open[], const double &high[],
                       const double &low[], const double &close[], double atrVal, int shift = 1)
{
   if(atrVal <= 0) return false;
   double pad = atrVal * 0.10;
   bool touches = (low[shift] <= z.upperBound + pad && high[shift] >= z.lowerBound - pad);
   if(!touches) return false;
   if(IsResistanceRole(z))
      return (close[shift] >= z.upperBound - pad);
   if(IsSupportRole(z))
      return (close[shift] <= z.lowerBound + pad);
   return false;
}

bool IsRetestRejectedInDirection(const ZoneInfo &z, const double &open[], const double &high[],
                                 const double &low[], const double &close[], int shift = 1)
{
   double body  = MathAbs(close[shift] - open[shift]);
   double range = high[shift] - low[shift];
   if(range <= 0) return false;
   double upperWick = high[shift] - MathMax(open[shift], close[shift]);
   double lowerWick = MathMin(open[shift], close[shift]) - low[shift];
   if(IsResistanceRole(z))
      return (lowerWick <= upperWick && close[shift] > open[shift]);
   if(IsSupportRole(z))
      return (upperWick >= lowerWick && close[shift] < open[shift]);
   return false;
}

void UpdateZoneReversalSignals(const double &open[], const double &high[],
                               const double &low[], const double &close[],
                               int bars, double atrVal)
{
   if(bars < 3 || atrVal <= 0) return;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active) continue;

      ZoneInfo z = g_zoneReg.zones[i];
      double score = 0.0;

      bool touchNear = PriceNearZone(close[1], z, atrVal, 0.20) ||
                       (high[1] >= z.lowerBound && low[1] <= z.upperBound);

      if(!touchNear)
      {
         g_zoneReg.zones[i].reversalCandidate = false;
         g_zoneReg.zones[i].reversalScore = 0.0;
         continue;
      }

      if(z.majorTFZone)          score += 2.0;
      if(z.hasRejection)         score += 1.5;
      if(z.rejectionScore > 0.50) score += 1.5;

      if(IsSupportRole(z))
      {
         bool sweepBelow = (low[1] < z.lowerBound - atrVal * 0.10 && close[1] > z.lowerBound);
         if(sweepBelow) score += 2.0;
      }
      else if(IsResistanceRole(z))
      {
         bool sweepAbove = (high[1] > z.upperBound + atrVal * 0.10 && close[1] < z.upperBound);
         if(sweepAbove) score += 2.0;
      }

      g_zoneReg.zones[i].reversalScore     = score;
      g_zoneReg.zones[i].reversalCandidate = (score >= 4.0);
   }
}

void DetectBreakRetestZones(const double &close[], const double &high[],
                            const double &low[], int bars, double atrVal)
{
   if(bars < 3 || atrVal <= 0) return;
   double pad = atrVal * 0.15;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].active) continue;
      if(!g_zoneReg.zones[i].broken) continue;

      double zHi = g_zoneReg.zones[i].upperBound;
      double zLo = g_zoneReg.zones[i].lowerBound;

      // For FLIP zones: use originalType to determine retest direction
      // originalType = what zone WAS before it flipped
      // - If originalType was RESISTANCE_MAJOR → broke upward → now support → bullish continuation
      // - If originalType was SUPPORT_MAJOR → broke downward → now resistance → bearish continuation
      bool isFlip = g_zoneReg.zones[i].isFlipZone;
      ENUM_ZONE_TYPE checkType = isFlip ? g_zoneReg.zones[i].originalType : g_zoneReg.zones[i].type;
      
      bool wasResistance = (checkType == ZONE_RESISTANCE_MAJOR || checkType == ZONE_RESISTANCE_MINOR);
      bool wasSupport    = (checkType == ZONE_SUPPORT_MAJOR || checkType == ZONE_SUPPORT_MINOR);

      // --- Resistance broken upward => now acting as support => bullish continuation ---
      // Retest from above: price pulls back to zone and holds above
      if(wasResistance)
      {
         bool priceAbove = (close[1] > zHi);  // Price is above zone (broke up)
         bool retestNow  = (low[1] <= zHi + pad && low[1] >= zLo - pad);  // Wick touched zone
         bool holdsAbove = (close[1] >= zLo);  // Closed above zone low (held as support)

         if(priceAbove && retestNow)
         {
            if(!g_zoneReg.zones[i].breakRetestReady)
            {
               g_zoneReg.zones[i].breakRetestReady = true;
               g_zoneReg.zones[i].breakBarIndex    = Bars(_Symbol, PERIOD_CURRENT);
               Print("[BREAK_RETEST] zone[", i, "] flip=", isFlip, " originalType=", ZoneTypeToString(checkType),
                     " | retest detected at ", DoubleToString(zHi, _Digits));
            }

            if(holdsAbove)
            {
               g_zoneReg.zones[i].confirmedRetest      = true;
               g_zoneReg.zones[i].continuationEligible = true;
               if(isFlip)
                  g_zoneReg.zones[i].flipRetestConfirmed = true;
               double cscore = 4.0;
               if(g_zoneReg.zones[i].majorTFZone) cscore += 1.0;
               if(g_zoneReg.zones[i].hasRejection) cscore += 0.5;
               if(isFlip) cscore += 1.0;  // Flip zone bonus
               g_zoneReg.zones[i].continuationScore = cscore;
               Print("[BREAK_RETEST_CONFIRMED] BUY zone[", i, "] flip=", isFlip,
                     " | held as support at ", DoubleToString(zHi, _Digits),
                     " | score=", DoubleToString(cscore, 1));
            }

            // Failed retest: closed back below zone entirely
            if(close[1] < zLo - pad)
            {
               g_zoneReg.zones[i].failedRetest          = true;
               g_zoneReg.zones[i].continuationEligible  = false;
               g_zoneReg.zones[i].continuationScore     = 0.0;
               Print("[BREAK_RETEST_FAILED] zone[", i, "] closed below zone — retest failed");
            }
         }
      }

      // --- Support broken downward => now acting as resistance => bearish continuation ---
      // Retest from below: price rallies back to zone and holds below
      else if(wasSupport)
      {
         bool priceBelow = (close[1] < zLo);  // Price is below zone (broke down)
         bool retestNow  = (high[1] >= zLo - pad && high[1] <= zHi + pad);  // Wick touched zone
         bool holdsBelow = (close[1] <= zHi);  // Closed below zone high (held as resistance)

         if(priceBelow && retestNow)
         {
            if(!g_zoneReg.zones[i].breakRetestReady)
            {
               g_zoneReg.zones[i].breakRetestReady = true;
               g_zoneReg.zones[i].breakBarIndex    = Bars(_Symbol, g_zoneTF);
               Print("[BREAK_RETEST] zone[", i, "] flip=", isFlip, " originalType=", ZoneTypeToString(checkType),
                     " | retest detected at ", DoubleToString(zLo, _Digits));
            }

            if(holdsBelow)
            {
               g_zoneReg.zones[i].confirmedRetest      = true;
               g_zoneReg.zones[i].continuationEligible = true;
               if(isFlip)
                  g_zoneReg.zones[i].flipRetestConfirmed = true;
               double cscore = 4.0;
               if(g_zoneReg.zones[i].majorTFZone) cscore += 1.0;
               if(g_zoneReg.zones[i].hasRejection) cscore += 0.5;
               if(isFlip) cscore += 1.0;  // Flip zone bonus
               g_zoneReg.zones[i].continuationScore = cscore;
               Print("[BREAK_RETEST_CONFIRMED] SELL zone[", i, "] flip=", isFlip,
                     " | held as resistance at ", DoubleToString(zLo, _Digits),
                     " | score=", DoubleToString(cscore, 1));
            }

            if(close[1] > zHi + pad)
            {
               g_zoneReg.zones[i].failedRetest          = true;
               g_zoneReg.zones[i].continuationEligible  = false;
               g_zoneReg.zones[i].continuationScore     = 0.0;
               Print("[BREAK_RETEST_FAILED] zone[", i, "] closed above zone — retest failed");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Inject zones from a secondary timeframe into shared registry    |
//| Call AFTER RefreshZones() — detection only, no maintenance pass |
//+------------------------------------------------------------------+
void RefreshZonesForTF(ENUM_TIMEFRAMES tf, const IndicatorState &ind,
                       const SymbolProfile &prof, int mergePoints = 150)
{
   ENUM_TIMEFRAMES prevTF = g_zoneTF;
   g_zoneTF = tf;

   int scanBars = g_zoneReg.initialized ? ZM_FRESH_BARS : ZM_HISTORY_BARS;

   double histHigh[], histLow[], histClose[];
   int copied = CopyHigh(_Symbol, tf, 0, scanBars, histHigh);
   int minNeeded = g_zoneReg.initialized ? (g_zoneSwingLookback * 2 + 3) : 50;
   if(copied < minNeeded)
   {
      Print("ZONE_INJECT: Not enough ", EnumToString(tf), " bars (", copied, ")");
      g_zoneTF = prevTF;
      return;
   }

   int cL = CopyLow  (_Symbol, tf, 0, scanBars, histLow);
   int cC = CopyClose(_Symbol, tf, 0, scanBars, histClose);
   int bars = (int)MathMin(copied, MathMin(cL, cC));
   if(bars < g_zoneSwingLookback * 2 + 3)
   {
      g_zoneTF = prevTF;
      return;
   }

   double atrVal    = GetATR(ind, 1);
   double atrRefVal  = GetATRRef(ind, 1);
   if(atrVal    <= 0) atrVal    = prof.defaultSLBufferPoints * prof.point * 2.0;
   if(atrRefVal <= 0) atrRefVal = atrVal;
   g_atrScale = (atrVal > 0) ? (atrRefVal / atrVal) : 1.0;
   double mergePrice = MathMax(mergePoints * prof.point, atrVal * (1.0 * g_atrScale));

   DetectSwingHighs(histHigh, histLow, histClose, bars, g_zoneSwingLookback, prof, atrVal);
   DetectSwingLows (histHigh, histLow, histClose, bars, g_zoneSwingLookback, prof, atrVal);
   StampTrendStructureZones(prof, atrVal);

   // Step 2-4: merge overlapping + edge-gap <= ATR, repeat until convergence
   MergePass(mergePrice);

   // Step 5: rank zones (must happen before eviction so scores are fresh)
   ClassifyKeyZones();
   for(int i = 0; i < g_zoneReg.count; i++)
      UpdateZoneScoreAndValid(i);

   // Step 6: keep top 3 support + top 3 resistance (proximity-weighted)
   EvictExcessByDirection(histClose[0], atrVal);
   CleanupHistoricalZones();

   g_zoneTF = prevTF;

   Print("ZONE_INJECT [", EnumToString(tf), "]: active=", CountActiveZones(),
         " historical=", CountHistoricalZones(), " total=", g_zoneReg.count);
}

//+------------------------------------------------------------------+
//| Zone extreme helpers for zone-to-zone SL/TP (Part A)            |
//+------------------------------------------------------------------+
double GetZoneExtremeLow(int zoneIdx)
{
   if(zoneIdx < 0 || zoneIdx >= g_zoneReg.count) return 0.0;
   return g_zoneReg.zones[zoneIdx].lowerBound;
}

double GetZoneExtremeHigh(int zoneIdx)
{
   if(zoneIdx < 0 || zoneIdx >= g_zoneReg.count) return 0.0;
   return g_zoneReg.zones[zoneIdx].upperBound;
}

bool FindNextResistanceZoneAbove(double price, double atrVal,
                                  int &zoneIdx, double &zoneLow, double &zoneHigh)
{
   zoneIdx  = -1;
   zoneLow  = 0.0;
   zoneHigh = 0.0;
   double minGap   = (atrVal > 0) ? atrVal * 0.5 : _Point * 50;
   double bestDist = 999999.0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.broken || z.historical) continue;
      if(!IsBearishZone(z.type))               continue;
      if(!z.valid || z.score < ZM_MIN_VALID_SCORE) continue;
      if(z.lowerBound < price + minGap) continue;
      double dist = z.lowerBound - price;
      if(dist < bestDist) { bestDist = dist; zoneIdx = i; zoneLow = z.lowerBound; zoneHigh = z.upperBound; }
   }
   if(zoneIdx >= 0)
      Print("[ZONE_TARGET_FOUND] resistance zone[", zoneIdx, "] low=",
            DoubleToString(zoneLow, _Digits), " high=", DoubleToString(zoneHigh, _Digits));
   return (zoneIdx >= 0);
}

bool FindNextSupportZoneBelow(double price, double atrVal,
                               int &zoneIdx, double &zoneLow, double &zoneHigh)
{
   zoneIdx  = -1;
   zoneLow  = 0.0;
   zoneHigh = 0.0;
   double minGap   = (atrVal > 0) ? atrVal * 0.5 : _Point * 50;
   double bestDist = 999999.0;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.broken || z.historical) continue;
      if(!IsBullishZone(z.type))               continue;
      if(!z.valid || z.score < ZM_MIN_VALID_SCORE) continue;
      if(z.upperBound > price - minGap) continue;
      double dist = price - z.upperBound;
      if(dist < bestDist) { bestDist = dist; zoneIdx = i; zoneLow = z.lowerBound; zoneHigh = z.upperBound; }
   }
   if(zoneIdx >= 0)
      Print("[ZONE_TARGET_FOUND] support zone[", zoneIdx, "] low=",
            DoubleToString(zoneLow, _Digits), " high=", DoubleToString(zoneHigh, _Digits));
   return (zoneIdx >= 0);
}

//+------------------------------------------------------------------+
//| Find nearest support zone below price (returns zone index)       |
//+------------------------------------------------------------------+
int FindNearestSupportIndexBelow(double price, double atr)
{
   double minGap   = (atr > 0) ? atr * 0.5 : _Point * 50;
   double bestDist = 999999.0;
   int bestIdx = -1;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.broken || z.historical) continue;
      if(!IsBullishZone(z.type))               continue;
      if(!z.valid || z.score < ZM_MIN_VALID_SCORE) continue;
      if(z.upperBound > price - minGap) continue;
      double dist = price - z.upperBound;
      if(dist < bestDist) { bestDist = dist; bestIdx = i; }
   }
   return bestIdx;
}

//+------------------------------------------------------------------+
//| Find nearest resistance zone above price (returns zone index)     |
//+------------------------------------------------------------------+
int FindNearestResistanceIndexAbove(double price, double atr)
{
   double minGap   = (atr > 0) ? atr * 0.5 : _Point * 50;
   double bestDist = 999999.0;
   int bestIdx = -1;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.broken || z.historical) continue;
      if(!IsBearishZone(z.type))               continue;
      if(!z.valid || z.score < ZM_MIN_VALID_SCORE) continue;
      if(z.lowerBound < price + minGap) continue;
      double dist = z.lowerBound - price;
      if(dist < bestDist) { bestDist = dist; bestIdx = i; }
   }
   return bestIdx;
}

void MarkZoneTraded(int idx)
{
   if(idx >= 0 && idx < g_zoneReg.count)
   {
      g_zoneReg.zones[idx].traded        = true;
      g_zoneReg.zones[idx].lastTradeTime = TimeCurrent();
   }
}

//+------------------------------------------------------------------+
//| Reset traded flag when price has moved away from the zone        |
//+------------------------------------------------------------------+
void ResetTradedZonesIfPriceLeft(double price, double atrVal)
{
   double resetDist = MathMax(atrVal * 1.5, 0.0001);
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].traded) continue;
      double lo = g_zoneReg.zones[i].lowerBound;
      double hi = g_zoneReg.zones[i].upperBound;
      double d  = (price >= lo && price <= hi) ? 0.0
                : MathMin(MathAbs(price - lo), MathAbs(price - hi));
      if(d > resetDist)
         g_zoneReg.zones[i].traded = false;
   }
}

//+------------------------------------------------------------------+
//| IsRangeZoneMapMessy                                               |
//| Returns true when the active (non-historical, non-traded) zone    |
//| map has more than maxSameSide zones on either the support or      |
//| resistance side — a sign of structural ambiguity.                 |
//+------------------------------------------------------------------+
bool IsRangeZoneMapMessy(double atr, int maxSameSide = 4)
{
   if(atr <= 0.0 || g_zoneReg.count <= 0) return false;

   int supportCount = 0, resistCount = 0;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.traded || z.historical) continue;

      if(IsSupportRole(z))        supportCount++;
      else if(IsResistanceRole(z)) resistCount++;
   }

   if(supportCount > maxSameSide || resistCount > maxSameSide) return true;

   return false;
}

//+------------------------------------------------------------------+
//| PATCH 7 — Reduce dense range zone stacks                        |
//| If 3+ same-family zones are within 1.0 ATR of each other,       |
//| keep only the strongest (major/fresh) one, deactivate the rest. |
//+------------------------------------------------------------------+
void ReduceDenseRangeZoneStacks(double atr)
{
   if(atr <= 0.0) return;

   for(int pass = 0; pass < 2; pass++)
   {
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         if(!g_zoneReg.zones[i].active) continue;

         ENUM_ZONE_TYPE typeI = g_zoneReg.zones[i].type;
         bool isSupportI = IsBullishZone(typeI);
         bool isResistanceI = IsBearishZone(typeI);
         if(!isSupportI && !isResistanceI) continue;

         int clusterIdx[16];
         int clusterCount = 0;
         double midI = g_zoneReg.zones[i].midPoint;

         for(int j = 0; j < g_zoneReg.count; j++)
         {
            if(!g_zoneReg.zones[j].active) continue;
            ENUM_ZONE_TYPE typeJ = g_zoneReg.zones[j].type;
            bool sameFamily = (isSupportI && IsBullishZone(typeJ)) ||
                              (isResistanceI && IsBearishZone(typeJ));
            if(!sameFamily) continue;

            double midJ = g_zoneReg.zones[j].midPoint;
            if(MathAbs(midJ - midI) <= atr * 1.0)
            {
               if(clusterCount < 16)
                  clusterIdx[clusterCount++] = j;
            }
         }

         if(clusterCount >= 3)
         {
            int keepIdx = clusterIdx[0];
            double keepScore = -DBL_MAX;

            for(int k = 0; k < clusterCount; k++)
            {
               int z = clusterIdx[k];
               double s = 0.0;

               s += g_zoneReg.zones[z].qualityScore * 1.50;
               s += g_zoneReg.zones[z].strength * 1.00;
               s += g_zoneReg.zones[z].qualityChecklistHits * 0.75;

               if(g_zoneReg.zones[z].majorQualified)     s += 2.00;
               if(g_zoneReg.zones[z].structuralAnchor)   s += 1.50;
               if(g_zoneReg.zones[z].protectedKeyZone)   s += 1.25;
               if(g_zoneReg.zones[z].isFlipZone)         s += 1.00;
               if(g_zoneReg.zones[z].freshness > 0.5)    s += 0.75;

               ENUM_ZONE_TYPE zt = g_zoneReg.zones[z].type;
               if(zt == ZONE_SUPPORT_MAJOR || zt == ZONE_RESISTANCE_MAJOR ||
                  zt == ZONE_DEMAND || zt == ZONE_SUPPLY)
                  s += 1.25;

               s -= MathMax(0, g_zoneReg.zones[z].cleanTouchCount - 2) * 0.50;

               if(s > keepScore)
               {
                  keepScore = s;
                  keepIdx = z;
               }
            }

            for(int k = 0; k < clusterCount; k++)
            {
               int z = clusterIdx[k];
               if(z == keepIdx) continue;
               Print("[ZONE_STACK_REDUCE] deactivating zone[", z, "] type=",
                     EnumToString(g_zoneReg.zones[z].type),
                     " mid=", DoubleToString(g_zoneReg.zones[z].midPoint, _Digits),
                     " keeping zone[", keepIdx, "]");
               g_zoneReg.zones[z].active = false;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| PATCH 15 — Recompute zone quality scores for all active zones      |
//+------------------------------------------------------------------+
void RecomputeZoneQualityScores(double price, double atr)
{
   int trendBias = GetZoneTrendBias();
   int majorCount = 0;
   int moderateCount = 0;
   int weakCount = 0;
   int droppedCount = 0;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].valid)
         continue;

      ComputeStrictZoneQualityScore(g_zoneReg.zones[i], atr, trendBias);

      bool protectedException =
         (g_zoneReg.zones[i].protectedKeyZone ||
          g_zoneReg.zones[i].isPrimary ||
          g_zoneReg.zones[i].isBackup ||
          g_zoneReg.zones[i].isFlipZone ||
          g_zoneReg.zones[i].structuralLocked);

      if(UsePhotoZoneFilterEffective() &&
         !protectedException &&
         g_zoneReg.zones[i].qualityChecklistHits < ZoneMinimumChecklistHitsEffective())
      {
         g_zoneReg.zones[i].valid = false;
         g_zoneReg.zones[i].active = false;
         g_zoneReg.zones[i].historical = true;

         Print("[ZONE_PHOTO_FILTER_DROP] id=", g_zoneReg.zones[i].id,
               " hits=", g_zoneReg.zones[i].qualityChecklistHits,
               " quality=", DoubleToString(g_zoneReg.zones[i].qualityScore, 2),
               " tag=", g_zoneReg.zones[i].structuralTag,
               " reason=failed_3_of_5_checklist");

         droppedCount++;
         weakCount++;
         continue;
      }

      if(g_zoneReg.zones[i].majorQualified)
         majorCount++;
      else if(g_zoneReg.zones[i].qualityScore >= ZoneWeakThresholdEffective())
         moderateCount++;
      else
         weakCount++;
   }

   Print("[ZONE_QUALITY_SUMMARY] total=", g_zoneReg.count,
         " major=", majorCount,
         " moderate=", moderateCount,
         " weak=", weakCount,
         " dropped=", droppedCount,
         " photoFilter=", (UsePhotoZoneFilterEffective() ? "true" : "false"),
         " forcePreset=", (InpForcePhotoStyleZonePreset ? "true" : "false"),
         " minHits=", ZoneMinimumChecklistHitsEffective(),
         " majorThreshold=", DoubleToString(ZoneMajorThresholdEffective(), 2),
         " weakThreshold=", DoubleToString(ZoneWeakThresholdEffective(), 2));
}

//+------------------------------------------------------------------+
//| PATCH 15 — Stronger clustered-zone winner logic                    |
//+------------------------------------------------------------------+
bool IsPreferredClusterWinner(const ZoneInfo &a, const ZoneInfo &b)
{
   if(a.qualityScore != b.qualityScore)
      return a.qualityScore > b.qualityScore;

   if(a.majorQualified != b.majorQualified)
      return a.majorQualified;

   if(a.departureATR != b.departureATR)
      return a.departureATR > b.departureATR;

   if(a.structureImpactScore != b.structureImpactScore)
      return a.structureImpactScore > b.structureImpactScore;

   return a.touchCountTotal < b.touchCountTotal;
}

//+------------------------------------------------------------------+
//| Assign zone strategy roles based on trend bias and D1 trendline    |
//+------------------------------------------------------------------+
void AssignZoneStrategyRoles(double price, double atr, int trendBias, bool d1TrendValid)
{
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].valid || !g_zoneReg.zones[i].active ||
         g_zoneReg.zones[i].historical || g_zoneReg.zones[i].broken)
      {
         g_zoneReg.zones[i].strategyRole = ZROLE_NONE;
         continue;
      }

      g_zoneReg.zones[i].strategyRole = ZROLE_NONE;

      // Preserve Supply/Demand pattern roles
      if(InpUseSupplyDemandZones && InpSDClassifyPatternType)
      {
         string tag = g_zoneReg.zones[i].structuralTag;
         if(tag == "RBD" || tag == "DBD")
            g_zoneReg.zones[i].strategyRole = ZROLE_SUPPLY_DEMAND;
         else if(tag == "DBR" || tag == "RBR")
            g_zoneReg.zones[i].strategyRole = ZROLE_SUPPLY_DEMAND;
      }

      if(d1TrendValid)
      {
         if(trendBias == 1)
         {
            if(g_zoneReg.zones[i].structuralTag == "HL" ||
               g_zoneReg.zones[i].type == ZONE_SUPPORT_MAJOR ||
               g_zoneReg.zones[i].type == ZONE_DEMAND)
               g_zoneReg.zones[i].strategyRole = ZROLE_TREND_CONTINUATION;

            if(g_zoneReg.zones[i].structuralTag == "HH" || g_zoneReg.zones[i].isFlipZone)
               g_zoneReg.zones[i].strategyRole = ZROLE_COUNTERTREND_EXHAUSTION;
         }
         else if(trendBias == -1)
         {
            if(g_zoneReg.zones[i].structuralTag == "LH" ||
               g_zoneReg.zones[i].type == ZONE_RESISTANCE_MAJOR ||
               g_zoneReg.zones[i].type == ZONE_SUPPLY)
               g_zoneReg.zones[i].strategyRole = ZROLE_TREND_CONTINUATION;

            if(g_zoneReg.zones[i].structuralTag == "LL" || g_zoneReg.zones[i].isFlipZone)
               g_zoneReg.zones[i].strategyRole = ZROLE_COUNTERTREND_EXHAUSTION;
         }
      }
      else
      {
         ZONE_CANONICAL_ROLE role = ResolveZoneRole(g_zoneReg.zones[i], price, atr);
         if(role == ZROLE_SUPPORT)
            g_zoneReg.zones[i].strategyRole = ZROLE_RANGE_SUPPORT;
         else if(role == ZROLE_RESISTANCE)
            g_zoneReg.zones[i].strategyRole = ZROLE_RANGE_RESISTANCE;
      }
   }
}

//+------------------------------------------------------------------+
//| Zone Eligibility for Visual D1 Drawing                           |
//+------------------------------------------------------------------+
bool ZoneEligibleForVisualD1(const ZoneInfo &z, double price, double atr)
{
   if(!z.valid || !z.active || z.historical || z.broken)
      return false;

   if(z.sourceTF != g_zoneTF)
      return false;

   if(!PassesZoneStrengthMode(z, InpVisualZoneStrengthMode))
      return false;

   ZONE_CANONICAL_ROLE role = ResolveZoneRole(z, price, atr);

   bool roleOk =
      (role == ZROLE_SUPPORT) ||
      (role == ZROLE_RESISTANCE) ||
      (z.structuralTag == "HL") ||
      (z.structuralTag == "LH") ||
      (z.structuralTag == "HH") ||
      (z.structuralTag == "LL") ||
      z.isFlipZone ||
      z.structuralAnchor ||
      z.protectedKeyZone ||
      z.majorTFZone;

   if(!roleOk)
      return false;

   if(MathAbs(z.midPoint - price) > MathMax(atr * 20.0, _Point * 1500.0))
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Score Visual D1 Zone for Chart Display Priority                  |
//+------------------------------------------------------------------+
double ScoreVisualD1Zone(const ZoneInfo &z, double price, double atr)
{
   double safeAtr = MathMax(atr, _Point * 50.0);
   double distATR = MathAbs(z.midPoint - price) / safeAtr;

   double score = 0.0;

   score += z.qualityScore * 1.10;
   score += z.cleanTouchCount * 0.65;
   score += z.strength * 2.40;

   if(z.structuralAnchor)      score += 2.60;
   if(z.protectedKeyZone)      score += 2.10;
   if(z.isFlipZone)            score += 1.80;
   if(z.majorTFZone)           score += 1.60;

   if(z.structuralTag == "HL" || z.structuralTag == "LH") score += 1.25;
   if(z.structuralTag == "HH" || z.structuralTag == "LL") score += 0.75;

   if(InpVisualZoneStrengthMode == ZONE_STRENGTH_STRONG_ONLY)
      score += z.qualityScore * 0.50;

   score -= distATR * 0.08;

   return score;
}

//+------------------------------------------------------------------+
//| Should retire trend zone based on D1 trendline break/retest        |
//+------------------------------------------------------------------+
bool ShouldRetireTrendZone(const ZoneInfo &z, const IndicatorState &ind, double atr, int trendBias)
{
   if(!InpKeepTrendZonesUntilRetestFail)
      return z.broken;

   bool brokenAndRetested = IsD1TrendlineBrokenAndRetested(ind, atr);
   bool consolidating = IsTrendStructureConsolidating(ind, atr);

   if(brokenAndRetested)
   {
      Print("[TREND_ZONE_RETIRE] id=", z.id, " reason=break_retest_or_consolidation");
      return true;
   }

   if(consolidating)
   {
      Print("[TREND_ZONE_RETIRE] id=", z.id, " reason=break_retest_or_consolidation");
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Range Boundary Candidate                                          |
//+------------------------------------------------------------------+
struct RangeBoundaryCandidate
{
   bool   valid;
   int    zoneIdx;
   double lowerBound;
   double upperBound;
   double mid;
   double score;
   bool   isDemand;
};

//+------------------------------------------------------------------+
//| Range Boundary Selection Result                                   |
//+------------------------------------------------------------------+
struct RangeBoundarySelection
{
   bool                    valid;
   string                  reason;
   RangeBoundaryCandidate  bestDemand;
   RangeBoundaryCandidate  bestSupply;
   double                  totalWidth;
   bool                    provisional;
};

//+------------------------------------------------------------------+
//| Visual Line Range Fallback - use yellow D1 lines when primary fails |
//+------------------------------------------------------------------+
bool BuildVisualLineRangeFallback(double price, double atr, RangeBoundarySelection &out)
{
   out.valid = false;

   VisualLineSet vs;
   if(g_lastDrawnVisualValid && g_lastDrawnVisualD1.count > 0)
      vs = g_lastDrawnVisualD1;
   else
      vs = BuildVisualD1LineSet(price, atr);

   if(vs.count < 2)
      return false;

   int bestBelow = -1;
   int bestAbove = -1;
   double bestBelowDist = DBL_MAX;
   double bestAboveDist = DBL_MAX;

   for(int i = 0; i < vs.count; i++)
   {
      ZoneInfo z = vs.zones[i];
      double dist = MathAbs(z.midPoint - price);

      if(z.midPoint <= price && dist < bestBelowDist)
      {
         bestBelow = i;
         bestBelowDist = dist;
      }

      if(z.midPoint >= price && dist < bestAboveDist)
      {
         bestAbove = i;
         bestAboveDist = dist;
      }
   }

   if(bestBelow < 0 || bestAbove < 0)
      return false;

   ZoneInfo below = vs.zones[bestBelow];
   ZoneInfo above = vs.zones[bestAbove];

   if(below.id == above.id)
      return false;

   double widthATR = (above.midPoint - below.midPoint) / MathMax(atr, _Point * 10.0);
   if(widthATR < 1.2 || widthATR > 12.0)
      return false;

   int belowIdx = FindZoneById(below.id);
   int aboveIdx = FindZoneById(above.id);

   out.valid = true;
   out.reason = "visual_d1_line_fallback";

   out.bestDemand.valid = true;
   out.bestDemand.zoneIdx = belowIdx;   // may be -1
   out.bestDemand.lowerBound = below.lowerBound;
   out.bestDemand.upperBound = below.upperBound;
   out.bestDemand.mid = below.midPoint;
   out.bestDemand.score = 0.0;
   out.bestDemand.isDemand = true;

   out.bestSupply.valid = true;
   out.bestSupply.zoneIdx = aboveIdx; // may be -1
   out.bestSupply.lowerBound = above.lowerBound;
   out.bestSupply.upperBound = above.upperBound;
   out.bestSupply.mid = above.midPoint;
   out.bestSupply.score = 0.0;
   out.bestSupply.isDemand = false;

   out.totalWidth = above.midPoint - below.midPoint;
   out.provisional = (belowIdx < 0 || aboveIdx < 0);

   Print("[RANGE_MAP_VISUAL_FALLBACK] demandId=", below.id,
         " supplyId=", above.id,
         " demandIdx=", belowIdx,
         " supplyIdx=", aboveIdx,
         " demandMid=", DoubleToString(below.midPoint, _Digits),
         " supplyMid=", DoubleToString(above.midPoint, _Digits),
         " widthATR=", DoubleToString(widthATR, 2),
         " provisional=", (out.provisional ? "true" : "false"));

   // Align range map with visible active pair
   if(InpSDShowOnlyActivePair && belowIdx >= 0)
      g_activeDemandZoneId = below.id;
   if(InpSDShowOnlyActivePair && aboveIdx >= 0)
      g_activeSupplyZoneId = above.id;

   return true;
}

//+------------------------------------------------------------------+
//| Build Final Horizontal Range Map - Two-sided boundary assignment |
//| HARD RULE: Enforce strict demand/supply roles and validity        |
//+------------------------------------------------------------------+
RangeBoundarySelection BuildFinalHorizontalRangeMap(const IndicatorState &ind, double price, double atr)
{
   RangeBoundarySelection result = {};
   result.valid = false;

   if(atr <= 0.0)
      return result;

   ZoneInfo demand = {};
   ZoneInfo supply = {};
   bool hasDemand = false;
   bool hasSupply = false;

   if(!SelectPrimaryZonePair(price, atr, demand, supply, hasDemand, hasSupply) ||
      !hasDemand || !hasSupply)
   {
      if(BuildVisualLineRangeFallback(price, atr, result))
         return result;

      Print("[RANGE_MAP_INVALID] missing_demand_or_supply demandIdx=-1 supplyIdx=-1");
      return result;
   }

   double demandTol = MathMax(atr * 0.08, _Point * 8.0);
   if(!ZoneEligibleAsSupportHere(demand, price, atr) || demand.midPoint > price + demandTol)
   {
      if(BuildVisualLineRangeFallback(price, atr, result))
         return result;

      Print("[RANGE_MAP_INVALID] demand_invalid id=", demand.id,
            " mid=", DoubleToString(demand.midPoint, _Digits),
            " price=", DoubleToString(price, _Digits));
      return result;
   }

   double supplyTol = MathMax(atr * 0.08, _Point * 8.0);
   if(!ZoneEligibleAsResistanceHere(supply, price, atr) || supply.midPoint < price - supplyTol)
   {
      if(BuildVisualLineRangeFallback(price, atr, result))
         return result;

      Print("[RANGE_MAP_INVALID] supply_invalid id=", supply.id,
            " mid=", DoubleToString(supply.midPoint, _Digits),
            " price=", DoubleToString(price, _Digits));
      return result;
   }

   if(demand.midPoint >= supply.midPoint)
   {
      Print("[RANGE_MAP_INVALID] demand_above_supply demand=", DoubleToString(demand.midPoint, _Digits),
            " supply=", DoubleToString(supply.midPoint, _Digits));
      return result;
   }

   double rangeWidth = supply.midPoint - demand.midPoint;
   double rangeWidthATR = rangeWidth / atr;

   if(rangeWidthATR < 1.5 || rangeWidthATR > 12.0)
   {
      Print("[RANGE_MAP_INVALID] width_out_of_bounds widthATR=", DoubleToString(rangeWidthATR, 2),
            " demand=", DoubleToString(demand.midPoint, _Digits),
            " supply=", DoubleToString(supply.midPoint, _Digits));
      return result;
   }

   double distToDemand = MathAbs(price - demand.midPoint) / atr;
   double distToSupply = MathAbs(supply.midPoint - price) / atr;

   if(distToDemand > 2.5 && distToSupply > 2.5)
   {
      Print("[RANGE_MAP_INVALID] price_too_far_from_boundaries distDemand=", DoubleToString(distToDemand, 2),
            " distSupply=", DoubleToString(distToSupply, 2));
      return result;
   }

   int demandIdx = FindZoneById(demand.id);
   int supplyIdx = FindZoneById(supply.id);

   if(demandIdx < 0 || supplyIdx < 0)
   {
      Print("[RANGE_MAP_INVALID] zone_lookup_failed demandId=", demand.id,
            " supplyId=", supply.id);
      return result;
   }

   result.valid = true;

   result.bestDemand.zoneIdx = demandIdx;
   result.bestDemand.mid = demand.midPoint;
   result.bestDemand.lowerBound = demand.lowerBound;
   result.bestDemand.upperBound = demand.upperBound;
   result.bestDemand.score = SafePrimaryScoreValue(demand, true, price, atr);
   result.bestDemand.valid = true;
   result.bestDemand.isDemand = true;

   result.bestSupply.zoneIdx = supplyIdx;
   result.bestSupply.mid = supply.midPoint;
   result.bestSupply.lowerBound = supply.lowerBound;
   result.bestSupply.upperBound = supply.upperBound;
   result.bestSupply.score = SafePrimaryScoreValue(supply, false, price, atr);
   result.bestSupply.valid = true;
   result.bestSupply.isDemand = false;

   Print("[RANGE_MAP_VALID] demandId=", demand.id,
         " supplyId=", supply.id,
         " widthATR=", DoubleToString(rangeWidthATR, 2));

   // Align range map with visible active pair
   if(InpSDShowOnlyActivePair)
   {
      g_activeDemandZoneId = demand.id;
      g_activeSupplyZoneId = supply.id;
   }

   return result;
}

#endif // ZONE_MANAGER_MQH
