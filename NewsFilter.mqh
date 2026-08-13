//+------------------------------------------------------------------+
//|                                                   NewsFilter.mqh |
//|  Forex news event filter — blocks entries and force-closes trades |
//|  around high/medium impact news events                           |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef NEWS_FILTER_MQH
#define NEWS_FILTER_MQH

//+------------------------------------------------------------------+
//| News impact levels                                               |
//+------------------------------------------------------------------+
enum ENUM_NEWS_IMPACT
{
   NEWS_LOW    = 0,
   NEWS_MEDIUM = 1,
   NEWS_HIGH   = 2
};

//+------------------------------------------------------------------+
//| Single news event                                                |
//+------------------------------------------------------------------+
struct NewsEvent
{
   string           currency;   // e.g. "USD", "EUR", "GBP"
   datetime         eventTime;  // scheduled release time
   ENUM_NEWS_IMPACT impact;     // HIGH, MEDIUM, LOW
   string           title;      // description (for logging)
};

//+------------------------------------------------------------------+
//| News calendar state                                              |
//+------------------------------------------------------------------+
#define MAX_NEWS_EVENTS 64

struct NewsCalendar
{
   NewsEvent events[MAX_NEWS_EVENTS];
   int       count;
   datetime  lastLoad;
};

NewsCalendar g_news;
bool g_newsCalendarAvailable = false;  // true if last load succeeded with data
bool g_newsUnavailableLogged = false;  // prevent log spam when calendar unavailable

//+------------------------------------------------------------------+
//| Initialize news calendar                                         |
//+------------------------------------------------------------------+
void InitNewsCalendar()
{
   g_news.count    = 0;
   g_news.lastLoad = 0;
   g_newsCalendarAvailable = false;
   g_newsUnavailableLogged = false;
}

bool IsNewsCalendarAvailable() { return g_newsCalendarAvailable; }

//+------------------------------------------------------------------+
//| Add a news event manually (call from OnInit or timer)            |
//+------------------------------------------------------------------+
bool AddNewsEvent(const string currency, datetime eventTime,
                  ENUM_NEWS_IMPACT impact, const string title = "")
{
   if(g_news.count >= MAX_NEWS_EVENTS)
   {
      Print("NEWS: Calendar full (", MAX_NEWS_EVENTS, " events)");
      return false;
   }

   int idx = g_news.count;
   g_news.events[idx].currency  = currency;
   g_news.events[idx].eventTime = eventTime;
   g_news.events[idx].impact    = impact;
   g_news.events[idx].title     = title;
   g_news.count++;
   return true;
}

//+------------------------------------------------------------------+
//| Clear all expired events (older than 2 hours)                    |
//+------------------------------------------------------------------+
void PurgeOldNewsEvents()
{
   datetime cutoff = TimeCurrent() - 2 * 3600;
   int write = 0;

   for(int i = 0; i < g_news.count; i++)
   {
      if(g_news.events[i].eventTime >= cutoff)
      {
         if(write != i)
            g_news.events[write] = g_news.events[i];
         write++;
      }
   }
   g_news.count = write;
}

//+------------------------------------------------------------------+
//| Check if symbol's currencies are affected by a news currency     |
//+------------------------------------------------------------------+
bool SymbolAffectedByCurrency(const string symbol, const string currency)
{
   string sym = symbol;
   StringToUpper(sym);
   string cur = currency;
   StringToUpper(cur);

   return (StringFind(sym, cur) >= 0);
}

