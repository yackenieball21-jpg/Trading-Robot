#ifndef __CANDLE_PATTERNS_MQH__
#define __CANDLE_PATTERNS_MQH__

// =====================================================
// CandlePatterns.mqh
// MT5 helper for candle confirmation entries
// =====================================================

struct CandleData
{
   double open;
   double high;
   double low;
   double close;
};

bool GetCandleData(const string symbol, ENUM_TIMEFRAMES tf, int shift, CandleData &c)
{
   c.open  = iOpen(symbol, tf, shift);
   c.high  = iHigh(symbol, tf, shift);
   c.low   = iLow(symbol, tf, shift);
   c.close = iClose(symbol, tf, shift);

   if(c.open == 0.0 && c.high == 0.0 && c.low == 0.0 && c.close == 0.0)
      return false;

   return true;
}

double CandleRange(const CandleData &c)
{
   return (c.high - c.low);
}

double CandleBody(const CandleData &c)
{
   return MathAbs(c.close - c.open);
}

double UpperWick(const CandleData &c)
{
   return c.high - MathMax(c.open, c.close);
}

double LowerWick(const CandleData &c)
{
   return MathMin(c.open, c.close) - c.low;
}

bool IsBullishCandle(const CandleData &c)
{
   return (c.close > c.open);
}

bool IsBearishCandle(const CandleData &c)
{
   return (c.close < c.open);
}

bool IsDojiLike(const CandleData &c, double maxBodyToRange = 0.15)
{
   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body = CandleBody(c);
   return ((body / range) <= maxBodyToRange);
}

double CandleClosePosition(const CandleData &c)
{
   double range = CandleRange(c);
   if(range <= 0.0)
      return 0.50;

   return (c.close - c.low) / range;
}

bool IsDoji(const string symbol, ENUM_TIMEFRAMES tf, int shift,
            double maxBodyToRange = 0.15)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   return IsDojiLike(c, maxBodyToRange);
}

bool IsBullishDojiRejection(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                            double maxBodyToRange = 0.15,
                            double minLowerWickToRange = 0.35)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body  = CandleBody(c);
   double lower = LowerWick(c);
   double upper = UpperWick(c);
   double closePos = CandleClosePosition(c);

   if((body / range) > maxBodyToRange)
      return false;

   if((lower / range) < minLowerWickToRange)
      return false;

   if(lower <= upper)
      return false;

   return (closePos >= 0.45);
}

bool IsBearishDojiRejection(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                            double maxBodyToRange = 0.15,
                            double minUpperWickToRange = 0.35)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body  = CandleBody(c);
   double lower = LowerWick(c);
   double upper = UpperWick(c);
   double closePos = CandleClosePosition(c);

   if((body / range) > maxBodyToRange)
      return false;

   if((upper / range) < minUpperWickToRange)
      return false;

   if(upper <= lower)
      return false;

   return (closePos <= 0.55);
}

bool IsSDHammer(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                double minLowerWickToBody = 2.0,
                double maxUpperWickToBody = 1.0)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   double body  = CandleBody(c);
   if(range <= 0.0 || body <= 0.0)
      return false;

   double lower = LowerWick(c);
   double upper = UpperWick(c);
   double closePos = CandleClosePosition(c);

   if(lower < body * minLowerWickToBody)
      return false;

   if(upper > body * maxUpperWickToBody)
      return false;

   return (closePos >= 0.50);
}

bool IsInvertedHammer(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                      double minUpperWickToBody = 2.0,
                      double maxLowerWickToBody = 1.0)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   double body  = CandleBody(c);
   if(range <= 0.0 || body <= 0.0)
      return false;

   double lower = LowerWick(c);
   double upper = UpperWick(c);

   if(upper < body * minUpperWickToBody)
      return false;

   if(lower > body * maxLowerWickToBody)
      return false;

   return true;
}

bool IsBullishHammerAtDemand(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   return IsSDHammer(symbol, tf, shift, 2.0, 1.0);
}

bool IsBullishInvertedHammerAtDemand(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   if(!IsInvertedHammer(symbol, tf, shift, 2.0, 1.0))
      return false;

   double closePos = CandleClosePosition(c);
   return (c.close >= c.open || closePos >= 0.50);
}

bool IsBearishInvertedHammerAtSupply(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   if(!IsInvertedHammer(symbol, tf, shift, 2.0, 1.0))
      return false;

   double closePos = CandleClosePosition(c);
   return (c.close <= c.open || closePos <= 0.50);
}

bool IsBearishHammerAtSupply(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   if(!IsSDHammer(symbol, tf, shift, 2.0, 1.0))
      return false;

   return (c.close < c.open);
}

bool IsSmallStarCandle(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                       double maxBodyToRange = 0.35)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body = CandleBody(c);
   return ((body / range) <= maxBodyToRange);
}

bool IsLongBearishCandle(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                         double minBodyToRange = 0.55)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body = CandleBody(c);

   return (c.close < c.open && (body / range) >= minBodyToRange);
}

bool IsLongBullishCandle(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                         double minBodyToRange = 0.55)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body = CandleBody(c);

   return (c.close > c.open && (body / range) >= minBodyToRange);
}

bool IsSDMorningStar(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1,
                     double maxStarBodyPct = 0.35,
                     double closeBeyondMidPct = 0.50)
{
   CandleData c1, c2, c3;

   if(!GetCandleData(symbol, tf, shift,     c1)) return false;
   if(!GetCandleData(symbol, tf, shift + 1, c2)) return false;
   if(!GetCandleData(symbol, tf, shift + 2, c3)) return false;

   if(!IsLongBearishCandle(symbol, tf, shift + 2, 0.55))
      return false;

   if(!IsSmallStarCandle(symbol, tf, shift + 1, maxStarBodyPct))
      return false;

   if(c1.close <= c1.open)
      return false;

   double firstMid = c3.close + ((c3.open - c3.close) * closeBeyondMidPct);

   if(c1.close < firstMid)
      return false;

   return true;
}

