//+------------------------------------------------------------------+
//| TickMomentumBurstEA.mq5                                          |
//| Tick Momentum Burst + Cost-Aware BE + Dynamic Trailing           |
//|                                                                  |
//| Current-chart-symbol EA. Tick stream is the primary signal.      |
//+------------------------------------------------------------------+
#property copyright "Tick Momentum Research"
#property version   "1.40"
#property strict
#property description "Tick Momentum Burst EA: tick imbalance + displacement + tick rate."
#property description "Broker tick behaviour only - NOT centralized order flow."

#include <Trade\Trade.mqh>
#include "..\Include\TickMomentum\StrategyController.mqh"

//--- Trading
input double   InpLotSize              = 0.01;      // Fixed lot
input double   InpSLMoney              = 1.0;       // Initial SL (account $)
input double   InpTPMoney              = 2.0;       // Initial TP (account $)
input long     InpMagicNumber          = 26061001;  // Magic number
input int      InpDeviationPoints      = 20;        // Max slippage (points)
input int      InpMaxPositions         = 1;         // Must be 1 (single-position design)
input int      InpTPMode               = 0;         // TP mode: 0=FIXED 1=TRAILING_ONLY 2=HYBRID

//--- Risk-based sizing (off by default; scales volume so SL money = equity * pct)
input bool     InpUseRiskSizing        = false;     // false=fixed lot, true=risk % of equity
input double   InpRiskPercent          = 0.5;       // Risk per trade (% of equity) -> SL money
input double   InpRiskMaxLot           = 1.0;       // Cap for risk-scaled volume

//--- Commission (estimated; actual read from deal history on close)
input double   InpCommissionPerLot     = 6.0;       // Est. commission per 1.0 lot, one side (account $)
input bool     InpCommissionDoubledRT  = true;      // true = round-trip estimate = 2 x one side

//--- Tick momentum (initial research values, NOT optimized)
input int      InpTickWindow           = 50;        // Ticks per window
input double   InpMinimumDirectionalRatio = 0.70;   // Min directional ratio [0.5..1]
input int      InpMinimumPriceMovePoints  = 10;     // Min |displacement| (points)
input double   InpMinimumTicksPerSecond   = 1.0;    // Min tick rate
input double   InpMaximumTicksPerSecond   = 0.0;    // Abnormal tick-rate cap (0=off)
input int      InpMaximumDisplacementPoints = 0;    // Abnormal displacement cap pts (0=off)
input int      InpMaximumWindowSeconds    = 0;      // Stale window cap sec (0=off)

//--- Spread
input int      InpMaxSpreadPoints      = 100;       // Max spread (points)

//--- Break-even
input bool     InpEnableBreakEven      = true;
input double   InpBreakEvenBufferMoney = 0.02;      // Extra net profit target at BE ($)

//--- Trailing
input bool     InpEnableTrailing       = true;
input double   InpTrailingDistanceMoney= 0.50;      // Trailing distance (account $)

//--- Context (optional candle filter; tick stream stays primary)
input bool     InpUseContextTrend      = false;     // BUY only above EMA / SELL only below EMA
input ENUM_TIMEFRAMES InpContextTimeframe = PERIOD_H1; // Context timeframe
input int      InpContextMAPeriod      = 50;        // EMA period (closed bars)
input bool     InpUseVolatilityFilter  = false;     // Block entries while ATR > max
input int      InpATRPeriod            = 14;        // ATR period
input double   InpMaxATRPoints         = 0.0;       // Max ATR (points); required>0 when vol filter on

//--- Protection
input int      InpCooldownSeconds      = 5;
input int      InpMaxTradesPerDay      = 50;
input int      InpMaxConsecutiveLosses = 5;
input double   InpMaxDailyLossMoney    = 10.0;
input bool     InpResetConsecOnNewDay  = true;      // Clear loss streak + lock on a new server day

//--- Logging / journal
input int      InpLogLevel             = 3;         // 0=OFF 1=ERR 2=WARN 3=INFO 4=DEBUG
input bool     InpEnableCSVJournal     = true;
input string   InpCSVFile              = "TickMomentumJournal.csv";

#define EA_VERSION "1.40"

CStrategyController g_ctl;

