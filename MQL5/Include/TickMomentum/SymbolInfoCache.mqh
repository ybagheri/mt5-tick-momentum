//+------------------------------------------------------------------+
//| SymbolInfoCache.mqh - cached dynamic symbol properties           |
//+------------------------------------------------------------------+
#ifndef __TMB_SYMBOLINFO_MQH__
#define __TMB_SYMBOLINFO_MQH__

class CSymbolInfoCache
  {
private:
   string   m_symbol;
   int      m_digits;
   double   m_point;
   double   m_tickSize;
   double   m_tickValue;
   double   m_tickValueProfit;
   double   m_tickValueLoss;
   double   m_volMin;
   double   m_volMax;
   double   m_volStep;
   long     m_stopsLevel;
   long     m_freezeLevel;
   long     m_fillingMode;
   bool     m_tradeAllowed;
   bool     m_valid;
public:
                     CSymbolInfoCache(void): m_symbol(""), m_digits(0), m_point(0),
                      m_tickSize(0), m_tickValue(0), m_tickValueProfit(0), m_tickValueLoss(0),
                      m_volMin(0), m_volMax(0), m_volStep(0),
                      m_stopsLevel(0), m_freezeLevel(0), m_fillingMode(0),
                      m_tradeAllowed(false), m_valid(false) {}

   bool              Refresh(string symbol)
     {
      m_symbol = symbol;
      m_digits       = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      m_point        = SymbolInfoDouble(symbol, SYMBOL_POINT);
      m_tickSize     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      m_tickValue    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      m_tickValueProfit = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
      m_tickValueLoss   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      m_volMin       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      m_volMax       = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      m_volStep      = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      m_stopsLevel   = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      m_freezeLevel  = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      // SYMBOL_FILLING_MODE may not exist on old builds; query safely
      m_fillingMode  = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      m_tradeAllowed = (bool)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
      //--- sanity fallbacks
      if(m_point <= 0) { m_valid=false; return false; }
      if(m_tickSize <= 0) m_tickSize = m_point;
      if(m_tickValue <= 0)
        {
         // fall back to profit/loss variants if one-sided quote is zero
         if(m_tickValueProfit > 0) m_tickValue = m_tickValueProfit;
         else if(m_tickValueLoss > 0) m_tickValue = m_tickValueLoss;
         else { m_valid=false; return false; }
        }
      if(m_volMin <= 0 || m_volMax <= 0 || m_volStep <= 0) { m_valid=false; return false; }
      m_valid = true;
      return true;
     }

   //--- getters
   string            Symbol(void) const { return m_symbol; }
   int               Digits(void) const { return m_digits; }
   double            Point(void)  const { return m_point; }
   double            TickSize(void) const { return m_tickSize; }
   double            TickValue(void) const { return m_tickValue; }
   double            VolMin(void)  const { return m_volMin; }
   double            VolMax(void)  const { return m_volMax; }
   double            VolStep(void) const { return m_volStep; }
   long              StopsLevelPoints(void) const { return m_stopsLevel; }
   long              FreezeLevelPoints(void) const { return m_freezeLevel; }
   long              FillingMode(void) const { return m_fillingMode; }
   bool              IsValid(void) const { return m_valid; }

   double            NormalizePrice(double price) const
     { return NormalizeDouble(price, m_digits); }

   double            NormalizeVolume(double vol) const
     {
      double v = MathMax(m_volMin, MathMin(m_volMax, vol));
      double steps = MathFloor(v / m_volStep + 1e-8);
      v = steps * m_volStep;
      v = MathMax(m_volMin, MathMin(m_volMax, v));
      return NormalizeDouble(v, 8);
     }

   double            StopsLevelPrice(void) const { return (double)m_stopsLevel * m_point; }
   double            FreezeLevelPrice(void) const { return (double)m_freezeLevel * m_point; }
  };

#endif