bool IsSDEveningStar(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1,
                     double maxStarBodyPct = 0.35,
                     double closeBeyondMidPct = 0.50)
{
   CandleData c1, c2, c3;

   if(!GetCandleData(symbol, tf, shift,     c1)) return false;
   if(!GetCandleData(symbol, tf, shift + 1, c2)) return false;
   if(!GetCandleData(symbol, tf, shift + 2, c3)) return false;

   if(!IsLongBullishCandle(symbol, tf, shift + 2, 0.55))
      return false;

   if(!IsSmallStarCandle(symbol, tf, shift + 1, maxStarBodyPct))
      return false;

   if(c1.close >= c1.open)
      return false;

   double firstMid = c3.open + ((c3.close - c3.open) * closeBeyondMidPct);

   if(c1.close > firstMid)
      return false;

   return true;
}

bool IsMorningStarAtDemand(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1)
{
   return IsSDMorningStar(symbol, tf, shift, InpSDStarSmallBodyPct, 0.50);
}

bool IsEveningStarAtSupply(const string symbol, ENUM_TIMEFRAMES tf, int shift = 1)
{
   return IsSDEveningStar(symbol, tf, shift, InpSDStarSmallBodyPct, 0.50);
}

// -----------------------------------------------------
// Strong body candles
// -----------------------------------------------------
bool IsStrongBullishBody(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                         double minBodyToRange = 0.60)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body = CandleBody(c);

   if(!IsBullishCandle(c))
      return false;

   return ((body / range) >= minBodyToRange);
}

bool IsStrongBearishBody(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                         double minBodyToRange = 0.60)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body = CandleBody(c);

   if(!IsBearishCandle(c))
      return false;

   return ((body / range) >= minBodyToRange);
}

// -----------------------------------------------------
// Engulfing patterns
// -----------------------------------------------------
bool IsBullishEngulfing(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   CandleData prev, curr;
   if(!GetCandleData(symbol, tf, shift + 1, prev))
      return false;
   if(!GetCandleData(symbol, tf, shift, curr))
      return false;

   if(!IsBearishCandle(prev) || !IsBullishCandle(curr))
      return false;

   bool bodyEngulfs =
      (curr.open  <= prev.close) &&
      (curr.close >= prev.open);

   return bodyEngulfs;
}

bool IsBearishEngulfing(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   CandleData prev, curr;
   if(!GetCandleData(symbol, tf, shift + 1, prev))
      return false;
   if(!GetCandleData(symbol, tf, shift, curr))
      return false;

   if(!IsBullishCandle(prev) || !IsBearishCandle(curr))
      return false;

   bool bodyEngulfs =
      (curr.open  >= prev.close) &&
      (curr.close <= prev.open);

   return bodyEngulfs;
}

// -----------------------------------------------------
// Pin bars
// -----------------------------------------------------
bool IsBullishPinBar(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                     double minLowerWickToBody = 2.0,
                     double maxUpperWickToBody = 1.0,
                     double minClosePositionInRange = 0.60)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   double body  = CandleBody(c);
   if(range <= 0.0 || body <= 0.0)
      return false;

   double upper = UpperWick(c);
   double lower = LowerWick(c);

   double closePos = (c.close - c.low) / range;

   if(lower < body * minLowerWickToBody)
      return false;

   if(upper > body * maxUpperWickToBody)
      return false;

   if(closePos < minClosePositionInRange)
      return false;

   return true;
}

bool IsBearishPinBar(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                     double minUpperWickToBody = 2.0,
                     double maxLowerWickToBody = 1.0,
                     double maxClosePositionInRange = 0.40)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   double body  = CandleBody(c);
   if(range <= 0.0 || body <= 0.0)
      return false;

   double upper = UpperWick(c);
   double lower = LowerWick(c);

   double closePos = (c.close - c.low) / range;

   if(upper < body * minUpperWickToBody)
      return false;

   if(lower > body * maxLowerWickToBody)
      return false;

   if(closePos > maxClosePositionInRange)
      return false;

   return true;
}

// -----------------------------------------------------
// Wick rejection candles
// More flexible than pin bars
// -----------------------------------------------------
bool IsBullishWickRejection(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                            double minLowerWickToRange = 0.40,
                            double maxBodyToRange      = 0.45,
                            bool requireBullishClose   = false)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body  = CandleBody(c);
   double lower = LowerWick(c);
   double upper = UpperWick(c);

   if((lower / range) < minLowerWickToRange)
      return false;

   if((body / range) > maxBodyToRange)
      return false;

   if(lower <= upper)
      return false;

   if(requireBullishClose && !IsBullishCandle(c))
      return false;

   return true;
}

bool IsBearishWickRejection(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                            double minUpperWickToRange = 0.40,
                            double maxBodyToRange      = 0.45,
                            bool requireBearishClose   = false)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body  = CandleBody(c);
   double lower = LowerWick(c);
   double upper = UpperWick(c);

   if((upper / range) < minUpperWickToRange)
      return false;

   if((body / range) > maxBodyToRange)
      return false;

   if(upper <= lower)
      return false;

   if(requireBearishClose && !IsBearishCandle(c))
      return false;

   return true;
}

// -----------------------------------------------------
// Inside bars
// -----------------------------------------------------
bool IsInsideBar(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   CandleData prev, curr;
   if(!GetCandleData(symbol, tf, shift + 1, prev))
      return false;
   if(!GetCandleData(symbol, tf, shift, curr))
      return false;

   return (curr.high < prev.high && curr.low > prev.low);
}

// -----------------------------------------------------
// Rejection + body continuation combo
// Useful for zone entries
// -----------------------------------------------------
bool IsBullishRejectionCombo(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   return (
      IsBullishEngulfing(symbol, tf, shift) ||
      (InpSDUseMorningStarConfirmation && IsMorningStarAtDemand(symbol, tf, shift)) ||
      IsBullishPinBar(symbol, tf, shift) ||
      IsBullishWickRejection(symbol, tf, shift, 0.40, 0.45, true) ||
      IsStrongBullishBody(symbol, tf, shift, 0.65) ||
      IsBullishHammerAtDemand(symbol, tf, shift) ||
      IsBullishDojiRejection(symbol, tf, shift) ||
      IsBullishInvertedHammerAtDemand(symbol, tf, shift)
   );
}

