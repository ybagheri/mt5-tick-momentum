//+------------------------------------------------------------------+
//| PositionSizer.mqh - fixed lot with validation (risk % reserved) |
//+------------------------------------------------------------------+
#ifndef __TMB_SIZER_MQH__
#define __TMB_SIZER_MQH__

#include "SymbolInfoCache.mqh"

class CPositionSizer
  {
private:
   CSymbolInfoCache *m_sym;
   double            m_fixedLot;
public:
                     CPositionSizer(void): m_sym(NULL), m_fixedLot(0.01) {}
   void              Init(CSymbolInfoCache *sym, double fixedLot) { m_sym=sym; m_fixedLot=fixedLot; }
   double            ComputeVolume(void)
     {
      if(m_sym==NULL) return 0.0;
      return m_sym.NormalizeVolume(m_fixedLot);
     }
   bool              ValidateVolume(double vol, string &err)
     {
      if(m_sym==NULL) { err="NO_SYMBOL"; return false; }
      if(vol < m_sym.VolMin() - 1e-12) { err="BELOW_MIN"; return false; }
      if(vol > m_sym.VolMax() + 1e-12) { err="ABOVE_MAX"; return false; }
      return true;
     }
  };

#endif
