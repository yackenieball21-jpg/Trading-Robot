//+------------------------------------------------------------------+
//|                                            MaintenanceFilter.mqh |
//|  Broker/Deriv maintenance window filter — blocks entries and     |
//|  force-closes trades around scheduled maintenance                |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef MAINTENANCE_FILTER_MQH
#define MAINTENANCE_FILTER_MQH

//+------------------------------------------------------------------+
//| Single maintenance window                                        |
//+------------------------------------------------------------------+
struct MaintenanceWindow
{
   string   symbol;      // affected symbol, or "ALL" for all symbols
   datetime startTime;   // maintenance start
   datetime endTime;     // maintenance end
   string   description; // reason (for logging)
};

//+------------------------------------------------------------------+
//| Maintenance schedule state                                       |
//+------------------------------------------------------------------+
#define MAX_MAINT_WINDOWS 16

struct MaintenanceSchedule
{
   MaintenanceWindow windows[MAX_MAINT_WINDOWS];
   int               count;
   datetime          lastAutoRefresh;
};

MaintenanceSchedule g_maint;

//+------------------------------------------------------------------+
//| Initialize maintenance schedule                                  |
//+------------------------------------------------------------------+
void InitMaintenanceSchedule()
{
   g_maint.count = 0;
   g_maint.lastAutoRefresh = 0;
}

