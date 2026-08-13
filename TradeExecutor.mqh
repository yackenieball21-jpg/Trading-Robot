//+------------------------------------------------------------------+
//|                                               TradeExecutor.mqh |
//|  ACTUAL TRADE EXECUTION                                          |
//|  - Lot size CALCULATION (uses RiskManager limits)                |
//|  - Order sending to broker                                       |
//|  - Retcode handling and retries                                  |
//|  - CSV logging of trades                                         |
//|  - Position opening with SL/TP                                   |
//|                                                                   |
//|  Uses RiskManager for validation, not vice versa                 |
//|  v5.13 — SL based on nearest S/R zone, 1:2 RR                    |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef TRADE_EXECUTOR_MQH
#define TRADE_EXECUTOR_MQH

#include <Trade\Trade.mqh>
#include "SymbolProfiler.mqh"
#include "MarketStateManager.mqh"
#include "IndicatorManager.mqh"
#include "RiskManager.mqh"

//+------------------------------------------------------------------+
//| Last trade details for AI outcome logging                        |
//+------------------------------------------------------------------+
struct LastTradeDetails
{
   bool   valid;
   double entry;
   double sl;
   double tp;
   double lots;
   ulong  ticket;
   string direction;
};

LastTradeDetails g_lastTrade;

//+------------------------------------------------------------------+
//| Lot sizing mode - set by MY BOT.mq5                              |
//+------------------------------------------------------------------+
double g_equityPercentForLots = 1.0;   // Legacy fallback - primary sizing is now CalcLotByRisk

//+------------------------------------------------------------------+
//| Normalize lots down to step (never round up)                     |
//+------------------------------------------------------------------+
double NormalizeLotsDown(double lots, double step)
{
   if(step <= 0.0) return lots;
   return MathFloor((lots + 1e-12) / step) * step;
}

