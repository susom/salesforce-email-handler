/**
 * Created by scweber on 7/8/18.
 */

global class SMScheduledJobArchiveClosedCase implements Schedulable {
    global void execute(SchedulableContext sc){
        List<Case> theCaseList = [SELECT Id FROM Case WHERE Status='Closed' AND Days_Since_Modified__c > 1];
        System.debug(theCaseList);
        for(Case theCase : theCaseList) {
            theCase.Status = 'Archived';
        }
        update theCaseList;
    }
}

