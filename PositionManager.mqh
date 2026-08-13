//+------------------------------------------------------------------+
//|                                             PositionManager.mqh |
//|  COMPLETE POSITION LIFECYCLE MANAGEMENT                          |
//|  - Position counting and tracking                                |
//|  - Position closing (safe close with retries)                    |
//|  - R-based breakeven and trailing stops                          |
//|  - Structure-aware trailing (swing highs/lows)                   |
//|  - EMA50/ATR-based trailing                                      |
//|  - Exit filters (EMA50 reversal, profit protection)              |
//|  - Initial risk registry (1R tracking)                           |
//|  - Strategy owner detection (trend/range/breakout/reversal)      |
//|                                                                   |
//|  v7.1 - Merged TradeManager.mqh for unified position management  |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef POSITION_MANAGER_MQH
#define POSITION_MANAGER_MQH

#include <Trade\Trade.mqh>
#include "SymbolProfiler.mqh"
#include "MarketStateManager.mqh"
#include "IndicatorManager.mqh"
#include "MarketStructure.mqh"
#include "ZoneManager.mqh"

//+------------------------------------------------------------------+
//| Strategy Owner Types                                             |
//+------------------------------------------------------------------+
enum STRATEGY_OWNER
{
   OWNER_NONE      = 0,
   OWNER_TREND     = 1,
   OWNER_BREAKOUT  = 2,
   OWNER_RANGE     = 3,
   OWNER_REVERSAL  = 4
};

//+------------------------------------------------------------------+
//| Position Comment Helpers                                         |
//+------------------------------------------------------------------+
bool IsTrendTradeComment(const string comment)
{
   if(IsCounterTrendTradeComment(comment))
      return false;

   return (StringFind(comment, "TREND_BUY") >= 0 ||
           StringFind(comment, "TREND_SELL") >= 0 ||
           StringFind(comment, "TREND_RUNNER_BUY") >= 0 ||
           StringFind(comment, "TREND_RUNNER_SELL") >= 0 ||
           StringFind(comment, "TREND_CONTINUATION_BUY") >= 0 ||
           StringFind(comment, "TREND_CONTINUATION_SELL") >= 0);
}

bool IsTrendPositionComment(const string comment)
{
   if(IsCounterTrendTradeComment(comment))
      return false;

   return (StringFind(comment, "TREND_BUY") >= 0 ||
           StringFind(comment, "TREND_SELL") >= 0 ||
           StringFind(comment, "TREND_RUNNER_BUY") >= 0 ||
           StringFind(comment, "TREND_RUNNER_SELL") >= 0 ||
           StringFind(comment, "TREND_CONTINUATION_BUY") >= 0 ||
           StringFind(comment, "TREND_CONTINUATION_SELL") >= 0);
}

bool IsBreakoutTradeComment(const string comment)
{
   return (StringFind(comment, "BREAKOUT") >= 0);
}

bool IsRangeTradeComment(const string comment)
{
   return (StringFind(comment, "RANGE") >= 0);
}

bool IsReversalTradeComment(const string comment)
{
   return (StringFind(comment, "REVERSAL") >= 0);
}

bool IsCounterTrendTradeComment(const string comment)
{
   return (StringFind(comment, "CT_BUY") >= 0 || StringFind(comment, "CT_SELL") >= 0);
}

STRATEGY_OWNER GetOwnerFromComment(const string comment)
{
   if(IsBreakoutTradeComment(comment))      return OWNER_BREAKOUT;
   if(IsCounterTrendTradeComment(comment))  return OWNER_REVERSAL;
   if(IsReversalTradeComment(comment))      return OWNER_REVERSAL;
   if(IsTrendTradeComment(comment))        return OWNER_TREND;
   if(IsRangeTradeComment(comment))       return OWNER_RANGE;
   return OWNER_NONE;
}

string OwnerToString(STRATEGY_OWNER owner)
{
   switch(owner)
   {
      case OWNER_TREND:     return "TREND";
      case OWNER_BREAKOUT:  return "BREAKOUT";
      case OWNER_RANGE:     return "RANGE";
      case OWNER_REVERSAL:  return "REVERSAL";
      default:              return "NONE";
   }
}

bool AreOwnersCompatible(const STRATEGY_OWNER openOwner,
                         const STRATEGY_OWNER requestedOwner,
                         const bool sameDirection)
{
   if(openOwner == OWNER_NONE || requestedOwner == OWNER_NONE)
      return false;

   if(openOwner == requestedOwner)
      return true;

   // Allow same-direction TREND <-> BREAKOUT coexistence.
   if(sameDirection)
   {
      if((openOwner == OWNER_TREND    && requestedOwner == OWNER_BREAKOUT) ||
         (openOwner == OWNER_BREAKOUT && requestedOwner == OWNER_TREND))
         return true;
   }

   return false;
}

string DeriveModelFromTradeComment(const string comment)
{
   if(IsCounterTrendTradeComment(comment) || IsReversalTradeComment(comment))
      return "COUNTER_TREND";
   if(IsBreakoutTradeComment(comment))
      return "BREAKOUT";
   if(IsTrendTradeComment(comment))
      return "TREND";
   if(IsRangeTradeComment(comment))
      return "RANGE";
   return "UNKNOWN";
}

STRATEGY_OWNER GetOpenSymbolOwner(ulong magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      STRATEGY_OWNER owner = GetOwnerFromComment(comment);
      if(owner != OWNER_NONE)
         return owner;
   }
   return OWNER_NONE;
}

// STEP 6: Trend runner globals
bool   g_sdTrendRetestsAreRunners       = true;
bool   g_trendRunnerNoBrokerTP          = true;
bool   g_trendRunnerUseVirtualTarget    = true;
double g_trendRunnerTrailStartR         = 1.50;
double g_trendRunnerBEAtR               = 1.20;
bool   g_trendRunnerCloseOnlyOnTrendEnd = true;

// Trend campaign holding and add-on logic helpers
bool IsTrendCampaignTrade(const string comment);
bool ShouldCloseTrendCampaign(const IndicatorState &ind, double atr, bool isBull);

// Strategy-specific management helpers
bool IsCounterTrendTrade(const string comment);
bool IsRangeTrade(const string comment);
bool IsBreakoutTrade(const string comment);
bool IsTrendContinuationTrade(const string comment);
bool ShouldCloseCounterTrend(const IndicatorState &ind, double atr, bool isBull);
bool ShouldCloseRangeTrade(const IndicatorState &ind, double atr, bool isBull);
bool ShouldCloseBreakoutTrade(const IndicatorState &ind, double atr, bool isBull);

// Track last close attempt per ticket to prevent repeated failures on same bar
// but allow different positions to close independently
#define MAX_CLOSE_TRACK 32
struct CloseAttemptEntry { ulong ticket; datetime bar; };
CloseAttemptEntry g_closeAttempts[MAX_CLOSE_TRACK];
int g_closeAttemptCount = 0;

datetime GetLastCloseAttemptBar(ulong ticket)
{
   for(int i = 0; i < g_closeAttemptCount; i++)
      if(g_closeAttempts[i].ticket == ticket)
         return g_closeAttempts[i].bar;
   return 0;
}

void SetCloseAttemptBar(ulong ticket, datetime bar)
{
   for(int i = 0; i < g_closeAttemptCount; i++)
   {
      if(g_closeAttempts[i].ticket == ticket)
      {
         g_closeAttempts[i].bar = bar;
         return;
      }
   }
   if(g_closeAttemptCount < MAX_CLOSE_TRACK)
   {
      g_closeAttempts[g_closeAttemptCount].ticket = ticket;
      g_closeAttempts[g_closeAttemptCount].bar    = bar;
      g_closeAttemptCount++;
   }
   else
   {
      // Overwrite oldest entry
      g_closeAttempts[0].ticket = ticket;
      g_closeAttempts[0].bar   = bar;
   }
}

//+------------------------------------------------------------------+
//| Modify cooldown — prevents repeated modify attempts when market  |
//| is closed. Logs once, then silently blocks until cooldown expires.|
//+------------------------------------------------------------------+
#define MAX_MODIFY_COOLDOWN 16
#define MODIFY_COOLDOWN_SEC 120

struct ModifyCooldownEntry
{
   string   symbol;
   datetime cooldownUntil;
   bool     loggedOnce;
};
ModifyCooldownEntry g_modifyCooldowns[MAX_MODIFY_COOLDOWN];
int g_modifyCooldownCount = 0;

int GetModifyCooldownIndex(const string symbol)
{
   for(int i = 0; i < g_modifyCooldownCount; i++)
      if(g_modifyCooldowns[i].symbol == symbol) return i;
   if(g_modifyCooldownCount < MAX_MODIFY_COOLDOWN)
   {
      int idx = g_modifyCooldownCount++;
      g_modifyCooldowns[idx].symbol = symbol;
      g_modifyCooldowns[idx].cooldownUntil = 0;
      g_modifyCooldowns[idx].loggedOnce = false;
      return idx;
   }
   return 0;
}

bool IsModifyAllowed(const string symbol)
{
   if((bool)MQLInfoInteger(MQL_TESTER)) return true;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;

   ENUM_SYMBOL_TRADE_MODE tmode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   if(tmode == SYMBOL_TRADE_MODE_DISABLED) return false;

   int idx = GetModifyCooldownIndex(symbol);
   if(TimeCurrent() < g_modifyCooldowns[idx].cooldownUntil)
      return false;

   return true;
}

bool IsMarketClosedRetcode(uint retcode)
{
   return (retcode == TRADE_RETCODE_MARKET_CLOSED ||
           retcode == TRADE_RETCODE_TRADE_DISABLED ||
           retcode == TRADE_RETCODE_SERVER_DISABLES_AT ||
           retcode == TRADE_RETCODE_CLIENT_DISABLES_AT);
}

bool SafeModifyPosition(CTrade &trade, ulong ticket, double newSL, double newTP,
                        double currentSL, double currentTP,
                        double point, string reason)
{
   // 1. Market-open / cooldown guard
   if(!IsModifyAllowed(_Symbol))
      return false;

   // 2. Changed-enough guard — skip if proposed SL/TP within 1 point of current
   if(MathAbs(newSL - currentSL) <= point && MathAbs(newTP - currentTP) <= point)
      return false;

   // 3. Execute modify
   if(trade.PositionModify(ticket, newSL, newTP))
   {
      // Success — clear any cooldown for this symbol
      int idx = GetModifyCooldownIndex(_Symbol);
      g_modifyCooldowns[idx].cooldownUntil = 0;
      g_modifyCooldowns[idx].loggedOnce = false;
      Print(reason);
      return true;
   }

   // 4. Handle failure
   uint retcode = trade.ResultRetcode();

   if(IsMarketClosedRetcode(retcode))
   {
      int idx = GetModifyCooldownIndex(_Symbol);
      g_modifyCooldowns[idx].cooldownUntil = TimeCurrent() + MODIFY_COOLDOWN_SEC;
      if(!g_modifyCooldowns[idx].loggedOnce)
      {
         Print("MODIFY SKIPPED: market closed for ", _Symbol,
               " (retcode=", retcode, ") — retry in ", MODIFY_COOLDOWN_SEC, "s");
         g_modifyCooldowns[idx].loggedOnce = true;
      }
      return false;
   }

   if(retcode != TRADE_RETCODE_NO_CHANGES)
      Print("MODIFY FAILED: ticket=", ticket, " retcode=", retcode);

   return false;
}

