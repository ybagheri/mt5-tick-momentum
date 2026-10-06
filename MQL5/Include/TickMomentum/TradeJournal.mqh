//+------------------------------------------------------------------+
//| TradeJournal.mqh - in-memory trade record + optional CSV export |
//+------------------------------------------------------------------+
#ifndef __TMB_JOURNAL_MQH__
#define __TMB_JOURNAL_MQH__

#include "MarketMetrics.mqh"
#include "Logger.mqh"

enum ENUM_TMB_EXIT_REASON
  {
   TMB_EXIT_UNKNOWN=0,
   TMB_EXIT_SL=1,
   TMB_EXIT_TP=2,
   TMB_EXIT_BE=3,
   TMB_EXIT_TRAIL=4,
   TMB_EXIT_MANUAL=5,
   TMB_EXIT_RISK=6,
   TMB_EXIT_EMERGENCY=7
  };

string TMBExitReasonToString(ENUM_TMB_EXIT_REASON r)
  {
   switch(r)
     {
      case TMB_EXIT_SL: return "STOP_LOSS";
      case TMB_EXIT_TP: return "TAKE_PROFIT";
      case TMB_EXIT_BE: return "BREAK_EVEN";
      case TMB_EXIT_TRAIL: return "TRAILING_STOP";
      case TMB_EXIT_MANUAL: return "MANUAL";
      case TMB_EXIT_RISK: return "RISK_LIMIT";
      case TMB_EXIT_EMERGENCY: return "EMERGENCY";
      default: return "UNKNOWN";
     }
  }

struct TMBTradeRecord
  {
   ulong             ticket;
   string            symbol;
   int               direction;   // +1 buy -1 sell
   double            volume;
   double            entryPrice;
   double            exitPrice;
   double            initialSL;
   double            initialTP;
   int               spreadEntry;
   double            estCommission;
   double            actualCommission;
   double            grossProfit;
   double            netProfit;
   double            mfeMoney;
   double            maeMoney;
   long              holdingSec;
   long              tickCount;
   double            entryRatio;
   int               entryDispPoints;
   double            entryTps;
   ENUM_TMB_EXIT_REASON exitReason;
   datetime          openTime;
   datetime          closeTime;
  };

