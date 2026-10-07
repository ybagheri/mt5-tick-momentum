//+------------------------------------------------------------------+
//| TickCollector.mqh - rolling tick window from tick stream         |
//| Uses live SymbolInfoTick() each OnTick + CopyTicks backfill.     |
//| Classification on mid-price: Mid=(Bid+Ask)/2.                    |
//+------------------------------------------------------------------+
#ifndef __TMB_TICKCOLLECTOR_MQH__
#define __TMB_TICKCOLLECTOR_MQH__

enum ENUM_TMB_TICK_DIR { TMB_TICK_NEUTRAL=0, TMB_TICK_UP=1, TMB_TICK_DOWN=-1 };

struct TMBTick
  {
   datetime          time;      // tick time (server)
   datetime          timeMsc;   // ms precision truncated to seconds for struct simplicity
   long              time_msc;  // full ms epoch
   double            bid;
   double            ask;
   double            mid;
   double            last;
   long              volume;
   int               flags;
   int               spreadPoints;
   ENUM_TMB_TICK_DIR dir;       // vs previous mid
  };

class CTickDataCollector
  {
private:
   string            m_symbol;
   int               m_window;
   TMBTick           m_buf[];
   int               m_count;      // valid entries (<= m_window)
   int               m_head;       // next write index (ring)
   double            m_prevMid;
   bool              m_hasPrev;
   long              m_totalTicks;
public:
                     CTickDataCollector(void): m_symbol(""), m_window(50),
                      m_count(0), m_head(0), m_prevMid(0), m_hasPrev(false), m_totalTicks(0) {}

   bool              Init(string symbol, int window)
     {
      if(window < 5) window = 5;
      if(window > 2000) window = 2000;
      m_symbol=symbol; m_window=window;
      ArrayResize(m_buf, m_window);
      m_count=0; m_head=0; m_hasPrev=false; m_totalTicks=0;
      return true;
     }

   int               Window(void) const { return m_window; }
   int               Count(void)  const { return m_count; }
   long              TotalTicks(void) const { return m_totalTicks; }

   //--- Backfill with recent history (best effort; works in Tester too)
   int               Backfill(void)
     {
      MqlTick ticks[];
      int need = m_window;
      int got = CopyTicks(m_symbol, ticks, COPY_TICKS_ALL, 0, need);
      if(got <= 0) return 0;
      // ticks are oldest->newest; feed in order
      for(int i=0; i<got; i++)
         PushTick(ticks[i].time_msc, ticks[i].bid, ticks[i].ask,
                  ticks[i].last, (long)ticks[i].volume, (int)ticks[i].flags,
                  (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD));
      return got;
     }

   //--- Push one live tick; returns direction
   ENUM_TMB_TICK_DIR PushTick(long time_msc, double bid, double ask, double last,
                              long volume, int flags, int spreadPoints)
     {
      if(bid<=0 || ask<=0 || ask<bid) return TMB_TICK_NEUTRAL;
      double mid = (bid + ask) * 0.5;
      ENUM_TMB_TICK_DIR d = TMB_TICK_NEUTRAL;
      if(m_hasPrev)
        {
         if(mid > m_prevMid) d = TMB_TICK_UP;
         else if(mid < m_prevMid) d = TMB_TICK_DOWN;
        }
      m_prevMid = mid; m_hasPrev = true;

      TMBTick t;
      t.time_msc = time_msc;
      t.time     = (datetime)(time_msc / 1000);
      t.timeMsc  = (datetime)(time_msc / 1000);
      t.bid=bid; t.ask=ask; t.mid=mid; t.last=last;
      t.volume=volume; t.flags=flags; t.spreadPoints=spreadPoints; t.dir=d;

      m_buf[m_head] = t;
      m_head = (m_head + 1) % m_window;
      if(m_count < m_window) m_count++;
      m_totalTicks++;
      return d;
     }

   //--- Convenience: capture current market tick
   bool              OnMarketTick(void)
     {
      MqlTick tk;
      if(!SymbolInfoTick(m_symbol, tk)) return false;
      // NOTE: MqlTick has no spread field; read it from symbol properties.
      int sp = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      PushTick(tk.time_msc, tk.bid, tk.ask, tk.last, (long)tk.volume, (int)tk.flags, sp);
      return true;
     }

   //--- Copy window oldest->newest into out[] (up to count). Returns n.
   int               GetWindow(TMBTick &out[])
     {
      int n = m_count;
      ArrayResize(out, n);
      int start = (m_head - m_count + m_window * 10) % m_window;
      for(int i=0; i<n; i++)
         out[i] = m_buf[(start + i) % m_window];
      return n;
     }

   bool              GetLatest(TMBTick &t)
     {
      if(m_count==0) return false;
      int idx = (m_head - 1 + m_window) % m_window;
      t = m_buf[idx];
      return true;
     }

   bool              GetOldest(TMBTick &t)
     {
      if(m_count==0) return false;
      int start = (m_head - m_count + m_window * 10) % m_window;
      t = m_buf[start];
      return true;
     }
  };

#endif
