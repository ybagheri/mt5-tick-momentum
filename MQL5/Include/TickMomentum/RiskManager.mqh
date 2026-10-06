//+------------------------------------------------------------------+
//| RiskManager.mqh - frequency / loss / cooldown guards             |
//+------------------------------------------------------------------+
#ifndef __TMB_RISK_MQH__
#define __TMB_RISK_MQH__

#include "Logger.mqh"

class CRiskManager
  {
private:
   CLogger          *m_log;
   int               m_maxTradesPerDay;
   int               m_maxConsecLosses;
   double            m_maxDailyLossMoney;
   int               m_cooldownSec;
   datetime          m_lastCloseTime;
   string            m_dayKey;
   int               m_tradesToday;
   int               m_consecLosses;
   double            m_dailyNet;
   bool              m_locked;
   string            m_lockReason;
public:
                     CRiskManager(void): m_log(NULL), m_maxTradesPerDay(50),
                      m_maxConsecLosses(5), m_maxDailyLossMoney(10.0),
                      m_cooldownSec(5), m_lastCloseTime(0), m_dayKey(""),
                      m_tradesToday(0), m_consecLosses(0), m_dailyNet(0.0),
                      m_locked(false), m_lockReason("") {}

   void              Init(CLogger *log, int maxTradesDay, int maxConsecLoss,
                          double maxDailyLossMoney, int cooldownSec)
     {
      m_log=log; m_maxTradesPerDay=maxTradesDay; m_maxConsecLosses=maxConsecLoss;
      m_maxDailyLossMoney=maxDailyLossMoney; m_cooldownSec=cooldownSec;
     }

   void              OnNewDay(string dayKey)
     {
      if(dayKey!=m_dayKey)
        {
         m_dayKey=dayKey; m_tradesToday=0; m_dailyNet=0.0;
         // keep consec losses across days? reset lock only if daily-based
         if(m_lockReason=="DAILY_LOSS" || m_lockReason=="MAX_TRADES")
           { m_locked=false; m_lockReason=""; }
        }
     }

   bool              InCooldown(datetime nowServer) const
     {
      if(m_lastCloseTime==0) return false;
      return ((long)nowServer - (long)m_lastCloseTime) < (long)m_cooldownSec;
     }

   void              NotifyClose(datetime nowServer, double netProfit, string dayKey)
     {
      OnNewDay(dayKey);
      m_lastCloseTime = nowServer;
      m_tradesToday++;
      m_dailyNet += netProfit;
      if(netProfit < 0) m_consecLosses++;
      else m_consecLosses = 0;
      EvaluateLocks();
     }

   void              NotifyOpen(string dayKey)
     {
      OnNewDay(dayKey);
      m_tradesToday++;
      EvaluateLocks();
     }

   void              EvaluateLocks(void)
     {
      if(m_tradesToday >= m_maxTradesPerDay && m_maxTradesPerDay>0)
        { m_locked=true; m_lockReason="MAX_TRADES"; }
      if(m_consecLosses >= m_maxConsecLosses && m_maxConsecLosses>0)
        { m_locked=true; m_lockReason="CONSEC_LOSS"; }
      if(m_maxDailyLossMoney>0 && m_dailyNet <= -m_maxDailyLossMoney)
        { m_locked=true; m_lockReason="DAILY_LOSS"; }
      if(m_locked && m_log!=NULL)
         m_log.Warning("Risk lock: " + m_lockReason);
     }

   bool              IsLocked(void) const { return m_locked; }
   string            LockReason(void) const { return m_lockReason; }
   bool              CanOpen(datetime nowServer) const
     { return !m_locked && !InCooldown(nowServer); }

   //--- abnormal market: tick-rate or displacement beyond hard caps
   bool              AbnormalMarket(double tps, int dispPoints, double maxTps, int maxDispPoints) const
     {
      if(maxTps>0 && tps > maxTps) return true;
      if(maxDispPoints>0 && dispPoints > maxDispPoints) return true;
      return false;
     }

   //--- accessors for journal/tests
   int               TradesToday(void) const { return m_tradesToday; }
   int               ConsecLosses(void) const { return m_consecLosses; }
   double            DailyNet(void) const { return m_dailyNet; }
   datetime          LastClose(void) const { return m_lastCloseTime; }
  };

#endif
