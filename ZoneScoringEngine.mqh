//+------------------------------------------------------------------+
//|                                         ZoneScoringEngine.mqh   |
//|  Rules-based key-zone memory + entry scoring system             |
//|  v2.1 — Uses ZoneManager v7.1 unified g_zoneReg registry       |
//|  No reference-to-array-element patterns (MQL5 safe)             |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef ZONE_SCORING_ENGINE_MQH
#define ZONE_SCORING_ENGINE_MQH

#define ZSE_MAX_HIST_ZONES   5
#define ZSE_MAX_FRESH_ZONES  3

//+------------------------------------------------------------------+
//| A single scoreable zone                                          |
//+------------------------------------------------------------------+
struct ScoredZone
{
   double         upper;
   double         lower;
   double         mid;
   ENUM_ZONE_TYPE type;
   int            retestCount;
   int            ageInBars;
   bool           active;
   bool           partiallyBroken;
   bool           confluent;
   bool           isKeyZone;
   bool           isFlipZone;
   bool           isRefinement;
   int            zoneRegIdx;
   double         score;
   bool           valid;
   double         freshness;
   bool           hasRejection;
   bool           isBreakoutOrigin;
};

//+------------------------------------------------------------------+
//| Dual-bank zone storage                                           |
//+------------------------------------------------------------------+
struct ZoneScoreBank
{
   ScoredZone hist[ZSE_MAX_HIST_ZONES];
   ScoredZone fresh[ZSE_MAX_FRESH_ZONES];
   int        histCount;
   int        freshCount;
};

ZoneScoreBank g_zseBank;

//+------------------------------------------------------------------+
//| Initialise the bank                                              |
//+------------------------------------------------------------------+
void InitZoneScoreBank()
{
   g_zseBank.histCount  = 0;
   g_zseBank.freshCount = 0;
   for(int i = 0; i < ZSE_MAX_HIST_ZONES;  i++) g_zseBank.hist[i].active  = false;
   for(int i = 0; i < ZSE_MAX_FRESH_ZONES; i++) g_zseBank.fresh[i].active = false;
}

//+------------------------------------------------------------------+
//| Fill a ScoredZone from g_zoneReg index                          |
//+------------------------------------------------------------------+
void FillScoredZone(ScoredZone &sz, int regIdx)
{
   ZoneInfo z = g_zoneReg.zones[regIdx];
   sz.upper          = z.upperBound;
   sz.lower          = z.lowerBound;
   sz.mid            = z.midPoint;
   sz.type           = z.type;
   sz.retestCount    = z.retestCount;
   sz.ageInBars      = z.ageInBars;
   sz.active         = true;
   sz.partiallyBroken = z.broken;
   sz.confluent      = false;
   sz.isKeyZone      = z.protectedKeyZone;
   sz.isFlipZone     = z.isFlipZone;
   sz.isRefinement   = z.isRefinement;
   sz.zoneRegIdx     = regIdx;
   sz.score          = z.score;
   sz.valid          = z.valid;
   sz.freshness      = z.freshness;
   sz.hasRejection   = z.hasRejection;
   sz.isBreakoutOrigin = z.isBreakoutOrigin;
}

