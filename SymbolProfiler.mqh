//+------------------------------------------------------------------+
//|                                              SymbolProfiler.mqh |
//|  Symbol profiling: class detection, broker rules, per-symbol     |
//|  overrides, runtime ATR calibration, session awareness           |
//|  v6.0                                                            |
//+------------------------------------------------------------------+
#property copyright "MY BOT"
#property strict

#ifndef SYMBOL_PROFILER_MQH
#define SYMBOL_PROFILER_MQH

//+------------------------------------------------------------------+
//| Instrument Class Enum                                            |
//+------------------------------------------------------------------+
enum ENUM_INSTRUMENT_CLASS
{
   INST_FOREX_MAJOR,     // Majors and crosses: EURUSD, GBPJPY, etc.
   INST_XAUUSD,          // Gold (XAUUSD / GOLD)
   INST_XAGUSD,          // Silver (XAGUSD / SILVER)
   INST_OIL,             // Crude oil (WTI, BRENT, USOIL, UKOIL)
   INST_INDEX_US,        // US equity indices: US30, NAS100, SPX500, US500
   INST_INDEX_EU,        // EU indices: GER40, UK100, FRA40
   INST_CRYPTO,          // BTC, ETH, crypto CFDs
   INST_SYNTH_VOL10,     // Volatility 10 Index (slow, digits=2)
   INST_SYNTH_VOL25,     // Volatility 25 Index (digits=2)
   INST_SYNTH_VOL50,     // Volatility 50 Index (digits=4)
   INST_SYNTH_VOL75,     // Volatility 75 Index (fast, digits=4)
   INST_SYNTH_VOL100,    // Volatility 100 Index (very fast, digits=2)
   INST_SYNTH_BOOM,      // Boom 300/500/1000 (spike up, digits=1)
   INST_SYNTH_CRASH,     // Crash 300/500/1000 (spike down, digits=1)
   INST_SYNTH_STEP,      // Step Index (fixed-step moves)
   INST_SYNTH_JUMP,      // Jump 10/25/50/75/100
   INST_SYNTH_VOL,       // Fallback: any other Deriv synthetic
   INST_OTHER,           // Any other tradeable
   INST_UNSUPPORTED      // Unrecognised — fallback only
};

//+------------------------------------------------------------------+
//| Symbol Profile Struct                                            |
//+------------------------------------------------------------------+
struct SymbolProfile
{
   string symbol;
   string instrumentClass;
   ENUM_INSTRUMENT_CLASS classEnum;
   int    digits;
   double point;
   double tickSize;
   double tickValue;
   double contractSize;
   double volumeMin;
   double volumeMax;
   double volumeStep;
   int    stopsLevelPoints;
   int    freezeLevelPoints;
   bool   spreadFloat;
   long   fillingMode;
   long   tradeMode;
   bool   is24x7;
   double defaultSpreadCapPoints;
   double defaultMinTrendGapPoints;
   double defaultSLBufferPoints;
   double defaultMinSLPoints;

   // --- Trading multipliers (symbol-specific) ---
   double atrSLMult;              // ATR multiplier for SL buffer
   double atrTPMult;              // ATR multiplier for TP (via RR ratio override)
   double zoneMergeATRMult;       // Merge zones within ATR * this
   double zoneProximityATRMult;   // "Near zone" = within ATR * this
   double regimeTrendATRMult;     // Classifier: EMA gap >= ATR * this = trending
   double regimeConsolidRatio;    // Classifier: ATR/avg <= this = consolidation
   double regimeRangeATRMult;     // Classifier: EMA gap <= ATR * this = range
   double riskPctOverride;        // Per-symbol risk % (0 = use global input)
   bool   useMajorZonesOnly;      // Only trade off major S/R + supply/demand
   bool   allowZoneTrades;        // Allow zone-based sweep entries
   bool   allowMTF;               // Allow MTF alignment filter

   // --- Runtime ATR calibration ---
   double atrCalibrated;          // Current live ATR (H4, 14-period)
   double atrBaseline;            // Long-run baseline ATR (D1, 50-period)
   double atrVolatilityRatio;     // atrCalibrated / atrBaseline: >1.2 = elevated, <0.7 = quiet
   double spreadCalibrated;       // Current live spread in points
   double spreadBaselinePts;      // Typical spread for this symbol (calibrated at startup)
   bool   spreadElevated;         // true if current spread > 2x baseline
   datetime lastCalibrationTime;  // When calibration was last run

   // --- Session awareness ---
   bool   inAsianSession;         // 00:00-09:00 UTC
   bool   inLondonSession;        // 07:00-16:00 UTC
   bool   inNewYorkSession;       // 12:00-21:00 UTC
   bool   inLondonNYOverlap;      // 12:00-16:00 UTC (highest liquidity)
   bool   isSessionOpen;          // At least one major session active

   // --- Dynamic spread cap (adjusts per session + volatility) ---
   double effectiveSpreadCapPoints; // Runtime spread cap (may widen in off-peak)

   bool   validated;
};

//+------------------------------------------------------------------+
//| Strip common broker suffixes for matching                        |
//+------------------------------------------------------------------+
string StripBrokerSuffix(string sym)
{
   string clean = sym;
   StringToUpper(clean);

   // Common suffixes: .pro, .ecn, .raw, _SB, -ECN, .m, .z, #, etc.
   string suffixes[] = {".PRO",".ECN",".RAW",".SB",".STD",".M",".Z",".R",
                        "_PRO","_ECN","_RAW","_SB","_STD","-ECN","-PRO",
                        ".MINI",".MICRO","#"};
   for(int i = 0; i < ArraySize(suffixes); i++)
   {
      int pos = StringFind(clean, suffixes[i]);
      if(pos > 0) // Only strip if not at position 0
         clean = StringSubstr(clean, 0, pos);
   }
   return clean;
}

