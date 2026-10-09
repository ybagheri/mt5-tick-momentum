//+------------------------------------------------------------------+
//| Enums.mqh - shared enumerations (no dependencies)                |
//+------------------------------------------------------------------+
#ifndef __TMB_ENUMS_MQH__
#define __TMB_ENUMS_MQH__

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

enum ENUM_TMB_TP_MODE
  {
   TMB_TP_FIXED=0,        // place a fixed TP at open
   TMB_TP_TRAILING_ONLY=1,// no TP; exit managed by trailing stop only
   TMB_TP_HYBRID=2        // fixed TP AND trailing stop
  };

#endif