//+------------------------------------------------------------------+
//| Count open positions for current symbol by magic                 |
//+------------------------------------------------------------------+
int CountPositionsForSymbol(ulong magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count ALL open positions by magic (cross-symbol)                 |
//+------------------------------------------------------------------+
int CountAllPositionsByMagic(ulong magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if any position exists for symbol                          |
//+------------------------------------------------------------------+
bool HasOpenPositionForSymbol(ulong magic)
{
   return (CountPositionsForSymbol(magic) > 0);
}

//+------------------------------------------------------------------+
//| Check if BUY position exists for symbol                          |
//+------------------------------------------------------------------+
bool HasOpenBuyPosition(ulong magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if SELL position exists for symbol                         |
//+------------------------------------------------------------------+
bool HasOpenSellPosition(ulong magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Count BUY positions for symbol by magic                          |
//+------------------------------------------------------------------+
int CountBuyPositionsByMagic(ulong magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count SELL positions for symbol by magic                         |
//+------------------------------------------------------------------+
int CountSellPositionsByMagic(ulong magic)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Get position ticket for symbol                                   |
//+------------------------------------------------------------------+
ulong GetPositionTicketForSymbol(ulong magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      return ticket;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Close ALL positions for current symbol by magic (force-close)    |
//+------------------------------------------------------------------+
void CloseAllPositionsForSymbol(CTrade &trade, ulong magic)
{
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string typeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double lots = PositionGetDouble(POSITION_VOLUME);

      if(trade.PositionClose(ticket))
      {
         Print("FORCE CLOSED: ticket=", ticket, " ", typeStr,
               " lots=", DoubleToString(lots, 4));
         closed++;
      }
      else
      {
         Print("FORCE CLOSE FAILED: ticket=", ticket, " ", typeStr,
               " error=", GetLastError());
      }
   }
   if(closed > 0)
      Print("FORCE CLOSE: Closed ", closed, " position(s) for ", _Symbol);
}

//+------------------------------------------------------------------+
//| Safe close position with result check and logging                |
//+------------------------------------------------------------------+
bool SafeClosePosition(CTrade &trade, ulong ticket, string reason)
{
   // Check if we already tried to close THIS ticket on this bar
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(GetLastCloseAttemptBar(ticket) == currentBar)
   {
      // Already attempted close for this specific ticket on this bar
      return false;
   }

   // Select position
   if(!PositionSelectByTicket(ticket))
   {
      Print("CLOSE ERROR: Cannot select position ticket=", ticket);
      return false;
   }

   double lots = PositionGetDouble(POSITION_VOLUME);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   string typeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";

   Print("CLOSE ATTEMPT: ticket=", ticket, " type=", typeStr,
         " lots=", DoubleToString(lots, 4), " reason=", reason);

   SetCloseAttemptBar(ticket, currentBar);

   // Attempt close with retry
   int maxRetries = 3;
   for(int attempt = 1; attempt <= maxRetries; attempt++)
   {
      bool result = trade.PositionClose(ticket);
      uint retcode = trade.ResultRetcode();

      if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         Print("CLOSE SUCCESS: ticket=", ticket, " reason=", reason);
         return true;
      }

      Print("CLOSE ATTEMPT ", attempt, " FAILED: ticket=", ticket,
            " retcode=", retcode);

      if(attempt < maxRetries)
         Sleep(300);
   }

   Print("CLOSE FAILED: ticket=", ticket, " all retries exhausted");
   return false;
}

//+------------------------------------------------------------------+
//| Multi-indicator exit confirmation for trend positions            |
//| Uses only available IndicatorState fields: ADX, EMA50, price    |
//+------------------------------------------------------------------+
bool ShouldExitOnMultiIndicatorSignal(const IndicatorState &ind, ENUM_POSITION_TYPE type)
{
   // 1. ADX momentum loss: trending strength fading
   double adx     = GetADX(ind, 1);
   double adxPrev = GetADX(ind, 2);
   bool adxWeakening = (adx < 20.0) ||
                       (adxPrev > 25.0 && adx < adxPrev * 0.80);

   // 2. EMA50 cross: price closed on wrong side of EMA50
   double ema50   = GetEMA50(ind, 1);
   bool ema50Cross = false;
   if(type == POSITION_TYPE_BUY  && ind.closeArr[1] < ema50) ema50Cross = true;
   if(type == POSITION_TYPE_SELL && ind.closeArr[1] > ema50) ema50Cross = true;

   // 3. Price momentum: two consecutive closes moving against position
   bool priceMomentumLost = false;
   if(type == POSITION_TYPE_BUY  && ind.closeArr[1] < ind.closeArr[2] &&
                                     ind.closeArr[2] < ind.closeArr[3])
      priceMomentumLost = true;
   if(type == POSITION_TYPE_SELL && ind.closeArr[1] > ind.closeArr[2] &&
                                     ind.closeArr[2] > ind.closeArr[3])
      priceMomentumLost = true;

   // Require at least 2 of 3 confirmations
   int confirmations = 0;
   if(adxWeakening)      confirmations++;
   if(ema50Cross)        confirmations++;
   if(priceMomentumLost) confirmations++;

   if(confirmations >= 2)
   {
      Print("[MULTI_INDICATOR_EXIT] confirmations=", confirmations,
            " ADX=", DoubleToString(adx, 1),
            " EMA50cross=", ema50Cross,
            " priceMomentumLost=", priceMomentumLost);
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| CloseOnOppositeSignal — HOLD/RANGE EXIT ONLY                     |
//| HOLD/RANGE: rejection candle exit                                |
//| TREND: managed by ManageStructureTrail only (not here)           |
//+------------------------------------------------------------------+
void CloseOnOppositeSignal(CTrade &trade, const IndicatorState &ind, ulong magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string comment = PositionGetString(POSITION_COMMENT);

      bool isHoldTrade  = (StringFind(comment, "HOLD")  >= 0);
      bool isRangeTrade = IsRangeTradeComment(comment);

      // TREND trades are NOT managed here — ManageStructureTrail handles them
      if(isHoldTrade)
      {
         if(posType == POSITION_TYPE_BUY && IsBearishRejection(ind))
         {
            Print("[HOLD_EXIT] Bearish rejection - closing HOLD BUY");
            SafeClosePosition(trade, ticket, "Bearish rejection (HOLD exit)");
            ResetExitFilter();
         }
         else if(posType == POSITION_TYPE_SELL && IsBullishRejection(ind))
         {
            Print("[HOLD_EXIT] Bullish rejection - closing HOLD SELL");
            SafeClosePosition(trade, ticket, "Bullish rejection (HOLD exit)");
            ResetExitFilter();
         }
      }
      else if(isRangeTrade)
      {
         if(posType == POSITION_TYPE_BUY && IsBearishRejection(ind))
         {
            Print("[RANGE_EXIT] Bearish rejection - closing RANGE BUY");
            SafeClosePosition(trade, ticket, "Bearish rejection (RANGE exit)");
            ResetExitFilter();
         }
         else if(posType == POSITION_TYPE_SELL && IsBullishRejection(ind))
         {
            Print("[RANGE_EXIT] Bullish rejection - closing RANGE SELL");
            SafeClosePosition(trade, ticket, "Bullish rejection (RANGE exit)");
            ResetExitFilter();
         }
      }
      // TREND branch removed — trend trades exit via ManageStructureTrail only
   }
}

//+------------------------------------------------------------------+
//| Close on single close beyond EMA50 — SECONDARY SAFETY EXIT       |
//| TREND-tagged trades only.                                         |
//+------------------------------------------------------------------+
void CloseOnCloseBeyondEMA50(CTrade &trade, const IndicatorState &ind, ulong magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(!IsTrendTradeComment(comment))
         continue;

      // STEP 11: Do not close trend runners from ordinary opposite-cross rules
      bool isTrendRunner = IsTrendCampaignTrade(comment);

      if(isTrendRunner && g_trendRunnerCloseOnlyOnTrendEnd)
      {
         // Trend runners are closed by ManageStructureTrail trend-end logic,
         // not by ordinary EMA/opposite-cross exits.
         continue;
      }

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Check multi-indicator exit first
      if(ShouldExitOnMultiIndicatorSignal(ind, posType))
      {
         SafeClosePosition(trade, ticket, "Multi-indicator exit (ADX/RSI/MACD)");
         ResetExitFilter();
         continue;
      }

      if(ShouldExitOnCloseBeyondEMA50(ind, posType))
      {
         string reason = (posType == POSITION_TYPE_BUY)
                         ? "Close below EMA50 safety exit (BUY)"
                         : "Close above EMA50 safety exit (SELL)";
         SafeClosePosition(trade, ticket, reason);
         ResetExitFilter();
      }
   }
}

//+------------------------------------------------------------------+
//| EMA50 Profit Protection — tighten SL to EMA50 + ATR buffer      |
//| TREND-tagged trades only.                                         |
//+------------------------------------------------------------------+
void CloseOnEMA50ProfitProtection(CTrade &trade, const IndicatorState &ind,
                                  const SymbolProfile &prof, ulong magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(!IsTrendTradeComment(comment))
         continue;

      // STEP 11: Do not close trend runners from ordinary opposite-cross rules
      bool isTrendRunner = IsTrendCampaignTrade(comment);

      if(isTrendRunner && g_trendRunnerCloseOnlyOnTrendEnd)
      {
         // Trend runners are closed by ManageStructureTrail trend-end logic,
         // not by ordinary EMA/opposite-cross exits.
         continue;
      }

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL  = PositionGetDouble(POSITION_SL);
      double currentTP  = PositionGetDouble(POSITION_TP);

      if(!ShouldExitOnEMA50ProfitProtection(ind, posType, entryPrice))
         continue;

      // Tighten SL to EMA50 ± ATR buffer
      double ema50_1     = GetEMA50(ind, 1);
      double atr         = GetATR(ind, 1);
      double buffer      = atr * 0.25;   // 0.25 ATR breathing room
      double minStopDist = prof.stopsLevelPoints * prof.point;

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0)
         continue;

      if(posType == POSITION_TYPE_BUY)
      {
         double newSL = NormalizeDouble(ema50_1 - buffer, prof.digits);
         if(newSL > currentSL && tick.bid - newSL >= minStopDist)
         {
            SafeModifyPosition(trade, ticket, newSL, currentTP, currentSL, currentTP, prof.point,
               "PROFIT PROTECTION: BUY SL tightened to EMA50=" + DoubleToString(newSL, prof.digits));
         }
      }
      else
      {
         double newSL = NormalizeDouble(ema50_1 + buffer, prof.digits);
         if((newSL < currentSL || currentSL == 0) && newSL - tick.ask >= minStopDist)
         {
            SafeModifyPosition(trade, ticket, newSL, currentTP, currentSL, currentTP, prof.point,
               "PROFIT PROTECTION: SELL SL tightened to EMA50=" + DoubleToString(newSL, prof.digits));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all positions on risk event                                |
//+------------------------------------------------------------------+
void CloseAllOnRiskEvent(CTrade &trade, ulong magic, string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      SafeClosePosition(trade, ticket, reason);
   }
}

//+------------------------------------------------------------------+
//| Multi-condition trend exit                                       |
//| Closes TREND_BUY/TREND_SELL positions when 2+ of 4 exit signals |
//| fire (ADX<18, slope flat/reversed, 2 closes beyond EMA50, H4 lost)|
//+------------------------------------------------------------------+
void CloseTrendTradeOnMultiCondition(CTrade &trade, const IndicatorState &ind, ulong magic)
{
   double h1Adx    = GetADX(ind, 1);
   double h1Ema50  = GetEMA50(ind, 1);
   double h1Ema50p = GetEMA50(ind, 2);
   double h1Slope  = GetEMA50Slope(ind, 3);
   double atr      = GetATR(ind, 1);
   double flatThresh = (atr > 0) ? atr * 0.05 : 0.0;

   // H4 EMA alignment (lightweight one-shot handle)
   bool h4BullAlign = true, h4BearAlign = true;
   {
      int hE50  = iMA(_Symbol, PERIOD_H4, 50,  0, MODE_EMA, PRICE_CLOSE);
      int hE200 = iMA(_Symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
      double e50[], e200[];
      ArraySetAsSeries(e50,  true);
      ArraySetAsSeries(e200, true);
      if(hE50 != INVALID_HANDLE && hE200 != INVALID_HANDLE &&
         CopyBuffer(hE50,  0, 0, 3, e50)  >= 3 &&
         CopyBuffer(hE200, 0, 0, 3, e200) >= 3)
      {
         h4BullAlign = (e50[1] > e200[1]);
         h4BearAlign = (e50[1] < e200[1]);
      }
      if(hE50  != INVALID_HANDLE) IndicatorRelease(hE50);
      if(hE200 != INVALID_HANDLE) IndicatorRelease(hE200);
   }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      bool isTrendTrade = (StringFind(comment, "TREND") >= 0);
      if(!isTrendTrade) continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int    exitCount   = 0;
      string exitReasons = "";

      if(posType == POSITION_TYPE_BUY)
      {
         if(h1Adx < 18.0)
            { exitCount++; exitReasons += "ADX_WEAK("+DoubleToString(h1Adx,1)+") "; }
         if(h1Slope <= flatThresh)
            { exitCount++; exitReasons += "SLOPE_FLAT_NEG "; }
         if(ind.closeArr[1] < h1Ema50 && ind.closeArr[2] < h1Ema50p)
            { exitCount++; exitReasons += "2CLOSES_BELOW_EMA50 "; }
         if(!h4BullAlign)
            { exitCount++; exitReasons += "H4_BULL_LOST "; }

         if(exitCount >= 2)
         {
            Print("[TREND_EXIT_BUY] ticket=", ticket, " conditions=", exitCount,
                  " reasons=", exitReasons);
            SafeClosePosition(trade, ticket, "TREND_EXIT: " + exitReasons);
            ResetExitFilter();
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         if(h1Adx < 18.0)
            { exitCount++; exitReasons += "ADX_WEAK("+DoubleToString(h1Adx,1)+") "; }
         if(h1Slope >= -flatThresh)
            { exitCount++; exitReasons += "SLOPE_FLAT_POS "; }
         if(ind.closeArr[1] > h1Ema50 && ind.closeArr[2] > h1Ema50p)
            { exitCount++; exitReasons += "2CLOSES_ABOVE_EMA50 "; }
         if(!h4BearAlign)
            { exitCount++; exitReasons += "H4_BEAR_LOST "; }

         if(exitCount >= 2)
         {
            Print("[TREND_EXIT_SELL] ticket=", ticket, " conditions=", exitCount,
                  " reasons=", exitReasons);
            SafeClosePosition(trade, ticket, "TREND_EXIT: " + exitReasons);
            ResetExitFilter();
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage open position (exits on closed candle)                    |
//| RANGE/HOLD-only: rejection candle exits                          |
//| TREND trades are managed by ManageStructureTrail only            |
//+------------------------------------------------------------------+
void ManageOpenPosition(CTrade &trade, const IndicatorState &ind,
                        const MarketState &ms, const SymbolProfile &prof,
                        ulong magic, bool closeOnOpposite, bool exitOnCloseBeyond,
                        bool useEMA50ProfitProtection)
{
   // Trend trades are managed only by ManageStructureTrail().
   // Closed-candle exit manager is reserved for HOLD/RANGE-style positions.
   if(closeOnOpposite)
      CloseOnOppositeSignal(trade, ind, magic);
   
   // NOTE: The following are intentionally disabled for trend runners:
   // - CloseTrendTradeOnMultiCondition() — removed
   // - CloseOnCloseBeyondEMA50() — removed
   // - CloseOnEMA50ProfitProtection() — removed
   // Trend positions exit via ManageStructureTrail (swing trail, EMA50 trail, breakeven)
}

//+------------------------------------------------------------------+
//| ATR Chandelier-style trailing stop with R-based breakeven        |
//|                                                                   |
//| 1. Open with ATR initial SL                                      |
//| 2. Breakeven at breakevenAtR * R                                 |
//| 3. Start ATR trailing at trailStartAtR * R                       |
//| 4. Trail: HighestHigh(lookback) - ATR*mult (BUY)                |
//|           LowestLow(lookback)  + ATR*mult (SELL)                 |
//+------------------------------------------------------------------+
void ManageTrailingStop(CTrade &trade, const SymbolProfile &prof,
                        const IndicatorState &ind, ulong magic,
                        bool useATRTrail, double atrTrailMult,
                        int atrTrailLookback, bool useBreakeven,
                        double breakevenAtR, double trailStartAtR,
                        double fixedTrailPts)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0)
      return;

   double minStopDist = prof.stopsLevelPoints * prof.point;
   double freezeDist  = prof.freezeLevelPoints * prof.point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double riskR = GetInitialRiskR(openPrice, currentSL);
      if(riskR <= 0) continue;

      if(posType == POSITION_TYPE_BUY)
      {
         double profit = tick.bid - openPrice;

         // === BREAKEVEN: at breakevenAtR * R ===
         if(useBreakeven && profit >= riskR * breakevenAtR && currentSL < openPrice)
         {
            double beSL = NormalizeDouble(openPrice + prof.point, prof.digits);
            if(beSL > currentSL && tick.bid - beSL >= minStopDist)
            {
               SafeModifyPosition(trade, ticket, beSL, currentTP, currentSL, currentTP, prof.point,
                  "BREAKEVEN: ticket=" + IntegerToString(ticket) + " SL moved to " + DoubleToString(beSL, prof.digits) +
                  " at " + DoubleToString(breakevenAtR, 1) + "R");
            }
         }

         // === ATR CHANDELIER TRAILING: at trailStartAtR * R ===
         if(useATRTrail && profit >= riskR * trailStartAtR)
         {
            double atrVal = GetATRTrail(ind, 1);
            if(atrVal > 0)
            {
               double hh = GetHighestHigh(ind, atrTrailLookback, 1);
               double newSL = NormalizeDouble(hh - atrVal * atrTrailMult, prof.digits);

               // Only move SL up, never down
               if(newSL > currentSL && tick.bid - newSL >= minStopDist)
               {
                  SafeModifyPosition(trade, ticket, newSL, currentTP, currentSL, currentTP, prof.point,
                     "ATR TRAIL BUY: ticket=" + IntegerToString(ticket) + " newSL=" + DoubleToString(newSL, prof.digits) +
                     " HH=" + DoubleToString(hh, prof.digits) + " ATR=" + DoubleToString(atrVal, prof.digits));
               }
            }
         }
         // Fixed fallback only if ATR trailing is disabled
         else if(!useATRTrail && fixedTrailPts > 0 && profit >= riskR * trailStartAtR)
         {
            double fixedSL = NormalizeDouble(tick.bid - fixedTrailPts * prof.point, prof.digits);
            if(fixedSL > currentSL && tick.bid - fixedSL >= minStopDist)
            {
               SafeModifyPosition(trade, ticket, fixedSL, currentTP, currentSL, currentTP, prof.point,
                  "FIXED TRAIL BUY: ticket=" + IntegerToString(ticket) + " newSL=" + DoubleToString(fixedSL, prof.digits));
            }
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         double profit = openPrice - tick.ask;

         // === BREAKEVEN: at breakevenAtR * R ===
         if(useBreakeven && profit >= riskR * breakevenAtR
            && (currentSL > openPrice || currentSL == 0))
         {
            double beSL = NormalizeDouble(openPrice - prof.point, prof.digits);
            if((beSL < currentSL || currentSL == 0) && beSL - tick.ask >= minStopDist)
            {
               SafeModifyPosition(trade, ticket, beSL, currentTP, currentSL, currentTP, prof.point,
                  "BREAKEVEN: ticket=" + IntegerToString(ticket) + " SL moved to " + DoubleToString(beSL, prof.digits) +
                  " at " + DoubleToString(breakevenAtR, 1) + "R");
            }
         }

         // === ATR CHANDELIER TRAILING: at trailStartAtR * R ===
         if(useATRTrail && profit >= riskR * trailStartAtR)
         {
            double atrVal = GetATRTrail(ind, 1);
            if(atrVal > 0)
            {
               double ll = GetLowestLow(ind, atrTrailLookback, 1);
               double newSL = NormalizeDouble(ll + atrVal * atrTrailMult, prof.digits);

               // Only move SL down (tighter), never up (wider)
               if(newSL > 0 && (newSL < currentSL || currentSL == 0) && newSL - tick.ask >= minStopDist)
               {
                  SafeModifyPosition(trade, ticket, newSL, currentTP, currentSL, currentTP, prof.point,
                     "ATR TRAIL SELL: ticket=" + IntegerToString(ticket) + " newSL=" + DoubleToString(newSL, prof.digits) +
                     " LL=" + DoubleToString(ll, prof.digits) + " ATR=" + DoubleToString(atrVal, prof.digits));
               }
            }
         }
         // Fixed fallback only if ATR trailing is disabled
         else if(!useATRTrail && fixedTrailPts > 0 && profit >= riskR * trailStartAtR)
         {
            double fixedSL = NormalizeDouble(tick.ask + fixedTrailPts * prof.point, prof.digits);
            if((fixedSL < currentSL || currentSL == 0) && fixedSL - tick.ask >= minStopDist)
            {
               SafeModifyPosition(trade, ticket, fixedSL, currentTP, currentSL, currentTP, prof.point,
                  "FIXED TRAIL SELL: ticket=" + IntegerToString(ticket) + " newSL=" + DoubleToString(fixedSL, prof.digits));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dynamic Zone Anchor Trail — trend campaign stop management       |
//| Uses dynamic zone band with wick-aware protection                 |
//| Called for TREND_BUY/TREND_SELL positions only                   |
//| Logs once per bar to reduce spam                                  |
//+------------------------------------------------------------------+
static datetime s_lastDynamicZoneTrailBar = 0;

void ManageDynamicZoneTrail(CTrade &trade, const SymbolProfile &prof,
                            const IndicatorState &ind, ulong magic,
                            double zoneBandATR, double slBufferATR,
                            int wickLookback, bool useWickExtreme)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0)
      return;

   double atr         = GetATR(ind, 1);
   double minStopDist = prof.stopsLevelPoints * prof.point;
   double minStep     = prof.point * 2;

   if(atr <= 0) return;
   
   // Only log once per bar to reduce spam
   datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
   bool shouldLog = (currentBar != s_lastDynamicZoneTrailBar);
   if(shouldLog) s_lastDynamicZoneTrailBar = currentBar;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      
      // Only apply to TREND positions
      if(!IsTrendTradeComment(comment))
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Don't trail until position has minimum profit
      double dzProfit = (posType == POSITION_TYPE_BUY) ? (tick.bid - openPrice) : (openPrice - tick.ask);
      if(atr > 0.0 && dzProfit < atr * g_trendTrailMinProfitATR)
         continue;

      if(posType == POSITION_TYPE_BUY)
      {
         // Get bull dynamic support zone band
         DynamicZoneBand zone = GetBullDynamicZoneBand(atr, zoneBandATR);
         if(!zone.valid)
         {
            if(shouldLog) Print("[DYNAMIC_ZONE_TRAIL] side=BUY applied=false reason=no_valid_zone");
            continue;
         }

         // Find wick extreme within lookback that interacted with zone
         double wickExtreme = zone.low;
         if(useWickExtreme)
         {
            for(int j = 1; j <= wickLookback && j < ArraySize(ind.lowArr); j++)
            {
               // Check if bar interacted with zone
               if(ind.lowArr[j] <= zone.high && ind.highArr[j] >= zone.low)
               {
                  if(ind.lowArr[j] < wickExtreme)
                     wickExtreme = ind.lowArr[j];
               }
            }
         }

         // Build anchor: use wick extreme if it's below zone low
         double anchorBase = zone.low;
         if(useWickExtreme && wickExtreme < zone.low)
            anchorBase = wickExtreme;

         // Final SL with buffer
         double newSL = NormalizeDouble(anchorBase - atr * slBufferATR, prof.digits);

         if(shouldLog)
            Print("[DYNAMIC_ZONE_TRAIL] side=BUY zoneLow=", DoubleToString(zone.low, prof.digits),
                  " zoneHigh=", DoubleToString(zone.high, prof.digits),
                  " wickExtreme=", DoubleToString(wickExtreme, prof.digits),
                  " newSL=", DoubleToString(newSL, prof.digits),
                  " currentSL=", DoubleToString(currentSL, prof.digits));

         // Only move SL up, never down
         if(newSL > currentSL + minStep && tick.bid - newSL >= minStopDist)
         {
            SafeModifyPosition(trade, ticket, newSL, currentTP, currentSL, currentTP, prof.point,
               "DYNAMIC_ZONE_TRAIL BUY: ticket=" + IntegerToString(ticket) +
               " zoneMid=" + DoubleToString(zone.mid, prof.digits) +
               " newSL=" + DoubleToString(newSL, prof.digits));
            Print("[DYNAMIC_ZONE_TRAIL] applied=true side=BUY reason=sl_moved_up");
         }
         else if(shouldLog)
         {
            Print("[DYNAMIC_ZONE_TRAIL] applied=false side=BUY reason=",
                  (newSL <= currentSL + minStep ? "no_improvement" : "min_stop_dist"));
         }
      }
      else if(posType == POSITION_TYPE_SELL)
      {
         if(currentSL <= 0) continue;

         // Get bear dynamic resistance zone band
         DynamicZoneBand zone = GetBearDynamicZoneBand(atr, zoneBandATR);
         if(!zone.valid)
         {
            if(shouldLog) Print("[DYNAMIC_ZONE_TRAIL] side=SELL applied=false reason=no_valid_zone");
            continue;
         }

         // Find wick extreme within lookback that interacted with zone
         double wickExtreme = zone.high;
         if(useWickExtreme)
         {
            for(int j = 1; j <= wickLookback && j < ArraySize(ind.highArr); j++)
            {
               // Check if bar interacted with zone
               if(ind.highArr[j] >= zone.low && ind.lowArr[j] <= zone.high)
               {
                  if(ind.highArr[j] > wickExtreme)
                     wickExtreme = ind.highArr[j];
               }
            }
         }

         // Build anchor: use wick extreme if it's above zone high
         double anchorBase = zone.high;
         if(useWickExtreme && wickExtreme > zone.high)
            anchorBase = wickExtreme;

         // Final SL with buffer
         double newSL = NormalizeDouble(anchorBase + atr * slBufferATR, prof.digits);

         if(shouldLog)
            Print("[DYNAMIC_ZONE_TRAIL] side=SELL zoneLow=", DoubleToString(zone.low, prof.digits),
                  " zoneHigh=", DoubleToString(zone.high, prof.digits),
                  " wickExtreme=", DoubleToString(wickExtreme, prof.digits),
                  " newSL=", DoubleToString(newSL, prof.digits),
                  " currentSL=", DoubleToString(currentSL, prof.digits));

         // Only move SL down (tighter), never up (wider)
         if(newSL > 0 && newSL < currentSL - minStep && newSL - tick.ask >= minStopDist)
         {
            SafeModifyPosition(trade, ticket, newSL, currentTP, currentSL, currentTP, prof.point,
               "DYNAMIC_ZONE_TRAIL SELL: ticket=" + IntegerToString(ticket) +
               " zoneMid=" + DoubleToString(zone.mid, prof.digits) +
               " newSL=" + DoubleToString(newSL, prof.digits));
            Print("[DYNAMIC_ZONE_TRAIL] applied=true side=SELL reason=sl_moved_down");
         }
         else if(shouldLog)
         {
            Print("[DYNAMIC_ZONE_TRAIL] applied=false side=SELL reason=",
                  (newSL >= currentSL - minStep ? "no_improvement" : "min_stop_dist"));
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Close all trend campaign positions for a direction               |
//+------------------------------------------------------------------+
void CloseTrendCampaignPositions(CTrade &trade, ulong magic, int direction, string reason)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(!IsTrendTradeComment(comment))
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      // Check direction match
      if(direction == +1 && posType == POSITION_TYPE_BUY)
      {
         // STEP 9: Add trend runner exit log before closing
         Print("[TREND_RUNNER_EXIT] side=BUY reason=confirmed_trend_end details=", reason);
         Print("[TREND_END_CLOSE] side=BUY reason=", reason);
         SafeClosePosition(trade, ticket, reason);
      }
      else if(direction == -1 && posType == POSITION_TYPE_SELL)
      {
         // STEP 9: Add trend runner exit log before closing
         Print("[TREND_RUNNER_EXIT] side=SELL reason=confirmed_trend_end details=", reason);
         Print("[TREND_END_CLOSE] side=SELL reason=", reason);
         SafeClosePosition(trade, ticket, reason);
      }
   }
}

//+------------------------------------------------------------------+
//| Count open trend campaign positions for a direction              |
//+------------------------------------------------------------------+
int CountTrendCampaignPositions(ulong magic, int direction)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(!IsTrendTradeComment(comment))
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(direction == +1 && posType == POSITION_TYPE_BUY)
         count++;
      else if(direction == -1 && posType == POSITION_TYPE_SELL)
         count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Check if any trend campaign position is in profit                 |
//+------------------------------------------------------------------+
bool HasTrendCampaignPositionInProfit(ulong magic, int direction)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0)
      return false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(!IsTrendTradeComment(comment))
         continue;

      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);

      if(direction == +1 && posType == POSITION_TYPE_BUY)
      {
         if(tick.bid > openPrice)
            return true;
      }
      else if(direction == -1 && posType == POSITION_TYPE_SELL)
      {
         if(tick.ask < openPrice)
            return true;
      }
   }
   return false;
}

int TrendCommentDirection(const string comment)
{
   if(StringFind(comment, "BUY") >= 0)  return +1;
   if(StringFind(comment, "SELL") >= 0) return -1;
   return 0;
}

double GetLastTrendCampaignEntryPrice(ulong magic, int direction)
{
   double newestPrice = 0.0;
   datetime newestTime = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(!IsTrendPositionComment(comment)) continue;
      if(TrendCommentDirection(comment) != direction) continue;

      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(t >= newestTime)
      {
         newestTime  = t;
         newestPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }
   return newestPrice;
}

bool AnyTrendCampaignPositionInProfit(ulong magic, int direction)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return false;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      if(!IsTrendPositionComment(comment)) continue;
      if(TrendCommentDirection(comment) != direction) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(direction == +1 && tick.bid > openPrice) return true;
      if(direction == -1 && tick.ask < openPrice) return true;
   }
   return false;
}

void RefreshTrendCampaignState(ulong magic)
{
   int buyCount  = CountTrendCampaignPositions(magic, +1);
   int sellCount = CountTrendCampaignPositions(magic, -1);

   if(buyCount <= 0 && sellCount <= 0)
   {
      g_campaign.active         = false;
      g_campaign.direction      = 0;
      g_campaign.positionCount  = 0;
      g_campaign.lastAddBar     = 0;
      g_campaign.lastAddPrice   = 0.0;
      g_campaign.lastZoneAnchor = 0.0;
      g_campaign.lastAddTime    = 0;
      return;
   }

   g_campaign.active         = true;
   g_campaign.direction      = (buyCount >= sellCount ? +1 : -1);
   g_campaign.positionCount  = (buyCount >= sellCount ? buyCount : sellCount);
}

bool TrendAddAllowed(const IndicatorState &ind,
                     const SymbolProfile &prof,
                     ulong magic,
                     bool isBuy,
                     double entryPrice,
                     double zoneAnchor,
                     string &reason)
{
   reason = "";

   if(!g_enableTrendCampaign)
      { reason = "trend_campaign_disabled"; return false; }

   if(!g_allowTrendAddsAtDynamicZones)
      { reason = "trend_adds_disabled"; return false; }

   int direction = isBuy ? +1 : -1;
   int countSame = CountTrendCampaignPositions(magic, direction);

   if(countSame <= 0)
      { reason = "leader_entry"; return true; }

   // --- ALLOW ADDS IN BIAS STATES TOO ---
   // Check if current state supports same-direction adds
   bool stateAllowsAdd = false;
   if(isBuy)
   {
      stateAllowsAdd = (g_structure.state == STRUCTURE_BULL_TREND ||
                        g_structure.state == STRUCTURE_BIAS_BULL);
   }
   else
   {
      stateAllowsAdd = (g_structure.state == STRUCTURE_BEAR_TREND ||
                        g_structure.state == STRUCTURE_BIAS_BEAR);
   }

   if(!stateAllowsAdd)
   {
      reason = "structure_not_supporting_same_direction";
      Print("[TREND_ADD_GATE] side=", (isBuy ? "BUY" : "SELL"),
            " state=", StructureStateToString(g_structure.state),
            " allowed=false reason=", reason);
      return false;
   }

   Print("[TREND_ADD_GATE] side=", (isBuy ? "BUY" : "SELL"),
         " state=", StructureStateToString(g_structure.state),
         " allowed=true reason=state_supports_direction");

   if(countSame >= g_maxTrendCampaignPositions)
      { reason = "max_campaign_positions"; return false; }

   datetime currentBar = iTime(_Symbol, g_indicatorTF, 0);
   if(g_campaign.lastAddTime > 0)
   {
      int barsSince = iBarShift(_Symbol, g_indicatorTF, g_campaign.lastAddTime, false);
      if(barsSince >= 0 && barsSince < g_minBarsBetweenTrendAdds)
      {
         reason = "min_bars_between_adds";
         return false;
      }
   }

   double atr = GetATR(ind, 1);
   if(atr > 0.0 && g_campaign.lastAddPrice > 0.0)
   {
      if(MathAbs(entryPrice - g_campaign.lastAddPrice) < atr * g_minATRDistanceBetweenTrendAdds)
      {
         reason = "too_close_to_last_add";
         return false;
      }
   }

   if(g_requireExistingTrendPositionProfit && !AnyTrendCampaignPositionInProfit(magic, direction))
   {
      reason = "no_existing_position_in_profit";
      return false;
   }

   if(g_oneAddPerFreshDynamicZone && g_campaign.lastZoneAnchor > 0.0 && atr > 0.0)
   {
      if(MathAbs(zoneAnchor - g_campaign.lastZoneAnchor) < atr * 0.20)
      {
         reason = "same_dynamic_zone_not_fresh";
         return false;
      }
   }

   reason = "ok";
   return true;
}

void RegisterTrendCampaignFill(bool isBuy, double entryPrice, double zoneAnchor)
{
   g_campaign.active         = true;
   g_campaign.direction      = isBuy ? +1 : -1;
   g_campaign.positionCount++;
   g_campaign.lastAddBar     = (int)iBarShift(_Symbol, g_indicatorTF, iTime(_Symbol, g_indicatorTF, 0), false);
   g_campaign.lastAddTime    = iTime(_Symbol, g_indicatorTF, 0);
   g_campaign.lastAddPrice   = entryPrice;
   g_campaign.lastZoneAnchor = zoneAnchor;
}

bool PM_IsActiveHorizontalResistanceZone(const ZoneInfo &z)
{
   if(!z.valid || !z.active || z.historical) return false;

   bool majorRes      = (z.type == ZONE_RESISTANCE_MAJOR);
   bool structuralRes = (z.structuralAnchor && (z.structuralTag == "HH" || z.structuralTag == "LH"));
   bool execRes       = (z.isPrimary || z.isBackup || z.confirmedRetest || z.continuationEligible);

   return (majorRes || structuralRes || execRes) && IsResistanceRole(z);
}

bool PM_IsActiveHorizontalSupportZone(const ZoneInfo &z)
{
   if(!z.valid || !z.active || z.historical) return false;

   bool majorSup      = (z.type == ZONE_SUPPORT_MAJOR);
   bool structuralSup = (z.structuralAnchor && (z.structuralTag == "LL" || z.structuralTag == "HL"));
   bool execSup       = (z.isPrimary || z.isBackup || z.confirmedRetest || z.continuationEligible);

   return (majorSup || structuralSup || execSup) && IsSupportRole(z);
}

bool PM_IsBearishRejectionFromResistance(const IndicatorState &ind, int shift, double zoneLow, double zoneHigh)
{
   if(shift < 1 || shift >= ArraySize(ind.highArr)) return false;

   double open_  = ind.openArr[shift];
   double close_ = ind.closeArr[shift];
   double high_  = ind.highArr[shift];
   double low_   = ind.lowArr[shift];
   double range_ = high_ - low_;
   if(range_ <= 0.0) return false;

   double upperWick = high_ - MathMax(open_, close_);
   double zoneMid   = (zoneLow + zoneHigh) * 0.5;

   bool touched  = (high_ >= zoneLow && low_ <= zoneHigh);
   bool rejected = (upperWick >= range_ * 0.35 && close_ <= zoneMid);

   return (touched && rejected);
}

bool PM_IsBullishRejectionFromSupport(const IndicatorState &ind, int shift, double zoneLow, double zoneHigh)
{
   if(shift < 1 || shift >= ArraySize(ind.lowArr)) return false;

   double open_  = ind.openArr[shift];
   double close_ = ind.closeArr[shift];
   double high_  = ind.highArr[shift];
   double low_   = ind.lowArr[shift];
   double range_ = high_ - low_;
   if(range_ <= 0.0) return false;

   double lowerWick = MathMin(open_, close_) - low_;
   double zoneMid   = (zoneLow + zoneHigh) * 0.5;

   bool touched  = (low_ <= zoneHigh && high_ >= zoneLow);
   bool rejected = (lowerWick >= range_ * 0.35 && close_ >= zoneMid);

   return (touched && rejected);
}

int PM_CountBullHHRejectionsAtSameResistanceZone(const IndicatorState &ind,
                                                 double atr,
                                                 int &matchedZoneId,
                                                 double &matchedZoneMid)
{
   matchedZoneId  = -1;
   matchedZoneMid = 0.0;
   if(atr <= 0.0) return 0;

   int bestCount = 0;

   for(int zIdx = 0; zIdx < g_zoneReg.count; zIdx++)
   {
      ZoneInfo z = g_zoneReg.zones[zIdx];
      if(!PM_IsActiveHorizontalResistanceZone(z)) continue;

      int count = 0;
      for(int s = 0; s < g_structure.swingHighCount && s < g_trendExhaustionSwingLookback; s++)
      {
         SwingPoint sp = g_structure.swingHighs[s];
         if(!sp.valid || !sp.isHigherHigh) continue;

         int shift = sp.barIndex;
         if(shift < 1 || shift >= ArraySize(ind.highArr)) continue;

         bool nearZone =
            (ind.highArr[shift] >= z.lowerBound - atr * g_trendEndZoneTouchTolATR &&
             ind.highArr[shift] <= z.upperBound + atr * g_trendEndZoneTouchTolATR);

         if(!nearZone) continue;

         if(PM_IsBearishRejectionFromResistance(ind, shift, z.lowerBound, z.upperBound))
            count++;
      }

      if(count > bestCount)
      {
         bestCount     = count;
         matchedZoneId = z.id;
         matchedZoneMid= z.midPoint;
      }
   }

   return bestCount;
}

int PM_CountBearLLRejectionsAtSameSupportZone(const IndicatorState &ind,
                                              double atr,
                                              int &matchedZoneId,
                                              double &matchedZoneMid)
{
   matchedZoneId  = -1;
   matchedZoneMid = 0.0;
   if(atr <= 0.0) return 0;

   int bestCount = 0;

   for(int zIdx = 0; zIdx < g_zoneReg.count; zIdx++)
   {
      ZoneInfo z = g_zoneReg.zones[zIdx];
      if(!PM_IsActiveHorizontalSupportZone(z)) continue;

      int count = 0;
      for(int s = 0; s < g_structure.swingLowCount && s < g_trendExhaustionSwingLookback; s++)
      {
         SwingPoint sp = g_structure.swingLows[s];
         if(!sp.valid || !sp.isLowerLow) continue;

         int shift = sp.barIndex;
         if(shift < 1 || shift >= ArraySize(ind.lowArr)) continue;

         bool nearZone =
            (ind.lowArr[shift] <= z.upperBound + atr * g_trendEndZoneTouchTolATR &&
             ind.lowArr[shift] >= z.lowerBound - atr * g_trendEndZoneTouchTolATR);

         if(!nearZone) continue;

         if(PM_IsBullishRejectionFromSupport(ind, shift, z.lowerBound, z.upperBound))
            count++;
      }

      if(count > bestCount)
      {
         bestCount     = count;
         matchedZoneId = z.id;
         matchedZoneMid= z.midPoint;
      }
   }

   return bestCount;
}

double PM_GetBullTrendStrengthScore(const IndicatorState &ind)
{
   double atr = GetATR(ind, 1);
   if(atr <= 0.0) atr = 1.0;

   double score = 0.0;

   if(g_structure.consecutiveHH >= 1) score += 1.0;
   if(g_structure.consecutiveHL >= 1) score += 1.0;

   if(g_structure.channel.valid && g_structure.channel.directionalValid &&
      g_structure.channel.direction == +1 &&
      g_structure.channel.slopesSameSign &&
      !g_structure.channel.weakSlope &&
      g_structure.channel.geometryClean &&
      g_structure.channel.slopeDivergence <= 0.60)
      score += 1.5;

   double adxNow = GetADX(ind, 1);
   if(adxNow >= 25.0) score += 1.0;

   double ema50 = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   double ema50Prev = GetEMA50(ind, 2);
   double ema200Prev = GetEMA200(ind, 2);

   double emaSpreadATR = MathAbs(ema50 - ema200) / atr;
   double slope50ATR   = MathAbs(ema50 - ema50Prev) / atr;
   double slope200ATR  = MathAbs(ema200 - ema200Prev) / atr;

   if(ema50 > ema200 && emaSpreadATR >= 0.85) score += 1.0;
   if((ema50 - ema50Prev) > 0.0 && slope50ATR >= 0.012) score += 0.5;
   if((ema200 - ema200Prev) > 0.0 && slope200ATR >= 0.008) score += 0.5;

   if(GetD1Bias() == D1_BIAS_BULL) score += 0.5;

   return score;
}

double PM_GetBearTrendStrengthScore(const IndicatorState &ind)
{
   double atr = GetATR(ind, 1);
   if(atr <= 0.0) atr = 1.0;

   double score = 0.0;

   if(g_structure.consecutiveLH >= 1) score += 1.0;
   if(g_structure.consecutiveLL >= 1) score += 1.0;

   if(g_structure.channel.valid && g_structure.channel.directionalValid &&
      g_structure.channel.direction == -1 &&
      g_structure.channel.slopesSameSign &&
      !g_structure.channel.weakSlope &&
      g_structure.channel.geometryClean &&
      g_structure.channel.slopeDivergence <= 0.60)
      score += 1.5;

   double adxNow = GetADX(ind, 1);
   if(adxNow >= 25.0) score += 1.0;

   double ema50 = GetEMA50(ind, 1);
   double ema200 = GetEMA200(ind, 1);
   double ema50Prev = GetEMA50(ind, 2);
   double ema200Prev = GetEMA200(ind, 2);

   double emaSpreadATR = MathAbs(ema50 - ema200) / atr;
   double slope50ATR   = MathAbs(ema50 - ema50Prev) / atr;
   double slope200ATR  = MathAbs(ema200 - ema200Prev) / atr;

   if(ema50 < ema200 && emaSpreadATR >= 0.85) score += 1.0;
   if((ema50 - ema50Prev) < 0.0 && slope50ATR >= 0.012) score += 0.5;
   if((ema200 - ema200Prev) < 0.0 && slope200ATR >= 0.008) score += 0.5;

   if(GetD1Bias() == D1_BIAS_BEAR) score += 0.5;

   return score;
}

double PM_GetOpenTrendCampaignProfitR(int direction)
{
   double totalProfit = 0.0;
   double totalRisk   = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(direction > 0 && pt != POSITION_TYPE_BUY)  continue;
      if(direction < 0 && pt != POSITION_TYPE_SELL) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl        = PositionGetDouble(POSITION_SL);
      double profit    = PositionGetDouble(POSITION_PROFIT);

      if(sl <= 0.0) continue;

      double riskPerUnit = MathAbs(openPrice - sl);
      if(riskPerUnit <= 0.0) continue;

      totalProfit += profit;
      totalRisk   += riskPerUnit / _Point;
   }

   if(totalRisk <= 0.0)
      return 0.0;

   return totalProfit / totalRisk;
}

bool IsBullTrendEnded(const IndicatorState &ind, string &reason)
{
   int votes = 0;
   reason = "";

   double atr      = GetATR(ind, 1);
   double adxNow   = GetADX(ind, 1);
   double adxPrev  = GetADX(ind, 2);
   double ema50    = GetEMA50(ind, 1);
   double ema200   = GetEMA200(ind, 1);
   double ema50Prev= GetEMA50(ind, 2);
   double ema200Prev=GetEMA200(ind, 2);

   double emaSpreadATR = (atr > 0.0) ? MathAbs(ema50 - ema200) / atr : 999.0;
   double slope50ATR   = (atr > 0.0) ? MathAbs(ema50 - ema50Prev) / atr : 0.0;
   double slope200ATR  = (atr > 0.0) ? MathAbs(ema200 - ema200Prev) / atr : 0.0;

   double trendStrength = PM_GetBullTrendStrengthScore(ind);

   int rejectZoneId = -1;
   double rejectZoneMid = 0.0;
   int hhRejectCount = PM_CountBullHHRejectionsAtSameResistanceZone(ind, atr, rejectZoneId, rejectZoneMid);

   double trendProfitR = PM_GetOpenTrendCampaignProfitR(+1);

   if(hhRejectCount >= g_trendZoneRejectionMinCount)
   {
      if(trendProfitR >= 1.60 &&
         ((g_structure.dynamicSupport > 0.0 && ind.closeArr[1] < g_structure.dynamicSupport - atr * 0.10) ||
          g_structure.consecutiveHL < 1 ||
          g_structure.state == STRUCTURE_RANGE ||
          g_structure.state == STRUCTURE_BIAS_BEAR ||
          g_structure.state == STRUCTURE_BEAR_TREND))
      {
         votes += 2;
         reason += "hh_multi_reject_same_res_zone ";
         Print("[TREND_EXHAUSTION] side=BUY count=", hhRejectCount,
               " zoneId=", rejectZoneId,
               " zoneMid=", DoubleToString(rejectZoneMid, _Digits),
               " profitR=", DoubleToString(trendProfitR, 2));
      }
   }

   if(g_structure.state == STRUCTURE_BEAR_TREND || g_structure.state == STRUCTURE_BIAS_BEAR)
   {
      votes++;
      reason += "state_flip ";
   }

   bool swingStillBull = (g_structure.consecutiveHH >= 1 && g_structure.consecutiveHL >= 1);

   if(g_structure.channel.valid && g_structure.channel.direction == -1)
   {
      if(!swingStillBull)
      {
         votes++;
         reason += "opposite_channel_no_swing_support ";
      }
      else
      {
         reason += "opposite_channel_but_swings_hold ";
      }
   }
   else if(!g_structure.channel.directionalValid)
   {
      reason += "channel_neutral ";
   }

   double zLow=0.0, zMid=0.0, zHigh=0.0, zHalf=0.0;
   if(GetBullDynamicZoneBand(ind, zLow, zMid, zHigh, zHalf))
   {
      int broken = 0;
      for(int i = 1; i <= g_trendEndConfirmBars && i < ArraySize(ind.closeArr); i++)
         if(ind.closeArr[i] < zLow) broken++;

      if(broken >= g_trendEndConfirmBars)
      {
         votes++;
         reason += "close_below_dynamic_support ";
      }
   }

   bool adxWeakening = (adxNow < g_trendEndADXWeakFloor || (adxPrev - adxNow) >= g_trendEndADXDecayMin);
   bool emaWeakening = (emaSpreadATR <= g_trendEndEmaSpreadWeakATR &&
                        slope50ATR   <= g_trendEndSlopeWeakATR50 &&
                        slope200ATR  <= g_trendEndSlopeWeakATR200);

   if(adxWeakening && emaWeakening && ind.closeArr[1] < ema50)
   {
      votes++;
      reason += "momentum_compression ";
   }

   if(g_structure.dynamicSupport > 0.0 &&
      ind.closeArr[1] < g_structure.dynamicSupport &&
      g_structure.consecutiveHL < 1)
   {
      votes++;
      reason += "anchor_invalidated_no_hl_rebuild ";
   }

   if((g_structure.rangeLikelyTransition && g_structure.state == STRUCTURE_RANGE) ||
       g_structure.state == STRUCTURE_CONSOLIDATION)
   {
      votes++;
      reason += "transition_context ";
   }

   if(GetD1Bias() == D1_BIAS_BEAR)
   {
      votes++;
      reason += "d1_opposes ";
   }

   int requiredVotes = 3;

   if(trendStrength >= 4.5 && hhRejectCount < g_trendZoneRejectionMinCount)
      requiredVotes = 4;

   if(hhRejectCount >= g_trendZoneRejectionMinCount && votes >= 2)
      requiredVotes = 2;

   bool ended = (votes >= requiredVotes);

   Print("[TREND_END_CHECK] side=BUY votes=", votes,
         " required=", requiredVotes,
         " ended=", ended,
         " strength=", DoubleToString(trendStrength, 2),
         " adxNow=", DoubleToString(adxNow, 1),
         " adxPrev=", DoubleToString(adxPrev, 1),
         " emaSpreadATR=", DoubleToString(emaSpreadATR, 2),
         " slope50ATR=", DoubleToString(slope50ATR, 3),
         " slope200ATR=", DoubleToString(slope200ATR, 3),
         " hhRejectCount=", hhRejectCount,
         " reason=", reason);

   return ended;
}

bool IsBearTrendEnded(const IndicatorState &ind, string &reason)
{
   int votes = 0;
   reason = "";

   double atr      = GetATR(ind, 1);
   double adxNow   = GetADX(ind, 1);
   double adxPrev  = GetADX(ind, 2);
   double ema50    = GetEMA50(ind, 1);
   double ema200   = GetEMA200(ind, 1);
   double ema50Prev= GetEMA50(ind, 2);
   double ema200Prev=GetEMA200(ind, 2);

   double emaSpreadATR = (atr > 0.0) ? MathAbs(ema50 - ema200) / atr : 999.0;
   double slope50ATR   = (atr > 0.0) ? MathAbs(ema50 - ema50Prev) / atr : 0.0;
   double slope200ATR  = (atr > 0.0) ? MathAbs(ema200 - ema200Prev) / atr : 0.0;

   double trendStrength = PM_GetBearTrendStrengthScore(ind);

   int rejectZoneId = -1;
   double rejectZoneMid = 0.0;
   int llRejectCount = PM_CountBearLLRejectionsAtSameSupportZone(ind, atr, rejectZoneId, rejectZoneMid);

   double trendProfitR = PM_GetOpenTrendCampaignProfitR(-1);

   if(llRejectCount >= g_trendZoneRejectionMinCount)
   {
      if(trendProfitR >= 1.60 &&
         ((g_structure.dynamicResistance > 0.0 && ind.closeArr[1] > g_structure.dynamicResistance + atr * 0.10) ||
          g_structure.consecutiveLH < 1 ||
          g_structure.state == STRUCTURE_RANGE ||
          g_structure.state == STRUCTURE_BIAS_BULL ||
          g_structure.state == STRUCTURE_BULL_TREND))
      {
         votes += 2;
         reason += "ll_multi_reject_same_sup_zone ";
         Print("[TREND_EXHAUSTION] side=SELL count=", llRejectCount,
               " zoneId=", rejectZoneId,
               " zoneMid=", DoubleToString(rejectZoneMid, _Digits),
               " profitR=", DoubleToString(trendProfitR, 2));
      }
   }

   if(g_structure.state == STRUCTURE_BULL_TREND || g_structure.state == STRUCTURE_BIAS_BULL)
   {
      votes++;
      reason += "state_flip ";
   }

   bool swingStillBear = (g_structure.consecutiveLH >= 1 && g_structure.consecutiveLL >= 1);

   if(g_structure.channel.valid && g_structure.channel.direction == +1)
   {
      if(!swingStillBear)
      {
         votes++;
         reason += "opposite_channel_no_swing_support ";
      }
      else
      {
         reason += "opposite_channel_but_swings_hold ";
      }
   }
   else if(!g_structure.channel.directionalValid)
   {
      reason += "channel_neutral ";
   }

   double zLow=0.0, zMid=0.0, zHigh=0.0, zHalf=0.0;
   if(GetBearDynamicZoneBand(ind, zLow, zMid, zHigh, zHalf))
   {
      int broken = 0;
      for(int i = 1; i <= g_trendEndConfirmBars && i < ArraySize(ind.closeArr); i++)
         if(ind.closeArr[i] > zHigh) broken++;

      if(broken >= g_trendEndConfirmBars)
      {
         votes++;
         reason += "close_above_dynamic_resistance ";
      }
   }

   bool adxWeakening = (adxNow < g_trendEndADXWeakFloor || (adxPrev - adxNow) >= g_trendEndADXDecayMin);
   bool emaWeakening = (emaSpreadATR <= g_trendEndEmaSpreadWeakATR &&
                        slope50ATR   <= g_trendEndSlopeWeakATR50 &&
                        slope200ATR  <= g_trendEndSlopeWeakATR200);

   if(adxWeakening && emaWeakening && ind.closeArr[1] > ema50)
   {
      votes++;
      reason += "momentum_compression ";
   }

   if(g_structure.dynamicResistance > 0.0 &&
      ind.closeArr[1] > g_structure.dynamicResistance &&
      g_structure.consecutiveLH < 1)
   {
      votes++;
      reason += "anchor_invalidated_no_lh_rebuild ";
   }

   if((g_structure.rangeLikelyTransition && g_structure.state == STRUCTURE_RANGE) ||
       g_structure.state == STRUCTURE_CONSOLIDATION)
   {
      votes++;
      reason += "transition_context ";
   }

   if(GetD1Bias() == D1_BIAS_BULL)
   {
      votes++;
      reason += "d1_opposes ";
   }

   int requiredVotes = 3;

   if(trendStrength >= 4.5 && llRejectCount < g_trendZoneRejectionMinCount)
      requiredVotes = 4;

   if(llRejectCount >= g_trendZoneRejectionMinCount && votes >= 2)
      requiredVotes = 2;

   bool ended = (votes >= requiredVotes);

   Print("[TREND_END_CHECK] side=SELL votes=", votes,
         " required=", requiredVotes,
         " ended=", ended,
         " strength=", DoubleToString(trendStrength, 2),
         " adxNow=", DoubleToString(adxNow, 1),
         " adxPrev=", DoubleToString(adxPrev, 1),
         " emaSpreadATR=", DoubleToString(emaSpreadATR, 2),
         " slope50ATR=", DoubleToString(slope50ATR, 3),
         " slope200ATR=", DoubleToString(slope200ATR, 3),
         " llRejectCount=", llRejectCount,
         " reason=", reason);

   return ended;
}


//+------------------------------------------------------------------+
//| Zone-Aware Trailing Helpers                                       |
//+------------------------------------------------------------------+
double GetBestBullTrailAnchor(const IndicatorState &ind, const SymbolProfile &prof)
{
   double hl = GetLatestHigherLow(ind, 10);
   double zone = 0.0;

   if(g_structure.dynamicSupport > 0.0)
      zone = g_structure.dynamicSupport;
   else
      zone = FindNearestSupportBelow(ind.closeArr[1], prof);

   if(hl > 0.0 && zone > 0.0)
      return MathMax(hl, zone);

   if(hl > 0.0)   return hl;
   if(zone > 0.0) return zone;
   return 0.0;
}

double GetBestBearTrailAnchor(const IndicatorState &ind, const SymbolProfile &prof)
{
   double lh = GetLatestLowerHigh(ind, 10);
   double zone = 0.0;

   if(g_structure.dynamicResistance > 0.0)
      zone = g_structure.dynamicResistance;
   else
      zone = FindNearestResistanceAbove(ind.closeArr[1], prof);

   if(lh > 0.0 && zone > 0.0)
      return MathMin(lh, zone);

   if(lh > 0.0)   return lh;
   if(zone > 0.0) return zone;
   return 0.0;
}

//+------------------------------------------------------------------+
//| ManageStructureTrail — with dynamic zone trailing for trends     |
//+------------------------------------------------------------------+
void ManageStructureTrail(CTrade &trade, const SymbolProfile &prof,
                          const IndicatorState &ind, ulong magic,
                          bool   useBreakeven,  double breakevenAtR,
                          int    swingLB,        double swingBuffATR,
                          bool   useEMA50Trail,  double ema50BuffATR,
                          double adxTrend,       int    slopeLB)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0)
      return;

   RefreshTrendCampaignState(magic);

   static datetime s_lastManageBar = 0;
   datetime manageBar = iTime(_Symbol, g_indicatorTF, 0);
   if(manageBar == s_lastManageBar)
      return;
   s_lastManageBar = manageBar;

   static datetime s_lastTrendEndCheckBar = 0;
   datetime trendBarTime = iTime(_Symbol, g_indicatorTF, 0);

   if(trendBarTime != s_lastTrendEndCheckBar)
   {
      s_lastTrendEndCheckBar = trendBarTime;

      string endReason = "";
      if(CountTrendCampaignPositions(magic, +1) > 0 && IsBullTrendEnded(ind, endReason))
      {
         Print("[TREND_END_CLOSE] side=BUY reason=", endReason);
         CloseTrendCampaignPositions(trade, magic, +1, "TREND_END_BUY: " + endReason);
      }
      if(CountTrendCampaignPositions(magic, -1) > 0 && IsBearTrendEnded(ind, endReason))
      {
         Print("[TREND_END_CLOSE] side=SELL reason=", endReason);
         CloseTrendCampaignPositions(trade, magic, -1, "TREND_END_SELL: " + endReason);
      }
   }

   double atr         = GetATR(ind, 1);
   double minStopDist = prof.stopsLevelPoints * prof.point;
   double minStep     = prof.point * 1;


   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      
      bool isBreakoutTrade = IsBreakoutTradeComment(comment);
      bool isReversalTrade = IsReversalTradeComment(comment);
      bool isTrendTrade    = IsTrendPositionComment(comment);
      
      if(!isTrendTrade && !isBreakoutTrade && !isReversalTrade)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double profit = (posType == POSITION_TYPE_BUY) ? (tick.bid - openPrice) : (openPrice - tick.ask);
      double riskR  = GetRegisteredInitialRisk(ticket);
      if(riskR <= 0.0)
         riskR = GetInitialRiskR(openPrice, currentSL);

      // ---------------------------------------------------------------
      // BREAKOUT TRADES: faster protection using TradeManager BE rules
      // REVERSAL TRADES: faster protection using TradeManager BE rules
      // ---------------------------------------------------------------
      if(isBreakoutTrade && riskR > 0.0)
      {
         // Use TradeManager helper for BE decision (checks >= 1R profit)
         if(ShouldMoveToBreakeven(posType, openPrice, currentSL, tick.bid, tick.ask))
         {
            double breakEvenSL = NormalizeDouble(openPrice, prof.digits);

            if(posType == POSITION_TYPE_BUY)
            {
               if(breakEvenSL > currentSL + minStep && tick.bid - breakEvenSL >= minStopDist)
               {
                  SafeModifyPosition(trade, ticket, breakEvenSL, currentTP, currentSL, currentTP, prof.point,
                                     "BREAKOUT_BE BUY");
               }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               if((currentSL == 0.0 || breakEvenSL < currentSL - minStep) && breakEvenSL - tick.ask >= minStopDist)
               {
                  SafeModifyPosition(trade, ticket, breakEvenSL, currentTP, currentSL, currentTP, prof.point,
                                     "BREAKOUT_BE SELL");
               }
            }
         }
      }

      if(isReversalTrade && riskR > 0.0)
      {
         // Use TradeManager helper for BE decision (checks >= 1R profit)
         if(ShouldMoveToBreakeven(posType, openPrice, currentSL, tick.bid, tick.ask))
         {
            double breakEvenSL = NormalizeDouble(openPrice, prof.digits);

            if(posType == POSITION_TYPE_BUY)
            {
               if(breakEvenSL > currentSL + minStep && tick.bid - breakEvenSL >= minStopDist)
               {
                  SafeModifyPosition(trade, ticket, breakEvenSL, currentTP, currentSL, currentTP, prof.point,
                                     "REVERSAL_BE BUY");
               }
            }
            else if(posType == POSITION_TYPE_SELL)
            {
               if((currentSL == 0.0 || breakEvenSL < currentSL - minStep) && breakEvenSL - tick.ask >= minStopDist)
               {
                  SafeModifyPosition(trade, ticket, breakEvenSL, currentTP, currentSL, currentTP, prof.point,
                                     "REVERSAL_BE SELL");
               }
            }
         }
      }
      
      // ---------------------------------------------------------------
      // TREND TRADES: Use TradeManager structure trail helpers
      // ---------------------------------------------------------------
      if(isTrendTrade && posType == POSITION_TYPE_BUY)
      {
         if(riskR <= 0.0)
         {
            Print("[STRUCTURE_TRAIL] side=BUY riskR=0: keep_original_SL");
            continue;
         }
         
         // STEP 8: Use TradeManager helper for trailing start decision
         double trailStartR = g_trendRunnerTrailStartR;

         if(!ShouldStartTrailing(posType, openPrice, currentSL, tick.bid, tick.ask, trailStartR))
         {
            Print("[STRUCTURE_TRAIL] side=BUY profitR=",
                  DoubleToString(profit / riskR, 2),
                  " below_", DoubleToString(trailStartR, 2),
                  "R: keep_original_SL");
            continue;
         }

         // Try structure trail first (preferred)
         double newSL = GetStructureTrailStopBuy(ind, prof, 10, currentSL, 0.40);
         string trailSource = "STRUCTURE";
         
         // Fallback to EMA50 trail if structure trail unavailable
         if(newSL <= 0.0)
         {
            newSL = GetEMA50TrailStopBuy(ind, prof, currentSL, 0.50);
            if(newSL > 0.0)
               trailSource = "EMA50";
         }
         
         // Final fallback to ATR trail
         if(newSL <= 0.0)
         {
            newSL = GetATRTrailStopBuy(ind, prof, tick.bid, currentSL, 2.0);
            if(newSL > 0.0)
               trailSource = "ATR";
         }
         
         if(newSL > 0.0)
         {
            // Check for full reversal to tighten further
            if(IsFullReversalConfirmed(ind, +1, atr) && profit >= riskR * 1.60)
            {
               Print("[TREND_EXIT_WARN] side=BUY reason=full_reversal_confirmed profitR=",
                     DoubleToString(profit / riskR, 2));
               
               double emergencySL = NormalizeDouble(MathMax(currentSL, tick.bid - atr * 0.35), prof.digits);
               if(emergencySL > currentSL + minStep && tick.bid - emergencySL >= minStopDist)
                  newSL = emergencySL;
            }
            
            Print("[STRUCTURE_TRAIL] side=BUY source=", trailSource,
                  " newSL=", DoubleToString(newSL, prof.digits),
                  " profitR=", DoubleToString(profit / riskR, 2));

            if(newSL > currentSL + minStep && tick.bid - newSL >= minStopDist)
               SafeModifyPosition(trade, ticket, newSL, currentTP, currentSL, currentTP, prof.point,
                                  "TRAIL_" + trailSource + " BUY: ticket=" + IntegerToString((int)ticket) +
                                  " newSL=" + DoubleToString(newSL, prof.digits));
         }
         else
         {
            Print("[STRUCTURE_TRAIL] side=BUY no_valid_trail profitR=",
                  DoubleToString(profit / riskR, 2), " keep_original_SL");
         }
      }
      else if(isTrendTrade && posType == POSITION_TYPE_SELL)
      {
         if(riskR <= 0.0)
         {
            Print("[STRUCTURE_TRAIL] side=SELL riskR=0: keep_original_SL");
            continue;
         }
         
         // STEP 8: Use TradeManager helper for trailing start decision
         double trailStartR = g_trendRunnerTrailStartR;

         if(!ShouldStartTrailing(posType, openPrice, currentSL, tick.bid, tick.ask, trailStartR))
         {
            Print("[STRUCTURE_TRAIL] side=SELL profitR=",
                  DoubleToString(profit / riskR, 2),
                  " below_", DoubleToString(trailStartR, 2),
                  "R: keep_original_SL");
            continue;
         }

         // Try structure trail first (preferred)
         double newSL = GetStructureTrailStopSell(ind, prof, 10, currentSL, 0.40);
         string trailSource = "STRUCTURE";
         
         // Fallback to EMA50 trail if structure trail unavailable
         if(newSL <= 0.0)
         {
            newSL = GetEMA50TrailStopSell(ind, prof, currentSL, 0.50);
            if(newSL > 0.0)
               trailSource = "EMA50";
         }
         
         // Final fallback to ATR trail
         if(newSL <= 0.0)
         {
            newSL = GetATRTrailStopSell(ind, prof, tick.ask, currentSL, 2.0);
            if(newSL > 0.0)
               trailSource = "ATR";
         }
         
         if(newSL > 0.0)
         {
            // Check for full reversal to tighten further
            if(IsFullReversalConfirmed(ind, -1, atr) && profit >= riskR * 1.60)
            {
               Print("[TREND_EXIT_WARN] side=SELL reason=full_reversal_confirmed profitR=",
                     DoubleToString(profit / riskR, 2));
               
               double emergencySL = NormalizeDouble(MathMin((currentSL > 0.0 ? currentSL : tick.ask + atr * 0.60),
                                                            tick.ask + atr * 0.35), prof.digits);
               if((currentSL == 0.0 || emergencySL < currentSL - minStep) && emergencySL - tick.ask >= minStopDist)
                  newSL = emergencySL;
            }
            
            Print("[STRUCTURE_TRAIL] side=SELL source=", trailSource,
                  " newSL=", DoubleToString(newSL, prof.digits),
                  " profitR=", DoubleToString(profit / riskR, 2));

            if(newSL < currentSL - minStep && newSL - tick.ask >= minStopDist)
               SafeModifyPosition(trade, ticket, newSL, currentTP, currentSL, currentTP, prof.point,
                                  "TRAIL_" + trailSource + " SELL: ticket=" + IntegerToString((int)ticket) +
                                  " newSL=" + DoubleToString(newSL, prof.digits));
         }
         else
         {
            Print("[STRUCTURE_TRAIL] side=SELL no_valid_trail profitR=",
                  DoubleToString(profit / riskR, 2), " keep_original_SL");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trend campaign holding and add-on logic helpers                     |
//+------------------------------------------------------------------+
// STEP 7: Recognize trend runner comments
bool IsTrendCampaignTrade(const string comment)
{
   return (
      StringFind(comment, "TREND") >= 0 ||
      StringFind(comment, "TREND_RUNNER") >= 0 ||
      StringFind(comment, "TREND_CONTINUATION") >= 0
   );
}

bool ShouldCloseTrendCampaign(const IndicatorState &ind, double atr, bool isBull)
{
   if(InpCloseTrendOnDoubleTopBottom)
   {
      if(isBull && IsTrendExhaustionDoubleTop(ind, atr)) return true;
      if(!isBull && IsTrendExhaustionDoubleBottom(ind, atr)) return true;
   }

   if(InpCloseTrendOnRepeatedExhaustion)
   {
      if(HasRepeatedExhaustionRejections(isBull ? 1 : -1, atr)) return true;
   }

   if(IsD1TrendlineBrokenAndRetested(ind, atr))
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Strategy-specific management helpers                                |
//+------------------------------------------------------------------+
bool IsCounterTrendTrade(const string comment)
{
   return (StringFind(comment, "COUNTERTREND") >= 0);
}

bool IsRangeTrade(const string comment)
{
   return (StringFind(comment, "RANGE") >= 0);
}

bool IsBreakoutTrade(const string comment)
{
   return (StringFind(comment, "BREAKOUT") >= 0);
}

bool IsTrendContinuationTrade(const string comment)
{
   return (StringFind(comment, "TREND_CONTINUATION") >= 0);
}

bool ShouldCloseCounterTrend(const IndicatorState &ind, double atr, bool isBull)
{
   if(isBull)
   {
      if(IsTrendExhaustionDoubleTop(ind, atr)) return true;
      if(ind.closeArr[1] < ind.openArr[1]) return true;
   }
   else
   {
      if(IsTrendExhaustionDoubleBottom(ind, atr)) return true;
      if(ind.closeArr[1] > ind.openArr[1]) return true;
   }

   return false;
}

bool ShouldCloseRangeTrade(const IndicatorState &ind, double atr, bool isBull)
{
   if(IsBreakoutFromRange(ind, atr))
      return true;

   return false;
}

bool ShouldCloseBreakoutTrade(const IndicatorState &ind, double atr, bool isBull)
{
   ZoneInfo z;
   int zIdx = -1;
   if(IsBreakoutRetestZone(ind, atr, z, zIdx))
   {
      if(isBull && ind.closeArr[1] < z.lowerBound - atr * 0.3)
         return true;
      if(!isBull && ind.closeArr[1] > z.upperBound + atr * 0.3)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| TRADE LIFECYCLE MANAGEMENT (merged from TradeManager.mqh)       |
//| R-based breakeven, trailing, exit filters, structure-aware      |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Entry model enum for trade tagging                               |
//+------------------------------------------------------------------+
enum EntryModel
{
   ENTRY_MODEL_UNKNOWN = 0,
   ENTRY_MODEL_SWEEP_REVERSAL,
   ENTRY_MODEL_BREAK_RETEST,
   ENTRY_MODEL_STACK_CONTINUATION
};

//+------------------------------------------------------------------+
//| Exit Filter State — tracks EMA50 close violations                |
//+------------------------------------------------------------------+
struct ExitFilterState
{
   int closeBeyondEMA50;  // consecutive closes beyond EMA50 against position
};

ExitFilterState g_exitFilter;

//+------------------------------------------------------------------+
//| Initial Risk Registry — preserves true 1R for trailing/BE        |
//| Stores original entry price and SL to compute real risk distance |
//+------------------------------------------------------------------+
#define MAX_INITIAL_RISK_ENTRIES 50

struct InitialRiskEntry
{
   ulong    positionId;
   double   entryPrice;
   double   initialSL;
   double   initialRiskDist;
   datetime openTime;
   bool     valid;
};

InitialRiskEntry g_initialRiskMap[MAX_INITIAL_RISK_ENTRIES];
int g_initialRiskCount = 0;

//+------------------------------------------------------------------+
//| Register initial risk for a newly opened position                |
//+------------------------------------------------------------------+
void RegisterInitialRisk(ulong positionId, double entryPrice, double initialSL)
{
   // Check if already registered
   for(int i = 0; i < g_initialRiskCount; i++)
   {
      if(g_initialRiskMap[i].valid && g_initialRiskMap[i].positionId == positionId)
      {
         // Already registered - skip
         return;
      }
   }
   
   // Find empty slot or add new
   int slot = -1;
   for(int i = 0; i < g_initialRiskCount; i++)
   {
      if(!g_initialRiskMap[i].valid)
      {
         slot = i;
         break;
      }
   }
   if(slot < 0 && g_initialRiskCount < MAX_INITIAL_RISK_ENTRIES)
      slot = g_initialRiskCount++;
   
   if(slot >= 0)
   {
      g_initialRiskMap[slot].positionId      = positionId;
      g_initialRiskMap[slot].entryPrice      = entryPrice;
      g_initialRiskMap[slot].initialSL       = initialSL;
      g_initialRiskMap[slot].initialRiskDist = MathAbs(entryPrice - initialSL);
      g_initialRiskMap[slot].openTime        = TimeCurrent();
      g_initialRiskMap[slot].valid           = true;
      Print("[INITIAL_RISK] registered posId=", positionId,
            " entry=", DoubleToString(entryPrice, _Digits),
            " sl=", DoubleToString(initialSL, _Digits),
            " riskDist=", DoubleToString(g_initialRiskMap[slot].initialRiskDist, _Digits));
   }
   else
   {
      Print("[INITIAL_RISK] WARNING: registry full, cannot register posId=", positionId);
   }
}

//+------------------------------------------------------------------+
//| Get registered initial risk distance for a position              |
//| Returns 0.0 if not found (caller should fallback with warning)   |
//+------------------------------------------------------------------+
double GetRegisteredInitialRisk(ulong positionId)
{
   for(int i = 0; i < g_initialRiskCount; i++)
   {
      if(g_initialRiskMap[i].valid && g_initialRiskMap[i].positionId == positionId)
         return g_initialRiskMap[i].initialRiskDist;
   }
   return 0.0;  // Not found
}

//+------------------------------------------------------------------+
//| Get registered entry price for a position                        |
//+------------------------------------------------------------------+
double GetRegisteredEntryPrice(ulong positionId)
{
   for(int i = 0; i < g_initialRiskCount; i++)
   {
      if(g_initialRiskMap[i].valid && g_initialRiskMap[i].positionId == positionId)
         return g_initialRiskMap[i].entryPrice;
   }
   return 0.0;  // Not found
}

//+------------------------------------------------------------------+
//| Remove initial risk entry when position closes                   |
//+------------------------------------------------------------------+
void RemoveInitialRisk(ulong positionId)
{
   for(int i = 0; i < g_initialRiskCount; i++)
   {
      if(g_initialRiskMap[i].valid && g_initialRiskMap[i].positionId == positionId)
      {
         g_initialRiskMap[i].valid = false;
         Print("[INITIAL_RISK] removed posId=", positionId);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Initialize trade manager states                                  |
//+------------------------------------------------------------------+
void InitTradeManager()
{
   g_exitFilter.closeBeyondEMA50 = 0;
   g_initialRiskCount = 0;
   for(int i = 0; i < MAX_INITIAL_RISK_ENTRIES; i++)
      g_initialRiskMap[i].valid = false;
}

//+------------------------------------------------------------------+
//| GetInitialRiskR — calculate 1R = distance from entry to SL      |
//+------------------------------------------------------------------+
double GetInitialRiskR(double entryPrice, double stopLoss)
{
   return MathAbs(entryPrice - stopLoss);
}

//+------------------------------------------------------------------+
//| ShouldMoveToBreakeven — true when profit >= 1R                   |
//+------------------------------------------------------------------+
bool ShouldMoveToBreakeven(ENUM_POSITION_TYPE posType, double entryPrice,
                           double stopLoss, double currentBid, double currentAsk)
{
   double riskR = GetInitialRiskR(entryPrice, stopLoss);
   if(riskR <= 0) return false;

   double profit = 0;
   if(posType == POSITION_TYPE_BUY)
      profit = currentBid - entryPrice;
   else
      profit = entryPrice - currentAsk;

   return (profit >= riskR);
}

//+------------------------------------------------------------------+
//| ShouldStartTrailing — true when profit >= trailingRMultiple * R  |
//+------------------------------------------------------------------+
bool ShouldStartTrailing(ENUM_POSITION_TYPE posType, double entryPrice,
                         double stopLoss, double currentBid, double currentAsk,
                         double trailingRMultiple)
{
   double riskR = GetInitialRiskR(entryPrice, stopLoss);
   if(riskR <= 0) return false;

   double profit = 0;
   if(posType == POSITION_TYPE_BUY)
      profit = currentBid - entryPrice;
   else
      profit = entryPrice - currentAsk;

   return (profit >= riskR * trailingRMultiple);
}

//+------------------------------------------------------------------+
//| Structure-based trailing stops                                   |
//+------------------------------------------------------------------+
double GetLatestHigherLow(const IndicatorState &ind, int lookback)
{
   int swingCount = 0;
   double swingLows[20];
   int lb = MathMax(lookback / 2, 2);
   int startBar = 1 + lb;
   int endBar   = 199 - lb;

   for(int i = startBar; i <= endBar && swingCount < 20; i++)
   {
      bool isSwing = true;
      for(int j = 1; j <= lb; j++)
      {
         if(ind.lowArr[i] >= ind.lowArr[i - j] || ind.lowArr[i] >= ind.lowArr[i + j])
         { isSwing = false; break; }
      }
      if(isSwing)
      {
         swingLows[swingCount] = ind.lowArr[i];
         swingCount++;
      }
   }

   for(int i = 0; i < swingCount - 1; i++)
   {
      if(swingLows[i] > swingLows[i + 1])
         return swingLows[i];
   }

   if(swingCount > 0)
      return swingLows[0];

   return 0;
}

double GetLatestLowerHigh(const IndicatorState &ind, int lookback)
{
   int swingCount = 0;
   double swingHighs[20];
   int lb = MathMax(lookback / 2, 2);
   int startBar = 1 + lb;
   int endBar   = 199 - lb;

   for(int i = startBar; i <= endBar && swingCount < 20; i++)
   {
      bool isSwing = true;
      for(int j = 1; j <= lb; j++)
      {
         if(ind.highArr[i] <= ind.highArr[i - j] || ind.highArr[i] <= ind.highArr[i + j])
         { isSwing = false; break; }
      }
      if(isSwing)
      {
         swingHighs[swingCount] = ind.highArr[i];
         swingCount++;
      }
   }

   for(int i = 0; i < swingCount - 1; i++)
   {
      if(swingHighs[i] < swingHighs[i + 1])
         return swingHighs[i];
   }

   if(swingCount > 0)
      return swingHighs[0];

   return 0;
}

double GetStructureTrailStopBuy(const IndicatorState &ind, const SymbolProfile &prof,
                                int lookback, double currentSL,
                                double atrBuffMult = 0.40)
{
   double hl = GetLatestHigherLow(ind, lookback);
   if(hl <= 0) return 0;

   double atr    = GetATR(ind, 1);
   double buffer = (atr > 0) ? atr * atrBuffMult
                             : prof.defaultSLBufferPoints * prof.point * 0.5;
   double newSL  = NormalizeDouble(hl - buffer, prof.digits);

   if(newSL > currentSL)
      return newSL;

   return 0;
}

double GetStructureTrailStopSell(const IndicatorState &ind, const SymbolProfile &prof,
                                 int lookback, double currentSL,
                                 double atrBuffMult = 0.40)
{
   double lh = GetLatestLowerHigh(ind, lookback);
   if(lh <= 0) return 0;

   double atr    = GetATR(ind, 1);
   double buffer = (atr > 0) ? atr * atrBuffMult
                             : prof.defaultSLBufferPoints * prof.point * 0.5;
   double newSL  = NormalizeDouble(lh + buffer, prof.digits);

   if(newSL < currentSL || currentSL == 0)
      return newSL;

   return 0;
}

//+------------------------------------------------------------------+
//| EMA50-based trailing stops                                       |
//+------------------------------------------------------------------+
double GetEMA50TrailStopBuy(const IndicatorState &ind, const SymbolProfile &prof,
                             double currentSL, double atrBuffMult = 0.50)
{
   double ema50 = GetEMA50(ind, 1);
   double atr   = GetATR(ind, 1);
   if(ema50 <= 0 || atr <= 0) return 0;

   double newSL = NormalizeDouble(ema50 - atr * atrBuffMult, prof.digits);
   if(newSL > currentSL)
      return newSL;

   return 0;
}

double GetEMA50TrailStopSell(const IndicatorState &ind, const SymbolProfile &prof,
                              double currentSL, double atrBuffMult = 0.50)
{
   double ema50 = GetEMA50(ind, 1);
   double atr   = GetATR(ind, 1);
   if(ema50 <= 0 || atr <= 0) return 0;

   double newSL = NormalizeDouble(ema50 + atr * atrBuffMult, prof.digits);
   if(newSL < currentSL || currentSL == 0)
      return newSL;

   return 0;
}

//+------------------------------------------------------------------+
//| ATR-based trailing stops                                         |
//+------------------------------------------------------------------+
double GetATRTrailStopBuy(const IndicatorState &ind, const SymbolProfile &prof,
                          double currentBid, double currentSL, double atrMultiplier)
{
   double atrVal = GetATR(ind, 1);
   if(atrVal <= 0) return 0;

   double newSL = NormalizeDouble(currentBid - atrVal * atrMultiplier, prof.digits);
   if(newSL > currentSL)
      return newSL;

   return 0;
}

double GetATRTrailStopSell(const IndicatorState &ind, const SymbolProfile &prof,
                           double currentAsk, double currentSL, double atrMultiplier)
{
   double atrVal = GetATR(ind, 1);
   if(atrVal <= 0) return 0;

   double newSL = NormalizeDouble(currentAsk + atrVal * atrMultiplier, prof.digits);
   if(newSL < currentSL || currentSL == 0)
      return newSL;

   return 0;
}

//+------------------------------------------------------------------+
//| Exit filter management                                            |
//+------------------------------------------------------------------+
void UpdateExitFilter(const IndicatorState &ind, ENUM_POSITION_TYPE posType)
{
   double close1   = ind.closeArr[1];
   double ema50_1 = GetEMA50(ind, 1);

   if(posType == POSITION_TYPE_BUY)
   {
      if(close1 < ema50_1)
         g_exitFilter.closeBeyondEMA50++;
      else
         g_exitFilter.closeBeyondEMA50 = 0;
   }
   else
   {
      if(close1 > ema50_1)
         g_exitFilter.closeBeyondEMA50++;
      else
         g_exitFilter.closeBeyondEMA50 = 0;
   }
}

bool ShouldExitOnEMA50Reversal(const IndicatorState &ind, ENUM_POSITION_TYPE posType)
{
   double close1  = ind.closeArr[1];
   double close2  = ind.closeArr[2];
   double ema50_1 = GetEMA50(ind, 1);
   double ema50_2 = GetEMA50(ind, 2);

   if(posType == POSITION_TYPE_BUY)
   {
      if(close1 < ema50_1 && close2 < ema50_2)
      {
         Print("EXIT: 2 consecutive closes below EMA50 — closing BUY");
         return true;
      }
   }
   else
   {
      if(close1 > ema50_1 && close2 > ema50_2)
      {
         Print("EXIT: 2 consecutive closes above EMA50 — closing SELL");
         return true;
      }
   }

   return false;
}

bool ShouldExitOnOppositeCross(const IndicatorState &ind, ENUM_POSITION_TYPE posType)
{
   return ShouldExitOnEMA50Reversal(ind, posType);
}

bool ShouldExitOnCloseBeyondEMA50(const IndicatorState &ind, ENUM_POSITION_TYPE posType)
{
   double close1  = ind.closeArr[1];
   double ema50_1 = GetEMA50(ind, 1);

   if(posType == POSITION_TYPE_BUY && close1 < ema50_1)
   {
      Print("EXIT: Price closed below EMA50 — closing BUY");
      return true;
   }
   if(posType == POSITION_TYPE_SELL && close1 > ema50_1)
   {
      Print("EXIT: Price closed above EMA50 — closing SELL");
      return true;
   }

   return false;
}

bool ShouldExitOnEMA50ProfitProtection(const IndicatorState &ind,
                                         ENUM_POSITION_TYPE posType,
                                         double entryPrice)
{
   double close1  = ind.closeArr[1];
   double ema50_1 = GetEMA50(ind, 1);

   if(posType == POSITION_TYPE_BUY)
   {
      if(close1 > entryPrice && close1 < ema50_1)
      {
         Print("PROFIT PROTECTION: close back through EMA50 while BUY in profit");
         return true;
      }
   }
   else
   {
      if(close1 < entryPrice && close1 > ema50_1)
      {
         Print("PROFIT PROTECTION: close back through EMA50 while SELL in profit");
         return true;
      }
   }

   return false;
}

void ResetExitFilter()
{
   g_exitFilter.closeBeyondEMA50 = 0;
}

//+------------------------------------------------------------------+
//| Count open trend positions                                       |
//+------------------------------------------------------------------+
int CountOpenTrendPositions(const string symbol, ulong magic, int dir)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != symbol) continue;

      string comment = PositionGetString(POSITION_COMMENT);
      bool isTrendBuy  = (StringFind(comment, "TREND") >= 0 && StringFind(comment, "BUY") >= 0);
      bool isTrendSell = (StringFind(comment, "TREND") >= 0 && StringFind(comment, "SELL") >= 0);

      if(!isTrendBuy && !isTrendSell)
         continue;

      if(dir == 0)
         count++;
      else if(dir == +1 && isTrendBuy)
         count++;
      else if(dir == -1 && isTrendSell)
         count++;
   }

   Print("[TREND_POSITION_COUNT] dir=", (dir == +1 ? "BUY" : (dir == -1 ? "SELL" : "ANY")),
         " count=", count);
   return count;
}

//+------------------------------------------------------------------+
//| Check if structure has fully reversed                            |
//+------------------------------------------------------------------+
bool IsFullReversalConfirmed(const IndicatorState &ind, int trendDir, double atr)
{
   if(atr <= 0.0) return false;

   bool structureFlipped = false;
   if(trendDir == +1)
      structureFlipped = (g_structure.state == STRUCTURE_BEAR_TREND || g_structure.state == STRUCTURE_BIAS_BEAR);
   else if(trendDir == -1)
      structureFlipped = (g_structure.state == STRUCTURE_BULL_TREND || g_structure.state == STRUCTURE_BIAS_BULL);

   if(!structureFlipped)
      return false;

   double ema50     = GetEMA50(ind, 1);
   double ema50Prev = GetEMA50(ind, 4);
   double slopeATR  = (ema50 - ema50Prev) / atr;

   bool slopeAgrees = false;
   if(trendDir == +1)
      slopeAgrees = (slopeATR < -0.02);
   else
      slopeAgrees = (slopeATR > 0.02);

   bool anchorBroken = false;
   if(trendDir == +1 && g_structure.dynamicSupport > 0.0)
      anchorBroken = (ind.closeArr[1] < g_structure.dynamicSupport);
   else if(trendDir == -1 && g_structure.dynamicResistance > 0.0)
      anchorBroken = (ind.closeArr[1] > g_structure.dynamicResistance);
   else
      anchorBroken = true;

   return (structureFlipped && slopeAgrees && anchorBroken);
}

#endif // POSITION_MANAGER_MQH