//+------------------------------------------------------------------+
//| Detect instrument class with robust matching                     |
//+------------------------------------------------------------------+
ENUM_INSTRUMENT_CLASS DetectInstrumentClass(const string sym)
{
   string clean = StripBrokerSuffix(sym);

   // --- Deriv Synthetic: Boom ---
   if(StringFind(clean, "BOOM") >= 0)
      return INST_SYNTH_BOOM;

   // --- Deriv Synthetic: Crash ---
   if(StringFind(clean, "CRASH") >= 0)
      return INST_SYNTH_CRASH;

   // --- Deriv Synthetic: Step Index ---
   if(StringFind(clean, "STEP") >= 0)
      return INST_SYNTH_STEP;

   // --- Deriv Synthetic: Jump ---
   if(StringFind(clean, "JUMP") >= 0)
      return INST_SYNTH_JUMP;

   // --- Deriv Synthetic: Volatility (by number) ---
   // Must check from most specific to least to avoid V10 matching V100
   if(StringFind(clean, "VOLATILITY 100") >= 0 || StringFind(clean, "VOL 100") >= 0 ||
      StringFind(clean, "V100") >= 0)
      return INST_SYNTH_VOL100;

   if(StringFind(clean, "VOLATILITY 75") >= 0  || StringFind(clean, "VOL 75") >= 0 ||
      StringFind(clean, "V75") >= 0)
      return INST_SYNTH_VOL75;

   if(StringFind(clean, "VOLATILITY 50") >= 0  || StringFind(clean, "VOL 50") >= 0 ||
      StringFind(clean, "V50") >= 0)
      return INST_SYNTH_VOL50;

   if(StringFind(clean, "VOLATILITY 25") >= 0  || StringFind(clean, "VOL 25") >= 0 ||
      StringFind(clean, "V25") >= 0)
      return INST_SYNTH_VOL25;

   if(StringFind(clean, "VOLATILITY 10") >= 0  || StringFind(clean, "VOL 10") >= 0 ||
      StringFind(clean, "V10") >= 0)
      return INST_SYNTH_VOL10;

   // --- Deriv Synthetic: Range Break / Drift / other ---
   if(StringFind(clean, "VOLATILITY") >= 0 || StringFind(clean, "VOL ") >= 0 ||
      StringFind(clean, "RANGE BREAK") >= 0 || StringFind(clean, "DRIFT") >= 0)
      return INST_SYNTH_VOL;

   // --- Gold ---
   if(StringFind(clean, "XAUUSD") >= 0 || StringFind(clean, "GOLD") >= 0)
      return INST_XAUUSD;

   // --- Silver ---
   if(StringFind(clean, "XAGUSD") >= 0 || StringFind(clean, "SILVER") >= 0 ||
      StringFind(clean, "XAGUS") >= 0)
      return INST_XAGUSD;

   // --- Crude Oil / Brent ---
   if(StringFind(clean, "USOIL") >= 0 || StringFind(clean, "UKOIL") >= 0 ||
      StringFind(clean, "WTI") >= 0   || StringFind(clean, "BRENT") >= 0 ||
      StringFind(clean, "XTIUSD") >= 0 || StringFind(clean, "XBRUSD") >= 0 ||
      StringFind(clean, "OILUSD") >= 0 || StringFind(clean, "CL") >= 0)
      return INST_OIL;

   // --- US Equity Indices ---
   if(StringFind(clean, "US30") >= 0  || StringFind(clean, "DJ30") >= 0  ||
      StringFind(clean, "DOW") >= 0   || StringFind(clean, "NAS100") >= 0 ||
      StringFind(clean, "NASDAQ") >= 0 || StringFind(clean, "NDX") >= 0  ||
      StringFind(clean, "SPX") >= 0   || StringFind(clean, "SP500") >= 0 ||
      StringFind(clean, "US500") >= 0 || StringFind(clean, "USTEC") >= 0 ||
      StringFind(clean, "USA500") >= 0)
      return INST_INDEX_US;

   // --- European/Other Equity Indices ---
   if(StringFind(clean, "GER40") >= 0  || StringFind(clean, "DAX") >= 0   ||
      StringFind(clean, "UK100") >= 0  || StringFind(clean, "FTSE") >= 0  ||
      StringFind(clean, "FRA40") >= 0  || StringFind(clean, "CAC") >= 0   ||
      StringFind(clean, "EU50") >= 0   || StringFind(clean, "STOXX") >= 0 ||
      StringFind(clean, "AUS200") >= 0 || StringFind(clean, "JPN225") >= 0 ||
      StringFind(clean, "HK50") >= 0   || StringFind(clean, "NIKKEI") >= 0)
      return INST_INDEX_EU;

   // --- Crypto CFDs ---
   if(StringFind(clean, "BTC") >= 0 || StringFind(clean, "ETH") >= 0 ||
      StringFind(clean, "XRP") >= 0 || StringFind(clean, "LTC") >= 0 ||
      StringFind(clean, "BCH") >= 0 || StringFind(clean, "ADA") >= 0 ||
      StringFind(clean, "SOL") >= 0 || StringFind(clean, "DOGE") >= 0)
      return INST_CRYPTO;

   // --- Forex Majors + all crosses ---
   string majors[] = {
      "EURUSD","GBPUSD","USDJPY","USDCHF","AUDUSD","NZDUSD","USDCAD",
      "EURGBP","EURJPY","GBPJPY","AUDJPY","EURAUD","EURNZD","GBPAUD",
      "GBPNZD","GBPCAD","AUDCAD","AUDNZD","NZDJPY","NZDCAD","CADJPY",
      "CHFJPY","EURCHF","EURCAD","SGDJPY","USDSGD","USDMXN","USDHKD",
      "USDNOK","USDSEK","USDDKK","USDZAR","USDTRY","USDPLN","USDCZK",
      "EURHUF","EURNOK","EURSEK","GBPCHF","NZDCHF","AUDCHF","CADCHF"
   };
   for(int i = 0; i < ArraySize(majors); i++)
   {
      if(StringFind(clean, majors[i]) >= 0)
         return INST_FOREX_MAJOR;
   }

   return INST_OTHER;
}

