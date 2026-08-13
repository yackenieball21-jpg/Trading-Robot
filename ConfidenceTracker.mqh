//+------------------------------------------------------------------+
//|                                            ConfidenceTracker.mqh |
//|  Tracks trade confidence scores vs actual outcomes               |
//|  Buckets: <60, 60-69, 70-79, 80+                                |
//|  Prints summary at shutdown for backtest analysis                |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef CONFIDENCE_TRACKER_MQH
#define CONFIDENCE_TRACKER_MQH

#define MAX_CONF_ENTRIES 200
#define CONF_BUCKETS     4

//+------------------------------------------------------------------+
//| Per-trade entry snapshot — kept until close                      |
//+------------------------------------------------------------------+
struct ConfidenceEntryLog
{
   ulong    positionId;
   ulong    ticket;
   string   symbol;
   string   direction;
   datetime entryTime;
   double   confidence;
   string   setupType;
   string   regime;
   string   zoneState;
   double   entryPrice;
   double   sl;
   bool     active;
};

//+------------------------------------------------------------------+
//| Aggregate stats per confidence bucket                            |
//+------------------------------------------------------------------+
struct ConfidenceBucketStats
{
   int      trades;
   int      wins;
   int      losses;
   double   grossProfit;
   double   grossLoss;
   double   totalPnl;
};

// Globals
ConfidenceEntryLog   g_confEntries[];
int                  g_confEntryCount = 0;
ConfidenceBucketStats g_confBuckets[CONF_BUCKETS];

//+------------------------------------------------------------------+
//| Bucket helpers                                                    |
//+------------------------------------------------------------------+
int GetConfBucketIndex(double confidence)
{
   if(confidence < 60.0) return 0;
   if(confidence < 70.0) return 1;
   if(confidence < 80.0) return 2;
   return 3;
}

string GetConfBucketLabel(int idx)
{
   switch(idx)
   {
      case 0: return "<60";
      case 1: return "60-69";
      case 2: return "70-79";
      case 3: return "80+";
   }
   return "?";
}

//+------------------------------------------------------------------+
//| Compute trade confidence score (0-100) from entry signals        |
//| Base 50 (passed all hard gates) + bonuses for each confirmation  |
//+------------------------------------------------------------------+
// Pattern-family bonus: rewards patterns that match the current market state
// trendCont   = trend continuation pattern in trend state
// rangeRev    = range reversal pattern in range state
// breakoutPat = breakout pattern in consolidation state
// mismatch    = pattern used in wrong state (penalty)
double GetPatternFamilyBonus(bool trendCont, bool rangeRev, bool breakoutPat)
{
   if(trendCont)    return 8.0;   // strong match: trend pattern in trend
   if(rangeRev)     return 6.0;   // good match: reversal at range edge
   if(breakoutPat)  return 5.0;   // decent match: breakout from compression
   return 0.0;                    // no pattern-family bonus
}

double ComputeTradeConfidence(bool emaBias, bool /*reserved1*/,
                               bool candlePattern, bool /*reserved2*/,
                               bool /*reserved3*/, bool /*reserved4*/,
                               double aiLearningConf,
                               double patternFamilyBonus = 0.0)
{
   // Zone-sweep confidence model: EMA50 bias + candle confirmation + AI learning + pattern family
   double score = 50.0;

   if(emaBias)            score += 25.0;   // EMA50 direction
   if(candlePattern)      score += 25.0;   // candle confirmation

   // Pattern-family match bonus (0-8 pts)
   score += patternFamilyBonus;

   // AI learning: scale [-0.35,+0.25] → roughly [-10,+8]
   score += aiLearningConf * 30.0;

   if(score < 0.0)   score = 0.0;
   if(score > 100.0) score = 100.0;
   return score;
}

