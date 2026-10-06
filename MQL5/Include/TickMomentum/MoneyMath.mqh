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

   double            PointsToPrice(int points)
     { return (m_sym==NULL ? 0.0 : (double)points * m_sym.Point()); }

   int               PriceToPoints(double distance)
     {
      if(m_sym==NULL || m_sym.Point()<=0) return 0;
      return (int)MathRound(distance / m_sym.Point());
     }

   //--- enforce broker stop distance; returns adjusted distance
   double            EnforceMinStopDistance(double distance)
     {
      if(m_sym==NULL) return distance;
      double minDist = StopsLevelPrice();
      // add one point safety margin
      minDist += m_sym.Point();
      if(distance < minDist) distance = minDist;
      return distance;
     }

   double            StopsLevelPrice(void)
     {
      if(m_sym==NULL) return 0.0;
      return (double)m_sym.StopsLevelPoints() * m_sym.Point() + m_sym.Point();
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
