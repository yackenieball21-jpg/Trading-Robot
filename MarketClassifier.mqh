//+------------------------------------------------------------------+
//|                                            MarketClassifier.mqh |
//|  4-state market regime classifier                                |
//|  Uses EMA50, EMA200, ADX, ATR-normalized separation, slope       |
//|                                                                   |
//|  Priority: Consolidation (compressed) > Trend > Range > Unknown  |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef __MARKET_CLASSIFIER_MQH__
#define __MARKET_CLASSIFIER_MQH__

enum MARKET_REGIME
{
   MARKET_UNKNOWN = 0,
   MARKET_TREND_BULL,
   MARKET_TREND_BEAR,
   MARKET_RANGE,
   MARKET_CONSOLIDATION,
   MARKET_BREAKOUT_BULL,
   MARKET_BREAKOUT_BEAR,
   MARKET_REVERSAL_BULL,
   MARKET_REVERSAL_BEAR
};

class CMarketClassifier
{
private:
   // Configurable thresholds (set via Configure)
   double m_trendADX;          // ADX >= this for trend (default 25)
   double m_consolidADX;       // ADX < this for consolidation (default 18)
   double m_trendSepATR;       // |EMA50-EMA200|/ATR >= this for trend (default 0.80)
   double m_rangeSepATR;       // |EMA50-EMA200|/ATR <= this for range (default 0.35)
   double m_slopeThreshold;    // min EMA50 slope pts for trend (default 0)
   double m_touchDistATR;      // price within this*ATR of EMA50 = compressed (default 0.15)
   int    m_slopeLookback;     // bars for slope calc (default 3)
   bool   m_useSlopeFilter;    // require slope for trend

   //--- Internal helpers ---

   // EMA50 slope in points over m_slopeLookback bars
   double GetSlopePoints(double ema50Now, double ema50Past) const
   {
      return ema50Now - ema50Past;
   }

   // ATR-normalized EMA separation: |EMA50 - EMA200| / ATR
   double GetNormSep(double ema50, double ema200, double atr) const
   {
      if(atr <= 0) return 0;
      return MathAbs(ema50 - ema200) / atr;
   }

   // Is price compressed around EMA50?
   bool IsPriceCompressed(double close, double ema50, double atr) const
   {
      if(atr <= 0) return false;
      return (MathAbs(close - ema50) <= atr * m_touchDistATR);
   }

   // Bull trend: EMA50>EMA200, slope up, ADX strong, separation wide
   bool IsBullTrend(double close, double ema50, double ema200,
                    double ema50Past, double adx, double atr) const
   {
      if(ema50 <= ema200)                return false;
      if(adx < m_trendADX)              return false;
      if(GetNormSep(ema50, ema200, atr) < m_trendSepATR) return false;
      if(m_useSlopeFilter && GetSlopePoints(ema50, ema50Past) <= m_slopeThreshold)
         return false;
      return true;
   }

   // Bear trend: EMA50<EMA200, slope down, ADX strong, separation wide
   bool IsBearTrend(double close, double ema50, double ema200,
                    double ema50Past, double adx, double atr) const
   {
      if(ema50 >= ema200)               return false;
      if(adx < m_trendADX)             return false;
      if(GetNormSep(ema50, ema200, atr) < m_trendSepATR) return false;
      if(m_useSlopeFilter && GetSlopePoints(ema50, ema50Past) >= -m_slopeThreshold)
         return false;
      return true;
   }

   // Consolidation: very low ADX or price compressed around EMA50
   bool IsConsolidating(double close, double ema50, double ema200,
                        double adx, double atr) const
   {
      if(adx < m_consolidADX)           return true;
      if(IsPriceCompressed(close, ema50, atr)
         && GetNormSep(ema50, ema200, atr) < m_rangeSepATR)
         return true;
      return false;
   }

   // Range: not trending, not ultra-compressed, moderate ADX, modest EMA sep
   bool IsRanging(double close, double ema50, double ema200,
                  double adx, double atr) const
   {
      if(adx >= m_trendADX)             return false;  // too strong for range
      double sep = GetNormSep(ema50, ema200, atr);
      if(sep > m_trendSepATR)           return false;  // EMAs too far apart
      if(sep <= m_rangeSepATR && adx < m_consolidADX)
         return false;  // this is consolidation, not range
      return true;
   }

public:
   CMarketClassifier()
   {
      m_trendADX       = 25.0;
      m_consolidADX    = 18.0;
      m_trendSepATR    = 0.80;
      m_rangeSepATR    = 0.35;
      m_slopeThreshold = 0.0;
      m_touchDistATR   = 0.15;
      m_slopeLookback  = 3;
      m_useSlopeFilter = true;
   }

