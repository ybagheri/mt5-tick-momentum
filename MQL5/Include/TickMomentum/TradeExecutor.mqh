//+------------------------------------------------------------------+
//| TradeExecutor.mqh - CTrade market orders with money SL/TP        |
//+------------------------------------------------------------------+
#ifndef __TMB_EXECUTOR_MQH__
#define __TMB_EXECUTOR_MQH__

#include <Trade\Trade.mqh>
#include "Enums.mqh"
#include "SymbolInfoCache.mqh"
#include "MoneyMath.mqh"
#include "Logger.mqh"

struct TBOpenResult
   {
   bool              ok;
   ulong             ticket;      // position ticket (POSITION_TICKET)
   ulong             deal;        // opening deal ticket
   double            price;       // executed price
   double            sl;
   double            tp;
   int               retcode;
   string            message;

   void              Reset(void)
      {
       ok=false; ticket=0; deal=0; price=0; sl=0; tp=0;
       retcode=0; message="";
      }
   };

class CTradeExecutor
  {
private:
   CTrade            m_trade;
   CSymbolInfoCache *m_sym;
   CMoneyMath       *m_math;
   CLogger          *m_log;
   long              m_magic;
   int               m_deviation;
public:
                     CTradeExecutor(void): m_sym(NULL), m_math(NULL), m_log(NULL),
                      m_magic(26061001), m_deviation(20) {}

   void              Init(CSymbolInfoCache *sym, CMoneyMath *math, CLogger *log,
                          long magic, int deviation)
     {
      m_sym=sym; m_math=math; m_log=log;
      m_magic=magic; m_deviation=deviation;
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_deviation);
      m_trade.SetAsyncMode(false);
     }

TBOpenResult      OpenMarket(bool isBuy, double volume,
                               double slMoney, double tpMoney, ENUM_TMB_TP_MODE tpMode)
      {
      TBOpenResult r; r.Reset();
      // volume normalized by caller
      MqlTick tk;
      if(!SymbolInfoTick(m_sym.Symbol(), tk)) { r.message="NO_TICK"; return r; }
      double entryRef = isBuy ? tk.ask : tk.bid;
      double slDist = m_math.MoneyToPriceDistance(slMoney, volume);
      slDist = m_math.EnforceMinStopDistance(slDist);
      double tpDist = 0.0;
      bool placeTP = (tpMode==TMB_TP_FIXED || tpMode==TMB_TP_HYBRID);
      if(placeTP && tpMoney > 0)
        {
         tpDist = m_math.MoneyToPriceDistance(tpMoney, volume);
         tpDist = m_math.EnforceMinStopDistance(tpDist);
        }
      double sl = 0.0, tp = 0.0;
      if(isBuy)
        {
         sl = m_math.SnapToTick(m_sym.NormalizePrice(entryRef - slDist));
         if(placeTP && tpDist>0) tp = m_math.SnapToTick(m_sym.NormalizePrice(entryRef + tpDist));
        }
      else
        {
         sl = m_math.SnapToTick(m_sym.NormalizePrice(entryRef + slDist));
         if(placeTP && tpDist>0) tp = m_math.SnapToTick(m_sym.NormalizePrice(entryRef - tpDist));
        }
      bool req = isBuy ? m_trade.Buy(volume, m_sym.Symbol(), 0, sl, tp, "TMB burst")
                       : m_trade.Sell(volume, m_sym.Symbol(), 0, sl, tp, "TMB burst");
      r.retcode = (int)m_trade.ResultRetcode();
      r.message = m_trade.ResultRetcodeDescription();
      if(!req || r.retcode!=TRADE_RETCODE_DONE)
        {
         if(m_log!=NULL) m_log.Error(StringFormat("Order failed ret=%d %s", r.retcode, r.message));
         return r;
        }
      r.deal  = m_trade.ResultDeal();
      r.price = m_trade.ResultPrice();
      //--- find position ticket
      r.ticket = FindMyPositionTicket();
      r.sl = sl; r.tp = tp;
      //--- If broker filled at a different price, SL/TP already sent relative to
      //--- requested ref; re-anchor to actual fill to preserve monetary intent:
      ReanchorSLTPToFill(r.ticket, isBuy, r.price, volume, slMoney, tpMoney, placeTP);
      // refresh r.sl/r.tp from position
      if(PositionSelectByTicket(r.ticket))
        {
         r.sl = PositionGetDouble(POSITION_SL);
         r.tp = PositionGetDouble(POSITION_TP);
         r.price = PositionGetDouble(POSITION_PRICE_OPEN);
        }
      r.ok = true;
      return r;
     }

   ulong             FindMyPositionTicket(void)
     {
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         ulong tk = PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym.Symbol()) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         return tk;
        }
      return 0;
     }

   int               CountMyPositions(void)
     {
      int c=0;
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         ulong tk=PositionGetTicket(i);
         if(tk==0) continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_sym.Symbol()) continue;
         if(PositionGetInteger(POSITION_MAGIC)!=m_magic) continue;
         c++;
        }
      return c;
     }

private:
   void              ReanchorSLTPToFill(ulong ticket, bool isBuy, double fillPrice,
                                       double volume, double slMoney, double tpMoney, bool placeTP)
     {
      if(ticket==0 || fillPrice<=0) return;
      double slDist = m_math.EnforceMinStopDistance(m_math.MoneyToPriceDistance(slMoney, volume));
      double sl = isBuy ? fillPrice - slDist : fillPrice + slDist;
      double tp = 0.0;
      if(placeTP && tpMoney>0)
        {
         double tpDist = m_math.EnforceMinStopDistance(m_math.MoneyToPriceDistance(tpMoney, volume));
         tp = isBuy ? fillPrice + tpDist : fillPrice - tpDist;
        }
      sl = m_math.SnapToTick(m_sym.NormalizePrice(sl));
      if(tp>0) tp = m_math.SnapToTick(m_sym.NormalizePrice(tp));
      //--- Skip the extra modify when the re-anchored levels already match the
      //--- position (avoids needless requests, retcodes and spread exposure).
      if(!PositionSelectByTicket(ticket)) return;
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double eps = m_sym.Point() * 0.5;
      if(MathAbs(curSL-sl) <= eps && MathAbs(curTP-tp) <= eps) return;
      if(!m_trade.PositionModify(ticket, sl, tp) && m_log!=NULL)
         m_log.Warning(StringFormat("Re-anchor modify failed #%I64u ret=%d",
                                     ticket, m_trade.ResultRetcode()));
     }
  };

#endif
