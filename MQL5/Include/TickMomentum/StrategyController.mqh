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
#include "Logger.mqh"

enum ENUM_TMB_STATE
  {
   TMB_ST_WAITING=0,
   TMB_ST_SIGNAL=1,
   TMB_ST_ORDER=2,
   TMB_ST_OPEN=3,
   TMB_ST_COST_COVERED=4,
   TMB_ST_BE=5,
   TMB_ST_TRAIL=6,
   TMB_ST_COOLDOWN=7
  };

enum ENUM_TMB_TP_MODE { TMB_TP_FIXED=0, TMB_TP_TRAILING_ONLY=1, TMB_TP_HYBRID=2 };

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
   CLogger               m_log;

   //--- config (mirrors inputs)
   double            m_lot, m_slMoney, m_tpMoney, m_commPerLot;
   int               m_tickWindow;
   double            m_minRatio, m_minTps, m_maxTps;
   int               m_minMovePts, m_maxSpreadPts, m_maxDispPts;
   int               m_maxWindowSec;
   bool              m_useBE; double m_beBuf;
   bool              m_useTrail; double m_trailMoney;
   int               m_tpMode;
   int               m_cooldown, m_maxTradesDay, m_maxConsecLoss;
   double            m_maxDailyLoss;
   long              m_magic; int m_dev; int m_maxPos;
   bool              m_commDoubled;
   bool              m_useRisk; double m_riskPct; double m_riskMaxLot;

   ENUM_TMB_STATE    m_state;
   ulong             m_ticket;
   bool              m_beDone;
   TBMetrics         m_lastMetrics;
   bool              m_haveMetrics;

