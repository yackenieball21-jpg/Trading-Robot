//+------------------------------------------------------------------+
//|                                                RiskManager.mqh |
//|  RISK GUARDS AND LIMITS ONLY                                     |
//|  - Daily loss limits                                              |
//|  - Drawdown protection                                            |
//|  - Consecutive loss tracking                                      |
//|  - Min-lot fallback CONFIG (not calculation)                      |
//|  - Risk validation and blocking logic                             |
//|                                                                   |
//|  Does NOT calculate lots - see TradeExecutor.mqh                  |
//|  v5.13 — SL based on nearest S/R zone from ZoneManager          |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

#include <Trade\Trade.mqh>
#include "SymbolProfiler.mqh"
#include "MarketStateManager.mqh"
#include "IndicatorManager.mqh"

//+------------------------------------------------------------------+
//| Min-lot fallback config (set by MY BOT.mq5 inputs)              |
//+------------------------------------------------------------------+
bool   g_minLotFallbackEnabled  = false; // allow volMin when idealLots < volMin
double g_minLotFallbackMaxMult  = 5.0;   // block if volMin risk > this multiple of target risk
double g_minLotFallbackMaxEqPct = 6.0;   // block if volMin risk > this % of equity

//+------------------------------------------------------------------+
//| Aggressive min-lot fallback config (optional, default OFF)       |
//+------------------------------------------------------------------+
bool   g_allowAggressiveMinLotFallback   = false;  // second-stage fallback (default OFF)
double g_aggressiveMinLotFallbackMaxMult = 12.0;   // aggressive cap: max risk multiplier
double g_aggressiveMinLotFallbackMaxEqPct = 12.0;  // aggressive cap: max equity %

//+------------------------------------------------------------------+
//| Lot block reason tracking                                        |
//+------------------------------------------------------------------+
string g_lastLotBlockReason = "";

void SetLastLotBlockReason(string reason)
{
   g_lastLotBlockReason = reason;
}

string GetLastLotBlockReason()
{
   return g_lastLotBlockReason;
}

//+------------------------------------------------------------------+
//| Risk State — tracked per session                                 |
//+------------------------------------------------------------------+
struct RiskState
{
   double   dayStartEquity;
   double   dailyPnL;
   bool     dailyLossLocked;
   double   maxEquitySeen;
   double   currentDrawdownPct;
   bool     drawdownLocked;
   int      consecutiveLosses;
   bool     consecLossLocked;
   int      brokerErrorCount;
   bool     brokerErrorLocked;
   datetime dayStartTime;
   string   lockReason;
};

// Global risk state
RiskState g_risk;

//+------------------------------------------------------------------+
//| Initialize risk state at startup / daily reset                   |
//| dailyPnL starts at 0.0, NOT equity                               |
//+------------------------------------------------------------------+
void InitRiskState()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_risk.dayStartEquity    = equity;
   g_risk.dailyPnL          = 0.0;  // FIXED: Must be 0, not equity
   g_risk.dailyLossLocked   = false;
   g_risk.maxEquitySeen     = equity;
   g_risk.currentDrawdownPct = 0.0;
   g_risk.drawdownLocked    = false;
   g_risk.consecutiveLosses = 0;
   g_risk.consecLossLocked  = false;
   g_risk.brokerErrorCount  = 0;
   g_risk.brokerErrorLocked = false;
   g_risk.dayStartTime      = TimeCurrent();
   g_risk.lockReason        = "";
}

