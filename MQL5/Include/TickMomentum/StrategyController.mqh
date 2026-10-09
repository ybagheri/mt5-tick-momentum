//+------------------------------------------------------------------+
//| StrategyController.mqh - state machine + orchestration           |
//+------------------------------------------------------------------+
#ifndef __TMB_CONTROLLER_MQH__
#define __TMB_CONTROLLER_MQH__

#include "TickCollector.mqh"
#include "MarketMetrics.mqh"
#include "MomentumDetector.mqh"
#include "SignalEngine.mqh"
#include "SymbolInfoCache.mqh"
#include "MoneyMath.mqh"
#include "CostCalculator.mqh"
#include "PositionSizer.mqh"
#include "TradeExecutor.mqh"
#include "BreakEvenManager.mqh"
#include "TrailingManager.mqh"
#include "RiskManager.mqh"
#include "TradeJournal.mqh"
#include "ContextFilter.mqh"
#include "Logger.mqh"
#include "Enums.mqh"

//--- Single configuration entry point: one struct, one place to extend.
struct TMBConfig
  {
   // trading
   double            lot;            double slMoney;        double tpMoney;
   long              magic;          int dev;              int maxPositions;
   ENUM_TMB_TP_MODE  tpMode;
   // commission
   double            commissionPerLot; bool commissionDoubled;
   // momentum
   int               tickWindow;     double minRatio;      int minMovePoints;
   double            minTicksPerSec; double maxTicksPerSec;
   int               maxDispPoints;  int maxWindowSec;     int maxSpreadPoints;
   // breakeven / trailing
   bool              useBreakEven;   double beBufferMoney;
   bool              useTrailing;    double trailDistanceMoney;
   // risk
   int               cooldownSec;    int maxTradesPerDay;  int maxConsecutiveLosses;
   double            maxDailyLossMoney; bool resetConsecOnNewDay;
   // risk-based sizing
   bool              useRiskSizing;  double riskPercent;   double riskMaxLot;
   // context filter
   bool              ctxTrend;       ENUM_TIMEFRAMES ctxTF; int ctxMAPeriod;
   bool              ctxVolatility;  int ctxATRPeriod;     double ctxMaxATRPoints;
   // logging
   int               logLevel;       bool csvJournal;      string csvFile;

   void              SetDefaults(void)
     {
      lot=0.01; slMoney=1.0; tpMoney=2.0;
      magic=26061001; dev=20; maxPositions=1; tpMode=TMB_TP_FIXED;
      commissionPerLot=6.0; commissionDoubled=true;
      tickWindow=50; minRatio=0.70; minMovePoints=10;
      minTicksPerSec=1.0; maxTicksPerSec=0.0;
      maxDispPoints=0; maxWindowSec=0; maxSpreadPoints=100;
      useBreakEven=true; beBufferMoney=0.02;
      useTrailing=true; trailDistanceMoney=0.50;
      cooldownSec=5; maxTradesPerDay=50; maxConsecutiveLosses=5;
      maxDailyLossMoney=10.0; resetConsecOnNewDay=true;
      useRiskSizing=false; riskPercent=0.5; riskMaxLot=1.0;
      ctxTrend=false; ctxTF=PERIOD_H1; ctxMAPeriod=50;
      ctxVolatility=false; ctxATRPeriod=14; ctxMaxATRPoints=0.0;
      logLevel=3; csvJournal=true; csvFile="TickMomentumJournal.csv";
     }
  };