//+------------------------------------------------------------------+
//| Build historical zone bank from g_zoneReg                       |
//+------------------------------------------------------------------+
void BuildHistoricalZones(double currentPrice, int maxRetests, int lifetimeBars)
{
   g_zseBank.histCount = 0;
   for(int i = 0; i < ZSE_MAX_HIST_ZONES; i++) g_zseBank.hist[i].active = false;

   double bestStr[ZSE_MAX_HIST_ZONES];
   int    bestIdx[ZSE_MAX_HIST_ZONES];
   int    slots = 0;
   for(int s = 0; s < ZSE_MAX_HIST_ZONES; s++) { bestStr[s] = -1.0; bestIdx[s] = -1; }

   for(int i = 0; i < g_zoneReg.count; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.historical && !z.protectedKeyZone) continue;
      if(z.type == ZONE_SUPPORT_MINOR || z.type == ZONE_RESISTANCE_MINOR ||
         z.type == ZONE_EMA_CONFLUENCE) continue;
      if(z.ageInBars > lifetimeBars || z.retestCount >= maxRetests) continue;

      double str = z.strength + (z.protectedKeyZone ? 0.1 : 0.0);

      if(slots < ZSE_MAX_HIST_ZONES)
      {
         bestStr[slots] = str;
         bestIdx[slots] = i;
         slots++;
         for(int k = slots-1; k > 0 && bestStr[k] > bestStr[k-1]; k--)
         {
            double t = bestStr[k]; bestStr[k] = bestStr[k-1]; bestStr[k-1] = t;
            int    u = bestIdx[k]; bestIdx[k] = bestIdx[k-1]; bestIdx[k-1] = u;
         }
      }
      else if(str > bestStr[slots-1])
      {
         bestStr[slots-1] = str;
         bestIdx[slots-1] = i;
         for(int k = slots-1; k > 0 && bestStr[k] > bestStr[k-1]; k--)
         {
            double t = bestStr[k]; bestStr[k] = bestStr[k-1]; bestStr[k-1] = t;
            int    u = bestIdx[k]; bestIdx[k] = bestIdx[k-1]; bestIdx[k-1] = u;
         }
      }
   }

   for(int s = 0; s < slots && g_zseBank.histCount < ZSE_MAX_HIST_ZONES; s++)
   {
      if(bestIdx[s] < 0) continue;
      FillScoredZone(g_zseBank.hist[g_zseBank.histCount], bestIdx[s]);
      g_zseBank.histCount++;
   }

   for(int i = 0; i < g_zoneReg.count && g_zseBank.histCount < ZSE_MAX_HIST_ZONES; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.historical) continue;
      if(z.type == ZONE_SUPPORT_MINOR || z.type == ZONE_RESISTANCE_MINOR ||
         z.type == ZONE_EMA_CONFLUENCE) continue;
      if(z.ageInBars > lifetimeBars || z.retestCount >= maxRetests) continue;
      bool dup = false;
      for(int h = 0; h < g_zseBank.histCount && !dup; h++)
         if(g_zseBank.hist[h].zoneRegIdx == i) dup = true;
      if(dup) continue;
      FillScoredZone(g_zseBank.hist[g_zseBank.histCount], i);
      g_zseBank.histCount++;
   }
}

//+------------------------------------------------------------------+
//| Build fresh zones from active g_zoneReg entries                  |
//+------------------------------------------------------------------+
void BuildFreshZones(double currentPrice, const SymbolProfile &prof, int freshLookback = 30)
{
   g_zseBank.freshCount = 0;
   for(int i = 0; i < ZSE_MAX_FRESH_ZONES; i++) g_zseBank.fresh[i].active = false;

   for(int i = 0; i < g_zoneReg.count && g_zseBank.freshCount < ZSE_MAX_FRESH_ZONES; i++)
   {
      ZoneInfo z = g_zoneReg.zones[i];
      if(!z.active || z.historical) continue;
      if(z.ageInBars > freshLookback) continue;
      bool dup = false;
      for(int h = 0; h < g_zseBank.histCount && !dup; h++)
         if(g_zseBank.hist[h].zoneRegIdx == i) dup = true;
      if(dup) continue;
      FillScoredZone(g_zseBank.fresh[g_zseBank.freshCount], i);
      g_zseBank.freshCount++;
   }
}