//+------------------------------------------------------------------+
//| Save risk state to file (survive restarts)                       |
//+------------------------------------------------------------------+
void SaveRiskState()
{
   string filename = "risk_state_" + _Symbol + ".dat";
   int fh = FileOpen(filename, FILE_WRITE | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE) return;

   FileWriteString(fh, DoubleToString(g_risk.dayStartEquity, 2) + "\n");
   FileWriteString(fh, DoubleToString(g_risk.dailyPnL, 2) + "\n");
   FileWriteString(fh, IntegerToString(g_risk.dailyLossLocked) + "\n");
   FileWriteString(fh, DoubleToString(g_risk.maxEquitySeen, 2) + "\n");
   FileWriteString(fh, DoubleToString(g_risk.currentDrawdownPct, 4) + "\n");
   FileWriteString(fh, IntegerToString(g_risk.drawdownLocked) + "\n");
   FileWriteString(fh, IntegerToString(g_risk.consecutiveLosses) + "\n");
   FileWriteString(fh, IntegerToString(g_risk.consecLossLocked) + "\n");
   FileWriteString(fh, IntegerToString(g_risk.brokerErrorCount) + "\n");
   FileWriteString(fh, IntegerToString(g_risk.brokerErrorLocked) + "\n");
   FileWriteString(fh, IntegerToString((long)g_risk.dayStartTime) + "\n");
   FileWriteString(fh, g_risk.lockReason + "\n");
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| Load risk state from file (returns false if stale or missing)    |
//+------------------------------------------------------------------+
bool LoadRiskState()
{
   string filename = "risk_state_" + _Symbol + ".dat";
   if(!FileIsExist(filename, FILE_COMMON)) return false;

   int fh = FileOpen(filename, FILE_READ | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE) return false;

   g_risk.dayStartEquity    = StringToDouble(FileReadString(fh));
   g_risk.dailyPnL          = StringToDouble(FileReadString(fh));
   g_risk.dailyLossLocked   = (bool)StringToInteger(FileReadString(fh));
   g_risk.maxEquitySeen     = StringToDouble(FileReadString(fh));
   g_risk.currentDrawdownPct = StringToDouble(FileReadString(fh));
   g_risk.drawdownLocked    = (bool)StringToInteger(FileReadString(fh));
   g_risk.consecutiveLosses = (int)StringToInteger(FileReadString(fh));
   g_risk.consecLossLocked  = (bool)StringToInteger(FileReadString(fh));
   g_risk.brokerErrorCount  = (int)StringToInteger(FileReadString(fh));
   g_risk.brokerErrorLocked = (bool)StringToInteger(FileReadString(fh));
   g_risk.dayStartTime      = (datetime)StringToInteger(FileReadString(fh));
   g_risk.lockReason        = FileReadString(fh);
   FileClose(fh);

   // Verify saved state is from today
   MqlDateTime dtNow, dtSaved;
   TimeToStruct(TimeCurrent(), dtNow);
   TimeToStruct(g_risk.dayStartTime, dtSaved);
   if(dtNow.day != dtSaved.day || dtNow.mon != dtSaved.mon || dtNow.year != dtSaved.year)
   {
      Print("RISK: Saved state is from a different day - using fresh init");
      return false;
   }

   Print("RISK: Restored state from file. dailyPnL=$", DoubleToString(g_risk.dailyPnL, 2),
         " consecLosses=", g_risk.consecutiveLosses,
         " locked=", g_risk.lockReason);
   return true;
}

//+------------------------------------------------------------------+
//| Check if a new trading day has started and reset daily counters   |
//+------------------------------------------------------------------+
void CheckDailyRiskReset()
{
   MqlDateTime dtNow, dtStart;
   TimeToStruct(TimeCurrent(), dtNow);
   TimeToStruct(g_risk.dayStartTime, dtStart);

   if(dtNow.day != dtStart.day || dtNow.mon != dtStart.mon || dtNow.year != dtStart.year)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      Print("RISK: Daily reset. Previous day PnL: $", DoubleToString(g_risk.dailyPnL, 2),
            " New equity baseline: $", DoubleToString(equity, 2));
      g_risk.dayStartEquity    = equity;
      g_risk.dailyPnL          = 0.0;
      g_risk.dailyLossLocked   = false;
      g_risk.consecutiveLosses = 0;
      g_risk.consecLossLocked  = false;
      g_risk.brokerErrorCount  = 0;
      g_risk.brokerErrorLocked = false;
      g_risk.drawdownLocked    = false;
      g_risk.dayStartTime      = TimeCurrent();
      g_risk.lockReason        = "";
   }
}

//+------------------------------------------------------------------+
//| Update daily PnL and drawdown tracking                           |
//+------------------------------------------------------------------+
void UpdateRiskMetrics(double maxDailyLossPct, double maxDrawdownPct)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   // Track high water mark
   if(equity > g_risk.maxEquitySeen)
      g_risk.maxEquitySeen = equity;

   // Daily PnL = current equity minus day start equity
   g_risk.dailyPnL = equity - g_risk.dayStartEquity;
   double dailyLossPct = 0.0;
   if(g_risk.dayStartEquity > 0)
      dailyLossPct = (-g_risk.dailyPnL / g_risk.dayStartEquity) * 100.0;

   // Daily loss lock
   if(!g_risk.dailyLossLocked && maxDailyLossPct > 0 && dailyLossPct >= maxDailyLossPct)
   {
      g_risk.dailyLossLocked = true;
      g_risk.lockReason = "Daily loss limit hit: " + DoubleToString(dailyLossPct, 2) + "% (max " + DoubleToString(maxDailyLossPct, 1) + "%)";
      Print("RISK LOCK: ", g_risk.lockReason);
   }

   // Account drawdown
   g_risk.currentDrawdownPct = 0.0;
   if(g_risk.maxEquitySeen > 0)
      g_risk.currentDrawdownPct = ((g_risk.maxEquitySeen - equity) / g_risk.maxEquitySeen) * 100.0;

   if(!g_risk.drawdownLocked && maxDrawdownPct > 0 && g_risk.currentDrawdownPct >= maxDrawdownPct)
   {
      g_risk.drawdownLocked = true;
      g_risk.lockReason = "Max drawdown hit: " + DoubleToString(g_risk.currentDrawdownPct, 2) + "% (max " + DoubleToString(maxDrawdownPct, 1) + "%)";
      Print("RISK LOCK: ", g_risk.lockReason);
   }

   // Drawdown recovery: unlock if dd drops 2% below threshold (hysteresis to prevent flapping)
   if(g_risk.drawdownLocked && maxDrawdownPct > 0 && g_risk.currentDrawdownPct < (maxDrawdownPct - 2.0))
   {
      g_risk.drawdownLocked = false;
      g_risk.lockReason = "";
      Print("RISK UNLOCK: Drawdown recovered to ", DoubleToString(g_risk.currentDrawdownPct, 2),
            "% (threshold=", DoubleToString(maxDrawdownPct, 1), "%) — resuming trading");
   }
}

