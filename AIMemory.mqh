//+------------------------------------------------------------------+
//|                                                    AIMemory.mqh  |
//|  Persistent AI learning system                                   |
//|  - Learns from bot trades AND manual trades                      |
//|  - Tracks pattern performance (win rate, profit factor, etc.)    |
//|  - Adjusts entry confidence based on historical outcomes         |
//|  - Saves/loads all data to disk, survives restarts               |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef AI_MEMORY_MQH
#define AI_MEMORY_MQH

#define MAX_LEARNED_PATTERNS 500
#define MAX_MANUAL_TRACKS    50
#define MAX_LEARNING_MAP     100
#define MIN_TRADES_FOR_ADJUST 5

//+------------------------------------------------------------------+
//| AI Learning mode                                                 |
//+------------------------------------------------------------------+
enum ENUM_AI_LEARN_MODE
{
   AI_LEARN_NORMAL   = 0,  // Normal — read & write shared memory
   AI_LEARN_READONLY = 1,  // Read-only — use learned data, don't update
   AI_LEARN_ISOLATED = 2,  // Isolated — separate backtest memory file
   AI_LEARN_DISABLED = 3   // Disabled — no AI learning at all
};

//+------------------------------------------------------------------+
//| Learned pattern — rich statistics per setup combination          |
//+------------------------------------------------------------------+
struct LearnedPattern
{
   string   key;
   int      wins;
   int      losses;
   double   grossProfit;     // sum of winning PnL
   double   grossLoss;       // sum of losing PnL (stored negative)
   double   bestTrade;
   double   worstTrade;
   int      fromBot;
   int      fromManual;
   datetime lastUpdate;
   // Session performance (0=Asian 00-08, 1=London 08-16, 2=NY 16-24 UTC)
   int      winsSession[3];
   int      lossesSession[3];
   double   profitSession[3];
   // Volatility tracking
   int      winsHighVol;
   int      lossesHighVol;
   int      winsLowVol;
   int      lossesLowVol;
   // Recency (exponentially decayed recent performance)
   double   recentWins;
   double   recentLosses;
   double   recentProfit;
   double   recentLoss;
};

//+------------------------------------------------------------------+
//| Manual trade tracker — captures context when user trade detected |
//+------------------------------------------------------------------+
struct ManualTradeTracker
{
   ulong    posTicket;
   datetime openTime;
   int      posType;         // POSITION_TYPE_BUY or POSITION_TYPE_SELL
   double   entryPrice;
   double   lots;
   string   patternKey;      // market context at detection
   bool     active;
};

//+------------------------------------------------------------------+
//| Learning trade map — maps position ID → learning key for bot     |
//+------------------------------------------------------------------+
struct LearningTradeMap
{
   ulong  ticket;
   string learningKey;
};

// Globals
LearnedPattern     g_learnedPatterns[];
int                g_learnedPatternCount = 0;
ManualTradeTracker g_manualTracks[];
int                g_manualTrackCount = 0;
LearningTradeMap   g_learningMap[];
int                g_learningMapCount = 0;
string             g_patternFile  = "";
string             g_manualFile   = "";
bool               g_currentHighVolatility = false;
ENUM_AI_LEARN_MODE g_aiLearnMode = AI_LEARN_NORMAL;
string             g_aiMemoryTag = "";

//+------------------------------------------------------------------+
//| Determine trading session from server time                       |
//| 0 = Asian (00:00-07:59), 1 = London (08:00-15:59),             |
//| 2 = New York (16:00-23:59)                                      |
//+------------------------------------------------------------------+
int GetTradingSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int hour = dt.hour;
   if(hour < 8)  return 0;  // Asian
   if(hour < 16) return 1;  // London
   return 2;                 // New York
}

//+------------------------------------------------------------------+
//| Get session name string                                          |
//+------------------------------------------------------------------+
string GetSessionName(int session)
{
   if(session == 0) return "ASIAN";
   if(session == 1) return "LONDON";
   return "NY";
}

