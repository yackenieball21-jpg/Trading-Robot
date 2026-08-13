//+------------------------------------------------------------------+
//|                                                AIScaffold.mqh |
//|  AI layer: ONNX scaffold, rule-based fallback, outcome logging   |
//|  v5.13 — Honest model state, no fake loading                     |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef AI_SCAFFOLD_MQH
#define AI_SCAFFOLD_MQH

#include "SymbolProfiler.mqh"
#include "MarketStateManager.mqh"
#include "IndicatorManager.mqh"
#include "ZoneManager.mqh"

// ONNX support: define ONNX_AVAILABLE manually if your MT5 build supports it (build 3490+)
// To enable: add  #define ONNX_AVAILABLE  before including this file, OR
//            uncomment the line below if your build has <Onnx.mqh>
// #define ONNX_AVAILABLE
#include "MarketClassifier.mqh"

// Backward compatibility value aliases
#ifndef REGIME_NONE
#define REGIME_NONE           MARKET_UNKNOWN
#endif
#ifndef REGIME_TREND_BULL
#define REGIME_TREND_BULL     MARKET_TREND_BULL
#endif
#ifndef REGIME_TREND_BEAR
#define REGIME_TREND_BEAR     MARKET_TREND_BEAR
#endif
#ifndef REGIME_RANGE
#define REGIME_RANGE          MARKET_RANGE
#endif
#ifndef REGIME_CONSOLIDATION
#define REGIME_CONSOLIDATION  MARKET_CONSOLIDATION
#endif

//+------------------------------------------------------------------+
//| AI State Struct                                                  |
//+------------------------------------------------------------------+
struct AIState
{
   bool   enabled;
   bool   modelLoaded;        // TRUE only if real ONNX inference works
   long   modelHandle;        // ONNX model handle (-1 = none)
   string modelVersion;       // version string
   int    regimeClass;        // 0=unknown, 1=trending, 2=ranging, 3=volatile
   double tradeScore;         // 0.0 to 1.0
   double riskMultiplier;     // 0.5 to 1.0
   double stopMultiplier;     // 0.85 to 1.20
   int    inferenceErrors;    // count of consecutive inference failures
   int    maxInferenceErrors; // threshold to disable model
   bool   usingRuleFallback;  // TRUE if using rules instead of real AI
};

//+------------------------------------------------------------------+
//| Setup context — passed from entry engine to AI scoring          |
//| SignalEngine fills this; AI only reads it.                       |
//+------------------------------------------------------------------+
struct SetupContext
{
   bool          isBuy;
   MARKET_REGIME regime;
   bool          isTrendTrade;
   string        zoneRole;        // SUPPORT_MAJOR, RESISTANCE_MAJOR, FLIP_SUPPORT, FLIP_RESISTANCE
   double        zoneStrength;
   double        zoneFreshness;
   int           zoneTouches;
   bool          isFlip;
   double        distToZoneATR;   // 0 = price inside zone
   double        distToTargetATR; // distance entry → TP in ATR
   double        stopSizeATR;     // distance entry → SL in ATR
   string        patternName;     // REJECTION, SWEEP_RECLAIM, BREAK_RETEST, NONE
   double        roomToNextATR;   // ATR distance to next opposing major zone
};

//+------------------------------------------------------------------+
//| Pending trade record for outcome logging                         |
//+------------------------------------------------------------------+
struct PendingTradeRecord
{
   bool     active;
   datetime entryTime;
   string   symbol;
   string   direction;
   double   entryPrice;
   double   stopLoss;
   double   takeProfit;
   double   lotSize;
   double   spreadAtEntry;
   double   stopDistPoints;
   double   tpDistPoints;
   int      regimeLabel;
   double   tradeScore;
   double   featureVector[24];
   string   zoneRole;
   bool     isFlip;
   string   patternName;
   bool     isTrendTrade;
   double   roomToNextATR;
   double   aiRiskMult;
   double   aiStopMult;
   ENUM_TIMEFRAMES timeframe;
   double   maxFavorableExcursion;
   double   maxAdverseExcursion;
   double   equityAtEntry;
};

//+------------------------------------------------------------------+
//| Lightweight Setup Memory for AIScaffold backward compatibility   |
//| Separate from AIMemory's richer LearnedPattern tracking         |
//+------------------------------------------------------------------+
struct SetupMemory
{
   string key;
   int    wins;
   int    losses;
};