//+------------------------------------------------------------------+
//| Record a trade result for consecutive loss tracking               |
//+------------------------------------------------------------------+
void RecordTradeResult(bool isWin, int maxConsecLosses)
{
   if(isWin)
   {
      g_risk.consecutiveLosses = 0;
      g_risk.consecLossLocked  = false;
   }
   else
   {
      g_risk.consecutiveLosses++;
      if(maxConsecLosses > 0 && g_risk.consecutiveLosses >= maxConsecLosses)
      {
         g_risk.consecLossLocked = true;
         g_risk.lockReason = "Consecutive losses: " + IntegerToString(g_risk.consecutiveLosses) + " (max " + IntegerToString(maxConsecLosses) + ")";
         Print("RISK LOCK: ", g_risk.lockReason);
      }
   }
}

//+------------------------------------------------------------------+
//| Record broker error                                              |
//+------------------------------------------------------------------+
void RecordBrokerError(int maxErrors)
{
   g_risk.brokerErrorCount++;
   if(maxErrors > 0 && g_risk.brokerErrorCount >= maxErrors)
   {
      g_risk.brokerErrorLocked = true;
      g_risk.lockReason = "Too many broker errors: " + IntegerToString(g_risk.brokerErrorCount);
      Print("RISK LOCK: ", g_risk.lockReason);
   }
}

//+------------------------------------------------------------------+
//| Check if trading is risk-allowed                                 |
//+------------------------------------------------------------------+
bool IsRiskAllowed()
{
   if(g_risk.dailyLossLocked)   return false;
   if(g_risk.drawdownLocked)    return false;
   if(g_risk.consecLossLocked)  return false;
   if(g_risk.brokerErrorLocked) return false;
   return true;
}

//+------------------------------------------------------------------+
//| Normalize price to symbol digits                                 |
//+------------------------------------------------------------------+
double NormalizePrice(double price, int digits)
{
   return NormalizeDouble(price, digits);
}

//+------------------------------------------------------------------+
//| Determine decimal digits from volume step                        |
//+------------------------------------------------------------------+
int VolumeStepDigits(double step)
{
   if(step <= 0) return 2;
   int digits = 0;
   double s = step;
   while(s < 1.0 && digits < 8)
   {
      s *= 10.0;
      digits++;
   }
   return digits;
}

//+------------------------------------------------------------------+
//| Round volume down to step — use step-based precision             |
//+------------------------------------------------------------------+
double NormalizeVolumeToStep(double volume, const SymbolProfile &prof)
{
   double step = prof.volumeStep;
   if(step <= 0.0) step = 0.01;

   double normalized = MathFloor(volume / step) * step;

   if(normalized < prof.volumeMin)
      return 0.0;

   if(normalized > prof.volumeMax)
      normalized = prof.volumeMax;

   int stepDigits = VolumeStepDigits(step);
   return NormalizeDouble(normalized, stepDigits);
}

//+------------------------------------------------------------------+
//| Get effective minimum SL distance for this symbol                |
//+------------------------------------------------------------------+
double GetMinSLDistance(const SymbolProfile &prof, double minSLOverridePoints)
{
   double brokerMin = prof.stopsLevelPoints * prof.point;
   double overrideMin = minSLOverridePoints * prof.point;
   double profileMin = prof.defaultMinSLPoints * prof.point;
   // Minimum SL must also be at least 2x the spread to make sense
   double spreadMin = prof.defaultSpreadCapPoints * prof.point * 2.0;

   double effective = MathMax(brokerMin, overrideMin);
   effective = MathMax(effective, profileMin);
   effective = MathMax(effective, spreadMin);

   if(effective <= 0)
      effective = prof.point * 500;  // Absolute fallback: 500 points

   return effective;
}

//+------------------------------------------------------------------+
//| Find swing lows in closed-candle data (index 1..maxBars)         |
//| A swing low at bar i: low[i] < low[i-1] AND low[i] < low[i+1]   |
//| Returns count of swing lows found, fills swingLows[] (price) and |
//| swingLowBars[] (bar index).  Sorted newest-first.                |
//+------------------------------------------------------------------+
int FindSwingLows(const IndicatorState &ind, double &swingLows[], int &swingLowBars[],
                  int maxResults, int lookback)
{
   int count = 0;
   // Scan closed candles: index 2..57 (need 1 bar each side)
   int startBar = 1 + lookback;
   int endBar   = 199 - lookback; // highArr/lowArr have 200 elements, indices 0-199

   for(int i = startBar; i <= endBar && count < maxResults; i++)
   {
      bool isSwingLow = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(ind.lowArr[i] >= ind.lowArr[i - j] || ind.lowArr[i] >= ind.lowArr[i + j])
         { isSwingLow = false; break; }
      }
      if(isSwingLow)
      {
         swingLows[count]    = ind.lowArr[i];
         swingLowBars[count] = i;
         count++;
      }
   }
   return count; // already newest-first (smallest index = most recent)
}