//+------------------------------------------------------------------+
//| Load execution rules from broker                                 |
//+------------------------------------------------------------------+
void LoadExecutionRules(SymbolProfile &prof)
{
   prof.fillingMode = SymbolInfoInteger(prof.symbol, SYMBOL_FILLING_MODE);
   prof.tradeMode   = SymbolInfoInteger(prof.symbol, SYMBOL_TRADE_MODE);
   prof.spreadFloat = (SymbolInfoInteger(prof.symbol, SYMBOL_SPREAD_FLOAT) != 0);

   prof.is24x7 = (prof.classEnum == INST_SYNTH_VOL   ||
                  prof.classEnum == INST_SYNTH_VOL10  ||
                  prof.classEnum == INST_SYNTH_VOL25  ||
                  prof.classEnum == INST_SYNTH_VOL50  ||
                  prof.classEnum == INST_SYNTH_VOL75  ||
                  prof.classEnum == INST_SYNTH_VOL100 ||
                  prof.classEnum == INST_SYNTH_BOOM   ||
                  prof.classEnum == INST_SYNTH_CRASH  ||
                  prof.classEnum == INST_SYNTH_STEP   ||
                  prof.classEnum == INST_SYNTH_JUMP   ||
                  prof.classEnum == INST_CRYPTO);
}

//+------------------------------------------------------------------+
//| Load volume rules from broker                                    |
//+------------------------------------------------------------------+
void LoadVolumeRules(SymbolProfile &prof)
{
   prof.volumeMin  = SymbolInfoDouble(prof.symbol, SYMBOL_VOLUME_MIN);
   prof.volumeMax  = SymbolInfoDouble(prof.symbol, SYMBOL_VOLUME_MAX);
   prof.volumeStep = SymbolInfoDouble(prof.symbol, SYMBOL_VOLUME_STEP);
   if(prof.volumeMin  <= 0) prof.volumeMin  = 0.01;
   if(prof.volumeMax  <= 0) prof.volumeMax  = 100.0;
   if(prof.volumeStep <= 0) prof.volumeStep = 0.01;
}

