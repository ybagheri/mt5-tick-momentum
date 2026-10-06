//+------------------------------------------------------------------+
//| Logger.mqh - configurable log levels                             |
//+------------------------------------------------------------------+
#ifndef __TMB_LOGGER_MQH__
#define __TMB_LOGGER_MQH__

enum ENUM_TMB_LOG_LEVEL
  {
   TMB_LOG_OFF     = 0,
   TMB_LOG_ERROR   = 1,
   TMB_LOG_WARNING = 2,
   TMB_LOG_INFO    = 3,
   TMB_LOG_DEBUG   = 4
  };

class CLogger
  {
private:
   ENUM_TMB_LOG_LEVEL m_level;
   string              m_prefix;
public:
                     CLogger(void): m_level(TMB_LOG_INFO), m_prefix("TMB") {}
   void              Init(ENUM_TMB_LOG_LEVEL level, string prefix) { m_level=level; m_prefix=prefix; }
   void              SetLevel(ENUM_TMB_LOG_LEVEL level) { m_level=level; }

   void              Error(string msg)   { if(m_level>=TMB_LOG_ERROR)   PrintFormat("[%s][ERROR] %s", m_prefix, msg); }
   void              Warning(string msg) { if(m_level>=TMB_LOG_WARNING) PrintFormat("[%s][WARN] %s", m_prefix, msg); }
   void              Info(string msg)    { if(m_level>=TMB_LOG_INFO)    PrintFormat("[%s][INFO] %s", m_prefix, msg); }
   void              Debug(string msg)   { if(m_level>=TMB_LOG_DEBUG)   PrintFormat("[%s][DBG] %s", m_prefix, msg); }
  };

#endif
