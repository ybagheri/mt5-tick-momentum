//+------------------------------------------------------------------+
//| MomentumDetector.mqh - multi-condition burst detection           |
//+------------------------------------------------------------------+
#ifndef __TMB_MOMENTUM_MQH__
#define __TMB_MOMENTUM_MQH__

#include "MarketMetrics.mqh"

enum ENUM_TMB_BURST_DIR { TMB_BURST_NONE=0, TMB_BURST_BULL=1, TMB_BURST_BEAR=-1 };

struct TBBurstResult
  {
   bool              isBurst;
   ENUM_TMB_BURST_DIR dir;
   string            reason;   // rejection explanation
   TBMetrics         metrics;
  };

class CMomentumDetector
  {
private:
   double            m_minRatio;
   int               m_minMovePoints;
   double            m_minTicksPerSec;
   double            m_maxWindowSeconds; // 0 = disabled (abnormal stall filter)
   double            m_point;
public:
                     CMomentumDetector(void): m_minRatio(0.7), m_minMovePoints(10),
                      m_minTicksPerSec(1.0), m_maxWindowSeconds(0), m_point(0) {}

   void              Init(double minRatio, int minMovePoints, double minTps,
                          double point, double maxWindowSeconds)
     {
      m_minRatio=minRatio; m_minMovePoints=minMovePoints;
      m_minTicksPerSec=minTps; m_point=point;
      m_maxWindowSeconds=maxWindowSeconds;
     }

   TBBurstResult     Evaluate(TBMetrics &m)
     {
      TBBurstResult r;
      ZeroMemory(r);
      r.metrics = m;
      r.isBurst=false; r.dir=TMB_BURST_NONE;
      if(!m.ready) { r.reason="WARMUP"; return r; }
      if(m.domDir==0) { r.reason="NO_DOMINANCE"; return r; }
      if(m.dirRatio < m_minRatio) { r.reason="RATIO"; return r; }
      if(m.displacementPoints < m_minMovePoints) { r.reason="DISPLACEMENT"; return r; }
      if(m.ticksPerSecond < m_minTicksPerSec) { r.reason="TICKRATE"; return r; }
      if(m_maxWindowSeconds > 0 && m.windowSeconds > m_maxWindowSeconds) { r.reason="STALE"; return r; }
      //--- direction must agree between count dominance and displacement sign
      if(m.domDir>0 && m.displacement<=0) { r.reason="DIR_MISMATCH"; return r; }
      if(m.domDir<0 && m.displacement>=0) { r.reason="DIR_MISMATCH"; return r; }
      r.isBurst=true;
      r.dir = (m.domDir>0 ? TMB_BURST_BULL : TMB_BURST_BEAR);
      r.reason="BURST";
      return r;
     }
  };

#endif