public:
                     CStrategyController(void): m_state(TMB_ST_WAITING), m_ticket(0),
                      m_beDone(false), m_haveMetrics(false) { ZeroMemory(m_lastMetrics); }

   CLogger          *LogPtr(void) { return &m_log; }
   CRiskManager     *RiskPtr(void) { return &m_risk; }

   bool              Configure(
      double lot, double slM, double tpM, double commPerLot, bool commDoubled,
      int tickWindow, double minRatio, int minMovePts, double minTps,
      int maxSpreadPts, double maxTps, int maxDispPts, int maxWindowSec,
      bool useBE, double beBuf, bool useTrail, double trailMoney, int tpMode,
       int cooldown, int maxTradesDay, int maxConsecLoss, double maxDailyLoss,
       long magic, int dev, int maxPos, int logLevel,
       bool useRisk, double riskPct, double riskMaxLot)
     {
      m_lot=lot; m_slMoney=slM; m_tpMoney=tpM; m_commPerLot=commPerLot; m_commDoubled=commDoubled;
      m_tickWindow=tickWindow; m_minRatio=minRatio; m_minMovePts=minMovePts; m_minTps=minTps;
      m_maxSpreadPts=maxSpreadPts; m_maxTps=maxTps; m_maxDispPts=maxDispPts; m_maxWindowSec=maxWindowSec;
      m_useBE=useBE; m_beBuf=beBuf; m_useTrail=useTrail; m_trailMoney=trailMoney; m_tpMode=tpMode;
      m_cooldown=cooldown; m_maxTradesDay=maxTradesDay; m_maxConsecLoss=maxConsecLoss;
      m_maxDailyLoss=maxDailyLoss; m_magic=magic; m_dev=dev; m_maxPos=maxPos;
      m_useRisk=useRisk; m_riskPct=riskPct; m_riskMaxLot=riskMaxLot;
      m_log.Init((ENUM_TMB_LOG_LEVEL)logLevel, "TMB");
      return Validate();
     }

   bool              Validate(void)
     {
      if(m_lot<=0) { m_log.Error("Lot must be > 0"); return false; }
      if(m_slMoney<=0) { m_log.Error("SL money must be > 0"); return false; }
      if(m_tpMoney<0) { m_log.Error("TP money must be >= 0"); return false; }
      if(m_tickWindow<5) { m_log.Error("TickWindow too small"); return false; }
      if(m_minRatio<0.5 || m_minRatio>1.0) { m_log.Error("MinRatio must be in [0.5,1]"); return false; }
      if(m_minMovePts<=0) { m_log.Error("MinMovePoints must be > 0"); return false; }
      if(m_maxPos<1) { m_log.Error("MaxPositions must be >= 1"); return false; }
      if(m_tpMode==TMB_TP_TRAILING_ONLY && !m_useTrail)
        { m_log.Error("TRAILING_ONLY requires trailing enabled"); return false; }
      if(m_useRisk)
        {
         if(m_riskPct<=0 || m_riskPct>10.0) { m_log.Error("RiskPct must be in (0,10]"); return false; }
         if(m_riskMaxLot<=0) { m_log.Error("RiskMaxLot must be > 0"); return false; }
        }
      return true;
     }

   bool              InitOnSymbol(string symbol)
     {
      if(!m_sym.Refresh(symbol)) { m_log.Error("Bad symbol props for " + symbol); return false; }
      double normLot = m_sym.NormalizeVolume(m_lot);
      string verr="";
      if(normLot < m_sym.VolMin()-1e-12) { m_log.Error("Lot below broker minimum"); return false; }
      m_math.Init(&m_sym);
      m_metrics.Init(m_sym.Point());
      m_cost.Init(&m_sym, &m_math, m_commPerLot, m_commDoubled);
      m_ticks.Init(symbol, m_tickWindow);
      m_detector.Init(m_minRatio, m_minMovePts, m_minTps, m_sym.Point(), (double)m_maxWindowSec);
      m_signal.Init(m_maxSpreadPts, m_maxPos);
      m_sizer.Init(&m_sym, m_lot, m_riskPct, m_riskMaxLot);
      m_exec.Init(&m_sym, &m_math, &m_log, m_magic, m_dev);
      m_be.Init(&m_sym, &m_math, &m_cost, &m_log, m_useBE, m_beBuf, m_magic);
      m_trail.Init(&m_sym, &m_math, &m_cost, &m_log, m_useTrail, m_trailMoney, m_magic, true);
      // risk + journal inited by EA (needs csv settings); do safe defaults here
      m_ticks.Backfill();
      ReattachToExistingPosition();
      m_log.Info(StringFormat("Init %s digits=%d pt=%s ts=%s tv=%s vol=[%s/%s/%s] stops=%d freeze=%d",
         symbol, m_sym.Digits(), DoubleToString(m_sym.Point(),8), DoubleToString(m_sym.TickSize(),8),
         DoubleToString(m_sym.TickValue(),4), DoubleToString(m_sym.VolMin(),2),
         DoubleToString(m_sym.VolMax(),2), DoubleToString(m_sym.VolStep(),2),
         m_sym.StopsLevelPoints(), m_sym.FreezeLevelPoints()));
      return true;
     }

   void              InitRiskJournal(CLogger *extLog, int maxTradesDay, int maxConsecLoss,
                                    double maxDailyLoss, int cooldown,
                                    bool csvEnabled, string csvFile)
     {
      // risk uses internal logger (already configured)
      m_risk.Init(&m_log, maxTradesDay, maxConsecLoss, maxDailyLoss, cooldown);
      m_journal.Init(&m_log, csvEnabled, csvFile);
     }

   void              ReattachToExistingPosition(void)
     {
      ulong t = m_exec.FindMyPositionTicket();
      if(t!=0)
        {
         m_ticket=t; m_state=TMB_ST_OPEN; m_beDone=false;
         m_log.Warning(StringFormat("Reattached to existing position #%I64u", t));
        }
     }

   //--- Called by EA after detecting a position close (via OnTradeTransaction)
   double              HandleExternalClose(double exitPrice, double grossProfit, double actualComm,
                                          ENUM_TMB_EXIT_REASON reason, datetime nowServer, string dayKey)
     {
      double net = 0.0;
      if(m_journal.HasOpen())
         net = m_journal.OnClose(exitPrice, grossProfit, actualComm, reason, nowServer,
                                 m_sym.TickValue(), m_sym.TickSize());
      m_risk.NotifyClose(nowServer, net, dayKey);
      m_ticket=0; m_beDone=false; m_state=TMB_ST_COOLDOWN;
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
      if(!m_ticks.OnMarketTick()) return;
      TMBTick latest; m_ticks.GetLatest(latest);
      m_lastMetrics = m_metrics.Compute(m_ticks);
      m_haveMetrics = m_lastMetrics.ready;

      // 2) ALWAYS manage open position first (spec section 22)
      ulong managed = m_exec.FindMyPositionTicket();
      if(managed!=0)
        {
         m_ticket=managed;
         if(m_state==TMB_ST_WAITING || m_state==TMB_ST_COOLDOWN) m_state=TMB_ST_OPEN;
         ManageOpenPosition();
         // update journal excursion
         if(PositionSelectByTicket(m_ticket))
           {
            long tp = PositionGetInteger(POSITION_TYPE);
            m_journal.OnTickInTrade(latest.bid, latest.ask, tp==POSITION_TYPE_BUY);
           }
         return; // no new entry while managing (maxPos default 1; gate below handles >1)
        }
      else
        {
         // position disappeared (SL/TP hit or manual close): if journal thinks one is open,
         // EA.OnTradeTransaction does authoritative close accounting; here just reset state.
         if(m_ticket!=0 && !m_journal.HasOpen())
           { m_ticket=0; m_beDone=false; m_state=TMB_ST_COOLDOWN;
             m_be.ClearEffective(); m_trail.ClearEffective(); }
        }

      // 3) entry gates
      MqlTick tk; SymbolInfoTick(symbol, tk);
      int spreadPts = (int)MathRound((tk.ask-tk.bid)/m_sym.Point());
      bool inCooldown = m_risk.InCooldown(nowServer);
      bool riskLocked = m_risk.IsLocked();
      bool abnormal = false;
      if(m_haveMetrics)
         abnormal = m_risk.AbnormalMarket(m_lastMetrics.ticksPerSecond,
                                           m_lastMetrics.displacementPoints,
                                           m_maxTps, m_maxDispPts);
      TBBurstResult burst; ZeroMemory(burst);
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

      // 4) execute: fixed lot, or risk-scaled volume with k-scaled money targets
      // (price geometry identical to fixed mode; only money scales by k)
      m_state=TMB_ST_SIGNAL;
      double vol = m_sizer.ComputeVolume();
      double scaleK = 1.0;
      if(m_useRisk)
        {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         TMBRiskVolume rv = m_sizer.ComputeRiskVolume(equity, m_slMoney);
         if(rv.volume<=0)
           {
            m_log.Warning("Risk sizing rejected: " + rv.note + " (no trade)");
            m_state=TMB_ST_WAITING; return;
           }
         vol = rv.volume; scaleK = rv.scaleK;
         if(rv.capped)
            m_log.Warning(StringFormat("Risk volume capped at %.2f (k=%.2f, SL money=%.2f)",
               vol, scaleK, rv.riskMoney));
         m_be.SetEffectiveBuffer(m_beBuf*scaleK);
         m_trail.SetEffectiveDistance(m_trailMoney*scaleK);
        }
      double slEff = m_slMoney*scaleK, tpEff = m_tpMoney*scaleK;
      string verr=""; if(!m_sizer.ValidateVolume(vol, verr)) { m_log.Error("Bad volume: "+verr); return; }
      bool isBuy = (sig.signal==TMB_SIG_BUY);
      m_log.Info(StringFormat("SIGNAL %s ratio=%.2f disp=%dpts tps=%.1f spread=%d vol=%.2f k=%.2f",
         (isBuy?"BUY":"SELL"), m_lastMetrics.dirRatio, m_lastMetrics.displacementPoints,
         m_lastMetrics.ticksPerSecond, spreadPts, vol, scaleK));
      m_state=TMB_ST_ORDER;
      TBOpenResult or_ = m_exec.OpenMarket(isBuy, vol, slEff, tpEff, m_tpMode);
      if(!or_.ok) { m_state=TMB_ST_WAITING; return; }
      m_ticket = or_.ticket;
      m_beDone = false;
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
      if(beNow && !m_beDone) { m_beDone=true; m_state=TMB_ST_BE; }
      if(beNow && m_useTrail)
        {
         bool tr = m_trail.Manage(m_ticket, m_beDone);
         if(tr) m_state=TMB_ST_TRAIL;
        }
      else if(m_beDone) m_state=TMB_ST_COST_COVERED;
     }

   //--- accessors
   ENUM_TMB_STATE    State(void) const { return m_state; }
   ulong             Ticket(void) const { return m_ticket; }
   bool              BeDone(void) const { return m_beDone; }
   TBMetrics         LastMetrics(void) const { return m_lastMetrics; }
  };

#endif
