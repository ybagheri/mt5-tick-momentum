//+------------------------------------------------------------------+
//| CostCalculator.mqh - spread/commission/BE economics              |
//+------------------------------------------------------------------+
#ifndef __TMB_COSTCALC_MQH__
#define __TMB_COSTCALC_MQH__

#include "SymbolInfoCache.mqh"
#include "MoneyMath.mqh"

class CCostCalculator
  {
private:
   CSymbolInfoCache *m_sym;
   CMoneyMath       *m_math;
   double            m_commissionPerLot; // one-way per 1.0 lot, account currency
   bool              m_commissionRoundTripDoubled; // if true, total = 2 sides
public:
                     CCostCalculator(void): m_sym(NULL), m_math(NULL),
                      m_commissionPerLot(6.0), m_commissionRoundTripDoubled(true) {}

   void              Init(CSymbolInfoCache *sym, CMoneyMath *math,
                          double commissionPerLot, bool doubledRoundTrip)
     {
      m_sym=sym; m_math=math;
      m_commissionPerLot=commissionPerLot;
      m_commissionRoundTripDoubled=doubledRoundTrip;
     }

   //--- estimated commission for a position (default round-trip)
   double            EstimateCommission(double volume, int sides)
     {
      if(volume<=0) return 0.0;
      return m_commissionPerLot * volume * (double)sides;
     }
   double            EstimateRoundTripCommission(double volume)
     {
      int sides = m_commissionRoundTripDoubled ? 2 : 1;
      return EstimateCommission(volume, sides);
     }

   double            SpreadPriceDistance(double bid, double ask)
     { return MathMax(0.0, ask - bid); }

   int               SpreadPoints(double bid, double ask)
     {
      if(m_sym==NULL) return 0;
      double d = SpreadPriceDistance(bid, ask);
      return (int)MathRound(d / m_sym.Point());
     }

   double            SpreadCostMoney(double bid, double ask, double volume)
     {
      if(m_math==NULL) return 0.0;
      return m_math.PriceDistanceToMoney(SpreadPriceDistance(bid,ask), volume);
     }

   //--- True break-even exit price (the price at which NET ~= +buffer).
   //--- BUY: entered at ask (entryAsk), exits at bid. BE bid = entryAsk + costDist + bufferDist
   //--- SELL: entered at bid (entryBid), exits at ask. BE ask = entryBid - costDist - bufferDist
   double            BreakEvenPriceBuy(double entryAsk, double volume, double bufferMoney)
     {
      double costs = EstimateRoundTripCommission(volume) + MathMax(0.0, bufferMoney);
      double d = m_math.MoneyToPriceDistance(costs, volume);
      double be = entryAsk + d;
      return m_math.SnapToTick(m_sym.NormalizePrice(be));
     }
   double            BreakEvenPriceSell(double entryBid, double volume, double bufferMoney)
     {
      double costs = EstimateRoundTripCommission(volume) + MathMax(0.0, bufferMoney);
      double d = m_math.MoneyToPriceDistance(costs, volume);
      double be = entryBid - d;
      return m_math.SnapToTick(m_sym.NormalizePrice(be));
     }

   //--- Favourable-movement trigger: current floating gross must cover costs+buffer.
   //--- Returns required price distance from entry (favourable direction).
   double            RequiredFavourableDistance(double volume, double bufferMoney)
     {
      double costs = EstimateRoundTripCommission(volume) + MathMax(0.0, bufferMoney);
      return m_math.MoneyToPriceDistance(costs, volume);
     }
  };

#endif