class CTradeJournal
  {
private:
   CLogger          *m_log;
   TMBTradeRecord    m_open;       // currently open (single position model)
   bool              m_hasOpen;
   double            m_bestFav;    // price excursion favourable
   double            m_worstAdv;   // adverse
   long              m_ticksInTrade;
   bool              m_csvEnabled;
   string            m_csvFile;
   int               m_closedCount;
   double            m_totalNet;
public:
                     CTradeJournal(void): m_log(NULL), m_hasOpen(false),
                      m_bestFav(0), m_worstAdv(0), m_ticksInTrade(0),
                      m_csvEnabled(false), m_csvFile("TickMomentumJournal.csv"),
                      m_closedCount(0), m_totalNet(0.0) { ZeroMemory(m_open); }

   void              Init(CLogger *log, bool csvEnabled, string csvFile)
     {
      m_log=log; m_csvEnabled=csvEnabled;
      if(csvFile!="") m_csvFile=csvFile;
      if(m_csvEnabled) WriteHeader();
     }

   void              OnOpen(ulong ticket, string symbol, int dir, double vol,
                            double entry, double sl, double tp, int spreadEntry,
                            double estComm, TBMetrics &metrics, datetime nowServer)
     {
      ZeroMemory(m_open);
      m_open.ticket=ticket; m_open.symbol=symbol; m_open.direction=dir;
      m_open.volume=vol; m_open.entryPrice=entry;
      m_open.initialSL=sl; m_open.initialTP=tp;
      m_open.spreadEntry=spreadEntry; m_open.estCommission=estComm;
      m_open.entryRatio=metrics.dirRatio;
      m_open.entryDispPoints=metrics.displacementPoints;
      m_open.entryTps=metrics.ticksPerSecond;
      m_open.openTime=nowServer;
      m_hasOpen=true; m_bestFav=entry; m_worstAdv=entry; m_ticksInTrade=0;
     }

   void              OnTickInTrade(double bid, double ask, bool isBuy)
     {
      if(!m_hasOpen) return;
      m_ticksInTrade++;
      double px = isBuy ? bid : ask; // exit-side price
      if(isBuy) { if(px>m_bestFav) m_bestFav=px; if(px<m_worstAdv) m_worstAdv=px; }
      else      { if(px<m_bestFav) m_bestFav=px; if(px>m_worstAdv) m_worstAdv=px; }
     }

   //--- Close: caller supplies deal economics from history
   double            OnClose(double exitPrice, double grossProfit, double actualComm,
                             ENUM_TMB_EXIT_REASON reason, datetime nowServer,
                             double tickValue, double tickSize)
     {
      if(!m_hasOpen) return 0.0;
      m_open.exitPrice=exitPrice;
      m_open.grossProfit=grossProfit;
      m_open.actualCommission=actualComm;
      m_open.netProfit=grossProfit - actualComm;
      m_open.exitReason=reason;
      m_open.closeTime=nowServer;
      m_open.holdingSec=(long)nowServer-(long)m_open.openTime;
      m_open.tickCount=m_ticksInTrade;
      // MFE/MAE in money from excursion
      double favD = MathAbs(m_bestFav - m_open.entryPrice);
      double advD = MathAbs(m_worstAdv - m_open.entryPrice);
      if(tickSize>0 && tickValue>0)
        {
         m_open.mfeMoney = favD/tickSize*tickValue*m_open.volume;
         m_open.maeMoney = advD/tickSize*tickValue*m_open.volume;
        }
      m_closedCount++; m_totalNet += m_open.netProfit;
      if(m_log!=NULL)
         m_log.Info(StringFormat("CLOSE #%I64u %s net=%.2f gross=%.2f comm=%.2f reason=%s",
            m_open.ticket, m_open.symbol, m_open.netProfit, grossProfit, actualComm,
            TMBExitReasonToString(reason)));
      if(m_csvEnabled) AppendCSV(m_open);
      double net = m_open.netProfit;
      m_hasOpen=false;
      return net;
     }

   bool              HasOpen(void) const { return m_hasOpen; }
   ulong             OpenTicket(void) const { return m_open.ticket; }
   int               ClosedCount(void) const { return m_closedCount; }
   double            TotalNet(void) const { return m_totalNet; }

private:
   void              WriteHeader(void)
     {
      int h=FileOpen(m_csvFile, FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
      if(h==INVALID_HANDLE) return;
      FileWrite(h,"close_time","symbol","dir","vol","entry","exit","sl0","tp0",
         "spread_entry","est_comm","actual_comm","gross","net","mfe","mae",
         "hold_s","ticks","ratio","disp_pts","tps","exit_reason","ticket");
      FileClose(h);
     }
   void              AppendCSV(TMBTradeRecord &r)
     {
      int h=FileOpen(m_csvFile, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ';');
      if(h==INVALID_HANDLE) return;
      FileSeek(h,0,SEEK_END);
      FileWrite(h, TimeToString(r.closeTime,TIME_DATE|TIME_SECONDS), r.symbol,
         (r.direction>0?"BUY":"SELL"), r.volume, r.entryPrice, r.exitPrice,
         r.initialSL, r.initialTP, r.spreadEntry, r.estCommission, r.actualCommission,
         r.grossProfit, r.netProfit, r.mfeMoney, r.maeMoney, r.holdingSec, r.tickCount,
         r.entryRatio, r.entryDispPoints, r.entryTps,
         TMBExitReasonToString(r.exitReason), r.ticket);
      FileClose(h);
     }
  };

#endif
