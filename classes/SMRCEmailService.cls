/**
 * Created by scweber on 2019-01-24.
 */

global class SMRCEmailService implements Messaging.InboundEmailHandler  {

    SMEmailService helper = new SMEmailService();

    global Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail param1, Messaging.InboundEnvelope param2)
    {
        helper.setSendCaseCommentToCustomer(true);
        helper.setPreselectedQueueRedcap();
        return helper.handleInboundEmail(param1, param2);
    }

}