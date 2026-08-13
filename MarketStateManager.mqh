//+------------------------------------------------------------------+
//|                                          MarketStateManager.mqh |
//|  Market state: tick, spread, session, execution permission       |
//|  v5.13 — tickTime, tickFresh, proper session checks, bool return |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef MARKET_STATE_MANAGER_MQH
#define MARKET_STATE_MANAGER_MQH

#include "SymbolProfiler.mqh"

const int MAX_TICK_AGE_SECONDS = 120;

//+------------------------------------------------------------------+
//| Market State Struct                                              |
//+------------------------------------------------------------------+
struct MarketState
{
   double   bid;
   double   ask;
   double   spreadPoints;
   double   avgSpread;
   double   maxSpread;
   int      spreadSamples;
   bool     sessionOpen;
   bool     tradeAllowed;
   bool     canTradeNow;
   datetime tickTime;
   bool     tickFresh;
};

// Global market state
MarketState g_market;

//+------------------------------------------------------------------+
//| Get latest tick — returns false if invalid or stale              |
//+------------------------------------------------------------------+
bool GetLatestTick(MarketState &ms, const SymbolProfile &prof)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
   {
      Print("TICK ERROR: SymbolInfoTick failed");
      ms.tickFresh = false;
      return false;
   }

   if(tick.bid <= 0 || tick.ask <= 0)
   {
      Print("TICK ERROR: Invalid bid/ask: bid=", tick.bid, " ask=", tick.ask);
      ms.tickFresh = false;
      return false;
   }

   // Check tick staleness (30 seconds for live, relaxed for tester)
   bool isTester = MQLInfoInteger(MQL_TESTER);
   datetime tickAge = TimeCurrent() - tick.time;

   if(!isTester && tickAge > MAX_TICK_AGE_SECONDS)
   {
      Print("TICK WARNING: Stale tick, age=", tickAge, "s");
      ms.tickFresh = false;
      // Still populate values but mark as stale
   }
   else
   {
      ms.tickFresh = true;
   }

   ms.bid = tick.bid;
   ms.ask = tick.ask;

   if(prof.point <= 0)
   {
      Print("TICK ERROR: Invalid point size");
      ms.tickFresh = false;
      return false;
   }

   ms.spreadPoints = (tick.ask - tick.bid) / prof.point;
   ms.tickTime = tick.time;

   return true;
}

//+------------------------------------------------------------------+
//| Update spread statistics                                         |
//+------------------------------------------------------------------+
void UpdateSpreadStats(MarketState &ms)
{
   ms.spreadSamples++;

   if(ms.spreadSamples == 1)
   {
      ms.avgSpread = ms.spreadPoints;
      ms.maxSpread = ms.spreadPoints;
   }
   else
   {
      ms.avgSpread = ((ms.avgSpread * (ms.spreadSamples - 1)) + ms.spreadPoints) / ms.spreadSamples;
      if(ms.spreadPoints > ms.maxSpread)
         ms.maxSpread = ms.spreadPoints;
   }
}

//+------------------------------------------------------------------+
//| Check if spread is acceptable                                    |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(const MarketState &ms, const SymbolProfile &prof, double maxMultiplier)
{
   double maxAllowed = prof.defaultSpreadCapPoints * maxMultiplier;
   return (ms.spreadPoints <= maxAllowed);
}

