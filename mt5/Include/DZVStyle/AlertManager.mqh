#ifndef DZV_STYLE_ALERT_MANAGER_MQH
#define DZV_STYLE_ALERT_MANAGER_MQH

#include <DZVStyle/DZVTypes.mqh>

bool DZVShouldEmitAlert(const string alertKey)
{
   string gv = "DZVStyle.alert." + alertKey;
   if(GlobalVariableCheck(gv))
      return false;
   GlobalVariableSet(gv, (double)TimeCurrent());
   return true;
}

void DZVEmitAlert(const string alertKey,
                  const string message,
                  const bool terminalAlert,
                  const bool pushNotification,
                  const bool emailNotification)
{
   Print("DZVStyle: ", message);
   if(!DZVShouldEmitAlert(alertKey))
      return;
   if(terminalAlert)
      Alert(message);
   if(pushNotification)
      SendNotification(message);
   if(emailNotification)
      SendMail("DZVStyle alert", message);
}

#endif
