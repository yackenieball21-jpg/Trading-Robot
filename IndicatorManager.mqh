//+------------------------------------------------------------------+
//|                                            IndicatorManager.mqh |
//|  Indicator init, release, copy with diagnostics, bar history     |
//|  enforcement, BarsCalculated checks, value getters               |
//|  v5.13                                                           |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef INDICATOR_MANAGER_MQH
#define INDICATOR_MANAGER_MQH

//+------------------------------------------------------------------+
//| Indicator State Struct                                           |
//+------------------------------------------------------------------+
struct IndicatorState
{
   double ema50[50];
   double ema200[50];
   double adx[20];
   double atr[20];       // live ATR (ATRPeriod)
   double atrRef[20];    // reference ATR (ATRReferencePeriod) for multiplier scaling
   double atrTrail[20];
   double plusDI[20];
   double minusDI[20];
   double closeArr[200];
   double highArr[200];
   double lowArr[200];
   double openArr[200];
};

//+------------------------------------------------------------------+
//| MTF State — stub kept for compile compatibility                  |
//+------------------------------------------------------------------+
struct MTFState
{
   bool   valid;
};

// Indicator handles — execution timeframe (set via g_indicatorTF)
int h_ema50    = INVALID_HANDLE;
int h_ema200   = INVALID_HANDLE;
int h_adx      = INVALID_HANDLE;
int h_atr      = INVALID_HANDLE;
int h_atrRef   = INVALID_HANDLE;  // reference-period ATR for scaling multipliers
int h_atrTrail = INVALID_HANDLE;

// Indicator handles — HTF bias timeframe (set via g_htfBiasTF)
int h_d1_ema50  = INVALID_HANDLE;
int h_d1_ema200 = INVALID_HANDLE;
int h_d1_adx    = INVALID_HANDLE;
int h_d1_atr    = INVALID_HANDLE;

// HTF bias indicator state (timeframe set via g_htfBiasTF)
struct D1IndicatorState
{
   double ema50[10];
   double ema200[10];
   double adx[10];
   double atr[10];
   double closeArr[20];
   double highArr[20];
   double lowArr[20];
   double openArr[20];
   bool   valid;
};

D1IndicatorState g_d1Ind;

// Indicator timeframes (set from EA inputs via SetIndicatorTimeframe / g_htfBiasTF)
ENUM_TIMEFRAMES g_indicatorTF = PERIOD_H4;   // Execution timeframe (default, override from input)
ENUM_TIMEFRAMES g_htfBiasTF   = PERIOD_D1;   // HTF bias timeframe (default, override from input)
ENUM_TIMEFRAMES g_zoneTF      = PERIOD_H4;   // Zone detection timeframe (default, override from input)

// New bar detection
datetime g_lastBarTime    = 0;
datetime g_lastD1BarTime  = 0;

void SetIndicatorTimeframe(ENUM_TIMEFRAMES tf)
{
   g_indicatorTF = tf;
   g_lastBarTime = 0;
}

// Per-timeframe new bar detection state
datetime g_lastBarTimeMap[10];  // Index by timeframe enum hash
int GetTFMapIndex(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return 0;
      case PERIOD_M5:  return 1;
      case PERIOD_M15: return 2;
      case PERIOD_M30: return 3;
      case PERIOD_H1:  return 4;
      case PERIOD_H4:  return 5;
      case PERIOD_D1:  return 6;
      case PERIOD_W1:  return 7;
      case PERIOD_MN1: return 8;
      default:         return 9;
   }
}