#define MAX_SETUP_MEMORY 100
SetupMemory g_setupMemory[MAX_SETUP_MEMORY];
int g_setupMemoryCount = 0;

//+------------------------------------------------------------------+
//| Lightweight Trade-to-Key Mapping for AIScaffold                 |
//| Independent from AIMemory's learning context                     |
//+------------------------------------------------------------------+
struct TradeSetupMap
{
   ulong  ticket;
   string setupKey;
};

#define MAX_TRADE_SETUPS 50
TradeSetupMap g_tradeSetups[MAX_TRADE_SETUPS];
int g_tradeSetupCount = 0;

// AI tracking globals
int    g_aiTradeCount     = 0;
int    g_aiCorrectCount   = 0;
double g_aiFeatureVector[];
string g_aiOutcomeLogFile = "";
PendingTradeRecord g_pendingTrade;

//+------------------------------------------------------------------+
//| Initialize AI outcome logger                                     |
//+------------------------------------------------------------------+
void InitAIOutcomeLog()
{
   g_aiOutcomeLogFile = "ai_outcomes_" + _Symbol + ".csv";
   int fh = FileOpen(g_aiOutcomeLogFile, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh != INVALID_HANDLE)
   {
      if(FileSize(fh) == 0)
      {
         string header = "time,symbol,direction,timeframe,entry_price,sl,tp,lots,spread_pts,"
                         "sl_dist_pts,tp_dist_pts,regime,score,equity,"
                         "f0_spread,f1_ema50_slope,f2_adx,f3_atr,"
                         "f4_range,f5_class,f6_above_ema50,f7_below_ema50,"
                         "f8_close_vs_ema50,f9_reserved,f10_reserved,f11_atr_ratio,"
                         "outcome,pnl,mfe,mae,win_loss,close_time\n";
         FileWriteString(fh, header);
      }
      FileClose(fh);
   }
   g_pendingTrade.active = false;
}

//+------------------------------------------------------------------+
//| Build feature vector from current market state                   |
//+------------------------------------------------------------------+
void BuildFeatureVector(const IndicatorState &ind, const MarketState &ms,
                        const SymbolProfile &prof, int slopeLookback)
{
   ArrayResize(g_aiFeatureVector, 12);

   int lb = slopeLookback;
   if(lb < 2)  lb = 2;
   if(lb >= 50) lb = 49;

   g_aiFeatureVector[0]  = ms.spreadPoints;
   g_aiFeatureVector[1]  = (GetEMA50(ind, 1) - GetEMA50(ind, lb)) / prof.point;
   g_aiFeatureVector[2]  = GetADX(ind, 1);
   g_aiFeatureVector[3]  = GetATR(ind, 1) / prof.point;

   double rangeHigh = ind.highArr[1];
   double rangeLow  = ind.lowArr[1];
   for(int i = 2; i <= 10 && i < 60; i++)
   {
      if(ind.highArr[i] > rangeHigh) rangeHigh = ind.highArr[i];
      if(ind.lowArr[i]  < rangeLow)  rangeLow  = ind.lowArr[i];
   }
   g_aiFeatureVector[4]  = (rangeHigh - rangeLow) / prof.point;

   g_aiFeatureVector[5]  = (double)prof.classEnum;
   g_aiFeatureVector[6]  = (ind.closeArr[1] > GetEMA50(ind, 1)) ? 1.0 : 0.0;
   g_aiFeatureVector[7]  = (ind.closeArr[1] < GetEMA50(ind, 1)) ? 1.0 : 0.0;
   g_aiFeatureVector[8]  = (ind.closeArr[1] - GetEMA50(ind, 1)) / prof.point;
   g_aiFeatureVector[9]  = (GetPlusDI(ind, 1) > GetMinusDI(ind, 1)) ? 1.0 : 0.0;
   g_aiFeatureVector[10] = (GetMinusDI(ind, 1) > GetPlusDI(ind, 1)) ? 1.0 : 0.0;
   g_aiFeatureVector[11] = GetATR(ind, 1) / MathMax(GetATR(ind, 5), prof.point);
}

