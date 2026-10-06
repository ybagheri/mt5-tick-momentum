//+------------------------------------------------------------------+
//| ContextFilter.mqh - OPTIONAL candle context filter (off by def.) |
//| Tick stream stays the primary signal. When enabled, candles add: |
//|  1) trend alignment: BUY only above EMA, SELL only below EMA      |
//|     (last CLOSED bar, no intra-bar repaint), and/or              |
//|  2) volatility cap: block entries while ATR > maximum.            |
//| Fail-safe: missing indicator data BLOCKS entries (management of  |
//| open positions always continues). Tester-safe (shift-1 reads).   |
//+------------------------------------------------------------------+
#ifndef __TMB_CONTEXT_MQH__
#define __TMB_CONTEXT_MQH__

#include "Logger.mqh"

class CMarketContextFilter
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   bool              m_useTrend;
   int               m_maPeriod;
   bool              m_useVol;
   int               m_atrPeriod;
   double            m_maxATRPoints;
   double            m_point;
   int               m_hMA;
   int               m_hATR;
   CLogger          *m_log;
   bool              m_warned;
public:
                     CMarketContextFilter(void): m_symbol(""), m_tf(PERIOD_H1),
                      m_useTrend(false), m_maPeriod(50), m_useVol(false),
                      m_atrPeriod(14), m_maxATRPoints(0), m_point(0),
                      m_hMA(INVALID_HANDLE), m_hATR(INVALID_HANDLE),
                      m_log(NULL), m_warned(false) {}

   bool              Init(string symbol, ENUM_TIMEFRAMES tf, double point,
                          bool useTrend, int maPeriod,
                          bool useVol, int atrPeriod, double maxATRPoints,
                          CLogger *log)
     {
      Cleanup();
      m_symbol=symbol; m_tf=tf; m_point=point;
      m_useTrend=useTrend; m_maPeriod=maPeriod;
      m_useVol=useVol; m_atrPeriod=atrPeriod; m_maxATRPoints=maxATRPoints;
      m_log=log; m_warned=false;
      if(!IsActive()) return true;               // disabled: nothing to build
      if(m_useTrend)
        {
         m_hMA = iMA(symbol, tf, maPeriod, 0, MODE_EMA, PRICE_CLOSE);
         if(m_hMA==INVALID_HANDLE) { LogOnce("CTX: iMA handle failed"); return false; }
        }
      if(m_useVol)
        {
         m_hATR = iATR(symbol, tf, atrPeriod);
         if(m_hATR==INVALID_HANDLE) { LogOnce("CTX: iATR handle failed"); return false; }
        }
      return true;
     }

   void              Cleanup(void)
     {
      if(m_hMA!=INVALID_HANDLE) { IndicatorRelease(m_hMA); m_hMA=INVALID_HANDLE; }
      if(m_hATR!=INVALID_HANDLE) { IndicatorRelease(m_hATR); m_hATR=INVALID_HANDLE; }
     }

   bool              IsActive(void) const { return (m_useTrend || m_useVol); }

   bool              BuyAllowed(string &reason)
     {
      reason="OK";
      if(!IsActive()) return true;
      double ema, atr;
      if(!ReadValues(ema, atr, reason)) return false;   // fail-safe block
      if(m_useVol && m_maxATRPoints>0 && atr > m_maxATRPoints)
        { reason="VOLATILITY"; return false; }
      if(m_useTrend)
        {
         double c = Close1();
         if(c==0) { reason="CTX_NO_DATA"; return false; }
         if(c <= ema) { reason="CONTEXT_FILTER"; return false; }
        }
      return true;
     }

   bool              SellAllowed(string &reason)
     {
      reason="OK";
      if(!IsActive()) return true;
      double ema, atr;
      if(!ReadValues(ema, atr, reason)) return false;
      if(m_useVol && m_maxATRPoints>0 && atr > m_maxATRPoints)
        { reason="VOLATILITY"; return false; }
      if(m_useTrend)
        {
         double c = Close1();
         if(c==0) { reason="CTX_NO_DATA"; return false; }
         if(c >= ema) { reason="CONTEXT_FILTER"; return false; }
        }
      return true;
     }

private:
   void              LogOnce(string msg)
     {
      if(!m_warned && m_log!=NULL) { m_log.Warning(msg); m_warned=true; }
     }

   double            Close1(void)
     {
      MqlRates r[];
      if(CopyRates(m_symbol, m_tf, 1, 1, r) < 1) return 0.0;
      return r[0].close;
     }

   bool              ReadValues(double &ema, double &atrPoints, string &reason)
     {
      ema=0; atrPoints=0; reason="OK";
      if(m_useTrend)
        {
         double b[];
         if(CopyBuffer(m_hMA, 0, 1, 1, b) < 1) { reason="CTX_NO_DATA"; LogOnce("CTX: waiting for MA data"); return false; }
         ema=b[0];
        }
      if(m_useVol)
        {
         double b[];
         if(CopyBuffer(m_hATR, 0, 1, 1, b) < 1) { reason="CTX_NO_DATA"; LogOnce("CTX: waiting for ATR data"); return false; }
         if(m_point>0) atrPoints=b[0]/m_point;
        }
      return true;
     }
  };

#endif