bool IsBearishRejectionCombo(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   return (
      IsBearishEngulfing(symbol, tf, shift) ||
      (InpSDUseEveningStarConfirmation && IsEveningStarAtSupply(symbol, tf, shift)) ||
      IsBearishPinBar(symbol, tf, shift) ||
      IsBearishWickRejection(symbol, tf, shift, 0.40, 0.45, true) ||
      IsStrongBearishBody(symbol, tf, shift, 0.65) ||
      IsBearishInvertedHammerAtSupply(symbol, tf, shift) ||
      IsBearishDojiRejection(symbol, tf, shift) ||
      IsBearishHammerAtSupply(symbol, tf, shift)
   );
}

// -----------------------------------------------------
// Optional scoring system
// Lets you require stronger confirmation
// -----------------------------------------------------
int BullishPatternScore(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   int score = 0;

   if(IsBullishEngulfing(symbol, tf, shift))                         score += 3;
   if(InpSDUseMorningStarConfirmation && IsMorningStarAtDemand(symbol, tf, shift)) score += 4;
   if(IsBullishPinBar(symbol, tf, shift))                            score += 3;
   if(IsBullishWickRejection(symbol, tf, shift, 0.40, 0.45, true))   score += 2;
   if(IsStrongBullishBody(symbol, tf, shift, 0.60))                 score += 2;
   if(IsBullishHammerAtDemand(symbol, tf, shift))                   score += 3;
   if(IsBullishDojiRejection(symbol, tf, shift))                    score += 2;
   if(IsBullishInvertedHammerAtDemand(symbol, tf, shift))           score += 1;
   if(IsInsideBar(symbol, tf, shift))                               score += 1;

   return score;
}

int BearishPatternScore(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   int score = 0;

   if(IsBearishEngulfing(symbol, tf, shift))                         score += 3;
   if(InpSDUseEveningStarConfirmation && IsEveningStarAtSupply(symbol, tf, shift)) score += 4;
   if(IsBearishPinBar(symbol, tf, shift))                            score += 3;
   if(IsBearishWickRejection(symbol, tf, shift, 0.40, 0.45, true))   score += 2;
   if(IsStrongBearishBody(symbol, tf, shift, 0.60))                 score += 2;
   if(IsBearishInvertedHammerAtSupply(symbol, tf, shift))           score += 3;
   if(IsBearishDojiRejection(symbol, tf, shift))                    score += 2;
   if(IsBearishHammerAtSupply(symbol, tf, shift))                   score += 1;
   if(IsInsideBar(symbol, tf, shift))                               score += 1;

   return score;
}

// -----------------------------------------------------
// Market-state aware pattern helpers
// -----------------------------------------------------

double HighestHigh(const double &arr[], int start, int count)
{
   double hh = -DBL_MAX;
   for(int i = start; i < start + count; i++)
      hh = MathMax(hh, arr[i]);
   return hh;
}

double LowestLow(const double &arr[], int start, int count)
{
   double ll = DBL_MAX;
   for(int i = start; i < start + count; i++)
      ll = MathMin(ll, arr[i]);
   return ll;
}

bool ArePricesNear(double a, double b, double tolerance)
{
   return (MathAbs(a - b) <= tolerance);
}

// -----------------------------------------------------
// Trend continuation wrappers
// -----------------------------------------------------
bool IsTrendBullishContinuation(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   return (
      IsBullishEngulfing(symbol, tf, shift) ||
      IsStrongBullishBody(symbol, tf, shift, 0.60)
   );
}

bool IsTrendBearishContinuation(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   return (
      IsBearishEngulfing(symbol, tf, shift) ||
      IsStrongBearishBody(symbol, tf, shift, 0.60)
   );
}

bool IsTrendBullishPinRejection(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   return (
      IsBullishPinBar(symbol, tf, shift, 2.0, 1.0, 0.60) ||
      IsBullishWickRejection(symbol, tf, shift, 0.40, 0.45, true)
   );
}

bool IsTrendBearishPinRejection(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   return (
      IsBearishPinBar(symbol, tf, shift, 2.0, 1.0, 0.40) ||
      IsBearishWickRejection(symbol, tf, shift, 0.40, 0.45, true)
   );
}

bool IsTrendInsideBarBreakoutBull(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   if(!IsInsideBar(symbol, tf, shift))
      return false;

   CandleData mother, curr;
   if(!GetCandleData(symbol, tf, shift + 1, mother))
      return false;
   if(!GetCandleData(symbol, tf, shift, curr))
      return false;

   return (curr.close > mother.high && curr.close > curr.open);
}

bool IsTrendInsideBarBreakoutBear(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   if(!IsInsideBar(symbol, tf, shift))
      return false;

   CandleData mother, curr;
   if(!GetCandleData(symbol, tf, shift + 1, mother))
      return false;
   if(!GetCandleData(symbol, tf, shift, curr))
      return false;

   return (curr.close < mother.low && curr.close < curr.open);
}

// -----------------------------------------------------
// Range reversal helpers
// lowArr / highArr expected as timeseries arrays
// with index 1 = recently closed bar
// -----------------------------------------------------
bool IsDoubleBottom(const double &lowArr[], const double &highArr[],
                    const double &closeArr[], const double &openArr[],
                    double atr, int lookback = 20, int minSeparation = 3,
                    double tolMult = 0.25)
{
   if(atr <= 0.0) return false;

   double tol = atr * tolMult;
   int first = -1, second = -1;

   for(int i = 2; i <= lookback; i++)
   {
      if(lowArr[i] < lowArr[i - 1] && lowArr[i] < lowArr[i + 1])
      {
         if(first == -1)
         {
            first = i;
         }
         else if(MathAbs(i - first) >= minSeparation &&
                 MathAbs(lowArr[i] - lowArr[first]) <= tol)
         {
            second = i;
            break;
         }
      }
   }

   if(first == -1 || second == -1)
      return false;

   if(MathAbs(second - first) > 15)
      return false;

   if(lowArr[second] < lowArr[first] - atr * 0.35)
      return false;

   int start = MathMin(first, second);
   int end   = MathMax(first, second);

   double neckline = -DBL_MAX;
   for(int j = start; j <= end; j++)
      neckline = MathMax(neckline, highArr[j]);

   double avgLow = 0.5 * (lowArr[first] + lowArr[second]);
   if(neckline - avgLow < atr * 0.35)
      return false;

   bool secondLowSweep = (lowArr[1] <= avgLow + atr * 0.15);
   bool bullishClose   = (closeArr[1] > openArr[1]);
   bool necklineBreak  = (closeArr[1] > neckline);
   bool reclaimClose   = (closeArr[1] > avgLow + atr * 0.20);

   bool valid = (bullishClose && reclaimClose && (necklineBreak || secondLowSweep));
   return valid;
}