//+------------------------------------------------------------------+
//| Check if a maintenance window already exists (dedup)             |
//+------------------------------------------------------------------+
bool MaintenanceWindowExists(const string symbol, datetime startTime,
                             datetime endTime, const string description = "")
{
   for(int i = 0; i < g_maint.count; i++)
   {
      if(g_maint.windows[i].symbol == symbol &&
         g_maint.windows[i].startTime == startTime &&
         g_maint.windows[i].endTime == endTime &&
         g_maint.windows[i].description == description)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Add a maintenance window                                         |
//+------------------------------------------------------------------+
bool AddMaintenanceWindow(const string symbol, datetime startTime,
                          datetime endTime, const string description = "")
{
   if(endTime <= startTime)
   {
      Print("MAINT: Invalid window ignored for ", symbol);
      return false;
   }

   if(MaintenanceWindowExists(symbol, startTime, endTime, description))
      return true;

   if(g_maint.count >= MAX_MAINT_WINDOWS)
   {
      Print("MAINT: Schedule full (", MAX_MAINT_WINDOWS, " windows)");
      return false;
   }

   int idx = g_maint.count;
   g_maint.windows[idx].symbol      = symbol;
   g_maint.windows[idx].startTime   = startTime;
   g_maint.windows[idx].endTime     = endTime;
   g_maint.windows[idx].description = description;
   g_maint.count++;

   Print("MAINT: Added window for ", symbol, " from ",
         TimeToString(startTime, TIME_DATE|TIME_MINUTES), " to ",
         TimeToString(endTime, TIME_DATE|TIME_MINUTES),
         (description != "" ? " (" + description + ")" : ""));
   return true;
}

//+------------------------------------------------------------------+
//| Clear expired maintenance windows (ended > 1 hour ago)           |
//+------------------------------------------------------------------+
void PurgeOldMaintenanceWindows()
{
   datetime cutoff = TimeCurrent() - 3600;
   int write = 0;

   for(int i = 0; i < g_maint.count; i++)
   {
      if(g_maint.windows[i].endTime >= cutoff)
      {
         if(write != i)
            g_maint.windows[write] = g_maint.windows[i];
         write++;
      }
   }
   g_maint.count = write;
}

//+------------------------------------------------------------------+
//| Check if symbol matches a maintenance window                     |
//+------------------------------------------------------------------+
bool MaintWindowMatchesSymbol(const MaintenanceWindow &w, const string symbol)
{
   if(w.symbol == "ALL")
      return true;

   string ws = w.symbol;
   StringToUpper(ws);
   string ss = symbol;
   StringToUpper(ss);

   return (ws == ss || StringFind(ss, ws) >= 0);
}

//+------------------------------------------------------------------+
//| Is symbol in a maintenance entry-block zone?                     |
//| Blocks entries: blockBefore minutes before start                 |
//|                 through blockAfter minutes after end              |
//+------------------------------------------------------------------+
bool IsSymbolInMaintenanceWindow(const string symbol,
                                  int blockMinutesBefore = 30,
                                  int blockMinutesAfter  = 15)
{
   datetime now = TimeCurrent();

   for(int i = 0; i < g_maint.count; i++)
   {
      if(!MaintWindowMatchesSymbol(g_maint.windows[i], symbol))
         continue;

      datetime blockStart = g_maint.windows[i].startTime - blockMinutesBefore * 60;
      datetime blockEnd   = g_maint.windows[i].endTime   + blockMinutesAfter  * 60;

      if(now >= blockStart && now <= blockEnd)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Should force-close trades? (closeMinutes before maintenance)     |
//+------------------------------------------------------------------+
bool IsSymbolInMaintenanceCloseWindow(const string symbol,
                                       int closeMinutesBefore = 10)
{
   datetime now = TimeCurrent();

   for(int i = 0; i < g_maint.count; i++)
   {
      if(!MaintWindowMatchesSymbol(g_maint.windows[i], symbol))
         continue;

      int minToStart = (int)((g_maint.windows[i].startTime - now) / 60);

      if(minToStart >= 0 && minToStart <= closeMinutesBefore)
         return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| Get maintenance block reason for logging                         |
//+------------------------------------------------------------------+
string GetMaintenanceBlockReason(const string symbol,
                                 int blockMinutesBefore = 30,
                                 int blockMinutesAfter  = 15)
{
   datetime now = TimeCurrent();

   for(int i = 0; i < g_maint.count; i++)
   {
      if(!MaintWindowMatchesSymbol(g_maint.windows[i], symbol))
         continue;

      datetime blockStart = g_maint.windows[i].startTime - blockMinutesBefore * 60;
      datetime blockEnd   = g_maint.windows[i].endTime   + blockMinutesAfter  * 60;

      if(now >= blockStart && now <= blockEnd)
      {
         int minToStart = (int)((g_maint.windows[i].startTime - now) / 60);
         string timeInfo = "";

         if(now < g_maint.windows[i].startTime)
            timeInfo = IntegerToString(minToStart) + "min before start";
         else if(now <= g_maint.windows[i].endTime)
            timeInfo = "during maintenance";
         else
            timeInfo = "post-maintenance cooldown";

         return "Maintenance: " + g_maint.windows[i].description +
                " (" + timeInfo + ")";
      }
   }

   return "";
}

//+------------------------------------------------------------------+
//| GMT to server time conversion helpers                            |
//+------------------------------------------------------------------+
int GetServerToGMTOffsetSeconds()
{
   return (int)(TimeCurrent() - TimeGMT());
}

datetime MakeServerTimeFromGMT(const MqlDateTime &gmtDt)
{
   MqlDateTime serverDt = gmtDt;
   datetime gmtTime = StructToTime(serverDt);
   return gmtTime + GetServerToGMTOffsetSeconds();
}

//+------------------------------------------------------------------+
//| Check if a future maintenance window exists by description       |
//+------------------------------------------------------------------+
bool HasFutureMaintenanceByDescription(const string description)
{
   datetime now = TimeCurrent();
   for(int i = 0; i < g_maint.count; i++)
   {
      if(g_maint.windows[i].description == description && g_maint.windows[i].endTime > now)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Dynamic broker news/maintenance API scan                         |
//| Scans MT5 calendar for maintenance-type events matching symbol   |
//| currency and adds them automatically                             |
//+------------------------------------------------------------------+
bool LoadMaintenanceFromBrokerCalendar(const string symbol,
                                       int lookAheadHours = 48)
{
   string base    = StringSubstr(symbol, 0, 3);
   string quote   = StringSubstr(symbol, 3, 3);
   StringToUpper(base);
   StringToUpper(quote);

   datetime fromTime = TimeCurrent();
   datetime toTime   = fromTime + lookAheadHours * 3600;

   MqlCalendarValue calValues[];
   int total = CalendarValueHistory(calValues, fromTime, toTime, "", "");
   if(total <= 0)
      return false;

   bool added = false;
   for(int i = 0; i < total; i++)
   {
      MqlCalendarEvent ev;
      if(!CalendarEventById(calValues[i].event_id, ev))
         continue;

      // Check for maintenance/outage keywords
      string name = ev.name;
      StringToUpper(name);
      bool isMaint = (StringFind(name, "MAINTENANCE") >= 0 ||
                      StringFind(name, "OUTAGE")      >= 0 ||
                      StringFind(name, "SHUTDOWN")    >= 0 ||
                      StringFind(name, "DOWNTIME")    >= 0 ||
                      StringFind(name, "HALT")        >= 0);
      if(!isMaint)
         continue;

      // Currency is on MqlCalendarCountry, not MqlCalendarEvent
      MqlCalendarCountry country;
      string evCur = "";
      if(CalendarCountryById(ev.country_id, country))
         evCur = country.currency;
      StringToUpper(evCur);
      bool matches = (evCur == base || evCur == quote || evCur == "ALL" || evCur == "");
      if(!matches)
         continue;

      // Use event time ± buffer as maintenance window
      datetime maintStart = calValues[i].time - 15 * 60;   // 15 min pre-buffer
      datetime maintEnd   = calValues[i].time + 90 * 60;   // 90 min window

      if(AddMaintenanceWindow(symbol, maintStart, maintEnd,
                              "Calendar: " + ev.name))
         added = true;
   }

   if(added)
      Print("[MAINT] Loaded broker calendar maintenance windows for ", symbol);

   return added;
}

//+------------------------------------------------------------------+
//| Auto-refresh broker calendar (call from OnTick, hourly)         |
//+------------------------------------------------------------------+
void RefreshMaintenanceFromCalendar(const string symbol,
                                    int lookAheadHours = 48)
{
   static datetime lastCalRefresh = 0;
   datetime now = TimeCurrent();

   if(lastCalRefresh != 0 && (now - lastCalRefresh) < 3600)
      return;

   lastCalRefresh = now;
   PurgeOldMaintenanceWindows();
   LoadMaintenanceFromBrokerCalendar(symbol, lookAheadHours);
}

//+------------------------------------------------------------------+
//| Load Deriv recurring weekly maintenance (synthetics)             |
//| Deriv typically has maintenance on Sundays ~06:00-09:00 GMT      |
//| Converts GMT to broker server time automatically                 |
//+------------------------------------------------------------------+
void LoadDerivWeeklyMaintenance(int maintDayOfWeek = 0,
                                int startHourGMT   = 6,
                                int endHourGMT     = 9)
{
   datetime now = TimeCurrent();

   for(int d = 0; d < 14; d++)
   {
      datetime checkDay = now + d * 86400;
      MqlDateTime ddt;
      TimeToStruct(checkDay, ddt);

      if(ddt.day_of_week != maintDayOfWeek)
         continue;

      MqlDateTime startGmt;
      TimeToStruct(TimeGMT() + d * 86400, startGmt);
      startGmt.hour = startHourGMT;
      startGmt.min  = 0;
      startGmt.sec  = 0;

      MqlDateTime endGmt = startGmt;
      endGmt.hour = endHourGMT;
      if(endHourGMT <= startHourGMT)
      {
         datetime tmp = StructToTime(endGmt) + 86400;
         TimeToStruct(tmp, endGmt);
      }

      datetime maintStartServer = MakeServerTimeFromGMT(startGmt);
      datetime maintEndServer   = MakeServerTimeFromGMT(endGmt);

      if(maintEndServer <= now)
         continue;

      AddMaintenanceWindow("ALL", maintStartServer, maintEndServer,
                           "Deriv weekly maintenance");
      break;
   }
}

//+------------------------------------------------------------------+
//| Auto-refresh Deriv weekly maintenance (call from OnTick)         |
//+------------------------------------------------------------------+
void EnsureDerivWeeklyMaintenanceLoaded(int maintDayOfWeek = 0,
                                        int startHourGMT   = 6,
                                        int endHourGMT     = 9)
{
   datetime now = TimeCurrent();
   if(g_maint.lastAutoRefresh != 0 && (now - g_maint.lastAutoRefresh) < 3600)
      return;

   g_maint.lastAutoRefresh = now;
   PurgeOldMaintenanceWindows();

   if(!HasFutureMaintenanceByDescription("Deriv weekly maintenance"))
      LoadDerivWeeklyMaintenance(maintDayOfWeek, startHourGMT, endHourGMT);
}

#endif // MAINTENANCE_FILTER_MQH