//+------------------------------------------------------------------+
//| Add previous-day high/low as structural reference zones          |
//+------------------------------------------------------------------+
void AddPrevDayZones(double currentPrice, const SymbolProfile &prof)
{
   if(g_zseBank.histCount >= ZSE_MAX_HIST_ZONES) return;
   double hi[], lo[];
   if(CopyHigh(_Symbol, PERIOD_D1, 1, 1, hi) < 1) return;
   if(CopyLow (_Symbol, PERIOD_D1, 1, 1, lo) < 1) return;
   double tol = prof.defaultSLBufferPoints * prof.point * 2.0;

   if(hi[0] > currentPrice && g_zseBank.histCount < ZSE_MAX_HIST_ZONES)
   {
      ScoredZone sz;
      sz.upper = hi[0]+tol; sz.lower = hi[0]-tol; sz.mid = hi[0];
      sz.type = ZONE_RESISTANCE_MAJOR; sz.retestCount = 1; sz.ageInBars = 1;
      sz.active = true; sz.partiallyBroken = false; sz.confluent = false;
      sz.isKeyZone = false; sz.isFlipZone = false; sz.isRefinement = false;
      sz.zoneRegIdx = -1;
      g_zseBank.hist[g_zseBank.histCount++] = sz;
   }
   if(lo[0] < currentPrice && g_zseBank.histCount < ZSE_MAX_HIST_ZONES)
   {
      ScoredZone sz;
      sz.upper = lo[0]+tol; sz.lower = lo[0]-tol; sz.mid = lo[0];
      sz.type = ZONE_SUPPORT_MAJOR; sz.retestCount = 1; sz.ageInBars = 1;
      sz.active = true; sz.partiallyBroken = false; sz.confluent = false;
      sz.isKeyZone = false; sz.isFlipZone = false; sz.isRefinement = false;
      sz.zoneRegIdx = -1;
      g_zseBank.hist[g_zseBank.histCount++] = sz;
   }
}