bool IsDoubleTop(const double &highArr[], const double &lowArr[],
                 const double &closeArr[], const double &openArr[],
                 double atr, int lookback = 20, int minSeparation = 3,
                 double tolMult = 0.25)
{
   if(atr <= 0.0) return false;

   double tol = atr * tolMult;
   int first = -1, second = -1;

   for(int i = 2; i <= lookback; i++)
   {
      if(highArr[i] > highArr[i - 1] && highArr[i] > highArr[i + 1])
      {
         if(first == -1)
         {
            first = i;
         }
         else if(MathAbs(i - first) >= minSeparation &&
                 MathAbs(highArr[i] - highArr[first]) <= tol)
         {
            second = i;
            break;
         }
      }
   }

   if(first == -1 || second == -1)
      return false;

   if(MathAbs(second - first) > 15)
      return false;

   if(highArr[second] > highArr[first] + atr * 0.35)
      return false;

   int start = MathMin(first, second);
   int end   = MathMax(first, second);

   double neckline = DBL_MAX;
   for(int j = start; j <= end; j++)
      neckline = MathMin(neckline, lowArr[j]);

   double avgHigh = 0.5 * (highArr[first] + highArr[second]);
   if(avgHigh - neckline < atr * 0.35)
      return false;

   bool secondHighSweep = (highArr[1] >= avgHigh - atr * 0.15);
   bool bearishClose    = (closeArr[1] < openArr[1]);
   bool necklineBreak   = (closeArr[1] < neckline);
   bool reclaimClose    = (closeArr[1] < avgHigh - atr * 0.20);

   bool valid = (bearishClose && reclaimClose && (necklineBreak || secondHighSweep));
   return valid;
}

bool IsInverseHeadAndShouldersBottom(const double &lowArr[], const double &highArr[], double atr,
                                     int lookback = 25, double shoulderTolMult = 0.30)
{
   if(atr <= 0.0) return false;

   double tol = atr * shoulderTolMult;

   for(int i = 4; i <= lookback - 2; i++)
   {
      double leftShoulder  = lowArr[i + 2];
      double head          = lowArr[i];
      double rightShoulder = lowArr[i - 2];

      // Head must be clearly lower than both shoulders (at least 0.3 ATR)
      if(head >= leftShoulder - atr * 0.30) continue;
      if(head >= rightShoulder - atr * 0.30) continue;

      // Shoulders must be reasonably symmetric in price
      if(!ArePricesNear(leftShoulder, rightShoulder, tol))
         continue;

      // Right shoulder must be recent enough (within 8 bars of bar 1)
      if(i - 2 > 8) continue;

      // Neckline from shoulder swing highs
      double neckline = MathMax(highArr[i + 1], highArr[i - 1]);

      // Neckline must be meaningfully above head (at least 0.25 ATR)
      if(neckline - head < atr * 0.25) continue;

      // Confirmation: recent bar high must break above neckline AND low must be above head
      if(highArr[1] > neckline && lowArr[1] > head)
         return true;
   }

   return false;
}

bool IsHeadAndShouldersTop(const double &highArr[], const double &lowArr[], double atr,
                           int lookback = 25, double shoulderTolMult = 0.30)
{
   if(atr <= 0.0) return false;

   double tol = atr * shoulderTolMult;

   for(int i = 4; i <= lookback - 2; i++)
   {
      double leftShoulder  = highArr[i + 2];
      double head          = highArr[i];
      double rightShoulder = highArr[i - 2];

      // Head must be clearly above both shoulders (at least 0.3 ATR)
      if(head <= leftShoulder + atr * 0.30) continue;
      if(head <= rightShoulder + atr * 0.30) continue;

      // Shoulders must be reasonably symmetric in price
      if(!ArePricesNear(leftShoulder, rightShoulder, tol))
         continue;

      // Right shoulder must be recent enough (within 8 bars of bar 1)
      if(i - 2 > 8) continue;

      // Neckline from shoulder swing lows
      double neckline = MathMin(lowArr[i + 1], lowArr[i - 1]);

      // Neckline must be meaningfully below head (at least 0.25 ATR)
      if(head - neckline < atr * 0.25) continue;

      // Confirmation: recent bar low must break below neckline AND high must be below head
      if(lowArr[1] < neckline && highArr[1] < head)
         return true;
   }

   return false;
}

// -----------------------------------------------------
// Range edge rejection using actual zone bounds
// -----------------------------------------------------
bool IsRangeBullishRejection(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                             double zoneLow, double zoneHigh)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   bool touched = (c.low <= zoneHigh && c.high >= zoneLow);
   if(!touched)
      return false;

   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body      = CandleBody(c);
   double lowerWick = LowerWick(c);
   double closePos  = (c.close - c.low) / range;

   return (lowerWick > range * 0.40 &&
           body <= range * 0.50 &&
           closePos >= 0.55 &&
           c.close >= zoneLow);
}

bool IsRangeBearishRejection(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                             double zoneLow, double zoneHigh)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   bool touched = (c.low <= zoneHigh && c.high >= zoneLow);
   if(!touched)
      return false;

   double range = CandleRange(c);
   if(range <= 0.0)
      return false;

   double body      = CandleBody(c);
   double upperWick = UpperWick(c);
   double closePos  = (c.close - c.low) / range;

   return (upperWick > range * 0.40 &&
           body <= range * 0.50 &&
           closePos <= 0.45 &&
           c.close <= zoneHigh);
}

// -----------------------------------------------------
// False break / sweep helpers
// -----------------------------------------------------
bool IsFalseBreakRangeLow(const double &lowArr[], const double &closeArr[],
                          double rangeLow, double atr, double reclaimTolMult = 0.10)
{
   if(atr <= 0.0) return false;

   double reclaimTol = atr * reclaimTolMult;

   bool sweptBelow = (lowArr[1] < rangeLow);
   bool reclaimed  = (closeArr[1] >= (rangeLow - reclaimTol));

   return (sweptBelow && reclaimed);
}

