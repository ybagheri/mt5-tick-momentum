//+------------------------------------------------------------------+
//| SignalEngine.mqh - burst + spread + position + cooldown gates    |
//+------------------------------------------------------------------+
#ifndef __TMB_SIGNAL_MQH__
#define __TMB_SIGNAL_MQH__

#include "MomentumDetector.mqh"

enum ENUM_TMB_SIGNAL { TMB_SIG_NONE=0, TMB_SIG_BUY=1, TMB_SIG_SELL=-1 };

struct TBSignal
   {
   ENUM_TMB_SIGNAL   signal;
   string            rejectReason;
   TBBurstResult     burst;

   void              Reset(void)
      {
       signal=TMB_SIG_NONE; rejectReason=""; burst.Reset();
      }
   };

class CSignalEngine
  {
private:
   int               m_maxSpreadPoints;
   int               m_maxPositions;
public:
                     CSignalEngine(void): m_maxSpreadPoints(100), m_maxPositions(1) {}
   void              Init(int maxSpreadPoints, int maxPositions)
     { m_maxSpreadPoints=maxSpreadPoints; m_maxPositions=maxPositions; }

   TBSignal          Evaluate(TBBurstResult &burst, int spreadPoints,
                              int myPositions, bool inCooldown,
                              bool riskLocked, bool abnormalMarket)
     {
      TBSignal s;
      s.Reset();
      s.burst = burst;
      s.signal = TMB_SIG_NONE;
      if(riskLocked)       { s.rejectReason="RISK_LOCK"; return s; }
      if(inCooldown)       { s.rejectReason="COOLDOWN"; return s; }
      if(myPositions >= m_maxPositions) { s.rejectReason="POSITION_LIMIT"; return s; }
      if(spreadPoints > m_maxSpreadPoints) { s.rejectReason="SPREAD"; return s; }
      if(abnormalMarket)   { s.rejectReason="ABNORMAL_MARKET"; return s; }
      if(!burst.isBurst)   { s.rejectReason="NO_BURST:" + burst.reason; return s; }
      if(burst.dir==TMB_BURST_BULL) { s.signal=TMB_SIG_BUY; s.rejectReason="OK"; }
      else if(burst.dir==TMB_BURST_BEAR) { s.signal=TMB_SIG_SELL; s.rejectReason="OK"; }
      return s;
     }
  };

#endif