//+------------------------------------------------------------------+
//| Cross-mark confluent zones                                       |
//+------------------------------------------------------------------+
void MarkConfluentZones(double atrVal, double confluenceATRMult)
{
   double threshold = MathMax(atrVal * confluenceATRMult, 0.0001);
   for(int f = 0; f < g_zseBank.freshCount; f++)
   {
      if(!g_zseBank.fresh[f].active) continue;
      for(int h = 0; h < g_zseBank.histCount; h++)
      {
         if(!g_zseBank.hist[h].active) continue;
         if(MathAbs(g_zseBank.fresh[f].mid - g_zseBank.hist[h].mid) <= threshold)
         {
            g_zseBank.fresh[f].confluent = true;
            g_zseBank.hist[h].confluent  = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Full zone bank refresh                                           |
//+------------------------------------------------------------------+
void RefreshZoneScoreBank(double currentPrice,
                          const SymbolProfile &prof,
                          double atrVal,
                          int    maxRetests,
                          int    lifetimeBars,
                          double confluenceATRMult)
{
   BuildHistoricalZones(currentPrice, maxRetests, lifetimeBars);
   BuildFreshZones(currentPrice, prof);
   AddPrevDayZones(currentPrice, prof);
   MarkConfluentZones(atrVal, confluenceATRMult);
   Print("ZSCORE BANK: hist=", g_zseBank.histCount, " fresh=", g_zseBank.freshCount);
}

//+------------------------------------------------------------------+
//| Find best historical zone for a BUY or SELL setup               |
//+------------------------------------------------------------------+
int FindBestHistZone(bool isBuy, double currentPrice, double atrVal,
                     bool &inZone, bool &freshConfluent,
                     int &retestCount, bool &partiallyBroken)
{
   inZone = false; freshConfluent = false; retestCount = 0; partiallyBroken = false;
   int    bestIdx  = -1;
   double bestDist = 999999.0;

   for(int i = 0; i < g_zseBank.histCount; i++)
   {
      if(!g_zseBank.hist[i].active) continue;
      bool isSupportType = (g_zseBank.hist[i].type == ZONE_SUPPORT_MAJOR ||
                            g_zseBank.hist[i].type == ZONE_DEMAND);
      bool isResistType  = (g_zseBank.hist[i].type == ZONE_RESISTANCE_MAJOR ||
                            g_zseBank.hist[i].type == ZONE_SUPPLY);
      if( isBuy && !isSupportType) continue;
      if(!isBuy && !isResistType)  continue;
      double dist = isBuy ? (currentPrice - g_zseBank.hist[i].mid)
                          : (g_zseBank.hist[i].mid - currentPrice);
      if(dist < 0 || dist > atrVal * 2.0) continue;
      if(dist < bestDist)
      {
         bestDist        = dist;
         bestIdx         = i;
         inZone          = (currentPrice >= g_zseBank.hist[i].lower &&
                            currentPrice <= g_zseBank.hist[i].upper);
         freshConfluent  = g_zseBank.hist[i].confluent;
         retestCount     = g_zseBank.hist[i].retestCount;
         partiallyBroken = g_zseBank.hist[i].partiallyBroken;
      }
   }
   return bestIdx;
}

//+------------------------------------------------------------------+
//| Score a BUY or SELL setup                                        |
//+------------------------------------------------------------------+
int ScoreSetup(bool   isBuy,
               double currentPrice,
               double atrVal,
               bool   htfTrendAligned,
               bool   candleConfirmOK,
               string &scoreDetail)
{
   scoreDetail = "";
   int score = 0;

   bool inZone = false, freshConfluent = false, zonePBroken = false;
   int  zoneRetests = 0;
   int histIdx = FindBestHistZone(isBuy, currentPrice, atrVal,
                                   inZone, freshConfluent, zoneRetests, zonePBroken);

   if(histIdx >= 0)
   {
      if(inZone) { score += 2; scoreDetail += "+2(inHistZone) "; }
      else       { score += 1; scoreDetail += "+1(nearHistZone) "; }
      if(g_zseBank.hist[histIdx].isKeyZone)    { score += 1; scoreDetail += "+1(keyZone) "; }
      if(g_zseBank.hist[histIdx].isFlipZone)   { score += 1; scoreDetail += "+1(flipZone) "; }
      if(g_zseBank.hist[histIdx].isRefinement) { score += 1; scoreDetail += "+1(refinement) "; }
   }

   if(freshConfluent)      { score += 2; scoreDetail += "+2(confluence) "; }
   if(htfTrendAligned)     { score += 1; scoreDetail += "+1(htfTrend) "; }
   if(candleConfirmOK)      { score += 1; scoreDetail += "+1(candle) "; }

   if(IsPriceRetestingHistoricalKeyLevel(currentPrice, atrVal))
      { score += 1; scoreDetail += "+1(histKeyRetest) "; }

   if(histIdx >= 0 && g_zseBank.hist[histIdx].hasRejection)
      { score += 1; scoreDetail += "+1(rejection) "; }
   if(histIdx >= 0 && g_zseBank.hist[histIdx].isBreakoutOrigin)
      { score += 1; scoreDetail += "+1(breakoutOrigin) "; }
   if(histIdx >= 0 && g_zseBank.hist[histIdx].freshness >= 0.5)
      { score += 1; scoreDetail += "+1(fresh) "; }
   if(histIdx >= 0 && !g_zseBank.hist[histIdx].valid)
      { score -= 2; scoreDetail += "-2(invalidZone) "; }

   if(zoneRetests >= 3) { score -= 2; scoreDetail += "-2(overtested) "; }
   if(zonePBroken)      { score -= 3; scoreDetail += "-3(partialBreak) "; }

   return score;
}

//+------------------------------------------------------------------+
//| PATCH 15 — Strong-zone scoring helpers                             |
//+------------------------------------------------------------------+
double ScoreDepartureStrength(const ZoneInfo &z, double atr)
{
   if(atr <= 0.0) return 0.0;

   if(z.departureATR >= 2.2) return 2.0;
   if(z.departureATR >= 1.5) return 1.5;
   if(z.departureATR >= 1.0) return 1.0;
   if(z.departureATR >= 0.7) return 0.5;
   return 0.0;
}

double ScoreStructureImpact(const ZoneInfo &z)
{
   double s = 0.0;

   if(z.structuralTag == "HL" || z.structuralTag == "LH")
      s += 1.2;

   if(z.structuralTag == "HH" || z.structuralTag == "LL")
      s += 1.0;

   if(z.structuralAnchor)
      s += 0.8;

   if(z.protectedKeyZone)
      s += 0.5;

   if(z.continuationEligible)
      s += 0.5;

   return MathMin(s, 2.0);
}

double ScoreFreshness(const ZoneInfo &z)
{
   int touches = MathMax(z.touchCountTotal, z.cleanTouchCount);

   if(touches <= 1) return 1.0;
   if(touches == 2) return 0.4;
   if(touches == 3) return -0.6;
   return -1.2;
}

double ScoreHTFVisibility(const ZoneInfo &z)
{
   double s = 0.0;

   if(z.sourceTF == PERIOD_D1) return 1.0;
   if(z.sourceTF == PERIOD_H4) s += 0.6;
   if(z.structuralAnchor) s += 0.25;
   if(z.protectedKeyZone) s += 0.15;

   return MathMin(s, 1.0);
}

double ScoreCleanShape(const ZoneInfo &z, double atr)
{
   if(atr <= 0.0) return 0.0;

   double widthATR = MathAbs(z.upperBound - z.lowerBound) / atr;

   if(widthATR <= 0.35) return 1.0;
   if(widthATR <= 0.60) return 0.6;
   if(widthATR <= 0.90) return 0.2;
   return -0.5;
}

double ScoreRejectionQuality(const ZoneInfo &z)
{
   double s = 0.0;

   if(z.rejections >= 2) s += 1.0;
   else if(z.rejections == 1) s += 0.5;

   if(z.isFlipZone) s += 0.25;

   return MathMin(s, 1.0);
}

double ScoreConfluence(const ZoneInfo &z, int trendBias)
{
   double s = 0.0;

   if(z.structuralAnchor) s += 0.35;
   if(z.protectedKeyZone) s += 0.25;
   if(z.isFlipZone) s += 0.20;
   if(z.continuationEligible) s += 0.20;

   if(trendBias == 1 && (z.structuralTag == "HL" || z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_DEMAND))
      s += 0.25;

   if(trendBias == -1 && (z.structuralTag == "LH" || z.type == ZONE_RESISTANCE_MAJOR || z.type == ZONE_SUPPLY))
      s += 0.25;

   return MathMin(s, 1.0);
}

bool UsePhotoZoneFilterEffective()
{
   return (InpForcePhotoStyleZonePreset ? true : InpUsePhotoLikeZoneFilter);
}

double ZoneMajorThresholdEffective()
{
   return (InpForcePhotoStyleZonePreset ? InpPhotoZoneMajorScoreThreshold : ZoneMajorScoreThreshold);
}

double ZoneWeakThresholdEffective()
{
   return (InpForcePhotoStyleZonePreset ? InpPhotoZoneWeakRejectThreshold : ZoneWeakRejectThreshold);
}

int ZoneMinimumChecklistHitsEffective()
{
   return (InpForcePhotoStyleZonePreset ? InpPhotoZoneMinimumChecklistHits : InpZoneMinimumChecklistHits);
}

double ComputeStrictZoneQualityScore(ZoneInfo &z, double atr, int trendBias)
{
   double departure  = ScoreDepartureStrength(z, atr);
   double structure  = ScoreStructureImpact(z);
   double freshness  = ScoreFreshness(z);
   double htf        = ScoreHTFVisibility(z);
   double cleanShape = ScoreCleanShape(z, atr);
   double rejection  = ScoreRejectionQuality(z);
   double confluence = ScoreConfluence(z, trendBias);

   z.structureImpactScore  = structure;
   z.freshnessScore        = freshness;
   z.htfVisibilityScore    = htf;
   z.cleanShapeScore       = cleanShape;
   z.rejectionQualityScore = rejection;
   z.confluenceScore       = confluence;

   double swingOrigin = (z.structuralTag != "" || z.structuralAnchor) ? 1.0 : 0.0;

   double total =
      departure +
      structure +
      swingOrigin +
      freshness +
      htf +
      cleanShape +
      rejection +
      confluence;

   int checklistHits = 0;

   // 1. Strong move away / impulsive departure
   bool strongMoveAway =
      (z.departureATR >= 1.0 ||
       departure >= 1.0 ||
       z.reactionScore >= 1.0 ||
       z.hasRejection ||
       rejection >= 0.75);

   if(strongMoveAway)
      checklistHits++;

   // 2. Break of structure / market impact
   bool breakOfStructure =
      (structure >= 1.0 ||
       z.isBreakoutOrigin ||
       z.continuationEligible ||
       z.breakRetestReady ||
       z.structuralTag == "HH" ||
       z.structuralTag == "LL");

   if(breakOfStructure)
      checklistHits++;

   // 3. Clear swing point
   bool clearSwingPoint =
      (z.structuralAnchor ||
       z.structuralTag == "HL" ||
       z.structuralTag == "LH" ||
       z.structuralTag == "HH" ||
       z.structuralTag == "LL" ||
       z.sourceSwingTime > 0);

   if(clearSwingPoint)
      checklistHits++;

   // 4. Fresh zone, not over-tested
   int touches = MathMax(z.touchCountTotal, z.cleanTouchCount);
   bool freshZone =
      (touches <= 2 &&
       freshness >= 0.40 &&
       !z.broken &&
       z.breakConfirmCount <= 0);

   if(freshZone)
      checklistHits++;

   // 5. Confluence
   bool hasConfluence =
      (htf >= 0.60 ||
       confluence >= 0.35 ||
       z.majorTFZone ||
       z.protectedKeyZone ||
       z.isFlipZone ||
       z.isRetestOfHistoricalZone ||
       z.continuationEligible);

   if(hasConfluence)
      checklistHits++;

   z.qualityChecklistHits = checklistHits;
   z.qualityScore = total;

   z.majorQualified =
      (checklistHits >= ZoneMinimumChecklistHitsEffective() &&
       total >= ZoneMajorThresholdEffective());

   return total;
}

bool IsZoneWeakByChecklist(const ZoneInfo &z)
{
   if(UsePhotoZoneFilterEffective())
      return (z.qualityChecklistHits < ZoneMinimumChecklistHitsEffective() ||
              z.qualityScore < ZoneWeakThresholdEffective());

   return (z.qualityScore < ZoneWeakThresholdEffective());
}

//+------------------------------------------------------------------+
//| Score trend continuation zone                                      |
//+------------------------------------------------------------------+
double ScoreTrendContinuationZone(const ZoneInfo &z, int trendBias)
{
   double s = z.qualityScore;

   if(trendBias == 1)
   {
      if(z.structuralTag == "HL") s += 2.0;
      if(z.continuationEligible) s += 1.0;
      if(z.type == ZONE_SUPPORT_MAJOR || z.type == ZONE_DEMAND) s += 0.8;
   }
   else if(trendBias == -1)
   {
      if(z.structuralTag == "LH") s += 2.0;
      if(z.continuationEligible) s += 1.0;
      if(z.type == ZONE_RESISTANCE_MAJOR || z.type == ZONE_SUPPLY) s += 0.8;
   }

   return s;
}

//+------------------------------------------------------------------+
//| Score exhaustion zone                                              |
//+------------------------------------------------------------------+
double ScoreExhaustionZone(const ZoneInfo &z, int trendBias)
{
   double s = z.qualityScore;

   if(trendBias == 1)
   {
      if(z.structuralTag == "HH") s += 1.5;
      if(z.rejections >= 2) s += 1.0;
      if(z.isFlipZone) s += 0.5;
   }
   else if(trendBias == -1)
   {
      if(z.structuralTag == "LL") s += 1.5;
      if(z.rejections >= 2) s += 1.0;
      if(z.isFlipZone) s += 0.5;
   }

   return s;
}

#endif // ZONE_SCORING_ENGINE_MQH