bool IsNewBarOnTF(ENUM_TIMEFRAMES tf)
{
   int idx = GetTFMapIndex(tf);
   datetime now = iTime(_Symbol, tf, 0);
   if(now != g_lastBarTimeMap[idx])
   {
      g_lastBarTimeMap[idx] = now;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Initialize all indicator handles (H4 execution + D1 bias)        |
//+------------------------------------------------------------------+
bool InitIndicators(int atrPeriod = 20, int atrTrailPeriod = 20,
                    int adxPeriod = 14, int atrRefPeriod = 20)
{
   // Execution timeframe indicators (g_indicatorTF)
   h_ema50  = iMA(_Symbol, g_indicatorTF, 50, 0, MODE_EMA, PRICE_CLOSE);
   h_ema200 = iMA(_Symbol, g_indicatorTF, 200, 0, MODE_EMA, PRICE_CLOSE);
   h_adx    = iADX(_Symbol, g_indicatorTF, adxPeriod);
   h_atr    = iATR(_Symbol, g_indicatorTF, atrPeriod);

   if(atrRefPeriod == atrPeriod)
      h_atrRef = h_atr;
   else
      h_atrRef = iATR(_Symbol, g_indicatorTF, atrRefPeriod);

   if(atrTrailPeriod == atrPeriod)
      h_atrTrail = h_atr;
   else if(atrTrailPeriod == atrRefPeriod)
      h_atrTrail = h_atrRef;
   else
      h_atrTrail = iATR(_Symbol, g_indicatorTF, atrTrailPeriod);

   // HTF bias indicators (g_htfBiasTF)
   h_d1_ema50  = iMA(_Symbol, g_htfBiasTF, 50, 0, MODE_EMA, PRICE_CLOSE);
   h_d1_ema200 = iMA(_Symbol, g_htfBiasTF, 200, 0, MODE_EMA, PRICE_CLOSE);
   h_d1_adx    = iADX(_Symbol, g_htfBiasTF, adxPeriod);
   h_d1_atr    = iATR(_Symbol, g_htfBiasTF, atrPeriod);

   bool ok = true;
   if(h_ema50    == INVALID_HANDLE) { Print("IND ERROR: Failed to create EMA50 handle");      ok = false; }
   if(h_ema200   == INVALID_HANDLE) { Print("IND ERROR: Failed to create EMA200 handle");     ok = false; }
   if(h_adx      == INVALID_HANDLE) { Print("IND ERROR: Failed to create ADX handle");        ok = false; }
   if(h_atr      == INVALID_HANDLE) { Print("IND ERROR: Failed to create ATR handle");        ok = false; }
   if(h_atrRef   == INVALID_HANDLE) { Print("IND ERROR: Failed to create ATR Ref handle");    ok = false; }
   if(h_atrTrail == INVALID_HANDLE) { Print("IND ERROR: Failed to create ATR Trail handle");  ok = false; }
   if(h_d1_ema50 == INVALID_HANDLE) { Print("IND ERROR: Failed to create D1 EMA50 handle");   ok = false; }
   if(h_d1_ema200== INVALID_HANDLE) { Print("IND ERROR: Failed to create D1 EMA200 handle");  ok = false; }
   if(h_d1_adx   == INVALID_HANDLE) { Print("IND ERROR: Failed to create D1 ADX handle");     ok = false; }
   if(h_d1_atr   == INVALID_HANDLE) { Print("IND ERROR: Failed to create D1 ATR handle");     ok = false; }

   if(ok)
   {
      Print("[TF_CONFIG] execution_tf=", EnumToString(g_indicatorTF),
            " bias_tf=", EnumToString(g_htfBiasTF),
            " zone_tf=", EnumToString(g_zoneTF));
      Print("IND: Execution TF Handles OK (ADX=", adxPeriod, " ATR=", atrPeriod,
            " ATRRef=", atrRefPeriod, " ATRTrail=", atrTrailPeriod, ")");
      Print("IND: HTF Bias Handles OK (EMA50, EMA200, ADX, ATR)");
   }

   return ok;
}

//+------------------------------------------------------------------+
//| Release all indicator handles safely                             |
//+------------------------------------------------------------------+
void ReleaseIndicators()
{
   // Execution timeframe handles
   if(h_ema50  != INVALID_HANDLE) { IndicatorRelease(h_ema50);  h_ema50  = INVALID_HANDLE; }
   if(h_ema200 != INVALID_HANDLE) { IndicatorRelease(h_ema200); h_ema200 = INVALID_HANDLE; }
   if(h_adx    != INVALID_HANDLE) { IndicatorRelease(h_adx);    h_adx    = INVALID_HANDLE; }

   if(h_atrTrail != INVALID_HANDLE && h_atrTrail != h_atr && h_atrTrail != h_atrRef)
      { IndicatorRelease(h_atrTrail); h_atrTrail = INVALID_HANDLE; }

   if(h_atrRef != INVALID_HANDLE && h_atrRef != h_atr)
      { IndicatorRelease(h_atrRef); h_atrRef = INVALID_HANDLE; }

   if(h_atr != INVALID_HANDLE) { IndicatorRelease(h_atr); h_atr = INVALID_HANDLE; }

   h_atrTrail = INVALID_HANDLE;
   h_atrRef   = INVALID_HANDLE;

   // HTF bias handles
   if(h_d1_ema50  != INVALID_HANDLE) { IndicatorRelease(h_d1_ema50);  h_d1_ema50  = INVALID_HANDLE; }
   if(h_d1_ema200 != INVALID_HANDLE) { IndicatorRelease(h_d1_ema200); h_d1_ema200 = INVALID_HANDLE; }
   if(h_d1_adx    != INVALID_HANDLE) { IndicatorRelease(h_d1_adx);    h_d1_adx    = INVALID_HANDLE; }
   if(h_d1_atr    != INVALID_HANDLE) { IndicatorRelease(h_d1_atr);    h_d1_atr    = INVALID_HANDLE; }
}

//+------------------------------------------------------------------+
//| Check all indicators have valid handles and enough bars          |
//+------------------------------------------------------------------+
bool IndicatorsReady()
{
   if(h_ema50    == INVALID_HANDLE ||
      h_ema200   == INVALID_HANDLE ||
      h_adx      == INVALID_HANDLE ||
      h_atr      == INVALID_HANDLE ||
      h_atrRef   == INVALID_HANDLE ||
      h_atrTrail == INVALID_HANDLE)
      return false;

   if(BarsCalculated(h_ema50)  <  50) return false;
   if(BarsCalculated(h_ema200) < 200) return false;
   if(BarsCalculated(h_adx)    < 20) return false;
   if(BarsCalculated(h_atr)    < 20) return false;
   if(h_atrRef != h_atr && BarsCalculated(h_atrRef) < 20) return false;
   if(h_atrTrail != h_atr && h_atrTrail != h_atrRef && BarsCalculated(h_atrTrail) < 20) return false;

   if(Bars(_Symbol, g_indicatorTF) < 200)
      return false;

   return true;
}

//+------------------------------------------------------------------+
//| Copy latest indicator values with full diagnostics               |
//+------------------------------------------------------------------+
bool CopyLatestIndicatorValues(IndicatorState &ind)
{
   if(!IndicatorsReady())
      return false;

   // Use temporary dynamic arrays (ArraySetAsSeries requires dynamic arrays)
   double tmpATR[];
   double tmpClose[], tmpHigh[], tmpLow[], tmpOpen[];

   ArraySetAsSeries(tmpATR, true);
   ArraySetAsSeries(tmpClose, true);
   ArraySetAsSeries(tmpHigh, true);
   ArraySetAsSeries(tmpLow, true);
   ArraySetAsSeries(tmpOpen, true);

   if(CopyBuffer(h_atr, 0, 0, 20, tmpATR) < 20)
   {
      Print("CopyBuffer failed: ATR");
      return false;
   }

   double tmpATRRef[];
   ArraySetAsSeries(tmpATRRef, true);
   if(h_atrRef == h_atr)
   {
      ArrayResize(tmpATRRef, 20);
      for(int k = 0; k < 20; k++) tmpATRRef[k] = tmpATR[k];
   }
   else if(CopyBuffer(h_atrRef, 0, 0, 20, tmpATRRef) < 20)
   {
      Print("CopyBuffer failed: ATR Ref");
      return false;
   }

   double tmpEma50[], tmpEma200[];
   ArraySetAsSeries(tmpEma50, true);
   ArraySetAsSeries(tmpEma200, true);
   if(CopyBuffer(h_ema50, 0, 0, 50, tmpEma50) < 50)
   {
      Print("CopyBuffer failed: EMA50");
      return false;
   }
   if(CopyBuffer(h_ema200, 0, 0, 50, tmpEma200) < 50)
   {
      Print("CopyBuffer failed: EMA200");
      return false;
   }

   double tmpADX[], tmpPDI[], tmpMDI[];
   ArraySetAsSeries(tmpADX, true);
   ArraySetAsSeries(tmpPDI, true);
   ArraySetAsSeries(tmpMDI, true);
   if(CopyBuffer(h_adx, 0, 0, 20, tmpADX) < 20)
   {
      Print("CopyBuffer failed: ADX");
      return false;
   }
   if(CopyBuffer(h_adx, 1, 0, 20, tmpPDI) < 20)
   {
      Print("CopyBuffer failed: +DI");
      return false;
   }
   if(CopyBuffer(h_adx, 2, 0, 20, tmpMDI) < 20)
   {
      Print("CopyBuffer failed: -DI");
      return false;
   }

   double tmpATRTrail[];
   ArraySetAsSeries(tmpATRTrail, true);
   if(h_atrTrail == h_atr)
   {
      // Same period — just reuse tmpATR
      ArrayResize(tmpATRTrail, 20);
      for(int k = 0; k < 20; k++) tmpATRTrail[k] = tmpATR[k];
   }
   else
   {
      if(CopyBuffer(h_atrTrail, 0, 0, 20, tmpATRTrail) < 20)
      {
         Print("CopyBuffer failed: ATR Trail");
         return false;
      }
   }

   if(CopyClose(_Symbol, g_indicatorTF, 0, 200, tmpClose) < 200)
   {
      Print("CopyBuffer failed: Close");
      return false;
   }

   if(CopyHigh(_Symbol, g_indicatorTF, 0, 200, tmpHigh) < 200)
   {
      Print("CopyBuffer failed: High");
      return false;
   }

   if(CopyLow(_Symbol, g_indicatorTF, 0, 200, tmpLow) < 200)
   {
      Print("CopyBuffer failed: Low");
      return false;
   }

   if(CopyOpen(_Symbol, g_indicatorTF, 0, 200, tmpOpen) < 200)
   {
      Print("CopyBuffer failed: Open");
      return false;
   }

   // Copy into struct static arrays
   for(int i = 0; i < 20; i++)
   {
      ind.adx[i]      = tmpADX[i];
      ind.atr[i]      = tmpATR[i];
      ind.atrRef[i]   = tmpATRRef[i];
      ind.atrTrail[i] = tmpATRTrail[i];
      ind.plusDI[i]   = tmpPDI[i];
      ind.minusDI[i]  = tmpMDI[i];
   }
   for(int i = 0; i < 50; i++)
   {
      ind.ema50[i]  = tmpEma50[i];
      ind.ema200[i] = tmpEma200[i];
   }
   for(int i = 0; i < 200; i++)
   {
      ind.closeArr[i] = tmpClose[i];
      ind.highArr[i]  = tmpHigh[i];
      ind.lowArr[i]   = tmpLow[i];
      ind.openArr[i]  = tmpOpen[i];
   }

   return true;
}

//+------------------------------------------------------------------+
//| Detect new bar on current timeframe                              |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentBar = iTime(_Symbol, g_indicatorTF, 0);
   if(currentBar != g_lastBarTime)
   {
      g_lastBarTime = currentBar;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Indicator value getters with bounds safety                       |
//+------------------------------------------------------------------+
double GetATR(const IndicatorState &ind, int shift)
{
   return (shift >= 0 && shift < 20) ? ind.atr[shift] : 0.0;
}

double GetATRRef(const IndicatorState &ind, int shift)
{
   return (shift >= 0 && shift < 20) ? ind.atrRef[shift] : 0.0;
}

// Returns atrRef/atrLive so old ATRref-tuned multipliers stay proportional.
// atrLive > atrRef (volatile) → scale < 1 → distances shrink.
// atrLive < atrRef (quiet)    → scale > 1 → distances grow.
double GetScaledATRMultiplier(double baseMultiplier,
                              const IndicatorState &ind, int shift = 1)
{
   double atrLive = GetATR(ind, shift);
   double atrRef  = GetATRRef(ind, shift);
   if(atrLive <= 0.0 || atrRef <= 0.0) return baseMultiplier;
   return baseMultiplier * (atrRef / atrLive);
}

double GetATRTrail(const IndicatorState &ind, int shift)
{
   return (shift >= 0 && shift < 20) ? ind.atrTrail[shift] : 0.0;
}

double GetEMA50(const IndicatorState &ind, int shift)
{
   return (shift >= 0 && shift < 50) ? ind.ema50[shift] : 0.0;
}

double GetEMA200(const IndicatorState &ind, int shift)
{
   return (shift >= 0 && shift < 50) ? ind.ema200[shift] : 0.0;
}

double GetADX(const IndicatorState &ind, int shift)
{
   return (shift >= 0 && shift < 20) ? ind.adx[shift] : 0.0;
}

double GetPlusDI(const IndicatorState &ind, int shift)
{
   return (shift >= 0 && shift < 20) ? ind.plusDI[shift] : 0.0;
}

double GetMinusDI(const IndicatorState &ind, int shift)
{
   return (shift >= 0 && shift < 20) ? ind.minusDI[shift] : 0.0;
}


//+------------------------------------------------------------------+
//| GetHighestHigh — highest high over lookback closed candles        |
//+------------------------------------------------------------------+
double GetHighestHigh(const IndicatorState &ind, int lookback, int startShift = 1)
{
   double highest = 0;
   int endShift = startShift + lookback;
   if(endShift > 200) endShift = 200;
   for(int i = startShift; i < endShift; i++)
   {
      if(ind.highArr[i] > highest)
         highest = ind.highArr[i];
   }
   return highest;
}

//+------------------------------------------------------------------+
//| GetLowestLow — lowest low over lookback closed candles            |
//+------------------------------------------------------------------+
double GetLowestLow(const IndicatorState &ind, int lookback, int startShift = 1)
{
   double lowest = 999999999;
   int endShift = startShift + lookback;
   if(endShift > 200) endShift = 200;
   for(int i = startShift; i < endShift; i++)
   {
      if(ind.lowArr[i] < lowest)
         lowest = ind.lowArr[i];
   }
   return (lowest < 999999999) ? lowest : 0;
}

//+------------------------------------------------------------------+
//| Copy D1 HTF bias indicator values                                |
//+------------------------------------------------------------------+
bool CopyD1IndicatorValues()
{
   if(h_d1_ema50 == INVALID_HANDLE || h_d1_ema200 == INVALID_HANDLE ||
      h_d1_adx == INVALID_HANDLE || h_d1_atr == INVALID_HANDLE)
   {
      g_d1Ind.valid = false;
      return false;
   }

   double tmpEMA50[], tmpEMA200[], tmpADX[], tmpATR[];
   double tmpClose[], tmpHigh[], tmpLow[], tmpOpen[];

   ArraySetAsSeries(tmpEMA50, true);
   ArraySetAsSeries(tmpEMA200, true);
   ArraySetAsSeries(tmpADX, true);
   ArraySetAsSeries(tmpATR, true);
   ArraySetAsSeries(tmpClose, true);
   ArraySetAsSeries(tmpHigh, true);
   ArraySetAsSeries(tmpLow, true);
   ArraySetAsSeries(tmpOpen, true);

   bool ok = true;
   if(CopyBuffer(h_d1_ema50, 0, 0, 10, tmpEMA50) < 10) ok = false;
   if(CopyBuffer(h_d1_ema200, 0, 0, 10, tmpEMA200) < 10) ok = false;
   if(CopyBuffer(h_d1_adx, 0, 0, 10, tmpADX) < 10) ok = false;
   if(CopyBuffer(h_d1_atr, 0, 0, 10, tmpATR) < 10) ok = false;
   if(CopyClose(_Symbol, g_htfBiasTF, 0, 20, tmpClose) < 20) ok = false;
   if(CopyHigh(_Symbol, g_htfBiasTF, 0, 20, tmpHigh) < 20) ok = false;
   if(CopyLow(_Symbol, g_htfBiasTF, 0, 20, tmpLow) < 20) ok = false;
   if(CopyOpen(_Symbol, g_htfBiasTF, 0, 20, tmpOpen) < 20) ok = false;

   if(!ok)
   {
      g_d1Ind.valid = false;
      return false;
   }

   for(int i = 0; i < 10; i++)
   {
      g_d1Ind.ema50[i]  = tmpEMA50[i];
      g_d1Ind.ema200[i] = tmpEMA200[i];
      g_d1Ind.adx[i]    = tmpADX[i];
      g_d1Ind.atr[i]    = tmpATR[i];
   }
   for(int i = 0; i < 20; i++)
   {
      g_d1Ind.closeArr[i] = tmpClose[i];
      g_d1Ind.highArr[i]  = tmpHigh[i];
      g_d1Ind.lowArr[i]   = tmpLow[i];
      g_d1Ind.openArr[i]  = tmpOpen[i];
   }

   g_d1Ind.valid = true;
   return true;
}

//+------------------------------------------------------------------+
//| D1 HTF Bias Classification                                        |
//| E1) EMA = bias filter, retest = bonus, NOT standalone trigger        |
//+------------------------------------------------------------------+
enum ENUM_D1_BIAS
{
   D1_BIAS_BULL,
   D1_BIAS_BEAR,
   D1_BIAS_NEUTRAL
};

ENUM_D1_BIAS GetD1Bias()
{
   if(!g_d1Ind.valid) return D1_BIAS_NEUTRAL;

   double ema50  = g_d1Ind.ema50[1];
   double ema200 = g_d1Ind.ema200[1];
   double close1 = g_d1Ind.closeArr[1];
   double adx    = g_d1Ind.adx[1];
   double atr    = g_d1Ind.atr[1];

   if(ema50 <= 0 || ema200 <= 0) return D1_BIAS_NEUTRAL;

   // ATR-normalized EMA separation — ignore marginal EMA differences
   double emaSepATR = (atr > 0) ? MathAbs(ema50 - ema200) / atr : 0;

   // E1) EMA alignment = bias filter only, NOT entry trigger
   // Strong bull: EMA50 > EMA200 and price > EMA50
   bool bullStack = (ema50 > ema200 && close1 > ema50);
   // Strong bear: EMA50 < EMA200 and price < EMA50
   bool bearStack = (ema50 < ema200 && close1 < ema50);

   // Weak bull: EMA50 > EMA200 only
   bool weakBull = (ema50 > ema200 && !bullStack);
   // Weak bear: EMA50 < EMA200 only
   bool weakBear = (ema50 < ema200 && !bearStack);

   // ADX threshold for trending
   bool trending = (adx >= 20.0);

   // Strong stack (price + EMA + ADX): needs separation >= 0.30 ATR
   if(bullStack && trending && emaSepATR >= 0.30) return D1_BIAS_BULL;
   if(bearStack && trending && emaSepATR >= 0.30) return D1_BIAS_BEAR;

   // Medium stack (price + EMA, no ADX): needs separation >= 0.50 ATR
   if(bullStack && emaSepATR >= 0.50) return D1_BIAS_BULL;
   if(bearStack && emaSepATR >= 0.50) return D1_BIAS_BEAR;

   // Weak (just EMA order): needs separation >= 0.80 ATR
   if(weakBull && emaSepATR >= 0.80) return D1_BIAS_BULL;
   if(weakBear && emaSepATR >= 0.80) return D1_BIAS_BEAR;

   return D1_BIAS_NEUTRAL;
}

string D1BiasToString(ENUM_D1_BIAS bias)
{
   switch(bias)
   {
      case D1_BIAS_BULL:    return "D1_BULL";
      case D1_BIAS_BEAR:    return "D1_BEAR";
      case D1_BIAS_NEUTRAL: return "D1_NEUTRAL";
   }
   return "D1_UNKNOWN";
}

//+------------------------------------------------------------------+
//| Check if H4 trade direction aligns with D1 bias                   |
//+------------------------------------------------------------------+
bool IsD1AlignedForBuy()
{
   ENUM_D1_BIAS bias = GetD1Bias();
   return (bias == D1_BIAS_BULL);
}

bool IsD1AlignedForSell()
{
   ENUM_D1_BIAS bias = GetD1Bias();
   return (bias == D1_BIAS_BEAR);
}

bool IsStrictTrendBuyAllowedByD1()
{
   return (GetD1Bias() == D1_BIAS_BULL);
}

bool IsStrictTrendSellAllowedByD1()
{
   return (GetD1Bias() == D1_BIAS_BEAR);
}

//+------------------------------------------------------------------+
//| Check for new D1 bar (for bias refresh)                           |
//+------------------------------------------------------------------+
bool IsNewD1Bar()
{
   datetime currentD1Bar = iTime(_Symbol, g_htfBiasTF, 0);
   if(currentD1Bar != g_lastD1BarTime)
   {
      g_lastD1BarTime = currentD1Bar;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| MTF stubs — kept for compile compatibility                       |
//+------------------------------------------------------------------+
bool IsMTFBullAligned(const MTFState &mtf) { return true; }
bool IsMTFBearAligned(const MTFState &mtf) { return true; }

#endif // INDICATOR_MANAGER_MQH
