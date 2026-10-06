//+------------------------------------------------------------------+
//| MarketMetrics.mqh - rolling metrics over tick window             |
//+------------------------------------------------------------------+
#ifndef __TMB_MARKETMETRICS_MQH__
#define __TMB_MARKETMETRICS_MQH__

#include "TickCollector.mqh"

struct TBMetrics
  {
   int               total;
   int               up;
   int               down;
   int               neutral;
   double            dirRatio;      // max(up,down)/(up+down), 0 if none
   int               domDir;        // +1 bull, -1 bear, 0 none
   double            displacement;  // latest.mid - oldest.mid (price)
   double            absDisplacement;
   int               displacementPoints;
   double            ticksPerSecond;
   double            windowSeconds;
   double            latestMid;
   double            oldestMid;
   bool              ready;
  };

class CMarketMetrics
  {
private:
   double            m_point;
public:
                     CMarketMetrics(void): m_point(0) {}
   void              Init(double point) { m_point = point; }

   TBMetrics         Compute(CTickDataCollector &collector)
     {
      TBMetrics m;
      ZeroMemory(m);
      TMBTick w[];
      int n = collector.GetWindow(w);
      m.total = n;
      if(n < 2) { m.ready=false; return m; }
      m.oldestMid = w[0].mid;
      m.latestMid = w[n-1].mid;
      for(int i=1; i<n; i++) // skip first (no predecessor)
        {
         if(w[i].dir==TMB_TICK_UP) m.up++;
         else if(w[i].dir==TMB_TICK_DOWN) m.down++;
         else m.neutral++;
        }
      int denom = m.up + m.down;
      if(denom > 0)
        {
         m.dirRatio = (double)MathMax(m.up, m.down) / (double)denom;
         m.domDir = (m.up >= m.down ? 1 : -1);
         if(m.up==m.down) m.domDir = 0;
        }
      else { m.dirRatio=0.0; m.domDir=0; }
      m.displacement = m.latestMid - m.oldestMid;
      m.absDisplacement = MathAbs(m.displacement);
      if(m_point > 0) m.displacementPoints = (int)MathRound(m.absDisplacement / m_point);
      long t0 = w[0].time_msc, t1 = w[n-1].time_msc;
      double secs = (double)(t1 - t0) / 1000.0;
      m.windowSeconds = secs;
      if(secs > 0) m.ticksPerSecond = (double)(n - 1) / secs;
      else m.ticksPerSecond = 0.0;
      m.ready = true;
      return m;
     }
  };

#endif