bool IsFalseBreakRangeHigh(const double &highArr[], const double &closeArr[],
                           double rangeHigh, double atr, double reclaimTolMult = 0.10)
{
   if(atr <= 0.0) return false;

   double reclaimTol = atr * reclaimTolMult;

   bool sweptAbove = (highArr[1] > rangeHigh);
   bool rejected   = (closeArr[1] <= (rangeHigh + reclaimTol));

   return (sweptAbove && rejected);
}

// -----------------------------------------------------
// Consolidation / breakout helpers
// -----------------------------------------------------
bool IsCompressionBreakoutBull(const double &highArr[], const double &lowArr[],
                               const double &openArr[], const double &closeArr[],
                               double atr, int lookback = 8, double spanATRMult = 1.5)
{
   if(atr <= 0.0) return false;

   double hh = HighestHigh(highArr, 2, lookback);
   double ll = LowestLow(lowArr, 2, lookback);
   double span = hh - ll;

   if(span > atr * spanATRMult)
      return false;

   return (closeArr[1] > hh && closeArr[1] > openArr[1]);
}

bool IsCompressionBreakoutBear(const double &highArr[], const double &lowArr[],
                               const double &openArr[], const double &closeArr[],
                               double atr, int lookback = 8, double spanATRMult = 1.5)
{
   if(atr <= 0.0) return false;

   double hh = HighestHigh(highArr, 2, lookback);
   double ll = LowestLow(lowArr, 2, lookback);
   double span = hh - ll;

   if(span > atr * spanATRMult)
      return false;

   return (closeArr[1] < ll && closeArr[1] < openArr[1]);
}

//+------------------------------------------------------------------+
//| ADVANCED CANDLE PATTERNS - Trend Reversal & Continuation         |
//+------------------------------------------------------------------+

// -----------------------------------------------------
// Hammer & Shooting Star - Classic single-candle reversals
// Note: IsSDHammer is defined earlier in the file (line 147)
// -----------------------------------------------------

bool IsShootingStar(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                    double minUpperWickToBody = 2.0,
                    double maxLowerWickToBody = 0.5,
                    double minBodyToRange = 0.05,
                    double maxBodyToRange = 0.30)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   double range = CandleRange(c);
   double body = CandleBody(c);
   if(range <= 0.0 || body <= 0.0)
      return false;

   double bodyToRange = body / range;
   if(bodyToRange < minBodyToRange || bodyToRange > maxBodyToRange)
      return false;

   double lowerWick = LowerWick(c);
   double upperWick = UpperWick(c);

   // Upper wick must be at least 2x the body
   if(upperWick < body * minUpperWickToBody)
      return false;

   // Lower wick must be small
   if(lowerWick > body * maxLowerWickToBody)
      return false;

   // Close in lower half of range (bearish)
   double closePos = (c.close - c.low) / range;
   return (closePos <= 0.40);
}

// -----------------------------------------------------
// Marubozu - Strong momentum candles (little to no wicks)
// -----------------------------------------------------
bool IsBullishMarubozu(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                       double minBodyToRange = 0.90,
                       double minClosePosition = 0.98)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   if(!IsBullishCandle(c))
      return false;

   double range = CandleRange(c);
   double body = CandleBody(c);
   if(range <= 0.0)
      return false;

   // Body must be 90%+ of range
   if((body / range) < minBodyToRange)
      return false;

   // Close must be near the high
   double closePos = (c.close - c.low) / range;
   return (closePos >= minClosePosition);
}

bool IsBearishMarubozu(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                       double minBodyToRange = 0.90,
                       double maxClosePosition = 0.02)
{
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   if(!IsBearishCandle(c))
      return false;

   double range = CandleRange(c);
   double body = CandleBody(c);
   if(range <= 0.0)
      return false;

   // Body must be 90%+ of range
   if((body / range) < minBodyToRange)
      return false;

   // Close must be near the low
   double closePos = (c.close - c.low) / range;
   return (closePos <= maxClosePosition);
}

// -----------------------------------------------------
// Harami Pattern - Inside bar reversal
// -----------------------------------------------------
bool IsBullishHarami(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                     double maxBodyToRange = 0.30)
{
   CandleData mother, baby;
   if(!GetCandleData(symbol, tf, shift + 1, mother))
      return false;
   if(!GetCandleData(symbol, tf, shift, baby))
      return false;

   // Mother must be bearish and larger
   if(!IsBearishCandle(mother))
      return false;

   double motherRange = CandleRange(mother);
   double babyRange = CandleRange(baby);
   if(motherRange <= 0.0 || babyRange <= 0.0)
      return false;

   // Baby must be inside mother's range
   if(baby.high > mother.high || baby.low < mother.low)
      return false;

   // Baby must be bullish
   if(!IsBullishCandle(baby))
      return false;

   // Baby body should be small (indecision)
   double babyBody = CandleBody(baby);
   if((babyBody / babyRange) > maxBodyToRange)
      return false;

   return true;
}

bool IsBearishHarami(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                     double maxBodyToRange = 0.30)
{
   CandleData mother, baby;
   if(!GetCandleData(symbol, tf, shift + 1, mother))
      return false;
   if(!GetCandleData(symbol, tf, shift, baby))
      return false;

   // Mother must be bullish and larger
   if(!IsBullishCandle(mother))
      return false;

   double motherRange = CandleRange(mother);
   double babyRange = CandleRange(baby);
   if(motherRange <= 0.0 || babyRange <= 0.0)
      return false;

   // Baby must be inside mother's range
   if(baby.high > mother.high || baby.low < mother.low)
      return false;

   // Baby must be bearish
   if(!IsBearishCandle(baby))
      return false;

   // Baby body should be small (indecision)
   double babyBody = CandleBody(baby);
   if((babyBody / babyRange) > maxBodyToRange)
      return false;

   return true;
}

