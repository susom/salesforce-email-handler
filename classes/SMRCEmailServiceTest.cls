/**
 * Created by scweber on 8/1/18.
 */
@isTest
private class SMRCEmailServiceTest {
    // Utility function to send a test email
    public static String CONSULT_QUEUE = 'Consult Request Queue';
    public static String TEST_JSON = '{"LastName":"Kiamanesh","FirstName":"Eileen F","SuppliedName":"Eileen Kiamanesh","SUNet_ID__c":"eileenk","Email":"ekiamanesh@gmail.com","SuppliedEmail":"ekiamanesh@gmail.com"}~#~#~{"SUnet_ID_case__c":"eileenk","Subject":"Pilot of SF2 ","Availability__c":"","Origin":"Web","ContactEmail":"ekiamanesh@gmail.com","ContactPhone":"(650) 723-7688","Description":"Initial submission for testing purposes. ","Funding_status__c":"Funding Status Unknown","I_am_PI_case__c":"false","IRB_Protocol__c":"25486","Project_Department__c":null,"REDCap_StudyName__c":"","Publication_Plans__c":"Unsure","Original_Queue_Name__c":"queuename=Consult Request Queue;shortname=RIC;longname=Research Informatics Center;url=https://ric-help.med.stanford.edu/;email=informaticsonconsultation@lists.stanford.edu;owneralias=richelp","CustomOrigin__c":"RIC Form V1","Primary_Category__c":"General Inquiry","Project_Record_ID__c":"2","PI_Name__c":"Eileen-PI Kiamanesh"}';

    public static void setup() {

        // call the class and test it with this email

        Group theQueu = new Group();
        theQueu.Type = 'Queue';
        theQueu.Name = CONSULT_QUEUE;
        insert theQueu;
        List<Group> theQueuList = [SELECT Id, Name FROM Group WHERE Type = 'Queue' AND Name = :CONSULT_QUEUE];
        theQueu = theQueuList.get(0);
        User sweber = new User();
        sweber.FirstName = 'Testy';
        sweber.Email = 'test@noorg.edu';
        sweber.LastName = 'Testerson';
        sweber.Username = 'test@noorg.edu';
        sweber.CommunityNickname = 'testy';
        sweber.Alias = 'testy';
        sweber.TimeZoneSidKey = 'America/Los_Angeles';
        sweber.LocaleSidKey = 'en_US';
        sweber.EmailEncodingKey = 'UTF-8';
        sweber.LanguageLocaleKey = 'en_US';
        Profile p = [select id from profile where name = 'Standard User'];
        sweber.ProfileId = p.Id;
        insert sweber;
        List<User> userList = [SELECT FirstName, LastName, Email from User where Email = :sweber.Email];
        sweber = userList.get(0);
        GroupMember groupMember = new GroupMember();
        groupMember.groupId = theQueu.Id;
        groupMember.UserOrGroupId = sweber.Id;
        insert groupMember;

        QueueSobject mappingObject = new QueueSobject(QueueId = theQueu.Id, SobjectType = 'Case');
        System.runAs(new User(Id = UserInfo.getUserId()))
        {insert mappingObject;}
    }


    @isTest public static void validateNewCaseCreation() {
        setup();
        SMRCEmailService emailServObj = new SMRCEmailService();
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        email.toAddresses = new String[]{
                'test@noorg.edu'
        };
        email.subject = 'test';
        email.fromName = 'scweber';
        email.fromAddress = 'test@noorg.edu';
        email.replyTo = 'nobody';

        email.plainTextBody = TEST_JSON;
        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        // Insert account as current user

        System.runAs (thisUser) {
            Messaging.Inboundemailresult result = emailServObj.handleInboundEmail(email, env);

            System.assertEquals(result.success, true);
        }
    }

    @isTest public static void validateIncomingEmailNotInReferenceToExistingCase() {
        setup();
        SMRCEmailService emailServObj = new SMRCEmailService();
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        email.toAddresses = new String[]{
                'test@noorg.edu'
        };
        email.subject = 'some random subject';
        email.fromName = 'scweber';
        email.fromAddress = 'test@noorg.edu';
        email.replyTo = 'nobody@stanford.edu';

        email.plainTextBody = 'this is random and should be politely rejected';
        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        // Insert account as current user

        System.runAs (thisUser) {
            Messaging.InboundEmailResult result = emailServObj.handleInboundEmail(email, env);

            result = emailServObj.handleInboundEmail(email, env);

            System.assertEquals(result.success, true);
        }
    }

    @isTest public static  void validateCaseResponse2() {
        setup();
        SMRCEmailService emailServObj = new SMRCEmailService();
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        email.toAddresses = new String[]{
                'test@noorg.edu'
        };
        email.subject = 'test';
        email.fromName = 'scweber';
        email.fromAddress = 'test@noorg.edu';
        email.replyTo = 'nobody@stanford.edu';

        email.plainTextBody = TEST_JSON;
        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        // Insert account as current user

        System.runAs (thisUser) {

            Messaging.InboundEmailResult result = emailServObj.handleInboundEmail(email, env);
            // ok, now look up the case and send a response email
            List<Case> caseList = [SELECT Id, CaseNumber, reference__c, Description, Subject,OwnerId, Owner.Id, Owner.Name FROM Case ];
            if (caseList.size() > 0) {
                Case theCase = caseList.get(0);

                email.subject = 'Re ' + theCase.CaseNumber;
                email.plainTextBody = 'Hi, this is not so random';

                result = emailServObj.handleInboundEmail(email, env);

                System.assertEquals(result.success, true);
            }
        }
    }

    @isTest public static  void validateCaseResponse3() {
        setup();
        SMRCEmailService emailServObj = new SMRCEmailService();
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        email.toAddresses = new String[]{
                'test@noorg.edu'
        };
        email.subject = 'test';
        email.fromName = 'scweber';
        email.fromAddress = 'test@noorg.edu';
        email.replyTo = 'nobody@stanford.edu';

        email.plainTextBody = TEST_JSON;
        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        // Insert account as current user

        System.runAs (thisUser) {

            Messaging.InboundEmailResult result = emailServObj.handleInboundEmail(email, env);
            // ok, now look up the case and send a response email
            List<Case> caseList = [SELECT Id, CaseNumber, reference__c, Description, Subject,OwnerId, Owner.Id, Owner.Name, Project_Record_ID__c FROM Case ];
            if (caseList.size() > 0) {
                Case theCase = caseList.get(0);
                System.debug('found case found after insertion '+theCase.Project_Record_ID__c);
                email.subject =  SMEmailService.SUBJECT_PREFIX  + theCase.Project_Record_ID__c;
                email.plainTextBody = 'Hi, this is not so random';

                result = emailServObj.handleInboundEmail(email, env);

                System.assertEquals(result.success, true);
            } else {
                System.debug('no cases found after insertion');
            }
        }
    }



}