//+------------------------------------------------------------------+
//| Find swing highs in closed-candle data (index 1..maxBars)        |
//+------------------------------------------------------------------+
int FindSwingHighs(const IndicatorState &ind, double &swingHighs[], int &swingHighBars[],
                   int maxResults, int lookback)
{
   int count = 0;
   int startBar = 1 + lookback;
   int endBar   = 199 - lookback;

   for(int i = startBar; i <= endBar && count < maxResults; i++)
   {
      bool isSwingHigh = true;
      for(int j = 1; j <= lookback; j++)
      {
         if(ind.highArr[i] <= ind.highArr[i - j] || ind.highArr[i] <= ind.highArr[i + j])
         { isSwingHigh = false; break; }
      }
      if(isSwingHigh)
      {
         swingHighs[count]    = ind.highArr[i];
         swingHighBars[count] = i;
         count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Find the most recent Higher Low for BUY SL                       |
//| A "higher low" = a swing low whose price > the previous swing low|
//| Returns the price of the higher low, or 0 if none found.         |
//+------------------------------------------------------------------+
double FindLastHigherLow(const IndicatorState &ind, int swingLookback)
{
   double swingLows[20];
   int    swingLowBars[20];
   int count = FindSwingLows(ind, swingLows, swingLowBars, 20, swingLookback);

   if(count < 2)
   {
      Print("SL STRUCT: Not enough swing lows found (", count, ")");
      return 0;
   }

   // Swing lows are newest-first (index 0 = most recent)
   // Walk from newest to oldest, find the first pair where swingLows[i] > swingLows[i+1]
   // That means swingLows[i] is a higher low relative to the older swingLows[i+1]
   for(int i = 0; i < count - 1; i++)
   {
      if(swingLows[i] > swingLows[i + 1])
      {
         Print("SL STRUCT BUY: Found higher low at bar ", swingLowBars[i],
               " price=", swingLows[i],
               " (prev low at bar ", swingLowBars[i + 1],
               " price=", swingLows[i + 1], ")");
         return swingLows[i];
      }
   }

   Print("SL STRUCT: No higher low found in ", count, " swing lows");
   return 0;
}

//+------------------------------------------------------------------+
//| Find the most recent Lower High for SELL SL                      |
//| A "lower high" = a swing high whose price < the previous swing   |
//| high. Returns the price, or 0 if none found.                     |
//+------------------------------------------------------------------+
double FindLastLowerHigh(const IndicatorState &ind, int swingLookback)
{
   double swingHighs[20];
   int    swingHighBars[20];
   int count = FindSwingHighs(ind, swingHighs, swingHighBars, 20, swingLookback);

   if(count < 2)
   {
      Print("SL STRUCT: Not enough swing highs found (", count, ")");
      return 0;
   }

   // Walk from newest to oldest, find first pair where swingHighs[i] < swingHighs[i+1]
   for(int i = 0; i < count - 1; i++)
   {
      if(swingHighs[i] < swingHighs[i + 1])
      {
         Print("SL STRUCT SELL: Found lower high at bar ", swingHighBars[i],
               " price=", swingHighs[i],
               " (prev high at bar ", swingHighBars[i + 1],
               " price=", swingHighs[i + 1], ")");
         return swingHighs[i];
      }
   }

   Print("SL STRUCT: No lower high found in ", count, " swing highs");
   return 0;
}

//+------------------------------------------------------------------+
//| GetStructuralLow — nearest swing low below entry for buy SL      |
//| Scans closed candles for swing lows using left/right comparison   |
//| Returns the most recent swing low below entry, or 0 if none      |
//+------------------------------------------------------------------+
double GetStructuralLow(const IndicatorState &ind, double entryPrice, int lookback)
{
   int lb = MathMax(lookback / 2, 2);
   int startBar = 1 + lb;
   int endBar   = 199 - lb;
   if(endBar < startBar) endBar = startBar;

   // Collect swing lows below entry (most recent first, index 0 = closest to now)
   double swingLows[];
   ArrayResize(swingLows, 0);

   for(int i = startBar; i <= endBar; i++)
   {
      bool isSwing = true;
      for(int j = 1; j <= lb; j++)
      {
         if(ind.lowArr[i] >= ind.lowArr[i - j] || ind.lowArr[i] >= ind.lowArr[i + j])
         { isSwing = false; break; }
      }
      if(isSwing && ind.lowArr[i] < entryPrice)
      {
         int sz = ArraySize(swingLows);
         ArrayResize(swingLows, sz + 1);
         swingLows[sz] = ind.lowArr[i];
      }
   }

   int count = ArraySize(swingLows);
   if(count == 0) return 0;

   // Prefer the most recent higher low (stronger structure)
   for(int i = 0; i < count - 1; i++)
   {
      if(swingLows[i] > swingLows[i + 1])
         return swingLows[i];
   }

   // Fallback: most recent swing low
   return swingLows[0];
}

//+------------------------------------------------------------------+
//| GetStructuralHigh — nearest swing high above entry for sell SL    |
//| Scans closed candles for swing highs using left/right comparison  |
//| Returns the most recent swing high above entry, or 0 if none     |
//+------------------------------------------------------------------+
double GetStructuralHigh(const IndicatorState &ind, double entryPrice, int lookback)
{
   int lb = MathMax(lookback / 2, 2);
   int startBar = 1 + lb;
   int endBar   = 199 - lb;
   if(endBar < startBar) endBar = startBar;

   // Collect swing highs above entry (most recent first)
   double swingHighs[];
   ArrayResize(swingHighs, 0);

   for(int i = startBar; i <= endBar; i++)
   {
      bool isSwing = true;
      for(int j = 1; j <= lb; j++)
      {
         if(ind.highArr[i] <= ind.highArr[i - j] || ind.highArr[i] <= ind.highArr[i + j])
         { isSwing = false; break; }
      }
      if(isSwing && ind.highArr[i] > entryPrice)
      {
         int sz = ArraySize(swingHighs);
         ArrayResize(swingHighs, sz + 1);
         swingHighs[sz] = ind.highArr[i];
      }
   }

   int count = ArraySize(swingHighs);
   if(count == 0) return 0;

   // Prefer the most recent lower high (stronger structure)
   for(int i = 0; i < count - 1; i++)
   {
      if(swingHighs[i] < swingHighs[i + 1])
         return swingHighs[i];
   }

   // Fallback: most recent swing high
   return swingHighs[0];
}

//+------------------------------------------------------------------+
//| Buy SL: StructuralLow - ATR (structure + ATR buffer)             |
//| Returns 0 if no valid structure or ATR is invalid (reject trade)  |
//+------------------------------------------------------------------+
double GetBuyStopLoss(double entryPrice, const IndicatorState &ind,
                      const SymbolProfile &prof, int swingLookback,
                      double minSLOverride)
{
   double atrVal = GetATR(ind, 1);
   if(atrVal <= 0)
   {
      Print("SL CALC BUY: ATR is zero or invalid — skipping trade");
      return 0;
   }

   double structLow = GetStructuralLow(ind, entryPrice, swingLookback);
   if(structLow <= 0)
   {
      // ATR fallback: use entry - ATR * 1.5 when no structure found
      structLow = entryPrice - atrVal * 1.5;
      Print("SL CALC BUY: No structural low found — using ATR fallback: ", DoubleToString(structLow, prof.digits));
   }

   // SL = structural low - ATR * profile SL multiplier
   double sl = NormalizePrice(structLow - atrVal * prof.atrSLMult, prof.digits);

   // Ensure SL meets minimum distance requirement
   double minDist = GetMinSLDistance(prof, minSLOverride);
   if(entryPrice - sl < minDist)
      sl = NormalizePrice(entryPrice - minDist, prof.digits);

   if(sl >= entryPrice)
      sl = NormalizePrice(entryPrice - minDist, prof.digits);

   Print("SL CALC BUY: entry=", DoubleToString(entryPrice, prof.digits),
         " structLow=", DoubleToString(structLow, prof.digits),
         " ATR=", DoubleToString(atrVal, prof.digits),
         " atrSLMult=", DoubleToString(prof.atrSLMult, 2),
         " buffer=", DoubleToString(atrVal * prof.atrSLMult, prof.digits),
         " sl=", DoubleToString(sl, prof.digits),
         " dist=", DoubleToString((entryPrice - sl) / prof.point, 0), "pts");

   return sl;
}

//+------------------------------------------------------------------+
//| Sell SL: StructuralHigh + ATR (structure + ATR buffer)            |
//| Returns 0 if no valid structure or ATR is invalid (reject trade)  |
//+------------------------------------------------------------------+
double GetSellStopLoss(double entryPrice, const IndicatorState &ind,
                       const SymbolProfile &prof, int swingLookback,
                       double minSLOverride)
{
   double atrVal = GetATR(ind, 1);
   if(atrVal <= 0)
   {
      Print("SL CALC SELL: ATR is zero or invalid — skipping trade");
      return 0;
   }

   double structHigh = GetStructuralHigh(ind, entryPrice, swingLookback);
   if(structHigh <= 0)
   {
      // ATR fallback: use entry + ATR * 1.5 when no structure found
      structHigh = entryPrice + atrVal * 1.5;
      Print("SL CALC SELL: No structural high found — using ATR fallback: ", DoubleToString(structHigh, prof.digits));
   }

   // SL = structural high + ATR * profile SL multiplier
   double sl = NormalizePrice(structHigh + atrVal * prof.atrSLMult, prof.digits);

   // Ensure SL meets minimum distance requirement
   double minDist = GetMinSLDistance(prof, minSLOverride);
   if(sl - entryPrice < minDist)
      sl = NormalizePrice(entryPrice + minDist, prof.digits);

   if(sl <= entryPrice)
      sl = NormalizePrice(entryPrice + minDist, prof.digits);

   Print("SL CALC SELL: entry=", DoubleToString(entryPrice, prof.digits),
         " structHigh=", DoubleToString(structHigh, prof.digits),
         " ATR=", DoubleToString(atrVal, prof.digits),
         " atrSLMult=", DoubleToString(prof.atrSLMult, 2),
         " buffer=", DoubleToString(atrVal * prof.atrSLMult, prof.digits),
         " sl=", DoubleToString(sl, prof.digits),
         " dist=", DoubleToString((sl - entryPrice) / prof.point, 0), "pts");

   return sl;
}

//+------------------------------------------------------------------+
//| Calculate TP from entry, SL, and reward-risk ratio               |
//+------------------------------------------------------------------+
double GetTakeProfitFromRR(ENUM_ORDER_TYPE type, double entry, double sl, double rr, int digits)
{
   double dist = MathAbs(entry - sl);
   if(type == ORDER_TYPE_BUY)
      return NormalizePrice(entry + dist * rr, digits);
   else
      return NormalizePrice(entry - dist * rr, digits);
}

//+------------------------------------------------------------------+
//| Calculate lot size as fixed % of equity (simpler approach)        |
//| Uses equity percentage directly without risk calculation          |
//+------------------------------------------------------------------+
double CalcLotByEquityPercent(double equityPercent, const SymbolProfile &prof)
{
   SetLastLotBlockReason("");
   
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lotValue = equity * equityPercent / 100.0;
   
   if(lotValue <= 0 || equity <= 0)
   {
      SetLastLotBlockReason("INVALID_EQUITY | equity=" + DoubleToString(equity, 2));
      return 0.0;
   }
   
   // Get contract size (lot value per 1.0 lot)
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   if(contractSize <= 0) contractSize = 100000.0; // Default for forex
   
   // Calculate lot size: lotValue / contractSize
   double lots = lotValue / contractSize;
   
   Print("LOT CALC (EQUITY%): equity=", DoubleToString(equity, 2),
         " equityPct=", DoubleToString(equityPercent, 2), "%",
         " lotValue=", DoubleToString(lotValue, 2),
         " contractSize=", DoubleToString(contractSize, 0),
         " rawLots=", DoubleToString(lots, 4));
   
   // Normalize to broker's volume step
   int stepDigits = VolumeStepDigits(prof.volumeStep);
   double normalizedLots = NormalizeVolumeToStep(lots, prof);
   
   if(normalizedLots < prof.volumeMin)
   {
      Print("LOT WARNING: Calculated lots (", DoubleToString(normalizedLots, stepDigits),
            ") below broker minimum (", DoubleToString(prof.volumeMin, stepDigits),
            ") - using minimum");
      normalizedLots = prof.volumeMin;
   }
   
   if(normalizedLots > prof.volumeMax)
   {
      Print("LOT WARNING: Calculated lots (", DoubleToString(normalizedLots, stepDigits),
            ") above broker maximum (", DoubleToString(prof.volumeMax, stepDigits),
            ") - using maximum");
      normalizedLots = prof.volumeMax;
   }
   
   Print("LOT CALC (EQUITY%): Final lots=", DoubleToString(normalizedLots, stepDigits));
   
   return normalizedLots;
}

//+------------------------------------------------------------------+
//| Calculate lot size by risking riskPercent of equity               |
//| Rejects if min lot exceeds intended risk by >10%                 |
//+------------------------------------------------------------------+
double CalcLotByRisk(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLossPrice,
                     double riskPercent, const SymbolProfile &prof,
                     double aiRiskMult, bool aiActive)
{
   // Clear previous reason
   SetLastLotBlockReason("");
   
   double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney = equity * riskPercent / 100.0;

   if(riskMoney <= 0 || entryPrice <= 0 || stopLossPrice <= 0)
   {
      SetLastLotBlockReason("INVALID_INPUTS | riskMoney=" + DoubleToString(riskMoney, 2) +
                            " entry=" + DoubleToString(entryPrice, _Digits) +
                            " sl=" + DoubleToString(stopLossPrice, _Digits));
      return 0.0;
   }

   double slDist = MathAbs(entryPrice - stopLossPrice);
   if(slDist <= 0)
   {
      SetLastLotBlockReason("INVALID_STOP_DISTANCE | slDist=0");
      return 0.0;
   }

   // Refresh tick value from broker (can change for cross-currency pairs)
   double freshTickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double freshTickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(freshTickSize <= 0) freshTickSize = prof.tickSize;
   if(freshTickValue <= 0) freshTickValue = prof.tickValue;

   // Use OrderCalcProfit to find loss per 1 lot (most accurate)
   double profitPerLot = 0.0;
   bool ok = false;

   if(orderType == ORDER_TYPE_BUY)
      ok = OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, entryPrice, stopLossPrice, profitPerLot);
   else
      ok = OrderCalcProfit(ORDER_TYPE_SELL, _Symbol, 1.0, entryPrice, stopLossPrice, profitPerLot);

   double lossPerLot = 0.0;

   if(!ok || profitPerLot >= 0)
   {
      // Fallback: tick-based calculation with FRESH values
      if(freshTickSize <= 0 || freshTickValue <= 0)
      {
         SetLastLotBlockReason("INVALID_TICK_DATA | tickSize=" + DoubleToString(freshTickSize, 8) +
                               " tickValue=" + DoubleToString(freshTickValue, 8));
         Print("LOT ERROR: Invalid tick data for lot calc (tickSize=", freshTickSize,
               " tickValue=", freshTickValue, ")");
         return 0.0;
      }
      double ticks = slDist / freshTickSize;
      lossPerLot = ticks * freshTickValue;
      Print("LOT CALC: using tick-based fallback (OrderCalcProfit failed or returned >=0)");
   }
   else
   {
      lossPerLot = MathAbs(profitPerLot);
   }

   if(lossPerLot <= 0)
   {
      SetLastLotBlockReason("ZERO_LOSS_PER_LOT | lossPerLot=0");
      Print("LOT ERROR: Zero loss per lot");
      return 0.0;
   }

   double lots = riskMoney / lossPerLot;

   Print("LOT CALC: equity=", DoubleToString(equity, 2),
         " riskPct=", DoubleToString(riskPercent, 2), "%",
         " riskMoney=", DoubleToString(riskMoney, 2),
         " slDist=", DoubleToString(slDist, prof.digits),
         " lossPerLot=", DoubleToString(lossPerLot, 2),
         " idealLots=", DoubleToString(lots, 4));

   // Apply AI risk multiplier if active (can only reduce, not increase)
   if(aiActive && aiRiskMult > 0 && aiRiskMult <= 1.0)
   {
      Print("LOT CALC: AI risk multiplier applied: ", DoubleToString(aiRiskMult, 2),
            " lots reduced from ", DoubleToString(lots, 4),
            " to ", DoubleToString(lots * aiRiskMult, 4));
      lots *= aiRiskMult;
   }

   int stepDigits = VolumeStepDigits(prof.volumeStep);

   // Case 1: ideal lot is already at/above broker minimum -> normal path
   if(lots >= prof.volumeMin)
   {
      double normalizedLots = NormalizeVolumeToStep(lots, prof);
      if(normalizedLots <= 0.0)
      {
         SetLastLotBlockReason("NORMALIZED_TO_ZERO | idealLots=" + DoubleToString(lots, 4) +
                               " volMin=" + DoubleToString(prof.volumeMin, stepDigits) +
                               " volStep=" + DoubleToString(prof.volumeStep, stepDigits));
         Print("LOT BLOCKED: normalized to 0 even though idealLots>=volMin (idealLots=",
               DoubleToString(lots, 4),
               " volMin=", DoubleToString(prof.volumeMin, stepDigits),
               " volStep=", DoubleToString(prof.volumeStep, stepDigits), ")");
         return 0.0;
      }

      Print("LOT CALC: normalizedLots=", DoubleToString(normalizedLots, stepDigits));
      SetLastLotBlockReason("");  // Success - clear any reason
      return normalizedLots;
   }

   // Case 2: ideal lot is below broker minimum -> controlled fallback evaluation
   Print("LOT BELOW MIN: idealLots=", DoubleToString(lots, 4),
         " volMin=", DoubleToString(prof.volumeMin, stepDigits),
         " volStep=", DoubleToString(prof.volumeStep, stepDigits));

   double minLotRisk      = lossPerLot * prof.volumeMin;
   double minLotRiskMult  = (riskMoney > 0.0) ? (minLotRisk / riskMoney) : 999.0;
   double minLotRiskPctEq = (equity > 0.0) ? (minLotRisk / equity * 100.0) : 999.0;

   // STAGE 1: Normal fallback (strict caps)
   if(g_minLotFallbackEnabled && lossPerLot > 0.0)
   {
      bool passMultCap  = (minLotRiskMult  <= g_minLotFallbackMaxMult);
      bool passEqPctCap = (minLotRiskPctEq <= g_minLotFallbackMaxEqPct);

      if(passMultCap && passEqPctCap)
      {
         double minLot = NormalizeDouble(prof.volumeMin, stepDigits);

         Print("LOT FALLBACK: using volMin=", DoubleToString(minLot, stepDigits),
               " pass=mult+eqpct",
               " riskMult=", DoubleToString(minLotRiskMult, 2),
               "x max=", DoubleToString(g_minLotFallbackMaxMult, 2),
               " eqRisk=", DoubleToString(minLotRiskPctEq, 2),
               "% maxEq=", DoubleToString(g_minLotFallbackMaxEqPct, 2), "%");

         SetLastLotBlockReason("");  // Success - clear any reason
         return minLot;
      }
   }

   // STAGE 2: Aggressive fallback (optional, default OFF)
   if(g_allowAggressiveMinLotFallback && lossPerLot > 0.0)
   {
      bool passAggrMult  = (minLotRiskMult  <= g_aggressiveMinLotFallbackMaxMult);
      bool passAggrEqPct = (minLotRiskPctEq <= g_aggressiveMinLotFallbackMaxEqPct);

      if(passAggrMult && passAggrEqPct)
      {
         double minLot = NormalizeDouble(prof.volumeMin, stepDigits);

         Print("LOT FALLBACK: aggressive mode using volMin=", DoubleToString(minLot, stepDigits),
               " riskMult=", DoubleToString(minLotRiskMult, 2),
               "x aggrMax=", DoubleToString(g_aggressiveMinLotFallbackMaxMult, 2),
               " eqRisk=", DoubleToString(minLotRiskPctEq, 2),
               "% aggrMaxEq=", DoubleToString(g_aggressiveMinLotFallbackMaxEqPct, 2), "%");

         SetLastLotBlockReason("");  // Success - clear any reason
         return minLot;
      }
   }

   // HARD SKIP: Account too small for stop
   string blockReason = StringFormat(
      "HARD_SKIP_ACCOUNT_TOO_SMALL_FOR_STOP | symbol=%s tf=%s equity=%.2f riskMoney=%.2f idealLots=%.4f volMin=%.4f minLotRiskMult=%.2f minLotRiskPctEq=%.2f",
      _Symbol, EnumToString(Period()), equity, riskMoney, lots, prof.volumeMin, minLotRiskMult, minLotRiskPctEq);
   
   SetLastLotBlockReason(blockReason);

   Print("LOT BLOCKED: ", blockReason);

   return 0.0;
}

//+------------------------------------------------------------------+
//| Validate SL/TP against broker stops level                        |
//+------------------------------------------------------------------+
bool ValidateStopsAgainstStopsLevel(ENUM_ORDER_TYPE type, double entry, double sl, double tp,
                                     const SymbolProfile &prof, double minSLOverride)
{
   double minDist = GetMinSLDistance(prof, minSLOverride);

   if(sl != 0)
   {
      if(MathAbs(entry - sl) < minDist)
      {
         Print("VALIDATE: SL too close. dist=", DoubleToString(MathAbs(entry - sl), prof.digits),
               " min=", DoubleToString(minDist, prof.digits));
         return false;
      }
      if(type == ORDER_TYPE_BUY  && sl >= entry) { Print("VALIDATE: SL above entry for BUY");  return false; }
      if(type == ORDER_TYPE_SELL && sl <= entry) { Print("VALIDATE: SL below entry for SELL"); return false; }
   }
   if(tp != 0)
   {
      if(MathAbs(entry - tp) < minDist)
      {
         Print("VALIDATE: TP too close. dist=", DoubleToString(MathAbs(entry - tp), prof.digits),
               " min=", DoubleToString(minDist, prof.digits));
         return false;
      }
      if(type == ORDER_TYPE_BUY  && tp <= entry) { Print("VALIDATE: TP below entry for BUY");  return false; }
      if(type == ORDER_TYPE_SELL && tp >= entry) { Print("VALIDATE: TP above entry for SELL"); return false; }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Validate AI-adjusted SL is still valid after multiplier          |
//+------------------------------------------------------------------+
bool ValidateAIAdjustedStop(ENUM_ORDER_TYPE type, double entry, double sl,
                             const SymbolProfile &prof, double minSLOverride)
{
   double minDist = GetMinSLDistance(prof, minSLOverride);

   if(type == ORDER_TYPE_BUY)
   {
      if(sl >= entry) { Print("AI SL INVALID: Buy SL above entry after AI adjustment"); return false; }
      if(entry - sl < minDist) { Print("AI SL INVALID: Buy SL too close after AI adjustment"); return false; }
   }
   else
   {
      if(sl <= entry) { Print("AI SL INVALID: Sell SL below entry after AI adjustment"); return false; }
      if(sl - entry < minDist) { Print("AI SL INVALID: Sell SL too close after AI adjustment"); return false; }
   }
   return true;
}

//+------------------------------------------------------------------+
//| Validate and set appropriate filling mode                        |
//+------------------------------------------------------------------+
bool ValidateOrderFillingMode(CTrade &trade, const SymbolProfile &prof)
{
   long fm = prof.fillingMode;

   if((fm & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fm & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);

   return true;
}

//+------------------------------------------------------------------+
//| Zone-based SL: entry zone extreme + ATR buffer (Part A1)        |
//+------------------------------------------------------------------+
double ComputeZoneStopLoss(ENUM_ORDER_TYPE orderType, int entryZoneIdx, double atr, int digits)
{
   if(entryZoneIdx < 0 || atr <= 0) return 0.0;
   if(orderType == ORDER_TYPE_BUY)
   {
      double extremeLow = GetZoneExtremeLow(entryZoneIdx);
      if(extremeLow <= 0) return 0.0;
      return NormalizeDouble(extremeLow - atr * 0.30, digits);
   }
   else
   {
      double extremeHigh = GetZoneExtremeHigh(entryZoneIdx);
      if(extremeHigh <= 0) return 0.0;
      return NormalizeDouble(extremeHigh + atr * 0.30, digits);
   }
}

//+------------------------------------------------------------------+
//| Zone-to-zone TP: buffered before opposing zone, or RR fallback  |
//+------------------------------------------------------------------+
double ComputeZoneTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice, double atr,
                              int digits, double fallbackSL, double rewardRisk,
                              bool &usedZoneTarget)
{
   usedZoneTarget = false;
   int    tIdx  = -1;
   double tLow  = 0.0;
   double tHigh = 0.0;

   if(orderType == ORDER_TYPE_BUY)
   {
      if(FindNextResistanceZoneAbove(entryPrice, atr, tIdx, tLow, tHigh))
      {
         double tp = NormalizeDouble(tLow - atr * 0.30, digits);
         if(tp > entryPrice + atr * 0.5)
         {
            usedZoneTarget = true;
            Print("[TP source = next resistance zone] zone[", tIdx,
                  "] tp=", DoubleToString(tp, digits));
            return tp;
         }
      }
      double tp = GetTakeProfitFromRR(ORDER_TYPE_BUY, entryPrice, fallbackSL, rewardRisk, digits);
      Print("[TP source = RR fallback] tp=", DoubleToString(tp, digits));
      return tp;
   }
   else
   {
      if(FindNextSupportZoneBelow(entryPrice, atr, tIdx, tLow, tHigh))
      {
         double tp = NormalizeDouble(tHigh + atr * 0.30, digits);
         if(tp < entryPrice - atr * 0.5)
         {
            usedZoneTarget = true;
            Print("[TP source = next support zone] zone[", tIdx,
                  "] tp=", DoubleToString(tp, digits));
            return tp;
         }
      }
      double tp = GetTakeProfitFromRR(ORDER_TYPE_SELL, entryPrice, fallbackSL, rewardRisk, digits);
      Print("[TP source = RR fallback] tp=", DoubleToString(tp, digits));
      return tp;
   }
}

//+------------------------------------------------------------------+
//| Projected R:R = |TP - entry| / |entry - SL|                    |
//+------------------------------------------------------------------+
double ComputeProjectedRR(double entry, double sl, double tp)
{
   double risk = MathAbs(entry - sl);
   if(risk <= 0) return 0.0;
   return MathAbs(tp - entry) / risk;
}

#endif // RISK_MANAGER_MQH
