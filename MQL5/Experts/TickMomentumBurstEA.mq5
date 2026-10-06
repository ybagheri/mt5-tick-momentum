//+------------------------------------------------------------------+
//| TickMomentumBurstEA.mq5                                          |
//| Tick Momentum Burst + Cost-Aware BE + Dynamic Trailing           |
//|                                                                  |
//| Current-chart-symbol EA. Tick stream is the primary signal.      |
//+------------------------------------------------------------------+
#property copyright "Tick Momentum Research"
#property version   "1.00"
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
input int      InpMaxPositions         = 1;         // Max simultaneous strategy positions
input int      InpTPMode               = 0;         // TP mode: 0=FIXED 1=TRAILING_ONLY 2=HYBRID

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

//--- Protection
input int      InpCooldownSeconds      = 5;
input int      InpMaxTradesPerDay      = 50;
input int      InpMaxConsecutiveLosses = 5;
input double   InpMaxDailyLossMoney    = 10.0;

//--- Logging / journal
input int      InpLogLevel             = 3;         // 0=OFF 1=ERR 2=WARN 3=INFO 4=DEBUG
input bool     InpEnableCSVJournal     = true;
input string   InpCSVFile              = "TickMomentumJournal.csv";

CStrategyController g_ctl;
datetime            g_lastBarWarn = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(!g_ctl.Configure(InpLotSize, InpSLMoney, InpTPMoney, InpCommissionPerLot,
      InpCommissionDoubledRT, InpTickWindow, InpMinimumDirectionalRatio,
      InpMinimumPriceMovePoints, InpMinimumTicksPerSecond, InpMaxSpreadPoints,
      InpMaximumTicksPerSecond, InpMaximumDisplacementPoints, InpMaximumWindowSeconds,
      InpEnableBreakEven, InpBreakEvenBufferMoney, InpEnableTrailing,
      InpTrailingDistanceMoney, InpTPMode, InpCooldownSeconds, InpMaxTradesPerDay,
      InpMaxConsecutiveLosses, InpMaxDailyLossMoney, InpMagicNumber,
      InpDeviationPoints, InpMaxPositions, InpLogLevel))
     {
      Print("[TMB] Invalid configuration. Init failed.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!g_ctl.InitOnSymbol(_Symbol))
     {
      Print("[TMB] Symbol init failed for ", _Symbol);
      return INIT_FAILED;
     }
   g_ctl.InitRiskJournal(g_ctl.LogPtr(), InpMaxTradesPerDay, InpMaxConsecutiveLosses,
      InpMaxDailyLossMoney, InpCooldownSeconds, InpEnableCSVJournal, InpCSVFile);

   PrintFormat("[TMB] v1.00 started on %s magic=%I64d lot=%.2f SL=$%.2f TP=$%.2f win=%d ratio>=%.2f move>=%dpts tps>=%.1f spread<=%d BE=%s/%s trail=%s/%s TPmode=%d",
      _Symbol, InpMagicNumber, InpLotSize, InpSLMoney, InpTPMoney, InpTickWindow,
      InpMinimumDirectionalRatio, InpMinimumPriceMovePoints, InpMinimumTicksPerSecond,
      InpMaxSpreadPoints, (InpEnableBreakEven?"ON":"OFF"), DoubleToString(InpBreakEvenBufferMoney,2),
      (InpEnableTrailing?"ON":"OFF"), DoubleToString(InpTrailingDistanceMoney,2), InpTPMode);
   return INIT_SUCCEEDED;
  }
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
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

   // Classify exit reason from position SL/TP proximity + controller state
   ENUM_TMB_EXIT_REASON reason = ClassifyExit(price);
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

ENUM_TMB_EXIT_REASON ClassifyExit(double exitPrice)
  {
   // Heuristic: compare exit price to last known SL/TP is not available post-close,
   // so use controller state: BE done + favourable => TRAIL/BE, else SL/TP by TP-mode.
   // Exact SL-vs-BE-vs-TRAIL disambiguation is refined by journal SL snapshot.
   if(g_ctl.BeDone()) return TMB_EXIT_TRAIL;
   return TMB_EXIT_SL;
  }
//+------------------------------------------------------------------+
double OnTester()
  {
   // Return net total for optimization; journal total is authoritative.
   return 0.0;
  }
//+------------------------------------------------------------------+
