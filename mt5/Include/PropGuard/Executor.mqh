#ifndef PROPGUARD_EXECUTOR_MQH
#define PROPGUARD_EXECUTOR_MQH

#include <Trade/Trade.mqh>
#include "PropRules.mqh"

//+------------------------------------------------------------------+
//| Executor.mqh -- market-order send with retry/fill verification,   |
//| and position management (session-end / weekend / emergency        |
//| flatten). No pending orders, no ladders, no partials, no          |
//| trailing -- see the approved plan §4.                             |
//+------------------------------------------------------------------+

//--- Per-position session-end hour, set at send time so Executor knows when to flatten a
//--- position without needing to know which engine opened it.
string PropGuardPositionFlattenKey(const long magic,const ulong ticket)
  {
   return StringFormat("PropGuard.%I64d.pos.%I64u.flattenHour", magic, ticket);
  }

void PropGuardSetPositionFlattenHour(const long magic,const ulong ticket,const int hour)
  {
   GlobalVariableSet(PropGuardPositionFlattenKey(magic,ticket),(double)hour);
  }

int PropGuardGetPositionFlattenHour(const long magic,const ulong ticket,const int fallbackHour)
  {
   string key=PropGuardPositionFlattenKey(magic,ticket);
   if(!GlobalVariableCheck(key))
      return fallbackHour;
   return (int)GlobalVariableGet(key);
  }

void PropGuardClearPositionState(const long magic,const ulong ticket)
  {
   string key=PropGuardPositionFlattenKey(magic,ticket);
   if(GlobalVariableCheck(key))
      GlobalVariableDel(key);
  }

//--- Sends a market order with a hard SL/TP attached at send time (never a naked position).
//--- Retries only on transient broker rejects (requote / price-changed); anything else fails
//--- fast rather than hammering the trade server. Returns the resulting position ticket via
//--- `outTicket` on success.
bool PropGuardSendMarketOrder(CTrade &trade,const string symbol,const long magic,
                               const int direction,const double lots,
                               const double sl,const double tp,const string comment,
                               const int flattenHour,ulong &outTicket,string &resultReason)
  {
   outTicket=0;
   if(lots<=0.0)
     { resultReason="lot size is not positive"; return false; }
   if(direction!=1 && direction!=-1)
     { resultReason="invalid direction"; return false; }

   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   bool ok=false;
   uint lastRetcode=0;

   for(int attempt=0; attempt<3 && !ok; attempt++)
     {
      double price=(direction==1) ? SymbolInfoDouble(symbol,SYMBOL_ASK) : SymbolInfoDouble(symbol,SYMBOL_BID);
      double slN=NormalizeDouble(sl,digits);
      double tpN=NormalizeDouble(tp,digits);

      if(direction==1)
         ok=trade.Buy(lots,symbol,price,slN,tpN,comment);
      else
         ok=trade.Sell(lots,symbol,price,slN,tpN,comment);

      if(!ok)
        {
         lastRetcode=trade.ResultRetcode();
         resultReason=StringFormat("attempt=%d retcode=%u desc=%s",attempt+1,lastRetcode,trade.ResultRetcodeDescription());
         bool transient=(lastRetcode==TRADE_RETCODE_REQUOTE ||
                          lastRetcode==TRADE_RETCODE_PRICE_CHANGED ||
                          lastRetcode==TRADE_RETCODE_PRICE_OFF ||
                          lastRetcode==TRADE_RETCODE_REJECT);
         if(!transient)
            break;
        }
     }

   if(!ok)
      return false;

   ulong posTicket=trade.ResultOrder();
   //--- Fill verification: confirm a position actually exists with the SL we asked for.
   //--- A mismatch here (partial fill, broker-side SL rejection) is logged by the caller
   //--- via resultReason, not silently trusted.
   if(posTicket!=0 && PositionSelectByTicket(posTicket))
     {
      double actualSl=PositionGetDouble(POSITION_SL);
      if(MathAbs(actualSl-NormalizeDouble(sl,digits))>SymbolInfoDouble(symbol,SYMBOL_POINT)*2.0)
         resultReason=StringFormat("fill verified but SL mismatch: requested=%.5f actual=%.5f",sl,actualSl);
      else
         resultReason="ok";
     }
   else
     {
      resultReason="order accepted but position not found on select";
     }

   PropGuardSetPositionFlattenHour(magic,posTicket,flattenHour);
   outTicket=posTicket;
   return true;
  }

//--- Closes every PropGuard position for this symbol/magic, unconditionally. Used for
//--- weekend flatten, emergency max-DD/daily-hard halts, and per-position session-end.
//--- `forceReason` non-empty forces every position closed regardless of its own flatten hour
//--- (weekend and emergency paths); empty means "evaluate each position's own rule".
int PropGuardManagePositions(CTrade &trade,const string symbol,const long magic,
                              const datetime now,const PropGuardConfig &cfg,
                              const string forceReason)
  {
   MqlDateTime t;
   TimeToStruct(now,t);
   bool weekend=PropGuardIsWeekendFlattenTime(now,cfg);
   int closedCount=0;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)!=magic) continue;

      bool shouldClose=false;
      string reason="";

      if(forceReason!="")
        { shouldClose=true; reason=forceReason; }
      else if(weekend)
        { shouldClose=true; reason="weekend_flatten"; }
      else
        {
         int flattenHour=PropGuardGetPositionFlattenHour(magic,ticket,23);
         if(t.hour>=flattenHour)
           { shouldClose=true; reason="session_end_flatten"; }
        }

      if(!shouldClose)
         continue;

      if(trade.PositionClose(ticket))
        {
         PropGuardClearPositionState(magic,ticket);
         closedCount++;
         PrintFormat("PropGuard: closed ticket=%I64u reason=%s",ticket,reason);
        }
      else
        {
         PrintFormat("PropGuard: FAILED to close ticket=%I64u reason=%s retcode=%u desc=%s",
                     ticket,reason,trade.ResultRetcode(),trade.ResultRetcodeDescription());
        }
     }
   return closedCount;
  }

#endif