//+------------------------------------------------------------------+
int OnInit()
  {
   TMBConfig cfg;
   cfg.SetDefaults();
   cfg.lot=InpLotSize; cfg.slMoney=InpSLMoney; cfg.tpMoney=InpTPMoney;
   cfg.magic=InpMagicNumber; cfg.dev=InpDeviationPoints; cfg.maxPositions=InpMaxPositions;
   cfg.tpMode=(ENUM_TMB_TP_MODE)InpTPMode;
   cfg.commissionPerLot=InpCommissionPerLot; cfg.commissionDoubled=InpCommissionDoubledRT;
   cfg.tickWindow=InpTickWindow; cfg.minRatio=InpMinimumDirectionalRatio;
   cfg.minMovePoints=InpMinimumPriceMovePoints;
   cfg.minTicksPerSec=InpMinimumTicksPerSecond; cfg.maxTicksPerSec=InpMaximumTicksPerSecond;
   cfg.maxDispPoints=InpMaximumDisplacementPoints; cfg.maxWindowSec=InpMaximumWindowSeconds;
   cfg.maxSpreadPoints=InpMaxSpreadPoints;
   cfg.useBreakEven=InpEnableBreakEven; cfg.beBufferMoney=InpBreakEvenBufferMoney;
   cfg.useTrailing=InpEnableTrailing; cfg.trailDistanceMoney=InpTrailingDistanceMoney;
   cfg.cooldownSec=InpCooldownSeconds; cfg.maxTradesPerDay=InpMaxTradesPerDay;
   cfg.maxConsecutiveLosses=InpMaxConsecutiveLosses;
   cfg.maxDailyLossMoney=InpMaxDailyLossMoney;
   cfg.resetConsecOnNewDay=InpResetConsecOnNewDay;
   cfg.useRiskSizing=InpUseRiskSizing; cfg.riskPercent=InpRiskPercent;
   cfg.riskMaxLot=InpRiskMaxLot;
   cfg.ctxTrend=InpUseContextTrend; cfg.ctxTF=InpContextTimeframe;
   cfg.ctxMAPeriod=InpContextMAPeriod;
   cfg.ctxVolatility=InpUseVolatilityFilter; cfg.ctxATRPeriod=InpATRPeriod;
   cfg.ctxMaxATRPoints=InpMaxATRPoints;
   cfg.logLevel=InpLogLevel; cfg.csvJournal=InpEnableCSVJournal; cfg.csvFile=InpCSVFile;

   if(!g_ctl.Configure(cfg))
     {
      Print("[TMB] Invalid configuration. Init failed.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!g_ctl.InitOnSymbol(_Symbol))
     {
      Print("[TMB] Symbol init failed for ", _Symbol);
      return INIT_FAILED;
     }

   PrintFormat("[TMB] v%s started on %s magic=%I64d lot=%.2f SL=$%.2f TP=$%.2f win=%d ratio>=%.2f move>=%dpts tps>=%.1f spread<=%d BE=%s/%s trail=%s/%s TPmode=%d risk=%s/%.2f%%/max%.2f",
      EA_VERSION, _Symbol, InpMagicNumber, InpLotSize, InpSLMoney, InpTPMoney, InpTickWindow,
      InpMinimumDirectionalRatio, InpMinimumPriceMovePoints, InpMinimumTicksPerSecond,
      InpMaxSpreadPoints, (InpEnableBreakEven?"ON":"OFF"), DoubleToString(InpBreakEvenBufferMoney,2),
      (InpEnableTrailing?"ON":"OFF"), DoubleToString(InpTrailingDistanceMoney,2), InpTPMode,
      (InpUseRiskSizing?"ON":"OFF"), InpRiskPercent, InpRiskMaxLot);
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   g_ctl.Cleanup();
   PrintFormat("[TMB] Stopped. reason=%d", reason);
  }
//+------------------------------------------------------------------+
void OnTick()
  {
   g_ctl.OnTick();
  }
//+------------------------------------------------------------------+
//| Authoritative close accounting from deal history.                |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.symbol != _Symbol) return;
   ulong dealTicket = trans.deal;
   if(dealTicket == 0) return;
   if(!HistoryDealSelect(dealTicket)) return;
   long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   long magic     = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(magic != InpMagicNumber) return;               // not ours
   if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_INOUT) return; // closing side only

   double price  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                 + HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double comm   = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION); // negative or 0
   double actualComm = MathAbs(comm); // closing-leg commission; opening leg added below

   // Add opening-leg commission for true round-trip actual: find matching IN deal
   ulong openDeal = FindOpeningDeal(dealTicket);
   if(openDeal != 0 && HistoryDealSelect(openDeal))
      actualComm += MathAbs(HistoryDealGetDouble(openDeal, DEAL_COMMISSION));

   //--- Reason is derived from the journal record (placed TP vs last SL vs BE/trail
   //--- state); a hint of UNKNOWN means "let the journal decide".
   ENUM_TMB_EXIT_REASON reason = TMB_EXIT_UNKNOWN;
   datetime nowServer = TimeCurrent();
   string dayKey = TimeToString(nowServer, TIME_DATE);
   g_ctl.HandleExternalClose(price, profit, actualComm, reason, nowServer, dayKey);
  }

ulong FindOpeningDeal(ulong closeDeal)
  {
   // Best effort: the most recent DEAL_ENTRY_IN with same symbol+magic before closeDeal.
   //deal tickets increment; scan back a bounded window.
   ulong best = 0;
   datetime tClose = 0;
   if(HistoryDealSelect(closeDeal)) tClose = (datetime)HistoryDealGetInteger(closeDeal, DEAL_TIME);
   for(int i = (int)MathMin((double)HistoryDealsTotal(), 500.0) - 1; i >= 0; i--)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk == 0 || tk >= closeDeal) continue;
      if(!HistoryDealSelect(tk)) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagicNumber) continue;
      if(HistoryDealGetInteger(tk, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      best = tk;
      break; // most recent IN (HistoryDealsTotal order is chronological)
     }
   return best;
  }

//+------------------------------------------------------------------+
//| Optimization criterion: net profit of THIS EA on THIS symbol,    |
//| read from deal history (authoritative, commission included).      |
//+------------------------------------------------------------------+
double OnTester()
   {
   double net = 0.0;
   datetime from = 0, to = TimeCurrent();
   if(!HistorySelect(from, to)) return 0.0;
   int total = HistoryDealsTotal();
   for(int i=0; i<total; i++)
     {
      ulong tk = HistoryDealGetTicket(i);
      if(tk==0) continue;
      if(!HistoryDealSelect(tk)) continue;
      if(HistoryDealGetString(tk, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(tk, DEAL_MAGIC) != InpMagicNumber) continue;
      net += HistoryDealGetDouble(tk, DEAL_PROFIT)
           + HistoryDealGetDouble(tk, DEAL_SWAP)
           + HistoryDealGetDouble(tk, DEAL_COMMISSION);
     }
   return net;
  }
//+------------------------------------------------------------------+