//+------------------------------------------------------------------+
//| Load distance rules with per-symbol and per-vol-index defaults   |
//+------------------------------------------------------------------+
void LoadDistanceRules(SymbolProfile &prof, double userMinTrendGap,
                       double userSpreadCapForex, double userSpreadCapGold,
                       double userSpreadCapSynth, double userMinSLOverride)
{
   prof.stopsLevelPoints  = (int)SymbolInfoInteger(prof.symbol, SYMBOL_TRADE_STOPS_LEVEL);
   prof.freezeLevelPoints = (int)SymbolInfoInteger(prof.symbol, SYMBOL_TRADE_FREEZE_LEVEL);

   switch(prof.classEnum)
   {
      case INST_FOREX_MAJOR:
         prof.defaultSpreadCapPoints    = 30.0;
         prof.defaultMinTrendGapPoints  = 50.0;
         prof.defaultSLBufferPoints     = 20.0;
         prof.defaultMinSLPoints        = 30.0;
         break;
      case INST_XAUUSD:
         prof.defaultSpreadCapPoints    = 80.0;
         prof.defaultMinTrendGapPoints  = 200.0;
         prof.defaultSLBufferPoints     = 50.0;
         prof.defaultMinSLPoints        = 80.0;
         break;
      case INST_XAGUSD:
         prof.defaultSpreadCapPoints    = 60.0;
         prof.defaultMinTrendGapPoints  = 150.0;
         prof.defaultSLBufferPoints     = 40.0;
         prof.defaultMinSLPoints        = 60.0;
         break;
      case INST_OIL:
         prof.defaultSpreadCapPoints    = 100.0;
         prof.defaultMinTrendGapPoints  = 250.0;
         prof.defaultSLBufferPoints     = 60.0;
         prof.defaultMinSLPoints        = 100.0;
         break;
      case INST_INDEX_US:
         prof.defaultSpreadCapPoints    = 150.0;
         prof.defaultMinTrendGapPoints  = 400.0;
         prof.defaultSLBufferPoints     = 100.0;
         prof.defaultMinSLPoints        = 200.0;
         break;
      case INST_INDEX_EU:
         prof.defaultSpreadCapPoints    = 120.0;
         prof.defaultMinTrendGapPoints  = 300.0;
         prof.defaultSLBufferPoints     = 80.0;
         prof.defaultMinSLPoints        = 150.0;
         break;
      case INST_CRYPTO:
         prof.defaultSpreadCapPoints    = 500.0;
         prof.defaultMinTrendGapPoints  = 1000.0;
         prof.defaultSLBufferPoints     = 300.0;
         prof.defaultMinSLPoints        = 500.0;
         break;
      case INST_SYNTH_VOL10:
         prof.defaultSpreadCapPoints    = 50.0;
         prof.defaultMinTrendGapPoints  = 100.0;
         prof.defaultSLBufferPoints     = 30.0;
         prof.defaultMinSLPoints        = 50.0;
         break;
      case INST_SYNTH_VOL25:
         prof.defaultSpreadCapPoints    = 80.0;
         prof.defaultMinTrendGapPoints  = 150.0;
         prof.defaultSLBufferPoints     = 50.0;
         prof.defaultMinSLPoints        = 80.0;
         break;
      case INST_SYNTH_VOL50:
         prof.defaultSpreadCapPoints    = 120.0;
         prof.defaultMinTrendGapPoints  = 250.0;
         prof.defaultSLBufferPoints     = 80.0;
         prof.defaultMinSLPoints        = 120.0;
         break;
      case INST_SYNTH_VOL75:
         prof.defaultSpreadCapPoints    = 150.0;
         prof.defaultMinTrendGapPoints  = 300.0;
         prof.defaultSLBufferPoints     = 100.0;
         prof.defaultMinSLPoints        = 150.0;
         break;
      case INST_SYNTH_VOL100:
         prof.defaultSpreadCapPoints    = 200.0;
         prof.defaultMinTrendGapPoints  = 400.0;
         prof.defaultSLBufferPoints     = 150.0;
         prof.defaultMinSLPoints        = 200.0;
         break;
      case INST_SYNTH_BOOM:
      case INST_SYNTH_CRASH:
         prof.defaultSpreadCapPoints    = 300.0;
         prof.defaultMinTrendGapPoints  = 500.0;
         prof.defaultSLBufferPoints     = 200.0;
         prof.defaultMinSLPoints        = 300.0;
         break;
      case INST_SYNTH_STEP:
         prof.defaultSpreadCapPoints    = 100.0;
         prof.defaultMinTrendGapPoints  = 200.0;
         prof.defaultSLBufferPoints     = 80.0;
         prof.defaultMinSLPoints        = 100.0;
         break;
      case INST_SYNTH_JUMP:
         prof.defaultSpreadCapPoints    = 200.0;
         prof.defaultMinTrendGapPoints  = 400.0;
         prof.defaultSLBufferPoints     = 150.0;
         prof.defaultMinSLPoints        = 200.0;
         break;
      case INST_SYNTH_VOL:
         prof.defaultSpreadCapPoints    = 150.0;
         prof.defaultMinTrendGapPoints  = 300.0;
         prof.defaultSLBufferPoints     = 100.0;
         prof.defaultMinSLPoints        = 150.0;
         break;
      default:
         prof.defaultSpreadCapPoints    = 100.0;
         prof.defaultMinTrendGapPoints  = 200.0;
         prof.defaultSLBufferPoints     = 50.0;
         prof.defaultMinSLPoints        = 100.0;
         break;
   }

   // Ensure stops level floor is respected
   if(prof.stopsLevelPoints > 0)
   {
      if(prof.defaultMinSLPoints < (double)prof.stopsLevelPoints * 1.10)
         prof.defaultMinSLPoints = (double)prof.stopsLevelPoints * 1.10;
      if(prof.defaultSLBufferPoints < (double)prof.stopsLevelPoints * 0.50)
         prof.defaultSLBufferPoints = (double)prof.stopsLevelPoints * 0.50;
   }

   // User overrides per class
   if(userMinTrendGap > 0)
      prof.defaultMinTrendGapPoints = userMinTrendGap;
   if(userSpreadCapForex > 0 && prof.classEnum == INST_FOREX_MAJOR)
      prof.defaultSpreadCapPoints = userSpreadCapForex;
   if(userSpreadCapGold > 0 && prof.classEnum == INST_XAUUSD)
      prof.defaultSpreadCapPoints = userSpreadCapGold;
   bool isSynth = (prof.classEnum == INST_SYNTH_VOL    ||
                   prof.classEnum == INST_SYNTH_VOL10  ||
                   prof.classEnum == INST_SYNTH_VOL25  ||
                   prof.classEnum == INST_SYNTH_VOL50  ||
                   prof.classEnum == INST_SYNTH_VOL75  ||
                   prof.classEnum == INST_SYNTH_VOL100 ||
                   prof.classEnum == INST_SYNTH_BOOM   ||
                   prof.classEnum == INST_SYNTH_CRASH  ||
                   prof.classEnum == INST_SYNTH_STEP   ||
                   prof.classEnum == INST_SYNTH_JUMP);
   if(userSpreadCapSynth > 0 && isSynth)
      prof.defaultSpreadCapPoints = userSpreadCapSynth;
   if(userMinSLOverride > 0)
      prof.defaultMinSLPoints = userMinSLOverride;

   // Initialise calibration fields — will be populated by CalibrateProfileATR()
   prof.atrCalibrated          = 0.0;
   prof.atrBaseline            = 0.0;
   prof.atrVolatilityRatio     = 1.0;
   prof.spreadCalibrated       = 0.0;
   prof.spreadBaselinePts      = prof.defaultSpreadCapPoints * 0.50;
   prof.spreadElevated         = false;
   prof.lastCalibrationTime    = 0;
   prof.effectiveSpreadCapPoints = prof.defaultSpreadCapPoints;

   // Initialise session fields
   prof.inAsianSession         = false;
   prof.inLondonSession        = false;
   prof.inNewYorkSession       = false;
   prof.inLondonNYOverlap      = false;
   prof.isSessionOpen          = false;
}