//+------------------------------------------------------------------+
//| Initialize tracker                                                |
//+------------------------------------------------------------------+
void InitConfidenceTracker()
{
   g_confEntryCount = 0;
   ArrayResize(g_confEntries, 0);
   for(int i = 0; i < CONF_BUCKETS; i++)
   {
      g_confBuckets[i].trades      = 0;
      g_confBuckets[i].wins        = 0;
      g_confBuckets[i].losses      = 0;
      g_confBuckets[i].grossProfit = 0.0;
      g_confBuckets[i].grossLoss   = 0.0;
      g_confBuckets[i].totalPnl    = 0.0;
   }
   Print("CONFIDENCE TRACKER: Initialized");
}

//+------------------------------------------------------------------+
//| Log entry — called after successful trade open                   |
//+------------------------------------------------------------------+
void LogConfidenceEntry(ulong positionId, ulong ticket, string direction,
                        double confidence, string setupType, string regime,
                        string zoneState, double entryPrice, double sl)
{
   // Find inactive slot or append
   int idx = -1;
   for(int i = 0; i < g_confEntryCount; i++)
   {
      if(!g_confEntries[i].active) { idx = i; break; }
   }
   if(idx < 0)
   {
      if(g_confEntryCount >= MAX_CONF_ENTRIES)
         idx = 0;  // overwrite oldest
      else
      {
         idx = g_confEntryCount++;
         ArrayResize(g_confEntries, g_confEntryCount);
      }
   }

   g_confEntries[idx].positionId = positionId;
   g_confEntries[idx].ticket     = ticket;
   g_confEntries[idx].symbol     = _Symbol;
   g_confEntries[idx].direction  = direction;
   g_confEntries[idx].entryTime  = TimeCurrent();
   g_confEntries[idx].confidence = confidence;
   g_confEntries[idx].setupType  = setupType;
   g_confEntries[idx].regime     = regime;
   g_confEntries[idx].zoneState  = zoneState;
   g_confEntries[idx].entryPrice = entryPrice;
   g_confEntries[idx].sl         = sl;
   g_confEntries[idx].active     = true;

   int bucket = GetConfBucketIndex(confidence);
   Print("CONF ENTRY: ticket=", ticket, " ", direction,
         " conf=", DoubleToString(confidence, 1),
         " bucket=[", GetConfBucketLabel(bucket), "]",
         " setup=", setupType,
         " regime=", regime,
         " zone=", zoneState);
}