// -----------------------------------------------------
// Piercing Line & Dark Cloud Cover - Two-candle reversals
// -----------------------------------------------------
bool IsPiercingLine(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   CandleData first, second;
   if(!GetCandleData(symbol, tf, shift + 1, first))
      return false;
   if(!GetCandleData(symbol, tf, shift, second))
      return false;

   // First candle must be bearish with decent size
   if(!IsBearishCandle(first))
      return false;

   double firstBody = CandleBody(first);
   double firstRange = CandleRange(first);
   if(firstRange <= 0.0 || (firstBody / firstRange) < 0.50)
      return false;

   // Second candle must be bullish
   if(!IsBullishCandle(second))
      return false;

   // Second candle must open below first close (gap down)
   if(second.open >= first.close)
      return false;

   // Second candle must close above 50% of first candle's body
   double firstMid = (first.open + first.close) / 2.0;
   return (second.close > firstMid);
}

bool IsDarkCloudCover(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   CandleData first, second;
   if(!GetCandleData(symbol, tf, shift + 1, first))
      return false;
   if(!GetCandleData(symbol, tf, shift, second))
      return false;

   // First candle must be bullish with decent size
   if(!IsBullishCandle(first))
      return false;

   double firstBody = CandleBody(first);
   double firstRange = CandleRange(first);
   if(firstRange <= 0.0 || (firstBody / firstRange) < 0.50)
      return false;

   // Second candle must be bearish
   if(!IsBearishCandle(second))
      return false;

   // Second candle must open above first close (gap up)
   if(second.open <= first.close)
      return false;

   // Second candle must close below 50% of first candle's body
   double firstMid = (first.open + first.close) / 2.0;
   return (second.close < firstMid);
}

// -----------------------------------------------------
// Morning Star & Evening Star - Three-candle reversals
// Note: IsSDMorningStar and IsSDEveningStar are defined earlier in the file (lines 288-339)
// -----------------------------------------------------

// -----------------------------------------------------
// Three White Soldiers & Three Black Crows - Strong trend
// -----------------------------------------------------
bool IsThreeWhiteSoldiers(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                          double minBodyToRange = 0.60,
                          double maxUpperWickToRange = 0.15)
{
   for(int i = 0; i < 3; i++)
   {
      CandleData c;
      if(!GetCandleData(symbol, tf, shift + i, c))
         return false;

      // Must be bullish
      if(!IsBullishCandle(c))
         return false;

      double range = CandleRange(c);
      double body = CandleBody(c);
      if(range <= 0.0)
         return false;

      // Strong body
      if((body / range) < minBodyToRange)
         return false;

      // Small upper wick (close near high)
      double upperWick = UpperWick(c);
      if((upperWick / range) > maxUpperWickToRange)
         return false;

      // Each candle should open within or near previous body
      if(i > 0)
      {
         CandleData prev;
         if(!GetCandleData(symbol, tf, shift + i - 1, prev))
            return false;
         if(c.open < prev.open || c.open > prev.close)
            return false;
      }
   }
   return true;
}

bool IsThreeBlackCrows(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                       double minBodyToRange = 0.60,
                       double maxLowerWickToRange = 0.15)
{
   for(int i = 0; i < 3; i++)
   {
      CandleData c;
      if(!GetCandleData(symbol, tf, shift + i, c))
         return false;

      // Must be bearish
      if(!IsBearishCandle(c))
         return false;

      double range = CandleRange(c);
      double body = CandleBody(c);
      if(range <= 0.0)
         return false;

      // Strong body
      if((body / range) < minBodyToRange)
         return false;

      // Small lower wick (close near low)
      double lowerWick = LowerWick(c);
      if((lowerWick / range) > maxLowerWickToRange)
         return false;

      // Each candle should open within or near previous body
      if(i > 0)
      {
         CandleData prev;
         if(!GetCandleData(symbol, tf, shift + i - 1, prev))
            return false;
         if(c.open > prev.open || c.open < prev.close)
            return false;
      }
   }
   return true;
}

// -----------------------------------------------------
// Tweezer Top & Tweezer Bottom - Double rejection
// -----------------------------------------------------
bool IsTweezerTop(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                  double tolerancePoints = 0)
{
   CandleData first, second;
   if(!GetCandleData(symbol, tf, shift + 1, first))
      return false;
   if(!GetCandleData(symbol, tf, shift, second))
      return false;

   // First candle: bullish
   if(!IsBullishCandle(first))
      return false;

   // Second candle: bearish
   if(!IsBearishCandle(second))
      return false;

   // Highs must match (within tolerance)
   double highDiff = MathAbs(first.high - second.high);
   if(highDiff > tolerancePoints)
      return false;

   // Second candle should show rejection at the high
   double secondUpper = UpperWick(second);
   double secondRange = CandleRange(second);
   if(secondRange <= 0.0)
      return false;

   return ((secondUpper / secondRange) >= 0.40);
}

bool IsTweezerBottom(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                     double tolerancePoints = 0)
{
   CandleData first, second;
   if(!GetCandleData(symbol, tf, shift + 1, first))
      return false;
   if(!GetCandleData(symbol, tf, shift, second))
      return false;

   // First candle: bearish
   if(!IsBearishCandle(first))
      return false;

   // Second candle: bullish
   if(!IsBullishCandle(second))
      return false;

   // Lows must match (within tolerance)
   double lowDiff = MathAbs(first.low - second.low);
   if(lowDiff > tolerancePoints)
      return false;

   // Second candle should show rejection at the low
   double secondLower = LowerWick(second);
   double secondRange = CandleRange(second);
   if(secondRange <= 0.0)
      return false;

   return ((secondLower / secondRange) >= 0.40);
}

// -----------------------------------------------------
// Rising Three Methods & Falling Three Methods - Continuation
// -----------------------------------------------------
bool IsRisingThreeMethods(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                          double maxConsolidationATRMult = 0.50)
{
   CandleData first, c2, c3, c4, fifth;
   if(!GetCandleData(symbol, tf, shift + 4, first)) return false;
   if(!GetCandleData(symbol, tf, shift + 3, c2)) return false;
   if(!GetCandleData(symbol, tf, shift + 2, c3)) return false;
   if(!GetCandleData(symbol, tf, shift + 1, c4)) return false;
   if(!GetCandleData(symbol, tf, shift, fifth)) return false;

   // First candle: strong bullish (long white)
   if(!IsBullishCandle(first))
      return false;
   double firstBody = CandleBody(first);
   double firstRange = CandleRange(first);
   if(firstRange <= 0.0 || (firstBody / firstRange) < 0.60)
      return false;

   // Next three candles: consolidation (small, within first candle's range)
   double firstTop = MathMax(first.open, first.close);
   double firstBottom = MathMin(first.open, first.close);

   for(int i = 3; i >= 1; i--)
   {
      CandleData c;
      if(!GetCandleData(symbol, tf, shift + i, c))
         return false;

      // All within first candle's body
      if(c.high > firstTop || c.low < firstBottom)
         return false;

      // Small candles
      double cRange = CandleRange(c);
      if(cRange > firstRange * maxConsolidationATRMult)
         return false;
   }

   // Fifth candle: strong bullish breaking above first candle high
   if(!IsBullishCandle(fifth))
      return false;
   double fifthBody = CandleBody(fifth);
   double fifthRange = CandleRange(fifth);
   if(fifthRange <= 0.0 || (fifthBody / fifthRange) < 0.60)
      return false;

   return (fifth.close > first.high);
}

