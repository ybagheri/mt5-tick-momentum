//+------------------------------------------------------------------+
//| MoneyMath.mqh - money <-> price distance conversions            |
//|                                                                  |
//| Economics: money = (priceDistance / tickSize) * tickValue * vol  |
//| so       distance = money * tickSize / (tickValue * vol)         |
//+------------------------------------------------------------------+
#ifndef __TMB_MONEYMATH_MQH__
#define __TMB_MONEYMATH_MQH__

#include "SymbolInfoCache.mqh"

class CMoneyMath
  {
private:
   CSymbolInfoCache *m_sym;
public:
                     CMoneyMath(void): m_sym(NULL) {}
   void              Init(CSymbolInfoCache *sym) { m_sym = sym; }

   //--- money -> price distance (always non-negative input expected)
   double            MoneyToPriceDistance(double money, double volume)
     {
      if(m_sym==NULL || !m_sym.IsValid()) return 0.0;
      if(volume <= 0 || money <= 0) return 0.0;
      double ts = m_sym.TickSize();
      double tv = m_sym.TickValue();
      if(ts <= 0 || tv <= 0) return 0.0;
      return money * ts / (tv * volume);
     }

   double            PriceDistanceToMoney(double distance, double volume)
     {
      if(m_sym==NULL || !m_sym.IsValid()) return 0.0;
      if(volume <= 0 || distance <= 0) return 0.0;
      double ts = m_sym.TickSize();
      double tv = m_sym.TickValue();
      if(ts <= 0 || tv <= 0) return 0.0;
      return distance / ts * tv * volume;
     }

//--- Broker minimum SL/TP distance in price, WITH one point safety margin.
   //--- Single source of truth: every SL/TP gap check must use this value.
   double            StopsLevelPrice(void) const
      {
      if(m_sym==NULL) return 0.0;
      return ((double)m_sym.StopsLevelPoints() + 1.0) * m_sym.Point();
     }

   double            FreezeLevelPrice(void) const
      {
      if(m_sym==NULL) return 0.0;
      return ((double)m_sym.FreezeLevelPoints() + 1.0) * m_sym.Point();
     }

   double            EnforceMinStopDistance(double distance) const
      {
      double minDist = StopsLevelPrice();
      return (distance < minDist ? minDist : distance);
     }

   double            SnapToTick(double price)
     {
      if(m_sym==NULL) return price;
      double ts = m_sym.TickSize();
      if(ts <= 0) return m_sym.NormalizePrice(price);
      double snapped = MathRound(price / ts) * ts;
      return m_sym.NormalizePrice(snapped);
     }
  };

#endif