//+------------------------------------------------------------------+
//| Load trading multipliers per symbol class                        |
//+------------------------------------------------------------------+
void LoadTradingMultipliers(SymbolProfile &prof)
{
   // Defaults (safe for unknown symbols)
   prof.atrSLMult            = 1.0;
   prof.atrTPMult            = 2.0;
   prof.zoneMergeATRMult     = 0.35;
   prof.zoneProximityATRMult = 0.35;
   prof.regimeTrendATRMult   = 0.80;
   prof.regimeConsolidRatio  = 0.65;
   prof.regimeRangeATRMult   = 0.35;
   prof.riskPctOverride      = 0.0;
   prof.useMajorZonesOnly    = true;
   prof.allowZoneTrades      = true;
   prof.allowMTF             = true;

   switch(prof.classEnum)
   {
      case INST_FOREX_MAJOR:
         prof.atrSLMult            = 1.0;
         prof.atrTPMult            = 2.0;
         prof.zoneMergeATRMult     = 0.30;
         prof.zoneProximityATRMult = 0.35;
         prof.regimeTrendATRMult   = 0.80;
         prof.regimeConsolidRatio  = 0.65;
         prof.regimeRangeATRMult   = 0.35;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = true;
         break;

      case INST_XAUUSD:
         prof.atrSLMult            = 1.10;
         prof.atrTPMult            = 2.20;
         prof.zoneMergeATRMult     = 0.40;
         prof.zoneProximityATRMult = 0.40;
         prof.regimeTrendATRMult   = 0.80;
         prof.regimeConsolidRatio  = 0.60;
         prof.regimeRangeATRMult   = 0.40;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = true;
         break;

      case INST_XAGUSD:
         prof.atrSLMult            = 1.10;
         prof.atrTPMult            = 2.20;
         prof.zoneMergeATRMult     = 0.42;
         prof.zoneProximityATRMult = 0.42;
         prof.regimeTrendATRMult   = 0.80;
         prof.regimeConsolidRatio  = 0.60;
         prof.regimeRangeATRMult   = 0.40;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = true;
         break;

      case INST_OIL:
         prof.atrSLMult            = 1.20;
         prof.atrTPMult            = 2.40;
         prof.zoneMergeATRMult     = 0.45;
         prof.zoneProximityATRMult = 0.45;
         prof.regimeTrendATRMult   = 0.75;
         prof.regimeConsolidRatio  = 0.55;
         prof.regimeRangeATRMult   = 0.38;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = true;
         break;

      case INST_INDEX_US:
         prof.atrSLMult            = 1.20;
         prof.atrTPMult            = 2.50;
         prof.zoneMergeATRMult     = 0.50;
         prof.zoneProximityATRMult = 0.50;
         prof.regimeTrendATRMult   = 0.70;
         prof.regimeConsolidRatio  = 0.55;
         prof.regimeRangeATRMult   = 0.30;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = true;
         break;

      case INST_INDEX_EU:
         prof.atrSLMult            = 1.15;
         prof.atrTPMult            = 2.30;
         prof.zoneMergeATRMult     = 0.45;
         prof.zoneProximityATRMult = 0.45;
         prof.regimeTrendATRMult   = 0.75;
         prof.regimeConsolidRatio  = 0.58;
         prof.regimeRangeATRMult   = 0.32;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = true;
         break;

      case INST_CRYPTO:
         prof.atrSLMult            = 1.50;
         prof.atrTPMult            = 3.00;
         prof.zoneMergeATRMult     = 0.55;
         prof.zoneProximityATRMult = 0.55;
         prof.regimeTrendATRMult   = 0.65;
         prof.regimeConsolidRatio  = 0.50;
         prof.regimeRangeATRMult   = 0.25;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = false;
         break;

      case INST_SYNTH_VOL10:
         prof.atrSLMult            = 1.00;
         prof.atrTPMult            = 2.00;
         prof.zoneMergeATRMult     = 0.35;
         prof.zoneProximityATRMult = 0.35;
         prof.regimeTrendATRMult   = 0.65;
         prof.regimeConsolidRatio  = 0.60;
         prof.regimeRangeATRMult   = 0.25;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = false;
         break;

      case INST_SYNTH_VOL25:
         prof.atrSLMult            = 1.10;
         prof.atrTPMult            = 2.10;
         prof.zoneMergeATRMult     = 0.38;
         prof.zoneProximityATRMult = 0.38;
         prof.regimeTrendATRMult   = 0.63;
         prof.regimeConsolidRatio  = 0.58;
         prof.regimeRangeATRMult   = 0.22;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = false;
         break;

      case INST_SYNTH_VOL50:
         prof.atrSLMult            = 1.15;
         prof.atrTPMult            = 2.20;
         prof.zoneMergeATRMult     = 0.42;
         prof.zoneProximityATRMult = 0.42;
         prof.regimeTrendATRMult   = 0.62;
         prof.regimeConsolidRatio  = 0.57;
         prof.regimeRangeATRMult   = 0.21;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = false;
         break;

      case INST_SYNTH_VOL75:
         prof.atrSLMult            = 1.20;
         prof.atrTPMult            = 2.30;
         prof.zoneMergeATRMult     = 0.45;
         prof.zoneProximityATRMult = 0.45;
         prof.regimeTrendATRMult   = 0.60;
         prof.regimeConsolidRatio  = 0.55;
         prof.regimeRangeATRMult   = 0.20;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = false;
         break;

      case INST_SYNTH_VOL100:
         prof.atrSLMult            = 1.30;
         prof.atrTPMult            = 2.50;
         prof.zoneMergeATRMult     = 0.50;
         prof.zoneProximityATRMult = 0.50;
         prof.regimeTrendATRMult   = 0.58;
         prof.regimeConsolidRatio  = 0.52;
         prof.regimeRangeATRMult   = 0.18;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = false;
         break;

      case INST_SYNTH_BOOM:
      case INST_SYNTH_CRASH:
         prof.atrSLMult            = 1.50;
         prof.atrTPMult            = 3.00;
         prof.zoneMergeATRMult     = 0.55;
         prof.zoneProximityATRMult = 0.55;
         prof.regimeTrendATRMult   = 0.55;
         prof.regimeConsolidRatio  = 0.50;
         prof.regimeRangeATRMult   = 0.18;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = false;
         break;

      case INST_SYNTH_STEP:
         prof.atrSLMult            = 1.00;
         prof.atrTPMult            = 2.00;
         prof.zoneMergeATRMult     = 0.35;
         prof.zoneProximityATRMult = 0.35;
         prof.regimeTrendATRMult   = 0.65;
         prof.regimeConsolidRatio  = 0.60;
         prof.regimeRangeATRMult   = 0.25;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = false;
         break;

      case INST_SYNTH_JUMP:
         prof.atrSLMult            = 1.40;
         prof.atrTPMult            = 2.80;
         prof.zoneMergeATRMult     = 0.50;
         prof.zoneProximityATRMult = 0.50;
         prof.regimeTrendATRMult   = 0.58;
         prof.regimeConsolidRatio  = 0.52;
         prof.regimeRangeATRMult   = 0.18;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = false;
         break;

      case INST_SYNTH_VOL:
         prof.atrSLMult            = 1.20;
         prof.atrTPMult            = 2.20;
         prof.zoneMergeATRMult     = 0.45;
         prof.zoneProximityATRMult = 0.45;
         prof.regimeTrendATRMult   = 0.60;
         prof.regimeConsolidRatio  = 0.55;
         prof.regimeRangeATRMult   = 0.20;
         prof.riskPctOverride      = 0.0;
         prof.useMajorZonesOnly    = true;
         prof.allowZoneTrades      = true;
         prof.allowMTF             = false;
         break;

      default:
         break;
   }
}