//+------------------------------------------------------------------+
//| Is entry blocked for this symbol due to upcoming/recent news?    |
//|                                                                  |
//| HIGH:   block 30 min before, 30 min after                        |
//| MEDIUM: block 15 min before, 15 min after                        |
//| LOW:    ignored                                                  |
//+------------------------------------------------------------------+
bool IsNewsEntryBlocked(const string symbol,
                        int highBlockBefore  = 30,
                        int highBlockAfter   = 30,
                        int medBlockBefore   = 15,
                        int medBlockAfter    = 15)
{
   datetime now = TimeCurrent();

   for(int i = 0; i < g_news.count; i++)
   {
      if(!SymbolAffectedByCurrency(symbol, g_news.events[i].currency))
         continue;

      int minBefore = (int)((g_news.events[i].eventTime - now) / 60);
      int minAfter  = (int)((now - g_news.events[i].eventTime) / 60);

      if(g_news.events[i].impact == NEWS_HIGH)
      {
         if(minBefore >= 0 && minBefore <= highBlockBefore)
            return true;
         if(minAfter >= 0 && minAfter <= highBlockAfter)
            return true;
      }

      if(g_news.events[i].impact == NEWS_MEDIUM)
      {
         if(minBefore >= 0 && minBefore <= medBlockBefore)
            return true;
         if(minAfter >= 0 && minAfter <= medBlockAfter)
            return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Should we force-close trades? (10 min before HIGH impact only)   |
//+------------------------------------------------------------------+
bool IsHighImpactNewsCloseWindow(const string symbol,
                                  int closeMinutesBefore = 10)
{
   datetime now = TimeCurrent();

   for(int i = 0; i < g_news.count; i++)
   {
      if(g_news.events[i].impact != NEWS_HIGH)
         continue;

      if(!SymbolAffectedByCurrency(symbol, g_news.events[i].currency))
         continue;

      int minBefore = (int)((g_news.events[i].eventTime - now) / 60);

      if(minBefore >= 0 && minBefore <= closeMinutesBefore)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Get the reason string for the current news block (for logging)   |
//+------------------------------------------------------------------+
string GetNewsBlockReason(const string symbol,
                          int highBlockBefore = 30,
                          int highBlockAfter  = 30,
                          int medBlockBefore  = 15,
                          int medBlockAfter   = 15)
{
   datetime now = TimeCurrent();

   for(int i = 0; i < g_news.count; i++)
   {
      if(!SymbolAffectedByCurrency(symbol, g_news.events[i].currency))
         continue;

      int minBefore = (int)((g_news.events[i].eventTime - now) / 60);
      int minAfter  = (int)((now - g_news.events[i].eventTime) / 60);
      bool blocked  = false;

      if(g_news.events[i].impact == NEWS_HIGH)
      {
         blocked = ((minBefore >= 0 && minBefore <= highBlockBefore) ||
                    (minAfter  >= 0 && minAfter  <= highBlockAfter));
      }
      else if(g_news.events[i].impact == NEWS_MEDIUM)
      {
         blocked = ((minBefore >= 0 && minBefore <= medBlockBefore) ||
                    (minAfter  >= 0 && minAfter  <= medBlockAfter));
      }

      if(!blocked)
         continue;

      string impactStr = (g_news.events[i].impact == NEWS_HIGH) ? "HIGH" : "MEDIUM";
      string timeStr   = "";

      if(minBefore >= 0)
         timeStr = IntegerToString(minBefore) + "min before";
      else if(minAfter >= 0)
         timeStr = IntegerToString(minAfter) + "min after";

      return impactStr + " " + g_news.events[i].currency + " news (" +
             g_news.events[i].title + ") " + timeStr;
   }

   return "";
}

//+------------------------------------------------------------------+
//| Auto-refresh news calendar (call from OnTick — hourly)          |
//| Also refreshes at start of each new day                         |
//+------------------------------------------------------------------+
void EnsureNewsCalendarLoaded()
{
   datetime now = TimeCurrent();

   // Refresh if never loaded
   if(g_news.lastLoad == 0)
   {
      LoadTodaysNewsFromCalendar();
      return;
   }

   // Refresh at start of a new day
   MqlDateTime dtNow, dtLast;
   TimeToStruct(now, dtNow);
   TimeToStruct(g_news.lastLoad, dtLast);
   bool newDay = (dtNow.day != dtLast.day || dtNow.mon != dtLast.mon);

   // Or refresh every 60 minutes
   bool stale = ((now - g_news.lastLoad) >= 3600);

   if(newDay || stale)
      LoadTodaysNewsFromCalendar();
}

//+------------------------------------------------------------------+
//| Get the next upcoming high-impact news event for the symbol      |
//| Returns true if found, fills eventTime and title                 |
//+------------------------------------------------------------------+
bool GetNextHighImpactEvent(const string symbol, datetime &eventTime,
                             string &eventTitle, string &eventCurrency)
{
   datetime now = TimeCurrent();
   datetime soonest = 0;
   int      bestIdx = -1;

   for(int i = 0; i < g_news.count; i++)
   {
      if(g_news.events[i].eventTime <= now)
         continue;

      if(g_news.events[i].impact != NEWS_HIGH)
         continue;

      if(!SymbolAffectedByCurrency(symbol, g_news.events[i].currency))
         continue;

      if(soonest == 0 || g_news.events[i].eventTime < soonest)
      {
         soonest = g_news.events[i].eventTime;
         bestIdx = i;
      }
   }

   if(bestIdx < 0)
      return false;

   eventTime     = g_news.events[bestIdx].eventTime;
   eventTitle    = g_news.events[bestIdx].title;
   eventCurrency = g_news.events[bestIdx].currency;
   return true;
}

//+------------------------------------------------------------------+
//| Minutes until next high-impact news event (-1 if none today)    |
//+------------------------------------------------------------------+
int MinutesToNextHighImpact(const string symbol)
{
   datetime eventTime;
   string   title, currency;

   if(!GetNextHighImpactEvent(symbol, eventTime, title, currency))
      return -1;

   int mins = (int)((eventTime - TimeCurrent()) / 60);
   return MathMax(0, mins);
}

//+------------------------------------------------------------------+
//| Is there a high-impact event within N minutes for this symbol?   |
//+------------------------------------------------------------------+
bool IsHighImpactEventImminent(const string symbol, int withinMinutes = 30)
{
   int mins = MinutesToNextHighImpact(symbol);
   if(mins < 0) return false;
   return (mins <= withinMinutes);
}

//+------------------------------------------------------------------+
//| Get block reason string for logging                              |
//+------------------------------------------------------------------+
string GetNewsBlockReason(const string symbol,
                           int blockBefore = 30, int blockAfter = 15)
{
   if(!IsNewsEntryBlocked(symbol, blockBefore, blockAfter))
      return "";

   datetime eventTime;
   string   title, currency;

   if(GetNextHighImpactEvent(symbol, eventTime, title, currency))
   {
      int minsTo = (int)((eventTime - TimeCurrent()) / 60);
      if(minsTo >= 0)
         return "News block: " + title + " (" + currency + ") in " +
                IntegerToString(minsTo) + " min";
      else
         return "News block: post-event cooldown (" + title + ")";
   }

   return "News block: high-impact event";
}

void LoadTodaysNewsFromCalendar()
{
   g_news.count = 0;

   MqlDateTime dt;
   TimeCurrent(dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   datetime dayStart = StructToTime(dt);
   datetime dayEnd   = dayStart + 86400;

   // Try MQL5 built-in calendar
   MqlCalendarValue values[];
   int total = CalendarValueHistory(values, dayStart, dayEnd);

   if(total < 0)
   {
      // Calendar API error — degraded mode
      g_newsCalendarAvailable = false;
      g_news.lastLoad = TimeCurrent();
      if(!g_newsUnavailableLogged)
      {
         Print("NEWS WARNING: Economic calendar unavailable (API error) — news filter degraded, entries NOT blocked by news");
         g_newsUnavailableLogged = true;
      }
      return;
   }

   if(total == 0)
   {
      // Calendar works but no events today
      g_newsCalendarAvailable = true;
      g_newsUnavailableLogged = false;
      g_news.lastLoad = TimeCurrent();
      Print("NEWS: No medium/high impact events found for today");
      return;
   }

   for(int i = 0; i < total && g_news.count < MAX_NEWS_EVENTS; i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event))
         continue;

      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country))
         continue;

      // Map importance: CALENDAR_IMPORTANCE_HIGH=3, MEDIUM=2, LOW=1
      ENUM_NEWS_IMPACT impact = NEWS_LOW;
      if(event.importance == CALENDAR_IMPORTANCE_HIGH)
         impact = NEWS_HIGH;
      else if(event.importance == CALENDAR_IMPORTANCE_MODERATE)
         impact = NEWS_MEDIUM;
      else
         continue; // skip low impact

      AddNewsEvent(country.currency, values[i].time, impact, event.name);
   }

   g_news.lastLoad = TimeCurrent();
   g_newsCalendarAvailable = true;
   g_newsUnavailableLogged = false;
   Print("NEWS: Loaded ", g_news.count, " medium/high impact events for today");

   // Log upcoming events
   datetime now = TimeCurrent();
   for(int i = 0; i < g_news.count; i++)
   {
      if(g_news.events[i].eventTime >= now)
      {
         string impStr = (g_news.events[i].impact == NEWS_HIGH) ? "HIGH" : "MED";
         Print("  NEWS EVENT: ", impStr, " | ", g_news.events[i].currency,
               " | ", TimeToString(g_news.events[i].eventTime, TIME_MINUTES),
               " | ", g_news.events[i].title);
      }
   }
}

#endif // NEWS_FILTER_MQH
