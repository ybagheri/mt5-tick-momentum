//+------------------------------------------------------------------+
//| PositionSizer.mqh - fixed lot + risk-% extension                  |
//| Risk mode: V_risk = V_fixed * (equity*pct/100) / SLMoneyRef,      |
//| so the SL money amount equals the risk amount while the caller    |
//| scales money inputs by k (price geometry stays identical).        |
//+------------------------------------------------------------------+
#ifndef __TMB_SIZER_MQH__
#define __TMB_SIZER_MQH__

#include "SymbolInfoCache.mqh"

struct TMBRiskVolume
   {
   double            volume;     // normalized, capped (0 = cannot trade)
   double            scaleK;     // volume / fixedLot (money-input multiplier)
   double            riskMoney;  // effective SL money after caps
   bool              capped;
   string            note;

   void              Reject(string why)
      { volume=0; scaleK=0; riskMoney=0; capped=false; note=why; }

   void              Reset(void)
      { volume=0; scaleK=0; riskMoney=0; capped=false; note=""; }
   };

class CPositionSizer
  {
private:
   CSymbolInfoCache *m_sym;
   double            m_fixedLot;
   double            m_riskPct;
   double            m_riskMaxLot;
public:
                     CPositionSizer(void): m_sym(NULL), m_fixedLot(0.01),
                      m_riskPct(0.5), m_riskMaxLot(1.0) {}
   void              Init(CSymbolInfoCache *sym, double fixedLot, double riskPct, double riskMaxLot)
     { m_sym=sym; m_fixedLot=fixedLot; m_riskPct=riskPct; m_riskMaxLot=riskMaxLot; }
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
   //--- Risk sizing. equity>0 and slMoneyRef>0 required; else note=fallback.
   TMBRiskVolume     ComputeRiskVolume(double equity, double slMoneyRef)
     {
      TMBRiskVolume r; r.Reset();
      if(m_sym==NULL) { r.Reject("NO_SYMBOL"); return r; }
      if(equity<=0) { r.Reject("NO_EQUITY"); return r; }
      if(slMoneyRef<=0) { r.Reject("NO_SLREF"); return r; }
      if(m_fixedLot<=0) { r.Reject("NO_FIXEDLOT"); return r; }
      double want = equity * m_riskPct / 100.0;      // target SL money
      double k = want / slMoneyRef;
      double v = m_fixedLot * k;
      double cap = MathMin(m_sym.VolMax(), m_riskMaxLot);
      if(v > cap) { v = cap; r.capped=true; r.note="CAPPED"; }
      v = m_sym.NormalizeVolume(v);
      // NormalizeVolume clamps up to VolMin, so compare against the *pre-normalized*
      // request: a target below the broker minimum must not be silently lifted.
      if(v < m_sym.VolMin() - 1e-12) { r.Reject("BELOW_MIN"); return r; }
      if(v > m_sym.VolMax() + 1e-12) { r.Reject("ABOVE_MAX"); return r; }
      r.volume=v;
      r.scaleK=v/m_fixedLot;
      r.riskMoney=slMoneyRef*r.scaleK;               // actual SL money after caps
      return r;
     }
  };

#endif