//+------------------------------------------------------------------+
//| Find pattern index by key, -1 if not found                      |
//+------------------------------------------------------------------+
int FindLearnedPatternIndex(const string key)
{
   for(int i = 0; i < g_learnedPatternCount; i++)
      if(g_learnedPatterns[i].key == key)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| Get win rate for a pattern (0.5 if not enough data)             |
//+------------------------------------------------------------------+
double GetPatternWinRate(const string key)
{
   int idx = FindLearnedPatternIndex(key);
   if(idx < 0) return 0.5;
   int total = g_learnedPatterns[idx].wins + g_learnedPatterns[idx].losses;
   if(total < MIN_TRADES_FOR_ADJUST) return 0.5;
   return (double)g_learnedPatterns[idx].wins / (double)total;
}

//+------------------------------------------------------------------+
//| Get profit factor for a pattern (1.0 if not enough data)        |
//+------------------------------------------------------------------+
double GetPatternProfitFactor(const string key)
{
   int idx = FindLearnedPatternIndex(key);
   if(idx < 0) return 1.0;
   if(g_learnedPatterns[idx].grossLoss == 0.0) return 99.0;
   return g_learnedPatterns[idx].grossProfit / MathAbs(g_learnedPatterns[idx].grossLoss);
}

//+------------------------------------------------------------------+
//| Get total trades for a pattern                                  |
//+------------------------------------------------------------------+
int GetPatternTradeCount(const string key)
{
   int idx = FindLearnedPatternIndex(key);
   if(idx < 0) return 0;
   return g_learnedPatterns[idx].wins + g_learnedPatterns[idx].losses;
}

//+------------------------------------------------------------------+
//| Get recent win rate using exponentially decayed stats            |
//| Returns 0.5 if not enough recent data                           |
//+------------------------------------------------------------------+
double GetRecentWinRate(const string key)
{
   int idx = FindLearnedPatternIndex(key);
   if(idx < 0) return 0.5;
   double total = g_learnedPatterns[idx].recentWins + g_learnedPatterns[idx].recentLosses;
   if(total < 3.0) return 0.5;
   return g_learnedPatterns[idx].recentWins / total;
}

//+------------------------------------------------------------------+
//| Get session-specific win rate                                    |
//| session: 0=Asian, 1=London, 2=NY                                |
//+------------------------------------------------------------------+
double GetSessionWinRate(const string key, int session)
{
   if(session < 0 || session > 2) return 0.5;
   int idx = FindLearnedPatternIndex(key);
   if(idx < 0) return 0.5;
   int total = g_learnedPatterns[idx].winsSession[session] + g_learnedPatterns[idx].lossesSession[session];
   if(total < 3) return 0.5;
   return (double)g_learnedPatterns[idx].winsSession[session] / total;
}

//+------------------------------------------------------------------+
//| Get learned confidence adjustment for a pattern                 |
//| Returns value from -0.35 to +0.25                               |
//| Blends all-time, recency, session, and volatility metrics       |
//+------------------------------------------------------------------+
double GetLearnedConfidence(const string key)
{
   int idx = FindLearnedPatternIndex(key);
   if(idx < 0) return 0.0;

   int total = g_learnedPatterns[idx].wins + g_learnedPatterns[idx].losses;
   if(total < MIN_TRADES_FOR_ADJUST) return 0.0;

   double winRate = (double)g_learnedPatterns[idx].wins / (double)total;
   double pf = GetPatternProfitFactor(key);
   double adj = 0.0;

   // Win rate adjustments
   if(winRate >= 0.75)      adj += 0.15;
   else if(winRate >= 0.65) adj += 0.10;
   else if(winRate >= 0.55) adj += 0.05;
   else if(winRate < 0.35)  adj -= 0.25;
   else if(winRate < 0.45)  adj -= 0.15;
   else if(winRate < 0.50)  adj -= 0.05;

   // Profit factor adjustments
   if(pf >= 2.5)       adj += 0.05;
   else if(pf >= 1.8)  adj += 0.03;
   else if(pf < 0.7)   adj -= 0.10;
   else if(pf < 1.0)   adj -= 0.05;

   // Recency bonus/penalty — recent performance weighted more
   double recentWR = GetRecentWinRate(key);
   double recentTotal = g_learnedPatterns[idx].recentWins + g_learnedPatterns[idx].recentLosses;
   if(recentTotal >= 3.0)
   {
      if(recentWR >= 0.65)      adj += 0.05;
      else if(recentWR >= 0.55) adj += 0.02;
      else if(recentWR < 0.30)  adj -= 0.08;
      else if(recentWR < 0.40)  adj -= 0.04;
   }

   // Session bonus/penalty — current session track record
   int session = GetTradingSession();
   double sessWR = GetSessionWinRate(key, session);
   int sessTotal = g_learnedPatterns[idx].winsSession[session] + g_learnedPatterns[idx].lossesSession[session];
   if(sessTotal >= 3)
   {
      if(sessWR >= 0.65)      adj += 0.03;
      else if(sessWR < 0.30)  adj -= 0.05;
   }

   // Volatility match — how does this pattern perform in current conditions
   if(g_currentHighVolatility)
   {
      int hvTotal = g_learnedPatterns[idx].winsHighVol + g_learnedPatterns[idx].lossesHighVol;
      if(hvTotal >= 3)
      {
         double hvWR = (double)g_learnedPatterns[idx].winsHighVol / hvTotal;
         if(hvWR >= 0.60) adj += 0.03;
         else if(hvWR < 0.30) adj -= 0.05;
      }
   }
   else
   {
      int lvTotal = g_learnedPatterns[idx].winsLowVol + g_learnedPatterns[idx].lossesLowVol;
      if(lvTotal >= 3)
      {
         double lvWR = (double)g_learnedPatterns[idx].winsLowVol / lvTotal;
         if(lvWR >= 0.60) adj += 0.03;
         else if(lvWR < 0.30) adj -= 0.05;
      }
   }

   if(adj > 0.25)  adj = 0.25;
   if(adj < -0.35) adj = -0.35;

   return adj;
}

//+------------------------------------------------------------------+
//| Should block this pattern entirely?                             |
//| Requires minSampleSize trades before making any blocking        |
//| decision. Blocks only if BOTH win rate AND profit factor are    |
//| below their thresholds — a low WR pattern with high PF (big    |
//| winners) is still profitable and should not be blocked.         |
//+------------------------------------------------------------------+
bool ShouldBlockPattern(const string key, double minWinRate,
                        int minSampleSize = 10, double minProfitFactor = 1.0)
{
   int idx = FindLearnedPatternIndex(key);
   if(idx < 0) return false;

   int total = g_learnedPatterns[idx].wins + g_learnedPatterns[idx].losses;

   // Sample size gate: never block with insufficient data
   if(total < minSampleSize)
   {
      if(total > 0)
         Print("AI LEARN GATE: ", key, " has only ", total, " trades (need ", minSampleSize, ") — not enough to block");
      return false;
   }

   double winRate = (double)g_learnedPatterns[idx].wins / (double)total;
   double pf = GetPatternProfitFactor(key);

   // Block only if BOTH win rate AND profit factor are bad
   bool wrBad = (winRate < minWinRate);
   bool pfBad = (pf < minProfitFactor);

   if(wrBad && pfBad)
   {
      // Check if recent performance is recovering — don't block if trending up
      double recentWR = GetRecentWinRate(key);
      double recentTotal = g_learnedPatterns[idx].recentWins + g_learnedPatterns[idx].recentLosses;
      if(recentTotal >= 3.0 && recentWR >= 0.50)
      {
         Print("AI LEARN UNBLOCK: ", key,
               " all-time WR=", DoubleToString(winRate * 100, 1), "% is bad",
               " but recent WR=", DoubleToString(recentWR * 100, 1), "% is recovering — allowing entry");
         return false;
      }

      Print("AI LEARN BLOCK: ", key,
            " WR=", DoubleToString(winRate * 100, 1), "% (<", DoubleToString(minWinRate * 100, 0), "%)",
            " PF=", DoubleToString(pf, 2), " (<", DoubleToString(minProfitFactor, 1), ")",
            " trades=", total,
            " recentWR=", DoubleToString(recentWR * 100, 1), "%");
      return true;
   }

   // Log why we're NOT blocking despite one metric being weak
   if(wrBad && !pfBad)
      Print("AI LEARN PASS: ", key,
            " WR=", DoubleToString(winRate * 100, 1), "% is low but PF=", DoubleToString(pf, 2),
            " is profitable — allowing entry");
   else if(!wrBad && pfBad)
      Print("AI LEARN PASS: ", key,
            " PF=", DoubleToString(pf, 2), " is low but WR=", DoubleToString(winRate * 100, 1),
            "% is acceptable — allowing entry");

   return false;
}

//+------------------------------------------------------------------+
//| Record a trade outcome for a pattern                            |
//+------------------------------------------------------------------+
void RecordPatternOutcome(const string key, double pnl, bool isManual, bool highVol = false)
{
   if(StringLen(key) == 0) return;
   if(g_aiLearnMode == AI_LEARN_READONLY || g_aiLearnMode == AI_LEARN_DISABLED) return;

   int idx = FindLearnedPatternIndex(key);
   if(idx < 0)
   {
      if(g_learnedPatternCount >= MAX_LEARNED_PATTERNS)
      {
         // Overwrite least-used pattern
         int oldestIdx = 0;
         int minTrades = g_learnedPatterns[0].wins + g_learnedPatterns[0].losses;
         datetime oldestTime = g_learnedPatterns[0].lastUpdate;
         for(int i = 1; i < g_learnedPatternCount; i++)
         {
            int trades = g_learnedPatterns[i].wins + g_learnedPatterns[i].losses;
            if(trades < minTrades || (trades == minTrades && g_learnedPatterns[i].lastUpdate < oldestTime))
            {
               oldestIdx   = i;
               minTrades   = trades;
               oldestTime  = g_learnedPatterns[i].lastUpdate;
            }
         }
         idx = oldestIdx;
         g_learnedPatterns[idx].key         = key;
         g_learnedPatterns[idx].wins        = 0;
         g_learnedPatterns[idx].losses      = 0;
         g_learnedPatterns[idx].grossProfit = 0.0;
         g_learnedPatterns[idx].grossLoss   = 0.0;
         g_learnedPatterns[idx].bestTrade   = 0.0;
         g_learnedPatterns[idx].worstTrade  = 0.0;
         g_learnedPatterns[idx].fromBot     = 0;
         g_learnedPatterns[idx].fromManual  = 0;
         for(int ss = 0; ss < 3; ss++) { g_learnedPatterns[idx].winsSession[ss] = 0; g_learnedPatterns[idx].lossesSession[ss] = 0; g_learnedPatterns[idx].profitSession[ss] = 0.0; }
         g_learnedPatterns[idx].winsHighVol  = 0; g_learnedPatterns[idx].lossesHighVol = 0;
         g_learnedPatterns[idx].winsLowVol   = 0; g_learnedPatterns[idx].lossesLowVol  = 0;
         g_learnedPatterns[idx].recentWins   = 0.0; g_learnedPatterns[idx].recentLosses = 0.0;
         g_learnedPatterns[idx].recentProfit = 0.0; g_learnedPatterns[idx].recentLoss   = 0.0;
      }
      else
      {
         ArrayResize(g_learnedPatterns, g_learnedPatternCount + 1);
         idx = g_learnedPatternCount;
         g_learnedPatterns[idx].key         = key;
         g_learnedPatterns[idx].wins        = 0;
         g_learnedPatterns[idx].losses      = 0;
         g_learnedPatterns[idx].grossProfit = 0.0;
         g_learnedPatterns[idx].grossLoss   = 0.0;
         g_learnedPatterns[idx].bestTrade   = 0.0;
         g_learnedPatterns[idx].worstTrade  = 0.0;
         g_learnedPatterns[idx].fromBot     = 0;
         g_learnedPatterns[idx].fromManual  = 0;
         for(int ss = 0; ss < 3; ss++) { g_learnedPatterns[idx].winsSession[ss] = 0; g_learnedPatterns[idx].lossesSession[ss] = 0; g_learnedPatterns[idx].profitSession[ss] = 0.0; }
         g_learnedPatterns[idx].winsHighVol  = 0; g_learnedPatterns[idx].lossesHighVol = 0;
         g_learnedPatterns[idx].winsLowVol   = 0; g_learnedPatterns[idx].lossesLowVol  = 0;
         g_learnedPatterns[idx].recentWins   = 0.0; g_learnedPatterns[idx].recentLosses = 0.0;
         g_learnedPatterns[idx].recentProfit = 0.0; g_learnedPatterns[idx].recentLoss   = 0.0;
         g_learnedPatternCount++;
      }
   }

   if(pnl > 0)
   {
      g_learnedPatterns[idx].wins++;
      g_learnedPatterns[idx].grossProfit += pnl;
   }
   else if(pnl < 0)
   {
      g_learnedPatterns[idx].losses++;
      g_learnedPatterns[idx].grossLoss += pnl;
   }

   if(pnl > g_learnedPatterns[idx].bestTrade)  g_learnedPatterns[idx].bestTrade  = pnl;
   if(pnl < g_learnedPatterns[idx].worstTrade) g_learnedPatterns[idx].worstTrade = pnl;

   if(isManual) g_learnedPatterns[idx].fromManual++;
   else         g_learnedPatterns[idx].fromBot++;

   // Session tracking
   int session = GetTradingSession();
   if(pnl > 0) { g_learnedPatterns[idx].winsSession[session]++; g_learnedPatterns[idx].profitSession[session] += pnl; }
   else if(pnl < 0) { g_learnedPatterns[idx].lossesSession[session]++; g_learnedPatterns[idx].profitSession[session] += pnl; }

   // Volatility tracking
   if(highVol || g_currentHighVolatility)
   {
      if(pnl > 0) g_learnedPatterns[idx].winsHighVol++;
      else if(pnl < 0) g_learnedPatterns[idx].lossesHighVol++;
   }
   else
   {
      if(pnl > 0) g_learnedPatterns[idx].winsLowVol++;
      else if(pnl < 0) g_learnedPatterns[idx].lossesLowVol++;
   }

   // Recency: decay old data then add new trade
   g_learnedPatterns[idx].recentWins   *= 0.95;
   g_learnedPatterns[idx].recentLosses *= 0.95;
   g_learnedPatterns[idx].recentProfit *= 0.95;
   g_learnedPatterns[idx].recentLoss   *= 0.95;
   if(pnl > 0) { g_learnedPatterns[idx].recentWins += 1.0; g_learnedPatterns[idx].recentProfit += pnl; }
   else if(pnl < 0) { g_learnedPatterns[idx].recentLosses += 1.0; g_learnedPatterns[idx].recentLoss += pnl; }

   g_learnedPatterns[idx].lastUpdate = TimeCurrent();

   int total = g_learnedPatterns[idx].wins + g_learnedPatterns[idx].losses;
   double wr = (total > 0) ? (double)g_learnedPatterns[idx].wins / total : 0.5;
   double pf = GetPatternProfitFactor(key);
   double conf = GetLearnedConfidence(key);
   double rwr = GetRecentWinRate(key);

   Print("AI LEARN [", (isManual ? "MANUAL" : "BOT"), "]: ", key,
         " W=", g_learnedPatterns[idx].wins, " L=", g_learnedPatterns[idx].losses,
         " WR=", DoubleToString(wr * 100, 1), "%",
         " recentWR=", DoubleToString(rwr * 100, 1), "%",
         " PF=", DoubleToString(pf, 2),
         " Conf=", DoubleToString(conf, 2),
         " sess=", GetSessionName(session),
         " vol=", (g_currentHighVolatility ? "HIGH" : "LOW"),
         " (bot=", g_learnedPatterns[idx].fromBot,
         " manual=", g_learnedPatterns[idx].fromManual, ")");
}

//+------------------------------------------------------------------+
//| Save learned patterns to CSV                                    |
//+------------------------------------------------------------------+
void SaveLearnedPatterns()
{
   if(g_patternFile == "") return;
   if(g_aiLearnMode == AI_LEARN_READONLY || g_aiLearnMode == AI_LEARN_DISABLED) return;

   int fh = FileOpen(g_patternFile, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
   {
      Print("AI MEMORY: Failed to save — cannot open ", g_patternFile);
      return;
   }

   FileWriteString(fh, "v2,key,wins,losses,gross_profit,gross_loss,best,worst,bot,manual,last_update,wS0,wS1,wS2,lS0,lS1,lS2,pS0,pS1,pS2,wHV,lHV,wLV,lLV,rW,rL,rP,rLs\n");
   for(int i = 0; i < g_learnedPatternCount; i++)
   {
      FileWriteString(fh,
         "v2," +
         g_learnedPatterns[i].key + "," +
         IntegerToString(g_learnedPatterns[i].wins) + "," +
         IntegerToString(g_learnedPatterns[i].losses) + "," +
         DoubleToString(g_learnedPatterns[i].grossProfit, 2) + "," +
         DoubleToString(g_learnedPatterns[i].grossLoss, 2) + "," +
         DoubleToString(g_learnedPatterns[i].bestTrade, 2) + "," +
         DoubleToString(g_learnedPatterns[i].worstTrade, 2) + "," +
         IntegerToString(g_learnedPatterns[i].fromBot) + "," +
         IntegerToString(g_learnedPatterns[i].fromManual) + "," +
         IntegerToString((long)g_learnedPatterns[i].lastUpdate) + "," +
         IntegerToString(g_learnedPatterns[i].winsSession[0]) + "," +
         IntegerToString(g_learnedPatterns[i].winsSession[1]) + "," +
         IntegerToString(g_learnedPatterns[i].winsSession[2]) + "," +
         IntegerToString(g_learnedPatterns[i].lossesSession[0]) + "," +
         IntegerToString(g_learnedPatterns[i].lossesSession[1]) + "," +
         IntegerToString(g_learnedPatterns[i].lossesSession[2]) + "," +
         DoubleToString(g_learnedPatterns[i].profitSession[0], 2) + "," +
         DoubleToString(g_learnedPatterns[i].profitSession[1], 2) + "," +
         DoubleToString(g_learnedPatterns[i].profitSession[2], 2) + "," +
         IntegerToString(g_learnedPatterns[i].winsHighVol) + "," +
         IntegerToString(g_learnedPatterns[i].lossesHighVol) + "," +
         IntegerToString(g_learnedPatterns[i].winsLowVol) + "," +
         IntegerToString(g_learnedPatterns[i].lossesLowVol) + "," +
         DoubleToString(g_learnedPatterns[i].recentWins, 4) + "," +
         DoubleToString(g_learnedPatterns[i].recentLosses, 4) + "," +
         DoubleToString(g_learnedPatterns[i].recentProfit, 2) + "," +
         DoubleToString(g_learnedPatterns[i].recentLoss, 2) + "\n");
   }
   FileClose(fh);
   Print("AI MEMORY: Saved ", g_learnedPatternCount, " patterns to ", g_patternFile);
}

//+------------------------------------------------------------------+
//| Load learned patterns from CSV                                  |
//+------------------------------------------------------------------+
void LoadLearnedPatterns()
{
   if(g_patternFile == "")
      g_patternFile = "ai_patterns_" + _Symbol + ".csv";
   g_learnedPatternCount = 0;
   ArrayResize(g_learnedPatterns, 0);

   int fh = FileOpen(g_patternFile, FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
   {
      Print("AI MEMORY: No existing pattern file — starting fresh");
      return;
   }

   // Detect format version from header
   string firstField = "";
   if(!FileIsEnding(fh))
      firstField = FileReadString(fh);

   bool isV2 = (firstField == "v2");
   if(isV2)
   {
      // Skip remaining 27 header fields (v2 format has 28 columns total)
      for(int h = 0; h < 27; h++) FileReadString(fh);
   }
   else
   {
      // Old format: first field was "key", skip remaining 9 header fields
      for(int h = 0; h < 9; h++) FileReadString(fh);
   }

   while(!FileIsEnding(fh) && g_learnedPatternCount < MAX_LEARNED_PATTERNS)
   {
      string key = "";
      if(isV2)
      {
         string ver = FileReadString(fh);  // skip "v2" row marker
         if(StringLen(ver) == 0) break;
         key = FileReadString(fh);
      }
      else
      {
         key = FileReadString(fh);
      }
      if(StringLen(key) == 0) break;

      int    wins    = (int)FileReadNumber(fh);
      int    losses  = (int)FileReadNumber(fh);
      double gProfit = FileReadNumber(fh);
      double gLoss   = FileReadNumber(fh);
      double best    = FileReadNumber(fh);
      double worst   = FileReadNumber(fh);
      int    bot     = (int)FileReadNumber(fh);
      int    manual  = (int)FileReadNumber(fh);
      long   lastUpd = (long)FileReadNumber(fh);

      ArrayResize(g_learnedPatterns, g_learnedPatternCount + 1);
      int ci = g_learnedPatternCount;
      g_learnedPatterns[ci].key         = key;
      g_learnedPatterns[ci].wins        = wins;
      g_learnedPatterns[ci].losses      = losses;
      g_learnedPatterns[ci].grossProfit = gProfit;
      g_learnedPatterns[ci].grossLoss   = gLoss;
      g_learnedPatterns[ci].bestTrade   = best;
      g_learnedPatterns[ci].worstTrade  = worst;
      g_learnedPatterns[ci].fromBot     = bot;
      g_learnedPatterns[ci].fromManual  = manual;
      g_learnedPatterns[ci].lastUpdate  = (datetime)lastUpd;

      if(isV2)
      {
         g_learnedPatterns[ci].winsSession[0]   = (int)FileReadNumber(fh);
         g_learnedPatterns[ci].winsSession[1]   = (int)FileReadNumber(fh);
         g_learnedPatterns[ci].winsSession[2]   = (int)FileReadNumber(fh);
         g_learnedPatterns[ci].lossesSession[0]  = (int)FileReadNumber(fh);
         g_learnedPatterns[ci].lossesSession[1]  = (int)FileReadNumber(fh);
         g_learnedPatterns[ci].lossesSession[2]  = (int)FileReadNumber(fh);
         g_learnedPatterns[ci].profitSession[0]  = FileReadNumber(fh);
         g_learnedPatterns[ci].profitSession[1]  = FileReadNumber(fh);
         g_learnedPatterns[ci].profitSession[2]  = FileReadNumber(fh);
         g_learnedPatterns[ci].winsHighVol       = (int)FileReadNumber(fh);
         g_learnedPatterns[ci].lossesHighVol     = (int)FileReadNumber(fh);
         g_learnedPatterns[ci].winsLowVol        = (int)FileReadNumber(fh);
         g_learnedPatterns[ci].lossesLowVol      = (int)FileReadNumber(fh);
         g_learnedPatterns[ci].recentWins        = FileReadNumber(fh);
         g_learnedPatterns[ci].recentLosses      = FileReadNumber(fh);
         g_learnedPatterns[ci].recentProfit      = FileReadNumber(fh);
         g_learnedPatterns[ci].recentLoss        = FileReadNumber(fh);
      }
      else
      {
         // Old format: initialize new fields with defaults
         for(int ss = 0; ss < 3; ss++) { g_learnedPatterns[ci].winsSession[ss] = 0; g_learnedPatterns[ci].lossesSession[ss] = 0; g_learnedPatterns[ci].profitSession[ss] = 0.0; }
         g_learnedPatterns[ci].winsHighVol  = 0; g_learnedPatterns[ci].lossesHighVol = 0;
         g_learnedPatterns[ci].winsLowVol   = 0; g_learnedPatterns[ci].lossesLowVol  = 0;
         g_learnedPatterns[ci].recentWins   = 0.0; g_learnedPatterns[ci].recentLosses = 0.0;
         g_learnedPatterns[ci].recentProfit = 0.0; g_learnedPatterns[ci].recentLoss   = 0.0;
      }

      g_learnedPatternCount++;
   }
   FileClose(fh);

   Print("AI MEMORY: Loaded ", g_learnedPatternCount, " learned patterns",
         (isV2 ? " (v2 format)" : " (v1 format — will upgrade on save)"));
}

//+------------------------------------------------------------------+
//| Build learning pattern key from market context                  |
//| Format: SYMBOL|DIR|REGIME|ZONE|BIAS                             |
//+------------------------------------------------------------------+
string BuildLearningKey(const string direction,
                        const string regimeStr,
                        bool nearZone,
                        int zoneTypeInt,
                        bool biasAligned)
{
   string zoneStr = nearZone ? ("Z" + IntegerToString(zoneTypeInt)) : "NOZONE";
   string biasStr = biasAligned ? "BIAS" : "NOBIAS";
   return _Symbol + "|" + direction + "|" + regimeStr + "|" + zoneStr + "|" + biasStr;
}

//+------------------------------------------------------------------+
//| BuildLearningKeyV2 — strategy-specific key using real setup data |
//| Format: SYMBOLCLASS|TREND_OR_RANGE|DIR|ZONE_ROLE|PATTERN|SESSION |
//| Example: FOREX|TREND|BUY|SUPPORT_MAJOR|SWEEP_RECLAIM|LONDON     |
//+------------------------------------------------------------------+
string BuildLearningKeyV2(const string direction, bool isTrend,
                          const string zoneRole, const string patternName,
                          int symbolClass)
{
   string classStr;
   switch(symbolClass)
   {
      case 1:  classStr = "FOREX";     break;
      case 2:  classStr = "CRYPTO";    break;
      case 3:  classStr = "INDEX";     break;
      case 4:  classStr = "SYNTHETIC"; break;
      default: classStr = "OTHER";     break;
   }
   string modeStr = isTrend ? "TREND" : "RANGE";
   return classStr + "|" + modeStr + "|" + direction + "|" + zoneRole + "|" + patternName + "|" + GetSessionName(GetTradingSession());
}

//+------------------------------------------------------------------+
//| Register a bot trade → learning key mapping                     |
//+------------------------------------------------------------------+
void RegisterLearningContext(ulong ticket, const string key)
{
   if(StringLen(key) == 0 || ticket == 0) return;

   for(int i = 0; i < g_learningMapCount; i++)
   {
      if(g_learningMap[i].ticket == ticket)
      {
         g_learningMap[i].learningKey = key;
         return;
      }
   }

   if(g_learningMapCount >= MAX_LEARNING_MAP)
   {
      for(int i = 0; i < g_learningMapCount - 1; i++)
         g_learningMap[i] = g_learningMap[i + 1];
      g_learningMapCount--;
   }

   ArrayResize(g_learningMap, g_learningMapCount + 1);
   g_learningMap[g_learningMapCount].ticket      = ticket;
   g_learningMap[g_learningMapCount].learningKey  = key;
   g_learningMapCount++;
}

//+------------------------------------------------------------------+
//| Find learning key for a position ticket                         |
//+------------------------------------------------------------------+
string FindLearningKey(ulong ticket)
{
   for(int i = 0; i < g_learningMapCount; i++)
      if(g_learningMap[i].ticket == ticket)
         return g_learningMap[i].learningKey;
   return "";
}

//+------------------------------------------------------------------+
//| Remove learning map entry after trade close                     |
//+------------------------------------------------------------------+
void RemoveLearningEntry(ulong ticket)
{
   for(int i = 0; i < g_learningMapCount; i++)
   {
      if(g_learningMap[i].ticket == ticket)
      {
         for(int j = i; j < g_learningMapCount - 1; j++)
            g_learningMap[j] = g_learningMap[j + 1];
         g_learningMapCount--;
         ArrayResize(g_learningMap, g_learningMapCount);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if a manual trade ticket is already tracked               |
//+------------------------------------------------------------------+
bool IsManualTrackKnown(ulong ticket)
{
   for(int i = 0; i < g_manualTrackCount; i++)
      if(g_manualTracks[i].posTicket == ticket && g_manualTracks[i].active)
         return true;
   return false;
}

//+------------------------------------------------------------------+
//| Scan open positions for manual trades (non-bot magic)           |
//| Call on each new bar to detect trades the user opens manually   |
//+------------------------------------------------------------------+
void ScanForManualTrades(ulong botMagic,
                         const string regimeStr,
                         bool nearZone,
                         int zoneTypeInt,
                         bool bullBias,
                         bool bearBias)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long posMagic = PositionGetInteger(POSITION_MAGIC);
      if(posMagic == (long)botMagic) continue;

      if(IsManualTrackKnown(ticket)) continue;

      // New manual trade detected
      int    posType    = (int)PositionGetInteger(POSITION_TYPE);
      string dir        = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double lots       = PositionGetDouble(POSITION_VOLUME);

      bool biasOK = (dir == "BUY") ? bullBias : bearBias;
      string ctxKey = BuildLearningKey(dir, regimeStr, nearZone, zoneTypeInt, biasOK);

      // Find inactive slot or add new
      int slot = -1;
      for(int j = 0; j < g_manualTrackCount; j++)
      {
         if(!g_manualTracks[j].active)
         {
            slot = j;
            break;
         }
      }
      if(slot < 0)
      {
         if(g_manualTrackCount >= MAX_MANUAL_TRACKS)
            slot = 0; // overwrite oldest
         else
         {
            ArrayResize(g_manualTracks, g_manualTrackCount + 1);
            slot = g_manualTrackCount;
            g_manualTrackCount++;
         }
      }

      g_manualTracks[slot].posTicket  = ticket;
      g_manualTracks[slot].openTime   = (datetime)PositionGetInteger(POSITION_TIME);
      g_manualTracks[slot].posType    = posType;
      g_manualTracks[slot].entryPrice = entryPrice;
      g_manualTracks[slot].lots       = lots;
      g_manualTracks[slot].patternKey = ctxKey;
      g_manualTracks[slot].active     = true;

      Print("AI MEMORY: Manual trade detected! ticket=", ticket,
            " ", dir, " ", DoubleToString(lots, 2), " lots @ ",
            DoubleToString(entryPrice, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)),
            " context=", ctxKey);

      LogManualTradeEntry(ticket, dir, entryPrice, lots, ctxKey);
   }
}

//+------------------------------------------------------------------+
//| Log manual trade entry to CSV                                   |
//+------------------------------------------------------------------+
void LogManualTradeEntry(ulong ticket, string dir, double price, double lots, string ctxKey)
{
   if(g_manualFile == "") return;

   int fh = FileOpen(g_manualFile, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE) return;

   if(FileSize(fh) == 0)
      FileWriteString(fh, "time,ticket,direction,price,lots,context_key,outcome,pnl,close_time\n");

   FileSeek(fh, 0, SEEK_END);
   FileWriteString(fh,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "," +
      IntegerToString(ticket) + "," +
      dir + "," +
      DoubleToString(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS)) + "," +
      DoubleToString(lots, 4) + "," +
      ctxKey + ",OPEN,0.0,\n");
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| Process a closed deal — check if it's a tracked manual trade    |
//| Call from OnTradeTransaction for non-bot deals                  |
//+------------------------------------------------------------------+
void ProcessManualTradeClose(ulong dealTicket)
{
   if(!HistoryDealSelect(dealTicket)) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   if(dealSymbol != _Symbol) return;

   ulong posId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

   for(int i = 0; i < g_manualTrackCount; i++)
   {
      if(!g_manualTracks[i].active) continue;
      if(g_manualTracks[i].posTicket == posId)
      {
         double pnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                    + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)
                    + HistoryDealGetDouble(dealTicket, DEAL_SWAP);

         string key = g_manualTracks[i].patternKey;
         RecordPatternOutcome(key, pnl, true);

         string resultStr = (pnl > 0) ? "WIN" : (pnl < 0 ? "LOSS" : "SCRATCH");
         Print("AI MEMORY: Manual trade closed! ticket=", posId,
               " pnl=", DoubleToString(pnl, 2),
               " result=", resultStr,
               " pattern=", key);

         g_manualTracks[i].active = false;

         SaveLearnedPatterns();
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Backup pattern file with timestamp                               |
//+------------------------------------------------------------------+
void BackupPatternFile()
{
   if(g_patternFile == "") return;
   if(!FileIsExist(g_patternFile, FILE_COMMON)) return;

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string timestamp = IntegerToString(dt.year) +
                      StringFormat("%02d", dt.mon) +
                      StringFormat("%02d", dt.day) + "_" +
                      StringFormat("%02d", dt.hour) +
                      StringFormat("%02d", dt.min);

   string backupFile = StringSubstr(g_patternFile, 0, StringLen(g_patternFile) - 4)
                     + "_backup_" + timestamp + ".csv";

   if(FileCopy(g_patternFile, FILE_COMMON, backupFile, FILE_COMMON))
      Print("AI MEMORY: Backed up to ", backupFile);
   else
      Print("AI MEMORY: Backup failed for ", g_patternFile);
}

//+------------------------------------------------------------------+
//| Initialize AI Memory system                                     |
//+------------------------------------------------------------------+
void InitAIMemory(ENUM_AI_LEARN_MODE mode = AI_LEARN_NORMAL,
                  bool resetMemory = false,
                  string memoryTag = "")
{
   g_aiLearnMode = mode;
   g_aiMemoryTag = memoryTag;
   bool inTester = (bool)MQLInfoInteger(MQL_TESTER);

   // Build base filename
   string base = "ai_patterns_" + _Symbol;
   if(StringLen(memoryTag) > 0)
      base += "_" + memoryTag;

   // Guard: reset only works in NORMAL mode
   if(resetMemory && mode != AI_LEARN_NORMAL)
   {
      Print("AI MEMORY WARNING: Reset ignored — only works in NORMAL mode (current=", EnumToString(mode), ")");
      resetMemory = false;
   }

   if(mode == AI_LEARN_DISABLED)
   {
      g_patternFile = "";
      g_learnedPatternCount = 0;
      ArrayResize(g_learnedPatterns, 0);
   }
   else if(mode == AI_LEARN_ISOLATED)
   {
      // Load from main file (existing knowledge), save to isolated file
      g_patternFile = base + ".csv";
      LoadLearnedPatterns();
      g_patternFile = "bt_" + base + ".csv";
      Print("AI MEMORY: Isolated mode — loaded from main, saving to ", g_patternFile);
   }
   else
   {
      g_patternFile = base + ".csv";

      if(resetMemory)
      {
         BackupPatternFile();
         g_learnedPatternCount = 0;
         ArrayResize(g_learnedPatterns, 0);
         SaveLearnedPatterns();
         Print("AI MEMORY: All patterns RESET (backup created)");
      }
      else
      {
         LoadLearnedPatterns();
      }
   }

   g_manualTrackCount = 0;
   ArrayResize(g_manualTracks, 0);
   g_learningMapCount = 0;
   ArrayResize(g_learningMap, 0);
   g_manualFile = "ai_manual_log_" + _Symbol + ".csv";

   Print("========================================");
   Print("AI MEMORY: System initialized for ", _Symbol);
   Print("AI MEMORY: mode=", EnumToString(mode),
         (StringLen(memoryTag) > 0 ? " tag=" + memoryTag : ""),
         (inTester ? " [TESTER]" : " [LIVE]"),
         (resetMemory ? " [RESET]" : ""));
   if(mode != AI_LEARN_DISABLED)
      PrintLearningSummary();
   Print("========================================");
}

//+------------------------------------------------------------------+
//| Shutdown AI Memory — save everything                            |
//+------------------------------------------------------------------+
void ShutdownAIMemory()
{
   if(g_aiLearnMode != AI_LEARN_DISABLED)
      PrintParameterSuggestions();
   SaveLearnedPatterns();
   Print("AI MEMORY: System shutdown — mode=", EnumToString(g_aiLearnMode),
         " — ", g_learnedPatternCount, " patterns",
         (g_aiLearnMode == AI_LEARN_READONLY ? " (read-only, not saved)" :
          g_aiLearnMode == AI_LEARN_DISABLED ? " (disabled)" : " saved"));
}

//+------------------------------------------------------------------+
//| Print learning summary on startup                               |
//+------------------------------------------------------------------+
void PrintLearningSummary()
{
   if(g_learnedPatternCount == 0)
   {
      Print("AI MEMORY: No patterns learned yet — bot will start fresh");
      return;
   }

   int totalTrades = 0, totalWins = 0, totalLosses = 0;
   int boosted = 0, penalized = 0, blocked = 0;
   double totalProfit = 0.0;

   for(int i = 0; i < g_learnedPatternCount; i++)
   {
      int t = g_learnedPatterns[i].wins + g_learnedPatterns[i].losses;
      totalTrades  += t;
      totalWins    += g_learnedPatterns[i].wins;
      totalLosses  += g_learnedPatterns[i].losses;
      totalProfit  += g_learnedPatterns[i].grossProfit + g_learnedPatterns[i].grossLoss;

      if(t >= MIN_TRADES_FOR_ADJUST)
      {
         double conf = GetLearnedConfidence(g_learnedPatterns[i].key);
         if(conf > 0.05)  boosted++;
         if(conf < -0.05) penalized++;

         double wr = (double)g_learnedPatterns[i].wins / t;
         double pf = GetPatternProfitFactor(g_learnedPatterns[i].key);
         if(wr < 0.35 && pf < 1.0 && t >= 10) blocked++;

         string status = "";
         if(conf > 0.05)  status = " [BOOST]";
         else if(wr < 0.35 && pf < 1.0 && t >= 10) status = " [BLOCKED]";
         else if(conf < -0.05) status = " [PENALIZE]";

         double rwr = GetRecentWinRate(g_learnedPatterns[i].key);
         Print("  ", g_learnedPatterns[i].key,
               " | trades=", t,
               " WR=", DoubleToString(wr * 100, 1), "%",
               " recentWR=", DoubleToString(rwr * 100, 1), "%",
               " PF=", DoubleToString(pf, 2),
               " conf=", DoubleToString(conf, 2),
               status,
               " bot=", g_learnedPatterns[i].fromBot,
               " manual=", g_learnedPatterns[i].fromManual);
         // Session breakdown
         Print("    sessions: ASIAN W/L=", g_learnedPatterns[i].winsSession[0], "/", g_learnedPatterns[i].lossesSession[0],
               " LONDON W/L=", g_learnedPatterns[i].winsSession[1], "/", g_learnedPatterns[i].lossesSession[1],
               " NY W/L=", g_learnedPatterns[i].winsSession[2], "/", g_learnedPatterns[i].lossesSession[2],
               " | highVol W/L=", g_learnedPatterns[i].winsHighVol, "/", g_learnedPatterns[i].lossesHighVol,
               " lowVol W/L=", g_learnedPatterns[i].winsLowVol, "/", g_learnedPatterns[i].lossesLowVol);
      }
   }

   Print("AI MEMORY: ", g_learnedPatternCount, " patterns | ",
         totalTrades, " trades (W=", totalWins, " L=", totalLosses, ") | ",
         "net=", DoubleToString(totalProfit, 2), " | ",
         boosted, " boosted | ", penalized, " penalized | ", blocked, " blocked");
}

//+------------------------------------------------------------------+
//| Analyze outcomes and suggest parameter adjustments               |
//| Called at shutdown — prints actionable suggestions to log        |
//+------------------------------------------------------------------+
void PrintParameterSuggestions()
{
   if(g_learnedPatternCount == 0) return;

   Print("========================================");
   Print("AI PARAMETER SUGGESTIONS for ", _Symbol);
   Print("========================================");

   // Aggregate stats across all patterns
   int sessW[3], sessL[3];
   double sessP[3];
   for(int s = 0; s < 3; s++) { sessW[s] = 0; sessL[s] = 0; sessP[s] = 0.0; }
   int hvW = 0, hvL = 0, lvW = 0, lvL = 0;
   double totalGrossProfit = 0.0, totalGrossLoss = 0.0;
   int totalWins = 0, totalLosses = 0;
   int nearBlockCount = 0;

   for(int i = 0; i < g_learnedPatternCount; i++)
   {
      for(int s = 0; s < 3; s++)
      {
         sessW[s] += g_learnedPatterns[i].winsSession[s];
         sessL[s] += g_learnedPatterns[i].lossesSession[s];
         sessP[s] += g_learnedPatterns[i].profitSession[s];
      }
      hvW += g_learnedPatterns[i].winsHighVol;
      hvL += g_learnedPatterns[i].lossesHighVol;
      lvW += g_learnedPatterns[i].winsLowVol;
      lvL += g_learnedPatterns[i].lossesLowVol;
      totalGrossProfit += g_learnedPatterns[i].grossProfit;
      totalGrossLoss   += g_learnedPatterns[i].grossLoss;
      totalWins   += g_learnedPatterns[i].wins;
      totalLosses += g_learnedPatterns[i].losses;

      int t = g_learnedPatterns[i].wins + g_learnedPatterns[i].losses;
      if(t >= 5)
      {
         double wr = (double)g_learnedPatterns[i].wins / t;
         if(wr >= 0.30 && wr <= 0.40) nearBlockCount++;
      }
   }

   int sugCount = 0;

   // 1. Session analysis
   for(int s = 0; s < 3; s++)
   {
      int st = sessW[s] + sessL[s];
      if(st >= 5)
      {
         double swr = (double)sessW[s] / st;
         if(swr < 0.35)
         {
            sugCount++;
            Print("  SUGGEST #", sugCount, ": ", GetSessionName(s),
                  " session WR=", DoubleToString(swr * 100, 1), "% (", st, " trades)",
                  " net=", DoubleToString(sessP[s], 2),
                  " — consider TradingStartHour/TradingEndHour to avoid this session");
         }
         else if(swr >= 0.65 && sessP[s] > 0)
         {
            sugCount++;
            Print("  SUGGEST #", sugCount, ": ", GetSessionName(s),
                  " session WR=", DoubleToString(swr * 100, 1), "% is strong",
                  " net=", DoubleToString(sessP[s], 2),
                  " — consider focusing trading hours on this session");
         }
      }
   }

   // 2. Volatility analysis
   int hvT = hvW + hvL;
   int lvT = lvW + lvL;
   if(hvT >= 5 && lvT >= 5)
   {
      double hvWR = (double)hvW / hvT;
      double lvWR = (double)lvW / lvT;
      if(hvWR < 0.35 && lvWR >= 0.50)
      {
         sugCount++;
         Print("  SUGGEST #", sugCount, ": High-vol WR=", DoubleToString(hvWR * 100, 1),
               "% vs Low-vol WR=", DoubleToString(lvWR * 100, 1),
               "% — consider wider stops (ATRTrailMultiplier) or lower RiskPercent in volatile markets");
      }
      else if(lvWR < 0.35 && hvWR >= 0.50)
      {
         sugCount++;
         Print("  SUGGEST #", sugCount, ": Low-vol WR=", DoubleToString(lvWR * 100, 1),
               "% vs High-vol WR=", DoubleToString(hvWR * 100, 1),
               "% — bot works better in volatile markets, consider tighter ClassConsolidATRRatio to filter flat periods");
      }
   }

   // 3. R:R analysis
   if(totalWins > 0 && totalLosses > 0)
   {
      double avgWin  = totalGrossProfit / totalWins;
      double avgLoss = MathAbs(totalGrossLoss) / totalLosses;
      double actualRR = (avgLoss > 0) ? avgWin / avgLoss : 0;

      if(actualRR > 0)
      {
         sugCount++;
         Print("  SUGGEST #", sugCount, ": Actual R:R=", DoubleToString(actualRR, 2),
               " (avg win=", DoubleToString(avgWin, 2),
               " avg loss=", DoubleToString(avgLoss, 2), ")");

         if(actualRR < 1.0)
            Print("    -> R:R below 1.0 — wins smaller than losses. Consider increasing RewardRisk or tightening stop-loss");
         else if(actualRR > 3.0)
            Print("    -> R:R above 3.0 — trailing stop is capturing large moves effectively");
         else if(actualRR >= 1.5 && actualRR <= 2.5)
            Print("    -> R:R is healthy");
      }
   }

   // 4. Threshold analysis
   if(nearBlockCount > 0)
   {
      sugCount++;
      Print("  SUGGEST #", sugCount, ": ", nearBlockCount,
            " patterns have WR between 30-40% — near blocking threshold.",
            " Review MinLearnedWinRate if good patterns are being blocked");
   }

   // 5. Overall verdict
   int totalTrades = totalWins + totalLosses;
   if(totalTrades > 0)
   {
      double overallWR = (double)totalWins / totalTrades;
      double overallPF = (MathAbs(totalGrossLoss) > 0)
                       ? totalGrossProfit / MathAbs(totalGrossLoss) : 0;

      Print("  OVERALL: ", totalTrades, " trades | WR=", DoubleToString(overallWR * 100, 1),
            "% | PF=", DoubleToString(overallPF, 2),
            " | net=", DoubleToString(totalGrossProfit + totalGrossLoss, 2));

      if(overallWR >= 0.55 && overallPF >= 1.5)
         Print("  VERDICT: System is profitable — maintain current parameters");
      else if(overallWR < 0.40 || overallPF < 0.8)
         Print("  VERDICT: System needs tuning — run MT5 optimizer on key parameters");
      else
         Print("  VERDICT: System is marginal — review session/volatility suggestions above");
   }

   if(sugCount == 0)
      Print("  No specific suggestions — insufficient data or system is well-tuned");

   Print("========================================");
}

#endif // AI_MEMORY_MQH