//+------------------------------------------------------------------+
//| Session Detection — UTC-based                                    |
//| Call once per bar on H4 or M15 ticks                            |
//+------------------------------------------------------------------+
void UpdateSessionState(SymbolProfile &prof)
{
   if(prof.is24x7)
   {
      prof.inAsianSession    = true;
      prof.inLondonSession   = true;
      prof.inNewYorkSession  = true;
      prof.inLondonNYOverlap = true;
      prof.isSessionOpen     = true;
      prof.effectiveSpreadCapPoints = prof.defaultSpreadCapPoints;
      return;
   }

   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int h = dt.hour;
   int m = dt.min;
   int totalMins = h * 60 + m;

   // Session windows in UTC minutes
   int asianStart  =  0 * 60;   // 00:00
   int asianEnd    =  9 * 60;   // 09:00
   int londonStart =  7 * 60;   // 07:00
   int londonEnd   = 16 * 60;   // 16:00
   int nyStart     = 12 * 60;   // 12:00
   int nyEnd       = 21 * 60;   // 21:00
   int overlapStart = 12 * 60;  // 12:00
   int overlapEnd   = 16 * 60;  // 16:00

   prof.inAsianSession    = (totalMins >= asianStart  && totalMins < asianEnd);
   prof.inLondonSession   = (totalMins >= londonStart && totalMins < londonEnd);
   prof.inNewYorkSession  = (totalMins >= nyStart     && totalMins < nyEnd);
   prof.inLondonNYOverlap = (totalMins >= overlapStart && totalMins < overlapEnd);
   prof.isSessionOpen     = (prof.inLondonSession || prof.inNewYorkSession || prof.inAsianSession);

   // Widen spread cap outside London/NY — off-peak spreads can be much higher
   if(prof.inLondonNYOverlap)
      prof.effectiveSpreadCapPoints = prof.defaultSpreadCapPoints;
   else if(prof.inLondonSession || prof.inNewYorkSession)
      prof.effectiveSpreadCapPoints = prof.defaultSpreadCapPoints * 1.30;
   else if(prof.inAsianSession)
      prof.effectiveSpreadCapPoints = prof.defaultSpreadCapPoints * 1.60;
   else
      prof.effectiveSpreadCapPoints = prof.defaultSpreadCapPoints * 2.20;

   // If spread is already elevated, add a further buffer
   if(prof.spreadElevated)
      prof.effectiveSpreadCapPoints *= 1.25;
}