//+------------------------------------------------------------------+
//| Attempt to load ONNX model — real loading with honest fallback   |
//+------------------------------------------------------------------+
void LoadModel(AIState &ai, bool enableAI, const string modelPath)
{
   ai.enabled            = enableAI;
   ai.modelLoaded        = false;
   ai.modelHandle        = -1;
   ai.modelVersion       = "none";
   ai.regimeClass        = 0;
   ai.tradeScore         = 0.5;
   ai.riskMultiplier     = 1.0;
   ai.stopMultiplier     = 1.0;
   ai.inferenceErrors    = 0;
   ai.maxInferenceErrors = 5;
   ai.usingRuleFallback  = true;

   if(!enableAI)
   {
      Print("[AI] Layer disabled by input — using rule-based fallback");
      return;
   }

   if(StringLen(modelPath) == 0)
   {
      Print("[AI] No model path provided — using rule-based fallback");
      return;
   }

   // Check file exists in common or local path
   bool fileExists = FileIsExist(modelPath, FILE_COMMON) ||
                     FileIsExist(modelPath, 0);

   if(!fileExists)
   {
      Print("[AI] Model file not found: ", modelPath, " — using rule-based fallback");
      return;
   }

#ifdef ONNX_AVAILABLE
   // Attempt real ONNX load
   long handle = OnnxCreateFromFile(modelPath, ONNX_DEFAULT);
   if(handle == INVALID_HANDLE || handle < 0)
   {
      Print("[AI] OnnxCreateFromFile failed for: ", modelPath,
            " error=", GetLastError(), " — using rule-based fallback");
      return;
   }

   // Validate model with a probe inference (12 features → 1 output)
   const long inputShape[]  = {1, 12};
   const long outputShape[] = {1, 1};

   if(!OnnxSetInputShape(handle, 0, inputShape))
   {
      Print("[AI] Failed to set input shape — releasing model, using fallback");
      OnnxRelease(handle);
      return;
   }
   if(!OnnxSetOutputShape(handle, 0, outputShape))
   {
      Print("[AI] Failed to set output shape — releasing model, using fallback");
      OnnxRelease(handle);
      return;
   }

   // Probe inference with dummy data
   float probeInput[12];
   float probeOutput[1];
   ArrayInitialize(probeInput, 0.0f);
   probeOutput[0] = -999.0f;

   if(!OnnxRun(handle, ONNX_DEFAULT, probeInput, probeOutput))
   {
      Print("[AI] Probe inference failed — releasing model, using fallback");
      OnnxRelease(handle);
      return;
   }

   // Probe output must be finite in [0.0, 1.0]
   if(probeOutput[0] < 0.0f || probeOutput[0] > 1.0f || !MathIsValidNumber(probeOutput[0]))
   {
      Print("[AI] Probe output out of range: ", probeOutput[0],
            " — releasing model, using fallback");
      OnnxRelease(handle);
      return;
   }

   // SUCCESS — model loaded and validated
   ai.modelHandle    = handle;
   ai.modelLoaded    = true;
   ai.modelVersion   = modelPath;
   ai.usingRuleFallback = false;
   Print("[AI] ONNX model loaded and validated: ", modelPath,
         " probe_score=", DoubleToString(probeOutput[0], 4));
#else
   Print("[AI] ONNX not available on this MT5 build — using rule-based fallback");
#endif
}

//+------------------------------------------------------------------+
//| Run real ONNX inference — only called when model is confirmed    |
//+------------------------------------------------------------------+
bool RunONNXInference(AIState &ai, const double &features[], double &scoreOut)
{
#ifdef ONNX_AVAILABLE
   if(!ai.modelLoaded || ai.modelHandle == INVALID_HANDLE || ai.modelHandle < 0)
      return false;

   int fCount = ArraySize(features);
   if(fCount < 12)
      return false;

   float inputArr[12];
   float outputArr[1];
   outputArr[0] = -1.0f;

   for(int i = 0; i < 12; i++)
      inputArr[i] = (float)features[i];

   if(!OnnxRun(ai.modelHandle, ONNX_DEFAULT, inputArr, outputArr))
   {
      ai.inferenceErrors++;
      Print("[AI] Inference error #", ai.inferenceErrors,
            " — error=", GetLastError());

      if(ai.inferenceErrors >= ai.maxInferenceErrors)
      {
         Print("[AI] Too many inference errors — switching to rule-based fallback");
         OnnxRelease(ai.modelHandle);
         ai.modelHandle    = INVALID_HANDLE;
         ai.modelLoaded    = false;
         ai.usingRuleFallback = true;
      }
      return false;
   }

   ai.inferenceErrors = 0;
   scoreOut = (double)outputArr[0];
   scoreOut = MathMax(0.0, MathMin(1.0, scoreOut));
   return true;
#else
   return false;
#endif
}