bool IsFallingThreeMethods(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                           double maxConsolidationATRMult = 0.50)
{
   CandleData first, c2, c3, c4, fifth;
   if(!GetCandleData(symbol, tf, shift + 4, first)) return false;
   if(!GetCandleData(symbol, tf, shift + 3, c2)) return false;
   if(!GetCandleData(symbol, tf, shift + 2, c3)) return false;
   if(!GetCandleData(symbol, tf, shift + 1, c4)) return false;
   if(!GetCandleData(symbol, tf, shift, fifth)) return false;

   // First candle: strong bearish (long black)
   if(!IsBearishCandle(first))
      return false;
   double firstBody = CandleBody(first);
   double firstRange = CandleRange(first);
   if(firstRange <= 0.0 || (firstBody / firstRange) < 0.60)
      return false;

   // Next three candles: consolidation (small, within first candle's range)
   double firstTop = MathMax(first.open, first.close);
   double firstBottom = MathMin(first.open, first.close);

   for(int i = 3; i >= 1; i--)
   {
      CandleData c;
      if(!GetCandleData(symbol, tf, shift + i, c))
         return false;

      // All within first candle's body
      if(c.high > firstTop || c.low < firstBottom)
         return false;

      // Small candles
      double cRange = CandleRange(c);
      if(cRange > firstRange * maxConsolidationATRMult)
         return false;
   }

   // Fifth candle: strong bearish breaking below first candle low
   if(!IsBearishCandle(fifth))
      return false;
   double fifthBody = CandleBody(fifth);
   double fifthRange = CandleRange(fifth);
   if(fifthRange <= 0.0 || (fifthBody / fifthRange) < 0.60)
      return false;

   return (fifth.close < first.low);
}

// -----------------------------------------------------
// Pattern Context Detection - Where is the pattern?
// -----------------------------------------------------
enum ENUM_PATTERN_CONTEXT
{
   PATTERN_CONTEXT_UNKNOWN,
   PATTERN_CONTEXT_SUPPORT,      // At support level
   PATTERN_CONTEXT_RESISTANCE, // At resistance level
   PATTERN_CONTEXT_RANGE_LOW,  // At range low
   PATTERN_CONTEXT_RANGE_HIGH, // At range high
   PATTERN_CONTEXT_TREND_PULLBACK, // Pullback in trend
   PATTERN_CONTEXT_BREAKOUT    // After breakout
};

// Enhanced pattern detection with context awareness
bool IsBullishReversalAtSupport(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                                 double supportLevel, double atr)
{
   if(atr <= 0.0) return false;

   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   // Must be near support
   if(c.low > supportLevel + atr * 0.30)
      return false;

   // Check for reversal patterns
   return (
      IsSDHammer(symbol, tf, shift) ||
      IsBullishEngulfing(symbol, tf, shift) ||
      IsPiercingLine(symbol, tf, shift) ||
      IsBullishPinBar(symbol, tf, shift) ||
      IsSDMorningStar(symbol, tf, shift)
   );
}

bool IsBearishReversalAtResistance(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                                   double resistanceLevel, double atr)
{
   if(atr <= 0.0) return false;

   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   // Must be near resistance
   if(c.high < resistanceLevel - atr * 0.30)
      return false;

   // Check for reversal patterns
   return (
      IsShootingStar(symbol, tf, shift) ||
      IsBearishEngulfing(symbol, tf, shift) ||
      IsDarkCloudCover(symbol, tf, shift) ||
      IsBearishPinBar(symbol, tf, shift) ||
      IsSDEveningStar(symbol, tf, shift)
   );
}

// -----------------------------------------------------
// Master Pattern Scoring with ALL patterns
// -----------------------------------------------------
int AdvancedBullishPatternScore(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   int score = 0;

   // High-confidence patterns (5 points each)
   if(IsSDMorningStar(symbol, tf, shift))                  score += 5;
   if(IsThreeWhiteSoldiers(symbol, tf, shift))         score += 5;
   if(IsBullishMarubozu(symbol, tf, shift))              score += 5;

   // Strong patterns (4 points each)
   if(IsBullishEngulfing(symbol, tf, shift))             score += 4;
   if(IsPiercingLine(symbol, tf, shift))                 score += 4;
   if(IsTweezerBottom(symbol, tf, shift))                score += 4;

   // Moderate patterns (3 points each)
   if(IsBullishPinBar(symbol, tf, shift))                 score += 3;
   if(IsSDHammer(symbol, tf, shift))                     score += 3;
   if(IsBullishHarami(symbol, tf, shift))                score += 3;

   // Continuation patterns (2 points)
   if(IsRisingThreeMethods(symbol, tf, shift))          score += 2;
   if(IsStrongBullishBody(symbol, tf, shift, 0.65))      score += 2;

   // Weak patterns (1 point)
   if(IsBullishWickRejection(symbol, tf, shift, 0.40, 0.45)) score += 1;
   if(IsInsideBar(symbol, tf, shift))                    score += 1;

   return score;
}