//+------------------------------------------------------------------+
//| Calculate lot size by sizing mode (risk, equity notional, margin)  |
//+------------------------------------------------------------------+
double CalcLotBySizingMode(ENUM_ORDER_TYPE orderType, double entryPrice, double stopLossPrice,
                           double riskPct, const SymbolProfile &prof,
                           double aiRiskMult, bool aiActive)
{
   SetLastLotBlockReason("");

   double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
   double volMin   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volStep  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double price    = (orderType == ORDER_TYPE_BUY ? ask : bid);

   if(equity <= 0 || volMin <= 0 || volMax <= 0 || volStep <= 0 || contract <= 0 || price <= 0)
   {
      SetLastLotBlockReason("INVALID_SYMBOL_DATA | equity=" + DoubleToString(equity, 2) +
                            " volMin=" + DoubleToString(volMin, 4) +
                            " volMax=" + DoubleToString(volMax, 4) +
                            " volStep=" + DoubleToString(volStep, 4) +
                            " contract=" + DoubleToString(contract, 0) +
                            " price=" + DoubleToString(price, prof.digits));
      Print("LOT BLOCKED: Invalid symbol data");
      return 0.0;
   }

   Print("[LOT_MODE] mode=", EnumToString(LotSizingMode));

   // RISK MODE (SIZE_BY_RISK)
   if(LotSizingMode == SIZE_BY_RISK)
   {
      // Ensure min lot fallback is enabled for risk mode
      bool originalFallbackState = g_minLotFallbackEnabled;
      g_minLotFallbackEnabled = UseMinLotFallback;

      double lots = CalcLotByRisk(orderType, entryPrice, stopLossPrice, riskPct, prof, aiRiskMult, aiActive);

      // Restore original state
      g_minLotFallbackEnabled = originalFallbackState;

      Print("[LOT_FINAL] finalLots=", DoubleToString(lots, 4));
      return lots;
   }

   // EQUITY NOTIONAL MODE (SIZE_BY_EQUITY_NOTIONAL)
   if(LotSizingMode == SIZE_BY_EQUITY_NOTIONAL)
   {
      double targetNotional = equity * (EquityPerTradePercent / 100.0);
      double rawLots = targetNotional / (contract * price);

      Print("[LOT_EQUITY] mode=NOTIONAL equity=", DoubleToString(equity, 2),
            " targetPct=", DoubleToString(EquityPerTradePercent, 2),
            " targetNotional=", DoubleToString(targetNotional, 2),
            " rawLots=", DoubleToString(rawLots, 6));

      double lots = NormalizeLotsDown(rawLots, volStep);

      if(lots < volMin)
      {
         if(BlockTradeIfBelowMinLot)
         {
            PrintFormat("LOT BLOCKED: equity-notional size below broker minimum | mode=%d equity=%.2f targetPct=%.2f rawLots=%.6f volMin=%.2f",
                        (int)LotSizingMode, equity, EquityPerTradePercent, rawLots, volMin);
            SetLastLotBlockReason("BELOW_MIN_LOT | mode=EQUITY_NOTIONAL");
            return 0.0;
         }

         // Make the override explicit so the user knows it is no longer true notional sizing.
         lots = volMin;
         PrintFormat("LOT OVERRIDE: broker min lot replaced true equity-notional size | mode=%d equity=%.2f targetPct=%.2f rawLots=%.6f forcedLots=%.2f",
                     (int)LotSizingMode, equity, EquityPerTradePercent, rawLots, lots);
      }

      if(lots > volMax) lots = volMax;

      Print("[LOT_FINAL] finalLots=", DoubleToString(lots, 4));
      return lots;
   }

   // EQUITY MARGIN MODE (SIZE_BY_EQUITY_MARGIN)
   if(LotSizingMode == SIZE_BY_EQUITY_MARGIN)
   {
      double targetMargin = equity * (EquityPerTradePercent / 100.0);
      double marginPerLot = 0.0;

      if(!OrderCalcMargin(orderType, _Symbol, 1.0, price, marginPerLot) || marginPerLot <= 0.0)
      {
         Print("LOT BLOCKED: could not calculate margin per lot");
         SetLastLotBlockReason("MARGIN_CALC_FAILED | mode=EQUITY_MARGIN");
         return 0.0;
      }

      double rawLots = targetMargin / marginPerLot;

      Print("[LOT_EQUITY] mode=MARGIN equity=", DoubleToString(equity, 2),
            " targetPct=", DoubleToString(EquityPerTradePercent, 2),
            " targetMargin=", DoubleToString(targetMargin, 2),
            " marginPerLot=", DoubleToString(marginPerLot, 2),
            " rawLots=", DoubleToString(rawLots, 6));

      double lots = NormalizeLotsDown(rawLots, volStep);

      if(lots < volMin)
      {
         if(BlockTradeIfBelowMinLot)
         {
            PrintFormat("LOT BLOCKED: equity-based size below broker minimum | mode=%d equity=%.2f targetPct=%.2f rawLots=%.6f volMin=%.2f",
                        (int)LotSizingMode, equity, EquityPerTradePercent, rawLots, volMin);
            SetLastLotBlockReason("BELOW_MIN_LOT | mode=EQUITY_MARGIN");
            return 0.0;
         }
         else
         {
            lots = volMin;
            PrintFormat("LOT OVERRIDE: using broker min lot | mode=%d equity=%.2f targetPct=%.2f rawLots=%.6f forcedLots=%.2f",
                        (int)LotSizingMode, equity, EquityPerTradePercent, rawLots, lots);
         }
      }

      if(lots > volMax) lots = volMax;

      Print("[LOT_FINAL] finalLots=", DoubleToString(lots, 4));
      return lots;
   }

   // FIXED LOT MODE (SIZE_BY_FIXED_LOT)
   if(LotSizingMode == SIZE_BY_FIXED_LOT)
   {
      // Pick the right fixed lot for this instrument class
      double lots = FixedLotSize;

      switch(prof.classEnum)
      {
         case INST_XAUUSD:
         case INST_XAGUSD:
            lots = FixedLotSizeGold;
            break;
         case INST_SYNTH_VOL10:
            lots = FixedLotSizeVol10;
            break;
         case INST_SYNTH_VOL25:
            lots = FixedLotSizeVol25;
            break;
         case INST_SYNTH_VOL50:
            lots = FixedLotSizeVol50;
            break;
         case INST_SYNTH_VOL75:
            lots = FixedLotSizeVol75;
            break;
         case INST_SYNTH_VOL100:
            lots = FixedLotSizeVol100;
            break;
         case INST_SYNTH_BOOM:
            lots = FixedLotSizeBoom;
            break;
         case INST_SYNTH_CRASH:
            lots = FixedLotSizeCrash;
            break;
         case INST_SYNTH_STEP:
            lots = FixedLotSizeStep;
            break;
         case INST_SYNTH_JUMP:
            lots = FixedLotSizeJump;
            break;
         case INST_SYNTH_VOL:
            lots = FixedLotSizeVol75;
            break;
         case INST_INDEX_US:
         case INST_INDEX_EU:
            lots = FixedLotSizeIndex;
            break;
         case INST_CRYPTO:
            lots = FixedLotSizeCrypto;
            break;
         default:
            lots = FixedLotSize;
            break;
      }

      if(lots < volMin)
      {
         Print("LOT WARNING: FixedLotSize (", DoubleToString(lots, 4),
               ") below broker min (", DoubleToString(volMin, 4),
               ") — using broker minimum");
         lots = volMin;
      }
      if(lots > volMax)
      {
         Print("LOT WARNING: FixedLotSize (", DoubleToString(lots, 4),
               ") above broker max (", DoubleToString(volMax, 4),
               ") — capped to broker maximum");
         lots = volMax;
      }

      lots = NormalizeLotsDown(lots, volStep);

      Print("[LOT_FINAL] mode=FIXED_LOT class=", prof.instrumentClass,
            " finalLots=", DoubleToString(lots, 4));
      return lots;
   }

   // Unknown mode
   Print("LOT BLOCKED: Unknown sizing mode");
   SetLastLotBlockReason("UNKNOWN_SIZING_MODE");
   return 0.0;
}