//+------------------------------------------------------------------+
//| Release ONNX model                                               |
//+------------------------------------------------------------------+
void ReleaseModel(AIState &ai)
{
#ifdef ONNX_AVAILABLE
   if(ai.modelHandle != -1 && ai.modelHandle != INVALID_HANDLE)
   {
      OnnxRelease(ai.modelHandle);
      ai.modelHandle = -1;
      Print("AI: Model released");
   }
#endif
   ai.modelLoaded = false;
   ai.usingRuleFallback = true;
}

//+------------------------------------------------------------------+
//| Classify market regime — deterministic rules                     |
//+------------------------------------------------------------------+
void ClassifyMarketRegime(AIState &ai, const IndicatorState &ind,
                           const SymbolProfile &prof)
{
   double trendGap    = MathAbs(GetEMA50(ind, 1) - GetEMA50(ind, 3)) / prof.point;
   double requiredGap = prof.defaultMinTrendGapPoints;

   double rangeHigh = ind.highArr[1];
   double rangeLow  = ind.lowArr[1];
   for(int i = 2; i <= 10 && i < 60; i++)
   {
      if(ind.highArr[i] > rangeHigh) rangeHigh = ind.highArr[i];
      if(ind.lowArr[i]  < rangeLow)  rangeLow  = ind.lowArr[i];
   }
   double recentRange = (rangeHigh - rangeLow) / prof.point;

   if(trendGap >= requiredGap * 1.5)
      ai.regimeClass = 1; // Strong trend
   else if(trendGap < requiredGap * 0.5)
      ai.regimeClass = 2; // Ranging
   else if(recentRange > requiredGap * 3.0)
      ai.regimeClass = 3; // Volatile
   else
      ai.regimeClass = 0; // Unknown
}

//+------------------------------------------------------------------+
//| Score trade quality — deterministic rules                        |
//+------------------------------------------------------------------+
void ScoreTradeQuality(AIState &ai, const IndicatorState &ind,
                       const SymbolProfile &prof, int slopeLookback)
{
   double score = 0.5;
   double ema50slope = MathAbs(GetEMA50(ind, 1) - GetEMA50(ind, slopeLookback));
   if(ema50slope > GetATR(ind, 1) * 0.5) score += 0.15;
   if(ind.closeArr[1] > GetEMA50(ind, 1) || ind.closeArr[1] < GetEMA50(ind, 1)) score += 0.10;
   if(ai.regimeClass == 1) score += 0.10;

   double adxVal = GetADX(ind, 1);
   if(adxVal > 25.0) score += 0.05;

   if(score > 1.0) score = 1.0;
   if(score < 0.0) score = 0.0;
   ai.tradeScore = score;
}

