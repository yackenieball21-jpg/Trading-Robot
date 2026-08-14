//+------------------------------------------------------------------+
//|                                                SignalEngine.mqh |
//|  Signal logic: zone detection + candle patterns                  |
//|  v9.0 - Zone + Sweep + EMA50 + ADX entry system                  |
//|                                                                   |
//|  SECTION MAP:                                                     |
//|   L19   — SECTION 1: Trend Helpers & Indicator Utilities          |
//|   L812  — SECTION 2: Enums (TradeMode, D1Bias, ZoneInteraction)  |
//|   L1499 — SECTION 3: EntryDecision Struct & Factory              |
//|   L1534 — SECTION 4: Zone & Structural Helpers                    |
//|   L3785 — SECTION 5: Trend Signal Core (ShouldOpenBuy/Sell)      |
//|   L5101 — SECTION 6: Range Signal Core (ShouldOpenBuyRange/Sell) |
//|   L6060 — SECTION 7: Breakout & Reversal Signals                  |
//|   L6563 — SECTION 8: Trend Continuation Decision                  |
//|   L6807 — SECTION 9: Counter-Trend Decision                       |
//|   L7068 — SECTION 10: Zone Retest / Flip Decision                 |
//|   L7531 — SECTION 11: Channel Range Decision                      |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef SIGNAL_ENGINE_MQH
#define SIGNAL_ENGINE_MQH

#include "IndicatorManager.mqh"
#include "SymbolProfiler.mqh"
#include "ZoneManager.mqh"
#include "CandlePatterns.mqh"
#include "MarketStructure.mqh"
#include "MarketClassifier.mqh"

// Channel code removed per user request

//+==================================================================+
//| SECTION 1: TREND HELPERS & INDICATOR UTILITIES                   |
//| EMA slope, ADX, D1 bias helpers, market state checks            |
//+==================================================================+

//+------------------------------------------------------------------+
//| Trend helpers                                                    |
//+------------------------------------------------------------------+
double GetEMA50Slope(const IndicatorState &ind, int lookback)
{
   if(lookback < 2) lookback = 2;
   if(lookback >= 50) lookback = 49;
   return GetEMA50(ind, 1) - GetEMA50(ind, lookback);
}

bool IsAboveEMA50(const IndicatorState &ind)
{
   return (ind.closeArr[1] > GetEMA50(ind, 1));
}

bool IsBelowEMA50(const IndicatorState &ind)
{
   return (ind.closeArr[1] < GetEMA50(ind, 1));
}

bool IsADXTrending(const IndicatorState &ind, double minADX = 20.0)
{
   return (GetADX(ind, 1) >= minADX);
}

bool IsBullTrendStillValid(const IndicatorState &ind)
{
   return (IsAboveEMA50(ind) && IsADXTrending(ind, 20.0));
}

//+------------------------------------------------------------------+
//| EMA Filter Helpers - EMA as filter only, not trigger             |
//+------------------------------------------------------------------+
bool HasBullEMAFilter(const IndicatorState &ind)
{
   return (ind.ema50[1] > ind.ema200[1]);
}

bool HasBearEMAFilter(const IndicatorState &ind)
{
   return (ind.ema50[1] < ind.ema200[1]);
}

bool HasBullEMARetestBonus(const IndicatorState &ind, double atr)
{
   return (MathAbs(ind.lowArr[1] - ind.ema50[1]) <= atr * 0.25 && ind.closeArr[1] > ind.ema50[1]);
}

bool HasBearEMARetestBonus(const IndicatorState &ind, double atr)
{
   return (MathAbs(ind.highArr[1] - ind.ema50[1]) <= atr * 0.25 && ind.closeArr[1] < ind.ema50[1]);
}

//+------------------------------------------------------------------+
//| Get EMA for specific timeframe and shift                          |
//+------------------------------------------------------------------+
double GetEMAForTF(string symbol, ENUM_TIMEFRAMES tf, int period, int shift)
{
   double emaBuffer[];
   ArraySetAsSeries(emaBuffer, true);
   
   int handle = iMA(symbol, tf, period, 0, MODE_EMA, PRICE_CLOSE);
   if(handle == INVALID_HANDLE)
      return 0.0;
   
   if(CopyBuffer(handle, 0, shift, 1, emaBuffer) < 1)
   {
      IndicatorRelease(handle);
      return 0.0;
   }
   
   double value = emaBuffer[0];
   IndicatorRelease(handle);
   return value;
}

//+------------------------------------------------------------------+
//| H4 EMA200 Directional Filter (OPTIONAL confirmation only)        |
//| DO NOT use for drawing - only for trade filtering               |
//+------------------------------------------------------------------+
bool PassesH4EMA200DirectionalFilter(bool isBull)
{
   // PATCH: use dedicated higher-TF trend reference so the filter stays valid
   // when the bot is attached to lower timeframes (M1/M5/M15...).
   ENUM_TIMEFRAMES trendTF = InpSDTrendReferenceTF;
   if(trendTF == PERIOD_CURRENT) trendTF = PERIOD_H4;

   double closeH4    = iClose(_Symbol, trendTF, 1);
   double ema200H4   = GetEMAForTF(_Symbol, trendTF, 200, 1);
   double ema200Prev = GetEMAForTF(_Symbol, trendTF, 200, 2);

   if(closeH4 <= 0.0 || ema200H4 <= 0.0 || ema200Prev <= 0.0)
      return true; // fail open if data missing

   double slope = ema200H4 - ema200Prev;

   if(isBull)
      return (closeH4 >= ema200H4 && slope >= -_Point * 5);
   else
      return (closeH4 <= ema200H4 && slope <=  _Point * 5);
}

//+------------------------------------------------------------------+
//| Pattern-aware S/D trend gate                                     |
//| Returns true if the zone entry should be BLOCKED based on trend. |
//|  - Continuation patterns (RBR bull, DBD bear) must align with    |
//|    the higher-TF trend reference.                                |
//|  - Reversal patterns (DBR bull, RBD bear) may bypass the filter  |
//|    when the zone is structurally major (and InpSDReversalBypass- |
//|    IfMajor is enabled).                                          |
//|  - Unknown / non-S/D tags fall back to the uniform H4 gate.      |
//+------------------------------------------------------------------+
bool ShouldBlockSDEntryByTrend(const ZoneInfo &zone, bool isBull)
{
   if(!InpSDRequireH4TrendAlignment)
      return false;

   bool trendOk = PassesH4EMA200DirectionalFilter(isBull);
   if(trendOk)
      return false;

   string tag = zone.structuralTag;
   bool isContinuation = (isBull ? (tag == "RBR")
                                 : (tag == "DBD"));
   bool isReversal     = (isBull ? (tag == "DBR" || tag == "DBR_UNKNOWN")
                                 : (tag == "RBD" || tag == "RBD_UNKNOWN"));

   // Reversal bypass: allow counter-trend reversal entries at major zones.
   if(isReversal && InpSDReversalBypassIfMajor)
   {
      if(zone.majorQualified || zone.structureImpactScore >= 0.75)
         return false;
   }

   // Continuation patterns or unclassified zones: enforce trend alignment.
   if(isContinuation) return true;
   return true; // default: block when trend says no
}

//+------------------------------------------------------------------+
//| Execution Band Helper                                             |
//+------------------------------------------------------------------+
void ComputeExecutionBand(const ZoneInfo &z, bool isSupport, double &execLow, double &execHigh)
{
   double w = z.upperBound - z.lowerBound;
   if(w <= 0.0)
   {
      execLow = z.lowerBound;
      execHigh = z.upperBound;
      return;
   }

   if(isSupport)
   {
      execLow = z.lowerBound + w * 0.70;
      execHigh = z.upperBound;
   }
   else
   {
      execLow = z.lowerBound;
      execHigh = z.lowerBound + w * 0.30;
   }
}

//+------------------------------------------------------------------+
//| Get validated ATR with fallback for low volatility               |
//+------------------------------------------------------------------+
double GetValidatedATR(const IndicatorState &ind)
{
   double atr     = GetATR(ind, 1);
   double atrPrev = GetATR(ind, 2);
   
   // Filter out extreme spikes (>50% deviation from previous bar)
   double avgAtr = (atr + atrPrev) / 2.0;
   if(avgAtr > 0.0 && MathAbs(atr - avgAtr) > avgAtr * 0.5)
      return avgAtr;
   
   // Minimum ATR floor for very low volatility (0.05% of price)
   double minAtr = ind.closeArr[1] * 0.0005;
   return MathMax(atr, minAtr);
}

bool IsBearTrendStillValid(const IndicatorState &ind)
{
   return (IsBelowEMA50(ind) && IsADXTrending(ind, 20.0));
}

bool IsPriceAboveEMA200(const IndicatorState &ind, int shift = 1)
{
   return ind.closeArr[shift] > GetEMA200(ind, shift);
}

bool IsPriceBelowEMA200(const IndicatorState &ind, int shift = 1)
{
   return ind.closeArr[shift] < GetEMA200(ind, shift);
}

bool IsValidBullPullback(const IndicatorState &ind, const SymbolProfile &prof)
{
   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   double low1   = ind.lowArr[1];
   double ema50  = GetEMA50(ind, 1);
   double atr    = GetATR(ind, 1);
   if(atr <= 0) return false;
   bool nearEMA50    = (low1 <= ema50 + atr * 0.35);
   bool closedAbove  = (close1 > ema50);
   bool bullishClose = (close1 > open1);
   return (nearEMA50 && closedAbove && bullishClose && IsADXTrending(ind, 20.0));
}

bool IsValidBearPullback(const IndicatorState &ind, const SymbolProfile &prof)
{
   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   double high1  = ind.highArr[1];
   double ema50  = GetEMA50(ind, 1);
   double atr    = GetATR(ind, 1);
   if(atr <= 0) return false;
   bool nearEMA50    = (high1 >= ema50 - atr * 0.35);
   bool closedBelow  = (close1 < ema50);
   bool bearishClose = (close1 < open1);
   return (nearEMA50 && closedBelow && bearishClose && IsADXTrending(ind, 20.0));
}

// Compatibility wrappers — old callers use EMA200 name but logic is EMA50+ADX
bool IsEMA200RetestBuy(const IndicatorState &ind)
{
   return IsAboveEMA50(ind) && IsADXTrending(ind, 20.0);
}

bool IsEMA200RetestSell(const IndicatorState &ind)
{
   return IsBelowEMA50(ind) && IsADXTrending(ind, 20.0);
}

//+------------------------------------------------------------------+
//| HasBullishEntryPattern                                           |
//+------------------------------------------------------------------+
bool HasBullishEntryPattern(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                             bool engulfing, bool pinBar, bool breakout)
{
   if(engulfing && IsBullishEngulfing(symbol, tf, shift))                       return true;
   if(pinBar    && IsBullishPinBar(symbol, tf, shift))                          return true;
   if(pinBar    && IsBullishWickRejection(symbol, tf, shift, 0.40, 0.45, true)) return true;
   if(breakout  && IsStrongBullishBody(symbol, tf, shift, 0.60))                return true;
   return false;
}

//+------------------------------------------------------------------+
//| HasBearishEntryPattern                                           |
//+------------------------------------------------------------------+
bool HasBearishEntryPattern(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                             bool engulfing, bool pinBar, bool breakout)
{
   if(engulfing && IsBearishEngulfing(symbol, tf, shift))                       return true;
   if(pinBar    && IsBearishPinBar(symbol, tf, shift))                          return true;
   if(pinBar    && IsBearishWickRejection(symbol, tf, shift, 0.40, 0.45, true)) return true;
   if(breakout  && IsStrongBearishBody(symbol, tf, shift, 0.60))                return true;
   return false;
}

//+------------------------------------------------------------------+
//| D1 Zone Permission Functions                                      |
//+------------------------------------------------------------------+
double GetNearestD1Demand(double price)
{
   int idx = FindNearestSupportIndexBelow(price, 0.0);
   if(idx < 0) return 0.0;
   return g_zoneReg.zones[idx].midPoint;
}

double GetNearestD1Supply(double price)
{
   int idx = FindNearestResistanceIndexAbove(price, 0.0);
   if(idx < 0) return 0.0;
   return g_zoneReg.zones[idx].midPoint;
}

bool FindNextZoneAbove(double price, double atr, int &zoneIdx, double &zoneLow, double &zoneHigh)
{
   zoneIdx = -1; zoneLow = 0.0; zoneHigh = 0.0;
   double minGap = (atr > 0.0) ? atr * 0.30 : _Point * 30;
   double bestDist = DBL_MAX;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.broken || z.historical || !z.valid) continue;
      if(z.lowerBound < price + minGap) continue;
      double dist = z.lowerBound - price;
      if(dist < bestDist) { bestDist = dist; zoneIdx = i; zoneLow = z.lowerBound; zoneHigh = z.upperBound; }
   }
   return (zoneIdx >= 0);
}

bool FindNextZoneBelow(double price, double atr, int &zoneIdx, double &zoneLow, double &zoneHigh)
{
   zoneIdx = -1; zoneLow = 0.0; zoneHigh = 0.0;
   double minGap = (atr > 0.0) ? atr * 0.30 : _Point * 30;
   double bestDist = DBL_MAX;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.broken || z.historical || !z.valid) continue;
      if(z.upperBound > price - minGap) continue;
      double dist = price - z.upperBound;
      if(dist < bestDist) { bestDist = dist; zoneIdx = i; zoneLow = z.lowerBound; zoneHigh = z.upperBound; }
   }
   return (zoneIdx >= 0);
}

bool FindNearestRetestDemandZone(double price, double atr, int &zoneIdx, double &zoneLow, double &zoneHigh)
{
   zoneIdx = -1; zoneLow = 0.0; zoneHigh = 0.0;
   double maxDistATR = 1.5;  // Increased from 0.80 to 1.5
   double bestDistATR = DBL_MAX;
   double bestScore = -DBL_MAX;
   double minQualityScore = 2.0;  // Added quality floor

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.broken || !z.valid) continue;

      // Relax historical filter - allow high-quality historical zones
      if(z.historical && z.qualityScore < 3.0) continue;

      // Expanded zone types to include more options
      bool demandLike =
         z.type == ZONE_DEMAND_MAJOR ||
         z.type == ZONE_DEMAND_MINOR ||
         z.type == ZONE_SUPPORT_MAJOR ||
         z.type == ZONE_RESISTANCE_MAJOR ||  // Added as fallback
         z.type == ZONE_RESISTANCE_MINOR ||  // Added as fallback
         z.type == ZONE_SUPPLY_MAJOR ||      // Added as fallback
         z.structuralTag == "HL" ||
         z.structuralTag == "LL" ||
         z.structuralTag == "LH" ||          // Added as fallback
         z.structuralTag == "HH";            // Added as fallback

      if(!demandLike) continue;

      // Apply quality floor
      if(z.qualityScore < minQualityScore) continue;

      double dist = (price >= z.lowerBound && price <= z.upperBound)
         ? 0.0
         : MathMin(MathAbs(price - z.lowerBound), MathAbs(price - z.upperBound));

      double distATR = (atr > 0.0) ? dist / atr : DBL_MAX;
      if(distATR > maxDistATR) continue;

      double score = z.qualityScore;
      if(z.structuralTag == "HL" || z.structuralTag == "LL") score += 1.0;
      if(z.type == ZONE_DEMAND_MAJOR || z.type == ZONE_SUPPORT_MAJOR) score += 0.75;
      if(z.isFlipZone) score += 0.50;

      if(distATR < bestDistATR - 0.05 ||
         (MathAbs(distATR - bestDistATR) <= 0.05 && score > bestScore))
      {
         bestDistATR = distATR;
         bestScore = score;
         zoneIdx = i;
         zoneLow = z.lowerBound;
         zoneHigh = z.upperBound;
      }
   }

   return (zoneIdx >= 0);
}

bool FindNearestRetestSupplyZone(double price, double atr, int &zoneIdx, double &zoneLow, double &zoneHigh)
{
   zoneIdx = -1; zoneLow = 0.0; zoneHigh = 0.0;
   double maxDistATR = 1.5;  // Increased from 0.80 to 1.5
   double bestDistATR = DBL_MAX;
   double bestScore = -DBL_MAX;
   double minQualityScore = 2.0;  // Added quality floor

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.broken || !z.valid) continue;

      // Relax historical filter - allow high-quality historical zones
      if(z.historical && z.qualityScore < 3.0) continue;

      // Expanded zone types to include more options
      bool supplyLike =
         z.type == ZONE_SUPPLY_MAJOR ||
         z.type == ZONE_SUPPLY_MINOR ||
         z.type == ZONE_RESISTANCE_MAJOR ||
         z.type == ZONE_SUPPORT_MAJOR ||     // Added as fallback
         z.type == ZONE_SUPPORT_MINOR ||     // Added as fallback
         z.type == ZONE_DEMAND_MAJOR ||      // Added as fallback
         z.structuralTag == "LH" ||
         z.structuralTag == "HH" ||
         z.structuralTag == "HL" ||          // Added as fallback
         z.structuralTag == "LL";            // Added as fallback

      if(!supplyLike) continue;

      // Apply quality floor
      if(z.qualityScore < minQualityScore) continue;

      double dist = (price >= z.lowerBound && price <= z.upperBound)
         ? 0.0
         : MathMin(MathAbs(price - z.lowerBound), MathAbs(price - z.upperBound));

      double distATR = (atr > 0.0) ? dist / atr : DBL_MAX;
      if(distATR > maxDistATR) continue;

      double score = z.qualityScore;
      if(z.structuralTag == "LH" || z.structuralTag == "HH") score += 1.0;
      if(z.type == ZONE_SUPPLY_MAJOR || z.type == ZONE_RESISTANCE_MAJOR) score += 0.75;
      if(z.isFlipZone) score += 0.50;

      if(distATR < bestDistATR - 0.05 ||
         (MathAbs(distATR - bestDistATR) <= 0.05 && score > bestScore))
      {
         bestDistATR = distATR;
         bestScore = score;
         zoneIdx = i;
         zoneLow = z.lowerBound;
         zoneHigh = z.upperBound;
      }
   }

   return (zoneIdx >= 0);
}


//+------------------------------------------------------------------+
//| Strict Trend Context Helpers                                      |
//+------------------------------------------------------------------+
bool IsTrendBuyContextClean()
{
   if(!g_structure.valid) return false;
   if(GetD1Bias() != D1_BIAS_BULL) return false;

   bool stateOk =
      (g_structure.state == STRUCTURE_BULL_TREND ||
       g_structure.state == STRUCTURE_BIAS_BULL);

   if(!stateOk) return false;

   bool hasBullSwings =
      (g_structure.consecutiveHH >= 1 || g_structure.consecutiveHL >= 1);

   if(!hasBullSwings) return false;

   // Only block if the channel is explicitly pointing the OTHER way.
   bool explicitOpposition =
      (g_structure.channel.valid &&
       g_structure.channel.directionalValid &&
       g_structure.channel.direction == -1);

   if(explicitOpposition) return false;

   // PATCH 3: Override dirty H4 context on valid zone-touch continuation setups
   // Check if price is touching a valid support zone for continuation
   double atr = GetATR(g_ind, 1);
   if(atr > 0.0)
   {
      double price = g_ind.closeArr[1];
      
      // Check if near a valid support zone for continuation
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         if(!g_zoneReg.zones[i].valid || !g_zoneReg.zones[i].active)
            continue;
         
         // Check if zone is support type
         if(g_zoneReg.zones[i].type == ZONE_SUPPORT_MAJOR || g_zoneReg.zones[i].type == ZONE_SUPPORT_MINOR)
         {
            double dist = MathAbs(price - g_zoneReg.zones[i].midPoint);
            if(dist <= atr * 0.5) // Within 0.5 ATR of zone
            {
               // Valid zone-touch continuation setup - override dirty H4
               Print("[TREND_CONTEXT_OVERRIDE] side=BUY zone_touch_continuation idx=", i,
                     " distATR=", DoubleToString(dist / atr, 2),
                     " state=", StructureStateToString(g_structure.state));
               return true;
            }
         }
      }
   }

   // Do not hard-block just because rangeLikelyTransition=true if structure is still bullish.
   return true;
}

bool IsTrendSellContextClean()
{
   if(!g_structure.valid) return false;
   if(GetD1Bias() != D1_BIAS_BEAR) return false;

   bool stateOk =
      (g_structure.state == STRUCTURE_BEAR_TREND ||
       g_structure.state == STRUCTURE_BIAS_BEAR);

   if(!stateOk) return false;

   bool hasBearSwings =
      (g_structure.consecutiveLH >= 1 || g_structure.consecutiveLL >= 1);

   if(!hasBearSwings) return false;

   // Only block if the channel is explicitly pointing the OTHER way.
   bool explicitOpposition =
      (g_structure.channel.valid &&
       g_structure.channel.directionalValid &&
       g_structure.channel.direction == +1);

   if(explicitOpposition) return false;

   // PATCH 3: Override dirty H4 context on valid zone-touch continuation setups
   // Check if price is touching a valid resistance zone for continuation
   double atr = GetATR(g_ind, 1);
   if(atr > 0.0)
   {
      double price = g_ind.closeArr[1];
      
      // Check if near a valid resistance zone for continuation
      for(int i = 0; i < g_zoneReg.count; i++)
      {
         if(!g_zoneReg.zones[i].valid || !g_zoneReg.zones[i].active)
            continue;
         
         // Check if zone is resistance type
         if(g_zoneReg.zones[i].type == ZONE_RESISTANCE_MAJOR || g_zoneReg.zones[i].type == ZONE_RESISTANCE_MINOR)
         {
            double dist = MathAbs(price - g_zoneReg.zones[i].midPoint);
            if(dist <= atr * 0.5) // Within 0.5 ATR of zone
            {
               // Valid zone-touch continuation setup - override dirty H4
               Print("[TREND_CONTEXT_OVERRIDE] side=SELL zone_touch_continuation idx=", i,
                     " distATR=", DoubleToString(dist / atr, 2),
                     " state=", StructureStateToString(g_structure.state));
               return true;
            }
         }
      }
   }

   // Do not hard-block just because rangeLikelyTransition=true if structure is still bearish.
   return true;
}

//+------------------------------------------------------------------+
//| IsBearishRejection                                               |
//+------------------------------------------------------------------+
bool IsBearishRejection(const IndicatorState &ind)
{
   double open1  = ind.openArr[1];
   double close1 = ind.closeArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];
   double body   = MathAbs(close1 - open1);
   double range  = high1 - low1;
   if(range <= 0) return false;
   double upperWick = high1 - MathMax(close1, open1);
   return (upperWick > range * 0.6 &&
           body < range * 0.4 &&
           close1 < (high1 + low1) / 2.0);
}

//+------------------------------------------------------------------+
//| IsBullishRejection                                               |
//+------------------------------------------------------------------+
bool IsBullishRejection(const IndicatorState &ind)
{
   double open1  = ind.openArr[1];
   double close1 = ind.closeArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];
   double body   = MathAbs(close1 - open1);
   double range  = high1 - low1;
   if(range <= 0) return false;
   double lowerWick = MathMin(close1, open1) - low1;
   return (lowerWick > range * 0.6 &&
           body < range * 0.4 &&
           close1 > (high1 + low1) / 2.0);
}

//+------------------------------------------------------------------+
//| IsEMAsTooFlatForRange - Block range trades when EMAs are flat    |
//| Returns true if EMAs are too close/flat (should NOT trade range) |
//+------------------------------------------------------------------+
bool IsEMAsTooFlatForRange(const IndicatorState &ind)
{
   double ema50  = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   double atr    = GetATR(ind, 1);
   
   if(atr <= 0.0 || ema50 <= 0.0 || ema200 <= 0.0)
      return false;  // Can't determine, allow trade
   
   // Calculate EMA gap as fraction of ATR
   double emaGap = MathAbs(ema50 - ema200);
   double emaGapATR = emaGap / atr;
   
   // Check EMA50 slope over last 5 bars
   double ema50Now  = GetEMA50(ind, 1);
   double ema50Prev = GetEMA50(ind, 5);
   double ema50Slope = MathAbs(ema50Now - ema50Prev);
   double slopeATR = ema50Slope / atr;
   
   // EMAs are too flat if:
   // 1. Gap between EMA50 and EMA200 is less than 0.15 ATR (very close)
   // 2. AND EMA50 slope over 5 bars is less than 0.08 ATR (very flat)
   // Loosened thresholds to allow more range trades
   bool tooClose = (emaGapATR < 0.15);
   bool tooFlat  = (slopeATR < 0.08);
   
   if(tooClose && tooFlat)
   {
      Print("[FLAT_EMA_FILTER] BLOCKED emaGapATR=", DoubleToString(emaGapATR, 2),
            " slopeATR=", DoubleToString(slopeATR, 2));
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| HasMultipleRejectionWicksAtZone - Check for 2+ rejection wicks   |
//| For BUY at support: block if 2+ candles have long UPPER wicks    |
//|   (price tried to go up but got rejected multiple times)         |
//| For SELL at resistance: block if 2+ candles have long LOWER wicks|
//|   (price tried to go down but got rejected multiple times)       |
//| Multiple rejections indicate zone is being tested and may break  |
//+------------------------------------------------------------------+
bool HasMultipleRejectionWicksAtZone(const IndicatorState &ind, bool isBuy, int lookback = 5)
{
   if(lookback < 2) lookback = 2;
   if(lookback > 10) lookback = 10;
   
   int rejectionCount = 0;
   double wickThreshold = 0.45;  // Wick must be at least 45% of candle range
   
   for(int i = 1; i <= lookback && i < 200; i++)
   {
      double open_i  = ind.openArr[i];
      double close_i = ind.closeArr[i];
      double high_i  = ind.highArr[i];
      double low_i   = ind.lowArr[i];
      
      double range_i = high_i - low_i;
      if(range_i <= 0.0) continue;
      
      double upperWick_i = high_i - MathMax(close_i, open_i);
      double lowerWick_i = MathMin(close_i, open_i) - low_i;
      
      if(isBuy)
      {
         // For BUY at support: count candles with long upper wicks
         // Long upper wick = price tried to go up but was rejected back down
         if(upperWick_i > range_i * wickThreshold)
            rejectionCount++;
      }
      else // SELL
      {
         // For SELL at resistance: count candles with long lower wicks
         // Long lower wick = price tried to go down but was rejected back up
         if(lowerWick_i > range_i * wickThreshold)
            rejectionCount++;
      }
   }
   
   // Block if 2 or more rejection wicks detected
   if(rejectionCount >= 2)
   {
      Print("[MULTI_WICK_FILTER] ", isBuy ? "BUY" : "SELL", " blocked - ",
            rejectionCount, " rejection wicks detected in last ", lookback, " candles");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| HasRejectionWickAgainstTrade - Check if candle rejects the trade |
//| For SELL: returns true if candle has long LOWER wick (bullish rejection)
//| For BUY: returns true if candle has long UPPER wick (bearish rejection)
//| A rejection wick indicates price rejected that direction         |
//+------------------------------------------------------------------+
bool HasRejectionWickAgainstTrade(const IndicatorState &ind, bool isBuy)
{
   double open1  = ind.openArr[1];
   double close1 = ind.closeArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];
   
   double body   = MathAbs(close1 - open1);
   double range  = high1 - low1;
   
   if(range <= 0.0) return false;
   
   double upperWick = high1 - MathMax(close1, open1);
   double lowerWick = MathMin(close1, open1) - low1;
   
   // Rejection wick criteria:
   // - Wick is at least 65% of total range (loosened from 50%)
   // - Body is small (less than 30% of range) (tightened from 40%)
   // Only block on very extreme rejection wicks
   double wickThreshold = 0.65;
   double bodyMaxRatio  = 0.30;
   
   if(isBuy)
   {
      // For BUY: check if there's a bearish rejection (long upper wick)
      // This means price tried to go up but was rejected - bad for buy
      if(upperWick > range * wickThreshold && body < range * bodyMaxRatio)
      {
         Print("[REJECTION_WICK_FILTER] BUY blocked - bearish rejection wick detected",
               " upperWick=", DoubleToString(upperWick/_Point, 1), "pts",
               " body=", DoubleToString(body/_Point, 1), "pts");
         return true;
      }
   }
   else // SELL
   {
      // For SELL: check if there's a bullish rejection (long lower wick)
      // This means price tried to go down but was rejected - bad for sell
      if(lowerWick > range * wickThreshold && body < range * bodyMaxRatio)
      {
         Print("[REJECTION_WICK_FILTER] SELL blocked - bullish rejection wick detected",
               " lowerWick=", DoubleToString(lowerWick/_Point, 1), "pts",
               " body=", DoubleToString(body/_Point, 1), "pts");
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| IsBullishZoneType - MAJOR ONLY for live entry path               |
//| Demand/supply/minor are NOT tradable identities in live path     |
//+------------------------------------------------------------------+
bool IsBullishZoneType(ENUM_ZONE_TYPE t)
{
   return (t == ZONE_SUPPORT_MAJOR);
}

//+------------------------------------------------------------------+
//| IsBearishZoneType - MAJOR ONLY for live entry path               |
//| Demand/supply/minor are NOT tradable identities in live path     |
//+------------------------------------------------------------------+
bool IsBearishZoneType(ENUM_ZONE_TYPE t)
{
   return (t == ZONE_RESISTANCE_MAJOR);
}

//+------------------------------------------------------------------+
//| GetAllowedStackCount                                             |
//+------------------------------------------------------------------+
int GetAllowedStackCount(const string setupKey)
{
   double conf = GetSetupConfidence(setupKey);
   if(conf >= 0.80) return 6;
   if(conf >= 0.70) return 4;
   if(conf >= 0.55) return 3;
   if(conf >= 0.50) return 2;
   return 1;
}

//+------------------------------------------------------------------+
//| CanStackMorePositions                                            |
//+------------------------------------------------------------------+
bool CanStackMorePositions(const string setupKey, int currentPositions, int hardMaxPositions)
{
   int allowedByConfidence = GetAllowedStackCount(setupKey);
   int effectiveCap = MathMin(allowedByConfidence, hardMaxPositions);
   return (currentPositions < effectiveCap);
}

//+------------------------------------------------------------------+
//| IsBreakoutBuy                                                    |
//+------------------------------------------------------------------+
bool IsBreakoutBuy(const IndicatorState &ind, int lookback = 10)
{
   if(lookback < 3)  lookback = 3;
   if(lookback > 50) lookback = 50;
   double highestHigh = ind.highArr[2];
   for(int i = 3; i <= lookback && i < 200; i++)
      if(ind.highArr[i] > highestHigh) highestHigh = ind.highArr[i];
   return (ind.closeArr[1] > highestHigh);
}

//+------------------------------------------------------------------+
//| IsBreakoutSell                                                   |
//+------------------------------------------------------------------+
bool IsBreakoutSell(const IndicatorState &ind, int lookback = 10)
{
   if(lookback < 3)  lookback = 3;
   if(lookback > 50) lookback = 50;
   double lowestLow = ind.lowArr[2];
   for(int i = 3; i <= lookback && i < 200; i++)
      if(ind.lowArr[i] < lowestLow) lowestLow = ind.lowArr[i];
   return (ind.closeArr[1] < lowestLow);
}

//+------------------------------------------------------------------+
//| Zone context helpers                                             |
//+------------------------------------------------------------------+
bool IsBullishZoneContext(bool nearZone, ENUM_ZONE_TYPE zoneType)
{
   return (nearZone && IsBullishZoneType(zoneType));
}

bool IsBearishZoneContext(bool nearZone, ENUM_ZONE_TYPE zoneType)
{
   return (nearZone && IsBearishZoneType(zoneType));
}

//+------------------------------------------------------------------+
//| Candle confirmation helpers                                      |
//+------------------------------------------------------------------+
bool HasBullishCandleConfirmation(const string symbol, ENUM_TIMEFRAMES tf,
                                  int shift = 1, int minScore = 3)
{
   return (BullishPatternScore(symbol, tf, shift) >= minScore);
}

bool HasBearishCandleConfirmation(const string symbol, ENUM_TIMEFRAMES tf,
                                  int shift = 1, int minScore = 3)
{
   return (BearishPatternScore(symbol, tf, shift) >= minScore);
}

//+==================================================================+
//| SECTION 2: ENUMS — TRADE MODE, D1 BIAS, ZONE INTERACTION        |
//| Core enumerations used throughout signal logic                   |
//+==================================================================+

//+------------------------------------------------------------------+
//| Trade mode classification                                        |
//| Bull  : EMA50 > EMA200, ADX >= adxTrend, slope up              |
//| Bear  : EMA50 < EMA200, ADX >= adxTrend, slope down            |
//| Range : ADX < adxRange                                          |
//| Developing: ADX between thresholds                              |
//+------------------------------------------------------------------+
enum ENUM_TRADE_MODE
{
   TRADE_MODE_BLOCKED    = 0,
   TRADE_MODE_BULL_TREND = 1,
   TRADE_MODE_BEAR_TREND = 2,
   TRADE_MODE_RANGE      = 3,
   TRADE_MODE_DEVELOPING = 4,
   TRADE_MODE_REVERSAL   = 5
};

// REMOVED: Duplicate MARKET_REGIME enum - use MARKET_REGIME from MarketClassifier.mqh
// Mapping: MARKET_UNKNOWN=0, MARKET_TREND_BULL, MARKET_TREND_BEAR, MARKET_RANGE, MARKET_CONSOLIDATION

// Value aliases for backward compatibility
#define REGIME_NONE           MARKET_UNKNOWN
#define REGIME_TREND_BULL     MARKET_TREND_BULL
#define REGIME_TREND_BEAR     MARKET_TREND_BEAR
#define REGIME_RANGE          MARKET_RANGE
#define REGIME_CONSOLIDATION  MARKET_CONSOLIDATION
// Breakout/reversal now have their own distinct enum values
#define REGIME_BREAKOUT_BULL  MARKET_BREAKOUT_BULL
#define REGIME_BREAKOUT_BEAR  MARKET_BREAKOUT_BEAR
#define REGIME_REVERSAL_BULL  MARKET_REVERSAL_BULL
#define REGIME_REVERSAL_BEAR  MARKET_REVERSAL_BEAR

struct MTFTrendState
{
   bool   valid;
   double d1Ema50, d1Ema200;
   double h4Ema50, h4Ema200;
   double entryEma50, entryEma200;   // H4 execution timeframe
   double entryAdx, entrySlope50, entryClose;
   bool   d1Bull, d1Bear;
   bool   h4Bull, h4Bear;
   bool   entryBull, entryBear;  // H4 execution timeframe
   bool   allBull, allBear;
};

bool ReadSingleTFState(const string symbol, ENUM_TIMEFRAMES tf,
                       int adxPeriod, int slopeLookback,
                       double &ema50_1, double &ema200_1,
                       double &adx_1, double &close_1, double &slope50)
{
   ema50_1 = ema200_1 = adx_1 = close_1 = slope50 = 0.0;
   int barsNeeded = MathMax(6, slopeLookback + 3);
   int hE50  = iMA(symbol, tf, 50,  0, MODE_EMA, PRICE_CLOSE);
   int hE200 = iMA(symbol, tf, 200, 0, MODE_EMA, PRICE_CLOSE);
   int hADX  = iADX(symbol, tf, adxPeriod);
   if(hE50 == INVALID_HANDLE || hE200 == INVALID_HANDLE || hADX == INVALID_HANDLE)
   {
      if(hE50  != INVALID_HANDLE) IndicatorRelease(hE50);
      if(hE200 != INVALID_HANDLE) IndicatorRelease(hE200);
      if(hADX  != INVALID_HANDLE) IndicatorRelease(hADX);
      return false;
   }
   double ema50Buf[], ema200Buf[], adxBuf[];
   ArraySetAsSeries(ema50Buf,  true);
   ArraySetAsSeries(ema200Buf, true);
   ArraySetAsSeries(adxBuf,    true);
   bool ok = (CopyBuffer(hE50,  0, 0, barsNeeded, ema50Buf)  >= barsNeeded &&
              CopyBuffer(hE200, 0, 0, 3,           ema200Buf) >= 3          &&
              CopyBuffer(hADX,  0, 0, 3,           adxBuf)    >= 3);
   IndicatorRelease(hE50);
   IndicatorRelease(hE200);
   IndicatorRelease(hADX);
   if(!ok) return false;
   close_1  = iClose(symbol, tf, 1);
   if(close_1 <= 0.0) return false;
   ema50_1  = ema50Buf[1];
   ema200_1 = ema200Buf[1];
   adx_1    = adxBuf[1];
   slope50  = ema50Buf[1] - ema50Buf[1 + slopeLookback];
   return true;
}

bool BuildMTFTrendState(const string symbol, int slopeLookback, int adxPeriod, MTFTrendState &st)
{
   ZeroMemory(st);
   st.valid = false;
   double d1, d2, d3;
   // Use configured HTF bias timeframe (g_htfBiasTF) for D1-level reads
   if(!ReadSingleTFState(symbol, g_htfBiasTF, adxPeriod, slopeLookback, st.d1Ema50, st.d1Ema200, d1, d2, d3)) return false;
   // Use configured zone timeframe (g_zoneTF) for intermediate reads - typically same as execution
   if(!ReadSingleTFState(symbol, g_zoneTF, adxPeriod, slopeLookback, st.h4Ema50, st.h4Ema200, d1, d2, d3)) return false;
   // Use configured execution timeframe (g_indicatorTF) for entry-level reads
   if(!ReadSingleTFState(symbol, g_indicatorTF, adxPeriod, slopeLookback, st.entryEma50, st.entryEma200, st.entryAdx, st.entryClose, st.entrySlope50)) return false;
   st.d1Bull = (st.d1Ema50 > st.d1Ema200); st.d1Bear = (st.d1Ema50 < st.d1Ema200);
   st.h4Bull = (st.h4Ema50 > st.h4Ema200); st.h4Bear = (st.h4Ema50 < st.h4Ema200);
   st.entryBull = (st.entryEma50 > st.entryEma200); st.entryBear = (st.entryEma50 < st.entryEma200);
   st.allBull = (st.d1Bull && st.h4Bull && st.entryBull);
   st.allBear = (st.d1Bear && st.h4Bear && st.entryBear);
   st.valid = true;
   return true;
}

double AvgBodySize(const IndicatorState &ind, int barsCount)
{
   double sum = 0.0; int used = 0;
   for(int i = 1; i <= barsCount; i++) { sum += MathAbs(ind.closeArr[i] - ind.openArr[i]); used++; }
   return (used > 0 ? sum / used : 0.0);
}

double RecentRangeWidth(const IndicatorState &ind, int barsCount)
{
   double hh = -DBL_MAX, ll = DBL_MAX;
   for(int i = 1; i <= barsCount; i++)
   { if(ind.highArr[i] > hh) hh = ind.highArr[i]; if(ind.lowArr[i] < ll) ll = ind.lowArr[i]; }
   return (hh <= -DBL_MAX / 2 || ll >= DBL_MAX / 2) ? 0.0 : (hh - ll);
}

bool IsCloseConsolidation(const IndicatorState &ind, const MTFTrendState &st,
                          double adxHardBlock = 18.0, double slopeFlatFrac = 0.08,
                          double bodyFrac = 0.22, double rangeFrac = 1.20)
{
   double atr = GetATR(ind, 1);
   if(atr <= 0.0) return false;
   int score = 0;
   if(st.entryAdx < adxHardBlock)                                              score++;
   if(MathAbs(st.entrySlope50) <= atr * slopeFlatFrac)                         score++;
   if(AvgBodySize(ind, 6) <= atr * bodyFrac)                                 score++;
   if(RecentRangeWidth(ind, 10) <= atr * rangeFrac)                          score++;
   if(MathAbs(ind.closeArr[1] - st.entryEma50) <= atr * 0.15 ||
      (ind.closeArr[1] > st.entryEma50) != (ind.closeArr[2] > st.entryEma50))     score++;
   return (score >= 3);
}

//+------------------------------------------------------------------+
//| TIGHT CONSOLIDATION: Zone-width-based detection                  |
//| Returns true if range boundaries are too close for safe trading  |
//+------------------------------------------------------------------+
bool IsTightConsolidation(const IndicatorState &ind,
                          double supportMid,
                          double resistanceMid,
                          double minWidthATR = 3.00,
                          double maxAdxForConsolidation = 22.0,
                          double maxEmaSpreadATR = 1.10)
{
   double atr = GetATR(ind, 1);
   if(atr <= 0.0) return false;

   double localRangeWidth = resistanceMid - supportMid;
   if(localRangeWidth <= 0.0) return false;
   double widthATR = localRangeWidth / atr;

   double ema50Now   = GetEMA50(ind, 1);
   double ema50Prev  = GetEMA50(ind, 2);
   double ema200Now  = GetEMA200(ind, 1);
   double ema200Prev = GetEMA200(ind, 2);
   double adxNow     = GetADX(ind, 1);

   double emaSpread    = MathAbs(ema50Now - ema200Now);
   double emaSpreadATR = (atr > 0.0) ? emaSpread / atr : 999.0;
   double ema50Slope   = MathAbs(ema50Now - ema50Prev);
   double ema200Slope  = MathAbs(ema200Now - ema200Prev);
   double slopeATR50   = (atr > 0.0) ? ema50Slope / atr : 0.0;
   double slopeATR200  = (atr > 0.0) ? ema200Slope / atr : 0.0;
   double recentWidthATR = RecentRangeWidth(ind, 10) / atr;

   int score = 0;

   if(widthATR <= minWidthATR)            score++;   // box too compressed
   if(adxNow <= maxAdxForConsolidation)   score++;   // weak trend pressure
   if(emaSpreadATR <= maxEmaSpreadATR)    score++;   // EMA compression
   if(slopeATR50 <= 0.020)                score++;   // EMA50 flat
   if(slopeATR200 <= 0.015)               score++;   // EMA200 flat
   if(recentWidthATR <= 2.40)             score++;   // candles overlapping / no expansion

   bool hardBlock =
      (widthATR <= 2.20 &&
       adxNow <= 20.0 &&
       emaSpreadATR <= 0.95 &&
       slopeATR50 <= 0.015 &&
       slopeATR200 <= 0.012);

   bool isTight = hardBlock || (score >= 4);

   Print("[CONSOLIDATION_CHECK] widthATR=", DoubleToString(widthATR, 2),
         " adx=", DoubleToString(adxNow, 1),
         " emaSpreadATR=", DoubleToString(emaSpreadATR, 2),
         " slopeATR50=", DoubleToString(slopeATR50, 3),
         " slopeATR200=", DoubleToString(slopeATR200, 3),
         " recentWidthATR=", DoubleToString(recentWidthATR, 2),
         " score=", score,
         " hardBlock=", hardBlock,
         " result=", isTight);

   return isTight;
}

bool IsHorizontalRangeTooTight(double supportUpper, double resistanceLower, double atr)
{
   if(atr <= 0.0) return true;
   double gap = resistanceLower - supportUpper;
   return (gap < atr * 0.90);
}

bool IsTrueRangeState(const IndicatorState &ind, const MTFTrendState &st,
                      double adxRangeMax = 40.0, double slopeFlatFrac = 0.12)
{
   double atr = GetATR(ind, 1);
   if(atr <= 0.0) return false;
   return (!st.allBull && !st.allBear &&
           st.entryAdx < adxRangeMax &&
           MathAbs(st.entrySlope50) <= atr * slopeFlatFrac);
}

//+------------------------------------------------------------------+
//| EMA200 BIAS HELPERS - broad market context only                  |
//| These do NOT create trades by themselves                         |
//+------------------------------------------------------------------+
bool IsBullBiasByEMA200(const IndicatorState &ind)
{
   double price      = ind.closeArr[1];
   double ema200Now  = GetEMA200(ind, 1);
   double ema200Prev = GetEMA200(ind, 2);
   if(ema200Now <= 0 || ema200Prev <= 0) return false;
   return (price > ema200Now && ema200Now >= ema200Prev);
}

bool IsBearBiasByEMA200(const IndicatorState &ind)
{
   double price      = ind.closeArr[1];
   double ema200Now  = GetEMA200(ind, 1);
   double ema200Prev = GetEMA200(ind, 2);
   if(ema200Now <= 0 || ema200Prev <= 0) return false;
   return (price < ema200Now && ema200Now <= ema200Prev);
}

//+------------------------------------------------------------------+
//| EMA200 rank bonus - broad directional filter ONLY                 |
//| Simplified: uses only EMA50 vs EMA200 relationship               |
//| EMA20/EMA100 stack logic removed per EMA simplification          |
//+------------------------------------------------------------------+
double GetEMA200RankAdjustment(const IndicatorState &ind, bool isBuy)
{
   double bonus = 0.0;
   double ema50  = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   double price  = ind.closeArr[1];
   
   if(ema50 <= 0 || ema200 <= 0) return 0.0;
   
   bool bullBroad = (ema50 > ema200 && price > ema200);
   bool bearBroad = (ema50 < ema200 && price < ema200);
   
   if(isBuy)
   {
      if(bullBroad)
         bonus += 0.15;
      if(bearBroad)
         bonus -= 0.10;
   }
   else
   {
      if(bearBroad)
         bonus += 0.15;
      if(bullBroad)
         bonus -= 0.10;
   }
   
   return bonus;
}

//+------------------------------------------------------------------+
//| Check if EMA200 broad filter strongly disagrees with setup       |
//| Simplified: uses only EMA50 vs EMA200 and price vs EMA200        |
//| EMA100 logic removed per EMA simplification                      |
//+------------------------------------------------------------------+
bool IsAllEMAsStronglyAgainst(const IndicatorState &ind, bool isBuy)
{
   double price      = ind.closeArr[1];
   double ema50Now   = GetEMA50(ind, 1);
   double ema200Now  = GetEMA200(ind, 1);
   double ema200Prev = GetEMA200(ind, 2);
   double atr        = GetATR(ind, 1);
   if(ema50Now <= 0 || ema200Now <= 0 || atr <= 0) return false;
   
   if(isBuy)
   {
      // Strongly against BUY: price well below EMA200, EMA50 below EMA200, EMA200 falling
      bool priceUnder200 = (price < ema200Now - atr * 0.5);
      bool ema50Under200 = (ema50Now < ema200Now);
      bool ema200Falling = (ema200Now < ema200Prev);
      return (priceUnder200 && ema50Under200 && ema200Falling);
   }
   else
   {
      // Strongly against SELL: price well above EMA200, EMA50 above EMA200, EMA200 rising
      bool priceAbove200 = (price > ema200Now + atr * 0.5);
      bool ema50Above200 = (ema50Now > ema200Now);
      bool ema200Rising  = (ema200Now > ema200Prev);
      return (priceAbove200 && ema50Above200 && ema200Rising);
   }
}

//+------------------------------------------------------------------+
//| Derive regime from MarketStructure swing state (primary source)  |
//| Thin adapter mapping ENUM_STRUCTURE_STATE → ENUM_MARKET_REGIME   |
//+------------------------------------------------------------------+
MARKET_REGIME GetRegimeFromMarketStructure()
{
   if(!g_structure.valid) return MARKET_UNKNOWN;

   // Map structure states to market regimes
   switch(g_structure.state)
   {
      case STRUCTURE_BULL_TREND:
      case STRUCTURE_BIAS_BULL:
         return MARKET_TREND_BULL;
         
      case STRUCTURE_BEAR_TREND:
      case STRUCTURE_BIAS_BEAR:
         return MARKET_TREND_BEAR;
         
      case STRUCTURE_RANGE:
         return MARKET_RANGE;
         
      case STRUCTURE_CONSOLIDATION:
         return MARKET_CONSOLIDATION;
         
      default:
         return MARKET_UNKNOWN;
   }
}

//+------------------------------------------------------------------+
//| Fallback regime classifier using global g_classifier             |
//| Called when g_structure is not valid yet                        |
//+------------------------------------------------------------------+
MARKET_REGIME GetFallbackRegimeFromClassifier(const IndicatorState &ind, bool logIt = true)
{
   double ema50 = GetEMA50(ind, 1);
   double ema50Prev = GetEMA50(ind, g_classifier.GetSlopeLookback() + 1);
   double atr = GetATR(ind, 1);
   double atrAvg = GetATR(ind, 10);
   double ema200 = GetEMA200(ind, 1);
   double adx = GetADX(ind, 1);
   
   MARKET_REGIME regime = g_classifier.Classify(ind.closeArr[1], ema50, ema50Prev, atr, atrAvg, ema200, adx);
   
   if(logIt)
   {
      Print("[FALLBACK_REGIME] regime=", g_classifier.ToString(regime),
            " close=", ind.closeArr[1], " ema50=", ema50, " adx=", adx);
   }
   
   return regime;
}

//+------------------------------------------------------------------+
//| DEPRECATED: ClassifyMarketRegime - Thin wrapper for compatibility|
//| Use GetRegimeFromMarketStructure() or GetFallbackRegimeFromClassifier() |
//+------------------------------------------------------------------+
MARKET_REGIME ClassifyMarketRegime(const IndicatorState &ind,
                                   int slopeLookback = 3, int adxPeriod = 14,
                                   double adxTrend = 22.0, double adxRange = 20.0,
                                   bool logIt = true)
{
   // Prefer structure-based regime when available
   if(g_structure.valid)
      return GetRegimeFromMarketStructure();
   
   // Fallback: delegate to MarketClassifier
   return GetFallbackRegimeFromClassifier(ind, logIt);
}

//+------------------------------------------------------------------+
//| Mode-aware bullish pattern check                                 |
//| Routes to trend/range/breakout patterns based on trade mode      |
//+------------------------------------------------------------------+
bool HasModeAwareBullishPattern(const IndicatorState &ind,
                                 ENUM_TRADE_MODE mode,
                                 double zoneLow, double zoneHigh,
                                 double atr)
{
   string sym = _Symbol;
   ENUM_TIMEFRAMES tf = g_indicatorTF;

   switch(mode)
   {
      case TRADE_MODE_BULL_TREND:
      case TRADE_MODE_DEVELOPING:
         // Trend continuation at pullback/support
         if(IsBullishRejection(ind))                         return true;
         if(IsTrendBullishPinRejection(sym, tf, 1))         return true;
         if(IsTrendBullishContinuation(sym, tf, 1))         return true;
         if(IsTrendInsideBarBreakoutBull(sym, tf, 1))       return true;
         return false;

      case TRADE_MODE_RANGE:
      case TRADE_MODE_REVERSAL:
         // Range reversal at support
         if(zoneLow > 0.0 && atr > 0.0 &&
            IsFalseBreakRangeLow(ind.lowArr, ind.closeArr, zoneLow, atr))
            return true;

         if(atr > 0.0 && IsDoubleBottom(ind.lowArr, ind.highArr, ind.closeArr, ind.openArr, atr))
            return true;

         if(atr > 0.0 && IsInverseHeadAndShouldersBottom(ind.lowArr, ind.highArr, atr))
            return true;

         if(zoneLow > 0.0 && zoneHigh > 0.0 &&
            IsRangeBullishRejection(sym, tf, 1, zoneLow, zoneHigh))
            return true;

         return false;

      case TRADE_MODE_BLOCKED:
         return false;

      default:
         // Do not use generic fallback for unknown mode
         return false;
   }
}

//+------------------------------------------------------------------+
//| Mode-aware bearish pattern check                                 |
//+------------------------------------------------------------------+
bool HasModeAwareBearishPattern(const IndicatorState &ind,
                                 ENUM_TRADE_MODE mode,
                                 double zoneLow, double zoneHigh,
                                 double atr)
{
   string sym = _Symbol;
   ENUM_TIMEFRAMES tf = g_indicatorTF;

   switch(mode)
   {
      case TRADE_MODE_BEAR_TREND:
      case TRADE_MODE_DEVELOPING:
         // Trend continuation at pullback/resistance
         if(IsBearishRejection(ind))                         return true;
         if(IsTrendBearishPinRejection(sym, tf, 1))         return true;
         if(IsTrendBearishContinuation(sym, tf, 1))         return true;
         if(IsTrendInsideBarBreakoutBear(sym, tf, 1))       return true;
         return false;

      case TRADE_MODE_RANGE:
      case TRADE_MODE_REVERSAL:
         // Range reversal at resistance
         if(zoneHigh > 0.0 && atr > 0.0 &&
            IsFalseBreakRangeHigh(ind.highArr, ind.closeArr, zoneHigh, atr))
            return true;

         if(atr > 0.0 && IsDoubleTop(ind.highArr, ind.lowArr, ind.closeArr, ind.openArr, atr))
            return true;

         if(atr > 0.0 && IsHeadAndShouldersTop(ind.highArr, ind.lowArr, atr))
            return true;

         if(zoneLow > 0.0 && zoneHigh > 0.0 &&
            IsRangeBearishRejection(sym, tf, 1, zoneLow, zoneHigh))
            return true;

         return false;

      case TRADE_MODE_BLOCKED:
         return false;

      default:
         return false;
   }
}

//+------------------------------------------------------------------+
//| Persistent zone structure query helpers                          |
//| All use local ZoneInfo copies — no array reference variables     |
//+------------------------------------------------------------------+

bool IsNewDemandInsideOldSupport(double price, double atrVal)
{
   for(int f = 0; f < g_zoneReg.count; f++)
   {
      ZoneInfo fz = g_zoneReg.zones[f];
      if(!fz.active || fz.historical) continue;
      if(fz.type != ZONE_DEMAND) continue;
      if(!(price >= fz.lowerBound && price <= fz.upperBound)) continue;

      if(fz.relatedHistoricalZoneId > 0)
      {
         int hIdx = FindZoneById(fz.relatedHistoricalZoneId);
         if(hIdx >= 0)
         {
            ZoneInfo hz = g_zoneReg.zones[hIdx];
            if(hz.type == ZONE_SUPPORT_MAJOR || hz.type == ZONE_DEMAND)
               return true;
         }
      }
      for(int h = 0; h < g_zoneReg.count; h++)
      {
         ZoneInfo hz = g_zoneReg.zones[h];
         if(!hz.historical || !hz.protectedKeyZone) continue;
         if(hz.type != ZONE_SUPPORT_MAJOR && hz.type != ZONE_DEMAND) continue;
         if(fz.lowerBound >= hz.lowerBound && fz.upperBound <= hz.upperBound)
            return true;
      }
   }
   return false;
}

bool IsNewResistanceAtOldBrokenSupport(double price, double atrVal)
{
   double prox = MathMax(atrVal * 0.5, 0.0001);
   for(int f = 0; f < g_zoneReg.count; f++)
   {
      ZoneInfo fz = g_zoneReg.zones[f];
      if(!fz.active || fz.historical) continue;
      if(!IsBearishZone(fz.type)) continue;
      if(!fz.isFlipZone) continue;
      if(MathAbs(price - fz.midPoint) <= prox) return true;
   }
   return false;
}

bool IsSetupAlignedWithHistoricalKeyLevel(double price, bool isBuy, double atrVal)
{
   int idx = FindNearestProtectedHistoricalZone(price, isBuy);
   if(idx < 0) return false;
   ZoneInfo z = g_zoneReg.zones[idx];
   double prox = MathMax(atrVal * 0.8, 0.0001);
   double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
               : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
   return (d <= prox);
}

bool IsSetupNearRefinementZone(double price, bool isBuy, double atrVal)
{
   double prox = MathMax(atrVal * 0.5, 0.0001);
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      if(!z.isRefinement) continue;
      if(isBuy  && !IsBullishZone(z.type)) continue;
      if(!isBuy && !IsBearishZone(z.type)) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Quality-filtered zone entry helpers                              |
//+------------------------------------------------------------------+

bool IsQualityBuyZoneNearby(double price, const SymbolProfile &prof,
                            double minScore, double minFreshness,
                            double proximityOverride = 0.0)
{
   double prox = (proximityOverride > 0) ? proximityOverride
                  : prof.defaultMinTrendGapPoints * prof.point;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      if(!z.valid) continue;
      if(!IsBullishZone(z.type)) continue;
      if(z.score < minScore) continue;
      if(z.freshness < minFreshness) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox) return true;
   }
   return false;
}

bool IsQualitySellZoneNearby(double price, const SymbolProfile &prof,
                             double minScore, double minFreshness,
                             double proximityOverride = 0.0)
{
   double prox = (proximityOverride > 0) ? proximityOverride
                  : prof.defaultMinTrendGapPoints * prof.point;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      if(!z.valid) continue;
      if(!IsBearishZone(z.type)) continue;
      if(z.score < minScore) continue;
      if(z.freshness < minFreshness) continue;
      double d = (price >= z.lowerBound && price <= z.upperBound) ? 0.0
                  : MathMin(MathAbs(price - z.upperBound), MathAbs(price - z.lowerBound));
      if(d <= prox) return true;
   }
   return false;
}

bool HasZoneRejectionConfirmation(double price, bool isBuy)
{
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      if(!z.valid) continue;
      if(!z.hasRejection) continue;
      if(isBuy  && !IsBullishZone(z.type)) continue;
      if(!isBuy && !IsBearishZone(z.type)) continue;
      double d = MathAbs(price - z.midPoint);
      double w = z.upperBound - z.lowerBound;
      if(d <= w * 2.0) return true;
   }
   return false;
}


//+------------------------------------------------------------------+
//| Zone interaction classification                                  |
//+------------------------------------------------------------------+
enum ENUM_ZONE_INTERACTION
{
   ZONE_INTERACTION_NONE          = 0,
   ZONE_INTERACTION_REJECTION     = 1,
   ZONE_INTERACTION_BREAKRETEST   = 2,
   ZONE_INTERACTION_SWEEP_RECLAIM = 3
};

string InteractionToString(ENUM_ZONE_INTERACTION t)
{
   switch(t)
   {
      case ZONE_INTERACTION_REJECTION:     return "REJECTION";
      case ZONE_INTERACTION_BREAKRETEST:   return "BREAK_RETEST";
      case ZONE_INTERACTION_SWEEP_RECLAIM: return "SWEEP_RECLAIM";
      default:                             return "NONE";
   }
}



double ZoneDistanceFromPriceATR(const ZoneInfo &z, double price, double atr)
{
   if(atr <= 0.0) return 999.0;
   if(price >= z.lowerBound && price <= z.upperBound) return 0.0;

   if(price < z.lowerBound)
      return (z.lowerBound - price) / atr;

   return (price - z.upperBound) / atr;
}

bool IsEligibleDirectionalTrendZone(const ZoneInfo &z, bool isBuy)
{
   if(!z.active || z.historical || !z.valid || z.traded)
      return false;

   if(isBuy)
   {
      bool baseBull = (z.type == ZONE_SUPPORT_MAJOR);

      bool bullFlip = (z.broken &&
                       z.breakRetestReady &&
                       z.continuationEligible &&
                       z.type == ZONE_RESISTANCE_MAJOR);

      return (baseBull || bullFlip);
   }

   bool baseBear = (z.type == ZONE_RESISTANCE_MAJOR);

   bool bearFlip = (z.broken &&
                    z.breakRetestReady &&
                    z.continuationEligible &&
                    z.type == ZONE_SUPPORT_MAJOR);

   return (baseBear || bearFlip);
}

bool IsEligibleDirectionalRangeZone(const ZoneInfo &z, bool isBuy)
{
   if(!z.active || z.historical || !z.valid || z.traded || z.broken)
      return false;

   // P7: Unconfirmed flip zones may not anchor range boundaries
   if(z.isFlipZone && (z.retestCount < 1 || z.failedRetest))
      return false;

   if(isBuy)
      return (z.type == ZONE_SUPPORT_MAJOR);

   return (z.type == ZONE_RESISTANCE_MAJOR);
}




//+==================================================================+
//| SECTION 3: ENTRY DECISION STRUCT & FACTORY                      |
//| EntryDecision result + MakeEmptyDecision factory                 |
//+==================================================================+

//+------------------------------------------------------------------+
//| Entry decision result struct                                     |
//+------------------------------------------------------------------+
struct EntryDecision
{
   bool                  valid;
   bool                  isBuy;
   int                   zoneIdx;
   double                stopLoss;
   double                takeProfit;
   ENUM_TRADE_MODE       mode;
   string                reason;
   int                   targetZoneIdx;
   double                projectedRR;
   bool                  usedZoneTarget;
   double                rankScore;
   ENUM_ZONE_INTERACTION interactionType;
};

EntryDecision MakeEmptyDecision()
{
   EntryDecision d;
   d.valid          = false;
   d.isBuy          = false;
   d.zoneIdx        = -1;
   d.stopLoss        = 0.0;
   d.takeProfit      = 0.0;
   d.mode           = TRADE_MODE_BLOCKED;
   d.reason         = "";
   d.targetZoneIdx  = -1;
   d.projectedRR    = 0.0;
   d.usedZoneTarget = false;
   d.rankScore      = -1.0;
   d.interactionType = ZONE_INTERACTION_NONE;
   return d;
}


//+==================================================================+
//| SECTION 4: ZONE & STRUCTURAL HELPERS                            |
//| Zone proximity queries, structural checks, SL reference logic   |
//+==================================================================+

int FindNextMajorOppositeZone(bool isBuy, double price, double atr, double &outMid)
{
   outMid = 0.0;
   int bestIdx = -1;
   double bestDist = DBL_MAX;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;
      if(!z.valid) continue;
      if(z.historical) continue;
      if(isBuy)
      {
         if(z.type != ZONE_RESISTANCE_MAJOR) continue;
         if(z.midPoint <= price + atr * 0.30) continue;
         double dist = z.midPoint - price;
         if(dist < bestDist)
         {
            bestDist = dist;
            bestIdx = i;
            outMid = z.midPoint;
         }
      }
      else
      {
         if(z.type != ZONE_SUPPORT_MAJOR) continue;
         if(z.midPoint >= price - atr * 0.30) continue;
         double dist = price - z.midPoint;
         if(dist < bestDist)
         {
            bestDist = dist;
            bestIdx = i;
            outMid = z.midPoint;
         }
      }
   }

   if(bestIdx >= 0)
      Print("[TP_TARGET] side=", isBuy ? "BUY" : "SELL",
            " targetIdx=", bestIdx,
            " targetMid=", DoubleToString(outMid, _Digits),
            " distATR=", DoubleToString(bestDist / atr, 2));
   else
      Print("[TP_TARGET] side=", isBuy ? "BUY" : "SELL",
            " result=no_major_opposite_zone");

   return bestIdx;
}

//+------------------------------------------------------------------+
//| Find next MAJOR resistance zone above price (for BUY TP target)  |
//+------------------------------------------------------------------+
bool FindNextMajorResistanceZoneAbove(double price, double atrVal,
                                      int &zoneIdx, double &zoneLow, double &zoneHigh)
{
   zoneIdx  = -1;
   zoneLow  = 0.0;
   zoneHigh = 0.0;

   double minGap   = (atrVal > 0.0) ? atrVal * 0.50 : _Point * 50;
   double bestDist = DBL_MAX;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.broken || z.historical) continue;
      if(!z.valid) continue;
      
      // Filter for active zones only when trading Supply/Demand
      if(InpUseSupplyDemandZones && InpSDTradeOnlyActivePair && !SDIsActiveTradingZone(z))
         continue;
      
      if(z.type != ZONE_RESISTANCE_MAJOR) continue;
      if(z.score <= 0.0) continue;
      if(z.lowerBound < price + minGap) continue;

      double dist = z.lowerBound - price;
      if(dist < bestDist)
      {
         bestDist = dist;
         zoneIdx  = i;
         zoneLow  = z.lowerBound;
         zoneHigh = z.upperBound;
      }
   }

   return (zoneIdx >= 0);
}

//+------------------------------------------------------------------+
//| Find next MAJOR support zone below price (for SELL TP target)    |
//+------------------------------------------------------------------+
bool FindNextMajorSupportZoneBelow(double price, double atrVal,
                                   int &zoneIdx, double &zoneLow, double &zoneHigh)
{
   zoneIdx  = -1;
   zoneLow  = 0.0;
   zoneHigh = 0.0;

   double minGap   = (atrVal > 0.0) ? atrVal * 0.50 : _Point * 50;
   double bestDist = DBL_MAX;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.broken || z.historical) continue;
      if(!z.valid) continue;
      
      // Filter for active zones only when trading Supply/Demand
      if(InpUseSupplyDemandZones && InpSDTradeOnlyActivePair && !SDIsActiveTradingZone(z))
         continue;
      
      if(z.type != ZONE_SUPPORT_MAJOR) continue;
      if(z.score <= 0.0) continue;
      if(z.upperBound > price - minGap) continue;

      double dist = price - z.upperBound;
      if(dist < bestDist)
      {
         bestDist = dist;
         zoneIdx  = i;
         zoneLow  = z.lowerBound;
         zoneHigh = z.upperBound;
      }
   }

   return (zoneIdx >= 0);
}

EntryDecision BuildDecisionFromSpecificZone(bool isBuy,
                                            int zoneIdx,
                                            ENUM_ZONE_INTERACTION interaction,
                                            const IndicatorState &ind,
                                            const SymbolProfile &prof,
                                            double stopMult,
                                            double rr,
                                            ENUM_TRADE_MODE mode)
{
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = isBuy;

   if(zoneIdx < 0 || zoneIdx >= g_zoneReg.count)
   {
      out.reason = "invalid armed zone";
      return out;
   }

   ZoneInfo z = g_zoneReg.zones[zoneIdx];
   
   if(InpUseSupplyDemandZones && InpSDTradeOnlyActivePair && !SDIsActiveTradingZone(z))
   {
      out.reason = "blocked: non-active Supply/Demand zone";
      return out;
   }
   
   double atr   = GetATR(ind, 1);
   
   // Entry price: always use current close as projected RR basis
   // Execution uses live ask/bid; close[1] is the closest approximation without a live tick here
   // SL is still anchored to zone/wick extremes — this just ensures RR is not distorted by synthetic zone-boundary entry
   double price = ind.closeArr[1];
   Print("[DECISION_ENTRY_BASIS] interaction=", (int)interaction,
         " price_basis=close[1]=", DoubleToString(price, prof.digits),
         " zone_mid=", DoubleToString(z.midPoint, prof.digits));

   if(atr <= 0.0)
   {
      out.reason = "ATR<=0";
      return out;
   }

   double slBuffer = atr * MathMax(stopMult, 0.40);
   if(interaction == ZONE_INTERACTION_SWEEP_RECLAIM)
      slBuffer = atr * MathMax(stopMult, 0.50);

   // Find local wick extremes from recent candles
   double lowestWick  = ind.lowArr[1];
   double highestWick = ind.highArr[1];
   for(int i = 2; i <= 5; i++)
   {
      if(ind.lowArr[i] < lowestWick)   lowestWick  = ind.lowArr[i];
      if(ind.highArr[i] > highestWick) highestWick = ind.highArr[i];
   }

   // CAP wick override so one distant spike cannot blow out the stop
   double maxWickOvershootATR = 1.00;
   double maxAnchorFromZone   = atr * maxWickOvershootATR;

   double sl = 0.0;
   if(isBuy)
   {
      double cappedWickLow = MathMax(lowestWick, z.lowerBound - maxAnchorFromZone);
      double anchor        = MathMin(z.lowerBound, cappedWickLow);
      sl = anchor - slBuffer;

      Print("[STOP_BUILD] type=BUY zoneLow=", DoubleToString(z.lowerBound, prof.digits),
            " wickLow=", DoubleToString(lowestWick, prof.digits),
            " cappedWickLow=", DoubleToString(cappedWickLow, prof.digits),
            " anchor=", DoubleToString(anchor, prof.digits),
            " buffer=", DoubleToString(slBuffer, prof.digits),
            " finalSL=", DoubleToString(sl, prof.digits));
   }
   else // SELL
   {
      double cappedWickHigh = MathMin(highestWick, z.upperBound + maxAnchorFromZone);
      double anchor         = MathMax(z.upperBound, cappedWickHigh);
      sl = anchor + slBuffer;

      Print("[STOP_BUILD] type=SELL zoneHigh=", DoubleToString(z.upperBound, prof.digits),
            " wickHigh=", DoubleToString(highestWick, prof.digits),
            " cappedWickHigh=", DoubleToString(cappedWickHigh, prof.digits),
            " anchor=", DoubleToString(anchor, prof.digits),
            " buffer=", DoubleToString(slBuffer, prof.digits),
            " finalSL=", DoubleToString(sl, prof.digits));
   }

   sl = NormalizeDouble(sl, prof.digits);

   double risk = isBuy ? (price - sl) : (sl - price);
   if(risk <= prof.stopsLevelPoints * prof.point)
   {
      out.reason = "risk too small";
      return out;
   }

   // --- Zone-based TP targeting: find next major opposite zone ---
   double tp = 0.0;
   bool usedZoneTarget = false;

   bool isTrendMode = (mode == TRADE_MODE_BULL_TREND ||
                       mode == TRADE_MODE_BEAR_TREND ||
                       mode == TRADE_MODE_DEVELOPING);
   bool isRangeMode = (mode == TRADE_MODE_RANGE || mode == TRADE_MODE_REVERSAL);

   // TP buffer: RANGE gets larger buffer (0.40 ATR) to take profit before zone
   //            TREND gets smaller buffer (0.15 ATR) to let trends run
   double tpBuffer = isRangeMode ? atr * 0.40 : atr * 0.15;

   int targetIdx = -1;
   double targetLow = 0.0, targetHigh = 0.0;

   if(isBuy)
   {
      if(FindNextMajorResistanceZoneAbove(price, atr, targetIdx, targetLow, targetHigh))
      {
         tp = NormalizeDouble(targetLow - tpBuffer, prof.digits);
         usedZoneTarget = true;
         string zoneModeLabel = (mode == TRADE_MODE_RANGE ? "RANGE" :
                                (mode == TRADE_MODE_REVERSAL ? "REVERSAL" : "TREND"));
         Print("[ZONE_TARGET] BUY mode=", zoneModeLabel,
               " targetIdx=", targetIdx,
               " low=", DoubleToString(targetLow, prof.digits),
               " high=", DoubleToString(targetHigh, prof.digits),
               " buffer=", DoubleToString(tpBuffer, prof.digits),
               " tp=", DoubleToString(tp, prof.digits));
      }
   }
   else
   {
      if(FindNextMajorSupportZoneBelow(price, atr, targetIdx, targetLow, targetHigh))
      {
         tp = NormalizeDouble(targetHigh + tpBuffer, prof.digits);
         usedZoneTarget = true;
         string zoneModeLabel = (mode == TRADE_MODE_RANGE ? "RANGE" :
                                (mode == TRADE_MODE_REVERSAL ? "REVERSAL" : "TREND"));
         Print("[ZONE_TARGET] SELL mode=", zoneModeLabel,
               " targetIdx=", targetIdx,
               " low=", DoubleToString(targetLow, prof.digits),
               " high=", DoubleToString(targetHigh, prof.digits),
               " buffer=", DoubleToString(tpBuffer, prof.digits),
               " tp=", DoubleToString(tp, prof.digits));
      }
   }

   // Fallback to RR-based TP if no zone target found
   if(tp <= 0.0)
   {
      tp = isBuy
         ? NormalizeDouble(price + risk * rr, prof.digits)
         : NormalizeDouble(price - risk * rr, prof.digits);
   }

   double projRR = ComputeProjectedRR(price, sl, tp);
   if(projRR < 1.0)
   {
      out.reason = StringFormat("RR too small %.2f (zone TP)", projRR);
      Print("[DECISION_REJECT] side=", isBuy ? "BUY" : "SELL",
            " reason=zone_rr_too_small projRR=", DoubleToString(projRR, 2));
      return out;
   }

   out.valid = true;
   out.mode = mode;
   out.zoneIdx = zoneIdx;
   out.stopLoss = sl;
   out.takeProfit = tp;
   out.projectedRR = projRR;
   out.usedZoneTarget = usedZoneTarget;
   out.rankScore = 0.0;
   out.interactionType = interaction;
   out.reason = StringFormat("%s | %s | entry=%.5f | zone=[%.5f,%.5f] | SL=%.5f | TP=%.5f(zoneTarget=%s) | RR=%.2f",
                             isBuy ? ((mode == TRADE_MODE_RANGE) ? "RANGE BUY" :
                                      (mode == TRADE_MODE_REVERSAL ? "REVERSAL BUY" : "TREND BUY"))
                                   : ((mode == TRADE_MODE_RANGE) ? "RANGE SELL" :
                                      (mode == TRADE_MODE_REVERSAL ? "REVERSAL SELL" : "TREND SELL")),
                             InteractionToString(interaction),
                             price,
                             z.lowerBound, z.upperBound,
                             sl, tp, usedZoneTarget ? "true" : "false",
                             projRR);
   return out;
}

//+------------------------------------------------------------------+
//| PATCH 1 — TrendPullbackSignal struct                             |
//+------------------------------------------------------------------+
struct TrendPullbackSignal
{
   bool   valid;
   bool   isBuy;
   bool   nearEMA50;
   bool   nearTrendZone;
   int    zoneIdx;
   double entryPrice;
   double stopLoss;
   double takeProfit;
   double projectedRR;
   double score;
   string reason;
};

TrendPullbackSignal MakeEmptyTrendPullbackSignal()
{
   TrendPullbackSignal s;
   s.valid = false;
   s.isBuy = false;
   s.nearEMA50 = false;
   s.nearTrendZone = false;
   s.zoneIdx = -1;
   s.entryPrice = 0.0;
   s.stopLoss = 0.0;
   s.takeProfit = 0.0;
   s.projectedRR = 0.0;
   s.score = 0.0;
   s.reason = "";
   return s;
}

//+------------------------------------------------------------------+
//| PATCH 2 — H4 EMA50 proximity + continuation candle checks        |
//+------------------------------------------------------------------+
bool IsNearH4EMA50(const IndicatorState &ind, double atrFrac = 0.35)
{
   double atr = GetATR(ind, 1);
   double ema50 = GetEMA50(ind, 1);
   double low1 = ind.lowArr[1];
   double high1 = ind.highArr[1];

   if(atr <= 0.0 || ema50 <= 0.0) return false;

   return (low1 <= ema50 + atr * atrFrac && high1 >= ema50 - atr * atrFrac);
}

bool IsBullishContinuationAtEMA50(const IndicatorState &ind)
{
   double atr = GetATR(ind, 1);
   double ema50 = GetEMA50(ind, 1);
   double low1 = ind.lowArr[1];
   double close1 = ind.closeArr[1];
   double open1 = ind.openArr[1];

   if(IsBullishEngulfing(_Symbol, g_indicatorTF, 1)) return true;
   if(IsBullishPinBar(_Symbol, g_indicatorTF, 1)) return true;
   if(IsBullishWickRejection(_Symbol, g_indicatorTF, 1, 0.40, 0.45, true)) return true;
   if(IsTrendBullishContinuation(_Symbol, g_indicatorTF, 1)) return true;

   if(atr > 0.0 && ema50 > 0.0)
   {
      bool pullbackTouch = (low1 <= ema50 + atr * 0.25);
      bool reclaimClose = (close1 > ema50);
      bool bullishBody = (close1 > open1);
      if(pullbackTouch && reclaimClose && bullishBody)
         return true;
   }

   return false;
}

bool IsBearishContinuationAtEMA50(const IndicatorState &ind)
{
   double atr = GetATR(ind, 1);
   double ema50 = GetEMA50(ind, 1);
   double high1 = ind.highArr[1];
   double close1 = ind.closeArr[1];
   double open1 = ind.openArr[1];

   if(IsBearishEngulfing(_Symbol, g_indicatorTF, 1)) return true;
   if(IsBearishPinBar(_Symbol, g_indicatorTF, 1)) return true;
   if(IsBearishWickRejection(_Symbol, g_indicatorTF, 1, 0.40, 0.45, true)) return true;
   if(IsTrendBearishContinuation(_Symbol, g_indicatorTF, 1)) return true;

   if(atr > 0.0 && ema50 > 0.0)
   {
      bool pullbackTouch = (high1 >= ema50 - atr * 0.25);
      bool rejectClose = (close1 < ema50);
      bool bearishBody = (close1 < open1);
      if(pullbackTouch && rejectClose && bearishBody)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| PATCH 3 — Trend-side zone confluence (zone = confirmation ONLY)  |
//| HARD RULE: Zones cannot flip trade direction in trend mode.       |
//|   Bull trend => only support/demand zones near EMA50 as confirm  |
//|   Bear trend => only resistance/supply zones near EMA50 as confirm|
//|   Zones do NOT create the trade. They only strengthen the setup.  |
//+------------------------------------------------------------------+
bool IsTrendBuyZoneType(ENUM_ZONE_TYPE zt)
{
   return (zt == ZONE_SUPPORT_MAJOR);
}

bool IsTrendSellZoneType(ENUM_ZONE_TYPE zt)
{
   return (zt == ZONE_RESISTANCE_MAJOR);
}

bool FindNearestTrendConfluenceZone(const IndicatorState &ind,
                                    bool isBuy,
                                    double maxMidDistATR,
                                    int &bestIdx,
                                    double &bestDistATR,
                                    double &bestScore)
{
   bestIdx = -1;
   bestDistATR = DBL_MAX;
   bestScore = -DBL_MAX;

   double atr = GetATR(ind, 1);
   double ema50 = GetEMA50(ind, 1);
   if(atr <= 0.0 || ema50 <= 0.0) return false;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.traded || z.historical) continue;

      // HARD RULE: only same-side zones allowed as confluence
      if(isBuy && !IsTrendBuyZoneType(z.type)) continue;
      if(!isBuy && !IsTrendSellZoneType(z.type)) continue;

      double mid = z.midPoint;
      double distATR = MathAbs(mid - ema50) / atr;
      if(distATR > maxMidDistATR) continue;

      double score = 0.0;
      if(!z.traded) score += 0.5;
      score += z.strength;
      if(z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_RESISTANCE_MAJOR) score += 1.0;
      if(z.isFlipZone) score += 0.5;
      if(z.confirmedRetest) score += 0.5;

      if(score > bestScore || (MathAbs(score - bestScore) < 1e-6 && distATR < bestDistATR))
      {
         bestScore = score;
         bestDistATR = distATR;
         bestIdx = i;
      }
   }

   return (bestIdx >= 0);
}

//+------------------------------------------------------------------+
//| H4 Pullback Continuation Triggers                                 |
//| Entry only on pullback to EMA50 + continuation candle             |
//+------------------------------------------------------------------+

// Check if price pulled back to or near H4 EMA50 then closed above it bullishly
bool IsH4PullbackReclaimBuy(const IndicatorState &ind, double ema50, double atr)
{
   if(atr <= 0.0 || ema50 <= 0.0) return false;
   double low1   = ind.lowArr[1];
   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   // Low touched or dipped below EMA50 (within 0.35 ATR tolerance)
   bool touchedEMA = (low1 <= ema50 + atr * 0.35);
   // Closed above EMA50
   bool closedAbove = (close1 > ema50);
   // Bullish close
   bool bullClose = (close1 > open1);
   return (touchedEMA && closedAbove && bullClose);
}

// Check if price pulled back to or near H4 EMA50 then closed below it bearishly
bool IsH4PullbackReclaimSell(const IndicatorState &ind, double ema50, double atr)
{
   if(atr <= 0.0 || ema50 <= 0.0) return false;
   double high1  = ind.highArr[1];
   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   // High touched or spiked above EMA50 (within 0.35 ATR tolerance)
   bool touchedEMA = (high1 >= ema50 - atr * 0.35);
   // Closed below EMA50
   bool closedBelow = (close1 < ema50);
   // Bearish close
   bool bearClose = (close1 < open1);
   return (touchedEMA && closedBelow && bearClose);
}

// Bullish rejection wick from EMA50 area
bool IsH4RejectionWickBuy(const IndicatorState &ind, double ema50, double atr)
{
   if(atr <= 0.0) return false;
   double low1   = ind.lowArr[1];
   double high1  = ind.highArr[1];
   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   double range  = high1 - low1;
   if(range <= 0.0) return false;
   double lowerWick = MathMin(close1, open1) - low1;
   // Wick > 50% of range, low near EMA50, close in upper half
   bool longLowerWick = (lowerWick > range * 0.50);
   bool lowNearEMA    = (low1 <= ema50 + atr * 0.40 && low1 >= ema50 - atr * 0.40);
   bool closeUpperHalf = (close1 > (high1 + low1) / 2.0);
   return (longLowerWick && lowNearEMA && closeUpperHalf);
}

// Bearish rejection wick from EMA50 area
bool IsH4RejectionWickSell(const IndicatorState &ind, double ema50, double atr)
{
   if(atr <= 0.0) return false;
   double low1   = ind.lowArr[1];
   double high1  = ind.highArr[1];
   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   double range  = high1 - low1;
   if(range <= 0.0) return false;
   double upperWick = high1 - MathMax(close1, open1);
   // Wick > 50% of range, high near EMA50, close in lower half
   bool longUpperWick = (upperWick > range * 0.50);
   bool highNearEMA   = (high1 >= ema50 - atr * 0.40 && high1 <= ema50 + atr * 0.40);
   bool closeLowerHalf = (close1 < (high1 + low1) / 2.0);
   return (longUpperWick && highNearEMA && closeLowerHalf);
}

// Break-retest continuation: broke recent swing high, retested, now continuing
bool IsH4BreakRetestBuy(const IndicatorState &ind, double atr, int lookback = 10)
{
   if(atr <= 0.0 || lookback < 3) return false;
   // Find recent swing high (bars 3 to lookback)
   double swingHigh = ind.highArr[3];
   for(int i = 4; i <= lookback && i < 200; i++)
      if(ind.highArr[i] > swingHigh) swingHigh = ind.highArr[i];
   // Bar 2 broke above swing high
   bool brokeAbove = (ind.closeArr[2] > swingHigh);
   // Bar 1 retested (low near swing high) and closed above it bullishly
   bool retested = (ind.lowArr[1] <= swingHigh + atr * 0.30 && ind.lowArr[1] >= swingHigh - atr * 0.50);
   bool continuation = (ind.closeArr[1] > swingHigh && ind.closeArr[1] > ind.openArr[1]);
   return (brokeAbove && retested && continuation);
}

// Break-retest continuation: broke recent swing low, retested, now continuing
bool IsH4BreakRetestSell(const IndicatorState &ind, double atr, int lookback = 10)
{
   if(atr <= 0.0 || lookback < 3) return false;
   // Find recent swing low (bars 3 to lookback)
   double swingLow = ind.lowArr[3];
   for(int i = 4; i <= lookback && i < 200; i++)
      if(ind.lowArr[i] < swingLow) swingLow = ind.lowArr[i];
   // Bar 2 broke below swing low
   bool brokeBelow = (ind.closeArr[2] < swingLow);
   // Bar 1 retested (high near swing low) and closed below it bearishly
   bool retested = (ind.highArr[1] >= swingLow - atr * 0.30 && ind.highArr[1] <= swingLow + atr * 0.50);
   bool continuation = (ind.closeArr[1] < swingLow && ind.closeArr[1] < ind.openArr[1]);
   return (brokeBelow && retested && continuation);
}

// Combined H4 pullback continuation trigger for BUY
bool IsH4PullbackContinuationBuy(const IndicatorState &ind, double ema50, double atr)
{
   string sym = _Symbol;
   ENUM_TIMEFRAMES tf = g_indicatorTF;
   // 1. Pullback to EMA50 then bullish reclaim
   if(IsH4PullbackReclaimBuy(ind, ema50, atr)) return true;
   // 2. Bullish engulfing after pullback
   if(IsBullishEngulfing(sym, tf, 1) && ind.lowArr[1] <= ema50 + atr * 0.50) return true;
   // 3. Bullish rejection wick from EMA50
   if(IsH4RejectionWickBuy(ind, ema50, atr)) return true;
   // 4. Break-retest continuation
   if(IsH4BreakRetestBuy(ind, atr)) return true;
   return false;
}

// Combined H4 pullback continuation trigger for SELL
bool IsH4PullbackContinuationSell(const IndicatorState &ind, double ema50, double atr)
{
   string sym = _Symbol;
   ENUM_TIMEFRAMES tf = g_indicatorTF;
   // 1. Pullback to EMA50 then bearish reject
   if(IsH4PullbackReclaimSell(ind, ema50, atr)) return true;
   // 2. Bearish engulfing after pullback
   if(IsBearishEngulfing(sym, tf, 1) && ind.highArr[1] >= ema50 - atr * 0.50) return true;
   // 3. Bearish rejection wick from EMA50
   if(IsH4RejectionWickSell(ind, ema50, atr)) return true;
   // 4. Break-retest continuation
   if(IsH4BreakRetestSell(ind, atr)) return true;
   return false;
}

bool IsOverstretchedBuy(const IndicatorState &ind, double maxAtr = 1.80)
{
   double atr = GetATR(ind, 1); double ema50 = GetEMA50(ind, 1);
   if(atr <= 0.0 || ema50 <= 0.0) return false;
   return ((ind.closeArr[1] - ema50) > atr * maxAtr);
}

bool IsOverstretchedSell(const IndicatorState &ind, double maxAtr = 1.80)
{
   double atr = GetATR(ind, 1); double ema50 = GetEMA50(ind, 1);
   if(atr <= 0.0 || ema50 <= 0.0) return false;
   return ((ema50 - ind.closeArr[1]) > atr * maxAtr);
}

//+------------------------------------------------------------------+
//| TrendCluster — one projected trend boundary for trend entries    |
//| dynamicSupport/Resistance == channel boundary in current arch.   |
//| ONE source only. No fake dual-source scoring.                    |
//+------------------------------------------------------------------+
struct TrendCluster
{
   bool   valid;
   bool   isBuy;
   double level;
   double low;
   double high;
   double mid;
   double baseScore;
   string label;
   bool   fromDynamicChannel;
};

TrendCluster MakeEmptyTrendCluster()
{
   TrendCluster c;
   c.valid     = false;
   c.isBuy     = false;
   c.level     = 0.0;
   c.low       = 0.0;
   c.high      = 0.0;
   c.mid       = 0.0;
   c.baseScore = 0.0;
   c.label     = "";
   c.fromDynamicChannel = false;
   return c;
}

//+------------------------------------------------------------------+
//| TrendBoundaryCandidate — Phase 5 multi-source boundary selection |
//| Allows trend entries from dynamic channel OR horizontal zones    |
//+------------------------------------------------------------------+
struct TrendBoundaryCandidate
{
   bool   valid;
   bool   isBuy;
   double level;
   double low;
   double high;
   double mid;
   double score;
   string label;
   int    zoneIdx;
   bool   fromDynamicChannel;
   bool   fromHorizontalZone;
   bool   isMajor;
   bool   isFlip;
};

TrendBoundaryCandidate MakeEmptyBoundaryCandidate(bool isBuy)
{
   TrendBoundaryCandidate c;
   c.valid              = false;
   c.isBuy              = isBuy;
   c.level              = 0.0;
   c.low                = 0.0;
   c.high               = 0.0;
   c.mid                = 0.0;
   c.score              = 0.0;
   c.label              = "";
   c.zoneIdx            = -1;
   c.fromDynamicChannel = false;
   c.fromHorizontalZone = false;
   c.isMajor            = false;
   c.isFlip             = false;
   return c;
}

//+------------------------------------------------------------------+
//| Strict zone-interaction helpers for two-pass boundary selection  |
//+------------------------------------------------------------------+
bool ZoneActuallyOverlappedByBullBar(const IndicatorState &ind, const ZoneInfo &z, double atr)
{
   double low1   = ind.lowArr[1];
   double high1  = ind.highArr[1];
   double close1 = ind.closeArr[1];

   bool wickOverlap = (high1 >= z.lowerBound && low1 <= z.upperBound);
   bool closeInside = (close1 >= z.lowerBound - atr * 0.08 &&
                       close1 <= z.upperBound + atr * 0.08);
   bool lowNearZone = (MathAbs(low1 - z.upperBound) <= atr * 0.20 ||
                       MathAbs(low1 - z.lowerBound) <= atr * 0.20);

   return wickOverlap || closeInside || lowNearZone;
}

bool ZoneActuallyOverlappedByBearBar(const IndicatorState &ind, const ZoneInfo &z, double atr)
{
   double low1   = ind.lowArr[1];
   double high1  = ind.highArr[1];
   double close1 = ind.closeArr[1];

   bool wickOverlap  = (high1 >= z.lowerBound && low1 <= z.upperBound);
   bool closeInside  = (close1 >= z.lowerBound - atr * 0.08 &&
                        close1 <= z.upperBound + atr * 0.08);
   bool highNearZone = (MathAbs(high1 - z.lowerBound) <= atr * 0.20 ||
                        MathAbs(high1 - z.upperBound) <= atr * 0.20);

   return wickOverlap || closeInside || highNearZone;
}

bool IsZoneNearCurrentPrice(double price, const ZoneInfo &z, double atr, double maxATR = 1.25)
{
   return (MathAbs(price - z.midPoint) <= atr * maxATR);
}

//+------------------------------------------------------------------+
//| FindBestBullTrendBoundary — two-pass near-price selector         |
//| Pass 1: interacted + near-price (strict overlap + 1.25 ATR)      |
//| Pass 2: nearest valid same-side (near-price, no interaction req) |
//| Pass 3: dynamic channel (directional + near-price only)          |
//+------------------------------------------------------------------+
TrendBoundaryCandidate FindBestBullTrendBoundary(const IndicatorState &ind, double atr, bool useDiagonalChannels)
{
   TrendBoundaryCandidate empty = MakeEmptyBoundaryCandidate(true);
   if(atr <= 0.0) return empty;

   double price = ind.closeArr[1];

   // ---------------------------------------------------------------
   // PASS 1 — Interacted + near-price horizontal zones (strict)
   // Only zones the last bar is actually touching AND within 1.25 ATR
   // Far zones are skipped here — never selected-then-rejected
   // ---------------------------------------------------------------
   TrendBoundaryCandidate p1Best = MakeEmptyBoundaryCandidate(true);

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;

      if(InpUseSupplyDemandZones && InpSDTradeOnlyActivePair && !SDIsActiveTradingZone(z))
         continue;

      bool isSupport = (z.type == ZONE_SUPPORT_MAJOR ||
                        z.type == ZONE_SUPPORT_MINOR  ||
                        (z.isFlipZone && z.originalType == ZONE_RESISTANCE_MAJOR));
      if(!isSupport) continue;

      // Zone lower bound must be below price (support role; allows zone to straddle price)
      if(z.lowerBound >= price + atr * 0.15) continue;

      // Gate 1: must be within 1.25 ATR — skip far zones inline
      if(!IsZoneNearCurrentPrice(price, z, atr, 1.25)) continue;

      // Gate 2: strict bar overlap — must be ACTUALLY touching this zone
      if(!ZoneActuallyOverlappedByBullBar(ind, z, atr)) continue;

      TrendBoundaryCandidate cand = MakeEmptyBoundaryCandidate(true);
      cand.valid = true;
      cand.level = z.midPoint;
      cand.low   = z.lowerBound;
      cand.high  = z.upperBound;
      cand.mid   = z.midPoint;
      cand.zoneIdx = i;
      cand.fromHorizontalZone = true;

      if(z.isFlipZone)
         { cand.score = 1.05; cand.isFlip  = true; cand.label = "flip_resistance_to_support_INTERACTED"; }
      else if(z.type == ZONE_SUPPORT_MAJOR)
         { cand.score = 1.20; cand.isMajor = true; cand.label = "major_support_INTERACTED"; }
      else
         { cand.score = 0.90; cand.label = "minor_support_INTERACTED"; }

      double dist = MathAbs(price - z.midPoint);
      cand.score += 2.50;                                        // near-price interaction bonus
      cand.score += (1.0 - dist / (atr * 1.25)) * 0.70;         // proximity up to +0.70
      if(z.cleanTouchCount <= 1) cand.score += 0.20;            // freshness
      if((z.upperBound - z.lowerBound) > atr * 1.75) cand.score -= 0.20; // wide-zone penalty
      if(z.isPrimary)     cand.score += 1.50;
      else if(z.isBackup) cand.score += 0.30;
      if(z.isPrimary && z.hasExecBand)
      { cand.low = z.execBandLow; cand.high = z.execBandHigh; cand.mid = (z.execBandLow + z.execBandHigh) * 0.5; }

      Print("[TREND_BOUNDARY_BUY] pass=1 interaction=true id=", z.id,
            " type=", ZoneTypeToString(z.type),
            " distATR=", DoubleToString(dist / atr, 2),
            " score=", DoubleToString(cand.score, 2),
            " primary=", z.isPrimary);

      if(cand.score > p1Best.score)
         p1Best = cand;
   }

   // Pass 1 winner: immediately prefer interacted near-price zone over any farther wall
   if(p1Best.valid)
   {
      Print("[TREND_BOUNDARY_BUY] selected=pass1_interacted label=", p1Best.label,
            " level=", DoubleToString(p1Best.level, _Digits),
            " score=", DoubleToString(p1Best.score, 2),
            " distATR=", DoubleToString(MathAbs(price - p1Best.mid) / MathMax(atr, 0.0001), 2));
      return p1Best;
   }

   // ---------------------------------------------------------------
   // PASS 2 — Nearest valid same-side zone (near-price, no interaction required)
   // Far zones are skipped inline — not selected-then-rejected
   // ---------------------------------------------------------------
   TrendBoundaryCandidate p2Best = MakeEmptyBoundaryCandidate(true);

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;

      if(InpUseSupplyDemandZones && InpSDTradeOnlyActivePair && !SDIsActiveTradingZone(z))
         continue;

      bool isSupport = (z.type == ZONE_SUPPORT_MAJOR ||
                        z.type == ZONE_SUPPORT_MINOR  ||
                        (z.isFlipZone && z.originalType == ZONE_RESISTANCE_MAJOR));
      if(!isSupport) continue;

      // Midpoint should be below price (structural validity)
      if(z.midPoint >= price + atr * 0.15) continue;

      // Near-price gate — skip far zones inline, log them explicitly
      if(!IsZoneNearCurrentPrice(price, z, atr, 1.25))
      {
         Print("[TREND_BOUNDARY_BUY] interaction=false reason=far_from_price id=", z.id,
               " distATR=", DoubleToString(MathAbs(price - z.midPoint) / atr, 2));
         continue;
      }

      TrendBoundaryCandidate cand = MakeEmptyBoundaryCandidate(true);
      cand.valid = true;
      cand.level = z.midPoint;
      cand.low   = z.lowerBound;
      cand.high  = z.upperBound;
      cand.mid   = z.midPoint;
      cand.zoneIdx = i;
      cand.fromHorizontalZone = true;

      if(z.isFlipZone)
         { cand.score = 1.05; cand.isFlip  = true; cand.label = "flip_resistance_to_support"; }
      else if(z.type == ZONE_SUPPORT_MAJOR)
         { cand.score = 1.20; cand.isMajor = true; cand.label = "major_support"; }
      else
         { cand.score = 0.90; cand.label = "minor_support"; }

      double dist = MathAbs(price - z.midPoint);
      cand.score += (1.0 - dist / (atr * 1.25)) * 0.70;         // proximity up to +0.70
      if(z.cleanTouchCount <= 1) cand.score += 0.20;            // freshness
      if((z.upperBound - z.lowerBound) > atr * 1.75) cand.score -= 0.20; // wide-zone penalty

      // Confluence bonus: zone near dynamic channel
      if(useDiagonalChannels && g_structure.channel.directionalValid &&
         g_structure.channel.direction == +1 && g_structure.dynamicSupport > 0.0 &&
         MathAbs(z.midPoint - g_structure.dynamicSupport) <= atr * 0.40)
         cand.score += 0.40;
      if(z.isPrimary)     cand.score += 1.50;
      else if(z.isBackup) cand.score += 0.30;
      if(z.isPrimary && z.hasExecBand)
      { cand.low = z.execBandLow; cand.high = z.execBandHigh; cand.mid = (z.execBandLow + z.execBandHigh) * 0.5; }

      if(cand.score > p2Best.score)
         p2Best = cand;
   }

   // ---------------------------------------------------------------
   // PASS 3 — Dynamic channel boundary (near-price + directional only)
   // Channel is confluence fallback, not preferred over real horizontal zones
   // ---------------------------------------------------------------
   TrendBoundaryCandidate chanBest = MakeEmptyBoundaryCandidate(true);

   if(useDiagonalChannels && g_structure.channel.directionalValid &&
      g_structure.channel.direction == +1)
   {
      double dzLow=0.0, dzMid=0.0, dzHigh=0.0, dzHalf=0.0;
      if(GetBullDynamicZoneBand(ind, dzLow, dzMid, dzHigh, dzHalf))
      {
         double distMid = MathAbs(price - dzMid);
         if(dzMid < price && distMid <= atr * 1.25)
         {
            chanBest.valid = true;
            chanBest.level = dzMid;
            chanBest.low   = dzLow;
            chanBest.high  = dzHigh;
            chanBest.mid   = dzMid;
            chanBest.score = 1.10 + (1.0 - distMid / (atr * 1.25)) * 0.25;
            chanBest.label = "dynamic_diagonal_support_zone";
            chanBest.fromDynamicChannel = true;
         }
      }
   }

   // Final: horizontal near-price wins over channel when scores tie
   TrendBoundaryCandidate finalBest = MakeEmptyBoundaryCandidate(true);
   if(p2Best.valid && chanBest.valid)
      finalBest = (p2Best.score >= chanBest.score) ? p2Best : chanBest;
   else if(p2Best.valid)
      finalBest = p2Best;
   else if(chanBest.valid)
      finalBest = chanBest;

   if(finalBest.valid)
      Print("[TREND_BOUNDARY_BUY] selected: ", finalBest.label,
            " level=", DoubleToString(finalBest.level, _Digits),
            " score=", DoubleToString(finalBest.score, 2),
            " distATR=", DoubleToString(MathAbs(price - finalBest.mid) / MathMax(atr, 0.0001), 2),
            " pass=", (p2Best.valid ? "2" : "3_channel"));
   else
      Print("[TREND_BOUNDARY_BUY] no_candidate: no near zone within 1.25 ATR price=",
            DoubleToString(price, _Digits));

   return finalBest;
}

//+------------------------------------------------------------------+
//| FindBestBearTrendBoundary — two-pass near-price selector         |
//| Pass 1: interacted + near-price (strict overlap + 1.25 ATR)      |
//| Pass 2: nearest valid same-side (near-price, no interaction req) |
//| Pass 3: dynamic channel (directional + near-price only)          |
//+------------------------------------------------------------------+
TrendBoundaryCandidate FindBestBearTrendBoundary(const IndicatorState &ind, double atr, bool useDiagonalChannels)
{
   TrendBoundaryCandidate empty = MakeEmptyBoundaryCandidate(false);
   if(atr <= 0.0) return empty;

   double price = ind.closeArr[1];

   // ---------------------------------------------------------------
   // PASS 1 — Interacted + near-price horizontal zones (strict)
   // Only zones the last bar is actually touching AND within 1.25 ATR
   // Far zones are skipped here — never selected-then-rejected
   // ---------------------------------------------------------------
   TrendBoundaryCandidate p1Best = MakeEmptyBoundaryCandidate(false);

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;

      if(InpUseSupplyDemandZones && InpSDTradeOnlyActivePair && !SDIsActiveTradingZone(z))
         continue;

      bool isResistance = (z.type == ZONE_RESISTANCE_MAJOR ||
                           z.type == ZONE_RESISTANCE_MINOR  ||
                           (z.isFlipZone && z.originalType == ZONE_SUPPORT_MAJOR));
      if(!isResistance) continue;

      // Zone upper bound must be above price (resistance role; allows zone to straddle price)
      if(z.upperBound <= price - atr * 0.15) continue;

      // Gate 1: must be within 1.25 ATR — skip far zones inline
      if(!IsZoneNearCurrentPrice(price, z, atr, 1.25)) continue;

      // Gate 2: strict bar overlap — must be ACTUALLY touching this zone
      if(!ZoneActuallyOverlappedByBearBar(ind, z, atr)) continue;

      TrendBoundaryCandidate cand = MakeEmptyBoundaryCandidate(false);
      cand.valid = true;
      cand.level = z.midPoint;
      cand.low   = z.lowerBound;
      cand.high  = z.upperBound;
      cand.mid   = z.midPoint;
      cand.zoneIdx = i;
      cand.fromHorizontalZone = true;

      if(z.isFlipZone)
         { cand.score = 1.05; cand.isFlip  = true; cand.label = "flip_support_to_resistance_INTERACTED"; }
      else if(z.type == ZONE_RESISTANCE_MAJOR)
         { cand.score = 1.20; cand.isMajor = true; cand.label = "major_resistance_INTERACTED"; }
      else
         { cand.score = 0.90; cand.label = "minor_resistance_INTERACTED"; }

      double dist = MathAbs(price - z.midPoint);
      cand.score += 2.50;                                        // near-price interaction bonus
      cand.score += (1.0 - dist / (atr * 1.25)) * 0.70;         // proximity up to +0.70
      if(z.cleanTouchCount <= 1) cand.score += 0.20;            // freshness
      if((z.upperBound - z.lowerBound) > atr * 1.75) cand.score -= 0.20; // wide-zone penalty
      if(z.isPrimary)     cand.score += 1.50;
      else if(z.isBackup) cand.score += 0.30;
      if(z.isPrimary && z.hasExecBand)
      { cand.low = z.execBandLow; cand.high = z.execBandHigh; cand.mid = (z.execBandLow + z.execBandHigh) * 0.5; }

      Print("[TREND_BOUNDARY_SELL] pass=1 interaction=true id=", z.id,
            " type=", ZoneTypeToString(z.type),
            " distATR=", DoubleToString(dist / atr, 2),
            " score=", DoubleToString(cand.score, 2),
            " primary=", z.isPrimary);

      if(cand.score > p1Best.score)
         p1Best = cand;
   }

   // Pass 1 winner: immediately prefer interacted near-price zone over any farther wall
   if(p1Best.valid)
   {
      Print("[TREND_BOUNDARY_SELL] selected=pass1_interacted label=", p1Best.label,
            " level=", DoubleToString(p1Best.level, _Digits),
            " score=", DoubleToString(p1Best.score, 2),
            " distATR=", DoubleToString(MathAbs(price - p1Best.mid) / MathMax(atr, 0.0001), 2));
      return p1Best;
   }

   // ---------------------------------------------------------------
   // PASS 2 — Nearest valid same-side zone (near-price, no interaction required)
   // Far zones are skipped inline — not selected-then-rejected
   // ---------------------------------------------------------------
   TrendBoundaryCandidate p2Best = MakeEmptyBoundaryCandidate(false);

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active) continue;

      if(InpUseSupplyDemandZones && InpSDTradeOnlyActivePair && !SDIsActiveTradingZone(z))
         continue;

      bool isResistance = (z.type == ZONE_RESISTANCE_MAJOR ||
                           z.type == ZONE_RESISTANCE_MINOR  ||
                           (z.isFlipZone && z.originalType == ZONE_SUPPORT_MAJOR));
      if(!isResistance) continue;

      // Midpoint should be above price (structural validity)
      if(z.midPoint <= price - atr * 0.15) continue;

      // Near-price gate — skip far zones inline, log them explicitly
      if(!IsZoneNearCurrentPrice(price, z, atr, 1.25))
      {
         Print("[TREND_BOUNDARY_SELL] interaction=false reason=far_from_price id=", z.id,
               " distATR=", DoubleToString(MathAbs(price - z.midPoint) / atr, 2));
         continue;
      }

      TrendBoundaryCandidate cand = MakeEmptyBoundaryCandidate(false);
      cand.valid = true;
      cand.level = z.midPoint;
      cand.low   = z.lowerBound;
      cand.high  = z.upperBound;
      cand.mid   = z.midPoint;
      cand.zoneIdx = i;
      cand.fromHorizontalZone = true;

      if(z.isFlipZone)
         { cand.score = 1.05; cand.isFlip  = true; cand.label = "flip_support_to_resistance"; }
      else if(z.type == ZONE_RESISTANCE_MAJOR)
         { cand.score = 1.20; cand.isMajor = true; cand.label = "major_resistance"; }
      else
         { cand.score = 0.90; cand.label = "minor_resistance"; }

      double dist = MathAbs(price - z.midPoint);
      cand.score += (1.0 - dist / (atr * 1.25)) * 0.70;         // proximity up to +0.70
      if(z.cleanTouchCount <= 1) cand.score += 0.20;            // freshness
      if((z.upperBound - z.lowerBound) > atr * 1.75) cand.score -= 0.20; // wide-zone penalty

      // Confluence bonus: zone near dynamic channel
      if(useDiagonalChannels && g_structure.channel.directionalValid &&
         g_structure.channel.direction == -1 && g_structure.dynamicResistance > 0.0 &&
         MathAbs(z.midPoint - g_structure.dynamicResistance) <= atr * 0.40)
         cand.score += 0.40;
      if(z.isPrimary)     cand.score += 1.50;
      else if(z.isBackup) cand.score += 0.30;
      if(z.isPrimary && z.hasExecBand)
      { cand.low = z.execBandLow; cand.high = z.execBandHigh; cand.mid = (z.execBandLow + z.execBandHigh) * 0.5; }

      if(cand.score > p2Best.score)
         p2Best = cand;
   }

   // ---------------------------------------------------------------
   // PASS 3 — Dynamic channel boundary (near-price + directional only)
   // Channel is confluence fallback, not preferred over real horizontal zones
   // ---------------------------------------------------------------
   TrendBoundaryCandidate chanBest = MakeEmptyBoundaryCandidate(false);

   if(useDiagonalChannels && g_structure.channel.directionalValid &&
      g_structure.channel.direction == -1)
   {
      double dzLow=0.0, dzMid=0.0, dzHigh=0.0, dzHalf=0.0;
      if(GetBearDynamicZoneBand(ind, dzLow, dzMid, dzHigh, dzHalf))
      {
         double distMid = MathAbs(price - dzMid);
         if(dzMid > price && distMid <= atr * 1.25)
         {
            chanBest.valid = true;
            chanBest.level = dzMid;
            chanBest.low   = dzLow;
            chanBest.high  = dzHigh;
            chanBest.mid   = dzMid;
            chanBest.score = 1.10 + (1.0 - distMid / (atr * 1.25)) * 0.25;
            chanBest.label = "dynamic_diagonal_resistance_zone";
            chanBest.fromDynamicChannel = true;
         }
      }
   }

   // Final: horizontal near-price wins over channel when scores tie
   TrendBoundaryCandidate finalBest = MakeEmptyBoundaryCandidate(false);
   if(p2Best.valid && chanBest.valid)
      finalBest = (p2Best.score >= chanBest.score) ? p2Best : chanBest;
   else if(p2Best.valid)
      finalBest = p2Best;
   else if(chanBest.valid)
      finalBest = chanBest;

   if(finalBest.valid)
      Print("[TREND_BOUNDARY_SELL] selected: ", finalBest.label,
            " level=", DoubleToString(finalBest.level, _Digits),
            " score=", DoubleToString(finalBest.score, 2),
            " distATR=", DoubleToString(MathAbs(price - finalBest.mid) / MathMax(atr, 0.0001), 2),
            " pass=", (p2Best.valid ? "2" : "3_channel"));
   else
      Print("[TREND_BOUNDARY_SELL] no_candidate: no near zone within 1.25 ATR price=",
            DoubleToString(price, _Digits));

   return finalBest;
}

//+------------------------------------------------------------------+
//| BuildBullTrendCluster - Phase 5/10 updated                       |
//| Uses FindBestBullTrendBoundary for multi-source selection        |
//| Phase 10: useDiagonalChannels controls dynamic channel usage     |
//+------------------------------------------------------------------+
TrendCluster BuildBullTrendCluster(const IndicatorState &ind, double atr, bool useDiagonalChannels = false)
{
   TrendCluster c = MakeEmptyTrendCluster();
   c.isBuy = true;
   if(atr <= 0.0) return c;

   // Phase 5/10: Use multi-source boundary selector (channels disabled)
   bool allowDiagonalBoundary = false; // Channel code removed
   TrendBoundaryCandidate boundary = FindBestBullTrendBoundary(ind, atr, allowDiagonalBoundary);
   
   if(!boundary.valid)
   {
      Print("[TREND_CLUSTER_BUY] No valid boundary found within range useDiagChannels=", useDiagonalChannels);
      return c;
   }

   c.level     = boundary.level;
   c.low       = boundary.low;
   c.high      = boundary.high;
   c.mid       = boundary.mid;
   c.baseScore = boundary.score;
   c.label     = boundary.label;
   c.fromDynamicChannel = boundary.fromDynamicChannel;
   c.valid     = true;
   return c;
}

//+------------------------------------------------------------------+
//| BuildBearTrendCluster - Phase 5/10 updated                       |
//| Uses FindBestBearTrendBoundary for multi-source selection        |
//| Phase 10: useDiagonalChannels controls dynamic channel usage     |
//+------------------------------------------------------------------+
TrendCluster BuildBearTrendCluster(const IndicatorState &ind, double atr, bool useDiagonalChannels = false)
{
   TrendCluster c = MakeEmptyTrendCluster();
   c.isBuy = false;
   if(atr <= 0.0) return c;

   // Phase 5/10: Use multi-source boundary selector (channels disabled)
   bool allowDiagonalBoundary = false; // Channel code removed
   TrendBoundaryCandidate boundary = FindBestBearTrendBoundary(ind, atr, allowDiagonalBoundary);
   
   if(!boundary.valid)
   {
      Print("[TREND_CLUSTER_SELL] No valid boundary found within range useDiagChannels=", useDiagonalChannels);
      return c;
   }

   c.level     = boundary.level;
   c.low       = boundary.low;
   c.high      = boundary.high;
   c.mid       = boundary.mid;
   c.baseScore = boundary.score;
   c.label     = boundary.label;
   c.fromDynamicChannel = boundary.fromDynamicChannel;
   c.valid     = true;
   return c;
}

//+------------------------------------------------------------------+
//| Strong Continuation Event Helpers                                  |
//+------------------------------------------------------------------+
bool IsBullishWickPlayAtZone(const IndicatorState &ind,
                             double zoneLow,
                             double zoneHigh,
                             double atr,
                             double &stopAnchor,
                             string &triggerLabel)
{
   stopAnchor = zoneLow;
   triggerLabel = "";

   double open1  = ind.openArr[1];
   double close1 = ind.closeArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];

   double range1 = high1 - low1;
   if(range1 <= 0.0 || atr <= 0.0)
      return false;

   double lowerWick = MathMin(open1, close1) - low1;
   double body      = MathAbs(close1 - open1);
   double zoneMid   = (zoneLow + zoneHigh) * 0.5;

   // PATCH: H4 trend alignment gate - block counter-trend S/D entries
   if(InpSDRequireH4TrendAlignment && !PassesH4EMA200DirectionalFilter(true))
      return false;

   bool touchedZone =
      (low1 <= zoneHigh + atr * InpWickPlayZoneTouchATR &&
       high1 >= zoneLow  - atr * InpWickPlayZoneTouchATR);

   if(!touchedZone)
      return false;

   // Aggressive mode: allow entry on any bullish candle touching zone
   if(InpAggressiveZoneEntry && close1 > open1 && close1 >= zoneLow)
   {
      // PATCH: require confirmation candle (wick rejection OR close-back out of zone)
      if(InpSDBodyTouchRequiresConfirmation)
      {
         double range1Local = high1 - low1;
         bool hasWickReject = (range1Local > 0.0 &&
                               lowerWick >= range1Local * InpWickPlayMinWickToRange);
         bool hasCloseBack  = (close1 > zoneHigh + atr * InpWickPlayMinCloseBackZoneATR) ||
                              (close1 > zoneLow  + atr * InpWickPlayMinCloseBackZoneATR &&
                               close1 >= zoneMid);
         if(!(hasWickReject || hasCloseBack))
            return false;
      }
      stopAnchor = low1;
      triggerLabel = "AGGRESSIVE_ZONE_TOUCH_BUY";
      return true;
   }

   bool sweepReclaim =
      (low1 < zoneLow - atr * 0.02 &&
       close1 > zoneLow + atr * InpWickPlayMinCloseBackZoneATR);

   if(sweepReclaim)
   {
      stopAnchor = low1;
      triggerLabel = "WICK_PLAY_SWEEP_RECLAIM_BUY";
      return true;
   }

   bool wickReject =
      (lowerWick >= range1 * InpWickPlayMinWickToRange &&
       close1 > open1 &&
       close1 >= zoneMid);

   if(wickReject)
   {
      stopAnchor = low1;
      triggerLabel = "WICK_PLAY_REJECTION_BUY";
      return true;
   }

   if(InpWickPlayAllowEngulfingConfirm &&
      IsBullishEngulfing(_Symbol, g_indicatorTF, 1) &&
      low1 <= zoneHigh + atr * InpWickPlayZoneTouchATR &&
      close1 >= zoneMid)
   {
      stopAnchor = low1;
      triggerLabel = "WICK_PLAY_ENGULFING_BUY";
      return true;
   }

   return false;
}


bool IsBearishWickPlayAtZone(const IndicatorState &ind,
                             double zoneLow,
                             double zoneHigh,
                             double atr,
                             double &stopAnchor,
                             string &triggerLabel)
{
   stopAnchor = zoneHigh;
   triggerLabel = "";

   double open1  = ind.openArr[1];
   double close1 = ind.closeArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];

   double range1 = high1 - low1;
   if(range1 <= 0.0 || atr <= 0.0)
      return false;

   double upperWick = high1 - MathMax(open1, close1);
   double body      = MathAbs(close1 - open1);
   double zoneMid   = (zoneLow + zoneHigh) * 0.5;

   // PATCH: H4 trend alignment gate - block counter-trend S/D entries
   if(InpSDRequireH4TrendAlignment && !PassesH4EMA200DirectionalFilter(false))
      return false;

   bool touchedZone =
      (high1 >= zoneLow  - atr * InpWickPlayZoneTouchATR &&
       low1  <= zoneHigh + atr * InpWickPlayZoneTouchATR);

   if(!touchedZone)
      return false;

   // Aggressive mode: allow entry on any bearish candle touching zone
   if(InpAggressiveZoneEntry && close1 < open1 && close1 <= zoneHigh)
   {
      // PATCH: require confirmation candle (wick rejection OR close-back out of zone)
      if(InpSDBodyTouchRequiresConfirmation)
      {
         double range1Local = high1 - low1;
         bool hasWickReject = (range1Local > 0.0 &&
                               upperWick >= range1Local * InpWickPlayMinWickToRange);
         bool hasCloseBack  = (close1 < zoneLow  - atr * InpWickPlayMinCloseBackZoneATR) ||
                              (close1 < zoneHigh - atr * InpWickPlayMinCloseBackZoneATR &&
                               close1 <= zoneMid);
         if(!(hasWickReject || hasCloseBack))
            return false;
      }
      stopAnchor = high1;
      triggerLabel = "AGGRESSIVE_ZONE_TOUCH_SELL";
      return true;
   }

   bool sweepReclaim =
      (high1 > zoneHigh + atr * 0.02 &&
       close1 < zoneHigh - atr * InpWickPlayMinCloseBackZoneATR);

   if(sweepReclaim)
   {
      stopAnchor = high1;
      triggerLabel = "WICK_PLAY_SWEEP_RECLAIM_SELL";
      return true;
   }

   bool wickReject =
      (upperWick >= range1 * InpWickPlayMinWickToRange &&
       close1 < open1 &&
       close1 <= zoneMid);

   if(wickReject)
   {
      stopAnchor = high1;
      triggerLabel = "WICK_PLAY_REJECTION_SELL";
      return true;
   }

   if(InpWickPlayAllowEngulfingConfirm &&
      IsBearishEngulfing(_Symbol, g_indicatorTF, 1) &&
      high1 >= zoneLow - atr * InpWickPlayZoneTouchATR &&
      close1 <= zoneMid)
   {
      stopAnchor = high1;
      triggerLabel = "WICK_PLAY_ENGULFING_SELL";
      return true;
   }

   return false;
}

bool IsBullContinuationEvent(const IndicatorState &ind, const TrendCluster &cluster, double atr)
{
   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];
   double close2 = ind.closeArr[2];
   double high2  = ind.highArr[2];
   double low2   = ind.lowArr[2];

   double range1 = high1 - low1;
   if(range1 <= 0.0) return false;

   double body1 = MathAbs(close1 - open1);
   bool bullishBody      = (close1 > open1 && body1 >= range1 * 0.45);
   bool touchedPullback  = (low1 <= cluster.high + atr * 0.40 || low2 <= cluster.high + atr * 0.40);
   bool closedStrong     = (close1 >= high1 - range1 * 0.25);
   bool brokePrevHigh    = (close1 > high2);
   bool heldCluster      = (close1 >= cluster.mid - atr * 0.20);

   return (bullishBody && touchedPullback && closedStrong && brokePrevHigh && heldCluster);
}

bool IsBearContinuationEvent(const IndicatorState &ind, const TrendCluster &cluster, double atr)
{
   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];
   double close2 = ind.closeArr[2];
   double high2  = ind.highArr[2];
   double low2   = ind.lowArr[2];

   double range1 = high1 - low1;
   if(range1 <= 0.0) return false;

   double body1 = MathAbs(close1 - open1);
   bool bearishBody      = (close1 < open1 && body1 >= range1 * 0.45);
   bool touchedPullback  = (high1 >= cluster.low - atr * 0.40 || high2 >= cluster.low - atr * 0.40);
   bool closedStrong     = (close1 <= low1 + range1 * 0.25);
   bool brokePrevLow     = (close1 < low2);
   bool heldCluster      = (close1 <= cluster.mid + atr * 0.20);

   return (bearishBody && touchedPullback && closedStrong && brokePrevLow && heldCluster);
}

//+------------------------------------------------------------------+
//| ConfirmBullTrendClusterEntry                                     |
//+------------------------------------------------------------------+
bool ConfirmBullTrendClusterEntry(const IndicatorState &ind,
                                  const TrendCluster   &cluster,
                                  double atr,
                                  bool   useSweep,
                                  double &stopAnchor,
                                  double &scoreBoost,
                                  string &triggerLabel)
{
   stopAnchor   = cluster.low;
   scoreBoost   = 0.0;
   triggerLabel = "";

   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];

   double close2 = ind.closeArr[2];
   double open2  = ind.openArr[2];
   double high2  = ind.highArr[2];
   double low2   = ind.lowArr[2];

   double range1 = high1 - low1;
   double body1  = MathAbs(close1 - open1);
   double bandW  = MathMax(cluster.high - cluster.low, atr * 0.10);

   bool bar1Inside =
      (close1 >= cluster.low - atr * 0.70 && close1 <= cluster.high + atr * 0.70) ||
      (low1   <= cluster.high + atr * 0.55 && high1 >= cluster.low - atr * 0.55) ||
      (MathAbs(close1 - cluster.mid) <= atr * 1.60);

   bool bar2Inside =
      (close2 >= cluster.low - atr * 0.70 && close2 <= cluster.high + atr * 0.70) ||
      (low2   <= cluster.high + atr * 0.55 && high2 >= cluster.low - atr * 0.55) ||
      (MathAbs(close2 - cluster.mid) <= atr * 1.60);

   bool recentPullbackContext =
      (low1 <= cluster.high + atr * 0.55) ||
      (low2 <= cluster.high + atr * 0.55) ||
      (MathMin(low1, low2) <= cluster.mid + atr * 0.35);

   bool nearCluster = bar1Inside || bar2Inside || recentPullbackContext;

   if(!nearCluster)
   {
      Print("[TREND_CONTINUATION] side=BUY result=invalid reason=not_near_dynamic_zone",
            " close1=", DoubleToString(close1, _Digits),
            " close2=", DoubleToString(close2, _Digits),
            " zoneLow=", DoubleToString(cluster.low, _Digits),
            " zoneHigh=", DoubleToString(cluster.high, _Digits));
      return false;
   }

   if(InpUseWickPlayEntryOnly)
   {
      bool ok = IsBullishWickPlayAtZone(ind, cluster.low, cluster.high, atr, stopAnchor, triggerLabel);
      if(ok)
      {
         scoreBoost = 1.20;
         triggerLabel = "WICK_PLAY_ZONE_BUY";
         Print("[WICK_PLAY_ENTRY] side=BUY trigger=", triggerLabel,
               " zoneLow=", DoubleToString(cluster.low, _Digits),
               " zoneHigh=", DoubleToString(cluster.high, _Digits),
               " stopAnchor=", DoubleToString(stopAnchor, _Digits));
         return true;
      }

      Print("[WICK_PLAY_ENTRY_BLOCKED] side=BUY reason=no_wick_play_confirmation",
            " zoneLow=", DoubleToString(cluster.low, _Digits),
            " zoneHigh=", DoubleToString(cluster.high, _Digits));
      return false;
   }

   bool bullishSweep = false;
   if(useSweep)
   {
      bullishSweep = (low1 < cluster.low - atr * 0.02 && close1 >= cluster.mid - atr * 0.20);
      if(bullishSweep)
      {
         stopAnchor   = MathMin(stopAnchor, low1);
         scoreBoost   = 1.15;
         triggerLabel = "SWEEP_RECLAIM";
         Print("[TREND_TRIGGER] result=sweep_reclaim side=BUY low=", DoubleToString(low1, _Digits));
         return true;
      }
   }

   double lowerWick1 = MathMin(open1, close1) - low1;
   bool bullishReject =
      (close1 > open1) &&
      (range1 > 0.0) &&
      (lowerWick1 >= range1 * 0.12) &&
      (low1 <= cluster.mid + atr * 0.45) &&
      (close1 >= cluster.low + bandW * 0.08);

   if(bullishReject)
   {
      stopAnchor   = MathMin(stopAnchor, low1);
      scoreBoost   = 0.85;
      triggerLabel = "REJECTION";
      Print("[TREND_TRIGGER] result=rejection side=BUY low=", DoubleToString(low1, _Digits));
      return true;
   }

   bool bullishEngulf = IsBullishEngulfing(_Symbol, g_indicatorTF, 1) &&
                        close1 >= cluster.low + bandW * 0.08;

   if(bullishEngulf)
   {
      stopAnchor   = MathMin(stopAnchor, low1);
      scoreBoost   = 0.80;
      triggerLabel = "ENGULFING";
      Print("[TREND_TRIGGER] result=engulfing side=BUY close=", DoubleToString(close1, _Digits));
      return true;
   }

   if(!InpUseWickPlayEntryOnly)
   {
      bool bullishContinuation = IsBullContinuationEvent(ind, cluster, atr);

      if(bullishContinuation)
      {
         stopAnchor   = MathMin(stopAnchor, MathMin(low1, low2));
         scoreBoost   = 0.95;
         triggerLabel = "CONTINUATION_STRONG";
         Print("[TREND_TRIGGER] result=continuation_strong side=BUY close=", DoubleToString(close1, _Digits));
         return true;
      }
   }

   Print("[TREND_CONTINUATION] side=BUY result=invalid reason=no_valid_trigger",
         " close1=", DoubleToString(close1, _Digits),
         " zoneMid=", DoubleToString(cluster.mid, _Digits));
   return false;
}

//+------------------------------------------------------------------+
//| ConfirmBearTrendClusterEntry                                     |
//+------------------------------------------------------------------+
bool ConfirmBearTrendClusterEntry(const IndicatorState &ind,
                                  const TrendCluster   &cluster,
                                  double atr,
                                  bool   useSweep,
                                  double &stopAnchor,
                                  double &scoreBoost,
                                  string &triggerLabel)
{
   stopAnchor   = cluster.high;
   scoreBoost   = 0.0;
   triggerLabel = "";

   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];

   double close2 = ind.closeArr[2];
   double open2  = ind.openArr[2];
   double high2  = ind.highArr[2];
   double low2   = ind.lowArr[2];

   double range1 = high1 - low1;
   double body1  = MathAbs(close1 - open1);
   double bandW  = MathMax(cluster.high - cluster.low, atr * 0.10);

   bool bar1Inside =
      (close1 >= cluster.low - atr * 0.70 && close1 <= cluster.high + atr * 0.70) ||
      (high1  >= cluster.low - atr * 0.55 && low1  <= cluster.high + atr * 0.55) ||
      (MathAbs(close1 - cluster.mid) <= atr * 1.60);

   bool bar2Inside =
      (close2 >= cluster.low - atr * 0.70 && close2 <= cluster.high + atr * 0.70) ||
      (high2  >= cluster.low - atr * 0.55 && low2  <= cluster.high + atr * 0.55) ||
      (MathAbs(close2 - cluster.mid) <= atr * 1.60);

   bool recentPullbackContext =
      (high1 >= cluster.low - atr * 0.55) ||
      (high2 >= cluster.low - atr * 0.55) ||
      (MathMax(high1, high2) >= cluster.mid - atr * 0.35);

   bool nearCluster = bar1Inside || bar2Inside || recentPullbackContext;

   if(!nearCluster)
   {
      Print("[TREND_CONTINUATION] side=SELL result=invalid reason=not_near_dynamic_zone",
            " close1=", DoubleToString(close1, _Digits),
            " close2=", DoubleToString(close2, _Digits),
            " zoneLow=", DoubleToString(cluster.low, _Digits),
            " zoneHigh=", DoubleToString(cluster.high, _Digits));
      return false;
   }

   if(InpUseWickPlayEntryOnly)
   {
      bool ok = IsBearishWickPlayAtZone(ind, cluster.low, cluster.high, atr, stopAnchor, triggerLabel);
      if(ok)
      {
         scoreBoost = 1.20;
         triggerLabel = "WICK_PLAY_ZONE_SELL";
         Print("[WICK_PLAY_ENTRY] side=SELL trigger=", triggerLabel,
               " zoneLow=", DoubleToString(cluster.low, _Digits),
               " zoneHigh=", DoubleToString(cluster.high, _Digits),
               " stopAnchor=", DoubleToString(stopAnchor, _Digits));
         return true;
      }

      Print("[WICK_PLAY_ENTRY_BLOCKED] side=SELL reason=no_wick_play_confirmation",
            " zoneLow=", DoubleToString(cluster.low, _Digits),
            " zoneHigh=", DoubleToString(cluster.high, _Digits));
      return false;
   }

   bool bearishSweep = false;
   if(useSweep)
   {
      bearishSweep = (high1 > cluster.high + atr * 0.02 && close1 <= cluster.mid + atr * 0.20);
      if(bearishSweep)
      {
         stopAnchor   = MathMax(stopAnchor, high1);
         scoreBoost   = 1.15;
         triggerLabel = "SWEEP_RECLAIM";
         Print("[TREND_TRIGGER] result=sweep_reclaim side=SELL high=", DoubleToString(high1, _Digits));
         return true;
      }
   }

   double upperWick1 = high1 - MathMax(open1, close1);
   bool bearishReject =
      (close1 < open1) &&
      (range1 > 0.0) &&
      (upperWick1 >= range1 * 0.12) &&
      (high1 >= cluster.mid - atr * 0.45) &&
      (close1 <= cluster.high - bandW * 0.08);

   if(bearishReject)
   {
      stopAnchor   = MathMax(stopAnchor, high1);
      scoreBoost   = 0.85;
      triggerLabel = "REJECTION";
      Print("[TREND_TRIGGER] result=rejection side=SELL high=", DoubleToString(high1, _Digits));
      return true;
   }

   bool bearishEngulf = IsBearishEngulfing(_Symbol, g_indicatorTF, 1) &&
                        close1 <= cluster.high - bandW * 0.08;

   if(bearishEngulf)
   {
      stopAnchor   = MathMax(stopAnchor, high1);
      scoreBoost   = 0.80;
      triggerLabel = "ENGULFING";
      Print("[TREND_TRIGGER] result=engulfing side=SELL close=", DoubleToString(close1, _Digits));
      return true;
   }

   if(!InpUseWickPlayEntryOnly)
   {
      bool bearishContinuation = IsBearContinuationEvent(ind, cluster, atr);

      if(bearishContinuation)
      {
         stopAnchor   = MathMax(stopAnchor, MathMax(high1, high2));
         scoreBoost   = 0.95;
         triggerLabel = "CONTINUATION_STRONG";
         Print("[TREND_TRIGGER] result=continuation_strong side=SELL close=", DoubleToString(close1, _Digits));
         return true;
      }
   }

   Print("[TREND_CONTINUATION] side=SELL result=invalid reason=no_valid_trigger",
         " close1=", DoubleToString(close1, _Digits),
         " zoneMid=", DoubleToString(cluster.mid, _Digits));
   return false;
}

//+------------------------------------------------------------------+
//| Trend Campaign Continuation Trigger - Bull                        |
//| At active bull dynamic support zone, accept BUY if ANY is true:   |
//| 1. Bullish sweep reclaim of dynamic support zone                  |
//| 2. Bullish rejection wick from lower half of zone                 |
//| 3. Bullish engulfing closing above zone mid                       |
//| 4. Break-retest continuation (pullback into band, bullish close)  |
//+------------------------------------------------------------------+
bool CheckBullTrendContinuationTrigger(const IndicatorState &ind,
                                        const DynamicZoneBand &zone,
                                        double atr,
                                        double &stopAnchor,
                                        string &triggerLabel)
{
   stopAnchor   = zone.low;
   triggerLabel = "";
   
   if(!zone.valid) return false;
   
   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   double low1   = ind.lowArr[1];
   double high1  = ind.highArr[1];
   double range1 = high1 - low1;
   bool bullClose = (close1 > open1);
   
   // Check if price is near or within the dynamic zone
   bool nearZone = (low1 <= zone.high + atr * 0.15) && (close1 >= zone.low - atr * 0.25);
   if(!nearZone)
   {
      Print("[TREND_CONTINUATION] side=BUY result=invalid reason=not_near_zone");
      return false;
   }
   
   // 1. Bullish sweep reclaim - wick below zone low, close back above
   double sweepTol = atr * 0.10;
   if(low1 < zone.low - sweepTol && close1 > zone.low)
   {
      stopAnchor   = MathMin(stopAnchor, low1);
      triggerLabel = "SWEEP_RECLAIM";
      Print("[TREND_CONTINUATION] side=BUY trigger=SWEEP_RECLAIM low=", DoubleToString(low1, _Digits),
            " zoneLow=", DoubleToString(zone.low, _Digits));
      return true;
   }
   
   // 2. Bullish rejection wick from lower half of zone
   double zoneMidLine = (zone.low + zone.high) / 2.0;
   double lowerWick = MathMin(open1, close1) - low1;
   double upperWick = high1 - MathMax(open1, close1);
   bool wickFromLowerHalf = (low1 <= zoneMidLine);
   bool significantLowerWick = (range1 > 0 && lowerWick >= range1 * 0.40);
   
   if(bullClose && wickFromLowerHalf && significantLowerWick && close1 > zoneMidLine)
   {
      stopAnchor   = MathMin(stopAnchor, low1);
      triggerLabel = "REJECTION_WICK";
      Print("[TREND_CONTINUATION] side=BUY trigger=REJECTION_WICK low=", DoubleToString(low1, _Digits),
            " zoneMid=", DoubleToString(zoneMidLine, _Digits));
      return true;
   }
   
   // 3. Bullish engulfing closing above zone mid
   if(IsBullishEngulfing(_Symbol, g_indicatorTF, 1) && close1 > zoneMidLine)
   {
      stopAnchor   = MathMin(stopAnchor, low1);
      triggerLabel = "ENGULFING";
      Print("[TREND_CONTINUATION] side=BUY trigger=ENGULFING close=", DoubleToString(close1, _Digits),
            " zoneMid=", DoubleToString(zoneMidLine, _Digits));
      return true;
   }
   
   // 4. Break-retest continuation: pullback into band + bullish close rejecting band
   bool pulledBackIntoBand = (low1 <= zone.high && low1 >= zone.low - atr * 0.15);
   bool closeAboveBand = (close1 > zone.high);
   
   if(bullClose && pulledBackIntoBand && closeAboveBand)
   {
      stopAnchor   = MathMin(stopAnchor, low1);
      triggerLabel = "BREAK_RETEST";
      Print("[TREND_CONTINUATION] side=BUY trigger=BREAK_RETEST close=", DoubleToString(close1, _Digits),
            " zoneHigh=", DoubleToString(zone.high, _Digits));
      return true;
   }
   
   Print("[TREND_CONTINUATION] side=BUY result=invalid reason=no_trigger_pattern");
   return false;
}

//+------------------------------------------------------------------+
//| Trend Campaign Continuation Trigger - Bear                        |
//| At active bear dynamic resistance zone, accept SELL if ANY true:  |
//| 1. Bearish sweep reclaim of dynamic resistance zone               |
//| 2. Bearish rejection wick from upper half of zone                 |
//| 3. Bearish engulfing closing below zone mid                       |
//| 4. Break-retest continuation (pullback into band, bearish close)  |
//+------------------------------------------------------------------+
bool CheckBearTrendContinuationTrigger(const IndicatorState &ind,
                                        const DynamicZoneBand &zone,
                                        double atr,
                                        double &stopAnchor,
                                        string &triggerLabel)
{
   stopAnchor   = zone.high;
   triggerLabel = "";
   
   if(!zone.valid) return false;
   
   double close1 = ind.closeArr[1];
   double open1  = ind.openArr[1];
   double low1   = ind.lowArr[1];
   double high1  = ind.highArr[1];
   double range1 = high1 - low1;
   bool bearClose = (close1 < open1);
   
   // Check if price is near or within the dynamic zone
   bool nearZone = (high1 >= zone.low - atr * 0.15) && (close1 <= zone.high + atr * 0.25);
   if(!nearZone)
   {
      Print("[TREND_CONTINUATION] side=SELL result=invalid reason=not_near_zone");
      return false;
   }
   
   // 1. Bearish sweep reclaim - wick above zone high, close back below
   double sweepTol = atr * 0.10;
   if(high1 > zone.high + sweepTol && close1 < zone.high)
   {
      stopAnchor   = MathMax(stopAnchor, high1);
      triggerLabel = "SWEEP_RECLAIM";
      Print("[TREND_CONTINUATION] side=SELL trigger=SWEEP_RECLAIM high=", DoubleToString(high1, _Digits),
            " zoneHigh=", DoubleToString(zone.high, _Digits));
      return true;
   }
   
   // 2. Bearish rejection wick from upper half of zone
   double zoneMidLine = (zone.low + zone.high) / 2.0;
   double lowerWick = MathMin(open1, close1) - low1;
   double upperWick = high1 - MathMax(open1, close1);
   bool wickFromUpperHalf = (high1 >= zoneMidLine);
   bool significantUpperWick = (range1 > 0 && upperWick >= range1 * 0.40);
   
   if(bearClose && wickFromUpperHalf && significantUpperWick && close1 < zoneMidLine)
   {
      stopAnchor   = MathMax(stopAnchor, high1);
      triggerLabel = "REJECTION_WICK";
      Print("[TREND_CONTINUATION] side=SELL trigger=REJECTION_WICK high=", DoubleToString(high1, _Digits),
            " zoneMid=", DoubleToString(zoneMidLine, _Digits));
      return true;
   }
   
   // 3. Bearish engulfing closing below zone mid
   if(IsBearishEngulfing(_Symbol, g_indicatorTF, 1) && close1 < zoneMidLine)
   {
      stopAnchor   = MathMax(stopAnchor, high1);
      triggerLabel = "ENGULFING";
      Print("[TREND_CONTINUATION] side=SELL trigger=ENGULFING close=", DoubleToString(close1, _Digits),
            " zoneMid=", DoubleToString(zoneMidLine, _Digits));
      return true;
   }
   
   // 4. Break-retest continuation: pullback into band + bearish close rejecting band
   bool pulledBackIntoBand = (high1 >= zone.low && high1 <= zone.high + atr * 0.15);
   bool closeBelowBand = (close1 < zone.low);
   
   if(bearClose && pulledBackIntoBand && closeBelowBand)
   {
      stopAnchor   = MathMax(stopAnchor, high1);
      triggerLabel = "BREAK_RETEST";
      Print("[TREND_CONTINUATION] side=SELL trigger=BREAK_RETEST close=", DoubleToString(close1, _Digits),
            " zoneLow=", DoubleToString(zone.low, _Digits));
      return true;
   }
   
   Print("[TREND_CONTINUATION] side=SELL result=invalid reason=no_trigger_pattern");
   return false;
}

//+------------------------------------------------------------------+
//| Wick-aware stop helpers                                          |
//+------------------------------------------------------------------+
double GetRecentSetupWickLow(const IndicatorState &ind, int barsLookback = 5)
{
   double lowest = ind.lowArr[1];
   int lb = MathMin(barsLookback, ArraySize(ind.lowArr) - 1);

   for(int i = 2; i <= lb; i++)
   {
      if(ind.lowArr[i] < lowest && ind.lowArr[i] > ind.lowArr[1] - GetATR(ind, 1) * 1.20)
         lowest = ind.lowArr[i];
   }

   return lowest;
}

double GetRecentSetupWickHigh(const IndicatorState &ind, int barsLookback = 5)
{
   double highest = ind.highArr[1];
   int lb = MathMin(barsLookback, ArraySize(ind.highArr) - 1);

   for(int i = 2; i <= lb; i++)
   {
      if(ind.highArr[i] > highest && ind.highArr[i] < ind.highArr[1] + GetATR(ind, 1) * 1.20)
         highest = ind.highArr[i];
   }

   return highest;
}

double BuildBufferedBuyStop(double zoneLow, double wickLow, double atr,
                            double bufferAtr, int digits)
{
   double maxOvershootAtr = 0.85;
   double cappedWickLow   = MathMax(wickLow, zoneLow - atr * maxOvershootAtr);
   double anchor          = MathMin(zoneLow, cappedWickLow);

   double adaptiveBufferAtr = bufferAtr;
   if(MathAbs(zoneLow - cappedWickLow) > atr * 0.30)
      adaptiveBufferAtr += 0.10;

   double sl = anchor - atr * adaptiveBufferAtr;

   Print("[STOP_BUILD] type=BUY zoneLow=", DoubleToString(zoneLow, digits),
         " wickLow=", DoubleToString(wickLow, digits),
         " cappedWickLow=", DoubleToString(cappedWickLow, digits),
         " anchor=", DoubleToString(anchor, digits),
         " bufferATR=", DoubleToString(adaptiveBufferAtr, 2),
         " finalSL=", DoubleToString(sl, digits));

   return NormalizeDouble(sl, digits);
}

double BuildBufferedSellStop(double zoneHigh, double wickHigh, double atr,
                             double bufferAtr, int digits)
{
   double maxOvershootAtr = 0.85;
   double cappedWickHigh  = MathMin(wickHigh, zoneHigh + atr * maxOvershootAtr);
   double anchor          = MathMax(zoneHigh, cappedWickHigh);

   double adaptiveBufferAtr = bufferAtr;
   if(MathAbs(cappedWickHigh - zoneHigh) > atr * 0.30)
      adaptiveBufferAtr += 0.10;

   double sl = anchor + atr * adaptiveBufferAtr;

   Print("[STOP_BUILD] type=SELL zoneHigh=", DoubleToString(zoneHigh, digits),
         " wickHigh=", DoubleToString(wickHigh, digits),
         " cappedWickHigh=", DoubleToString(cappedWickHigh, digits),
         " anchor=", DoubleToString(anchor, digits),
         " bufferATR=", DoubleToString(adaptiveBufferAtr, 2),
         " finalSL=", DoubleToString(sl, digits));

   return NormalizeDouble(sl, digits);
}

bool BuildBullChannelToChannelOrder(const IndicatorState &ind,
                                    const TrendCluster   &cluster,
                                    const SymbolProfile  &prof,
                                    double               stopAnchor,
                                    double              &sl,
                                    double              &tp,
                                    double              &projRR)
{
   projRR = 0.0;
   sl = 0.0;
   tp = 0.0;
   return false;
}

bool BuildBearChannelToChannelOrder(const IndicatorState &ind,
                                    const TrendCluster   &cluster,
                                    const SymbolProfile  &prof,
                                    double               stopAnchor,
                                    double              &sl,
                                    double              &tp,
                                    double              &projRR)
{
   projRR = 0.0;
   sl = 0.0;
   tp = 0.0;
   return false;
}

//+------------------------------------------------------------------+
//| PRIMARY ZONE SIGNAL GENERATION - ARCHITECTURE FIX                 |
//+------------------------------------------------------------------+

bool FindBestDirectionalTrendZone(bool wantSupport,
                                  double price,
                                  double atr,
                                  ZoneInfo &outZone,
                                  int &outIdx)
{
   outIdx = -1;

   if(!FindPrimarySideFallback(wantSupport, price, atr, -1, outZone))
      return false;

   outIdx = FindZoneById(outZone.id);
   return (outIdx >= 0);
}

bool HasBullishPrimaryZoneConfirmation(const IndicatorState &ind,
                                       const ZoneInfo &zone,
                                       double atr,
                                       ENUM_ZONE_INTERACTION &interaction,
                                       double &stopAnchor)
{
   interaction = ZONE_INTERACTION_NONE;
   stopAnchor = 0.0;

   if(ArraySize(ind.openArr) < 4 || ArraySize(ind.highArr) < 4 ||
      ArraySize(ind.lowArr) < 4 || ArraySize(ind.closeArr) < 4)
      return false;

   // PATCH: H4 trend alignment gate - block counter-trend demand entries
   if(InpSDRequireH4TrendAlignment && !PassesH4EMA200DirectionalFilter(true))
      return false;

   double open1  = ind.openArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];
   double close1 = ind.closeArr[1];

   double open2  = ind.openArr[2];
   double high2  = ind.highArr[2];
   double low2   = ind.lowArr[2];
   double close2 = ind.closeArr[2];

   bool touchedZone = (low1 <= zone.upperBound + atr * 0.18) ||
                      (low2 <= zone.upperBound + atr * 0.18) ||
                      (MathAbs(close1 - zone.midPoint) <= atr * 0.12);

   if(!touchedZone)
      return false;

   bool deepCloseThroughZone = (close1 < zone.lowerBound - atr * 0.18);
   if(deepCloseThroughZone)
      return false;

   double range1 = MathMax(high1 - low1, _Point * 10.0);
   double wick1  = MathMin(open1, close1) - low1;

   bool rejection1 = (wick1 / range1 >= 0.30 && close1 > open1);
   bool reclaim1   = ((close1 >= zone.midPoint - atr * 0.05) && close1 > open1);
   bool engulf1    = (close2 < open2 && close1 > open1 && close1 > high2);

   int score = 0;
   if(touchedZone) score++;
   if(rejection1)  score++;
   if(reclaim1)    score++;
   if(engulf1)     score++;

   bool softPass = touchedZone && (rejection1 || reclaim1) && close1 >= zone.lowerBound - atr * 0.05;
   if(score < 2 && !softPass)
      return false;

   bool sweepReclaim = ((low1 < zone.lowerBound && close1 >= zone.lowerBound) ||
                        (low2 < zone.lowerBound && close1 > zone.midPoint));

   if(sweepReclaim)
      interaction = ZONE_INTERACTION_SWEEP_RECLAIM;
   else if(rejection1)
      interaction = ZONE_INTERACTION_REJECTION;
   else
      interaction = ZONE_INTERACTION_BREAKRETEST;

   stopAnchor = MathMin(low1, low2);
   return true;
}

bool HasBearishPrimaryZoneConfirmation(const IndicatorState &ind,
                                       const ZoneInfo &zone,
                                       double atr,
                                       ENUM_ZONE_INTERACTION &interaction,
                                       double &stopAnchor)
{
   interaction = ZONE_INTERACTION_NONE;
   stopAnchor = 0.0;

   if(ArraySize(ind.openArr) < 4 || ArraySize(ind.highArr) < 4 ||
      ArraySize(ind.lowArr) < 4 || ArraySize(ind.closeArr) < 4)
      return false;

   // PATCH: H4 trend alignment gate - block counter-trend supply entries
   if(InpSDRequireH4TrendAlignment && !PassesH4EMA200DirectionalFilter(false))
      return false;

   double open1  = ind.openArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];
   double close1 = ind.closeArr[1];

   double open2  = ind.openArr[2];
   double high2  = ind.highArr[2];
   double low2   = ind.lowArr[2];
   double close2 = ind.closeArr[2];

   bool touchedZone = (high1 >= zone.lowerBound - atr * 0.18) ||
                      (high2 >= zone.lowerBound - atr * 0.18) ||
                      (MathAbs(close1 - zone.midPoint) <= atr * 0.12);

   if(!touchedZone)
      return false;

   bool deepCloseThroughZone = (close1 > zone.upperBound + atr * 0.18);
   if(deepCloseThroughZone)
      return false;

   double range1 = MathMax(high1 - low1, _Point * 10.0);
   double wick1  = high1 - MathMax(open1, close1);

   bool rejection1 = (wick1 / range1 >= 0.30 && close1 < open1);
   bool reclaim1   = ((close1 <= zone.midPoint + atr * 0.05) && close1 < open1);
   bool engulf1    = (close2 > open2 && close1 < open1 && close1 < low2);

   int score = 0;
   if(touchedZone) score++;
   if(rejection1)  score++;
   if(reclaim1)    score++;
   if(engulf1)     score++;

   bool softPass = touchedZone && (rejection1 || reclaim1) && close1 <= zone.upperBound + atr * 0.05;
   if(score < 2 && !softPass)
      return false;

   bool sweepReclaim = ((high1 > zone.upperBound && close1 <= zone.upperBound) ||
                        (high2 > zone.upperBound && close1 < zone.midPoint));

   if(sweepReclaim)
      interaction = ZONE_INTERACTION_SWEEP_RECLAIM;
   else if(rejection1)
      interaction = ZONE_INTERACTION_REJECTION;
   else
      interaction = ZONE_INTERACTION_BREAKRETEST;

   stopAnchor = MathMax(high1, high2);
   return true;
}

EntryDecision GenerateSignalFromPrimaryZones(const IndicatorState &ind,
                                             const SymbolProfile  &prof)
{
   EntryDecision out = MakeEmptyDecision();

   double currentPrice = ind.closeArr[1];
   double atr = GetATR(ind, 1);
   if(atr <= 0.0)
   {
      out.reason = "ATR<=0";
      return out;
   }

   // STEP 7: Call S/D retest entry generation first, return early if valid
   if(InpUseSupplyDemandZones && InpSDTradeOnlyActivePair)
   {
      // Try BUY S/D retest first
      EntryDecision sdBuyDecision = GenerateZoneRetestDecision(ind, prof, true, 1.5, 2.2);
      if(sdBuyDecision.valid)
      {
         Print("[TREND_WRAPPER] SD_retest_BUY took priority over old primary-zone logic");
         return sdBuyDecision;
      }

      // Try SELL S/D retest first
      EntryDecision sdSellDecision = GenerateZoneRetestDecision(ind, prof, false, 1.5, 2.2);
      if(sdSellDecision.valid)
      {
         Print("[TREND_WRAPPER] SD_retest_SELL took priority over old primary-zone logic");
         return sdSellDecision;
      }

      out.reason = "SD_ENTRY_WAIT | buy=" + sdBuyDecision.reason + " | sell=" + sdSellDecision.reason;
      Print("[SD_ENTRY_WAIT] buy=", sdBuyDecision.reason, " sell=", sdSellDecision.reason);

      // In active Supply/Demand mode, do not fall through into old Support/Resistance primary logic.
      return out;
   }

   // Sync signal engine with promoted/drawn primary zones
   PromotePrimaryZones(currentPrice, atr);
   g_primaryZones = BuildPrimaryZonesFromRegistry(currentPrice, atr);
   SanitizePrimaryZones(g_primaryZones, currentPrice, atr);

   int trend = GetMarketTrend(); // 1 = bull, -1 = bear, 0 = neutral
   Print("[PRIMARY_SIGNAL] trend=", trend, " price=", DoubleToString(currentPrice, _Digits));

   ZoneInfo workingZone;
   int workingIdx = -1;

   if(trend == 1) // BULL
   {
      if(g_primaryZones.hasSupport)
      {
         workingZone = g_primaryZones.support;
         workingIdx = FindZoneById(workingZone.id);
      }
      else if(FindBestDirectionalTrendZone(true, currentPrice, atr, workingZone, workingIdx))
      {
         Print("[PRIMARY_SIGNAL_FALLBACK] side=BUY zoneId=", workingZone.id,
               " mid=", DoubleToString(workingZone.midPoint, _Digits),
               " tag=", workingZone.structuralTag);
      }
      else
      {
         out.reason = "BULL trend: no primary or fallback support zone";
         Print("[PRIMARY_SIGNAL] No support zone for BULL trend");
         return out;
      }

      // PATCH 15: Trend mode should only use major continuation zones
      // PATCH 4: Allow HL/LH continuation zones with medium-good quality
      bool continuationLike =
         (workingZone.strategyRole == ZROLE_TREND_CONTINUATION ||
          workingZone.structuralTag == "HL" ||
          workingZone.structuralTag == "LH");

      double minTrendZoneQuality =
         continuationLike
         ? MathMax(5.25, ZoneWeakRejectThreshold)
         : ZoneMajorScoreThreshold;

      if(workingZone.qualityScore < minTrendZoneQuality)
      {
         out.reason = "BULL trend: primary support zone too weak";
         Print("[ZONE_REJECT] trend_primary_too_weak id=", workingZone.id,
               " quality=", DoubleToString(workingZone.qualityScore, 2),
               " threshold=", DoubleToString(minTrendZoneQuality, 2),
               " continuationLike=", continuationLike);
         return out;
      }

      out = EvaluateBuyFromPrimaryZone(workingZone, ind, prof);
      if(out.zoneIdx < 0)
         out.zoneIdx = workingIdx;
      return out;
   }

   if(trend == -1) // BEAR
   {
      if(g_primaryZones.hasResistance)
      {
         workingZone = g_primaryZones.resistance;
         workingIdx = FindZoneById(workingZone.id);
      }
      else if(FindBestDirectionalTrendZone(false, currentPrice, atr, workingZone, workingIdx))
      {
         Print("[PRIMARY_SIGNAL_FALLBACK] side=SELL zoneId=", workingZone.id,
               " mid=", DoubleToString(workingZone.midPoint, _Digits),
               " tag=", workingZone.structuralTag);
      }
      else
      {
         out.reason = "BEAR trend: no primary or fallback resistance zone";
         Print("[PRIMARY_SIGNAL] No resistance zone for BEAR trend");
         return out;
      }

      // PATCH 15: Trend mode should only use major continuation zones
      // PATCH 4: Allow HL/LH continuation zones with medium-good quality
      bool continuationLike =
         (workingZone.strategyRole == ZROLE_TREND_CONTINUATION ||
          workingZone.structuralTag == "HL" ||
          workingZone.structuralTag == "LH");

      double minTrendZoneQuality =
         continuationLike
         ? MathMax(5.25, ZoneWeakRejectThreshold)
         : ZoneMajorScoreThreshold;

      if(workingZone.qualityScore < minTrendZoneQuality)
      {
         out.reason = "BEAR trend: primary resistance zone too weak";
         Print("[ZONE_REJECT] trend_primary_too_weak id=", workingZone.id,
               " quality=", DoubleToString(workingZone.qualityScore, 2),
               " threshold=", DoubleToString(minTrendZoneQuality, 2),
               " continuationLike=", continuationLike);
         return out;
      }

      out = EvaluateSellFromPrimaryZone(workingZone, ind, prof);
      if(out.zoneIdx < 0)
         out.zoneIdx = workingIdx;
      return out;
   }

   out.reason = "NEUTRAL trend - no trades";
   return out;
}

EntryDecision EvaluateBuyFromPrimaryZone(const ZoneInfo &zone, const IndicatorState &ind, const SymbolProfile &prof)
{
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = true;
   out.mode = TRADE_MODE_BULL_TREND;

   double price = ind.closeArr[1];
   double atr = GetATR(ind, 1);
   if(atr <= 0.0)
   {
      out.reason = "ATR<=0";
      return out;
   }

   double distATR = ZoneDistanceFromPriceATR(zone, price, atr);
   if(distATR > 1.75)
   {
      out.reason = "Price too far from bull continuation zone";
      return out;
   }

   ENUM_ZONE_INTERACTION interaction = ZONE_INTERACTION_NONE;
   double stopAnchor = 0.0;
   if(!HasBullishPrimaryZoneConfirmation(ind, zone, atr, interaction, stopAnchor))
   {
      out.reason = "No bullish confirmation at primary demand";
      return out;
   }

   double anchor = MathMin(zone.lowerBound, stopAnchor);
   double sl = NormalizeDouble(anchor - atr * 0.22, prof.digits);
   if(sl >= price - prof.point * 5)
   {
      out.reason = "Invalid SL for bull continuation";
      return out;
   }

   double oppMid = 0.0;
   bool hasOpp = (FindNextMajorOppositeZone(true, price, atr, oppMid) >= 0 &&
                  oppMid > price + atr * 0.30);

   double tpCandidate = hasOpp ? oppMid : price + (price - sl) * 2.2;
   double rr = (tpCandidate - price) / MathMax(price - sl, prof.point * 10.0);

   if(rr < 1.40)
   {
      out.reason = "RR too low for bull continuation";
      return out;
   }

   out.valid = true;
   out.stopLoss = sl;
   out.takeProfit = NormalizeDouble(tpCandidate, prof.digits);
   out.projectedRR = rr;
   out.zoneIdx = FindZoneById(zone.id);
   out.interactionType = interaction;
   out.reason = StringFormat("PRIMARY BUY | trigger=CONTINUATION | interaction=%s | demand=%s | RR=%.2f",
                             InteractionToString(interaction),
                             DoubleToString(zone.midPoint, _Digits),
                             rr);

   Print("[PRIMARY_BUY] tag=", zone.structuralTag,
         " price=", DoubleToString(price, _Digits),
         " demand=", DoubleToString(zone.midPoint, _Digits),
         " sl=", DoubleToString(sl, _Digits),
         " tpRef=", DoubleToString(tpCandidate, _Digits),
         " rr=", DoubleToString(rr, 2),
         " interaction=", InteractionToString(interaction));

   return out;
}

EntryDecision EvaluateSellFromPrimaryZone(const ZoneInfo &zone, const IndicatorState &ind, const SymbolProfile &prof)
{
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = false;
   out.mode = TRADE_MODE_BEAR_TREND;

   double price = ind.closeArr[1];
   double atr = GetATR(ind, 1);
   if(atr <= 0.0)
   {
      out.reason = "ATR<=0";
      return out;
   }

   double distATR = ZoneDistanceFromPriceATR(zone, price, atr);
   if(distATR > 1.75)
   {
      out.reason = "Price too far from bear continuation zone";
      return out;
   }

   ENUM_ZONE_INTERACTION interaction = ZONE_INTERACTION_NONE;
   double stopAnchor = 0.0;
   if(!HasBearishPrimaryZoneConfirmation(ind, zone, atr, interaction, stopAnchor))
   {
      out.reason = "No bearish confirmation at primary supply";
      return out;
   }

   double anchor = MathMax(zone.upperBound, stopAnchor);
   double sl = NormalizeDouble(anchor + atr * 0.22, prof.digits);
   if(sl <= price + prof.point * 5)
   {
      out.reason = "Invalid SL for bear continuation";
      return out;
   }

   double oppMid = 0.0;
   bool hasOpp = (FindNextMajorOppositeZone(false, price, atr, oppMid) >= 0 &&
                  oppMid < price - atr * 0.30);

   double tpCandidate = hasOpp ? oppMid : price - (sl - price) * 2.2;
   double rr = (price - tpCandidate) / MathMax(sl - price, prof.point * 10.0);

   if(rr < 1.40)
   {
      out.reason = "RR too low for bear continuation";
      return out;
   }

   out.valid = true;
   out.stopLoss = sl;
   out.takeProfit = NormalizeDouble(tpCandidate, prof.digits);
   out.projectedRR = rr;
   out.zoneIdx = FindZoneById(zone.id);
   out.interactionType = interaction;
   out.reason = StringFormat("PRIMARY SELL | trigger=CONTINUATION | interaction=%s | supply=%s | RR=%.2f",
                             InteractionToString(interaction),
                             DoubleToString(zone.midPoint, _Digits),
                             rr);

   Print("[PRIMARY_SELL] tag=", zone.structuralTag,
         " price=", DoubleToString(price, _Digits),
         " supply=", DoubleToString(zone.midPoint, _Digits),
         " sl=", DoubleToString(sl, _Digits),
         " tpRef=", DoubleToString(tpCandidate, _Digits),
         " rr=", DoubleToString(rr, 2),
         " interaction=", InteractionToString(interaction));

   return out;
}

//+==================================================================+
//| SECTION 5: TREND SIGNAL CORE — BUY & SELL                       |
//| ShouldOpenBuy / ShouldOpenSell: full H4 trend entry stack        |
//+==================================================================+

//+------------------------------------------------------------------+
//| ShouldOpenBuy — STRUCTURE-FIRST CLUSTER ARCHITECTURE             |
//+------------------------------------------------------------------+
EntryDecision ShouldOpenBuy(const IndicatorState &ind,
                             const SymbolProfile  &prof,
                             double adxMin,      double adxTrend,
                             double adxRange,    double zoneTolMult,
                             double stopMult,    double rr,
                             int    slopeLB = 3)
{
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = true;

   if(!IsTrendBuyContextClean())
   {
      out.reason = "buy blocked: D1/H4 trend context not clean enough";
      Print("[TREND_CONTEXT_BLOCK] side=BUY d1=", D1BiasToString(GetD1Bias()),
            " state=", StructureStateToString(g_structure.state),
            " transition=", g_structure.rangeLikelyTransition,
            " dirValid=", (g_structure.channel.valid ? g_structure.channel.directionalValid : true),
            " HH=", g_structure.consecutiveHH, " HL=", g_structure.consecutiveHL);
      return out;
   }

   // --- STEP 1: STRUCTURE-FIRST CHECK ---
   // Require bullish structure (HH+HL) or bull bias from market structure
   // Indicators alone cannot create bull trend direction
   bool hasBullishStructure = (g_structure.consecutiveHH >= 1 && g_structure.consecutiveHL >= 1);
   bool hasBullBias = (g_structure.state == STRUCTURE_BULL_TREND || 
                       g_structure.state == STRUCTURE_BIAS_BULL);
   
   // BLOCK: Do not allow indicator-only trends
   // EMA50 > EMA200 + ADX high but no HH/HL sequence => reject
   double ema50 = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   double adxNow = GetADX(ind, 1);
   double atr   = GetATR(ind, 1);
   double price = ind.closeArr[1];
   if(atr <= 0.0) { out.reason = "ATR<=0"; return out; }

   // D1 ZONE PERMISSION - Soft guidance only, no hard block
   {
      double d1DemandMid = GetNearestD1Demand(price);
      bool insideD1Zone = (d1DemandMid > 0.0 && MathAbs(price - d1DemandMid) <= atr * 1.8);

      if(insideD1Zone)
      {
         Print("[D1_ZONE_CONFIRM] side=BUY d1Demand=", DoubleToString(d1DemandMid, _Digits),
               " price=", DoubleToString(price, _Digits),
               " distATR=", DoubleToString(MathAbs(price - d1DemandMid) / atr, 2));
      }
      else
      {
         Print("[D1_ZONE_SOFT] side=BUY no_hard_block d1Demand=", DoubleToString(d1DemandMid, _Digits),
               " price=", DoubleToString(price, _Digits));
      }
   }
   bool emaOnlyBull = (ema50 > ema200 && adxNow >= adxTrend && !hasBullishStructure && !hasBullBias);
   
   if(emaOnlyBull)
   {
      out.reason = "BLOCKED: EMA/ADX alone cannot create bull trend without HH/HL structure";
      Print("[INDICATOR_ONLY_BLOCK] side=BUY reason=no_structure ema50>ema200=true adx=", 
            DoubleToString(adxNow, 1), " HH=", g_structure.consecutiveHH, " HL=", g_structure.consecutiveHL);
      return out;
   }
   
   MARKET_REGIME regime = GetRegimeFromMarketStructure();
   if(regime == REGIME_NONE)
   {
      regime = ClassifyMarketRegime(ind, slopeLB, 14, adxTrend, adxRange, false);
      Print("[REGIME_SOURCE] fallback_classifier regime=", EnumToString(regime));
   }
   else
      Print("[REGIME_SOURCE] market_structure regime=", EnumToString(regime),
            " state=", StructureStateToString(g_structure.state),
            " HH=", g_structure.consecutiveHH, " HL=", g_structure.consecutiveHL);

   if(regime != REGIME_TREND_BULL)
   {
      out.reason = "regime is not bull trend";
      return out;
   }

   // --- STEP 2: Quality gates (indicators CONFIRM, not DECIDE) ---

   // ADX filter - but allow weak ADX if structure is strong
   if(adxNow < adxMin && !hasBullishStructure)
   {
      out.reason = StringFormat("ADX too low %.1f < %.1f and no strong structure", adxNow, adxMin);
      return out;
   }
   // Phase 6: Overstretched check moved after cluster selection (see below)

   // --- STEP 3: Break-retest continuation (priority 1) ---
   double pullbackSL = 0.0, pullbackTP = 0.0;
   if(g_breakout.valid && IsBullishPullbackEntryAllowed(ind, price, atr, pullbackSL, pullbackTP))
   {
      double risk   = price - pullbackSL;
      double reward = pullbackTP - price;
      double projRR = (risk > 0.0) ? reward / risk : 0.0;
      if(projRR >= 1.0)
      {
         double ema200Adj = GetEMA200RankAdjustment(ind, true);
         out.valid          = true;
         out.isBuy          = true;
         out.mode           = TRADE_MODE_BULL_TREND;
         out.zoneIdx        = -1;
         out.stopLoss       = NormalizeDouble(pullbackSL, prof.digits);
         out.takeProfit     = NormalizeDouble(pullbackTP, prof.digits);
         out.projectedRR    = projRR;
         out.usedZoneTarget = true;
         out.rankScore      = projRR + 1.25 + ema200Adj;
         out.reason         = StringFormat("PULLBACK BUY | SL=%.5f | TP=%.5f | RR=%.2f",
                                           pullbackSL, pullbackTP, projRR);
         return out;
      }
   }

   // --- STEP 4: Build bull trend cluster (single trend boundary) ---
   TrendCluster cluster = BuildBullTrendCluster(ind, atr);
   if(!cluster.valid)
   {
      out.reason = "no valid bull trend cluster (no trend boundary support)";
      Print("[TREND_CLUSTER] side=BUY result=no_cluster");
      return out;
   }
   Print("[TREND_CLUSTER] side=BUY type=", cluster.label,
         " mid=", DoubleToString(cluster.mid, prof.digits),
         " score=", DoubleToString(cluster.baseScore, 2));

   // Pullback-quality veto: reject shallow or deep pullbacks
   double pullbackDepth = cluster.high - MathMin(ind.lowArr[1], ind.lowArr[2]);
   if(pullbackDepth < atr * 0.20)
   {
      out.reason = "bull trend pullback too shallow";
      return out;
   }

   if(pullbackDepth > atr * 1.80)
   {
      out.reason = "bull trend pullback too deep";
      return out;
   }

   // Phase 6: Overstretched check AFTER cluster found, with near-boundary exception
   bool nearBoundary = (cluster.mid > 0.0 && MathAbs(price - cluster.mid) <= atr * 0.75);
   if(IsOverstretchedBuy(ind, 3.50) && !nearBoundary)
   {
      out.reason = "buy overstretched away from boundary";
      Print("[OVERSTRETCHED] side=BUY nearBoundary=false price_to_cluster=", 
            DoubleToString(MathAbs(price - cluster.mid) / atr, 2), "ATR");
      return out;
   }

   // --- STEP 5: Require confirmation at cluster ---
   double stopAnchor  = 0.0;
   double scoreBoost  = 0.0;
   string triggerLabel = "";
   if(!ConfirmBullTrendClusterEntry(ind, cluster, atr, UseSweepEntry,
                                    stopAnchor, scoreBoost, triggerLabel))
   {
      out.reason = "no confirmation at bull cluster (no sweep/rejection/engulfing/continuation)";
      Print("[TREND_CLUSTER_REJECT] side=BUY reason=no_confirmation_at_selected_boundary cluster=", cluster.label);
      // MOMENTUM_CONTINUATION no longer creates standalone entries — requires valid zone interaction
      return out;
   }
   Print("[TREND_TRIGGER] side=BUY trigger=", triggerLabel,
         " cluster=", cluster.label,
         " boost=", DoubleToString(scoreBoost, 2));

   // Patch 5: Reject if price has chased too far from the selected cluster
   double maxChaseDistATR = (StringFind(_Symbol, "GBPUSD") >= 0) ? 0.55 : 0.35;
   if(atr > 0.0 && MathAbs(price - cluster.mid) / atr > maxChaseDistATR)
   {
      out.reason = "buy trigger confirmed but entry too far from selected cluster";
      Print("[TREND_CLUSTER_REJECT] side=BUY reason=entry_chased_cluster dist_atr=",
            DoubleToString(MathAbs(price - cluster.mid) / atr, 2));
      return out;
   }

   // --- STEP 6: Build ONE buy decision ---
   double sl      = 0.0;
   double tp      = 0.0;
   double oppMid  = 0.0;
   double projRR  = 0.0;
   double risk    = 0.0;
   double reward  = 0.0;

   bool usedMajorOpp   = false;
   bool usedDynamicOpp = false;

   // Zone-first target logic only.
   // Channels are visual/context only and must not provide entries or TP.
   double wickLow = GetRecentSetupWickLow(ind, 5);
   double stopBufferATR = (StringFind(_Symbol, "GBPUSD") >= 0 ? 0.45 : 0.30);
   sl = BuildBufferedBuyStop(MathMin(cluster.low, stopAnchor), wickLow, atr, stopBufferATR, prof.digits);

   if(FindNextMajorOppositeZone(true, price, atr, oppMid) >= 0 && oppMid > price + atr * 0.30)
   {
      tp = NormalizeDouble(oppMid - atr * 0.15, prof.digits);
      usedMajorOpp = true;
   }
   else
   {
      tp = NormalizeDouble(price + (price - sl) * MathMax(1.20, rr * 0.75), prof.digits);
   }

   risk   = price - sl;
   reward = tp - price;
   projRR = (risk > 0.0) ? reward / risk : 0.0;

   bool isBiasState = (g_structure.valid && g_structure.state == STRUCTURE_BIAS_BULL);
   bool diagContinuation = cluster.fromDynamicChannel;
   bool channelToChannelTrade = false;
   bool runnerStyle = (g_trendTradesUseNoFixedTP &&
                       !channelToChannelTrade &&
                       (cluster.fromDynamicChannel || triggerLabel == "CONTINUATION" || triggerLabel == "CONTINUATION_STRONG"));

   double minRR = isBiasState ? 0.75 : 1.0;
   if(!isBiasState && triggerLabel == "CONTINUATION")
      minRR = 1.10;

   if(diagContinuation)
      minRR = isBiasState ? 0.60 : 0.50;

   if(runnerStyle && !usedMajorOpp)
      minRR = MathMin(minRR, isBiasState ? 0.55 : 0.45);

   if(risk <= 0.0 || projRR < minRR)
   {
      out.reason = StringFormat("cluster BUY RR too low %.2f (min=%.2f%s)",
                                projRR, minRR, isBiasState ? " bias" : "");
      Print("[TREND_CLUSTER_REJECT] side=BUY reason=rr_too_low projRR=",
            DoubleToString(projRR, 2), " minRR=", DoubleToString(minRR, 2));
      return out;
   }

   if(runnerStyle && !usedMajorOpp)
   {
      Print("[TREND_CLUSTER_RR_OVERRIDE] side=BUY runner=true usedDynamicOpp=", usedDynamicOpp,
            " projRR=", DoubleToString(projRR, 2),
            " minRR=", DoubleToString(minRR, 2));
   }

   double ema200Adj = GetEMA200RankAdjustment(ind, true);

   out.valid          = true;
   out.isBuy          = true;
   out.mode           = TRADE_MODE_BULL_TREND;
   out.zoneIdx        = -1;
   out.stopLoss       = sl;
   out.takeProfit     = tp;
   out.projectedRR    = projRR;
   out.usedZoneTarget = (oppMid > 0.0);

   // Dynamic channel confluence disabled (channel code removed)
   double chanBonusBuy = 0.0;
   bool   nearChanSup  = false; // Channel code removed
   if(nearChanSup) chanBonusBuy = 0.15;
   Print("[DYNAMIC_CHANNEL] buy_confluence=", nearChanSup,
         " bonus=", DoubleToString(chanBonusBuy, 2));

   out.rankScore      = projRR + cluster.baseScore + scoreBoost + ema200Adj + chanBonusBuy;
   out.reason         = StringFormat(
      "TREND CLUSTER BUY | trigger=%s | path=%s | cluster=%s | SL=%.5f | TP=%.5f | RR=%.2f",
      triggerLabel,
      "STANDARD",
      cluster.label, sl, tp, projRR);
   return out;
}

//+------------------------------------------------------------------+
//| Range zone interaction role                                      |
//+------------------------------------------------------------------+
enum RANGE_ZONE_ROLE
{
   RANGE_ROLE_NONE   = 0,
   RANGE_ROLE_DEMAND = 1,
   RANGE_ROLE_SUPPLY = 2
};

RANGE_ZONE_ROLE DetectRangeZoneRole(const IndicatorState &ind,
                                    double zoneLow,
                                    double zoneHigh,
                                    double atr,
                                    bool   useSweep,
                                    string &triggerLabel)
{
   triggerLabel = "";
   if(atr <= 0.0) return RANGE_ROLE_NONE;

   double zoneMid = (zoneLow + zoneHigh) * 0.5;
   double close1  = ind.closeArr[1];
   double open1   = ind.openArr[1];
   double low1    = ind.lowArr[1];
   double high1   = ind.highArr[1];

   // TIGHTER interaction window — do not treat far-away candles as valid zone interaction
   bool closeNearZone = (close1 >= zoneLow - atr * 0.30 && close1 <= zoneHigh + atr * 0.30);
   bool wickOverlap   = (low1  <= zoneHigh + atr * 0.15 && high1 >= zoneLow - atr * 0.15);
   bool nearZone      = (closeNearZone || wickOverlap);

   Print("[RANGE_ROLE] nearZone=", nearZone, " closeNear=", closeNearZone, " wickOverlap=", wickOverlap,
         " close=", DoubleToString(close1, _Digits),
         " zoneLow=", DoubleToString(zoneLow, _Digits),
         " zoneHigh=", DoubleToString(zoneHigh, _Digits));

   if(!nearZone)
   {
      Print("[RANGE_ROLE] detected=NONE reason=price_not_near_zone");
      return RANGE_ROLE_NONE;
   }

   // Require a reclaim/hold condition so the bot does not flip role from one weak candle
   bool buyAccept  = (close1 >= zoneLow - atr * 0.03);
   bool sellAccept = (close1 <= zoneHigh + atr * 0.03);

   bool bullSweep  = (useSweep && low1 < zoneLow - atr * 0.05 && close1 > zoneLow);
   bool bullReject = (IsBullishRejection(ind) && close1 >= zoneLow && close1 >= open1);
   bool bullEngulf = (IsBullishEngulfing(_Symbol, g_indicatorTF, 1) && close1 >= zoneLow);

   bool bearSweep  = (useSweep && high1 > zoneHigh + atr * 0.05 && close1 < zoneHigh);
   bool bearReject = (IsBearishRejection(ind) && close1 <= zoneHigh && close1 <= open1);
   bool bearEngulf = (IsBearishEngulfing(_Symbol, g_indicatorTF, 1) && close1 <= zoneHigh);

   double demandScore = 0.0;
   double supplyScore = 0.0;

   if(buyAccept)
   {
      if(bullSweep)  demandScore += 2.50;
      if(bullReject) demandScore += 1.75;
      if(bullEngulf) demandScore += 1.00;
      if(close1 >= zoneMid) demandScore += 0.25;
   }

   if(sellAccept)
   {
      if(bearSweep)  supplyScore += 2.50;
      if(bearReject) supplyScore += 1.75;
      if(bearEngulf) supplyScore += 1.00;
      if(close1 <= zoneMid) supplyScore += 0.25;
   }

   Print("[RANGE_ROLE] demandScore=", DoubleToString(demandScore, 2),
         " supplyScore=", DoubleToString(supplyScore, 2),
         " bullSweep=", bullSweep, " bullReject=", bullReject, " bullEngulf=", bullEngulf,
         " bearSweep=", bearSweep, " bearReject=", bearReject, " bearEngulf=", bearEngulf,
         " buyAccept=", buyAccept, " sellAccept=", sellAccept);

   // Stronger threshold and wider separation
   if(demandScore < 1.50 && supplyScore < 1.50)
   {
      Print("[RANGE_ROLE] detected=NONE reason=both_scores_too_low");
      return RANGE_ROLE_NONE;
   }

   double scoreDiff = MathAbs(demandScore - supplyScore);
   if(scoreDiff < 0.75)
   {
      Print("[RANGE_ROLE] detected=NONE reason=scores_too_close diff=", DoubleToString(scoreDiff, 2));
      return RANGE_ROLE_NONE;
   }

   if(demandScore > supplyScore)
   {
      if(!buyAccept)
      {
         Print("[RANGE_ROLE] detected=NONE reason=demand_not_accepted");
         return RANGE_ROLE_NONE;
      }

      if(bullSweep)       triggerLabel = "SWEEP";
      else if(bullReject) triggerLabel = "REJECTION";
      else                triggerLabel = "ENGULFING";

      Print("[RANGE_ROLE] detected=DEMAND trigger=", triggerLabel,
            " score=", DoubleToString(demandScore, 2));
      return RANGE_ROLE_DEMAND;
   }
   else
   {
      if(!sellAccept)
      {
         Print("[RANGE_ROLE] detected=NONE reason=supply_not_accepted");
         return RANGE_ROLE_NONE;
      }

      if(bearSweep)       triggerLabel = "SWEEP";
      else if(bearReject) triggerLabel = "REJECTION";
      else                triggerLabel = "ENGULFING";

      Print("[RANGE_ROLE] detected=SUPPLY trigger=", triggerLabel,
            " score=", DoubleToString(supplyScore, 2));
      return RANGE_ROLE_SUPPLY;
   }
}

//+------------------------------------------------------------------+
//| Range boundary structs (defined in ZoneManager.mqh)              |
//+------------------------------------------------------------------+
// RangeBoundaryCandidate and RangeBoundarySelection are defined in ZoneManager.mqh
// Using ZoneManager.mqh versions to avoid duplicate declaration errors

RangeBoundaryCandidate MakeEmptyRangeBoundaryCandidate()
{
   RangeBoundaryCandidate c;
   c.valid = false;
   c.zoneIdx = -1;
   c.isDemand = false;
   c.lowerBound = 0.0;
   c.upperBound = 0.0;
   c.mid = 0.0;
   c.score = 0.0;
   return c;
}

RangeBoundarySelection MakeEmptyRangeBoundarySelection()
{
   RangeBoundarySelection s;
   s.valid = false;
   s.reason = "";
   s.bestDemand = MakeEmptyRangeBoundaryCandidate();
   s.bestSupply = MakeEmptyRangeBoundaryCandidate();
   s.totalWidth = 0.0;
   s.provisional = false;
   return s;
}

//+------------------------------------------------------------------+
//| PATCH 2 — Demand/Supply family type helpers                     |
//+------------------------------------------------------------------+
bool IsDemandFamilyZoneType(ENUM_ZONE_TYPE zt)
{
   return (zt == ZONE_DEMAND_MAJOR ||
           zt == ZONE_DEMAND_MINOR ||
           zt == ZONE_DEMAND);
}

bool IsSupplyFamilyZoneType(ENUM_ZONE_TYPE zt)
{
   return (zt == ZONE_SUPPLY_MAJOR ||
           zt == ZONE_SUPPLY_MINOR ||
           zt == ZONE_SUPPLY);
}

bool IsMajorDemandFamilyZoneType(ENUM_ZONE_TYPE zt)
{
   return (zt == ZONE_DEMAND_MAJOR || zt == ZONE_DEMAND);
}

bool IsMajorSupplyFamilyZoneType(ENUM_ZONE_TYPE zt)
{
   return (zt == ZONE_SUPPLY_MAJOR || zt == ZONE_SUPPLY);
}

//+------------------------------------------------------------------+
//| PATCH 3 — Build range boundary candidate from a zone index       |
//+------------------------------------------------------------------+
RangeBoundaryCandidate BuildRangeBoundaryCandidateFromZone(int idx)
{
   RangeBoundaryCandidate c = MakeEmptyRangeBoundaryCandidate();
   if(idx < 0 || idx >= g_zoneReg.count) return c;

   ZoneInfo z = g_zoneReg.zones[idx];
   if(!z.active || z.traded || z.historical) return c;

   c.valid = true;
   c.zoneIdx = idx;
   c.lowerBound = z.lowerBound;
   c.upperBound = z.upperBound;
   c.mid = z.midPoint;
   c.isDemand = IsDemandFamilyZoneType(z.type);

   c.score = z.strength;
   bool isMajor = IsMajorDemandFamilyZoneType(z.type) ||
                 IsMajorSupplyFamilyZoneType(z.type);
   bool isFresh = (z.freshness > 0.5);
   if(isMajor) c.score += 1.5;
   if(isFresh) c.score += 0.75;

   return c;
}

RangeBoundaryCandidate MakeBoundaryCandidate(int idx, const ZoneInfo &z, double score)
{
   RangeBoundaryCandidate c = MakeEmptyRangeBoundaryCandidate();
   c.valid = true;
   c.zoneIdx = idx;
   c.lowerBound = z.lowerBound;
   c.upperBound = z.upperBound;
   c.mid = z.midPoint;
   
   // Set isDemand based on zone family type - will be validated later against price position
   c.isDemand = IsDemandFamilyZoneType(z.type);
   c.score = score;
   return c;
}

//+------------------------------------------------------------------+
//| PATCH 5 — Reset range boundary candidate helper                   |
//+------------------------------------------------------------------+
void ResetRangeBoundaryCandidate(RangeBoundaryCandidate &c)
{
   c = MakeEmptyRangeBoundaryCandidate();
}

//+------------------------------------------------------------------+
//| PATCH 6 — Sticky boundary validation helper                       |
//+------------------------------------------------------------------+
bool IsBoundaryCandidateUsable(const RangeBoundaryCandidate &c, bool wantDemand, double price, double atr)
{
   if(!c.valid)
      return false;

   // RELAXED: Allow swing-based boundaries (zoneIdx == -1)
   // if(c.zoneIdx < 0)
   //    return false;

   double tol = MathMax(atr * 0.30, _Point * 16.0);

   // CRITICAL: Validate position vs price to prevent wrong-side assignments
   if(wantDemand)
   {
      // Demand must be BELOW price
      if(c.mid >= price - tol)
         return false;
      // Demand candidate must have isDemand flag
      if(!c.isDemand)
         return false;
   }
   else
   {
      // Supply must be ABOVE price
      if(c.mid <= price + tol)
         return false;
      // Supply candidate must NOT have isDemand flag
      if(c.isDemand)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| PATCH 7 — Resolve same zone on both sides helper                  |
//+------------------------------------------------------------------+
void ResolveBoundaryCollision(RangeBoundarySelection &out, double price, double atr)
{
   if(!out.bestDemand.valid || !out.bestSupply.valid)
      return;

   if(out.bestDemand.zoneIdx != out.bestSupply.zoneIdx)
      return;

   // same zone cannot be both sides
   Print("[RANGE_BOUNDARY_COLLISION] zoneIdx=", out.bestDemand.zoneIdx,
         " demandScore=", DoubleToString(out.bestDemand.score, 2),
         " supplyScore=", DoubleToString(out.bestSupply.score, 2));

   if(out.bestDemand.score >= out.bestSupply.score)
      ResetRangeBoundaryCandidate(out.bestSupply);
   else
      ResetRangeBoundaryCandidate(out.bestDemand);
}

//+------------------------------------------------------------------+
//| PATCH 4 — Select nearest support below + nearest resistance above|
//| HARD RULE: Range trades may ONLY open near strongest outer       |
//|   support or resistance. Reject oversized ranges.                |
//+------------------------------------------------------------------+
RangeBoundarySelection SelectStrongestRangeBoundaries(const IndicatorState &ind,
                                                      double maxZoneDistATR = 2.0,
                                                      double minWidthATR = 0.8,
                                                      double maxWidthATR = 6.0)
{
   RangeBoundarySelection out = MakeEmptyRangeBoundarySelection();

   ResetRangeBoundaryCandidate(out.bestDemand);
   ResetRangeBoundaryCandidate(out.bestSupply);

   double atr   = GetATR(ind, 1);
   double price = ind.closeArr[1];
   if(atr <= 0.0)
   {
      out.reason = "ATR<=0";
      return out;
   }

   PromotePrimaryZones(price, atr);
   g_primaryZones = BuildPrimaryZonesFromRegistry(price, atr);
   SanitizePrimaryZones(g_primaryZones, price, atr);

   if(g_primaryZones.hasSupport &&
      g_primaryZones.hasResistance &&
      g_primaryZones.support.id != g_primaryZones.resistance.id &&
      g_primaryZones.support.midPoint < price &&
      g_primaryZones.resistance.midPoint > price)
   {
      int supIdx = FindZoneById(g_primaryZones.support.id);
      int resIdx = FindZoneById(g_primaryZones.resistance.id);

      if(supIdx >= 0)
      {
         out.bestDemand = MakeBoundaryCandidate(
            supIdx,
            g_primaryZones.support,
            g_primaryZones.support.score + 3.0
         );
         // PATCH 15: Reject weak zones in range mode
         if(g_primaryZones.support.qualityScore < ZoneWeakRejectThreshold)
         {
            Print("[ZONE_REJECT] range_boundary_too_weak id=", g_primaryZones.support.id,
                  " quality=", DoubleToString(g_primaryZones.support.qualityScore, 2),
                  " threshold=", DoubleToString(ZoneWeakRejectThreshold, 2));
            out.bestDemand = MakeEmptyRangeBoundaryCandidate();
         }
      }

      if(resIdx >= 0)
      {
         out.bestSupply = MakeBoundaryCandidate(
            resIdx,
            g_primaryZones.resistance,
            g_primaryZones.resistance.score + 3.0
         );
         // PATCH 15: Reject weak zones in range mode
         if(g_primaryZones.resistance.qualityScore < ZoneWeakRejectThreshold)
         {
            Print("[ZONE_REJECT] range_boundary_too_weak id=", g_primaryZones.resistance.id,
                  " quality=", DoubleToString(g_primaryZones.resistance.qualityScore, 2),
                  " threshold=", DoubleToString(ZoneWeakRejectThreshold, 2));
            out.bestSupply = MakeEmptyRangeBoundaryCandidate();
         }
      }

      Print("[RANGE_PRIMARY_SEED] supportIdx=", supIdx,
            " resistanceIdx=", resIdx,
            " supportId=", g_primaryZones.support.id,
            " resistanceId=", g_primaryZones.resistance.id);
   }

   // Primary sort: boundaryScore (strength + freshness + major bonus + demand/supply small bonus - touch penalty).
   // Tiebreaker: prefer OUTER boundary (farther support / higher resistance) so range uses
   // the strongest structural walls, not inner clutter near current price.
   double bestSupScore = -DBL_MAX;
   double bestResScore = -DBL_MAX;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!IsEligibleDirectionalRangeZone(z, true) && !IsEligibleDirectionalRangeZone(z, false))
         continue;

      if(InpUseSupplyDemandZones && InpSDTradeOnlyActivePair && !SDIsActiveTradingZone(z))
         continue;

      double distATR = ZoneDistanceFromPriceATR(z, price, atr);

      // PROMOTED PRIMARY PAIR BONUS: Give strong bonus to zones that match promoted primary pair
      double primaryPairBonus = 0.0;
      if(z.isPrimary)
      {
         if(g_primaryZones.hasSupport && z.id == g_primaryZones.support.id && z.midPoint < price)
            primaryPairBonus = 3.00;
         if(g_primaryZones.hasResistance && z.id == g_primaryZones.resistance.id && z.midPoint > price)
            primaryPairBonus = 3.00;
      }

      // Phase 8: Check for SUPPORT zones - horizontal SR only (no ZONE_DEMAND)
      // Support candidates: SUPPORT_MAJOR, SUPPORT_MINOR, or flipped resistance zones
      bool isSupportType = (z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_SUPPORT_MINOR || 
                            (z.isFlipZone && (z.originalType == ZONE_RESISTANCE_MAJOR || z.originalType == ZONE_RESISTANCE_MINOR)));
      if(isSupportType && z.midPoint < price && distATR <= maxZoneDistATR)
      {
         // PATCH 15: Reject weak zones in range mode
         if(z.qualityScore < ZoneWeakRejectThreshold)
            continue;

         double majorBonus = (z.type == ZONE_SUPPORT_MAJOR) ? 1.50 : 0.50;
         double flipBonus = z.isFlipZone ? 0.75 : 0.0;
         double primaryBonusSup = z.isPrimary ? 2.00 : (z.isBackup ? 0.50 : 0.0);
         double bScore = z.score    * 2.0
                       + z.strength * 1.5
                       + (z.freshness > 0.5 ? 0.75 : 0.0)
                       + majorBonus
                       + flipBonus
                       - z.cleanTouchCount * 0.20
                       + primaryBonusSup
                       + primaryPairBonus;
         bool isOuter = (!out.bestDemand.valid || z.midPoint < out.bestDemand.mid);
         if(bScore > bestSupScore || (bScore > bestSupScore - 0.30 && isOuter))
         {
            bestSupScore = bScore;
            out.bestDemand = MakeBoundaryCandidate(i, z, bScore);
         }
      }

      // Phase 8: Check for RESISTANCE zones - horizontal SR only (no ZONE_SUPPLY)
      // Resistance candidates: RESISTANCE_MAJOR, RESISTANCE_MINOR, or flipped support zones
      bool isResistanceType = (z.type == ZONE_RESISTANCE_MAJOR || z.type == ZONE_RESISTANCE_MINOR || 
                               (z.isFlipZone && (z.originalType == ZONE_SUPPORT_MAJOR || z.originalType == ZONE_SUPPORT_MINOR)));
      if(isResistanceType && z.midPoint > price && distATR <= maxZoneDistATR)
      {
         // PATCH 15: Reject weak zones in range mode
         if(z.qualityScore < ZoneWeakRejectThreshold)
            continue;

         double majorBonus = (z.type == ZONE_RESISTANCE_MAJOR) ? 1.50 : 0.50;
         double flipBonus = z.isFlipZone ? 0.75 : 0.0;
         double primaryBonusRes = z.isPrimary ? 2.00 : (z.isBackup ? 0.50 : 0.0);
         double bScore = z.score    * 2.0
                       + z.strength * 1.5
                       + (z.freshness > 0.5 ? 0.75 : 0.0)
                       + majorBonus
                       + flipBonus
                       - z.cleanTouchCount * 0.20
                       + primaryBonusRes
                       + primaryPairBonus;
         bool isOuter = (!out.bestSupply.valid || z.midPoint > out.bestSupply.mid);
         if(bScore > bestResScore || (bScore > bestResScore - 0.30 && isOuter))
         {
            bestResScore = bScore;
            out.bestSupply = MakeBoundaryCandidate(i, z, bScore);
         }
      }
   }

   // P6: Stickiness — keep previous boundary unless new candidate is clearly better or more outer
   static RangeBoundaryCandidate s_prevSupport;
   static RangeBoundaryCandidate s_prevResistance;
   static bool s_hasPrev = false;

   if(s_hasPrev)
   {
      // Keep previous support if it's still a valid zone and new one isn't materially better/more outer
      if(IsBoundaryCandidateUsable(s_prevSupport, true, price, atr))
      {
         if(s_prevSupport.zoneIdx >= 0 &&
            s_prevSupport.zoneIdx < g_zoneReg.count &&
            g_zoneReg.zones[s_prevSupport.zoneIdx].active)
         {
            bool newIsSignificantlyBetter = (out.bestDemand.valid &&
                                             out.bestDemand.score > s_prevSupport.score * 1.15);
            bool newIsMateriallyOuter     = (out.bestDemand.valid &&
                                             s_prevSupport.mid - out.bestDemand.mid > atr * 0.5);
            if(!newIsSignificantlyBetter && !newIsMateriallyOuter && out.bestDemand.valid)
            {
               Print("[RANGE_BOUNDARY_STICKINESS] kept_previous_support=", s_prevSupport.zoneIdx,
                     " prevScore=", DoubleToString(s_prevSupport.score, 2),
                     " newScore=", DoubleToString(out.bestDemand.score, 2));
               out.bestDemand = s_prevSupport;
            }
         }
      }
      else
      {
         ResetRangeBoundaryCandidate(s_prevSupport);
      }

      // Keep previous resistance if it's still a valid zone and new one isn't materially better/more outer
      if(IsBoundaryCandidateUsable(s_prevResistance, false, price, atr))
      {
         if(s_prevResistance.zoneIdx >= 0 &&
            s_prevResistance.zoneIdx < g_zoneReg.count &&
            g_zoneReg.zones[s_prevResistance.zoneIdx].active)
         {
            bool newIsSignificantlyBetter = (out.bestSupply.valid &&
                                             out.bestSupply.score > s_prevResistance.score * 1.15);
            bool newIsMateriallyOuter     = (out.bestSupply.valid &&
                                             out.bestSupply.mid - s_prevResistance.mid > atr * 0.5);
            if(!newIsSignificantlyBetter && !newIsMateriallyOuter && out.bestSupply.valid)
            {
               Print("[RANGE_BOUNDARY_STICKINESS] kept_previous_resistance=", s_prevResistance.zoneIdx,
                     " prevScore=", DoubleToString(s_prevResistance.score, 2),
                     " newScore=", DoubleToString(out.bestSupply.score, 2));
               out.bestSupply = s_prevResistance;
            }
         }
      }
      else
      {
         ResetRangeBoundaryCandidate(s_prevResistance);
      }
   }

   // POST-STICKINESS POSITION ASSERTIONS: Sticky boundaries must be on correct side of price
   // Support must be BELOW price, resistance must be ABOVE price
   if(out.bestDemand.valid && out.bestDemand.mid >= price)
   {
      Print("[RANGE_BOUNDARIES] invalidated_sticky_support_wrong_side idx=", out.bestDemand.zoneIdx,
            " supportMid=", DoubleToString(out.bestDemand.mid, _Digits),
            " price=", DoubleToString(price, _Digits));
      out.bestDemand = MakeEmptyRangeBoundaryCandidate();
   }
   if(out.bestSupply.valid && out.bestSupply.mid <= price)
   {
      Print("[RANGE_BOUNDARIES] invalidated_sticky_resistance_wrong_side idx=", out.bestSupply.zoneIdx,
            " resistanceMid=", DoubleToString(out.bestSupply.mid, _Digits),
            " price=", DoubleToString(price, _Digits));
      out.bestSupply = MakeEmptyRangeBoundaryCandidate();
   }

   // --- Part 2 patch: Swing-based provisional fallback ---
   // Count swing touches per cluster for logging
   int supTouches = 0, resTouches = 0;

   if(!out.bestDemand.valid || !out.bestSupply.valid)
   {
      // Try swing highs as resistance candidates
      if(!out.bestSupply.valid && g_structure.swingHighCount >= 1)
      {
         double tol = MathMax(atr * 0.20, _Point * 120);
         double bestClusterMid = 0.0;
         int    bestClusterCnt = 0;

         for(int si = 0; si < g_structure.swingHighCount && si < 6; si++)
         {
            double sh = g_structure.swingHighs[si].price;
            if(sh <= price) continue;           // must be above price
            // Count other swings within tolerance of this one
            int cnt = 1;
            for(int sj = 0; sj < g_structure.swingHighCount && sj < 6; sj++)
            {
               if(si == sj) continue;
               if(MathAbs(g_structure.swingHighs[sj].price - sh) <= tol) cnt++;
            }
            double clusterMid = sh;
            if(cnt > bestClusterCnt || (cnt == bestClusterCnt && clusterMid < bestClusterMid))
            {
               bestClusterCnt = cnt;
               bestClusterMid = clusterMid;
            }
         }

         if(bestClusterMid > price && (bestClusterCnt >= 2 ||
            (bestClusterCnt >= 1 && MathAbs(bestClusterMid - price) <= atr * 2.5)))
         {
            RangeBoundaryCandidate swingRes = MakeEmptyRangeBoundaryCandidate();
            swingRes.valid    = true;
            swingRes.zoneIdx  = -1;
            swingRes.isDemand = false;
            swingRes.lowerBound   = bestClusterMid - tol * 0.5;
            swingRes.upperBound  = bestClusterMid + tol * 0.5;
            swingRes.mid   = bestClusterMid;
            swingRes.score = 1.0 + bestClusterCnt * 0.8;
            out.bestSupply = swingRes;
            resTouches = bestClusterCnt;
         }
      }

      // Try swing lows as support candidates
      if(!out.bestDemand.valid && g_structure.swingLowCount >= 1)
      {
         double tol = MathMax(atr * 0.20, _Point * 120);
         double bestClusterMid = 0.0;
         int    bestClusterCnt = 0;

         for(int si = 0; si < g_structure.swingLowCount && si < 6; si++)
         {
            double sl = g_structure.swingLows[si].price;
            if(sl >= price) continue;           // must be below price
            int cnt = 1;
            for(int sj = 0; sj < g_structure.swingLowCount && sj < 6; sj++)
            {
               if(si == sj) continue;
               if(MathAbs(g_structure.swingLows[sj].price - sl) <= tol) cnt++;
            }
            double clusterMid = sl;
            if(cnt > bestClusterCnt || (cnt == bestClusterCnt && clusterMid > bestClusterMid))
            {
               bestClusterCnt = cnt;
               bestClusterMid = clusterMid;
            }
         }

         if(bestClusterMid > 0 && bestClusterMid < price && (bestClusterCnt >= 2 ||
            (bestClusterCnt >= 1 && MathAbs(price - bestClusterMid) <= atr * 2.5)))
         {
            RangeBoundaryCandidate swingSup = MakeEmptyRangeBoundaryCandidate();
            swingSup.valid    = true;
            swingSup.zoneIdx  = -1;
            swingSup.isDemand = true;
            swingSup.lowerBound   = bestClusterMid - tol * 0.5;
            swingSup.upperBound  = bestClusterMid + tol * 0.5;
            swingSup.mid   = bestClusterMid;
            swingSup.score = 1.0 + bestClusterCnt * 0.8;
            out.bestDemand = swingSup;
            supTouches = bestClusterCnt;
         }
      }

      // Also check current primary/backup zones if still missing one side
      if(!out.bestSupply.valid)
      {
         for(int i = 0; i < g_zoneReg.count; i++)
         {
            ZoneInfo z = g_zoneReg.zones[i];
            if(!z.active || z.historical || z.broken) continue;
            if(z.midPoint <= price) continue;
            if(z.isPrimary || z.isBackup || z.structuralAnchor)
            {
               RangeBoundaryCandidate fc = MakeEmptyRangeBoundaryCandidate();
               fc.valid = true; fc.zoneIdx = i;
               fc.isDemand = false;
               fc.lowerBound = z.lowerBound; fc.upperBound = z.upperBound; fc.mid = z.midPoint;
               fc.score = z.strength + (z.isPrimary ? 1.5 : 0.5);
               out.bestSupply = fc;
               resTouches = 1;
               break;
            }
         }
      }
      if(!out.bestDemand.valid)
      {
         for(int i = 0; i < g_zoneReg.count; i++)
         {
            ZoneInfo z = g_zoneReg.zones[i];
            if(!z.active || z.historical || z.broken) continue;
            if(z.midPoint >= price) continue;
            if(z.isPrimary || z.isBackup || z.structuralAnchor)
            {
               RangeBoundaryCandidate fc = MakeEmptyRangeBoundaryCandidate();
               fc.valid = true; fc.zoneIdx = i;
               fc.isDemand = true;
               fc.lowerBound = z.lowerBound; fc.upperBound = z.upperBound; fc.mid = z.midPoint;
               fc.score = z.strength + (z.isPrimary ? 1.5 : 0.5);
               out.bestDemand = fc;
               supTouches = 1;
               break;
            }
         }
      }
   }

   // Boundary scores are stored in bestDemand.score and bestSupply.score

   if(!IsBoundaryCandidateUsable(out.bestDemand, true, price, atr))
      ResetRangeBoundaryCandidate(out.bestDemand);

   if(!IsBoundaryCandidateUsable(out.bestSupply, false, price, atr))
      ResetRangeBoundaryCandidate(out.bestSupply);

   // Collision detection after all scoring/stickiness
   if(out.bestDemand.valid && out.bestSupply.valid &&
      out.bestDemand.zoneIdx == out.bestSupply.zoneIdx)
   {
      Print("[RANGE_BOUNDARY_COLLISION] zoneIdx=", out.bestDemand.zoneIdx,
            " supportScore=", DoubleToString(out.bestDemand.score, 2),
            " resistanceScore=", DoubleToString(out.bestSupply.score, 2));

      if(out.bestDemand.score >= out.bestSupply.score)
         ResetRangeBoundaryCandidate(out.bestSupply);
      else
         ResetRangeBoundaryCandidate(out.bestDemand);
   }

   Print("[RANGE_BOUNDARY_BUILD] supportTouches=", supTouches,
         " resistanceTouches=", resTouches);

   // Hybrid model: range mode uses horizontal boundaries only
   if(!out.bestDemand.valid || !out.bestSupply.valid)
   {
      out.reason = "no horizontal range boundaries";
      static datetime lastLogTime = 0;
      if(TimeCurrent() - lastLogTime > 300)
      {
         Print("[RANGE_BOUNDARIES] valid=false reason=", out.reason);
         lastLogTime = TimeCurrent();
      }
      return out;
   }

   // Mark provisional if swing-based
   out.provisional = (out.bestDemand.zoneIdx < 0 || out.bestSupply.zoneIdx < 0);

   if(out.bestDemand.valid && out.bestSupply.valid)
      out.totalWidth = out.bestSupply.mid - out.bestDemand.mid;
   else
      out.totalWidth = 0.0;

   // Reject immediately if either side is missing
   if(!out.bestDemand.valid)
   {
      out.reason = "missing support";
      Print("[RANGE_BOUNDARY_FINAL] reason=missing_support");
      return out;
   }

   if(!out.bestSupply.valid)
   {
      out.reason = "missing resistance";
      Print("[RANGE_BOUNDARY_FINAL] reason=missing_resistance");
      return out;
   }

   if(out.totalWidth < atr * minWidthATR)
   {
      out.reason = "range too narrow";
      Print("[RANGE_BOUNDARIES] valid=false reason=", out.reason,
            " widthATR=", DoubleToString(out.totalWidth / atr, 1));
      return out;
   }

   if(out.totalWidth > atr * maxWidthATR)
   {
      out.reason = "range too wide";
      Print("[RANGE_BOUNDARIES] valid=false reason=", out.reason,
            " widthATR=", DoubleToString(out.totalWidth / atr, 1));
      return out;
   }

   if(IsHorizontalRangeTooTight(out.bestDemand.upperBound, out.bestSupply.lowerBound, atr))
   {
      out.reason = "horizontal zones too close";
      double edgeGap = out.bestSupply.lowerBound - out.bestDemand.upperBound;
      Print("[RANGE_BOUNDARIES] valid=false reason=horizontal_zones_too_close gapATR=",
            DoubleToString((atr > 0 ? edgeGap / atr : 0.0), 2));
      return out;
   }

   // Hard assertions: support slot must be truly support; resistance slot must be truly resistance.
   // Flip-zone type mismatches are caught here and invalidated before any trade evaluates them.
   if(out.bestDemand.valid && !out.bestDemand.isDemand)
   {
      Print("[RANGE_BOUNDARIES] bestDemand failed isDemand assertion — invalidated");
      out.bestDemand = MakeEmptyRangeBoundaryCandidate();
   }
   if(out.bestSupply.valid && out.bestSupply.isDemand)
   {
      Print("[RANGE_BOUNDARIES] bestSupply failed !isDemand assertion — invalidated");
      out.bestSupply = MakeEmptyRangeBoundaryCandidate();
   }
   if(!out.bestDemand.valid || !out.bestSupply.valid)
   {
      out.reason = "boundary side assertion failed";
      Print("[RANGE_BOUNDARIES] valid=false reason=", out.reason);
      return out;
   }

   if(!out.bestDemand.valid || !out.bestSupply.valid)
   {
      out.provisional = true;
   }

   double rangeBoxQuality = MathMin(out.bestDemand.score, out.bestSupply.score);
   // RELAXED: Lower score requirements to accept weaker ranges
   bool strongBox      = (out.bestDemand.score >= 2.0 && out.bestSupply.score >= 2.0);
   bool provisionalBox = (!strongBox && rangeBoxQuality >= 1.5);
   if(!strongBox && !provisionalBox)
   {
      out.reason = "boundary scores too low for provisional range";
      Print("[RANGE_BOX_QUALITY] score=", DoubleToString(rangeBoxQuality, 2),
            " strong=false provisional=false — rejected");
      return out;
   }

   out.provisional = out.provisional || provisionalBox;
   out.valid = true;
   out.reason = out.provisional ? "provisional" : "ok";

   Print("[RANGE_BOX_QUALITY] score=", DoubleToString(rangeBoxQuality, 2),
         " strong=", strongBox, " provisional=", out.provisional);

   // P6: persist for next-bar stickiness (zone-based only)
   if(!out.provisional)
   {
      s_prevSupport    = out.bestDemand;
      s_prevResistance = out.bestSupply;
      s_hasPrev        = true;
   }
   Print("[RANGE_BOUNDARIES] bestSup=", out.bestDemand.zoneIdx,
         "(score=", DoubleToString(out.bestDemand.score, 2), " isDemand=true)",
         " bestRes=", out.bestSupply.zoneIdx,
         "(score=", DoubleToString(out.bestSupply.score, 2), " isDemand=false)",
         " width=", DoubleToString(out.totalWidth, _Digits),
         " widthATR=", DoubleToString(out.totalWidth / atr, 1),
         " provisional=", out.provisional);

   Print("[RANGE_BOUNDARY_FINAL] supIdx=", out.bestDemand.valid ? out.bestDemand.zoneIdx : -1,
         " resIdx=", out.bestSupply.valid ? out.bestSupply.zoneIdx : -1,
         " widthATR=", DoubleToString(out.totalWidth / atr, 2));

   return out;
}

//+------------------------------------------------------------------+
//| PATCH 5 — Block messy or clustered range maps                    |
//| HARD RULE: If boundary map is messy or too narrow, skip range.   |
//|   Dense stacked clusters must be blocked.                        |
//|   Mid-range bounces must be blocked.                             |
//+------------------------------------------------------------------+
bool IsRangeBoundaryMapMessy(const RangeBoundarySelection &sel,
                             const IndicatorState &ind,
                             double minOuterWidthATR = 1.5,
                             double edgeFraction = 0.40)
{
   if(!sel.valid) return true;

   double atr = GetATR(ind, 1);
   double price = ind.closeArr[1];
   if(atr <= 0.0) return true;

   double outerWidthATR = sel.totalWidth / atr;
   if(outerWidthATR < minOuterWidthATR) return true;

   // Proportional mid-range check: price must be within edgeFraction (30%) of total
   // range width from at least one boundary edge. This works for both narrow and wide ranges.
   double localDistToSupport = MathAbs(price - sel.bestDemand.mid);
   double localDistToResistance = MathAbs(sel.bestSupply.mid - price);
   double edgeZone = sel.totalWidth * edgeFraction;

   bool nearSupport = (localDistToSupport <= edgeZone);
   bool nearResistance = (localDistToResistance <= edgeZone);
   if(!nearSupport && !nearResistance) return true;

   return false;
}

//+------------------------------------------------------------------+
//| Horizontal Range Map Validation Helper                           |
//| Returns true only when range map has valid two-sided boundaries  |
//+------------------------------------------------------------------+
bool IsHorizontalRangeMapValid(const RangeBoundarySelection &rb)
{
   if(!rb.valid)
      return false;

   if(!rb.bestDemand.valid ||
      !rb.bestSupply.valid)
      return false;

   if(rb.bestDemand.mid <= 0.0 ||
      rb.bestSupply.mid <= 0.0)
      return false;

   if(rb.bestDemand.mid >= rb.bestSupply.mid)
      return false;

   if(rb.totalWidth <= 0.0)
      return false;

   if(rb.bestDemand.zoneIdx < 0 ||
      rb.bestSupply.zoneIdx < 0)
   {
      if(!rb.provisional)
         return false;

      Print("[RANGE_MAP_PROVISIONAL_VALID]",
            " demandMid=",
            DoubleToString(rb.bestDemand.mid, _Digits),
            " supplyMid=",
            DoubleToString(rb.bestSupply.mid, _Digits));
   }

   return true;
}

//+------------------------------------------------------------------+
//| PATCH 2 — Boundary proximity helpers for range patterns          |
//+------------------------------------------------------------------+
bool CandleClusterNearBoundary(const IndicatorState &ind,
                               double boundaryMid,
                               double atr,
                               int barsBack = 8,
                               double maxDistATR = 0.80)
{
   if(atr <= 0.0) return false;

   for(int i = 1; i <= barsBack; i++)
   {
      double mid = 0.5 * (ind.highArr[i] + ind.lowArr[i]);
      if(MathAbs(mid - boundaryMid) / atr <= maxDistATR)
         return true;
   }
   return false;
}

bool IsNearBoundaryMid(double price, double boundaryMid, double atr, double maxDistATR = 0.80)
{
   if(atr <= 0.0) return false;
   return (MathAbs(price - boundaryMid) / atr <= maxDistATR);
}

//+------------------------------------------------------------------+
//| PATCH 4 — Range-specific pattern gates tied to chosen boundary   |
//| HARD RULE: Patterns may ONLY trigger at selected strongest       |
//|   range boundaries. Not at internal zones. Not mid-range.        |
//+------------------------------------------------------------------+
bool HasBullishPatternAtRangeBoundary(const IndicatorState &ind,
                                      const RangeBoundaryCandidate &boundary)
{
   if(!boundary.valid) return false;

   double atr = GetATR(ind, 1);
   if(atr <= 0.0) return false;

   if(!CandleClusterNearBoundary(ind, boundary.mid, atr, 8, 0.80))
      return false;

   bool pattern =
      IsDoubleBottom(ind.lowArr, ind.highArr, ind.closeArr, ind.openArr, atr) ||
      IsInverseHeadAndShouldersBottom(ind.lowArr, ind.highArr, atr) ||
      IsBullishPinBar(_Symbol, g_indicatorTF, 1) ||
      IsBullishWickRejection(_Symbol, g_indicatorTF, 1, 0.40, 0.45, true) ||
      IsBullishEngulfing(_Symbol, g_indicatorTF, 1) ||
      IsFalseBreakRangeLow(ind.lowArr, ind.closeArr, boundary.lowerBound, atr);

   if(!pattern) return false;

   double price = ind.closeArr[1];
   return IsNearBoundaryMid(price, boundary.mid, atr, 0.90);
}

bool HasBearishPatternAtRangeBoundary(const IndicatorState &ind,
                                      const RangeBoundaryCandidate &boundary)
{
   if(!boundary.valid) return false;

   double atr = GetATR(ind, 1);
   if(atr <= 0.0) return false;

   if(!CandleClusterNearBoundary(ind, boundary.mid, atr, 8, 0.80))
      return false;

   bool pattern =
      IsDoubleTop(ind.highArr, ind.lowArr, ind.closeArr, ind.openArr, atr) ||
      IsHeadAndShouldersTop(ind.highArr, ind.lowArr, atr) ||
      IsBearishPinBar(_Symbol, g_indicatorTF, 1) ||
      IsBearishWickRejection(_Symbol, g_indicatorTF, 1, 0.40, 0.45, true) ||
      IsBearishEngulfing(_Symbol, g_indicatorTF, 1) ||
      IsFalseBreakRangeHigh(ind.highArr, ind.closeArr, boundary.upperBound, atr);

   if(!pattern) return false;

   double price = ind.closeArr[1];
   return IsNearBoundaryMid(price, boundary.mid, atr, 0.90);
}

//+------------------------------------------------------------------+
//| BuildRangeEntryFromBoundary — entry builder for swing-based     |
//| or any boundary candidate that has no zone registry index        |
//+------------------------------------------------------------------+
EntryDecision BuildRangeEntryFromBoundary(bool isBuy,
                                           const RangeBoundaryCandidate &entry,
                                           const RangeBoundaryCandidate &target,
                                           const IndicatorState &ind,
                                           const SymbolProfile &prof,
                                           double stopMult, double rr)
{
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = isBuy;
   out.mode  = TRADE_MODE_RANGE;

   double atr   = GetATR(ind, 1);
   double price = ind.closeArr[1];
   if(atr <= 0.0) { out.reason = "ATR<=0"; return out; }

   double lowestWick  = ind.lowArr[1];
   double highestWick = ind.highArr[1];
   for(int i = 2; i <= 5; i++)
   {
      if(ind.lowArr[i] < lowestWick)   lowestWick  = ind.lowArr[i];
      if(ind.highArr[i] > highestWick) highestWick = ind.highArr[i];
   }

   // H4-only wick detection (H1 sniper removed)

   double sl = 0.0, tp = 0.0;
   if(isBuy)
   {
      double anchor = MathMin(entry.lowerBound, lowestWick);
      sl = NormalizeDouble(anchor - atr * MathMax(stopMult, 0.25), prof.digits);
      tp = (target.valid && target.mid > price)
           ? NormalizeDouble(target.mid, prof.digits)
           : NormalizeDouble(price + (price - sl) * rr, prof.digits);
   }
   else
   {
      double anchor = MathMax(entry.upperBound, highestWick);
      sl = NormalizeDouble(anchor + atr * MathMax(stopMult, 0.25), prof.digits);
      tp = (target.valid && target.mid < price)
           ? NormalizeDouble(target.mid, prof.digits)
           : NormalizeDouble(price - (sl - price) * rr, prof.digits);
   }

   double risk = isBuy ? (price - sl) : (sl - price);
   if(risk <= prof.stopsLevelPoints * prof.point)
      { out.reason = "risk too small"; return out; }

   double projRR = (isBuy ? (tp - price) : (price - tp)) / risk;
   if(projRR < rr * 0.70)
      { out.reason = StringFormat("RR too low: %.2f < %.2f", projRR, rr * 0.70); return out; }

   out.valid       = true;
   out.stopLoss    = sl;
   out.takeProfit  = tp;
   out.projectedRR = projRR;
   Print("[RANGE_BOUNDARY_ENTRY] side=", (isBuy?"BUY":"SELL"),
         " SL=", DoubleToString(sl, prof.digits),
         " TP=", DoubleToString(tp, prof.digits),
         " RR=", DoubleToString(projRR, 2));
   out.reason = StringFormat("RANGE %s boundary entry | SL=%.5f | TP=%.5f | RR=%.2f",
                              isBuy ? "BUY" : "SELL", sl, tp, projRR);
   return out;
}

//+==================================================================+
//| SECTION 6: RANGE SIGNAL CORE — BUY & SELL                       |
//| ShouldOpenBuyRange / ShouldOpenSellRange: zone bounce entries     |
//+==================================================================+

//+------------------------------------------------------------------+
//| ShouldOpenBuyRange — armed local edge setup path                 |
//+------------------------------------------------------------------+
EntryDecision ShouldOpenBuyRange(const IndicatorState &ind,
                                  const SymbolProfile  &prof,
                                  double adxMin,      double adxTrend,
                                  double adxRange,    double zoneTolMult,
                                  double stopMult,    double rr,
                                  int    slopeLB = 3)
{
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = true;
   out.mode  = TRADE_MODE_RANGE;

   // PRIMARY: Use market structure as regime source
   // FALLBACK: Only use classifier if structure is invalid
   MARKET_REGIME regime = GetRegimeFromMarketStructure();
   if(regime == REGIME_NONE)
   {
      regime = ClassifyMarketRegime(ind, slopeLB, 14, adxTrend, adxRange, false);
      Print("[REGIME_SOURCE] range_buy fallback_classifier regime=", EnumToString(regime));
   }
   else
   {
      Print("[REGIME_SOURCE] range_buy market_structure regime=", EnumToString(regime),
            " state=", StructureStateToString(g_structure.state));
   }

   bool rangeContext =
      (regime == REGIME_RANGE) ||
      (g_structure.valid &&
       (g_structure.state == STRUCTURE_RANGE ||
        g_structure.state == STRUCTURE_CONSOLIDATION) &&
       g_structure.rangeQuality >= 6.0);

   if(!rangeContext)
   {
      out.reason = "regime is not range";
      return out;
   }

   if(regime != REGIME_RANGE)
      Print("[RANGE_SOFT_CONTEXT] side=BUY");

   Print("[DYNAMIC_CHANNEL] ignored_for_range=true side=BUY");

   // --- GRADED COUNTERTREND BLOCK FOR RANGE BUY (Part 4 patch) ---
   if(BlockCounterTrendTrades)
   {
      // Full BEAR_TREND still hard-vetoes range buys — do not fade clean breakouts
      if(g_structure.state == STRUCTURE_BEAR_TREND)
      {
         out.reason = "countertrend range buy blocked by full bear trend";
         Print("[RANGE_COUNTERTREND_BLOCK] side=BUY reason=full_bear_trend");
         return out;
      }

      // For BIAS_BEAR + channel: only block when ALL 4 conditions are met
      double adxNow_rb  = GetADX(ind, 1);
      bool chanBearNow  = (g_structure.channel.valid && g_structure.channel.directionalValid &&
                           g_structure.channel.direction == -1);
      bool transitionRB = g_structure.rangeLikelyTransition;
      double maxChaseATR_rb = MathMax(adxRange + 5.0, 26.0);

      // Check if price is inside any valid box
      RangeBoundarySelection selRB = BuildFinalHorizontalRangeMap(ind, ind.closeArr[1], MathMax(GetATR(ind, 1), 0.0000001));
      bool insideBoxRB = (selRB.valid &&
                          ind.closeArr[1] >= selRB.bestDemand.mid &&
                          ind.closeArr[1] <= selRB.bestSupply.mid);

      bool gradedVetoRB = (g_structure.state == STRUCTURE_BIAS_BEAR || chanBearNow) &&
                           adxNow_rb > maxChaseATR_rb &&
                           chanBearNow && transitionRB && !insideBoxRB;

      Print("[RANGE_ENTRY_GATE] side=BUY blocked=", gradedVetoRB,
            " adx=", DoubleToString(adxNow_rb, 1),
            " chanBear=", chanBearNow,
            " transition=", transitionRB,
            " insideBox=", insideBoxRB);

      if(gradedVetoRB)
      {
         out.reason = "range buy: graded veto (ADX+channel+transition+outside_box)";
         Print("[RANGE_COUNTERTREND_BLOCK] side=BUY reason=graded_veto adx=", DoubleToString(adxNow_rb,1));
         return out;
      }
   }

   double atr   = GetATR(ind, 1);
   double price = ind.closeArr[1];
   if(atr <= 0.0)
   {
      out.reason = "ATR<=0";
      return out;
   }

   // RANGE ADX LOGIC: No minimum floor - range entries should NOT require ADX minimum.
   // Instead, reject only when trend strength is VERY HIGH AND rising sharply.
   double adxNow  = GetADX(ind, 1);
   double adxPrev = GetADX(ind, 2);
   // RELAXED: Only reject if ADX >= 35 (strong trend) AND rising >= 4.0 (sharply increasing)
   if(adxNow >= 35.0 && (adxNow - adxPrev) >= 4.0)
   {
      out.reason = StringFormat("trend-strength too high for range ADX=%.1f rising=%.1f", adxNow, adxNow - adxPrev);
      Print("[RANGE_ADX] side=BUY adxNow=", DoubleToString(adxNow, 1),
            " adxPrev=", DoubleToString(adxPrev, 1), " pass=false (strong trend)");
      return out;
   }
   Print("[RANGE_ADX] side=BUY adxNow=", DoubleToString(adxNow, 1),
         " adxPrev=", DoubleToString(adxPrev, 1), " pass=true");

   // Select STRONGEST OUTER MAJOR support boundary — score-first, not nearest.
   RangeBoundarySelection sel = BuildFinalHorizontalRangeMap(ind, price, atr);

   if(!sel.valid || !sel.bestDemand.valid)
   {
      out.reason = StringFormat("no horizontal support boundary found: %s", sel.reason);
      Print("[RANGE_REJECT] side=BUY reason=no_horizontal_boundary detail=", sel.reason);
      return out;
   }


   // HARD SIDE LOCK: support boundary must be truly support — no exceptions
   if(!sel.bestDemand.isDemand)
   {
      out.reason = "boundary is not support — BUY side lock rejected";
      Print("[RANGE_SIDE_LOCK] side=BUY rejected_non_support_boundary idx=", sel.bestDemand.zoneIdx);
      return out;
   }
   Print("[RANGE_SIDE_LOCK] side=BUY support_idx=", sel.bestDemand.zoneIdx,
         " isDemand=", sel.bestDemand.isDemand);

   // TIGHT CONSOLIDATION CHECK: Reject if range is too narrow for safe trading
   if(sel.bestDemand.valid && sel.bestSupply.valid)
   {
      if(IsTightConsolidation(ind, sel.bestDemand.mid, sel.bestSupply.mid))
      {
         out.reason = "tight consolidation - range too narrow";
         Print("[RANGE_REJECT] side=BUY reason=tight_consolidation widthATR=",
               DoubleToString((sel.bestSupply.mid - sel.bestDemand.mid) / atr, 2));
         return out;
      }

      double widthATR_now = (sel.bestSupply.mid - sel.bestDemand.mid) / atr;
      double adxNow_now   = GetADX(ind, 1);
      double emaSpreadNow = MathAbs(GetEMA50(ind, 1) - GetEMA200(ind, 1));
      double emaSpreadATR_now = (atr > 0.0) ? emaSpreadNow / atr : 999.0;

      bool hardConsolBlock =
         (widthATR_now <= 3.00 &&
          adxNow_now <= 22.0 &&
          emaSpreadATR_now <= 1.10);

      if(hardConsolBlock)
      {
         out.reason = "hard consolidation block";
         Print("[RANGE_REJECT] side=BUY reason=hard_consolidation widthATR=",
               DoubleToString(widthATR_now, 2),
               " adx=", DoubleToString(adxNow_now, 1),
               " emaSpreadATR=", DoubleToString(emaSpreadATR_now, 2));
         return out;
      }
   }

   bool messyMap = IsRangeBoundaryMapMessy(sel, ind);
   if(messyMap)
   {
      out.reason = "messy range boundary map";
      Print("[RANGE_BOUNDARY_REJECT] side=BUY reason=messy_map");
      return out;
   }

   int supIdx = sel.bestDemand.zoneIdx;
   bool swingBasedBuy = (supIdx < 0);

   ZoneInfo z;
   if(!swingBasedBuy)
      z = g_zoneReg.zones[supIdx];
   else
   {
      ZeroMemory(z);
      z.lowerBound = sel.bestDemand.lowerBound;
      z.upperBound = sel.bestDemand.upperBound;
      z.midPoint   = sel.bestDemand.mid;
      z.type       = ZONE_SUPPORT_MAJOR;
      z.active = true; z.valid = true;
      z.score = sel.bestDemand.score;
      z.strength = sel.bestDemand.score;
   }

   double distATR = (price > z.upperBound) ? (price - z.upperBound) / atr
                  : (price < z.lowerBound) ? (z.lowerBound - price) / atr : 0.0;

   Print("[BEST_RANGE_BOUNDARIES] side=BUY supportIdx=", supIdx,
         " swing=", swingBasedBuy,
         " score=", DoubleToString(sel.bestDemand.score, 2),
         " distATR=", DoubleToString(distATR, 2));

   // Allow provisional visual D1 support boundaries
   if(swingBasedBuy)
   {
      Print("[RANGE_BOUNDARY_VISUAL] side=BUY provisional_support=true");
   }

   // Price must be genuinely interacting with the chosen support band now
   bool buyInteractionNow =
      (price >= z.lowerBound - atr * 0.15 &&
       price <= z.upperBound + atr * 0.20);

   if(!buyInteractionNow)
   {
      out.reason = "price not actively interacting with support zone";
      Print("[RANGE_BOUNDARY_REJECT] side=BUY reason=not_interacting_now price=", DoubleToString(price, _Digits));
      return out;
   }

   if(distATR > 1.25)
   {
      out.reason = StringFormat("strongest support too far distATR=%.2f", distATR);
      Print("[RANGE_BOUNDARY_REJECT] side=BUY reason=too_far distATR=", DoubleToString(distATR, 2));
      return out;
   }

   double oppResMid = 0.0;
   bool hasOppRes = (FindNextMajorOppositeZone(true, price, atr, oppResMid) >= 0);

   double effectiveGap = 0.0;
   if(hasOppRes)
      effectiveGap = oppResMid - z.upperBound;

   bool horizontalTooClose =
      (effectiveGap > 0.0 && effectiveGap < atr * 0.90);

   if(horizontalTooClose)
   {
      out.reason = StringFormat("horizontal zones too close for BUY gapATR=%.2f", effectiveGap / atr);
      Print("[RANGE_BLOCK] side=BUY reason=horizontal_zones_too_close gapATR=", DoubleToString(effectiveGap / atr, 2));
      return out;
   }

   // H4-only range entry logic (H1 sniper removed)
   if(InpRangeNeedsDoublePattern)
   {
      if(!IsDoubleBottom(ind.lowArr, ind.highArr, ind.closeArr, ind.openArr, atr))
      {
         out.reason = "missing H4 double bottom at support";
         Print("[RANGE_REJECT] side=BUY reason=h4_double_bottom_missing");
         return out;
      }
      Print("[RANGE_ENTRY_CHECK] side=BUY boundary=SUPPORT doubleBottom=true");
   }

   // Role detector: classify current price interaction at zone (neutral zone → role from behavior)
   Print("[RANGE_ZONE] side=BUY low=", DoubleToString(z.lowerBound, _Digits),
         " high=", DoubleToString(z.upperBound, _Digits),
         " mid=", DoubleToString(z.midPoint, _Digits));

   string roleLabel = "";
   RANGE_ZONE_ROLE role = DetectRangeZoneRole(ind, z.lowerBound, z.upperBound,
                                              atr, UseSweepEntry, roleLabel);

   // ROLE LOCK with FALLBACK for BUY:
   // - RESISTANCE role => hard reject (zone acting opposite)
   // - SUPPORT role => pass normally
   // - NONE role => allow fallback if conditions met
   bool rolePass = false;
   bool fallbackRolePass = false;
   string fallbackReason = "";

   if(role == RANGE_ROLE_SUPPLY)
   {
      out.reason = "zone acting as resistance — opposite role for BUY";
      Print("[RANGE_ROLE] side=BUY rejected_opposite_role=RESISTANCE");
      return out;
   }
   else if(role == RANGE_ROLE_DEMAND)
   {
      rolePass = true;
      Print("[RANGE_ROLE] side=BUY role=SUPPORT pass=normal");
   }
   else
   {
      out.reason = "zone role ambiguous — fallback disabled";
      Print("[RANGE_ROLE] side=BUY role=NONE fallback_disabled");
      return out;
   }

   // Map role trigger to interaction type for BuildDecisionFromSpecificZone
   ENUM_ZONE_INTERACTION interaction =
      (StringFind(roleLabel, "SWEEP") >= 0) ? ZONE_INTERACTION_SWEEP_RECLAIM : ZONE_INTERACTION_REJECTION;

   // REJECTION WICK FILTER: Block if candle has bearish rejection wick (bad for buy)
   // Note: already checked in fallback path, but re-check for normal SUPPORT role path
   if(HasRejectionWickAgainstTrade(ind, true))
   {
      out.reason = "bearish rejection wick detected - not safe for buy";
      Print("[RANGE_BOUNDARY_REJECT] side=BUY idx=", supIdx,
            " zone=", ZoneTypeToString(z.type),
            " reason=rejection_wick");
      return out;
   }

   // MULTI-WICK FILTER: Block if 2+ rejection wicks at zone (zone being tested, may break)
   if(HasMultipleRejectionWicksAtZone(ind, true, 5))
   {
      out.reason = "multiple rejection wicks at support - zone may break";
      Print("[RANGE_BOUNDARY_REJECT] side=BUY idx=", supIdx,
            " zone=", ZoneTypeToString(z.type),
            " reason=multi_wick_rejection");
      return out;
   }

   Print("[RANGE_TRIGGER] side=BUY trigger=", roleLabel,
         " idx=", supIdx, " boundary=support");

   if(swingBasedBuy)
      out = BuildRangeEntryFromBoundary(true, sel.bestDemand, sel.bestSupply, ind, prof, stopMult, rr);
   else
      out = BuildDecisionFromSpecificZone(true, supIdx, interaction, ind, prof, stopMult, rr, TRADE_MODE_RANGE);

   if(out.valid)
   {
      out.reason = StringFormat("RANGE BUY | role=support | trigger=%s | idx=%d | swing=%d",
                                roleLabel, supIdx, (int)swingBasedBuy);
      Print("[RANGE_DECISION] side=BUY idx=", supIdx, " swing=", swingBasedBuy,
            " role=support trigger=", roleLabel);
   }

   return out;
}

//+------------------------------------------------------------------+
//| ShouldOpenSell — STRUCTURE-FIRST CLUSTER ARCHITECTURE            |
//| Requires: bearish structure or bear bias                         |
//| Indicators confirm quality, do NOT create direction              |
//+------------------------------------------------------------------+
EntryDecision ShouldOpenSell(const IndicatorState &ind,
                              const SymbolProfile  &prof,
                              double adxMin,      double adxTrend,
                              double adxRange,    double zoneTolMult,
                              double stopMult,    double rr,
                              int    slopeLB = 3)
{
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = false;

   if(!IsTrendSellContextClean())
   {
      out.reason = "sell blocked: D1/H4 trend context not clean enough";
      Print("[TREND_CONTEXT_BLOCK] side=SELL d1=", D1BiasToString(GetD1Bias()),
            " state=", StructureStateToString(g_structure.state),
            " transition=", g_structure.rangeLikelyTransition,
            " dirValid=", (g_structure.channel.valid ? g_structure.channel.directionalValid : true),
            " LH=", g_structure.consecutiveLH, " LL=", g_structure.consecutiveLL);
      return out;
   }

   // --- STEP 1: STRUCTURE-FIRST CHECK ---
   // Require bearish structure (LL+LH) or bear bias from market structure
   // Indicators alone cannot create bear trend direction
   bool hasBearishStructure = (g_structure.consecutiveLH >= 1 && g_structure.consecutiveLL >= 1);
   bool hasBearBias = (g_structure.state == STRUCTURE_BEAR_TREND || 
                       g_structure.state == STRUCTURE_BIAS_BEAR);
   
   // BLOCK: Do not allow indicator-only trends
   // EMA50 < EMA200 + ADX high but no LL/LH sequence => reject
   double ema50 = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   double adxNow = GetADX(ind, 1);
   double atr   = GetATR(ind, 1);
   double price = ind.closeArr[1];
   if(atr <= 0.0) { out.reason = "ATR<=0"; return out; }

   // D1 ZONE PERMISSION - Soft guidance only, no hard block
   {
      double d1ResMid = GetNearestD1Supply(price);
      bool insideD1Zone = (d1ResMid > 0.0 && MathAbs(price - d1ResMid) <= atr * 1.8);

      if(insideD1Zone)
      {
         Print("[D1_ZONE_CONFIRM] side=SELL d1Resistance=", DoubleToString(d1ResMid, _Digits),
               " price=", DoubleToString(price, _Digits),
               " distATR=", DoubleToString(MathAbs(price - d1ResMid) / atr, 2));
      }
      else
      {
         Print("[D1_ZONE_SOFT] side=SELL no_hard_block d1Resistance=", DoubleToString(d1ResMid, _Digits),
               " price=", DoubleToString(price, _Digits));
      }
   }
   bool emaOnlyBear = (ema50 < ema200 && adxNow >= adxTrend && !hasBearishStructure && !hasBearBias);
   
   if(emaOnlyBear)
   {
      out.reason = "BLOCKED: EMA/ADX alone cannot create bear trend without LL/LH structure";
      Print("[INDICATOR_ONLY_BLOCK] side=SELL reason=no_structure ema50<ema200=true adx=", 
            DoubleToString(adxNow, 1), " LH=", g_structure.consecutiveLH, " LL=", g_structure.consecutiveLL);
      return out;
   }
   
   MARKET_REGIME regime = GetRegimeFromMarketStructure();
   if(regime == REGIME_NONE)
   {
      regime = ClassifyMarketRegime(ind, slopeLB, 14, adxTrend, adxRange, false);
      Print("[REGIME_SOURCE] fallback_classifier regime=", EnumToString(regime));
   }
   else
      Print("[REGIME_SOURCE] market_structure regime=", EnumToString(regime),
            " state=", StructureStateToString(g_structure.state),
            " LH=", g_structure.consecutiveLH, " LL=", g_structure.consecutiveLL);

   if(regime != REGIME_TREND_BEAR)
   {
      out.reason = "regime is not bear trend";
      return out;
   }

   // --- STEP 2: Quality gates (indicators CONFIRM, not DECIDE) ---

   // ADX filter - but allow weak ADX if structure is strong
   if(adxNow < adxMin && !hasBearishStructure)
   {
      out.reason = StringFormat("ADX too low %.1f < %.1f and no strong structure", adxNow, adxMin);
      return out;
   }
   // Phase 6: Overstretched check moved after cluster selection (see below)

   // --- STEP 3: Break-retest continuation (priority 1) ---
   double pullbackSL = 0.0, pullbackTP = 0.0;
   if(g_breakout.valid && IsBearishPullbackEntryAllowed(ind, price, atr, pullbackSL, pullbackTP))
   {
      double risk   = pullbackSL - price;
      double reward = price - pullbackTP;
      double projRR = (risk > 0.0) ? reward / risk : 0.0;
      if(projRR >= 1.0)
      {
         double ema200Adj = GetEMA200RankAdjustment(ind, false);
         out.valid          = true;
         out.isBuy          = false;
         out.mode           = TRADE_MODE_BEAR_TREND;
         out.zoneIdx        = -1;
         out.stopLoss       = NormalizeDouble(pullbackSL, prof.digits);
         out.takeProfit     = NormalizeDouble(pullbackTP, prof.digits);
         out.projectedRR    = projRR;
         out.usedZoneTarget = true;
         out.rankScore      = projRR + 1.25 + ema200Adj;
         out.reason         = StringFormat("PULLBACK SELL | SL=%.5f | TP=%.5f | RR=%.2f",
                                           pullbackSL, pullbackTP, projRR);
         return out;
      }
   }

   // --- STEP 4: Build bear trend cluster (single trend boundary) ---
   TrendCluster cluster = BuildBearTrendCluster(ind, atr);
   if(!cluster.valid)
   {
      out.reason = "no valid bear trend cluster (no trend boundary resistance)";
      Print("[TREND_CLUSTER] side=SELL result=no_cluster");
      return out;
   }
   Print("[TREND_CLUSTER] side=SELL type=", cluster.label,
         " mid=", DoubleToString(cluster.mid, prof.digits),
         " score=", DoubleToString(cluster.baseScore, 2));

   // Pullback-quality veto: reject shallow or deep pullbacks
   double pullbackDepth = MathMax(ind.highArr[1], ind.highArr[2]) - cluster.low;
   if(pullbackDepth < atr * 0.20)
   {
      out.reason = "bear trend pullback too shallow";
      return out;
   }

   if(pullbackDepth > atr * 1.80)
   {
      out.reason = "bear trend pullback too deep";
      return out;
   }

   // Phase 6: Overstretched check AFTER cluster found, with near-boundary exception
   bool nearBoundary = (cluster.mid > 0.0 && MathAbs(price - cluster.mid) <= atr * 0.75);
   if(IsOverstretchedSell(ind, 3.50) && !nearBoundary)
   {
      out.reason = "sell overstretched away from boundary";
      Print("[OVERSTRETCHED] side=SELL nearBoundary=false price_to_cluster=", 
            DoubleToString(MathAbs(price - cluster.mid) / atr, 2), "ATR");
      return out;
   }

   // --- STEP 5: Require confirmation at cluster ---
   double stopAnchor   = 0.0;
   double scoreBoost   = 0.0;
   string triggerLabel = "";
   if(!ConfirmBearTrendClusterEntry(ind, cluster, atr, UseSweepEntry,
                                    stopAnchor, scoreBoost, triggerLabel))
   {
      out.reason = "no confirmation at bear cluster (no sweep/rejection/engulfing/continuation)";
      Print("[TREND_CLUSTER_REJECT] side=SELL reason=no_confirmation_at_selected_boundary cluster=", cluster.label);
      // MOMENTUM_CONTINUATION no longer creates standalone entries — requires valid zone interaction
      return out;
   }
   Print("[TREND_TRIGGER] side=SELL trigger=", triggerLabel,
         " cluster=", cluster.label,
         " boost=", DoubleToString(scoreBoost, 2));

   // Patch 5: Reject if price has chased too far from the selected cluster
   double maxChaseDistATR = (StringFind(_Symbol, "GBPUSD") >= 0) ? 0.55 : 0.35;
   if(atr > 0.0 && MathAbs(price - cluster.mid) / atr > maxChaseDistATR)
   {
      out.reason = "sell trigger confirmed but entry too far from selected cluster";
      Print("[TREND_CLUSTER_REJECT] side=SELL reason=entry_chased_cluster dist_atr=",
            DoubleToString(MathAbs(price - cluster.mid) / atr, 2));
      return out;
   }

   // --- STEP 6: Build ONE sell decision ---
   double sl     = 0.0;
   double tp     = 0.0;
   double oppMid = 0.0;
   double projRR = 0.0;
   double risk   = 0.0;
   double reward = 0.0;

   bool usedMajorOppSell   = false;
   bool usedDynamicOppSell = false;

   // Zone-first target logic only.
   // Channels are visual/context only and must not provide entries or TP.
   double wickHigh = GetRecentSetupWickHigh(ind, 5);
   double stopBufferATR = (StringFind(_Symbol, "GBPUSD") >= 0 ? 0.45 : 0.30);
   sl = BuildBufferedSellStop(MathMax(cluster.high, stopAnchor), wickHigh, atr, stopBufferATR, prof.digits);

   if(FindNextMajorOppositeZone(false, price, atr, oppMid) >= 0 && oppMid < price - atr * 0.30)
   {
      tp = NormalizeDouble(oppMid + atr * 0.15, prof.digits);
      usedMajorOppSell = true;
   }
   else
   {
      tp = NormalizeDouble(price - (sl - price) * MathMax(1.20, rr * 0.75), prof.digits);
   }

   risk   = sl - price;
   reward = price - tp;
   projRR = (risk > 0.0) ? reward / risk : 0.0;

   bool isBiasStateSell = (g_structure.valid && g_structure.state == STRUCTURE_BIAS_BEAR);
   bool diagContinuationSell = cluster.fromDynamicChannel;
   bool channelToChannelTradeSell = false;
   bool runnerStyleSell = (g_trendTradesUseNoFixedTP &&
                           !channelToChannelTradeSell &&
                           (cluster.fromDynamicChannel || triggerLabel == "CONTINUATION" || triggerLabel == "CONTINUATION_STRONG"));

   double minRRSell = isBiasStateSell ? 0.75 : 1.0;
   if(!isBiasStateSell && triggerLabel == "CONTINUATION")
      minRRSell = 1.10;

   if(diagContinuationSell)
      minRRSell = isBiasStateSell ? 0.60 : 0.50;

   if(runnerStyleSell && !usedMajorOppSell)
      minRRSell = MathMin(minRRSell, isBiasStateSell ? 0.55 : 0.45);

   if(risk <= 0.0 || projRR < minRRSell)
   {
      out.reason = StringFormat("cluster SELL RR too low %.2f (min=%.2f%s)",
                                projRR, minRRSell, isBiasStateSell ? " bias" : "");
      Print("[TREND_CLUSTER_REJECT] side=SELL reason=rr_too_low projRR=",
            DoubleToString(projRR, 2), " minRR=", DoubleToString(minRRSell, 2));
      return out;
   }

   if(runnerStyleSell && !usedMajorOppSell)
   {
      Print("[TREND_CLUSTER_RR_OVERRIDE] side=SELL runner=true usedDynamicOpp=", usedDynamicOppSell,
            " projRR=", DoubleToString(projRR, 2),
            " minRR=", DoubleToString(minRRSell, 2));
   }

   double ema200Adj = GetEMA200RankAdjustment(ind, false);

   out.valid          = true;
   out.isBuy          = false;
   out.mode           = TRADE_MODE_BEAR_TREND;
   out.zoneIdx        = -1;
   out.stopLoss       = sl;
   out.takeProfit     = tp;
   out.projectedRR    = projRR;
   out.usedZoneTarget = (oppMid > 0.0);

   // Dynamic channel confluence disabled (channel code removed)
   double chanBonusSell = 0.0;
   bool   nearChanRes   = false; // Channel code removed
   if(nearChanRes) chanBonusSell = 0.15;
   Print("[DYNAMIC_CHANNEL] sell_confluence=", nearChanRes,
         " bonus=", DoubleToString(chanBonusSell, 2));

   out.rankScore      = projRR + cluster.baseScore + scoreBoost + ema200Adj + chanBonusSell;
   out.reason         = StringFormat(
      "TREND CLUSTER SELL | trigger=%s | path=%s | cluster=%s | SL=%.5f | TP=%.5f | RR=%.2f",
      triggerLabel,
      "STANDARD",
      cluster.label, sl, tp, projRR);
   return out;
}

//+------------------------------------------------------------------+
//| ShouldOpenSellRange — armed local edge setup path                |
//+------------------------------------------------------------------+
EntryDecision ShouldOpenSellRange(const IndicatorState &ind,
                                   const SymbolProfile  &prof,
                                   double adxMin,      double adxTrend,
                                   double adxRange,    double zoneTolMult,
                                   double stopMult,    double rr,
                                   int    slopeLB = 3)
{
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = false;
   out.mode  = TRADE_MODE_RANGE;

   // PRIMARY: Use market structure as regime source
   // FALLBACK: Only use classifier if structure is invalid
   MARKET_REGIME regime = GetRegimeFromMarketStructure();
   if(regime == REGIME_NONE)
   {
      regime = ClassifyMarketRegime(ind, slopeLB, 14, adxTrend, adxRange, false);
      Print("[REGIME_SOURCE] range_sell fallback_classifier regime=", EnumToString(regime));
   }
   else
   {
      Print("[REGIME_SOURCE] range_sell market_structure regime=", EnumToString(regime),
            " state=", StructureStateToString(g_structure.state));
   }

   bool rangeContext =
      (regime == REGIME_RANGE) ||
      (g_structure.valid &&
       (g_structure.state == STRUCTURE_RANGE ||
        g_structure.state == STRUCTURE_CONSOLIDATION) &&
       g_structure.rangeQuality >= 6.0);

   if(!rangeContext)
   {
      out.reason = "regime is not range";
      return out;
   }

   if(regime != REGIME_RANGE)
      Print("[RANGE_SOFT_CONTEXT] side=SELL");

   // --- GRADED COUNTERTREND BLOCK FOR RANGE SELL (Part 4 patch) ---
   if(BlockCounterTrendTrades)
   {
      // Full BULL_TREND still hard-vetoes range sells — do not fade clean breakouts
      if(g_structure.state == STRUCTURE_BULL_TREND)
      {
         out.reason = "countertrend range sell blocked by full bull trend";
         Print("[RANGE_COUNTERTREND_BLOCK] side=SELL reason=full_bull_trend");
         return out;
      }

      double adxNow_rs  = GetADX(ind, 1);
      bool chanBullNow  = (g_structure.channel.valid && g_structure.channel.directionalValid &&
                           g_structure.channel.direction == +1);
      bool transitionRS = g_structure.rangeLikelyTransition;
      double maxChaseATR_rs = MathMax(adxRange + 5.0, 26.0);

      RangeBoundarySelection selRS = BuildFinalHorizontalRangeMap(ind, ind.closeArr[1], MathMax(GetATR(ind, 1), 0.0000001));
      bool insideBoxRS = (selRS.valid &&
                          ind.closeArr[1] >= selRS.bestDemand.mid &&
                          ind.closeArr[1] <= selRS.bestSupply.mid);

      bool gradedVetoRS = (g_structure.state == STRUCTURE_BIAS_BULL || chanBullNow) &&
                           adxNow_rs > maxChaseATR_rs &&
                           chanBullNow && transitionRS && !insideBoxRS;

      Print("[RANGE_ENTRY_GATE] side=SELL blocked=", gradedVetoRS,
            " adx=", DoubleToString(adxNow_rs, 1),
            " chanBull=", chanBullNow,
            " transition=", transitionRS,
            " insideBox=", insideBoxRS);

      if(gradedVetoRS)
      {
         out.reason = "range sell: graded veto (ADX+channel+transition+outside_box)";
         Print("[RANGE_COUNTERTREND_BLOCK] side=SELL reason=graded_veto adx=", DoubleToString(adxNow_rs,1));
         return out;
      }
   }

   Print("[DYNAMIC_CHANNEL] ignored_for_range=true side=SELL");

   double atr   = GetATR(ind, 1);
   double price = ind.closeArr[1];
   if(atr <= 0.0)
   {
      out.reason = "ATR<=0";
      return out;
   }

   // RANGE ADX LOGIC: No minimum floor - range entries should NOT require ADX minimum.
   // Instead, reject only when trend strength is VERY HIGH AND rising sharply.
   double adxNow  = GetADX(ind, 1);
   double adxPrev = GetADX(ind, 2);
   // RELAXED: Only reject if ADX >= 35 (strong trend) AND rising >= 4.0 (sharply increasing)
   if(adxNow >= 35.0 && (adxNow - adxPrev) >= 4.0)
   {
      out.reason = StringFormat("trend-strength too high for range ADX=%.1f rising=%.1f", adxNow, adxNow - adxPrev);
      Print("[RANGE_ADX] side=SELL adxNow=", DoubleToString(adxNow, 1),
            " adxPrev=", DoubleToString(adxPrev, 1), " pass=false (strong trend)");
      return out;
   }
   Print("[RANGE_ADX] side=SELL adxNow=", DoubleToString(adxNow, 1),
         " adxPrev=", DoubleToString(adxPrev, 1), " pass=true");

   // Select STRONGEST OUTER MAJOR resistance boundary — score-first, not nearest.
   RangeBoundarySelection sel = BuildFinalHorizontalRangeMap(ind, price, atr);

   if(!sel.valid || !sel.bestSupply.valid)
   {
      out.reason = StringFormat("no horizontal resistance boundary found: %s", sel.reason);
      Print("[RANGE_REJECT] side=SELL reason=no_horizontal_boundary detail=", sel.reason);
      return out;
   }


   // HARD SIDE LOCK: resistance boundary must be truly resistance — no exceptions
   if(sel.bestSupply.isDemand)
   {
      out.reason = "boundary is not resistance — SELL side lock rejected";
      Print("[RANGE_SIDE_LOCK] side=SELL rejected_non_resistance_boundary idx=", sel.bestSupply.zoneIdx);
      return out;
   }
   Print("[RANGE_SIDE_LOCK] side=SELL resistance_idx=", sel.bestSupply.zoneIdx,
         " isDemand=", sel.bestSupply.isDemand);

   // TIGHT CONSOLIDATION CHECK: Reject if range is too narrow for safe trading
   if(sel.bestDemand.valid && sel.bestSupply.valid)
   {
      if(IsTightConsolidation(ind, sel.bestDemand.mid, sel.bestSupply.mid))
      {
         out.reason = "tight consolidation - range too narrow";
         Print("[RANGE_REJECT] side=SELL reason=tight_consolidation widthATR=",
               DoubleToString((sel.bestSupply.mid - sel.bestDemand.mid) / atr, 2));
         return out;
      }

      double widthATR_now = (sel.bestSupply.mid - sel.bestDemand.mid) / atr;
      double adxNow_now   = GetADX(ind, 1);
      double emaSpreadNow = MathAbs(GetEMA50(ind, 1) - GetEMA200(ind, 1));
      double emaSpreadATR_now = (atr > 0.0) ? emaSpreadNow / atr : 999.0;

      bool hardConsolBlock =
         (widthATR_now <= 3.00 &&
          adxNow_now <= 22.0 &&
          emaSpreadATR_now <= 1.10);

      if(hardConsolBlock)
      {
         out.reason = "hard consolidation block";
         Print("[RANGE_REJECT] side=SELL reason=hard_consolidation widthATR=",
               DoubleToString(widthATR_now, 2),
               " adx=", DoubleToString(adxNow_now, 1),
               " emaSpreadATR=", DoubleToString(emaSpreadATR_now, 2));
         return out;
      }
   }

   bool messyMap = IsRangeBoundaryMapMessy(sel, ind);
   if(messyMap)
   {
      out.reason = "messy range boundary map";
      Print("[RANGE_BOUNDARY_REJECT] side=SELL reason=messy_map");
      return out;
   }

   int resIdx = sel.bestSupply.zoneIdx;
   bool swingBasedSell = (resIdx < 0);

   ZoneInfo z;
   if(!swingBasedSell)
      z = g_zoneReg.zones[resIdx];
   else
   {
      ZeroMemory(z);
      z.lowerBound = sel.bestSupply.lowerBound;
      z.upperBound = sel.bestSupply.upperBound;
      z.midPoint   = sel.bestSupply.mid;
      z.type       = ZONE_RESISTANCE_MAJOR;
      z.active = true; z.valid = true;
      z.score = sel.bestSupply.score;
      z.strength = sel.bestSupply.score;
   }

   double distATR = (price < z.lowerBound) ? (z.lowerBound - price) / atr
                  : (price > z.upperBound) ? (price - z.upperBound) / atr : 0.0;

   Print("[BEST_RANGE_BOUNDARIES] side=SELL resistanceIdx=", resIdx,
         " swing=", swingBasedSell,
         " score=", DoubleToString(sel.bestSupply.score, 2),
         " distATR=", DoubleToString(distATR, 2));

   // Allow provisional visual D1 resistance boundaries
   if(swingBasedSell)
   {
      Print("[RANGE_BOUNDARY_VISUAL] side=SELL provisional_resistance=true");
   }

   // Price must be genuinely interacting with the chosen resistance band now
   bool sellInteractionNow =
      (price >= z.lowerBound - atr * 0.20 &&
       price <= z.upperBound + atr * 0.15);

   if(!sellInteractionNow)
   {
      out.reason = "price not actively interacting with resistance zone";
      Print("[RANGE_BOUNDARY_REJECT] side=SELL reason=not_interacting_now price=", DoubleToString(price, _Digits));
      return out;
   }

   if(distATR > 1.25)
   {
      out.reason = StringFormat("strongest resistance too far distATR=%.2f", distATR);
      Print("[RANGE_BOUNDARY_REJECT] side=SELL reason=too_far distATR=", DoubleToString(distATR, 2));
      return out;
   }

   double oppSupMid = 0.0;
   bool hasOppSup = (FindNextMajorOppositeZone(false, price, atr, oppSupMid) >= 0);

   double effectiveGap = 0.0;
   if(hasOppSup)
      effectiveGap = z.lowerBound - oppSupMid;

   bool horizontalTooClose =
      (effectiveGap > 0.0 && effectiveGap < atr * 0.90);

   if(horizontalTooClose)
   {
      out.reason = StringFormat("horizontal zones too close for SELL gapATR=%.2f", effectiveGap / atr);
      Print("[RANGE_BLOCK] side=SELL reason=horizontal_zones_too_close gapATR=", DoubleToString(effectiveGap / atr, 2));
      return out;
   }

   // H4-only range entry logic (H1 sniper removed)
   if(InpRangeNeedsDoublePattern)
   {
      if(!IsDoubleTop(ind.highArr, ind.lowArr, ind.closeArr, ind.openArr, atr))
      {
         out.reason = "missing H4 double top at resistance";
         Print("[RANGE_REJECT] side=SELL reason=h4_double_top_missing");
         return out;
      }
      Print("[RANGE_ENTRY_CHECK] side=SELL boundary=RESISTANCE doubleTop=true");
   }

   // Role detector: classify current price interaction at zone (neutral zone → role from behavior)
   Print("[RANGE_ZONE] side=SELL low=", DoubleToString(z.lowerBound, _Digits),
         " high=", DoubleToString(z.upperBound, _Digits),
         " mid=", DoubleToString(z.midPoint, _Digits));

   string roleLabel = "";
   RANGE_ZONE_ROLE role = DetectRangeZoneRole(ind, z.lowerBound, z.upperBound,
                                              atr, UseSweepEntry, roleLabel);

   // ROLE LOCK with FALLBACK for SELL:
   // - SUPPORT role => hard reject (zone acting opposite)
   // - RESISTANCE role => pass normally
   // - NONE role => allow fallback if conditions met
   bool rolePass = false;
   bool fallbackRolePass = false;
   string fallbackReason = "";

   if(role == RANGE_ROLE_DEMAND)
   {
      out.reason = "zone acting as support — opposite role for SELL";
      Print("[RANGE_ROLE] side=SELL rejected_opposite_role=SUPPORT");
      return out;
   }
   else if(role == RANGE_ROLE_SUPPLY)
   {
      rolePass = true;
      Print("[RANGE_ROLE] side=SELL role=RESISTANCE pass=normal");
   }
   else
   {
      out.reason = "zone role ambiguous — fallback disabled";
      Print("[RANGE_ROLE] side=SELL role=NONE fallback_disabled");
      return out;
   }

   // Map role trigger to interaction type for BuildDecisionFromSpecificZone
   ENUM_ZONE_INTERACTION interaction =
      (StringFind(roleLabel, "SWEEP") >= 0) ? ZONE_INTERACTION_SWEEP_RECLAIM : ZONE_INTERACTION_REJECTION;

   // REJECTION WICK FILTER: Block if candle has bullish rejection wick (bad for sell)
   // Note: already checked in fallback path, but re-check for normal RESISTANCE role path
   if(HasRejectionWickAgainstTrade(ind, false))
   {
      out.reason = "bullish rejection wick detected - not safe for sell";
      Print("[RANGE_BOUNDARY_REJECT] side=SELL idx=", resIdx,
            " zone=", ZoneTypeToString(z.type),
            " reason=rejection_wick");
      return out;
   }

   // MULTI-WICK FILTER: Block if 2+ rejection wicks at zone (zone being tested, may break)
   if(HasMultipleRejectionWicksAtZone(ind, false, 5))
   {
      out.reason = "multiple rejection wicks at resistance - zone may break";
      Print("[RANGE_BOUNDARY_REJECT] side=SELL idx=", resIdx,
            " zone=", ZoneTypeToString(z.type),
            " reason=multi_wick_rejection");
      return out;
   }

   Print("[RANGE_TRIGGER] side=SELL trigger=", roleLabel,
         " idx=", resIdx, " boundary=resistance");

   if(swingBasedSell)
      out = BuildRangeEntryFromBoundary(false, sel.bestSupply, sel.bestDemand, ind, prof, stopMult, rr);
   else
      out = BuildDecisionFromSpecificZone(false, resIdx, interaction, ind, prof, stopMult, rr, TRADE_MODE_RANGE);

   if(out.valid)
   {
      out.reason = StringFormat("RANGE SELL | role=resistance | trigger=%s | idx=%d",
                                roleLabel, resIdx);
      Print("[RANGE_DECISION] side=SELL idx=", resIdx,
            " type=", ZoneTypeToString(z.type),
            " role=resistance trigger=", roleLabel);
   }

   return out;
}

//+==================================================================+
//| SECTION 7: BREAKOUT & REVERSAL SIGNALS                          |
//| Breakout buy/sell, reversal buy/sell, range boundary wrapper     |
//+==================================================================+

//+------------------------------------------------------------------+
//| Generate Breakout Buy Signal                                     |
//+------------------------------------------------------------------+
EntryDecision GenerateBreakoutBuySignal(const IndicatorState &ind,
                                        const SymbolProfile &prof,
                                        double stopMult, double rr)
{
   // ENTRY LOGIC DISABLED - All entry decision functions disabled
   // Bot will compile but will not open any trades
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = true;
   out.reason = "ENTRY_LOGIC_DISABLED";
   return out;
}

//+------------------------------------------------------------------+
//| Generate Breakout Sell Signal                                    |
//+------------------------------------------------------------------+
EntryDecision GenerateBreakoutSellSignal(const IndicatorState &ind,
                                         const SymbolProfile &prof,
                                         double stopMult, double rr)
{
   // ENTRY LOGIC DISABLED - All entry decision functions disabled
   // Bot will compile but will not open any trades
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = false;
   out.reason = "ENTRY_LOGIC_DISABLED";
   return out;
}

//+------------------------------------------------------------------+
//| Generate Reversal Buy Signal                                     |
//+------------------------------------------------------------------+
EntryDecision GenerateReversalBuySignal(const IndicatorState &ind,
                                        const SymbolProfile &prof,
                                        double stopMult, double rr)
{
   // ENTRY LOGIC DISABLED - All entry decision functions disabled
   // Bot will compile but will not open any trades
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = true;
   out.reason = "ENTRY_LOGIC_DISABLED";
   return out;
}

//+------------------------------------------------------------------+
//| Generate Reversal Sell Signal                                    |
//+------------------------------------------------------------------+
EntryDecision GenerateReversalSellSignal(const IndicatorState &ind,
                                         const SymbolProfile &prof,
                                         double stopMult, double rr)
{
   // ENTRY LOGIC DISABLED - All entry decision functions disabled
   // Bot will compile but will not open any trades
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = false;
   out.reason = "ENTRY_LOGIC_DISABLED";
   return out;
}

//+------------------------------------------------------------------+
//| Generate Range Boundary Entries - Wrapper for range signals     |
//+------------------------------------------------------------------+
EntryDecision GenerateRangeBoundaryEntries(const IndicatorState &ind,
                                          const SymbolProfile &prof,
                                          double adxMin, double adxTrend, double adxRange,
                                          double zoneTolMult, double stopMult, double rr,
                                          int slopeLB = 3)
{
   EntryDecision out = MakeEmptyDecision();

   // Try both sides
   EntryDecision buyRange  = ShouldOpenBuyRange(ind, prof, adxMin, adxTrend, adxRange,
                                                 zoneTolMult, stopMult, rr, slopeLB);
   EntryDecision sellRange = ShouldOpenSellRange(ind, prof, adxMin, adxTrend, adxRange,
                                                  zoneTolMult, stopMult, rr, slopeLB);

   Print("[RANGE_BOUNDARY_WRAPPER] buyValid=", buyRange.valid,
         " buyReason=", buyRange.reason,
         " sellValid=", sellRange.valid,
         " sellReason=", sellRange.reason);

   // Pick the best valid result (higher rankScore wins)
   if(buyRange.valid && sellRange.valid)
   {
      out = (buyRange.rankScore >= sellRange.rankScore) ? buyRange : sellRange;
      Print("[RANGE_BOUNDARY_PICK] both_valid winner=", (out.isBuy ? "BUY" : "SELL"),
            " buyRank=", DoubleToString(buyRange.rankScore, 2),
            " sellRank=", DoubleToString(sellRange.rankScore, 2));
   }
   else if(buyRange.valid)
      out = buyRange;
   else if(sellRange.valid)
      out = sellRange;

   // Fallback: if no boundary entry, try structural zone-based entry
   if(!out.valid)
   {
      double atr   = GetATR(ind, 1);
      double price = ind.closeArr[1];
      if(atr > 0.0)
      {
         // Scan registry for nearest execution-eligible demand below / supply above
         int bestDemIdx = -1, bestSupIdx = -1;
         double bestDemDist = DBL_MAX, bestSupDist = DBL_MAX;

         for(int i = 0; i < g_zoneReg.count; i++)
         {
            ZoneInfo z = g_zoneReg.zones[i];
            // Patch 13: include backup zones in fallback scan even if not visually active
            bool zoneAlive = z.active || (InpSDKeepBackupZonesInMemory && z.isBackup);
            if(!zoneAlive || z.historical || z.broken) continue;
            if(!z.isExecutionEligible) continue;  // only execution candidates

            bool isDemandType = (z.type == ZONE_DEMAND || z.type == ZONE_DEMAND_MAJOR ||
                                 z.type == ZONE_DEMAND_MINOR || z.type == ZONE_SUPPORT_MAJOR ||
                                 z.type == ZONE_SUPPORT_MINOR);
            bool isSupplyType = (z.type == ZONE_SUPPLY || z.type == ZONE_SUPPLY_MAJOR ||
                                 z.type == ZONE_SUPPLY_MINOR || z.type == ZONE_RESISTANCE_MAJOR ||
                                 z.type == ZONE_RESISTANCE_MINOR);

            if(isDemandType && z.midPoint < price)
            {
               double d = price - z.midPoint;
               if(d < bestDemDist) { bestDemDist = d; bestDemIdx = i; }
            }
            if(isSupplyType && z.midPoint > price)
            {
               double d = z.midPoint - price;
               if(d < bestSupDist) { bestSupDist = d; bestSupIdx = i; }
            }
         }

         // Try building entry from nearest zone if price is interacting
         if(bestDemIdx >= 0 && bestDemDist <= atr * 0.50)
         {
            out = BuildDecisionFromSpecificZone(true, bestDemIdx,
                     ZONE_INTERACTION_REJECTION, ind, prof, stopMult, rr, TRADE_MODE_RANGE);
            if(out.valid)
            {
               out.reason += " | RANGE_SD_FALLBACK_BUY";
               Print("[RANGE_SD_FALLBACK] side=BUY zoneIdx=", bestDemIdx,
                     " distATR=", DoubleToString(bestDemDist / atr, 2));
            }
         }

         if(!out.valid && bestSupIdx >= 0 && bestSupDist <= atr * 0.50)
         {
            out = BuildDecisionFromSpecificZone(false, bestSupIdx,
                     ZONE_INTERACTION_REJECTION, ind, prof, stopMult, rr, TRADE_MODE_RANGE);
            if(out.valid)
            {
               out.reason += " | RANGE_SD_FALLBACK_SELL";
               Print("[RANGE_SD_FALLBACK] side=SELL zoneIdx=", bestSupIdx,
                     " distATR=", DoubleToString(bestSupDist / atr, 2));
            }
         }

         if(!out.valid)
         {
            out.reason = StringFormat("range: no boundary entry and no nearby S/D fallback | buy=%s | sell=%s",
                                       buyRange.reason, sellRange.reason);
         }
      }
      else
         out.reason = "range: ATR<=0";
   }

   return out;
}

//+------------------------------------------------------------------+
//| Generate Counter-Trend Decision                                   |
//+------------------------------------------------------------------+
EntryDecision GenerateCounterTrendDecision(const IndicatorState &ind,
                                          const SymbolProfile &prof,
                                          bool isBuy)
{
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = isBuy;
   out.mode = TRADE_MODE_REVERSAL;
   out.reason = "counter_trend_not_implemented";
   return out;
}

// TREND LINE CODE REMOVED - All trend line functions deleted per user request

bool IsNearContinuationZone(bool isBull, double price, double atr, ZoneInfo &outZone, int &outIdx)
{
   if(!InpUseHorizontalTrendZones)
      return false;

   outIdx = -1;
   double bestScore = -DBL_MAX;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];

      if(!z.valid || !z.active || z.historical || z.broken)
         continue;

      if(InpUseSupplyDemandZones && InpSDTradeOnlyActivePair && !SDIsActiveTradingZone(z))
         continue;

      if(!PassesZoneStrengthMode(z, InpTradeZoneStrengthMode))
         continue;

      ZONE_CANONICAL_ROLE role = ResolveZoneRole(z, price, atr);

      bool directionOk = false;
      if(isBull)
      {
         directionOk =
            (role == ZROLE_SUPPORT) ||
            (z.structuralTag == "HL") ||
            (z.structuralTag == "HH") ||
            (z.strategyRole == ZROLE_TREND_CONTINUATION) ||
            (z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_SUPPORT_MINOR || z.type == ZONE_DEMAND) ||
            (z.isFlipZone && z.originalType == ZONE_RESISTANCE_MAJOR);
      }
      else
      {
         directionOk =
            (role == ZROLE_RESISTANCE) ||
            (z.structuralTag == "LH") ||
            (z.structuralTag == "LL") ||
            (z.strategyRole == ZROLE_TREND_CONTINUATION) ||
            (z.type == ZONE_RESISTANCE_MAJOR || z.type == ZONE_RESISTANCE_MINOR || z.type == ZONE_SUPPLY) ||
            (z.isFlipZone && z.originalType == ZONE_SUPPORT_MAJOR);
      }

      if(!directionOk)
         continue;

      double distATR = MathAbs(z.midPoint - price) / atr;
      double maxTrendDistATR = 4.50;
      if(distATR > maxTrendDistATR)
         continue;

      double score = 0.0;
      score += z.qualityScore * 1.10;
      score += z.cleanTouchCount * 0.50;
      score += z.strength * 2.0;

      if(z.strategyRole == ZROLE_TREND_CONTINUATION) score += 1.50;
      if(z.structuralTag == "HL" || z.structuralTag == "LH") score += 1.20;
      if(z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_RESISTANCE_MAJOR) score += 1.00;
      if(z.isFlipZone) score += 0.75;

      score -= distATR * 0.30;

      if(score > bestScore)
      {
         bestScore = score;
         outZone = z;
         outIdx = i;
      }
   }

   return (outIdx >= 0);
}

//+------------------------------------------------------------------+
//| H1 Sniper Helpers - Series/ATR/Stochastic                          |
//+------------------------------------------------------------------+
bool CopyTFSeries(const string symbol, ENUM_TIMEFRAMES tf, int bars,
                  double &openArr[], double &highArr[], double &lowArr[], double &closeArr[])
{
   ArrayResize(openArr, bars);
   ArrayResize(highArr, bars);
   ArrayResize(lowArr, bars);
   ArrayResize(closeArr, bars);

   ArraySetAsSeries(openArr, true);
   ArraySetAsSeries(highArr, true);
   ArraySetAsSeries(lowArr, true);
   ArraySetAsSeries(closeArr, true);

   if(CopyOpen(symbol, tf, 0, bars, openArr) < bars) return false;
   if(CopyHigh(symbol, tf, 0, bars, highArr) < bars) return false;
   if(CopyLow(symbol, tf, 0, bars, lowArr) < bars) return false;
   if(CopyClose(symbol, tf, 0, bars, closeArr) < bars) return false;

   return true;
}

double GetATRForTF(const string symbol, ENUM_TIMEFRAMES tf, int period, int shift = 1)
{
   int h = iATR(symbol, tf, period);
   if(h == INVALID_HANDLE)
      return 0.0;

   double buf[];
   ArraySetAsSeries(buf, true);
   double out = 0.0;

   if(CopyBuffer(h, 0, shift, 2, buf) > 0)
      out = buf[0];

   IndicatorRelease(h);
   return out;
}

bool GetStochasticSnapshot(const string symbol, ENUM_TIMEFRAMES tf,
                           int kPeriod, int dPeriod, int slowing,
                           double &k1, double &d1, double &k2, double &d2)
{
   int h = iStochastic(symbol, tf, kPeriod, dPeriod, slowing, MODE_SMA, STO_LOWHIGH);
   if(h == INVALID_HANDLE)
      return false;

   double kBuf[], dBuf[];
   ArraySetAsSeries(kBuf, true);
   ArraySetAsSeries(dBuf, true);

   bool ok = (CopyBuffer(h, 0, 1, 3, kBuf) >= 2 &&
              CopyBuffer(h, 1, 1, 3, dBuf) >= 2);

   if(ok)
   {
      k1 = kBuf[0];
      d1 = dBuf[0];
      k2 = kBuf[1];
      d2 = dBuf[1];
   }

   IndicatorRelease(h);
   return ok;
}

bool IsNearPriceBand(double price, double low, double high, double atr, double tolATR)
{
   double tol = atr * tolATR;
   return (price >= low - tol && price <= high + tol);
}

//+------------------------------------------------------------------+
//| H1 Sniper functions removed - using H4-only confirmation         |
//+------------------------------------------------------------------+

bool HasTrendContinuationConfirmation(const IndicatorState &ind, bool isBull)
{
   // H4-only trend continuation confirmation (H1 sniper removed)
   double bodySize = MathAbs(ind.closeArr[1] - ind.openArr[1]);
   double candleRange = ind.highArr[1] - ind.lowArr[1];
   double bodyRatio = (candleRange > 0) ? bodySize / candleRange : 0.0;
   if(bodyRatio < 0.4)
      return false;

   return isBull ? (ind.closeArr[1] > ind.openArr[1]) : (ind.closeArr[1] < ind.openArr[1]);
}

// NOTE: H1 Sniper helpers already defined above at lines ~6583-6662
// Duplicate definitions removed to prevent compilation errors

//+------------------------------------------------------------------+
//| Fast Directional Confirmation (Wick + Pattern)                   |
//+------------------------------------------------------------------+
bool HasFastDirectionalConfirmation(bool isBull, const ZoneInfo &z, double atr)
{
   // H4-only directional confirmation (H1 sniper removed)
   ENUM_TIMEFRAMES tfExec = InpEntryTF;

   bool fast = false;

   if(isBull)
   {
      fast =
         IsBullishEngulfing(_Symbol, tfExec, 1) ||
         IsBullishPinBar(_Symbol, tfExec, 1) ||
         IsBullishWickRejection(_Symbol, tfExec, 1, 0.35, 0.45, true) ||
         IsTrendBullishContinuation(_Symbol, tfExec, 1);
   }
   else
   {
      fast =
         IsBearishEngulfing(_Symbol, tfExec, 1) ||
         IsBearishPinBar(_Symbol, tfExec, 1) ||
         IsBearishWickRejection(_Symbol, tfExec, 1, 0.35, 0.45, true) ||
         IsTrendBearishContinuation(_Symbol, tfExec, 1);
   }

   return fast;
}

//+------------------------------------------------------------------+
//| Zone Touch Distance in ATR                                       |
//+------------------------------------------------------------------+
double GetZoneTouchATRDistance(double price, const ZoneInfo &z, double atr)
{
   if(atr <= 0.0) return 999.0;
   return MathAbs(price - z.midPoint) / atr;
}

//+------------------------------------------------------------------+
//| Signal Wick Stop Reference (Multi-TF)                            |
//+------------------------------------------------------------------+
double GetSignalWickStopReference(bool isBull,
                                  bool nearZone,
                                  const ZoneInfo &z)
{
   // H4-only wick stop reference (H1 sniper removed, trendline removed)
   double h4Low  = iLow(_Symbol, InpEntryTF, 1);
   double h4High = iHigh(_Symbol, InpEntryTF, 1);

   if(isBull)
   {
      double ref = h4Low;
      if(nearZone)
         ref = MathMin(ref, z.lowerBound);
      return ref;
   }
   else
   {
      double ref = h4High;
      if(nearZone)
         ref = MathMax(ref, z.upperBound);
      return ref;
   }
}

//+==================================================================+
//| SECTION 8: TREND CONTINUATION DECISION                          |
//| Channel-to-channel + zone continuation with H4 pattern confirm  |
//+==================================================================+

//+------------------------------------------------------------------+
//| Generate Trend Continuation Decision (Enhanced)                  |
//+------------------------------------------------------------------+
EntryDecision GenerateTrendContinuationDecision(const IndicatorState &ind,
                                               const SymbolProfile &prof,
                                               bool isBull)
{
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = isBull;
   out.mode  = isBull ? TRADE_MODE_BULL_TREND : TRADE_MODE_BEAR_TREND;

   if(ArraySize(ind.openArr) < 4 ||
      ArraySize(ind.highArr) < 4 ||
      ArraySize(ind.lowArr)  < 4 ||
      ArraySize(ind.closeArr) < 4)
   {
      out.reason = "trend continuation blocked: insufficient candle data";
      return out;
   }

   double atr = GetATR(ind, 1);
   if(atr <= 0.0)
   {
      out.reason = "trend continuation blocked: ATR<=0";
      return out;
   }

   // FIRST: use the existing full trend engine.
   EntryDecision core =
      isBull
      ? ShouldOpenBuy(ind, prof, EntryADXMin, EntryADXTrend, EntryADXRange,
                      EntryZoneTolATR, EntryStopATR, RewardRisk, TrendSlopeLookback)
      : ShouldOpenSell(ind, prof, EntryADXMin, EntryADXTrend, EntryADXRange,
                       EntryZoneTolATR, EntryStopATR, RewardRisk, TrendSlopeLookback);

   if(core.valid)
   {
      core.isBuy = isBull;
      core.mode  = isBull ? TRADE_MODE_BULL_TREND : TRADE_MODE_BEAR_TREND;
      core.reason += " | TREND_CONTINUATION_CORE";
      return core;
   }

   string coreFailReason = core.reason;

   // SECOND: controlled fallback trend entry.
   // This prevents a full year backtest from going dead just because the active S/D pair was not retested.
   double open1  = ind.openArr[1];
   double high1  = ind.highArr[1];
   double low1   = ind.lowArr[1];
   double close1 = ind.closeArr[1];

   double high2  = ind.highArr[2];
   double low2   = ind.lowArr[2];
   double close2 = ind.closeArr[2];

   double price  = close1;
   double ema50  = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   double adxNow = GetADX(ind, 1);

   if(ema50 <= 0.0 || ema200 <= 0.0)
   {
      out.reason = "trend continuation blocked: EMA data missing | core=" + coreFailReason;
      return out;
   }

   ENUM_D1_BIAS d1 = GetD1Bias();

   if(isBull && d1 == D1_BIAS_BEAR)
   {
      out.reason = "trend continuation BUY blocked: D1 bias is bearish | core=" + coreFailReason;
      return out;
   }

   if(!isBull && d1 == D1_BIAS_BULL)
   {
      out.reason = "trend continuation SELL blocked: D1 bias is bullish | core=" + coreFailReason;
      return out;
   }

   bool bullStructure =
      (g_structure.state == STRUCTURE_BULL_TREND ||
       g_structure.state == STRUCTURE_BIAS_BULL ||
       (g_structure.consecutiveHH >= 1 && g_structure.consecutiveHL >= 1));

   bool bearStructure =
      (g_structure.state == STRUCTURE_BEAR_TREND ||
       g_structure.state == STRUCTURE_BIAS_BEAR ||
       (g_structure.consecutiveLH >= 1 && g_structure.consecutiveLL >= 1));

   if(isBull && !bullStructure)
   {
      out.reason = "trend continuation BUY blocked: no HH/HL bull structure | core=" + coreFailReason;
      return out;
   }

   if(!isBull && !bearStructure)
   {
      out.reason = "trend continuation SELL blocked: no LH/LL bear structure | core=" + coreFailReason;
      return out;
   }

   bool strictBullEMA = (close1 > ema200 && ema50 >= ema200);
   bool strictBearEMA = (close1 < ema200 && ema50 <= ema200);

   bool bullStructureOverride =
      (d1 == D1_BIAS_BULL &&
       bullStructure &&
       close1 > ema50 &&
       g_structure.consecutiveHH >= 1 &&
       g_structure.consecutiveHL >= 1 &&
       adxNow >= MathMax(EntryADXMin, 18.0));

   bool bearStructureOverride =
      (d1 == D1_BIAS_BEAR &&
       bearStructure &&
       close1 < ema50 &&
       g_structure.consecutiveLH >= 1 &&
       g_structure.consecutiveLL >= 1 &&
       adxNow >= MathMax(EntryADXMin, 18.0));

   if(isBull && !(strictBullEMA || bullStructureOverride))
   {
      out.reason = "trend continuation BUY blocked: EMA50/EMA200 filter not bullish and no structural override | core=" + coreFailReason;
      return out;
   }

   if(!isBull && !(strictBearEMA || bearStructureOverride))
   {
      out.reason = "trend continuation SELL blocked: EMA50/EMA200 filter not bearish and no structural override | core=" + coreFailReason;
      return out;
   }

   if(isBull && !strictBullEMA && bullStructureOverride)
      Print("[TREND_EMA_OVERRIDE] side=BUY");

   if(!isBull && !strictBearEMA && bearStructureOverride)
      Print("[TREND_EMA_OVERRIDE] side=SELL");

   if(adxNow < MathMax(EntryADXMin, 12.0))
   {
      out.reason = "trend continuation blocked: ADX too low | core=" + coreFailReason;
      return out;
   }

   double range1 = MathMax(high1 - low1, prof.point * 10.0);

   if(isBull)
   {
      double lowerWick1 = MathMin(open1, close1) - low1;

      bool pulledBackToEMA50 =
         (low1 <= ema50 + atr * 0.45) ||
         (low2 <= ema50 + atr * 0.45);

      bool bullishReject =
         close1 > open1 &&
         lowerWick1 / range1 >= MathMax(0.12, InpWickPlayMinWickToRange * 0.60) &&
         close1 > ema50;

      bool sweepReclaim =
         (low1 < ema50 - atr * 0.10 && close1 > ema50) ||
         (low2 < ema50 - atr * 0.10 && close1 > high2);

      bool bullishMomentum =
         close1 > close2 &&
         close1 > ema50 &&
         close1 >= high1 - range1 * 0.30;

      bool notOverstretched =
         (price - ema50 <= atr * 1.60);

      bool triggerOk =
         pulledBackToEMA50 &&
         notOverstretched &&
         (bullishReject || sweepReclaim || (!InpUseWickPlayEntryOnly && bullishMomentum));

      if(!triggerOk)
      {
         out.reason = "trend continuation BUY waiting: no pullback wick/sweep confirmation | core=" + coreFailReason;
         return out;
      }

      double stopAnchor = MathMin(low1, low2);
      double sl = NormalizeDouble(stopAnchor - atr * MathMax(EntryStopATR, 0.30), prof.digits);
      double risk = price - sl;

      double minStop = MathMax(prof.point * MathMax(prof.stopsLevelPoints + 5, 20), prof.point * 20.0);
      if(risk <= minStop)
      {
         out.reason = "trend continuation BUY blocked: SL too tight";
         return out;
      }

      double tp = NormalizeDouble(price + risk * MathMax(RewardRisk, 1.50), prof.digits);
      double reward = tp - price;
      double rr = reward / risk;

      out.valid          = true;
      out.isBuy          = true;
      out.mode           = TRADE_MODE_BULL_TREND;
      out.zoneIdx        = -1;
      out.targetZoneIdx  = -1;
      out.stopLoss       = sl;
      out.takeProfit     = tp;
      out.projectedRR    = rr;
      out.usedZoneTarget = false;
      out.rankScore      = rr + 1.75;
      out.interactionType = sweepReclaim ? ZONE_INTERACTION_SWEEP_RECLAIM : ZONE_INTERACTION_REJECTION;
      out.reason         = StringFormat("TREND FALLBACK BUY | EMA50 pullback wick/sweep | SL=%.5f | TP=%.5f | RR=%.2f | core=%s",
                                        sl, tp, rr, coreFailReason);
      return out;
   }

   // Bear trend fallback
   double upperWick1 = high1 - MathMax(open1, close1);

   bool pulledBackToEMA50 =
      (high1 >= ema50 - atr * 0.45) ||
      (high2 >= ema50 - atr * 0.45);

   bool bearishReject =
      close1 < open1 &&
      upperWick1 / range1 >= MathMax(0.12, InpWickPlayMinWickToRange * 0.60) &&
      close1 < ema50;

   bool sweepReclaim =
      (high1 > ema50 + atr * 0.10 && close1 < ema50) ||
      (high2 > ema50 + atr * 0.10 && close1 < low2);

   bool bearishMomentum =
      close1 < close2 &&
      close1 < ema50 &&
      close1 <= low1 + range1 * 0.30;

   bool notOverstretched =
      (ema50 - price <= atr * 1.60);

   bool triggerOk =
      pulledBackToEMA50 &&
      notOverstretched &&
      (bearishReject || sweepReclaim || (!InpUseWickPlayEntryOnly && bearishMomentum));

   if(!triggerOk)
   {
      out.reason = "trend continuation SELL waiting: no pullback wick/sweep confirmation | core=" + coreFailReason;
      return out;
   }

   double stopAnchor = MathMax(high1, high2);
   double sl = NormalizeDouble(stopAnchor + atr * MathMax(EntryStopATR, 0.30), prof.digits);
   double risk = sl - price;

   double minStop = MathMax(prof.point * MathMax(prof.stopsLevelPoints + 5, 20), prof.point * 20.0);
   if(risk <= minStop)
   {
      out.reason = "trend continuation SELL blocked: SL too tight";
      return out;
   }

   double tp = NormalizeDouble(price - risk * MathMax(RewardRisk, 1.50), prof.digits);
   double reward = price - tp;
   double rr = reward / risk;

   out.valid          = true;
   out.isBuy          = false;
   out.mode           = TRADE_MODE_BEAR_TREND;
   out.zoneIdx        = -1;
   out.targetZoneIdx  = -1;
   out.stopLoss       = sl;
   out.takeProfit     = tp;
   out.projectedRR    = rr;
   out.usedZoneTarget = false;
   out.rankScore      = rr + 1.75;
   out.interactionType = sweepReclaim ? ZONE_INTERACTION_SWEEP_RECLAIM : ZONE_INTERACTION_REJECTION;
   out.reason         = StringFormat("TREND FALLBACK SELL | EMA50 pullback wick/sweep | SL=%.5f | TP=%.5f | RR=%.2f | core=%s",
                                     sl, tp, rr, coreFailReason);
   return out;
}

//+------------------------------------------------------------------+
//| Trend exhaustion exit helpers                                      |
//+------------------------------------------------------------------+
bool IsTrendExhaustionDoubleTop(const IndicatorState &ind, double atr)
{
   if(ind.highArr[1] <= ind.highArr[2] || ind.highArr[2] <= ind.highArr[3])
      return false;

   double tolerance = atr * 0.1;
   return (MathAbs(ind.highArr[1] - ind.highArr[3]) <= tolerance);
}

bool IsTrendExhaustionDoubleBottom(const IndicatorState &ind, double atr)
{
   if(ind.lowArr[1] >= ind.lowArr[2] || ind.lowArr[2] >= ind.lowArr[3])
      return false;

   double tolerance = atr * 0.1;
   return (MathAbs(ind.lowArr[1] - ind.lowArr[3]) <= tolerance);
}

bool HasRepeatedExhaustionRejections(int trendBias, double atr)
{
   int rejectCount = 0;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].valid || !g_zoneReg.zones[i].active ||
         g_zoneReg.zones[i].historical || g_zoneReg.zones[i].broken)
         continue;

      if(g_zoneReg.zones[i].strategyRole != ZROLE_COUNTERTREND_EXHAUSTION)
         continue;

      if(trendBias == 1 && g_zoneReg.zones[i].structuralTag == "HH")
      {
         if(g_zoneReg.zones[i].rejections >= InpExhaustionRejectCount)
            rejectCount++;
      }
      else if(trendBias == -1 && g_zoneReg.zones[i].structuralTag == "LL")
      {
         if(g_zoneReg.zones[i].rejections >= InpExhaustionRejectCount)
            rejectCount++;
      }
   }

   return (rejectCount >= 1);
}

//+------------------------------------------------------------------+
//| Counter-trend strategy helpers                                     |
//+------------------------------------------------------------------+
bool HasFreshHHThenPullback(const IndicatorState &ind, double atr)
{
   if(g_structure.consecutiveHH < 1)
      return false;

   double recentHH = 0.0;
   for(int i = 0; i < g_structure.swingHighCount && i < 3; i++)
   {
      if(g_structure.swingHighs[i].isHigherHigh)
      {
         recentHH = g_structure.swingHighs[i].price;
         break;
      }
   }

   if(recentHH <= 0.0)
      return false;

   double pullback = recentHH - ind.closeArr[1];
   return (pullback > atr * 0.3 && pullback < atr * 1.0);
}

bool HasFreshLLThenPullback(const IndicatorState &ind, double atr)
{
   if(g_structure.consecutiveLL < 1)
      return false;

   double recentLL = 0.0;
   for(int i = 0; i < g_structure.swingLowCount && i < 3; i++)
   {
      if(g_structure.swingLows[i].isLowerLow)
      {
         recentLL = g_structure.swingLows[i].price;
         break;
      }
   }

   if(recentLL <= 0.0)
      return false;

   double pullback = ind.closeArr[1] - recentLL;
   return (pullback > atr * 0.3 && pullback < atr * 1.0);
}

bool HasCounterTrendConfirmation(const IndicatorState &ind, bool isBullCounter)
{
   // H4-only counter-trend confirmation (H1 sniper removed)
   double atrH4 = GetATR(ind, 1);
   if(atrH4 <= 0.0)
      return false;

   bool pattern = false;

   if(isBullCounter)
   {
      pattern =
         IsBullishEngulfing(_Symbol, PERIOD_H4, 1) ||
         IsBullishPinBar(_Symbol, PERIOD_H4, 1) ||
         IsBullishWickRejection(_Symbol, PERIOD_H4, 1, 0.40, 0.45, true);
   }
   else
   {
      pattern =
         IsBearishEngulfing(_Symbol, PERIOD_H4, 1) ||
         IsBearishPinBar(_Symbol, PERIOD_H4, 1) ||
         IsBearishWickRejection(_Symbol, PERIOD_H4, 1, 0.40, 0.45, true);
   }

   if(!pattern)
      return false;

   if(InpUseStochasticInCounterTrend)
   {
      double k1, d1, k2, d2;
      if(GetStochasticSnapshot(_Symbol, PERIOD_H4, InpStochK, InpStochD, InpStochSlowing, k1, d1, k2, d2))
      {
         if(isBullCounter)
            return (k1 <= InpStochOversold || (k2 < d2 && k1 > d1));
         else
            return (k1 >= InpStochOverbought || (k2 > d2 && k1 < d1));
      }
   }

   return true;
}

bool FindBestCounterTrendExhaustionZone(bool isBullCounter, double price, double atr, ZoneInfo &outZone, int &outIdx)
{
   outIdx = -1;
   double bestScore = -DBL_MAX;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].valid || !g_zoneReg.zones[i].active ||
         g_zoneReg.zones[i].historical || g_zoneReg.zones[i].broken)
         continue;

      if(g_zoneReg.zones[i].strategyRole != ZROLE_COUNTERTREND_EXHAUSTION)
         continue;

      double dist = MathAbs(g_zoneReg.zones[i].midPoint - price);
      double distATR = dist / atr;

      if(distATR > 0.5)
         continue;

      double score = ScoreExhaustionZone(g_zoneReg.zones[i], isBullCounter ? -1 : 1);
      if(score > bestScore)
      {
         bestScore = score;
         outZone = g_zoneReg.zones[i];
         outIdx = i;
      }
   }

   return (outIdx >= 0);
}

//+------------------------------------------------------------------+
//| STEP 2: Trend-aligned S/D entry wrapper                         |
//| Prioritizes trend-aligned entries, blocks counter-trend unless  |
//| valid BOS/flip proof exists                                     |
//+------------------------------------------------------------------+
EntryDecision GenerateTrendAlignedSDDecision(const IndicatorState &ind,
                                             const SymbolProfile &prof,
                                             bool &handled)
{
   EntryDecision out = MakeEmptyDecision();
   handled = false;

   if(!InpUseSupplyDemandZones || !InpSDTradeOnlyActivePair)
      return out;

   handled = true;

   int trend = GetMarketTrend();

   // Bull trend: buy active Demand first.
   if(trend == 1)
   {
      EntryDecision sdBuy = GenerateZoneRetestDecision(ind, prof, true, 1.5, 2.2);

      if(sdBuy.valid)
      {
         Print("[SD_PRIORITY_ENTRY] BUY active Support retest selected in bull structure");
         return sdBuy;
      }

      if(InpSDAllowCounterTrendIfBOS)
      {
         EntryDecision sdSell = GenerateZoneRetestDecision(ind, prof, false, 1.5, 2.2);

         if(sdSell.valid)
         {
            Print("[SD_COUNTERTREND_ENTRY] SELL active Resistance allowed after BOS/flip proof");
            return sdSell;
         }

         out.reason = "SD_WAITING_FOR_TREND_ALIGNED_RETEST | buy=" + sdBuy.reason + " | sell=" + sdSell.reason;
         Print("[SD_ENTRY_WAIT] trend=BULL buy=", sdBuy.reason, " sell=", sdSell.reason);
         return out;
      }

      out.reason = "SD_WAITING_FOR_BULL_SUPPORT_RETEST | buy=" + sdBuy.reason;
      Print("[SD_ENTRY_WAIT] trend=BULL buy=", sdBuy.reason);
      return out;
   }

   // Bear trend: sell active Supply first.
   if(trend == -1)
   {
      EntryDecision sdSell = GenerateZoneRetestDecision(ind, prof, false, 1.5, 2.2);

      if(sdSell.valid)
      {
         Print("[SD_PRIORITY_ENTRY] SELL active Resistance retest selected in bear structure");
         return sdSell;
      }

      if(InpSDAllowCounterTrendIfBOS)
      {
         EntryDecision sdBuy = GenerateZoneRetestDecision(ind, prof, true, 1.5, 2.2);

         if(sdBuy.valid)
         {
            Print("[SD_COUNTERTREND_ENTRY] BUY active Support allowed after BOS/flip proof");
            return sdBuy;
         }

         out.reason = "SD_WAITING_FOR_TREND_ALIGNED_RETEST | sell=" + sdSell.reason + " | buy=" + sdBuy.reason;
         Print("[SD_ENTRY_WAIT] trend=BEAR sell=", sdSell.reason, " buy=", sdBuy.reason);
         return out;
      }

      out.reason = "SD_WAITING_FOR_BEAR_RESISTANCE_RETEST | sell=" + sdSell.reason;
      Print("[SD_ENTRY_WAIT] trend=BEAR sell=", sdSell.reason);
      return out;
   }

   // Range/neutral: evaluate both sides and choose the stronger confirmed setup.
   EntryDecision rangeBuy = GenerateZoneRetestDecision(ind, prof, true, 1.5, 2.2);
   EntryDecision rangeSell = GenerateZoneRetestDecision(ind, prof, false, 1.5, 2.2);

   if(rangeBuy.valid && rangeSell.valid)
   {
      if(rangeBuy.rankScore >= rangeSell.rankScore)
      {
         Print("[SD_PRIORITY_ENTRY] RANGE selected BUY active Support by score");
         return rangeBuy;
      }

      Print("[SD_PRIORITY_ENTRY] RANGE selected SELL active Resistance by score");
      return rangeSell;
   }

   if(rangeBuy.valid)
   {
      Print("[SD_PRIORITY_ENTRY] RANGE selected BUY active Support");
      return rangeBuy;
   }

   if(rangeSell.valid)
   {
      Print("[SD_PRIORITY_ENTRY] RANGE selected SELL active Resistance");
      return rangeSell;
   }

   out.reason = "SD_WAITING_FOR_RANGE_RETEST | buy=" + rangeBuy.reason + " | sell=" + rangeSell.reason;
   Print("[SD_ENTRY_WAIT] trend=RANGE buy=", rangeBuy.reason, " sell=", rangeSell.reason);
   return out;
}

//+==================================================================+
//| SECTION 10: ZONE RETEST / FLIP DECISION                         |
//| D1-filtered zone retests, flip zones, S/R retest entries         |
//+==================================================================+

//+------------------------------------------------------------------+
//| SDStructureAllowsEntry - Check if market structure allows S/D    |
//| STEP 1: Strict top-down structure permission                     |
//+------------------------------------------------------------------+
bool SDStructureAllowsEntry(bool isBuy, ZoneInfo &z)
{
   if(!InpSDUseStructurePermission)
      return true;

   int trend = GetMarketTrend(); // 1 = bull, -1 = bear, 0 = range/neutral
   ENUM_D1_BIAS d1 = GetD1Bias();

   string p = z.structuralTag;

   double currentPrice = (SymbolInfoDouble(_Symbol, SYMBOL_BID) +
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK)) * 0.5;

   // Use dynamic role: zone below price acts as Demand, above as Supply.
   bool actsAsDemand = SDZoneActsAsDemand(z, currentPrice);
   bool actsAsSupply = SDZoneActsAsSupply(z, currentPrice);

   // Neutral/range: allow both sides.
   if(trend == 0)
      return true;

   // Bullish structure: normal trade = BUY (zone acts as Demand)
   if(trend == 1)
   {
      if(isBuy && actsAsDemand)
         return true;

      // D1 pullback override: H4 bull is just a pullback in strong D1 bear.
      // Allow SELL at supply zones to capture D1 trend continuation.
      // Relaxed: also allow when D1 is neutral but price < D1 EMA200 (intact downtrend).
      if(!isBuy && actsAsSupply)
      {
         bool d1ExplicitBear = (d1 == D1_BIAS_BEAR);
         bool d1StructuralBear = (d1 == D1_BIAS_NEUTRAL && g_d1Ind.valid &&
                                  g_d1Ind.closeArr[1] < g_d1Ind.ema200[1]);
         if(d1ExplicitBear || d1StructuralBear)
         {
            Print("[SD_D1_PULLBACK_OVERRIDE] side=SELL d1=", D1BiasToString(d1),
                  " h4_trend=BULL zoneId=", z.id,
                  " pattern=", p, " note=H4_bull_is_D1_pullback",
                  " structural=", d1StructuralBear ? "true" : "false");
            return true;
         }
      }

      // Counter-trend SELL only when zone acts as Supply and reversal proven.
      if(!isBuy && actsAsSupply)
      {
         bool validReversalSupply =
            (p == "RBD" || p == "FLIP_SUPPLY" || p == "PDF_MOMENTUM_SUPPLY" ||
             p == "PDF_CONSOLIDATION_SUPPLY" || p == "PDF_WICK_SUPPLY");

         bool tookOutDemand =
            (z.breakScore >= 0.50 || z.structureImpactScore >= 0.95);

         bool d1DoesNotFightSell = (d1 != D1_BIAS_BULL);

         return InpSDAllowCounterTrendIfBOS &&
                validReversalSupply &&
                tookOutDemand &&
                d1DoesNotFightSell;
      }

      return false;
   }

   // Bearish structure: normal trade = SELL (zone acts as Supply)
   if(trend == -1)
   {
      if(!isBuy && actsAsSupply)
         return true;

      // D1 pullback override: H4 bear is just a pullback in strong D1 bull.
      // Allow BUY at demand zones to capture D1 trend continuation.
      // Relaxed: also allow when D1 is neutral but price > D1 EMA200 (intact uptrend).
      if(isBuy && actsAsDemand)
      {
         bool d1ExplicitBull = (d1 == D1_BIAS_BULL);
         bool d1StructuralBull = (d1 == D1_BIAS_NEUTRAL && g_d1Ind.valid &&
                                  g_d1Ind.closeArr[1] > g_d1Ind.ema200[1]);
         if(d1ExplicitBull || d1StructuralBull)
         {
            Print("[SD_D1_PULLBACK_OVERRIDE] side=BUY d1=", D1BiasToString(d1),
                  " h4_trend=BEAR zoneId=", z.id,
                  " pattern=", p, " note=H4_bear_is_D1_pullback",
                  " structural=", d1StructuralBull ? "true" : "false");
            return true;
         }
      }

      // Counter-trend BUY only when zone acts as Demand and reversal proven.
      if(isBuy && actsAsDemand)
      {
         bool validReversalDemand =
            (p == "DBR" || p == "FLIP_DEMAND" || p == "PDF_MOMENTUM_DEMAND" ||
             p == "PDF_CONSOLIDATION_DEMAND" || p == "PDF_WICK_DEMAND");

         bool tookOutSupply =
            (z.breakScore >= 0.50 || z.structureImpactScore >= 0.95);

         bool d1DoesNotFightBuy = (d1 != D1_BIAS_BEAR);

         return InpSDAllowCounterTrendIfBOS &&
                validReversalDemand &&
                tookOutSupply &&
                d1DoesNotFightBuy;
      }

      return false;
   }

   return false;
}

//+------------------------------------------------------------------+
//| SDCandlesInsideZone - Count candles inside zone                  |
//+------------------------------------------------------------------+
int SDCandlesInsideZone(ZoneInfo &z, const IndicatorState &ind, int lookback)
{
   int count = 0;
   int maxBars = MathMin(lookback, 10);

   for(int i = 1; i <= maxBars; i++)
   {
      bool overlaps =
         (ind.lowArr[i] <= z.upperBound &&
          ind.highArr[i] >= z.lowerBound);

      if(overlaps)
         count++;
      else
         break;
   }

   return count;
}

//+------------------------------------------------------------------+
//| S/D oscillator policy helpers                                    |
//| Stochastic is helper only in trend. It can be required for range  |
//| and counter-trend/reversal setups.                               |
//+------------------------------------------------------------------+
bool SDIsTrendAlignedSide(bool isBuy)
{
   int trend = GetMarketTrend();

   if(isBuy && trend == 1)
      return true;

   if(!isBuy && trend == -1)
      return true;

   return false;
}

int SDOscillatorConfirmationScore(bool isBuy)
{
   if(!InpSDUseStochIndicatorConfirm)
      return 0;

   double k1 = 0.0, d1 = 0.0, k2 = 0.0, d2 = 0.0;

   if(!GetStochasticSnapshot(_Symbol, InpEntryTF, InpStochK, InpStochD, InpStochSlowing, k1, d1, k2, d2))
      return 0;

   if(isBuy)
   {
      bool oversoldTurn =
         (k1 <= InpStochOversold) ||
         (k2 < d2 && k1 > d1 && k1 < 50.0);

      return oversoldTurn ? 1 : 0;
   }

   bool overboughtTurn =
      (k1 >= InpStochOverbought) ||
      (k2 > d2 && k1 < d1 && k1 > 50.0);

   return overboughtTurn ? 1 : 0;
}

bool SDOscillatorShouldBeRequired(bool isBuy, bool trendAligned)
{
   // For trend-aligned S/D retests, Stochastic should NOT be a hard blocker
   // unless the user explicitly enables this input.
   if(trendAligned)
      return InpSDUseOscillatorAsTrendHardFilter;

   // For range/reversal/counter-trend, Stochastic can be required.
   if(InpSDUseOscillatorForRangeReversal)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Generate Zone Retest/Flip Decision (one-sided D1 zone entry)      |
//+------------------------------------------------------------------+
int SDIndicatorConfirmationScore(const IndicatorState &ind, bool isBuy)
{
   if(!InpSDUseIndicatorConfirmation)
      return 99;

   int score = 0;

   double close1 = ind.closeArr[1];
   double ema50  = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   double adx    = GetADX(ind, 1);

   // EMA/ADX remain normal confirmation tools.
   // Stochastic is handled separately so it does not block trend S/D entries.
   if(InpSDUseEMAIndicatorConfirm && ema50 > 0.0 && ema200 > 0.0)
   {
      if(isBuy)
      {
         if(close1 >= ema50) score += 1;
         if(ema50 >= ema200) score += 1;
      }
      else
      {
         if(close1 <= ema50) score += 1;
         if(ema50 <= ema200) score += 1;
      }
   }

   if(InpSDUseADXIndicatorConfirm && adx >= InpSDMinADXForTrendConfirm)
      score += 1;

   return score;
}

int SDCandleConfirmationScore(bool isBuy)
{
   if(!InpSDUseCandlePatternConfirmation)
      return 99;

   int score = 0;

   if(isBuy)
   {
      if(InpSDUseMorningStarConfirmation && IsMorningStarAtDemand(_Symbol, InpEntryTF, 1)) score += 4;
      if(InpSDUseEngulfingConfirmation && IsBullishEngulfing(_Symbol, InpEntryTF, 1)) score += 3;
      if(InpSDUsePinbarConfirmation && IsBullishPinBar(_Symbol, InpEntryTF, 1, InpSDPinbarMinWickToBody, 1.0, 0.60)) score += 3;
      if(IsBullishWickRejection(_Symbol, InpEntryTF, 1, 0.40, 0.45, true)) score += 2;
      if(InpSDUseStrongCandleConfirmation && IsStrongBullishBody(_Symbol, InpEntryTF, 1, 0.60)) score += 2;
      if(InpSDUseHammerConfirmation && IsBullishHammerAtDemand(_Symbol, InpEntryTF, 1)) score += 3;
      if(InpSDUseDojiConfirmation && IsBullishDojiRejection(_Symbol, InpEntryTF, 1, InpSDDojiMaxBodyPct, 0.35)) score += 2;
      if(InpSDUseInvertedHammerConfirmation && IsBullishInvertedHammerAtDemand(_Symbol, InpEntryTF, 1)) score += 1;
   }
   else
   {
      if(InpSDUseEveningStarConfirmation && IsEveningStarAtSupply(_Symbol, InpEntryTF, 1)) score += 4;
      if(InpSDUseEngulfingConfirmation && IsBearishEngulfing(_Symbol, InpEntryTF, 1)) score += 3;
      if(InpSDUsePinbarConfirmation && IsBearishPinBar(_Symbol, InpEntryTF, 1, InpSDPinbarMinWickToBody, 1.0, 0.40)) score += 3;
      if(IsBearishWickRejection(_Symbol, InpEntryTF, 1, 0.40, 0.45, true)) score += 2;
      if(InpSDUseStrongCandleConfirmation && IsStrongBearishBody(_Symbol, InpEntryTF, 1, 0.60)) score += 2;
      if(InpSDUseInvertedHammerConfirmation && IsBearishInvertedHammerAtSupply(_Symbol, InpEntryTF, 1)) score += 3;
      if(InpSDUseDojiConfirmation && IsBearishDojiRejection(_Symbol, InpEntryTF, 1, InpSDDojiMaxBodyPct, 0.35)) score += 2;
      if(InpSDUseHammerConfirmation && IsBearishHammerAtSupply(_Symbol, InpEntryTF, 1)) score += 1;
   }

   return score;
}

string SDCandlePatternName(bool isBuy)
{
   if(isBuy)
   {
      if(IsMorningStarAtDemand(_Symbol, InpEntryTF, 1)) return "MorningStar";
      if(IsBullishEngulfing(_Symbol, InpEntryTF, 1)) return "BullishEngulfing";
      if(IsBullishHammerAtDemand(_Symbol, InpEntryTF, 1)) return "Hammer";
      if(IsBullishPinBar(_Symbol, InpEntryTF, 1)) return "BullishPinBar";
      if(IsBullishDojiRejection(_Symbol, InpEntryTF, 1)) return "BullishDojiRejection";
      if(IsBullishInvertedHammerAtDemand(_Symbol, InpEntryTF, 1)) return "InvertedHammer";
      if(IsBullishWickRejection(_Symbol, InpEntryTF, 1, 0.40, 0.45, true)) return "BullishWickRejection";
      if(IsStrongBullishBody(_Symbol, InpEntryTF, 1, 0.60)) return "StrongBullishCandle";
   }
   else
   {
      if(IsEveningStarAtSupply(_Symbol, InpEntryTF, 1)) return "EveningStar";
      if(IsBearishEngulfing(_Symbol, InpEntryTF, 1)) return "BearishEngulfing";
      if(IsBearishInvertedHammerAtSupply(_Symbol, InpEntryTF, 1)) return "InvertedHammerAtSupply";
      if(IsBearishPinBar(_Symbol, InpEntryTF, 1)) return "BearishPinBar";
      if(IsBearishDojiRejection(_Symbol, InpEntryTF, 1)) return "BearishDojiRejection";
      if(IsBearishWickRejection(_Symbol, InpEntryTF, 1, 0.40, 0.45, true)) return "BearishWickRejection";
      if(IsStrongBearishBody(_Symbol, InpEntryTF, 1, 0.60)) return "StrongBearishCandle";
   }

   return "None";
}

//+------------------------------------------------------------------+
//| STEP 4: Contextual Candle Interpretation at S/D Zones            |
//| Validates candle patterns match zone type (no bearish at Support)|
//+------------------------------------------------------------------+
enum ENUM_SD_CANDLE_CONTEXT
{
   SD_CANDLE_NONE = 0,
   SD_CANDLE_BULLISH_REJECTION,
   SD_CANDLE_BEARISH_REJECTION,
   SD_CANDLE_INDECISION,
   SD_CANDLE_WEAK_REJECTION,
   SD_CANDLE_INVALID_FOR_ZONE
};

string SDCandleContextToString(ENUM_SD_CANDLE_CONTEXT ctx)
{
   switch(ctx)
   {
      case SD_CANDLE_BULLISH_REJECTION: return "BULLISH_REJECTION";
      case SD_CANDLE_BEARISH_REJECTION: return "BEARISH_REJECTION";
      case SD_CANDLE_INDECISION:        return "INDECISION";
      case SD_CANDLE_WEAK_REJECTION:    return "WEAK_REJECTION";
      case SD_CANDLE_INVALID_FOR_ZONE:  return "INVALID_FOR_ZONE";
      default:                          return "NONE";
   }
}

ENUM_SD_CANDLE_CONTEXT SDInterpretCandleAtZone(bool isBuy,
                                               ZoneInfo &z,
                                               const IndicatorState &ind,
                                               double atrVal)
{
   double o1 = ind.openArr[1];
   double h1 = ind.highArr[1];
   double l1 = ind.lowArr[1];
   double c1 = ind.closeArr[1];

   double range = MathMax(h1 - l1, _Point * 10.0);
   double body  = MathAbs(c1 - o1);

   double upperWick = h1 - MathMax(o1, c1);
   double lowerWick = MathMin(o1, c1) - l1;
   double closePos  = (c1 - l1) / range;

   bool candleTouchedZone =
      (l1 <= z.upperBound &&
       h1 >= z.lowerBound);

   if(!candleTouchedZone)
      return SD_CANDLE_NONE;

   // Dynamic role instead of static type
   double currentPrice = (SymbolInfoDouble(_Symbol, SYMBOL_BID) +
                          SymbolInfoDouble(_Symbol, SYMBOL_ASK)) * 0.5;
   bool actsAsDemand = SDZoneActsAsDemand(z, currentPrice);
   bool actsAsSupply = SDZoneActsAsSupply(z, currentPrice);

   bool doji = IsDoji(_Symbol, InpEntryTF, 1, InpSDDojiMaxBodyPct);

   bool bullEngulf = IsBullishEngulfing(_Symbol, InpEntryTF, 1);
   bool bearEngulf = IsBearishEngulfing(_Symbol, InpEntryTF, 1);

   bool bullishPinbar = IsBullishPinBar(_Symbol, InpEntryTF, 1, InpSDPinbarMinWickToBody, 1.0, 0.60);
   bool bearishPinbar = IsBearishPinBar(_Symbol, InpEntryTF, 1, InpSDPinbarMinWickToBody, 1.0, 0.40);

   bool hammerDemand = IsBullishHammerAtDemand(_Symbol, InpEntryTF, 1);
   bool invertedHammerDemand = IsBullishInvertedHammerAtDemand(_Symbol, InpEntryTF, 1);
   bool invertedHammerSupply = IsBearishInvertedHammerAtSupply(_Symbol, InpEntryTF, 1);
   bool hammerSupply = IsBearishHammerAtSupply(_Symbol, InpEntryTF, 1);

   bool morningStar = InpSDUseMorningStarConfirmation && IsMorningStarAtDemand(_Symbol, InpEntryTF, 1);
   bool eveningStar = InpSDUseEveningStarConfirmation && IsEveningStarAtSupply(_Symbol, InpEntryTF, 1);

   bool strongBull = IsStrongBullishBody(_Symbol, InpEntryTF, 1, 0.60);
   bool strongBear = IsStrongBearishBody(_Symbol, InpEntryTF, 1, 0.60);

   bool lowerRejection = (lowerWick / range >= 0.35 && closePos >= 0.50);
   bool upperRejection = (upperWick / range >= 0.35 && closePos <= 0.50);

   // Dynamic Demand context: only bullish patterns are valid.
   if(actsAsDemand)
   {
      if(!isBuy)
         return SD_CANDLE_INVALID_FOR_ZONE;

      if(eveningStar || bearEngulf || bearishPinbar || strongBear)
         return SD_CANDLE_INVALID_FOR_ZONE;

      if(morningStar || bullEngulf || bullishPinbar || hammerDemand || strongBull || lowerRejection)
         return SD_CANDLE_BULLISH_REJECTION;

      if(invertedHammerDemand)
         return SD_CANDLE_WEAK_REJECTION;

      if(doji)
         return SD_CANDLE_INDECISION;

      return SD_CANDLE_NONE;
   }

   // Dynamic Supply context: only bearish patterns are valid.
   if(actsAsSupply)
   {
      if(isBuy)
         return SD_CANDLE_INVALID_FOR_ZONE;

      if(morningStar || bullEngulf || bullishPinbar || strongBull)
         return SD_CANDLE_INVALID_FOR_ZONE;

      if(eveningStar || bearEngulf || bearishPinbar || invertedHammerSupply || strongBear || upperRejection)
         return SD_CANDLE_BEARISH_REJECTION;

      if(hammerSupply)
         return SD_CANDLE_WEAK_REJECTION;

      if(doji)
         return SD_CANDLE_INDECISION;

      return SD_CANDLE_NONE;
   }

   return SD_CANDLE_NONE;
}

EntryDecision GenerateZoneRetestDecision(const IndicatorState &ind,
                                         const SymbolProfile &prof,
                                         bool isBuy,
                                         double stopMult,
                                         double rr)
{
   EntryDecision out = MakeEmptyDecision();
   out.isBuy = isBuy;
   out.mode  = isBuy ? TRADE_MODE_BULL_TREND : TRADE_MODE_BEAR_TREND;

   if(!InpUseSupplyDemandZones)
   {
      out.reason = "SD_disabled";
      return out;
   }

   double atrVal = GetATR(ind, 1);
   if(atrVal <= 0.0)
   {
      out.reason = "invalid_atr";
      return out;
   }

   double price = ind.closeArr[1];
   if(price <= 0.0)
   {
      out.reason = "invalid_price";
      return out;
   }

   ZoneInfo z;
   bool hasZone = false;

   if(isBuy)
      hasZone = SDGetActiveDemandZone(z);
   else
      hasZone = SDGetActiveSupplyZone(z);

   if(!hasZone)
   {
      out.reason = isBuy ? "no_active_demand" : "no_active_supply";
      return out;
   }

   if(!SDIsActiveTradingZone(z))
   {
      out.reason = "blocked_non_active_sd_zone";
      
      Print("[SD_BLOCKED] zoneId=", z.id,
            " valid=", z.valid,
            " broken=", z.broken,
            " active=", z.active,
            " isTPTargetOnly=", z.isTPTargetOnly,
            " isPrimary=", z.isPrimary,
            " isExecutionEligible=", z.isExecutionEligible,
            " type=", z.type,
            " ageInBars=", z.ageInBars,
            " cleanTouchCount=", z.cleanTouchCount);
      
      return out;
   }

   if(!SDStructureAllowsEntry(isBuy, z))
   {
      out.reason = isBuy ? "structure_blocks_active_demand_buy"
                         : "structure_blocks_active_supply_sell";

      Print("[SD_STRUCTURE_BLOCK] side=", isBuy ? "BUY" : "SELL",
            " zoneId=", z.id,
            " pattern=", z.structuralTag,
            " trend=", GetMarketTrend());

      return out;
   }

   if(!z.valid || z.broken || !z.active)
   {
      out.reason = isBuy ? "active_demand_invalid" : "active_supply_invalid";
      return out;
   }

   double tol = atrVal * 0.15;

   // True retest check:
   // The last closed H4 candle must overlap/touch the active zone.
   bool candleTouchedZone =
      (ind.lowArr[1] <= z.upperBound + tol &&
       ind.highArr[1] >= z.lowerBound - tol);

   if(!candleTouchedZone)
   {
      out.reason = isBuy ? "waiting_for_price_to_return_to_active_demand"
                         : "waiting_for_price_to_return_to_active_supply";

      Print("[SD_RETEST_WAIT] side=", isBuy ? "BUY" : "SELL",
            " zoneId=", z.id,
            " pattern=", z.structuralTag,
            " price=", DoubleToString(price, _Digits),
            " upper=", DoubleToString(z.upperBound, _Digits),
            " lower=", DoubleToString(z.lowerBound, _Digits));

      return out;
   }

   int candlesInside = SDCandlesInsideZone(z, ind, InpSDMaxCandlesInsideZone + 2);

   if(candlesInside > InpSDMaxCandlesInsideZone)
   {
      out.reason = "price_spent_too_long_inside_active_zone";

      Print("[SD_TIME_IN_ZONE_BLOCK] side=", isBuy ? "BUY" : "SELL",
            " zoneId=", z.id,
            " candlesInside=", candlesInside,
            " maxAllowed=", InpSDMaxCandlesInsideZone);

      return out;
   }

   double zoneWidth = MathMax(z.upperBound - z.lowerBound, prof.point * 10.0);

   bool deepInZone = false;

   if(isBuy)
      deepInZone = (ind.lowArr[1] < z.midPoint);
   else
      deepInZone = (ind.highArr[1] > z.midPoint);

   double o1 = ind.openArr[1];
   double h1 = ind.highArr[1];
   double l1 = ind.lowArr[1];
   double c1 = ind.closeArr[1];

   double range = MathMax(h1 - l1, prof.point * 10.0);
   double body  = MathAbs(c1 - o1);

   double upperWick = h1 - MathMax(o1, c1);
   double lowerWick = MathMin(o1, c1) - l1;

   bool rejection = false;
   bool strongConfirm = false;

   if(isBuy)
   {
      rejection = (lowerWick / range >= 0.35 && c1 > o1);
      strongConfirm = (c1 > o1 && body >= atrVal * 0.20);
   }
   else
   {
      rejection = (upperWick / range >= 0.35 && c1 < o1);
      strongConfirm = (c1 < o1 && body >= atrVal * 0.20);
   }

   bool doublePattern = isBuy ? IsDoubleBottom(ind.lowArr, ind.highArr, ind.closeArr, ind.openArr, atrVal)
                              : IsDoubleTop(ind.highArr, ind.lowArr, ind.closeArr, ind.openArr, atrVal);

   // Get contextual candle interpretation at the zone
   ENUM_SD_CANDLE_CONTEXT candleContext = SDInterpretCandleAtZone(isBuy, z, ind, atrVal);
   
   string contextStr = SDCandleContextToString(candleContext);

   if(candleContext == SD_CANDLE_INVALID_FOR_ZONE)
   {
      out.reason = "candle_pattern_invalid_for_active_zone";

      string dynamicLabel = SDDynamicRoleName(z, price);

      Print("[SD_CANDLE_CONTEXT_BLOCK] side=", isBuy ? "BUY" : "SELL",
            " zoneId=", z.id,
            " dynamicRole=", dynamicLabel,
            " origType=", ZoneTypeToString(z.type),
            " context=", contextStr,
            " reason=", out.reason);

      return out;
   }

   // STEP 9: Block indecision and weak candle context BEFORE confirmation
   if(InpSDBlockIndecisionEntries &&
      (candleContext == SD_CANDLE_INDECISION ||
       candleContext == SD_CANDLE_WEAK_REJECTION))
   {
      out.reason = isBuy ? "demand_retest_candle_needs_followup"
                         : "supply_retest_candle_needs_followup";

      Print("[SD_CANDLE_CONTEXT_BLOCK] side=", isBuy ? "BUY" : "SELL",
            " zoneId=", z.id,
            " context=", SDCandleContextToString(candleContext),
            " reason=", out.reason);

      return out;
   }

   int candleScore = SDCandleConfirmationScore(isBuy);
   int indicatorScore = SDIndicatorConfirmationScore(ind, isBuy);
   int oscillatorScore = SDOscillatorConfirmationScore(isBuy);

   bool trendAlignedSD = SDIsTrendAlignedSide(isBuy);
   bool oscillatorRequired = SDOscillatorShouldBeRequired(isBuy, trendAlignedSD);
   bool oscillatorOk = (!oscillatorRequired || oscillatorScore > 0);

   // Stochastic can boost total confirmation, but trend-aligned S/D entries
   // should not fail only because Stochastic is not overbought/oversold.
   int totalConfirmScore = candleScore + indicatorScore;

   if(InpSDUseOscillatorConfidenceBoost && oscillatorScore > 0)
      totalConfirmScore += oscillatorScore;

   bool candleOk =
      (!InpSDUseCandlePatternConfirmation ||
       candleScore >= InpSDMinCandlePatternScore ||
       doublePattern);

   bool indicatorOk = true;

   if(!trendAlignedSD)
   {
      // Range/reversal/counter-trend entries can require oscillator confirmation.
      indicatorOk =
         (!InpSDUseIndicatorConfirmation ||
          (indicatorScore + oscillatorScore) >= InpSDMinIndicatorScore) &&
         oscillatorOk;
   }
   else
   {
      // Trend-aligned entries: EMA/ADX/Stoch can help, but Stochastic does not block.
      if(InpSDUseOscillatorAsTrendHardFilter)
         indicatorOk = oscillatorOk;
      else
         indicatorOk = true;
   }

   int requiredTotalScore = InpSDMinTotalConfirmationScore;

   // Trend S/D entries should be allowed from strong wick/candle rejection.
   // This stops Stochastic from indirectly forcing the total score too high.
   if(trendAlignedSD && !InpSDUseOscillatorAsTrendHardFilter)
      requiredTotalScore = MathMax(InpSDMinCandlePatternScore, InpSDMinTotalConfirmationScore - 1);

   bool strongPatternOverride = (InpSDAllowStrongPatternOverride && candleScore >= 4);
   
   // Context-aware confirmation boost
   bool contextBonus = (candleContext == SD_CANDLE_BULLISH_REJECTION ||
                        candleContext == SD_CANDLE_BEARISH_REJECTION);
   
   bool contextPenalty = false;

   // STEP 9: Improved confirmation logic - block indecision/weak rejection
   bool confirmed = false;

   if(isBuy && candleContext == SD_CANDLE_BULLISH_REJECTION)
   {
      confirmed =
         (candleOk && indicatorOk && totalConfirmScore >= requiredTotalScore);
   }

   if(!isBuy && candleContext == SD_CANDLE_BEARISH_REJECTION)
   {
      confirmed =
         (candleOk && indicatorOk && totalConfirmScore >= requiredTotalScore);
   }

   if(strongPatternOverride &&
      candleContext != SD_CANDLE_INDECISION &&
      candleContext != SD_CANDLE_WEAK_REJECTION &&
      candleContext != SD_CANDLE_INVALID_FOR_ZONE)
   {
      confirmed = true;
   }

   if(doublePattern &&
      candleContext != SD_CANDLE_INDECISION &&
      candleContext != SD_CANDLE_WEAK_REJECTION &&
      candleContext != SD_CANDLE_INVALID_FOR_ZONE)
   {
      confirmed = true;
   }

   Print("[SD_CONFIRM_CHECK] side=", isBuy ? "BUY" : "SELL",
         " candleScore=", candleScore,
         " indicatorScore=", indicatorScore,
         " oscillatorScore=", oscillatorScore,
         " total=", totalConfirmScore,
         " requiredTotal=", requiredTotalScore,
         " trendAlignedSD=", trendAlignedSD ? "true" : "false",
         " oscillatorRequired=", oscillatorRequired ? "true" : "false",
         " oscillatorOk=", oscillatorOk ? "true" : "false",
         " candlePattern=", SDCandlePatternName(isBuy),
         " doublePattern=", doublePattern,
         " candleContext=", contextStr,
         " contextBonus=", contextBonus,
         " contextPenalty=", contextPenalty,
         " confirmed=", confirmed);

   if(!confirmed)
   {
      out.reason = isBuy ? "active_demand_touched_no_bullish_confirmation"
                         : "active_supply_touched_no_bearish_confirmation";

      Print("[SD_RETEST_NO_CONFIRM] side=", isBuy ? "BUY" : "SELL",
            " zoneId=", z.id,
            " pattern=", z.structuralTag,
            " candleScore=", candleScore,
            " indicatorScore=", indicatorScore,
            " oscillatorScore=", oscillatorScore,
            " trendAlignedSD=", trendAlignedSD ? "true" : "false",
            " oscillatorRequired=", oscillatorRequired ? "true" : "false",
            " oscillatorOk=", oscillatorOk ? "true" : "false",
            " candlePattern=", SDCandlePatternName(isBuy),
            " candleContext=", contextStr,
            " doublePattern=", doublePattern,
            " reason=", out.reason);

      return out;
   }

   if(deepInZone && candleScore < 3)
   {
      out.reason = "deep_zone_penetration_without_strong_confirmation";
      return out;
   }

   int zoneIdx = -1;
   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(g_zoneReg.zones[i].id == z.id)
      {
         zoneIdx = i;
         break;
      }
   }

   if(zoneIdx < 0)
   {
      out.reason = "active_zone_not_found_in_registry";
      return out;
   }

   // Find local wick extremes from recent candles for proper SL placement
   double lowestWick  = ind.lowArr[1];
   double highestWick = ind.highArr[1];
   for(int w = 2; w <= 5; w++)
   {
      if(ind.lowArr[w] < lowestWick)   lowestWick  = ind.lowArr[w];
      if(ind.highArr[w] > highestWick) highestWick = ind.highArr[w];
   }

   double sl = 0.0;
   double tp = 0.0;
   bool usedZoneTarget = false;
   int targetZoneIdx = -1;

   // STEP 10: Use opposite-zone TP before RR fallback
   if(isBuy)
   {
      // SL below candle wicks at zone (not just zone edge)
      sl = BuildBufferedBuyStop(z.lowerBound, lowestWick, atrVal, 0.50, prof.digits);

      // Try to get nearest Supply zone above price for TP target
      ZoneInfo targetZone;
      if(SDGetNearestTargetZone(true, price, atrVal, targetZone) && targetZone.lowerBound > price)
      {
         tp = NormalizeDouble(targetZone.lowerBound - atrVal * 0.10, prof.digits);
         usedZoneTarget = true;
         targetZoneIdx = SDFindZoneIndexById(targetZone.id);
         
         Print("[SD_TP_TARGET] side=BUY using nearest Supply zone id=", targetZone.id,
               " at ", DoubleToString(targetZone.lowerBound, _Digits));
      }
      else
      {
         // Fallback to RR-based TP
         tp = NormalizeDouble(price + (price - sl) * rr, prof.digits);
         
         Print("[SD_TP_FALLBACK] side=BUY using RR=", DoubleToString(rr, 2),
               " no suitable Supply zone found");
      }
   }
   else
   {
      // SL above candle wicks at zone (not just zone edge)
      sl = BuildBufferedSellStop(z.upperBound, highestWick, atrVal, 0.50, prof.digits);

      // Try to get nearest Demand zone below price for TP target
      ZoneInfo targetZone;
      if(SDGetNearestTargetZone(false, price, atrVal, targetZone) && targetZone.upperBound < price)
      {
         tp = NormalizeDouble(targetZone.upperBound + atrVal * 0.10, prof.digits);
         usedZoneTarget = true;
         targetZoneIdx = SDFindZoneIndexById(targetZone.id);
         
         Print("[SD_TP_TARGET] side=SELL using nearest Demand zone id=", targetZone.id,
               " at ", DoubleToString(targetZone.upperBound, _Digits));
      }
      else
      {
         // Fallback to RR-based TP
         tp = NormalizeDouble(price - (sl - price) * rr, prof.digits);
         
         Print("[SD_TP_FALLBACK] side=SELL using RR=", DoubleToString(rr, 2),
               " no suitable Demand zone found");
      }
   }

   double risk = isBuy ? (price - sl) : (sl - price);
   double reward = isBuy ? (tp - price) : (price - tp);

   if(risk <= prof.point * 10.0 || reward <= 0.0)
   {
      out.reason = "invalid_sd_risk_reward";
      return out;
   }

   double projRR = reward / risk;
   if(projRR < 1.0)
   {
      out.reason = "sd_rr_too_small";
      return out;
   }

   // STEP 11: Require stronger confirmation when no opposite-zone TP exists
   if(InpSDRequireOppositeZoneOrStrongRR && !usedZoneTarget)
   {
      int requiredScore = InpSDMinTotalConfirmationScore + InpSDExtraConfirmWithoutOppZone;

      if(totalConfirmScore < requiredScore)
      {
         out.reason = "rr_fallback_requires_stronger_confirmation";

         Print("[SD_ENTRY_BLOCK] reason=RR_FALLBACK_WEAK_CONFIRM",
               " side=", isBuy ? "BUY" : "SELL",
               " totalConfirmScore=", totalConfirmScore,
               " required=", requiredScore);

         return out;
      }

      if(projRR < InpSDMinRRWithoutOppositeZone)
      {
         out.reason = "rr_fallback_rr_too_small";

         Print("[SD_ENTRY_BLOCK] reason=RR_FALLBACK_RR_TOO_SMALL",
               " rr=", DoubleToString(projRR, 2),
               " required=", DoubleToString(InpSDMinRRWithoutOppositeZone, 2));

         return out;
      }
   }

   out.valid = true;
   out.zoneIdx = zoneIdx;
   out.stopLoss = sl;
   out.takeProfit = tp;
   out.projectedRR = projRR;
   out.usedZoneTarget = usedZoneTarget;
   out.targetZoneIdx = targetZoneIdx;
   out.rankScore = z.qualityScore;
   out.interactionType =
      (rejection || candleScore >= InpSDMinCandlePatternScore)
      ? ZONE_INTERACTION_REJECTION
      : ZONE_INTERACTION_BREAKRETEST;
   out.reason = isBuy ? "BUY active Demand retest confirmed"
                     : "SELL active Supply retest confirmed";

   // STEP 10: Mark S/D trend entries as hold-until-trend-end candidates
   int trendNow = GetMarketTrend();

   // Trend-aligned runner uses dynamic role (zones below price act as Demand for buys,
   // zones above price act as Supply for sells in trend direction)
   bool trendAlignedRunner =
      (isBuy && trendNow == 1 && SDZoneActsAsDemand(z, price)) ||
      (!isBuy && trendNow == -1 && SDZoneActsAsSupply(z, price));

   if(InpSDTrendRetestsAreRunners && trendAlignedRunner)
   {
      string roleName = SDDynamicRoleName(z, price);

      out.reason += " | TREND_RUNNER_HOLD";
      Print("[SD_TREND_RUNNER_CANDIDATE] side=", isBuy ? "BUY" : "SELL",
            " zoneId=", z.id,
            " dynamicRole=", roleName,
            " trend=", trendNow,
            " reason=trend_aligned_sd_retest");
   }

   Print("[SD_RETEST_ENTRY] side=", isBuy ? "BUY" : "SELL",
         " zoneId=", z.id,
         " pattern=", z.structuralTag,
         " price=", DoubleToString(price, _Digits),
         " sl=", DoubleToString(out.stopLoss, _Digits),
         " tp=", DoubleToString(out.takeProfit, _Digits),
         " rr=", DoubleToString(out.projectedRR, 2),
         " usedOppositeZoneTP=", usedZoneTarget,
         " reason=", out.reason);

   return out;
}

//+------------------------------------------------------------------+
//| Range strategy helpers                                              |
//+------------------------------------------------------------------+
void GetBestRangeSupportResistance(double price, double atr, ZoneInfo &outSupport, int &outSupportIdx, ZoneInfo &outResistance, int &outResistanceIdx)
{
   outSupportIdx = -1;
   outResistanceIdx = -1;
   double bestSupportScore = -DBL_MAX;
   double bestResistanceScore = -DBL_MAX;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].valid || !g_zoneReg.zones[i].active ||
         g_zoneReg.zones[i].historical || g_zoneReg.zones[i].broken)
         continue;

      if(g_zoneReg.zones[i].strategyRole != ZROLE_RANGE_SUPPORT &&
         g_zoneReg.zones[i].strategyRole != ZROLE_RANGE_RESISTANCE)
         continue;

      double dist = MathAbs(g_zoneReg.zones[i].midPoint - price);
      double distATR = dist / atr;

      if(distATR > 1.5)
         continue;

      if(g_zoneReg.zones[i].strategyRole == ZROLE_RANGE_SUPPORT)
      {
         if(g_zoneReg.zones[i].qualityScore > bestSupportScore)
         {
            bestSupportScore = g_zoneReg.zones[i].qualityScore;
            outSupport = g_zoneReg.zones[i];
            outSupportIdx = i;
         }
      }
      else if(g_zoneReg.zones[i].strategyRole == ZROLE_RANGE_RESISTANCE)
      {
         if(g_zoneReg.zones[i].qualityScore > bestResistanceScore)
         {
            bestResistanceScore = g_zoneReg.zones[i].qualityScore;
            outResistance = g_zoneReg.zones[i];
            outResistanceIdx = i;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Stochastic range mode helper                                        |
//+------------------------------------------------------------------+
bool StochasticRangeConfirmation(const IndicatorState &ind, bool isBuy)
{
   if(!InpUseStochasticForRangeOnly || !InpUseStochasticInRange)
      return true;

   double k1 = 0.0, d1 = 0.0, k2 = 0.0, d2 = 0.0;
   if(!GetStochasticSnapshot(_Symbol, InpEntryTF, InpStochK, InpStochD, InpStochSlowing, k1, d1, k2, d2))
      return false;

   bool pass = false;
   if(isBuy)
      pass = (k1 <= InpStochOversold) || (k2 < d2 && k1 > d1 && k1 < 50.0);
   else
      pass = (k1 >= InpStochOverbought) || (k2 > d2 && k1 < d1 && k1 > 50.0);

   Print("[RANGE_STOCH] side=", (isBuy ? "BUY" : "SELL"),
         " tf=", EnumToString(InpEntryTF),
         " k1=", DoubleToString(k1, 2),
         " d1=", DoubleToString(d1, 2),
         " pass=", pass);

   return pass;
}

//+------------------------------------------------------------------+
//| Breakout/transition behavior helpers                                |
//+------------------------------------------------------------------+
bool IsBreakoutFromRange(const IndicatorState &ind, double atr)
{
   double price = ind.closeArr[1];
   ZoneInfo support, resistance;
   int supportIdx = -1, resistanceIdx = -1;

   GetBestRangeSupportResistance(price, atr, support, supportIdx, resistance, resistanceIdx);

   if(supportIdx >= 0 && resistanceIdx >= 0)
   {
      double rangeWidth = resistance.upperBound - support.lowerBound;
      if(price > resistance.upperBound + atr * 0.2)
         return true;
      if(price < support.lowerBound - atr * 0.2)
         return true;
   }

   return false;
}

bool IsBreakoutRetestZone(const IndicatorState &ind, double atr, ZoneInfo &outZone, int &outIdx)
{
   outIdx = -1;

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      if(!g_zoneReg.zones[i].valid || !g_zoneReg.zones[i].active ||
         g_zoneReg.zones[i].historical || g_zoneReg.zones[i].broken)
         continue;

      if(g_zoneReg.zones[i].strategyRole != ZROLE_BREAKOUT_RETEST)
         continue;

      double dist = MathAbs(g_zoneReg.zones[i].midPoint - ind.closeArr[1]);
      double distATR = dist / atr;

      if(distATR <= 0.3)
      {
         outZone = g_zoneReg.zones[i];
         outIdx = i;
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| CHANNEL BOUNDARY ENTRY HELPERS - DISABLED                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check if price is near channel lower boundary - STUB             |
//+------------------------------------------------------------------+
bool IsNearChannelLowerBoundary(double price, double atr, double maxDistATR = 0.30)
{
   // Channel code removed
   return false;
}

//+------------------------------------------------------------------+
//| Check if price is near channel upper boundary - STUB             |
//+------------------------------------------------------------------+
bool IsNearChannelUpperBoundary(double price, double atr, double maxDistATR = 0.30)
{
   // Channel code removed
   return false;
}

//+------------------------------------------------------------------+
//| Check for bullish channel entry - STUB                           |
//+------------------------------------------------------------------+
bool HasBullishChannelEntryConfirmation(const IndicatorState &ind, double atr)
{
   // Channel code removed
   return false;
}

//+------------------------------------------------------------------+
//| Check for bearish channel entry - STUB                           |
//+------------------------------------------------------------------+
bool HasBearishChannelEntryConfirmation(const IndicatorState &ind, double atr)
{
   // Channel code removed
   return false;
}

//+------------------------------------------------------------------+
//| D1 Zone Retest/Flip Entry Helpers                                 |
//+------------------------------------------------------------------+
bool HasBullishRetestConfirmation(const IndicatorState &ind, double atr)
{
   if(atr <= 0.0) return false;
   bool bullEngulfing = IsBullishEngulfing(_Symbol, g_indicatorTF, 1);
   bool bullRejection = IsBullishWickRejection(_Symbol, g_indicatorTF, 1, 0.40, 0.45, true);
   bool bullContinuation = IsTrendBullishContinuation(_Symbol, g_indicatorTF, 1);
   return (bullEngulfing || bullRejection || bullContinuation);
}

bool HasBearishRetestConfirmation(const IndicatorState &ind, double atr)
{
   if(atr <= 0.0) return false;
   bool bearEngulfing = IsBearishEngulfing(_Symbol, g_indicatorTF, 1);
   bool bearRejection = IsBearishWickRejection(_Symbol, g_indicatorTF, 1, 0.40, 0.45, true);
   bool bearContinuation = IsTrendBearishContinuation(_Symbol, g_indicatorTF, 1);
   return (bearEngulfing || bearRejection || bearContinuation);
}

//+------------------------------------------------------------------+
//| RANGE BOUNDARY ENTRY HELPERS                                      |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Check for bullish range entry at support boundary                |
//+------------------------------------------------------------------+
bool HasBullishRangeEntryConfirmation(const IndicatorState &ind, 
                                      const RangeBoundaryCandidate &support,
                                      double atr)
{
   if(!support.valid || !support.isDemand)
      return false;
   
   double price = ind.closeArr[1];
   double dist = MathAbs(price - support.mid);
   
   if(dist > atr * 0.80)
      return false;
   
   bool doubleBottom = IsDoubleBottom(ind.lowArr, ind.highArr, ind.closeArr, ind.openArr, atr);
   bool bullRejection = IsBullishWickRejection(_Symbol, g_indicatorTF, 1, 0.40, 0.45, true);
   
   if(doubleBottom || bullRejection)
   {
      Print("[RANGE_ENTRY_CHECK] side=BUY boundary=SUPPORT doubleBottom=", doubleBottom, 
            " rejection=", bullRejection);
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Check for bearish range entry at resistance boundary             |
//+------------------------------------------------------------------+
bool HasBearishRangeEntryConfirmation(const IndicatorState &ind,
                                      const RangeBoundaryCandidate &resistance,
                                      double atr)
{
   if(!resistance.valid || resistance.isDemand)
      return false;
   
   double price = ind.closeArr[1];
   double dist = MathAbs(price - resistance.mid);
   
   if(dist > atr * 0.80)
      return false;
   
   bool doubleTop = IsDoubleTop(ind.highArr, ind.lowArr, ind.closeArr, ind.openArr, atr);
   bool bearRejection = IsBearishWickRejection(_Symbol, g_indicatorTF, 1, 0.40, 0.45, true);
   
   if(doubleTop || bearRejection)
   {
      Print("[RANGE_ENTRY_CHECK] side=SELL boundary=RESISTANCE doubleTop=", doubleTop,
            " rejection=", bearRejection);
      return true;
   }
   
   return false;
}

// Channel code removed per user request

#endif // SIGNAL_ENGINE_MQH