int AdvancedBearishPatternScore(const string symbol, ENUM_TIMEFRAMES tf, int shift)
{
   int score = 0;

   // High-confidence patterns (5 points each)
   if(IsSDEveningStar(symbol, tf, shift))                score += 5;
   if(IsThreeBlackCrows(symbol, tf, shift))              score += 5;
   if(IsBearishMarubozu(symbol, tf, shift))              score += 5;

   // Strong patterns (4 points each)
   if(IsBearishEngulfing(symbol, tf, shift))             score += 4;
   if(IsDarkCloudCover(symbol, tf, shift))                 score += 4;
   if(IsTweezerTop(symbol, tf, shift))                    score += 4;

   // Moderate patterns (3 points each)
   if(IsBearishPinBar(symbol, tf, shift))                 score += 3;
   if(IsShootingStar(symbol, tf, shift))                 score += 3;
   if(IsBearishHarami(symbol, tf, shift))                score += 3;

   // Continuation patterns (2 points)
   if(IsFallingThreeMethods(symbol, tf, shift))          score += 2;
   if(IsStrongBearishBody(symbol, tf, shift, 0.65))       score += 2;

   // Weak patterns (1 point)
   if(IsBearishWickRejection(symbol, tf, shift, 0.40, 0.45)) score += 1;
   if(IsInsideBar(symbol, tf, shift))                    score += 1;

   return score;
}

// -----------------------------------------------------
// Startup/Trend Change Detection
// -----------------------------------------------------
bool IsBullishTrendStartup(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                           const double &closeArr[], int lookback = 10)
{
   // Check for strong bullish pattern
   if(!IsBullishMarubozu(symbol, tf, shift) &&
      !IsThreeWhiteSoldiers(symbol, tf, shift) &&
      !IsSDMorningStar(symbol, tf, shift))
      return false;

   // Check that price was declining or ranging before
   double highestInLookback = -DBL_MAX;
   double lowestInLookback = DBL_MAX;

   for(int i = shift + 1; i <= shift + lookback && i < ArraySize(closeArr); i++)
   {
      highestInLookback = MathMax(highestInLookback, closeArr[i]);
      lowestInLookback = MathMin(lowestInLookback, closeArr[i]);
   }

   if(lowestInLookback == DBL_MAX || highestInLookback == -DBL_MAX)
      return false;

   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   // Pattern should break above recent range or be at range low
   return (c.close > highestInLookback - (highestInLookback - lowestInLookback) * 0.30);
}

bool IsBearishTrendStartup(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                           const double &closeArr[], int lookback = 10)
{
   // Check for strong bearish pattern
   if(!IsBearishMarubozu(symbol, tf, shift) &&
      !IsThreeBlackCrows(symbol, tf, shift) &&
      !IsSDEveningStar(symbol, tf, shift))
      return false;

   // Check that price was rising or ranging before
   double highestInLookback = -DBL_MAX;
   double lowestInLookback = DBL_MAX;

   for(int i = shift + 1; i <= shift + lookback && i < ArraySize(closeArr); i++)
   {
      highestInLookback = MathMax(highestInLookback, closeArr[i]);
      lowestInLookback = MathMin(lowestInLookback, closeArr[i]);
   }

   if(lowestInLookback == DBL_MAX || highestInLookback == -DBL_MAX)
      return false;

   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   // Pattern should break below recent range or be at range high
   return (c.close < lowestInLookback + (highestInLookback - lowestInLookback) * 0.30);
}

// -----------------------------------------------------
// Trend Reversal Detection (High Confidence)
// -----------------------------------------------------
bool IsHighConfidenceBullishReversal(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                                       double supportLevel, double atr,
                                       const double &lowArr[], int lookback = 15)
{
   if(atr <= 0.0) return false;

   // Must have made a lower low or be at support
   double lowestLow = DBL_MAX;
   int lowestIdx = -1;
   for(int i = 2; i <= lookback && i < ArraySize(lowArr); i++)
   {
      if(lowArr[i] < lowestLow)
      {
         lowestLow = lowArr[i];
         lowestIdx = i;
      }
   }

   if(lowestIdx < 0) return false;

   // Recent price action near the low or support
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   bool nearLow = (c.low <= lowestLow + atr * 0.20);
   bool nearSupport = (c.low <= supportLevel + atr * 0.30);

   if(!nearLow && !nearSupport)
      return false;

   // High-scoring pattern required
   int score = AdvancedBullishPatternScore(symbol, tf, shift);
   return (score >= 4); // At least 4 points (strong engulfing or better)
}

bool IsHighConfidenceBearishReversal(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                                     double resistanceLevel, double atr,
                                     const double &highArr[], int lookback = 15)
{
   if(atr <= 0.0) return false;

   // Must have made a higher high or be at resistance
   double highestHigh = -DBL_MAX;
   int highestIdx = -1;
   for(int i = 2; i <= lookback && i < ArraySize(highArr); i++)
   {
      if(highArr[i] > highestHigh)
      {
         highestHigh = highArr[i];
         highestIdx = i;
      }
   }

   if(highestIdx < 0) return false;

   // Recent price action near the high or resistance
   CandleData c;
   if(!GetCandleData(symbol, tf, shift, c))
      return false;

   bool nearHigh = (c.high >= highestHigh - atr * 0.20);
   bool nearResistance = (c.high >= resistanceLevel - atr * 0.30);

   if(!nearHigh && !nearResistance)
      return false;

   // High-scoring pattern required
   int score = AdvancedBearishPatternScore(symbol, tf, shift);
   return (score >= 4); // At least 4 points (strong engulfing or better)
}

// -----------------------------------------------------
// Enhanced Combo with ALL patterns
// -----------------------------------------------------
bool IsAdvancedBullishCombo(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                            double supportLevel, double atr)
{
   double dummyClose[];
   ArrayResize(dummyClose, 0);
   return (
      IsBullishReversalAtSupport(symbol, tf, shift, supportLevel, atr) ||
      IsBullishTrendStartup(symbol, tf, shift, dummyClose, 10) ||
      AdvancedBullishPatternScore(symbol, tf, shift) >= 3
   );
}

bool IsAdvancedBearishCombo(const string symbol, ENUM_TIMEFRAMES tf, int shift,
                            double resistanceLevel, double atr)
{
   double dummyClose[];
   ArrayResize(dummyClose, 0);
   return (
      IsBearishReversalAtResistance(symbol, tf, shift, resistanceLevel, atr) ||
      IsBearishTrendStartup(symbol, tf, shift, dummyClose, 10) ||
      AdvancedBearishPatternScore(symbol, tf, shift) >= 3
   );
}

#endif