   void Configure(double trendSepATR,
                  double consolidADXRatio,
                  double rangeSepATR,
                  bool useSlopeFilter = true,
                  int slopeLookback = 3)
   {
      m_trendSepATR    = (trendSepATR > 0)    ? trendSepATR    : 0.80;
      m_consolidADX    = (consolidADXRatio > 0)? consolidADXRatio * 100.0 : 18.0;
      if(m_consolidADX > 50) m_consolidADX = consolidADXRatio; // already in ADX units
      m_rangeSepATR    = (rangeSepATR > 0)    ? rangeSepATR    : 0.35;
      m_useSlopeFilter = useSlopeFilter;
      m_slopeLookback  = MathMax(1, slopeLookback);
   }

   // Extended configure with all thresholds
   void ConfigureFull(double trendADX,    double consolidADX,
                      double trendSepATR, double rangeSepATR,
                      double touchDistATR, double slopeThreshold,
                      bool useSlopeFilter, int slopeLookback)
   {
      m_trendADX       = (trendADX > 0)       ? trendADX       : 25.0;
      m_consolidADX    = (consolidADX > 0)    ? consolidADX    : 18.0;
      m_trendSepATR    = (trendSepATR > 0)    ? trendSepATR    : 0.80;
      m_rangeSepATR    = (rangeSepATR > 0)    ? rangeSepATR    : 0.35;
      m_touchDistATR   = (touchDistATR > 0)   ? touchDistATR   : 0.15;
      m_slopeThreshold = (slopeThreshold >= 0)? slopeThreshold : 0.0;
      m_useSlopeFilter = useSlopeFilter;
      m_slopeLookback  = MathMax(1, slopeLookback);
   }

   int GetSlopeLookback() const { return m_slopeLookback; }

   string ToString(MARKET_REGIME state) const
   {
      switch(state)
      {
         case MARKET_TREND_BULL:     return "TREND_BULL";
         case MARKET_TREND_BEAR:     return "TREND_BEAR";
         case MARKET_RANGE:          return "RANGE";
         case MARKET_CONSOLIDATION:  return "CONSOLIDATION";
         default:                    return "UNKNOWN";
      }
   }

   //--- Primary classifier ---
   // Accepts full indicator state: close, EMA50, EMA200, ADX, ATR
   // ema50Past = EMA50 at (shift + slopeLookback) for slope calc
   MARKET_REGIME Classify(double closePrice,
                          double ema50Current,
                          double ema50Past,
                          double atrCurrent,
                          double atrAverage,
                          double ema200Current = 0,
                          double adxCurrent = 0) const
   {
      if(ema50Current <= 0.0 || atrCurrent <= 0.0)
         return MARKET_UNKNOWN;

      // If EMA200 not supplied, fall back to simple EMA50-only logic
      double e200 = (ema200Current > 0) ? ema200Current : ema50Current;
      double adx  = (adxCurrent > 0)    ? adxCurrent    : 0.0;

      // 1. Consolidation first (very compressed market)
      if(IsConsolidating(closePrice, ema50Current, e200, adx, atrCurrent))
         return MARKET_CONSOLIDATION;

      // 2. Trend detection (strong directional move)
      if(IsBullTrend(closePrice, ema50Current, e200, ema50Past, adx, atrCurrent))
         return MARKET_TREND_BULL;

      if(IsBearTrend(closePrice, ema50Current, e200, ema50Past, adx, atrCurrent))
         return MARKET_TREND_BEAR;

      // 3. Range (not trending, not ultra-compressed)
      if(IsRanging(closePrice, ema50Current, e200, adx, atrCurrent))
         return MARKET_RANGE;

      // 4. Fallback
      return MARKET_CONSOLIDATION;
   }

   bool AllowBuy(MARKET_REGIME state) const
   {
      return (state == MARKET_TREND_BULL || state == MARKET_RANGE);
   }

   bool AllowSell(MARKET_REGIME state) const
   {
      return (state == MARKET_TREND_BEAR || state == MARKET_RANGE);
   }

