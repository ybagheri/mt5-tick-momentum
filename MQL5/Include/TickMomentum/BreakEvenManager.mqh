//+------------------------------------------------------------------+
//| BreakEvenManager.mqh - cost-aware BE (never fake BE)             |
//+------------------------------------------------------------------+
#ifndef __TMB_BE_MQH__
#define __TMB_BE_MQH__

#include <Trade\Trade.mqh>
#include "SymbolInfoCache.mqh"
#include "MoneyMath.mqh"
#include "CostCalculator.mqh"
#include "Logger.mqh"

class CBreakEvenManager
  {
private:
   CTrade            m_trade;
   CSymbolInfoCache *m_sym;
   CMoneyMath       *m_math;
   CCostCalculator  *m_cost;
   CLogger          *m_log;
   bool              m_enabled;
   double            m_bufferMoney;
   double            m_effBuffer;    // per-trade override (risk mode scaling)
   bool              m_hasEff;
   long              m_magic;
public:
                     CBreakEvenManager(void): m_sym(NULL), m_math(NULL), m_cost(NULL),
                      m_log(NULL), m_enabled(true), m_bufferMoney(0.02),
                      m_effBuffer(0.0), m_hasEff(false), m_magic(26061001) {}

   void              Init(CSymbolInfoCache *sym, CMoneyMath *math, CCostCalculator *cost,
                          CLogger *log, bool enabled, double bufferMoney, long magic)
     {
      m_sym=sym; m_math=math; m_cost=cost; m_log=log;
      m_enabled=enabled; m_bufferMoney=bufferMoney; m_magic=magic;
      m_trade.SetExpertMagicNumber(magic);
     }

   //--- per-trade effective buffer (risk-mode k scaling); cleared on close
   void              SetEffectiveBuffer(double b) { m_effBuffer=b; m_hasEff=true; }
   void              ClearEffective(void) { m_hasEff=false; }
   double            ActiveBuffer(void) const { return m_hasEff ? m_effBuffer : m_bufferMoney; }
   //--- Returns true if BE was newly applied (or already at/beyond BE).
   //--- mustBeBuy / ticket owned by EA; volume/entry from position.
   bool              Manage(ulong ticket)
     {
      if(!m_enabled) return false;
      if(!m_sym.IsValid()) return false;
      if(!PositionSelectByTicket(ticket)) return false;
      if(PositionGetString(POSITION_SYMBOL)!=m_sym.Symbol()) return false;
      if(PositionGetInteger(POSITION_MAGIC)!=m_magic) return false;
      long type = PositionGetInteger(POSITION_TYPE);
      bool isBuy = (type==POSITION_TYPE_BUY);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      double curSL = PositionGetDouble(POSITION_SL);
      MqlTick tk;
      if(!SymbolInfoTick(m_sym.Symbol(), tk)) return false;

      double buf = ActiveBuffer();
      double reqDist = m_cost.RequiredFavourableDistance(vol, buf);
      if(reqDist <= 0) return false;                 // cost model unusable: never fake BE
      //--- trigger: favourable move covers costs+buffer
      bool covered;
      if(isBuy) covered = (tk.bid >= entry + reqDist - 1e-12);
      else      covered = (tk.ask <= entry - reqDist + 1e-12);
      if(!covered) return false;

      double bePrice = isBuy ? m_cost.BreakEvenPriceBuy(entry, vol, buf)
                             : m_cost.BreakEvenPriceSell(entry, vol, buf);

      //--- never move SL backwards; BE must improve protection
      bool needMove = false;
      if(isBuy)  needMove = (curSL < bePrice - m_sym.Point()*0.5);
      else       needMove = (curSL==0 || curSL > bePrice + m_sym.Point()*0.5);

      //--- respect stops level vs current price
      double minGap = m_math.StopsLevelPrice();
      if(isBuy && (tk.bid - bePrice) < minGap) return false;   // too close, retry later
      if(!isBuy && (bePrice - tk.ask) < minGap) return false;

      if(needMove)
        {
         double tp = PositionGetDouble(POSITION_TP);
         if(!m_trade.PositionModify(ticket, bePrice, tp))
           {
            if(m_log!=NULL) m_log.Warning(StringFormat("BE modify failed #%I64u ret=%d", ticket, m_trade.ResultRetcode()));
            return false;
           }
         if(m_log!=NULL) m_log.Info(StringFormat("BE applied #%I64u -> %s", ticket, DoubleToString(bePrice, m_sym.Digits())));
         return true;
        }
      return true; // already protected
     }
  };

#endif