//+------------------------------------------------------------------+
//| Runtime ATR and Spread Calibration                               |
//| Call once at startup and then every N bars                       |
//+------------------------------------------------------------------+
void CalibrateProfileATR(SymbolProfile &prof)
{
   // H4 ATR(14) — reflects current volatility
   int atrH4Handle = iATR(_Symbol, PERIOD_H4, 14);
   if(atrH4Handle != INVALID_HANDLE)
   {
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(atrH4Handle, 0, 0, 3, buf) >= 1)
      {
         double pts = prof.point > 0 ? prof.point : _Point;
         prof.atrCalibrated = buf[1] / pts;
      }
      IndicatorRelease(atrH4Handle);
   }

   // D1 ATR(50) — long-run baseline
   int atrD1Handle = iATR(_Symbol, PERIOD_D1, 50);
   if(atrD1Handle != INVALID_HANDLE)
   {
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(atrD1Handle, 0, 0, 3, buf) >= 1)
      {
         double pts = prof.point > 0 ? prof.point : _Point;
         prof.atrBaseline = buf[1] / pts;
      }
      IndicatorRelease(atrD1Handle);
   }

   if(prof.atrBaseline > 0.0 && prof.atrCalibrated > 0.0)
      prof.atrVolatilityRatio = prof.atrCalibrated / prof.atrBaseline;
   else
      prof.atrVolatilityRatio = 1.0;

   // Live spread
   long spreadRaw = SymbolInfoInteger(prof.symbol, SYMBOL_SPREAD);
   double pts = prof.point > 0 ? prof.point : _Point;
   prof.spreadCalibrated = (double)spreadRaw * pts / pts;

   // First-time baseline
   if(prof.spreadBaselinePts <= 0.0 || prof.lastCalibrationTime == 0)
      prof.spreadBaselinePts = MathMax(prof.spreadCalibrated, prof.defaultSpreadCapPoints * 0.30);

   prof.spreadElevated = (prof.spreadCalibrated > prof.spreadBaselinePts * 2.0);

   prof.lastCalibrationTime = TimeCurrent();

   // Adjust SL/TP multipliers dynamically when volatility is elevated or suppressed
   if(prof.atrVolatilityRatio > 1.40)
   {
      // High volatility: wider SL, bigger TP potential
      prof.atrSLMult = MathMin(prof.atrSLMult * 1.15, 2.50);
      prof.atrTPMult = MathMin(prof.atrTPMult * 1.10, 5.00);
   }
   else if(prof.atrVolatilityRatio < 0.65)
   {
      // Low volatility: tighter SL, more conservative TP
      prof.atrSLMult = MathMax(prof.atrSLMult * 0.90, 0.60);
      prof.atrTPMult = MathMax(prof.atrTPMult * 0.90, 1.20);
   }

   UpdateSessionState(prof);

   Print("[PROFILE_CALIBRATE] atrH4=", DoubleToString(prof.atrCalibrated, 1),
         " atrD1=", DoubleToString(prof.atrBaseline, 1),
         " volRatio=", DoubleToString(prof.atrVolatilityRatio, 2),
         " spread=", DoubleToString(prof.spreadCalibrated, 1),
         " spreadBase=", DoubleToString(prof.spreadBaselinePts, 1),
         " spreadElev=", prof.spreadElevated,
         " effSpreadCap=", DoubleToString(prof.effectiveSpreadCapPoints, 1),
         " london=", prof.inLondonSession,
         " ny=", prof.inNewYorkSession,
         " overlap=", prof.inLondonNYOverlap,
         " atrSL=", DoubleToString(prof.atrSLMult, 2),
         " atrTP=", DoubleToString(prof.atrTPMult, 2));
}

//+------------------------------------------------------------------+
//| Validate critical symbol properties                              |
//+------------------------------------------------------------------+
bool ValidateSymbolProperties(SymbolProfile &prof)
{
   prof.validated = true;

   if(prof.point <= 0)
   {
      Print("PROFILE ERROR: point=0 for ", prof.symbol, " — trading blocked");
      prof.validated = false;
   }
   if(prof.tickSize <= 0)
   {
      Print("PROFILE WARNING: tickSize=0 for ", prof.symbol, " — using point as fallback");
      prof.tickSize = prof.point;
   }
   if(prof.tickValue <= 0)
   {
      Print("PROFILE ERROR: tickValue=0 for ", prof.symbol, " — lot sizing will fail, trading blocked");
      prof.validated = false;
   }
   if(prof.contractSize <= 0)
   {
      Print("PROFILE WARNING: contractSize=0 for ", prof.symbol, " — using 100000 as fallback");
      prof.contractSize = 100000.0;
   }
   if(prof.digits < 0 || prof.digits > 8)
   {
      Print("PROFILE ERROR: invalid digits=", prof.digits, " for ", prof.symbol, " — trading blocked");
      prof.validated = false;
   }
   if(prof.volumeMin <= 0 || prof.volumeStep <= 0)
   {
      Print("PROFILE WARNING: volume rules suspicious for ", prof.symbol,
            " min=", prof.volumeMin, " step=", prof.volumeStep);
   }
   if(prof.tradeMode == SYMBOL_TRADE_MODE_DISABLED)
   {
      Print("PROFILE ERROR: trading disabled by broker for ", prof.symbol, " — trading blocked");
      prof.validated = false;
   }

   return prof.validated;
}