//+------------------------------------------------------------------+
//| Check trading permission from broker                             |
//+------------------------------------------------------------------+
bool IsTradingAllowed(const SymbolProfile &prof)
{
   // Check terminal trading
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      Print("TRADE BLOCKED: Terminal trading disabled");
      return false;
   }

   // Check expert trading
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      Print("TRADE BLOCKED: Expert trading disabled");
      return false;
   }

   // Check symbol trade mode
   ENUM_SYMBOL_TRADE_MODE mode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED)
   {
      Print("TRADE BLOCKED: Symbol trading disabled");
      return false;
   }

   if(mode == SYMBOL_TRADE_MODE_CLOSEONLY)
   {
      Print("TRADE BLOCKED: Symbol is close-only");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check if trading session is open — checks ALL sessions           |
//+------------------------------------------------------------------+
bool IsTradingSessionOpen(const SymbolProfile &prof)
{
   ENUM_SYMBOL_TRADE_MODE mode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);

   // If symbol itself is not tradable, session is effectively closed
   if(mode == SYMBOL_TRADE_MODE_DISABLED || mode == SYMBOL_TRADE_MODE_CLOSEONLY)
      return false;

   // In MT5 tester, forex session tables are often unreliable for majors.
   // For forex majors in backtests, prefer a broad weekday-open rule.
   if(MQLInfoInteger(MQL_TESTER) && prof.classEnum == INST_FOREX_MAJOR)
   {
      MqlDateTime testerDt;
      TimeToStruct(TimeCurrent(), testerDt);
      return (mode == SYMBOL_TRADE_MODE_FULL &&
              testerDt.day_of_week >= 1 &&
              testerDt.day_of_week <= 5);
   }

   // 24/7 symbols
   if(prof.classEnum == INST_SYNTH_VOL || prof.is24x7)
      return (mode == SYMBOL_TRADE_MODE_FULL);

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   ENUM_DAY_OF_WEEK dow = (ENUM_DAY_OF_WEEK)dt.day_of_week;

   bool foundAnySession = false;
   int currentTime = dt.hour * 3600 + dt.min * 60 + dt.sec;

   for(int sessionIdx = 0; sessionIdx < 10; sessionIdx++)
   {
      datetime from = 0, to = 0;
      if(!SymbolInfoSessionTrade(_Symbol, dow, sessionIdx, from, to))
         break;

      foundAnySession = true;

      int sessionFrom = (int)(from % 86400);
      int sessionTo   = (int)(to % 86400);

      if(sessionTo < sessionFrom)
      {
         if(currentTime >= sessionFrom || currentTime <= sessionTo)
            return true;
      }
      else
      {
         if(currentTime >= sessionFrom && currentTime <= sessionTo)
            return true;
      }
   }

   // Fallback for brokers that don't return session data cleanly
   if(!foundAnySession)
   {
      Print("SESSION WARNING: No session data returned, using trade mode fallback");
      return (mode == SYMBOL_TRADE_MODE_FULL);
   }

   return false;
}

//+------------------------------------------------------------------+
//| Refresh full market state — returns false if critical failure    |
//+------------------------------------------------------------------+
bool RefreshMarketState(MarketState &ms, const SymbolProfile &prof, double maxSpreadMult)
{
   // 1. Get latest tick
   if(!GetLatestTick(ms, prof))
   {
      ms.canTradeNow = false;
      return false;
   }

   // 2. Update spread stats
   UpdateSpreadStats(ms);

   // 3. Check session
   ms.sessionOpen = IsTradingSessionOpen(prof);

   // 4. Check trading permission
   ms.tradeAllowed = IsTradingAllowed(prof);

   // 5. Determine if we can trade now - HARD BLOCK on stale tick
   ms.canTradeNow = ms.sessionOpen && ms.tradeAllowed && ms.tickFresh;
   if(!ms.tickFresh)
      Print("[ENTRY_BLOCKED] reason=stale_tick - new entries not allowed on stale quotes");

   // 6. Check spread (informational, doesn't block refresh)
   if(!IsSpreadAcceptable(ms, prof, maxSpreadMult))
   {
      // Spread too wide, but state refresh succeeded
      // Entry logic will check spread separately
   }

   return true;
}

//+------------------------------------------------------------------+
//| Log market state for diagnostics                                 |
//+------------------------------------------------------------------+
void LogMarketState(const MarketState &ms, const SymbolProfile &prof)
{
   Print("MARKET: bid=", DoubleToString(ms.bid, prof.digits),
         " ask=", DoubleToString(ms.ask, prof.digits),
         " spread=", DoubleToString(ms.spreadPoints, 1), "pts",
         " session=", (ms.sessionOpen ? "OPEN" : "CLOSED"),
         " trade=", (ms.tradeAllowed ? "ALLOWED" : "BLOCKED"),
         " tickFresh=", (ms.tickFresh ? "YES" : "STALE"),
         " canTrade=", (ms.canTradeNow ? "YES" : "NO"));
}

#endif // MARKET_STATE_MANAGER_MQH