class CStrategyController
  {
private:
   //--- modules
   CTickDataCollector    m_ticks;
   CMarketMetrics        m_metrics;
   CMomentumDetector     m_detector;
   CSignalEngine         m_signal;
   CSymbolInfoCache      m_sym;
   CMoneyMath            m_math;
   CCostCalculator       m_cost;
   CPositionSizer        m_sizer;
   CTradeExecutor        m_exec;
   CBreakEvenManager     m_be;
   CTrailingStopManager  m_trail;
   CRiskManager          m_risk;
   CTradeJournal         m_journal;
   CMarketContextFilter  m_ctx;
   CLogger               m_log;

   TMBConfig         m_cfg;

ENUM_TMB_STATE    m_state;
   ulong             m_ticket;
   bool              m_beDone;
   bool              m_trailActive;
   TBMetrics         m_lastMetrics;
   bool              m_haveMetrics;

 public:
                     CStrategyController(void): m_state(TMB_ST_WAITING), m_ticket(0),
                      m_beDone(false), m_trailActive(false), m_haveMetrics(false)
      { ZeroMemory(m_lastMetrics); }

   CLogger          *LogPtr(void) { return &m_log; }
   CRiskManager     *RiskPtr(void) { return &m_risk; }
   TMBConfig        *CfgPtr(void)  { return &m_cfg; }

   bool              Configure(TMBConfig &cfg)
     {
      m_cfg = cfg;
      m_log.Init((ENUM_TMB_LOG_LEVEL)m_cfg.logLevel, "TMB");
      return Validate();
     }

   bool              Validate(void)
     {
      if(m_cfg.lot<=0) { m_log.Error("Lot must be > 0"); return false; }
      if(m_cfg.slMoney<=0) { m_log.Error("SL money must be > 0"); return false; }
      if(m_cfg.tpMoney<0) { m_log.Error("TP money must be >= 0"); return false; }
      if(m_cfg.tickWindow<5) { m_log.Error("TickWindow too small"); return false; }
      if(m_cfg.minRatio<0.5 || m_cfg.minRatio>1.0) { m_log.Error("MinRatio must be in [0.5,1]"); return false; }
      if(m_cfg.minMovePoints<=0) { m_log.Error("MinMovePoints must be > 0"); return false; }
      if(m_cfg.maxSpreadPoints<0) { m_log.Error("MaxSpreadPoints must be >= 0"); return false; }
      //--- One position at a time by design (no grid/averaging). The tick pipeline
      //--- manages a single ticket, so a higher cap would be silently ignored.
      if(m_cfg.maxPositions!=1)
        { m_log.Error("MaxPositions must be 1 (single-position design)"); return false; }
      if(m_cfg.cooldownSec<0) { m_log.Error("CooldownSeconds must be >= 0"); return false; }
      if(m_cfg.tpMode==TMB_TP_FIXED && m_cfg.tpMoney<=0)
        { m_log.Error("FIXED TP mode requires TP money > 0"); return false; }
      if(m_cfg.tpMode==TMB_TP_TRAILING_ONLY && !m_cfg.useTrailing)
        { m_log.Error("TRAILING_ONLY requires trailing enabled"); return false; }
      if(m_cfg.useRiskSizing)
        {
         if(m_cfg.riskPercent<=0 || m_cfg.riskPercent>10.0) { m_log.Error("RiskPercent must be in (0,10]"); return false; }
         if(m_cfg.riskMaxLot<=0) { m_log.Error("RiskMaxLot must be > 0"); return false; }
        }
      if(m_cfg.ctxTrend && m_cfg.ctxMAPeriod<2) { m_log.Error("ContextMAPeriod must be >= 2"); return false; }
      if(m_cfg.ctxVolatility)
        {
         if(m_cfg.ctxATRPeriod<2) { m_log.Error("ATRPeriod must be >= 2"); return false; }
         if(m_cfg.ctxMaxATRPoints<=0) { m_log.Error("MaxATRPoints must be > 0 when vol filter on"); return false; }
        }
      return true;
     }

   bool              InitOnSymbol(string symbol)
     {
      if(!m_sym.Refresh(symbol)) { m_log.Error("Bad symbol props for " + symbol); return false; }
      double normLot = m_sym.NormalizeVolume(m_cfg.lot);
      if(normLot < m_sym.VolMin()-1e-12) { m_log.Error("Lot below broker minimum"); return false; }
      m_math.Init(&m_sym);
      //--- metrics need a FULL tick window before they are trustworthy
      m_metrics.Init(m_sym.Point(), m_cfg.tickWindow);
      m_cost.Init(&m_sym, &m_math, m_cfg.commissionPerLot, m_cfg.commissionDoubled);
      m_ticks.Init(symbol, m_cfg.tickWindow);
      m_detector.Init(m_cfg.minRatio, m_cfg.minMovePoints, m_cfg.minTicksPerSec,
                      m_sym.Point(), (double)m_cfg.maxWindowSec);
      m_signal.Init(m_cfg.maxSpreadPoints, m_cfg.maxPositions);
      m_sizer.Init(&m_sym, m_cfg.lot, m_cfg.riskPercent, m_cfg.riskMaxLot);
      m_exec.Init(&m_sym, &m_math, &m_log, m_cfg.magic, m_cfg.dev);
      m_be.Init(&m_sym, &m_math, &m_cost, &m_log, m_cfg.useBreakEven, m_cfg.beBufferMoney, m_cfg.magic);
      m_trail.Init(&m_sym, &m_math, &m_cost, &m_log, m_cfg.useTrailing,
                   m_cfg.trailDistanceMoney, m_cfg.magic, true);
      if(!m_ctx.Init(symbol, m_cfg.ctxTF, m_sym.Point(), m_cfg.ctxTrend, m_cfg.ctxMAPeriod,
                     m_cfg.ctxVolatility, m_cfg.ctxATRPeriod, m_cfg.ctxMaxATRPoints, &m_log))
        { m_log.Error("Context filter init failed"); return false; }
      //--- risk + journal need the configured log level; safe to do here
      m_risk.Init(&m_log, m_cfg.maxTradesPerDay, m_cfg.maxConsecutiveLosses,
                  m_cfg.maxDailyLossMoney, m_cfg.cooldownSec, m_cfg.resetConsecOnNewDay);
      m_journal.Init(&m_log, m_cfg.csvJournal, m_cfg.csvFile);
      m_ticks.Backfill();
      ReattachToExistingPosition();
      m_log.Info(StringFormat("Init %s digits=%d pt=%s ts=%s tv=%s vol=[%s/%s/%s] stops=%d freeze=%d",
         symbol, m_sym.Digits(), DoubleToString(m_sym.Point(),8), DoubleToString(m_sym.TickSize(),8),
         DoubleToString(m_sym.TickValue(),4), DoubleToString(m_sym.VolMin(),2),
         DoubleToString(m_sym.VolMax(),2), DoubleToString(m_sym.VolStep(),2),
         m_sym.StopsLevelPoints(), m_sym.FreezeLevelPoints()));
      return true;
     }

   void              Cleanup(void) { m_ctx.Cleanup(); }

   void              ReattachToExistingPosition(void)
     {
      ulong t = m_exec.FindMyPositionTicket();
      if(t!=0)
        {
         m_ticket=t; m_state=TMB_ST_OPEN; m_beDone=false; m_trailActive=false;
         m_log.Warning(StringFormat("Reattached to existing position #%I64u (no journal record; "
                                    "exit economics will come from deal history)", t));
        }
     }

   //--- Called by EA after detecting a position close (via OnTradeTransaction).
   //--- riskHint: 1 = we initiated the close (SL/TP/BE/trailing), 0 = unknown/manual.
   //--- Risk state is ONLY advanced when the journal actually tracks the trade,
   //--- otherwise a stray deal would award a phantom breakeven and reset the loss streak.
   double              HandleExternalClose(double exitPrice, double grossProfit, double actualComm,
                                          ENUM_TMB_EXIT_REASON reasonHint, datetime nowServer, string dayKey)
     {
      //--- Deal history is authoritative for economics; the journal only records it.
      double net = grossProfit - actualComm;
      if(m_journal.HasOpen())
         m_journal.OnClose(exitPrice, grossProfit, actualComm, reasonHint, nowServer,
                           m_sym.TickValue(), m_sym.TickSize());
      else
         m_log.Warning("Close without journal record (restart?); risk updated from deal only");
      m_risk.NotifyClose(nowServer, net, dayKey);
      m_ticket=0; m_beDone=false; m_trailActive=false; m_state=TMB_ST_COOLDOWN;
      m_be.ClearEffective(); m_trail.ClearEffective();
      return net;
     }

   void              OnTick(void)
     {
      string symbol = m_sym.Symbol();
      datetime nowServer = TimeCurrent();
      string dayKey = TimeToString(nowServer, TIME_DATE);
      m_risk.OnNewDay(dayKey);

      // 1) feed live tick (even during open position: needed for MFE/journal/trailing)
      bool duplicate=false;
      if(!m_ticks.OnMarketTick(duplicate)) return;
      TMBTick latest; if(!m_ticks.GetLatest(latest)) return;
      //--- Position management must run on EVERY tick, but signal metrics only
      //--- change when a genuinely new tick arrives.
      if(!duplicate)
        {
         m_lastMetrics = m_metrics.Compute(m_ticks);
         m_haveMetrics = m_lastMetrics.ready;
        }

      // 2) ALWAYS manage open position first (spec section 22)
      ulong managed = m_exec.FindMyPositionTicket();
      if(managed!=0)
        {
         m_ticket=managed;
         if(m_state==TMB_ST_WAITING || m_state==TMB_ST_COOLDOWN) m_state=TMB_ST_OPEN;
         ManageOpenPosition();
         // update journal excursion + exit-classification context
         if(PositionSelectByTicket(m_ticket))
           {
            long ptype = PositionGetInteger(POSITION_TYPE);
            m_journal.OnTickInTrade(latest.bid, latest.ask, ptype==POSITION_TYPE_BUY,
                                    PositionGetDouble(POSITION_SL));
            m_journal.SetManagementState(PositionGetDouble(POSITION_SL), m_beDone,
                                         m_trailActive);
           }
         return; // one position at a time: never enter while managing one
        }
      else
        {
         // position disappeared (SL/TP hit or manual close): OnTradeTransaction does the
         // authoritative close accounting; here only clear local state if it already did.
         if(m_ticket!=0 && !m_journal.HasOpen())
           { m_ticket=0; m_beDone=false; m_trailActive=false; m_state=TMB_ST_COOLDOWN;
             m_be.ClearEffective(); m_trail.ClearEffective(); }
        }

      // 3) entry gates. A duplicate tick carries no new information and no new
      //--- price, so re-evaluating could only repeat a rejected/attempted entry.
      if(duplicate) return;
      MqlTick tk; if(!SymbolInfoTick(symbol, tk)) return;
      int spreadPts = m_cost.SpreadPoints(tk.bid, tk.ask);
      bool inCooldown = m_risk.InCooldown(nowServer);
      bool riskLocked = m_risk.IsLocked();
      bool abnormal = false;
      if(m_haveMetrics)
         abnormal = m_risk.AbnormalMarket(m_lastMetrics.ticksPerSecond,
                                           m_lastMetrics.displacementPoints,
                                           m_cfg.maxTicksPerSec, m_cfg.maxDispPoints);
      TBBurstResult burst; burst.Reset();
      if(m_haveMetrics) burst = m_detector.Evaluate(m_lastMetrics);
      int myPos = m_exec.CountMyPositions();
      TBSignal sig = m_signal.Evaluate(burst, spreadPts, myPos, inCooldown, riskLocked, abnormal);

      if(sig.signal==TMB_SIG_NONE)
        {
         // light debug only to avoid journal flooding
         // m_log.Debug("Reject: " + sig.rejectReason);
         if(m_state!=TMB_ST_COOLDOWN) m_state=TMB_ST_WAITING;
         return;
        }

      // 3b) optional candle context (trend alignment / volatility cap)
      if(m_ctx.IsActive())
        {
         bool wantBuy = (sig.signal==TMB_SIG_BUY);
         string ctxReason="";
         bool ctxOk = wantBuy ? m_ctx.BuyAllowed(ctxReason) : m_ctx.SellAllowed(ctxReason);
         if(!ctxOk)
           {
            m_log.Debug("Context reject: " + ctxReason);
            if(m_state!=TMB_ST_COOLDOWN) m_state=TMB_ST_WAITING;
            return;
           }
        }

      // 4) execute: fixed lot, or risk-scaled volume with k-scaled money targets
      // (price geometry identical to fixed mode; only money scales by k)
      m_state=TMB_ST_SIGNAL;
      double vol = m_sizer.ComputeVolume();
      double scaleK = 1.0;
      if(m_cfg.useRiskSizing)
        {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         TMBRiskVolume rv = m_sizer.ComputeRiskVolume(equity, m_cfg.slMoney);
         if(rv.volume<=0)
           {
            m_log.Warning("Risk sizing rejected: " + rv.note + " (no trade)");
            m_state=TMB_ST_WAITING; return;
           }
         vol = rv.volume; scaleK = rv.scaleK;
         if(rv.capped)
            m_log.Warning(StringFormat("Risk volume capped at %.2f (k=%.2f, SL money=%.2f)",
               vol, scaleK, rv.riskMoney));
         m_be.SetEffectiveBuffer(m_cfg.beBufferMoney*scaleK);
         m_trail.SetEffectiveDistance(m_cfg.trailDistanceMoney*scaleK);
        }
      double slEff = m_cfg.slMoney*scaleK, tpEff = m_cfg.tpMoney*scaleK;
      string verr="";
      if(!m_sizer.ValidateVolume(vol, verr))
        { m_log.Error("Bad volume: "+verr); m_state=TMB_ST_WAITING; return; }
      bool isBuy = (sig.signal==TMB_SIG_BUY);
      m_log.Info(StringFormat("SIGNAL %s ratio=%.2f disp=%dpts tps=%.1f spread=%d vol=%.2f k=%.2f",
         (isBuy?"BUY":"SELL"), m_lastMetrics.dirRatio, m_lastMetrics.displacementPoints,
         m_lastMetrics.ticksPerSecond, spreadPts, vol, scaleK));
      m_state=TMB_ST_ORDER;
      TBOpenResult or_ = m_exec.OpenMarket(isBuy, vol, slEff, tpEff, m_cfg.tpMode);
      if(!or_.ok || or_.ticket==0)
        {
         if(or_.ok) m_log.Warning("Open reported success but no position ticket found");
         m_state=TMB_ST_WAITING; return;
        }
      m_ticket = or_.ticket;
      m_beDone = false;
      m_trailActive = false;
      m_state = TMB_ST_OPEN;
      double estComm = m_cost.EstimateRoundTripCommission(vol);
      m_journal.OnOpen(m_ticket, symbol, (isBuy?1:-1), vol, or_.price, or_.sl, or_.tp,
                       spreadPts, estComm, m_lastMetrics, nowServer, scaleK);
      m_risk.NotifyOpen(dayKey);
      m_log.Info(StringFormat("OPEN #%I64u %s %.2f @ %s SL=%s TP=%s", m_ticket, symbol, vol,
         DoubleToString(or_.price, m_sym.Digits()), DoubleToString(or_.sl, m_sym.Digits()),
         DoubleToString(or_.tp, m_sym.Digits())));
     }

   void              ManageOpenPosition(void)
     {
      if(m_ticket==0) return;
      bool beNow = m_be.Manage(m_ticket);
      if(beNow && !m_beDone)
        { m_beDone=true; m_state=TMB_ST_BE; }
      else if(beNow && m_state==TMB_ST_BE && !m_trailActive)
        { m_state=TMB_ST_COST_COVERED; }

      if(beNow && m_cfg.useTrailing)
        {
         if(m_trail.Manage(m_ticket, m_beDone))
           { m_trailActive=true; m_state=TMB_ST_TRAIL; }
        }
     }

   //--- accessors
   ENUM_TMB_STATE    State(void) const { return m_state; }
   ulong             Ticket(void) const { return m_ticket; }
   bool              BeDone(void) const { return m_beDone; }
   TBMetrics         LastMetrics(void) const { return m_lastMetrics; }
  };

#endif