//+------------------------------------------------------------------+
//| Score trade quality — context-aware (zone + pattern + regime)   |
//| Uses SetupContext filled by SignalEngine. AI never decides zone. |
//+------------------------------------------------------------------+
void ScoreTradeQuality(AIState &ai, const IndicatorState &ind,
                       const SymbolProfile &prof, int slopeLookback,
                       const SetupContext &ctx)
{
   double score = 0.0;

   // Regime alignment
   if(ctx.isTrendTrade)
   {
      bool aligned = (ctx.isBuy  && ctx.regime == REGIME_TREND_BULL) ||
                     (!ctx.isBuy && ctx.regime == REGIME_TREND_BEAR);
      score += aligned ? 0.20 : -0.15;
   }
   else if(ctx.regime == REGIME_RANGE)
      score += 0.15;

   // Zone quality
   if(ctx.zoneStrength > 0.70)      score += 0.20;
   else if(ctx.zoneStrength > 0.50) score += 0.12;
   else if(ctx.zoneStrength > 0.35) score += 0.05;
   else                             score -= 0.10;

   // Zone freshness
   if(ctx.zoneFreshness > 0.80)      score += 0.10;
   else if(ctx.zoneFreshness > 0.60) score += 0.06;
   else if(ctx.zoneFreshness < 0.30) score -= 0.08;

   // Touch decay — fresh zones score higher
   if(ctx.zoneTouches <= 1)      score += 0.08;
   else if(ctx.zoneTouches == 2) score += 0.04;
   else if(ctx.zoneTouches >= 4) score -= 0.10;

   // Flip bonus — flipped zone is a high-conviction level
   if(ctx.isFlip) score += 0.08;

   // Pattern quality
   if(ctx.patternName == "SWEEP_RECLAIM")     score += 0.15;
   else if(ctx.patternName == "BREAK_RETEST") score += 0.12;
   else if(ctx.patternName == "REJECTION")    score += 0.08;

   // Price proximity to zone (already inside/at zone = better)
   if(ctx.distToZoneATR <= 0.20)      score += 0.08;
   else if(ctx.distToZoneATR <= 0.50) score += 0.04;
   else if(ctx.distToZoneATR > 1.50)  score -= 0.10;

   // Room to target
   if(ctx.distToTargetATR >= 3.0)      score += 0.12;
   else if(ctx.distToTargetATR >= 2.0) score += 0.06;
   else if(ctx.distToTargetATR < 1.0)  score -= 0.15;

   // Stop efficiency
   if(ctx.stopSizeATR < 1.5)      score += 0.05;
   else if(ctx.stopSizeATR > 3.0) score -= 0.08;

   // Room to next opposing major zone
   if(ctx.roomToNextATR >= 4.0)      score += 0.10;
   else if(ctx.roomToNextATR >= 2.5) score += 0.05;
   else if(ctx.roomToNextATR < 1.0)  score -= 0.15;

   // ADX quality
   double adx = GetADX(ind, 1);
   if(ctx.isTrendTrade)
   {
      if(adx > 30.0)      score += 0.08;
      else if(adx > 20.0) score += 0.03;
      else if(adx < 15.0) score -= 0.08;
   }

   score += 0.40;  // neutral base — scores add/subtract from here
   ai.tradeScore = MathMax(0.0, MathMin(1.0, score));
}

//+------------------------------------------------------------------+
//| Fallback to pure rules                                           |
//+------------------------------------------------------------------+
void FallbackToRulesIfModelFails(AIState &ai)
{
   ai.riskMultiplier    = 1.0;
   ai.stopMultiplier    = 1.0;
   ai.tradeScore        = 0.5;
   ai.regimeClass       = 0;
   ai.usingRuleFallback = true;
}

//+------------------------------------------------------------------+
//| Run model inference — ONNX first, rule-based fallback            |
//+------------------------------------------------------------------+
void RunModelInference(AIState &ai, const IndicatorState &ind,
                       const MarketState &ms, const SymbolProfile &prof,
                       int slopeLookback)
{
   BuildFeatureVector(ind, ms, prof, slopeLookback);

   if(!ai.enabled)
   {
      FallbackToRulesIfModelFails(ai);
      return;
   }

   ClassifyMarketRegime(ai, ind, prof);

   // Try real ONNX first
   double onnxScore = 0.5;
   bool   onnxUsed  = RunONNXInference(ai, g_aiFeatureVector, onnxScore);

   if(onnxUsed)
   {
      ai.tradeScore        = onnxScore;
      ai.usingRuleFallback = false;
      Print("[AI] ONNX inference score=", DoubleToString(onnxScore, 4));
   }
   else
   {
      // Rule-based fallback
      ScoreTradeQuality(ai, ind, prof, slopeLookback);
      ai.usingRuleFallback = true;
   }

   // Risk/stop multipliers based on score
   double mult = 0.5 + ai.tradeScore * 0.5;
   ai.riskMultiplier = MathMax(0.5, MathMin(1.0, mult));

   double stopMult = 1.0;
   if(ai.regimeClass == 3)      stopMult = 1.15;
   else if(ai.regimeClass == 1) stopMult = 0.90;
   ai.stopMultiplier = MathMax(0.85, MathMin(1.20, stopMult));
}

