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
   long              time_msc;  // full ms epoch (server)
   double            bid;
   double            ask;
   double            mid;
   long              volume;
   int               flags;
   int               spreadPoints;
   ENUM_TMB_TICK_DIR dir;       // vs previous mid

   datetime          TimeSec(void) const { return (datetime)(time_msc/1000); }
   void              Clear(void)
     { time_msc=0; bid=0; ask=0; mid=0; volume=0; flags=0; spreadPoints=0; dir=TMB_TICK_NEUTRAL; }
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
   bool              IsFull(void)  const { return m_count >= m_window; }

   //--- Zero-based access oldest->newest over the ring (0 = oldest, Count()-1 = newest)
   bool              At(int index, TMBTick &t) const
      {
       if(index < 0 || index >= m_count) return false;
       t = m_buf[(FirstIndex() + index) % m_window];
       return true;
      }

   //--- Backfill with recent history (best effort; works in Tester too)
   int               Backfill(void)
     {
      MqlTick ticks[];
      int need = m_window;
      int got = CopyTicks(m_symbol, ticks, COPY_TICKS_ALL, 0, need);
      if(got <= 0) return 0;
      int sp = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);   // hoisted out of loop
      // ticks are oldest->newest; feed in order
      for(int i=0; i<got; i++)
         PushTick(ticks[i].time_msc, ticks[i].bid, ticks[i].ask,
                  ticks[i].last, (long)ticks[i].volume, (int)ticks[i].flags, sp);
      return got;
     }

   //--- Push one tick; returns direction. `last` is accepted for API symmetry.
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
      t.bid=bid; t.ask=ask; t.mid=mid;
      t.volume=volume; t.flags=flags; t.spreadPoints=spreadPoints; t.dir=d;

      m_buf[m_head] = t;
      m_head = (m_head + 1) % m_window;
      if(m_count < m_window) m_count++;
      m_totalTicks++;
      return d;
     }

   //--- Convenience: capture current market tick.
   //--- Returns false ONLY when there is no tick at all; a duplicate tick is
   //--- reported as `duplicate` so callers can skip recomputing metrics on it
   //--- (OnTick can fire several times for the very same tick).
   bool              OnMarketTick(bool &duplicate)
     {
      MqlTick tk;
      duplicate=false;
      if(!SymbolInfoTick(m_symbol, tk)) return false;
      // NOTE: MqlTick has no spread field; read it from symbol properties.
      int sp = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      if(m_count>0)
        {
         TMBTick lastTick = m_buf[(m_head - 1 + m_window) % m_window];
         if(lastTick.time_msc==tk.time_msc && lastTick.bid==tk.bid && lastTick.ask==tk.ask)
           { duplicate=true; return true; }
        }
      PushTick(tk.time_msc, tk.bid, tk.ask, tk.last, (long)tk.volume, (int)tk.flags, sp);
      return true;
     }

bool              GetLatest(TMBTick &t)
      {
      if(m_count==0) return false;
      t = m_buf[(m_head - 1 + m_window) % m_window];
      return true;
      }

   bool              GetOldest(TMBTick &t)
      {
      if(m_count==0) return false;
      t = m_buf[FirstIndex()];
      return true;
      }

private:
   int               FirstIndex(void) const
      { return (m_head - m_count + m_window) % m_window; }
   };

#endif
