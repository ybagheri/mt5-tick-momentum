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
   int               m_minWindowTicks;  // ticks required before metrics are trustworthy
public:
                     CMarketMetrics(void): m_point(0), m_minWindowTicks(0) {}
   void              Init(double point, int minWindowTicks) { m_point=point; m_minWindowTicks=minWindowTicks; }

   //--- Iterates the ring buffer in place (no per-tick array copy).
   //--- Direction counts skip the oldest tick: its predecessor is outside the window.
   TBMetrics         Compute(CTickDataCollector &collector)
      {
      TBMetrics m;
      ZeroMemory(m);
      int n = collector.Count();
      m.total = n;
      if(n < 2 || n < m_minWindowTicks) { m.ready=false; return m; }

      TMBTick oldest, latest;
      if(!collector.GetOldest(oldest) || !collector.GetLatest(latest)) { m.ready=false; return m; }
      m.oldestMid = oldest.mid;
      m.latestMid = latest.mid;

      for(int i=0; i<n; i++)
        {
         if(!collector.At(i, oldest)) { m.ready=false; return m; }
         if(i==0) continue;              // no predecessor inside window
         if(oldest.dir==TMB_TICK_UP) m.up++;
         else if(oldest.dir==TMB_TICK_DOWN) m.down++;
         else m.neutral++;
        }
      int denom = m.up + m.down;
      if(denom > 0)
        {
         m.dirRatio = (double)MathMax(m.up, m.down) / (double)denom;
         if(m.up==m.down) m.domDir=0;
         else m.domDir = (m.up > m.down ? 1 : -1);
        }
      else { m.dirRatio=0.0; m.domDir=0; }
      m.displacement = m.latestMid - m.oldestMid;
      m.absDisplacement = MathAbs(m.displacement);
      if(m_point > 0) m.displacementPoints = (int)MathRound(m.absDisplacement / m_point);
      double secs = (double)(latest.time_msc - oldest.time_msc) / 1000.0;
      m.windowSeconds = secs;
      m.ticksPerSecond = (secs > 0 ? (double)(n - 1) / secs : 0.0);
      m.ready = true;
      return m;
      }
   };

#endif