//+------------------------------------------------------------------+
//| Build complete symbol profile                                    |
//+------------------------------------------------------------------+
bool BuildSymbolProfile(SymbolProfile &prof, double userMinTrendGap,
                         double userSpreadCapForex, double userSpreadCapGold,
                         double userSpreadCapSynth, double userMinSLOverride)
{
   prof.symbol       = _Symbol;
   prof.digits       = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   prof.point        = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   prof.tickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   prof.tickValue    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   prof.contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   prof.classEnum = DetectInstrumentClass(_Symbol);
   switch(prof.classEnum)
   {
      case INST_FOREX_MAJOR:    prof.instrumentClass = "FOREX_MAJOR";   break;
      case INST_XAUUSD:         prof.instrumentClass = "XAUUSD";        break;
      case INST_XAGUSD:         prof.instrumentClass = "XAGUSD";        break;
      case INST_OIL:            prof.instrumentClass = "OIL";           break;
      case INST_INDEX_US:       prof.instrumentClass = "INDEX_US";      break;
      case INST_INDEX_EU:       prof.instrumentClass = "INDEX_EU";      break;
      case INST_CRYPTO:         prof.instrumentClass = "CRYPTO";        break;
      case INST_SYNTH_VOL10:    prof.instrumentClass = "SYNTH_VOL10";   break;
      case INST_SYNTH_VOL25:    prof.instrumentClass = "SYNTH_VOL25";   break;
      case INST_SYNTH_VOL50:    prof.instrumentClass = "SYNTH_VOL50";   break;
      case INST_SYNTH_VOL75:    prof.instrumentClass = "SYNTH_VOL75";   break;
      case INST_SYNTH_VOL100:   prof.instrumentClass = "SYNTH_VOL100";  break;
      case INST_SYNTH_BOOM:     prof.instrumentClass = "SYNTH_BOOM";    break;
      case INST_SYNTH_CRASH:    prof.instrumentClass = "SYNTH_CRASH";   break;
      case INST_SYNTH_STEP:     prof.instrumentClass = "SYNTH_STEP";    break;
      case INST_SYNTH_JUMP:     prof.instrumentClass = "SYNTH_JUMP";    break;
      case INST_SYNTH_VOL:      prof.instrumentClass = "SYNTH_VOL";     break;
      case INST_OTHER:          prof.instrumentClass = "OTHER";         break;
      default:                  prof.instrumentClass = "UNKNOWN";       break;
   }

   if(prof.classEnum == INST_UNSUPPORTED)
   {
      Print("PROFILE WARNING: Symbol ", _Symbol, " not recognized — using fallback defaults.");
      prof.classEnum = INST_OTHER;
      prof.instrumentClass = "OTHER";
   }

   LoadExecutionRules(prof);
   LoadVolumeRules(prof);
   LoadDistanceRules(prof, userMinTrendGap, userSpreadCapForex, userSpreadCapGold,
                     userSpreadCapSynth, userMinSLOverride);
   LoadTradingMultipliers(prof);

   bool valid = ValidateSymbolProperties(prof);

   // Run initial ATR calibration — requires bars to be available
   CalibrateProfileATR(prof);

   Print("PROFILE: ", prof.symbol, " class=", prof.instrumentClass,
         " digits=", prof.digits, " point=", DoubleToString(prof.point, prof.digits),
         " tickSz=", prof.tickSize, " tickVal=", prof.tickValue,
         " contract=", prof.contractSize,
         " volMin=", prof.volumeMin, " volMax=", prof.volumeMax, " volStep=", prof.volumeStep,
         " stopsLvl=", prof.stopsLevelPoints, " freezeLvl=", prof.freezeLevelPoints,
         " is24x7=", prof.is24x7, " valid=", valid);
   Print("PROFILE DEFAULTS: spreadCap=", DoubleToString(prof.defaultSpreadCapPoints, 0), "pts",
         " effCap=", DoubleToString(prof.effectiveSpreadCapPoints, 0), "pts",
         " trendGap=", DoubleToString(prof.defaultMinTrendGapPoints, 0), "pts",
         " slBuffer=", DoubleToString(prof.defaultSLBufferPoints, 0), "pts",
         " minSL=", DoubleToString(prof.defaultMinSLPoints, 0), "pts");
   Print("PROFILE TRADING: atrSL=", DoubleToString(prof.atrSLMult, 2),
         " atrTP=", DoubleToString(prof.atrTPMult, 2),
         " zoneMerge=", DoubleToString(prof.zoneMergeATRMult, 2),
         " zoneProx=", DoubleToString(prof.zoneProximityATRMult, 2),
         " regTrend=", DoubleToString(prof.regimeTrendATRMult, 2),
         " regConsol=", DoubleToString(prof.regimeConsolidRatio, 2),
         " regRange=", DoubleToString(prof.regimeRangeATRMult, 2),
         " riskOvr=", DoubleToString(prof.riskPctOverride, 2),
         " MTF=", prof.allowMTF,
         " volRatio=", DoubleToString(prof.atrVolatilityRatio, 2),
         " session=", (prof.inLondonNYOverlap ? "OVERLAP" :
                       prof.inLondonSession   ? "LONDON"  :
                       prof.inNewYorkSession  ? "NEWYORK" :
                       prof.inAsianSession    ? "ASIAN"   : "CLOSED"));

   return valid;
}

//+------------------------------------------------------------------+
//| Refresh runtime state — call each new bar (not every tick)       |
//+------------------------------------------------------------------+
void RefreshSymbolProfile(SymbolProfile &prof)
{
   if(!prof.validated) return;

   // Re-calibrate ATR every 4 hours (14400 seconds)
   if(TimeCurrent() - prof.lastCalibrationTime >= 14400 || prof.lastCalibrationTime == 0)
      CalibrateProfileATR(prof);
   else
      UpdateSessionState(prof);
}

//+------------------------------------------------------------------+
//| Simple wrapper for main EA to load profile with defaults         |
//+------------------------------------------------------------------+
bool LoadSymbolProfile(SymbolProfile &prof)
{
   return BuildSymbolProfile(prof, 0.0, 0.0, 0.0, 0.0, 0.0);
}

//+------------------------------------------------------------------+
//| Convenience: is current spread tradeable?                        |
//+------------------------------------------------------------------+
bool IsSpreadAcceptable(const SymbolProfile &prof)
{
   if(prof.spreadCalibrated <= 0) return true;
   return (prof.spreadCalibrated <= prof.effectiveSpreadCapPoints);
}

//+------------------------------------------------------------------+
//| Convenience: is this a high-liquidity window?                    |
//+------------------------------------------------------------------+
bool IsHighLiquiditySession(const SymbolProfile &prof)
{
   if(prof.is24x7) return true;
   return (prof.inLondonNYOverlap || prof.inLondonSession || prof.inNewYorkSession);
}

#endif // SYMBOL_PROFILER_MQH