   bool IsTrendBull(MARKET_REGIME state) const
   {
      return (state == MARKET_TREND_BULL);
   }

   bool IsTrendBear(MARKET_REGIME state) const
   {
      return (state == MARKET_TREND_BEAR);
   }

   bool IsRange(MARKET_REGIME state) const
   {
      return (state == MARKET_RANGE);
   }

   bool IsConsolidation(MARKET_REGIME state) const
   {
      return (state == MARKET_CONSOLIDATION);
   }

   //+------------------------------------------------------------------+
   //| Trend strength score 0.0–1.0                                     |
   //| Combines ADX, EMA separation, and slope into a single score      |
   //| Used directly by SignalEngine to weight entry confidence          |
   //+------------------------------------------------------------------+
   double TrendStrengthScore(double ema50Now, double ema50Past,
                              double ema200, double adx,
                              double atr) const
   {
      if(atr <= 0.0) return 0.0;

      double score = 0.0;

      // ADX component (0.0–0.40)
      if(adx >= 40.0)      score += 0.40;
      else if(adx >= 30.0) score += 0.30;
      else if(adx >= 25.0) score += 0.20;
      else if(adx >= 18.0) score += 0.08;

      // EMA separation component (0.0–0.35)
      double sep = GetNormSep(ema50Now, ema200, atr);
      if(sep >= 2.0)      score += 0.35;
      else if(sep >= 1.2) score += 0.25;
      else if(sep >= 0.8) score += 0.15;
      else if(sep >= 0.4) score += 0.06;

      // Slope momentum component (0.0–0.25)
      double slopeATR = MathAbs(GetSlopePoints(ema50Now, ema50Past)) / atr;
      if(slopeATR >= 0.20)      score += 0.25;
      else if(slopeATR >= 0.12) score += 0.15;
      else if(slopeATR >= 0.06) score += 0.08;

      if(score > 1.0) score = 1.0;
      return score;
   }

   //+------------------------------------------------------------------+
   //| Range quality score 0.0–1.0                                      |
   //| High score = clean, tradeable range (low ADX + tight EMA stack)  |
   //+------------------------------------------------------------------+
   double RangeQualityScore(double ema50Now, double ema200,
                             double adx, double atr) const
   {
      if(atr <= 0.0) return 0.0;

      double score = 0.0;

      // Low ADX = cleaner range
      if(adx < 15.0)      score += 0.40;
      else if(adx < 20.0) score += 0.28;
      else if(adx < 25.0) score += 0.15;

      // Tight EMA separation = balanced range
      double sep = GetNormSep(ema50Now, ema200, atr);
      if(sep < 0.20)      score += 0.35;
      else if(sep < 0.40) score += 0.22;
      else if(sep < 0.60) score += 0.10;

      // Price near EMA50 = midrange
      score += 0.25;  // base — always get some credit in range

      if(score > 1.0) score = 1.0;
      return score;
   }

   //+------------------------------------------------------------------+
   //| Combined regime confidence: how strongly is this regime valid?   |
   //| Returns 0.0–1.0 regardless of which regime is active            |
   //+------------------------------------------------------------------+
   double RegimeConfidence(MARKET_REGIME state,
                            double ema50Now, double ema50Past,
                            double ema200, double adx, double atr) const
   {
      switch(state)
      {
         case MARKET_TREND_BULL:
         case MARKET_TREND_BEAR:
            return TrendStrengthScore(ema50Now, ema50Past, ema200, adx, atr);

         case MARKET_RANGE:
            return RangeQualityScore(ema50Now, ema200, adx, atr);

         case MARKET_CONSOLIDATION:
            // Consolidation confidence = inverse of trend score
            return 1.0 - TrendStrengthScore(ema50Now, ema50Past, ema200, adx, atr);

         default:
            return 0.0;
      }
   }

   //+------------------------------------------------------------------+
   //| Is the regime strong enough to trade? (confidence >= threshold)  |
   //+------------------------------------------------------------------+
   bool IsRegimeTradeable(MARKET_REGIME state,
                           double ema50Now, double ema50Past,
                           double ema200, double adx, double atr,
                           double minConfidence = 0.35) const
   {
      if(state == MARKET_UNKNOWN || state == MARKET_CONSOLIDATION)
         return false;

      return RegimeConfidence(state, ema50Now, ema50Past, ema200, adx, atr) >= minConfidence;
   }
};

#endif // __MARKET_CLASSIFIER_MQH__
