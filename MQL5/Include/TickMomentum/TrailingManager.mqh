//+------------------------------------------------------------------+
//| TrailingManager.mqh - only tightens, never loosens              |
//+------------------------------------------------------------------+
#ifndef __TMB_TRAIL_MQH__
#define __TMB_TRAIL_MQH__

#include <Trade\Trade.mqh>
#include "SymbolInfoCache.mqh"
#include "MoneyMath.mqh"
#include "CostCalculator.mqh"
#include "Logger.mqh"

class CTrailingStopManager
  {
private:
   CTrade            m_trade;
   CSymbolInfoCache *m_sym;
   CMoneyMath       *m_math;
   CCostCalculator  *m_cost;
   CLogger          *m_log;
   bool              m_enabled;
   double            m_distanceMoney;
   long              m_magic;
   bool              m_requireBreakEvenFirst;
public:
                     CTrailingStopManager(void): m_sym(NULL), m_math(NULL), m_cost(NULL),
                      m_log(NULL), m_enabled(true), m_distanceMoney(0.50),
                      m_magic(26061001), m_requireBreakEvenFirst(true) {}

   void              Init(CSymbolInfoCache *sym, CMoneyMath *math, CCostCalculator *cost,
                          CLogger *log, bool enabled, double distMoney, long magic,
                          bool requireBEFirst)
     {
      m_sym=sym; m_math=math; m_cost=cost; m_log=log;
      m_enabled=enabled; m_distanceMoney=distMoney; m_magic=magic;
      m_requireBreakEvenFirst=requireBEFirst;
      m_trade.SetExpertMagicNumber(magic);
     }

   bool              Manage(ulong ticket, bool breakEvenDone)
     {
      if(!m_enabled) return false;
      if(m_requireBreakEvenFirst && !breakEvenDone) return false;
      if(!PositionSelectByTicket(ticket)) return false;
      if(PositionGetString(POSITION_SYMBOL)!=m_sym.Symbol()) return false;
      if(PositionGetInteger(POSITION_MAGIC)!=m_magic) return false;
      long type = PositionGetInteger(POSITION_TYPE);
      bool isBuy = (type==POSITION_TYPE_BUY);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double curSL = PositionGetDouble(POSITION_SL);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      MqlTick tk;
      if(!SymbolInfoTick(m_sym.Symbol(), tk)) return false;

      double trailDist = m_math.MoneyToPriceDistance(m_distanceMoney, vol);
      trailDist = m_math.EnforceMinStopDistance(trailDist);
      double minGap = m_math.StopsLevelPrice();
      bool moved=false;

      if(isBuy)
        {
         double bePrice = m_cost.BreakEvenPriceBuy(entry, vol, 0.0);
         double newSL = tk.bid - trailDist;
         newSL = m_math.SnapToTick(m_sym.NormalizePrice(newSL));
         // must at least be at BE and strictly better than current
         if(newSL < bePrice) return false;
         if(newSL <= curSL + m_sym.Point()*0.5) return false;
         if((tk.bid - newSL) < minGap) return false;
         // freeze level: do not modify if too close to SL already? (broker constraint best-effort)
         double tp = PositionGetDouble(POSITION_TP);
         if(m_trade.PositionModify(ticket, newSL, tp))
           { moved=true; if(m_log!=NULL) m_log.Info(StringFormat("TRAIL BUY #%I64u -> %s", ticket, DoubleToString(newSL, m_sym.Digits()))); }
        }
      else
        {
         double bePrice = m_cost.BreakEvenPriceSell(entry, vol, 0.0);
         double newSL = tk.ask + trailDist;
         newSL = m_math.SnapToTick(m_sym.NormalizePrice(newSL));
         if(newSL > bePrice) return false;
         if(curSL!=0 && newSL >= curSL - m_sym.Point()*0.5) return false;
         if((newSL - tk.ask) < minGap) return false;
         double tp = PositionGetDouble(POSITION_TP);
         if(m_trade.PositionModify(ticket, newSL, tp))
           { moved=true; if(m_log!=NULL) m_log.Info(StringFormat("TRAIL SELL #%I64u -> %s", ticket, DoubleToString(newSL, m_sym.Digits()))); }
        }
      return moved;
     }
  };

#endif