//+------------------------------------------------------------------+
//| Run inference with full setup context (replaces generic version) |
//| SetupContext must be built from the valid EntryDecision.         |
//+------------------------------------------------------------------+
void RunModelInferenceEx(AIState &ai, const IndicatorState &ind,
                         const MarketState &ms, const SymbolProfile &prof,
                         int slopeLookback, const SetupContext &ctx)
{
   if(!ai.enabled)
   {
      FallbackToRulesIfModelFails(ai);
      return;
   }

   ClassifyMarketRegime(ai, ind, prof);
   BuildFeatureVector(ind, ms, prof, slopeLookback);

   // Try ONNX first — if successful blend with context score
   double onnxScore = 0.5;
   bool   onnxUsed  = RunONNXInference(ai, g_aiFeatureVector, onnxScore);

   // Always run context-aware rules (zone/pattern/regime)
   ScoreTradeQuality(ai, ind, prof, slopeLookback, ctx);
   double ruleScore = ai.tradeScore;

   if(onnxUsed)
   {
      // Blend: 60% ONNX + 40% rule-based context score
      ai.tradeScore        = onnxScore * 0.60 + ruleScore * 0.40;
      ai.usingRuleFallback = false;
      Print("[AI_EX] ONNX=", DoubleToString(onnxScore, 3),
            " rules=", DoubleToString(ruleScore, 3),
            " blended=", DoubleToString(ai.tradeScore, 3));
   }
   else
   {
      ai.tradeScore        = ruleScore;
      ai.usingRuleFallback = true;
   }

   double score = ai.tradeScore;

   // Risk multiplier: strong setup = full risk, medium = reduced
   ai.riskMultiplier = (score >= 0.70) ? 1.00 : (score >= 0.55) ? 0.70 : 0.50;

   // Stop multiplier: range trades slightly wider, clean trends slightly tighter
   double stopMult = 1.0;
   if(!ctx.isTrendTrade)  stopMult = 1.10;
   else if(score >= 0.70) stopMult = 0.92;
   ai.stopMultiplier = MathMax(0.85, MathMin(1.20, stopMult));

   Print("[AI_SCORE] dir=", (ctx.isBuy ? "BUY" : "SELL"),
         " score=", DoubleToString(score, 3),
         " risk=", DoubleToString(ai.riskMultiplier, 2),
         " stop=", DoubleToString(ai.stopMultiplier, 2),
         " zone=", ctx.zoneRole,
         " pattern=", ctx.patternName,
         " roomATR=", DoubleToString(ctx.roomToNextATR, 1));
}

//+------------------------------------------------------------------+
//| Record entry for pending outcome log                             |
//+------------------------------------------------------------------+
void RecordEntryForOutcome(const AIState &ai, const MarketState &ms,
                            const SymbolProfile &prof, string direction,
                            double entry, double sl, double tp, double lots)
{
   g_pendingTrade.active         = true;
   g_pendingTrade.entryTime      = TimeCurrent();
   g_pendingTrade.symbol         = _Symbol;
   g_pendingTrade.direction      = direction;
   g_pendingTrade.entryPrice     = entry;
   g_pendingTrade.stopLoss       = sl;
   g_pendingTrade.takeProfit     = tp;
   g_pendingTrade.lotSize        = lots;
   g_pendingTrade.spreadAtEntry  = ms.spreadPoints;
   g_pendingTrade.stopDistPoints = MathAbs(entry - sl) / prof.point;
   g_pendingTrade.tpDistPoints   = MathAbs(entry - tp) / prof.point;
   g_pendingTrade.regimeLabel    = ai.regimeClass;
   g_pendingTrade.tradeScore     = ai.tradeScore;
   g_pendingTrade.timeframe      = Period();
   g_pendingTrade.maxFavorableExcursion = 0.0;
   g_pendingTrade.maxAdverseExcursion   = 0.0;
   g_pendingTrade.equityAtEntry  = AccountInfoDouble(ACCOUNT_EQUITY);

   for(int i = 0; i < 24 && i < ArraySize(g_aiFeatureVector); i++)
      g_pendingTrade.featureVector[i] = g_aiFeatureVector[i];
}

