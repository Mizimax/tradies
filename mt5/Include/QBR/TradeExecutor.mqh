#ifndef QBR_TRADEEXECUTOR_MQH
#define QBR_TRADEEXECUTOR_MQH

#include <Trade/Trade.mqh>
#include "Types.mqh"

class CTradeExecutor
  {
private:
   string    m_symbol;
   QBRConfig m_cfg;
   CTrade    m_trade;
   string    m_last_error;

   bool IsOwnPosition(const ulong ticket)
     {
      if(ticket==0 || !PositionSelectByTicket(ticket)) return false;
      if(PositionGetString(POSITION_SYMBOL)!=m_symbol) return false;
      return ((long)PositionGetInteger(POSITION_MAGIC)==m_cfg.magic);
     }

   bool SuccessfulRetcode(const uint code) const
     {
      return (code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_DONE_PARTIAL || code==TRADE_RETCODE_PLACED ||
              code==TRADE_RETCODE_NO_CHANGES);
     }

public:
   void Configure(const string symbol,const QBRConfig &cfg)
     {
      m_symbol=symbol;
      m_cfg=cfg;
      m_trade.SetExpertMagicNumber((ulong)cfg.magic);
      m_trade.SetDeviationInPoints((ulong)cfg.deviation_points);
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.SetAsyncMode(false);
      m_last_error="";
     }

   string LastError(void) const { return m_last_error; }
   uint LastRetcode(void) const { return m_trade.ResultRetcode(); }

   bool Open(const QBRDirection direction,const double volume,const string comment,const double stop_loss=0.0,const double take_profit=0.0)
     {
      ResetLastError();
      bool ok=false;
      if(direction==QBR_DIR_LONG)
         ok=m_trade.Buy(volume,m_symbol,0.0,stop_loss,take_profit,comment);
      else if(direction==QBR_DIR_SHORT)
         ok=m_trade.Sell(volume,m_symbol,0.0,stop_loss,take_profit,comment);
      else
        {
         m_last_error="Cannot open FLAT direction";
         return false;
        }
      uint retcode=m_trade.ResultRetcode();
      bool executed=(ok && SuccessfulRetcode(retcode));
      if(!executed)
         m_last_error=StringFormat("Open failed: retcode=%u %s terminal_error=%d",retcode,m_trade.ResultRetcodeDescription(),GetLastError());
      return executed;
     }

   bool CloseTicket(const ulong ticket)
     {
      if(!IsOwnPosition(ticket))
        {
         m_last_error="Refused to close non-EA position";
         return false;
        }
      for(int attempt=0;attempt<m_cfg.close_retry_count;attempt++)
        {
         ResetLastError();
         bool submitted=m_trade.PositionClose(ticket,(ulong)m_cfg.deviation_points);
         uint retcode=m_trade.ResultRetcode();
         if(submitted && SuccessfulRetcode(retcode) && !PositionSelectByTicket(ticket)) return true;
         m_last_error=StringFormat("Close ticket %I64u failed/incomplete attempt %d: %u %s",ticket,attempt+1,retcode,m_trade.ResultRetcodeDescription());
         if(!PositionSelectByTicket(ticket)) return true;
         Sleep(100);
        }
      return false;
     }

   int CloseBasket(void)
     {
      int failed=0;
      ulong tickets[];
      int count=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!IsOwnPosition(ticket)) continue;
         ArrayResize(tickets,count+1);
         tickets[count++]=ticket;
        }
      for(int i=0;i<count;i++) if(!CloseTicket(tickets[i])) failed++;
      return failed;
     }

   int SetBasketStop(const double stop_loss)
     {
      if(stop_loss<=0.0) return 1;
      int failed=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!IsOwnPosition(ticket)) continue;
         double take_profit=PositionGetDouble(POSITION_TP);
         ResetLastError();
         bool submitted=m_trade.PositionModify(ticket,stop_loss,take_profit);
         uint retcode=m_trade.ResultRetcode();
         if(!submitted || !SuccessfulRetcode(retcode))
           {
            failed++;
            m_last_error=StringFormat("Set stop for %I64u failed: %u %s",ticket,retcode,m_trade.ResultRetcodeDescription());
           }
        }
      return failed;
     }

   int CloseProfitableOnly(void)
     {
      int failed=0;
      ulong tickets[];
      int count=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!IsOwnPosition(ticket)) continue;
         double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
         if(profit<=0.0) continue;
         ArrayResize(tickets,count+1);
         tickets[count++]=ticket;
        }
      for(int i=0;i<count;i++) if(!CloseTicket(tickets[i])) failed++;
      return failed;
     }
  };

#endif