//+------------------------------------------------------------------+
//| Trade log CSV file                                               |
//+------------------------------------------------------------------+
string g_tradeLogFile = "";

//+------------------------------------------------------------------+
//| Initialize trade log                                             |
//+------------------------------------------------------------------+
void InitTradeLog()
{
   g_tradeLogFile = "trade_log_" + _Symbol + ".csv";
   int fh = FileOpen(g_tradeLogFile, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh != INVALID_HANDLE)
   {
      if(FileSize(fh) == 0)
      {
         string header = "time,symbol,direction,entry,sl,tp,lots,spread_pts,result,ticket,comment\n";
         FileWriteString(fh, header);
      }
      FileClose(fh);
   }
}

//+------------------------------------------------------------------+
//| Log trade to CSV                                                 |
//+------------------------------------------------------------------+
void LogTradeToCSV(string direction, double entry, double sl, double tp,
                   double lots, double spreadPts, string result, ulong ticket, string comment)
{
   if(g_tradeLogFile == "") return;

   int fh = FileOpen(g_tradeLogFile, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
   if(fh == INVALID_HANDLE) return;

   FileSeek(fh, 0, SEEK_END);

   string line = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "," +
                 _Symbol + "," +
                 direction + "," +
                 DoubleToString(entry, _Digits) + "," +
                 DoubleToString(sl, _Digits) + "," +
                 DoubleToString(tp, _Digits) + "," +
                 DoubleToString(lots, 4) + "," +
                 DoubleToString(spreadPts, 1) + "," +
                 result + "," +
                 IntegerToString(ticket) + "," +
                 comment;

   FileWriteString(fh, line + "\n");
   FileClose(fh);
}

//+------------------------------------------------------------------+
//| Get retcode description                                          |
//+------------------------------------------------------------------+
string GetRetcodeDescription(uint retcode)
{
   switch(retcode)
   {
      case TRADE_RETCODE_REQUOTE:        return "REQUOTE";
      case TRADE_RETCODE_REJECT:         return "REJECTED";
      case TRADE_RETCODE_CANCEL:         return "CANCELED";
      case TRADE_RETCODE_PLACED:         return "PLACED";
      case TRADE_RETCODE_DONE:           return "DONE";
      case TRADE_RETCODE_DONE_PARTIAL:   return "PARTIAL";
      case TRADE_RETCODE_ERROR:          return "ERROR";
      case TRADE_RETCODE_TIMEOUT:        return "TIMEOUT";
      case TRADE_RETCODE_INVALID:        return "INVALID";
      case TRADE_RETCODE_INVALID_VOLUME: return "INVALID_VOLUME";
      case TRADE_RETCODE_INVALID_PRICE:  return "INVALID_PRICE";
      case TRADE_RETCODE_INVALID_STOPS:  return "INVALID_STOPS";
      case TRADE_RETCODE_TRADE_DISABLED: return "TRADE_DISABLED";
      case TRADE_RETCODE_MARKET_CLOSED:  return "MARKET_CLOSED";
      case TRADE_RETCODE_NO_MONEY:       return "NO_MONEY";
      case TRADE_RETCODE_PRICE_CHANGED:  return "PRICE_CHANGED";
      case TRADE_RETCODE_PRICE_OFF:      return "PRICE_OFF";
      case TRADE_RETCODE_INVALID_EXPIRATION: return "INVALID_EXPIRATION";
      case TRADE_RETCODE_ORDER_CHANGED:  return "ORDER_CHANGED";
      case TRADE_RETCODE_TOO_MANY_REQUESTS: return "TOO_MANY_REQUESTS";
      case TRADE_RETCODE_NO_CHANGES:     return "NO_CHANGES";
      case TRADE_RETCODE_SERVER_DISABLES_AT: return "SERVER_DISABLES_AT";
      case TRADE_RETCODE_CLIENT_DISABLES_AT: return "CLIENT_DISABLES_AT";
      case TRADE_RETCODE_LOCKED:         return "LOCKED";
      case TRADE_RETCODE_FROZEN:         return "FROZEN";
      case TRADE_RETCODE_INVALID_FILL:   return "INVALID_FILL";
      case TRADE_RETCODE_CONNECTION:     return "CONNECTION";
      case TRADE_RETCODE_ONLY_REAL:      return "ONLY_REAL";
      case TRADE_RETCODE_LIMIT_ORDERS:   return "LIMIT_ORDERS";
      case TRADE_RETCODE_LIMIT_VOLUME:   return "LIMIT_VOLUME";
      case TRADE_RETCODE_INVALID_ORDER:  return "INVALID_ORDER";
      case TRADE_RETCODE_POSITION_CLOSED: return "POSITION_CLOSED";
      default: return "UNKNOWN(" + IntegerToString(retcode) + ")";
   }
}

//+------------------------------------------------------------------+
//| Check if retcode is retriable                                    |
//+------------------------------------------------------------------+
bool IsRetriableRetcode(uint retcode)
{
   return (retcode == TRADE_RETCODE_REQUOTE ||
           retcode == TRADE_RETCODE_PRICE_CHANGED ||
           retcode == TRADE_RETCODE_PRICE_OFF ||
           retcode == TRADE_RETCODE_CONNECTION ||
           retcode == TRADE_RETCODE_TIMEOUT);
}

//+------------------------------------------------------------------+
//| Determine best filling mode for preflight from symbol profile    |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetPreflightFillingMode(const SymbolProfile &prof)
{
   long fm = prof.fillingMode;

   if((fm & SYMBOL_FILLING_FOK) != 0)
      return ORDER_FILLING_FOK;
   else if((fm & SYMBOL_FILLING_IOC) != 0)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Pre-flight order check                                           |
//+------------------------------------------------------------------+
bool PreflightOrderCheck(ENUM_ORDER_TYPE type, double volume, double price,
                         double sl, double tp, const SymbolProfile &prof,
                         string preflightComment = "PREFLIGHT")
{
   MqlTradeRequest request = {};
   MqlTradeCheckResult checkResult = {};

   request.action       = TRADE_ACTION_DEAL;
   request.symbol       = _Symbol;
   request.volume       = volume;
   request.type         = type;
   request.price        = price;
   request.sl           = sl;
   request.tp           = tp;
   request.deviation    = 30;
   request.magic        = 0;
   request.comment      = preflightComment;
   request.type_filling = GetPreflightFillingMode(prof);
   request.type_time    = ORDER_TIME_GTC;

   if(!OrderCheck(request, checkResult))
   {
      Print("PREFLIGHT FAIL: retcode=", checkResult.retcode,
            " (", GetRetcodeDescription(checkResult.retcode), ")",
            " margin_free=", DoubleToString(checkResult.margin_free, 2),
            " balance=", DoubleToString(checkResult.balance, 2),
            " comment=", preflightComment);
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Send BUY order with full safety checks                           |
//+------------------------------------------------------------------+
bool SendBuy(CTrade &trade, const SymbolProfile &prof, MarketState &ms,
             const IndicatorState &ind, double riskPct, double rewardRisk,
             int swingLookback, double maxSpreadMult, double minSLOverride,
             double aiStopMult, double aiRiskMult, bool aiActive,
             int maxBrokerErrors, bool enableNotifications,
             string tradeComment = "MY BOT BUY",
             double overrideSL = 0.0,
             double overrideTP = 0.0)
{
   g_lastTrade.valid = false;

   // 1. Refresh market state with fresh tick
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0)
   {
      Print("BUY BLOCKED: Cannot get fresh tick");
      return false;
   }

   // Check tick freshness (warn but don't block)
   datetime tickAge = TimeCurrent() - tick.time;
   bool isTester = MQLInfoInteger(MQL_TESTER);
   if(!isTester && tickAge > MAX_TICK_AGE_SECONDS)
   {
      Print("BUY WARNING: Stale tick, age=", tickAge, "s - continuing with caution");
   }

   // Update market state with fresh prices
   ms.bid = tick.bid;
   ms.ask = tick.ask;
   ms.spreadPoints = (tick.ask - tick.bid) / prof.point;
   ms.tickTime = tick.time;
   ms.tickFresh = true;

   // 2. Check spread again with fresh data
   if(!IsSpreadAcceptable(ms, prof, maxSpreadMult))
   {
      Print("BUY BLOCKED: Spread too wide after refresh: ", DoubleToString(ms.spreadPoints, 1), " pts");
      return false;
   }

   // 3. Calculate entry from fresh ask
   double entry = NormalizePrice(ms.ask, prof.digits);

   // 4. Calculate SL: use override (zone sweep SL) if provided, else structure + ATR
   double sl = 0.0;
   if(overrideSL > 0.0)
   {
      sl = NormalizePrice(overrideSL, prof.digits);
      Print("BUY SL: using zone sweep override SL = ", DoubleToString(sl, prof.digits));
   }
   else
   {
      sl = GetBuyStopLoss(entry, ind, prof, swingLookback, minSLOverride);
   }
   if(sl <= 0)
   {
      Print("BUY SKIPPED: No valid structure or ATR for stop-loss");
      return false;
   }

   // 5. Apply AI stop multiplier if active (never modify explicit override SL)
   if(aiActive && aiStopMult > 0 && aiStopMult != 1.0 && overrideSL <= 0.0)
   {
      double slDist = entry - sl;
      sl = NormalizePrice(entry - slDist * aiStopMult, prof.digits);
      if(!ValidateAIAdjustedStop(ORDER_TYPE_BUY, entry, sl, prof, minSLOverride))
      {
         Print("BUY BLOCKED: AI-adjusted SL invalid");
         return false;
      }
   }

   // 6. Calculate TP: use zone-target override when provided, else RR fallback
   double tp = 0.0;
   if(overrideTP > 0.0)
   {
      tp = NormalizePrice(overrideTP, prof.digits);
      Print("BUY TP: zone-target override tp=", DoubleToString(tp, prof.digits));
   }
   else
   {
      tp = GetTakeProfitFromRR(ORDER_TYPE_BUY, entry, sl, rewardRisk, prof.digits);
   }

   // 6b. No-fixed-TP for trend runners and trend continuation
   if(g_trendTradesUseNoFixedTP && (StringFind(tradeComment, "TREND_RUNNER") >= 0 || StringFind(tradeComment, "TREND_CONTINUATION") >= 0))
   {
      tp = 0.0;
      Print("[TREND_RUNNER] tp_mode=NONE side=BUY comment=", tradeComment);
   }

   // 6c. Auto-widen SL if too close (don't waste confirmed setups)
   double minDistBuy = GetMinSLDistance(prof, minSLOverride);
   if(sl > 0 && sl < entry && (entry - sl) < minDistBuy)
   {
      double origSL = sl;
      sl = NormalizePrice(entry - minDistBuy - prof.point, prof.digits);
      Print("BUY SL: auto-widened from ", DoubleToString(origSL, prof.digits),
            " to ", DoubleToString(sl, prof.digits),
            " (minDist=", DoubleToString(minDistBuy, prof.digits), ")");
      // Recalculate RR-based TP with widened SL (zone-target TP stays unchanged)
      if(overrideTP <= 0.0 && tp > 0.0)
         tp = GetTakeProfitFromRR(ORDER_TYPE_BUY, entry, sl, rewardRisk, prof.digits);
   }

   // 7. Validate stops
   if(!ValidateStopsAgainstStopsLevel(ORDER_TYPE_BUY, entry, sl, tp, prof, minSLOverride))
   {
      Print("BUY BLOCKED: Stops validation failed");
      return false;
   }

   // 8. Calculate lot size (by selected sizing mode)
   double lots = CalcLotBySizingMode(ORDER_TYPE_BUY, entry, sl, riskPct, prof, aiRiskMult, aiActive);
   if(lots <= 0)
   {
      Print("BUY BLOCKED: ", GetLastLotBlockReason());
      return false;
   }

   // 9. Set filling mode
   ValidateOrderFillingMode(trade, prof);

   // 10. Preflight check
   if(!PreflightOrderCheck(ORDER_TYPE_BUY, lots, entry, sl, tp, prof, tradeComment))
   {
      Print("BUY BLOCKED: Preflight check failed");
      RecordBrokerError(maxBrokerErrors);
      LogTradeToCSV("BUY", entry, sl, tp, lots, ms.spreadPoints, "PREFLIGHT_FAIL", 0, "OrderCheck failed");
      return false;
   }

   // 11. Execute with retry
   int maxRetries = 3;
   for(int attempt = 1; attempt <= maxRetries; attempt++)
   {
      // Re-fetch tick and RECALCULATE everything for each retry
      if(attempt > 1)
      {
         Sleep(500);
         if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0)
         {
            Print("BUY RETRY ", attempt, ": Cannot get tick");
            continue;
         }
         entry = NormalizePrice(tick.ask, prof.digits);

         if(overrideSL > 0.0)
         {
            sl = NormalizePrice(overrideSL, prof.digits);
         }
         else
         {
            sl = GetBuyStopLoss(entry, ind, prof, swingLookback, minSLOverride);
         }

         if(aiActive && aiStopMult > 0 && aiStopMult != 1.0 && overrideSL <= 0.0)
         {
            double slDist2 = entry - sl;
            sl = NormalizePrice(entry - slDist2 * aiStopMult, prof.digits);
         }

         if(overrideTP > 0.0)
            tp = NormalizePrice(overrideTP, prof.digits);
         else
            tp = GetTakeProfitFromRR(ORDER_TYPE_BUY, entry, sl, rewardRisk, prof.digits);

         // Re-apply no-fixed-TP rule AFTER recalculation — trend runners/continuation must stay TP-free on retries
         if(g_trendTradesUseNoFixedTP && (StringFind(tradeComment, "TREND_RUNNER") >= 0 || StringFind(tradeComment, "TREND_CONTINUATION") >= 0))
         {
            tp = 0.0;
            Print("[TREND_RUNNER] retry tp_mode=NONE side=BUY attempt=", attempt, " comment=", tradeComment);
         }

         // RECALCULATE LOT SIZE (by selected sizing mode)
         lots = CalcLotBySizingMode(ORDER_TYPE_BUY, entry, sl, riskPct, prof, aiRiskMult, aiActive);
         if(lots <= 0)
         {
            Print("BUY RETRY ", attempt, ": Lot recalc returned 0 - abort retry");
            break;
         }

         // RE-RUN PREFLIGHT CHECK with new values
         if(!PreflightOrderCheck(ORDER_TYPE_BUY, lots, entry, sl, tp, prof, tradeComment))
         {
            Print("BUY RETRY ", attempt, ": Preflight failed - abort retry");
            break;
         }

         Print("[RETRY_RECALC] attempt=", attempt, " entry=", DoubleToString(entry, prof.digits),
               " sl=", DoubleToString(sl, prof.digits), " tp=", DoubleToString(tp, prof.digits),
               " lots=", DoubleToString(lots, 4));
      }

      bool result = trade.Buy(lots, _Symbol, entry, sl, tp, tradeComment);
      uint retcode = trade.ResultRetcode();

      if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         ulong ticket = trade.ResultDeal();
         double fillPrice = trade.ResultPrice();
         Print("BUY SUCCESS: ticket=", ticket, " price=", DoubleToString(fillPrice, prof.digits),
               " lots=", DoubleToString(lots, 4), " sl=", DoubleToString(sl, prof.digits),
               " tp=", DoubleToString(tp, prof.digits));

         g_lastTrade.valid     = true;
         g_lastTrade.entry     = fillPrice;
         g_lastTrade.sl        = sl;
         g_lastTrade.tp        = tp;
         g_lastTrade.lots      = lots;
         g_lastTrade.ticket    = ticket;
         g_lastTrade.direction = "BUY";

         LogTradeToCSV("BUY", fillPrice, sl, tp, lots, ms.spreadPoints, "SUCCESS", ticket, "");

         if(enableNotifications)
            SendNotification("BUY opened: " + _Symbol + " @ " + DoubleToString(fillPrice, prof.digits));

         return true;
      }

      Print("BUY ATTEMPT ", attempt, " FAILED: retcode=", retcode,
            " (", GetRetcodeDescription(retcode), ")");

      if(!IsRetriableRetcode(retcode))
      {
         RecordBrokerError(maxBrokerErrors);
         LogTradeToCSV("BUY", entry, sl, tp, lots, ms.spreadPoints, "FAIL", 0, GetRetcodeDescription(retcode));
         return false;
      }
   }

   Print("BUY FAILED: All retries exhausted");
   RecordBrokerError(maxBrokerErrors);
   LogTradeToCSV("BUY", entry, sl, tp, lots, ms.spreadPoints, "RETRY_EXHAUSTED", 0, "");
   return false;
}

//+------------------------------------------------------------------+
//| Send SELL order with full safety checks                          |
//+------------------------------------------------------------------+
bool SendSell(CTrade &trade, const SymbolProfile &prof, MarketState &ms,
              const IndicatorState &ind, double riskPct, double rewardRisk,
              int swingLookback, double maxSpreadMult, double minSLOverride,
              double aiStopMult, double aiRiskMult, bool aiActive,
              int maxBrokerErrors, bool enableNotifications,
              string tradeComment = "MY BOT SELL",
              double overrideSL = 0.0,
              double overrideTP = 0.0)
{
   g_lastTrade.valid = false;

   // 1. Refresh market state with fresh tick
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0)
   {
      Print("SELL BLOCKED: Cannot get fresh tick");
      return false;
   }

   // Check tick freshness (warn but don't block)
   datetime tickAge = TimeCurrent() - tick.time;
   bool isTester = MQLInfoInteger(MQL_TESTER);
   if(!isTester && tickAge > MAX_TICK_AGE_SECONDS)
   {
      Print("SELL WARNING: Stale tick, age=", tickAge, "s - continuing with caution");
   }

   // Update market state with fresh prices
   ms.bid = tick.bid;
   ms.ask = tick.ask;
   ms.spreadPoints = (tick.ask - tick.bid) / prof.point;
   ms.tickTime = tick.time;
   ms.tickFresh = true;

   // 2. Check spread again with fresh data
   if(!IsSpreadAcceptable(ms, prof, maxSpreadMult))
   {
      Print("SELL BLOCKED: Spread too wide after refresh: ", DoubleToString(ms.spreadPoints, 1), " pts");
      return false;
   }

   // 3. Calculate entry from fresh bid
   double entry = NormalizePrice(ms.bid, prof.digits);

   // 4. Calculate SL: use override (zone sweep SL) if provided, else structure + ATR
   double sl = 0.0;
   if(overrideSL > 0.0)
   {
      sl = NormalizePrice(overrideSL, prof.digits);
      Print("SELL SL: using zone sweep override SL = ", DoubleToString(sl, prof.digits));
   }
   else
   {
      sl = GetSellStopLoss(entry, ind, prof, swingLookback, minSLOverride);
   }
   if(sl <= 0)
   {
      Print("SELL SKIPPED: No valid structure or ATR for stop-loss");
      return false;
   }

   // 5. Apply AI stop multiplier if active (never modify explicit override SL)
   if(aiActive && aiStopMult > 0 && aiStopMult != 1.0 && overrideSL <= 0.0)
   {
      double slDist = sl - entry;
      sl = NormalizePrice(entry + slDist * aiStopMult, prof.digits);
      if(!ValidateAIAdjustedStop(ORDER_TYPE_SELL, entry, sl, prof, minSLOverride))
      {
         Print("SELL BLOCKED: AI-adjusted SL invalid");
         return false;
      }
   }

   // 6. Calculate TP: use zone-target override when provided, else RR fallback
   double tp = 0.0;
   if(overrideTP > 0.0)
   {
      tp = NormalizePrice(overrideTP, prof.digits);
      Print("SELL TP: zone-target override tp=", DoubleToString(tp, prof.digits));
   }
   else
   {
      tp = GetTakeProfitFromRR(ORDER_TYPE_SELL, entry, sl, rewardRisk, prof.digits);
   }

   // 6b. No-fixed-TP for trend runners and trend continuation
   if(g_trendTradesUseNoFixedTP && (StringFind(tradeComment, "TREND_RUNNER") >= 0 || StringFind(tradeComment, "TREND_CONTINUATION") >= 0))
   {
      tp = 0.0;
      Print("[TREND_RUNNER] tp_mode=NONE side=SELL comment=", tradeComment);
   }

   // 6c. Auto-widen SL if too close (don't waste confirmed setups)
   double minDistSell = GetMinSLDistance(prof, minSLOverride);
   if(sl > 0 && sl > entry && (sl - entry) < minDistSell)
   {
      double origSLs = sl;
      sl = NormalizePrice(entry + minDistSell + prof.point, prof.digits);
      Print("SELL SL: auto-widened from ", DoubleToString(origSLs, prof.digits),
            " to ", DoubleToString(sl, prof.digits),
            " (minDist=", DoubleToString(minDistSell, prof.digits), ")");
      // Recalculate RR-based TP with widened SL (zone-target TP stays unchanged)
      if(overrideTP <= 0.0 && tp > 0.0)
         tp = GetTakeProfitFromRR(ORDER_TYPE_SELL, entry, sl, rewardRisk, prof.digits);
   }

   // 7. Validate stops
   if(!ValidateStopsAgainstStopsLevel(ORDER_TYPE_SELL, entry, sl, tp, prof, minSLOverride))
   {
      Print("SELL BLOCKED: Stops validation failed");
      return false;
   }

   // 8. Calculate lot size (by selected sizing mode)
   double lots = CalcLotBySizingMode(ORDER_TYPE_SELL, entry, sl, riskPct, prof, aiRiskMult, aiActive);
   if(lots <= 0)
   {
      Print("SELL BLOCKED: ", GetLastLotBlockReason());
      return false;
   }

   // 9. Set filling mode
   ValidateOrderFillingMode(trade, prof);

   // 10. Preflight check
   if(!PreflightOrderCheck(ORDER_TYPE_SELL, lots, entry, sl, tp, prof, tradeComment))
   {
      Print("SELL BLOCKED: Preflight check failed");
      RecordBrokerError(maxBrokerErrors);
      LogTradeToCSV("SELL", entry, sl, tp, lots, ms.spreadPoints, "PREFLIGHT_FAIL", 0, "OrderCheck failed");
      return false;
   }

   // 11. Execute with retry
   int maxRetries = 3;
   for(int attempt = 1; attempt <= maxRetries; attempt++)
   {
      // Re-fetch tick and RECALCULATE everything for each retry
      if(attempt > 1)
      {
         Sleep(500);
         if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0)
         {
            Print("SELL RETRY ", attempt, ": Cannot get tick");
            continue;
         }
         entry = NormalizePrice(tick.bid, prof.digits);

         if(overrideSL > 0.0)
         {
            sl = NormalizePrice(overrideSL, prof.digits);
         }
         else
         {
            sl = GetSellStopLoss(entry, ind, prof, swingLookback, minSLOverride);
         }

         if(aiActive && aiStopMult > 0 && aiStopMult != 1.0 && overrideSL <= 0.0)
         {
            double slDist2 = sl - entry;
            sl = NormalizePrice(entry + slDist2 * aiStopMult, prof.digits);
         }

         if(overrideTP > 0.0)
            tp = NormalizePrice(overrideTP, prof.digits);
         else
            tp = GetTakeProfitFromRR(ORDER_TYPE_SELL, entry, sl, rewardRisk, prof.digits);

         // Re-apply no-fixed-TP rule AFTER recalculation — trend runners/continuation must stay TP-free on retries
         if(g_trendTradesUseNoFixedTP && (StringFind(tradeComment, "TREND_RUNNER") >= 0 || StringFind(tradeComment, "TREND_CONTINUATION") >= 0))
         {
            tp = 0.0;
            Print("[TREND_RUNNER] retry tp_mode=NONE side=SELL attempt=", attempt, " comment=", tradeComment);
         }

         // RECALCULATE LOT SIZE (by selected sizing mode)
         lots = CalcLotBySizingMode(ORDER_TYPE_SELL, entry, sl, riskPct, prof, aiRiskMult, aiActive);
         if(lots <= 0)
         {
            Print("SELL RETRY ", attempt, ": Lot recalc returned 0 - abort retry");
            break;
         }

         // RE-RUN PREFLIGHT CHECK with new values
         if(!PreflightOrderCheck(ORDER_TYPE_SELL, lots, entry, sl, tp, prof, tradeComment))
         {
            Print("SELL RETRY ", attempt, ": Preflight failed - abort retry");
            break;
         }

         Print("[RETRY_RECALC] attempt=", attempt, " entry=", DoubleToString(entry, prof.digits),
               " sl=", DoubleToString(sl, prof.digits), " tp=", DoubleToString(tp, prof.digits),
               " lots=", DoubleToString(lots, 4));
      }

      bool result = trade.Sell(lots, _Symbol, entry, sl, tp, tradeComment);
      uint retcode = trade.ResultRetcode();

      if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_DONE_PARTIAL)
      {
         ulong ticket = trade.ResultDeal();
         double fillPrice = trade.ResultPrice();
         Print("SELL SUCCESS: ticket=", ticket, " price=", DoubleToString(fillPrice, prof.digits),
               " lots=", DoubleToString(lots, 4), " sl=", DoubleToString(sl, prof.digits),
               " tp=", DoubleToString(tp, prof.digits));

         g_lastTrade.valid     = true;
         g_lastTrade.entry     = fillPrice;
         g_lastTrade.sl        = sl;
         g_lastTrade.tp        = tp;
         g_lastTrade.lots      = lots;
         g_lastTrade.ticket    = ticket;
         g_lastTrade.direction = "SELL";

         LogTradeToCSV("SELL", fillPrice, sl, tp, lots, ms.spreadPoints, "SUCCESS", ticket, "");

         if(enableNotifications)
            SendNotification("SELL opened: " + _Symbol + " @ " + DoubleToString(fillPrice, prof.digits));

         return true;
      }

      Print("SELL ATTEMPT ", attempt, " FAILED: retcode=", retcode,
            " (", GetRetcodeDescription(retcode), ")");

      if(!IsRetriableRetcode(retcode))
      {
         RecordBrokerError(maxBrokerErrors);
         LogTradeToCSV("SELL", entry, sl, tp, lots, ms.spreadPoints, "FAIL", 0, GetRetcodeDescription(retcode));
         return false;
      }
   }

   Print("SELL FAILED: All retries exhausted");
   RecordBrokerError(maxBrokerErrors);
   LogTradeToCSV("SELL", entry, sl, tp, lots, ms.spreadPoints, "RETRY_EXHAUSTED", 0, "");
   return false;
}

