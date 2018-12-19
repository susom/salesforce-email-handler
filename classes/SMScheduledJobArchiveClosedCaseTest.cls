/**
 * Created by scweber on 9/3/18.
 */
@isTest
public with sharing class SMScheduledJobArchiveClosedCaseTest {
    @isTest public static void  testSchedule() {

        String CRON_EXP = '0 0 0 15 3 ? *';
        Test.startTest();
        String jobId = System.schedule('ScheduleApexClassTest',  CRON_EXP, new SMScheduledJobArchiveClosedCase());
        CronTrigger ct = [SELECT Id, CronExpression, TimesTriggered, NextFireTime FROM CronTrigger WHERE id = :jobId];
        System.assertEquals(CRON_EXP, ct.CronExpression);
        System.assertEquals(0, ct.TimesTriggered);
        Test.stopTest();
        System.assertEquals(true, true);
    }
}