//+------------------------------------------------------------------+
//| Update MFE/MAE on each tick while position is open               |
//+------------------------------------------------------------------+
void UpdateMFEMAE(const MarketState &ms)
{
   if(!g_pendingTrade.active) return;

   double currentPrice = (g_pendingTrade.direction == "BUY") ? ms.bid : ms.ask;
   double excursion = 0.0;

   if(g_pendingTrade.direction == "BUY")
      excursion = currentPrice - g_pendingTrade.entryPrice;
   else
      excursion = g_pendingTrade.entryPrice - currentPrice;

   if(excursion > g_pendingTrade.maxFavorableExcursion)
      g_pendingTrade.maxFavorableExcursion = excursion;

   if(excursion < 0 && MathAbs(excursion) > g_pendingTrade.maxAdverseExcursion)
      g_pendingTrade.maxAdverseExcursion = MathAbs(excursion);
}

//+------------------------------------------------------------------+
//| Log full labeled outcome on trade close                          |
//+------------------------------------------------------------------+
void LogLabeledOutcome(double pnl, const SymbolProfile &prof)
{
   if(!g_pendingTrade.active) return;
   if(g_aiOutcomeLogFile == "") return;

   int fh = FileOpen(g_aiOutcomeLogFile, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE)
   {
      g_pendingTrade.active = false;
      return;
   }

   FileSeek(fh, 0, SEEK_END);

   string winLoss = (pnl > 0) ? "WIN" : (pnl < 0 ? "LOSS" : "SCRATCH");
   double mfePts = g_pendingTrade.maxFavorableExcursion / prof.point;
   double maePts = g_pendingTrade.maxAdverseExcursion / prof.point;

   string featureStr = "";
   for(int i = 0; i < 16; i++)
   {
      if(i > 0) featureStr += ",";
      featureStr += DoubleToString(g_pendingTrade.featureVector[i], 4);
   }

   string line = TimeToString(g_pendingTrade.entryTime, TIME_DATE | TIME_SECONDS) + "," +
                 g_pendingTrade.symbol + "," +
                 g_pendingTrade.direction + "," +
                 EnumToString(g_pendingTrade.timeframe) + "," +
                 DoubleToString(g_pendingTrade.entryPrice, prof.digits) + "," +
                 DoubleToString(g_pendingTrade.stopLoss, prof.digits) + "," +
                 DoubleToString(g_pendingTrade.takeProfit, prof.digits) + "," +
                 DoubleToString(g_pendingTrade.lotSize, 4) + "," +
                 DoubleToString(g_pendingTrade.spreadAtEntry, 1) + "," +
                 DoubleToString(g_pendingTrade.stopDistPoints, 1) + "," +
                 DoubleToString(g_pendingTrade.tpDistPoints, 1) + "," +
                 IntegerToString(g_pendingTrade.regimeLabel) + "," +
                 DoubleToString(g_pendingTrade.tradeScore, 4) + "," +
                 DoubleToString(g_pendingTrade.equityAtEntry, 2) + "," +
                 featureStr + "," +
                 winLoss + "," +
                 DoubleToString(pnl, 2) + "," +
                 DoubleToString(mfePts, 1) + "," +
                 DoubleToString(maePts, 1) + "," +
                 winLoss + "," +
                 TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);

   FileWriteString(fh, line + "\n");
   FileClose(fh);

   g_pendingTrade.active = false;
}