//+------------------------------------------------------------------+
//| Find the most recently opened position for symbol + magic        |
//| Scans open positions and returns the one with the latest open    |
//| time. This is the authoritative way to map a just-executed trade |
//| to its position identifier for setup tracking.                   |
//+------------------------------------------------------------------+
ulong FindLastOpenedPositionId(ulong magic)
{
   ulong bestPosId = 0;
   datetime bestTime = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;

      if(PositionGetInteger(POSITION_MAGIC) != (long)magic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);

      if(openTime > bestTime && posId > 0)
      {
         bestTime = openTime;
         bestPosId = posId;
      }
   }

   return bestPosId;
}

//+------------------------------------------------------------------+
//| Process trade transaction for outcome logging                    |
//+------------------------------------------------------------------+
void ProcessTradeTransaction(const MqlTradeTransaction &trans,
                              const MqlTradeRequest &request,
                              const MqlTradeResult &result,
                              ulong expertMagic, const SymbolProfile &prof,
                              int maxConsecLosses)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

   ulong dealTicket = trans.deal;
   if(dealTicket == 0) return;

   if(!HistoryDealSelect(dealTicket)) return;

   ulong dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(dealMagic != expertMagic) return;

   string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
   if(dealSymbol != _Symbol) return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   double pnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double netPnl = pnl + commission + swap;

   bool isWin = (netPnl > 0);
   RecordTradeResult(isWin, maxConsecLosses);

   Print("DEAL CLOSED: ticket=", dealTicket, " pnl=", DoubleToString(pnl, 2),
         " comm=", DoubleToString(commission, 2), " swap=", DoubleToString(swap, 2),
         " net=", DoubleToString(netPnl, 2), " result=", (isWin ? "WIN" : "LOSS"));

   // Log AI outcome if pending
   if(g_pendingTrade.active)
      LogLabeledOutcome(netPnl, prof);
}

#endif // TRADE_EXECUTOR_MQH