//+------------------------------------------------------------------+
//| Log outcome — called when trade closes                           |
//+------------------------------------------------------------------+
void LogConfidenceOutcome(ulong positionId, double netPnl, double closePrice)
{
   for(int i = 0; i < g_confEntryCount; i++)
   {
      if(g_confEntries[i].active && g_confEntries[i].positionId == positionId)
      {
         double conf = g_confEntries[i].confidence;
         bool isWin  = (netPnl > 0);

         // R-multiple from price movement
         double riskDist = MathAbs(g_confEntries[i].entryPrice - g_confEntries[i].sl);
         double rMultiple = 0.0;
         if(riskDist > 0)
         {
            if(g_confEntries[i].direction == "BUY")
               rMultiple = (closePrice - g_confEntries[i].entryPrice) / riskDist;
            else
               rMultiple = (g_confEntries[i].entryPrice - closePrice) / riskDist;
         }

         // Update bucket stats
         int bucket = GetConfBucketIndex(conf);
         g_confBuckets[bucket].trades++;
         g_confBuckets[bucket].totalPnl += netPnl;
         if(isWin)
         {
            g_confBuckets[bucket].wins++;
            g_confBuckets[bucket].grossProfit += netPnl;
         }
         else
         {
            g_confBuckets[bucket].losses++;
            g_confBuckets[bucket].grossLoss += netPnl;
         }

         Print("CONF CLOSE: ticket=", g_confEntries[i].ticket,
               " ", g_confEntries[i].direction,
               " conf=", DoubleToString(conf, 1),
               " result=", (isWin ? "WIN" : "LOSS"),
               " pnl=", DoubleToString(netPnl, 2),
               " R=", DoubleToString(rMultiple, 2),
               " bucket=[", GetConfBucketLabel(bucket), "]");

         g_confEntries[i].active = false;
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Print bucket summary — called at shutdown                        |
//+------------------------------------------------------------------+
void PrintConfidenceSummary()
{
   Print("========================================");
   Print("CONFIDENCE BUCKET SUMMARY for ", _Symbol);
   Print("========================================");

   int totalTrades = 0;
   for(int b = 0; b < CONF_BUCKETS; b++)
      totalTrades += g_confBuckets[b].trades;

   if(totalTrades == 0)
   {
      Print("  No confidence-tracked trades recorded");
      Print("========================================");
      return;
   }

   for(int b = 0; b < CONF_BUCKETS; b++)
   {
      int t = g_confBuckets[b].trades;
      if(t == 0)
      {
         Print("  [", GetConfBucketLabel(b), "] — no trades");
         continue;
      }

      double wr = (double)g_confBuckets[b].wins / t;
      double pf = (MathAbs(g_confBuckets[b].grossLoss) > 0)
                ? g_confBuckets[b].grossProfit / MathAbs(g_confBuckets[b].grossLoss) : 0;
      double avgPnl = g_confBuckets[b].totalPnl / t;

      Print("  [", GetConfBucketLabel(b), "]",
            " trades=", t,
            " W=", g_confBuckets[b].wins,
            " L=", g_confBuckets[b].losses,
            " WR=", DoubleToString(wr * 100, 1), "%",
            " PF=", DoubleToString(pf, 2),
            " avgPnl=", DoubleToString(avgPnl, 2),
            " net=", DoubleToString(g_confBuckets[b].totalPnl, 2));
   }

   // Overall
   double overallWR = 0, overallPF = 0, totalNet = 0;
   int totalW = 0, totalL = 0;
   double totalGP = 0, totalGL = 0;
   for(int b = 0; b < CONF_BUCKETS; b++)
   {
      totalW  += g_confBuckets[b].wins;
      totalL  += g_confBuckets[b].losses;
      totalGP += g_confBuckets[b].grossProfit;
      totalGL += g_confBuckets[b].grossLoss;
      totalNet += g_confBuckets[b].totalPnl;
   }
   overallWR = (totalTrades > 0) ? (double)totalW / totalTrades : 0;
   overallPF = (MathAbs(totalGL) > 0) ? totalGP / MathAbs(totalGL) : 0;

   Print("  TOTAL: ", totalTrades, " trades",
         " W=", totalW, " L=", totalL,
         " WR=", DoubleToString(overallWR * 100, 1), "%",
         " PF=", DoubleToString(overallPF, 2),
         " net=", DoubleToString(totalNet, 2));

   // Verdict: does high confidence outperform?
   int hiIdx = 3;  // 80+ bucket
   int loIdx = 0;  // <60 bucket
   if(g_confBuckets[hiIdx].trades >= 3 && g_confBuckets[loIdx].trades >= 3)
   {
      double hiWR = (double)g_confBuckets[hiIdx].wins / g_confBuckets[hiIdx].trades;
      double loWR = (double)g_confBuckets[loIdx].wins / g_confBuckets[loIdx].trades;
      if(hiWR > loWR + 0.10)
         Print("  VERDICT: High-confidence trades outperform low-confidence by ",
               DoubleToString((hiWR - loWR) * 100, 1), " pp — confidence scoring is effective");
      else if(loWR > hiWR + 0.10)
         Print("  VERDICT: Low-confidence trades outperform — review scoring model");
      else
         Print("  VERDICT: No significant difference between confidence levels");
   }
   else
      Print("  VERDICT: Insufficient data for high/low comparison (need 3+ trades per bucket)");

   Print("========================================");
}

//+------------------------------------------------------------------+
//| Shutdown tracker                                                  |
//+------------------------------------------------------------------+
void ShutdownConfidenceTracker()
{
   PrintConfidenceSummary();
}

//+==================================================================+
//| FEEDBACK LOOP — Confidence → Entry Adjustment                    |
//| Returns a multiplier [0.70 .. 1.15] applied to trade confidence  |
//| based on historical win-rate for that confidence bucket.         |
//| Call this just before deciding whether to take a trade.          |
//+==================================================================+

//+------------------------------------------------------------------+
//| Minimum trades in a bucket before feedback is applied            |
//+------------------------------------------------------------------+
#define CONF_FEEDBACK_MIN_TRADES 10

//+------------------------------------------------------------------+
//| Get confidence adjustment multiplier for a given confidence score|
//| Returns 1.0 (neutral) until enough data is accumulated.         |
//| > 1.0 = bucket historically over-performs → boost allowed       |
//| < 1.0 = bucket historically under-performs → score penalised    |
//+------------------------------------------------------------------+
double GetConfidenceAdjustment(double confidence)
{
   int bucket = GetConfBucketIndex(confidence);
   if(bucket < 0 || bucket >= 4)
      return 1.0;

   int   trades  = g_confBuckets[bucket].trades;
   int   wins    = g_confBuckets[bucket].wins;

   if(trades < CONF_FEEDBACK_MIN_TRADES)
      return 1.0;  // not enough data — neutral

   double winRate  = (double)wins / (double)trades;
   double expected = 0.50;  // baseline expectation

   // Scale: +/- 15% max adjustment
   double delta = (winRate - expected) * 0.30;  // 0.30 per unit of win-rate deviation
   double mult  = 1.0 + delta;

   if(mult < 0.70) mult = 0.70;
   if(mult > 1.15) mult = 1.15;

   return mult;
}

//+------------------------------------------------------------------+
//| Apply confidence adjustment to a raw confidence score            |
//| Clamps result to [0.0, 100.0]                                    |
//+------------------------------------------------------------------+
double AdjustConfidenceScore(double rawConfidence)
{
   double mult = GetConfidenceAdjustment(rawConfidence);
   double adjusted = rawConfidence * mult;
   if(adjusted < 0.0)   adjusted = 0.0;
   if(adjusted > 100.0) adjusted = 100.0;
   return adjusted;
}

//+------------------------------------------------------------------+
//| Is this confidence bucket currently reliable?                    |
//| Returns false if win-rate < 40% over 10+ trades (avoid bucket)  |
//+------------------------------------------------------------------+
bool IsConfidenceBucketReliable(double confidence)
{
   int bucket = GetConfBucketIndex(confidence);
   if(bucket < 0 || bucket >= 4)
      return true;  // no data = assume ok

   int trades = g_confBuckets[bucket].trades;
   int wins   = g_confBuckets[bucket].wins;

   if(trades < CONF_FEEDBACK_MIN_TRADES)
      return true;  // insufficient data = allow

   double winRate = (double)wins / (double)trades;
   return (winRate >= 0.40);
}

//+------------------------------------------------------------------+
//| Print feedback state — call from diagnostics                     |
//+------------------------------------------------------------------+
void PrintConfidenceFeedback()
{
   string labels[4] = {"<60", "60-69", "70-79", "80+"};
   Print("[CONF_FEEDBACK] Bucket adjustments:");
   for(int i = 0; i < 4; i++)
   {
      int    trades  = g_confBuckets[i].trades;
      int    wins    = g_confBuckets[i].wins;
      double wr      = (trades > 0) ? (double)wins / trades : 0.0;
      double midConf = (i == 0) ? 55.0 : (i == 1) ? 65.0 : (i == 2) ? 75.0 : 85.0;
      double mult    = GetConfidenceAdjustment(midConf);

      Print("  bucket=[", labels[i], "] trades=", trades,
            " winRate=", DoubleToString(wr * 100.0, 1), "%",
            " adj=x", DoubleToString(mult, 3),
            (trades < CONF_FEEDBACK_MIN_TRADES ? " (pending)" : ""));
   }
}

#endif // CONFIDENCE_TRACKER_MQH