//+------------------------------------------------------------------+
//| Detect model drift — rolling window accuracy check               |
//+------------------------------------------------------------------+
bool DetectModelDrift(const AIState &ai)
{
   if(!ai.enabled || !ai.modelLoaded) return false;
   if(g_aiTradeCount < 20) return false;

   double accuracy = (double)g_aiCorrectCount / (double)g_aiTradeCount;
   if(accuracy < 0.40)
   {
      Print("AI DRIFT: Accuracy ", DoubleToString(accuracy * 100.0, 1),
            "% over ", g_aiTradeCount, " trades - reverting to rules");
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| BuildSetupKey — DEPRECATED wrapper for AIMemory compatibility    |
//| Kept for old code, but should use AIMemory pattern keys directly |
//+------------------------------------------------------------------+
string BuildSetupKey(const string direction, const IndicatorState &ind,
                     ENUM_ZONE_TYPE zoneType)
{
   double emaSlope = MathAbs(GetEMA50(ind, 1) - GetEMA50(ind, 5));
   string trendTag = (emaSlope > GetATR(ind, 1) * 0.5) ? "TREND" : "RANGE";
   double adx = GetADX(ind, 1);
   string adxTag = (adx >= 30) ? "ADXhigh" : (adx <= 15) ? "ADXlow" : "ADXmid";
   return direction + "|" + trendTag + "|" + adxTag + "|" + ZoneTypeToString(zoneType);
}

int FindSetupIndex(const string key)
{
   for(int i = 0; i < g_setupMemoryCount; i++)
      if(g_setupMemory[i].key == key)
         return i;
   return -1;
}

//+------------------------------------------------------------------+
//| GetSetupConfidence — AIScaffold's lightweight confidence         |
//| Independent from AIMemory's learned patterns                     |
//+------------------------------------------------------------------+
double GetSetupConfidence(const string key)
{
   int idx = FindSetupIndex(key);
   if(idx < 0) return 0.5;
   
   int total = g_setupMemory[idx].wins + g_setupMemory[idx].losses;
   if(total <= 0) return 0.5;
   
   return (double)g_setupMemory[idx].wins / (double)total;
}

//+------------------------------------------------------------------+
//| UpdateSetupOutcome — AIScaffold's lightweight outcome tracker    |
//| Independent from AIMemory's learned patterns                     |
//+------------------------------------------------------------------+
void UpdateSetupOutcome(const string key, double pnl)
{
   int idx = FindSetupIndex(key);
   if(idx < 0)
   {
      if(g_setupMemoryCount >= MAX_SETUP_MEMORY) return;
      idx = g_setupMemoryCount++;
      g_setupMemory[idx].key = key;
      g_setupMemory[idx].wins = 0;
      g_setupMemory[idx].losses = 0;
   }
   
   if(pnl > 0.0)
      g_setupMemory[idx].wins++;
   else
      g_setupMemory[idx].losses++;
}

//+------------------------------------------------------------------+
//| LoadSetupMemory — AIScaffold's lightweight persistence           |
//| Separate from AIMemory's learned patterns                        |
//+------------------------------------------------------------------+
void LoadSetupMemory()
{
   g_setupMemoryCount = 0;
   // Lightweight CSV loading - not implemented for simplicity
   // AIMemory handles rich pattern persistence
}

//+------------------------------------------------------------------+
//| SaveSetupMemory — AIScaffold's lightweight persistence           |
//| Separate from AIMemory's learned patterns                        |
//+------------------------------------------------------------------+
void SaveSetupMemory()
{
   // Lightweight CSV saving - not implemented for simplicity
   // AIMemory handles rich pattern persistence
}

//+------------------------------------------------------------------+
//| RegisterTradeSetup — AIScaffold's lightweight trade mapping      |
//| Independent from AIMemory's learning context                     |
//+------------------------------------------------------------------+
void RegisterTradeSetup(ulong ticket, const string setupKey)
{
   // Check if already registered
   for(int i = 0; i < g_tradeSetupCount; i++)
      if(g_tradeSetups[i].ticket == ticket)
         return;
   
   if(g_tradeSetupCount >= MAX_TRADE_SETUPS) return;
   
   g_tradeSetups[g_tradeSetupCount].ticket = ticket;
   g_tradeSetups[g_tradeSetupCount].setupKey = setupKey;
   g_tradeSetupCount++;
}

//+------------------------------------------------------------------+
//| FindTradeSetup — AIScaffold's lightweight trade lookup           |
//| Independent from AIMemory's learning context                     |
//+------------------------------------------------------------------+
string FindTradeSetup(ulong ticket)
{
   for(int i = 0; i < g_tradeSetupCount; i++)
      if(g_tradeSetups[i].ticket == ticket)
         return g_tradeSetups[i].setupKey;
   return "";
}

//+------------------------------------------------------------------+
//| RemoveTradeSetup — AIScaffold's lightweight trade cleanup        |
//| Independent from AIMemory's learning context                     |
//+------------------------------------------------------------------+
void RemoveTradeSetup(ulong ticket)
{
   for(int i = 0; i < g_tradeSetupCount; i++)
   {
      if(g_tradeSetups[i].ticket == ticket)
      {
         // Shift remaining entries down
         for(int j = i; j < g_tradeSetupCount - 1; j++)
            g_tradeSetups[j] = g_tradeSetups[j + 1];
         g_tradeSetupCount--;
         return;
      }
   }
}

#endif // AI_SCAFFOLD_MQH
